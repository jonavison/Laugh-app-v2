import AppKit

/// Fully rounded toolbar chip — content-sized stack so label never compresses.
final class LibraryPillButton: NSButton {
    enum Style {
        case labeled
        case iconOnly
    }

    private let style: Style
    private let pillHeight: CGFloat = 30
    private let horizontalPadding: CGFloat = 12
    private let iconPointSize: CGFloat = 11
    private let iconLabelSpacing: CGFloat = 6
    private let labelText: String
    private let symbolName: String?

    private let contentStack = NSStackView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    init(title: String, symbol: String?, style: Style, toolTip: String?) {
        self.style = style
        self.labelText = title
        self.symbolName = symbol
        super.init(frame: .zero)
        self.toolTip = toolTip
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        if style == .iconOnly {
            return NSSize(width: pillHeight, height: pillHeight)
        }
        var width = horizontalPadding * 2
        if symbolName != nil {
            width += iconPointSize + iconLabelSpacing
        }
        width += titleLabel.intrinsicContentSize.width
        return NSSize(width: ceil(width), height: pillHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChrome()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    func refreshChrome() {
        let appearance = effectiveAppearance
        layer?.backgroundColor = LaughTheme.chromeHoverFill(appearance: appearance).cgColor
        iconView.contentTintColor = .labelColor
        titleLabel.textColor = .labelColor
    }

    private func configure() {
        wantsLayer = true
        layer?.masksToBounds = true
        isBordered = false
        bezelStyle = .inline
        focusRingType = .none
        setButtonType(.momentaryChange)
        title = ""
        image = nil
        imagePosition = .noImage
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: pillHeight).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = iconLabelSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.isHidden = style == .iconOnly
        addSubview(contentStack)

        iconView.imageScaling = .scaleNone
        iconView.imageAlignment = .alignCenter
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.lineBreakMode = .byClipping
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.stringValue = labelText

        if style == .iconOnly {
            widthAnchor.constraint(equalToConstant: pillHeight).isActive = true
            iconView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 12),
                iconView.heightAnchor.constraint(equalToConstant: 12)
            ])
        } else {
            if symbolName != nil {
                contentStack.addArrangedSubview(iconView)
                NSLayoutConstraint.activate([
                    iconView.widthAnchor.constraint(equalToConstant: iconPointSize),
                    iconView.heightAnchor.constraint(equalToConstant: iconPointSize)
                ])
            }
            contentStack.addArrangedSubview(titleLabel)
            NSLayoutConstraint.activate([
                contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
                contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
                contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: horizontalPadding),
                trailingAnchor.constraint(greaterThanOrEqualTo: contentStack.trailingAnchor, constant: horizontalPadding)
            ])
        }

        applyIcon()
        refreshChrome()
        invalidateIntrinsicContentSize()
    }

    private func applyIcon() {
        guard let symbolName,
              let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip ?? labelText)
        else {
            iconView.image = nil
            return
        }
        let pointSize: CGFloat = style == .iconOnly ? 12 : iconPointSize
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let configured = image.withSymbolConfiguration(config) else { return }
        configured.isTemplate = true
        configured.size = NSSize(width: pointSize, height: pointSize)
        iconView.image = configured
        iconView.contentTintColor = .labelColor
    }
}

/// Icon-only rounded button that presents a menu (centered glyph, no stretch).
final class LibraryPillPopUp: NSButton {
    private let pillHeight: CGFloat = 30
    private let iconPointSize: CGFloat = 12
    private let symbolName: String
    private var itemsMenu = NSMenu()
    private let iconView = NSImageView()

    init(symbol: String, toolTip: String) {
        self.symbolName = symbol
        super.init(frame: .zero)
        self.toolTip = toolTip
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: pillHeight, height: pillHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChrome()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    func refreshChrome() {
        let appearance = effectiveAppearance
        layer?.backgroundColor = LaughTheme.chromeHoverFill(appearance: appearance).cgColor
        iconView.contentTintColor = .labelColor
        applyIcon()
    }

    func setPullDownItems(_ items: [NSMenuItem], iconSymbol: String? = nil) {
        let menu = NSMenu()
        for item in items {
            menu.addItem(item)
        }
        itemsMenu = menu
        applyIcon(symbol: iconSymbol)
    }

    private func configure() {
        wantsLayer = true
        layer?.masksToBounds = true
        isBordered = false
        bezelStyle = .inline
        focusRingType = .none
        setButtonType(.momentaryChange)
        title = ""
        image = nil
        imagePosition = .noImage
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: pillHeight).isActive = true
        widthAnchor.constraint(equalToConstant: pillHeight).isActive = true
        target = self
        action = #selector(showMenuPressed)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleNone
        iconView.imageAlignment = .alignCenter
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconPointSize),
            iconView.heightAnchor.constraint(equalToConstant: iconPointSize)
        ])

        applyIcon()
        refreshChrome()
    }

    private func applyIcon(symbol: String? = nil) {
        let name = symbol ?? symbolName
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: toolTip) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .semibold)
        guard let configured = image.withSymbolConfiguration(config) else { return }
        configured.isTemplate = true
        configured.size = NSSize(width: iconPointSize, height: iconPointSize)
        iconView.image = configured
        iconView.contentTintColor = .labelColor
    }

    @objc private func showMenuPressed() {
        guard !itemsMenu.items.isEmpty else { return }
        let location = NSPoint(x: 0, y: bounds.height + 2)
        itemsMenu.popUp(positioning: nil, at: location, in: self)
    }
}

/// Labeled pill that opens a menu — sizes to its icon + title, never compresses text.
final class LibraryLabeledPillMenu: NSButton {
    private let pillHeight: CGFloat = 30
    private let horizontalPadding: CGFloat = 12
    private let iconPointSize: CGFloat = 11
    private let chevronPointSize: CGFloat = 8
    private let iconLabelSpacing: CGFloat = 6
    private let labelChevronSpacing: CGFloat = 5

    private let contentStack = NSStackView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()
    private var itemsMenu = NSMenu()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let width = horizontalPadding * 2
            + iconPointSize
            + iconLabelSpacing
            + titleLabel.intrinsicContentSize.width
            + labelChevronSpacing
            + chevronPointSize
        return NSSize(width: ceil(width), height: pillHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChrome()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    func refreshChrome() {
        let appearance = effectiveAppearance
        layer?.backgroundColor = LaughTheme.chromeHoverFill(appearance: appearance).cgColor
        iconView.contentTintColor = .labelColor
        chevronView.contentTintColor = .secondaryLabelColor
        titleLabel.textColor = .labelColor
    }

    func setContent(title: String, symbolName: String, menuItems: [NSMenuItem]) {
        titleLabel.stringValue = title
        setAccessibilityLabel(title)
        toolTip = title

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .semibold)
            let configured = image.withSymbolConfiguration(config)
            configured?.isTemplate = true
            configured?.size = NSSize(width: iconPointSize, height: iconPointSize)
            iconView.image = configured
        }

        let menu = NSMenu()
        for item in menuItems {
            menu.addItem(item)
        }
        itemsMenu = menu
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func configure() {
        wantsLayer = true
        layer?.masksToBounds = true
        isBordered = false
        bezelStyle = .inline
        focusRingType = .none
        setButtonType(.momentaryChange)
        title = ""
        image = nil
        imagePosition = .noImage
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: pillHeight).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        target = self
        action = #selector(showMenuPressed)

        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        iconView.imageScaling = .scaleNone
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.lineBreakMode = .byClipping
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        chevronView.imageScaling = .scaleNone
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: chevronPointSize, weight: .bold)
            let configured = chevron.withSymbolConfiguration(config)
            configured?.isTemplate = true
            configured?.size = NSSize(width: chevronPointSize, height: chevronPointSize)
            chevronView.image = configured
        }

        let iconWrap = padded(iconView, leading: 0, trailing: iconLabelSpacing)
        let titleWrap = padded(titleLabel, leading: 0, trailing: labelChevronSpacing)
        contentStack.addArrangedSubview(iconWrap)
        contentStack.addArrangedSubview(titleWrap)
        contentStack.addArrangedSubview(chevronView)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: iconPointSize),
            iconView.heightAnchor.constraint(equalToConstant: iconPointSize),
            chevronView.widthAnchor.constraint(equalToConstant: chevronPointSize),
            chevronView.heightAnchor.constraint(equalToConstant: chevronPointSize),

            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding)
        ])

        refreshChrome()
    }

    private func padded(_ view: NSView, leading: CGFloat, trailing: CGFloat) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: leading),
            view.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -trailing),
            view.topAnchor.constraint(equalTo: wrap.topAnchor),
            view.bottomAnchor.constraint(equalTo: wrap.bottomAnchor)
        ])
        return wrap
    }

    @objc private func showMenuPressed() {
        guard !itemsMenu.items.isEmpty else { return }
        let location = NSPoint(x: 0, y: bounds.height + 2)
        itemsMenu.popUp(positioning: nil, at: location, in: self)
    }
}
