import AppKit

/// Non-blocking tip-style banner for playback / compatibility notices.
final class CompatibilityBannerView: NSVisualEffectView {
    private let iconView = NSImageView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private let closeButton = NSButton()
    private var messageBottomToBanner: NSLayoutConstraint?
    private var messageBottomToAction: NSLayoutConstraint?

    var onDismiss: (() -> Void)?
    var onAction: (() -> Void)?

    /// Soft warm yellow for the tip bulb (readable in light + dark).
    private static let tipIconColor = NSColor(calibratedRed: 0.92, green: 0.74, blue: 0.28, alpha: 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = Self.tipIconColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let image = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: "Tip") {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            iconView.image = image.withSymbolConfiguration(config)
        }

        messageLabel.font = .systemFont(ofSize: 12, weight: .medium)
        messageLabel.textColor = .labelColor
        messageLabel.maximumNumberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        actionButton.isHidden = true
        actionButton.isBordered = false
        actionButton.bezelStyle = .inline
        actionButton.setButtonType(.momentaryPushIn)
        actionButton.focusRingType = .none
        actionButton.font = .systemFont(ofSize: 11, weight: .semibold)
        actionButton.contentTintColor = LaughTheme.interactiveAccent
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.target = self
        actionButton.action = #selector(actionPressed)
        if let gear = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            actionButton.image = gear.withSymbolConfiguration(config)
            actionButton.imagePosition = .imageLeading
        }

        closeButton.isBordered = false
        closeButton.bezelStyle = .inline
        closeButton.setButtonType(.momentaryPushIn)
        closeButton.focusRingType = .none
        closeButton.toolTip = "Dismiss"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(dismissPressed)
        closeButton.contentTintColor = NSColor.secondaryLabelColor
        if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            closeButton.image = image.withSymbolConfiguration(config)
        }

        addSubview(iconView)
        addSubview(messageLabel)
        addSubview(actionButton)
        addSubview(closeButton)

        let messageBottom = messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11)
        let messageToAction = messageLabel.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -8)
        messageBottomToBanner = messageBottom
        messageBottomToAction = messageToAction

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),

            messageLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            messageLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            messageBottom,

            actionButton.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            actionButton.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    func show(message: String, actionTitle: String? = nil) {
        messageLabel.stringValue = message
        let hasAction = !(actionTitle ?? "").isEmpty
        actionButton.title = actionTitle ?? ""
        actionButton.isHidden = !hasAction
        messageBottomToBanner?.isActive = !hasAction
        messageBottomToAction?.isActive = hasAction
        isHidden = false
    }

    func hideBanner() {
        isHidden = true
        onAction = nil
        actionButton.isHidden = true
        messageBottomToAction?.isActive = false
        messageBottomToBanner?.isActive = true
    }

    @objc private func dismissPressed() {
        hideBanner()
        onDismiss?()
    }

    @objc private func actionPressed() {
        onAction?()
    }
}
