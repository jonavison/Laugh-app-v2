import Foundation

/// Pure rules for whether a playable URL belongs to a logical source file.
/// Used so resume/timeline never attribute file A's clock to file B during switches.
enum PlaybackSourceIdentity {
    /// `playingURL` matches `sourceURL` either as the source itself or as one of its known remux/preview URLs.
    static func playerURL(
        _ playingURL: URL?,
        matchesSource sourceURL: URL,
        remuxURLs: [URL]
    ) -> Bool {
        guard let playing = playingURL?.standardizedFileURL else { return false }
        let source = sourceURL.standardizedFileURL
        if playing == source { return true }
        let remuxSet = Set(remuxURLs.map(\.standardizedFileURL))
        return remuxSet.contains(playing)
    }
}
