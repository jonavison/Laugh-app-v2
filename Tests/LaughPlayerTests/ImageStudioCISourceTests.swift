import XCTest
import CoreGraphics
@testable import LaughPlayer

final class ImageStudioCISourceTests: XCTestCase {
    func testOpaqueRGBWithoutPremulAlphaIsCopiedToPremultipliedRGBA8() throws {
        let source = try makeSolidOpaqueRGB(red: 200, green: 40, blue: 12, width: 33, height: 19)
        XCTAssertFalse(ImageStudioCISource.isMetalSafeRGBA8(source))

        let canonical = ImageStudioCISource.rgba8Premultiplied(source)
        XCTAssertTrue(ImageStudioCISource.isMetalSafeRGBA8(canonical))
        XCTAssertEqual(canonical.width, 33)
        XCTAssertEqual(canonical.height, 19)
        XCTAssertEqual(canonical.bitsPerPixel, 32)
    }

    func testOpaqueRGBSurvivesStudioCIRenderWithoutStripeShift() throws {
        let source = try makeSolidOpaqueRGB(red: 200, green: 40, blue: 12, width: 33, height: 19)
        let ci = ImageStudioCISource.ciImage(from: source)
        let context = CIContext(options: [.cacheIntermediates: false])
        let extent = ci.extent.integral
        let rendered = try XCTUnwrap(
            context.createCGImage(
                ci,
                from: extent,
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB(),
                deferred: false
            )
        )
        let sample = try XCTUnwrap(samplePixel(rendered, x: 8, y: 6))
        XCTAssertEqual(Double(sample.r), 200, accuracy: 12)
        XCTAssertEqual(Double(sample.g), 40, accuracy: 12)
        XCTAssertEqual(Double(sample.b), 12, accuracy: 12)
    }

    private func makeSolidOpaqueRGB(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        width: Int,
        height: Int
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        )
        context.setFillColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func samplePixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(
            image,
            in: CGRect(x: -CGFloat(x), y: CGFloat(y + 1) - CGFloat(image.height), width: CGFloat(image.width), height: CGFloat(image.height))
        )
        return (pixel[0], pixel[1], pixel[2])
    }
}

