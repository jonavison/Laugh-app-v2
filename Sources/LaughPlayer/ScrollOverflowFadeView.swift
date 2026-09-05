import AppKit

/// Soft bottom (or top) fade over an `NSScrollView` that appears when more content is off-screen.
final class ScrollOverflowFadeView: NSView {
    enum Edge {
        case top
        case bottom
    }

    var edge: Edge = .bottom {
        didSet { needsDisplay = true }
    }

    /// Floor color the fade dissolves into (column chrome).
    var floorColor: NSColor = .windowBackgroundColor {
        didSet { needsDisplay = true }
    }

    private var overflowVisible = false
    private weak var observedScrollView: NSScrollView?
    private weak var observedDocument: NSView?
    private var boundsObserver: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?
    private var documentFrameObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        clipsToBounds = true
        layer?.masksToBounds = true
        alphaValue = 0
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        detach()
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func attach(to scrollView: NSScrollView) {
        detach()
        observedScrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.refreshOverflow()
        }
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.refreshOverflow()
        }
        if let document = scrollView.documentView {
            observedDocument = document
            document.postsFrameChangedNotifications = true
            documentFrameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: document,
                queue: .main
            ) { [weak self] _ in
                self?.refreshOverflow()
            }
        }
        refreshOverflow()
    }

    func detach() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
            self.frameObserver = nil
        }
        if let documentFrameObserver {
            NotificationCenter.default.removeObserver(documentFrameObserver)
            self.documentFrameObserver = nil
        }
        observedScrollView = nil
        observedDocument = nil
    }

    func refreshOverflow(animated: Bool = true) {
        guard let scrollView = observedScrollView,
              let document = scrollView.documentView else {
            setOverflowVisible(false, animated: animated)
            return
        }

        let clip = scrollView.contentView
        let docHeight = document.bounds.height
        let clipHeight = clip.bounds.height
        guard docHeight > clipHeight + 1 else {
            setOverflowVisible(false, animated: animated)
            return
        }

        let maxOffset = max(0, docHeight - clipHeight)
        let y = clip.bounds.origin.y
        let remaining: CGFloat
        switch edge {
        case .bottom:
            remaining = maxOffset - y
        case .top:
            remaining = y
        }
        setOverflowVisible(remaining > 2, animated: animated)
    }

    private func setOverflowVisible(_ visible: Bool, animated: Bool) {
        guard overflowVisible != visible || (visible && isHidden) || (!visible && alphaValue > 0.01) else {
            return
        }
        overflowVisible = visible
        isHidden = false
        let target: CGFloat = visible ? 1 : 0
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().alphaValue = target
            }, completionHandler: { [weak self] in
                guard let self, !self.overflowVisible else { return }
                self.isHidden = true
            })
        } else {
            alphaValue = target
            isHidden = !visible
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.height > 0.5 else { return }
        // Opaque floor (ignore any translucent wash) so content actually dissolves under the tabs.
        let floor = (floorColor.usingColorSpace(.deviceRGB) ?? floorColor)
            .withAlphaComponent(1)
        // Match filmstrip edge fades: hold coverage longer so cards vanish into the column.
        let deep = floor.withAlphaComponent(1)
        let heavy = floor.withAlphaComponent(0.92)
        let mid = floor.withAlphaComponent(0.58)
        let soft = floor.withAlphaComponent(0.22)
        let clear = floor.withAlphaComponent(0)

        let colors: [NSColor]
        let locations: [CGFloat]
        switch edge {
        case .bottom:
            // Transparent at top → solid floor at bottom edge.
            colors = [clear, soft, mid, heavy, deep]
            locations = [0, 0.18, 0.45, 0.72, 1]
        case .top:
            // Solid under tabs → transparent below.
            colors = [deep, heavy, mid, soft, clear]
            locations = [0, 0.28, 0.55, 0.82, 1]
        }

        guard let gradient = NSGradient(colors: colors, atLocations: locations, colorSpace: .deviceRGB) else {
            floor.setFill()
            dirtyRect.fill()
            return
        }
        // Flipped view: y=0 is top.
        gradient.draw(from: NSPoint(x: 0, y: 0), to: NSPoint(x: 0, y: bounds.height), options: [])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Hard clip for the settings scroll column — keeps overflow fades off the video surface.
final class SettingsScrollClipHostView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
