import XCTest
@testable import LaughPlayer

final class FilmstripThumbnailPriorityTests: XCTestCase {
    func testOrdersByDistanceFromSelected() {
        let urls = (0..<7).map { URL(fileURLWithPath: "/tmp/img\($0).jpg") }
        let ordered = FilmstripThumbnailPriority.ordered(urls: urls, selected: urls[3])
        XCTAssertEqual(ordered.map(\.lastPathComponent), [
            "img3.jpg",
            "img4.jpg", "img2.jpg",
            "img5.jpg", "img1.jpg",
            "img6.jpg", "img0.jpg"
        ])
    }

    func testFallsBackToOriginalOrderWhenNothingSelected() {
        let urls = (0..<4).map { URL(fileURLWithPath: "/tmp/a\($0).jpg") }
        let ordered = FilmstripThumbnailPriority.ordered(urls: urls, selected: nil)
        XCTAssertEqual(ordered, urls)
    }

    func testUnknownSelectionKeepsOriginalOrder() {
        let urls = (0..<3).map { URL(fileURLWithPath: "/tmp/b\($0).jpg") }
        let ordered = FilmstripThumbnailPriority.ordered(
            urls: urls,
            selected: URL(fileURLWithPath: "/tmp/missing.jpg")
        )
        XCTAssertEqual(ordered, urls)
    }
}
