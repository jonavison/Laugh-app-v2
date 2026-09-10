import XCTest
@testable import LaughPlayer

final class PlaybackFreezeWatchdogTests: XCTestCase {
    func testHealthyWhenFramesArrive() {
        var state = PlaybackFreezeState()
        var now: TimeInterval = 100
        XCTAssertEqual(
            state.evaluate(
                rate: 1, itemTimeSec: 10, hasNewFrame: true,
                isSeeking: false, isRecovering: false, displaySuppressed: false, now: now
            ),
            .healthy
        )
        now += 1
        XCTAssertEqual(
            state.evaluate(
                rate: 1, itemTimeSec: 11, hasNewFrame: true,
                isSeeking: false, isRecovering: false, displaySuppressed: false, now: now
            ),
            .healthy
        )
    }

    func testFreezeWhenClockAdvancesWithoutFrames() {
        var state = PlaybackFreezeState()
        var now: TimeInterval = 100
        _ = state.evaluate(
            rate: 1, itemTimeSec: 10, hasNewFrame: true,
            isSeeking: false, isRecovering: false, displaySuppressed: false, now: now
        )

        now += 3
        let decision = state.evaluate(
            rate: 1,
            itemTimeSec: 13.5,
            hasNewFrame: false,
            isSeeking: false,
            isRecovering: false,
            displaySuppressed: false,
            now: now
        )
        XCTAssertEqual(decision, .freezeDetected)
    }

    func testNeverFiresIfProbeNeverSawAFrame() {
        var state = PlaybackFreezeState()
        var now: TimeInterval = 100
        // Remuxed HEVC often never feeds AVPlayerItemVideoOutput — must not "recover".
        XCTAssertEqual(
            state.evaluate(
                rate: 1, itemTimeSec: 10, hasNewFrame: false,
                isSeeking: false, isRecovering: false, displaySuppressed: false, now: now
            ),
            .ignore
        )
        now += 5
        XCTAssertEqual(
            state.evaluate(
                rate: 1, itemTimeSec: 15, hasNewFrame: false,
                isSeeking: false, isRecovering: false, displaySuppressed: false, now: now
            ),
            .ignore
        )
    }

    func testIgnoresPauseAndSeek() {
        var state = PlaybackFreezeState()
        var now: TimeInterval = 100
        _ = state.evaluate(
            rate: 1, itemTimeSec: 10, hasNewFrame: true,
            isSeeking: false, isRecovering: false, displaySuppressed: false, now: now
        )
        now += 5
        XCTAssertEqual(
            state.evaluate(
                rate: 0, itemTimeSec: 10, hasNewFrame: false,
                isSeeking: false, isRecovering: false, displaySuppressed: false, now: now
            ),
            .ignore
        )
        now += 5
        XCTAssertEqual(
            state.evaluate(
                rate: 1, itemTimeSec: 10, hasNewFrame: false,
                isSeeking: true, isRecovering: false, displaySuppressed: false, now: now
            ),
            .ignore
        )
    }

    func testIgnoresWhenDisplaySuppressed() {
        var state = PlaybackFreezeState()
        var now: TimeInterval = 100
        _ = state.evaluate(
            rate: 1, itemTimeSec: 10, hasNewFrame: true,
            isSeeking: false, isRecovering: false, displaySuppressed: false, now: now
        )

        now += 5
        XCTAssertEqual(
            state.evaluate(
                rate: 1, itemTimeSec: 15, hasNewFrame: false,
                isSeeking: false, isRecovering: false, displaySuppressed: true, now: now
            ),
            .ignore
        )
    }

    func testCooldownAfterRecovery() {
        var state = PlaybackFreezeState()
        var now: TimeInterval = 100
        _ = state.evaluate(
            rate: 1, itemTimeSec: 10, hasNewFrame: true,
            isSeeking: false, isRecovering: false, displaySuppressed: false, now: now
        )
        now += 3
        XCTAssertEqual(
            state.evaluate(
                rate: 1, itemTimeSec: 14, hasNewFrame: false,
                isSeeking: false, isRecovering: false, displaySuppressed: false, now: now
            ),
            .freezeDetected
        )
        state.noteRecovery(at: now)

        now += 3
        XCTAssertEqual(
            state.evaluate(
                rate: 1, itemTimeSec: 17, hasNewFrame: false,
                isSeeking: false, isRecovering: false, displaySuppressed: false, now: now
            ),
            .ignore
        )
    }

    func testDoesNotFireWhenClockStuck() {
        var state = PlaybackFreezeState()
        var now: TimeInterval = 100
        _ = state.evaluate(
            rate: 1, itemTimeSec: 10, hasNewFrame: true,
            isSeeking: false, isRecovering: false, displaySuppressed: false, now: now
        )
        now += 5
        XCTAssertEqual(
            state.evaluate(
                rate: 1, itemTimeSec: 10.05, hasNewFrame: false,
                isSeeking: false, isRecovering: false, displaySuppressed: false, now: now
            ),
            .healthy
        )
    }
}
