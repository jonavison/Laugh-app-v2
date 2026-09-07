import AppKit

/// Pinned footer on the image studio edit sidebar when adjusts are dirty:
/// Reset All above Save Preset / Export.
final class ImageStudioCommitFooter: NSView {
    let resetAllButton = CommitFooterActionButton(
        title: "Reset All",
        symbol: "arrow.counterclockwise",
        emphasized: false,
        toolTip: "Clear all develop edits (crop and rotation stay)"
    )
    let exportButton = CommitFooterActionButton(
        title: "Export…",
        symbol: "square.and.arrow.up",
        emphasized: true,
        toolTip: "Write a new file with these edits (original is unchanged)"
    )
    let savePresetButton = CommitFooterActionButton(
        title: "Save Preset",
        symbol: "bookmark",
        emphasized: false,
        toolTip: "Save the current sliders as a reusable look"
    )

    private let hairline = NSView()
    private let column = NSStackView()
    private let actionsRow = NSStackView()

    /// Preferred height when Reset All + actions are visible.
    static let preferredHeight: CGFloat = 112
    /// Height when only Save Preset / Export show (geometry dirty, adjusts clean).
    static let preferredHeightActionsOnly: CGFloat = 68

    func setShowsResetAll(_ show: Bool) {
        resetAllButton.isHidden = !show
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor.separatorColor.cgColor
        hairline.translatesAutoresizingMaskIntoConstraints = false

        actionsRow.orientation = .horizontal
        actionsRow.alignment = .centerY
        actionsRow.spacing = 10
        actionsRow.distribution = .fillEqually
        actionsRow.translatesAutoresizingMaskIntoConstraints = false
        actionsRow.addArrangedSubview(savePresetButton)
        actionsRow.addArrangedSubview(exportButton)

        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        column.addArrangedSubview(resetAllButton)
        column.addArrangedSubview(actionsRow)
        resetAllButton.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        actionsRow.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true

        addSubview(hairline)
        addSubview(column)

        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            column.topAnchor.constraint(equalTo: hairline.bottomAnchor, constant: 12),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])

        refreshActionButtonChrome()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        hairline.layer?.backgroundColor = NSColor.separatorColor.cgColor
        refreshActionButtonChrome()
    }

    private func refreshActionButtonChrome() {
        let appearance = effectiveAppearance
        resetAllButton.refreshChrome(appearance: appearance)
        savePresetButton.refreshChrome(appearance: appearance)
        exportButton.refreshChrome(appearance: appearance)
    }
}

/// Custom-filled action chip with a manually centered SF Symbol + title.
/// Avoids NSButton `imageLeading` on borderless buttons, which draws icons outside the fill.
final class CommitFooterActionButton: NSButton {
    static let buttonHeight: CGFloat = 34
    private static let iconSize: CGFloat = 13
    private static let iconTitleSpacing: CGFloat = 6

    private let emphasized: Bool
    private let contentStack = NSStackView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    init(title: String, symbol: String, emphasized: Bool, toolTip: String) {
        self.emphasized = emphasized
        super.init(frame: .zero)
        self.toolTip = toolTip
        configure(title: title, symbol: symbol)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshChrome(appearance: NSAppearance) {
        let fill = emphasized
            ? LaughTheme.chromeActiveFill(appearance: appearance)
            : LaughTheme.chromeHoverFill(appearance: appearance)
        layer?.backgroundColor = fill.cgColor
        iconView.contentTintColor = .labelColor
        titleLabel.textColor = .labelColor
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.45
        }
    }

    private func configure(title: String, symbol: String) {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        isBordered = false
        bezelStyle = .inline
        setButtonType(.momentaryChange)
        focusRingType = .none
        self.title = ""
        image = nil
        imagePosition = .noImage
        setAccessibilityLabel(title)
        heightAnchor.constraint(equalToConstant: Self.buttonHeight).isActive = true

        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = Self.iconTitleSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleNone
        iconView.imageAlignment = .alignCenter
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(
                pointSize: Self.iconSize,
                weight: emphasized ? .semibold : .medium
            )
            if let configured = image.withSymbolConfiguration(config) {
                configured.isTemplate = true
                configured.size = NSSize(width: Self.iconSize, height: Self.iconSize)
                iconView.image = configured
            }
        }
        iconView.contentTintColor = .labelColor

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: emphasized ? .semibold : .medium)
        titleLabel.textColor = .labelColor
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.lineBreakMode = .byClipping
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(titleLabel)
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            trailingAnchor.constraint(greaterThanOrEqualTo: contentStack.trailingAnchor, constant: 10)
        ])
    }
}
