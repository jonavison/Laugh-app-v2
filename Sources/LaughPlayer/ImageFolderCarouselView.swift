import AppKit
import QuartzCore

/// Filmstrip badge for per-image develop state (ADR 0006).
enum FilmstripDevelopMark: Equatable {
    case none
    /// Saved **ImageDevelopEdit** on disk (in-app store).
    case saved
    /// Open image with unsaved session changes.
    case dirty
}

/// Decode order for filmstrip thumbs: selected first, then expand outward.
enum FilmstripThumbnailPriority {
    static func ordered(urls: [URL], selected: URL?) -> [URL] {
        guard !urls.isEmpty else { return [] }
        guard let selected else { return urls }
        let selectedKey = selected.standardizedFileURL
        guard let center = urls.firstIndex(where: { $0.standardizedFileURL == selectedKey }) else {
            return urls
        }
        var result: [URL] = []
        result.reserveCapacity(urls.count)
        result.append(urls[center])
        var radius = 1
        while result.count < urls.count {
            let right = center + radius
            let left = center - radius
            if right < urls.count { result.append(urls[right]) }
            if left >= 0 { result.append(urls[left]) }
            radius += 1
        }
        return result
    }
}

/// Bottom filmstrip of sibling images in the same folder as the open **ImageMedia**.
/// Square-ish thumbs, tight spacing, scroll-edge gradient shadows (no scrollbar).
final class ImageFolderCarouselView: NSView {
    /// Plain click — open this still.
    var onSelect: ((URL) -> Void)?
    /// ⌘-click — toggle batch membership (does not open).
    var onBatchToggle: ((URL) -> Void)?
    /// ⇧-click — range-select into batch (does not open).
    var onBatchRange: ((URL) -> Void)?

    private let scrollView = FilmstripScrollView()
    private let stack = NSStackView()
    private let leftFadeView = FadeEdgeView(edge: .leading)
    private let rightFadeView = FadeEdgeView(edge: .trailing)
    private var urls: [URL] = []
    private var selectedURL: URL?
    private var batchSelectedURLs: Set<URL> = []
    private var thumbnailButtons: [URL: FilmstripThumbButton] = [:]
    private var developMarks: [URL: FilmstripDevelopMark] = [:]
    private var loadGeneration = 0
    private var clipObserver: NSObjectProtocol?

    /// Near-square crop-fill previews.
    private static let thumbSide: CGFloat = 80
    /// Wide enough that an edge thumb clearly dissolves into the studio floor.
    private static let fadeWidth: CGFloat = 96

    /// Opaque studio-floor fill so the photo never shows through the filmstrip.
    func applyStudioChromeBackground() {
        wantsLayer = true
        layer?.backgroundColor = LaughTheme.imageStudioFloorColor(appearance: effectiveAppearance).cgColor
        needsDisplay = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        applyStudioChromeBackground()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = stack
        addSubview(scrollView)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        leftFadeView.translatesAutoresizingMaskIntoConstraints = false
        rightFadeView.translatesAutoresizingMaskIntoConstraints = false
        // Overlay above the scroll content so fades are actually visible.
        addSubview(leftFadeView)
        addSubview(rightFadeView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),

            leftFadeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftFadeView.topAnchor.constraint(equalTo: topAnchor),
            leftFadeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftFadeView.widthAnchor.constraint(equalToConstant: Self.fadeWidth),

            rightFadeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightFadeView.topAnchor.constraint(equalTo: topAnchor),
            rightFadeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            rightFadeView.widthAnchor.constraint(equalToConstant: Self.fadeWidth)
        ])

        clipObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateFadeVisibility()
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    deinit {
        if let clipObserver {
            NotificationCenter.default.removeObserver(clipObserver)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStudioChromeBackground()
        leftFadeView.needsDisplay = true
        rightFadeView.needsDisplay = true
    }

    override func layout() {
        super.layout()
        updateFadeVisibility()
    }

    func setImages(_ files: [LibraryMediaFile], selected: URL?) {
        let newURLs = files.map(\.url.standardizedFileURL)
        let previousURLs = urls.map(\.standardizedFileURL)
        selectedURL = selected?.standardizedFileURL

        // Same folder strip: only restyle selection — avoid full rebuild / thumb flicker.
        if newURLs == previousURLs, !thumbnailButtons.isEmpty {
            selectSibling(selectedURL, animatedScroll: false)
            return
        }

        urls = files.map(\.url)
        rebuildButtons()
        loadThumbnails()
        scrollSelectedIntoViewIfNeeded()
        updateFadeVisibility()
    }

    func clear() {
        urls = []
        selectedURL = nil
        batchSelectedURLs = []
        developMarks = [:]
        loadGeneration += 1
        rebuildButtons()
        updateFadeVisibility()
    }

    /// Update top-left edit icons without rebuilding thumbs.
    func setDevelopMarks(_ marks: [URL: FilmstripDevelopMark]) {
        var normalized: [URL: FilmstripDevelopMark] = [:]
        for (url, mark) in marks where mark != .none {
            normalized[url.standardizedFileURL] = mark
        }
        developMarks = normalized
        for (url, button) in thumbnailButtons {
            button.setDevelopMark(normalized[url.standardizedFileURL] ?? .none)
        }
    }

    /// Grey ring for batch membership (open still still uses teal).
    func setBatchSelection(_ urls: [URL]) {
        batchSelectedURLs = Set(urls.map(\.standardizedFileURL))
        refreshAllThumbChrome(animated: false)
    }

    func refreshEdgeFades() {
        layoutSubtreeIfNeeded()
        updateFadeVisibility()
    }

    /// Re-run center/clamp after the filmstrip width changes (e.g. edit column open/close).
    func recenterSelected(animated: Bool) {
        layoutSubtreeIfNeeded()
        centerSelectedThumbnailIfPossible(animated: animated)
    }

    private func updateFadeVisibility() {
        // Always-on left/right edge shadows (studio filmstrip cue).
        leftFadeView.alphaValue = 1
        rightFadeView.alphaValue = 1
        leftFadeView.isHidden = false
        rightFadeView.isHidden = false
        leftFadeView.needsDisplay = true
        rightFadeView.needsDisplay = true
    }

    /// Filmstrip scroll motion — never use during hold/spam steps.
    enum ScrollMotion {
        case none
        /// Single deliberate ←/→.
        case deliberate
        /// Soft recenter after a fast scrub parks.
        case settle

        var animates: Bool { self != .none }

        var duration: TimeInterval {
            switch self {
            case .none: return 0
            case .deliberate: return 0.15
            case .settle: return 0.18
            }
        }

        var timing: CAMediaTimingFunction {
            switch self {
            case .none, .deliberate:
                return CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1)
            case .settle:
                return CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
            }
        }
    }

    /// Already-decoded filmstrip bitmap for instant surface placeholders while ImageIO loads.
    func thumbnailImage(for url: URL) -> NSImage? {
        thumbnailButtons[url.standardizedFileURL]?.image
    }

    /// Selection-only update (no rebuild). Fast scrub uses `.none`; slow taps use `.deliberate`.
    func selectSibling(_ selected: URL?, scrollMotion: ScrollMotion) {
        let previous = selectedURL
        let next = selected?.standardizedFileURL
        guard previous != next else {
            if scrollMotion.animates {
                centerSelectedThumbnailIfPossible(motion: scrollMotion)
            }
            return
        }
        selectedURL = next
        if let previous, let button = thumbnailButtons[previous] {
            applyThumbChrome(
                button,
                open: false,
                batched: batchSelectedURLs.contains(previous),
                animated: scrollMotion == .deliberate
            )
        }
        if let next, let button = thumbnailButtons[next] {
            applyThumbChrome(
                button,
                open: true,
                batched: batchSelectedURLs.contains(next),
                animated: scrollMotion == .deliberate
            )
            // Scrub landed on a still whose RAW thumb is still queued — jump the line.
            if button.image == nil {
                decodeThumbnail(for: next, generation: loadGeneration, preferImmediate: true)
            }
        }
        centerSelectedThumbnailIfPossible(
            motion: scrollMotion,
            allowLayoutPass: scrollMotion.animates
        )
    }

    /// Convenience for call sites that only care about animated vs snap.
    func selectSibling(_ selected: URL?, animatedScroll: Bool) {
        selectSibling(selected, scrollMotion: animatedScroll ? .deliberate : .none)
    }

    /// Ease the selected thumb to center after a scrub burst parks (no selection change).
    func settleScrollToSelection() {
        centerSelectedThumbnailIfPossible(motion: .settle, allowLayoutPass: true)
    }

    private func rebuildButtons() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        thumbnailButtons.removeAll()

        for url in urls {
            let button = FilmstripThumbButton()
            button.toolTip = url.lastPathComponent
            button.translatesAutoresizingMaskIntoConstraints = false
            button.onClick = { [weak self] flags in
                self?.handleThumbClick(url: url, modifiers: flags)
            }
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Self.thumbSide),
                button.heightAnchor.constraint(equalToConstant: Self.thumbSide)
            ])
            let key = url.standardizedFileURL
            applyThumbChrome(
                button,
                open: isSelected(url),
                batched: batchSelectedURLs.contains(key),
                animated: false
            )
            button.setDevelopMark(developMarks[key] ?? .none)
            button.beginLoadingShimmer()
            stack.addArrangedSubview(button)
            thumbnailButtons[key] = button
        }
        stack.layoutSubtreeIfNeeded()
        let width = max(stack.fittingSize.width, scrollView.contentView.bounds.width)
        stack.setFrameSize(NSSize(width: width, height: Self.thumbSide + 20))
        updateFadeVisibility()
    }

    private func isSelected(_ url: URL) -> Bool {
        guard let selectedURL else { return false }
        return url.standardizedFileURL == selectedURL
    }

    private func refreshAllThumbChrome(animated: Bool) {
        for (url, button) in thumbnailButtons {
            applyThumbChrome(
                button,
                open: selectedURL == url,
                batched: batchSelectedURLs.contains(url),
                animated: animated
            )
        }
    }

    private func applyThumbChrome(
        _ button: FilmstripThumbButton,
        open: Bool,
        batched: Bool,
        animated: Bool = false
    ) {
        button.wantsLayer = true
        guard let layer = button.layer else { return }

        // Open = teal ring; batch-only = grey chrome ring; else hairline.
        let borderWidth: CGFloat
        let borderColor: CGColor
        if open {
            borderWidth = 2.5
            borderColor = LaughTheme.interactiveAccent.cgColor
        } else if batched {
            borderWidth = 2
            borderColor = LaughTheme.chromeActiveFill(appearance: effectiveAppearance).cgColor
        } else {
            borderWidth = 1
            borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        }

        let apply: () -> Void = {
            layer.borderWidth = borderWidth
            layer.borderColor = borderColor
            layer.transform = CATransform3DIdentity
        }

        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            apply()
            CATransaction.commit()
            return
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        apply()
        CATransaction.commit()
    }

    private func loadThumbnails() {
        loadGeneration += 1
        let generation = loadGeneration
        let targets = FilmstripThumbnailPriority.ordered(urls: urls, selected: selectedURL)
        guard !targets.isEmpty else { return }
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? MediaThumbnailGenerator.defaultScreenScale()
        let pointSide = Self.thumbSide
        // Finish the open still before the pool races for the serial RAW decoder.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runThumbnailDecode(
                url: targets[0],
                generation: generation,
                pointSide: pointSide,
                scale: scale
            )
            for url in targets.dropFirst() {
                Self.thumbnailDecodeQueue.async {
                    Self.thumbnailDecodeLimiter.wait()
                    defer { Self.thumbnailDecodeLimiter.signal() }
                    self?.runThumbnailDecode(
                        url: url,
                        generation: generation,
                        pointSide: pointSide,
                        scale: scale
                    )
                }
            }
        }
    }

    /// ImageIO embedded JPEG thumbs are thread-safe — keep a modest pool.
    private static let thumbnailDecodeQueue: DispatchQueue = {
        DispatchQueue(label: "ch.laugh.filmstrip.thumbs", qos: .utility, attributes: .concurrent)
    }()
    private static let thumbnailDecodeLimiter = DispatchSemaphore(value: 4)

    private func decodeThumbnail(for url: URL, generation: Int, preferImmediate: Bool) {
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? MediaThumbnailGenerator.defaultScreenScale()
        let pointSide = Self.thumbSide
        let work = { [weak self] in
            if !preferImmediate {
                Self.thumbnailDecodeLimiter.wait()
            }
            defer {
                if !preferImmediate {
                    Self.thumbnailDecodeLimiter.signal()
                }
            }
            self?.runThumbnailDecode(
                url: url,
                generation: generation,
                pointSide: pointSide,
                scale: scale
            )
        }
        if preferImmediate {
            DispatchQueue.global(qos: .userInitiated).async(execute: work)
        } else {
            Self.thumbnailDecodeQueue.async(execute: work)
        }
    }

    private func runThumbnailDecode(
        url: URL,
        generation: Int,
        pointSide: CGFloat,
        scale: CGFloat
    ) {
        let kind = MediaKindDetector.kind(for: url)
        let image = MediaThumbnailGenerator.squareThumbnail(
            for: url,
            kind: kind,
            pointSide: pointSide,
            screenScale: scale
        )
        DispatchQueue.main.async { [weak self] in
            guard let self, self.loadGeneration == generation else { return }
            guard let button = self.thumbnailButtons[url.standardizedFileURL] else { return }
            button.applyThumbnail(image)
        }
    }

    private func scrollSelectedIntoViewIfNeeded() {
        guard let selectedURL,
              thumbnailButtons[selectedURL] != nil else { return }
        layoutSubtreeIfNeeded()
        stack.layoutSubtreeIfNeeded()
        if scrollView.contentView.bounds.width > 1 {
            centerSelectedThumbnailIfPossible(animated: true)
        } else {
            // Layout may not be final yet after first mount; center on next runloop tick.
            DispatchQueue.main.async { [weak self] in
                self?.centerSelectedThumbnailIfPossible(animated: true)
            }
        }
    }

    /// Keep the selected thumb in the horizontal middle of the filmstrip when the strip
    /// is long enough; near the start/end, clamp so we don't scroll past the edges.
    /// Fast scrub skips `layoutSubtreeIfNeeded` — frames are already stable after the initial strip build.
    private func centerSelectedThumbnailIfPossible(
        motion: ScrollMotion,
        allowLayoutPass: Bool = true
    ) {
        guard let selectedURL,
              let button = thumbnailButtons[selectedURL],
              let documentView = scrollView.documentView else { return }

        if allowLayoutPass {
            layoutSubtreeIfNeeded()
            stack.layoutSubtreeIfNeeded()
        }

        let clipView = scrollView.contentView
        let clipBounds = clipView.bounds
        guard clipBounds.width > 1 else { return }

        let thumbInDocument = button.convert(button.bounds, to: documentView)
        let desiredOriginX = thumbInDocument.midX - (clipBounds.width / 2)

        let docWidth = max(documentView.frame.width, clipBounds.width)
        let maxOriginX = max(0, docWidth - clipBounds.width)
        let clampedOriginX = min(max(0, desiredOriginX), maxOriginX)

        if abs(clampedOriginX - clipBounds.origin.x) < 0.5 {
            return
        }

        let target = NSPoint(x: clampedOriginX, y: clipBounds.origin.y)
        if motion.animates {
            // Cancel an in-flight animator so settle doesn’t fight a prior deliberate ease.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            clipView.layer?.removeAllAnimations()
            CATransaction.commit()

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = motion.duration
                context.timingFunction = motion.timing
                context.allowsImplicitAnimation = true
                clipView.animator().setBoundsOrigin(target)
                self.scrollView.reflectScrolledClipView(clipView)
            }, completionHandler: { [weak self] in
                guard let self else { return }
                self.scrollView.reflectScrolledClipView(clipView)
            })
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            clipView.setBoundsOrigin(target)
            scrollView.reflectScrolledClipView(clipView)
            CATransaction.commit()
        }
    }

    private func centerSelectedThumbnailIfPossible(animated: Bool, allowLayoutPass: Bool = true) {
        centerSelectedThumbnailIfPossible(
            motion: animated ? .deliberate : .none,
            allowLayoutPass: allowLayoutPass
        )
    }

    private func handleThumbClick(url: URL, modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection([.command, .shift])
        if flags.contains(.command) {
            onBatchToggle?(url)
        } else if flags.contains(.shift) {
            onBatchRange?(url)
        } else {
            onSelect?(url)
        }
    }
}

/// Filmstrip cell with a brighten-on-hover wash (photo content, not chrome blue).
private final class FilmstripThumbButton: NSButton {
    var onClick: ((NSEvent.ModifierFlags) -> Void)?

    private let hoverWash = CALayer()
    private let shimmerHost = FilmstripShimmerView()
    private let editHost = NSView()
    private let editBadge = NSImageView()
    private var tracking: NSTrackingArea?
    private var developMark: FilmstripDevelopMark = .none
    private var mouseDownModifiers: NSEvent.ModifierFlags = []

    init() {
        super.init(frame: .zero)
        title = ""
        alternateTitle = ""
        bezelStyle = .regularSquare
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleAxesIndependently
        // Never let AppKit draw a truncated filename over the photo.
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        // Muted plate so transparent PNGs read correctly through the shared crop-fill path.
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor

        shimmerHost.translatesAutoresizingMaskIntoConstraints = false
        shimmerHost.isHidden = true
        addSubview(shimmerHost)

        hoverWash.name = "filmstripHoverWash"
        hoverWash.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        hoverWash.opacity = 0
        hoverWash.zPosition = 10
        layer?.addSublayer(hoverWash)

        editHost.translatesAutoresizingMaskIntoConstraints = false
        editHost.wantsLayer = true
        editHost.layer?.cornerRadius = 9
        editHost.layer?.masksToBounds = false
        editHost.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        editHost.layer?.borderWidth = 0.5
        editHost.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        editHost.layer?.shadowColor = NSColor.black.cgColor
        editHost.layer?.shadowOpacity = 0.55
        editHost.layer?.shadowRadius = 1.6
        editHost.layer?.shadowOffset = CGSize(width: 0, height: -0.5)
        editHost.layer?.zPosition = 20
        editHost.isHidden = true

        editBadge.translatesAutoresizingMaskIntoConstraints = false
        editBadge.imageScaling = .scaleProportionallyDown
        editHost.addSubview(editBadge)
        addSubview(editHost)
        NSLayoutConstraint.activate([
            shimmerHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            shimmerHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            shimmerHost.topAnchor.constraint(equalTo: topAnchor),
            shimmerHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            editHost.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            editHost.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            editHost.widthAnchor.constraint(equalToConstant: 18),
            editHost.heightAnchor.constraint(equalToConstant: 18),
            editBadge.centerXAnchor.constraint(equalTo: editHost.centerXAnchor),
            editBadge.centerYAnchor.constraint(equalTo: editHost.centerYAnchor),
            editBadge.widthAnchor.constraint(equalToConstant: 12),
            editBadge.heightAnchor.constraint(equalToConstant: 12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownModifiers = event.modifierFlags
        isHighlighted = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasHighlighted = isHighlighted
        isHighlighted = false
        let local = convert(event.locationInWindow, from: nil)
        guard wasHighlighted, bounds.contains(local) else { return }
        // Prefer mouse-down modifiers — more reliable than NSApp.currentEvent in button actions.
        onClick?(mouseDownModifiers.union(event.modifierFlags))
    }

    override func mouseDragged(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        isHighlighted = bounds.contains(local)
    }

    func setDevelopMark(_ mark: FilmstripDevelopMark) {
        developMark = mark
        guard mark != .none else {
            editHost.isHidden = true
            editBadge.image = nil
            return
        }
        let symbolName = mark == .dirty ? "pencil.circle" : "pencil.circle.fill"
        let accessibility = mark == .dirty ? "Unsaved edits" : "Saved edits"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibility) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            let configured = image.withSymbolConfiguration(config) ?? image
            configured.isTemplate = true
            editBadge.image = configured
        }
        // White / accent glyph on a dark plate so the mark reads on light and dark photos.
        editBadge.contentTintColor = mark == .dirty
            ? NSColor.white.withAlphaComponent(0.92)
            : LaughTheme.interactiveAccent
        editHost.isHidden = false
    }

    func beginLoadingShimmer() {
        guard image == nil else {
            stopLoadingShimmer()
            return
        }
        shimmerHost.isHidden = false
        shimmerHost.startAnimating()
    }

    func applyThumbnail(_ thumbnail: NSImage?) {
        title = ""
        alternateTitle = ""
        image = thumbnail
        if thumbnail != nil {
            stopLoadingShimmer()
        } else {
            beginLoadingShimmer()
        }
    }

    private func stopLoadingShimmer() {
        shimmerHost.stopAnimating()
        shimmerHost.isHidden = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        shimmerHost.refreshColors()
    }

    override func layout() {
        super.layout()
        let corner = layer?.cornerRadius ?? 7
        hoverWash.frame = bounds
        hoverWash.cornerRadius = corner
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Shimmer / badge must not steal clicks from the button.
        let hit = super.hitTest(point)
        if hit === shimmerHost || hit === editHost || hit === editBadge {
            return self
        }
        return hit
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        tracking = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHoverBright(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHoverBright(false)
    }

    private func setHoverBright(_ on: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        hoverWash.opacity = on ? 1 : 0
        CATransaction.commit()
    }
}

/// Skeleton wash above the NSButton cell (sublayers get covered by AppKit drawing).
private final class FilmstripShimmerView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 7
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(gradient)
        refreshColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        gradient.frame = bounds
        gradient.cornerRadius = layer?.cornerRadius ?? 7
    }

    func refreshColors() {
        // High-contrast on dark studio floor — chrome fills alone read as “empty”.
        let base = NSColor.white.withAlphaComponent(0.06)
        let peak = NSColor.white.withAlphaComponent(0.22)
        gradient.colors = [base.cgColor, peak.cgColor, base.cgColor]
        gradient.locations = [-0.4, -0.2, 0.0] as [NSNumber]
    }

    func startAnimating() {
        refreshColors()
        guard gradient.animation(forKey: "shimmer") == nil else { return }
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-0.5, -0.25, 0.0]
        animation.toValue = [1.0, 1.25, 1.5]
        animation.duration = 0.95
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(animation, forKey: "shimmer")
    }

    func stopAnimating() {
        gradient.removeAnimation(forKey: "shimmer")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Horizontal filmstrip: map vertical wheel / trackpad scroll onto sideways scrubbing.
private final class FilmstripScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY

        // Native horizontal gestures keep their axis; vertical wheel becomes sideways scrub.
        if abs(dx) >= abs(dy), abs(dx) > 0.01 {
            super.scrollWheel(with: event)
            return
        }
        guard abs(dy) > 0.01, let document = documentView else {
            super.scrollWheel(with: event)
            return
        }

        let clip = contentView
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        var origin = clip.bounds.origin
        // Scroll up → earlier thumbs; scroll down → later thumbs.
        origin.x -= dy * scale
        let maxX = max(0, document.bounds.width - clip.bounds.width)
        origin.x = min(max(origin.x, 0), maxX)
        origin.y = clip.bounds.origin.y
        clip.scroll(to: origin)
        reflectScrolledClipView(clip)
    }
}

/// Soft edge veil that dissolves filmstrip thumbs into the studio backdrop color.
private final class FadeEdgeView: NSView {
    enum Edge {
        case leading
        case trailing
    }

    private let edge: Edge

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let floor = sampledStudioFloorColor()
        // Hold opaque coverage longer so thumbs vanish into the real studio floor.
        let deep = floor.withAlphaComponent(1)
        let heavy = floor.withAlphaComponent(0.97)
        let mid = floor.withAlphaComponent(0.72)
        let soft = floor.withAlphaComponent(0.28)
        let clear = floor.withAlphaComponent(0)

        let colors: [NSColor]
        let locations: [CGFloat]
        switch edge {
        case .leading:
            colors = [deep, heavy, mid, soft, clear]
            locations = [0, 0.28, 0.55, 0.82, 1]
        case .trailing:
            colors = [clear, soft, mid, heavy, deep]
            locations = [0, 0.18, 0.45, 0.72, 1]
        }

        guard let gradient = NSGradient(colors: colors, atLocations: locations, colorSpace: .deviceRGB) else {
            floor.setFill()
            dirtyRect.fill()
            return
        }
        gradient.draw(in: bounds, angle: 0)
    }

    /// Match the flat studio floor `DragHostView` actually paints (not a lighter wash).
    private func sampledStudioFloorColor() -> NSColor {
        LaughTheme.imageStudioFloorColor(appearance: effectiveAppearance)
    }
}
