import AppKit
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController {
    private static let defaultWindowMinSize = NSSize(width: 640, height: 400)
    private static let windowFrameAutosaveName = "LaughPlayerMainWindow"

    private let playerViewController = PlayerViewController()
    private var shouldCenterOnNextPlacement = false
    private var didRestoreWindowFrame = false

    private var playbackWindow: PlaybackWindow? {
        window as? PlaybackWindow
    }

    init() {
        LaunchLog.emit("MainWindowController.init: begin")
        let initialContentSize = NSSize(width: 960, height: 600)
        let window = PlaybackWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LaughPlayer"
        window.minSize = Self.defaultWindowMinSize
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed, .participatesInCycle]
        super.init(window: window)

        window.delegate = self
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

        restoreOrPrepareWindowFrame()
        ImmersiveWindowChrome.configure(window: window)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        playerViewController.installPlayerInterfaceIfNeeded()
        playerViewController.prepareInterfaceForDisplay()
        applyAspectPreference()
        centerWindowIfNeeded()
        logWindowState("show")
    }

    private func restoreOrPrepareWindowFrame() {
        guard let window else { return }

        if window.frame.width < 64 || window.frame.height < 64 {
            window.setContentSize(NSSize(width: 960, height: 600))
        }

        guard !didRestoreWindowFrame else { return }
        didRestoreWindowFrame = true

        window.setFrameAutosaveName(Self.windowFrameAutosaveName)
        let restored = window.setFrameUsingName(Self.windowFrameAutosaveName)
        shouldCenterOnNextPlacement = !restored || !isWindowFrameOnScreen(window)
    }

    private func centerWindowIfNeeded() {
        guard shouldCenterOnNextPlacement, let window else { return }
        window.center()
        shouldCenterOnNextPlacement = false
    }

    private func isWindowFrameOnScreen(_ window: NSWindow) -> Bool {
        let frame = window.frame
        guard frame.width > 64, frame.height > 64 else { return false }
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
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
        playerViewController.prepareImmersiveChromeForFullscreenToggle()
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

    func openImagePanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = MediaKindDetector.openPanelImageContentTypes()
        if panel.runModal() == .OK, let url = panel.url {
            playerViewController.loadImage(url: url)
        }
    }

    func commandPlayPause() { playerViewController.commandTogglePlayPause() }
    func commandSeekBackward() { playerViewController.commandSeek(bySeconds: -10) }
    func commandSeekForward() { playerViewController.commandSeek(bySeconds: 10) }
    func commandSeekBackwardFine() { playerViewController.commandSeek(bySeconds: -1) }
    func commandSeekForwardFine() { playerViewController.commandSeek(bySeconds: 1) }
    func commandJumpToStart() { playerViewController.commandSeekToStart() }
    func commandJumpToEnd() { playerViewController.commandSeekToEnd() }
    func commandVolumeUp() { playerViewController.commandAdjustVolume(by: 0.05) }
    func commandVolumeDown() { playerViewController.commandAdjustVolume(by: -0.05) }
    func commandToggleMute() { playerViewController.commandToggleMute() }
    func commandSlower() { playerViewController.commandStepPlaybackSpeed(by: -1) }
    func commandFaster() { playerViewController.commandStepPlaybackSpeed(by: 1) }
    func commandNormalSpeed() { playerViewController.commandResetPlaybackSpeed() }
    func commandToggleLoop() { playerViewController.commandToggleLoopPlayback() }
    func commandQueuePrevious() { playerViewController.commandPlaybackQueuePrevious() }
    func commandQueueNext() { playerViewController.commandPlaybackQueueNext() }
    func commandToggleQueue() {
        playerViewController.toggleQueuePopoverFromShortcut()
    }
    func commandStopAndClose() { playerViewController.commandStopAndClose() }
    func commandToggleLibrary() { playerViewController.commandToggleLibraryPanel() }
    func commandToggleInspector() { playerViewController.commandToggleSettingsInspector() }
    func commandSelectSettingsTab(_ index: Int) { playerViewController.commandSelectSettingsTab(index) }
    func commandToggleFitFill() { playerViewController.commandToggleVideoFitMode() }
    func commandCycleAspect() { playerViewController.commandCycleWindowAspectPreset() }
    func commandToggleLockAspect() { playerViewController.commandToggleLockAspect() }
    func commandSwitchPlaySource() { playerViewController.commandTogglePlaybackSource() }
    func commandPreviousAudioTrack() { playerViewController.commandStepAudioTrack(forward: false) }
    func commandNextAudioTrack() { playerViewController.commandStepAudioTrack(forward: true) }
    func commandCycleEQ() { playerViewController.commandCycleEQPreset() }

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

    func windowDidExitFullScreen(_ notification: Notification) {
        reassertWindowAspectConstraintsFromSettings()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        reassertWindowAspectConstraintsFromSettings()
    }
}

extension MainWindowController: PlayerViewControllerDelegate {
    func playerViewController(_ controller: PlayerViewController, didRequestWindowAspectRatio ratio: CGFloat?) {
        applyWindowAspectRatioConstraints(ratio)
        guard let ratio, ratio > 0, let window, !window.styleMask.contains(.fullScreen) else { return }
        resizeWindowContent(toAspectRatio: ratio)
    }

    private func applyWindowAspectRatioConstraints(_ ratio: CGFloat?) {
        guard let window else { return }

        playbackWindow?.aspectLockRatio = ratio

        guard let ratio, ratio > 0 else {
            window.contentAspectRatio = .zero
            window.contentMinSize = .zero
            window.minSize = Self.defaultWindowMinSize
            return
        }

        window.contentAspectRatio = NSSize(width: ratio * 1000, height: 1000)
        let contentMin = PlaybackWindow.minimumContentSize(forAspectRatio: ratio)
        window.contentMinSize = contentMin
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentMin)).size
    }

    private func reassertWindowAspectConstraintsFromSettings() {
        applyWindowAspectRatioConstraints(activeLockedAspectRatio())
    }

    private func activeLockedAspectRatio() -> CGFloat? {
        playerViewController.resolvedWindowAspectRatio()
    }

    private func resizeWindowContent(toAspectRatio ratio: CGFloat) {
        guard let window, ratio > 0 else { return }

        let current = window.contentLayoutRect.size
        guard current.width > 1, current.height > 1 else { return }

        let minSize = window.contentMinSize
        var width = current.width
        var height = width / ratio

        if minSize.height > 0, height < minSize.height {
            height = minSize.height
            width = height * ratio
        }
        if minSize.width > 0, width < minSize.width {
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

    func playerViewController(
        _ controller: PlayerViewController,
        setImmersiveChromeVisible visible: Bool,
        animated: Bool
    ) {
        guard let window else { return }
        let playingName = controller.playingTitleForWindow()
        ImmersiveWindowChrome.setTitleBarVisible(visible, playingName: playingName, on: window, animated: animated)
    }
}
