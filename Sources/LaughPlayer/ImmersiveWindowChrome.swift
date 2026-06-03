import AppKit

/// Title bar + traffic lights that appear on window hover during focused playback.
enum ImmersiveWindowChrome {
    static let hideDelay: TimeInterval = 1.25
    static let animationDuration: TimeInterval = 0.22

    static func configure(window: NSWindow) {
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        setStandardButtonsHidden(true, on: window)
    }

    static func formattedTitle(playingName: String?) -> String {
        guard let playingName, !playingName.isEmpty else { return "LaughPlayer" }
        return "LaughPlayer – \(playingName)"
    }

    static func setStandardButtonsHidden(_ hidden: Bool, on window: NSWindow) {
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    static func titleBarStripHeight(for window: NSWindow?) -> CGFloat {
        guard let window, window.styleMask.contains(.fullSizeContentView) else { return 0 }
        return max(0, window.frame.height - window.contentLayoutRect.height)
    }

    /// Height of the frosted title-bar overlay (matches `titleBarChromeStrip` in the player).
    static func titleBarChromeStripHeight(for window: NSWindow?) -> CGFloat {
        max(28, titleBarStripHeight(for: window))
    }

    /// Gap between the bottom of the title-bar chrome and the first library row / toolbar.
    static let libraryContentGapBelowTitleChrome: CGFloat = 18

    /// Top inset for library sidebar / browse content below the title-bar chrome.
    static func libraryContentTopInset(for window: NSWindow?, chromeVisible: Bool) -> CGFloat {
        let baseContentInset: CGFloat = 18
        guard chromeVisible else { return baseContentInset }
        let strip = titleBarChromeStripHeight(for: window)
        return max(52, strip + libraryContentGapBelowTitleChrome)
    }

    static func applyFrostedPanelStyle(to effectView: NSVisualEffectView, leadingShadow: Bool) {
        effectView.material = .menu
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 0
        effectView.layer?.masksToBounds = false
        effectView.layer?.borderWidth = 0
        effectView.layer?.borderColor = nil
        effectView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.78).cgColor
        if leadingShadow {
            effectView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.22).cgColor
            effectView.layer?.shadowOpacity = 1
            effectView.layer?.shadowRadius = 16
            effectView.layer?.shadowOffset = NSSize(width: -3, height: 0)
        } else {
            effectView.layer?.shadowOpacity = 0
        }
    }

    static func setTitleBarVisible(_ visible: Bool, playingName: String?, on window: NSWindow, animated: Bool) {
        window.title = formattedTitle(playingName: playingName)
        let apply = {
            window.titleVisibility = visible ? .visible : .hidden
            setStandardButtonsHidden(!visible, on: window)
        }
        guard animated else {
            apply()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            apply()
        }
    }

}
