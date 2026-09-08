import Foundation

struct PlaybackOpenFailure {
    let kind: PlaybackErrorFormatter.Kind
    let userMessage: String
    let debugDetails: String

    var offersFileAccessSettings: Bool { kind == .accessDenied }
}

struct PlaybackUserNotice {
    let kind: PlaybackErrorFormatter.Kind
    let message: String

    var offersFileAccessSettings: Bool { kind == .accessDenied }
}

enum PlaybackErrorFormatter {
    /// Classifies why open/playback failed so the banner can stay short and actionable.
    enum Kind: Equatable {
        case accessDenied
        case missingFile
        case unsupportedOrUnreadable
        case remuxFailed
        /// File exists but its container header is missing, zeroed, or unreadable —
        /// typical of a torrent still downloading, or a truncated/corrupt file.
        case incompleteOrDamaged
        case decoderUnavailable
        case noVideoTrack
        case genericPlayback
    }

    static func describe(_ error: Error?) -> String {
        guard let error else { return "Unknown error" }
        let ns = error as NSError
        var parts = ["domain=\(ns.domain)", "code=\(ns.code)", "desc=\(ns.localizedDescription)"]
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain)/\(underlying.code)/\(underlying.localizedDescription)")
        }
        return parts.joined(separator: ", ")
    }

    static func openFailure(url: URL, reason: String, probeDetails: String?) -> PlaybackOpenFailure {
        let kind = classifyOpenFailure(url: url, reason: reason, probeDetails: probeDetails, error: nil)
        let message = userMessage(kind: kind, url: url, detail: reason)
        var debug = probeDetails ?? ""
        if debug.isEmpty { debug = reason }
        return PlaybackOpenFailure(kind: kind, userMessage: message, debugDetails: debug)
    }

    static func remuxFailedNotice(for url: URL) -> PlaybackUserNotice {
        if matchesAccessProbe(url: url) {
            return PlaybackUserNotice(
                kind: .accessDenied,
                message: userMessage(kind: .accessDenied, url: url, detail: nil)
            )
        }
        if looksLikeMissingFile(url) {
            return PlaybackUserNotice(
                kind: .missingFile,
                message: userMessage(kind: .missingFile, url: url, detail: nil)
            )
        }
        if IncompleteMediaProbe.looksLikeIncompleteDownload(at: url) {
            return incompleteOrDamagedNotice(for: url)
        }
        return PlaybackUserNotice(
            kind: .remuxFailed,
            message: userMessage(kind: .remuxFailed, url: url, detail: nil)
        )
    }

    static func incompleteOrDamagedNotice(for url: URL) -> PlaybackUserNotice {
        PlaybackUserNotice(
            kind: .incompleteOrDamaged,
            message: userMessage(kind: .incompleteOrDamaged, url: url, detail: nil)
        )
    }

    /// Kept for call sites that named the torrent case; same notice as `incompleteOrDamagedNotice`.
    static func incompleteDownloadNotice(for url: URL) -> PlaybackUserNotice {
        incompleteOrDamagedNotice(for: url)
    }

    static func remuxFailedMessage(for url: URL) -> String {
        remuxFailedNotice(for: url).message
    }

    static func accessDeniedNotice(for url: URL) -> PlaybackUserNotice {
        PlaybackUserNotice(
            kind: .accessDenied,
            message: userMessage(kind: .accessDenied, url: url, detail: nil)
        )
    }

    static func missingFileNotice(for url: URL) -> PlaybackUserNotice {
        PlaybackUserNotice(
            kind: .missingFile,
            message: userMessage(kind: .missingFile, url: url, detail: nil)
        )
    }

    static func playbackItemFailedNotice(url: URL?, error: Error?) -> PlaybackUserNotice {
        let resolved = url ?? URL(fileURLWithPath: "/")
        let kind = classifyOpenFailure(
            url: resolved,
            reason: error?.localizedDescription ?? "Playback failed",
            probeDetails: describe(error),
            error: error
        )
        return PlaybackUserNotice(
            kind: kind,
            message: userMessage(kind: kind, url: resolved, detail: shortDetail(from: error))
        )
    }

    static func playbackItemFailedMessage(url: URL?, error: Error?) -> String {
        playbackItemFailedNotice(url: url, error: error).message
    }

    static func noVideoTrackMessage() -> String {
        userMessage(kind: .noVideoTrack, url: URL(fileURLWithPath: "/"), detail: nil)
    }

    static func decoderUnavailableMessage(lookup: String) -> String {
        var message = userMessage(kind: .decoderUnavailable, url: URL(fileURLWithPath: "/"), detail: nil)
        if !lookup.isEmpty {
            message += "\n\n\(lookup)"
        }
        return message
    }

    static func classifyOpenFailure(
        url: URL,
        reason: String,
        probeDetails: String?,
        error: Error?
    ) -> Kind {
        // Prefer explicit signals over filesystem heuristics (TCC denial often looks like "missing").
        if matchesAccess(reason) || matchesAccess(probeDetails) || isAccessError(error) {
            return .accessDenied
        }
        if matchesMissing(reason) || matchesMissing(probeDetails) {
            return .missingFile
        }
        if matchesAccessProbe(url: url) {
            return .accessDenied
        }
        if looksLikeMissingFile(url) {
            return .missingFile
        }
        return .unsupportedOrUnreadable
    }

    /// True when the path looks blocked by permissions / TCC rather than simply absent.
    static func matchesAccessProbe(url: URL) -> Bool {
        let path = url.path
        guard !path.isEmpty, path != "/" else { return false }
        let fm = FileManager.default
        if fm.fileExists(atPath: path), !fm.isReadableFile(atPath: path) {
            return true
        }
        if !fm.fileExists(atPath: path), !isParentDirectoryReadable(url) {
            // Missing + unlistable parent is the usual shape of denied volume/folder access.
            return true
        }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.close()
            return false
        } catch let error as NSError {
            return isAccessError(error)
        } catch {
            return false
        }
    }

    static func looksLikeAccessProblem(url: URL) -> Bool {
        matchesAccessProbe(url: url)
    }

    static func looksLikeMissingFile(_ url: URL) -> Bool {
        let path = url.path
        guard !path.isEmpty, path != "/" else { return false }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: path) else { return false }
        // Only call it missing when we can see the parent folder (file really gone).
        return isParentDirectoryReadable(url)
    }

    static func isAccessError(_ error: Error?) -> Bool {
        guard let error else { return false }
        return isAccessNSError(error as NSError)
    }

    private static func isParentDirectoryReadable(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent()
        let parentPath = parent.path
        guard !parentPath.isEmpty, parentPath != "/" else { return false }
        let fm = FileManager.default
        guard fm.fileExists(atPath: parentPath) else { return false }
        return fm.isReadableFile(atPath: parentPath)
    }

    // MARK: - Messages

    static func userMessage(kind: Kind, url: URL, detail: String?) -> String {
        switch kind {
        case .accessDenied:
            return "Can't read this file. Allow LaughPlayer in Files and Folders, then open the file again."
        case .missingFile:
            return "This file wasn't found. Check that the drive is connected and the file is still there."
        case .unsupportedOrUnreadable:
            var message = "This video can't play with macOS's built-in decoder."
            if let tip = compatibilityTip(for: url) {
                message += "\n\n\(tip)"
            }
            return message
        case .remuxFailed:
            var message = "Couldn't prepare this video for playback."
            if PlaybackRuntime.canUseBundledCodecStack, !FFmpegVideoFallback.isHeavyTranscodeEnabled {
                message += "\n\nTip: set LAUGH_ENABLE_HEAVY_TRANSCODE=1 for a slower full-convert fallback."
            }
            return message
        case .incompleteOrDamaged:
            return "This video's file header looks missing or damaged — often a download that hasn't finished, or a corrupt file. Wait for the download to finish (or re-download), then open it again."
        case .decoderUnavailable:
            return "This video needs LaughPlayer's compatibility tools, which aren't available in this build."
        case .noVideoTrack:
            return "This file has no playable video track."
        case .genericPlayback:
            if let detail, !detail.isEmpty {
                return "Playback failed.\n\n\(detail)"
            }
            return "Playback failed."
        }
    }

    private static func compatibilityTip(for url: URL) -> String? {
        guard PlaybackRuntime.canUseBundledCodecStack else { return nil }
        if FFmpegVideoFallback.isAvailable() {
            return "LaughPlayer will try a compatibility remux when available."
        }
        return "Bundled ffmpeg was not found. Run ./scripts/bundle-codec-tools.sh and rebuild."
    }

    private static func shortDetail(from error: Error?) -> String? {
        guard let error else { return nil }
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Avoid dumping raw Cocoa domain codes into the banner.
        if matchesAccess(text) || matchesMissing(text) {
            return nil
        }
        return text
    }

    private static func matchesAccess(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        let lowered = text.lowercased()
        let needles = [
            "permission denied",
            "operation not permitted",
            "not readable",
            "no permission",
            "access denied",
            "user denied",
            "nofilereadnopermission",
            "nsfilereadnopermissionerror",
            "code=257",
            "eacces",
            "eperm"
        ]
        return needles.contains { lowered.contains($0) }
    }

    private static func matchesMissing(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        let lowered = text.lowercased()
        return lowered.contains("file not found")
            || lowered.contains("path missing")
            || lowered.contains("no such file")
            || lowered.contains("doesn't exist")
            || lowered.contains("does not exist")
    }

    private static func isAccessNSError(_ error: NSError) -> Bool {
        if matchesAccess(error.localizedDescription) {
            return true
        }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EACCES) || error.code == Int(EPERM) {
            return true
        }
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isAccessNSError(underlying)
        }
        return false
    }
}
