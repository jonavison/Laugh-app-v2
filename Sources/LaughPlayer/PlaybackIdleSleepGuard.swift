import Foundation

/// Holds a ProcessInfo activity so watching a video does not let the Mac idle-sleep.
final class PlaybackIdleSleepGuard {
    private var activity: NSObjectProtocol?

    deinit {
        update(shouldHold: false)
    }

    func update(shouldHold: Bool) {
        if shouldHold {
            guard activity == nil else { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
                reason: "LaughPlayer video playback"
            )
            PlaybackTrace.emit("[DEBUG-wake] idle sleep disabled")
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
            PlaybackTrace.emit("[DEBUG-wake] idle sleep allowed")
        }
    }
}
