import XCTest
@testable import LaughPlayer

final class ImageCropGeometryTests: XCTestCase {
    func testFreeAspectHasNoLockedRatio() {
        XCTAssertNil(ImageCropAspect.free.lockedRatio(imageSize: CGSize(width: 100, height: 50)))
    }

    func testOriginalAspectMatchesImage() {
        let ratio = ImageCropAspect.original.lockedRatio(imageSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(ratio ?? 0, 2, accuracy: 0.001)
    }

    func testPresetAspectRatios() {
        XCTAssertEqual(ImageCropAspect.square.lockedRatio(imageSize: .zero) ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(ImageCropAspect.portrait4x5.lockedRatio(imageSize: .zero) ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(ImageCropAspect.landscape16x9.lockedRatio(imageSize: .zero) ?? 0, 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(ImageCropAspect.instagramFeed.lockedRatio(imageSize: .zero) ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(ImageCropAspect.facebookCover.lockedRatio(imageSize: .zero) ?? 0, 820.0 / 312.0, accuracy: 0.001)
        XCTAssertEqual(ImageCropAspect.productPortrait.lockedRatio(imageSize: .zero) ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(ImageCropAspect.twitterHeader.lockedRatio(imageSize: .zero) ?? 0, 3.0, accuracy: 0.001)
    }

    func testLargestCenteredSquare() {
        let r = ImageCropGeometry.largestCenteredRect(aspectRatio: 1)
        XCTAssertEqual(r.width, 1, accuracy: 0.001)
        XCTAssertEqual(r.height, 1, accuracy: 0.001)
    }

    func testLargestCenteredWide() {
        let r = ImageCropGeometry.largestCenteredRect(aspectRatio: 2)
        XCTAssertEqual(r.width, 1, accuracy: 0.001)
        XCTAssertEqual(r.height, 0.5, accuracy: 0.001)
        XCTAssertEqual(r.midY, 0.5, accuracy: 0.001)
    }

    func testApplyAspectSnapsToLargestPresetFrame() {
        let start = CGRect(x: 0.4, y: 0.4, width: 0.15, height: 0.12)
        let square = ImageCropGeometry.applyAspect(
            .square,
            to: start,
            imageSize: CGSize(width: 1000, height: 800)
        )
        XCTAssertEqual(square.width, square.height, accuracy: 0.002)
        XCTAssertEqual(square.width, 1, accuracy: 0.001)
        XCTAssertEqual(square.midX, 0.5, accuracy: 0.001)
        XCTAssertEqual(square.midY, 0.5, accuracy: 0.001)

        let cover = ImageCropGeometry.applyAspect(
            .facebookCover,
            to: start,
            imageSize: CGSize(width: 2000, height: 2000)
        )
        let expected = 820.0 / 312.0
        XCTAssertEqual(cover.width / cover.height, expected, accuracy: 0.01)
        XCTAssertEqual(cover.width, 1, accuracy: 0.001)
        XCTAssertLessThan(cover.height, 0.5)
    }

    func testApplyFreeAspectKeepsCurrentRect() {
        let start = CGRect(x: 0.2, y: 0.25, width: 0.3, height: 0.2)
        let out = ImageCropGeometry.applyAspect(
            .free,
            to: start,
            imageSize: CGSize(width: 1000, height: 800)
        )
        XCTAssertEqual(out.origin.x, start.origin.x, accuracy: 0.001)
        XCTAssertEqual(out.origin.y, start.origin.y, accuracy: 0.001)
        XCTAssertEqual(out.width, start.width, accuracy: 0.001)
        XCTAssertEqual(out.height, start.height, accuracy: 0.001)
    }

    func testPixelRectMapsNormalized() {
        let pixel = ImageCropGeometry.pixelRect(
            normalized: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            imageSize: CGSize(width: 200, height: 100)
        )
        XCTAssertEqual(pixel.minX, 50, accuracy: 1)
        XCTAssertEqual(pixel.minY, 25, accuracy: 1)
        XCTAssertEqual(pixel.width, 100, accuracy: 1)
        XCTAssertEqual(pixel.height, 50, accuracy: 1)
    }

    func testIdentityDetection() {
        XCTAssertTrue(ImageCropGeometry.isIdentity(nil))
        XCTAssertTrue(ImageCropGeometry.isIdentity(ImageCropGeometry.fullNormalized))
        XCTAssertFalse(ImageCropGeometry.isIdentity(CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)))
    }

    func testFreeResizeCorner() {
        let start = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        let out = ImageCropGeometry.resize(
            rect: start,
            handle: .maxXMaxY,
            to: CGPoint(x: 0.9, y: 0.8),
            aspectRatio: nil
        )
        XCTAssertGreaterThan(out.maxX, start.maxX)
        XCTAssertGreaterThan(out.maxY, start.maxY)
    }

    func testLockedResizeKeepsSquare() {
        let start = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        let out = ImageCropGeometry.resize(
            rect: start,
            handle: .maxXMaxY,
            to: CGPoint(x: 0.8, y: 0.9),
            aspectRatio: 1
        )
        XCTAssertEqual(out.width, out.height, accuracy: 0.01)
    }

    func testStraightenClamp() {
        let over = ImageCropGeometry.clampStraightenRadians(2)
        XCTAssertEqual(
            ImageCropGeometry.straightenDegrees(from: over),
            ImageCropGeometry.maxStraightenDegrees,
            accuracy: 0.01
        )
        XCTAssertTrue(ImageCropGeometry.isIdentityStraighten(0))
        XCTAssertFalse(ImageCropGeometry.isIdentityStraighten(0.1))
    }

    func testSanitizedNeverLeavesUnitSquare() {
        let samples: [CGRect] = [
            CGRect(x: -0.5, y: -0.2, width: 2, height: 2),
            CGRect(x: 0.9, y: 0.9, width: 0.5, height: 0.5),
            CGRect(x: 0.2, y: 0.2, width: 0.01, height: 0.01),
            CGRect(x: 1.2, y: -0.1, width: 0.3, height: 0.4)
        ]
        for sample in samples {
            let out = ImageCropGeometry.sanitized(sample)
            XCTAssertGreaterThanOrEqual(out.minX, -0.0001, "\(out)")
            XCTAssertGreaterThanOrEqual(out.minY, -0.0001, "\(out)")
            XCTAssertLessThanOrEqual(out.maxX, 1.0001, "\(out)")
            XCTAssertLessThanOrEqual(out.maxY, 1.0001, "\(out)")
            XCTAssertGreaterThanOrEqual(out.width, ImageCropGeometry.minNormalizedEdge - 0.0001)
            XCTAssertGreaterThanOrEqual(out.height, ImageCropGeometry.minNormalizedEdge - 0.0001)
        }
    }

    func testResizeNeverLeavesUnitSquare() {
        let start = CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        let handles: [ImageCropHandle] = [
            .move, .minX, .maxX, .minY, .maxY,
            .minXMinY, .maxXMinY, .minXMaxY, .maxXMaxY
        ]
        let points = [
            CGPoint(x: -0.2, y: 0.5),
            CGPoint(x: 1.2, y: 1.2),
            CGPoint(x: 0.5, y: -0.1),
            CGPoint(x: 0.95, y: 0.05)
        ]
        for handle in handles {
            for point in points {
                for ratio: CGFloat? in [nil, 1.0, 16.0 / 9.0] {
                    let out = ImageCropGeometry.resize(
                        rect: start,
                        handle: handle,
                        to: point,
                        aspectRatio: ratio
                    )
                    XCTAssertGreaterThanOrEqual(out.minX, -0.0001, "\(handle) \(point) \(out)")
                    XCTAssertGreaterThanOrEqual(out.minY, -0.0001, "\(handle) \(point) \(out)")
                    XCTAssertLessThanOrEqual(out.maxX, 1.0001, "\(handle) \(point) \(out)")
                    XCTAssertLessThanOrEqual(out.maxY, 1.0001, "\(handle) \(point) \(out)")
                }
            }
        }
    }

    func testStraightenKeepsCropOnOpaquePixels() {
        let pre = CGSize(width: 1000, height: 800)
        let angle = 20 * CGFloat.pi / 180
        let full = ImageCropGeometry.fullNormalized
        XCTAssertFalse(
            ImageCropGeometry.opaqueContentContains(full, radians: angle, preSize: pre),
            "full AABB includes empty corners when straightened"
        )
        let clamped = ImageCropGeometry.clampToOpaqueContent(
            full,
            straightenRadians: angle,
            preStraightenSize: pre
        )
        XCTAssertTrue(
            ImageCropGeometry.opaqueContentContains(clamped, radians: angle, preSize: pre)
        )
        XCTAssertLessThan(clamped.width, 1)
        XCTAssertLessThan(clamped.height, 1)
    }
}
