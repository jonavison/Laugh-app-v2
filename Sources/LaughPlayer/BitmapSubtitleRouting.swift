import Foundation

/// Open-time policy for bitmap-only embeds (PGS/VobSub).
///
/// Soft DirectMpv software-blit can show PGS like IINA, but picture is CPU-scaled and
/// soft compared to CompatibilityRemux + AVPlayer. Until Metal present lands, **default
/// open stays remux** (sharp picture + OpenSubtitles tip). DirectMpv is opt-in only
/// (`forceDirectMpv` / “Embedded subs” tip action).
enum BitmapSubtitleRouting: Equatable {
    /// Auto-route to DirectMpv at open. Off while present path is software blit only.
    static var prefersDirectMpvAtOpen: Bool { false }

    /// Probe EmbeddedSubtitleTrack codecs once at open — never mid-playback.
    static func shouldPreferDirectMpv(
        subtitleCodecs: [String],
        presentCapable: Bool,
        remuxAvailable: Bool,
        mpvAvailable: Bool
    ) -> Bool {
        guard prefersDirectMpvAtOpen else { return false }
        guard presentCapable, mpvAvailable else { return false }
        _ = remuxAvailable
        return FFmpegProbeParser.hasBitmapSubtitlesOnly(codecs: subtitleCodecs)
    }

    /// Pure policy after present init failure for a bitmap-only file.
    static func fallbackAfterPresentInitFailure(
        remuxAvailable: Bool
    ) -> PlaybackRoute {
        if remuxAvailable {
            return .compatibilityRemux(reason: "bitmap.presentInitFailed")
        }
        return .directMpv(reason: "bitmap.noRemuxFallback")
    }
}
