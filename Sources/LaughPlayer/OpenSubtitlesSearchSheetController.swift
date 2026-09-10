import AppKit

/// Modal sheet: search OpenSubtitles anonymously and pick a result to download.
final class OpenSubtitlesSearchSheetController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var onAttach: ((URL) -> Void)?
    var onDismiss: (() -> Void)?
    var videoURL: URL?
    var initialQuery: String = ""

    private let client: OpenSubtitlesClient
    private var results: [OpenSubtitlesSearchResult] = []
    private var searchTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?

    private let queryField = NSTextField(string: "")
    private let languagePopUp = NSPopUpButton()
    private let searchButton = NSButton(title: "Search", target: nil, action: nil)
    private let useButton = NSButton(title: "Use", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private let scroll = NSScrollView()

    init(client: OpenSubtitlesClient = OpenSubtitlesClient()) {
        self.client = client
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Search OpenSubtitles"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareAndPresent(asSheetOn parent: NSWindow) {
        queryField.stringValue = initialQuery
        results = []
        table.reloadData()
        useButton.isEnabled = false
        spinner.stopAnimation(nil)
        spinner.isHidden = true

        if videoURL == nil {
            setStatus(OpenSubtitlesClientError.noVideoOpen.userMessage, isError: true)
            searchButton.isEnabled = false
        } else if !OpenSubtitlesConfig.hasApiKey {
            setStatus(OpenSubtitlesConfig.missingKeyMessage(), isError: true)
            searchButton.isEnabled = false
        } else {
            setStatus("Anonymous search — about 5 downloads per day per IP.", isError: false)
            searchButton.isEnabled = true
        }

        parent.beginSheet(window!) { [weak self] _ in
            self?.searchTask?.cancel()
            self?.downloadTask?.cancel()
            self?.onDismiss?()
        }
        if searchButton.isEnabled, !initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runSearch()
        }
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        queryField.placeholderString = "Movie or episode title"
        queryField.delegate = self
        queryField.translatesAutoresizingMaskIntoConstraints = false

        languagePopUp.removeAllItems()
        for lang in OpenSubtitlesLanguage.allCases {
            languagePopUp.addItem(withTitle: lang.menuTitle)
            languagePopUp.lastItem?.representedObject = lang.rawValue
        }
        languagePopUp.selectItem(at: 0)
        languagePopUp.controlSize = .small
        languagePopUp.translatesAutoresizingMaskIntoConstraints = false
        LaughTheme.applySettingsAccentChrome(to: languagePopUp)

        searchButton.bezelStyle = .rounded
        searchButton.controlSize = .small
        searchButton.target = self
        searchButton.action = #selector(searchPressed)
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        LaughTheme.applySettingsAccentChrome(to: searchButton)

        useButton.bezelStyle = .rounded
        useButton.controlSize = .small
        useButton.target = self
        useButton.action = #selector(usePressed)
        useButton.isEnabled = false
        useButton.keyEquivalent = "\r"
        useButton.translatesAutoresizingMaskIntoConstraints = false
        LaughTheme.applySettingsAccentChrome(to: useButton)

        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        LaughTheme.applySettingsAccentChrome(to: cancelButton)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Release"
        nameCol.width = 280
        let langCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("lang"))
        langCol.title = "Lang"
        langCol.width = 48
        let dlCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("downloads"))
        dlCol.title = "Downloads"
        dlCol.width = 80
        let ratingCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rating"))
        ratingCol.title = "Rating"
        ratingCol.width = 60

        table.addTableColumn(nameCol)
        table.addTableColumn(langCol)
        table.addTableColumn(dlCol)
        table.addTableColumn(ratingCol)
        table.headerView = NSTableHeaderView()
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.usesAlternatingRowBackgroundColors = true
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(usePressed)
        table.rowHeight = 22

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let topRow = NSStackView(views: [queryField, languagePopUp, searchButton, spinner])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8
        topRow.translatesAutoresizingMaskIntoConstraints = false

        let bottomRow = NSStackView(views: [cancelButton, useButton])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.spacing = 8
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(topRow)
        content.addSubview(scroll)
        content.addSubview(statusLabel)
        content.addSubview(bottomRow)

        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            topRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            topRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            queryField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            languagePopUp.widthAnchor.constraint(equalToConstant: 110),

            scroll.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: bottomRow.topAnchor, constant: -10),

            bottomRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            bottomRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        ])
    }

    private func setStatus(_ text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    private func selectedLanguageCode() -> String {
        (languagePopUp.selectedItem?.representedObject as? String) ?? OpenSubtitlesLanguage.en.rawValue
    }

    private func selectedResult() -> OpenSubtitlesSearchResult? {
        let row = table.selectedRow
        guard row >= 0, row < results.count else { return nil }
        return results[row]
    }

    // MARK: - Actions

    @objc private func cancelPressed() {
        guard let window, let parent = window.sheetParent else {
            window?.close()
            return
        }
        parent.endSheet(window, returnCode: .cancel)
    }

    @objc private func searchPressed() {
        runSearch()
    }

    @objc private func usePressed() {
        guard let result = selectedResult() else { return }
        guard let videoURL else {
            setStatus(OpenSubtitlesClientError.noVideoOpen.userMessage, isError: true)
            return
        }
        downloadTask?.cancel()
        setBusy(true)
        setStatus("Downloading…", isError: false)
        let language = selectedLanguageCode()
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (link, suggested) = try await client.requestDownload(fileID: result.fileID)
                let data = try await client.downloadFile(from: link)
                let dest = OpenSubtitlesSidecarStore.destinationURL(
                    forVideo: videoURL,
                    language: language,
                    suggestedFileName: suggested ?? result.fileName
                )
                let written = try OpenSubtitlesSidecarStore.write(data, to: dest)
                await MainActor.run {
                    self.setBusy(false)
                    self.onAttach?(written)
                    if let window = self.window, let parent = window.sheetParent {
                        parent.endSheet(window, returnCode: .OK)
                    } else {
                        self.window?.close()
                    }
                }
            } catch let error as OpenSubtitlesClientError {
                await MainActor.run {
                    self.setBusy(false)
                    self.setStatus(error.userMessage, isError: true)
                }
            } catch {
                await MainActor.run {
                    self.setBusy(false)
                    self.setStatus(OpenSubtitlesClientError.network(error.localizedDescription).userMessage, isError: true)
                }
            }
        }
    }

    private func runSearch() {
        searchTask?.cancel()
        let query = queryField.stringValue
        let language = selectedLanguageCode()
        setBusy(true)
        setStatus("Searching…", isError: false)
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let hits = try await client.search(query: query, language: language)
                await MainActor.run {
                    self.setBusy(false)
                    self.results = hits
                    self.table.reloadData()
                    self.useButton.isEnabled = false
                    if hits.isEmpty {
                        self.setStatus(OpenSubtitlesClientError.emptyResults.userMessage, isError: true)
                    } else {
                        self.setStatus("\(hits.count) result\(hits.count == 1 ? "" : "s"). Select one and click Use.", isError: false)
                    }
                }
            } catch let error as OpenSubtitlesClientError {
                await MainActor.run {
                    self.setBusy(false)
                    self.results = []
                    self.table.reloadData()
                    self.setStatus(error.userMessage, isError: true)
                }
            } catch {
                await MainActor.run {
                    self.setBusy(false)
                    self.setStatus(OpenSubtitlesClientError.network(error.localizedDescription).userMessage, isError: true)
                }
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        if busy {
            spinner.isHidden = false
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
        }
        searchButton.isEnabled = !busy && OpenSubtitlesConfig.hasApiKey && videoURL != nil
        useButton.isEnabled = !busy && table.selectedRow >= 0
        queryField.isEnabled = !busy
        languagePopUp.isEnabled = !busy
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < results.count, let tableColumn else { return nil }
        let item = results[row]
        let id = tableColumn.identifier
        let text: String
        switch id.rawValue {
        case "name":
            text = item.release.isEmpty ? item.fileName : item.release
        case "lang":
            text = item.language.uppercased()
        case "downloads":
            text = "\(item.downloadCount)"
        case "rating":
            if let rating = item.rating {
                text = String(format: "%.1f", rating)
            } else {
                text = "—"
            }
        default:
            text = ""
        }
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView
            ?? {
                let cell = NSTableCellView()
                cell.identifier = id
                let field = NSTextField(labelWithString: "")
                field.font = .systemFont(ofSize: 12)
                field.lineBreakMode = .byTruncatingMiddle
                field.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(field)
                cell.textField = field
                NSLayoutConstraint.activate([
                    field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
                return cell
            }()
        cell.textField?.stringValue = text
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        useButton.isEnabled = selectedResult() != nil && spinner.isHidden
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            runSearch()
            return true
        }
        return false
    }
}
