import Foundation

/// Persisted favorites and star ratings for still images (keyed by absolute path).
enum ImageLibraryMetaStore {
    private static let favoritesKey = "ImageLibraryFavorites"
    private static let ratingsKey = "ImageLibraryRatings"

    private static var defaults: UserDefaults { .standard }

    static func isFavorite(path: String) -> Bool {
        favoritePaths().contains(path)
    }

    /// Favorited image files that still exist on disk (missing paths omitted).
    static func favoritedImageFiles() -> [LibraryMediaFile] {
        favoritePaths().compactMap { path in
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  MediaKindDetector.kind(for: url) == .image
            else {
                return nil
            }
            return LibraryMediaFile(url: url, kind: .image)
        }
        .sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
    }

    static func setFavorite(_ favorite: Bool, path: String) {
        var set = favoritePaths()
        if favorite {
            set.insert(path)
        } else {
            set.remove(path)
        }
        defaults.set(Array(set), forKey: favoritesKey)
    }

    static func rating(path: String) -> Int {
        let map = ratingsMap()
        return max(0, min(5, map[path] ?? 0))
    }

    static func setRating(_ rating: Int, path: String) {
        var map = ratingsMap()
        let clamped = max(0, min(5, rating))
        if clamped == 0 {
            map.removeValue(forKey: path)
        } else {
            map[path] = clamped
        }
        defaults.set(map, forKey: ratingsKey)
    }

    private static func favoritePaths() -> Set<String> {
        Set(defaults.stringArray(forKey: favoritesKey) ?? [])
    }

    private static func ratingsMap() -> [String: Int] {
        (defaults.dictionary(forKey: ratingsKey) as? [String: Int]) ?? [:]
    }
}
