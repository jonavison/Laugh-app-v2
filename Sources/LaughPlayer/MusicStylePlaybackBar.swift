import AppKit

enum MusicStylePlaybackBar {
    static let maxBarWidth: CGFloat = 560
    static let minBarWidth: CGFloat = 360
    static let barCornerRadius: CGFloat = 16
    static let barBottomInset: CGFloat = 24

    static func applyChrome(to bar: NSVisualEffectView) {
        bar.material = .underWindowBackground
        bar.blendingMode = .behindWindow
        bar.state = .active
        bar.wantsLayer = true
        bar.layer?.cornerRadius = barCornerRadius
        bar.layer?.masksToBounds = false
        bar.layer?.shadowColor = NSColor.black.cgColor
        bar.layer?.shadowOpacity = 0.22
        bar.layer?.shadowRadius = 14
        bar.layer?.shadowOffset = CGSize(width: 0, height: -3)
    }

    static func iconButton(symbolName: String, accessibilityLabel: String, pointSize: CGFloat = 16) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.title = ""
        button.toolTip = accessibilityLabel
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel) {
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
            button.image?.isTemplate = true
        }
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    static func playPauseButton(pointSize: CGFloat = 22) -> NSButton {
        let button = iconButton(symbolName: "play.fill", accessibilityLabel: "Play", pointSize: pointSize)
        button.setButtonType(.momentaryPushIn)
        return button
    }

    static func preferredBarWidth(forContentWidthPoints width: CGFloat) -> CGFloat {
        let margin: CGFloat = 48
        let available = max(minBarWidth, width - margin)
        if width < 700 { return min(400, available) }
        if width <= 1200 { return min(480, available) }
        return min(maxBarWidth, available)
    }
}
