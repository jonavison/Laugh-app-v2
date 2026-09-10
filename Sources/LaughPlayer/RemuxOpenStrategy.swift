import Foundation

/// Chooses remux strategies for fast open. Progressive preview stays without subs so
/// playback starts in seconds. Full remux includes text embeds when present; bitmap
/// (PGS) cannot remux — overlay (subtitle-only mpv) / OpenSubtitles / sidecars cover that.
enum RemuxOpenStrategy: Equatable {
    case firstAudioNoSubs
    case firstAudioWithTextSubs
    case allAudioNoSubs
    case firstAudioTranscodeAudio
    case allAudioWithSubs
    case progressivePreviewStereo

    /// Fragmented preview: never wait on subtitle remux.
    static func progressive(needsAudioTranscode: Bool) -> RemuxOpenStrategy {
        needsAudioTranscode ? .progressivePreviewStereo : .firstAudioNoSubs
    }

    /// Background / full remux: A/V first; mux text embeds when the source has them.
    static func full(needsAudioTranscode: Bool, includeTextSubs: Bool = false) -> RemuxOpenStrategy {
        if needsAudioTranscode {
            return .firstAudioTranscodeAudio
        }
        return includeTextSubs ? .firstAudioWithTextSubs : .firstAudioNoSubs
    }

    /// Blocking fallback order when the preferred strategy fails.
    static func blockingOrder(needsAudioTranscode: Bool) -> [RemuxOpenStrategy] {
        if needsAudioTranscode {
            return [
                .firstAudioTranscodeAudio,
                .firstAudioNoSubs,
                .allAudioNoSubs,
                .firstAudioWithTextSubs
            ]
        }
        return [
            .firstAudioNoSubs,
            .allAudioNoSubs,
            .firstAudioWithTextSubs,
            .firstAudioTranscodeAudio,
            .allAudioWithSubs
        ]
    }
}
