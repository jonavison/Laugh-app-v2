import Foundation

/// What the open session can actually render right now.
enum SubtitlePlaybackSession: Equatable {
    /// Remux / AVPlayer — text embeds + native sidecars only.
    case remuxText
    /// Remux picture + libmpv PGS/VobSub overlay.
    case remuxWithBitmapOverlay
    /// DirectMpv picture — full mpv track list.
    case directMpv
}

enum SubtitleTrackPlayability {
    static func isPlayable(_ track: SubtitleTrackInfo, session: SubtitlePlaybackSession) -> Bool {
        switch session {
        case .remuxText:
            switch track.backendID {
            case .avFoundation:
                return true
            case .companionSidecar(let path):
                return SidecarSubtitleLoader.isNativeRenderableSidecar(path)
            case .mpv, .externalMpv, .embeddedBitmapOverlay:
                return false
            }
        case .remuxWithBitmapOverlay:
            switch track.backendID {
            case .avFoundation, .mpv, .embeddedBitmapOverlay:
                return true
            case .companionSidecar(let path):
                return SidecarSubtitleLoader.isNativeRenderableSidecar(path)
            case .externalMpv:
                // External tracks on the overlay controller are rare; keep if listed.
                return true
            }
        case .directMpv:
            switch track.backendID {
            case .mpv, .externalMpv, .companionSidecar:
                return true
            case .avFoundation, .embeddedBitmapOverlay:
                return false
            }
        }
    }

    /// Drops tracks the current engine cannot show and renumbers `#n` for the picker.
    static func playableTracks(
        _ tracks: [SubtitleTrackInfo],
        session: SubtitlePlaybackSession
    ) -> [SubtitleTrackInfo] {
        let filtered = tracks.filter { isPlayable($0, session: session) }
        return filtered.enumerated().map { offset, track in
            SubtitleTrackInfo(
                backendID: track.backendID,
                displayIndex: offset + 1,
                language: track.language,
                title: track.title,
                codec: track.codec
            )
        }
    }

    static func isForced(_ track: SubtitleTrackInfo) -> Bool {
        let title = (track.title ?? "").lowercased()
        return title.contains("forced") || title == "force" || title.hasPrefix("forced")
    }

    static func isEnglish(_ track: SubtitleTrackInfo) -> Bool {
        let lang = (track.language ?? "").lowercased()
        return lang.contains("english") || lang.hasPrefix("en")
    }

    /// Prefer full English dialogue over Forced / empty-looking first slots.
    static func preferredDefault(in tracks: [SubtitleTrackInfo]) -> SubtitleTrackInfo? {
        let english = tracks.filter(isEnglish)
        if let full = english.first(where: { !isForced($0) }) {
            return full
        }
        if let englishFirst = english.first {
            return englishFirst
        }
        if let full = tracks.first(where: { !isForced($0) }) {
            return full
        }
        return tracks.first
    }
}
