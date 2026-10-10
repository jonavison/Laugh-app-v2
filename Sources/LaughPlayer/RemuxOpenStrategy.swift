import Foundation

/// Chooses remux strategies for fast open. Progressive preview muxes text embeds
/// (SRT/ASS → mov_text) — cheap and required because incomplete torrents never get a
/// full remux upgrade. Bitmap (PGS) cannot remux — overlay / OpenSubtitles / sidecars.
enum RemuxOpenStrategy: Equatable {
    case firstAudioNoSubs
    case firstAudioWithTextSubs
    case allAudioNoSubs
    case firstAudioTranscodeAudio
    case allAudioWithSubs
    case progressivePreviewStereo

    /// Fragmented preview: A/V (+ AAC when needed) with text embeds when present.
    static func progressive(needsAudioTranscode: Bool) -> RemuxOpenStrategy {
        needsAudioTranscode ? .progressivePreviewStereo : .firstAudioWithTextSubs
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
