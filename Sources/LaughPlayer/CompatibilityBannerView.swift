import AppKit

/// Non-blocking tip-style banner for playback / compatibility notices.
final class CompatibilityBannerView: NSVisualEffectView {
    private let iconView = NSImageView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private let closeChrome = NSView()
    private let closeButton = NSButton()
    private var messageBottomToBanner: NSLayoutConstraint?
    private var messageBottomToAction: NSLayoutConstraint?
    private var autoDismissWorkItem: DispatchWorkItem?

    var onDismiss: (() -> Void)?
    var onAction: (() -> Void)?

    /// Soft warm yellow for the tip bulb (readable in light + dark).
    private static let tipIconColor = NSColor(calibratedRed: 0.92, green: 0.74, blue: 0.28, alpha: 1)
    private static let closeChromeSize: CGFloat = 20
    private static let defaultAutoDismissSec: TimeInterval = 6
    private static let actionAutoDismissSec: TimeInterval = 12

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

        configureCloseControl()

        addSubview(iconView)
        addSubview(messageLabel)
        addSubview(actionButton)
        addSubview(closeChrome)
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

            closeChrome.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeChrome.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            closeChrome.widthAnchor.constraint(equalToConstant: Self.closeChromeSize),
            closeChrome.heightAnchor.constraint(equalToConstant: Self.closeChromeSize),

            closeButton.centerXAnchor.constraint(equalTo: closeChrome.centerXAnchor),
            closeButton.centerYAnchor.constraint(equalTo: closeChrome.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: Self.closeChromeSize),
            closeButton.heightAnchor.constraint(equalToConstant: Self.closeChromeSize),

            messageLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            messageLabel.trailingAnchor.constraint(equalTo: closeChrome.leadingAnchor, constant: -8),
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            messageBottom,

            actionButton.leadingAnchor.constraint(equalTo: messageLabel.leadingAnchor),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            actionButton.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    private func configureCloseControl() {
        closeChrome.translatesAutoresizingMaskIntoConstraints = false
        closeChrome.wantsLayer = true
        closeChrome.layer?.cornerRadius = Self.closeChromeSize / 2
        closeChrome.layer?.masksToBounds = true
        closeChrome.setContentHuggingPriority(.required, for: .horizontal)
        closeChrome.setContentHuggingPriority(.required, for: .vertical)
        closeChrome.setContentCompressionResistancePriority(.required, for: .horizontal)
        closeChrome.setContentCompressionResistancePriority(.required, for: .vertical)
        refreshCloseChromeFill()

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.bezelStyle = .accessoryBarAction
        closeButton.setButtonType(.momentaryPushIn)
        closeButton.focusRingType = .none
        closeButton.toolTip = "Dismiss"
        closeButton.title = ""
        closeButton.imagePosition = .imageOnly
        closeButton.imageScaling = .scaleNone
        closeButton.target = self
        closeButton.action = #selector(dismissPressed)
        closeButton.contentTintColor = NSColor.secondaryLabelColor
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        closeButton.setContentHuggingPriority(.required, for: .vertical)
        closeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        closeButton.setContentCompressionResistancePriority(.required, for: .vertical)
        if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss") {
            let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            let symbol = image.withSymbolConfiguration(config)
            symbol?.isTemplate = true
            closeButton.image = symbol
        }
    }

    private func refreshCloseChromeFill() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Light wash circle — readable on the HUD tip without stretching the glyph.
        let fill = NSColor.labelColor.withAlphaComponent(isDark ? 0.18 : 0.10)
        closeChrome.layer?.backgroundColor = fill.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshCloseChromeFill()
    }

    func show(message: String, actionTitle: String? = nil) {
        messageLabel.stringValue = message
        let hasAction = !(actionTitle ?? "").isEmpty
        actionButton.title = actionTitle ?? ""
        actionButton.isHidden = !hasAction
        messageBottomToBanner?.isActive = !hasAction
        messageBottomToAction?.isActive = hasAction
        isHidden = false
        scheduleAutoDismiss(after: hasAction ? Self.actionAutoDismissSec : Self.defaultAutoDismissSec)
    }

    func hideBanner() {
        cancelAutoDismiss()
        isHidden = true
        onAction = nil
        actionButton.isHidden = true
        messageBottomToAction?.isActive = false
        messageBottomToBanner?.isActive = true
    }

    private func scheduleAutoDismiss(after seconds: TimeInterval) {
        cancelAutoDismiss()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isHidden else { return }
            self.hideBanner()
            self.onDismiss?()
        }
        autoDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelAutoDismiss() {
        autoDismissWorkItem?.cancel()
        autoDismissWorkItem = nil
    }

    @objc private func dismissPressed() {
        hideBanner()
        onDismiss?()
    }

    @objc private func actionPressed() {
        onAction?()
    }
}
