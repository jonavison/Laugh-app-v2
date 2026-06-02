import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?
    private var preferencesWindowController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        let controller = MainWindowController()
        controller.show()
        windowController = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
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

        let viewItem = NSMenuItem()
        viewItem.submenu = buildViewMenu()
        menu.addItem(viewItem)

        NSApplication.shared.mainMenu = menu
    }

    private func buildAppMenu() -> NSMenu {
        let menu = NSMenu(title: "App")
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit LaughPlayer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func buildFileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        let open = NSMenuItem(title: "Open Video…", action: #selector(openVideo), keyEquivalent: "o")
        open.keyEquivalentModifierMask = [.command]
        menu.addItem(open)
        return menu
    }

    private func buildViewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        let fullscreen = NSMenuItem(title: "Toggle Full Screen", action: #selector(toggleFullScreen), keyEquivalent: "f")
        fullscreen.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(fullscreen)

        let debugInfo = NSMenuItem(title: "Show Playback Debug Info", action: #selector(showPlaybackDebugInfo), keyEquivalent: "D")
        debugInfo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(debugInfo)
        return menu
    }

    @objc private func openVideo() {
        windowController?.openVideoPanel()
    }

    @objc private func toggleFullScreen() {
        windowController?.toggleFullScreen()
    }

    @objc private func openPreferences() {
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
}
