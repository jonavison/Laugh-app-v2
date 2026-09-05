import Foundation

/// Whether playback should keep the Mac from idling to sleep (display + system).
enum PlaybackIdleSleepPolicy {
    static func shouldPreventIdleSleep(isPlaying: Bool, mediaKind: ActiveMediaKind) -> Bool {
        isPlaying && mediaKind == .video
    }
}
