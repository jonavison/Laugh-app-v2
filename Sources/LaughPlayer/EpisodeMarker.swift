import Foundation

/// Season/episode marker parsed from a media filename (scene-style naming).
struct EpisodeMarker: Equatable {
    let season: Int
    let episode: Int

    /// Compact grid badge, e.g. `S01E04`, `S12E104`.
    var badgeText: String {
        let seasonText = String(format: "%02d", season)
        let episodeText = episode >= 100 ? "\(episode)" : String(format: "%02d", episode)
        return "S\(seasonText)E\(episodeText)"
    }
}

enum EpisodeMarkerParser {
    /// Best-effort parse from a file name or path. Extension is ignored.
    static func parse(from fileNameOrPath: String) -> EpisodeMarker? {
        let base = ((fileNameOrPath as NSString).lastPathComponent as NSString).deletingPathExtension
        guard !base.isEmpty else { return nil }

        if let marker = matchSxEx(in: base) { return marker }
        if let marker = matchNxNN(in: base) { return marker }
        if let marker = matchSeasonEpisodeWords(in: base) { return marker }
        return nil
    }

    // S01E02, S1E2, S01EP02, s1.e2, S01_E02
    private static func matchSxEx(in text: String) -> EpisodeMarker? {
        let pattern = #"(?i)(?:^|[^A-Za-z0-9])S(\d{1,2})\s*[._\-\s]?\s*E(?:P)?(\d{1,3})(?:[^A-Za-z0-9]|$)"#
        return firstMarker(in: text, pattern: pattern)
    }

    // 1x02, 12x104
    private static func matchNxNN(in text: String) -> EpisodeMarker? {
        let pattern = #"(?i)(?:^|[^A-Za-z0-9])(\d{1,2})\s*[xX]\s*(\d{1,3})(?:[^A-Za-z0-9]|$)"#
        return firstMarker(in: text, pattern: pattern)
    }

    // Season 1 Episode 2 / Season 01 Ep 02
    private static func matchSeasonEpisodeWords(in text: String) -> EpisodeMarker? {
        let pattern = #"(?i)season\s*(\d{1,2})\s*(?:[-._\s]+)?(?:episode|ep\.?)\s*(\d{1,3})"#
        return firstMarker(in: text, pattern: pattern)
    }

    private static func firstMarker(in text: String, pattern: String) -> EpisodeMarker? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 3,
              let seasonRange = Range(match.range(at: 1), in: text),
              let episodeRange = Range(match.range(at: 2), in: text),
              let season = Int(text[seasonRange]),
              let episode = Int(text[episodeRange]),
              season >= 0,
              episode >= 0
        else {
            return nil
        }
        return EpisodeMarker(season: season, episode: episode)
    }
}
