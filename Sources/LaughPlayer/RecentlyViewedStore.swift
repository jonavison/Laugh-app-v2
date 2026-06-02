import Foundation

final class RecentlyViewedStore {
    static let shared = RecentlyViewedStore()

    private let userDefaultsKey = "recentlyViewedMedia"
    private let maxItems = 50

    private struct StoredItem: Codable {
        let path: String
        let kindRaw: String
        let lastOpened: Date
    }

    private init() {}

    func record(url: URL, kind: DroppedMediaKind) {
        guard kind == .video || kind == .image else { return }

        var items = loadStored()
        let path = url.standardizedFileURL.path
        items.removeAll { $0.path == path }
        items.insert(
            StoredItem(path: path, kindRaw: kind == .video ? "video" : "image", lastOpened: Date()),
            at: 0
        )
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    func mediaFiles(limit: Int? = nil) -> [LibraryMediaFile] {
        let all = loadStored().compactMap { stored -> LibraryMediaFile? in
            let url = URL(fileURLWithPath: stored.path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let kind: DroppedMediaKind = stored.kindRaw == "video" ? .video : .image
            guard MediaKindDetector.kind(for: url) == kind else { return nil }
            return LibraryMediaFile(url: url, kind: kind)
        }
        guard let limit else { return all }
        return Array(all.prefix(limit))
    }

    /// Sidebar preview list (max 5).
    func sidebarPreview() -> [LibraryMediaFile] {
        mediaFiles(limit: 5)
    }

    private func loadStored() -> [StoredItem] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let items = try? JSONDecoder().decode([StoredItem].self, from: data) else {
            return []
        }
        return items
    }
}
