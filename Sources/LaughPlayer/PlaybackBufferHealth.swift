import Foundation

/// AVPlayer buffer flags collapsed into a single playback-health label.
enum PlaybackBufferHealth: String, Equatable {
    /// No packets; player cannot keep up.
    case starving
    /// Filling; not yet likely to keep up.
    case buffering
    /// Likely to keep up; buffer not full.
    case ready
    /// Likely to keep up and buffer is full.
    case full

    static func classify(keepUp: Bool, empty: Bool, full: Bool) -> PlaybackBufferHealth {
        if empty && !keepUp { return .starving }
        if !keepUp { return .buffering }
        if full { return .full }
        return .ready
    }

    var logLabel: String { rawValue }
}
