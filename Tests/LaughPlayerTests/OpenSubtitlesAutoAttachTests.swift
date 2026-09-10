import XCTest
@testable import LaughPlayer

final class OpenSubtitlesAutoAttachTests: XCTestCase {
    func testDecisionRequiresBitmapOnlyEmptyTracksAndKey() {
        XCTAssertEqual(
            OpenSubtitlesAutoAttach.decision(
                hasApiKey: true,
                playableTracksEmpty: true,
                sourceHasBitmapOnly: true,
                hasCompanionSidecar: false
            ),
            .attempt
        )
        XCTAssertEqual(
            OpenSubtitlesAutoAttach.decision(
                hasApiKey: false,
                playableTracksEmpty: true,
                sourceHasBitmapOnly: true,
                hasCompanionSidecar: false
            ),
            .skip(reason: "missingApiKey")
        )
        XCTAssertEqual(
            OpenSubtitlesAutoAttach.decision(
                hasApiKey: true,
                playableTracksEmpty: false,
                sourceHasBitmapOnly: true,
                hasCompanionSidecar: false
            ),
            .skip(reason: "tracksAlreadyPresent")
        )
        XCTAssertEqual(
            OpenSubtitlesAutoAttach.decision(
                hasApiKey: true,
                playableTracksEmpty: true,
                sourceHasBitmapOnly: true,
                hasCompanionSidecar: true
            ),
            .skip(reason: "companionPresent")
        )
    }

    func testPickBestPrefersPreferredLanguageThenDownloads() {
        let enLow = OpenSubtitlesSearchResult(
            fileID: 1, fileName: "a.srt", language: "en", release: "a",
            title: "a", downloadCount: 10, rating: 5
        )
        let enHigh = OpenSubtitlesSearchResult(
            fileID: 2, fileName: "b.srt", language: "en", release: "b",
            title: "b", downloadCount: 99, rating: 4
        )
        let frHigh = OpenSubtitlesSearchResult(
            fileID: 3, fileName: "c.srt", language: "fr", release: "c",
            title: "c", downloadCount: 500, rating: 9
        )
        let best = OpenSubtitlesAutoAttach.pickBest(from: [enLow, frHigh, enHigh], preferredLanguage: "en")
        XCTAssertEqual(best?.fileID, 2)
    }
}
