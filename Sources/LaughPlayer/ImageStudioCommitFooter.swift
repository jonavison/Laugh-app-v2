import AppKit

/// Pinned footer on the image studio edit sidebar when adjusts are dirty:
/// Reset All above Save Preset / Export.
final class ImageStudioCommitFooter: NSView {
    let resetAllButton = NSButton(title: "Reset All", target: nil, action: nil)
    let exportButton = NSButton(title: "Export…", target: nil, action: nil)
    let savePresetButton = NSButton(title: "Save Preset", target: nil, action: nil)

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

    private static let buttonHeight: CGFloat = 34

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor.separatorColor.cgColor
        hairline.translatesAutoresizingMaskIntoConstraints = false

        styleActionButton(
            resetAllButton,
            title: "Reset All",
            symbol: "arrow.counterclockwise",
            semibold: false,
            toolTip: "Clear all develop edits (crop and rotation stay)"
        )
        styleActionButton(
            exportButton,
            title: "Export…",
            symbol: "square.and.arrow.up",
            semibold: true,
            toolTip: "Write a new file with these edits (original is unchanged)"
        )
        styleActionButton(
            savePresetButton,
            title: "Save Preset",
            symbol: "bookmark",
            semibold: false,
            toolTip: "Save the current sliders as a reusable look"
        )

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

    private func styleActionButton(
        _ button: NSButton,
        title: String,
        symbol: String,
        semibold: Bool,
        toolTip: String
    ) {
        button.title = title
        // Custom fill — system `.rounded` bezels flash controlAccentColor (often blue).
        button.setButtonType(.momentaryChange)
        button.bezelStyle = .flexiblePush
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.masksToBounds = true
        button.focusRingType = .none
        if #available(macOS 11.0, *) {
            button.controlSize = .large
        } else {
            button.controlSize = .regular
        }
        button.font = .systemFont(ofSize: 13, weight: semibold ? .semibold : .medium)
        button.toolTip = toolTip
        button.contentTintColor = .labelColor
        button.heightAnchor.constraint(equalToConstant: Self.buttonHeight).isActive = true
        if #available(macOS 11.0, *) {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.imagePosition = .imageLeading
            button.symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: 12,
                weight: semibold ? .semibold : .medium
            )
        }
        button.tag = semibold ? 1 : 0
    }

    private func refreshActionButtonChrome() {
        let appearance = effectiveAppearance
        let idle = LaughTheme.chromeHoverFill(appearance: appearance)
        let emphasized = LaughTheme.chromeActiveFill(appearance: appearance)
        for button in [resetAllButton, savePresetButton, exportButton] {
            let fill = button.tag == 1 ? emphasized : idle
            button.layer?.backgroundColor = fill.cgColor
            button.contentTintColor = .labelColor
        }
    }
}
