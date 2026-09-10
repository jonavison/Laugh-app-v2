import XCTest
@testable import LaughPlayer

final class EmbeddedBitmapOverlayPolicyTests: XCTestCase {
    func testAutoAttachWhenBitmapOnlyRemuxAndLibmpv() {
        XCTAssertTrue(
            EmbeddedBitmapOverlayPolicy.shouldAutoAttach(
                mpvBackendActive: false,
                playableTextTracksEmpty: true,
                sourceHasBitmapOnly: true,
                hasTextSidecarActive: false,
                libmpvAvailable: true
            )
        )
    }

    func testSkipsWhenDirectMpvOrTextPresentOrNoLibmpv() {
        XCTAssertFalse(
            EmbeddedBitmapOverlayPolicy.shouldAutoAttach(
                mpvBackendActive: true,
                playableTextTracksEmpty: true,
                sourceHasBitmapOnly: true,
                hasTextSidecarActive: false,
                libmpvAvailable: true
            )
        )
        XCTAssertFalse(
            EmbeddedBitmapOverlayPolicy.shouldAutoAttach(
                mpvBackendActive: false,
                playableTextTracksEmpty: false,
                sourceHasBitmapOnly: true,
                hasTextSidecarActive: false,
                libmpvAvailable: true
            )
        )
        XCTAssertFalse(
            EmbeddedBitmapOverlayPolicy.shouldAutoAttach(
                mpvBackendActive: false,
                playableTextTracksEmpty: true,
                sourceHasBitmapOnly: true,
                hasTextSidecarActive: true,
                libmpvAvailable: true
            )
        )
        XCTAssertFalse(
            EmbeddedBitmapOverlayPolicy.shouldAutoAttach(
                mpvBackendActive: false,
                playableTextTracksEmpty: true,
                sourceHasBitmapOnly: true,
                hasTextSidecarActive: false,
                libmpvAvailable: false
            )
        )
        XCTAssertFalse(
            EmbeddedBitmapOverlayPolicy.shouldAutoAttach(
                mpvBackendActive: false,
                playableTextTracksEmpty: true,
                sourceHasBitmapOnly: false,
                hasTextSidecarActive: false,
                libmpvAvailable: true
            )
        )
    }
}
