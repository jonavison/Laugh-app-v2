import Foundation

/// Next/previous media in the same folder, using that folder’s browse sort (e.g. Name A→Z).
enum FolderPlaybackNeighbors {
    struct Result: Equatable {
        var previous: URL?
        var next: URL?
    }

    static func neighbors(
        around url: URL,
        matchingKind kind: DroppedMediaKind,
        sort: LibraryBrowseSort = .default,
        entriesInDirectory: (URL) -> [LibraryBrowseEntry] = { MediaLibraryScanner.browseEntries(in: $0) }
    ) -> Result {
        guard kind == .video || kind == .image else {
            return Result(previous: nil, next: nil)
        }
        let directory = url.deletingLastPathComponent()
        let entries = entriesInDirectory(directory)
        let sorted = LibraryBrowseItemSorter.sorted(entries, by: sort)
        let files: [URL] = sorted.compactMap { entry in
            guard case .media(let file) = entry.kind, file.kind == kind else { return nil }
            return file.url.standardizedFileURL
        }
        let current = url.standardizedFileURL
        guard let index = files.firstIndex(of: current) else {
            return Result(previous: nil, next: nil)
        }
        let previous = index > 0 ? files[index - 1] : nil
        let next = index + 1 < files.count ? files[index + 1] : nil
        return Result(previous: previous, next: next)
    }

    /// Step one item in an already-ordered sibling list (e.g. image filmstrip). No wrap-around.
    static func adjacentURL(in ordered: [URL], around url: URL, forward: Bool) -> URL? {
        let files = ordered.map { $0.standardizedFileURL }
        let current = url.standardizedFileURL
        guard let index = files.firstIndex(of: current) else { return nil }
        let nextIndex = forward ? index + 1 : index - 1
        guard files.indices.contains(nextIndex) else { return nil }
        return ordered[nextIndex]
    }

    /// Step with wrap-around (slideshow). Needs 2+ items; single-item lists return `nil`.
    static func adjacentURLWrapping(in ordered: [URL], around url: URL, forward: Bool) -> URL? {
        guard ordered.count >= 2 else { return nil }
        let files = ordered.map { $0.standardizedFileURL }
        let current = url.standardizedFileURL
        guard let index = files.firstIndex(of: current) else { return nil }
        let count = files.count
        let nextIndex = forward
            ? (index + 1) % count
            : (index - 1 + count) % count
        return ordered[nextIndex]
    }
}
