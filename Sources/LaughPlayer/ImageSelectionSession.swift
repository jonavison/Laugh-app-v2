import Foundation
import CoreImage
import Metal

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
    private var brushMode: SelectionBrushMode = .refineEdge
    /// Brush radius in image pixels (clamped on apply).
    private var brushRadius: CGFloat = 24
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
    /// Accumulated click/box prompt for Click Select mode (cleared on Clear / Auto Select).
    private var promptDraft = SelectionPrompt.empty
    private let brushContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

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
    var currentBrushMode: SelectionBrushMode { brushMode }
    var currentBrushRadius: CGFloat { brushRadius }
    var currentPromptDraft: SelectionPrompt { promptDraft }
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

    func setBrushMode(_ mode: SelectionBrushMode) {
        guard brushMode != mode else { return }
        brushMode = mode
        notifyChrome()
    }

    func setBrushRadius(_ radius: CGFloat) {
        let clamped = min(120, max(4, radius))
        guard abs(clamped - brushRadius) > 0.05 else { return }
        brushRadius = clamped
        notifyChrome()
    }

    /// Local brush stroke in source pixel space. Requires an active matte + pending photo.
    @discardableResult
    func applyBrush(at point: CGPoint, preview: Bool = true) -> Bool {
        guard var current = mask, let photo = pendingImage else { return false }
        let extent = photo.extent.integral
        let maskCI = current.ciImageMatching(extent: extent)
        let nextCI = SelectionBrushEngine.apply(
            mask: maskCI,
            photo: photo,
            mode: brushMode,
            center: point,
            radius: brushRadius,
            extent: extent
        )
        guard let cg = brushContext.createCGImage(nextCI, from: extent) else { return false }
        current = SelectionMask(
            cgImage: cg,
            extent: extent,
            confidence: current.confidence,
            semanticClass: current.semanticClass,
            source: current.source
        )
        mask = current
        cachedMask = current
        cacheKey = nil // brush invalidates select cache
        notifyChrome()
        onChange?(preview ? .preview : .accurate)
        return true
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
        promptDraft = prompt
        lastSelectKind = .prompt(prompt)
        notifyChrome()
        Task { await runSelect(kind: .prompt(prompt), in: image, quality: .accurate, settleAccurate: false) }
    }

    /// Tool-layer convenience for Subject Select → Auto Select Person.
    func selectPerson(in image: CIImage) {
        promptDraft = .empty
        displayMode = .marchingAnts
        select(in: image, class: .person)
    }

    /// Point select — SAM when ready (downloads if needed).
    func selectRegion(in image: CIImage, at point: CGPoint) {
        clickSelect(in: image, at: point, negative: false, additive: false)
    }

    /// Click Select: positive/negative points with optional additive prompting.
    func clickSelect(in image: CIImage, at point: CGPoint, negative: Bool, additive: Bool) {
        pendingImage = image
        lastError = nil
        usedVisionFallback = false
        if !additive {
            promptDraft = .empty
        }
        if negative {
            promptDraft.negativePoints.append(point)
        } else {
            promptDraft.positivePoints.append(point)
        }
        let prompt = promptDraft
        lastSelectKind = .prompt(prompt)
        notifyChrome()
        Task { await runSelect(kind: .prompt(prompt), in: image, quality: .accurate, settleAccurate: false) }
    }

    /// Box Select: axis-aligned box in source pixels (replaces draft unless additive).
    func boxSelect(in image: CIImage, box: CGRect, additive: Bool) {
        pendingImage = image
        lastError = nil
        usedVisionFallback = false
        if !additive {
            promptDraft = SelectionPrompt(positivePoints: [], negativePoints: [], box: box)
        } else {
            promptDraft.box = box
        }
        let prompt = promptDraft
        lastSelectKind = .prompt(prompt)
        notifyChrome()
        Task { await runSelect(kind: .prompt(prompt), in: image, quality: .accurate, settleAccurate: false) }
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
        brushMode = .refineEdge
        brushRadius = 24
        promptDraft = .empty
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
            if requested == .accurate {
                let ready = try await ensureModelIfNeeded(generation: gen)
                guard ready || modelStore.isReady(SelectionModelArtifact.mobileSAM) else {
                    throw SelectionError.modelNotReady
                }
                await MainActor.run {
                    guard gen == self.generation else { return }
                    self.phase = .selecting
                    self.notifyChrome()
                }
                return try await samProvider.select(in: image, prompt: prompt, quality: requested)
            }
            if let point = prompt.positivePoints.first {
                return try await visionProvider.selectRegion(in: image, at: point, quality: requested)
            }
            throw SelectionError.emptyResult

        case .region(let point):
            // Prefer prompt path (downloads + SAM).
            return try await performSelect(
                kind: .prompt(.point(point)),
                image: image,
                quality: requested,
                generation: gen
            )
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
