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
        applyToolbarButtonChrome()
    }

    private func configureSubviews() {
        configureToolbarButton(addFolderButton, symbol: "plus", toolTip: "Add folder…")
        configureToolbarButton(removeFolderButton, symbol: "minus", toolTip: "Remove selected folder")
        addFolderButton.target = self
        addFolderButton.action = #selector(addFolderPressed)
        removeFolderButton.target = self
        removeFolderButton.action = #selector(removeFolderPressed)
        applyToolbarButtonChrome()

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

    private func configureToolbarButton(_ button: NSButton, symbol: String, toolTip: String) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.toolTip = toolTip
        if #available(macOS 11.0, *),
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip) {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let templated = image.withSymbolConfiguration(config) ?? image
            templated.isTemplate = true
            button.image = templated
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func applyToolbarButtonChrome() {
        // Same quiet grey as other sidebar chrome — never green/red accent.
        let tint = NSColor.secondaryLabelColor
        addFolderButton.contentTintColor = tint
        removeFolderButton.contentTintColor = tint
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
        applyToolbarButtonChrome()
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
                symbol: "folder",
                directoryURL: root.directoryURL
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
        iconColor: NSColor? = nil,
        directoryURL: URL? = nil
    ) {
        nameLabel.stringValue = title
        self.style = style
        self.toolTip = toolTip.isEmpty ? nil : toolTip
        iconTint = iconColor
        applyRowMetrics()
        applySectionIcon(symbol: symbol, directoryURL: directoryURL)
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

    private func applySectionIcon(symbol: String?, directoryURL: URL? = nil) {
        let pointSize: CGFloat
        switch style {
        case .groupLabel:
            pointSize = LaughTheme.Sidebar.GroupLabel.iconSize
        case .menuSubButton:
            pointSize = LaughTheme.Sidebar.MenuSubButton.iconSize
        case .menuButton:
            pointSize = LaughTheme.Sidebar.MenuButton.iconSize
        }

        if let directoryURL {
            // Clear any prior SF Symbol config from cell reuse.
            iconView.symbolConfiguration = nil
            let resolved = LibraryFolderIcon.resolve(
                for: directoryURL,
                pointSize: pointSize,
                symbolFallback: symbol ?? "folder",
                forceFinderAppearance: true
            )
            let image = resolved.image
            image.isTemplate = resolved.isTemplate
            iconView.image = image
            if resolved.isTemplate {
                iconTint = resolved.tintColor
                iconView.contentTintColor = resolved.tintColor
            } else {
                iconTint = nil
                iconView.contentTintColor = nil
            }
            iconView.isHidden = false
            return
        }

        guard let symbol,
              let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        else {
            iconView.symbolConfiguration = nil
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

        iconView.symbolConfiguration = config
        iconView.image = image
        if let iconTint {
            iconView.image?.isTemplate = false
            iconView.contentTintColor = iconTint
        } else {
            iconView.image?.isTemplate = true
            iconView.contentTintColor = nil
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
        if !iconView.isHidden, iconTint == nil, iconView.image?.isTemplate == true {
            iconView.contentTintColor = selected ? .labelColor : .secondaryLabelColor
        } else if !iconView.isHidden, let iconTint, iconView.image?.isTemplate == true {
            iconView.contentTintColor = iconTint
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
    private let openButton = LibraryPillButton(
        title: "Open…",
        symbol: "folder",
        style: .labeled,
        toolTip: "Open files"
    )
    private let playAllButton = LibraryPillButton(
        title: "Play All",
        symbol: "play.fill",
        style: .labeled,
        toolTip: "Play every video and image in this folder, in sort order"
    )
    private let batchPlayButton = LibraryPillButton(
        title: "Play",
        symbol: "play.fill",
        style: .labeled,
        toolTip: "Play selected items"
    )
    private let batchQueueButton = LibraryPillButton(
        title: "Queue",
        symbol: "text.badge.plus",
        style: .labeled,
        toolTip: "Add selected items to queue"
    )
    private let batchDeleteButton = LibraryPillButton(
        title: "Delete",
        symbol: "trash",
        style: .labeled,
        toolTip: "Move selected items to Trash"
    )
    private let batchEditPopUp = LibraryPillPopUp(symbol: "ellipsis", toolTip: "Edit selection")
    private let layoutModeControl = LibraryLayoutModeSwitcher()
    private let galleryScaleSlider = NSSlider()
    private let layoutControlsStack = NSStackView()
    private let searchField = NSSearchField()
    private let kindFilterPopUp = LibraryLabeledPillMenu()
    private let sortPopUp = LibraryPillPopUp(symbol: "arrow.up.arrow.down", toolTip: "Sort")
    private let gridScroll = NSScrollView()
    private let collectionView = LibraryGridCollectionView()
    private let browseListScroll = NSScrollView()
    private let browseListTable = NSTableView()
    private let recentListScroll = NSScrollView()
    private let recentListTable = NSTableView()
    private let breadcrumbStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "Empty folder")
    private let browsePlaceholder = LibraryBrowsePlaceholderView()
    private let topOverflowFade = ScrollOverflowFadeView()
    private let bottomOverflowFade = ScrollOverflowFadeView()
    private var toolbarTopConstraint: NSLayoutConstraint?
    private var contentTopBelowToolbarConstraint: NSLayoutConstraint?
    private var contentTopBelowViewConstraint: NSLayoutConstraint?
    private var breadcrumbTrailingToSliderConstraint: NSLayoutConstraint?
    private var breadcrumbTrailingToEdgeConstraint: NSLayoutConstraint?
    private var titleBarChromeVisible = false
    private var thumbnailTasks: [IndexPath: URL] = [:]
    private let gridCollectionLayout = NSCollectionViewGridLayout()
    private var searchDebounceWork: DispatchWorkItem?
    private var suppressBrowseListSelection = false
    private var appliedTileMetrics: LibraryBrowseTileMetrics?
    private var suppressGalleryScaleChange = false
    private var previewSelectionIndices: IndexSet?
    var onOpenMediaPanel: (() -> Void)?
    var onPlayAll: (() -> Void)?
    var onContextAction: ((LibraryBrowseContextAction, LibraryBrowseEntry) -> Void)?
    var onBatchAction: ((LibraryBrowseBatchAction, [LibraryBrowseEntry]) -> Void)?
    private var suppressCollectionSelectionCallback = false

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

        applyBrowseListContentInsets()
        updateOverflowFades()

        let hideNavToolbar = showRecentList
        backButton.isHidden = hideNavToolbar || showFavoritesChrome
        forwardButton.isHidden = hideNavToolbar || showFavoritesChrome
        openButton.isHidden = hideNavToolbar
        playAllButton.isHidden = hideNavToolbar || showPlaceholder
        sortPopUp.isHidden = hideNavToolbar || !controller.showsBrowseSortControl
        layoutModeControl.isHidden = hideNavToolbar || !controller.showsBrowseViewModeControl
        layoutControlsStack.isHidden = layoutModeControl.isHidden
        let showGalleryScale = !layoutModeControl.isHidden && mode == .gallery
        galleryScaleSlider.isHidden = !showGalleryScale
        breadcrumbTrailingToSliderConstraint?.isActive = showGalleryScale
        breadcrumbTrailingToEdgeConstraint?.isActive = !showGalleryScale
        searchField.isHidden = hideNavToolbar || !controller.showsBrowseSearch
        kindFilterPopUp.isHidden = hideNavToolbar || !controller.showsKindFilter

        let batchVisible = controller.hasBatchSelection && !showPlaceholder && !showRecentList
        updateBatchToolbar(visible: batchVisible)
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
        applyVisibleSelectionChrome()
        playAllButton.isEnabled = controller.canPlayAllInBrowse
        if showPlaceholder {
            playAllButton.isHidden = true
        }
    }

    /// Lightweight selection update — keeps checkmarks / batch chrome instant (no grid reload).
    func refreshSelection() {
        let showPlaceholder = controller.showsBrowsePlaceholder
        let showRecentList = controller.showsRecentList
        let batchVisible = controller.hasBatchSelection && !showPlaceholder && !showRecentList
        updateBatchToolbar(visible: batchVisible)
        if batchVisible {
            playAllButton.isHidden = true
        } else if !showRecentList && !showPlaceholder {
            playAllButton.isHidden = false
            playAllButton.isEnabled = controller.canPlayAllInBrowse
        }
        syncCollectionSelection()
        syncBrowseListSelection()
        applyVisibleSelectionChrome()
    }

    private func updateBatchToolbar(visible: Bool) {
        batchPlayButton.isHidden = !visible
        batchQueueButton.isHidden = !visible
        batchDeleteButton.isHidden = !visible
        batchEditPopUp.isHidden = !visible
        if visible {
            refreshBatchEditMenu()
        }
    }

    private func reflowVisibleCollectionItems(metrics: LibraryBrowseTileMetrics) {
        for path in collectionView.indexPathsForVisibleItems() {
            guard let entry = controller.entry(at: path) else { continue }
            switch entry.kind {
            case .folder(let folderURL):
                guard let item = collectionView.item(at: path) as? LibraryFolderGridItem else { continue }
                item.applyMetrics(metrics)
                let counts = MediaLibraryScanner.mediaCounts(in: folderURL)
                item.configure(
                    name: entry.name,
                    itemCount: counts.total,
                    dateModified: entry.dateModified,
                    folderURL: folderURL
                )
                if !metrics.showsTitle {
                    item.loadPreviews(folderURL: folderURL, maxSide: metrics.thumbnailMaxSide, indexPath: path) { [weak self, weak item] images, indexPath in
                        guard let self, let item, self.thumbnailTasks[indexPath] == folderURL else { return }
                        item.setPreviews(images)
                    }
                    thumbnailTasks[path] = folderURL
                } else {
                    thumbnailTasks.removeValue(forKey: path)
                }
            case .media(let file):
                guard let item = collectionView.item(at: path) as? LibraryMediaGridItem else { continue }
                item.applyMetrics(metrics)
                item.configure(name: entry.name, kind: file.kind, fileSize: entry.size, url: file.url)
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

        openButton.target = self
        openButton.action = #selector(openPressed)

        playAllButton.target = self
        playAllButton.action = #selector(playAllPressed)

        batchPlayButton.target = self
        batchPlayButton.action = #selector(batchPlayPressed)
        batchPlayButton.isHidden = true
        batchQueueButton.target = self
        batchQueueButton.action = #selector(batchQueuePressed)
        batchQueueButton.isHidden = true
        batchDeleteButton.target = self
        batchDeleteButton.action = #selector(batchDeletePressed)
        batchDeleteButton.isHidden = true

        batchEditPopUp.isHidden = true
        refreshBatchEditMenu()

        configureLayoutModeControl()
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
        layoutControlsStack.spacing = 10
        layoutControlsStack.translatesAutoresizingMaskIntoConstraints = false
        layoutControlsStack.addArrangedSubview(layoutModeControl)

        searchField.placeholderString = "Search this folder"
        searchField.font = .systemFont(ofSize: 11)
        searchField.controlSize = .regular
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        styleSearchFieldAsPill()

        kindFilterPopUp.translatesAutoresizingMaskIntoConstraints = false
        updateKindFilterControl()

        updateSortControl()

        let layout = gridCollectionLayout
        layout.margins = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        collectionView.collectionViewLayout = layout
        applyCollectionLayout(animated: false)

        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.multiSelectHost = self
        collectionView.contextMenuProvider = { [weak self] event, collectionView in
            self?.contextMenu(for: event, in: collectionView)
        }
        collectionView.onKeyCommand = { [weak self] command in
            self?.handleGridKeyCommand(command) ?? false
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
        addSubview(batchDeleteButton)
        addSubview(batchEditPopUp)
        addSubview(searchField)
        addSubview(kindFilterPopUp)
        addSubview(layoutControlsStack)
        addSubview(sortPopUp)
        addSubview(gridScroll)
        addSubview(browseListScroll)
        addSubview(recentListScroll)

        topOverflowFade.edge = .top
        topOverflowFade.translatesAutoresizingMaskIntoConstraints = false
        bottomOverflowFade.edge = .bottom
        bottomOverflowFade.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topOverflowFade)
        addSubview(bottomOverflowFade)
        refreshOverflowFadeFloor()

        addSubview(breadcrumbStack)
        addSubview(galleryScaleSlider)
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
        browseListScroll.automaticallyAdjustsContentInsets = false
        browseListScroll.translatesAutoresizingMaskIntoConstraints = false
        browseListScroll.isHidden = true
        applyBrowseListContentInsets()
    }

    func syncTitleBarContentInset(chromeVisible: Bool) {
        titleBarChromeVisible = chromeVisible
        applyTitleBarContentInset()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyTitleBarContentInset()
        updateOverflowFades()
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
            constant: 18
        )
        contentTopBelowViewConstraint = gridScroll.topAnchor.constraint(equalTo: topAnchor, constant: 24)
        contentTopBelowViewConstraint?.isActive = false

        NSLayoutConstraint.activate([
            toolbarTopConstraint!,
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            forwardButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),

            openButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            openButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 20),

            playAllButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            playAllButton.leadingAnchor.constraint(equalTo: openButton.trailingAnchor, constant: 8),

            batchPlayButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            batchPlayButton.leadingAnchor.constraint(equalTo: openButton.trailingAnchor, constant: 8),
            batchQueueButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            batchQueueButton.leadingAnchor.constraint(equalTo: batchPlayButton.trailingAnchor, constant: 6),
            batchDeleteButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            batchDeleteButton.leadingAnchor.constraint(equalTo: batchQueueButton.trailingAnchor, constant: 6),
            batchEditPopUp.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            batchEditPopUp.leadingAnchor.constraint(equalTo: batchDeleteButton.trailingAnchor, constant: 6),

            sortPopUp.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            sortPopUp.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            kindFilterPopUp.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            kindFilterPopUp.trailingAnchor.constraint(equalTo: sortPopUp.leadingAnchor, constant: -8),

            searchField.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: kindFilterPopUp.leadingAnchor, constant: -8),
            searchField.widthAnchor.constraint(equalToConstant: 160),
            searchField.leadingAnchor.constraint(greaterThanOrEqualTo: layoutControlsStack.trailingAnchor, constant: 16),
            searchField.leadingAnchor.constraint(greaterThanOrEqualTo: batchEditPopUp.trailingAnchor, constant: 12),
            searchField.leadingAnchor.constraint(greaterThanOrEqualTo: playAllButton.trailingAnchor, constant: 12),

            layoutControlsStack.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            layoutControlsStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            layoutControlsStack.leadingAnchor.constraint(greaterThanOrEqualTo: batchEditPopUp.trailingAnchor, constant: 12),
            layoutControlsStack.leadingAnchor.constraint(greaterThanOrEqualTo: playAllButton.trailingAnchor, constant: 12),

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

            topOverflowFade.leadingAnchor.constraint(equalTo: gridScroll.leadingAnchor),
            topOverflowFade.trailingAnchor.constraint(equalTo: gridScroll.trailingAnchor),
            topOverflowFade.topAnchor.constraint(equalTo: gridScroll.topAnchor),
            topOverflowFade.heightAnchor.constraint(equalToConstant: 40),

            bottomOverflowFade.leadingAnchor.constraint(equalTo: gridScroll.leadingAnchor),
            bottomOverflowFade.trailingAnchor.constraint(equalTo: gridScroll.trailingAnchor),
            bottomOverflowFade.bottomAnchor.constraint(equalTo: gridScroll.bottomAnchor),
            bottomOverflowFade.heightAnchor.constraint(equalToConstant: 40),

            emptyLabel.centerXAnchor.constraint(equalTo: gridScroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: gridScroll.centerYAnchor),

            browsePlaceholder.centerXAnchor.constraint(equalTo: gridScroll.centerXAnchor),
            browsePlaceholder.centerYAnchor.constraint(equalTo: gridScroll.centerYAnchor),

            breadcrumbStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            breadcrumbStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            galleryScaleSlider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            galleryScaleSlider.centerYAnchor.constraint(equalTo: breadcrumbStack.centerYAnchor)
        ])

        breadcrumbTrailingToSliderConstraint = breadcrumbStack.trailingAnchor.constraint(
            lessThanOrEqualTo: galleryScaleSlider.leadingAnchor,
            constant: -12
        )
        breadcrumbTrailingToEdgeConstraint = breadcrumbStack.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingAnchor,
            constant: -16
        )
        breadcrumbTrailingToEdgeConstraint?.isActive = true
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

    private func applyToolbarSymbol(_ button: NSButton, symbol: String, pointSize: CGFloat) {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: button.title) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        button.image = image.withSymbolConfiguration(config)
        button.imagePosition = .imageLeading
        button.contentTintColor = .labelColor
    }

    private func styleSearchFieldAsPill() {
        searchField.wantsLayer = true
        searchField.layer?.masksToBounds = true
        searchField.focusRingType = .none
        searchField.heightAnchor.constraint(equalToConstant: 30).isActive = true
        searchField.layer?.cornerRadius = 15
        searchField.layer?.backgroundColor = LaughTheme.libraryToolbarPillFill(appearance: searchField.effectiveAppearance).cgColor
    }

    private func refreshBrowseToolbarPillChrome() {
        openButton.refreshChrome()
        playAllButton.refreshChrome()
        batchPlayButton.refreshChrome()
        batchQueueButton.refreshChrome()
        batchDeleteButton.refreshChrome()
        batchEditPopUp.refreshChrome()
        sortPopUp.refreshChrome()
        kindFilterPopUp.refreshChrome()
        styleSearchFieldAsPill()
    }

    private func refreshBatchEditMenu() {
        var items: [NSMenuItem] = []
        let selectAll = NSMenuItem(title: "Select All", action: #selector(batchContextSelectAll), keyEquivalent: "")
        selectAll.target = self
        items.append(selectAll)
        let deselect = NSMenuItem(title: "Deselect All", action: #selector(batchContextDeselectAll), keyEquivalent: "")
        deselect.target = self
        items.append(deselect)
        batchEditPopUp.setPullDownItems(items, iconSymbol: "ellipsis")
    }

    private func configureLayoutModeControl() {
        layoutModeControl.translatesAutoresizingMaskIntoConstraints = false
        layoutModeControl.onChange = { [weak self] mode in
            self?.controller.setViewMode(mode)
        }
    }

    private func updateLayoutControl() {
        layoutModeControl.setSelectedMode(controller.viewMode, animated: false)
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
        guard controller.showsBrowseSortControl else { return }
        let sort = controller.browseSort

        var items: [NSMenuItem] = []
        for key in LibraryBrowseSortKey.allCases {
            let item = NSMenuItem(
                title: key.menuTitle,
                action: #selector(sortKeyChosen(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = key.menuTag
            item.state = sort.key == key ? .on : .off
            items.append(item)
        }
        items.append(.separator())
        for direction in [LibraryBrowseSortDirection.ascending, .descending] {
            let item = NSMenuItem(
                title: direction.menuTitle(for: sort.key),
                action: #selector(sortDirectionChosen(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = direction == .ascending
                ? LibraryBrowseSortDirection.ascendingMenuTag
                : LibraryBrowseSortDirection.descendingMenuTag
            item.state = sort.direction == direction ? .on : .off
            items.append(item)
        }
        sortPopUp.setPullDownItems(items, iconSymbol: "arrow.up.arrow.down")
    }

    private func updateKindFilterControl() {
        let selected = controller.kindFilter
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        var items: [NSMenuItem] = []
        for filter in LibraryKindFilter.allCases {
            let item = NSMenuItem(title: filter.title, action: #selector(kindFilterMenuChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = filter.rawValue
            item.state = filter == selected ? .on : .off
            if let image = NSImage(systemSymbolName: filter.symbolName, accessibilityDescription: filter.title) {
                let configured = image.withSymbolConfiguration(symbolConfig)
                configured?.isTemplate = true
                item.image = configured
            }
            items.append(item)
        }
        kindFilterPopUp.setContent(
            title: selected.title,
            symbolName: selected.symbolName,
            menuItems: items
        )
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
        let metrics = controller.tileMetrics
        let apply = {
            if self.collectionView.collectionViewLayout !== self.gridCollectionLayout {
                self.collectionView.collectionViewLayout = self.gridCollectionLayout
            }
            let layout = self.gridCollectionLayout
            layout.minimumItemSize = metrics.minItemSize
            layout.maximumItemSize = metrics.maxItemSize
            layout.minimumInteritemSpacing = metrics.interitemSpacing
            layout.minimumLineSpacing = metrics.lineSpacing
            let side = metrics.contentInset
            layout.margins = NSEdgeInsets(
                top: metrics.contentTopInset,
                left: side,
                bottom: max(side, 18),
                right: side
            )
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
        applyBrowseListContentInsets()
        updateOverflowFades()
    }

    private func applyBrowseListContentInsets() {
        let metrics = controller.tileMetrics
        let insets = NSEdgeInsets(
            top: metrics.contentTopInset,
            left: 8,
            bottom: max(metrics.contentInset, 18),
            right: 8
        )
        browseListScroll.contentInsets = insets
        browseListScroll.scrollerInsets = NSEdgeInsets(
            top: metrics.contentTopInset,
            left: 0,
            bottom: max(metrics.contentInset, 18),
            right: 0
        )
    }

    private func refreshOverflowFadeFloor() {
        let floor = LaughTheme.libraryContentBackground(appearance: effectiveAppearance)
        topOverflowFade.floorColor = floor
        bottomOverflowFade.floorColor = floor
    }

    private func updateOverflowFades() {
        refreshOverflowFadeFloor()
        let activeScroll: NSScrollView?
        if !gridScroll.isHidden {
            activeScroll = gridScroll
        } else if !browseListScroll.isHidden {
            activeScroll = browseListScroll
        } else if !recentListScroll.isHidden {
            activeScroll = recentListScroll
        } else {
            activeScroll = nil
        }

        guard let activeScroll else {
            topOverflowFade.detach()
            bottomOverflowFade.detach()
            topOverflowFade.alphaValue = 0
            bottomOverflowFade.alphaValue = 0
            topOverflowFade.isHidden = true
            bottomOverflowFade.isHidden = true
            return
        }

        topOverflowFade.attach(to: activeScroll)
        bottomOverflowFade.attach(to: activeScroll)
        addSubview(topOverflowFade, positioned: .above, relativeTo: nil)
        addSubview(bottomOverflowFade, positioned: .above, relativeTo: nil)
        topOverflowFade.refreshOverflow(animated: false)
        bottomOverflowFade.refreshOverflow(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshOverflowFadeFloor()
        refreshBrowseToolbarPillChrome()
        topOverflowFade.refreshOverflow(animated: false)
        bottomOverflowFade.refreshOverflow(animated: false)
    }

    override func layout() {
        super.layout()
        applyTitleBarContentInset()
        topOverflowFade.refreshOverflow(animated: false)
        bottomOverflowFade.refreshOverflow(animated: false)
    }

    private func syncCollectionSelection() {
        let paths = Set(controller.selectedEntryIndices.map { IndexPath(item: $0, section: 0) })
        suppressCollectionSelectionCallback = true
        defer { suppressCollectionSelectionCallback = false }
        if collectionView.selectionIndexPaths != paths {
            collectionView.selectionIndexPaths = paths
        }
    }

    private func applyVisibleSelectionChrome() {
        let live = previewSelectionIndices ?? controller.selectedEntryIndices
        let previewing = previewSelectionIndices != nil
        for path in collectionView.indexPathsForVisibleItems() {
            let resolved: LibraryTileSelectionChrome
            if !live.contains(path.item) {
                resolved = .none
            } else if previewing {
                resolved = .preview
            } else {
                resolved = .selected
            }
            configureSelectableItem(at: path, chrome: resolved)
        }
    }

    private func configureSelectableItem(at path: IndexPath, chrome: LibraryTileSelectionChrome) {
        let index = path.item
        if let folder = collectionView.item(at: path) as? LibraryFolderGridItem {
            folder.onDeselectRequested = { [weak self] in
                self?.deselectTile(at: index)
            }
            folder.applySelectionChrome(chrome)
        } else if let media = collectionView.item(at: path) as? LibraryMediaGridItem {
            media.onDeselectRequested = { [weak self] in
                self?.deselectTile(at: index)
            }
            media.applySelectionChrome(chrome)
        }
    }

    private func deselectTile(at index: Int) {
        controller.removeFromMultiSelection(at: index)
        syncCollectionSelection()
        applyVisibleSelectionChrome()
    }

    private func handleGridKeyCommand(_ command: LibraryGridKeyCommand) -> Bool {
        switch command {
        case .escape:
            guard controller.hasBatchSelection else { return false }
            controller.clearMultiSelection()
            return true
        case .selectAll:
            controller.selectAllDisplayed()
            return true
        case .move(let delta, let extending):
            guard !controller.displayedEntries.isEmpty else { return false }
            controller.moveSelection(by: delta, extending: extending)
            if let focus = controller.selectionFocusIndex {
                collectionView.scrollToItems(
                    at: [IndexPath(item: focus, section: 0)],
                    scrollPosition: .nearestHorizontalEdge
                )
            }
            return true
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
        sort.selectKey(key)
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

    @objc private func batchDeletePressed() {
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
        case .folder(let folderURL):
            let item = collectionView.makeItem(withIdentifier: LibraryFolderGridItem.reuseID, for: indexPath) as! LibraryFolderGridItem
            item.applyMetrics(metrics)
            let counts = MediaLibraryScanner.mediaCounts(in: folderURL)
            item.configure(
                name: entry.name,
                itemCount: counts.total,
                dateModified: entry.dateModified,
                folderURL: folderURL
            )
            if !metrics.showsTitle {
                item.loadPreviews(folderURL: folderURL, maxSide: metrics.thumbnailMaxSide, indexPath: indexPath) { [weak self, weak item] images, path in
                    guard let self, let item, self.thumbnailTasks[path] == folderURL else { return }
                    item.setPreviews(images)
                }
                thumbnailTasks[indexPath] = folderURL
            }
            return item
        case .media(let file):
            let item = collectionView.makeItem(withIdentifier: LibraryMediaGridItem.reuseID, for: indexPath) as! LibraryMediaGridItem
            item.applyMetrics(metrics)
            item.configure(name: entry.name, kind: file.kind, fileSize: entry.size, url: file.url)
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
        // Context menus come from LibraryGridCollectionView.contextMenuProvider.
        item.view.menu = nil
        let live = previewSelectionIndices ?? controller.selectedEntryIndices
        let chrome: LibraryTileSelectionChrome
        if !live.contains(indexPath.item) {
            chrome = .none
        } else if previewSelectionIndices != nil {
            chrome = .preview
        } else {
            chrome = .selected
        }
        configureSelectableItem(at: indexPath, chrome: chrome)
    }

    func collectionView(_ collectionView: NSCollectionView, shouldSelectItemsAt indexPaths: Set<IndexPath>) -> Set<IndexPath> {
        if suppressCollectionSelectionCallback { return indexPaths }
        guard let event = NSApp.currentEvent else { return indexPaths }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Custom marquee/paint/open path owns unmodified clicks.
        if !flags.contains(.command) && !flags.contains(.shift) {
            return []
        }
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
        if suppressCollectionSelectionCallback { return }
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if flags.contains(.command) || flags.contains(.shift) {
            let indices = IndexSet(indexPaths.map(\.item))
            if flags.contains(.shift), let last = indices.max() {
                controller.extendMultiSelection(to: last)
            } else if flags.contains(.command) {
                // Union newly selected (toggle off handled in didDeselect).
                controller.setMultiSelection(indices.union(controller.selectedEntryIndices), anchor: indices.max())
            }
            syncCollectionSelection()
            applyVisibleSelectionChrome()
            return
        }
        // Unmodified selection is handled by LibraryGridCollectionView multi-select host.
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        if suppressCollectionSelectionCallback { return }
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        guard flags.contains(.command) else { return }
        var next = controller.selectedEntryIndices
        for path in indexPaths {
            next.remove(path.item)
        }
        controller.setMultiSelection(next, anchor: next.max())
        applyVisibleSelectionChrome()
    }

    func collectionView(_ collectionView: NSCollectionView, menuFor event: NSEvent) -> NSMenu? {
        contextMenu(for: event, in: collectionView)
    }

    private func contextMenu(for event: NSEvent, in collectionView: NSCollectionView) -> NSMenu? {
        guard let indexPath = indexPath(for: event, in: collectionView) else {
            if controller.hasBatchSelection {
                return buildEmptySpaceContextMenu()
            }
            return nil
        }
        guard controller.entry(at: indexPath) != nil else { return nil }

        if controller.selectedEntryIndices.contains(indexPath.item), controller.hasBatchSelection {
            return buildBatchContextMenu()
        }

        // Context actions target the clicked tile via menu item tags — do not select it.
        guard let entry = controller.entry(at: indexPath) else { return nil }
        return buildContextMenu(for: entry, itemIndex: indexPath.item)
    }

    private func indexPath(for event: NSEvent, in collectionView: NSCollectionView) -> IndexPath? {
        let point = collectionView.convert(event.locationInWindow, from: nil)
        if let indexPath = collectionView.indexPathForItem(at: point) {
            return indexPath
        }
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard let item = collectionView.item(at: indexPath) else { continue }
            let pointInItem = item.view.convert(event.locationInWindow, from: nil)
            if item.view.bounds.contains(pointInItem) {
                return indexPath
            }
        }
        return nil
    }

    private func buildBatchContextMenu() -> NSMenu {
        let entries = controller.selectedEntries
        let hasPlayable = entries.contains { entryHasPlayableMedia($0) }
        let menu = NSMenu()

        func append(_ title: String, action: Selector, enabled: Bool = true) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
        }

        append("Play", action: #selector(batchContextPlay), enabled: hasPlayable)
        append("Add to Queue", action: #selector(batchContextQueue), enabled: hasPlayable)
        append("Move to Trash", action: #selector(batchContextTrash))
        menu.addItem(.separator())
        append("Select All", action: #selector(batchContextSelectAll))
        append("Deselect All", action: #selector(batchContextDeselectAll))
        return menu
    }

    private func buildEmptySpaceContextMenu() -> NSMenu {
        let menu = NSMenu()
        let deselect = menu.addItem(withTitle: "Deselect All", action: #selector(batchContextDeselectAll), keyEquivalent: "")
        deselect.target = self
        let selectAll = menu.addItem(withTitle: "Select All", action: #selector(batchContextSelectAll), keyEquivalent: "")
        selectAll.target = self
        return menu
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
        menu.addItem(.separator())
        appendItem("Select All", action: #selector(batchContextSelectAll))
        if controller.hasBatchSelection {
            appendItem("Deselect All", action: #selector(batchContextDeselectAll))
        }
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

    @objc private func batchContextPlay() {
        let entries = controller.selectedEntries
        guard !entries.isEmpty else { return }
        onBatchAction?(.play, entries)
    }

    @objc private func batchContextQueue() {
        let entries = controller.selectedEntries
        guard !entries.isEmpty else { return }
        onBatchAction?(.addToQueue, entries)
    }

    @objc private func batchContextTrash() {
        let entries = controller.selectedEntries
        guard !entries.isEmpty else { return }
        onBatchAction?(.remove, entries)
    }

    @objc private func batchContextSelectAll() {
        controller.selectAllDisplayed()
    }

    @objc private func batchContextDeselectAll() {
        controller.clearMultiSelection()
    }
}

// MARK: - Multi-select host

extension LibraryBrowseView: LibraryGridMultiSelectHost {
    func committedSelectionIndices() -> IndexSet {
        controller.selectedEntryIndices
    }

    func selectionGestureDidUpdatePreview(_ indices: IndexSet) {
        previewSelectionIndices = indices
        applyVisibleSelectionChrome()
    }

    func selectionGestureDidCommit(_ indices: IndexSet) {
        previewSelectionIndices = nil
        controller.setMultiSelection(indices, anchor: indices.max())
        syncCollectionSelection()
        applyVisibleSelectionChrome()
    }

    func selectionGestureDidRequestOpen(at index: Int) {
        previewSelectionIndices = nil
        let path = IndexPath(item: index, section: 0)
        guard let entry = controller.entry(at: path) else { return }
        if case .folder = entry.kind {
            guard let event = NSApp.currentEvent,
                  let item = collectionView.item(at: path) as? LibraryFolderGridItem,
                  item.containsFolderGlyphHit(for: event) else {
                applyVisibleSelectionChrome()
                return
            }
        }
        openBrowseEntry(entry)
        syncCollectionSelection()
        applyVisibleSelectionChrome()
    }
}

// MARK: - Grid items

private class LibraryGridItemView: NSView {
    /// Optional deselect control that must still receive clicks.
    var interactiveChromeHitTest: ((NSPoint) -> NSView?)?

    private var parentGridCollection: LibraryGridCollectionView? {
        sequence(first: superview as NSView?, next: { $0?.superview })
            .compactMap { $0 as? LibraryGridCollectionView }
            .first
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        let local = convert(point, from: superview)
        if let chromeHit = interactiveChromeHitTest?(local) {
            return chromeHit
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if let collection = parentGridCollection {
            collection.mouseDown(with: event)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let collection = parentGridCollection {
            collection.mouseDragged(with: event)
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if let collection = parentGridCollection {
            collection.mouseUp(with: event)
            return
        }
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        if let collection = parentGridCollection {
            collection.rightMouseDown(with: event)
            return
        }
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let menu { return menu }
        if let collection = parentGridCollection {
            return collection.menu(for: event)
        }
        return super.menu(for: event)
    }
}

/// Grid tile host that reports hover for border affordance (media + folders).
private final class LibraryTileHoverHostView: LibraryGridItemView {
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

private enum LibraryGridCardLayout {
    static let previewInset: CGFloat = 6
    /// Match Gallery caption breathing room (not flush to card edges).
    static let previewTop: CGFloat = 6
    static let nameTop: CGFloat = 6
    static let nameMetaSpacing: CGFloat = 2
    static let metaBottom: CGFloat = 6
    static let labelInset: CGFloat = 8
}

/// Colored status dot + format label (`● JPEG` / `● RAW` / `● MP4`) ahead of file size.
private final class LibraryMediaKindDotLabel: NSView {
    private let dotView = NSView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        dotView.wantsLayer = true
        dotView.layer?.masksToBounds = true
        dotView.translatesAutoresizingMaskIntoConstraints = false

        label.isEditable = false
        label.isBordered = false
        label.isBezeled = false
        label.drawsBackground = false
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(dotView)
        addSubview(label)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 6),
            dotView.heightAnchor.constraint(equalToConstant: 6),

            label.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        dotView.layer?.cornerRadius = dotView.bounds.height / 2
    }

    func apply(badge: LibraryMediaFormatBadge, appearance: NSAppearance) {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        label.stringValue = badge.title
        label.textColor = .secondaryLabelColor
        dotView.layer?.backgroundColor = Self.dotColor(for: badge.family, isDark: isDark).cgColor
    }

    private static func dotColor(for family: LibraryMediaFormatFamily, isDark: Bool) -> NSColor {
        switch family {
        case .photo:
            // Teal brand — not system blue.
            return LaughTheme.accent
        case .gif:
            return isDark
                ? NSColor(srgbRed: 0.95, green: 0.45, blue: 0.75, alpha: 1)
                : NSColor(srgbRed: 0.82, green: 0.28, blue: 0.58, alpha: 1)
        case .raw:
            return isDark
                ? NSColor(srgbRed: 0.55, green: 0.78, blue: 0.42, alpha: 1)
                : NSColor(srgbRed: 0.35, green: 0.58, blue: 0.22, alpha: 1)
        case .video:
            return isDark
                ? NSColor(srgbRed: 0.78, green: 0.55, blue: 0.98, alpha: 1)
                : NSColor(srgbRed: 0.58, green: 0.32, blue: 0.86, alpha: 1)
        case .other:
            return .tertiaryLabelColor
        }
    }
}

private enum LibraryMediaMetaFormatting {
    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    static func sizeLabel(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "—" }
        return sizeFormatter.string(fromByteCount: bytes)
    }
}

private final class LibraryFolderGridItem: NSCollectionViewItem, LibrarySelectableGridItem {
    static let reuseID = NSUserInterfaceItemIdentifier("LibraryFolderGridItem")

    private let cardView = LibraryFolderCardChromeView()
    private let previewHost = NSView()
    private let collageGap: CGFloat = 1
    private let leftThumb = LibraryCoverImageView()
    private let rightTopThumb = LibraryCoverImageView()
    private let rightBottomThumb = LibraryCoverImageView()
    private let emptyIconView = NSImageView()
    private let folderGlyphView = NSImageView()
    private let badgeView = NSView()
    private let badgeIconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let selectionChrome = LibraryTileSelectionChromeView()
    var onDeselectRequested: (() -> Void)?

    private var previewHeightConstraint: NSLayoutConstraint?
    private var previewAspectConstraint: NSLayoutConstraint?
    private var previewTopConstraint: NSLayoutConstraint?
    private var rightColumnWidthConstraint: NSLayoutConstraint?
    private var leftTrailingToRightConstraint: NSLayoutConstraint?
    private var leftTrailingToPreviewConstraint: NSLayoutConstraint?
    private var nameTopConstraint: NSLayoutConstraint?
    private var metaBottomConstraint: NSLayoutConstraint?
    private var nameMetaSpacingConstraint: NSLayoutConstraint?
    private var cardTopConstraint: NSLayoutConstraint?
    private var cardLeadingConstraint: NSLayoutConstraint?
    private var cardTrailingConstraint: NSLayoutConstraint?
    private var cardBottomConstraint: NSLayoutConstraint?
    private var folderGlyphSideConstraint: NSLayoutConstraint?
    private var loadToken = UUID()
    private var folderURL: URL?
    private var usesIconOnlyLayout = false
    private var isHovered = false
    private var selectionState: LibraryTileSelectionChrome = .none

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    override func loadView() {
        let host = LibraryTileHoverHostView()
        host.onHoverChange = { [weak self] hovered in
            self?.setHovered(hovered)
        }
        view = host
        view.wantsLayer = true
        view.layer?.masksToBounds = false
        view.layer?.borderWidth = 0

        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 6
        cardView.layer?.masksToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.onAppearanceChange = { [weak self] in
            self?.applyChrome()
        }

        previewHost.wantsLayer = true
        previewHost.layer?.cornerRadius = 4
        previewHost.layer?.masksToBounds = true
        previewHost.translatesAutoresizingMaskIntoConstraints = false

        for thumb in [leftThumb, rightTopThumb, rightBottomThumb] {
            thumb.translatesAutoresizingMaskIntoConstraints = false
            thumb.setFillMode(true, placeholderBackground: nil)
            previewHost.addSubview(thumb)
        }

        emptyIconView.imageScaling = .scaleNone
        emptyIconView.translatesAutoresizingMaskIntoConstraints = false
        previewHost.addSubview(emptyIconView)

        folderGlyphView.imageScaling = .scaleProportionallyUpOrDown
        folderGlyphView.translatesAutoresizingMaskIntoConstraints = false
        folderGlyphView.isHidden = true
        // Inside the preview container (above title/count) — not behind previewHost on the card.
        previewHost.addSubview(folderGlyphView)

        badgeView.wantsLayer = true
        badgeView.layer?.cornerRadius = 6
        badgeView.layer?.masksToBounds = true
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        previewHost.addSubview(badgeView)

        badgeIconView.imageScaling = .scaleNone
        badgeIconView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(badgeIconView)

        configureLibraryGridNameLabel(nameLabel, fontSize: 13)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.alignment = .left
        nameLabel.maximumNumberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.cell?.wraps = false
        nameLabel.cell?.usesSingleLineMode = true
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        nameLabel.setContentHuggingPriority(.required, for: .vertical)

        metaLabel.isEditable = false
        metaLabel.isBordered = false
        metaLabel.isBezeled = false
        metaLabel.drawsBackground = false
        metaLabel.font = .systemFont(ofSize: 11, weight: .regular)
        metaLabel.textColor = .secondaryLabelColor
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.maximumNumberOfLines = 1
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        metaLabel.setContentHuggingPriority(.required, for: .vertical)

        selectionChrome.translatesAutoresizingMaskIntoConstraints = false
        selectionChrome.onDeselect = { [weak self] in
            self?.onDeselectRequested?()
        }
        (view as? LibraryGridItemView)?.interactiveChromeHitTest = { [weak selectionChrome] local in
            selectionChrome?.hitTest(local)
        }

        view.addSubview(cardView)
        cardView.addSubview(previewHost)
        cardView.addSubview(nameLabel)
        cardView.addSubview(metaLabel)
        view.addSubview(selectionChrome)

        let previewTop = previewHost.topAnchor.constraint(equalTo: cardView.topAnchor, constant: LibraryGridCardLayout.previewTop)
        let previewHeight = previewHost.heightAnchor.constraint(equalToConstant: 112)
        previewHeight.priority = .defaultHigh
        let previewAspect = previewHost.heightAnchor.constraint(equalTo: previewHost.widthAnchor)
        previewAspect.priority = .required
        let rightWidth = rightTopThumb.widthAnchor.constraint(equalTo: previewHost.widthAnchor, multiplier: 1.0 / 3.0)
        let leftToRight = leftThumb.trailingAnchor.constraint(equalTo: rightTopThumb.leadingAnchor, constant: -collageGap)
        let leftToPreview = leftThumb.trailingAnchor.constraint(equalTo: previewHost.trailingAnchor)
        let nameTop = nameLabel.topAnchor.constraint(equalTo: previewHost.bottomAnchor, constant: LibraryGridCardLayout.nameTop)
        let nameMetaSpacing = metaLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: LibraryGridCardLayout.nameMetaSpacing)
        // Grid pins caption to the card bottom so height matches content (no tall empty band).
        let metaBottom = metaLabel.bottomAnchor.constraint(
            equalTo: cardView.bottomAnchor,
            constant: -LibraryGridCardLayout.metaBottom
        )
        let cardTop = cardView.topAnchor.constraint(equalTo: view.topAnchor)
        let cardLeading = cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let cardTrailing = cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        let cardBottom = cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        let glyphSide = folderGlyphView.widthAnchor.constraint(equalToConstant: 52)
        previewTopConstraint = previewTop
        previewHeightConstraint = previewHeight
        previewAspectConstraint = previewAspect
        rightColumnWidthConstraint = rightWidth
        leftTrailingToRightConstraint = leftToRight
        leftTrailingToPreviewConstraint = leftToPreview
        nameTopConstraint = nameTop
        nameMetaSpacingConstraint = nameMetaSpacing
        metaBottomConstraint = metaBottom
        cardTopConstraint = cardTop
        cardLeadingConstraint = cardLeading
        cardTrailingConstraint = cardTrailing
        cardBottomConstraint = cardBottom
        folderGlyphSideConstraint = glyphSide
        leftToPreview.isActive = false
        previewAspect.isActive = false

        NSLayoutConstraint.activate([
            cardTop,
            cardLeading,
            cardTrailing,
            cardBottom,

            previewTop,
            previewHost.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: LibraryGridCardLayout.previewInset),
            previewHost.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -LibraryGridCardLayout.previewInset),
            previewHeight,

            leftThumb.leadingAnchor.constraint(equalTo: previewHost.leadingAnchor),
            leftThumb.topAnchor.constraint(equalTo: previewHost.topAnchor),
            leftThumb.bottomAnchor.constraint(equalTo: previewHost.bottomAnchor),
            leftToRight,

            rightWidth,
            rightTopThumb.trailingAnchor.constraint(equalTo: previewHost.trailingAnchor),
            rightTopThumb.topAnchor.constraint(equalTo: previewHost.topAnchor),
            rightTopThumb.bottomAnchor.constraint(equalTo: rightBottomThumb.topAnchor, constant: -collageGap),
            rightTopThumb.heightAnchor.constraint(equalTo: rightBottomThumb.heightAnchor),

            rightBottomThumb.leadingAnchor.constraint(equalTo: rightTopThumb.leadingAnchor),
            rightBottomThumb.trailingAnchor.constraint(equalTo: rightTopThumb.trailingAnchor),
            rightBottomThumb.bottomAnchor.constraint(equalTo: previewHost.bottomAnchor),

            emptyIconView.centerXAnchor.constraint(equalTo: previewHost.centerXAnchor),
            emptyIconView.centerYAnchor.constraint(equalTo: previewHost.centerYAnchor),
            emptyIconView.widthAnchor.constraint(equalToConstant: 28),
            emptyIconView.heightAnchor.constraint(equalToConstant: 28),

            folderGlyphView.centerXAnchor.constraint(equalTo: previewHost.centerXAnchor),
            folderGlyphView.centerYAnchor.constraint(equalTo: previewHost.centerYAnchor),
            glyphSide,
            folderGlyphView.heightAnchor.constraint(equalTo: folderGlyphView.widthAnchor),

            badgeView.leadingAnchor.constraint(equalTo: previewHost.leadingAnchor, constant: 6),
            badgeView.bottomAnchor.constraint(equalTo: previewHost.bottomAnchor, constant: -6),
            badgeView.widthAnchor.constraint(equalToConstant: 28),
            badgeView.heightAnchor.constraint(equalToConstant: 28),

            badgeIconView.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            badgeIconView.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
            badgeIconView.widthAnchor.constraint(equalToConstant: 14),
            badgeIconView.heightAnchor.constraint(equalToConstant: 14),

            nameTop,
            nameLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: LibraryGridCardLayout.labelInset),
            nameLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -LibraryGridCardLayout.labelInset),

            nameMetaSpacing,
            metaLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            metaBottom,

            selectionChrome.topAnchor.constraint(equalTo: view.topAnchor),
            selectionChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectionChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectionChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        applyBadgeIcon()
        applyChrome()
        showEmptyPreview()
    }

    func applySelectionChrome(_ chrome: LibraryTileSelectionChrome) {
        selectionState = chrome
        selectionChrome.apply(chrome, appearance: view.effectiveAppearance, cornerRadius: 6)
        if chrome != .none {
            setHovered(false)
        }
    }

    func applyMetrics(_ metrics: LibraryBrowseTileMetrics) {
        if metrics.showsTitle {
            // Grid: square preview well + title/count — shared layout with media cards.
            usesIconOnlyLayout = true
            setCardInset(0)
            previewTopConstraint?.constant = LibraryGridCardLayout.previewTop
            nameTopConstraint?.constant = LibraryGridCardLayout.nameTop
            nameMetaSpacingConstraint?.constant = LibraryGridCardLayout.nameMetaSpacing
            metaBottomConstraint?.constant = -LibraryGridCardLayout.metaBottom
            metaBottomConstraint?.isActive = true
            nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
            nameLabel.alignment = .center
            nameLabel.maximumNumberOfLines = 1
            nameLabel.lineBreakMode = .byTruncatingTail
            nameLabel.cell?.wraps = false
            nameLabel.cell?.usesSingleLineMode = true
            nameLabel.cell?.truncatesLastVisibleLine = true
            metaLabel.font = .systemFont(ofSize: 11, weight: .regular)
            metaLabel.alignment = .center
            metaLabel.maximumNumberOfLines = 1
            metaLabel.isHidden = false
            previewHeightConstraint?.isActive = false
            previewAspectConstraint?.isActive = true
            folderGlyphSideConstraint?.constant = metrics.folderIconPointSize
            applyFolderGlyph(pointSize: metrics.folderIconPointSize)
            setCollageHidden(true)
            folderGlyphView.isHidden = false
            badgeView.isHidden = true
            clearThumbs()
            previewHost.layer?.backgroundColor = mutedPreviewFill().cgColor
        } else {
            // Gallery (~16:9): collage + caption with reserved space so title/count never overlap.
            usesIconOnlyLayout = false
            setCardInset(0)
            let previewTopInset: CGFloat = 5
            let captionBand: CGFloat = 44
            previewTopConstraint?.constant = previewTopInset
            nameTopConstraint?.constant = 6
            nameMetaSpacingConstraint?.constant = 1
            metaBottomConstraint?.constant = -6
            metaBottomConstraint?.isActive = true
            nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
            nameLabel.alignment = .left
            nameLabel.maximumNumberOfLines = 1
            metaLabel.font = .systemFont(ofSize: 10, weight: .regular)
            metaLabel.alignment = .left
            metaLabel.isHidden = false
            previewAspectConstraint?.isActive = false
            previewHeightConstraint?.isActive = true
            let cellHeight = metrics.minItemSize.height
            previewHeightConstraint?.constant = max(40, cellHeight - previewTopInset - captionBand)
            setCollageHidden(false)
            folderGlyphView.isHidden = true
            badgeView.isHidden = false
            showEmptyPreview()
        }
        applyChrome()
    }

    private func setCardInset(_ inset: CGFloat) {
        cardTopConstraint?.constant = inset
        cardLeadingConstraint?.constant = inset
        cardTrailingConstraint?.constant = -inset
        cardBottomConstraint?.constant = -inset
    }

    private func setCollageHidden(_ hidden: Bool) {
        leftThumb.isHidden = hidden
        rightTopThumb.isHidden = hidden
        rightBottomThumb.isHidden = hidden
        // Empty outline placeholder is gallery-only; grid uses folderGlyphView instead.
        if hidden {
            emptyIconView.isHidden = true
        }
    }

    private func applyFolderGlyph(pointSize: CGFloat) {
        guard let folderURL else {
            if let folder = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder") {
                let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
                let configured = folder.withSymbolConfiguration(config)
                configured?.isTemplate = true
                folderGlyphView.image = configured
                folderGlyphView.contentTintColor = .secondaryLabelColor
            }
            return
        }
        let resolved = LibraryFolderIcon.resolve(
            for: folderURL,
            pointSize: pointSize,
            symbolFallback: "folder.fill",
            forceFinderAppearance: true
        )
        folderGlyphView.image = resolved.image
        if resolved.isTemplate {
            folderGlyphView.contentTintColor = resolved.tintColor ?? .secondaryLabelColor
        } else {
            folderGlyphView.contentTintColor = nil
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadToken = UUID()
        folderURL = nil
        nameLabel.stringValue = ""
        metaLabel.stringValue = ""
        view.toolTip = nil
        onDeselectRequested = nil
        clearThumbs()
        showEmptyPreview()
        applySelectionChrome(.none)
        setHovered(false)
    }

    func configure(name: String, itemCount: Int, dateModified: Date?, folderURL: URL) {
        self.folderURL = folderURL
        nameLabel.stringValue = name
        view.toolTip = name
        let countText: String
        if itemCount == 1 {
            countText = "1 item"
        } else {
            countText = "\(FolderMediaCounts.compactLabel(itemCount)) items"
        }
        if let dateModified {
            let relative = Self.relativeDateFormatter.localizedString(for: dateModified, relativeTo: Date())
            metaLabel.stringValue = "\(countText)  ·  \(relative)"
        } else {
            metaLabel.stringValue = countText
        }
        applyBadgePalette(for: name)
        applyBadgeIcon()
        if usesIconOnlyLayout {
            applyFolderGlyph(pointSize: folderGlyphSideConstraint?.constant ?? 40)
        } else {
            // Refresh gallery empty/badge glyph now that folderURL is known.
            if emptyIconView.isHidden == false {
                showEmptyPreview()
            }
        }
    }

    func loadPreviews(
        folderURL: URL,
        maxSide: CGFloat,
        indexPath: IndexPath,
        completion: @escaping ([NSImage?], IndexPath) -> Void
    ) {
        self.folderURL = folderURL
        guard !usesIconOnlyLayout else {
            completion([], indexPath)
            return
        }
        let token = UUID()
        loadToken = token
        clearThumbs()
        showEmptyPreview()

        let scale = view.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? MediaThumbnailGenerator.defaultScreenScale()
        DispatchQueue.global(qos: .userInitiated).async {
            let files = MediaLibraryScanner.previewMediaFiles(in: folderURL, limit: 3)
            let images: [NSImage?] = files.map { file in
                MediaThumbnailGenerator.thumbnail(
                    for: file.url,
                    kind: file.kind,
                    maxSide: maxSide,
                    screenScale: scale
                )
            }
            DispatchQueue.main.async {
                completion(images, indexPath)
            }
        }
    }

    func setPreviews(_ images: [NSImage?]) {
        guard !usesIconOnlyLayout else { return }
        let photos = images.compactMap { $0 }
        clearThumbs()
        switch photos.count {
        case 0:
            showEmptyPreview()
        case 1:
            emptyIconView.isHidden = true
            leftThumb.isHidden = false
            rightTopThumb.isHidden = true
            rightBottomThumb.isHidden = true
            leftTrailingToRightConstraint?.isActive = false
            leftTrailingToPreviewConstraint?.isActive = true
            rightColumnWidthConstraint?.isActive = false
            leftThumb.setPhoto(photos[0])
        case 2:
            emptyIconView.isHidden = true
            leftThumb.isHidden = false
            rightTopThumb.isHidden = false
            rightBottomThumb.isHidden = false
            leftTrailingToPreviewConstraint?.isActive = false
            leftTrailingToRightConstraint?.isActive = true
            rightColumnWidthConstraint?.isActive = true
            leftThumb.setPhoto(photos[0])
            rightTopThumb.setPhoto(photos[1])
            rightBottomThumb.setFillMode(true, placeholderBackground: mutedPreviewFill())
        default:
            emptyIconView.isHidden = true
            leftThumb.isHidden = false
            rightTopThumb.isHidden = false
            rightBottomThumb.isHidden = false
            leftTrailingToPreviewConstraint?.isActive = false
            leftTrailingToRightConstraint?.isActive = true
            rightColumnWidthConstraint?.isActive = true
            leftThumb.setPhoto(photos[0])
            rightTopThumb.setPhoto(photos[1])
            rightBottomThumb.setPhoto(photos[2])
        }
        applyChrome()
    }

    /// Whole card opens the folder (card fills the cell like media tiles).
    func containsFolderGlyphHit(for event: NSEvent) -> Bool {
        let point = view.convert(event.locationInWindow, from: nil)
        return view.bounds.contains(point)
    }

    private func clearThumbs() {
        leftThumb.clearImage()
        rightTopThumb.clearImage()
        rightBottomThumb.clearImage()
        leftThumb.setFillMode(true, placeholderBackground: mutedPreviewFill())
        rightTopThumb.setFillMode(true, placeholderBackground: mutedPreviewFill())
        rightBottomThumb.setFillMode(true, placeholderBackground: mutedPreviewFill())
    }

    private func showEmptyPreview() {
        guard !usesIconOnlyLayout else { return }
        emptyIconView.isHidden = false
        leftThumb.isHidden = true
        rightTopThumb.isHidden = true
        rightBottomThumb.isHidden = true
        leftTrailingToPreviewConstraint?.isActive = false
        leftTrailingToRightConstraint?.isActive = true
        rightColumnWidthConstraint?.isActive = true
        if let folderURL {
            let resolved = LibraryFolderIcon.resolve(
                for: folderURL,
                pointSize: 22,
                symbolFallback: "folder.fill"
            )
            emptyIconView.image = resolved.image
            emptyIconView.contentTintColor = resolved.isTemplate ? .secondaryLabelColor : nil
        } else if let folder = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            let configured = folder.withSymbolConfiguration(config)
            configured?.isTemplate = true
            emptyIconView.image = configured
            emptyIconView.contentTintColor = .secondaryLabelColor
        }
        previewHost.layer?.backgroundColor = mutedPreviewFill().cgColor
    }

    private func applyBadgeIcon() {
        if let folderURL {
            let resolved = LibraryFolderIcon.resolve(
                for: folderURL,
                pointSize: 12,
                symbolFallback: "folder.fill"
            )
            let image = resolved.image
            image.size = NSSize(width: 14, height: 14)
            badgeIconView.image = image
            // Template badges keep the name-based palette tint; Finder icons stay full-color.
            if resolved.isTemplate {
                badgeIconView.image?.isTemplate = true
            } else {
                badgeIconView.image?.isTemplate = false
                badgeIconView.contentTintColor = nil
            }
            return
        }
        if let folder = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder") {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            let configured = folder.withSymbolConfiguration(config)
            configured?.isTemplate = true
            configured?.size = NSSize(width: 14, height: 14)
            badgeIconView.image = configured
        }
    }

    private func applyBadgePalette(for name: String) {
        let palette = Self.badgePalette(for: name, appearance: view.effectiveAppearance)
        badgeView.layer?.backgroundColor = palette.fill.cgColor
        // Finder custom icons stay full-color; SF Symbol badges take the palette tint.
        if badgeIconView.image?.isTemplate == true {
            badgeIconView.contentTintColor = palette.tint
        }
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        badgeView.layer?.borderWidth = 1
        badgeView.layer?.borderColor = NSColor.labelColor.withAlphaComponent(isDark ? 0.12 : 0.08).cgColor
    }

    private func applyChrome() {
        let appearance = view.effectiveAppearance
        // Card plate matches the left sidebar; collage gaps match the browse content pane.
        let card = LaughTheme.librarySidebarBackground(appearance: appearance)
        let content = LaughTheme.libraryContentBackground(appearance: appearance)
        cardView.layer?.backgroundColor = card.cgColor
        previewHost.layer?.borderWidth = 1
        previewHost.layer?.borderColor = NSColor.separatorColor.cgColor
        previewHost.layer?.backgroundColor = content.cgColor
        nameLabel.textColor = .labelColor
        metaLabel.textColor = .secondaryLabelColor
        let name = nameLabel.stringValue
        if !name.isEmpty {
            applyBadgePalette(for: name)
        }
        // Idle vs hover border — same treatment as media tiles.
        applyHoverBorderChrome()
    }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
        applyHoverBorderChrome()
    }

    private func applyHoverBorderChrome() {
        guard selectionState == .none else {
            view.layer?.borderWidth = 0
            view.layer?.borderColor = nil
            cardView.layer?.borderWidth = 1
            cardView.layer?.borderColor = NSColor.separatorColor.cgColor
            return
        }
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if usesIconOnlyLayout {
            // Grid cards: strengthen the card rim on hover (media tiles do the same).
            view.layer?.borderWidth = 0
            view.layer?.borderColor = nil
            if isHovered {
                cardView.layer?.borderWidth = 1.5
                cardView.layer?.borderColor = (isDark
                    ? NSColor.white.withAlphaComponent(0.85)
                    : NSColor.labelColor.withAlphaComponent(0.55)).cgColor
            } else {
                cardView.layer?.borderWidth = 1
                cardView.layer?.borderColor = NSColor.separatorColor.cgColor
            }
            return
        }
        // Gallery folders: outer tile rim like image Gallery hover.
        cardView.layer?.borderWidth = 1
        cardView.layer?.borderColor = NSColor.separatorColor.cgColor
        view.layer?.borderWidth = isHovered ? 1.5 : 0
        view.layer?.borderColor = isHovered
            ? NSColor.white.withAlphaComponent(0.95).cgColor
            : nil
    }

    private func mutedPreviewFill() -> NSColor {
        LaughTheme.libraryContentBackground(appearance: view.effectiveAppearance)
    }

    private struct BadgePalette {
        let fill: NSColor
        let tint: NSColor
    }

    private static func badgePalette(for name: String, appearance: NSAppearance) -> BadgePalette {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Soft tints inspired by the folder-management-grid cards (no system blue chrome).
        let palettes: [BadgePalette] = [
            BadgePalette(
                fill: NSColor(srgbRed: 0.12, green: 0.55, blue: 0.52, alpha: isDark ? 0.22 : 0.14),
                tint: NSColor(srgbRed: 0.18, green: 0.62, blue: 0.58, alpha: 1)
            ),
            BadgePalette(
                fill: NSColor(srgbRed: 0.55, green: 0.35, blue: 0.85, alpha: isDark ? 0.22 : 0.12),
                tint: NSColor(srgbRed: 0.58, green: 0.40, blue: 0.90, alpha: 1)
            ),
            BadgePalette(
                fill: NSColor(srgbRed: 0.92, green: 0.48, blue: 0.22, alpha: isDark ? 0.22 : 0.14),
                tint: NSColor(srgbRed: 0.90, green: 0.48, blue: 0.20, alpha: 1)
            ),
            BadgePalette(
                fill: NSColor(srgbRed: 0.20, green: 0.62, blue: 0.42, alpha: isDark ? 0.22 : 0.14),
                tint: NSColor(srgbRed: 0.22, green: 0.66, blue: 0.45, alpha: 1)
            ),
            BadgePalette(
                fill: NSColor(srgbRed: 0.88, green: 0.32, blue: 0.55, alpha: isDark ? 0.22 : 0.12),
                tint: NSColor(srgbRed: 0.90, green: 0.35, blue: 0.58, alpha: 1)
            ),
            BadgePalette(
                fill: LaughTheme.chromeHoverFill(appearance: appearance),
                tint: .secondaryLabelColor
            )
        ]
        let hash = name.unicodeScalars.reduce(0) { ($0 &+ Int($1.value) &* 31) }
        return palettes[abs(hash) % palettes.count]
    }
}

private final class LibraryFolderCardChromeView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

// MARK: - Tile selection chrome

private final class LibraryTileSelectionChromeView: NSView {
    var onDeselect: (() -> Void)?
    private let wash = NSView()
    private let badgeView = NSView()
    private let checkView = NSImageView()
    private let deselectButton = NSButton(title: "", target: nil, action: nil)
    private var current: LibraryTileSelectionChrome = .none
    private let badgeSide: CGFloat = 20

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        wash.wantsLayer = true
        wash.translatesAutoresizingMaskIntoConstraints = false
        addSubview(wash)

        badgeView.wantsLayer = true
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.layer?.masksToBounds = true
        badgeView.layer?.cornerRadius = badgeSide / 2
        addSubview(badgeView)

        checkView.imageScaling = .scaleProportionallyDown
        checkView.imageAlignment = .alignCenter
        checkView.contentTintColor = .white
        checkView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(checkView)

        deselectButton.bezelStyle = .inline
        deselectButton.isBordered = false
        deselectButton.focusRingType = .none
        deselectButton.title = ""
        deselectButton.image = nil
        deselectButton.translatesAutoresizingMaskIntoConstraints = false
        deselectButton.target = self
        deselectButton.action = #selector(deselectPressed)
        deselectButton.toolTip = "Deselect"
        addSubview(deselectButton)

        NSLayoutConstraint.activate([
            wash.topAnchor.constraint(equalTo: topAnchor),
            wash.leadingAnchor.constraint(equalTo: leadingAnchor),
            wash.trailingAnchor.constraint(equalTo: trailingAnchor),
            wash.bottomAnchor.constraint(equalTo: bottomAnchor),

            badgeView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            badgeView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            badgeView.widthAnchor.constraint(equalToConstant: badgeSide),
            badgeView.heightAnchor.constraint(equalToConstant: badgeSide),

            checkView.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            checkView.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: 11),
            checkView.heightAnchor.constraint(equalToConstant: 11),

            deselectButton.topAnchor.constraint(equalTo: badgeView.topAnchor),
            deselectButton.leadingAnchor.constraint(equalTo: badgeView.leadingAnchor),
            deselectButton.trailingAnchor.constraint(equalTo: badgeView.trailingAnchor),
            deselectButton.bottomAnchor.constraint(equalTo: badgeView.bottomAnchor)
        ])
        refreshDeselectButtonAppearance()
        apply(.none, appearance: effectiveAppearance, cornerRadius: 8)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshDeselectButtonAppearance()
        apply(current, appearance: effectiveAppearance, cornerRadius: layer?.cornerRadius ?? 8)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard (current == .selected || current == .preview), !badgeView.isHidden, !isHidden else { return nil }
        guard frame.contains(point) else { return nil }
        let local = convert(point, from: superview)
        if badgeView.frame.insetBy(dx: -2, dy: -2).contains(local) {
            return deselectButton
        }
        return nil
    }

    func apply(_ chrome: LibraryTileSelectionChrome, appearance: NSAppearance, cornerRadius: CGFloat) {
        current = chrome
        layer?.cornerRadius = cornerRadius
        wash.layer?.cornerRadius = cornerRadius
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch chrome {
        case .none:
            isHidden = true
            badgeView.isHidden = true
            deselectButton.isHidden = true
            wash.layer?.backgroundColor = nil
            layer?.borderWidth = 0
            layer?.borderColor = nil
        case .preview:
            isHidden = false
            badgeView.isHidden = false
            deselectButton.isHidden = false
            wash.layer?.backgroundColor = NSColor.black.withAlphaComponent(isDark ? 0.22 : 0.12).cgColor
            layer?.borderWidth = 1.5
            layer?.borderColor = LaughTheme.interactiveAccent.withAlphaComponent(isDark ? 0.55 : 0.45).cgColor
            refreshDeselectButtonAppearance()
        case .selected:
            isHidden = false
            badgeView.isHidden = false
            deselectButton.isHidden = false
            wash.layer?.backgroundColor = NSColor.black.withAlphaComponent(isDark ? 0.28 : 0.14).cgColor
            layer?.borderWidth = 1.5
            layer?.borderColor = LaughTheme.interactiveAccent.withAlphaComponent(isDark ? 0.70 : 0.55).cgColor
            refreshDeselectButtonAppearance()
        }
    }

    private func refreshDeselectButtonAppearance() {
        if let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Deselect") {
            let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            checkView.image = image.withSymbolConfiguration(config)
        }
        checkView.contentTintColor = .white
        checkView.imageScaling = .scaleProportionallyDown
        badgeView.layer?.backgroundColor = LaughTheme.interactiveAccent.cgColor
        badgeView.layer?.borderWidth = 1.5
        badgeView.layer?.borderColor = NSColor.white.cgColor
        badgeView.layer?.cornerRadius = badgeSide / 2
    }

    @objc private func deselectPressed() {
        onDeselect?()
    }
}

/// Thumbnail that aspect-fills (Gallery cover) or fits (Grid / placeholders).
private final class LibraryCoverImageView: NSView {
    private var displayedImage: NSImage?
    private var fillsBounds = false
    private var placeholderTint: NSColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspect
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        refreshContents()
    }

    func setFillMode(_ fills: Bool, placeholderBackground: NSColor?) {
        fillsBounds = fills
        layer?.backgroundColor = placeholderBackground?.cgColor
        layer?.contentsGravity = fills ? .resizeAspectFill : .resizeAspect
        refreshContents()
    }

    func setPhoto(_ image: NSImage) {
        displayedImage = image
        placeholderTint = nil
        refreshContents()
    }

    func setPlaceholderSymbol(_ image: NSImage, tint: NSColor) {
        displayedImage = image
        placeholderTint = tint
        refreshContents()
    }

    func clearImage() {
        displayedImage = nil
        placeholderTint = nil
        layer?.contents = nil
    }

    private func refreshContents() {
        guard let displayedImage else {
            layer?.contents = nil
            return
        }
        let scale = layer?.contentsScale ?? 2
        if let placeholderTint {
            let tinted = displayedImage.copy() as? NSImage ?? displayedImage
            tinted.isTemplate = true
            let size = tinted.size
            let rendered = NSImage(size: size, flipped: false) { rect in
                placeholderTint.set()
                tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                return true
            }
            layer?.contentsGravity = .center
            layer?.contents = rendered.layerContents(forContentsScale: scale)
            return
        }
        layer?.contentsGravity = fillsBounds ? .resizeAspectFill : .resizeAspect
        layer?.contents = displayedImage.layerContents(forContentsScale: scale)
    }
}

private final class LibraryMediaGridItem: NSCollectionViewItem, LibrarySelectableGridItem {
    static let reuseID = NSUserInterfaceItemIdentifier("LibraryMediaGridItem")

    private let cardView = LibraryFolderCardChromeView()
    private let thumbnailView = LibraryCoverImageView()
    private let playButton = NSImageView()
    private let episodeBadgeView = NSView()
    private let episodeBadgeLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let metaRow = NSStackView()
    private let kindDotLabel = LibraryMediaKindDotLabel()
    private let metaLabel = NSTextField(labelWithString: "")
    private let selectionChrome = LibraryTileSelectionChromeView()
    var onDeselectRequested: (() -> Void)?
    private var thumbHeightConstraint: NSLayoutConstraint?
    private var thumbAspectConstraint: NSLayoutConstraint?
    private var thumbBottomConstraint: NSLayoutConstraint?
    private var thumbTopConstraint: NSLayoutConstraint?
    private var thumbLeadingConstraint: NSLayoutConstraint?
    private var thumbTrailingConstraint: NSLayoutConstraint?
    private var nameTopConstraint: NSLayoutConstraint?
    private var nameMetaSpacingConstraint: NSLayoutConstraint?
    private var metaBottomConstraint: NSLayoutConstraint?
    private var nameLeadingConstraint: NSLayoutConstraint?
    private var nameTrailingConstraint: NSLayoutConstraint?
    private var showsTitle = true
    private var hoverBorderEnabled = false
    private var selectionState: LibraryTileSelectionChrome = .none
    private var loadToken = UUID()
    private var hasPhoto = false
    private var configuredFormat = LibraryMediaFormatBadge(title: "Image", family: .photo)
    override func loadView() {
        let host = LibraryTileHoverHostView()
        host.onHoverChange = { [weak self] hovered in
            self?.setHovered(hovered)
        }
        view = host
        view.wantsLayer = true
        view.layer?.masksToBounds = false
        view.layer?.borderWidth = 0

        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 6
        cardView.layer?.masksToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.onAppearanceChange = { [weak self] in
            self?.applyCardChrome()
        }

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.layer?.cornerRadius = 4
        thumbnailView.setFillMode(true, placeholderBackground: NSColor.quaternaryLabelColor)

        if let play = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Play") {
            let config = NSImage.SymbolConfiguration(pointSize: 30, weight: .regular)
            playButton.image = play.withSymbolConfiguration(config)
            playButton.contentTintColor = .white
        }
        playButton.translatesAutoresizingMaskIntoConstraints = false

        episodeBadgeView.wantsLayer = true
        episodeBadgeView.layer?.cornerRadius = 4
        episodeBadgeView.layer?.masksToBounds = true
        episodeBadgeView.translatesAutoresizingMaskIntoConstraints = false
        episodeBadgeView.isHidden = true

        episodeBadgeLabel.isEditable = false
        episodeBadgeLabel.isBordered = false
        episodeBadgeLabel.isBezeled = false
        episodeBadgeLabel.drawsBackground = false
        episodeBadgeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        episodeBadgeLabel.textColor = .white
        episodeBadgeLabel.alignment = .center
        episodeBadgeLabel.maximumNumberOfLines = 1
        episodeBadgeLabel.lineBreakMode = .byClipping
        episodeBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        episodeBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        episodeBadgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        configureLibraryGridNameLabel(nameLabel, fontSize: 12)
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.alignment = .center
        nameLabel.maximumNumberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        nameLabel.setContentHuggingPriority(.required, for: .vertical)

        kindDotLabel.translatesAutoresizingMaskIntoConstraints = false

        metaLabel.isEditable = false
        metaLabel.isBordered = false
        metaLabel.isBezeled = false
        metaLabel.drawsBackground = false
        metaLabel.font = .systemFont(ofSize: 11, weight: .regular)
        metaLabel.textColor = .tertiaryLabelColor
        metaLabel.alignment = .left
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.maximumNumberOfLines = 1
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        metaLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        metaLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        metaLabel.setContentHuggingPriority(.required, for: .vertical)

        metaRow.orientation = .horizontal
        metaRow.alignment = .centerY
        metaRow.spacing = 6
        metaRow.translatesAutoresizingMaskIntoConstraints = false
        metaRow.setViews([kindDotLabel, metaLabel], in: .leading)
        metaRow.setHuggingPriority(.required, for: .vertical)
        metaRow.setContentHuggingPriority(.required, for: .vertical)

        selectionChrome.translatesAutoresizingMaskIntoConstraints = false
        selectionChrome.onDeselect = { [weak self] in
            self?.onDeselectRequested?()
        }
        host.interactiveChromeHitTest = { [weak selectionChrome] local in
            selectionChrome?.hitTest(local)
        }

        view.addSubview(cardView)
        cardView.addSubview(thumbnailView)
        cardView.addSubview(playButton)
        thumbnailView.addSubview(episodeBadgeView)
        episodeBadgeView.addSubview(episodeBadgeLabel)
        cardView.addSubview(nameLabel)
        cardView.addSubview(metaRow)
        view.addSubview(selectionChrome)

        let thumbHeight = thumbnailView.heightAnchor.constraint(equalToConstant: 84)
        let thumbAspect = thumbnailView.heightAnchor.constraint(equalTo: thumbnailView.widthAnchor)
        let thumbTop = thumbnailView.topAnchor.constraint(
            equalTo: cardView.topAnchor,
            constant: LibraryGridCardLayout.previewTop
        )
        let thumbLeading = thumbnailView.leadingAnchor.constraint(
            equalTo: cardView.leadingAnchor,
            constant: LibraryGridCardLayout.previewInset
        )
        let thumbTrailing = thumbnailView.trailingAnchor.constraint(
            equalTo: cardView.trailingAnchor,
            constant: -LibraryGridCardLayout.previewInset
        )
        let thumbBottom = thumbnailView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
        let nameTop = nameLabel.topAnchor.constraint(
            equalTo: thumbnailView.bottomAnchor,
            constant: LibraryGridCardLayout.nameTop
        )
        let nameMetaSpacing = metaRow.topAnchor.constraint(
            equalTo: nameLabel.bottomAnchor,
            constant: LibraryGridCardLayout.nameMetaSpacing
        )
        let metaBottom = metaRow.bottomAnchor.constraint(
            equalTo: cardView.bottomAnchor,
            constant: -LibraryGridCardLayout.metaBottom
        )
        let nameLeading = nameLabel.leadingAnchor.constraint(
            equalTo: cardView.leadingAnchor,
            constant: LibraryGridCardLayout.labelInset
        )
        let nameTrailing = nameLabel.trailingAnchor.constraint(
            equalTo: cardView.trailingAnchor,
            constant: -LibraryGridCardLayout.labelInset
        )
        thumbHeightConstraint = thumbHeight
        thumbAspectConstraint = thumbAspect
        thumbTopConstraint = thumbTop
        thumbLeadingConstraint = thumbLeading
        thumbTrailingConstraint = thumbTrailing
        thumbBottomConstraint = thumbBottom
        nameTopConstraint = nameTop
        nameMetaSpacingConstraint = nameMetaSpacing
        metaBottomConstraint = metaBottom
        nameLeadingConstraint = nameLeading
        nameTrailingConstraint = nameTrailing
        thumbBottom.isActive = false
        thumbHeight.isActive = false
        thumbAspect.isActive = true

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: view.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            thumbTop,
            thumbLeading,
            thumbTrailing,
            thumbAspect,
            playButton.centerXAnchor.constraint(equalTo: thumbnailView.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),

            episodeBadgeView.trailingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: -5),
            episodeBadgeView.bottomAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: -5),
            episodeBadgeLabel.topAnchor.constraint(equalTo: episodeBadgeView.topAnchor, constant: 2),
            episodeBadgeLabel.bottomAnchor.constraint(equalTo: episodeBadgeView.bottomAnchor, constant: -2),
            episodeBadgeLabel.leadingAnchor.constraint(equalTo: episodeBadgeView.leadingAnchor, constant: 5),
            episodeBadgeLabel.trailingAnchor.constraint(equalTo: episodeBadgeView.trailingAnchor, constant: -5),

            nameTop,
            nameLeading,
            nameTrailing,
            nameMetaSpacing,
            metaRow.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            metaRow.leadingAnchor.constraint(
                greaterThanOrEqualTo: cardView.leadingAnchor,
                constant: LibraryGridCardLayout.labelInset
            ),
            metaRow.trailingAnchor.constraint(
                lessThanOrEqualTo: cardView.trailingAnchor,
                constant: -LibraryGridCardLayout.labelInset
            ),
            metaBottom,

            selectionChrome.topAnchor.constraint(equalTo: view.topAnchor),
            selectionChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectionChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectionChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        applyCardChrome()
        applyEpisodeBadgeChrome()
    }

    func applySelectionChrome(_ chrome: LibraryTileSelectionChrome) {
        selectionState = chrome
        let radius = showsTitle ? (cardView.layer?.cornerRadius ?? 6) : 4
        selectionChrome.apply(chrome, appearance: view.effectiveAppearance, cornerRadius: radius)
        if chrome != .none {
            view.layer?.borderWidth = 0
            view.layer?.borderColor = nil
            cardView.layer?.borderWidth = showsTitle ? 1 : 0
        }
    }

    func applyMetrics(_ metrics: LibraryBrowseTileMetrics) {
        showsTitle = metrics.showsTitle
        hoverBorderEnabled = true
        nameLabel.isHidden = !metrics.showsTitle
        metaRow.isHidden = !metrics.showsTitle
        setHovered(false)
        if metrics.showsTitle {
            // Grid: square preview + title/meta — same card behaviour as folders.
            thumbHeightConstraint?.isActive = false
            thumbAspectConstraint?.isActive = true
            thumbBottomConstraint?.isActive = false
            thumbTopConstraint?.constant = LibraryGridCardLayout.previewTop
            thumbLeadingConstraint?.constant = LibraryGridCardLayout.previewInset
            thumbTrailingConstraint?.constant = -LibraryGridCardLayout.previewInset
            nameTopConstraint?.isActive = true
            nameTopConstraint?.constant = LibraryGridCardLayout.nameTop
            nameMetaSpacingConstraint?.isActive = true
            nameMetaSpacingConstraint?.constant = LibraryGridCardLayout.nameMetaSpacing
            metaBottomConstraint?.isActive = true
            metaBottomConstraint?.constant = -LibraryGridCardLayout.metaBottom
            nameLeadingConstraint?.constant = LibraryGridCardLayout.labelInset
            nameTrailingConstraint?.constant = -LibraryGridCardLayout.labelInset
            nameLabel.alignment = .center
            nameLabel.maximumNumberOfLines = 1
            nameLabel.lineBreakMode = .byTruncatingTail
            nameLabel.cell?.wraps = false
            nameLabel.cell?.usesSingleLineMode = true
            nameLabel.cell?.truncatesLastVisibleLine = true
            nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
            metaLabel.alignment = .center
            metaLabel.maximumNumberOfLines = 1
            metaLabel.font = .systemFont(ofSize: 11, weight: .regular)
            cardView.layer?.cornerRadius = 6
            cardView.layer?.masksToBounds = true
            thumbnailView.layer?.cornerRadius = 4
            thumbnailView.setFillMode(
                true,
                placeholderBackground: LaughTheme.libraryContentBackground(appearance: view.effectiveAppearance)
            )
        } else {
            // Gallery (~16:9): image covers the whole tile.
            thumbAspectConstraint?.isActive = false
            thumbHeightConstraint?.isActive = false
            thumbBottomConstraint?.isActive = true
            thumbTopConstraint?.constant = 0
            thumbLeadingConstraint?.constant = 0
            thumbTrailingConstraint?.constant = 0
            nameTopConstraint?.isActive = false
            nameMetaSpacingConstraint?.isActive = false
            metaBottomConstraint?.isActive = false
            cardView.layer?.cornerRadius = 4
            cardView.layer?.masksToBounds = true
            thumbnailView.layer?.cornerRadius = 4
            thumbnailView.setFillMode(
                true,
                placeholderBackground: LaughTheme.libraryContentBackground(appearance: view.effectiveAppearance)
            )
        }
        applyCardChrome()
        let playSize = max(26, min(metrics.thumbHeight * 0.22, 42))
        if let play = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Play") {
            let config = NSImage.SymbolConfiguration(pointSize: playSize, weight: .regular)
            playButton.image = play.withSymbolConfiguration(config)
            playButton.contentTintColor = .white
        }
    }

    private func applyCardChrome() {
        let appearance = view.effectiveAppearance
        if showsTitle {
            let card = LaughTheme.librarySidebarBackground(appearance: appearance)
            let content = LaughTheme.libraryContentBackground(appearance: appearance)
            cardView.layer?.backgroundColor = card.cgColor
            cardView.layer?.borderWidth = 1
            cardView.layer?.borderColor = NSColor.separatorColor.cgColor
            thumbnailView.layer?.borderWidth = 1
            thumbnailView.layer?.borderColor = NSColor.separatorColor.cgColor
            thumbnailView.layer?.backgroundColor = content.cgColor
            nameLabel.textColor = .labelColor
            metaLabel.textColor = .tertiaryLabelColor
            kindDotLabel.apply(badge: configuredFormat, appearance: appearance)
        } else {
            cardView.layer?.backgroundColor = NSColor.clear.cgColor
            cardView.layer?.borderWidth = 0
            cardView.layer?.borderColor = nil
            thumbnailView.layer?.borderWidth = 0
            thumbnailView.layer?.borderColor = nil
        }
        applyEpisodeBadgeChrome()
    }

    private func applyEpisodeBadgeChrome() {
        episodeBadgeView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        episodeBadgeView.layer?.borderWidth = 0
        episodeBadgeLabel.textColor = .white
    }

    private func setHovered(_ hovered: Bool) {
        guard selectionState == .none else { return }
        guard hoverBorderEnabled else {
            view.layer?.borderWidth = 0
            view.layer?.borderColor = nil
            return
        }
        if showsTitle {
            view.layer?.borderWidth = 0
            view.layer?.borderColor = nil
            let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if hovered {
                cardView.layer?.borderWidth = 1.5
                cardView.layer?.borderColor = (isDark
                    ? NSColor.white.withAlphaComponent(0.85)
                    : NSColor.labelColor.withAlphaComponent(0.55)).cgColor
            } else {
                cardView.layer?.borderWidth = 1
                cardView.layer?.borderColor = NSColor.separatorColor.cgColor
            }
            return
        }

        view.layer?.borderWidth = hovered ? 1.5 : 0
        if hovered {
            view.layer?.borderColor = NSColor.white.withAlphaComponent(0.95).cgColor
        } else {
            view.layer?.borderColor = nil
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadToken = UUID()
        hasPhoto = false
        thumbnailView.clearImage()
        nameLabel.stringValue = ""
        metaLabel.stringValue = ""
        episodeBadgeLabel.stringValue = ""
        episodeBadgeView.isHidden = true
        configuredFormat = LibraryMediaFormatBadge(title: "Image", family: .photo)
        view.toolTip = nil
        onDeselectRequested = nil
        applySelectionChrome(.none)
        setHovered(false)
        playButton.isHidden = true
    }

    func configure(name: String, kind: DroppedMediaKind, fileSize: Int64?, url: URL) {
        nameLabel.stringValue = name
        view.toolTip = nil
        playButton.isHidden = kind != .video
        configuredFormat = MediaKindDetector.formatBadge(for: url)
        kindDotLabel.apply(badge: configuredFormat, appearance: view.effectiveAppearance)
        metaLabel.stringValue = LibraryMediaMetaFormatting.sizeLabel(fileSize)
        if let marker = EpisodeMarkerParser.parse(from: url.lastPathComponent) {
            episodeBadgeLabel.stringValue = marker.badgeText
            episodeBadgeView.isHidden = false
            applyEpisodeBadgeChrome()
        } else {
            episodeBadgeLabel.stringValue = ""
            episodeBadgeView.isHidden = true
        }
        guard !hasPhoto else { return }
        let symbol = kind == .video ? "film" : "photo"
        if let placeholder = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
            if let configured = placeholder.withSymbolConfiguration(config) {
                thumbnailView.setPlaceholderSymbol(configured, tint: .tertiaryLabelColor)
            }
        }
    }

    func setThumbnail(_ image: NSImage?) {
        guard let image else { return }
        hasPhoto = true
        thumbnailView.setPhoto(image)
    }

    func loadThumbnail(
        for url: URL,
        kind: DroppedMediaKind,
        maxSide: CGFloat,
        indexPath: IndexPath,
        completion: @escaping (NSImage?, IndexPath) -> Void
    ) {
        let token = loadToken
        let scale = view.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? MediaThumbnailGenerator.defaultScreenScale()
        DispatchQueue.global(qos: .utility).async {
            let image = MediaThumbnailGenerator.thumbnail(
                for: url,
                kind: kind,
                maxSide: maxSide,
                screenScale: scale
            )
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
