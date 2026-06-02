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

enum MediaLibraryScanner {
    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .contentModificationDateKey,
        .creationDateKey,
        .fileSizeKey
    ]

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

    /// Backward-compatible entry for video-only callers.
    static func videoFiles(in directory: URL) -> [URL] {
        browseEntries(in: directory).compactMap { entry in
            guard case .media(let file) = entry.kind, file.kind == .video else { return nil }
            return file.url
        }
    }
}
