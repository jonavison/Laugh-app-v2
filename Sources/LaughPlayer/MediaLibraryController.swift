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
        /// Browsing a directory. `root` is the library root it sits under, or `nil` when the
        /// folder is outside every root — where Recents and Finder opens land, since neither
        /// is confined to the library.
        case folder(root: MediaLibraryRoot?)
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
    /// Anchor for Shift-click / Shift-arrow range selection (fixed end of the range).
    private(set) var selectionAnchorIndex: Int?
    /// Active end for keyboard range selection (moves with arrows while Shift is held).
    private(set) var selectionFocusIndex: Int?

    var onChange: (() -> Void)?
    /// Fired for multi-select updates without reloading browse content.
    var onSelectionChange: (() -> Void)?

    init() {
        reloadRoots()
        clearSidebarSelection()
    }

    func reloadRoots() {
        roots = MediaLibraryRoots.allRoots()
        recentPreviewItems = RecentlyViewedStore.shared.sidebarPreview()
        if case .folder(root: nil) = sidebarMode, currentDirectoryURL != nil {
            // A root-less folder browse has no sidebar row to validate against — keep it.
            reloadGrid()
        } else if !isSidebarRowSelectable(selectedSidebarRow) {
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
            // Follow the file into its folder rather than emptying browse: a recent file is
            // the one piece of context the user just gave us about where they are working.
            revealFolder(file.url.deletingLastPathComponent())
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
            sidebarMode = .folder(root: root)
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
        case .folder:
            guard let directory = currentDirectoryURL else {
                sourceEntries = []
                break
            }
            sourceEntries = MediaLibraryScanner.browseEntries(in: directory)
        }

        if case .folder = sidebarMode {
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
        let previouslySelectedURLs = Set(selectedEntryIndices.compactMap { index -> URL? in
            guard index < displayedEntries.count else { return nil }
            return Self.identityURL(for: displayedEntries[index])
        })
        let previousAnchorURL: URL? = {
            guard let anchor = selectionAnchorIndex, anchor < displayedEntries.count else { return nil }
            return Self.identityURL(for: displayedEntries[anchor])
        }()
        let previousFocusURL: URL? = {
            guard let focus = selectionFocusIndex, focus < displayedEntries.count else { return nil }
            return Self.identityURL(for: displayedEntries[focus])
        }()

        displayedEntries = entries
        remapSelection(preserving: previouslySelectedURLs, anchorURL: previousAnchorURL, focusURL: previousFocusURL)
    }

    private static func identityURL(for entry: LibraryBrowseEntry) -> URL? {
        LibraryBrowseFileActions.itemURL(for: entry)?.standardizedFileURL
    }

    private func remapSelection(preserving urls: Set<URL>, anchorURL: URL?, focusURL: URL?) {
        guard !urls.isEmpty else {
            selectedEntryIndices = []
            selectionAnchorIndex = nil
            selectionFocusIndex = nil
            return
        }
        var next = IndexSet()
        var newAnchor: Int?
        var newFocus: Int?
        for (index, entry) in displayedEntries.enumerated() {
            guard let url = Self.identityURL(for: entry) else { continue }
            if urls.contains(url) {
                next.insert(index)
            }
            if let anchorURL, url == anchorURL {
                newAnchor = index
            }
            if let focusURL, url == focusURL {
                newFocus = index
            }
        }
        selectedEntryIndices = next
        selectionAnchorIndex = newAnchor ?? next.min()
        selectionFocusIndex = newFocus ?? selectionAnchorIndex
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
        applyDisplayFilters()
        onChange?()
    }

    func setKindFilter(_ filter: LibraryKindFilter) {
        guard kindFilter != filter else { return }
        kindFilter = filter
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
        guard case .folder = sidebarMode, let current = currentDirectoryURL, let previous = backStack.popLast() else { return }
        forwardStack.append(current)
        currentDirectoryURL = previous
        clearSearchAndFilters(notify: false)
        clearMultiSelection(notify: false)
        reloadGrid()
        onChange?()
    }

    func goForward() {
        guard case .folder = sidebarMode, let current = currentDirectoryURL, let next = forwardStack.popLast() else { return }
        backStack.append(current)
        currentDirectoryURL = next
        clearSearchAndFilters(notify: false)
        clearMultiSelection(notify: false)
        reloadGrid()
        onChange?()
    }

    func navigateTo(_ url: URL, pushingCurrent: Bool) {
        guard case .folder = sidebarMode else { return }
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
        guard case .folder(let root) = sidebarMode else { return }
        let components = breadcrumbTrail(root: root, current: url)
        backStack = components.dropLast().map(\.url)
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

    /// Point browse at `folder`, selecting the library root that contains it when there is
    /// one. A folder outside every root is browsed on its own, with no sidebar row selected:
    /// Recents and Finder opens reach files anywhere, and landing the user on an unrelated
    /// library root instead of the folder they just opened from is worse than no selection.
    func revealFolder(_ folder: URL) {
        let target = folder.resolvingSymlinksInPath().standardizedFileURL

        if let root = Self.root(containing: target, in: roots),
           let index = roots.firstIndex(where: { $0.id == root.id }) {
            selectSidebarRow(firstRootRowIndex() + index)
            let current = currentDirectoryURL?.resolvingSymlinksInPath().standardizedFileURL
            if current != target {
                // Pushing the root keeps Back going up to the root listing.
                navigateTo(target, pushingCurrent: true)
            } else {
                reloadGrid()
                onChange?()
            }
            return
        }

        selectedSidebarRow = Self.noSelectionRow
        sidebarMode = .folder(root: nil)
        currentDirectoryURL = target
        backStack = []
        forwardStack = []
        clearSearchAndFilters(notify: false)
        clearMultiSelection(notify: false)
        reloadGrid()
        onChange?()
    }

    /// Deepest root containing `folder` (or equal to it); `nil` when none do.
    static func root(containing folder: URL, in roots: [MediaLibraryRoot]) -> MediaLibraryRoot? {
        let path = folder.resolvingSymlinksInPath().standardizedFileURL.path
        return roots
            .filter { root in
                let rootPath = root.directoryURL.resolvingSymlinksInPath().standardizedFileURL.path
                return path == rootPath
                    || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
            }
            .max { lhs, rhs in
                lhs.directoryURL.standardizedFileURL.path.count
                    < rhs.directoryURL.standardizedFileURL.path.count
            }
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
        guard !selectedEntryIndices.isEmpty || selectionAnchorIndex != nil || selectionFocusIndex != nil else { return }
        selectedEntryIndices = []
        selectionAnchorIndex = nil
        selectionFocusIndex = nil
        if notify { onSelectionChange?() }
    }

    func setMultiSelection(_ indices: IndexSet, anchor: Int? = nil) {
        let filtered = indices.filteredIndexSet { $0 >= 0 && $0 < displayedEntries.count }
        let nextAnchor = anchor.flatMap { filtered.contains($0) ? $0 : nil } ?? filtered.max() ?? filtered.min()
        guard filtered != selectedEntryIndices
            || nextAnchor != selectionAnchorIndex
            || nextAnchor != selectionFocusIndex else { return }
        selectedEntryIndices = filtered
        selectionAnchorIndex = nextAnchor
        selectionFocusIndex = nextAnchor
        onSelectionChange?()
    }

    func selectAllDisplayed() {
        guard !displayedEntries.isEmpty else {
            clearMultiSelection()
            return
        }
        setMultiSelection(IndexSet(integersIn: 0..<displayedEntries.count), anchor: displayedEntries.count - 1)
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
        selectionAnchorIndex = index
        selectionFocusIndex = index
        onSelectionChange?()
    }

    func removeFromMultiSelection(at index: Int) {
        guard selectedEntryIndices.contains(index) else { return }
        var next = selectedEntryIndices
        next.remove(index)
        selectedEntryIndices = next
        if selectionAnchorIndex == index {
            selectionAnchorIndex = next.max() ?? next.min()
        }
        if selectionFocusIndex == index {
            selectionFocusIndex = selectionAnchorIndex
        }
        onSelectionChange?()
    }

    func extendMultiSelection(to index: Int) {
        guard index >= 0, index < displayedEntries.count else { return }
        let anchor = selectionAnchorIndex ?? selectedEntryIndices.min() ?? index
        let range = IndexSet(integersIn: min(anchor, index)...max(anchor, index))
        selectedEntryIndices = range
        selectionAnchorIndex = anchor
        selectionFocusIndex = index
        onSelectionChange?()
    }

    /// Move keyboard focus/selection by `delta` items. Shift extends from the selection anchor.
    func moveSelection(by delta: Int, extending: Bool) {
        guard !displayedEntries.isEmpty else { return }
        let current = selectionFocusIndex
            ?? selectionAnchorIndex
            ?? selectedEntryIndices.max()
            ?? selectedEntryIndices.min()
            ?? -1
        let nextIndex: Int
        if current < 0 {
            nextIndex = delta > 0 ? 0 : displayedEntries.count - 1
        } else {
            nextIndex = max(0, min(displayedEntries.count - 1, current + delta))
        }
        if extending {
            let anchor = selectionAnchorIndex ?? (current >= 0 ? current : nextIndex)
            selectionAnchorIndex = anchor
            let range = IndexSet(integersIn: min(anchor, nextIndex)...max(anchor, nextIndex))
            selectedEntryIndices = range
            selectionFocusIndex = nextIndex
            onSelectionChange?()
            return
        }
        setMultiSelection(IndexSet(integer: nextIndex), anchor: nextIndex)
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
        if case .folder = sidebarMode { return true }
        return false
    }

    var showsBrowseSearch: Bool {
        // Temporarily hidden from the browse toolbar.
        false
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
        case .folder:
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
        if case .folder = sidebarMode { return !sourceEntries.isEmpty || isFiltering }
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
        case .folder:
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
        case .folder(let root):
            guard let current = currentDirectoryURL else {
                guard let root else { return [] }
                return [(title: root.displayName, url: root.directoryURL)]
            }
            return breadcrumbTrail(root: root, current: current).map { (title: $0.title, url: $0.url) }
        }
    }

    private func breadcrumbTrail(root: MediaLibraryRoot?, current: URL) -> [(title: String, url: URL)] {
        guard let root else { return Self.folderBreadcrumbTrail(for: current) }
        return breadcrumbPathComponents(root: root, current: current)
    }

    /// Trail for a folder with no library root above it. Anchored at the home directory when
    /// the folder sits inside it, so it reads like the Finder path instead of starting at `/`.
    static func folderBreadcrumbTrail(
        for folder: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [(title: String, url: URL)] {
        let target = folder.standardizedFileURL
        let homeURL = home.standardizedFileURL
        let anchor: URL
        if target.path == homeURL.path || target.path.hasPrefix(homeURL.path + "/") {
            anchor = homeURL
        } else {
            anchor = URL(fileURLWithPath: "/", isDirectory: true)
        }

        var trail: [(title: String, url: URL)] = [
            (title: anchor.path == "/" ? "Computer" : anchor.lastPathComponent, url: anchor)
        ]
        var url = anchor
        let remainder = target.path.dropFirst(anchor.path == "/" ? 1 : anchor.path.count)
        for part in remainder.split(separator: "/") {
            url = url.appendingPathComponent(String(part), isDirectory: true)
            trail.append((title: String(part), url: url))
        }
        return trail
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
