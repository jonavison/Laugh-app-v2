import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?
    private var preferencesWindowController: PreferencesWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        LaughTheme.activate()
        LaunchLog.emit("applicationWillFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchLog.emit("applicationDidFinishLaunching: begin")
        buildMainMenu()

        LaunchLog.emit("applicationDidFinishLaunching: creating main window")
        let controller = MainWindowController()
        windowController = controller
        LaunchLog.emit("applicationDidFinishLaunching: showing main window")
        controller.show()

        DispatchQueue.main.async { [weak self] in
            LaunchLog.emit("applicationDidFinishLaunching: bringMainWindowToFront")
            self?.bringMainWindowToFront()
        }
        LaunchLog.emit("applicationDidFinishLaunching: end")
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

    private func bringMainWindowToFront() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        windowController?.show()
        guard let window = windowController?.window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func applicationWillTerminate(_ notification: Notification) {
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

        let helpItem = NSMenuItem()
        helpItem.submenu = buildHelpMenu()
        menu.addItem(helpItem)

        NSApplication.shared.mainMenu = menu
    }

    private func menuItem(
        title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if !key.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    private func buildAppMenu() -> NSMenu {
        let menu = NSMenu(title: "App")
        menu.addItem(menuItem(title: "Preferences…", action: #selector(openPreferences), key: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Quit LaughPlayer", action: #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private func buildFileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(menuItem(title: "Open Video…", action: #selector(openVideo), key: "o"))
        menu.addItem(menuItem(title: "Open Image…", action: #selector(openImage), key: "O", modifiers: [.command, .shift]))
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
        menu.addItem(menuItem(title: "Keyboard Shortcuts…", action: #selector(showKeyboardShortcuts), key: "/"))
        return menu
    }

    // MARK: - File

    @objc private func openVideo() {
        windowController?.openVideoPanel()
    }

    @objc private func openImage() {
        windowController?.openImagePanel()
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
