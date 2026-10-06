import CoreImage
import XCTest
@testable import LaughPlayer

final class ImageAdjustParametersWave2Tests: XCTestCase {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func testIdentityDoesNotChangePixels() {
        let source = solidImage(r: 0.4, g: 0.5, b: 0.6)
        XCTAssertNil(ImageAdjustParameters.identity.applying(to: source))
    }

    func testSharpenAmountChangesOutput() {
        let source = patternedImage()
        let sharp = ImageAdjustParameters(sharpness: 0.8).applying(to: source)
        XCTAssertNotNil(sharp)
        XCTAssertFalse(pixelsNearlyEqual(source, sharp!, tolerance: 0.01))
    }

    func testSharpenRadiusAndDetailMoveOutput() {
        let source = patternedImage()
        let amountOnly = ImageAdjustParameters(sharpness: 0.7).applying(to: source)!
        let radius = ImageAdjustParameters(sharpness: 0.7, sharpenRadius: 1.0).applying(to: source)!
        let detail = ImageAdjustParameters(sharpness: 0.7, sharpenDetail: 0.05).applying(to: source)!
        XCTAssertFalse(pixelsNearlyEqual(amountOnly, radius, tolerance: 0.008))
        XCTAssertFalse(pixelsNearlyEqual(amountOnly, detail, tolerance: 0.008))
    }

    func testDenoiseColorAndDetailMoveOutput() {
        let source = noisyImage()
        let luma = ImageAdjustParameters(denoise: 0.7).applying(to: source)!
        let color = ImageAdjustParameters(denoise: 0.7, denoiseColor: 0.8).applying(to: source)!
        let detail = ImageAdjustParameters(denoise: 0.7, denoiseDetail: 0.05).applying(to: source)!
        XCTAssertFalse(pixelsNearlyEqual(luma, color, tolerance: 0.008))
        XCTAssertFalse(pixelsNearlyEqual(luma, detail, tolerance: 0.008))
    }

    func testSmartContrastChangesMidtones() {
        let source = gradientImage()
        let smart = ImageAdjustParameters(smartContrast: 0.85).applying(to: source)
        XCTAssertNotNil(smart)
        XCTAssertFalse(pixelsNearlyEqual(source, smart!, tolerance: 0.01))
    }

    func testToneCurveChangesOutput() {
        let source = gradientImage()
        var curve = ImageAdjustParameters.identityCurve
        curve[2] = 0.65
        let out = ImageAdjustParameters(curveLuma: curve).applying(to: source)
        XCTAssertNotNil(out)
        XCTAssertFalse(pixelsNearlyEqual(source, out!, tolerance: 0.01))
    }

    func testRGBCurvePointMovesOutput() {
        let source = solidImage(r: 0.55, g: 0.35, b: 0.25)
        var red = ImageAdjustParameters.identityCurve
        red[2] = 0.85
        let out = ImageAdjustParameters(curveRed: red).applying(to: source)
        XCTAssertNotNil(out)
        XCTAssertFalse(pixelsNearlyEqual(source, out!, tolerance: 0.01))
    }

    func testHSLSaturationOnStrongChannelMovesOutput() {
        // Mid-sat red so a Reds sat boost has headroom to change pixels.
        let source = solidImage(r: 0.72, g: 0.38, b: 0.32)
        var sat = Array(repeating: 0.0, count: ImageAdjustParameters.hslChannelCount)
        sat[0] = 1.0
        let out = ImageAdjustParameters(hslSat: sat).applying(to: source)
        XCTAssertNotNil(out)
        XCTAssertFalse(pixelsNearlyEqual(source, out!, tolerance: 0.008))
    }

    func testHSLRedsEditLeavesPureBlueMostlyAlone() {
        let blue = solidImage(r: 0.12, g: 0.18, b: 0.88)
        var sat = Array(repeating: 0.0, count: ImageAdjustParameters.hslChannelCount)
        sat[0] = 1.0
        let out = ImageAdjustParameters(hslSat: sat).applying(to: blue) ?? blue
        // Selective HSL: a Reds-only sat boost should barely move a pure blue patch.
        XCTAssertTrue(pixelsNearlyEqual(blue, out, tolerance: 0.06))
    }

    func testLenientPresetDecodeFillsMissingWave2Fields() throws {
        // Legacy payload without smartContrast / curves / hsl / optics keys.
        let legacy = """
        {"exposure":0.25,"brightness":0,"contrast":1,"highlights":1,"shadows":0,\
        "whites":0,"blacks":0,"saturation":1.1,"vibrance":0,"hue":0,"temperature":0,\
        "tint":0,"colorBalance":0,"splitHighlight":0,"splitShadow":0,"splitAmount":0,\
        "dramatic":0,"mood":0,"matte":0,"glow":0,"glowRadius":0.45,"blur":0,\
        "filmGrain":0,"filmGrainSize":0.45,"mystical":0,"mysticalHaze":0.4,"mysticalHue":-0.25,\
        "toningAmount":0,"toningHighlights":0,"toningShadows":0,"highKey":0,"highKeySoftness":0.35,\
        "supercontrast":0,"supercontrastMidtones":0.5,"colorHarmony":0,"colorHarmonyBalance":0.15,\
        "sunrays":0,"sunraysLength":0.55,"sunraysWarmth":0.45,"landscape":0,\
        "landscapeFoliage":0.55,"landscapeSky":0.45,"blackAndWhite":0,"bwContrast":0.15,"bwWarmth":0,\
        "sharpness":0,"definition":0,"structure":0,"denoise":0,"vignette":0,"vignetteMidpoint":0.5,\
        "dodgeBurn":0,"dodgeBurnRange":0,"dodgeBurnSoftness":0.45}
        """.data(using: .utf8)!
        let params = try ImageAdjustParameters.decodingLenient(from: legacy)
        XCTAssertEqual(params.exposure, 0.25, accuracy: 0.0001)
        XCTAssertEqual(params.saturation, 1.1, accuracy: 0.0001)
        XCTAssertEqual(params.smartContrast, 0, accuracy: 0.0001)
        XCTAssertEqual(params.curveLuma, ImageAdjustParameters.identityCurve)
        XCTAssertEqual(params.sharpenRadius, 0.4, accuracy: 0.0001)
        XCTAssertEqual(params.vignetteCenterX, 0.5, accuracy: 0.0001)
        XCTAssertEqual(params.distortion, 0, accuracy: 0.0001)
    }

    func testVignetteCenterMovesOutput() {
        let source = solidImage(r: 0.55, g: 0.55, b: 0.55)
        let centered = ImageAdjustParameters(vignette: 0.9).applying(to: source)!
        let offset = ImageAdjustParameters(
            vignette: 0.9,
            vignetteCenterX: 0.2,
            vignetteCenterY: 0.8
        ).applying(to: source)!
        XCTAssertFalse(pixelsNearlyEqual(centered, offset, tolerance: 0.01))
    }

    func testOpticsDistortionAndCAMoveOutput() {
        let source = patternedImage()
        let distortion = ImageAdjustParameters(distortion: 0.9).applying(to: source)
        let ca = ImageAdjustParameters(chromaticAberration: 1.0).applying(to: source)
        XCTAssertNotNil(distortion)
        XCTAssertNotNil(ca)
        // Sample near a high-contrast corner so warp / channel shift is visible.
        XCTAssertFalse(pixelsNearlyEqual(source, distortion!, tolerance: 0.01, sampleInset: 6))
        XCTAssertFalse(pixelsNearlyEqual(source, ca!, tolerance: 0.01, sampleInset: 6))
    }

    func testWhiteBalanceOffsetsCoolWarmSample() {
        let warm = ImageAdjustParameters.whiteBalanceOffsets(fromNeutralRGB: 0.9, g: 0.55, b: 0.35)
        XCTAssertLessThan(warm.temperature, 0)
        let cool = ImageAdjustParameters.whiteBalanceOffsets(fromNeutralRGB: 0.35, g: 0.5, b: 0.9)
        XCTAssertGreaterThan(cool.temperature, 0)
        let green = ImageAdjustParameters.whiteBalanceOffsets(fromNeutralRGB: 0.4, g: 0.9, b: 0.4)
        XCTAssertGreaterThan(green.tint, 0)
    }

    // MARK: - Helpers

    private func solidImage(r: CGFloat, g: CGFloat, b: CGFloat, size: CGFloat = 32) -> CIImage {
        CIImage(color: CIColor(red: r, green: g, blue: b, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    private func patternedImage() -> CIImage {
        guard let checker = CIFilter(name: "CICheckerboardGenerator") else {
            return solidImage(r: 0.3, g: 0.3, b: 0.3)
        }
        checker.setValue(CIVector(x: 0, y: 0), forKey: "inputCenter")
        checker.setValue(CIColor(red: 0.1, green: 0.1, blue: 0.1), forKey: "inputColor0")
        checker.setValue(CIColor(red: 0.9, green: 0.9, blue: 0.9), forKey: "inputColor1")
        checker.setValue(NSNumber(value: 4), forKey: "inputWidth")
        return (checker.outputImage ?? solidImage(r: 0.5, g: 0.5, b: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 48, height: 48))
    }

    private func noisyImage() -> CIImage {
        let base = patternedImage()
        guard let noise = CIFilter(name: "CIRandomGenerator"),
              let noiseImage = noise.outputImage?.cropped(to: base.extent),
              let mix = CIFilter(name: "CIDissolveTransition")
        else { return base }
        mix.setValue(base, forKey: kCIInputImageKey)
        mix.setValue(noiseImage, forKey: kCIInputTargetImageKey)
        mix.setValue(NSNumber(value: 0.35), forKey: kCIInputTimeKey)
        return mix.outputImage?.cropped(to: base.extent) ?? base
    }

    private func gradientImage() -> CIImage {
        guard let filter = CIFilter(name: "CILinearGradient") else {
            return solidImage(r: 0.5, g: 0.5, b: 0.5)
        }
        filter.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        filter.setValue(CIColor(red: 0.05, green: 0.05, blue: 0.05), forKey: "inputColor0")
        filter.setValue(CIVector(x: 48, y: 48), forKey: "inputPoint1")
        filter.setValue(CIColor(red: 0.95, green: 0.95, blue: 0.95), forKey: "inputColor1")
        return (filter.outputImage ?? solidImage(r: 0.5, g: 0.5, b: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 48, height: 48))
    }

    private func pixelsNearlyEqual(
        _ a: CIImage,
        _ b: CIImage,
        tolerance: Float,
        sampleInset: CGFloat = 0
    ) -> Bool {
        let extent = a.extent.intersection(b.extent)
        guard extent.width >= 4, extent.height >= 4 else { return false }
        let sample = CGRect(
            x: extent.minX + sampleInset + 2,
            y: extent.minY + sampleInset + 2,
            width: 4,
            height: 4
        )
        var bufA = [Float](repeating: 0, count: 4 * 16)
        var bufB = [Float](repeating: 0, count: 4 * 16)
        context.render(a, toBitmap: &bufA, rowBytes: 16 * MemoryLayout<Float>.size, bounds: sample, format: .RGBAf, colorSpace: nil)
        context.render(b, toBitmap: &bufB, rowBytes: 16 * MemoryLayout<Float>.size, bounds: sample, format: .RGBAf, colorSpace: nil)
        var maxDelta: Float = 0
        for i in 0..<bufA.count {
            maxDelta = max(maxDelta, abs(bufA[i] - bufB[i]))
        }
        return maxDelta <= tolerance
    }
}
