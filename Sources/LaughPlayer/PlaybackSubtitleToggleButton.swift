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
        alphaValue = 1
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

    override var isEnabled: Bool {
        didSet {
            // Keep full opacity — AppKit otherwise fades disabled accessory buttons.
            alphaValue = 1
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Skip super — accessory bezels / disabled fade introduce unwanted transparency.
        guard !isHidden else { return }

        let tint = Self.opaqueTint(from: contentTintColor ?? MusicStylePlaybackBar.accessoryIconTintColor)

        let text = Self.labelText as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: tint
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
        tint.setStroke()
        path.stroke()
    }

    private static func opaqueTint(from color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return NSColor(
            deviceRed: rgb.redComponent,
            green: rgb.greenComponent,
            blue: rgb.blueComponent,
            alpha: 1
        )
    }
}
