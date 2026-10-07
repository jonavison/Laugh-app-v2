import Foundation

/// Last active batch develop set (ADR 0006). Survives quit so relaunch can restore
/// the shared wet look, Dry/Wet amounts, and membership — not only flattened per-image edits.
struct ImageBatchSessionRecord: Equatable, Codable {
    var orderedPaths: [String]
    var wetParameters: ImageAdjustParameters
    var mixByPath: [String: Double]
    var dryByPath: [String: ImageAdjustParameters]
}

enum ImageBatchSessionStore {
    private static let key = "ImageBatchSession"
    private static var defaults: UserDefaults { .standard }

    static func load() -> ImageBatchSessionRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ImageBatchSessionRecord.self, from: data)
    }

    static func save(_ record: ImageBatchSessionRecord) {
        guard record.orderedPaths.count >= 2 else {
            clear()
            return
        }
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }

    /// Test seam.
    static func removeAllForTesting() {
        clear()
    }
}
