import XCTest
@testable import LaughPlayer

final class ImageExportOptionsTests: XCTestCase {
    func testOriginalResizeKeepsSourceSize() {
        var options = ImageExportOptions.default
        options.resize = .original
        let out = options.outputPixelSize(sourcePixels: CGSize(width: 4288, height: 2848))
        XCTAssertEqual(out.width, 4288, accuracy: 0.5)
        XCTAssertEqual(out.height, 2848, accuracy: 0.5)
    }

    func testPercentResizeHalves() {
        var options = ImageExportOptions.default
        options.resize = .percent
        options.percent = 50
        let out = options.outputPixelSize(sourcePixels: CGSize(width: 2000, height: 1000))
        XCTAssertEqual(out.width, 1000, accuracy: 0.5)
        XCTAssertEqual(out.height, 500, accuracy: 0.5)
    }

    func testLongestEdgeLandscape() {
        var options = ImageExportOptions.default
        options.resize = .longestEdge
        options.width = 1000
        let out = options.outputPixelSize(sourcePixels: CGSize(width: 4000, height: 2000))
        XCTAssertEqual(out.width, 1000, accuracy: 0.5)
        XCTAssertEqual(out.height, 500, accuracy: 0.5)
    }

    func testLongestEdgePortrait() {
        var options = ImageExportOptions.default
        options.resize = .longestEdge
        options.width = 800
        let out = options.outputPixelSize(sourcePixels: CGSize(width: 1000, height: 2000))
        XCTAssertEqual(out.width, 400, accuracy: 0.5)
        XCTAssertEqual(out.height, 800, accuracy: 0.5)
    }

    func testWidthResizeKeepsAspect() {
        var options = ImageExportOptions.default
        options.resize = .width
        options.width = 500
        let out = options.outputPixelSize(sourcePixels: CGSize(width: 1000, height: 800))
        XCTAssertEqual(out.width, 500, accuracy: 0.5)
        XCTAssertEqual(out.height, 400, accuracy: 0.5)
    }

    func testHeightResizeKeepsAspect() {
        var options = ImageExportOptions.default
        options.resize = .height
        options.height = 400
        let out = options.outputPixelSize(sourcePixels: CGSize(width: 1000, height: 800))
        XCTAssertEqual(out.width, 500, accuracy: 0.5)
        XCTAssertEqual(out.height, 400, accuracy: 0.5)
    }

    func testFormatExtensionsAndQualitySupport() {
        XCTAssertEqual(ImageExportOptions.Format.jpeg.pathExtension, "jpg")
        XCTAssertEqual(ImageExportOptions.Format.webp.pathExtension, "webp")
        XCTAssertEqual(ImageExportOptions.Format.jpeg2000.pathExtension, "jp2")
        XCTAssertEqual(ImageExportOptions.Format.pdf.pathExtension, "pdf")
        XCTAssertTrue(ImageExportOptions.Format.jpeg.supportsLossyQuality)
        XCTAssertTrue(ImageExportOptions.Format.webp.supportsLossyQuality)
        XCTAssertFalse(ImageExportOptions.Format.png.supportsLossyQuality)
        XCTAssertFalse(ImageExportOptions.Format.pdf.supportsLossyQuality)
    }

    func testFormatFromURL() {
        XCTAssertEqual(ImageExportOptions.Format.from(url: URL(fileURLWithPath: "/a.webp")), .webp)
        XCTAssertEqual(ImageExportOptions.Format.from(url: URL(fileURLWithPath: "/a.jp2")), .jpeg2000)
        XCTAssertEqual(ImageExportOptions.Format.from(url: URL(fileURLWithPath: "/a.pdf")), .pdf)
        XCTAssertEqual(ImageExportOptions.Format.from(url: URL(fileURLWithPath: "/a.tiff")), .tiff)
        XCTAssertEqual(ImageExportOptions.Format.from(url: URL(fileURLWithPath: "/a.png")), .png)
        XCTAssertEqual(ImageExportOptions.Format.from(url: URL(fileURLWithPath: "/a.jpg")), .jpeg)
    }

    func testSuggestedFileNameUsesFormatExtension() {
        let source = URL(fileURLWithPath: "/tmp/Photo.NEF")
        XCTAssertTrue(ImageExportWriter.suggestedFileName(for: source, format: .webp).hasSuffix(".webp"))
        XCTAssertTrue(ImageExportWriter.suggestedFileName(for: source, format: .pdf).hasSuffix(".pdf"))
        XCTAssertTrue(ImageExportWriter.suggestedFileName(for: source, format: .jpeg).hasSuffix(".jpg"))
    }
}
