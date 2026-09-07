import AppKit

/// Fully rounded pill tab switcher for Gallery / Grid / List.
final class LibraryLayoutModeSwitcher: NSView {
    var onChange: ((LibraryBrowseViewMode) -> Void)?

    private let modes = LibraryBrowseViewMode.allCases
    private let trackView = NSView()
    private let selectionPill = NSView()
    private let buttonStack = NSStackView()
    private var buttons: [NSButton] = []
    private var selectedMode: LibraryBrowseViewMode = .gallery
    private var selectionLeadingConstraint: NSLayoutConstraint?
    private var selectionWidthConstraint: NSLayoutConstraint?
    private var suppressChange = false

    private let outerPadding: CGFloat = 3
    private let buttonWidth: CGFloat = 34
    private let controlHeight: CGFloat = 30

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let width = outerPadding * 2 + CGFloat(modes.count) * buttonWidth
        return NSSize(width: width, height: controlHeight)
    }

    func setSelectedMode(_ mode: LibraryBrowseViewMode, animated: Bool = false) {
        suppressChange = true
        selectedMode = mode
        refreshSelection(animated: animated)
        suppressChange = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChrome()
    }

    override func layout() {
        super.layout()
        let radius = bounds.height / 2
        trackView.layer?.cornerRadius = radius
        let pillHeight = max(0, bounds.height - outerPadding * 2)
        selectionPill.layer?.cornerRadius = pillHeight / 2
        refreshSelection(animated: false)
    }

    private func setup() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        trackView.wantsLayer = true
        trackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trackView)

        selectionPill.wantsLayer = true
        selectionPill.translatesAutoresizingMaskIntoConstraints = false
        trackView.addSubview(selectionPill)

        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 0
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        trackView.addSubview(buttonStack)

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        for (index, mode) in modes.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(tabPressed(_:)))
            button.bezelStyle = .inline
            button.isBordered = false
            button.focusRingType = .none
            button.tag = index
            button.toolTip = mode.menuTitle
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
            button.heightAnchor.constraint(equalToConstant: controlHeight - outerPadding * 2).isActive = true
            if let image = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: mode.menuTitle) {
                button.image = image.withSymbolConfiguration(symbolConfig)
                button.imagePosition = .imageOnly
            }
            buttons.append(button)
            buttonStack.addArrangedSubview(button)
        }

        let leading = selectionPill.leadingAnchor.constraint(equalTo: trackView.leadingAnchor, constant: outerPadding)
        let width = selectionPill.widthAnchor.constraint(equalToConstant: buttonWidth)
        selectionLeadingConstraint = leading
        selectionWidthConstraint = width

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: controlHeight),

            trackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            trackView.topAnchor.constraint(equalTo: topAnchor),
            trackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            buttonStack.leadingAnchor.constraint(equalTo: trackView.leadingAnchor, constant: outerPadding),
            buttonStack.trailingAnchor.constraint(equalTo: trackView.trailingAnchor, constant: -outerPadding),
            buttonStack.topAnchor.constraint(equalTo: trackView.topAnchor, constant: outerPadding),
            buttonStack.bottomAnchor.constraint(equalTo: trackView.bottomAnchor, constant: -outerPadding),

            leading,
            width,
            selectionPill.topAnchor.constraint(equalTo: trackView.topAnchor, constant: outerPadding),
            selectionPill.bottomAnchor.constraint(equalTo: trackView.bottomAnchor, constant: -outerPadding)
        ])

        refreshChrome()
        refreshSelection(animated: false)
    }

    private func refreshChrome() {
        let appearance = effectiveAppearance
        trackView.layer?.backgroundColor = LaughTheme.chromeHoverFill(appearance: appearance).cgColor
        selectionPill.layer?.backgroundColor = LaughTheme.chromeActiveFill(appearance: appearance).cgColor
        for (index, button) in buttons.enumerated() {
            let selected = modes[index] == selectedMode
            button.contentTintColor = selected ? .labelColor : .secondaryLabelColor
        }
    }

    private func refreshSelection(animated: Bool) {
        guard let index = modes.firstIndex(of: selectedMode) else { return }
        let originX = outerPadding + CGFloat(index) * buttonWidth
        let apply = {
            self.selectionLeadingConstraint?.constant = originX
            self.selectionWidthConstraint?.constant = self.buttonWidth
            self.refreshChrome()
            self.layoutSubtreeIfNeeded()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                apply()
            }
        } else {
            apply()
        }
    }

    @objc private func tabPressed(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0, index < modes.count else { return }
        let mode = modes[index]
        guard mode != selectedMode else { return }
        selectedMode = mode
        refreshSelection(animated: true)
        guard !suppressChange else { return }
        onChange?(mode)
    }
}
