import Foundation

/// One sidecar subtitle file found by **CompanionSubtitleDiscovery** beside **VideoMedia**.
struct DiscoveredCompanionSubtitle: Equatable {
    let url: URL
    let language: String?
    let isForced: Bool

    var menuTitle: String {
        var parts: [String] = [url.lastPathComponent]
        if let language, !language.isEmpty {
            parts.insert(language, at: 0)
        }
        if isForced {
            parts.append("Forced")
        }
        return parts.joined(separator: " · ")
    }
}

/// Finds **CompanionSubtitleFile**s per **CompanionSubtitleDiscovery** rules in CONTEXT.md.
enum CompanionSubtitleDiscovery {
    static let subtitleExtensions: Set<String> = ["srt", "vtt", "ass", "ssa"]
    private static let subtitleFolderNames = ["subs", "subtitles"]

    static func discover(for mediaURL: URL) -> [DiscoveredCompanionSubtitle] {
        let mediaBasename = mediaURL.deletingPathExtension().lastPathComponent
        guard !mediaBasename.isEmpty else { return [] }

        var seenPaths = Set<String>()
        var results: [DiscoveredCompanionSubtitle] = []

        for directory in searchDirectories(for: mediaURL) {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for fileURL in files {
                guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    continue
                }
                let standardized = fileURL.standardizedFileURL.path
                guard seenPaths.insert(standardized).inserted else { continue }
                guard let parsed = parseSubtitleFilename(
                    fileURL.lastPathComponent,
                    mediaBasename: mediaBasename
                ) else {
                    continue
                }
                results.append(
                    DiscoveredCompanionSubtitle(
                        url: fileURL,
                        language: parsed.language,
                        isForced: parsed.isForced
                    )
                )
            }
        }

        return results.sorted { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }
    }

    /// Search roots: media folder, flat `Subs/`/`subtitles/`, and `Subs/<basename>/`.
    private static func searchDirectories(for mediaURL: URL) -> [URL] {
        let parent = mediaURL.deletingLastPathComponent()
        let basename = mediaURL.deletingPathExtension().lastPathComponent
        var directories: [URL] = [parent]

        for folderName in subtitleFolderNames {
            let flat = parent.appendingPathComponent(folderName, isDirectory: true)
            directories.append(flat)
            directories.append(flat.appendingPathComponent(basename, isDirectory: true))
        }

        var unique: [URL] = []
        var seen = Set<String>()
        for url in directories {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                unique.append(url)
            }
        }
        return unique
    }

    private struct ParsedFilename {
        let language: String?
        let isForced: Bool
    }

    private static func parseSubtitleFilename(_ filename: String, mediaBasename: String) -> ParsedFilename? {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard subtitleExtensions.contains(ext) else { return nil }

        let stem = (filename as NSString).deletingPathExtension
        let baseLower = mediaBasename.lowercased()
        let stemLower = stem.lowercased()

        if stemLower == baseLower {
            return ParsedFilename(language: nil, isForced: false)
        }

        guard stemLower.hasPrefix(baseLower + ".") else { return nil }

        let suffix = String(stemLower.dropFirst(baseLower.count + 1))
        let parts = suffix.split(separator: ".").map { String($0) }
        guard !parts.isEmpty, parts.count <= 2 else { return nil }

        if parts.count == 1 {
            if parts[0].caseInsensitiveCompare("forced") == .orderedSame {
                return ParsedFilename(language: nil, isForced: true)
            }
            guard let language = languageLabel(from: parts[0]) else { return nil }
            return ParsedFilename(language: language, isForced: false)
        }

        guard let language = languageLabel(from: parts[0]),
              parts[1].caseInsensitiveCompare("forced") == .orderedSame else {
            return nil
        }
        return ParsedFilename(language: language, isForced: true)
    }

    private static func languageLabel(from token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.caseInsensitiveCompare("forced") == .orderedSame { return nil }
        return AudioTrackLanguageDisplay.displayName(for: trimmed) ?? trimmed
    }

    /// Fills language/title on mpv external tracks when the path matches a sidecar naming pattern.
    static func enrich(_ track: SubtitleTrackInfo, mediaURL: URL?) -> SubtitleTrackInfo {
        guard let mediaURL,
              case .externalMpv(let trackID, let path) = track.backendID else {
            return track
        }
        let filename = (path as NSString).lastPathComponent
        let mediaBasename = mediaURL.deletingPathExtension().lastPathComponent
        guard let parsed = parseSubtitleFilename(filename, mediaBasename: mediaBasename) else {
            return track
        }
        return SubtitleTrackInfo(
            backendID: .externalMpv(trackID: trackID, path: path),
            displayIndex: track.displayIndex,
            language: parsed.language ?? track.language,
            title: parsed.isForced ? "Forced" : track.title,
            codec: track.codec
        )
    }
}
