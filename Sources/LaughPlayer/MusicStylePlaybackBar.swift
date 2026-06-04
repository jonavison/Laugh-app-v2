import AppKit

/// Frosted playback bar with rounded corners; vibrancy blurs video beneath the bar.
final class RoundedPlaybackBarView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        MusicStylePlaybackBar.applyChrome(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        MusicStylePlaybackBar.syncRoundedShape(for: self)
    }
}

enum MusicStylePlaybackBar {
    static let maxBarWidth: CGFloat = 560
    static let minBarWidth: CGFloat = 360
    static let compactLayoutBreakpoint: CGFloat = 700
    /// Horizontal inset from window edges on narrow layouts (12pt each side).
    static let horizontalPaddingCompact: CGFloat = 12
    /// Horizontal inset from window edges on regular/wide layouts (24pt each side).
    static let horizontalPaddingRegular: CGFloat = 24
    static let minBarWidthCompact: CGFloat = 280
    /// Medium corner radius for the floating playback bar.
    static let barCornerRadius: CGFloat = 12
    static let barBottomInsetLow: CGFloat = 24
    static let barBottomInsetHigh: CGFloat = 100
    static let barBottomInsetRampStart: CGFloat = 720
    static let barBottomInsetRampEnd: CGFloat = 1440

    static func preferredBarBottomInset(forContentWidthPoints width: CGFloat) -> CGFloat {
        if width < barBottomInsetRampStart {
            return barBottomInsetLow
        }
        if width >= barBottomInsetRampEnd {
            return barBottomInsetHigh
        }
        let progress = (width - barBottomInsetRampStart) / (barBottomInsetRampEnd - barBottomInsetRampStart)
        return barBottomInsetLow + (barBottomInsetHigh - barBottomInsetLow) * progress
    }

    static func applyChrome(to bar: NSVisualEffectView) {
        bar.material = .hudWindow
        bar.blendingMode = .withinWindow
        bar.state = .active
        bar.isEmphasized = false
        bar.wantsLayer = true
        bar.layer?.cornerRadius = barCornerRadius
        bar.layer?.masksToBounds = true
        bar.layer?.backgroundColor = nil
        bar.layer?.borderWidth = 0
        bar.layer?.shadowColor = NSColor.black.cgColor
        bar.layer?.shadowOpacity = 0.22
        bar.layer?.shadowRadius = 14
        bar.layer?.shadowOffset = CGSize(width: 0, height: -3)
    }

    static func syncRoundedShape(for bar: NSVisualEffectView) {
        guard let layer = bar.layer else { return }
        let radius = barCornerRadius
        layer.cornerRadius = radius
        layer.masksToBounds = true
        let rounded = CGPath(
            roundedRect: bar.bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        layer.shadowPath = rounded
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
        if width < compactLayoutBreakpoint {
            let available = width - (horizontalPaddingCompact * 2)
            return max(minBarWidthCompact, available)
        }
        let available = max(minBarWidth, width - (horizontalPaddingRegular * 2))
        if width <= 1200 { return min(480, available) }
        return min(maxBarWidth, available)
    }
}
