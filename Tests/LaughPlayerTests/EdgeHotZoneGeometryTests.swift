import XCTest
@testable import LaughPlayer

final class EdgeHotZoneGeometryTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

    func testResizeRimIsNotPanelOpenZone() {
        XCTAssertTrue(EdgeHotZoneGeometry.isInWindowResizeRim(point: CGPoint(x: 3, y: 300), bounds: bounds))
        XCTAssertFalse(EdgeHotZoneGeometry.isInLeftOpenZone(point: CGPoint(x: 3, y: 300), bounds: bounds))
        XCTAssertFalse(EdgeHotZoneGeometry.isInRightOpenZone(point: CGPoint(x: 797, y: 300), bounds: bounds))
    }

    func testInnerBandArmsPanelOpen() {
        XCTAssertTrue(EdgeHotZoneGeometry.isInLeftOpenZone(point: CGPoint(x: 20, y: 300), bounds: bounds))
        XCTAssertTrue(EdgeHotZoneGeometry.isInRightOpenZone(point: CGPoint(x: 780, y: 300), bounds: bounds))
        XCTAssertFalse(EdgeHotZoneGeometry.isInLeftOpenZone(point: CGPoint(x: 50, y: 300), bounds: bounds))
    }

    func testCornerYIsExcludedFromSideZones() {
        XCTAssertFalse(EdgeHotZoneGeometry.isInLeftOpenZone(point: CGPoint(x: 20, y: 4), bounds: bounds))
        XCTAssertFalse(EdgeHotZoneGeometry.isInRightOpenZone(point: CGPoint(x: 780, y: 596), bounds: bounds))
    }

    func testClickSlopDistinguishesDrag() {
        let start = CGPoint(x: 20, y: 300)
        XCTAssertTrue(EdgeHotZoneGeometry.isClickNotDrag(from: start, to: CGPoint(x: 22, y: 301)))
        XCTAssertFalse(EdgeHotZoneGeometry.isClickNotDrag(from: start, to: CGPoint(x: 40, y: 300)))
    }

    func testRightCloseZoneUsesSheetLeading() {
        let sheetLeading: CGFloat = 560
        XCTAssertTrue(
            EdgeHotZoneGeometry.isInRightCloseZone(
                point: CGPoint(x: 540, y: 300),
                bounds: bounds,
                sheetLeadingX: sheetLeading
            )
        )
        XCTAssertFalse(
            EdgeHotZoneGeometry.isInRightCloseZone(
                point: CGPoint(x: 560, y: 300),
                bounds: bounds,
                sheetLeadingX: sheetLeading
            )
        )
    }
}
