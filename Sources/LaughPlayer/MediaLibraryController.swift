import Foundation

protocol MediaLibraryDelegate: AnyObject {
    func mediaLibraryDidSelectMedia(url: URL, kind: DroppedMediaKind)
}

final class MediaLibraryController {
    weak var delegate: MediaLibraryDelegate?

    enum SidebarRow: Equatable {
        case recentItem(LibraryMediaFile)
        case recentHeader
        case librarySeparator
        case librarySectionHeader
        case root(MediaLibraryRoot)
    }

    enum SidebarMode: Equatable {
        case none
        case recentHeader
        case root(MediaLibraryRoot)
    }

    static let recentPreviewLimit = 5
    static let noSelectionRow = -1

    private(set) var roots: [MediaLibraryRoot] = []
    private(set) var recentPreviewItems: [LibraryMediaFile] = []
    private(set) var selectedSidebarRow = noSelectionRow
    private(set) var sidebarMode: SidebarMode = .none
    private(set) var currentDirectoryURL: URL?
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []
    private(set) var browseSort = LibraryBrowseSort.default
    private(set) var displayedEntries: [LibraryBrowseEntry] = []

    var onChange: (() -> Void)?

    init() {
        reloadRoots()
        clearSidebarSelection()
    }

    func reloadRoots() {
        roots = MediaLibraryRoots.allRoots()
        recentPreviewItems = RecentlyViewedStore.shared.sidebarPreview()
        if !isSidebarRowSelectable(selectedSidebarRow) {
            clearSidebarSelection()
        } else {
            reloadGrid()
        }
        onChange?()
    }

    private let recentsHeaderRowIndex = 0

    private var librarySeparatorRowIndex: Int { 1 + recentPreviewItems.count }

    private var librarySectionRowIndex: Int { librarySeparatorRowIndex + 1 }

    func sidebarRowCount() -> Int {
        1 + recentPreviewItems.count + 1 + 1 + roots.count
    }

    func sidebarRow(at index: Int) -> SidebarRow? {
        guard index >= 0, index < sidebarRowCount() else { return nil }
        if index == recentsHeaderRowIndex { return .recentHeader }
        if index < librarySeparatorRowIndex {
            return .recentItem(recentPreviewItems[index - 1])
        }
        if index == librarySeparatorRowIndex { return .librarySeparator }
        if index == librarySectionRowIndex { return .librarySectionHeader }
        let rootIndex = index - librarySectionRowIndex - 1
        guard rootIndex < roots.count else { return nil }
        return .root(roots[rootIndex])
    }

    func firstRootRowIndex() -> Int {
        librarySectionRowIndex + 1
    }

    func isSidebarRowSelectable(_ row: Int) -> Bool {
        guard let sidebarRow = sidebarRow(at: row) else { return false }
        switch sidebarRow {
        case .librarySectionHeader, .librarySeparator:
            return false
        case .recentItem, .recentHeader, .root:
            return true
        }
    }

    func clearSidebarSelection() {
        selectedSidebarRow = Self.noSelectionRow
        sidebarMode = .none
        currentDirectoryURL = nil
        backStack = []
        forwardStack = []
        reloadGrid()
        onChange?()
    }

    func selectSidebarRow(_ row: Int) {
        guard let sidebarRow = sidebarRow(at: row) else { return }

        switch sidebarRow {
        case .recentItem(let file):
            openMedia(file)
            clearSidebarSelection()
            return
        case .librarySectionHeader, .librarySeparator:
            return
        case .recentHeader:
            selectedSidebarRow = row
            sidebarMode = .recentHeader
            currentDirectoryURL = nil
            backStack = []
            forwardStack = []
        case .root(let root):
            selectedSidebarRow = row
            sidebarMode = .root(root)
            currentDirectoryURL = root.directoryURL
            backStack = []
            forwardStack = []
        }

        reloadGrid()
        onChange?()
    }

    func reloadGrid() {
        switch sidebarMode {
        case .none:
            displayedEntries = []
        case .recentHeader:
            displayedEntries = recentBrowseEntries()
        case .root:
            guard let directory = currentDirectoryURL else {
                displayedEntries = []
                break
            }
            displayedEntries = MediaLibraryScanner.browseEntries(in: directory)
        }

        if case .root = sidebarMode {
            displayedEntries = LibraryBrowseItemSorter.sorted(displayedEntries, by: browseSort)
        }
    }

    /// Recents content list: store order is most recently played first (no browse sort).
    private func recentBrowseEntries() -> [LibraryBrowseEntry] {
        RecentlyViewedStore.shared.mediaFiles().map { file in
            LibraryBrowseEntry(
                kind: .media(file),
                name: file.url.lastPathComponent,
                dateModified: nil,
                dateAdded: nil,
                size: nil
            )
        }
    }

    func setSort(_ sort: LibraryBrowseSort) {
        browseSort = sort
        reloadGrid()
        onChange?()
    }

    func goBack() {
        guard case .root = sidebarMode, let current = currentDirectoryURL, let previous = backStack.popLast() else { return }
        forwardStack.append(current)
        currentDirectoryURL = previous
        reloadGrid()
        onChange?()
    }

    func goForward() {
        guard case .root = sidebarMode, let current = currentDirectoryURL, let next = forwardStack.popLast() else { return }
        backStack.append(current)
        currentDirectoryURL = next
        reloadGrid()
        onChange?()
    }

    func navigateTo(_ url: URL, pushingCurrent: Bool) {
        guard case .root = sidebarMode else { return }
        if pushingCurrent, let current = currentDirectoryURL {
            backStack.append(current)
            forwardStack.removeAll()
        }
        currentDirectoryURL = url
        reloadGrid()
        onChange?()
    }

    func jumpToBreadcrumb(_ url: URL) {
        guard case .root(let root) = sidebarMode else { return }
        var newBack: [URL] = []
        let components = breadcrumbPathComponents(root: root, current: url)
        if components.count > 1 {
            for i in 0..<(components.count - 1) {
                newBack.append(components[i].url)
            }
        }
        backStack = newBack
        forwardStack = []
        currentDirectoryURL = url
        reloadGrid()
        onChange?()
    }

    func openFolder(_ url: URL) {
        navigateTo(url, pushingCurrent: true)
    }

    func openMedia(_ file: LibraryMediaFile) {
        delegate?.mediaLibraryDidSelectMedia(url: file.url, kind: file.kind)
    }

    func addRoot(at url: URL) throws {
        _ = try LibraryRootsStore.shared.addRoot(at: url)
        reloadRoots()
        if let index = roots.firstIndex(where: { $0.directoryURL.standardizedFileURL == url.standardizedFileURL }) {
            selectSidebarRow(firstRootRowIndex() + index)
        }
    }

    func removeSelectedRoot() {
        guard case .root(let root) = sidebarRow(at: selectedSidebarRow), root.isUserAdded else { return }
        LibraryRootsStore.shared.removeRoot(id: root.id)
        reloadRoots()
        clearSidebarSelection()
    }

    var canGoBack: Bool {
        sidebarMode != .recentHeader && sidebarMode != .none && !backStack.isEmpty
    }

    var canGoForward: Bool {
        sidebarMode != .recentHeader && sidebarMode != .none && !forwardStack.isEmpty
    }

    var canRemoveSelectedRoot: Bool {
        guard case .root(let root) = sidebarRow(at: selectedSidebarRow) else { return false }
        return root.isUserAdded
    }

    var showsRecentList: Bool {
        sidebarMode == .recentHeader
    }

    /// True when nothing is selected in the sidebar (browse shows the drop hint).
    var showsBrowsePlaceholder: Bool {
        sidebarMode == .none
    }

    /// Media files in the current browse folder, in the same order as the grid (respects sort).
    func mediaFilesInBrowseOrder() -> [LibraryMediaFile] {
        mediaFiles(in: nil)
    }

    /// Media in a folder (or the current browse folder when `directory` is nil), using the active sort.
    func mediaFiles(in directory: URL?) -> [LibraryMediaFile] {
        switch sidebarMode {
        case .none:
            return []
        case .recentHeader:
            return RecentlyViewedStore.shared.mediaFiles()
        case .root:
            guard let targetDirectory = directory ?? currentDirectoryURL else { return [] }
            let entries = MediaLibraryScanner.browseEntries(in: targetDirectory)
            return LibraryBrowseItemSorter.sorted(entries, by: browseSort).compactMap { entry in
                guard case .media(let file) = entry.kind else { return nil }
                return file
            }
        }
    }

    func entry(at indexPath: IndexPath) -> LibraryBrowseEntry? {
        let index = indexPath.item
        guard index >= 0, index < displayedEntries.count else { return nil }
        return displayedEntries[index]
    }

    func reloadAfterFilesystemChange() {
        reloadGrid()
        onChange?()
    }

    var canPlayAllInBrowse: Bool {
        showsRecentList || (!showsBrowsePlaceholder && !mediaFilesInBrowseOrder().isEmpty)
    }

    /// Sort control for folder browse only (recents stay in recently-played order).
    var showsBrowseSortControl: Bool {
        if case .root = sidebarMode { return !displayedEntries.isEmpty }
        return false
    }

    var emptyGridMessage: String {
        switch sidebarMode {
        case .none:
            return ""
        case .recentHeader:
            return "No recent files"
        case .root:
            return "Empty folder"
        }
    }

    func breadcrumbComponents() -> [(title: String, url: URL?)] {
        switch sidebarMode {
        case .none:
            return []
        case .recentHeader:
            return [(title: "Recents", url: nil)]
        case .root(let root):
            guard let current = currentDirectoryURL else { return [(title: root.displayName, url: root.directoryURL)] }
            return breadcrumbPathComponents(root: root, current: current).map { (title: $0.title, url: $0.url) }
        }
    }

    private func breadcrumbPathComponents(root: MediaLibraryRoot, current: URL) -> [(title: String, url: URL)] {
        var components: [(String, URL)] = [(root.displayName, root.directoryURL)]
        let rootPath = root.directoryURL.standardizedFileURL.path
        let currentPath = current.standardizedFileURL.path
        guard currentPath.hasPrefix(rootPath), currentPath.count > rootPath.count else {
            return components
        }

        var url = root.directoryURL
        let remainder = currentPath.dropFirst(rootPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for part in remainder.split(separator: "/") {
            url = url.appendingPathComponent(String(part), isDirectory: true)
            components.append((String(part), url))
        }
        return components
    }
}
