import XCTest
@testable import LaughPlayer

final class PlaybackSourceIdentityTests: XCTestCase {
    private let sourceA = URL(fileURLWithPath: "/Movies/A.mkv")
    private let sourceB = URL(fileURLWithPath: "/Movies/B.mkv")
    private let remuxA = URL(fileURLWithPath: "/tmp/LaughPlayerFallback/A-remux.mp4")
    private let remuxB = URL(fileURLWithPath: "/tmp/LaughPlayerFallback/B-remux.mp4")

    func testNativeSourceMatchesItself() {
        XCTAssertTrue(
            PlaybackSourceIdentity.playerURL(sourceA, matchesSource: sourceA, remuxURLs: [])
        )
    }

    func testNativeSourceDoesNotMatchOtherFile() {
        XCTAssertFalse(
            PlaybackSourceIdentity.playerURL(sourceA, matchesSource: sourceB, remuxURLs: [])
        )
    }

    func testRemuxMatchesItsSource() {
        XCTAssertTrue(
            PlaybackSourceIdentity.playerURL(remuxA, matchesSource: sourceA, remuxURLs: [remuxA])
        )
    }

    /// Regression: after switching A→B, the player may still hold A's remux while
    /// `playbackSourceURL` already points at B. That remux must NOT match B.
    func testStaleRemuxOfADoesNotMatchSourceB() {
        XCTAssertFalse(
            PlaybackSourceIdentity.playerURL(remuxA, matchesSource: sourceB, remuxURLs: [remuxB])
        )
        // Even with an empty remux list for B (cache miss), A's remux must not match.
        XCTAssertFalse(
            PlaybackSourceIdentity.playerURL(remuxA, matchesSource: sourceB, remuxURLs: [])
        )
    }

    func testNilPlayingNeverMatches() {
        XCTAssertFalse(
            PlaybackSourceIdentity.playerURL(nil, matchesSource: sourceA, remuxURLs: [remuxA])
        )
    }
}
