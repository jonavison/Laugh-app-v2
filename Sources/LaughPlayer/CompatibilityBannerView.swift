import AppKit

/// Non-blocking compatibility banner (TryThenFailPolicy — shown after confirmed failure).
final class CompatibilityBannerView: NSVisualEffectView {
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let dismissButton = NSButton(title: "Dismiss", target: nil, action: nil)

    var onDismiss: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        material = .underWindowBackground
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false

        messageLabel.font = .systemFont(ofSize: 12, weight: .medium)
        messageLabel.textColor = .labelColor
        messageLabel.maximumNumberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        dismissButton.bezelStyle = .rounded
        dismissButton.controlSize = .small
        dismissButton.setContentHuggingPriority(.required, for: .horizontal)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.target = self
        dismissButton.action = #selector(dismissPressed)

        addSubview(messageLabel)
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            messageLabel.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -10),

            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func show(message: String) {
        messageLabel.stringValue = message
        isHidden = false
    }

    func hideBanner() {
        isHidden = true
    }

    @objc private func dismissPressed() {
        hideBanner()
        onDismiss?()
    }
}
