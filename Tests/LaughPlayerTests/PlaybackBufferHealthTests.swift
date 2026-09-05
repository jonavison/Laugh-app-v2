import XCTest
@testable import LaughPlayer

final class PlaybackBufferHealthTests: XCTestCase {
    func testStarvingWhenEmptyAndNotKeepingUp() {
        XCTAssertEqual(
            PlaybackBufferHealth.classify(keepUp: false, empty: true, full: false),
            .starving
        )
    }

    func testBufferingWhenFilling() {
        XCTAssertEqual(
            PlaybackBufferHealth.classify(keepUp: false, empty: false, full: false),
            .buffering
        )
    }

    func testReadyWhenKeepingUp() {
        XCTAssertEqual(
            PlaybackBufferHealth.classify(keepUp: true, empty: false, full: false),
            .ready
        )
    }

    func testFullWhenKeepUpAndFull() {
        XCTAssertEqual(
            PlaybackBufferHealth.classify(keepUp: true, empty: false, full: true),
            .full
        )
    }
}
