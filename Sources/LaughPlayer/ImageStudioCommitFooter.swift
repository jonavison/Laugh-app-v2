import AppKit

/// Pinned footer on the image studio edit sidebar (ADR 0006):
/// Save / Discard when dirty, Reset, then Save Preset / Export.
final class ImageStudioCommitFooter: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    let saveDevelopButton = CommitFooterActionButton(
        title: "Save",
        symbol: "square.and.arrow.down",
        emphasized: true,
        toolTip: "Save develop edits for this photo in Laugh"
    )
    let discardDevelopButton = CommitFooterActionButton(
        title: "Discard",
        symbol: "arrow.uturn.backward",
        emphasized: false,
        toolTip: "Reload the last saved look (or none)"
    )
    let resetButton = CommitFooterActionButton(
        title: "Reset",
        symbol: "arrow.counterclockwise",
        emphasized: false,
        toolTip: "Reset live sliders toward identity (Save to keep cleared; does not delete a saved look)"
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

    /// Back-compat alias used by existing PVC wiring.
    var resetAllButton: CommitFooterActionButton { resetButton }

    private let hairline = NSView()
    private let column = NSStackView()
    private let commitRow = NSStackView()
    private let resetRow = NSStackView()
    private let actionsRow = NSStackView()

    static let preferredHeightFull: CGFloat = 154
    static let preferredHeightUnsaved: CGFloat = 112
    static let preferredHeightSavedOnly: CGFloat = 68
    static let preferredHeightActionsOnly: CGFloat = 68
    /// Legacy name — full develop chrome.
    static let preferredHeight: CGFloat = preferredHeightFull

    func setShowsUnsavedCommit(_ show: Bool) {
        commitRow.isHidden = !show
    }

    func setShowsReset(_ show: Bool) {
        resetButton.isHidden = !show
        resetRow.isHidden = !show
    }

    /// Legacy: Reset All visibility (selection / develop identity chrome).
    func setShowsResetAll(_ show: Bool) {
        setShowsReset(show)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor.separatorColor.cgColor
        hairline.translatesAutoresizingMaskIntoConstraints = false

        commitRow.orientation = .horizontal
        commitRow.alignment = .centerY
        commitRow.spacing = 10
        commitRow.distribution = .fillEqually
        commitRow.translatesAutoresizingMaskIntoConstraints = false
        commitRow.addArrangedSubview(saveDevelopButton)
        commitRow.addArrangedSubview(discardDevelopButton)

        resetRow.orientation = .horizontal
        resetRow.alignment = .centerY
        resetRow.spacing = 10
        resetRow.distribution = .fillEqually
        resetRow.translatesAutoresizingMaskIntoConstraints = false
        resetRow.addArrangedSubview(resetButton)

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
        column.addArrangedSubview(commitRow)
        column.addArrangedSubview(resetRow)
        column.addArrangedSubview(actionsRow)
        commitRow.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        resetRow.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
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

        setShowsUnsavedCommit(false)
        setShowsReset(false)
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
        saveDevelopButton.refreshChrome(appearance: appearance)
        discardDevelopButton.refreshChrome(appearance: appearance)
        resetButton.refreshChrome(appearance: appearance)
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

    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false {
        didSet { applyFill() }
    }
    private var isPressed = false {
        didSet { applyFill() }
    }

    func refreshChrome(appearance: NSAppearance) {
        applyFill(appearance: appearance)
        iconView.contentTintColor = .labelColor
        titleLabel.textColor = .labelColor
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.45
            if !isEnabled {
                isHovered = false
                isPressed = false
            }
        }
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

    private var mouseDownInside = false

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        mouseDownInside = false
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        mouseDownInside = true
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        mouseDownInside = bounds.contains(local)
        isPressed = mouseDownInside
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let inside = mouseDownInside && bounds.contains(local)
        mouseDownInside = false
        isPressed = false
        guard isEnabled, inside else { return }
        // Don’t rely on NSButton cell action — empty highlightsBy + hitTest bugs skipped clicks.
        if let target, let action {
            _ = target.perform(action, with: self)
        }
    }

    /// `point` is in the superview’s coordinates — `bounds.contains` breaks offset chips.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyFill()
    }

    private func applyFill(appearance: NSAppearance? = nil) {
        let appearance = appearance ?? effectiveAppearance
        let fill: NSColor
        if emphasized {
            if isPressed || isHovered {
                fill = LaughTheme.chromePressedFill(appearance: appearance)
            } else {
                fill = LaughTheme.chromeActiveFill(appearance: appearance)
            }
        } else if isPressed || isHovered {
            fill = LaughTheme.chromeActiveFill(appearance: appearance)
        } else {
            fill = LaughTheme.chromeHoverFill(appearance: appearance)
        }
        layer?.backgroundColor = fill.cgColor
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
        if let cell = cell as? NSButtonCell {
            cell.highlightsBy = []
            cell.showsStateBy = []
        }
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
        applyFill()
    }
}
