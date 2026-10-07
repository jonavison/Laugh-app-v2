import AppKit

/// Fully rounded pill tab switcher for Gallery / Grid / List.
final class LibraryLayoutModeSwitcher: NSView {
    var onChange: ((LibraryBrowseViewMode) -> Void)?

    private let modes = LibraryBrowseViewMode.allCases
    private let trackView = NSView()
    private let selectionPill = NSView()
    private let hoverPill = NSView()
    private let buttonStack = NSStackView()
    private var buttons: [LibraryLayoutModeTabButton] = []
    private var selectedMode: LibraryBrowseViewMode = .gallery
    private var hoveredMode: LibraryBrowseViewMode?
    private var selectionLeadingConstraint: NSLayoutConstraint?
    private var selectionWidthConstraint: NSLayoutConstraint?
    private var hoverLeadingConstraint: NSLayoutConstraint?
    private var hoverWidthConstraint: NSLayoutConstraint?
    private var suppressChange = false

    private let outerPadding: CGFloat = 3
    private let buttonWidth: CGFloat = 34
    private let controlHeight: CGFloat = 30

    private var highlightedMode: LibraryBrowseViewMode {
        hoveredMode ?? selectedMode
    }

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
        if hoveredMode == mode {
            hoveredMode = nil
        }
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
        hoverPill.layer?.cornerRadius = pillHeight / 2
        refreshSelection(animated: false)
        refreshHoverPill(animated: false)
    }

    private func setup() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        trackView.wantsLayer = true
        trackView.translatesAutoresizingMaskIntoConstraints = false
        trackView.layer?.masksToBounds = true
        addSubview(trackView)

        hoverPill.wantsLayer = true
        hoverPill.translatesAutoresizingMaskIntoConstraints = false
        hoverPill.alphaValue = 0
        trackView.addSubview(hoverPill)

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
            let button = LibraryLayoutModeTabButton(mode: mode, symbolConfig: symbolConfig)
            button.tag = index
            button.target = self
            button.action = #selector(tabPressed(_:))
            button.onHoverChange = { [weak self] mode, hovering in
                self?.handleHover(mode, hovering: hovering)
            }
            button.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
            button.heightAnchor.constraint(equalToConstant: controlHeight - outerPadding * 2).isActive = true
            buttons.append(button)
            buttonStack.addArrangedSubview(button)
        }

        let leading = selectionPill.leadingAnchor.constraint(equalTo: trackView.leadingAnchor, constant: outerPadding)
        let width = selectionPill.widthAnchor.constraint(equalToConstant: buttonWidth)
        selectionLeadingConstraint = leading
        selectionWidthConstraint = width
        let hLeading = hoverPill.leadingAnchor.constraint(equalTo: trackView.leadingAnchor, constant: outerPadding)
        let hWidth = hoverPill.widthAnchor.constraint(equalToConstant: buttonWidth)
        hoverLeadingConstraint = hLeading
        hoverWidthConstraint = hWidth

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
            selectionPill.bottomAnchor.constraint(equalTo: trackView.bottomAnchor, constant: -outerPadding),
            hLeading,
            hWidth,
            hoverPill.topAnchor.constraint(equalTo: trackView.topAnchor, constant: outerPadding),
            hoverPill.bottomAnchor.constraint(equalTo: trackView.bottomAnchor, constant: -outerPadding)
        ])

        refreshChrome()
        refreshSelection(animated: false)
        refreshHoverPill(animated: false)
    }

    private func refreshChrome() {
        let appearance = effectiveAppearance
        trackView.layer?.backgroundColor = LaughTheme.libraryToolbarPillFill(appearance: appearance).cgColor
        selectionPill.layer?.backgroundColor = LaughTheme.chromeActiveFill(appearance: appearance).cgColor
        hoverPill.layer?.backgroundColor = LaughTheme.chromeActiveFill(appearance: appearance).cgColor
        for button in buttons {
            let emphasized = button.mode == highlightedMode
            button.contentTintColor = emphasized ? .labelColor : .secondaryLabelColor
        }
    }

    private func handleHover(_ mode: LibraryBrowseViewMode, hovering: Bool) {
        if hovering {
            hoveredMode = mode
        } else if hoveredMode == mode {
            hoveredMode = nil
        }
        refreshChrome()
        refreshHoverPill(animated: true)
    }

    private func refreshHoverPill(animated: Bool) {
        let show: Bool
        let index: Int?
        if let hoveredMode,
           let i = modes.firstIndex(of: hoveredMode),
           hoveredMode != selectedMode {
            show = true
            index = i
        } else {
            show = false
            index = nil
        }
        if let index {
            positionPill(leading: hoverLeadingConstraint, width: hoverWidthConstraint, at: index, animated: animated)
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.hoverPill.animator().alphaValue = show ? 1 : 0
            }
        } else {
            hoverPill.alphaValue = show ? 1 : 0
        }
    }

    private func refreshSelection(animated: Bool) {
        guard let index = modes.firstIndex(of: selectedMode) else { return }
        positionPill(leading: selectionLeadingConstraint, width: selectionWidthConstraint, at: index, animated: animated)
        refreshChrome()
        refreshHoverPill(animated: animated)
    }

    private func positionPill(
        leading: NSLayoutConstraint?,
        width: NSLayoutConstraint?,
        at index: Int,
        animated: Bool
    ) {
        let originX = outerPadding + CGFloat(index) * buttonWidth
        let apply = {
            leading?.constant = originX
            width?.constant = self.buttonWidth
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
        hoveredMode = nil
        refreshSelection(animated: true)
        guard !suppressChange else { return }
        onChange?(mode)
    }
}

private final class LibraryLayoutModeTabButton: NSButton {
    let mode: LibraryBrowseViewMode
    var onHoverChange: ((LibraryBrowseViewMode, Bool) -> Void)?
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false {
        didSet {
            guard oldValue != isHovered else { return }
            onHoverChange?(mode, isHovered)
        }
    }

    init(mode: LibraryBrowseViewMode, symbolConfig: NSImage.SymbolConfiguration) {
        self.mode = mode
        super.init(frame: .zero)
        bezelStyle = .inline
        isBordered = false
        focusRingType = .none
        title = ""
        toolTip = mode.menuTitle
        translatesAutoresizingMaskIntoConstraints = false
        if let image = NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: mode.menuTitle) {
            self.image = image.withSymbolConfiguration(symbolConfig)
            imagePosition = .imageOnly
        }
        contentTintColor = .secondaryLabelColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
}
