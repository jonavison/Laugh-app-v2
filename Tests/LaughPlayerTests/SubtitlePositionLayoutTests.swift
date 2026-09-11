import XCTest
@testable import LaughPlayer

final class SubtitlePositionLayoutTests: XCTestCase {
    func testBottomInsetMovesContinuouslyFromBottomToTop() {
        let height: CGFloat = 400
        let text: CGFloat = 40
        let bottom = SubtitleAppearanceStyle.bottomInset(
            userPosition: 0,
            containerHeight: height,
            textHeight: text
        )
        let mid = SubtitleAppearanceStyle.bottomInset(
            userPosition: 50,
            containerHeight: height,
            textHeight: text
        )
        let top = SubtitleAppearanceStyle.bottomInset(
            userPosition: 100,
            containerHeight: height,
            textHeight: text
        )

        XCTAssertEqual(bottom, SubtitleAppearanceStyle.positionEdgePadding, accuracy: 0.5)
        XCTAssertGreaterThan(mid, bottom)
        XCTAssertGreaterThan(top, mid)
        // Mid should sit roughly halfway through the travel range — not snapped to center via a different mode.
        XCTAssertEqual(mid, (bottom + top) / 2, accuracy: 1)
    }

    func testMpvSubPosInvertsUserSlider() {
        XCTAssertEqual(SubtitleAppearanceStyle.mpvSubPos(fromUserPosition: 0), 100)
        XCTAssertEqual(SubtitleAppearanceStyle.mpvSubPos(fromUserPosition: 50), 50)
        XCTAssertEqual(SubtitleAppearanceStyle.mpvSubPos(fromUserPosition: 100), 0)
    }

    func testResolvedOverlayFontSizeScalesWithViewportHeight() {
        let atReference = SubtitleAppearanceStyle.resolvedOverlayFontSize(
            fontSize: 36,
            scale: 1,
            containerHeight: SubtitleAppearanceStyle.referenceViewportHeight
        )
        let larger = SubtitleAppearanceStyle.resolvedOverlayFontSize(
            fontSize: 36,
            scale: 1,
            containerHeight: SubtitleAppearanceStyle.referenceViewportHeight * 2
        )
        let smaller = SubtitleAppearanceStyle.resolvedOverlayFontSize(
            fontSize: 36,
            scale: 1,
            containerHeight: SubtitleAppearanceStyle.referenceViewportHeight / 2
        )

        XCTAssertEqual(atReference, 36, accuracy: 0.5)
        XCTAssertEqual(larger, 72, accuracy: 0.5)
        XCTAssertEqual(smaller, 18, accuracy: 0.5)
    }

    func testResolvedOverlayBorderWidthScalesWithViewportHeight() {
        let atReference = SubtitleAppearanceStyle.resolvedOverlayBorderWidth(
            borderWidth: 2,
            containerHeight: SubtitleAppearanceStyle.referenceViewportHeight
        )
        let larger = SubtitleAppearanceStyle.resolvedOverlayBorderWidth(
            borderWidth: 2,
            containerHeight: SubtitleAppearanceStyle.referenceViewportHeight * 1.5
        )
        XCTAssertEqual(atReference, 2, accuracy: 0.01)
        XCTAssertEqual(larger, 3, accuracy: 0.01)
    }
}
