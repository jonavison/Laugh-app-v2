import AppKit
import AVFoundation

private enum SidebarMetrics {
    static let edgeInset: CGFloat = 16
    static let rowTextInset: CGFloat = 10
}

// MARK: - Sidebar (LibraryRoot list)

final class LibrarySidebarView: NSVisualEffectView, NSTableViewDelegate, NSTableViewDataSource {
    static let width: CGFloat = 220

    private enum Metrics {
        static let topInset: CGFloat = 18
        static let bottomInset: CGFloat = 12
        static let listToToolbarSpacing: CGFloat = 10
        static let rowSpacing: CGFloat = LaughTheme.Sidebar.menuItemGap
        static let rowHeight: CGFloat = LaughTheme.Sidebar.MenuButton.rowHeight
        static let sectionHeaderRowHeight: CGFloat = LaughTheme.Sidebar.GroupLabel.rowHeight
        static let recentFileRowHeight: CGFloat = LaughTheme.Sidebar.MenuSubButton.rowHeight
        static let librarySeparatorRowHeight: CGFloat = 10
    }

    private let controller: MediaLibraryController
    private let scroll = NSScrollView()
    private let table = NSTableView()
    private let toolbar = NSStackView()
    private let trailingDivider = NSBox()
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
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
    }

    private func configureSubviews() {
        configureToolbarButton(addFolderButton, symbol: "plus", toolTip: "Add folder…")
        configureToolbarButton(removeFolderButton, symbol: "minus", toolTip: "Remove selected folder")
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

        trailingDivider.boxType = .separator
        trailingDivider.translatesAutoresizingMaskIntoConstraints = false

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
        case .recentHeader, .root:
            return Metrics.rowHeight
        case .librarySectionHeader:
            return Metrics.sectionHeaderRowHeight
        case .librarySeparator:
            return Metrics.librarySeparatorRowHeight
        case .recentItem:
            return Metrics.recentFileRowHeight
        }
    }

    private func configureToolbarButton(_ button: NSButton, symbol: String, toolTip: String) {
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.toolTip = toolTip
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip) {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
            button.image?.isTemplate = true
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
            cell.configure(title: file.url.lastPathComponent, style: .menuSubButton, toolTip: file.url.path)
            return cell
        case .recentHeader:
            let cell = tableView.makeView(withIdentifier: SidebarListCell.reuseID, owner: self) as? SidebarListCell ?? SidebarListCell()
            cell.configure(
                title: "Recents",
                style: .menuButton,
                toolTip: "Show all recently opened files",
                symbol: "clock.fill"
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
                style: .groupLabel,
                toolTip: "Library folders",
                symbol: "folder.fill"
            )
            return cell
        case .root(let root):
            let cell = tableView.makeView(withIdentifier: SidebarListCell.reuseID, owner: self) as? SidebarListCell ?? SidebarListCell()
            cell.configure(title: root.displayName, style: .menuButton, toolTip: root.directoryURL.path)
            return cell
        }
    }
}

private final class SidebarGradientSeparatorView: NSView {
    static let reuseID = NSUserInterfaceItemIdentifier("SidebarGradientSeparatorView")

    private let gradientLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
        wantsLayer = true
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(gradientLayer)
        updateGradientColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let lineHeight: CGFloat = 1 / scale
        let horizontalInset = SidebarMetrics.rowTextInset
        gradientLayer.frame = CGRect(
            x: horizontalInset,
            y: (bounds.height - lineHeight) / 2,
            width: max(0, bounds.width - horizontalInset * 2),
            height: lineHeight
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateGradientColors()
    }

    private func updateGradientColors() {
        let gray = LaughTheme.sidebarSeparatorGradientEnd
        gradientLayer.colors = [
            LaughTheme.sidebarSeparatorGradientStart.cgColor,
            gray.cgColor,
            gray.cgColor
        ]
        // Brief teal at the leading edge, then gray for the rest of the line.
        gradientLayer.locations = [0, 0.12, 1.0]
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

    func configure(title: String, style: Style, toolTip: String, symbol: String? = nil) {
        nameLabel.stringValue = title
        self.style = style
        self.toolTip = toolTip
        applySectionIcon(symbol: symbol)
        applyRowMetrics()
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
            iconView.isHidden = true
            iconView.image = nil
            contentRow.spacing = LaughTheme.Sidebar.MenuSubButton.gap
            applyContentInsets(
                leading: LaughTheme.Sidebar.MenuSubButton.contentLeadingInset,
                trailing: LaughTheme.Sidebar.MenuSubButton.paddingX
            )
        }
    }

    private func applyContentInsets(leading: CGFloat, trailing: CGFloat) {
        contentLeadingConstraint.constant = leading
        contentTrailingConstraint.constant = -trailing
    }

    private func applySectionIcon(symbol: String?) {
        guard style == .menuButton || style == .groupLabel,
              let symbol,
              let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        else {
            if style != .groupLabel {
                iconView.isHidden = true
                iconView.image = nil
            }
            return
        }
        let config = style == .groupLabel
            ? LaughTheme.Sidebar.GroupLabel.symbolConfiguration()
            : LaughTheme.Sidebar.MenuButton.symbolConfiguration()
        iconView.image = image.withSymbolConfiguration(config)
        iconView.image?.isTemplate = true
        iconView.isHidden = false
    }

    private func applyTextAppearance() {
        let selected = backgroundStyle == .emphasized
        switch style {
        case .menuButton:
            nameLabel.font = LaughTheme.Sidebar.MenuButton.labelFont
            LaughTheme.applySidebarSelectionLabelStyle(to: nameLabel, selected: selected, idleColor: .labelColor)
            if !iconView.isHidden {
                iconView.contentTintColor = selected ? .labelColor : .secondaryLabelColor
            }
        case .groupLabel:
            nameLabel.font = LaughTheme.Sidebar.GroupLabel.labelFont
            nameLabel.textColor = .secondaryLabelColor
            if !iconView.isHidden {
                iconView.contentTintColor = .secondaryLabelColor
            }
        case .menuSubButton:
            nameLabel.font = LaughTheme.Sidebar.MenuSubButton.labelFont
            LaughTheme.applySidebarSelectionLabelStyle(to: nameLabel, selected: selected, idleColor: .secondaryLabelColor)
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
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Select Recents or a folder")
    private let hintLabel = NSTextField(labelWithString: "Drop videos or images")
    private let borderLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35).cgColor

        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1.5
        borderLayer.lineDashPattern = [7, 5]
        borderLayer.strokeColor = NSColor.tertiaryLabelColor.cgColor
        layer?.addSublayer(borderLayer)

        if let image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: "Drop files") {
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

final class LibraryBrowseView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let controller: MediaLibraryController
    private let backButton = NSButton(title: "", target: nil, action: nil)
    private let forwardButton = NSButton(title: "", target: nil, action: nil)
    private let openButton = NSButton(title: "Open…", target: nil, action: nil)
    private let playAllButton = NSButton(title: "Play All", target: nil, action: nil)
    private let sortPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let gridScroll = NSScrollView()
    private let collectionView = LibraryGridCollectionView()
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
    var onOpenMediaPanel: (() -> Void)?
    var onPlayAll: (() -> Void)?
    var onContextAction: ((LibraryBrowseContextAction, LibraryBrowseEntry) -> Void)?

    init(controller: MediaLibraryController) {
        self.controller = controller
        super.init(frame: .zero)
        configureSubviews()
        activateLayout()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh() {
        thumbnailTasks.removeAll()
        backButton.isEnabled = controller.canGoBack
        forwardButton.isEnabled = controller.canGoForward
        collectionView.reloadData()
        recentListTable.reloadData()

        let showPlaceholder = controller.showsBrowsePlaceholder
        let showRecentList = controller.showsRecentList
        browsePlaceholder.isHidden = !showPlaceholder
        recentListScroll.isHidden = !showRecentList
        gridScroll.isHidden = showPlaceholder || showRecentList
        emptyLabel.isHidden = showPlaceholder || !controller.displayedEntries.isEmpty
        if !showPlaceholder {
            emptyLabel.stringValue = controller.emptyGridMessage
        }

        let hideBrowseToolbar = showRecentList
        backButton.isHidden = hideBrowseToolbar
        forwardButton.isHidden = hideBrowseToolbar
        openButton.isHidden = hideBrowseToolbar
        playAllButton.isHidden = hideBrowseToolbar || showPlaceholder
        sortPopUp.isHidden = hideBrowseToolbar || !controller.showsBrowseSortControl

        contentTopBelowToolbarConstraint?.isActive = !hideBrowseToolbar
        contentTopBelowViewConstraint?.isActive = hideBrowseToolbar
        if hideBrowseToolbar {
            updateContentTopInsetForRecents()
        }

        updateBreadcrumb()
        updateSortControl()
        playAllButton.isEnabled = controller.canPlayAllInBrowse
        playAllButton.isHidden = showPlaceholder
    }

    func reloadContent() {
        controller.reloadGrid()
        refresh()
    }

    private func configureSubviews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.35).cgColor

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

        sortPopUp.font = .systemFont(ofSize: 11)
        sortPopUp.controlSize = .small
        sortPopUp.translatesAutoresizingMaskIntoConstraints = false
        sortPopUp.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sortPopUp.cell?.lineBreakMode = .byTruncatingTail
        updateSortControl()

        let layout = NSCollectionViewGridLayout()
        layout.minimumItemSize = NSSize(width: 120, height: 124)
        layout.maximumItemSize = NSSize(width: 160, height: 140)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 10
        layout.margins = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
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
        addSubview(sortPopUp)
        addSubview(gridScroll)
        addSubview(recentListScroll)
        addSubview(breadcrumbStack)
        addSubview(emptyLabel)
        addSubview(browsePlaceholder)
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

            sortPopUp.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            sortPopUp.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            sortPopUp.leadingAnchor.constraint(greaterThanOrEqualTo: playAllButton.trailingAnchor, constant: 12),

            contentTopBelowToolbarConstraint!,
            gridScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridScroll.bottomAnchor.constraint(equalTo: breadcrumbStack.topAnchor, constant: -6),

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

    @objc private func recentListDoubleClicked() {
        openRecentListSelection()
    }

    private func openRecentListSelection() {
        let row = recentListTable.selectedRow
        guard row >= 0, let entry = controller.entry(at: IndexPath(item: row, section: 0)),
              case .media(let file) = entry.kind else { return }
        controller.openMedia(file)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        guard controller.showsRecentList else { return 0 }
        return controller.displayedEntries.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard tableView === recentListTable else { return nil }
        return tableView.makeView(withIdentifier: LibraryRecentListRowView.reuseID, owner: self) as? LibraryRecentListRowView
            ?? LibraryRecentListRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let entry = controller.entry(at: IndexPath(item: row, section: 0)),
              case .media(let file) = entry.kind else { return nil }
        let cell = tableView.makeView(
            withIdentifier: LibraryRecentListCell.reuseID,
            owner: self
        ) as? LibraryRecentListCell ?? LibraryRecentListCell()
        cell.configure(file: file)
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
        switch entry.kind {
        case .folder:
            let item = collectionView.makeItem(withIdentifier: LibraryFolderGridItem.reuseID, for: indexPath) as! LibraryFolderGridItem
            item.configure(name: entry.name)
            return item
        case .media(let file):
            let item = collectionView.makeItem(withIdentifier: LibraryMediaGridItem.reuseID, for: indexPath) as! LibraryMediaGridItem
            item.configure(name: entry.name, kind: file.kind)
            item.loadThumbnail(for: file.url, kind: file.kind, indexPath: indexPath) { [weak self, weak item] image, path in
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

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first else { return }
        let entry = controller.displayedEntries[indexPath.item]
        collectionView.deselectItems(at: indexPaths)
        switch entry.kind {
        case .folder(let url):
            controller.openFolder(url)
        case .media(let file):
            controller.openMedia(file)
        }
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

private final class LibraryGridItemView: NSView {
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

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = LibraryGridItemView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let folder = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder") {
            let config = NSImage.SymbolConfiguration(pointSize: 46, weight: .regular)
            iconView.image = folder.withSymbolConfiguration(config)
            iconView.contentTintColor = .secondaryLabelColor
        }

        configureLibraryGridNameLabel(nameLabel, fontSize: 11)

        view.addSubview(iconView)
        view.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 68),
            iconView.heightAnchor.constraint(equalToConstant: 68),
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -6)
        ])
    }

    func configure(name: String) {
        nameLabel.stringValue = name
    }
}

private final class LibraryMediaGridItem: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("LibraryMediaGridItem")

    private let thumbnailView = NSImageView()
    private let playButton = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var loadToken = UUID()

    override func loadView() {
        view = LibraryGridItemView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true

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

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumbnailView.heightAnchor.constraint(equalToConstant: 84),
            playButton.centerXAnchor.constraint(equalTo: thumbnailView.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: thumbnailView.centerYAnchor),
            nameLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -4)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadToken = UUID()
        thumbnailView.image = nil
        nameLabel.stringValue = ""
        playButton.isHidden = true
    }

    func configure(name: String, kind: DroppedMediaKind) {
        nameLabel.stringValue = name
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

    func loadThumbnail(for url: URL, kind: DroppedMediaKind, indexPath: IndexPath, completion: @escaping (NSImage?, IndexPath) -> Void) {
        let token = loadToken
        DispatchQueue.global(qos: .utility).async {
            let image = Self.generateThumbnail(for: url, kind: kind)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadToken == token else { return }
                completion(image, indexPath)
            }
        }
    }

    private static func generateThumbnail(for url: URL, kind: DroppedMediaKind) -> NSImage? {
        if kind == .image {
            guard let source = NSImage(contentsOf: url) else { return nil }
            return downsample(source, maxSide: 200)
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return downsample(image, maxSide: 200)
    }

    private static func downsample(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let size = image.size
        let scale = min(maxSide / max(size.width, 1), maxSide / max(size.height, 1), 1)
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let output = NSImage(size: target)
        output.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        output.unlockFocus()
        return output
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
        toolTip = file.url.path
        let symbol = file.kind == .video ? "film" : "photo"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iconView.image = image.withSymbolConfiguration(LaughTheme.Sidebar.MenuButton.symbolConfiguration())
            iconView.image?.isTemplate = true
        }
    }
}
