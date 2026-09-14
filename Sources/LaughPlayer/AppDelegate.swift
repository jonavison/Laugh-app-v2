import AppKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private var windowController: MainWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var pendingOpenFileURLs: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        LaughTheme.activate()
        SubtitleFont.registerIfNeeded()
        FFmpegVideoFallback.warmAvailabilityCache()
        FFmpegVideoFallback.enforceRemuxCacheBudget()
        MpvPlaybackController.warmAvailabilityCache()
        MediaThumbnailGenerator.performLaunchMigrations()
        LaunchLog.emit("applicationWillFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchLog.emit("applicationDidFinishLaunching: begin")
        buildMainMenu()
        LaughSparkleUpdater.install(into: self)

        LaunchLog.emit("applicationDidFinishLaunching: creating main window")
        let controller = MainWindowController()
        windowController = controller
        LaunchLog.emit("applicationDidFinishLaunching: showing main window")
        let openingFiles = !pendingOpenFileURLs.isEmpty
        controller.show(skipInitialLibrary: openingFiles)
        consumePendingOpenFileURLs()

        DispatchQueue.main.async { [weak self] in
            LaunchLog.emit("applicationDidFinishLaunching: bringMainWindowToFront")
            self?.bringMainWindowToFront()
        }
        LaunchLog.emit("applicationDidFinishLaunching: end")
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else {
            sender.reply(toOpenOrPrint: .success)
            return
        }
        LaunchLog.emit("application(openFiles): count=\(urls.count) first=\(urls[0].lastPathComponent)")
        if windowController?.window?.contentViewController != nil {
            openMediaURLs(urls)
        } else {
            pendingOpenFileURLs.append(contentsOf: urls)
        }
        bringMainWindowToFront()
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let window = windowController?.window, !window.isMiniaturized else { return }
        if !window.isVisible {
            bringMainWindowToFront()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController?.show()
        }
        bringMainWindowToFront()
        return true
    }

    /// Custom items appear above the system Dock menu (Show All Windows, Options, Quit…).
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "Dock")
        menu.addItem(dockMenuItem(title: "Open…", action: #selector(dockOpenMedia)))
        menu.addItem(dockMenuItem(title: "Open Folder…", action: #selector(dockOpenFolder)))
        menu.addItem(.separator())
        menu.addItem(dockMenuItem(title: "Play / Pause", action: #selector(dockPlayPause)))
        menu.addItem(dockMenuItem(title: "Stop and Close", action: #selector(dockStopAndClose)))
        menu.addItem(.separator())
        menu.addItem(dockMenuItem(title: "Toggle Library", action: #selector(dockToggleLibrary)))
        menu.addItem(dockMenuItem(title: "Preferences…", action: #selector(dockOpenPreferences)))
        return menu
    }

    private func dockMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func dockOpenMedia() {
        bringMainWindowToFront()
        openMedia()
    }

    @objc private func dockOpenFolder() {
        bringMainWindowToFront()
        openFolder()
    }

    @objc private func dockPlayPause() {
        bringMainWindowToFront()
        commandPlayPause()
    }

    @objc private func dockStopAndClose() {
        bringMainWindowToFront()
        commandStopAndClose()
    }

    @objc private func dockToggleLibrary() {
        bringMainWindowToFront()
        commandToggleLibrary()
    }

    @objc private func dockOpenPreferences() {
        bringMainWindowToFront()
        openPreferences()
    }

    private func consumePendingOpenFileURLs() {
        guard !pendingOpenFileURLs.isEmpty else { return }
        let urls = pendingOpenFileURLs
        pendingOpenFileURLs.removeAll()
        openMediaURLs(urls)
    }

    private func openMediaURLs(_ urls: [URL]) {
        windowController?.openMediaURLs(urls)
    }

    private func bringMainWindowToFront() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard let window = windowController?.window else {
            windowController?.show()
            return
        }
        if window.contentViewController == nil {
            windowController?.show()
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.prepareForTermination()
        MpvPlaybackController.terminateRunningProcesses()
        FFmpegVideoFallback.terminateRunningProcesses()
        LibraryRootsStore.shared.stopAllSecurityScopedAccess()
    }

    private func buildMainMenu() {
        let menu = NSMenu()

        let appItem = NSMenuItem()
        appItem.submenu = buildAppMenu()
        menu.addItem(appItem)

        let fileItem = NSMenuItem()
        fileItem.submenu = buildFileMenu()
        menu.addItem(fileItem)

        let playbackItem = NSMenuItem()
        playbackItem.submenu = buildPlaybackMenu()
        menu.addItem(playbackItem)

        let viewItem = NSMenuItem()
        viewItem.submenu = buildViewMenu()
        menu.addItem(viewItem)

        let audioItem = NSMenuItem()
        audioItem.submenu = buildAudioMenu()
        menu.addItem(audioItem)

        let windowItem = NSMenuItem()
        windowItem.submenu = buildWindowMenu()
        menu.addItem(windowItem)

        let helpItem = NSMenuItem()
        helpItem.submenu = buildHelpMenu()
        menu.addItem(helpItem)

        NSApplication.shared.mainMenu = menu
    }

    private func menuItem(
        title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        // nil target → responder chain / NSApp (required for terminate: / performClose:).
        item.target = target ?? self
        if !key.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    /// System actions that must not target AppDelegate (validation would disable them).
    private func systemMenuItem(
        title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = nil
        if !key.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    private func buildAppMenu() -> NSMenu {
        let menu = NSMenu(title: "LaughPlayer")
        menu.addItem(menuItem(title: "About LaughPlayer", action: #selector(showAbout), key: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Preferences…", action: #selector(openPreferences), key: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(systemMenuItem(title: "Quit LaughPlayer", action: #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private func buildFileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(menuItem(title: "Open…", action: #selector(openMedia), key: "o"))
        menu.addItem(menuItem(title: "Open Folder…", action: #selector(openFolder), key: "O", modifiers: [.command, .shift]))
        return menu
    }

    private func buildWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(systemMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), key: "w"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(systemMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(systemMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), key: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(systemMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), key: ""))
        return menu
    }

    private func buildPlaybackMenu() -> NSMenu {
        let menu = NSMenu(title: "Playback")
        menu.addItem(menuItem(title: "Play / Pause", action: #selector(commandPlayPause), key: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Seek Backward 10 Seconds", action: #selector(commandSeekBackward), key: ""))
        menu.addItem(menuItem(title: "Seek Forward 10 Seconds", action: #selector(commandSeekForward), key: ""))
        menu.addItem(menuItem(title: "Seek Backward 1 Second", action: #selector(commandSeekBackwardFine), key: "", modifiers: [.option]))
        menu.addItem(menuItem(title: "Seek Forward 1 Second", action: #selector(commandSeekForwardFine), key: "", modifiers: [.option]))
        menu.addItem(menuItem(title: "Jump to Start", action: #selector(commandJumpToStart), key: ""))
        menu.addItem(menuItem(title: "Jump to End", action: #selector(commandJumpToEnd), key: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Volume Up", action: #selector(commandVolumeUp), key: ""))
        menu.addItem(menuItem(title: "Volume Down", action: #selector(commandVolumeDown), key: ""))
        menu.addItem(menuItem(title: "Mute", action: #selector(commandToggleMute), key: "m", modifiers: [.option]))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Slower", action: #selector(commandSlower), key: "-"))
        menu.addItem(menuItem(title: "Faster", action: #selector(commandFaster), key: "="))
        menu.addItem(menuItem(title: "Normal Speed", action: #selector(commandNormalSpeed), key: "0"))
        menu.addItem(menuItem(title: "Toggle Loop", action: #selector(commandToggleLoop), key: "L", modifiers: [.command, .shift]))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Previous in Queue", action: #selector(commandQueuePrevious), key: "["))
        menu.addItem(menuItem(title: "Next in Queue", action: #selector(commandQueueNext), key: "]"))
        menu.addItem(menuItem(title: "Toggle Queue", action: #selector(commandToggleQueue), key: "U", modifiers: [.command, .shift]))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Stop and Close", action: #selector(commandStopAndClose), key: "."))
        return menu
    }

    private func buildViewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(menuItem(title: "Toggle Library", action: #selector(commandToggleLibrary), key: "l"))
        menu.addItem(menuItem(title: "Toggle Settings Inspector", action: #selector(commandToggleInspector), key: "i"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Video Tab", action: #selector(commandVideoTab), key: "1"))
        menu.addItem(menuItem(title: "Audio Tab", action: #selector(commandAudioTab), key: "2"))
        menu.addItem(menuItem(title: "Subtitles Tab", action: #selector(commandSubtitlesTab), key: "3"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Toggle Fit / Fill", action: #selector(commandToggleFitFill), key: ""))
        menu.addItem(menuItem(title: "Cycle Window Aspect", action: #selector(commandCycleAspect), key: "a", modifiers: [.command, .control]))
        menu.addItem(menuItem(title: "Toggle Lock Aspect", action: #selector(commandToggleLockAspect), key: "K", modifiers: [.command, .shift]))
        menu.addItem(menuItem(title: "Switch Play Source", action: #selector(commandSwitchPlaySource), key: "S", modifiers: [.command, .shift]))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Toggle Full Screen", action: #selector(toggleFullScreen), key: "f", modifiers: [.command, .control]))
        menu.addItem(menuItem(title: "Show Playback Debug Info", action: #selector(showPlaybackDebugInfo), key: "D", modifiers: [.command, .shift]))
        return menu
    }

    private func buildAudioMenu() -> NSMenu {
        let menu = NSMenu(title: "Audio")
        menu.addItem(menuItem(title: "Previous Audio Track", action: #selector(commandPreviousAudioTrack), key: "", modifiers: [.command, .option]))
        menu.addItem(menuItem(title: "Next Audio Track", action: #selector(commandNextAudioTrack), key: "", modifiers: [.command, .option]))
        menu.addItem(menuItem(title: "Cycle EQ Preset", action: #selector(commandCycleEQ), key: "e", modifiers: [.command, .option]))
        return menu
    }

    private func buildHelpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        if LaughSparkleUpdater.isAvailable {
            menu.addItem(menuItem(title: "Check for Updates…", action: #selector(checkForUpdates), key: ""))
            menu.addItem(NSMenuItem.separator())
        }
        menu.addItem(menuItem(title: "Keyboard Shortcuts…", action: #selector(showKeyboardShortcuts), key: "/"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Laugh on the Web…", action: #selector(openLaughWebsite), key: ""))
        return menu
    }

    // MARK: - App / Help

    @objc private func showAbout() {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "LaughPlayer",
            .version: build,
            .applicationVersion: short
        ]
        if let credits = aboutCreditsAttributedString() {
            options[.credits] = credits
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    private func aboutCreditsAttributedString() -> NSAttributedString? {
        let text = "Avison · avison-soft.com/laugh"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        return NSAttributedString(string: text, attributes: attrs)
    }

    @objc private func checkForUpdates() {
        LaughSparkleUpdater.checkForUpdates()
    }

    @objc private func openLaughWebsite() {
        guard let url = URL(string: "https://avison-soft.com/laugh") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - File

    @objc private func openMedia() {
        windowController?.openMediaPanel()
    }

    @objc private func openFolder() {
        windowController?.openFolderPanel()
    }

    // MARK: - Playback commands

    @objc private func commandPlayPause() { windowController?.commandPlayPause() }
    @objc private func commandSeekBackward() { windowController?.commandSeekBackward() }
    @objc private func commandSeekForward() { windowController?.commandSeekForward() }
    @objc private func commandSeekBackwardFine() { windowController?.commandSeekBackwardFine() }
    @objc private func commandSeekForwardFine() { windowController?.commandSeekForwardFine() }
    @objc private func commandJumpToStart() { windowController?.commandJumpToStart() }
    @objc private func commandJumpToEnd() { windowController?.commandJumpToEnd() }
    @objc private func commandVolumeUp() { windowController?.commandVolumeUp() }
    @objc private func commandVolumeDown() { windowController?.commandVolumeDown() }
    @objc private func commandToggleMute() { windowController?.commandToggleMute() }
    @objc private func commandSlower() { windowController?.commandSlower() }
    @objc private func commandFaster() { windowController?.commandFaster() }
    @objc private func commandNormalSpeed() { windowController?.commandNormalSpeed() }
    @objc private func commandToggleLoop() { windowController?.commandToggleLoop() }
    @objc private func commandQueuePrevious() { windowController?.commandQueuePrevious() }
    @objc private func commandQueueNext() { windowController?.commandQueueNext() }
    @objc private func commandToggleQueue() { windowController?.commandToggleQueue() }
    @objc private func commandStopAndClose() { windowController?.commandStopAndClose() }

    // MARK: - View commands

    @objc private func commandToggleLibrary() { windowController?.commandToggleLibrary() }
    @objc private func commandToggleInspector() { windowController?.commandToggleInspector() }
    @objc private func commandVideoTab() { windowController?.commandSelectSettingsTab(0) }
    @objc private func commandAudioTab() { windowController?.commandSelectSettingsTab(1) }
    @objc private func commandSubtitlesTab() { windowController?.commandSelectSettingsTab(2) }
    @objc private func commandToggleFitFill() { windowController?.commandToggleFitFill() }
    @objc private func commandCycleAspect() { windowController?.commandCycleAspect() }
    @objc private func commandToggleLockAspect() { windowController?.commandToggleLockAspect() }
    @objc private func commandSwitchPlaySource() { windowController?.commandSwitchPlaySource() }

    // MARK: - Audio commands

    @objc private func commandPreviousAudioTrack() { windowController?.commandPreviousAudioTrack() }
    @objc private func commandNextAudioTrack() { windowController?.commandNextAudioTrack() }
    @objc private func commandCycleEQ() { windowController?.commandCycleEQ() }

    // MARK: - App

    @objc private func toggleFullScreen() {
        windowController?.toggleFullScreen()
    }

    @objc func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
            preferencesWindowController?.onSettingsChange = { [weak self] in
                self?.windowController?.applyAspectPreference()
            }
        }
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func showPlaybackDebugInfo() {
        windowController?.showDebugInfoPanel()
    }

    @objc private func showKeyboardShortcuts() {
        KeyboardShortcutsReference.showHelpPanel()
    }
}
