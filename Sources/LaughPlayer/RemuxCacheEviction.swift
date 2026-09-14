import Foundation

/// Keeps CompatibilityRemux temp MP4s from filling the system temp volume.
///
/// Policy:
/// - **Budget:** soft ceiling for the whole `LaughPlayerFallback/` folder (LRU).
/// - **Per-file cap:** never *retain* a full remux larger than `maxFullRemuxRetainBytes`
///   (120 GB twins are refused; oversized files are deleted when unprotected).
/// - **Previews** (capped progressive packages) are preferred over full remuxes in eviction order.
enum RemuxCacheEviction {
    /// Soft ceiling for `…/T/LaughPlayerFallback/`.
    /// ~a handful of ≤4 GiB remuxes or many small progressive packages — not a film archive.
    static let defaultBudgetBytes: Int64 = 12 * 1024 * 1024 * 1024

    /// Never keep a single full remux above this size. Play huge sources via DirectMpv
    /// (or progressive package only); do not mirror a 120 GB file in temp.
    static let maxFullRemuxRetainBytes: Int64 = 4 * 1024 * 1024 * 1024

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

    /// True when a full remux is small enough to keep for warm reopen.
    static func shouldRetainFullRemux(byteCount: Int64) -> Bool {
        byteCount > 0 && byteCount <= maxFullRemuxRetainBytes
    }

    /// Source files above the retain cap should not drive a retained full remux.
    static func sourceTooLargeForRetainedRemux(byteCount: Int64) -> Bool {
        byteCount > maxFullRemuxRetainBytes
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

    /// Eviction order: oversize full remuxes first, then previews (oldest first),
    /// then remaining full remuxes (oldest first).
    static func deletionOrder(_ entries: [Entry]) -> [Entry] {
        let oversizeFull = entries
            .filter { !$0.isPreview && !shouldRetainFullRemux(byteCount: $0.byteCount) }
            .sorted { $0.modifiedAt < $1.modifiedAt }
        let previews = entries.filter(\.isPreview).sorted { $0.modifiedAt < $1.modifiedAt }
        let full = entries
            .filter { !$0.isPreview && shouldRetainFullRemux(byteCount: $0.byteCount) }
            .sorted { $0.modifiedAt < $1.modifiedAt }
        return oversizeFull + previews + full
    }

    /// Deletes oversize full remuxes (always, unless protected), then oldest files until
    /// `total <= budgetBytes`. Never deletes `protectPaths` (active playback outputs).
    @discardableResult
    static func enforceBudget(
        in directory: URL? = nil,
        budgetBytes: Int64 = defaultBudgetBytes,
        maxFullRemuxBytes: Int64 = maxFullRemuxRetainBytes,
        protectPaths: Set<String> = [],
        fileManager: FileManager = .default
    ) -> Report {
        let root = directory ?? cacheDirectory(fileManager: fileManager)
        let protected = Set(protectPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let entries = listEntries(in: root, fileManager: fileManager)
        var total = entries.reduce(Int64(0)) { $0 + $1.byteCount }
        var deletedCount = 0
        var deletedBytes: Int64 = 0
        var remainingEntries = entries

        func delete(_ entry: Entry) {
            let path = entry.url.standardizedFileURL.path
            if protected.contains(path) { return }
            do {
                try fileManager.removeItem(at: entry.url)
                total -= entry.byteCount
                deletedBytes += entry.byteCount
                deletedCount += 1
                remainingEntries.removeAll { $0.url.standardizedFileURL.path == path }
            } catch {
                return
            }
        }

        // 1) Always drop full remuxes that exceed the per-file retain cap.
        for entry in remainingEntries where !entry.isPreview && entry.byteCount > maxFullRemuxBytes {
            delete(entry)
        }

        // 2) LRU until under the soft folder budget.
        if total > budgetBytes {
            for entry in deletionOrder(remainingEntries) {
                if total <= budgetBytes { break }
                delete(entry)
            }
        }

        return Report(
            deletedCount: deletedCount,
            deletedBytes: deletedBytes,
            remainingBytes: max(0, total),
            fileCount: remainingEntries.count
        )
    }
}
