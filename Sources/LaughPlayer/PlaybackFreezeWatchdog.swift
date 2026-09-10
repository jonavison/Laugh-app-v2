import AVFoundation
import CoreMedia
import Foundation

/// Pure decision state for mid-session freezes: clock advances, no new frames.
///
/// Frame probing must not use `AVPlayerItemVideoOutput` alongside `AVPlayerLayer`:
/// on remuxed HEVC that output often never reports frames (false freezes + seek nudges),
/// and attaching it can contend with the display path.
struct PlaybackFreezeState: Equatable {
    var lastFrameWallTime: TimeInterval?
    var lastObservedItemTimeSec: Double?
    var recoveryCount: Int = 0
    var lastRecoveryWallTime: TimeInterval?
    /// Only declare freeze after we have observed at least one real frame signal.
    var everReceivedFrame: Bool = false

    /// Seconds of advancing playback without a new video frame before declaring a freeze.
    static let freezeThresholdSec: TimeInterval = 2.5
    /// Minimum gap between automatic recoveries.
    static let recoveryCooldownSec: TimeInterval = 12
    static let maxRecoveriesPerItem: Int = 4

    enum Decision: Equatable {
        case healthy
        case ignore
        case freezeDetected
    }

    mutating func evaluate(
        rate: Float,
        itemTimeSec: Double,
        hasNewFrame: Bool,
        isSeeking: Bool,
        isRecovering: Bool,
        displaySuppressed: Bool,
        now: TimeInterval
    ) -> Decision {
        if isSeeking || isRecovering || displaySuppressed || rate <= 0.01 {
            // Don't accumulate freeze time across pause/seek/background.
            lastFrameWallTime = now
            if itemTimeSec.isFinite {
                lastObservedItemTimeSec = itemTimeSec
            }
            return .ignore
        }

        guard itemTimeSec.isFinite else { return .ignore }

        if hasNewFrame {
            everReceivedFrame = true
            lastFrameWallTime = now
            lastObservedItemTimeSec = itemTimeSec
            return .healthy
        }

        // Probe never produced a frame for this item — do not invent freezes.
        guard everReceivedFrame else {
            lastFrameWallTime = now
            lastObservedItemTimeSec = itemTimeSec
            return .ignore
        }

        if lastFrameWallTime == nil {
            lastFrameWallTime = now
            lastObservedItemTimeSec = itemTimeSec
            return .healthy
        }

        let previousTime = lastObservedItemTimeSec ?? itemTimeSec
        lastObservedItemTimeSec = itemTimeSec

        // Clock must be moving — stuck buffer is handled elsewhere.
        let timeAdvanced = itemTimeSec > previousTime + 0.2
        guard timeAdvanced else {
            lastFrameWallTime = now
            return .healthy
        }

        let sinceFrame = now - (lastFrameWallTime ?? now)
        guard sinceFrame >= Self.freezeThresholdSec else {
            return .healthy
        }

        if recoveryCount >= Self.maxRecoveriesPerItem {
            return .ignore
        }
        if let lastRecovery = lastRecoveryWallTime,
           now - lastRecovery < Self.recoveryCooldownSec {
            return .ignore
        }

        return .freezeDetected
    }

    mutating func noteRecovery(at now: TimeInterval) {
        recoveryCount += 1
        lastRecoveryWallTime = now
        lastFrameWallTime = now
    }

    mutating func reset() {
        lastFrameWallTime = nil
        lastObservedItemTimeSec = nil
        recoveryCount = 0
        lastRecoveryWallTime = nil
        everReceivedFrame = false
    }
}

/// Placeholder watchdog — VideoOutput-based probing is disabled (see `PlaybackFreezeState`).
/// Keeps the API so a safer probe can be reattached later without scattering call sites.
final class PlaybackFreezeWatchdog {
    var isSeekingProvider: (() -> Bool)?
    var isDisplaySuppressedProvider: (() -> Bool)?
    var onFreezeDetected: (() -> Void)?

    func reset() {}

    func begin(player: AVPlayer, item: AVPlayerItem) {
        _ = player
        _ = item
        // Intentionally inactive: attaching AVPlayerItemVideoOutput caused false
        // freeze recoveries (and visible stalls) on remuxed HEVC + AVPlayerLayer.
        PlaybackTrace.emit("[DEBUG-qos] freeze_watchdog disabled (VideoOutput probe unsafe with AVPlayerLayer)")
    }

    func noteSeeking() {}
    func noteRecoveryStarted() {}
    func noteRecoveryFinished() {}
}
