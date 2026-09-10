import Foundation

/// Sticky resume intent across a burst of cooperative seeks.
/// Rapid ←/→ pauses on the first seek; follow-up seeks see rate==0 and must still resume.
enum CooperativeSeekResumePolicy {
    /// Fold the latest rate into the chain's resume intent.
    static func markPlaying(currentRatePlaying: Bool, existingIntent: Bool) -> Bool {
        existingIntent || currentRatePlaying
    }

    /// Latest seek generation only. Resume even if `finished` is false — a cancelled
    /// final seek still leaves the player paused otherwise.
    static func shouldResume(intent: Bool, finished: Bool, mutedForSwitch: Bool) -> Bool {
        _ = finished
        return intent && !mutedForSwitch
    }
}
