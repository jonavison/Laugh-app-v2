import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import LaughPlayer

final class ImageFileMetadataTests: XCTestCase {
    func testPlainPNGHasFileAndImageOmitsCameraAndGPS() throws {
        let url = try writePNGFixture(name: "plain-meta.png", size: CGSize(width: 64, height: 48))
        defer { try? FileManager.default.removeItem(at: url) }

        let meta = ImageFileMetadata.load(from: url)
        let titles = meta.sections.map(\.title)
        XCTAssertTrue(titles.contains("File"))
        XCTAssertTrue(titles.contains("Image"))
        XCTAssertFalse(titles.contains("Camera"))
        XCTAssertFalse(titles.contains("GPS"))

        let file = try XCTUnwrap(meta.sections.first { $0.title == "File" })
        XCTAssertEqual(value(in: file, label: "Name"), "plain-meta.png")
        XCTAssertEqual(value(in: file, label: "Format"), "PNG")

        let image = try XCTUnwrap(meta.sections.first { $0.title == "Image" })
        XCTAssertEqual(value(in: image, label: "Dimensions"), "64 × 48")
        XCTAssertEqual(value(in: image, label: "Aspect"), "1.333")
    }

    func testJPEGWithEXIFIncludesCameraSection() throws {
        let url = try writeJPEGWithEXIF(
            name: "exif-meta.jpg",
            size: CGSize(width: 80, height: 60),
            make: "LaughCam",
            model: "Test-1",
            fNumber: 2.8,
            exposure: 1.0 / 125.0,
            iso: 200,
            focalLength: 35
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let meta = ImageFileMetadata.load(from: url)
        let titles = meta.sections.map(\.title)
        XCTAssertTrue(titles.contains("File"))
        XCTAssertTrue(titles.contains("Image"))
        XCTAssertTrue(titles.contains("Camera"))
        XCTAssertFalse(titles.contains("GPS"))

        let camera = try XCTUnwrap(meta.sections.first { $0.title == "Camera" })
        XCTAssertEqual(value(in: camera, label: "Make"), "LaughCam")
        XCTAssertEqual(value(in: camera, label: "Model"), "Test-1")
        XCTAssertEqual(value(in: camera, label: "Aperture"), "ƒ/2.8")
        XCTAssertEqual(value(in: camera, label: "Shutter"), "1/125 s")
        XCTAssertEqual(value(in: camera, label: "ISO"), "200")
        XCTAssertEqual(value(in: camera, label: "Focal length"), "35 mm")
    }

    // MARK: - Helpers

    private func value(in section: ImageFileMetadata.Section, label: String) -> String? {
        section.rows.first { $0.label == label }?.value
    }

    private func writePNGFixture(name: String, size: CGSize) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let cgImage = try makeSolidCGImage(size: size, color: .systemTeal)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "ImageFileMetadataTests", code: 1)
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ImageFileMetadataTests", code: 2)
        }
        return url
    }

    private func writeJPEGWithEXIF(
        name: String,
        size: CGSize,
        make: String,
        model: String,
        fNumber: Double,
        exposure: Double,
        iso: Int,
        focalLength: Double
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let cgImage = try makeSolidCGImage(size: size, color: .systemOrange)

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "ImageFileMetadataTests", code: 3)
        }

        let props: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: make,
                kCGImagePropertyTIFFModel: model
            ] as CFDictionary,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifFNumber: fNumber,
                kCGImagePropertyExifExposureTime: exposure,
                kCGImagePropertyExifISOSpeedRatings: [iso] as CFArray,
                kCGImagePropertyExifFocalLength: focalLength,
                kCGImagePropertyExifDateTimeOriginal: "2024:06:01 12:34:56"
            ] as CFDictionary
        ]
        CGImageDestinationAddImage(destination, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ImageFileMetadataTests", code: 4)
        }
        return url
    }

    private func makeSolidCGImage(size: CGSize, color: NSColor) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "ImageFileMetadataTests", code: 5)
        }
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw NSError(domain: "ImageFileMetadataTests", code: 6)
        }
        return image
    }
}
