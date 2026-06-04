import AppKit

/// Small settings toggle — teal when on, neutral when off.
final class CompactTealToggle: NSControl {
    private static let trackWidth: CGFloat = 26
    private static let trackHeight: CGFloat = 14
    private static let thumbDiameter: CGFloat = 10
    private static let thumbInset: CGFloat = 2

    private(set) var isOn = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.trackWidth + 4, height: max(20, Self.trackHeight + 6))
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    func applySwitchState(_ on: Bool) {
        guard isOn != on else { return }
        isOn = on
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        alphaValue = isEnabled ? 1 : 0.45
        let trackRect = NSRect(
            x: (bounds.width - Self.trackWidth) / 2,
            y: (bounds.height - Self.trackHeight) / 2,
            width: Self.trackWidth,
            height: Self.trackHeight
        )
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: Self.trackHeight / 2, yRadius: Self.trackHeight / 2)
        let trackColor = isOn
            ? LaughTheme.accent
            : NSColor.separatorColor.withAlphaComponent(0.55)
        trackColor.setFill()
        trackPath.fill()

        let thumbX = isOn
            ? trackRect.maxX - Self.thumbDiameter - Self.thumbInset
            : trackRect.minX + Self.thumbInset
        let thumbRect = NSRect(
            x: thumbX,
            y: trackRect.midY - Self.thumbDiameter / 2,
            width: Self.thumbDiameter,
            height: Self.thumbDiameter
        )
        NSColor.white.setFill()
        NSBezierPath(ovalIn: thumbRect).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isOn.toggle()
        needsDisplay = true
        sendAction(action, to: target)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
