import Foundation

/// Remembers where each video was last left, so reopen resumes near that time.
enum PlaybackResumeStore {
    private static let defaultsKey = "PlaybackResumePositions"
    private static let maxItems = 200
    /// Ignore tiny scrub positions (treat as start).
    static let minimumResumeSeconds: Double = 3
    /// Near the end → start over next time.
    static let endCompletionFraction: Double = 0.95
    static let endCompletionRemainingSeconds: Double = 8

    private struct Entry: Codable, Equatable {
        var seconds: Double
        var duration: Double?
        var updatedAt: Date
    }

    /// Seconds to seek on open, or `nil` to start at zero.
    static func resumeSeconds(for url: URL) -> Double? {
        let path = key(for: url)
        guard let entry = load()[path] else { return nil }
        return Self.sanitizedResumeSeconds(entry.seconds, duration: entry.duration)
    }

    /// Persist progress for a source file (original path, not remux cache).
    static func save(seconds: Double, duration: Double?, for url: URL) {
        let path = key(for: url)
        guard !path.isEmpty, !isGeneratedFallbackPath(path) else { return }

        if shouldClear(seconds: seconds, duration: duration) {
            clear(for: url)
            return
        }
        guard seconds >= minimumResumeSeconds else {
            clear(for: url)
            return
        }

        var map = load()
        map[path] = Entry(seconds: seconds, duration: duration, updatedAt: Date())
        if map.count > maxItems {
            let trimmed = map.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(maxItems)
            map = Dictionary(uniqueKeysWithValues: trimmed.map { ($0.key, $0.value) })
        }
        persist(map)
    }

    static func clear(for url: URL) {
        var map = load()
        let path = key(for: url)
        guard map.removeValue(forKey: path) != nil else { return }
        persist(map)
    }

    /// Pure policy used by tests and save/restore.
    static func sanitizedResumeSeconds(_ seconds: Double, duration: Double?) -> Double? {
        guard seconds.isFinite, seconds >= minimumResumeSeconds else { return nil }
        if shouldClear(seconds: seconds, duration: duration) { return nil }
        return seconds
    }

    static func shouldClear(seconds: Double, duration: Double?) -> Bool {
        guard seconds.isFinite, seconds >= 0 else { return true }
        guard let duration, duration.isFinite, duration > minimumResumeSeconds else {
            return false
        }
        // Corrupt / cross-file writes can leave a resume past the real duration.
        if seconds > duration { return true }
        if seconds >= duration - endCompletionRemainingSeconds { return true }
        if seconds / duration >= endCompletionFraction { return true }
        return false
    }

    private static func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private static func load() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let map = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return [:]
        }
        return map.filter { !isGeneratedFallbackPath($0.key) }
    }

    private static func persist(_ map: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static func isGeneratedFallbackPath(_ path: String) -> Bool {
        path.contains("/LaughPlayerFallback/")
    }
}
