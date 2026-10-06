import AppKit
import QuartzCore

/// Bottom filmstrip of sibling images in the same folder as the open **ImageMedia**.
/// Square-ish thumbs, tight spacing, scroll-edge gradient shadows (no scrollbar).
final class ImageFolderCarouselView: NSView {
    var onSelect: ((URL) -> Void)?

    private let scrollView = FilmstripScrollView()
    private let stack = NSStackView()
    private let leftFadeView = FadeEdgeView(edge: .leading)
    private let rightFadeView = FadeEdgeView(edge: .trailing)
    private var urls: [URL] = []
    private var selectedURL: URL?
    private var thumbnailButtons: [URL: FilmstripThumbButton] = [:]
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
        loadGeneration += 1
        rebuildButtons()
        updateFadeVisibility()
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
            applySelectionChrome(button, selected: false, animated: scrollMotion == .deliberate)
        }
        if let next, let button = thumbnailButtons[next] {
            applySelectionChrome(button, selected: true, animated: scrollMotion == .deliberate)
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
            let button = FilmstripThumbButton(
                title: "",
                target: self,
                action: #selector(thumbPressed(_:))
            )
            button.toolTip = url.lastPathComponent
            button.identifier = NSUserInterfaceItemIdentifier(url.path)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Self.thumbSide),
                button.heightAnchor.constraint(equalToConstant: Self.thumbSide)
            ])
            applySelectionChrome(button, selected: isSelected(url), animated: false)
            stack.addArrangedSubview(button)
            thumbnailButtons[url.standardizedFileURL] = button
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

    private func applySelectionChrome(_ button: FilmstripThumbButton, selected: Bool, animated: Bool = false) {
        button.wantsLayer = true
        guard let layer = button.layer else { return }

        // Selection is border-only — never scale the thumb (that reads as “bigger”).
        let borderWidth: CGFloat = selected ? 2.5 : 1
        let borderColor = (selected
            ? LaughTheme.interactiveAccent
            : NSColor.separatorColor.withAlphaComponent(0.55)).cgColor

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
        let targets = urls
        // Use the real display scale — hardcoding *2 goes soft on any screen above 2x.
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? MediaThumbnailGenerator.defaultScreenScale()
        let pointSide = Self.thumbSide
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for url in targets {
                let kind = MediaKindDetector.kind(for: url)
                let image = MediaThumbnailGenerator.squareThumbnail(
                    for: url,
                    kind: kind,
                    pointSide: pointSide,
                    screenScale: scale
                )
                DispatchQueue.main.async {
                    guard let self, self.loadGeneration == generation else { return }
                    guard let button = self.thumbnailButtons[url.standardizedFileURL] else { return }
                    button.image = image
                }
            }
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

    @objc private func thumbPressed(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        let url = URL(fileURLWithPath: path)
        onSelect?(url)
    }
}

/// Filmstrip cell with a brighten-on-hover wash (photo content, not chrome blue).
private final class FilmstripThumbButton: NSButton {
    private let hoverWash = CALayer()
    private var tracking: NSTrackingArea?

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        bezelStyle = .regularSquare
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        // Muted plate so transparent PNGs read correctly through the shared crop-fill path.
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor

        hoverWash.name = "filmstripHoverWash"
        hoverWash.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        hoverWash.opacity = 0
        hoverWash.zPosition = 10
        layer?.addSublayer(hoverWash)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        hoverWash.frame = bounds
        hoverWash.cornerRadius = layer?.cornerRadius ?? 7
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
