import XCTest
@testable import LaughPlayer

final class SubtitleTrackPlayabilityTests: XCTestCase {
    func testRemuxTextHidesBitmapAndNonNativeCompanions() {
        let tracks = [
            SubtitleTrackInfo(
                backendID: .embeddedBitmapOverlay(subtitleIndex: 0),
                displayIndex: 1,
                language: "English",
                title: nil,
                codec: "hdmv_pgs_subtitle"
            ),
            SubtitleTrackInfo(
                backendID: .companionSidecar(path: "/tmp/show.ass"),
                displayIndex: 2,
                language: "English",
                title: nil,
                codec: nil
            ),
            SubtitleTrackInfo(
                backendID: .companionSidecar(path: "/tmp/show.srt"),
                displayIndex: 3,
                language: "English",
                title: nil,
                codec: nil
            ),
            SubtitleTrackInfo(
                backendID: .avFoundation(optionIndex: 0),
                displayIndex: 4,
                language: "English",
                title: nil,
                codec: nil
            )
        ]
        let playable = SubtitleTrackPlayability.playableTracks(tracks, session: .remuxText)
        XCTAssertEqual(playable.count, 2)
        XCTAssertEqual(playable.map(\.displayIndex), [1, 2])
        XCTAssertEqual(
            playable.map(\.backendID),
            [
                .companionSidecar(path: "/tmp/show.srt"),
                .avFoundation(optionIndex: 0)
            ]
        )
    }

    func testBitmapOverlayKeepsPGSAndNativeSidecars() {
        let tracks = [
            SubtitleTrackInfo(
                backendID: .embeddedBitmapOverlay(subtitleIndex: 0),
                displayIndex: 1,
                language: "English",
                title: "Forced",
                codec: "hdmv_pgs_subtitle"
            ),
            SubtitleTrackInfo(
                backendID: .mpv(trackID: 3),
                displayIndex: 2,
                language: "English",
                title: nil,
                codec: "hdmv_pgs_subtitle"
            ),
            SubtitleTrackInfo(
                backendID: .companionSidecar(path: "/tmp/a.ass"),
                displayIndex: 3,
                language: nil,
                title: nil,
                codec: nil
            )
        ]
        let playable = SubtitleTrackPlayability.playableTracks(tracks, session: .remuxWithBitmapOverlay)
        XCTAssertEqual(playable.count, 2)
        XCTAssertEqual(playable[0].backendID, .embeddedBitmapOverlay(subtitleIndex: 0))
        XCTAssertEqual(playable[1].backendID, .mpv(trackID: 3))
    }

    func testPreferredDefaultSkipsForcedEnglish() {
        let tracks = [
            SubtitleTrackInfo(
                backendID: .mpv(trackID: 1),
                displayIndex: 1,
                language: "English",
                title: "Forced",
                codec: "hdmv_pgs_subtitle"
            ),
            SubtitleTrackInfo(
                backendID: .mpv(trackID: 2),
                displayIndex: 2,
                language: "English",
                title: nil,
                codec: "hdmv_pgs_subtitle"
            ),
            SubtitleTrackInfo(
                backendID: .mpv(trackID: 3),
                displayIndex: 3,
                language: "English",
                title: "SDH",
                codec: "hdmv_pgs_subtitle"
            )
        ]
        let preferred = SubtitleTrackPlayability.preferredDefault(in: tracks)
        XCTAssertEqual(preferred?.backendID, .mpv(trackID: 2))
    }
}
