import Foundation

enum LibraryBrowseSortKey: String, CaseIterable, Codable {
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

    /// Finder-like default direction when the user picks this key.
    var preferredDirection: LibraryBrowseSortDirection {
        switch self {
        case .dateModified, .dateAdded, .size:
            return .descending
        case .name, .kind:
            return .ascending
        }
    }

    var isDateKey: Bool {
        self == .dateModified || self == .dateAdded
    }
}

enum LibraryBrowseSortDirection: String, Equatable, Codable {
    case ascending
    case descending

    func menuTitle(for key: LibraryBrowseSortKey) -> String {
        switch key {
        case .dateModified, .dateAdded:
            switch self {
            case .ascending: return "Oldest First"
            case .descending: return "Newest First"
            }
        case .name:
            switch self {
            case .ascending: return "A to Z"
            case .descending: return "Z to A"
            }
        case .size:
            switch self {
            case .ascending: return "Smallest First"
            case .descending: return "Largest First"
            }
        case .kind:
            switch self {
            case .ascending: return "Ascending"
            case .descending: return "Descending"
            }
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

struct LibraryBrowseSort: Equatable, Codable {
    var key: LibraryBrowseSortKey
    var direction: LibraryBrowseSortDirection

    static let `default` = LibraryBrowseSort(key: .name, direction: .ascending)

    /// Applies a new sort key and switches to that key’s Finder-like direction.
    mutating func selectKey(_ key: LibraryBrowseSortKey) {
        self.key = key
        direction = key.preferredDirection
    }
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

/// Resolves “Date Added” the way Finder does: when the item was added to its parent directory.
enum LibraryBrowseDateMetadata {
    static func dateAdded(addedToDirectory: Date?, creation: Date?) -> Date? {
        addedToDirectory ?? creation
    }
}

enum LibraryBrowseItemSorter {
    static func sorted(_ entries: [LibraryBrowseEntry], by sort: LibraryBrowseSort) -> [LibraryBrowseEntry] {
        entries.sorted { lhs, rhs in
            let primary = compare(lhs, rhs, key: sort.key)
            if primary != .orderedSame {
                return sort.direction == .ascending
                    ? primary == .orderedAscending
                    : primary == .orderedDescending
            }
            let nameOrder = lhs.name.compare(rhs.name, options: [.numeric, .caseInsensitive])
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.name < rhs.name
        }
    }

    private static func compare(
        _ lhs: LibraryBrowseEntry,
        _ rhs: LibraryBrowseEntry,
        key: LibraryBrowseSortKey
    ) -> ComparisonResult {
        switch key {
        case .kind:
            let lk = kindRank(lhs)
            let rk = kindRank(rhs)
            if lk != rk {
                return lk < rk ? .orderedAscending : .orderedDescending
            }
            return .orderedSame
        case .name:
            if lhs.isFolder != rhs.isFolder {
                return lhs.isFolder ? .orderedAscending : .orderedDescending
            }
            return lhs.name.compare(rhs.name, options: [.numeric, .caseInsensitive])
        case .dateModified:
            return compareDates(lhs.dateModified, rhs.dateModified)
        case .dateAdded:
            return compareDates(lhs.dateAdded, rhs.dateAdded)
        case .size:
            let ls = lhs.size ?? 0
            let rs = rhs.size ?? 0
            if ls == rs { return .orderedSame }
            return ls < rs ? .orderedAscending : .orderedDescending
        }
    }

    private static func compareDates(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        let left = lhs ?? .distantPast
        let right = rhs ?? .distantPast
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
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
