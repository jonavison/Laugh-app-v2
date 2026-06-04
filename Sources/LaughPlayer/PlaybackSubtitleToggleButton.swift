import AppKit

/// Small “SUB” control beside the library button; slash when subtitles are off.
final class PlaybackSubtitleToggleButton: NSButton {
    var subtitlesActive = false {
        didSet {
            guard oldValue != subtitlesActive else { return }
            needsDisplay = true
        }
    }

    private static let labelText = "SUB"
    private static let font = NSFont.systemFont(ofSize: 9, weight: .semibold)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .accessoryBarAction
        title = ""
        toolTip = "Toggle subtitles"
        setButtonType(.momentaryPushIn)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 26, height: MusicStylePlaybackBar.accessoryButtonHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !isHidden else { return }

        let text = Self.labelText as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: contentTintColor ?? NSColor.labelColor
        ]
        let textSize = text.size(withAttributes: attributes)
        let origin = NSPoint(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2
        )
        let textRect = NSRect(origin: origin, size: textSize)
        text.draw(in: textRect, withAttributes: attributes)

        guard !subtitlesActive else { return }

        let slashInset: CGFloat = 1
        let path = NSBezierPath()
        path.lineWidth = 1.25
        path.move(to: NSPoint(x: textRect.minX - slashInset, y: textRect.maxY + slashInset))
        path.line(to: NSPoint(x: textRect.maxX + slashInset, y: textRect.minY - slashInset))
        (contentTintColor ?? NSColor.labelColor).setStroke()
        path.stroke()
    }
}
