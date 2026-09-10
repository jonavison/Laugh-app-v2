import XCTest
@testable import LaughPlayer

final class RemuxOpenStrategyTests: XCTestCase {
    func testProgressiveNeverWaitsOnTextSubs() {
        XCTAssertEqual(
            RemuxOpenStrategy.progressive(needsAudioTranscode: false),
            .firstAudioNoSubs
        )
        XCTAssertEqual(
            RemuxOpenStrategy.progressive(needsAudioTranscode: true),
            .progressivePreviewStereo
        )
    }

    func testFullRemuxPrefersNoSubsForFastOpen() {
        XCTAssertEqual(
            RemuxOpenStrategy.full(needsAudioTranscode: false),
            .firstAudioNoSubs
        )
        XCTAssertEqual(
            RemuxOpenStrategy.full(needsAudioTranscode: true),
            .firstAudioTranscodeAudio
        )
    }

    func testFullRemuxIncludesTextSubsWhenRequested() {
        XCTAssertEqual(
            RemuxOpenStrategy.full(needsAudioTranscode: false, includeTextSubs: true),
            .firstAudioWithTextSubs
        )
        // Audio transcode path stays focused on audio — text remux is a later strategy.
        XCTAssertEqual(
            RemuxOpenStrategy.full(needsAudioTranscode: true, includeTextSubs: true),
            .firstAudioTranscodeAudio
        )
    }

    func testBlockingOrderTriesNoSubsBeforeTextSubs() {
        let order = RemuxOpenStrategy.blockingOrder(needsAudioTranscode: false)
        XCTAssertEqual(order.first, .firstAudioNoSubs)
        let textIndex = order.firstIndex(of: .firstAudioWithTextSubs)
        let noSubsIndex = order.firstIndex(of: .firstAudioNoSubs)
        XCTAssertNotNil(textIndex)
        XCTAssertNotNil(noSubsIndex)
        XCTAssertLessThan(noSubsIndex!, textIndex!)
    }
}
