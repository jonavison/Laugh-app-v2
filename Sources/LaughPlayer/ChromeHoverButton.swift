import AppKit

/// Icon/text chrome control — hover brightens the tint, never a fill wash.
class ChromeHoverButton: NSButton {
    var horizontalPadding: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    /// Idle icon/label color. Hover steps this toward `.labelColor`.
    var idleTintColor: NSColor = .secondaryLabelColor {
        didSet { refreshHoverChrome() }
    }

    private var trackingAreaRef: NSTrackingArea?
    private(set) var isHovered = false {
        didSet { refreshHoverChrome() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        focusRingType = .none
        setButtonType(.momentaryChange)
        refreshHoverChrome()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += horizontalPadding * 2
        return size
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshHoverChrome()
    }

    func refreshHoverChrome() {
        let tint = isHovered
            ? LaughTheme.chromeHoverTint(from: idleTintColor)
            : idleTintColor
        contentTintColor = tint
        if attributedTitle.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: attributedTitle)
            mutable.addAttribute(
                .foregroundColor,
                value: tint,
                range: NSRange(location: 0, length: mutable.length)
            )
            attributedTitle = mutable
        }
        needsDisplay = true
    }
}
