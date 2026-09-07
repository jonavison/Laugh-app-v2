import CoreImage
import XCTest
@testable import LaughPlayer

final class SelectionBrushTests: XCTestCase {
    func testPaintInExpandsCoverage() {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let mask = CIImage(color: .black).cropped(to: extent)
        let painted = SelectionBrushEngine.apply(
            mask: mask,
            photo: nil,
            mode: .paintIn,
            center: CGPoint(x: 32, y: 32),
            radius: 12,
            extent: extent
        )
        XCTAssertGreaterThan(coverage(painted, extent: extent), 0.02)
    }

    func testPaintOutContractsCoverage() {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let full = CIImage(color: .white).cropped(to: extent)
        let erased = SelectionBrushEngine.apply(
            mask: full,
            photo: nil,
            mode: .paintOut,
            center: CGPoint(x: 32, y: 32),
            radius: 20,
            extent: extent
        )
        XCTAssertLessThan(coverage(erased, extent: extent), 0.98)
    }

    func testRefineEdgeAltersSoftMatteNearPhotoEdge() {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        var maskData = [UInt8](repeating: 0, count: 64 * 64)
        for y in 16..<48 {
            for x in 16..<48 { maskData[y * 64 + x] = 140 }
        }
        let maskCG = grayImage(maskData, width: 64, height: 64)
        let mask = CIImage(cgImage: maskCG)

        var photoData = [UInt8](repeating: 30, count: 64 * 64 * 4)
        for y in 0..<64 {
            for x in 0..<64 {
                let i = (y * 64 + x) * 4
                let v: UInt8 = x >= 20 ? 220 : 30
                photoData[i] = v; photoData[i + 1] = v; photoData[i + 2] = v; photoData[i + 3] = 255
            }
        }
        let photoCG = rgbaImage(photoData, width: 64, height: 64)
        let photo = CIImage(cgImage: photoCG)

        let refined = SelectionBrushEngine.apply(
            mask: mask,
            photo: photo,
            mode: .refineEdge,
            center: CGPoint(x: 20, y: 32),
            radius: 14,
            extent: extent
        )
        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let before = ctx.createCGImage(mask, from: extent),
              let after = ctx.createCGImage(refined, from: extent)
        else {
            return XCTFail("render")
        }
        XCTAssertNotEqual(fingerprint(before), fingerprint(after))
    }

    func testDecontaminateChangesCutoutFringe() {
        let extent = CGRect(x: 0, y: 0, width: 48, height: 48)
        let mask = CIImage(color: .white)
            .cropped(to: CGRect(x: 12, y: 12, width: 24, height: 24))
            .composited(over: CIImage(color: .black).cropped(to: extent))
            .cropped(to: extent)
        let photo = CIImage(color: CIColor(red: 1, green: 0, blue: 1, alpha: 1)).cropped(to: extent)
        let plain = SelectionCompositor.cutoutWithAlpha(
            image: photo,
            mask: SelectionMask(
                cgImage: render(mask, extent: extent),
                extent: extent,
                confidence: 1,
                semanticClass: .unknown,
                source: .pointPrompt
            ),
            refine: .identity
        )
        var withDecontam = SelectionRefineParameters.identity
        withDecontam.decontaminate = 1
        let cleaned = SelectionCompositor.cutoutWithAlpha(
            image: photo,
            mask: SelectionMask(
                cgImage: render(mask, extent: extent),
                extent: extent,
                confidence: 1,
                semanticClass: .unknown,
                source: .pointPrompt
            ),
            refine: withDecontam
        )
        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let a = ctx.createCGImage(plain, from: extent),
              let b = ctx.createCGImage(cleaned, from: extent)
        else {
            return XCTFail("render")
        }
        XCTAssertNotEqual(fingerprint(a), fingerprint(b))
    }

    func testDecontaminatePullsTowardInteriorColor() {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let core = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 1))
            .cropped(to: CGRect(x: 20, y: 20, width: 24, height: 24))
        let fringe = CIImage(color: CIColor(red: 1, green: 0, blue: 1, alpha: 1))
            .cropped(to: CGRect(x: 16, y: 16, width: 32, height: 32))
        let photo = core.composited(over: fringe.composited(over: CIImage(color: .black).cropped(to: extent)))
            .cropped(to: extent)
        let mask = CIImage(color: .white)
            .cropped(to: CGRect(x: 16, y: 16, width: 32, height: 32))
            .composited(over: CIImage(color: .black).cropped(to: extent))
            .cropped(to: extent)

        let cleaned = SelectionDecontaminate.apply(image: photo, mask: mask, amount: 1, extent: extent)
        let ctx = CIContext(options: [.cacheIntermediates: false])
        var before = [Float](repeating: 0, count: 4)
        var after = [Float](repeating: 0, count: 4)
        let sample = CGRect(x: 17, y: 32, width: 1, height: 1)
        ctx.render(photo, toBitmap: &before, rowBytes: 16, bounds: sample, format: .RGBAf, colorSpace: CGColorSpaceCreateDeviceRGB())
        ctx.render(cleaned, toBitmap: &after, rowBytes: 16, bounds: sample, format: .RGBAf, colorSpace: CGColorSpaceCreateDeviceRGB())
        XCTAssertGreaterThan(after[1], before[1] - 0.05, "green channel should rise toward interior")
        XCTAssertLessThan(after[0] + after[2], before[0] + before[2] + 0.05, "magenta spill should drop")
    }

    private func coverage(_ image: CIImage, extent: CGRect) -> Double {
        let w = Int(extent.width)
        let h = Int(extent.height)
        var buf = [UInt8](repeating: 0, count: w * h)
        CIContext().render(
            image,
            toBitmap: &buf,
            rowBytes: w,
            bounds: extent,
            format: .L8,
            colorSpace: CGColorSpaceCreateDeviceGray()
        )
        return Double(buf.filter { $0 > 32 }.count) / Double(w * h)
    }

    private func grayImage(_ data: [UInt8], width: Int, height: Int) -> CGImage {
        var copy = data
        let ctx = CGContext(
            data: &copy,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        return ctx.makeImage()!
    }

    private func rgbaImage(_ data: [UInt8], width: Int, height: Int) -> CGImage {
        var copy = data
        let ctx = CGContext(
            data: &copy,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    private func render(_ image: CIImage, extent: CGRect) -> CGImage {
        CIContext().createCGImage(image, from: extent)!
    }

    private func fingerprint(_ image: CGImage) -> Int {
        let w = image.width
        let h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(
            data: &buf,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var hash = 0
        for i in stride(from: 0, to: buf.count, by: 17) {
            hash = hash &* 31 &+ Int(buf[i])
        }
        return hash
    }
}
