import XCTest
@testable import LaughPlayer

final class CooperativeSeekResumePolicyTests: XCTestCase {
    func testFirstSeekCapturesPlaying() {
        XCTAssertTrue(
            CooperativeSeekResumePolicy.markPlaying(currentRatePlaying: true, existingIntent: false)
        )
    }

    func testFollowUpSeekKeepsIntentWhenAlreadyPaused() {
        // First arrow paused the player; second arrow must not clear resume intent.
        let afterFirst = CooperativeSeekResumePolicy.markPlaying(
            currentRatePlaying: true, existingIntent: false
        )
        let afterSecond = CooperativeSeekResumePolicy.markPlaying(
            currentRatePlaying: false, existingIntent: afterFirst
        )
        XCTAssertTrue(afterSecond)
        XCTAssertTrue(
            CooperativeSeekResumePolicy.shouldResume(
                intent: afterSecond, finished: true, mutedForSwitch: false
            )
        )
    }

    func testDoesNotResumeWhenNeverPlaying() {
        let intent = CooperativeSeekResumePolicy.markPlaying(
            currentRatePlaying: false, existingIntent: false
        )
        XCTAssertFalse(
            CooperativeSeekResumePolicy.shouldResume(
                intent: intent, finished: true, mutedForSwitch: false
            )
        )
    }

    func testResumesEvenWhenFinalSeekReportsNotFinished() {
        XCTAssertTrue(
            CooperativeSeekResumePolicy.shouldResume(
                intent: true, finished: false, mutedForSwitch: false
            )
        )
    }
}
