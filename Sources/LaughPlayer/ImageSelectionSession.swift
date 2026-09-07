import Foundation
import CoreImage

/// Source of truth for the current ImageMedia selection matte (ADR smart-selection).
/// Separate from `ImageAdjustSession` — Face/Body tools will combine both later.
///
/// Class-agnostic session APIs (`select(class:)`, `select(prompt:)`, `selectRegion`).
/// **Auto Select Person** is a thin tool-layer wrapper that still calls `select(class: .person)`;
/// Vision→prompt assist lives in `SelectionPersonPromptAssist`, not in shared refine/export.
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
    private var pendingImage: CIImage?
    private var lastSelectKind: SelectKind?

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
        guard mask != nil, let image = pendingImage, let kind = lastSelectKind else { return }
        Task { await runSelect(kind: kind, in: image, quality: next, settleAccurate: false) }
    }

    /// Class-agnostic semantic select (sky / rock / person / … as providers grow).
    func select(in image: CIImage, class semanticClass: SemanticClass) {
        pendingImage = image
        lastError = nil
        usedVisionFallback = false
        lastSelectKind = .semanticClass(semanticClass)
        notifyChrome()
        Task { await runSelect(kind: .semanticClass(semanticClass), in: image, quality: .accurate, settleAccurate: false) }
    }

    /// Class-agnostic prompt select (points / box).
    func select(in image: CIImage, prompt: SelectionPrompt) {
        pendingImage = image
        lastError = nil
        usedVisionFallback = false
        lastSelectKind = .prompt(prompt)
        notifyChrome()
        Task { await runSelect(kind: .prompt(prompt), in: image, quality: .accurate, settleAccurate: false) }
    }

    /// Tool-layer convenience for Subject Select → Auto Select Person.
    func selectPerson(in image: CIImage) {
        select(in: image, class: .person)
    }

    /// Point select — SAM when ready, else Vision region (person-capable providers).
    func selectRegion(in image: CIImage, at point: CGPoint) {
        pendingImage = image
        lastError = nil
        usedVisionFallback = false
        lastSelectKind = .region(point)
        notifyChrome()
        Task { await runSelect(kind: .region(point), in: image, quality: .accurate, settleAccurate: false) }
    }

    /// Cancel in-flight model download (triggers Vision matte fallback for person attempts).
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
        lastSelectKind = nil
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

    private enum SelectKind: Equatable {
        case semanticClass(SemanticClass)
        case prompt(SelectionPrompt)
        case region(CGPoint)
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

    private func runSelect(
        kind: SelectKind,
        in image: CIImage,
        quality requested: SelectionQuality,
        settleAccurate: Bool
    ) async {
        let key = cacheKey(for: image, kind: kind, quality: requested)
        if let cachedMask, cacheKey == key {
            await MainActor.run {
                self.mask = cachedMask
                self.quality = requested
                self.phase = .idle
                self.notifyChrome()
                self.onChange?(requested)
            }
            if settleAccurate, requested == .preview {
                scheduleAccurateSettle(image: image, kind: kind)
            }
            return
        }

        let gen = await MainActor.run { () -> Int in
            self.generation += 1
            self.resetCancelFlag()
            self.phase = .selecting
            self.usedVisionFallback = false
            self.lastSelectKind = kind
            self.notifyChrome()
            return self.generation
        }

        do {
            let result = try await performSelect(kind: kind, image: image, quality: requested, generation: gen)
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
                scheduleAccurateSettle(image: image, kind: kind)
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

    private func performSelect(
        kind: SelectKind,
        image: CIImage,
        quality requested: SelectionQuality,
        generation gen: Int
    ) async throws -> SelectionMask {
        if forceVisionOnly {
            return try await visionOnlySelect(kind: kind, image: image, quality: requested)
        }

        switch kind {
        case .semanticClass(let semanticClass):
            if requested == .accurate {
                return try await accurateSelect(
                    semanticClass: semanticClass,
                    image: image,
                    generation: gen
                )
            }
            return try await visionProvider.selectClass(in: image, class: semanticClass, quality: requested)

        case .prompt(let prompt):
            if requested == .accurate, modelStore.isReady(SelectionModelArtifact.mobileSAM) || allowsModelDownload {
                _ = try await ensureModelIfNeeded(generation: gen)
                do {
                    return try await samProvider.select(in: image, prompt: prompt, quality: requested)
                } catch {
                    await MainActor.run { self.usedVisionFallback = true }
                    if let point = prompt.positivePoints.first {
                        return try await visionProvider.selectRegion(in: image, at: point, quality: requested)
                    }
                    throw error
                }
            }
            if let point = prompt.positivePoints.first {
                return try await visionProvider.selectRegion(in: image, at: point, quality: requested)
            }
            throw SelectionError.emptyResult

        case .region(let point):
            if requested == .accurate, modelStore.isReady(SelectionModelArtifact.mobileSAM) {
                do {
                    return try await samProvider.select(in: image, prompt: .point(point), quality: requested)
                } catch {
                    await MainActor.run { self.usedVisionFallback = true }
                    return try await visionProvider.selectRegion(in: image, at: point, quality: requested)
                }
            }
            return try await visionProvider.selectRegion(in: image, at: point, quality: requested)
        }
    }

    private func visionOnlySelect(
        kind: SelectKind,
        image: CIImage,
        quality requested: SelectionQuality
    ) async throws -> SelectionMask {
        switch kind {
        case .semanticClass(let semanticClass):
            return try await visionProvider.selectClass(in: image, class: semanticClass, quality: requested)
        case .prompt(let prompt):
            if let point = prompt.positivePoints.first {
                return try await visionProvider.selectRegion(in: image, at: point, quality: requested)
            }
            if let box = prompt.box, !box.isEmpty {
                return try await visionProvider.selectRegion(
                    in: image,
                    at: CGPoint(x: box.midX, y: box.midY),
                    quality: requested
                )
            }
            throw SelectionError.emptyResult
        case .region(let point):
            return try await visionProvider.selectRegion(in: image, at: point, quality: requested)
        }
    }

    /// Accurate path: optional model download → (person: Vision prompt assist) → SAM; Vision fallback.
    private func accurateSelect(
        semanticClass: SemanticClass,
        image: CIImage,
        generation gen: Int
    ) async throws -> SelectionMask {
        let ready = try await ensureModelIfNeeded(generation: gen)
        if !ready {
            await MainActor.run { self.usedVisionFallback = true }
            return try await visionProvider.selectClass(in: image, class: semanticClass, quality: .accurate)
        }

        await MainActor.run {
            guard gen == self.generation else { return }
            self.phase = .selecting
            self.notifyChrome()
        }

        let prompt: SelectionPrompt
        if semanticClass == .person {
            // Person specificity stays in the prompt-assist helper, not in refine/export.
            prompt = try await SelectionPersonPromptAssist.buildPrompt(using: visionProvider, image: image)
        } else {
            let center = CGPoint(x: image.extent.midX, y: image.extent.midY)
            prompt = .point(center)
        }

        do {
            let mask = try await samProvider.select(in: image, prompt: prompt, quality: .accurate)
            // Preserve caller-facing class metadata when provider returns `.unknown`.
            if mask.semanticClass == .unknown, semanticClass != .unknown {
                return SelectionMask(
                    cgImage: mask.cgImage,
                    extent: mask.extent,
                    confidence: mask.confidence,
                    semanticClass: semanticClass,
                    source: mask.source
                )
            }
            return mask
        } catch SelectionError.modelNotReady, SelectionError.emptyResult {
            await MainActor.run { self.usedVisionFallback = true }
            return try await visionProvider.selectClass(in: image, class: semanticClass, quality: .accurate)
        } catch {
            await MainActor.run { self.usedVisionFallback = true }
            return try await visionProvider.selectClass(in: image, class: semanticClass, quality: .accurate)
        }
    }

    @discardableResult
    private func ensureModelIfNeeded(generation gen: Int) async throws -> Bool {
        let artifact = SelectionModelArtifact.mobileSAM
        if modelStore.isReady(artifact) { return true }
        guard allowsModelDownload else {
            await MainActor.run { self.usedVisionFallback = true }
            return false
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
            return true
        } catch SelectionModelStoreError.cancelled {
            await MainActor.run { self.usedVisionFallback = true }
            return false
        } catch {
            await MainActor.run { self.usedVisionFallback = true }
            return false
        }
    }

    private func scheduleAccurateSettle(image: CIImage, kind: SelectKind) {
        settleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task {
                await self.runSelect(kind: kind, in: image, quality: .accurate, settleAccurate: false)
            }
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
    }

    private func cacheKey(for image: CIImage, kind: SelectKind, quality: SelectionQuality) -> String {
        let extent = image.extent
        let token = sourceToken ?? "anon"
        let engine = modelStore.isReady(SelectionModelArtifact.mobileSAM) && !forceVisionOnly ? "sam" : "vision"
        let kindKey: String
        switch kind {
        case .semanticClass(let c):
            kindKey = "class.\(c.rawValue)"
        case .prompt(let p):
            kindKey = "prompt.\(p.positivePoints.count).\(p.negativePoints.count).\(p.box != nil)"
        case .region(let point):
            kindKey = "region.\(Int(point.x))x\(Int(point.y))"
        }
        return "\(token)|\(engine)|\(kindKey)|\(quality.rawValue)|\(Int(extent.width))x\(Int(extent.height))"
    }

    private func notifyChrome() {
        onChromeChange?()
    }
}
