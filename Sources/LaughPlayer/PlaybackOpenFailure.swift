import Foundation

struct PlaybackOpenFailure {
    let userMessage: String
    let debugDetails: String
}

enum PlaybackErrorFormatter {
    static func describe(_ error: Error?) -> String {
        guard let error else { return "Unknown error" }
        let ns = error as NSError
        var parts = ["domain=\(ns.domain)", "code=\(ns.code)", "desc=\(ns.localizedDescription)"]
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain)/\(underlying.code)/\(underlying.localizedDescription)")
        }
        return parts.joined(separator: ", ")
    }

    static func openFailure(url: URL, reason: String, probeDetails: String?) -> PlaybackOpenFailure {
        let ext = url.pathExtension.lowercased()
        var message = "This video could not be played with native macOS decoding."
        message += "\n\nReason: \(reason)"

        if ext == "mkv" {
            message += "\n\nMKV files often use codecs macOS cannot open natively (for example HEVC 10-bit in Matroska)."
        }

        if PlaybackRuntime.canUseBundledCodecStack {
            if FFmpegVideoFallback.isAvailable() {
                message += "\n\nLaughPlayer can remux this file with the bundled compatibility decoder (stream copy to MP4)."
            } else {
                message += "\n\nBundled ffmpeg was not found in this build. Run ./scripts/bundle-codec-tools.sh and rebuild."
            }
        }

        message += Self.manualRemuxHint(for: url)

        var debug = probeDetails ?? ""
        if debug.isEmpty { debug = reason }
        return PlaybackOpenFailure(userMessage: message, debugDetails: debug)
    }

    static func remuxFailedMessage(for url: URL) -> String {
        var message = "Native playback failed and the bundled remux could not prepare this file for AVFoundation."
        message += Self.manualRemuxHint(for: url)
        if PlaybackRuntime.canUseBundledCodecStack, !FFmpegVideoFallback.isHeavyTranscodeEnabled {
            message += "\n\nOptional: set LAUGH_ENABLE_HEAVY_TRANSCODE=1 to allow a slower full transcode fallback."
        }
        return message
    }

    private static func manualRemuxHint(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        guard ext == "mkv" || ext == "webm" else { return "" }
        let tagFlag = FFmpegVideoFallback.suggestedVideoTag(for: url).map { " -tag:v \($0)" } ?? ""
        return "\n\nYou can also remux manually without re-encoding video or audio:\nffmpeg -strict unofficial -i \"\(url.lastPathComponent)\" -map 0:v:0 -map 0:a:0? -map 0:s:0? -map_chapters -1 -c copy\(tagFlag) -c:s mov_text output.mp4"
    }
}
