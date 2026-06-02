import AppKit
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController {
    private let playerViewController = PlayerViewController()
    private let settingsStore = SettingsStore.shared

    init() {
        let initialContentSize = NSSize(width: 960, height: 600)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LaughPlayer"
        window.center()
        window.minSize = NSSize(width: 640, height: 400)
        super.init(window: window)

        window.contentViewController = playerViewController
        window.delegate = self

        playerViewController.delegate = self
        applyAspectPreference()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        if let window {
            window.setContentSize(NSSize(width: 960, height: 600))
            window.center()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
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
        if settingsStore.lockAspectRatioEnabled {
            if window?.contentAspectRatio == .zero {
                window?.contentAspectRatio = NSSize(width: 16, height: 9)
            }
        } else {
            window?.contentAspectRatio = .zero
        }
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
    func playerViewController(_ controller: PlayerViewController, didLoadMediaWithAspectRatio ratio: CGFloat) {
        guard ratio > 0 else { return }
        guard settingsStore.lockAspectRatioEnabled else { return }
        window?.contentAspectRatio = NSSize(width: ratio * 1000, height: 1000)
    }

    func playerViewControllerDidRequestOpenVideo(_ controller: PlayerViewController) {
        openVideoPanel()
    }

    func playerViewControllerDidRequestOpenSettings(_ controller: PlayerViewController) {
        NSApp.sendAction(Selector(("openPreferences")), to: nil, from: nil)
    }
}
