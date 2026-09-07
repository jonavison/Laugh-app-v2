import AppKit
import CoreImage
import XCTest
@testable import LaughPlayer

final class ImageSelectionTests: XCTestCase {
    func testUnsupportedClassThrows() async {
        let provider = VisionPersonSelectionProvider()
        let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        do {
            _ = try await provider.selectClass(in: image, class: .sky, quality: .preview)
            XCTFail("Expected unsupportedClass")
        } catch let error as SelectionError {
            XCTAssertEqual(error, .unsupportedClass(.sky))
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testInvalidImageThrows() async {
        let provider = VisionPersonSelectionProvider()
        let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        do {
            _ = try await provider.selectClass(in: image, class: .person, quality: .preview)
            XCTFail("Expected invalidImage")
        } catch let error as SelectionError {
            XCTAssertEqual(error, .invalidImage)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testSolidColorYieldsEmptyOrPersonMask() async {
        let provider = VisionPersonSelectionProvider()
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 256, height: 256))
        do {
            let mask = try await provider.selectClass(in: image, class: .person, quality: .preview)
            XCTAssertEqual(mask.semanticClass, .person)
            XCTAssertEqual(mask.source, .visionPerson)
            XCTAssertGreaterThan(mask.extent.width, 1)
            XCTAssertGreaterThan(mask.extent.height, 1)
        } catch let error as SelectionError {
            XCTAssertEqual(error, .emptyResult)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testPreviewScalingCapsLongEdge() {
        let large = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 4000, height: 2000))
        let scaled = VisionPersonSelectionProvider.scaledForPreview(large)
        XCTAssertLessThanOrEqual(max(scaled.extent.width, scaled.extent.height), VisionPersonSelectionProvider.previewMaxEdge + 1)
    }

    func testSelectionMaskScalesToTargetExtent() {
        let cg = makeGrayMatte(width: 50, height: 40)
        let mask = SelectionMask(
            cgImage: cg,
            extent: CGRect(x: 0, y: 0, width: 50, height: 40),
            confidence: 1,
            semanticClass: .person,
            source: .visionPerson
        )
        let matched = mask.ciImageMatching(extent: CGRect(x: 0, y: 0, width: 200, height: 160))
        XCTAssertEqual(matched.extent.width, 200, accuracy: 1)
        XCTAssertEqual(matched.extent.height, 160, accuracy: 1)
    }

    func testMattePrecisionRefineSnapsBoundary() {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        // Soft gray matte blob.
        var maskData = [UInt8](repeating: 0, count: 64 * 64)
        for y in 16..<48 {
            for x in 16..<48 {
                maskData[y * 64 + x] = 140
            }
        }
        let gray = CGColorSpaceCreateDeviceGray()
        let maskCtx = CGContext(
            data: &maskData,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 64,
            space: gray,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let maskCG = maskCtx.makeImage()!
        let mask = CIImage(cgImage: maskCG)

        // Photo with a hard luminance step at x=20 (strong edge inside soft matte).
        var photoData = [UInt8](repeating: 30, count: 64 * 64 * 4)
        for y in 0..<64 {
            for x in 0..<64 {
                let i = (y * 64 + x) * 4
                let v: UInt8 = x >= 20 ? 220 : 30
                photoData[i] = v
                photoData[i + 1] = v
                photoData[i + 2] = v
                photoData[i + 3] = 255
            }
        }
        let rgb = CGColorSpaceCreateDeviceRGB()
        let photoCtx = CGContext(
            data: &photoData,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 64 * 4,
            space: rgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let photoCG = photoCtx.makeImage()!
        let photo = CIImage(cgImage: photoCG)

        let refined = SelectionMattePrecision.refine(mask: mask, photo: photo, extent: extent)
        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let before = ctx.createCGImage(mask, from: extent),
              let after = ctx.createCGImage(refined, from: extent)
        else {
            return XCTFail("render failed")
        }
        XCTAssertNotEqual(fingerprint(before), fingerprint(after), "Precision refine should alter the soft matte")
    }

    func testCompositorOverlayChangesImage() {
        let image = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        let cg = makeGrayMatte(width: 32, height: 32, fill: 255)
        let mask = SelectionMask(
            cgImage: cg,
            extent: image.extent,
            confidence: 1,
            semanticClass: .person,
            source: .visionPerson
        )
        let out = SelectionCompositor.apply(
            image: image,
            mask: mask,
            mode: .overlay,
            appearance: NSAppearance(named: .darkAqua)!
        )
        XCTAssertEqual(out.extent, image.extent)
    }

    func testPreviewCycleOrderAndNext() {
        XCTAssertEqual(SelectionDisplayMode.previewCycle.count, 7)
        XCTAssertEqual(SelectionDisplayMode.overlay.nextInPreviewCycle(), .onBlack)
        XCTAssertEqual(SelectionDisplayMode.onLayers.nextInPreviewCycle(), .onionSkin)
        XCTAssertEqual(SelectionDisplayMode.none.nextInPreviewCycle(), .onionSkin)
    }

    func testAllPreviewModesRenderExtent() {
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 48, height: 48))
        // Half-selected matte so modes that depend on edges / contrast have signal.
        var data = [UInt8](repeating: 0, count: 48 * 48)
        for y in 0..<48 {
            for x in 0..<48 {
                if x < 24 { data[y * 48 + x] = 255 }
            }
        }
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(
            data: &data,
            width: 48,
            height: 48,
            bitsPerComponent: 8,
            bytesPerRow: 48,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let cg = ctx.makeImage()!
        let mask = SelectionMask(
            cgImage: cg,
            extent: image.extent,
            confidence: 1,
            semanticClass: .person,
            source: .visionPerson
        )
        let appearance = NSAppearance(named: .aqua)!
        for mode in SelectionDisplayMode.previewCycle {
            let out = SelectionCompositor.apply(
                image: image,
                mask: mask,
                mode: mode,
                appearance: appearance,
                antsPhase: 12
            )
            XCTAssertEqual(out.extent.integral, image.extent.integral, "mode \(mode.rawValue)")
        }
    }

    func testMarchingAntsDiffersFromSource() {
        let image = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        var data = [UInt8](repeating: 0, count: 64 * 64)
        for y in 12..<52 {
            for x in 12..<52 {
                data[y * 64 + x] = 255
            }
        }
        let cs = CGColorSpaceCreateDeviceGray()
        let grayCtx = CGContext(
            data: &data,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 64,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let cg = grayCtx.makeImage()!
        let mask = SelectionMask(
            cgImage: cg,
            extent: image.extent,
            confidence: 1,
            semanticClass: .person,
            source: .visionPerson
        )
        let appearance = NSAppearance(named: .aqua)!
        let ants = SelectionCompositor.apply(
            image: image,
            mask: mask,
            mode: .marchingAnts,
            appearance: appearance,
            antsPhase: 8
        )
        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let srcCG = ctx.createCGImage(image, from: image.extent.integral),
              let antsCG = ctx.createCGImage(ants, from: ants.extent.integral)
        else {
            return XCTFail("render failed")
        }
        XCTAssertNotEqual(fingerprint(srcCG), fingerprint(antsCG), "Marching ants should paint over the photo")

        // Regression: zebra wash painted full-frame when the edge gate was soft.
        // Corners / interior must stay near the source color (allow tiny CI round-trip drift).
        assertNearRGB(sampleRGB(srcCG, x: 2, y: 2), sampleRGB(antsCG, x: 2, y: 2))
        assertNearRGB(sampleRGB(srcCG, x: 61, y: 2), sampleRGB(antsCG, x: 61, y: 2))
        assertNearRGB(sampleRGB(srcCG, x: 2, y: 61), sampleRGB(antsCG, x: 2, y: 61))
        assertNearRGB(sampleRGB(srcCG, x: 61, y: 61), sampleRGB(antsCG, x: 61, y: 61))
        assertNearRGB(sampleRGB(srcCG, x: 32, y: 32), sampleRGB(antsCG, x: 32, y: 32))
        // And must not be pure white dash paint (old zebra / white-ant symptom).
        // Pure black is allowed only on the contour — corners/interior must stay photographic.
        for point in [(2, 2), (61, 2), (2, 61), (61, 61), (32, 32)] as [(Int, Int)] {
            let rgb = sampleRGB(antsCG, x: point.0, y: point.1)
            let isPureWhite = rgb.0 == 255 && rgb.1 == 255 && rgb.2 == 255
            let isPureBlack = rgb.0 == 0 && rgb.1 == 0 && rgb.2 == 0
            XCTAssertFalse(isPureWhite, "Unexpected white dash paint at \(point)")
            XCTAssertFalse(isPureBlack, "Unexpected black dash away from contour at \(point)")
        }
    }

    func testRefineShiftEdgeChangesMatte() {
        let image = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        var data = [UInt8](repeating: 0, count: 64 * 64)
        for y in 20..<44 {
            for x in 20..<44 {
                data[y * 64 + x] = 255
            }
        }
        let cs = CGColorSpaceCreateDeviceGray()
        let grayCtx = CGContext(
            data: &data,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 64,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let cg = grayCtx.makeImage()!
        let mask = SelectionMask(
            cgImage: cg,
            extent: image.extent,
            confidence: 1,
            semanticClass: .person,
            source: .visionPerson
        )
        let appearance = NSAppearance(named: .darkAqua)!
        let plain = SelectionCompositor.apply(
            image: image,
            mask: mask,
            mode: .blackAndWhite,
            appearance: appearance
        )
        let shifted = SelectionCompositor.apply(
            image: image,
            mask: mask,
            mode: .blackAndWhite,
            appearance: appearance,
            refine: SelectionRefineParameters(shiftEdge: 0.8)
        )
        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let a = ctx.createCGImage(plain, from: plain.extent.integral),
              let b = ctx.createCGImage(shifted, from: shifted.extent.integral)
        else {
            return XCTFail("render failed")
        }
        XCTAssertNotEqual(fingerprint(a), fingerprint(b))
    }

    func testSessionResetClearsMask() {
        let session = ImageSelectionSession(provider: VisionPersonSelectionProvider())
        let expectation = expectation(description: "chrome")
        expectation.assertForOverFulfill = false
        session.onChromeChange = { expectation.fulfill() }
        session.resetAll()
        wait(for: [expectation], timeout: 1)
        XCTAssertFalse(session.hasSelection)
        XCTAssertEqual(session.currentDisplayMode, .marchingAnts)
    }

    func testCutoutFileName() {
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        XCTAssertEqual(ImageExportWriter.suggestedCutoutFileName(for: url), "photo-cutout.png")
    }

    private func assertNearRGB(
        _ a: (UInt8, UInt8, UInt8),
        _ b: (UInt8, UInt8, UInt8),
        tolerance: Int = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(abs(Int(a.0) - Int(b.0)), tolerance, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(Int(a.1) - Int(b.1)), tolerance, file: file, line: line)
        XCTAssertLessThanOrEqual(abs(Int(a.2) - Int(b.2)), tolerance, file: file, line: line)
    }

    private func sampleRGB(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .none
        ctx.translateBy(x: CGFloat(-x), y: CGFloat(-y))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (pixel[0], pixel[1], pixel[2])
    }

    private func fingerprint(_ image: CGImage) -> UInt64 {
        let width = min(image.width, 32)
        let height = min(image.height, 32)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var hash: UInt64 = 14695981039346656037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    private func makeGrayMatte(width: Int, height: Int, fill: UInt8 = 200) -> CGImage {
        var data = [UInt8](repeating: fill, count: width * height)
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        return ctx.makeImage()!
    }
}
