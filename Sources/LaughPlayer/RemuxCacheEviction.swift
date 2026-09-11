import Foundation

/// Keeps CompatibilityRemux temp MP4s from filling the system temp volume.
enum RemuxCacheEviction {
    /// Soft ceiling for `…/T/LaughPlayerFallback/` — remuxes are near source size, so this is
    /// “a few recent films,” not a permanent archive.
    static let defaultBudgetBytes: Int64 = 12 * 1024 * 1024 * 1024

    struct Report: Equatable {
        var deletedCount: Int
        var deletedBytes: Int64
        var remainingBytes: Int64
        var fileCount: Int
    }

    struct Entry: Equatable {
        let url: URL
        let byteCount: Int64
        let modifiedAt: Date
        let isPreview: Bool
    }

    static func cacheDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.temporaryDirectory.appendingPathComponent("LaughPlayerFallback", isDirectory: true)
    }

    /// Lists remux cache `.mp4` files with size + mtime (for tests and eviction).
    static func listEntries(
        in directory: URL,
        fileManager: FileManager = .default
    ) -> [Entry] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        var entries: [Entry] = []
        for name in names where name.lowercased().hasSuffix(".mp4") {
            let url = directory.appendingPathComponent(name)
            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey
            ]),
                values.isRegularFile == true,
                let size = values.fileSize,
                size >= 0
            else { continue }
            entries.append(
                Entry(
                    url: url,
                    byteCount: Int64(size),
                    modifiedAt: values.contentModificationDate ?? .distantPast,
                    isPreview: name.contains("-preview-")
                )
            )
        }
        return entries
    }

    /// Eviction order: previews first (oldest first), then full remuxes (oldest first).
    static func deletionOrder(_ entries: [Entry]) -> [Entry] {
        let previews = entries.filter(\.isPreview).sorted { $0.modifiedAt < $1.modifiedAt }
        let full = entries.filter { !$0.isPreview }.sorted { $0.modifiedAt < $1.modifiedAt }
        return previews + full
    }

    /// Deletes oldest cache files until `total <= budgetBytes`. Never deletes `protectPaths`.
    @discardableResult
    static func enforceBudget(
        in directory: URL? = nil,
        budgetBytes: Int64 = defaultBudgetBytes,
        protectPaths: Set<String> = [],
        fileManager: FileManager = .default
    ) -> Report {
        let root = directory ?? cacheDirectory(fileManager: fileManager)
        let protected = Set(protectPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let entries = listEntries(in: root, fileManager: fileManager)
        var total = entries.reduce(Int64(0)) { $0 + $1.byteCount }
        var deletedCount = 0
        var deletedBytes: Int64 = 0

        guard total > budgetBytes else {
            return Report(
                deletedCount: 0,
                deletedBytes: 0,
                remainingBytes: total,
                fileCount: entries.count
            )
        }

        for entry in deletionOrder(entries) {
            if total <= budgetBytes { break }
            let path = entry.url.standardizedFileURL.path
            if protected.contains(path) { continue }
            do {
                try fileManager.removeItem(at: entry.url)
                total -= entry.byteCount
                deletedBytes += entry.byteCount
                deletedCount += 1
            } catch {
                continue
            }
        }

        return Report(
            deletedCount: deletedCount,
            deletedBytes: deletedBytes,
            remainingBytes: max(0, total),
            fileCount: entries.count - deletedCount
        )
    }
}
