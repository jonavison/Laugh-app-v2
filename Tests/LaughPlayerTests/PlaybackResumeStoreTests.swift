import XCTest
@testable import LaughPlayer

final class PlaybackResumeStoreTests: XCTestCase {
    func testIgnoresTinyPositions() {
        XCTAssertNil(PlaybackResumeStore.sanitizedResumeSeconds(1.5, duration: 120))
        XCTAssertEqual(PlaybackResumeStore.sanitizedResumeSeconds(12, duration: 120) ?? 0, 12, accuracy: 0.01)
    }

    func testClearsWhenPastDuration() {
        XCTAssertTrue(PlaybackResumeStore.shouldClear(seconds: 200, duration: 120))
        XCTAssertNil(PlaybackResumeStore.sanitizedResumeSeconds(200, duration: 120))
    }

    func testClearsNearEndByRemaining() {
        XCTAssertTrue(PlaybackResumeStore.shouldClear(seconds: 115, duration: 120))
        XCTAssertNil(PlaybackResumeStore.sanitizedResumeSeconds(115, duration: 120))
    }

    func testClearsNearEndByFraction() {
        XCTAssertTrue(PlaybackResumeStore.shouldClear(seconds: 96, duration: 100))
        XCTAssertFalse(PlaybackResumeStore.shouldClear(seconds: 50, duration: 100))
    }

    func testAllowsMidpointWithoutDuration() {
        XCTAssertEqual(PlaybackResumeStore.sanitizedResumeSeconds(40, duration: nil) ?? 0, 40, accuracy: 0.01)
        XCTAssertFalse(PlaybackResumeStore.shouldClear(seconds: 40, duration: nil))
    }
}
