import AppKit

LaunchLog.emit("main: starting")
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
LaunchLog.emit("main: entering run loop")
app.run()
