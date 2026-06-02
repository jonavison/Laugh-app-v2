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
            message += "\n\nTry remuxing without re-encoding:\nffmpeg -i \"\(url.lastPathComponent)\" -c copy -tag:v hvc1 output.mp4"
        }

        message += "\n\nAlternate decoder support is planned for a future update."

        var debug = probeDetails ?? ""
        if debug.isEmpty { debug = reason }
        return PlaybackOpenFailure(userMessage: message, debugDetails: debug)
    }
}
