import AppKit

/// Grouped settings section — soft translucent card with rounded corners (macOS Settings style).
enum SettingsSectionStyle {
    static let cornerRadius: CGFloat = 12
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 14
    static let rowSpacing: CGFloat = 6
    static let headerToCardSpacing: CGFloat = 6
    static let sectionGap: CGFloat = 10
    static let rowInnerSpacing: CGFloat = 5

    /// Rainbow accents that step around the hue wheel per section index.
    private static let rainbowHues: [CGFloat] = [
        0.02,  // coral / red
        0.08,  // orange
        0.14,  // amber
        0.33,  // green
        0.48,  // teal
        0.58,  // sky blue
        0.68,  // indigo
        0.78,  // violet
        0.88   // magenta
    ]

    static func rainbowAccent(at index: Int, appearance: NSAppearance = NSApp.effectiveAppearance) -> NSColor {
        let hue = rainbowHues[index % rainbowHues.count]
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(
            calibratedHue: hue,
            saturation: isDark ? 0.58 : 0.64,
            brightness: isDark ? 0.88 : 0.70,
            alpha: 1
        )
    }

    /// Default video/audio/subs cards — light frosted wash.
    static func fillColor(tint: NSColor? = nil, appearance: NSAppearance = NSApp.effectiveAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let tint {
            return tint.withAlphaComponent(isDark ? 0.10 : 0.065)
        }
        if isDark {
            return NSColor.white.withAlphaComponent(0.045)
        }
        return NSColor.black.withAlphaComponent(0.028)
    }

    /// Expanded Edits content — soft frosted base (mostly transparent).
    static func editsGlassTint(appearance: NSAppearance = NSApp.effectiveAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Keep the wash light so the bottom-trailing corner doesn’t go muddy.
        return NSColor.black.withAlphaComponent(isDark ? 0.12 : 0.035)
    }

    /// Soft specular highlight for glass depth (top → clear).
    static func editsGlassHighlight(appearance: NSAppearance = NSApp.effectiveAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor.white.withAlphaComponent(isDark ? 0.08 : 0.20)
    }

    /// Quiet accent veil — color present, not dominant.
    static func editsGlassAccentWash(
        tint: NSColor,
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return tint.withAlphaComponent(isDark ? 0.09 : 0.06)
    }

    /// Even quieter accent for the fade end of the wash gradient.
    static func editsGlassAccentWashSoft(
        tint: NSColor,
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return tint.withAlphaComponent(isDark ? 0.03 : 0.02)
    }

    /// Card fill when sitting inside the content glass plate — keep clear.
    static func editsCardFill(tint: NSColor? = nil, appearance: NSAppearance = NSApp.effectiveAppearance) -> NSColor {
        _ = tint
        _ = appearance
        return .clear
    }

    static func borderColor(tint: NSColor? = nil, appearance: NSAppearance = NSApp.effectiveAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let tint {
            return tint.withAlphaComponent(isDark ? 0.32 : 0.22)
        }
        return NSColor.separatorColor.withAlphaComponent(isDark ? 0.35 : 0.22)
    }

    /// Hairline rim — true translucent stroke (do not blend to opaque RGB).
    static func editsGlassBorder(
        tint: NSColor? = nil,
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let tint {
            return tint.withAlphaComponent(isDark ? 0.10 : 0.07)
        }
        return NSColor.white.withAlphaComponent(isDark ? 0.04 : 0.07)
    }
}

/// Soft frosted glass plate for expanded Edits content panels.
final class SettingsGlassPlateView: NSVisualEffectView {
    private let tintOverlay = NSView()
    private let accentOverlay = NSView()
    private let accentGradient = CAGradientLayer()
    private let highlightOverlay = NSView()
    private let highlightGradient = CAGradientLayer()
    /// Inset stroke — avoids `masksToBounds` clipping a centered `borderWidth` rim.
    private let rimLayer = CAShapeLayer()
    var accentTint: NSColor? {
        didSet { applyAppearanceChrome() }
    }

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
        // Lighter frosted material — more glass, less opaque panel.
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = SettingsSectionStyle.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        for view in [tintOverlay, accentOverlay, highlightOverlay] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.wantsLayer = true
            view.layer?.cornerRadius = SettingsSectionStyle.cornerRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        accentOverlay.layer?.masksToBounds = true
        // Soft diagonal color wash — stronger at top-leading, clears before bottom-trailing.
        accentGradient.startPoint = CGPoint(x: 0, y: 1)
        accentGradient.endPoint = CGPoint(x: 0.85, y: 0.2)
        accentOverlay.layer?.addSublayer(accentGradient)

        highlightOverlay.layer?.masksToBounds = true
        // Specular reaches farther down so the lower edge doesn’t go flat-dark.
        highlightGradient.startPoint = CGPoint(x: 0.5, y: 1)
        highlightGradient.endPoint = CGPoint(x: 0.5, y: 0.15)
        highlightOverlay.layer?.addSublayer(highlightGradient)

        rimLayer.fillColor = nil
        rimLayer.lineWidth = 0.5
        rimLayer.lineJoin = .round
        rimLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(rimLayer)

        applyAppearanceChrome()
    }

    override func layout() {
        super.layout()
        accentGradient.frame = accentOverlay.bounds
        highlightGradient.frame = highlightOverlay.bounds
        updateRimPath()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceChrome()
    }

    private func updateRimPath() {
        guard bounds.width > 2, bounds.height > 2 else {
            rimLayer.path = nil
            return
        }
        // Keep the full stroke inside bounds so corner masks never shave the rim.
        let inset = rimLayer.lineWidth / 2 + 0.25
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let radius = max(0, SettingsSectionStyle.cornerRadius - inset)
        rimLayer.frame = bounds
        rimLayer.path = CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }

    private func applyAppearanceChrome() {
        let appearance = effectiveAppearance
        tintOverlay.layer?.backgroundColor = SettingsSectionStyle.editsGlassTint(appearance: appearance).cgColor

        if let accentTint {
            accentOverlay.isHidden = false
            let strong = SettingsSectionStyle.editsGlassAccentWash(tint: accentTint, appearance: appearance)
            let soft = SettingsSectionStyle.editsGlassAccentWashSoft(tint: accentTint, appearance: appearance)
            accentGradient.colors = [
                strong.cgColor,
                soft.cgColor,
                NSColor.clear.cgColor
            ]
            // Clear sooner so bottom-trailing stays open/light.
            accentGradient.locations = [0, 0.38, 0.78] as [NSNumber]
        } else {
            accentOverlay.isHidden = true
            accentGradient.colors = nil
        }

        // Resolve through the current appearance so alpha is preserved on the stroke.
        var stroke = SettingsSectionStyle.editsGlassBorder(
            tint: accentTint,
            appearance: appearance
        )
        appearance.performAsCurrentDrawingAppearance {
            stroke = SettingsSectionStyle.editsGlassBorder(
                tint: accentTint,
                appearance: appearance
            )
        }
        rimLayer.strokeColor = stroke.cgColor
        rimLayer.opacity = 1
        rimLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        updateRimPath()

        let highlight = SettingsSectionStyle.editsGlassHighlight(appearance: appearance)
        highlightGradient.colors = [
            highlight.cgColor,
            NSColor.clear.cgColor
        ]

        accentGradient.frame = accentOverlay.bounds
        highlightGradient.frame = highlightOverlay.bounds
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
    private var accentTint: NSColor?
    /// When true, use the darker Edits glass fill instead of the light settings wash.
    var usesEditsGlassFill = false {
        didSet { applyChromeToBackground() }
    }

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

    func setAccentTint(_ tint: NSColor?) {
        accentTint = tint
        applyChromeToBackground()
        applyControlAccentChrome()
    }

    /// Paint sliders / controls inside this card with the section rainbow accent.
    func applyControlAccentChrome() {
        guard let accentTint else { return }
        LaughTheme.applySettingsAccentChrome(in: contentStack, accent: accentTint)
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
        if usesEditsGlassFill {
            // Body sits inside the glass shell — slightly deeper inset, no extra border.
            layer.backgroundColor = SettingsSectionStyle.editsCardFill(
                tint: accentTint,
                appearance: effectiveAppearance
            ).cgColor
            layer.borderWidth = 0
            layer.borderColor = nil
        } else {
            layer.backgroundColor = SettingsSectionStyle.fillColor(
                tint: accentTint,
                appearance: effectiveAppearance
            ).cgColor
            layer.borderWidth = 0.5
            layer.borderColor = SettingsSectionStyle.borderColor(
                tint: accentTint,
                appearance: effectiveAppearance
            ).cgColor
        }
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
    /// Collapsible section: icon + titled header toggles a tinted card of edit rows.
    /// - Returns: container stack and the collapsible header (for wiring section edit actions).
    @discardableResult
    static func sectionBlock(
        title: String,
        symbolName: String,
        accentIndex: Int,
        isFirst: Bool,
        initiallyExpanded: Bool = false,
        showsSectionEditActions: Bool = false,
        leadingGap: CGFloat? = nil,
        configure: (SettingsSectionCard) -> Void
    ) -> (container: NSStackView, section: CollapsibleSettingsSectionView) {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = SettingsSectionStyle.headerToCardSpacing
        container.translatesAutoresizingMaskIntoConstraints = false

        let gapHeight = leadingGap ?? (isFirst ? 0 : SettingsSectionStyle.sectionGap)
        if gapHeight > 0 {
            let gap = NSView()
            gap.translatesAutoresizingMaskIntoConstraints = false
            gap.heightAnchor.constraint(equalToConstant: gapHeight).isActive = true
            container.addArrangedSubview(gap)
        }

        let accent = SettingsSectionStyle.rainbowAccent(at: accentIndex)
        let card = SettingsSectionCard()
        card.usesEditsGlassFill = showsSectionEditActions
        configure(card)
        card.setAccentTint(accent)

        let section = CollapsibleSettingsSectionView(
            title: title,
            symbolName: symbolName,
            accentIndex: accentIndex,
            card: card,
            expanded: initiallyExpanded,
            showsSectionEditActions: showsSectionEditActions
        )
        container.addArrangedSubview(section)
        section.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        section.trailingAnchor.constraint(equalTo: container.trailingAnchor).isActive = true
        return (container, section)
    }
}

/// Titled disclosure header wrapping a `SettingsSectionCard` of edit controls.
/// Glass styling applies only to the expanded content body — not the header row.
final class CollapsibleSettingsSectionView: NSView {
    private let contentGlassPlate: SettingsGlassPlateView?
    private let headerButton = NSButton(title: "", target: nil, action: nil)
    private let headerChrome = SectionHeaderChromeView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()
    private let bypassButton = NSButton(title: "", target: nil, action: nil)
    private let restoreButton = NSButton(title: "", target: nil, action: nil)
    private let editActionsStack = NSStackView()
    private let bodyClip = NSView()
    private let card: SettingsSectionCard
    private let symbolName: String
    private let accentIndex: Int
    private let showsSectionEditActions: Bool
    private var isExpanded: Bool
    private var isHeaderHovered = false
    private var isSectionEdited = false
    private var isSectionBypassed = false
    private var bodyHeightConstraint: NSLayoutConstraint!
    private var isAnimatingExpand = false
    private var headerTrackingArea: NSTrackingArea?

    var onToggleBypass: (() -> Void)?
    var onRestoreSection: (() -> Void)?
    /// Fired after expand/collapse settles into `isExpanded` (used for Edits accordion).
    var onExpandedChange: ((Bool) -> Void)?

    var isCurrentlyExpanded: Bool { isExpanded }

    init(
        title: String,
        symbolName: String,
        accentIndex: Int,
        card: SettingsSectionCard,
        expanded: Bool,
        showsSectionEditActions: Bool = false
    ) {
        self.card = card
        self.symbolName = symbolName
        self.accentIndex = accentIndex
        self.isExpanded = expanded
        self.showsSectionEditActions = showsSectionEditActions
        self.contentGlassPlate = showsSectionEditActions ? SettingsGlassPlateView() : nil
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build(title: title)
        applyAccentChrome()
        applyExpandedState(animated: false)
        updateChevronVisibility(animated: false)
        updateEditActionsVisibility(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Programmatic expand/collapse (accordion). No-ops when already in the requested state.
    func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard isExpanded != expanded, !isAnimatingExpand else { return }
        isExpanded = expanded
        applyExpandedState(animated: animated)
        if expanded {
            onExpandedChange?(true)
        }
    }

    /// Update eye/restore affordances from the parameter model.
    func setSectionEditState(edited: Bool, bypassed: Bool, animated: Bool = true) {
        isSectionEdited = edited
        isSectionBypassed = bypassed
        refreshBypassButtonSymbol()
        updateEditActionsVisibility(animated: animated)
        applyAccentChrome()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAccentChrome()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let headerTrackingArea {
            headerChrome.removeTrackingArea(headerTrackingArea)
        }
        let area = NSTrackingArea(
            rect: headerChrome.bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        headerTrackingArea = area
        headerChrome.addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea == headerTrackingArea else {
            super.mouseEntered(with: event)
            return
        }
        isHeaderHovered = true
        updateHeaderTitleBrightness(animated: true)
        updateChevronVisibility(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea == headerTrackingArea else {
            super.mouseExited(with: event)
            return
        }
        isHeaderHovered = false
        updateHeaderTitleBrightness(animated: true)
        updateChevronVisibility(animated: true)
    }

    private func build(title: String) {
        let titleFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let headerIconPointSize: CGFloat = 13
        let headerIconSide: CGFloat = 18

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentHuggingPriority(.required, for: .vertical)
        if #available(macOS 11.0, *) {
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: headerIconPointSize, weight: .semibold)
            iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        }
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: headerIconSide),
            iconView.heightAnchor.constraint(equalToConstant: headerIconSide)
        ])

        titleLabel.stringValue = title
        titleLabel.font = titleFont
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        if let cell = titleLabel.cell as? NSTextFieldCell {
            cell.isScrollable = false
            cell.usesSingleLineMode = true
        }

        configureHeaderActionButton(
            bypassButton,
            toolTip: "Hide this section’s edits",
            accessibilityLabel: "Hide \(title) edits",
            action: #selector(bypassPressed)
        )
        configureHeaderActionButton(
            restoreButton,
            toolTip: "Reset this section",
            accessibilityLabel: "Reset \(title)",
            action: #selector(restorePressed)
        )
        if #available(macOS 11.0, *) {
            restoreButton.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset")
            restoreButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: headerIconPointSize, weight: .semibold)
        }
        refreshBypassButtonSymbol()

        editActionsStack.orientation = .horizontal
        editActionsStack.alignment = .centerY
        editActionsStack.spacing = 2
        editActionsStack.translatesAutoresizingMaskIntoConstraints = false
        editActionsStack.addArrangedSubview(bypassButton)
        editActionsStack.addArrangedSubview(restoreButton)
        editActionsStack.isHidden = true
        editActionsStack.alphaValue = 0

        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.wantsLayer = true
        chevronView.alphaValue = 0
        if #available(macOS 11.0, *) {
            chevronView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        }
        NSLayoutConstraint.activate([
            chevronView.widthAnchor.constraint(equalToConstant: 13),
            chevronView.heightAnchor.constraint(equalToConstant: 13)
        ])

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Icon + title as one optically centered cluster (not loose stack baseline drift).
        let titleCluster = NSView()
        titleCluster.translatesAutoresizingMaskIntoConstraints = false
        titleCluster.addSubview(iconView)
        titleCluster.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: titleCluster.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: titleCluster.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: titleCluster.trailingAnchor),
            // Optical nudge: SF Symbols sit a hair high vs AppKit label bounds.
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor, constant: 0.5),
            titleCluster.heightAnchor.constraint(equalToConstant: headerIconSide)
        ])

        let headerStack = NSStackView(views: [titleCluster, editActionsStack, spacer, chevronView])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 6
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.setHuggingPriority(.defaultHigh, for: .vertical)

        headerButton.title = ""
        headerButton.bezelStyle = .inline
        headerButton.isBordered = false
        headerButton.setButtonType(.momentaryChange)
        headerButton.target = self
        headerButton.action = #selector(toggleExpanded)
        headerButton.translatesAutoresizingMaskIntoConstraints = false
        headerButton.setAccessibilityLabel(title)
        headerButton.setAccessibilityRole(.button)

        headerChrome.translatesAutoresizingMaskIntoConstraints = false
        headerChrome.expandButton = headerButton
        headerChrome.protectedViews = [bypassButton, restoreButton]
        // Button under stack so expand works; action buttons protected via hitTest.
        headerChrome.addSubview(headerButton)
        headerChrome.addSubview(headerStack)
        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: headerChrome.leadingAnchor, constant: 2),
            headerStack.trailingAnchor.constraint(equalTo: headerChrome.trailingAnchor, constant: -2),
            headerStack.topAnchor.constraint(equalTo: headerChrome.topAnchor, constant: 5),
            headerStack.bottomAnchor.constraint(equalTo: headerChrome.bottomAnchor, constant: -5),
            headerButton.leadingAnchor.constraint(equalTo: headerChrome.leadingAnchor),
            headerButton.trailingAnchor.constraint(equalTo: headerChrome.trailingAnchor),
            headerButton.topAnchor.constraint(equalTo: headerChrome.topAnchor),
            headerButton.bottomAnchor.constraint(equalTo: headerChrome.bottomAnchor),
            headerChrome.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])

        bodyClip.translatesAutoresizingMaskIntoConstraints = false
        bodyClip.wantsLayer = true
        bodyClip.layer?.masksToBounds = true
        bodyClip.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        card.translatesAutoresizingMaskIntoConstraints = false

        // Glass wraps only the expanded content — header row stays plain.
        // Pin top only (not bottom) so height animation clips/reveals without vertically stretching the glass.
        if let contentGlassPlate {
            contentGlassPlate.addSubview(card)
            bodyClip.addSubview(contentGlassPlate)
            NSLayoutConstraint.activate([
                contentGlassPlate.leadingAnchor.constraint(equalTo: bodyClip.leadingAnchor),
                contentGlassPlate.trailingAnchor.constraint(equalTo: bodyClip.trailingAnchor),
                contentGlassPlate.topAnchor.constraint(
                    equalTo: bodyClip.topAnchor,
                    constant: SettingsSectionStyle.headerToCardSpacing
                ),
                card.leadingAnchor.constraint(equalTo: contentGlassPlate.leadingAnchor),
                card.trailingAnchor.constraint(equalTo: contentGlassPlate.trailingAnchor),
                card.topAnchor.constraint(equalTo: contentGlassPlate.topAnchor),
                card.bottomAnchor.constraint(equalTo: contentGlassPlate.bottomAnchor)
            ])
        } else {
            bodyClip.addSubview(card)
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: bodyClip.leadingAnchor),
                card.trailingAnchor.constraint(equalTo: bodyClip.trailingAnchor),
                card.topAnchor.constraint(
                    equalTo: bodyClip.topAnchor,
                    constant: SettingsSectionStyle.headerToCardSpacing
                )
            ])
        }
        bodyHeightConstraint = bodyClip.heightAnchor.constraint(equalToConstant: 0)
        bodyHeightConstraint.priority = .required

        let column = NSStackView(views: [headerChrome, bodyClip])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),

            headerChrome.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            headerChrome.trailingAnchor.constraint(equalTo: column.trailingAnchor),

            bodyClip.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            bodyClip.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            bodyHeightConstraint
        ])
        card.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        card.setContentHuggingPriority(.defaultHigh, for: .vertical)
    }

    private func configureHeaderActionButton(
        _ button: NSButton,
        toolTip: String,
        accessibilityLabel: String,
        action: Selector
    ) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.imagePosition = .imageOnly
        button.translatesAutoresizingMaskIntoConstraints = false
        button.target = self
        button.action = action
        button.toolTip = toolTip
        button.setAccessibilityLabel(accessibilityLabel)
        button.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 18),
            button.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    private func refreshBypassButtonSymbol() {
        guard #available(macOS 11.0, *) else { return }
        let name = isSectionBypassed ? "eye.slash" : "eye"
        bypassButton.image = NSImage(systemSymbolName: name, accessibilityDescription: name)
        bypassButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        bypassButton.toolTip = isSectionBypassed
            ? "Show this section’s edits"
            : "Hide this section’s edits"
        bypassButton.setAccessibilityLabel(
            isSectionBypassed ? "Show section edits" : "Hide section edits"
        )
    }

    private func applyAccentChrome() {
        let accent = SettingsSectionStyle.rainbowAccent(at: accentIndex, appearance: effectiveAppearance)
        // Soft gray title (brightens on hover); rainbow on section icon; card/sliders keep accent too.
        updateHeaderTitleBrightness(animated: false)
        iconView.contentTintColor = accent
        chevronView.contentTintColor = NSColor.secondaryLabelColor.withAlphaComponent(0.75)
        let actionTint = isSectionBypassed
            ? NSColor.tertiaryLabelColor
            : NSColor.secondaryLabelColor
        bypassButton.contentTintColor = actionTint
        restoreButton.contentTintColor = .secondaryLabelColor
        contentGlassPlate?.accentTint = accent
        card.setAccentTint(accent)
    }

    /// Idle: secondary gray. Hover: a step brighter toward primary label.
    private func updateHeaderTitleBrightness(animated: Bool) {
        let color: NSColor = isHeaderHovered ? .labelColor : .secondaryLabelColor
        let apply = {
            self.titleLabel.textColor = color
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                NSAnimationContext.current.allowsImplicitAnimation = true
                apply()
            }
        } else {
            apply()
        }
    }

    @objc private func toggleExpanded() {
        guard !isAnimatingExpand else { return }
        isExpanded.toggle()
        applyExpandedState(animated: true)
        onExpandedChange?(isExpanded)
    }

    @objc private func bypassPressed() {
        onToggleBypass?()
    }

    @objc private func restorePressed() {
        onRestoreSection?()
    }

    private func measuredBodyHeight() -> CGFloat {
        let wasActive = bodyHeightConstraint.isActive
        let previous = bodyHeightConstraint.constant
        bodyHeightConstraint.isActive = false
        card.isHidden = false
        layoutSubtreeIfNeeded()
        let cardHeight = max(card.fittingSize.height, card.bounds.height)
        bodyHeightConstraint.constant = previous
        bodyHeightConstraint.isActive = wasActive
        layoutSubtreeIfNeeded()
        return SettingsSectionStyle.headerToCardSpacing + max(cardHeight, 1)
    }

    private func applyExpandedState(animated: Bool) {
        headerButton.setAccessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        headerButton.toolTip = isExpanded ? "Collapse \(titleLabel.stringValue)" : "Expand \(titleLabel.stringValue)"
        animateChevron(expanded: isExpanded, animated: animated)
        updateChevronVisibility(animated: animated)

        if isExpanded {
            expandBody(animated: animated)
        } else {
            collapseBody(animated: animated)
        }
    }

    /// Chevron while the header is hovered — collapsed or expanded (stays after open).
    private func updateChevronVisibility(animated: Bool) {
        let visible = isHeaderHovered
        let target: CGFloat = visible ? 1 : 0
        guard abs(chevronView.alphaValue - target) > 0.01 else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                chevronView.animator().alphaValue = target
            }
        } else {
            chevronView.alphaValue = target
        }
    }

    private func updateEditActionsVisibility(animated: Bool) {
        guard showsSectionEditActions else {
            editActionsStack.isHidden = true
            editActionsStack.alphaValue = 0
            return
        }
        let visible = isSectionEdited
        editActionsStack.isHidden = false
        let target: CGFloat = visible ? 1 : 0
        if !visible && editActionsStack.alphaValue < 0.01 {
            editActionsStack.isHidden = true
            return
        }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                editActionsStack.animator().alphaValue = target
            }, completionHandler: { [weak self] in
                guard let self else { return }
                if !visible {
                    self.editActionsStack.isHidden = true
                }
            })
        } else {
            editActionsStack.alphaValue = target
            editActionsStack.isHidden = !visible
        }
    }

    private func animateChevron(expanded: Bool, animated: Bool) {
        let angle = expanded ? CGFloat.pi / 2 : 0
        chevronView.wantsLayer = true
        guard animated, let layer = chevronView.layer else {
            chevronView.layer?.setAffineTransform(CGAffineTransform(rotationAngle: angle))
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            layer.setAffineTransform(CGAffineTransform(rotationAngle: angle))
        }
    }

    private func expandBody(animated: Bool) {
        card.isHidden = false
        bodyClip.isHidden = false

        let target = measuredBodyHeight()
        bodyHeightConstraint.isActive = true
        bodyHeightConstraint.constant = 0
        let fadeTarget = contentGlassPlate ?? card
        fadeTarget.alphaValue = 0
        layoutSubtreeIfNeeded()

        guard animated else {
            bodyHeightConstraint.constant = target
            fadeTarget.alphaValue = 1
            return
        }

        isAnimatingExpand = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            self.bodyHeightConstraint.animator().constant = target
            fadeTarget.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            self?.isAnimatingExpand = false
        })
    }

    private func collapseBody(animated: Bool) {
        bodyHeightConstraint.isActive = true
        let current = max(bodyClip.bounds.height, bodyHeightConstraint.constant, measuredBodyHeight())
        bodyHeightConstraint.constant = current
        let fadeTarget = contentGlassPlate ?? card
        fadeTarget.alphaValue = 1
        layoutSubtreeIfNeeded()

        guard animated else {
            bodyHeightConstraint.constant = 0
            fadeTarget.alphaValue = 1
            return
        }

        isAnimatingExpand = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            self.bodyHeightConstraint.animator().constant = 0
            fadeTarget.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            fadeTarget.alphaValue = 1
            self?.isAnimatingExpand = false
        })
    }
}

/// Routes header clicks to expand, except for protected action buttons (eye / restore).
private final class SectionHeaderChromeView: NSView {
    weak var expandButton: NSButton?
    var protectedViews: [NSView] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for view in protectedViews {
            let inView = view.convert(local, from: self)
            if view.bounds.contains(inView), !view.isHidden, view.alphaValue > 0.01 {
                return view.hitTest(view.convert(point, from: superview)) ?? view
            }
        }
        if bounds.contains(local) {
            return expandButton ?? self
        }
        return nil
    }
}
