import AppKit

struct PlaybackQueueItem: Equatable {
    let url: URL
    let kind: DroppedMediaKind
}

struct PlaybackQueueListRow {
    let sectionTitle: String
    let fileName: String
    /// When set, choosing the row starts this queued item.
    let queueItem: PlaybackQueueItem?
}

final class PlaybackQueueListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private enum Metrics {
        static let rowHeight: CGFloat = 48
        static let contentInset: CGFloat = 12
        static let popoverWidth: CGFloat = 312
        static let maxHeight: CGFloat = 340
        static let minHeight: CGFloat = 96
    }

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var rows: [PlaybackQueueListRow] = []

    var onSelectQueueItem: ((PlaybackQueueItem) -> Void)?

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = Metrics.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.backgroundColor = .clear
        tableView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: Metrics.contentInset,
            left: Metrics.contentInset,
            bottom: Metrics.contentInset,
            right: Metrics.contentInset
        )
        scrollView.scrollerInsets = scrollView.contentInsets

        view = NSView(frame: NSRect(x: 0, y: 0, width: Metrics.popoverWidth, height: Metrics.minHeight))
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func setRows(_ rows: [PlaybackQueueListRow]) {
        self.rows = rows
        tableView.reloadData()

        let count = CGFloat(max(rows.count, 1))
        let spacing = tableView.intercellSpacing.height
        let rowsHeight = count * Metrics.rowHeight + max(0, count - 1) * spacing
        let chrome = Metrics.contentInset * 2
        let height = min(Metrics.maxHeight, max(Metrics.minHeight, rowsHeight + chrome))
        preferredContentSize = NSSize(width: Metrics.popoverWidth, height: height)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView.makeView(withIdentifier: QueueTableRowView.reuseID, owner: self) as? QueueTableRowView
            ?? QueueTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(
            withIdentifier: NSUserInterfaceItemIdentifier("QueueListCell"),
            owner: self
        ) as? QueueListCellView ?? QueueListCellView()

        let entry = rows[row]
        cell.configure(sectionTitle: entry.sectionTitle, fileName: entry.fileName)
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        rows[row].queueItem != nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < rows.count, let item = rows[row].queueItem else { return }
        onSelectQueueItem?(item)
        tableView.deselectAll(nil)
    }
}

private final class QueueListCellView: NSTableCellView {
    private let sectionLabel = NSTextField(labelWithString: "")
    private let fileLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("QueueListCell")

        sectionLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        sectionLabel.textColor = .secondaryLabelColor
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionLabel.setContentHuggingPriority(.required, for: .vertical)

        fileLabel.font = .systemFont(ofSize: 13)
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.translatesAutoresizingMaskIntoConstraints = false
        fileLabel.setContentHuggingPriority(.required, for: .vertical)

        addSubview(sectionLabel)
        addSubview(fileLabel)
        textField = fileLabel

        NSLayoutConstraint.activate([
            sectionLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            sectionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            sectionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            fileLabel.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 2),
            fileLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            fileLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            fileLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applySelectionColors() }
    }

    func configure(sectionTitle: String, fileName: String) {
        sectionLabel.stringValue = sectionTitle
        fileLabel.stringValue = fileName
        applySelectionColors()
    }

    private func applySelectionColors() {
        let selected = backgroundStyle == .emphasized
        LaughTheme.applySelectionLabelStyle(to: sectionLabel, selected: selected, idleColor: .secondaryLabelColor)
        LaughTheme.applySelectionLabelStyle(to: fileLabel, selected: selected, idleColor: .labelColor)
    }
}

private final class QueueTableRowView: NSTableRowView {
    static let reuseID = NSUserInterfaceItemIdentifier("QueueTableRowView")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.reuseID
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        // Soft inset so the pill breathes inside the taller queue rows.
        let rect = bounds.insetBy(dx: 4, dy: 2)
        LaughTheme.fillSelection(in: rect, cornerRadius: LaughTheme.InlineButton.cornerRadius)
    }
}
