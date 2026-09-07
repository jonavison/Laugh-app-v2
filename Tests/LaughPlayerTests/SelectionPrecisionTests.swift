import XCTest
import CoreImage
import CoreGraphics
@testable import LaughPlayer

/// Measures how closely Subject Select tracks a known silhouette — both the matte and the
/// marching-ants contour the user actually sees. Logs `[SEL-PRECISION]` lines.
final class SelectionPrecisionTests: XCTestCase {
    private static let logPrefix = "[SEL-PRECISION]"
    private let side = 384

    private func log(_ message: String) {
        print("\(Self.logPrefix) \(message)")
    }

    /// Off-centre ellipse on a contrasting background: hard edges, known area, and
    /// asymmetric so a flipped contour scores badly instead of passing by symmetry.
    private func syntheticSubject() -> (photo: CIImage, truth: [UInt8], extent: CGRect) {
        let width = side
        let height = side
        let shape = CGRect(x: 70, y: 110, width: 210, height: 240)

        var photo = [UInt8](repeating: 0, count: width * height * 4)
        var truth = [UInt8](repeating: 0, count: width * height)
        let ellipse = CGPath(ellipseIn: shape, transform: nil)
        guard let truthCtx = CGContext(
            data: &truth,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { fatalError("truth ctx") }
        truthCtx.setFillColor(gray: 1, alpha: 1)
        truthCtx.addPath(ellipse)
        truthCtx.fillPath()

        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let inside = truth[y * width + x] > 127
                photo[i] = inside ? 210 : 40
                photo[i + 1] = inside ? 70 : 44
                photo[i + 2] = inside ? 60 : 48
                photo[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(photo) as CFData)!
        let photoCG = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return (
            CIImage(cgImage: photoCG),
            truth,
            CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        )
    }

    /// Boundary quality on real photos, with and without the photo-edge polish. No ground
    /// truth exists for these, so we track softness (crispness) and edge agreement.
    func testRealFixtureBoundaryQuality() async throws {
        let store = SelectionModelStore()
        guard store.isReady(SelectionModelArtifact.mobileSAM) else {
            throw XCTSkip("MobileSAM not cached — run Auto Select once in-app first.")
        }
        var means: [Bool: (soft: Double, agree: Double)] = [:]
        for polish in [false, true] {
            let provider = MobileSAMSelectionProvider(store: store, applyPolish: polish)
            var softs: [Double] = []
            var agreements: [Double] = []
            for fixture in SelectionMeasurementHarness.personFixtures {
                let photo = try SelectionMeasurementHarness.loadCIImage(named: fixture)
                let center = CGPoint(x: photo.extent.midX, y: photo.extent.midY)
                let mask = try await provider.select(in: photo, prompt: .point(center), quality: .accurate)
                let soft = SelectionMeasurementHarness.boundarySoftness(mask)
                let agree = SelectionMeasurementHarness.edgeAgreement(mask: mask, photo: photo)
                softs.append(soft)
                agreements.append(agree)
                log(String(format: "polish=%@ %@ soft=%.4f edgeAgree=%.4f", polish ? "on " : "off", fixture, soft, agree))
            }
            let meanSoft = softs.reduce(0, +) / Double(softs.count)
            let meanAgree = agreements.reduce(0, +) / Double(agreements.count)
            means[polish] = (meanSoft, meanAgree)
            log(String(format: "polish=%@ MEAN soft=%.4f edgeAgree=%.4f", polish ? "on " : "off", meanSoft, meanAgree))
        }

        let off = try XCTUnwrap(means[false])
        let on = try XCTUnwrap(means[true])
        // Polish must earn its cost on both axes: a crisper edge that also sits on real
        // photo structure. Guided upsample + edge tightening moved it from 0.35/0.10.
        XCTAssertLessThan(on.soft, off.soft, "polish should sharpen, not blur, the boundary")
        XCTAssertGreaterThan(on.agree, off.agree, "polish should pull the boundary onto photo edges")
        XCTAssertLessThan(on.soft, 0.15, "boundary softness regressed")
        XCTAssertGreaterThan(on.agree, 0.12, "edge agreement regressed")
    }

    /// The ants contour is rebuilt on the main thread, so the raised plate cap must not
    /// turn Auto Select on a big photo into a visible hitch.
    func testAntsContourStaysWithinMainThreadBudget() async throws {
        let photo = try SelectionMeasurementHarness.loadCIImage(named: "person-portrait-2k.jpg")
        let ctx = CIContext(options: [.cacheIntermediates: false])
        let mask = try await VisionPersonSelectionProvider()
            .selectClass(in: photo, class: .person, quality: .accurate)

        // Warm caches so the number reflects steady-state redraws, not first-use setup.
        _ = SelectionAntsContour.normalizedPath(mask: mask, context: ctx)
        let start = CFAbsoluteTimeGetCurrent()
        let path = SelectionAntsContour.normalizedPath(mask: mask, context: ctx)
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log(String(format: "contour %dx%d %.1fms", Int(photo.extent.width), Int(photo.extent.height), ms))
        XCTAssertNotNil(path)
        XCTAssertLessThan(ms, 400, "ants contour rebuild would stall the UI")
    }

    /// SAM's upsampled logits leave a checkerboard wherever the model is undecided (dark
    /// hair on a dark background). Refine must consolidate that into solid coverage — if it
    /// steepens the speckle instead, the region survives only as sub-threshold specks and
    /// vanishes from the outline.
    func testRefineConsolidatesAmbiguousSpeckleIntoSolidCoverage() {
        let width = 256
        let height = 128
        let extent = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let band = CGRect(x: 32, y: 64, width: 192, height: 48)

        var matte = [UInt8](repeating: 0, count: width * height * 4)
        var photo = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let inBand = band.contains(CGPoint(x: CGFloat(x), y: CGFloat(height - 1 - y)))
                let solid = y > height - 40 && x > 32 && x < 224
                // Checkerboard in 3px blocks, mean 0.5 — the upsample artefact shape.
                let checker = ((x / 3) + (y / 3)) % 2 == 0
                let value: UInt8 = solid ? 255 : (inBand ? (checker ? 90 : 165) : 0)
                matte[i] = value
                matte[i + 1] = value
                matte[i + 2] = value
                matte[i + 3] = 255
                // Flat, dark photo: no edge for the gate to snap to, as in a dark scene.
                let luma: UInt8 = 38
                photo[i] = luma
                photo[i + 1] = luma
                photo[i + 2] = luma
                photo[i + 3] = 255
            }
        }

        func image(_ bytes: [UInt8]) -> CIImage {
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            let cg = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )!
            return CIImage(cgImage: cg)
        }

        let ctx = CIContext(options: [.cacheIntermediates: false])
        let refined = SelectionMattePrecision.refine(
            mask: image(matte),
            photo: image(photo),
            extent: extent
        )
        let plate = SelectionCompositor.hardBinaryMatte(mask: refined, extent: extent)
        let raster = SelectionMeasurementHarness.binaryRaster(plate, extent: extent, context: ctx)

        // Rows are top-down; convert the CI band rect once.
        let rowRange = (height - Int(band.maxY))..<(height - Int(band.minY))
        var on = 0
        var total = 0
        var transitions = 0
        for row in rowRange {
            var previous: Bool?
            for x in Int(band.minX)..<Int(band.maxX) {
                let lit = raster[row * width + x] > 127
                if lit { on += 1 }
                total += 1
                if let previous, previous != lit { transitions += 1 }
                previous = lit
            }
        }
        let coverage = Double(on) / Double(total)
        let speckle = Double(transitions) / Double(total)
        log(String(format: "ambiguous band coverage=%.3f speckle=%.3f", coverage, speckle))

        XCTAssertGreaterThan(coverage, 0.8, "ambiguous region should resolve as selected, not shaved off")
        XCTAssertLessThan(speckle, 0.05, "ambiguous region should be solid, not salt-and-pepper")
    }

    func testMobileSAMMattePrecisionOnKnownSilhouette() async throws {
        let store = SelectionModelStore()
        guard store.isReady(SelectionModelArtifact.mobileSAM) else {
            throw XCTSkip("MobileSAM not cached — run Auto Select once in-app first.")
        }
        let (photo, truth, extent) = syntheticSubject()
        let ctx = CIContext(options: [.cacheIntermediates: false])
        let provider = MobileSAMSelectionProvider(store: store)
        let mask = try await provider.select(
            in: photo,
            prompt: .point(CGPoint(x: 175, y: 230)),
            quality: .accurate
        )

        let plate = SelectionCompositor.hardBinaryMatte(
            mask: mask.ciImageMatching(extent: extent),
            extent: extent
        )
        let matteScore = SelectionMeasurementHarness.accuracy(
            prediction: SelectionMeasurementHarness.binaryRaster(plate, extent: extent, context: ctx),
            truth: truth,
            width: side,
            height: side
        )
        log(String(format: "matte iou=%.4f offsetPx=%+.2f", matteScore.iou, matteScore.boundaryOffsetPx))

        guard let normalized = SelectionAntsContour.normalizedPath(mask: mask, context: ctx) else {
            return XCTFail("no ants contour")
        }
        guard let viewPath = SelectionAntsContour.pathInView(normalized: normalized, photoFrame: extent) else {
            return XCTFail("no view path")
        }
        let antsScore = SelectionMeasurementHarness.accuracy(
            prediction: SelectionMeasurementHarness.binaryRaster(path: viewPath, width: side, height: side),
            truth: truth,
            width: side,
            height: side
        )
        log(String(format: "ants  iou=%.4f offsetPx=%+.2f", antsScore.iou, antsScore.boundaryOffsetPx))

        XCTAssertGreaterThan(matteScore.iou, 0.95, "matte should track a hard-edged silhouette")
        XCTAssertLessThan(abs(matteScore.boundaryOffsetPx), 1.5, "matte edge should not sit off the true edge")
        // The ants path is what the user sees, so it must not be looser than the matte.
        XCTAssertGreaterThan(antsScore.iou, 0.95, "ants contour should track the matte")
        XCTAssertLessThan(abs(antsScore.boundaryOffsetPx), 1.5, "ants contour should hug the true edge")
    }
}
