import AppKit

final class PreferencesWindowController: NSWindowController {
    var onSettingsChange: (() -> Void)?

    private let lockAspectCheckbox: NSButton = {
        let button = NSButton(checkboxWithTitle: "Lock window to video aspect ratio", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    init() {
        let contentSize = NSSize(width: 420, height: 140)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let rootView = NSView(frame: NSRect(origin: .zero, size: contentSize))
        window.contentView = rootView
        rootView.addSubview(lockAspectCheckbox)
        NSLayoutConstraint.activate([
            lockAspectCheckbox.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 20),
            lockAspectCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -20),
            lockAspectCheckbox.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 24)
        ])

        lockAspectCheckbox.state = SettingsStore.shared.lockAspectRatioEnabled ? .on : .off
        lockAspectCheckbox.target = self
        lockAspectCheckbox.action = #selector(toggleAspectLock)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggleAspectLock() {
        SettingsStore.shared.lockAspectRatioEnabled = (lockAspectCheckbox.state == .on)
        onSettingsChange?()
    }
}
