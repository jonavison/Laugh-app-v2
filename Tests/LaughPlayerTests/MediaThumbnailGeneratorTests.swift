import AppKit
import XCTest
@testable import LaughPlayer

final class MediaThumbnailGeneratorTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaughThumbTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        MediaThumbnailGenerator.clearMemoryCacheForTesting()
    }

    override func tearDownWithError() throws {
        MediaThumbnailGenerator.clearMemoryCacheForTesting()
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    func testTransparentPNGKeepsCornerAlphaAfterDiskCacheReload() throws {
        let url = try writeTransparentFixture(name: "cutout.png", size: 64)
        let first = try XCTUnwrap(
            MediaThumbnailGenerator.thumbnail(for: url, kind: .image, maxSide: 200, screenScale: 2)
        )
        XCTAssertLessThan(
            sampleAlpha(first, x: 0, y: 0),
            8,
            "Fresh thumb must keep transparent corners"
        )
        XCTAssertGreaterThan(
            sampleAlpha(first, x: 32, y: 32),
            200,
            "Subject pixels must stay opaque"
        )

        MediaThumbnailGenerator.clearMemoryCacheForTesting()

        let second = try XCTUnwrap(
            MediaThumbnailGenerator.thumbnail(for: url, kind: .image, maxSide: 200, screenScale: 2)
        )
        XCTAssertLessThan(
            sampleAlpha(second, x: 0, y: 0),
            8,
            "Disk-cached thumb must not flatten transparency to white/black (JPEG bug)"
        )
        XCTAssertGreaterThan(sampleAlpha(second, x: 32, y: 32), 200)
    }

    func testSquareCropFillPreservesTransparentCorners() throws {
        let url = try writeTransparentFixture(name: "carousel-cutout.png", size: 128)
        let square = try XCTUnwrap(
            MediaThumbnailGenerator.squareThumbnail(
                for: url,
                kind: .image,
                pointSide: 80,
                screenScale: 2
            )
        )
        XCTAssertEqual(square.size.width, 80, accuracy: 0.5)
        XCTAssertEqual(square.size.height, 80, accuracy: 0.5)
        let cg = try XCTUnwrap(square.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cg.width, 160)
        XCTAssertEqual(cg.height, 160)
        XCTAssertLessThan(sampleAlpha(square, x: 0, y: 0), 8)
        XCTAssertGreaterThan(sampleAlpha(square, x: 80, y: 80), 200)
    }

    func testSquareThumbnailPixelDensityFollowsScreenScale() throws {
        let url = try writeOpaqueJPEGFixture(name: "scale-source.jpg", size: 600)
        let at2 = try XCTUnwrap(
            MediaThumbnailGenerator.squareThumbnail(for: url, kind: .image, pointSide: 80, screenScale: 2)
        )
        let at3 = try XCTUnwrap(
            MediaThumbnailGenerator.squareThumbnail(for: url, kind: .image, pointSide: 80, screenScale: 3)
        )
        let cg2 = try XCTUnwrap(at2.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let cg3 = try XCTUnwrap(at3.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(cg2.width, 160)
        XCTAssertEqual(cg3.width, 240, "Hardcoded *2 would stay soft on 3x displays")
    }

    func testOpaqueJPEGThumbnailRemainsOpaque() throws {
        let url = try writeOpaqueJPEGFixture(name: "photo.jpg", size: 80)
        let thumb = try XCTUnwrap(
            MediaThumbnailGenerator.thumbnail(for: url, kind: .image, maxSide: 200, screenScale: 2)
        )
        XCTAssertGreaterThan(sampleAlpha(thumb, x: 0, y: 0), 200)
        XCTAssertGreaterThan(sampleAlpha(thumb, x: 40, y: 40), 200)
    }

    func testSmallMaxSideStillProducesRetinaReadyDecode() throws {
        let url = try writeOpaqueJPEGFixture(name: "large-source.jpg", size: 1200)
        let thumb = try XCTUnwrap(
            MediaThumbnailGenerator.thumbnail(for: url, kind: .image, maxSide: 200, screenScale: 2)
        )
        let cg = try XCTUnwrap(thumb.cgImage(forProposedRect: nil, context: nil, hints: nil))
        // Floor is 960 so Gallery @2x does not upscale a soft 320–400px cache entry.
        XCTAssertGreaterThanOrEqual(max(cg.width, cg.height), 900)
    }

    func testLaunchMigrationRemovesLegacyV1CacheFolder() throws {
        let base = try XCTUnwrap(
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        )
        let legacy = base.appendingPathComponent("LaughPlayerThumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let marker = legacy.appendingPathComponent("stale.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: marker)

        MediaThumbnailGenerator.resetLegacyCleanupFlagForTesting()
        MediaThumbnailGenerator.performLaunchMigrations()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacy.path),
            "V1 JPEG-only cache should be removed once on launch"
        )

        // Idempotent — second launch must not recreate or crash.
        MediaThumbnailGenerator.performLaunchMigrations()
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    // MARK: - Fixtures

    private func writeTransparentFixture(name: String, size: Int) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw NSError(domain: "MediaThumbnailGeneratorTests", code: 1)
        }
        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setFillColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1)
        let inset = CGFloat(size) * 0.25
        ctx.fillEllipse(in: CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2))
        guard let cgImage = ctx.makeImage() else {
            throw NSError(domain: "MediaThumbnailGeneratorTests", code: 2)
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "MediaThumbnailGeneratorTests", code: 3)
        }
        try png.write(to: url)
        return url
    }

    private func writeOpaqueJPEGFixture(name: String, size: Int) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw NSError(domain: "MediaThumbnailGeneratorTests", code: 4)
        }
        ctx.setFillColor(red: 0.2, green: 0.5, blue: 0.85, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setFillColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        ctx.fill(CGRect(x: CGFloat(size) * 0.25, y: CGFloat(size) * 0.25, width: CGFloat(size) * 0.5, height: CGFloat(size) * 0.5))
        guard let cgImage = ctx.makeImage() else {
            throw NSError(domain: "MediaThumbnailGeneratorTests", code: 5)
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
            throw NSError(domain: "MediaThumbnailGeneratorTests", code: 6)
        }
        try jpeg.write(to: url)
        return url
    }

    private func sampleAlpha(_ image: NSImage, x: Int, y: Int) -> UInt8 {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return 255
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 255
        }
        ctx.draw(
            cgImage,
            in: CGRect(x: -x, y: -y, width: cgImage.width, height: cgImage.height)
        )
        return pixel[3]
    }
}
