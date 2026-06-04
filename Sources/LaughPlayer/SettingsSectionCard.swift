import AppKit

/// Grouped settings section — soft translucent card with rounded corners (macOS Settings style).
enum SettingsSectionStyle {
    static let cornerRadius: CGFloat = 10
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 7
    static let rowSpacing: CGFloat = 6
    static let headerToCardSpacing: CGFloat = 3
    static let sectionGap: CGFloat = 10
    static let rowInnerSpacing: CGFloat = 5

    static func fillColor() -> NSColor {
        let appearance = NSApp.effectiveAppearance
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.07)
        }
        return NSColor.black.withAlphaComponent(0.045)
    }

    static func borderColor() -> NSColor {
        NSColor.separatorColor.withAlphaComponent(0.28)
    }
}

enum SettingsRowFactory {
    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    /// Title on top, slider full width below; optional value on the title line (trailing).
    static func sliderRow(title: String, slider: NSSlider, valueLabel: NSTextField?) -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = SettingsSectionStyle.rowInnerSpacing
        column.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.spacing = 8

        let label = makeTitleLabel(title)
        label.setContentHuggingPriority(.required, for: .horizontal)
        header.addArrangedSubview(label)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(spacer)

        if let valueLabel {
            valueLabel.font = valueFont
            valueLabel.textColor = .secondaryLabelColor
            valueLabel.alignment = .right
            valueLabel.setContentHuggingPriority(.required, for: .horizontal)
            header.addArrangedSubview(valueLabel)
        }

        let sliderHeight = SubtitleAppearanceStyle.settingsSliderTrackHeight + 10
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.heightAnchor.constraint(equalToConstant: sliderHeight).isActive = true

        column.addArrangedSubview(header)
        column.addArrangedSubview(slider)
        slider.leadingAnchor.constraint(equalTo: column.leadingAnchor).isActive = true
        slider.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
        return wrapFullWidth(column)
    }

    /// Title (leading) — flexible space — toggle (trailing).
    static func toggleRow(title: String, control: NSControl) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = makeTitleLabel(title)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)

        if let checkbox = control as? NSButton, !(control is CompactTealToggle) {
            checkbox.title = ""
            checkbox.attributedTitle = NSAttributedString(string: "")
            checkbox.setAccessibilityLabel(title)
        }

        row.addArrangedSubview(label)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(control)
        return wrapFullWidth(row)
    }

    /// Title (leading) — flexible space — control (trailing).
    static func valueRow(title: String, control: NSControl) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = makeTitleLabel(title)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addArrangedSubview(label)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(control)
        return wrapFullWidth(row)
    }

    /// Title on top, control full width below (segmented controls, pop-ups).
    static func stackedRow(title: String, control: NSControl) -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = SettingsSectionStyle.rowInnerSpacing
        column.translatesAutoresizingMaskIntoConstraints = false

        column.addArrangedSubview(makeTitleLabel(title))
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        column.addArrangedSubview(control)
        control.leadingAnchor.constraint(equalTo: column.leadingAnchor).isActive = true
        control.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
        return wrapFullWidth(column)
    }

    static func fullWidthRow(_ content: NSView) -> NSView {
        content.translatesAutoresizingMaskIntoConstraints = false
        return wrapFullWidth(content)
    }

    private static func makeTitleLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = titleFont
        label.textColor = .labelColor
        return label
    }

    private static func wrapFullWidth(_ content: NSView) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        return wrapper
    }
}

final class SettingsSectionCard: NSView {
    private let backgroundView = NSView()
    private let contentStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        translatesAutoresizingMaskIntoConstraints = false

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.wantsLayer = true
        applyChromeToBackground()

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = SettingsSectionStyle.rowSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(backgroundView)
        addSubview(contentStack)

        let pad = SettingsSectionStyle.horizontalPadding
        let vPad = SettingsSectionStyle.verticalPadding
        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: vPad),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vPad)
        ])
    }

    func addRow(_ view: NSView, separatorBelow: Bool = true) {
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        if separatorBelow {
            let sep = makeSeparator()
            contentStack.addArrangedSubview(sep)
            sep.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
            if #available(macOS 11.0, *) {
                contentStack.setCustomSpacing(2, after: view)
                contentStack.setCustomSpacing(4, after: sep)
            }
        }
    }

    func addFinalRow(_ view: NSView) {
        addRow(view, separatorBelow: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyChromeToBackground()
    }

    private func applyChromeToBackground() {
        guard let layer = backgroundView.layer else { return }
        layer.cornerRadius = SettingsSectionStyle.cornerRadius
        layer.cornerCurve = .continuous
        layer.backgroundColor = SettingsSectionStyle.fillColor().cgColor
        layer.borderWidth = 0.5
        layer.borderColor = SettingsSectionStyle.borderColor().cgColor
    }

    private func makeSeparator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }
}

enum SettingsSectionBuilder {
    /// Section title above a grouped card; `configure` adds rows to the card.
    static func sectionBlock(
        title: String,
        isFirst: Bool,
        configure: (SettingsSectionCard) -> Void
    ) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = SettingsSectionStyle.headerToCardSpacing
        container.translatesAutoresizingMaskIntoConstraints = false

        if !isFirst {
            let gap = NSView()
            gap.translatesAutoresizingMaskIntoConstraints = false
            gap.heightAnchor.constraint(equalToConstant: SettingsSectionStyle.sectionGap).isActive = true
            container.addArrangedSubview(gap)
        }

        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false

        let card = SettingsSectionCard()
        configure(card)

        container.addArrangedSubview(header)
        container.addArrangedSubview(card)
        card.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        card.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        return container
    }
}
