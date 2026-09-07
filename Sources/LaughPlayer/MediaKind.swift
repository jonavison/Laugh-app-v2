import Foundation
import UniformTypeIdentifiers

enum ActiveMediaKind {
    case empty
    case video
    case image
}

enum DroppedMediaKind {
    case video
    case image
    case unsupported
}

/// Grid status-line format chip (`● JPEG`, `● RAW`, `● MP4`, …).
enum LibraryMediaFormatFamily: Equatable {
    case photo
    case gif
    case raw
    case video
    case other
}

struct LibraryMediaFormatBadge: Equatable {
    let title: String
    let family: LibraryMediaFormatFamily
}

enum MediaKindDetector {
    private static let imageExtensions: Set<String> = [
        // Everyday stills
        "jpg", "jpeg", "jpe", "jfif", "png", "gif", "apng",
        "heic", "heif", "heics", "hif", "avci", "avcs",
        "webp", "avif", "jxl", "jp2", "j2k", "jpf",
        "bmp", "dib", "tiff", "tif", "tga", "ico", "icns",
        // HDR / scene-linear
        "exr", "hdr",
        // Design / layered (ImageIO / Quick Look when available)
        "psd",
        // Camera RAW
        "nef", "nrw", "cr2", "cr3", "crw", "arw", "sr2", "srf",
        "dng", "raf", "orf", "rw2", "pef", "ptx", "raw", "srw",
        "mrw", "dcr", "kdc", "erf", "3fr", "fff", "mef", "mos",
        "rwl", "x3f", "bay", "cap", "iiq", "rdc"
    ]

    private static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "qt",
        "mkv", "webm", "avi", "divx",
        "mpg", "mpeg", "m1v", "m2v", "mpv",
        "m2ts", "mts", "ts", "vob",
        "wmv", "asf", "flv", "f4v",
        "ogv", "ogm", "3gp", "3g2",
        "dv", "mxf", "rm", "rmvb",
        // Cinema / camera originals (thumb via ffmpeg when available)
        "braw", "r3d"
    ]

    private static let rawExtensions: Set<String> = [
        "nef", "nrw", "cr2", "cr3", "crw", "arw", "sr2", "srf",
        "dng", "raf", "orf", "rw2", "pef", "ptx", "raw", "srw",
        "mrw", "dcr", "kdc", "erf", "3fr", "fff", "mef", "mos",
        "rwl", "x3f", "bay", "cap", "iiq", "rdc"
    ]

    private static let gifExtensions: Set<String> = [
        "gif", "apng"
    ]

    static func kind(for url: URL) -> DroppedMediaKind {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }

        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent) {
                return .video
            }
        }
        if ext == "mkv", UTType("org.matroska.mkv") != nil {
            return .video
        }
        return .unsupported
    }

    /// Format label for grid status dots — more specific than Image/Video.
    static func formatBadge(for url: URL) -> LibraryMediaFormatBadge {
        let ext = url.pathExtension.lowercased()

        if let mapped = explicitBadge(forExtension: ext) {
            return mapped
        }

        switch kind(for: url) {
        case .image:
            if rawExtensions.contains(ext) {
                return LibraryMediaFormatBadge(title: "RAW", family: .raw)
            }
            if gifExtensions.contains(ext) {
                return LibraryMediaFormatBadge(title: "GIF", family: .gif)
            }
            let title = ext.isEmpty ? "Image" : ext.uppercased()
            return LibraryMediaFormatBadge(title: title, family: .photo)
        case .video:
            let title = ext.isEmpty ? "Video" : ext.uppercased()
            return LibraryMediaFormatBadge(title: title, family: .video)
        case .unsupported:
            let title = ext.isEmpty ? "File" : ext.uppercased()
            return LibraryMediaFormatBadge(title: title, family: .other)
        }
    }

    private static func explicitBadge(forExtension ext: String) -> LibraryMediaFormatBadge? {
        switch ext {
        case "jpg", "jpeg", "jpe", "jfif":
            return LibraryMediaFormatBadge(title: "JPEG", family: .photo)
        case "png":
            return LibraryMediaFormatBadge(title: "PNG", family: .photo)
        case "gif":
            return LibraryMediaFormatBadge(title: "GIF", family: .gif)
        case "apng":
            return LibraryMediaFormatBadge(title: "APNG", family: .gif)
        case "heic", "heif", "hif":
            return LibraryMediaFormatBadge(title: "HEIC", family: .photo)
        case "heics":
            return LibraryMediaFormatBadge(title: "HEICS", family: .photo)
        case "avci", "avcs":
            return LibraryMediaFormatBadge(title: "AVCI", family: .photo)
        case "webp":
            return LibraryMediaFormatBadge(title: "WebP", family: .photo)
        case "avif":
            return LibraryMediaFormatBadge(title: "AVIF", family: .photo)
        case "jxl":
            return LibraryMediaFormatBadge(title: "JXL", family: .photo)
        case "jp2", "j2k", "jpf":
            return LibraryMediaFormatBadge(title: "JP2", family: .photo)
        case "tif", "tiff":
            return LibraryMediaFormatBadge(title: "TIFF", family: .photo)
        case "bmp", "dib":
            return LibraryMediaFormatBadge(title: "BMP", family: .photo)
        case "tga":
            return LibraryMediaFormatBadge(title: "TGA", family: .photo)
        case "ico":
            return LibraryMediaFormatBadge(title: "ICO", family: .photo)
        case "icns":
            return LibraryMediaFormatBadge(title: "ICNS", family: .photo)
        case "exr":
            return LibraryMediaFormatBadge(title: "EXR", family: .photo)
        case "hdr":
            return LibraryMediaFormatBadge(title: "HDR", family: .photo)
        case "psd":
            return LibraryMediaFormatBadge(title: "PSD", family: .photo)
        case let raw where rawExtensions.contains(raw):
            return LibraryMediaFormatBadge(title: "RAW", family: .raw)
        case "mp4", "m4v":
            return LibraryMediaFormatBadge(title: "MP4", family: .video)
        case "mov", "qt":
            return LibraryMediaFormatBadge(title: "MOV", family: .video)
        case "mkv":
            return LibraryMediaFormatBadge(title: "MKV", family: .video)
        case "webm":
            return LibraryMediaFormatBadge(title: "WebM", family: .video)
        case "avi", "divx":
            return LibraryMediaFormatBadge(title: "AVI", family: .video)
        case "mpg", "mpeg", "m1v", "m2v", "mpv":
            return LibraryMediaFormatBadge(title: "MPEG", family: .video)
        case "m2ts", "mts", "ts":
            return LibraryMediaFormatBadge(title: "MTS", family: .video)
        case "vob":
            return LibraryMediaFormatBadge(title: "VOB", family: .video)
        case "wmv", "asf":
            return LibraryMediaFormatBadge(title: "WMV", family: .video)
        case "flv", "f4v":
            return LibraryMediaFormatBadge(title: "FLV", family: .video)
        case "ogv", "ogm":
            return LibraryMediaFormatBadge(title: "OGG", family: .video)
        case "3gp", "3g2":
            return LibraryMediaFormatBadge(title: "3GP", family: .video)
        case "dv":
            return LibraryMediaFormatBadge(title: "DV", family: .video)
        case "mxf":
            return LibraryMediaFormatBadge(title: "MXF", family: .video)
        case "rm", "rmvb":
            return LibraryMediaFormatBadge(title: "RM", family: .video)
        case "braw":
            return LibraryMediaFormatBadge(title: "BRAW", family: .video)
        case "r3d":
            return LibraryMediaFormatBadge(title: "R3D", family: .video)
        default:
            return nil
        }
    }

    static func filterVideos(_ urls: [URL]) -> [URL] {
        urls.filter { kind(for: $0) == .video }
    }

    static func openPanelImageContentTypes() -> [UTType] {
        var types: [UTType] = [.image, .jpeg, .png, .gif, .heic, .tiff, .webP]
        for ext in imageExtensions {
            if let type = UTType(filenameExtension: ext),
               !types.contains(where: { $0.identifier == type.identifier }) {
                types.append(type)
            }
        }
        return types
    }
}
