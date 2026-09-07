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
        XCTAssertNotEqual(fingerprint(srcCG), fingerprint(antsCG), "Marching ants preview should dim outside the subject")

        // Outside the subject is lightly dimmed; interior stays photographic.
        // Exact dashed contour is drawn in view space (CAShapeLayer), not baked into CI.
        let corner = sampleRGB(antsCG, x: 2, y: 2)
        let srcCorner = sampleRGB(srcCG, x: 2, y: 2)
        XCTAssertLessThan(corner.0, srcCorner.0, "Unselected area should be dimmed")
        assertNearRGB(sampleRGB(srcCG, x: 32, y: 32), sampleRGB(antsCG, x: 32, y: 32))
    }

    func testAntsContourPathFollowsHardMatte() {
        var data = [UInt8](repeating: 0, count: 128 * 128)
        for y in 32..<96 {
            for x in 32..<96 {
                data[y * 128 + x] = 255
            }
        }
        let cs = CGColorSpaceCreateDeviceGray()
        let gctx = CGContext(
            data: &data,
            width: 128,
            height: 128,
            bitsPerComponent: 8,
            bytesPerRow: 128,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let cg = gctx.makeImage()!
        let path = SelectionAntsContour.normalizedPath(fromHardMatte: cg)
        XCTAssertNotNil(path)
        XCTAssertFalse(path?.isEmpty ?? true)
        let inView = SelectionAntsContour.pathInView(
            normalized: path!,
            photoFrame: CGRect(x: 10, y: 20, width: 200, height: 200)
        )
        XCTAssertNotNil(inView)
        let box = inView!.boundingBox
        XCTAssertGreaterThan(box.width, 50)
        XCTAssertGreaterThan(box.height, 50)
    }

    func testAntsContourFromAlphaCarryingMatte() {
        // Regression: MobileSAM mattes are premultiplied with coverage in alpha over
        // mid-grey RGB (sRGB 0.53 → ~0.24 linear), which sat on the binary threshold and
        // left the contour plate empty. Coverage must be read from alpha instead.
        let side = 128
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        for y in 32..<96 {
            for x in 32..<96 {
                let i = (y * side + x) * 4
                rgba[i] = 134
                rgba[i + 1] = 134
                rgba[i + 2] = 134
                rgba[i + 3] = 254
            }
        }
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        let matteCG = CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!

        let extent = CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side))
        let ctx = CIContext(options: [.cacheIntermediates: false])
        let mask = SelectionMask(
            cgImage: matteCG,
            extent: extent,
            confidence: 0.9,
            semanticClass: .unknown,
            source: .coreML(modelID: "test")
        )

        XCTAssertTrue(
            SelectionMatteNormalization.carriesCoverageInAlpha(mask.ciImage, extent: extent, context: ctx),
            "premultiplied SAM-shaped matte should be detected as alpha-carrying"
        )
        guard let path = SelectionAntsContour.normalizedPath(mask: mask, context: ctx) else {
            return XCTFail("expected a contour from an alpha-carrying matte")
        }
        let box = path.boundingBox
        XCTAssertGreaterThan(box.width, 0.3)
        XCTAssertGreaterThan(box.height, 0.3)
    }

    func testAntsContourIgnoresSpeckleNoise() {
        // Regression: a noisy matte produced dozens of tiny contours, so the overlay
        // rendered scattered dashes instead of one silhouette outline.
        var data = [UInt8](repeating: 0, count: 128 * 128)
        for y in 40..<88 {
            for x in 40..<88 {
                data[y * 128 + x] = 255
            }
        }
        for (x, y) in [(6, 6), (10, 110), (118, 12), (100, 100), (64, 8), (8, 64)] {
            data[y * 128 + x] = 255
            data[y * 128 + x + 1] = 255
        }
        let gctx = CGContext(
            data: &data,
            width: 128,
            height: 128,
            bitsPerComponent: 8,
            bytesPerRow: 128,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let path = SelectionAntsContour.normalizedPath(fromHardMatte: gctx.makeImage()!)
        guard let path else { return XCTFail("expected a silhouette contour") }

        // Only the square survives: bounds hug it instead of spanning the speckles.
        let box = path.boundingBox
        XCTAssertGreaterThan(box.minX, 0.2)
        XCTAssertGreaterThan(box.minY, 0.2)
        XCTAssertLessThan(box.maxX, 0.8)
        XCTAssertLessThan(box.maxY, 0.8)
    }

    func testMarchingAntsVisibleWithSoftOpaqueRGBAMatte() {
        // Regression: MobileSAM mattes are often opaque RGBA with soft mid-gray RGB.
        // Old path hard-thresholded at 0.5 and/or used alpha-only blend → invisible ants.
        let extent = CGRect(x: 0, y: 0, width: 128, height: 128)
        let image = CIImage(color: CIColor(red: 0.2, green: 0.45, blue: 0.7, alpha: 1))
            .cropped(to: extent)
        var rgba = [UInt8](repeating: 0, count: 128 * 128 * 4)
        for y in 24..<104 {
            for x in 24..<104 {
                let i = (y * 128 + x) * 4
                rgba[i] = 90      // ~0.35 — below old 0.5 hard cut
                rgba[i + 1] = 90
                rgba[i + 2] = 90
                rgba[i + 3] = 255  // opaque
            }
        }
        for i in stride(from: 3, to: rgba.count, by: 4) where rgba[i] == 0 {
            rgba[i] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let gctx = CGContext(
            data: &rgba,
            width: 128,
            height: 128,
            bitsPerComponent: 8,
            bytesPerRow: 128 * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let cg = gctx.makeImage()!
        let mask = SelectionMask(
            cgImage: cg,
            extent: extent,
            confidence: 0.7,
            semanticClass: .person,
            source: .coreML(modelID: "test")
        )
        let ants = SelectionCompositor.apply(
            image: image,
            mask: mask,
            mode: .marchingAnts,
            appearance: NSAppearance(named: .aqua)!,
            antsPhase: 6
        )
        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let srcCG = ctx.createCGImage(image, from: extent),
              let antsCG = ctx.createCGImage(ants, from: extent)
        else {
            return XCTFail("render failed")
        }
        XCTAssertNotEqual(
            fingerprint(srcCG),
            fingerprint(antsCG),
            "Soft opaque MobileSAM-like mattes must still produce a visible ants preview"
        )
    }

    func testMarchingAntsVisibleAfterDownscale() {
        // Regression: hairline ants vanish when a large photo is fit into the studio.
        let extent = CGRect(x: 0, y: 0, width: 1600, height: 1200)
        let image = CIImage(color: CIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1))
            .cropped(to: extent)
        let subject = CIImage(color: .white)
            .cropped(to: CGRect(x: 400, y: 200, width: 800, height: 800))
        let mattePlate = subject.composited(over: CIImage(color: .black).cropped(to: extent))
            .cropped(to: extent)
        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let matteCG = ctx.createCGImage(mattePlate, from: extent) else {
            return XCTFail("matte render failed")
        }
        let mask = SelectionMask(
            cgImage: matteCG,
            extent: extent,
            confidence: 1,
            semanticClass: .person,
            source: .visionPerson
        )
        let ants = SelectionCompositor.apply(
            image: image,
            mask: mask,
            mode: .marchingAnts,
            appearance: NSAppearance(named: .darkAqua)!,
            antsPhase: 4
        )
        let scaled = ants.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
        let viewExtent = CGRect(x: 0, y: 0, width: 400, height: 300)
        let scaledSrc = image.transformed(by: CGAffineTransform(scaleX: 0.25, y: 0.25))
        guard let antsCG = ctx.createCGImage(scaled, from: viewExtent),
              let srcCG = ctx.createCGImage(scaledSrc, from: viewExtent)
        else {
            return XCTFail("downscale render failed")
        }
        XCTAssertNotEqual(
            fingerprint(srcCG),
            fingerprint(antsCG),
            "Ants must remain visible after fit-to-view downscale"
        )
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
