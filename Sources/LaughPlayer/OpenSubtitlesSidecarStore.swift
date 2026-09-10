import Foundation

/// Where to write a downloaded sidecar relative to the playing video.
enum OpenSubtitlesSidecarStore {
    /// Prefers an existing `Subs/` or `subtitles/` folder beside the video; otherwise the video folder.
    static func destinationURL(
        forVideo videoURL: URL,
        language: String,
        suggestedFileName: String?
    ) -> URL {
        let folder = companionFolder(for: videoURL) ?? videoURL.deletingLastPathComponent()
        let basename = videoURL.deletingPathExtension().lastPathComponent
        let lang = language.lowercased()
        if let suggested = suggestedFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !suggested.isEmpty {
            let ext = (suggested as NSString).pathExtension.lowercased()
            if ["srt", "vtt", "ass", "ssa"].contains(ext) {
                return folder.appendingPathComponent(suggested)
            }
            return folder.appendingPathComponent("\(suggested).srt")
        }
        return folder.appendingPathComponent("\(basename).\(lang).srt")
    }

    static func write(_ data: Data, to destination: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private static func companionFolder(for videoURL: URL) -> URL? {
        let parent = videoURL.deletingLastPathComponent()
        let fm = FileManager.default
        for name in ["Subs", "subs", "Subtitles", "subtitles"] {
            let candidate = parent.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
        }
        return nil
    }
}
