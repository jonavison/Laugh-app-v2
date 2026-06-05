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

    static func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    static func discover(for mediaURL: URL) -> [DiscoveredCompanionSubtitle] {
        let mediaBasename = mediaURL.deletingPathExtension().lastPathComponent
        guard !mediaBasename.isEmpty else { return [] }

        var seenPaths = Set<String>()
        var results: [DiscoveredCompanionSubtitle] = []

        for directory in searchDirectories(for: mediaURL) {
            let episodeSpecific = isEpisodeSpecificSubtitleDirectory(directory, mediaURL: mediaURL)
            let flatSubtitleFolder = isFlatSubtitleFolder(directory)
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
                let parsed: ParsedFilename?
                if episodeSpecific || flatSubtitleFolder {
                    parsed = parseLooseSubtitleFilename(fileURL.lastPathComponent)
                } else {
                    parsed = parseSubtitleFilename(
                        fileURL.lastPathComponent,
                        mediaBasename: mediaBasename
                    )
                }
                guard let parsed else { continue }
                results.append(
                    DiscoveredCompanionSubtitle(
                        url: fileURL.standardizedFileURL,
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

        if let entries = try? FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }
                guard subtitleFolderNames.contains(entry.lastPathComponent.lowercased()) else { continue }
                directories.append(entry)
                if let episodeDir = resolveChildDirectory(named: basename, in: entry) {
                    directories.append(episodeDir)
                }
            }
        } else {
            for folderName in subtitleFolderNames {
                let flat = parent.appendingPathComponent(folderName, isDirectory: true)
                directories.append(flat)
                directories.append(flat.appendingPathComponent(basename, isDirectory: true))
            }
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

    private static func resolveChildDirectory(named name: String, in parent: URL) -> URL? {
        var isDir: ObjCBool = false
        let direct = parent.appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: direct.path, isDirectory: &isDir), isDir.boolValue {
            return direct
        }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return children.first { entry in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
            return entry.lastPathComponent.compare(name, options: .caseInsensitive) == .orderedSame
        }
    }

    private static func isFlatSubtitleFolder(_ directory: URL) -> Bool {
        subtitleFolderNames.contains(directory.lastPathComponent.lowercased())
    }

    private static func isEpisodeSpecificSubtitleDirectory(_ directory: URL, mediaURL: URL) -> Bool {
        let basename = mediaURL.deletingPathExtension().lastPathComponent
        let parentName = directory.deletingLastPathComponent().lastPathComponent.lowercased()
        guard subtitleFolderNames.contains(parentName) else { return false }
        return directory.lastPathComponent.compare(basename, options: .caseInsensitive) == .orderedSame
    }

    private static func usesLooseSubtitleFilenameParsing(for fileURL: URL, mediaURL: URL) -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        return isFlatSubtitleFolder(directory)
            || isEpisodeSpecificSubtitleDirectory(directory, mediaURL: mediaURL)
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

    /// Accepts any subtitle in a Plex-style `Subs/<basename>/` folder (e.g. `2_English.srt`).
    private static func parseLooseSubtitleFilename(_ filename: String) -> ParsedFilename? {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard subtitleExtensions.contains(ext) else { return nil }

        var stem = (filename as NSString).deletingPathExtension
        var isForced = false
        if stem.lowercased().hasSuffix(".forced") {
            isForced = true
            stem = String(stem.dropLast(".forced".count))
        }

        if let underscore = stem.lastIndex(of: "_") {
            let languageToken = String(stem[stem.index(after: underscore)...])
            if let language = languageLabel(from: languageToken) {
                return ParsedFilename(language: language, isForced: isForced)
            }
        }

        if let language = languageLabel(from: stem) {
            return ParsedFilename(language: language, isForced: isForced)
        }

        return ParsedFilename(language: nil, isForced: isForced)
    }

    private static func languageLabel(from token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.caseInsensitiveCompare("forced") == .orderedSame { return nil }
        return AudioTrackLanguageDisplay.displayName(for: trimmed) ?? trimmed
    }

    static func subtitleTracks(
        from companions: [DiscoveredCompanionSubtitle],
        startingDisplayIndex: Int = 0
    ) -> [SubtitleTrackInfo] {
        companions.enumerated().map { offset, companion in
            SubtitleTrackInfo(
                backendID: .companionSidecar(path: normalizePath(companion.url.path)),
                displayIndex: startingDisplayIndex + offset + 1,
                language: companion.language,
                title: companion.isForced ? "Forced" : companion.url.deletingPathExtension().lastPathComponent,
                codec: companion.url.pathExtension.lowercased()
            )
        }
    }

    /// Fills language/title on mpv external tracks when the path matches a sidecar naming pattern.
    static func enrich(_ track: SubtitleTrackInfo, mediaURL: URL?) -> SubtitleTrackInfo {
        guard let mediaURL else { return track }
        if case .companionSidecar = track.backendID {
            return track
        }
        guard case .externalMpv(let trackID, let path) = track.backendID else {
            return track
        }
        let filename = (path as NSString).lastPathComponent
        let mediaBasename = mediaURL.deletingPathExtension().lastPathComponent
        let fileURL = URL(fileURLWithPath: path)
        let parsed: ParsedFilename?
        if usesLooseSubtitleFilenameParsing(for: fileURL, mediaURL: mediaURL) {
            parsed = parseLooseSubtitleFilename(filename)
        } else {
            parsed = parseSubtitleFilename(filename, mediaBasename: mediaBasename)
        }
        guard let parsed else { return track }
        return SubtitleTrackInfo(
            backendID: .externalMpv(trackID: trackID, path: path),
            displayIndex: track.displayIndex,
            language: parsed.language ?? track.language,
            title: parsed.isForced ? "Forced" : track.title,
            codec: track.codec
        )
    }
}
