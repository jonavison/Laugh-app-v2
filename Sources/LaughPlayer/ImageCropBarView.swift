import AppKit

/// Single-row crop chrome: aspect · transform · Cancel / Apply.
final class ImageCropBarView: NSView {
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    let rotateLeftButton = NSButton(title: "", target: nil, action: nil)
    let rotateRightButton = NSButton(title: "", target: nil, action: nil)
    let flipHorizontalButton = NSButton(title: "", target: nil, action: nil)
    let flipVerticalButton = NSButton(title: "", target: nil, action: nil)

    /// Fired when the user picks a ratio.
    var onAspectChange: (() -> Void)?

    /// Intrinsic content height (exclude the parent bar’s outer padding).
    static let preferredContentHeight: CGFloat = 36

    /// Full floating bar height while crop mode is active (matches normal image tools bar).
    static let preferredChromeHeight: CGFloat = 52

    private static let controlHeight: CGFloat = 28
    private static let iconSize: CGFloat = 28
    private static let iconPointSize: CGFloat = 13
    private static let dividerID = NSUserInterfaceItemIdentifier("cropBarDivider")
    private static let trayID = NSUserInterfaceItemIdentifier("cropBarTransformTray")

    private let rootStack = NSStackView()
    private let aspectPopUp = AspectScrollPopUpButton(frame: .zero, pullsDown: false)
    private let transformTray = NSView()
    private var selected = ImageCropAspect.free

    var selectedAspect: ImageCropAspect {
        get { selected }
        set {
            guard selected != newValue else { return }
            selected = newValue
            syncAspectPopUp()
            refreshChrome()
        }
    }

    /// Ordered selectable aspects (menu order, no headers).
    private static var aspectScrollOrder: [ImageCropAspect] {
        ImageCropAspect.menuSections.flatMap(\.items)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        configureAspectPopUp()
        styleTextButton(cancelButton, title: "Cancel", emphasized: false)
        styleTextButton(applyButton, title: "Apply", emphasized: true)
        styleIconButton(rotateLeftButton, symbol: "rotate.left", toolTip: "Rotate left")
        styleIconButton(rotateRightButton, symbol: "rotate.right", toolTip: "Rotate right")
        styleIconButton(
            flipHorizontalButton,
            symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
            toolTip: "Flip horizontal"
        )
        styleIconButton(
            flipVerticalButton,
            symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down",
            toolTip: "Flip vertical"
        )

        transformTray.identifier = Self.trayID
        transformTray.translatesAutoresizingMaskIntoConstraints = false
        transformTray.wantsLayer = true
        transformTray.layer?.cornerRadius = 7
        transformTray.layer?.masksToBounds = true
        transformTray.setContentHuggingPriority(.required, for: .horizontal)

        let transformStack = NSStackView()
        transformStack.orientation = .horizontal
        transformStack.alignment = .centerY
        transformStack.spacing = 0
        transformStack.translatesAutoresizingMaskIntoConstraints = false
        [
            rotateLeftButton,
            rotateRightButton,
            flipHorizontalButton,
            flipVerticalButton
        ].forEach { transformStack.addArrangedSubview($0) }
        transformTray.addSubview(transformStack)

        let actionsStack = NSStackView()
        actionsStack.orientation = .horizontal
        actionsStack.alignment = .centerY
        actionsStack.spacing = 6
        actionsStack.addArrangedSubview(cancelButton)
        actionsStack.addArrangedSubview(applyButton)

        rootStack.orientation = .horizontal
        rootStack.alignment = .centerY
        rootStack.spacing = 10
        rootStack.distribution = .fill
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(aspectPopUp)
        rootStack.addArrangedSubview(makeDivider())
        rootStack.addArrangedSubview(transformTray)
        rootStack.addArrangedSubview(makeDivider())
        rootStack.addArrangedSubview(actionsStack)
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            rootStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            rootStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            transformStack.leadingAnchor.constraint(equalTo: transformTray.leadingAnchor, constant: 2),
            transformStack.trailingAnchor.constraint(equalTo: transformTray.trailingAnchor, constant: -2),
            transformStack.topAnchor.constraint(equalTo: transformTray.topAnchor, constant: 2),
            transformStack.bottomAnchor.constraint(equalTo: transformTray.bottomAnchor, constant: -2),
            transformTray.heightAnchor.constraint(equalToConstant: Self.controlHeight + 4),

            aspectPopUp.heightAnchor.constraint(equalToConstant: Self.controlHeight),
            aspectPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 128)
        ])

        syncAspectPopUp()
        refreshChrome()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChrome()
    }

    private func configureAspectPopUp() {
        aspectPopUp.target = self
        aspectPopUp.action = #selector(aspectPopUpChanged)
        aspectPopUp.bezelStyle = .recessed
        aspectPopUp.controlSize = .regular
        aspectPopUp.font = .systemFont(ofSize: 12, weight: .medium)
        aspectPopUp.focusRingType = .none
        aspectPopUp.toolTip = "Aspect ratio — scroll to cycle"
        aspectPopUp.setContentHuggingPriority(.required, for: .horizontal)
        aspectPopUp.setContentCompressionResistancePriority(.required, for: .horizontal)
        aspectPopUp.onScrollStep = { [weak self] direction in
            self?.cycleAspect(by: direction)
        }
        rebuildAspectMenu()
    }

    private func rebuildAspectMenu() {
        aspectPopUp.removeAllItems()
        guard let menu = aspectPopUp.menu else { return }

        for (sectionIndex, section) in ImageCropAspect.menuSections.enumerated() {
            if sectionIndex > 0 {
                menu.addItem(.separator())
            }
            if let header = section.header {
                let headerItem = NSMenuItem(title: header, action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                menu.addItem(headerItem)
            }
            for aspect in section.items {
                let item = NSMenuItem(title: aspect.title, action: nil, keyEquivalent: "")
                item.tag = aspect.rawValue
                menu.addItem(item)
            }
        }
    }

    private func styleTextButton(_ button: NSButton, title: String, emphasized: Bool) {
        button.title = title
        button.setButtonType(.momentaryChange)
        button.bezelStyle = .flexiblePush
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.masksToBounds = true
        button.focusRingType = .none
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.heightAnchor.constraint(equalToConstant: Self.controlHeight).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: emphasized ? 68 : 64).isActive = true
    }

    private func styleIconButton(_ button: NSButton, symbol: String, toolTip: String) {
        button.title = ""
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.layer?.masksToBounds = true
        button.focusRingType = .none
        button.toolTip = toolTip
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip) {
            let config = NSImage.SymbolConfiguration(pointSize: Self.iconPointSize, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
            button.image?.isTemplate = true
        }
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.widthAnchor.constraint(equalToConstant: Self.iconSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: Self.iconSize).isActive = true
    }

    private func makeDivider() -> NSView {
        let divider = NSView()
        divider.identifier = Self.dividerID
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 16)
        ])
        return divider
    }

    @objc private func aspectPopUpChanged() {
        let tag = aspectPopUp.selectedItem?.tag ?? ImageCropAspect.free.rawValue
        let aspect = ImageCropAspect(rawValue: tag) ?? .free
        guard selected != aspect else { return }
        selected = aspect
        refreshChrome()
        onAspectChange?()
    }

    /// Scroll wheel: step through presets in menu order (`direction` +1 / −1).
    private func cycleAspect(by direction: Int) {
        let order = Self.aspectScrollOrder
        guard !order.isEmpty, direction != 0 else { return }
        let current = order.firstIndex(of: selected) ?? 0
        var next = (current + direction) % order.count
        if next < 0 { next += order.count }
        let aspect = order[next]
        guard aspect != selected else { return }
        selected = aspect
        syncAspectPopUp()
        refreshChrome()
        onAspectChange?()
    }

    private func syncAspectPopUp() {
        if let item = aspectPopUp.menu?.items.first(where: { $0.tag == selected.rawValue && $0.isEnabled }) {
            aspectPopUp.select(item)
        }
    }

    private func refreshChrome() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let trayFill = NSColor.labelColor.withAlphaComponent(isDark ? 0.10 : 0.06)
        let cancelFill = NSColor.labelColor.withAlphaComponent(isDark ? 0.10 : 0.06)
        let applyFill = NSColor.labelColor.withAlphaComponent(isDark ? 0.28 : 0.16)
        let dividerColor = NSColor.separatorColor.withAlphaComponent(isDark ? 0.55 : 0.70)

        transformTray.layer?.backgroundColor = trayFill.cgColor
        for view in rootStack.arrangedSubviews where view.identifier == Self.dividerID {
            view.layer?.backgroundColor = dividerColor.cgColor
        }

        cancelButton.layer?.backgroundColor = cancelFill.cgColor
        applyTitle(to: cancelButton, string: "Cancel", color: .secondaryLabelColor, weight: .medium, size: 12)
        applyButton.layer?.backgroundColor = applyFill.cgColor
        applyTitle(to: applyButton, string: "Apply", color: .labelColor, weight: .semibold, size: 12)

        for button in [rotateLeftButton, rotateRightButton, flipHorizontalButton, flipVerticalButton] {
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.contentTintColor = .secondaryLabelColor
        }
    }

    private func applyTitle(
        to button: NSButton,
        string: String,
        color: NSColor,
        weight: NSFont.Weight,
        size: CGFloat
    ) {
        button.attributedTitle = NSAttributedString(
            string: string,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: size, weight: weight)
            ]
        )
    }
}

/// Pop-up that reports discrete scroll steps so the crop bar can cycle aspects.
private final class AspectScrollPopUpButton: NSPopUpButton {
    /// +1 = next preset, −1 = previous.
    var onScrollStep: ((Int) -> Void)?

    private var scrollAccumulator: CGFloat = 0
    private static let stepThreshold: CGFloat = 6

    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            ? event.scrollingDeltaY
            : event.scrollingDeltaX
        guard abs(delta) > 0.05 else {
            super.scrollWheel(with: event)
            return
        }

        if !event.hasPreciseScrollingDeltas {
            onScrollStep?(delta > 0 ? -1 : 1)
            return
        }

        if event.phase == .began || event.momentumPhase == .began {
            scrollAccumulator = 0
        }
        scrollAccumulator += delta

        while scrollAccumulator >= Self.stepThreshold {
            scrollAccumulator -= Self.stepThreshold
            onScrollStep?(-1)
        }
        while scrollAccumulator <= -Self.stepThreshold {
            scrollAccumulator += Self.stepThreshold
            onScrollStep?(1)
        }
    }
}
