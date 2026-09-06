import AppKit
import AVFoundation
import QuartzCore

private enum SidebarMetrics {
    static let edgeInset: CGFloat = 16
    static let rowTextInset: CGFloat = 10
}

private enum LibraryPanelPlateStyle {
    case sidebar
    case content
    case contentRaised
}

/// Opaque library panel floor — paints via `updateLayer` so appearance changes stay in sync.
private final class LibraryPanelPlateView: NSView {
    private let style: LibraryPanelPlateStyle

    init(style: LibraryPanelPlateStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        let fill: NSColor
        switch style {
        case .sidebar:
            fill = LaughTheme.librarySidebarBackground(appearance: effectiveAppearance)
        case .content:
            fill = LaughTheme.libraryContentBackground(appearance: effectiveAppearance)
        case .contentRaised:
            fill = LaughTheme.libraryContentRaisedBackground(appearance: effectiveAppearance)
        }
        layer?.backgroundColor = fill.cgColor
    }
}

// MARK: - Sidebar (LibraryRoot list)

final class LibrarySidebarView: NSView, NSTableViewDelegate, NSTableViewDataSource {
    static let width: CGFloat = 220

    private enum Metrics {
        static let topInset: CGFloat = 18
        static let bottomInset: CGFloat = 12
        static let listToToolbarSpacing: CGFloat = 10
        static let rowSpacing: CGFloat = LaughTheme.Sidebar.menuItemGap
        static let rowHeight: CGFloat = LaughTheme.Sidebar.MenuButton.rowHeight
        static let librarySeparatorRowHeight: CGFloat = LaughTheme.Sidebar.sectionSeparatorHeight
    }

    private let controller: MediaLibraryController
    private let plateView = LibraryPanelPlateView(style: .sidebar)
    private let scroll = NSScrollView()
    private let table = NSTableView()
    private let toolbar = NSStackView()
    private let trailingDivider = NSView()
    private let addFolderButton = NSButton(title: "", target: nil, action: nil)
    private let removeFolderButton = NSButton(title: "", target: nil, action: nil)
    private var scrollTopConstraint: NSLayoutConstraint?
    private var titleBarChromeVisible = false
    private var suppressSelectionAction = false
    private var isUpdatingScrollerLayout = false

    init(controller: MediaLibraryController) {
        self.controller = controller
        super.init(frame: .zero)
        configureChrome()
        configureSubviews()
        activateLayout()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reloadRoots() {
        controller.reloadRoots()
    }

    private func configureChrome() {
        wantsLayer = true

        plateView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(plateView)
        NSLayoutConstraint.activate([
            plateView.topAnchor.constraint(equalTo: topAnchor),
            plateView.leadingAnchor.constraint(equalTo: leadingAnchor),
            plateView.trailingAnchor.constraint(equalTo: trailingAnchor),
            plateView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        trailingDivider.wantsLayer = true
        trailingDivider.translatesAutoresizingMaskIntoConstraints = false
        trailingDivider.layer?.backgroundColor = NSColor.separatorColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        trailingDivider.layer?.backgroundColor = NSColor.separatorColor.cgColor
    }

    private func configureSubviews() {
        configureToolbarButton(addFolderButton, symbol: "plus", toolTip: "Add folder…", tint: .secondaryLabelColor)
        configureToolbarButton(removeFolderButton, symbol: "minus", toolTip: "Remove selected folder", tint: .secondaryLabelColor)
        addFolderButton.target = self
        addFolderButton.action = #selector(addFolderPressed)
        removeFolderButton.target = self
        removeFolderButton.action = #selector(removeFolderPressed)

        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addArrangedSubview(addFolderButton)
        toolbar.addArrangedSubview(removeFolderButton)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        column.minWidth = 120
        column.maxWidth = 10_000
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = Metrics.rowHeight
        table.intercellSpacing = NSSize(width: 0, height: Metrics.rowSpacing)
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(selectionChanged)
        table.usesAutomaticRowHeights = false

        scroll.documentView = table
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scroll)
        addSubview(toolbar)
        addSubview(trailingDivider)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        guard !isUpdatingScrollerLayout else { return }
        isUpdatingScrollerLayout = true
        defer { isUpdatingScrollerLayout = false }
        updateScrollerVisibility()
    }

    func syncTitleBarContentInset(chromeVisible: Bool) {
        titleBarChromeVisible = chromeVisible
        applyTitleBarContentInset()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyTitleBarContentInset()
    }

    override func layout() {
        super.layout()
        applyTitleBarContentInset()
    }

    private func applyTitleBarContentInset() {
        scrollTopConstraint?.constant = ImmersiveWindowChrome.libraryContentTopInset(
            for: window,
            chromeVisible: titleBarChromeVisible
        )
    }

    private func activateLayout() {
        scrollTopConstraint = scroll.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.topInset)
        NSLayoutConstraint.activate([
            scrollTopConstraint!,
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SidebarMetrics.edgeInset),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SidebarMetrics.edgeInset),
            scroll.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -Metrics.listToToolbarSpacing),

            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SidebarMetrics.edgeInset + SidebarMetrics.rowTextInset),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -SidebarMetrics.edgeInset),
            toolbar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.bottomInset),

            trailingDivider.topAnchor.constraint(equalTo: topAnchor),
            trailingDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
            trailingDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            trailingDivider.widthAnchor.constraint(equalToConstant: 1)
        ])
    }

    private func updateScrollerVisibility() {
        guard bounds.width > 1, bounds.height > 1 else { return }

        let rows = controller.sidebarRowCount()
        let contentHeight = sidebarContentHeight(rowCount: rows)
        let clipHeight = scroll.contentView.bounds.height
        guard clipHeight > 0 else { return }

        let needsScroller = contentHeight > clipHeight + 1
        if scroll.hasVerticalScroller != needsScroller {
            scroll.hasVerticalScroller = needsScroller
        }
        if !needsScroller {
            scroll.contentView.scroll(to: .zero)
        }

        let targetWidth = scroll.contentView.bounds.width
        let targetHeight = max(contentHeight, clipHeight)
        var frame = table.frame
        let widthChanged = abs(frame.size.width - targetWidth) > 0.5
        let heightChanged = abs(frame.size.height - targetHeight) > 0.5
        guard widthChanged || heightChanged else { return }

        frame.size.width = targetWidth
        frame.size.height = targetHeight
        table.frame = frame
        if widthChanged {
            table.sizeLastColumnToFit()
        }
    }

    private func sidebarContentHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        let spacing = table.intercellSpacing.height
        var height: CGFloat = 0
        for row in 0..<rowCount {
            height += rowHeight(for: row)
            if row < rowCount - 1 {
                height += spacing
            }
        }
        return height
    }

    private func rowHeight(for row: Int) -> CGFloat {
        guard let sidebarRow = controller.sidebarRow(at: row) else { return Metrics.rowHeight }
        switch sidebarRow {
        case .librarySeparator:
            return Metrics.librarySeparatorRowHeight
        case .recentHeader, .favoritesHeader, .librarySectionHeader, .root, .recentItem:
            return Metrics.rowHeight
        }
    }

    private func configureToolbarButton(_ button: NSButton, symbol: String, toolTip: String, tint: NSColor) {
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.toolTip = toolTip
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip) {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
            button.image?.isTemplate = false
            button.contentTintColor = tint
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    func refresh() {
        suppressSelectionAction = true
        defer { suppressSelectionAction = false }
        table.reloadData()
        if controller.selectedSidebarRow < 0 {
            table.deselectAll(nil)
        } else {
            table.selectRowIndexes(IndexSet(integer: controller.selectedSidebarRow), byExtendingSelection: false)
        }
        removeFolderButton.isEnabled = controller.canRemoveSelectedRoot
        needsLayout = true
        updateScrollerVisibility()
    }

    @objc private func selectionChanged() {
        guard !suppressSelectionAction else { return }
        let row = table.selectedRow
        guard row >= 0 else {
            controller.clearSidebarSelection()
            return
        }
        controller.selectSidebarRow(row)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        controller.isSidebarRowSelectable(row)
    }

    @objc private func addFolderPressed() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a folder to add to the media library."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try controller.addRoot(at: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func removeFolderPressed() {
        controller.removeSelectedRoot()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        controller.sidebarRowCount()
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        rowHeight(for: row)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView.makeView(withIdentifier: SidebarTableRowView.reuseID, owner: self) as? SidebarTableRowView ?? SidebarTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let sidebarRow = controller.sidebarRow(at: row) else { return nil }

        switch sidebarRow {
        case .recentItem(let file):
            let cell = tableView.makeView(withIdentifier: SidebarListCell.reuseID, owner: self) as? SidebarListCell ?? SidebarListCell()
            cell.configure(
                title: file.url.lastPathComponent,
                style: .menuButton,
                toolTip: file.url.path,
                symbol: LaughTheme.Sidebar.mediaKindSymbol(for: file.kind)
            )
            return cell
        case .recentHeader:
            let cell = tableView.makeView(withIdentifier: SidebarListCell.reuseID, owner: self) as? SidebarListCell ?? SidebarListCell()
            cell.configure(
                title: "Recents",
                style: .menuButton,
                toolTip: "Show all recently opened files",
                symbol: "clock.fill",
                iconColor: LaughTheme.Sidebar.iconColor(forSymbol: "clock.fill")
            )
            return cell
        case .favoritesHeader:
            let cell = tableView.makeView(withIdentifier: SidebarListCell.reuseID, owner: self) as? SidebarListCell ?? SidebarListCell()
            cell.configure(
                title: "Favorites",
                style: .menuButton,
                toolTip: "Show favorite images",
                symbol: "heart.fill",
                iconColor: LaughTheme.Sidebar.iconColor(forSymbol: "heart.fill")
            )
            return cell
        case .librarySeparator:
            let cell = tableView.makeView(
                withIdentifier: SidebarGradientSeparatorView.reuseID,
                owner: self
            ) as? SidebarGradientSeparatorView ?? SidebarGradientSeparatorView()
            return cell
        case .librarySectionHeader:
            let cell = tableView.makeView(withIdentifier: SidebarListCell.reuseID, owner: self) as? SidebarListCell ?? SidebarListCell()
            cell.configure(
                title: "Library",
                style: .menuButton,
                toolTip: "Library folders",
                symbol: "folder.fill",
                iconColor: LaughTheme.Sidebar.iconColor(forSymbol: "folder.fill")
            )
            return cell
        case .root(let root):
            let cell = tableView.makeView(withIdentifier: SidebarListCell.reuseID, owner: self) as? SidebarListCell ?? SidebarListCell()
            cell.configure(
                title: root.displayName,
                style: .menuButton,
                toolTip: root.directoryURL.path,
                symbol: "folder"
            )
            return cell
        }
    }
}

private final class SidebarGradientSeparatorView: NSView {
    static let reuseID = NSUserInterfaceItemIdentifier("SidebarGradientSeparatorView")

    private let lineView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
        lineView.wantsLayer = true
        lineView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lineView)
        NSLayoutConstraint.activate([
            lineView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LaughTheme.Sidebar.MenuButton.padding),
            lineView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -LaughTheme.Sidebar.MenuButton.padding),
            lineView.centerYAnchor.constraint(equalTo: centerYAnchor),
            lineView.heightAnchor.constraint(equalToConstant: 1)
        ])
        updateLineColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLineColor()
    }

    private func updateLineColor() {
        lineView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
    }
}

private final class SidebarListCell: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("SidebarListCell")

    enum Style {
        /// shadcn `SidebarMenuButton` — Recents, library folders
        case menuButton
        /// shadcn `SidebarGroupLabel` — Library section title
        case groupLabel
        /// shadcn `SidebarMenuSubButton` — recent file shortcuts
        case menuSubButton
    }

    private let contentRow = NSStackView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var style: Style = .menuButton
    private var iconTint: NSColor?
    private var contentLeadingConstraint: NSLayoutConstraint!
    private var contentTrailingConstraint: NSLayoutConstraint!
    private var iconWidthConstraint: NSLayoutConstraint!
    private var iconHeightConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID

        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        iconView.isHidden = true

        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        contentRow.orientation = .horizontal
        contentRow.alignment = .centerY
        contentRow.spacing = LaughTheme.InlineButton.iconTextGap
        contentRow.translatesAutoresizingMaskIntoConstraints = false
        contentRow.addArrangedSubview(iconView)
        contentRow.addArrangedSubview(nameLabel)

        addSubview(contentRow)
        textField = nameLabel

        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: LaughTheme.Sidebar.MenuButton.iconSize)
        iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: LaughTheme.Sidebar.MenuButton.iconSize)
        contentLeadingConstraint = contentRow.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: LaughTheme.Sidebar.MenuButton.padding
        )
        contentTrailingConstraint = contentRow.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingAnchor,
            constant: -LaughTheme.Sidebar.MenuButton.padding
        )

        NSLayoutConstraint.activate([
            iconWidthConstraint,
            iconHeightConstraint,
            contentRow.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentLeadingConstraint,
            contentTrailingConstraint
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            applyTextAppearance()
        }
    }

    func configure(
        title: String,
        style: Style,
        toolTip: String,
        symbol: String? = nil,
        iconColor: NSColor? = nil
    ) {
        nameLabel.stringValue = title
        self.style = style
        self.toolTip = toolTip.isEmpty ? nil : toolTip
        iconTint = iconColor
        applyRowMetrics()
        applySectionIcon(symbol: symbol)
        applyTextAppearance()
    }

    private func applyRowMetrics() {
        switch style {
        case .menuButton:
            iconWidthConstraint.constant = LaughTheme.Sidebar.MenuButton.iconSize
            iconHeightConstraint.constant = LaughTheme.Sidebar.MenuButton.iconSize
            contentRow.spacing = LaughTheme.Sidebar.MenuButton.gap
            applyContentInsets(
                leading: LaughTheme.Sidebar.MenuButton.padding,
                trailing: LaughTheme.Sidebar.MenuButton.padding
            )
        case .groupLabel:
            iconWidthConstraint.constant = LaughTheme.Sidebar.GroupLabel.iconSize
            iconHeightConstraint.constant = LaughTheme.Sidebar.GroupLabel.iconSize
            contentRow.spacing = LaughTheme.Sidebar.GroupLabel.gap
            applyContentInsets(
                leading: LaughTheme.Sidebar.GroupLabel.paddingX,
                trailing: LaughTheme.Sidebar.GroupLabel.paddingX
            )
        case .menuSubButton:
            iconWidthConstraint.constant = LaughTheme.Sidebar.MenuButton.iconSize
            iconHeightConstraint.constant = LaughTheme.Sidebar.MenuButton.iconSize
            contentRow.spacing = LaughTheme.Sidebar.MenuButton.gap
            applyContentInsets(
                leading: LaughTheme.Sidebar.MenuSubButton.contentLeadingInset,
                trailing: LaughTheme.Sidebar.MenuButton.padding
            )
        }
    }

    private func applyContentInsets(leading: CGFloat, trailing: CGFloat) {
        contentLeadingConstraint.constant = leading
        contentTrailingConstraint.constant = -trailing
    }

    private func applySectionIcon(symbol: String?) {
        guard let symbol,
              let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        else {
            iconView.isHidden = true
            iconView.image = nil
            iconTint = nil
            return
        }

        let config: NSImage.SymbolConfiguration
        switch style {
        case .groupLabel:
            config = LaughTheme.Sidebar.GroupLabel.symbolConfiguration()
        case .menuSubButton:
            config = LaughTheme.Sidebar.MenuSubButton.symbolConfiguration()
        case .menuButton:
            config = LaughTheme.Sidebar.MenuButton.symbolConfiguration()
        }

        iconView.image = image.withSymbolConfiguration(config)
        if let iconTint {
            iconView.image?.isTemplate = false
            iconView.contentTintColor = iconTint
        } else {
            iconView.image?.isTemplate = true
        }
        iconView.isHidden = false
    }

    private func applyTextAppearance() {
        let selected = backgroundStyle == .emphasized
        switch style {
        case .menuButton:
            nameLabel.font = LaughTheme.Sidebar.MenuButton.labelFont
            LaughTheme.applySidebarSelectionLabelStyle(to: nameLabel, selected: selected, idleColor: .labelColor)
        case .groupLabel:
            nameLabel.font = LaughTheme.Sidebar.GroupLabel.labelFont
            nameLabel.textColor = .secondaryLabelColor
        case .menuSubButton:
            nameLabel.font = LaughTheme.Sidebar.MenuSubButton.labelFont
            LaughTheme.applySidebarSelectionLabelStyle(to: nameLabel, selected: selected, idleColor: .secondaryLabelColor)
        }
        if !iconView.isHidden, iconTint == nil {
            iconView.contentTintColor = selected ? .labelColor : .secondaryLabelColor
        }
    }
}

private final class SidebarTableRowView: NSTableRowView {
    static let reuseID = NSUserInterfaceItemIdentifier("SidebarTableRowView")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let rect: NSRect
        let radius: CGFloat
        if bounds.height <= LaughTheme.Sidebar.MenuSubButton.rowHeight + 1 {
            rect = LaughTheme.Sidebar.MenuSubButton.selectionRect(in: bounds)
            radius = LaughTheme.Sidebar.MenuSubButton.cornerRadius
        } else {
            rect = LaughTheme.Sidebar.MenuButton.selectionRect(in: bounds)
            radius = LaughTheme.Sidebar.MenuButton.cornerRadius
        }
        LaughTheme.fillSidebarSelection(in: rect, cornerRadius: radius)
    }
}

// MARK: - Browse placeholder (no folder selected)

private final class LibraryBrowsePlaceholderView: NSView {
    var onActivate: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Select Recents or a folder")
    private let hintLabel = NSTextField(labelWithString: "Click to open, or drop videos or images")
    private let borderLayer = CAShapeLayer()
    private var isPressed = false
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        applyPlaceholderFill()

        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1.5
        borderLayer.lineDashPattern = [7, 5]
        borderLayer.strokeColor = NSColor.tertiaryLabelColor.cgColor
        layer?.addSublayer(borderLayer)

        if let image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: "Open or drop files") {
            let config = NSImage.SymbolConfiguration(pointSize: 34, weight: .light)
            iconView.image = image.withSymbolConfiguration(config)
            iconView.image?.isTemplate = true
        }
        iconView.contentTintColor = .secondaryLabelColor
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, titleLabel, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 300),
            heightAnchor.constraint(equalToConstant: 188),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
        ])

        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    /// Capture clicks on labels / icon as clicks on the whole card.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01, bounds.contains(point) else { return nil }
        return self
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyPlaceholderFill()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        applyPlaceholderFill()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        applyPlaceholderFill()
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        applyPlaceholderFill()
        let local = convert(event.locationInWindow, from: nil)
        guard wasPressed, bounds.contains(local) else { return }
        onActivate?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPlaceholderFill()
    }

    private func applyPlaceholderFill() {
        let base = LaughTheme.libraryContentRaisedBackground(appearance: effectiveAppearance)
        let fill: NSColor
        if isPressed {
            fill = base.blended(withFraction: 0.14, of: .labelColor) ?? base
        } else if isHovered {
            fill = base.blended(withFraction: 0.08, of: .labelColor) ?? base
        } else {
            fill = base
        }
        layer?.backgroundColor = fill.cgColor
        borderLayer.strokeColor = (isHovered || isPressed
            ? NSColor.secondaryLabelColor
            : NSColor.tertiaryLabelColor).cgColor
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 1.5
        let rect = bounds.insetBy(dx: inset, dy: inset)
        borderLayer.path = CGPath(
            roundedRect: rect,
            cornerWidth: 12,
            cornerHeight: 12,
            transform: nil
        )
        borderLayer.frame = bounds
    }
}

// MARK: - Browse grid (main content area)

enum LibraryBrowseContextAction {
    case play
    case playNext
    case addToQueue
    case rename
    case showInFinder
    case remove
}

enum LibraryBrowseBatchAction {
    case play
    case addToQueue
    case remove
}

final class LibraryBrowseView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let controller: MediaLibraryController
    private let plateView = LibraryPanelPlateView(style: .content)
    private let backButton = NSButton(title: "", target: nil, action: nil)
    private let forwardButton = NSButton(title: "", target: nil, action: nil)
    private let openButton = NSButton(title: "Open…", target: nil, action: nil)
    private let playAllButton = NSButton(title: "Play All", target: nil, action: nil)
    private let batchPlayButton = NSButton(title: "Play", target: nil, action: nil)
    private let batchQueueButton = NSButton(title: "Queue", target: nil, action: nil)
    private let batchTrashButton = NSButton(title: "Trash", target: nil, action: nil)
    private let layoutPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let galleryScaleSlider = NSSlider()
    private let layoutControlsStack = NSStackView()
    private let searchField = NSSearchField()
    private let kindFilterPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sortPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let gridScroll = NSScrollView()
    private let collectionView = LibraryGridCollectionView()
    private let browseListScroll = NSScrollView()
    private let browseListTable = NSTableView()
    private let recentListScroll = NSScrollView()
    private let recentListTable = NSTableView()
    private let breadcrumbStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "Empty folder")
    private let browsePlaceholder = LibraryBrowsePlaceholderView()
    private var toolbarTopConstraint: NSLayoutConstraint?
    private var contentTopBelowToolbarConstraint: NSLayoutConstraint?
    private var contentTopBelowViewConstraint: NSLayoutConstraint?
    private var titleBarChromeVisible = false
    private var thumbnailTasks: [IndexPath: URL] = [:]
    private var searchDebounceWork: DispatchWorkItem?
    private var suppressBrowseListSelection = false
    private var appliedTileMetrics: LibraryBrowseTileMetrics?
    private var suppressGalleryScaleChange = false
    var onOpenMediaPanel: (() -> Void)?
    var onPlayAll: (() -> Void)?
    var onContextAction: ((LibraryBrowseContextAction, LibraryBrowseEntry) -> Void)?
    var onBatchAction: ((LibraryBrowseBatchAction, [LibraryBrowseEntry]) -> Void)?

    init(controller: MediaLibraryController) {
        self.controller = controller
        super.init(frame: .zero)
        browsePlaceholder.onActivate = { [weak self] in
            self?.onOpenMediaPanel?()
        }
        configureSubviews()
        activateLayout()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh() {
        backButton.isEnabled = controller.canGoBack
        forwardButton.isEnabled = controller.canGoForward
        recentListTable.reloadData()

        let showPlaceholder = controller.showsBrowsePlaceholder
        let showRecentList = controller.showsRecentList
        let showFavoritesChrome = controller.showsFavoritesList
        let folderChrome = controller.showsFolderBrowseChrome || showFavoritesChrome
        let mode = controller.effectiveViewMode
        let useList = mode.isListLayout
        let showGrid = !showPlaceholder && !showRecentList && folderChrome && !useList
        let showBrowseList = !showPlaceholder && !showRecentList && folderChrome && useList

        browsePlaceholder.isHidden = !showPlaceholder
        recentListScroll.isHidden = !showRecentList
        gridScroll.isHidden = !showGrid
        browseListScroll.isHidden = !showBrowseList
        emptyLabel.isHidden = showPlaceholder || !controller.displayedEntries.isEmpty
        if !showPlaceholder {
            emptyLabel.stringValue = controller.emptyGridMessage
        }

        let hideNavToolbar = showRecentList
        backButton.isHidden = hideNavToolbar || showFavoritesChrome
        forwardButton.isHidden = hideNavToolbar || showFavoritesChrome
        openButton.isHidden = hideNavToolbar
        playAllButton.isHidden = hideNavToolbar || showPlaceholder
        sortPopUp.isHidden = hideNavToolbar || !controller.showsBrowseSortControl
        layoutPopUp.isHidden = hideNavToolbar || !controller.showsBrowseViewModeControl
        layoutControlsStack.isHidden = layoutPopUp.isHidden
        let showGalleryScale = !layoutPopUp.isHidden && mode == .gallery
        galleryScaleSlider.isHidden = !showGalleryScale
        searchField.isHidden = hideNavToolbar || !controller.showsBrowseSearch
        kindFilterPopUp.isHidden = hideNavToolbar || !controller.showsKindFilter

        let batchVisible = controller.hasBatchSelection && !showPlaceholder && !showRecentList
        batchPlayButton.isHidden = !batchVisible
        batchQueueButton.isHidden = !batchVisible
        batchTrashButton.isHidden = !batchVisible
        if batchVisible {
            playAllButton.isHidden = true
        }

        contentTopBelowToolbarConstraint?.isActive = !hideNavToolbar
        contentTopBelowViewConstraint?.isActive = hideNavToolbar
        if hideNavToolbar {
            updateContentTopInsetForRecents()
        }

        if searchField.stringValue != controller.searchQuery {
            searchField.stringValue = controller.searchQuery
        }
        updateKindFilterControl()
        updateLayoutControl()
        updateGalleryScaleControl()
        updateBrowseListAppearance()

        let metrics = controller.tileMetrics
        let galleryScaleReflow = showGrid
            && mode == .gallery
            && appliedTileMetrics != nil
            && appliedTileMetrics != metrics
            && collectionView.numberOfItems(inSection: 0) == controller.displayedEntries.count

        if galleryScaleReflow {
            applyCollectionLayout(animated: true)
            reflowVisibleCollectionItems(metrics: metrics)
        } else {
            thumbnailTasks.removeAll()
            collectionView.reloadData()
            applyCollectionLayout(animated: false)
        }

        browseListTable.reloadData()
        updateBreadcrumb()
        updateSortControl()
        syncCollectionSelection()
        syncBrowseListSelection()
        playAllButton.isEnabled = controller.canPlayAllInBrowse
        if showPlaceholder {
            playAllButton.isHidden = true
        }
    }

    private func reflowVisibleCollectionItems(metrics: LibraryBrowseTileMetrics) {
        for path in collectionView.indexPathsForVisibleItems() {
            guard let entry = controller.entry(at: path) else { continue }
            switch entry.kind {
            case .folder:
                (collectionView.item(at: path) as? LibraryFolderGridItem)?.applyMetrics(metrics)
            case .media(let file):
                guard let item = collectionView.item(at: path) as? LibraryMediaGridItem else { continue }
                item.applyMetrics(metrics)
                item.loadThumbnail(for: file.url, kind: file.kind, maxSide: metrics.thumbnailMaxSide, indexPath: path) { [weak self, weak item] image, indexPath in
                    guard let self, let item, self.thumbnailTasks[indexPath] == file.url else { return }
                    item.setThumbnail(image)
                }
                thumbnailTasks[path] = file.url
            }
        }
    }

    func reloadContent() {
        controller.reloadGrid()
        refresh()
    }

    private func configureSubviews() {
        wantsLayer = true

        plateView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(plateView)
        NSLayoutConstraint.activate([
            plateView.topAnchor.constraint(equalTo: topAnchor),
            plateView.leadingAnchor.constraint(equalTo: leadingAnchor),
            plateView.trailingAnchor.constraint(equalTo: trailingAnchor),
            plateView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        configureNavButton(backButton, symbol: "chevron.left", toolTip: "Back")
        configureNavButton(forwardButton, symbol: "chevron.right", toolTip: "Forward")
        backButton.target = self
        backButton.action = #selector(backPressed)
        forwardButton.target = self
        forwardButton.action = #selector(forwardPressed)

        openButton.bezelStyle = .rounded
        openButton.font = .systemFont(ofSize: 11)
        openButton.target = self
        openButton.action = #selector(openPressed)
        openButton.translatesAutoresizingMaskIntoConstraints = false

        playAllButton.bezelStyle = .rounded
        playAllButton.font = .systemFont(ofSize: 11)
        playAllButton.toolTip = "Play every video and image in this folder, in sort order"
        playAllButton.target = self
        playAllButton.action = #selector(playAllPressed)
        playAllButton.translatesAutoresizingMaskIntoConstraints = false

        for button in [batchPlayButton, batchQueueButton, batchTrashButton] {
            button.bezelStyle = .rounded
            button.font = .systemFont(ofSize: 11)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.isHidden = true
        }
        batchPlayButton.toolTip = "Play selected items"
        batchPlayButton.target = self
        batchPlayButton.action = #selector(batchPlayPressed)
        batchQueueButton.toolTip = "Add selected items to queue"
        batchQueueButton.target = self
        batchQueueButton.action = #selector(batchQueuePressed)
        batchTrashButton.toolTip = "Move selected items to Trash"
        batchTrashButton.target = self
        batchTrashButton.action = #selector(batchTrashPressed)

        layoutPopUp.font = .systemFont(ofSize: 11)
        layoutPopUp.controlSize = .small
        layoutPopUp.toolTip = "Layout"
        layoutPopUp.translatesAutoresizingMaskIntoConstraints = false
        layoutPopUp.target = self
        layoutPopUp.action = #selector(layoutPopUpChanged)
        updateLayoutControl()

        galleryScaleSlider.minValue = 0
        galleryScaleSlider.maxValue = 2
        galleryScaleSlider.numberOfTickMarks = 3
        galleryScaleSlider.allowsTickMarkValuesOnly = true
        galleryScaleSlider.isContinuous = false
        galleryScaleSlider.controlSize = .small
        galleryScaleSlider.toolTip = "Gallery size"
        galleryScaleSlider.translatesAutoresizingMaskIntoConstraints = false
        galleryScaleSlider.target = self
        galleryScaleSlider.action = #selector(galleryScaleChanged)
        galleryScaleSlider.isHidden = true
        galleryScaleSlider.widthAnchor.constraint(equalToConstant: 72).isActive = true
        updateGalleryScaleControl()

        layoutControlsStack.orientation = .horizontal
        layoutControlsStack.alignment = .centerY
        layoutControlsStack.spacing = 8
        layoutControlsStack.translatesAutoresizingMaskIntoConstraints = false
        layoutControlsStack.addArrangedSubview(galleryScaleSlider)
        layoutControlsStack.addArrangedSubview(layoutPopUp)

        searchField.placeholderString = "Search this folder"
        searchField.font = .systemFont(ofSize: 11)
        searchField.controlSize = .small
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)

        kindFilterPopUp.font = .systemFont(ofSize: 11)
        kindFilterPopUp.controlSize = .small
        kindFilterPopUp.translatesAutoresizingMaskIntoConstraints = false
        kindFilterPopUp.target = self
        kindFilterPopUp.action = #selector(kindFilterChanged)
        updateKindFilterControl()

        sortPopUp.font = .systemFont(ofSize: 11)
        sortPopUp.controlSize = .small
        sortPopUp.translatesAutoresizingMaskIntoConstraints = false
        sortPopUp.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sortPopUp.cell?.lineBreakMode = .byTruncatingTail
        updateSortControl()

        let layout = NSCollectionViewGridLayout()
        layout.margins = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        collectionView.collectionViewLayout = layout
        applyCollectionLayout(animated: false)

        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.contextMenuProvider = { [weak self] event, collectionView in
            self?.contextMenu(for: event, in: collectionView)
        }
        collectionView.register(LibraryFolderGridItem.self, forItemWithIdentifier: LibraryFolderGridItem.reuseID)
        collectionView.register(LibraryMediaGridItem.self, forItemWithIdentifier: LibraryMediaGridItem.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        gridScroll.documentView = collectionView
        gridScroll.hasVerticalScroller = true
        gridScroll.autohidesScrollers = true
        gridScroll.scrollerStyle = .overlay
        gridScroll.drawsBackground = false
        gridScroll.borderType = .noBorder
        gridScroll.translatesAutoresizingMaskIntoConstraints = false

        configureBrowseListTable()

        let recentColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("recentList"))
        recentColumn.minWidth = 120
        recentListTable.addTableColumn(recentColumn)
        recentListTable.headerView = nil
        recentListTable.rowHeight = LaughTheme.Sidebar.MenuButton.rowHeight
        recentListTable.intercellSpacing = NSSize(width: 0, height: LaughTheme.Sidebar.menuItemGap)
        recentListTable.backgroundColor = .clear
        recentListTable.style = .plain
        recentListTable.selectionHighlightStyle = .regular
        recentListTable.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        recentListTable.delegate = self
        recentListTable.dataSource = self
        recentListTable.target = self
        recentListTable.doubleAction = #selector(recentListDoubleClicked)
        recentListTable.translatesAutoresizingMaskIntoConstraints = false

        recentListScroll.documentView = recentListTable
        recentListScroll.hasVerticalScroller = true
        recentListScroll.autohidesScrollers = true
        recentListScroll.scrollerStyle = .overlay
        recentListScroll.drawsBackground = false
        recentListScroll.borderType = .noBorder
        recentListScroll.automaticallyAdjustsContentInsets = false
        recentListScroll.contentInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        recentListScroll.translatesAutoresizingMaskIntoConstraints = false
        recentListScroll.isHidden = true

        breadcrumbStack.orientation = .horizontal
        breadcrumbStack.alignment = .centerY
        breadcrumbStack.spacing = 2
        breadcrumbStack.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        browsePlaceholder.isHidden = true
        browsePlaceholder.translatesAutoresizingMaskIntoConstraints = false

        addSubview(backButton)
        addSubview(forwardButton)
        addSubview(openButton)
        addSubview(playAllButton)
        addSubview(batchPlayButton)
        addSubview(batchQueueButton)
        addSubview(batchTrashButton)
        addSubview(searchField)
        addSubview(kindFilterPopUp)
        addSubview(layoutControlsStack)
        addSubview(sortPopUp)
        addSubview(gridScroll)
        addSubview(browseListScroll)
        addSubview(recentListScroll)
        addSubview(breadcrumbStack)
        addSubview(emptyLabel)
        addSubview(browsePlaceholder)
    }

    private func configureBrowseListTable() {
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("browseName"))
        nameColumn.title = "Name"
        nameColumn.minWidth = 160
        nameColumn.width = 280
        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("browseKind"))
        kindColumn.title = "Kind"
        kindColumn.minWidth = 70
        kindColumn.width = 90
        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("browseDate"))
        dateColumn.title = "Date Modified"
        dateColumn.minWidth = 120
        dateColumn.width = 150
        browseListTable.addTableColumn(nameColumn)
        browseListTable.addTableColumn(kindColumn)
        browseListTable.addTableColumn(dateColumn)
        browseListTable.usesAlternatingRowBackgroundColors = false
        browseListTable.headerView = NSTableHeaderView()
        browseListTable.rowHeight = 28
        browseListTable.backgroundColor = .clear
        browseListTable.style = .plain
        browseListTable.allowsMultipleSelection = true
        browseListTable.delegate = self
        browseListTable.dataSource = self
        browseListTable.target = self
        browseListTable.action = #selector(browseListClicked)
        browseListTable.doubleAction = #selector(browseListDoubleClicked)
        browseListTable.translatesAutoresizingMaskIntoConstraints = false

        browseListScroll.documentView = browseListTable
        browseListScroll.hasVerticalScroller = true
        browseListScroll.autohidesScrollers = true
        browseListScroll.scrollerStyle = .overlay
        browseListScroll.drawsBackground = false
        browseListScroll.borderType = .noBorder
        browseListScroll.translatesAutoresizingMaskIntoConstraints = false
        browseListScroll.isHidden = true
    }

    func syncTitleBarContentInset(chromeVisible: Bool) {
        titleBarChromeVisible = chromeVisible
        applyTitleBarContentInset()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyTitleBarContentInset()
    }

    override func layout() {
        super.layout()
        applyTitleBarContentInset()
    }

    private func applyTitleBarContentInset() {
        let inset = ImmersiveWindowChrome.libraryContentTopInset(
            for: window,
            chromeVisible: titleBarChromeVisible
        )
        toolbarTopConstraint?.constant = inset
        if contentTopBelowViewConstraint?.isActive == true {
            updateContentTopInsetForRecents()
        }
    }

    private func updateContentTopInsetForRecents() {
        let inset = ImmersiveWindowChrome.libraryContentTopInset(
            for: window,
            chromeVisible: titleBarChromeVisible
        )
        contentTopBelowViewConstraint?.constant = inset + 14
    }

    private func activateLayout() {
        toolbarTopConstraint = backButton.topAnchor.constraint(equalTo: topAnchor, constant: 18)
        contentTopBelowToolbarConstraint = gridScroll.topAnchor.constraint(
            equalTo: backButton.bottomAnchor,
            constant: 12
        )
        contentTopBelowViewConstraint = gridScroll.topAnchor.constraint(equalTo: topAnchor, constant: 24)
        contentTopBelowViewConstraint?.isActive = false

        NSLayoutConstraint.activate([
            toolbarTopConstraint!,
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            forwardButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),

            openButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            openButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 12),

            playAllButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            playAllButton.leadingAnchor.constraint(equalTo: openButton.trailingAnchor, constant: 8),

            batchPlayButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            batchPlayButton.leadingAnchor.constraint(equalTo: openButton.trailingAnchor, constant: 8),
            batchQueueButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            batchQueueButton.leadingAnchor.constraint(equalTo: batchPlayButton.trailingAnchor, constant: 6),
            batchTrashButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            batchTrashButton.leadingAnchor.constraint(equalTo: batchQueueButton.trailingAnchor, constant: 6),

            sortPopUp.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            sortPopUp.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            layoutControlsStack.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            layoutControlsStack.trailingAnchor.constraint(equalTo: sortPopUp.leadingAnchor, constant: -8),

            kindFilterPopUp.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            kindFilterPopUp.trailingAnchor.constraint(equalTo: layoutControlsStack.leadingAnchor, constant: -8),
            kindFilterPopUp.widthAnchor.constraint(lessThanOrEqualToConstant: 100),

            searchField.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: kindFilterPopUp.leadingAnchor, constant: -8),
            searchField.widthAnchor.constraint(equalToConstant: 160),
            searchField.leadingAnchor.constraint(greaterThanOrEqualTo: batchTrashButton.trailingAnchor, constant: 12),
            searchField.leadingAnchor.constraint(greaterThanOrEqualTo: playAllButton.trailingAnchor, constant: 12),

            contentTopBelowToolbarConstraint!,
            gridScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridScroll.bottomAnchor.constraint(equalTo: breadcrumbStack.topAnchor, constant: -6),

            browseListScroll.topAnchor.constraint(equalTo: gridScroll.topAnchor),
            browseListScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            browseListScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            browseListScroll.bottomAnchor.constraint(equalTo: breadcrumbStack.topAnchor, constant: -6),

            recentListScroll.topAnchor.constraint(equalTo: gridScroll.topAnchor),
            recentListScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            recentListScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            recentListScroll.bottomAnchor.constraint(equalTo: breadcrumbStack.topAnchor, constant: -6),

            emptyLabel.centerXAnchor.constraint(equalTo: gridScroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: gridScroll.centerYAnchor),

            browsePlaceholder.centerXAnchor.constraint(equalTo: gridScroll.centerXAnchor),
            browsePlaceholder.centerYAnchor.constraint(equalTo: gridScroll.centerYAnchor),

            breadcrumbStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            breadcrumbStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            breadcrumbStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    private func configureNavButton(_ button: NSButton, symbol: String, toolTip: String) {
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.toolTip = toolTip
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
            button.image?.isTemplate = true
        }
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updateBreadcrumb() {
        breadcrumbStack.arrangedSubviews.forEach { view in
            breadcrumbStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let components = controller.breadcrumbComponents()
        for (index, component) in components.enumerated() {
            appendBreadcrumbSegment(title: component.title, url: component.url, isLast: index == components.count - 1)
        }
    }

    private func appendBreadcrumbSegment(title: String, url: URL?, isLast: Bool) {
        if !breadcrumbStack.arrangedSubviews.isEmpty {
            let sep = NSTextField(labelWithString: "›")
            sep.font = .systemFont(ofSize: 10)
            sep.textColor = .tertiaryLabelColor
            breadcrumbStack.addArrangedSubview(sep)
        }

        let button = NSButton(title: title, target: self, action: #selector(breadcrumbPressed(_:)))
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = .systemFont(ofSize: 10, weight: isLast ? .semibold : .regular)
        button.contentTintColor = isLast ? .labelColor : .secondaryLabelColor
        button.identifier = url.map { NSUserInterfaceItemIdentifier($0.path) }
        button.isEnabled = url != nil && !isLast
        breadcrumbStack.addArrangedSubview(button)
    }

    private func updateSortControl() {
        let sort = controller.browseSort
        let showSort = controller.showsBrowseSortControl
        sortPopUp.isHidden = !showSort
        guard showSort else { return }

        let menu = NSMenu()
        for key in LibraryBrowseSortKey.allCases {
            let item = NSMenuItem(
                title: key.menuTitle,
                action: #selector(sortKeyChosen(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = key.menuTag
            item.state = sort.key == key ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for direction in [LibraryBrowseSortDirection.ascending, .descending] {
            let item = NSMenuItem(
                title: direction.menuTitle,
                action: #selector(sortDirectionChosen(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = direction == .ascending
                ? LibraryBrowseSortDirection.ascendingMenuTag
                : LibraryBrowseSortDirection.descendingMenuTag
            item.state = sort.direction == direction ? .on : .off
            menu.addItem(item)
        }

        sortPopUp.menu = menu
        sortPopUp.select(nil)
        sortPopUp.title = sort.key.menuTitle
    }

    private func updateKindFilterControl() {
        let selected = controller.kindFilter
        let menu = NSMenu()
        for filter in LibraryKindFilter.allCases {
            let item = NSMenuItem(title: filter.title, action: #selector(kindFilterMenuChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = filter.rawValue
            item.state = filter == selected ? .on : .off
            menu.addItem(item)
        }
        kindFilterPopUp.menu = menu
        kindFilterPopUp.select(nil)
        kindFilterPopUp.title = selected.title
    }

    private func updateLayoutControl() {
        let selected = controller.viewMode
        let menu = NSMenu()
        for mode in LibraryBrowseViewMode.allCases {
            let item = NSMenuItem(title: mode.menuTitle, action: #selector(layoutMenuChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == selected ? .on : .off
            menu.addItem(item)
        }
        layoutPopUp.menu = menu
        layoutPopUp.select(nil)
        layoutPopUp.title = selected.menuTitle
    }

    private func updateGalleryScaleControl() {
        suppressGalleryScaleChange = true
        defer { suppressGalleryScaleChange = false }
        galleryScaleSlider.doubleValue = controller.galleryScale.sliderValue
    }

    private func updateBrowseListAppearance() {
        browseListTable.rowHeight = 28
        browseListTable.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("browseKind"))?.isHidden = false
        browseListTable.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("browseDate"))?.isHidden = false
        if browseListTable.headerView == nil {
            browseListTable.headerView = NSTableHeaderView()
        }
    }

    private func applyCollectionLayout(animated: Bool) {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewGridLayout else { return }
        let metrics = controller.tileMetrics
        let apply = {
            layout.minimumItemSize = metrics.minItemSize
            layout.maximumItemSize = metrics.maxItemSize
            layout.minimumInteritemSpacing = metrics.interitemSpacing
            layout.minimumLineSpacing = metrics.lineSpacing
            let inset = metrics.contentInset
            layout.margins = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
            layout.invalidateLayout()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                apply()
            }
        } else {
            apply()
        }
        appliedTileMetrics = metrics
    }

    private func syncCollectionSelection() {
        let paths = Set(controller.selectedEntryIndices.map { IndexPath(item: $0, section: 0) })
        if collectionView.selectionIndexPaths != paths {
            collectionView.selectionIndexPaths = paths
        }
    }

    private func syncBrowseListSelection() {
        suppressBrowseListSelection = true
        defer { suppressBrowseListSelection = false }
        browseListTable.selectRowIndexes(controller.selectedEntryIndices, byExtendingSelection: false)
    }

    private static let browseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func kindLabel(for entry: LibraryBrowseEntry) -> String {
        switch entry.kind {
        case .folder:
            return "Folder"
        case .media(let file):
            return file.kind == .video ? "Video" : "Image"
        }
    }

    private func openBrowseEntry(_ entry: LibraryBrowseEntry) {
        controller.clearMultiSelection()
        switch entry.kind {
        case .folder(let url):
            controller.openFolder(url)
        case .media(let file):
            controller.openMedia(file)
        }
    }

    @objc private func sortKeyChosen(_ sender: NSMenuItem) {
        guard let key = LibraryBrowseSortKey(menuTag: sender.tag) else { return }
        var sort = controller.browseSort
        guard sort.key != key else { return }
        sort.key = key
        controller.setSort(sort)
        updateSortControl()
    }

    @objc private func sortDirectionChosen(_ sender: NSMenuItem) {
        guard let direction = LibraryBrowseSortDirection(menuTag: sender.tag) else { return }
        var sort = controller.browseSort
        guard sort.direction != direction else { return }
        sort.direction = direction
        controller.setSort(sort)
        updateSortControl()
    }

    @objc private func backPressed() { controller.goBack() }
    @objc private func forwardPressed() { controller.goForward() }
    @objc private func openPressed() { onOpenMediaPanel?() }

    @objc private func playAllPressed() { onPlayAll?() }

    @objc private func layoutPopUpChanged() {
        // Selection handled via menu items.
    }

    @objc private func layoutMenuChosen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = LibraryBrowseViewMode(rawValue: raw) else { return }
        controller.setViewMode(mode)
    }

    @objc private func galleryScaleChanged() {
        guard !suppressGalleryScaleChange else { return }
        let scale = LibraryBrowseGalleryScale.from(sliderValue: galleryScaleSlider.doubleValue)
        controller.setGalleryScale(scale)
    }

    @objc private func searchFieldChanged() {
        searchDebounceWork?.cancel()
        let text = searchField.stringValue
        let work = DispatchWorkItem { [weak self] in
            self?.controller.setSearchQuery(text)
        }
        searchDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSSearchField === searchField else { return }
        searchFieldChanged()
    }

    @objc private func kindFilterChanged() {
        // Selection driven by menu items.
    }

    @objc private func kindFilterMenuChosen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let filter = LibraryKindFilter(rawValue: raw) else { return }
        controller.setKindFilter(filter)
    }

    @objc private func batchPlayPressed() {
        let entries = controller.selectedEntries
        guard !entries.isEmpty else { return }
        onBatchAction?(.play, entries)
        controller.clearMultiSelection()
    }

    @objc private func batchQueuePressed() {
        let entries = controller.selectedEntries
        guard !entries.isEmpty else { return }
        onBatchAction?(.addToQueue, entries)
        controller.clearMultiSelection()
    }

    @objc private func batchTrashPressed() {
        let entries = controller.selectedEntries
        guard !entries.isEmpty else { return }
        onBatchAction?(.remove, entries)
        controller.clearMultiSelection()
    }

    @objc private func recentListDoubleClicked() {
        openRecentListSelection()
    }

    private func openRecentListSelection() {
        let row = recentListTable.selectedRow
        guard row >= 0, let entry = controller.entry(at: IndexPath(item: row, section: 0)),
              case .media(let file) = entry.kind else { return }
        controller.openMedia(file)
    }

    @objc private func browseListClicked() {
        guard !suppressBrowseListSelection else { return }
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        let row = browseListTable.clickedRow
        guard row >= 0 else {
            controller.setMultiSelection(browseListTable.selectedRowIndexes)
            return
        }
        if flags.contains(.command) {
            controller.toggleMultiSelection(at: row)
            syncBrowseListSelection()
            return
        }
        if flags.contains(.shift) {
            controller.extendMultiSelection(to: row)
            syncBrowseListSelection()
            return
        }
        guard let entry = controller.entry(at: IndexPath(item: row, section: 0)) else { return }
        openBrowseEntry(entry)
    }

    @objc private func browseListDoubleClicked() {
        let row = browseListTable.clickedRow
        guard row >= 0, let entry = controller.entry(at: IndexPath(item: row, section: 0)) else { return }
        openBrowseEntry(entry)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === recentListTable {
            guard controller.showsRecentList else { return 0 }
            return controller.displayedEntries.count
        }
        if tableView === browseListTable {
            return controller.displayedEntries.count
        }
        return 0
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard tableView === recentListTable else { return nil }
        return tableView.makeView(withIdentifier: LibraryRecentListRowView.reuseID, owner: self) as? LibraryRecentListRowView
            ?? LibraryRecentListRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === recentListTable {
            guard let entry = controller.entry(at: IndexPath(item: row, section: 0)),
                  case .media(let file) = entry.kind else { return nil }
            let cell = tableView.makeView(
                withIdentifier: LibraryRecentListCell.reuseID,
                owner: self
            ) as? LibraryRecentListCell ?? LibraryRecentListCell()
            cell.configure(file: file)
            return cell
        }

        guard tableView === browseListTable,
              let entry = controller.entry(at: IndexPath(item: row, section: 0)),
              let column = tableColumn else { return nil }

        let cell = tableView.makeView(withIdentifier: column.identifier, owner: self) as? NSTableCellView
            ?? {
                let view = NSTableCellView()
                view.identifier = column.identifier
                if column.identifier.rawValue == "browseName" {
                    let icon = NSImageView()
                    icon.identifier = NSUserInterfaceItemIdentifier("browseNameIcon")
                    icon.imageScaling = .scaleProportionallyUpOrDown
                    icon.translatesAutoresizingMaskIntoConstraints = false
                    let label = NSTextField(labelWithString: "")
                    label.font = .systemFont(ofSize: 12)
                    label.lineBreakMode = .byTruncatingMiddle
                    label.translatesAutoresizingMaskIntoConstraints = false
                    view.addSubview(icon)
                    view.addSubview(label)
                    view.imageView = icon
                    view.textField = label
                    NSLayoutConstraint.activate([
                        icon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
                        icon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                        icon.widthAnchor.constraint(equalToConstant: 16),
                        icon.heightAnchor.constraint(equalToConstant: 16),
                        label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                        label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
                        label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
                    ])
                } else {
                    let label = NSTextField(labelWithString: "")
                    label.font = .systemFont(ofSize: 12)
                    label.lineBreakMode = .byTruncatingMiddle
                    label.translatesAutoresizingMaskIntoConstraints = false
                    view.addSubview(label)
                    view.textField = label
                    NSLayoutConstraint.activate([
                        label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
                        label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
                        label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
                    ])
                }
                return view
            }()

        switch column.identifier.rawValue {
        case "browseName":
            cell.textField?.stringValue = entry.name
            cell.textField?.font = .systemFont(ofSize: 12)
            if let icon = cell.imageView {
                let symbol: String
                switch entry.kind {
                case .folder: symbol = "folder.fill"
                case .media(let file): symbol = file.kind == .video ? "film" : "photo"
                }
                if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                    let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                    icon.image = image.withSymbolConfiguration(config)
                    icon.contentTintColor = .secondaryLabelColor
                }
            }
        case "browseKind":
            cell.textField?.stringValue = kindLabel(for: entry)
        case "browseDate":
            if let date = entry.dateModified {
                cell.textField?.stringValue = Self.browseDateFormatter.string(from: date)
            } else {
                cell.textField?.stringValue = "—"
            }
        default:
            cell.textField?.stringValue = ""
        }
        return cell
    }

    @objc private func breadcrumbPressed(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        controller.jumpToBreadcrumb(URL(fileURLWithPath: path, isDirectory: true))
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        controller.displayedEntries.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let entry = controller.displayedEntries[indexPath.item]
        let metrics = controller.tileMetrics
        switch entry.kind {
        case .folder:
            let item = collectionView.makeItem(withIdentifier: LibraryFolderGridItem.reuseID, for: indexPath) as! LibraryFolderGridItem
            item.applyMetrics(metrics)
            item.configure(name: entry.name)
            return item
        case .media(let file):
            let item = collectionView.makeItem(withIdentifier: LibraryMediaGridItem.reuseID, for: indexPath) as! LibraryMediaGridItem
            item.applyMetrics(metrics)
            item.configure(name: entry.name, kind: file.kind)
            item.loadThumbnail(for: file.url, kind: file.kind, maxSide: metrics.thumbnailMaxSide, indexPath: indexPath) { [weak self, weak item] image, path in
                guard let self, let item, self.thumbnailTasks[path] == file.url else { return }
                item.setThumbnail(image)
            }
            thumbnailTasks[indexPath] = file.url
            return item
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        willDisplay item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        guard let entry = controller.entry(at: indexPath) else {
            item.view.menu = nil
            return
        }
        item.view.menu = buildContextMenu(for: entry, itemIndex: indexPath.item)
    }

    func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        guard let event = NSApp.currentEvent else { return indexPaths }
        return Set(indexPaths.filter { path in
            guard let entry = controller.entry(at: path) else { return false }
            if case .folder = entry.kind {
                guard let item = collectionView.item(at: path) as? LibraryFolderGridItem else { return false }
                return item.containsFolderGlyphHit(for: event)
            }
            return true
        })
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if flags.contains(.command) || flags.contains(.shift) {
            let indices = IndexSet(indexPaths.map(\.item))
            if flags.contains(.shift), let last = indices.max() {
                controller.extendMultiSelection(to: last)
            } else {
                controller.setMultiSelection(indices.union(controller.selectedEntryIndices))
            }
            syncCollectionSelection()
            return
        }
        guard let indexPath = indexPaths.first,
              let entry = controller.entry(at: indexPath) else { return }
        openBrowseEntry(entry)
        collectionView.deselectAll(nil)
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        guard flags.contains(.command) else { return }
        var next = controller.selectedEntryIndices
        for path in indexPaths {
            next.remove(path.item)
        }
        controller.setMultiSelection(next)
    }

    func collectionView(_ collectionView: NSCollectionView, menuFor event: NSEvent) -> NSMenu? {
        contextMenu(for: event, in: collectionView)
    }

    private func contextMenu(for event: NSEvent, in collectionView: NSCollectionView) -> NSMenu? {
        guard let indexPath = indexPath(for: event, in: collectionView),
              let entry = controller.entry(at: indexPath) else {
            return nil
        }
        return buildContextMenu(for: entry, itemIndex: indexPath.item)
    }

    private func indexPath(for event: NSEvent, in collectionView: NSCollectionView) -> IndexPath? {
        let point = collectionView.convert(event.locationInWindow, from: nil)
        if let indexPath = collectionView.indexPathForItem(at: point) {
            return indexPath
        }
        // Fallback: hit-test item views (grid layout can miss indexPathForItem at edges).
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) else { continue }
            let pointInItem = item.view.convert(event.locationInWindow, from: nil)
            if item.view.bounds.contains(pointInItem) {
                return indexPath
            }
        }
        return nil
    }

    private func buildContextMenu(for entry: LibraryBrowseEntry, itemIndex: Int) -> NSMenu {
        let hasPlayableMedia = entryHasPlayableMedia(entry)
        let menu = NSMenu()

        func appendItem(_ title: String, action: Selector, enabled: Bool = true) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = itemIndex
            item.isEnabled = enabled
        }

        appendItem("Play", action: #selector(contextMenuPlay(_:)), enabled: hasPlayableMedia)
        appendItem("Play Next", action: #selector(contextMenuPlayNext(_:)), enabled: hasPlayableMedia)
        appendItem("Add to Queue", action: #selector(contextMenuAddToQueue(_:)), enabled: hasPlayableMedia)
        menu.addItem(.separator())
        appendItem("Rename", action: #selector(contextMenuRename(_:)))
        appendItem("Show in Finder", action: #selector(contextMenuShowInFinder(_:)))
        menu.addItem(.separator())
        appendItem("Remove", action: #selector(contextMenuRemove(_:)))
        return menu
    }

    private func entryHasPlayableMedia(_ entry: LibraryBrowseEntry) -> Bool {
        switch entry.kind {
        case .media:
            return true
        case .folder(let url):
            return !controller.mediaFiles(in: url).isEmpty
        }
    }

    private func entry(for menuItem: NSMenuItem) -> LibraryBrowseEntry? {
        controller.entry(at: IndexPath(item: menuItem.tag, section: 0))
    }

    private func performContextAction(_ action: LibraryBrowseContextAction, sender: NSMenuItem) {
        guard let entry = entry(for: sender) else { return }
        onContextAction?(action, entry)
    }

    @objc private func contextMenuPlay(_ sender: NSMenuItem) { performContextAction(.play, sender: sender) }
    @objc private func contextMenuPlayNext(_ sender: NSMenuItem) { performContextAction(.playNext, sender: sender) }
    @objc private func contextMenuAddToQueue(_ sender: NSMenuItem) { performContextAction(.addToQueue, sender: sender) }
    @objc private func contextMenuRename(_ sender: NSMenuItem) { performContextAction(.rename, sender: sender) }
    @objc private func contextMenuShowInFinder(_ sender: NSMenuItem) { performContextAction(.showInFinder, sender: sender) }
    @objc private func contextMenuRemove(_ sender: NSMenuItem) { performContextAction(.remove, sender: sender) }
}

// MARK: - Collection view (explicit right-click)

private final class LibraryGridCollectionView: NSCollectionView {
    var contextMenuProvider: ((NSEvent, NSCollectionView) -> NSMenu?)?

    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenuProvider?(event, self) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?(event, self) ?? super.menu(for: event)
    }
}

// MARK: - Grid items

private class LibraryGridItemView: NSView {
    override func rightMouseDown(with event: NSEvent) {
        if let menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menu ?? super.menu(for: event)
    }
}

/// Media tile host that reports hover for Gallery border affordance.
private final class LibraryMediaTileHostView: LibraryGridItemView {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingAreaRef: NSTrackingArea?

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
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}

private func configureLibraryGridNameLabel(_ label: NSTextField, fontSize: CGFloat) {
    label.font = .systemFont(ofSize: fontSize)
    label.alignment = .center
    label.lineBreakMode = .byWordWrapping
    label.maximumNumberOfLines = 2
    label.cell?.wraps = true
    label.cell?.usesSingleLineMode = false
    label.cell?.truncatesLastVisibleLine = false
    label.translatesAutoresizingMaskIntoConstraints = false
}

private final class LibraryFolderGridItem: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("LibraryFolderGridItem")

    private let plateView = LibraryFolderPlateView()
    private let titleBar = LibraryFolderTitleBarView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var iconCenterYConstraint: NSLayoutConstraint?
    private var iconTopConstraint: NSLayoutConstraint?
    private var titleBarHeightConstraint: NSLayoutConstraint?
    private var nameLeadingConstraint: NSLayoutConstraint?
    private var nameTrailingConstraint: NSLayoutConstraint?
    private var isGalleryStyle = false

    override func loadView() {
        view = LibraryGridItemView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true

        plateView.wantsLayer = true
        plateView.layer?.cornerRadius = 8
        plateView.translatesAutoresizingMaskIntoConstraints = false
        plateView.refreshFill = { [weak self] in
            self?.applyFolderPlateFill()
        }

        titleBar.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        applyFolderIcon(pointSize: 46)

        configureLibraryGridNameLabel(nameLabel, fontSize: 11)

        view.addSubview(plateView)
        view.addSubview(iconView)
        view.addSubview(titleBar)
        view.addSubview(nameLabel)

        let width = iconView.widthAnchor.constraint(equalToConstant: 68)
        let height = iconView.heightAnchor.constraint(equalToConstant: 68)
        let iconTop = iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 6)
        let iconCenterY = iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -10)
        let titleHeight = titleBar.heightAnchor.constraint(equalToConstant: 38)
        let nameLeading = nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8)
        let nameTrailing = nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8)
        iconWidthConstraint = width
        iconHeightConstraint = height
        iconTopConstraint = iconTop
        iconCenterYConstraint = iconCenterY
        titleBarHeightConstraint = titleHeight
        nameLeadingConstraint = nameLeading
        nameTrailingConstraint = nameTrailing
        iconCenterY.isActive = false

        NSLayoutConstraint.activate([
            plateView.topAnchor.constraint(equalTo: view.topAnchor),
            plateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            plateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            plateView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            iconTop,
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            width,
            height,

            titleBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            titleHeight,

            nameLabel.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
            nameLeading,
            nameTrailing
        ])
    }

    func applyMetrics(_ metrics: LibraryBrowseTileMetrics) {
        isGalleryStyle = !metrics.showsTitle
        nameLabel.isHidden = false
        let side = metrics.folderIconPointSize + 18
        iconWidthConstraint?.constant = side
        iconHeightConstraint?.constant = side
        applyFolderIcon(pointSize: metrics.folderIconPointSize)

        plateView.isHidden = false
        titleBar.isHidden = false
        titleBarHeightConstraint?.constant = isGalleryStyle ? 40 : 36
        iconTopConstraint?.isActive = false
        iconCenterYConstraint?.isActive = true
        iconCenterYConstraint?.constant = isGalleryStyle ? -12 : -10
        nameLeadingConstraint?.constant = 10
        nameTrailingConstraint?.constant = -10
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: isGalleryStyle ? 12 : 11, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.maximumNumberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.cell?.wraps = true
        nameLabel.shadow = nil
        view.layer?.cornerRadius = 10
        plateView.layer?.cornerRadius = 10
        applyFolderPlateFill()
    }

    private func applyFolderPlateFill() {
        let fill = LaughTheme.librarySidebarBackground(appearance: view.effectiveAppearance)
        plateView.layer?.backgroundColor = fill.cgColor
        view.layer?.backgroundColor = fill.cgColor
        view.layer?.borderWidth = 1
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(isDark ? 0.18 : 0.22).cgColor
        let lift = isDark
            ? NSColor.white.withAlphaComponent(0.10)
            : NSColor.white.withAlphaComponent(0.62)
        titleBar.layer?.backgroundColor = LaughTheme.blend(fill, over: lift).cgColor
    }

    private func applyFolderIcon(pointSize: CGFloat) {
        if let folder = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder") {
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            iconView.image = folder.withSymbolConfiguration(config)
            iconView.contentTintColor = .tertiaryLabelColor
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.stringValue = ""
        view.toolTip = nil
    }

    func configure(name: String) {
        nameLabel.stringValue = name
        view.toolTip = nil
    }

    /// True when the click lands on the folder glyph (not empty cell padding).
    func containsFolderGlyphHit(for event: NSEvent) -> Bool {
        let point = iconView.convert(event.locationInWindow, from: nil)
        // Slightly generous so the glyph corners remain easy to hit.
        return iconView.bounds.insetBy(dx: -4, dy: -4).contains(point)
    }
}

/// Soft Gallery plate that refreshes fill when appearance changes.
private final class LibraryFolderPlateView: NSView {
    var refreshFill: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshFill?()
    }
}

/// Light caption band under the folder name.
private final class LibraryFolderTitleBarView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class LibraryMediaGridItem: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("LibraryMediaGridItem")

    private let thumbnailView = NSImageView()
    private let playButton = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var thumbHeightConstraint: NSLayoutConstraint?
    private var thumbBottomConstraint: NSLayoutConstraint?
    private var nameTopConstraint: NSLayoutConstraint?
    private var showsTitle = true
    private var hoverBorderEnabled = false
    private var loadToken = UUID()

    override func loadView() {
        let host = LibraryMediaTileHostView()
        host.onHoverChange = { [weak self] hovered in
            self?.setHovered(hovered)
        }
        view = host
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 0

        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false

        if let play = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Play") {
            let config = NSImage.SymbolConfiguration(pointSize: 30, weight: .regular)
            playButton.image = play.withSymbolConfiguration(config)
            playButton.contentTintColor = .white
        }
        playButton.translatesAutoresizingMaskIntoConstraints = false

        configureLibraryGridNameLabel(nameLabel, fontSize: 10)

        view.addSubview(thumbnailView)
        view.addSubview(playButton)
        view.addSubview(nameLabel)

        let thumbHeight = thumbnailView.heightAnchor.constraint(equalToConstant: 84)
        let thumbBottom = thumbnailView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let nameTop = nameLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 4)
        thumbHeightConstraint = thumbHeight
        thumbBottomConstraint = thumbBottom
        nameTopConstraint = nameTop
        thumbBottom.isActive = false

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumbHeight,
            playButton.centerXAnchor.constraint(equalTo: thumbnailView.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),
            nameTop,
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -4)
        ])
    }

    func applyMetrics(_ metrics: LibraryBrowseTileMetrics) {
        showsTitle = metrics.showsTitle
        hoverBorderEnabled = !metrics.showsTitle
        nameLabel.isHidden = !metrics.showsTitle
        setHovered(false)
        if metrics.showsTitle {
            thumbHeightConstraint?.isActive = true
            thumbHeightConstraint?.constant = metrics.thumbHeight
            thumbBottomConstraint?.isActive = false
            nameTopConstraint?.isActive = true
            view.layer?.cornerRadius = 8
            thumbnailView.imageScaling = .scaleProportionallyUpOrDown
            thumbnailView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        } else {
            thumbHeightConstraint?.isActive = false
            thumbBottomConstraint?.isActive = true
            nameTopConstraint?.isActive = false
            view.layer?.cornerRadius = 4
            thumbnailView.imageScaling = .scaleProportionallyUpOrDown
            thumbnailView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        }
        let playSize = max(26, min(metrics.thumbHeight * 0.18, 42))
        if let play = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Play") {
            let config = NSImage.SymbolConfiguration(pointSize: playSize, weight: .regular)
            playButton.image = play.withSymbolConfiguration(config)
            playButton.contentTintColor = .white
        }
    }

    private func setHovered(_ hovered: Bool) {
        guard hoverBorderEnabled else {
            view.layer?.borderWidth = 0
            view.layer?.borderColor = nil
            return
        }
        view.layer?.borderWidth = hovered ? 1.5 : 0
        view.layer?.borderColor = hovered
            ? NSColor.white.withAlphaComponent(0.95).cgColor
            : nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadToken = UUID()
        thumbnailView.image = nil
        nameLabel.stringValue = ""
        view.toolTip = nil
        setHovered(false)
        playButton.isHidden = true
    }

    func configure(name: String, kind: DroppedMediaKind) {
        nameLabel.stringValue = name
        view.toolTip = nil
        playButton.isHidden = kind != .video
        if thumbnailView.image == nil {
            let symbol = kind == .video ? "film" : "photo"
            if let placeholder = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
                thumbnailView.image = placeholder.withSymbolConfiguration(config)
                thumbnailView.contentTintColor = .tertiaryLabelColor
            }
        }
    }

    func setThumbnail(_ image: NSImage?) {
        guard let image else { return }
        thumbnailView.contentTintColor = nil
        thumbnailView.image = image
    }

    func loadThumbnail(
        for url: URL,
        kind: DroppedMediaKind,
        maxSide: CGFloat,
        indexPath: IndexPath,
        completion: @escaping (NSImage?, IndexPath) -> Void
    ) {
        let token = loadToken
        DispatchQueue.global(qos: .utility).async {
            let image = MediaThumbnailGenerator.thumbnail(for: url, kind: kind, maxSide: maxSide)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadToken == token else { return }
                completion(image, indexPath)
            }
        }
    }
}

// MARK: - Recents list (main content)

private final class LibraryRecentListRowView: NSTableRowView {
    static let reuseID = NSUserInterfaceItemIdentifier("LibraryRecentListRowView")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let rect = LaughTheme.Sidebar.MenuButton.ContentList.selectionRect(in: bounds)
        LaughTheme.fillSidebarSelection(in: rect, cornerRadius: LaughTheme.Sidebar.MenuButton.cornerRadius)
    }
}

private final class LibraryRecentListCell: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("LibraryRecentListCell")

    private let contentRow = NSStackView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID

        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.font = LaughTheme.Sidebar.MenuButton.labelFont
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        contentRow.orientation = .horizontal
        contentRow.alignment = .centerY
        contentRow.spacing = LaughTheme.Sidebar.MenuButton.gap
        contentRow.translatesAutoresizingMaskIntoConstraints = false
        contentRow.addArrangedSubview(iconView)
        contentRow.addArrangedSubview(nameLabel)

        addSubview(contentRow)
        textField = nameLabel

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: LaughTheme.Sidebar.MenuButton.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: LaughTheme.Sidebar.MenuButton.iconSize),

            contentRow.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentRow.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: LaughTheme.Sidebar.MenuButton.ContentList.contentLeadingInset
            ),
            contentRow.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -LaughTheme.Sidebar.MenuButton.ContentList.contentTrailingInset
            )
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let selected = backgroundStyle == .emphasized
            LaughTheme.applySidebarSelectionLabelStyle(to: nameLabel, selected: selected, idleColor: .labelColor)
            iconView.contentTintColor = selected ? .labelColor : .secondaryLabelColor
        }
    }

    func configure(file: LibraryMediaFile) {
        nameLabel.stringValue = file.url.lastPathComponent
        toolTip = nil
        let symbol = file.kind == .video ? "film" : "photo"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iconView.image = image.withSymbolConfiguration(LaughTheme.Sidebar.MenuButton.symbolConfiguration())
            iconView.image?.isTemplate = true
        }
    }
}
