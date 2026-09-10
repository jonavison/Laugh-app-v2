import Foundation

/// When remux/AVPlayer keeps sharp A/V but the source only has PGS/VobSub embeds.
enum EmbeddedBitmapOverlayPolicy {
    /// Auto-start a subtitle-only libmpv overlay (no OpenSubtitles key, no soft full-frame video).
    static func shouldAutoAttach(
        mpvBackendActive: Bool,
        playableTextTracksEmpty: Bool,
        sourceHasBitmapOnly: Bool,
        hasTextSidecarActive: Bool,
        libmpvAvailable: Bool
    ) -> Bool {
        guard !mpvBackendActive else { return false }
        guard playableTextTracksEmpty else { return false }
        guard sourceHasBitmapOnly else { return false }
        guard !hasTextSidecarActive else { return false }
        guard libmpvAvailable else { return false }
        return true
    }
}
