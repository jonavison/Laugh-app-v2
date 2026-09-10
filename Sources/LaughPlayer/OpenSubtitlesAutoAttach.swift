import Foundation

/// Picks and downloads a text sidecar when remux cannot carry embedded bitmap subs.
enum OpenSubtitlesAutoAttach {
    enum Decision: Equatable {
        case attempt
        case skip(reason: String)
    }

    /// Quality path: remux picture/audio is already chosen; fill empty track list from OS.com.
    static func decision(
        hasApiKey: Bool,
        playableTracksEmpty: Bool,
        sourceHasBitmapOnly: Bool,
        hasCompanionSidecar: Bool
    ) -> Decision {
        guard playableTracksEmpty else { return .skip(reason: "tracksAlreadyPresent") }
        guard sourceHasBitmapOnly else { return .skip(reason: "notBitmapOnly") }
        guard !hasCompanionSidecar else { return .skip(reason: "companionPresent") }
        guard hasApiKey else { return .skip(reason: "missingApiKey") }
        return .attempt
    }

    /// Prefer popular English (or requested language) hits.
    static func pickBest(
        from results: [OpenSubtitlesSearchResult],
        preferredLanguage: String = "en"
    ) -> OpenSubtitlesSearchResult? {
        let preferred = preferredLanguage.lowercased()
        let matching = results.filter { $0.language.lowercased() == preferred }
        let pool = matching.isEmpty ? results : matching
        return pool.max(by: { lhs, rhs in
            if lhs.downloadCount != rhs.downloadCount {
                return lhs.downloadCount < rhs.downloadCount
            }
            let lRating = lhs.rating ?? -1
            let rRating = rhs.rating ?? -1
            return lRating < rRating
        })
    }
}
