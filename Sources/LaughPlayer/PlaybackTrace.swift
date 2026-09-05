import Foundation
import os

/// Dual-writes playback diagnostics to stderr (dev `--logs`) and Unified Logging
/// so `scripts/watch-playback-logs.sh` can tail while a video plays.
enum PlaybackTrace {
    static let subsystem = "com.laughplayer.dev"

    private static let logger = Logger(subsystem: subsystem, category: "playback")
    private static let processStart = CFAbsoluteTimeGetCurrent()

    static func emit(_ message: String) {
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - processStart) * 1000)
        let line = "+\(elapsedMs)ms \(message)"
        // `.notice` persists in the unified log; `.info` is often dropped for GUI apps.
        logger.notice("\(line, privacy: .public)")
        print(line)
    }
}
