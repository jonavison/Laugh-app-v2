import AppKit

/// Options sheet before the save panel: format, resize, sharpen, color space, DPI, quality.
final class ImageExportOptionsSheetController: NSWindowController {
    var onContinue: ((ImageExportOptions) -> Void)?
    var onCancel: (() -> Void)?

    private var options: ImageExportOptions
    private let sourcePixelSize: CGSize

    private let formatPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let resizePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let widthField = NSTextField(string: "")
    private let heightField = NSTextField(string: "")
    private let percentField = NSTextField(string: "")
    private let sharpenPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let colorSpacePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let resolutionField = NSTextField(string: "")
    private let resolutionUnitLabel = NSTextField(labelWithString: "pixels/inch")
    private let qualitySlider = NSSlider(value: 92, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let qualityValueLabel = NSTextField(labelWithString: "92")

    private let sizeFieldsRow = NSStackView()
    private var percentLabeledRow: NSView!
    private var qualityLabeledRow: NSView!

    private let continueButton = NSButton(title: "Continue…", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    /// Longest-edge target while that mode is active (shown in the width field).
    private var longestEdgeTarget: Int = 0
    private var suppressFieldSync = false

    init(sourcePixelSize: CGSize, initial: ImageExportOptions = ImageExportOptionsStore.load()) {
        self.sourcePixelSize = CGSize(
            width: max(1, sourcePixelSize.width),
            height: max(1, sourcePixelSize.height)
        )
        var opts = initial
        if opts.width <= 0 || opts.height <= 0 || opts.resize == .original {
            opts.syncDimensionsFromSource(self.sourcePixelSize)
        }
        longestEdgeTarget = max(
            opts.width,
            Int(max(self.sourcePixelSize.width, self.sourcePixelSize.height).rounded())
        )
        self.options = opts

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Export Image"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        applyOptionsToControls()
        refreshDynamicRows()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(asSheetOn parent: NSWindow) {
        parent.beginSheet(window!) { [weak self] response in
            guard let self else { return }
            if response == .OK {
                ImageExportOptionsStore.save(self.options)
                self.onContinue?(self.options)
            } else {
                self.onCancel?()
            }
        }
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 12
        form.translatesAutoresizingMaskIntoConstraints = false

        populate(formatPopUp, titles: ImageExportOptions.Format.allCases.map(\.menuTitle))
        formatPopUp.target = self
        formatPopUp.action = #selector(formatChanged)
        LaughTheme.applySettingsAccentChrome(to: formatPopUp)
        form.addArrangedSubview(labeledRow(title: "Format:", control: formatPopUp))

        populate(resizePopUp, titles: ImageExportOptions.ResizeMode.allCases.map(\.menuTitle))
        resizePopUp.target = self
        resizePopUp.action = #selector(resizeChanged)
        LaughTheme.applySettingsAccentChrome(to: resizePopUp)
        form.addArrangedSubview(labeledRow(title: "Resize:", control: resizePopUp))

        configureNumberField(widthField)
        configureNumberField(heightField)
        widthField.target = self
        widthField.action = #selector(widthChanged)
        heightField.target = self
        heightField.action = #selector(heightChanged)
        let times = NSTextField(labelWithString: "×")
        times.textColor = .secondaryLabelColor
        sizeFieldsRow.orientation = .horizontal
        sizeFieldsRow.alignment = .centerY
        sizeFieldsRow.spacing = 6
        sizeFieldsRow.addArrangedSubview(widthField)
        sizeFieldsRow.addArrangedSubview(times)
        sizeFieldsRow.addArrangedSubview(heightField)
        widthField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        heightField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        form.addArrangedSubview(labeledRow(title: "Size:", control: sizeFieldsRow))

        configureNumberField(percentField)
        percentField.target = self
        percentField.action = #selector(percentChanged)
        let percentSuffix = NSTextField(labelWithString: "%")
        percentSuffix.textColor = .secondaryLabelColor
        let percentFields = NSStackView()
        percentFields.orientation = .horizontal
        percentFields.alignment = .centerY
        percentFields.spacing = 6
        percentFields.addArrangedSubview(percentField)
        percentFields.addArrangedSubview(percentSuffix)
        percentField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        percentLabeledRow = labeledRow(title: "Scale:", control: percentFields)
        form.addArrangedSubview(percentLabeledRow)

        populate(sharpenPopUp, titles: ImageExportOptions.Sharpen.allCases.map(\.menuTitle))
        sharpenPopUp.target = self
        sharpenPopUp.action = #selector(sharpenChanged)
        LaughTheme.applySettingsAccentChrome(to: sharpenPopUp)
        form.addArrangedSubview(labeledRow(title: "Sharpen:", control: sharpenPopUp))

        populate(colorSpacePopUp, titles: ImageExportOptions.ExportColorSpace.allCases.map(\.menuTitle))
        colorSpacePopUp.target = self
        colorSpacePopUp.action = #selector(colorSpaceChanged)
        LaughTheme.applySettingsAccentChrome(to: colorSpacePopUp)
        form.addArrangedSubview(labeledRow(title: "Color space:", control: colorSpacePopUp))

        configureNumberField(resolutionField)
        resolutionField.formatter = DPIFormatter()
        resolutionField.target = self
        resolutionField.action = #selector(resolutionChanged)
        resolutionUnitLabel.textColor = .secondaryLabelColor
        resolutionUnitLabel.font = .systemFont(ofSize: 12)
        let dpiRow = NSStackView()
        dpiRow.orientation = .horizontal
        dpiRow.alignment = .centerY
        dpiRow.spacing = 8
        dpiRow.addArrangedSubview(resolutionField)
        dpiRow.addArrangedSubview(resolutionUnitLabel)
        resolutionField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        form.addArrangedSubview(labeledRow(title: "Resolution:", control: dpiRow))

        qualitySlider.target = self
        qualitySlider.action = #selector(qualityChanged)
        qualitySlider.controlSize = .small
        LaughTheme.applySettingsAccentChrome(to: qualitySlider)
        qualityValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        qualityValueLabel.textColor = .secondaryLabelColor
        qualityValueLabel.alignment = .right
        qualityValueLabel.widthAnchor.constraint(equalToConstant: 32).isActive = true
        let qualityFields = NSStackView()
        qualityFields.orientation = .horizontal
        qualityFields.alignment = .centerY
        qualityFields.spacing = 10
        qualityFields.addArrangedSubview(qualitySlider)
        qualityFields.addArrangedSubview(qualityValueLabel)
        qualitySlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        qualityLabeledRow = labeledRow(title: "Quality:", control: qualityFields)
        form.addArrangedSubview(qualityLabeledRow)

        let note = NSTextField(wrappingLabelWithString: "Writes a new file. The original stays unchanged.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 2
        form.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true

        continueButton.bezelStyle = .rounded
        continueButton.keyEquivalent = "\r"
        continueButton.target = self
        continueButton.action = #selector(continuePressed)
        LaughTheme.applySettingsAccentChrome(to: continueButton)

        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        LaughTheme.applySettingsAccentChrome(to: cancelButton)

        let buttons = NSStackView(views: [cancelButton, continueButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.alignment = .centerY

        let root = NSStackView(views: [form, buttons])
        root.orientation = .vertical
        root.alignment = .trailing
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false
        form.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        content.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ])

        window?.initialFirstResponder = formatPopUp
    }

    private func populate(_ popUp: NSPopUpButton, titles: [String]) {
        popUp.removeAllItems()
        popUp.addItems(withTitles: titles)
        popUp.controlSize = .regular
        popUp.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureNumberField(_ field: NSTextField) {
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.focusRingType = .default
        field.isEditable = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.formatter = IntegerOnlyFormatter()
    }

    private func labeledRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 100).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return row
    }

    private func applyOptionsToControls() {
        suppressFieldSync = true
        defer { suppressFieldSync = false }

        formatPopUp.selectItem(at: ImageExportOptions.Format.allCases.firstIndex(of: options.format) ?? 0)
        resizePopUp.selectItem(at: ImageExportOptions.ResizeMode.allCases.firstIndex(of: options.resize) ?? 0)
        sharpenPopUp.selectItem(at: ImageExportOptions.Sharpen.allCases.firstIndex(of: options.sharpen) ?? 0)
        colorSpacePopUp.selectItem(
            at: ImageExportOptions.ExportColorSpace.allCases.firstIndex(of: options.colorSpace) ?? 0
        )

        refreshSizeFields()
        percentField.integerValue = options.percent
        resolutionField.doubleValue = options.resolutionDPI
        qualitySlider.doubleValue = Double(options.quality)
        qualityValueLabel.stringValue = "\(options.quality)"
    }

    private func refreshSizeFields() {
        var probe = options
        if options.resize == .longestEdge {
            probe.width = max(1, longestEdgeTarget)
            let display = probe.outputPixelSize(sourcePixels: sourcePixelSize)
            widthField.integerValue = max(1, longestEdgeTarget)
            heightField.integerValue = max(1, Int(min(display.width, display.height).rounded()))
            return
        }
        let display = options.outputPixelSize(sourcePixels: sourcePixelSize)
        widthField.integerValue = max(1, Int(display.width.rounded()))
        heightField.integerValue = max(1, Int(display.height.rounded()))
    }

    private func refreshDynamicRows() {
        percentLabeledRow.isHidden = options.resize != .percent
        qualityLabeledRow.isHidden = !options.format.supportsLossyQuality

        switch options.resize {
        case .original, .percent:
            widthField.isEnabled = false
            heightField.isEnabled = false
        case .longestEdge:
            widthField.isEnabled = true
            heightField.isEnabled = false
        case .width:
            widthField.isEnabled = true
            heightField.isEnabled = false
        case .height:
            widthField.isEnabled = false
            heightField.isEnabled = true
        }
        refreshSizeFields()
    }

    private func commitOptionsFromControls() {
        options.quality = Int(qualitySlider.doubleValue.rounded())
        options.resolutionDPI = max(36, resolutionField.doubleValue)
        options.percent = min(1000, max(1, percentField.integerValue))

        switch options.resize {
        case .original:
            options.syncDimensionsFromSource(sourcePixelSize)
        case .percent:
            let out = options.outputPixelSize(sourcePixels: sourcePixelSize)
            options.width = max(1, Int(out.width.rounded()))
            options.height = max(1, Int(out.height.rounded()))
        case .longestEdge:
            options.width = max(1, longestEdgeTarget)
            // Keep height as the computed short-side companion for UI restore.
            let out = options.outputPixelSize(sourcePixels: sourcePixelSize)
            options.height = max(1, Int(min(out.width, out.height).rounded()))
        case .width:
            options.width = max(1, widthField.integerValue)
            let out = options.outputPixelSize(sourcePixels: sourcePixelSize)
            options.height = max(1, Int(out.height.rounded()))
        case .height:
            options.height = max(1, heightField.integerValue)
            let out = options.outputPixelSize(sourcePixels: sourcePixelSize)
            options.width = max(1, Int(out.width.rounded()))
        }
    }

    // MARK: - Actions

    @objc private func formatChanged() {
        let idx = formatPopUp.indexOfSelectedItem
        guard ImageExportOptions.Format.allCases.indices.contains(idx) else { return }
        options.format = ImageExportOptions.Format.allCases[idx]
        refreshDynamicRows()
    }

    @objc private func resizeChanged() {
        let idx = resizePopUp.indexOfSelectedItem
        guard ImageExportOptions.ResizeMode.allCases.indices.contains(idx) else { return }
        options.resize = ImageExportOptions.ResizeMode.allCases[idx]
        if options.resize == .longestEdge {
            longestEdgeTarget = max(
                longestEdgeTarget,
                Int(max(sourcePixelSize.width, sourcePixelSize.height).rounded())
            )
        }
        if options.resize == .original {
            options.syncDimensionsFromSource(sourcePixelSize)
        }
        applyOptionsToControls()
        refreshDynamicRows()
    }

    @objc private func widthChanged() {
        guard !suppressFieldSync else { return }
        let w = max(1, widthField.integerValue)
        switch options.resize {
        case .longestEdge:
            longestEdgeTarget = w
            refreshDynamicRows()
        case .width:
            options.width = w
            let out = options.outputPixelSize(sourcePixels: sourcePixelSize)
            suppressFieldSync = true
            heightField.integerValue = max(1, Int(out.height.rounded()))
            suppressFieldSync = false
        default:
            break
        }
    }

    @objc private func heightChanged() {
        guard !suppressFieldSync else { return }
        let h = max(1, heightField.integerValue)
        if options.resize == .height {
            options.height = h
            let out = options.outputPixelSize(sourcePixels: sourcePixelSize)
            suppressFieldSync = true
            widthField.integerValue = max(1, Int(out.width.rounded()))
            suppressFieldSync = false
        }
    }

    @objc private func percentChanged() {
        guard !suppressFieldSync else { return }
        options.percent = min(1000, max(1, percentField.integerValue))
        let out = options.outputPixelSize(sourcePixels: sourcePixelSize)
        suppressFieldSync = true
        widthField.integerValue = max(1, Int(out.width.rounded()))
        heightField.integerValue = max(1, Int(out.height.rounded()))
        suppressFieldSync = false
    }

    @objc private func sharpenChanged() {
        let idx = sharpenPopUp.indexOfSelectedItem
        guard ImageExportOptions.Sharpen.allCases.indices.contains(idx) else { return }
        options.sharpen = ImageExportOptions.Sharpen.allCases[idx]
    }

    @objc private func colorSpaceChanged() {
        let idx = colorSpacePopUp.indexOfSelectedItem
        guard ImageExportOptions.ExportColorSpace.allCases.indices.contains(idx) else { return }
        options.colorSpace = ImageExportOptions.ExportColorSpace.allCases[idx]
    }

    @objc private func resolutionChanged() {
        options.resolutionDPI = max(36, resolutionField.doubleValue)
    }

    @objc private func qualityChanged() {
        options.quality = Int(qualitySlider.doubleValue.rounded())
        qualityValueLabel.stringValue = "\(options.quality)"
    }

    @objc private func continuePressed() {
        commitOptionsFromControls()
        // For longest-edge write path, width must be the edge target.
        if options.resize == .longestEdge {
            options.width = max(1, longestEdgeTarget)
        }
        window?.sheetParent?.endSheet(window!, returnCode: .OK)
    }

    @objc private func cancelPressed() {
        window?.sheetParent?.endSheet(window!, returnCode: .cancel)
    }
}

private final class IntegerOnlyFormatter: NumberFormatter, @unchecked Sendable {
    override init() {
        super.init()
        numberStyle = .none
        allowsFloats = false
        minimum = 1
        maximum = 100_000
        isPartialStringValidationEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class DPIFormatter: NumberFormatter, @unchecked Sendable {
    override init() {
        super.init()
        numberStyle = .decimal
        allowsFloats = true
        minimum = 36
        maximum = 1200
        maximumFractionDigits = 0
        isPartialStringValidationEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
