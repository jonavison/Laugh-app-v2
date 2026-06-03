import Foundation

protocol MediaLibraryDelegate: AnyObject {
    func mediaLibraryDidSelectMedia(url: URL, kind: DroppedMediaKind)
}

final class MediaLibraryController {
    weak var delegate: MediaLibraryDelegate?

    enum SidebarRow: Equatable {
        case recentHeader
        case recentItem(LibraryMediaFile)
        case root(MediaLibraryRoot)
    }

    enum SidebarMode: Equatable {
        case recentHeader
        case root(MediaLibraryRoot)
    }

    static let recentPreviewLimit = 5

    private(set) var roots: [MediaLibraryRoot] = []
    private(set) var recentPreviewItems: [LibraryMediaFile] = []
    private(set) var selectedSidebarRow = 0
    private(set) var sidebarMode: SidebarMode = .recentHeader
    private(set) var currentDirectoryURL: URL?
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []
    private(set) var browseSort = LibraryBrowseSort.default
    private(set) var displayedEntries: [LibraryBrowseEntry] = []

    var onChange: (() -> Void)?

    init() {
        reloadRoots()
        // Start on Recents — do not scan Movies/Videos on the main thread at launch.
        selectSidebarRow(0)
    }

    func reloadRoots() {
        roots = MediaLibraryRoots.allRoots()
        recentPreviewItems = RecentlyViewedStore.shared.sidebarPreview()
        reloadGrid()
        onChange?()
    }

    func sidebarRowCount() -> Int {
        1 + recentPreviewItems.count + roots.count
    }

    func sidebarRow(at index: Int) -> SidebarRow? {
        guard index >= 0, index < sidebarRowCount() else { return nil }
        if index == 0 { return .recentHeader }
        if index <= recentPreviewItems.count {
            return .recentItem(recentPreviewItems[index - 1])
        }
        return .root(roots[index - 1 - recentPreviewItems.count])
    }

    func firstRootRowIndex() -> Int {
        1 + recentPreviewItems.count
    }

    func selectSidebarRow(_ row: Int) {
        guard let sidebarRow = sidebarRow(at: row) else { return }

        switch sidebarRow {
        case .recentItem(let file):
            selectedSidebarRow = row
            openMedia(file)
            onChange?()
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
        case .recentHeader:
            displayedEntries = []
        case .root:
            guard let directory = currentDirectoryURL else {
                displayedEntries = []
                break
            }
            displayedEntries = MediaLibraryScanner.browseEntries(in: directory)
        }

        displayedEntries = LibraryBrowseItemSorter.sorted(displayedEntries, by: browseSort)
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
        selectSidebarRow(0)
    }

    var canGoBack: Bool {
        sidebarMode != .recentHeader && !backStack.isEmpty
    }

    var canGoForward: Bool {
        sidebarMode != .recentHeader && !forwardStack.isEmpty
    }

    var canRemoveSelectedRoot: Bool {
        guard case .root(let root) = sidebarRow(at: selectedSidebarRow) else { return false }
        return root.isUserAdded
    }

    /// True when the browse grid has no folder context (Recents header selected).
    var showsBrowsePlaceholder: Bool {
        if case .recentHeader = sidebarMode { return true }
        return false
    }

    /// Media files in the current browse folder, in the same order as the grid (respects sort).
    func mediaFilesInBrowseOrder() -> [LibraryMediaFile] {
        mediaFiles(in: nil)
    }

    /// Media in a folder (or the current browse folder when `directory` is nil), using the active sort.
    func mediaFiles(in directory: URL?) -> [LibraryMediaFile] {
        let targetDirectory: URL?
        switch sidebarMode {
        case .recentHeader:
            return []
        case .root:
            targetDirectory = directory ?? currentDirectoryURL
        }
        guard let targetDirectory else { return [] }

        let entries = MediaLibraryScanner.browseEntries(in: targetDirectory)
        return LibraryBrowseItemSorter.sorted(entries, by: browseSort).compactMap { entry in
            guard case .media(let file) = entry.kind else { return nil }
            return file
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
        !showsBrowsePlaceholder && !mediaFilesInBrowseOrder().isEmpty
    }

    /// Sort control is shown only when the browse grid has folder contents to order.
    var showsBrowseSortControl: Bool {
        !showsBrowsePlaceholder && !displayedEntries.isEmpty
    }

    var emptyGridMessage: String {
        switch sidebarMode {
        case .recentHeader:
            return "Select a folder to browse"
        case .root:
            return "Empty folder"
        }
    }

    func breadcrumbComponents() -> [(title: String, url: URL?)] {
        switch sidebarMode {
        case .recentHeader:
            return [(title: "Recent", url: nil)]
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
