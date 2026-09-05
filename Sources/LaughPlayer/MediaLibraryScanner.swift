import Foundation

struct LibraryMediaFile: Equatable {
    let url: URL
    let kind: DroppedMediaKind
}

struct LibraryBrowseEntry: Equatable {
    enum Kind: Equatable {
        case folder(URL)
        case media(LibraryMediaFile)
    }

    let kind: Kind
    let name: String
    let dateModified: Date?
    let dateAdded: Date?
    let size: Int64?

    var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }
}

struct FolderMediaCounts: Equatable {
    var videos: Int
    var images: Int

    var total: Int { videos + images }
    var isEmpty: Bool { total == 0 }

    /// Short badge label: `999`, `1.5k`, `20k`, `200k`, `1.2M`.
    static func compactLabel(_ count: Int) -> String {
        switch count {
        case ..<0:
            return "0"
        case 0..<1_000:
            return "\(count)"
        case 1_000..<10_000:
            let tenths = (count + 50) / 100
            if tenths % 10 == 0 {
                return "\(tenths / 10)k"
            }
            return String(format: "%d.%dk", tenths / 10, tenths % 10)
        case 10_000..<1_000_000:
            return "\(count / 1_000)k"
        case 1_000_000..<10_000_000:
            let tenths = (count + 50_000) / 100_000
            if tenths % 10 == 0 {
                return "\(tenths / 10)M"
            }
            return String(format: "%d.%dM", tenths / 10, tenths % 10)
        default:
            return "\(count / 1_000_000)M"
        }
    }

    static func fullLabel(_ count: Int, singular: String, plural: String) -> String {
        let formatted = Self.groupedNumberFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return "\(formatted) \(count == 1 ? singular : plural)"
    }

    private static let groupedNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = Locale.current.groupingSeparator
        return formatter
    }()
}

enum MediaLibraryScanner {
    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .contentModificationDateKey,
        .creationDateKey,
        .fileSizeKey
    ]

    private static let countsCache = NSCache<NSString, FolderMediaCountsBox>()

    static func browseEntries(in directory: URL) -> [LibraryBrowseEntry] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entries: [LibraryBrowseEntry] = []
        for url in contents {
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            if values?.isDirectory == true {
                entries.append(
                    LibraryBrowseEntry(
                        kind: .folder(url),
                        name: url.lastPathComponent,
                        dateModified: values?.contentModificationDate,
                        dateAdded: values?.creationDate,
                        size: nil
                    )
                )
                continue
            }

            let mediaKind = MediaKindDetector.kind(for: url)
            guard mediaKind == .video || mediaKind == .image else { continue }
            entries.append(
                LibraryBrowseEntry(
                    kind: .media(LibraryMediaFile(url: url, kind: mediaKind)),
                    name: url.lastPathComponent,
                    dateModified: values?.contentModificationDate,
                    dateAdded: values?.creationDate,
                    size: values?.fileSize.map(Int64.init)
                )
            )
        }

        return entries
    }

    /// Direct-child video/image counts for a folder tile badge (non-recursive).
    /// Streams the directory so folders with 100k+ files stay memory-safe.
    static func mediaCounts(in directory: URL) -> FolderMediaCounts {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return FolderMediaCounts(videos: 0, images: 0)
        }

        let modified = (try? directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
        let cacheKey = "\(directory.path)|\(modified.timeIntervalSince1970)" as NSString
        if let cached = countsCache.object(forKey: cacheKey)?.counts {
            return cached
        }

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return FolderMediaCounts(videos: 0, images: 0)
        }

        var videos = 0
        var images = 0
        for case let url as URL in enumerator {
            // Fast path: extension check before directory I/O when possible.
            let kind = MediaKindDetector.kind(for: url)
            if kind == .unsupported {
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true { continue }
            switch kind {
            case .video: videos += 1
            case .image: images += 1
            case .unsupported: break
            }
        }

        let counts = FolderMediaCounts(videos: videos, images: images)
        countsCache.setObject(FolderMediaCountsBox(counts), forKey: cacheKey)
        return counts
    }

    /// Backward-compatible entry for video-only callers.
    static func videoFiles(in directory: URL) -> [URL] {
        browseEntries(in: directory).compactMap { entry in
            guard case .media(let file) = entry.kind, file.kind == .video else { return nil }
            return file.url
        }
    }

    /// Image files in a folder, sorted like the library browse grid.
    static func imageFiles(in directory: URL, sort: LibraryBrowseSort = .default) -> [LibraryMediaFile] {
        let entries = browseEntries(in: directory)
        return LibraryBrowseItemSorter.sorted(entries, by: sort).compactMap { entry in
            guard case .media(let file) = entry.kind, file.kind == .image else { return nil }
            return file
        }
    }
}

private final class FolderMediaCountsBox: NSObject {
    let counts: FolderMediaCounts
    init(_ counts: FolderMediaCounts) { self.counts = counts }
}
