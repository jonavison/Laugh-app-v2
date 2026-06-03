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
        tableView.rowHeight = 36
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

        view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
    }

    func setRows(_ rows: [PlaybackQueueListRow]) {
        self.rows = rows
        tableView.reloadData()

        let rowHeight: CGFloat = 36
        let chrome: CGFloat = 24
        let maxHeight: CGFloat = 320
        let contentHeight = CGFloat(max(rows.count, 1)) * rowHeight + chrome
        let height = min(maxHeight, max(88, contentHeight))
        preferredContentSize = NSSize(width: 300, height: height)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
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

        fileLabel.font = .systemFont(ofSize: 12)
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(sectionLabel)
        addSubview(fileLabel)
        textField = fileLabel

        NSLayoutConstraint.activate([
            sectionLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            sectionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            sectionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),

            fileLabel.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 1),
            fileLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            fileLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            fileLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(sectionTitle: String, fileName: String) {
        sectionLabel.stringValue = sectionTitle
        fileLabel.stringValue = fileName
    }
}
