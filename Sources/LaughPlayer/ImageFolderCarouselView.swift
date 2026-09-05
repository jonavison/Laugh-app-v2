import AppKit
import ImageIO
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
    private var thumbnailButtons: [URL: NSButton] = [:]
    private var loadGeneration = 0
    private var clipObserver: NSObjectProtocol?

    /// Near-square crop-fill previews.
    private static let thumbSide: CGFloat = 80
    /// Wide enough that an edge thumb clearly dissolves into the studio floor.
    private static let fadeWidth: CGFloat = 96

    func applyStudioChromeBackground() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        needsDisplay = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

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

    override func layout() {
        super.layout()
        layer?.backgroundColor = NSColor.clear.cgColor
        updateFadeVisibility()
    }

    func setImages(_ files: [LibraryMediaFile], selected: URL?) {
        let newURLs = files.map(\.url.standardizedFileURL)
        let previousURLs = urls.map(\.standardizedFileURL)
        selectedURL = selected?.standardizedFileURL

        // Same folder strip: only restyle selection — avoid full rebuild / thumb flicker.
        if newURLs == previousURLs, !thumbnailButtons.isEmpty {
            for (url, button) in thumbnailButtons {
                applySelectionChrome(button, selected: isSelected(url), animated: true)
            }
            scrollSelectedIntoViewIfNeeded()
            updateFadeVisibility()
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

    private func rebuildButtons() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        thumbnailButtons.removeAll()

        for url in urls {
            let button = NSButton(title: "", target: self, action: #selector(thumbPressed(_:)))
            button.bezelStyle = .regularSquare
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleAxesIndependently
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.layer?.masksToBounds = true
            button.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
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

    private func applySelectionChrome(_ button: NSButton, selected: Bool, animated: Bool = false) {
        button.wantsLayer = true
        guard let layer = button.layer else { return }

        let borderWidth: CGFloat = selected ? 2.5 : 1
        let borderColor = (selected
            ? LaughTheme.interactiveAccent
            : NSColor.separatorColor.withAlphaComponent(0.55)).cgColor
        let scale: CGFloat = selected ? 1.045 : 1.0

        let apply: () -> Void = {
            layer.borderWidth = borderWidth
            layer.borderColor = borderColor
            layer.transform = CATransform3DMakeScale(scale, scale, 1)
        }

        guard animated else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            apply()
            CATransaction.commit()
            return
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.28)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        apply()
        CATransaction.commit()
    }

    private func loadThumbnails() {
        loadGeneration += 1
        let generation = loadGeneration
        let targets = urls
        let maxSide = Self.thumbSide * 2
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for url in targets {
                let image = Self.makeThumbnail(at: url, maxSide: maxSide)
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
    private func centerSelectedThumbnailIfPossible(animated: Bool) {
        guard let selectedURL,
              let button = thumbnailButtons[selectedURL],
              let documentView = scrollView.documentView else { return }

        layoutSubtreeIfNeeded()
        stack.layoutSubtreeIfNeeded()

        let clipView = scrollView.contentView
        let clipBounds = clipView.bounds
        guard clipBounds.width > 1 else { return }

        let thumbInDocument = button.convert(button.bounds, to: documentView)
        let desiredOriginX = thumbInDocument.midX - (clipBounds.width / 2)

        let docWidth = max(documentView.frame.width, stack.fittingSize.width, clipBounds.width)
        let maxOriginX = max(0, docWidth - clipBounds.width)
        let clampedOriginX = min(max(0, desiredOriginX), maxOriginX)

        if abs(clampedOriginX - clipBounds.origin.x) < 0.5 {
            updateFadeVisibility()
            return
        }

        let target = NSPoint(x: clampedOriginX, y: clipBounds.origin.y)
        if animated {
            // Longer ease curve reads smoother when stepping through photos.
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.38
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1)
                context.allowsImplicitAnimation = true
                clipView.animator().setBoundsOrigin(target)
                self.scrollView.reflectScrolledClipView(clipView)
            }, completionHandler: { [weak self] in
                guard let self else { return }
                self.scrollView.reflectScrolledClipView(clipView)
                self.updateFadeVisibility()
            })
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            clipView.setBoundsOrigin(target)
            scrollView.reflectScrolledClipView(clipView)
            CATransaction.commit()
            updateFadeVisibility()
        }
    }

    @objc private func thumbPressed(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        let url = URL(fileURLWithPath: path)
        onSelect?(url)
    }

    private static func makeThumbnail(at url: URL, maxSide: CGFloat) -> NSImage? {
        let target = NSSize(width: thumbSide, height: thumbSide)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url).flatMap { cropFill($0, size: target) }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return cropFill(image, size: target)
    }

    private static func cropFill(_ image: NSImage, size: NSSize) -> NSImage {
        let output = NSImage(size: size)
        output.lockFocus()
        let src = image.size
        let scale = max(size.width / max(src.width, 1), size.height / max(src.height, 1))
        let drawSize = NSSize(width: src.width * scale, height: src.height * scale)
        let origin = NSPoint(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2
        )
        image.draw(
            in: NSRect(origin: origin, size: drawSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        output.unlockFocus()
        return output
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
