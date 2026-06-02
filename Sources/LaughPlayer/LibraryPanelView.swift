import AppKit
import AVFoundation

private enum SidebarMetrics {
    static let edgeInset: CGFloat = 16
    static let rowTextInset: CGFloat = 10
    static let selectionInset: CGFloat = 6
    static let selectionCornerRadius: CGFloat = 6
}

// MARK: - Sidebar (LibraryRoot list)

final class LibrarySidebarView: NSVisualEffectView, NSTableViewDelegate, NSTableViewDataSource {
    static let width: CGFloat = 220

    private enum Metrics {
        static let topInset: CGFloat = 14
        static let bottomInset: CGFloat = 12
        static let titleToListSpacing: CGFloat = 10
        static let listToToolbarSpacing: CGFloat = 10
        static let rowSpacing: CGFloat = 1
        static let rowHeight: CGFloat = 32
        static let sectionHeaderRowHeight: CGFloat = 28
        static let recentFileRowHeight: CGFloat = 22
    }

    private let controller: MediaLibraryController
    private let titleLabel = NSTextField(labelWithString: "Library")
    private let scroll = NSScrollView()
    private let table = NSTableView()
    private let toolbar = NSStackView()
    private let trailingDivider = NSBox()
    private let addFolderButton = NSButton(title: "", target: nil, action: nil)
    private let removeFolderButton = NSButton(title: "", target: nil, action: nil)
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

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

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

        addSubview(titleLabel)
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

    private func activateLayout() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.topInset),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SidebarMetrics.edgeInset + SidebarMetrics.rowTextInset),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SidebarMetrics.edgeInset),

            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Metrics.titleToListSpacing),
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
        case .recentHeader:
            return Metrics.sectionHeaderRowHeight
        case .recentItem:
            return Metrics.recentFileRowHeight
        case .root:
            return Metrics.rowHeight
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
        table.selectRowIndexes(IndexSet(integer: controller.selectedSidebarRow), byExtendingSelection: false)
        removeFolderButton.isEnabled = controller.canRemoveSelectedRoot
        needsLayout = true
        updateScrollerVisibility()
    }

    @objc private func selectionChanged() {
        guard !suppressSelectionAction else { return }
        let row = table.selectedRow
        guard row >= 0 else { return }
        controller.selectSidebarRow(row)
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
        case .recentHeader:
            let cell = tableView.makeView(withIdentifier: SidebarListCell.reuseID, owner: self) as? SidebarListCell ?? SidebarListCell()
            cell.configure(title: "Recents", style: .sectionHeader, toolTip: "Recently opened files")
            return cell
        case .recentItem(let file):
            let cell = tableView.makeView(withIdentifier: SidebarListCell.reuseID, owner: self) as? SidebarListCell ?? SidebarListCell()
            cell.configure(title: file.url.lastPathComponent, style: .recentFile, toolTip: file.url.path)
            return cell
        case .root(let root):
            let cell = tableView.makeView(withIdentifier: SidebarListCell.reuseID, owner: self) as? SidebarListCell ?? SidebarListCell()
            cell.configure(title: root.displayName, style: .folder, toolTip: root.directoryURL.path)
            return cell
        }
    }
}

private final class SidebarListCell: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("SidebarListCell")

    enum Style {
        case sectionHeader
        case recentFile
        case folder
    }

    private let nameLabel = NSTextField(labelWithString: "")
    private var style: Style = .folder

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID

        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(nameLabel)
        textField = nameLabel

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SidebarMetrics.rowTextInset),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SidebarMetrics.rowTextInset),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
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

    func configure(title: String, style: Style, toolTip: String) {
        nameLabel.stringValue = title
        self.style = style
        self.toolTip = toolTip
        applyTextAppearance()
    }

    private func applyTextAppearance() {
        let emphasized = backgroundStyle == .emphasized

        switch style {
        case .sectionHeader:
            nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            nameLabel.textColor = emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
        case .recentFile:
            nameLabel.font = .systemFont(ofSize: 11, weight: .regular)
            nameLabel.textColor = emphasized ? .alternateSelectedControlTextColor : .tertiaryLabelColor
        case .folder:
            nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
            nameLabel.textColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
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
        let rect = bounds.insetBy(
            dx: SidebarMetrics.selectionInset,
            dy: 2
        )
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: SidebarMetrics.selectionCornerRadius,
            yRadius: SidebarMetrics.selectionCornerRadius
        )
        NSColor.selectedContentBackgroundColor.setFill()
        path.fill()
    }
}

// MARK: - Browse grid (main content area)

final class LibraryBrowseView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private let controller: MediaLibraryController
    private let backButton = NSButton(title: "", target: nil, action: nil)
    private let forwardButton = NSButton(title: "", target: nil, action: nil)
    private let openButton = NSButton(title: "Open…", target: nil, action: nil)
    private let sortPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let gridScroll = NSScrollView()
    private let collectionView = NSCollectionView()
    private let breadcrumbStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "Empty folder")
    private var thumbnailTasks: [IndexPath: URL] = [:]
    var onOpenMediaPanel: (() -> Void)?

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
        emptyLabel.isHidden = !controller.displayedEntries.isEmpty
        emptyLabel.stringValue = controller.emptyGridMessage
        updateBreadcrumb()
        selectSortInMenu(controller.browseSort)
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

        for option in LibraryBrowseSort.allOptions() {
            sortPopUp.addItem(withTitle: option.menuTitle)
        }
        sortPopUp.target = self
        sortPopUp.action = #selector(sortChanged)
        sortPopUp.font = .systemFont(ofSize: 11)
        sortPopUp.controlSize = .small
        sortPopUp.translatesAutoresizingMaskIntoConstraints = false
        sortPopUp.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sortPopUp.cell?.lineBreakMode = .byTruncatingTail
        selectSortInMenu(controller.browseSort)

        let layout = NSCollectionViewGridLayout()
        layout.minimumItemSize = NSSize(width: 120, height: 112)
        layout.maximumItemSize = NSSize(width: 160, height: 132)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 10
        layout.margins = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.delegate = self
        collectionView.dataSource = self
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

        breadcrumbStack.orientation = .horizontal
        breadcrumbStack.alignment = .centerY
        breadcrumbStack.spacing = 2
        breadcrumbStack.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(backButton)
        addSubview(forwardButton)
        addSubview(openButton)
        addSubview(sortPopUp)
        addSubview(gridScroll)
        addSubview(breadcrumbStack)
        addSubview(emptyLabel)
    }

    private func activateLayout() {
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            forwardButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),

            openButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            openButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 12),

            sortPopUp.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            sortPopUp.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            sortPopUp.leadingAnchor.constraint(greaterThanOrEqualTo: openButton.trailingAnchor, constant: 12),

            gridScroll.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 12),
            gridScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridScroll.bottomAnchor.constraint(equalTo: breadcrumbStack.topAnchor, constant: -6),

            emptyLabel.centerXAnchor.constraint(equalTo: gridScroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: gridScroll.centerYAnchor),

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

    private func selectSortInMenu(_ sort: LibraryBrowseSort) {
        let options = LibraryBrowseSort.allOptions()
        if let index = options.firstIndex(of: sort) {
            sortPopUp.selectItem(at: index)
        }
    }

    @objc private func backPressed() { controller.goBack() }
    @objc private func forwardPressed() { controller.goForward() }
    @objc private func openPressed() { onOpenMediaPanel?() }

    @objc private func sortChanged() {
        let options = LibraryBrowseSort.allOptions()
        let index = sortPopUp.indexOfSelectedItem
        guard index >= 0, index < options.count else { return }
        controller.setSort(options[index])
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
}

// MARK: - Grid items

private final class LibraryFolderGridItem: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("LibraryFolderGridItem")

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let folder = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder") {
            let config = NSImage.SymbolConfiguration(pointSize: 46, weight: .regular)
            iconView.image = folder.withSymbolConfiguration(config)
            iconView.contentTintColor = .secondaryLabelColor
        }

        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 2
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(iconView)
        view.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72),
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
        view = NSView()
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

        nameLabel.font = .systemFont(ofSize: 10)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 2
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(thumbnailView)
        view.addSubview(playButton)
        view.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumbnailView.heightAnchor.constraint(equalToConstant: 88),
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
