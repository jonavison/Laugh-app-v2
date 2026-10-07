import XCTest
import ImageIO
@testable import LaughPlayer

final class ImageDisplayLoaderTests: XCTestCase {
    private static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Selection", isDirectory: true)
    }

    func testFitDecodeReachesRequestedLongEdgeOnLargeJPEG() throws {
        let url = Self.fixturesDir.appendingPathComponent("stress-4k.jpg")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "stress-4k.jpg fixture missing")

        let sourceSize = try XCTUnwrap(ImageDisplayLoader.pixelSize(at: url))
        let sourceLong = max(sourceSize.width, sourceSize.height)
        XCTAssertGreaterThan(sourceLong, 2000, "fixture should be larger than display cap under test")

        let cap: CGFloat = 1800
        let loaded = try XCTUnwrap(ImageDisplayLoader.loadDisplayImage(at: url, maxPixelSize: cap))
        let decodedLong = max(loaded.image.size.width, loaded.image.size.height)

        // Must decode from full pixels near the cap — not a tiny camera/EXIF embedded thumb.
        XCTAssertGreaterThan(
            decodedLong,
            cap * 0.85,
            "fit decode stuck on low-res preview (\(decodedLong)px vs cap \(cap))"
        )
        XCTAssertEqual(loaded.pixelSize.width, sourceSize.width, accuracy: 0.5)
        XCTAssertEqual(loaded.pixelSize.height, sourceSize.height, accuracy: 0.5)
    }

    func testFitDecodeIsSharperThanScrubAndQuickOnLargeJPEG() throws {
        let url = Self.fixturesDir.appendingPathComponent("large-a.jpeg")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "large-a.jpeg fixture missing")

        let scrub = try XCTUnwrap(ImageDisplayLoader.loadScrubPreview(at: url))
        let quick = try XCTUnwrap(ImageDisplayLoader.loadQuickPreview(at: url))
        let fit = try XCTUnwrap(ImageDisplayLoader.loadDisplayImage(at: url, maxPixelSize: 2000))

        let scrubLong = max(scrub.image.size.width, scrub.image.size.height)
        let quickLong = max(quick.image.size.width, quick.image.size.height)
        let fitLong = max(fit.image.size.width, fit.image.size.height)

        XCTAssertLessThanOrEqual(scrubLong, quickLong + 1)
        XCTAssertGreaterThan(fitLong, scrubLong, "fit should out-resolve scrub preview")
        XCTAssertGreaterThanOrEqual(fitLong, min(quickLong, 1000), "fit should not be softer than quick")
    }

    func testFitDecodeIsPremultipliedRGBA8() throws {
        let url = try makeJPEGWithEmbeddedThumbnail()
        defer { try? FileManager.default.removeItem(at: url) }

        let fit = try XCTUnwrap(ImageDisplayLoader.loadDisplayImage(at: url, maxPixelSize: 800))
        let cg = try XCTUnwrap(fit.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertTrue(
            ImageStudioCISource.isMetalSafeRGBA8(cg),
            "Identity NSImageView path must not display ImageIO YCbCr / 24-bit RGB"
        )
    }

    func testFitDecodeIgnoresEmbeddedThumbnailTrap() throws {
        let url = try makeJPEGWithEmbeddedThumbnail()
        defer { try? FileManager.default.removeItem(at: url) }

        let sourceSize = try XCTUnwrap(ImageDisplayLoader.pixelSize(at: url))
        XCTAssertEqual(sourceSize.width, 2400, accuracy: 1)
        XCTAssertEqual(sourceSize.height, 1600, accuracy: 1)

        // Prove the file actually has a smaller IfAbsent thumb (the old fit-path trap).
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let ifAbsentOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        let ifAbsent = try XCTUnwrap(
            CGImageSourceCreateThumbnailAtIndex(source, 0, ifAbsentOpts as CFDictionary)
        )
        let ifAbsentLong = max(ifAbsent.width, ifAbsent.height)

        let fit = try XCTUnwrap(ImageDisplayLoader.loadDisplayImage(at: url, maxPixelSize: 1600))
        let fitLong = max(fit.image.size.width, fit.image.size.height)
        XCTAssertGreaterThan(
            fitLong,
            1200,
            "fit decode used embedded \(fitLong)px thumb instead of full image"
        )
        // If ImageIO embedded a smaller preview, fit must beat that IfAbsent result.
        if ifAbsentLong < 1200 {
            XCTAssertGreaterThan(fitLong, CGFloat(ifAbsentLong), "fit still stuck on IfAbsent embedded thumb")
        }
    }

    /// Builds a 2400×1600 JPEG with an embedded thumbnail (IfAbsent trap for camera JPEGs).
    private func makeJPEGWithEmbeddedThumbnail() throws -> URL {
        let width = 2400
        let height = 1600
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw XCTSkip("Could not create CGContext")
        }
        ctx.setFillColor(NSColor.systemTeal.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: 200, y: 200, width: width - 400, height: height - 400))
        guard let fullImage = ctx.makeImage() else {
            throw XCTSkip("Could not make full CGImage")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-embedded-thumb-\(UUID().uuidString).jpg")
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            throw XCTSkip("Could not create image destination")
        }

        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92,
            kCGImageDestinationEmbedThumbnail: true
        ]
        CGImageDestinationAddImage(dest, fullImage, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest), "Failed to write JPEG with embedded thumb")
        return url
    }

    func testCameraRAWExtensionsAreDetected() {
        XCTAssertTrue(MediaKindDetector.isCameraRAW(URL(fileURLWithPath: "/tmp/DSC_0001.NEF")))
        XCTAssertTrue(MediaKindDetector.isCameraRAW(URL(fileURLWithPath: "/tmp/IMG_0001.cr2")))
        XCTAssertTrue(MediaKindDetector.isCameraRAW(URL(fileURLWithPath: "/tmp/shot.dng")))
        XCTAssertTrue(MediaKindDetector.isCameraRAW(URL(fileURLWithPath: "/tmp/a.ARW")))
        XCTAssertFalse(MediaKindDetector.isCameraRAW(URL(fileURLWithPath: "/tmp/photo.jpg")))
        XCTAssertFalse(MediaKindDetector.isCameraRAW(URL(fileURLWithPath: "/tmp/photo.heic")))
    }

    func testFitRAWDemosaicBeatsEmbeddedPreviewWhenFixturePresent() throws {
        let fixtures = Self.fixturesDir
        let raws = (try? FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil))?
            .filter { MediaKindDetector.isCameraRAW($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        try XCTSkipUnless(raws.first != nil, "No camera RAW fixture in Fixtures/Selection")
        let url = try XCTUnwrap(raws.first)

        let native = try XCTUnwrap(ImageDisplayLoader.pixelSize(at: url))
        let nativeLong = max(native.width, native.height)
        XCTAssertGreaterThan(nativeLong, 1000, "RAW sensor size should be larger than a JPEG preview")

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let previewOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceThumbnailMaxPixelSize: 4000,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, previewOpts as CFDictionary)
        let previewLong = preview.map { max(CGFloat($0.width), CGFloat($0.height)) } ?? 0

        let cap: CGFloat = min(2200, nativeLong)
        let fit = try XCTUnwrap(ImageDisplayLoader.loadDisplayImage(at: url, maxPixelSize: cap))
        let fitLong = max(fit.image.size.width, fit.image.size.height)
        XCTAssertGreaterThan(
            fitLong,
            cap * 0.75,
            "RAW fit decode should demosaic near the display cap, not the camera JPEG (\(fitLong) vs cap \(cap), preview \(previewLong))"
        )
        if previewLong > 0, previewLong < cap * 0.6 {
            XCTAssertGreaterThan(fitLong, previewLong, "RAW fit still stuck on embedded JPEG preview")
        }
        XCTAssertEqual(fit.pixelSize.width, native.width, accuracy: 1)
        XCTAssertEqual(fit.pixelSize.height, native.height, accuracy: 1)
    }
}
