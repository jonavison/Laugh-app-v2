import Foundation
import CoreImage

/// Source of truth for the current ImageMedia selection matte (ADR smart-selection).
/// Separate from `ImageAdjustSession` — Face/Body tools will combine both later.
///
/// Auto Select Person (PR 1): Vision rough matte → prompt → MobileSAM; Vision matte is fallback
/// when download is cancelled or CoreML is unavailable. Session stays person-shaped until W3-08d.
final class ImageSelectionSession {
    enum Phase: Equatable {
        case idle
        case downloading(progress: Double)
        case selecting
    }

    private let visionProvider: SelectionProvider
    private let samProvider: SelectionProvider
    private let modelStore: SelectionModelStore
    /// When true, skip MobileSAM download/inference (tests / Vision-only).
    private let forceVisionOnly: Bool
    private let allowsModelDownload: Bool

    private var mask: SelectionMask?
    private var displayMode: SelectionDisplayMode = .marchingAnts
    private var refine = SelectionRefineParameters.identity
    private var quality: SelectionQuality = .accurate
    private var phase: Phase = .idle
    private var lastError: SelectionError?
    private var usedVisionFallback = false
    private var generation = 0
    private var settleWorkItem: DispatchWorkItem?
    private var cacheKey: String?
    private var cachedMask: SelectionMask?
    private var sourceToken: String?
    private var cancelDownloadRequested = false
    private let cancelLock = NSLock()

    /// Fired when mask / display mode should update the surface.
    var onChange: ((_ quality: SelectionQuality) -> Void)?
    /// Fired when chrome (loading / error / dirty) should refresh.
    var onChromeChange: (() -> Void)?

    init(
        visionProvider: SelectionProvider = VisionPersonSelectionProvider(),
        modelStore: SelectionModelStore = SelectionModelStore(),
        samProvider: SelectionProvider? = nil,
        allowsModelDownload: Bool = true,
        forceVisionOnly: Bool = false
    ) {
        self.visionProvider = visionProvider
        self.modelStore = modelStore
        self.samProvider = samProvider ?? MobileSAMSelectionProvider(store: modelStore)
        self.allowsModelDownload = allowsModelDownload
        self.forceVisionOnly = forceVisionOnly
    }

    /// Test / legacy helper: all selects go through `provider` (no SAM download).
    convenience init(provider: SelectionProvider) {
        let unusedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-sel-vision-only-\(UUID().uuidString)", isDirectory: true)
        self.init(
            visionProvider: provider,
            modelStore: SelectionModelStore(root: unusedRoot),
            samProvider: provider,
            allowsModelDownload: false,
            forceVisionOnly: true
        )
    }

    var currentMask: SelectionMask? { mask }
    var currentDisplayMode: SelectionDisplayMode { displayMode }
    var currentRefine: SelectionRefineParameters { refine }
    var currentQuality: SelectionQuality { quality }
    var currentPhase: Phase { phase }
    var isSelecting: Bool {
        switch phase {
        case .selecting, .downloading: return true
        case .idle: return false
        }
    }
    var isDownloadingModel: Bool {
        if case .downloading = phase { return true }
        return false
    }
    var downloadProgress: Double? {
        if case .downloading(let p) = phase { return p }
        return nil
    }
    var error: SelectionError? { lastError }
    var hasSelection: Bool { mask != nil }
    var didUseVisionFallback: Bool { usedVisionFallback }

    /// Bind to the open image so caches invalidate on switch.
    func setSourceToken(_ token: String?) {
        guard sourceToken != token else { return }
        sourceToken = token
        clearSelection(notify: true)
    }

    func setDisplayMode(_ mode: SelectionDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode
        notifyChrome()
        onChange?(quality == .accurate ? .accurate : .preview)
    }

    func setRefine(_ next: SelectionRefineParameters, preview: Bool = true) {
        guard next != refine else { return }
        refine = next
        notifyChrome()
        onChange?(preview ? .preview : .accurate)
    }

    func setQuality(_ next: SelectionQuality) {
        guard quality != next else { return }
        quality = next
        notifyChrome()
        guard mask != nil, let image = pendingImage else { return }
        Task { await runSelectPerson(in: image, quality: next, settleAccurate: false) }
    }

    private var pendingImage: CIImage?

    /// Auto-select person for the whole frame (v1 primary path).
    /// Accurate: Vision prompt-assist → SAM matte (Vision fallback on cancel / miss).
    func selectPerson(in image: CIImage) {
        pendingImage = image
        lastError = nil
        usedVisionFallback = false
        notifyChrome()
        Task { await runSelectPerson(in: image, quality: .accurate, settleAccurate: false) }
    }

    /// Hit-test person at a point — SAM point prompt when ready, else Vision.
    func selectRegion(in image: CIImage, at point: CGPoint) {
        pendingImage = image
        lastError = nil
        usedVisionFallback = false
        notifyChrome()
        Task { await runSelectRegion(in: image, at: point, quality: .accurate, settleAccurate: false) }
    }

    /// Cancel in-flight model download (triggers Vision matte fallback for that attempt).
    func cancelModelDownload() {
        cancelLock.lock()
        cancelDownloadRequested = true
        cancelLock.unlock()
        notifyChrome()
    }

    func clearSelection(notify: Bool = true) {
        settleWorkItem?.cancel()
        settleWorkItem = nil
        generation += 1
        cancelLock.lock()
        cancelDownloadRequested = true
        cancelLock.unlock()
        mask = nil
        cachedMask = nil
        cacheKey = nil
        lastError = nil
        usedVisionFallback = false
        phase = .idle
        refine = .identity
        if notify {
            notifyChrome()
            onChange?(.accurate)
        }
    }

    /// Reset All / image change — clears matte and restores default display mode.
    func resetAll() {
        displayMode = .marchingAnts
        refine = .identity
        quality = .accurate
        clearSelection(notify: true)
    }

    private func resetCancelFlag() {
        cancelLock.lock()
        cancelDownloadRequested = false
        cancelLock.unlock()
    }

    private func isCancelRequested() -> Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return cancelDownloadRequested
    }

    private func runSelectPerson(
        in image: CIImage,
        quality requested: SelectionQuality,
        settleAccurate: Bool
    ) async {
        let key = cacheKey(for: image, kind: "class.person", quality: requested)
        if let cachedMask, cacheKey == key {
            await MainActor.run {
                self.mask = cachedMask
                self.quality = requested
                self.phase = .idle
                self.notifyChrome()
                self.onChange?(requested)
            }
            if settleAccurate, requested == .preview {
                scheduleAccurateSettle(image: image, kind: .person)
            }
            return
        }

        let gen = await MainActor.run { () -> Int in
            self.generation += 1
            self.resetCancelFlag()
            self.phase = .selecting
            self.usedVisionFallback = false
            self.notifyChrome()
            return self.generation
        }

        do {
            let result: SelectionMask
            if requested == .accurate {
                result = try await accuratePersonViaSAM(image: image, generation: gen)
            } else {
                result = try await visionProvider.selectClass(in: image, class: .person, quality: requested)
            }
            await MainActor.run {
                guard gen == self.generation else { return }
                self.mask = result
                self.cachedMask = result
                self.cacheKey = key
                self.quality = requested
                self.phase = .idle
                self.lastError = nil
                self.notifyChrome()
                self.onChange?(requested)
            }
            if settleAccurate, requested == .preview {
                scheduleAccurateSettle(image: image, kind: .person)
            }
        } catch let error as SelectionError {
            await MainActor.run {
                guard gen == self.generation else { return }
                self.phase = .idle
                self.lastError = error
                self.notifyChrome()
            }
        } catch {
            await MainActor.run {
                guard gen == self.generation else { return }
                self.phase = .idle
                self.lastError = .emptyResult
                self.notifyChrome()
            }
        }
    }

    /// Accurate Auto Select: ensure model → Vision rough → prompt → SAM; Vision matte on fallback.
    private func accuratePersonViaSAM(image: CIImage, generation gen: Int) async throws -> SelectionMask {
        if forceVisionOnly {
            return try await visionProvider.selectClass(in: image, class: .person, quality: .accurate)
        }

        let artifact = SelectionModelArtifact.mobileSAM
        if !modelStore.isReady(artifact) {
            guard allowsModelDownload else {
                await MainActor.run { self.usedVisionFallback = true }
                return try await visionProvider.selectClass(in: image, class: .person, quality: .accurate)
            }
            await MainActor.run {
                guard gen == self.generation else { return }
                self.phase = .downloading(progress: 0)
                self.notifyChrome()
            }
            do {
                _ = try await modelStore.ensureAvailable(
                    artifact,
                    progress: { [weak self] p in
                        guard let self else { return }
                        Task { @MainActor in
                            guard gen == self.generation else { return }
                            self.phase = .downloading(progress: p)
                            self.notifyChrome()
                        }
                    },
                    isCancelled: { [weak self] in
                        self?.isCancelRequested() ?? true
                    }
                )
            } catch SelectionModelStoreError.cancelled {
                await MainActor.run { self.usedVisionFallback = true }
                return try await visionProvider.selectClass(in: image, class: .person, quality: .accurate)
            } catch {
                await MainActor.run { self.usedVisionFallback = true }
                return try await visionProvider.selectClass(in: image, class: .person, quality: .accurate)
            }
        }

        await MainActor.run {
            guard gen == self.generation else { return }
            self.phase = .selecting
            self.notifyChrome()
        }

        // Rough Vision matte → points/box only (SAM owns the result matte).
        let rough = try await visionProvider.selectClass(in: image, class: .person, quality: .preview)
        let prompt = SelectionPromptBuilder.fromRoughMask(rough, imageExtent: image.extent)

        do {
            return try await samProvider.select(in: image, prompt: prompt, quality: .accurate)
        } catch SelectionError.modelNotReady {
            await MainActor.run { self.usedVisionFallback = true }
            return try await visionProvider.selectClass(in: image, class: .person, quality: .accurate)
        } catch SelectionError.emptyResult {
            await MainActor.run { self.usedVisionFallback = true }
            return try await visionProvider.selectClass(in: image, class: .person, quality: .accurate)
        } catch {
            await MainActor.run { self.usedVisionFallback = true }
            return try await visionProvider.selectClass(in: image, class: .person, quality: .accurate)
        }
    }

    private enum SelectKind {
        case person
        case region(CGPoint)
    }

    private func runSelectRegion(
        in image: CIImage,
        at point: CGPoint,
        quality requested: SelectionQuality,
        settleAccurate: Bool
    ) async {
        let gen = await MainActor.run { () -> Int in
            self.generation += 1
            self.resetCancelFlag()
            self.phase = .selecting
            self.usedVisionFallback = false
            self.notifyChrome()
            return self.generation
        }

        do {
            let result: SelectionMask
            if requested == .accurate, modelStore.isReady(SelectionModelArtifact.mobileSAM) {
                do {
                    result = try await samProvider.select(
                        in: image,
                        prompt: .point(point),
                        quality: requested
                    )
                } catch {
                    await MainActor.run { self.usedVisionFallback = true }
                    result = try await visionProvider.selectRegion(in: image, at: point, quality: requested)
                }
            } else {
                result = try await visionProvider.selectRegion(in: image, at: point, quality: requested)
            }
            let key = cacheKey(for: image, kind: "region.person", quality: requested)
            await MainActor.run {
                guard gen == self.generation else { return }
                self.mask = result
                self.cachedMask = result
                self.cacheKey = key
                self.quality = requested
                self.phase = .idle
                self.lastError = nil
                self.notifyChrome()
                self.onChange?(requested)
            }
            if settleAccurate, requested == .preview {
                scheduleAccurateSettle(image: image, kind: .region(point))
            }
        } catch let error as SelectionError {
            await MainActor.run {
                guard gen == self.generation else { return }
                self.phase = .idle
                self.lastError = error
                self.notifyChrome()
            }
        } catch {
            await MainActor.run {
                guard gen == self.generation else { return }
                self.phase = .idle
                self.lastError = .emptyResult
                self.notifyChrome()
            }
        }
    }

    private func scheduleAccurateSettle(image: CIImage, kind: SelectKind) {
        settleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task {
                switch kind {
                case .person:
                    await self.runSelectPerson(in: image, quality: .accurate, settleAccurate: false)
                case .region(let point):
                    await self.runSelectRegion(in: image, at: point, quality: .accurate, settleAccurate: false)
                }
            }
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
    }

    private func cacheKey(for image: CIImage, kind: String, quality: SelectionQuality) -> String {
        let extent = image.extent
        let token = sourceToken ?? "anon"
        let engine = modelStore.isReady(SelectionModelArtifact.mobileSAM) ? "sam" : "vision"
        return "\(token)|\(engine)|\(kind)|\(quality.rawValue)|\(Int(extent.width))x\(Int(extent.height))"
    }

    private func notifyChrome() {
        onChromeChange?()
    }
}
