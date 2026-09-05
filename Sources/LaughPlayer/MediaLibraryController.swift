import Foundation

protocol MediaLibraryDelegate: AnyObject {
    func mediaLibraryDidSelectMedia(url: URL, kind: DroppedMediaKind)
}

final class MediaLibraryController {
    weak var delegate: MediaLibraryDelegate?

    enum SidebarRow: Equatable {
        case recentItem(LibraryMediaFile)
        case recentHeader
        case favoritesHeader
        case librarySeparator
        case librarySectionHeader
        case root(MediaLibraryRoot)
    }

    enum SidebarMode: Equatable {
        case none
        case recentHeader
        case favoritesHeader
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
    private(set) var viewMode: LibraryBrowseViewMode = LibraryBrowsePreferences.viewMode
    private(set) var galleryScale: LibraryBrowseGalleryScale = LibraryBrowsePreferences.galleryScale
    private(set) var searchQuery: String = ""
    private(set) var kindFilter: LibraryKindFilter = .all
    /// Unfiltered entries for the current destination (before search/kind filter).
    private(set) var sourceEntries: [LibraryBrowseEntry] = []
    private(set) var displayedEntries: [LibraryBrowseEntry] = []
    private(set) var selectedEntryIndices: IndexSet = []

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

    private var favoritesHeaderRowIndex: Int { 1 + recentPreviewItems.count }

    private var librarySeparatorRowIndex: Int { favoritesHeaderRowIndex + 1 }

    private var librarySectionRowIndex: Int { librarySeparatorRowIndex + 1 }

    func sidebarRowCount() -> Int {
        1 + recentPreviewItems.count + 1 + 1 + 1 + roots.count
    }

    func sidebarRow(at index: Int) -> SidebarRow? {
        guard index >= 0, index < sidebarRowCount() else { return nil }
        if index == recentsHeaderRowIndex { return .recentHeader }
        if index < favoritesHeaderRowIndex {
            return .recentItem(recentPreviewItems[index - 1])
        }
        if index == favoritesHeaderRowIndex { return .favoritesHeader }
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
        case .recentItem, .recentHeader, .favoritesHeader, .root:
            return true
        }
    }

    func clearSidebarSelection() {
        selectedSidebarRow = Self.noSelectionRow
        sidebarMode = .none
        currentDirectoryURL = nil
        backStack = []
        forwardStack = []
        clearSearchAndFilters(notify: false)
        clearMultiSelection(notify: false)
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
            clearSearchAndFilters(notify: false)
        case .favoritesHeader:
            selectedSidebarRow = row
            sidebarMode = .favoritesHeader
            currentDirectoryURL = nil
            backStack = []
            forwardStack = []
            clearSearchAndFilters(notify: false)
        case .root(let root):
            selectedSidebarRow = row
            sidebarMode = .root(root)
            currentDirectoryURL = root.directoryURL
            backStack = []
            forwardStack = []
            clearSearchAndFilters(notify: false)
        }

        clearMultiSelection(notify: false)
        reloadGrid()
        onChange?()
    }

    func reloadGrid() {
        switch sidebarMode {
        case .none:
            sourceEntries = []
        case .recentHeader:
            sourceEntries = recentBrowseEntries()
        case .favoritesHeader:
            sourceEntries = favoriteBrowseEntries()
        case .root:
            guard let directory = currentDirectoryURL else {
                sourceEntries = []
                break
            }
            sourceEntries = MediaLibraryScanner.browseEntries(in: directory)
        }

        if case .root = sidebarMode {
            sourceEntries = LibraryBrowseItemSorter.sorted(sourceEntries, by: browseSort)
        }

        applyDisplayFilters()
    }

    private func applyDisplayFilters() {
        var entries = sourceEntries
        if kindFilter != .all {
            entries = entries.filter { entry in
                switch kindFilter {
                case .all:
                    return true
                case .folders:
                    return entry.isFolder
                case .videos:
                    if case .media(let file) = entry.kind { return file.kind == .video }
                    return false
                case .images:
                    if case .media(let file) = entry.kind { return file.kind == .image }
                    return false
                }
            }
        }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            entries = entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        displayedEntries = entries
        selectedEntryIndices = selectedEntryIndices.filteredIndexSet { $0 < displayedEntries.count }
    }

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

    private func favoriteBrowseEntries() -> [LibraryBrowseEntry] {
        ImageLibraryMetaStore.favoritedImageFiles().map { file in
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

    func setViewMode(_ mode: LibraryBrowseViewMode) {
        guard viewMode != mode else { return }
        viewMode = mode
        LibraryBrowsePreferences.viewMode = mode
        onChange?()
    }

    func setGalleryScale(_ scale: LibraryBrowseGalleryScale) {
        guard galleryScale != scale else { return }
        galleryScale = scale
        LibraryBrowsePreferences.galleryScale = scale
        onChange?()
    }

    var tileMetrics: LibraryBrowseTileMetrics {
        LibraryBrowseTileMetrics.metrics(mode: effectiveViewMode, galleryScale: galleryScale)
    }

    func setSearchQuery(_ query: String) {
        let trimmed = query
        guard searchQuery != trimmed else { return }
        searchQuery = trimmed
        clearMultiSelection(notify: false)
        applyDisplayFilters()
        onChange?()
    }

    func setKindFilter(_ filter: LibraryKindFilter) {
        guard kindFilter != filter else { return }
        kindFilter = filter
        clearMultiSelection(notify: false)
        applyDisplayFilters()
        onChange?()
    }

    private func clearSearchAndFilters(notify: Bool) {
        searchQuery = ""
        kindFilter = .all
        if notify {
            applyDisplayFilters()
            onChange?()
        }
    }

    func goBack() {
        guard case .root = sidebarMode, let current = currentDirectoryURL, let previous = backStack.popLast() else { return }
        forwardStack.append(current)
        currentDirectoryURL = previous
        clearSearchAndFilters(notify: false)
        clearMultiSelection(notify: false)
        reloadGrid()
        onChange?()
    }

    func goForward() {
        guard case .root = sidebarMode, let current = currentDirectoryURL, let next = forwardStack.popLast() else { return }
        backStack.append(current)
        currentDirectoryURL = next
        clearSearchAndFilters(notify: false)
        clearMultiSelection(notify: false)
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
        clearSearchAndFilters(notify: false)
        clearMultiSelection(notify: false)
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
        clearSearchAndFilters(notify: false)
        clearMultiSelection(notify: false)
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

    // MARK: - Multi-select

    func clearMultiSelection(notify: Bool = true) {
        guard !selectedEntryIndices.isEmpty else { return }
        selectedEntryIndices = []
        if notify { onChange?() }
    }

    func setMultiSelection(_ indices: IndexSet) {
        let filtered = indices.filteredIndexSet { $0 >= 0 && $0 < displayedEntries.count }
        guard filtered != selectedEntryIndices else { return }
        selectedEntryIndices = filtered
        onChange?()
    }

    func toggleMultiSelection(at index: Int) {
        guard index >= 0, index < displayedEntries.count else { return }
        var next = selectedEntryIndices
        if next.contains(index) {
            next.remove(index)
        } else {
            next.insert(index)
        }
        selectedEntryIndices = next
        onChange?()
    }

    func extendMultiSelection(to index: Int) {
        guard index >= 0, index < displayedEntries.count else { return }
        let anchor = selectedEntryIndices.min() ?? index
        let range = IndexSet(integersIn: min(anchor, index)...max(anchor, index))
        selectedEntryIndices = range
        onChange?()
    }

    var selectedEntries: [LibraryBrowseEntry] {
        selectedEntryIndices.sorted().compactMap { idx in
            guard idx < displayedEntries.count else { return nil }
            return displayedEntries[idx]
        }
    }

    var hasMultiSelection: Bool {
        selectedEntryIndices.count > 1 || (selectedEntryIndices.count == 1 && !selectedEntryIndices.isEmpty)
    }

    /// True when at least one entry is multi-selected (including a single modifier-selected item).
    var hasBatchSelection: Bool {
        !selectedEntryIndices.isEmpty
    }

    var canGoBack: Bool {
        sidebarMode != .recentHeader
            && sidebarMode != .favoritesHeader
            && sidebarMode != .none
            && !backStack.isEmpty
    }

    var canGoForward: Bool {
        sidebarMode != .recentHeader
            && sidebarMode != .favoritesHeader
            && sidebarMode != .none
            && !forwardStack.isEmpty
    }

    var canRemoveSelectedRoot: Bool {
        guard case .root(let root) = sidebarRow(at: selectedSidebarRow) else { return false }
        return root.isUserAdded
    }

    var showsRecentList: Bool {
        sidebarMode == .recentHeader
    }

    var showsFavoritesList: Bool {
        sidebarMode == .favoritesHeader
    }

    /// True when nothing is selected in the sidebar (browse shows the drop hint).
    var showsBrowsePlaceholder: Bool {
        sidebarMode == .none
    }

    var showsFolderBrowseChrome: Bool {
        if case .root = sidebarMode { return true }
        return false
    }

    var showsBrowseSearch: Bool {
        showsFolderBrowseChrome || showsFavoritesList
    }

    var showsKindFilter: Bool {
        showsFolderBrowseChrome || showsFavoritesList
    }

    var showsBrowseViewModeControl: Bool {
        showsFolderBrowseChrome || showsFavoritesList
    }

    var effectiveViewMode: LibraryBrowseViewMode {
        if showsRecentList { return .list }
        return viewMode
    }

    var isFiltering: Bool {
        kindFilter != .all || !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Media files currently shown in browse order (respects search/kind filter).
    func mediaFilesInBrowseOrder() -> [LibraryMediaFile] {
        displayedEntries.compactMap { entry in
            guard case .media(let file) = entry.kind else { return nil }
            return file
        }
    }

    /// Media in a folder (or the current browse folder when `directory` is nil), using the active sort.
    func mediaFiles(in directory: URL?) -> [LibraryMediaFile] {
        switch sidebarMode {
        case .none:
            return []
        case .recentHeader:
            return RecentlyViewedStore.shared.mediaFiles()
        case .favoritesHeader:
            return ImageLibraryMetaStore.favoritedImageFiles()
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
        showsRecentList
            || showsFavoritesList
            || (!showsBrowsePlaceholder && !mediaFilesInBrowseOrder().isEmpty)
    }

    /// Sort control for folder browse only (recents/favorites stay fixed order).
    var showsBrowseSortControl: Bool {
        if case .root = sidebarMode { return !sourceEntries.isEmpty || isFiltering }
        return false
    }

    var emptyGridMessage: String {
        switch sidebarMode {
        case .none:
            return ""
        case .recentHeader:
            return "No recent files"
        case .favoritesHeader:
            if isFiltering { return "No matches" }
            return "No favorite images"
        case .root:
            if isFiltering { return "No matches" }
            return "Empty folder"
        }
    }

    func breadcrumbComponents() -> [(title: String, url: URL?)] {
        switch sidebarMode {
        case .none:
            return []
        case .recentHeader:
            return [(title: "Recents", url: nil)]
        case .favoritesHeader:
            return [(title: "Favorites", url: nil)]
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
