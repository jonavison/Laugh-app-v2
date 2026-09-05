import XCTest
@testable import LaughPlayer

final class PlaybackIdleSleepPolicyTests: XCTestCase {
    func testPlayingVideoPreventsIdleSleep() {
        XCTAssertTrue(
            PlaybackIdleSleepPolicy.shouldPreventIdleSleep(isPlaying: true, mediaKind: .video)
        )
    }

    func testPausedVideoAllowsIdleSleep() {
        XCTAssertFalse(
            PlaybackIdleSleepPolicy.shouldPreventIdleSleep(isPlaying: false, mediaKind: .video)
        )
    }

    func testPlayingImageDoesNotPreventIdleSleep() {
        XCTAssertFalse(
            PlaybackIdleSleepPolicy.shouldPreventIdleSleep(isPlaying: true, mediaKind: .image)
        )
    }

    func testEmptySurfaceAllowsIdleSleep() {
        XCTAssertFalse(
            PlaybackIdleSleepPolicy.shouldPreventIdleSleep(isPlaying: false, mediaKind: .empty)
        )
    }
}
