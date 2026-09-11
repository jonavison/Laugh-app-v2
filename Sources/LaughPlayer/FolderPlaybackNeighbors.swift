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
}
