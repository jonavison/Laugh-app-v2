import Foundation

/// Remembers browse sort per folder path so Downloads can stay Date Modified
/// while a season folder independently stays Name (A→Z).
enum LibraryFolderSortStore {
    private static let defaultsKey = "LibraryBrowseFolderSortV1"
    private static let maxEntries = 250

    private struct Record: Codable {
        var sort: LibraryBrowseSort
        var updatedAt: Date
    }

    static func resolvedSort(for directory: URL, defaults: UserDefaults = .standard) -> LibraryBrowseSort {
        sort(for: directory, defaults: defaults) ?? .default
    }

    static func sort(for directory: URL, defaults: UserDefaults = .standard) -> LibraryBrowseSort? {
        let key = storageKey(for: directory)
        return load(defaults: defaults)[key]?.sort
    }

    static func setSort(_ sort: LibraryBrowseSort, for directory: URL, defaults: UserDefaults = .standard) {
        let key = storageKey(for: directory)
        var records = load(defaults: defaults)
        records[key] = Record(sort: sort, updatedAt: Date())
        if records.count > maxEntries {
            let overflow = records.count - maxEntries
            let oldestKeys = records
                .sorted { $0.value.updatedAt < $1.value.updatedAt }
                .prefix(overflow)
                .map(\.key)
            for old in oldestKeys {
                records.removeValue(forKey: old)
            }
        }
        save(records, defaults: defaults)
    }

    static func clearAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    private static func storageKey(for directory: URL) -> String {
        directory.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func load(defaults: UserDefaults) -> [String: Record] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: Record].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func save(_ records: [String: Record], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
