import AppKit

enum KeyboardShortcutsReference {
    static func showHelpPanel() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 420))
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.font = .systemFont(ofSize: 12)
        text.string = helpText
        text.autoresizingMask = [.width, .height]
        scroll.documentView = text

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Keyboard Shortcuts"
        panel.contentView = scroll
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static let helpText = """
    PLAYBACK (video)
    Space — Play / Pause
    ← / → — Seek ±10 seconds
    ⌥← / ⌥→ — Seek ±1 second
    Home / End — Jump to start / end
    ↑ / ↓ — Volume up / down
    ⌥M — Mute / unmute
    ⌘- / ⌘+ — Slower / faster
    ⌘0 — Normal speed (1×)
    ⌘⇧L — Loop on / off
    ⌘[ / ⌘] — Previous / next in queue
    ⌘⇧U — Toggle queue list
    Esc — Pause while playing; stop when paused
    ⌘. — Stop and close (empty surface)

    VIEW & WINDOW
    ⌘O — Open video…
    ⌘⇧O — Open image…
    ⌘L — Toggle library panel
    ⌘I — Toggle settings inspector
    ⌃⌘F — Toggle full screen
    F — Toggle video fit / fill
    ⌃⌘A — Cycle window aspect preset
    ⌘⇧K — Toggle lock window aspect
    ⌘1 / ⌘2 / ⌘3 — Video / Audio / Subtitles tab

    AUDIO (video, when available)
    ⌥⌘← / ⌥⌘→ — Previous / next audio track
    ⌥⌘E — Cycle EQ preset (extended playback only)

    IMAGE
    ⌘+ / ⌘- — Zoom in / out
    ⌘0 — Reset zoom (fit)

    LIBRARY (browse grid visible)
    ⌘⌥← / ⌘⌥→ — Browse back / forward

    APP
    ⌘, — Preferences
    ⌘⇧D — Playback debug info
    ⌘/ — This shortcuts reference
    ⌘Q — Quit

    COMING SOON
    , / . — Frame back / forward (both engines)
    V / G — Subtitle toggle / cycle (when subtitles ship)
    """
}
