import Foundation

enum LibraryBrowseSortKey: String, CaseIterable {
    case name
    case dateModified
    case dateAdded
    case size
    case kind

    var menuTitle: String {
        switch self {
        case .name: return "Name"
        case .dateModified: return "Date Modified"
        case .dateAdded: return "Date Added"
        case .size: return "Size"
        case .kind: return "Kind"
        }
    }
}

enum LibraryBrowseSortDirection: Equatable {
    case ascending
    case descending

    var menuTitle: String {
        switch self {
        case .ascending: return "Ascending"
        case .descending: return "Descending"
        }
    }

    static let ascendingMenuTag = 0
    static let descendingMenuTag = 1

    init?(menuTag: Int) {
        switch menuTag {
        case Self.ascendingMenuTag: self = .ascending
        case Self.descendingMenuTag: self = .descending
        default: return nil
        }
    }
}

struct LibraryBrowseSort: Equatable {
    var key: LibraryBrowseSortKey
    var direction: LibraryBrowseSortDirection

    static let `default` = LibraryBrowseSort(key: .name, direction: .ascending)
}

extension LibraryBrowseSortKey {
    var menuTag: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    init?(menuTag: Int) {
        guard menuTag >= 0, menuTag < Self.allCases.count else { return nil }
        self = Self.allCases[menuTag]
    }
}

enum LibraryBrowseItemSorter {
    static func sorted(_ entries: [LibraryBrowseEntry], by sort: LibraryBrowseSort) -> [LibraryBrowseEntry] {
        entries.sorted { lhs, rhs in
            let order = compare(lhs, rhs, key: sort.key)
            return sort.direction == .ascending ? order : !order
        }
    }

    private static func compare(_ lhs: LibraryBrowseEntry, _ rhs: LibraryBrowseEntry, key: LibraryBrowseSortKey) -> Bool {
        switch key {
        case .kind:
            let lk = kindRank(lhs)
            let rk = kindRank(rhs)
            if lk != rk { return lk < rk }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .name:
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder && !rhs.isFolder }
            return lhs.name.compare(rhs.name, options: [.numeric, .caseInsensitive]) == .orderedAscending
        case .dateModified:
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder && !rhs.isFolder }
            return (lhs.dateModified ?? .distantPast) < (rhs.dateModified ?? .distantPast)
        case .dateAdded:
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder && !rhs.isFolder }
            return (lhs.dateAdded ?? .distantPast) < (rhs.dateAdded ?? .distantPast)
        case .size:
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder && !rhs.isFolder }
            return (lhs.size ?? 0) < (rhs.size ?? 0)
        }
    }

    private static func kindRank(_ entry: LibraryBrowseEntry) -> Int {
        switch entry.kind {
        case .folder: return 0
        case .media(let file):
            switch file.kind {
            case .image: return 1
            case .video: return 2
            case .unsupported: return 3
            }
        }
    }
}
