import Foundation

/// Turns a noisy release filename into a search-friendly movie/TV title.
enum OpenSubtitlesQueryCleaner {
    /// Tokens that are release tags, not title words.
    private static let junkTokens: Set<String> = [
        "bluray", "bdrip", "brrip", "webrip", "webdl", "web-dl", "hdtv", "dvdrip", "hdrip",
        "x264", "x265", "h264", "h265", "hevc", "avc", "aac", "ac3", "dts", "truehd", "atmos",
        "10bit", "8bit", "hdr", "dv", "sdr", "remux", "proper", "repack", "internal",
        "yts", "yify", "rarbg", "ettv", "eztv", "sparks", "ntb", "flux", "amzn", "nf", "dsnp",
        "multi", "subs", "subbed", "dubbed", "extended", "unrated", "directors", "cut",
        "2160p", "1080p", "720p", "480p", "4k", "uhd", "fhd", "hd", "sd",
        "5.1", "7.1", "2.0", "dd5", "ddp5", "ddp", "ma"
    ]

    static func query(fromFileName fileName: String) -> String {
        var base = (fileName as NSString).deletingPathExtension
        // Strip trailing bracket groups: [2160p] [YTS.MX]
        while let range = base.range(of: #"\s*\[[^\]]*\]\s*$"#, options: .regularExpression) {
            base.removeSubrange(range)
        }
        while base.last == "-" || base.last == "." || base.last == "_" || base.last == " " {
            base.removeLast()
        }
        let spaced = base
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        var tokens = spaced
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
            .filter { token in
                let lower = token.lowercased()
                if junkTokens.contains(lower) { return false }
                if lower.hasPrefix("yts") { return false }
                if isAudioVideoTag(lower) { return false }
                // Leftovers from splitting "5.1" / "AAC5.1" on dots.
                if token.count <= 2, token.allSatisfy(\.isNumber) { return false }
                return true
            }

        // Keep the first year-like token (often part of the title, e.g. Blade Runner 2049);
        // drop later years (release year after the title year).
        var sawYear = false
        tokens = tokens.filter { token in
            guard isStandaloneYear(token) else { return true }
            if sawYear { return false }
            sawYear = true
            return true
        }

        let joined = tokens.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? (fileName as NSString).deletingPathExtension : joined
    }

    private static func isStandaloneYear(_ token: String) -> Bool {
        guard token.count == 4, token.allSatisfy(\.isNumber), let year = Int(token) else {
            return false
        }
        return (1900...2100).contains(year)
    }

    private static func isAudioVideoTag(_ lower: String) -> Bool {
        if lower.hasPrefix("aac") || lower.hasPrefix("ddp") || lower.hasPrefix("dts") {
            return true
        }
        if lower.hasPrefix("x264") || lower.hasPrefix("x265") || lower.hasPrefix("h264") || lower.hasPrefix("h265") {
            return true
        }
        return false
    }
}
