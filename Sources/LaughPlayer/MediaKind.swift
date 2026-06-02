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

enum MediaKindDetector {
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "bmp", "tiff", "tif", "webp"
    ]

    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "mpg", "mpeg", "m2ts", "ts",
        "wmv", "flv", "ogv", "3gp"
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

    static func filterVideos(_ urls: [URL]) -> [URL] {
        urls.filter { kind(for: $0) == .video }
    }
}
