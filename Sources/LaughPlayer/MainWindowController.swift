import AppKit
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController {
    private let playerViewController = PlayerViewController()

    init() {
        LaunchLog.emit("MainWindowController.init: begin")
        let initialContentSize = NSSize(width: 960, height: 600)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LaughPlayer"
        window.minSize = NSSize(width: 640, height: 400)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed, .participatesInCycle]
        super.init(window: window)

        window.delegate = self
        ensureWindowIsOnScreen()
        LaunchLog.emit("MainWindowController.init: end")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }

        if window.contentViewController == nil {
            LaunchLog.emit("MainWindowController.show: attaching player")
            playerViewController.delegate = self
            window.contentViewController = playerViewController
        }

        ensureWindowIsOnScreen()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Build the heavy UI after the window exists (viewDidLoad must stay minimal).
        playerViewController.installPlayerInterfaceIfNeeded()
        playerViewController.prepareInterfaceForDisplay()
        applyAspectPreference()
        logWindowState("show")
    }

    private func ensureWindowIsOnScreen() {
        guard let window else { return }

        if window.frame.width < 64 || window.frame.height < 64 {
            window.setContentSize(NSSize(width: 960, height: 600))
        }

        let frame = window.frame
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if !onScreen {
            window.center()
        }
    }

    private func logWindowState(_ context: String) {
        guard let window else { return }
        LaunchLog.emit("\(context): frame=\(window.frame) visible=\(window.isVisible) key=\(window.isKeyWindow)")
    }

    func openVideoPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true
        panel.allowedContentTypes = VideoAssetLoader.openPanelContentTypes()
        if panel.runModal() == .OK, let url = panel.url {
            playerViewController.loadVideo(url: url)
        }
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    func applyAspectPreference() {
        refreshWindowAspectFromSettings()
    }

    func refreshWindowAspectFromSettings() {
        playerViewController.refreshWindowAspectFromSettings()
    }

    func advancePlaybackQueue() {
        playerViewController.advancePlaybackQueue()
    }

    func showDebugInfoPanel() {
        let info = playerViewController.debugInfo(window: window)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Playback Debug Info"
        alert.informativeText = info
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(nil)
    }
}

extension MainWindowController: PlayerViewControllerDelegate {
    func playerViewController(_ controller: PlayerViewController, didRequestWindowAspectRatio ratio: CGFloat?) {
        guard let window else { return }

        guard let ratio, ratio > 0 else {
            window.contentAspectRatio = .zero
            return
        }

        window.contentAspectRatio = NSSize(width: ratio * 1000, height: 1000)
        guard !window.styleMask.contains(.fullScreen) else { return }
        resizeWindowContent(toAspectRatio: ratio)
    }

    private func resizeWindowContent(toAspectRatio ratio: CGFloat) {
        guard let window, ratio > 0 else { return }

        let current = window.contentLayoutRect.size
        guard current.width > 1, current.height > 1 else { return }

        let minSize = window.contentMinSize
        var width = current.width
        var height = width / ratio

        if height < minSize.height {
            height = minSize.height
            width = height * ratio
        }
        if width < minSize.width {
            width = minSize.width
            height = width / ratio
        }

        let target = NSSize(width: width.rounded(.toNearestOrAwayFromZero), height: height.rounded(.toNearestOrAwayFromZero))
        guard abs(target.width - current.width) > 1 || abs(target.height - current.height) > 1 else { return }
        window.setContentSize(target)
    }

    func playerViewControllerDidRequestOpenVideo(_ controller: PlayerViewController) {
        openVideoPanel()
    }

    func playerViewControllerDidRequestOpenSettings(_ controller: PlayerViewController) {
        NSApp.sendAction(#selector(AppDelegate.openPreferences), to: nil, from: nil)
    }
}
