import Foundation

final class LibraryRootsStore {
    static let shared = LibraryRootsStore()

    private let userDefaultsKey = "userLibraryRoots"
    private var scopedURLs: [URL] = []

    private struct StoredRoot: Codable {
        let id: String
        let displayName: String
        let bookmarkData: Data
    }

    private init() {}

    func loadUserRoots() -> [MediaLibraryRoot] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let stored = try? JSONDecoder().decode([StoredRoot].self, from: data) else {
            return []
        }

        return stored.compactMap { item in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: item.bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return nil
            }
            _ = url.startAccessingSecurityScopedResource()
            scopedURLs.append(url)
            return MediaLibraryRoot(
                id: item.id,
                displayName: item.displayName,
                directoryURL: url,
                isUserAdded: true
            )
        }
    }

    @discardableResult
    func addRoot(at url: URL) throws -> MediaLibraryRoot {
        _ = url.startAccessingSecurityScopedResource()
        scopedURLs.append(url)

        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        let id = UUID().uuidString
        let displayName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let stored = StoredRoot(id: id, displayName: displayName, bookmarkData: bookmark)

        var existing = loadStoredRoots()
        let standardized = url.standardizedFileURL
        if existing.contains(where: {
            var isStale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: $0.bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return false
            }
            return resolved.standardizedFileURL == standardized
        }) {
            return MediaLibraryRoot(id: id, displayName: displayName, directoryURL: url, isUserAdded: true)
        }

        existing.append(stored)
        saveStoredRoots(existing)
        return MediaLibraryRoot(id: id, displayName: displayName, directoryURL: url, isUserAdded: true)
    }

    func removeRoot(id: String) {
        var existing = loadStoredRoots()
        existing.removeAll { $0.id == id }
        saveStoredRoots(existing)
    }

    func stopAllSecurityScopedAccess() {
        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        scopedURLs.removeAll()
    }

    private func loadStoredRoots() -> [StoredRoot] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let stored = try? JSONDecoder().decode([StoredRoot].self, from: data) else {
            return []
        }
        return stored
    }

    private func saveStoredRoots(_ roots: [StoredRoot]) {
        if let data = try? JSONEncoder().encode(roots) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
