import AppKit
import CoreImage
import XCTest
@testable import LaughPlayer

/// Second-wave hard checks: geometry cutout export, develops, cache, thrash, artifacts.
final class ImageSelectionExtendedTests: XCTestCase {
    private static let logPrefix = "[SEL-EXT]"

    private static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Selection", isDirectory: true)
    }

    private static var artifactDir: URL {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".tmp/selection-artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixtureURL(_ name: String) -> URL {
        Self.fixturesDir.appendingPathComponent(name)
    }

    private func loadCIImage(_ name: String) throws -> CIImage {
        let url = fixtureURL(name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing \(name)")
        guard let ns = NSImage(contentsOf: url),
              let tiff = ns.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage
        else { throw SelectionError.invalidImage }
        return CIImage(cgImage: cg)
    }

    private func log(_ message: String) {
        print("\(Self.logPrefix) \(message)")
    }

    private func matteCoverage(_ mask: SelectionMask) -> Double {
        let cg = mask.cgImage
        let w = min(cg.width, 96)
        let h = min(cg.height, 96)
        guard w > 0, h > 0,
              let ctx = CGContext(
                data: nil,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return 0 }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return 0 }
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h)
        var on = 0
        for i in 0..<(w * h) where buf[i] > 32 { on += 1 }
        return Double(on) / Double(w * h)
    }

    private func alphaCoverage(_ image: CGImage) -> Double {
        let w = min(image.width, 96)
        let h = min(image.height, 96)
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        data.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var opaque = 0
        for i in stride(from: 3, to: data.count, by: 4) where data[i] > 32 {
            opaque += 1
        }
        return Double(opaque) / Double(w * h)
    }

    private func writeArtifact(_ image: CGImage, name: String) {
        let url = Self.artifactDir.appendingPathComponent(name)
        try? ImageExportWriter.write(image, to: url, format: .png)
        log("artifact \(url.lastPathComponent) \(image.width)x\(image.height)")
    }

    // MARK: - Geometry cutouts

    func testCutoutExportWithRotationFlipCrop() async throws {
        let source = fixtureURL("person-portrait-studio.jpg")
        let provider = VisionPersonSelectionProvider()
        let image = try loadCIImage("person-portrait-studio.jpg")
        let mask = try await provider.selectClass(in: image, class: .person, quality: .accurate)

        let cases: [(String, Int, Bool, Bool, CGRect?)] = [
            ("identity", 0, false, false, nil),
            ("rot90", 1, false, false, nil),
            ("rot180", 2, false, false, nil),
            ("flipH", 0, true, false, nil),
            ("flipV", 0, false, true, nil),
            ("rot90flipH", 1, true, false, nil),
            ("cropCenter", 0, false, false, CGRect(x: 0.15, y: 0.1, width: 0.7, height: 0.8))
        ]

        for (label, turns, flipH, flipV, crop) in cases {
            let t0 = CFAbsoluteTimeGetCurrent()
            guard let cg = ImageExportWriter.renderCutoutCGImage(
                sourceURL: source,
                parameters: .identity,
                selectionMask: mask,
                quarterTurns: turns,
                cropNormalized: crop,
                straightenRadians: 0,
                flipHorizontal: flipH,
                flipVertical: flipV
            ) else {
                XCTFail("Cutout nil for \(label)")
                continue
            }
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            let alpha = alphaCoverage(cg)
            log(String(format: "cutout.%@ %.1fms alphaCoverage=%.3f size=%dx%d",
                       label, ms, alpha, cg.width, cg.height))
            XCTAssertGreaterThan(cg.width, 8)
            XCTAssertGreaterThan(cg.height, 8)
            XCTAssertGreaterThan(alpha, 0.05, "\(label) should keep subject alpha")
            XCTAssertLessThan(alpha, 0.98, "\(label) should keep some transparency")
            writeArtifact(cg, name: "cutout-\(label).png")
        }
    }

    func testCutoutExportWithStraightenAndDevelop() async throws {
        let source = fixtureURL("person-fullbody-street.jpg")
        let provider = VisionPersonSelectionProvider()
        let image = try loadCIImage("person-fullbody-street.jpg")
        let mask = try await provider.selectClass(in: image, class: .person, quality: .accurate)

        var params = ImageAdjustParameters.identity
        params.exposure = 0.35
        params.contrast = 1.25
        params.saturation = 1.15
        params.vignette = 0.4

        let t0 = CFAbsoluteTimeGetCurrent()
        guard let cg = ImageExportWriter.renderCutoutCGImage(
            sourceURL: source,
            parameters: params,
            selectionMask: mask,
            quarterTurns: 1,
            cropNormalized: CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.9),
            straightenRadians: 0.08,
            flipHorizontal: true,
            flipVertical: false
        ) else {
            return XCTFail("Develop+geometry cutout failed")
        }
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        let alpha = alphaCoverage(cg)
        log(String(format: "cutout.developGeom %.1fms alpha=%.3f %dx%d", ms, alpha, cg.width, cg.height))
        XCTAssertGreaterThan(alpha, 0.03)
        XCTAssertLessThan(alpha, 0.95)
        writeArtifact(cg, name: "cutout-develop-geom.png")
    }

    // MARK: - Preview vs accurate consistency

    func testPreviewAccurateCoverageCloseOnPortrait() async throws {
        let provider = VisionPersonSelectionProvider()
        let image = try loadCIImage("person-portrait-2k.jpg")
        let preview = try await provider.selectClass(in: image, class: .person, quality: .preview)
        let accurate = try await provider.selectClass(in: image, class: .person, quality: .accurate)
        let cp = matteCoverage(preview)
        let ca = matteCoverage(accurate)
        let delta = abs(cp - ca)
        log(String(format: "coverage preview=%.3f accurate=%.3f delta=%.3f", cp, ca, delta))
        XCTAssertLessThan(delta, 0.12, "Preview/accurate coverage diverged too far")
        XCTAssertLessThanOrEqual(
            max(preview.extent.width, preview.extent.height),
            VisionPersonSelectionProvider.previewMaxEdge + 1
        )
        XCTAssertGreaterThan(
            max(accurate.extent.width, accurate.extent.height),
            VisionPersonSelectionProvider.previewMaxEdge
        )
    }

    // MARK: - Compositor modes

    func testCompositorNoneIsIdentity() throws {
        let image = try loadCIImage("person-portrait-studio.jpg")
        let cg = makeGrayMatte(width: Int(image.extent.width), height: Int(image.extent.height), fill: 200)
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
            mode: .none,
            appearance: NSAppearance(named: .darkAqua)!
        )
        XCTAssertEqual(out.extent.integral, image.extent.integral)
    }

    // MARK: - Session cache & thrash

    func testSessionQualitySwitchReRunsAccurate() async throws {
        let session = ImageSelectionSession(provider: VisionPersonSelectionProvider())
        let image = try loadCIImage("person-portrait-studio.jpg")
        session.setSourceToken("quality-switch")

        let gotAccurate = expectation(description: "accurate")
        gotAccurate.assertForOverFulfill = false
        session.onChange = { q in
            if q == .accurate, session.hasSelection { gotAccurate.fulfill() }
        }
        session.selectPerson(in: image)
        await fulfillment(of: [gotAccurate], timeout: 8)

        // Force preview then accurate again via UI quality control path.
        session.setQuality(.preview)
        let backToAccurate = expectation(description: "back-accurate")
        backToAccurate.assertForOverFulfill = false
        session.onChange = { q in
            if q == .accurate, session.hasSelection { backToAccurate.fulfill() }
        }
        session.setQuality(.accurate)
        await fulfillment(of: [backToAccurate], timeout: 8)
        XCTAssertEqual(session.currentQuality, .accurate)
        XCTAssertTrue(session.hasSelection)
    }

    func testSessionTokenThrashDoesNotLeaveStaleMask() async throws {
        let session = ImageSelectionSession(provider: VisionPersonSelectionProvider())
        let a = try loadCIImage("person-portrait-studio.jpg")
        let b = try loadCIImage("person-fullbody-street.jpg")
        let blank = try loadCIImage("negative-blank.jpg")

        for i in 0..<12 {
            let token = "thrash-\(i)"
            session.setSourceToken(token)
            let image = [a, b, blank][i % 3]
            session.selectPerson(in: image)
            if i % 4 == 3 {
                session.clearSelection()
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        session.setSourceToken("thrash-final")
        // Drain
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(session.hasSelection)
        XCTAssertFalse(session.isSelecting)
        log("thrash complete")
    }

    func testSessionResetAllRestoresDefaults() async throws {
        let session = ImageSelectionSession(provider: VisionPersonSelectionProvider())
        let image = try loadCIImage("person-portrait-studio.jpg")
        session.setSourceToken("reset")
        session.selectPerson(in: image)
        let expect = expectation(description: "mask")
        expect.assertForOverFulfill = false
        session.onChange = { _ in if session.hasSelection { expect.fulfill() } }
        await fulfillment(of: [expect], timeout: 5)
        session.setDisplayMode(.onLayers)
        session.setQuality(.accurate)
        session.resetAll()
        XCTAssertFalse(session.hasSelection)
        XCTAssertEqual(session.currentDisplayMode, .marchingAnts)
        XCTAssertEqual(session.currentQuality, .accurate)
    }

    // MARK: - Parallel providers

    func testParallelProvidersOnSamePortrait() async throws {
        let image = try loadCIImage("person-portrait-studio.jpg")
        let providers = (0..<4).map { _ in VisionPersonSelectionProvider() }
        let start = CFAbsoluteTimeGetCurrent()
        var coverages: [Double] = []
        await withTaskGroup(of: Double.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let mask = try await provider.selectClass(in: image, class: .person, quality: .preview)
                        return self.matteCoverage(mask)
                    } catch {
                        return -1
                    }
                }
            }
            for await c in group { coverages.append(c) }
        }
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        log(String(format: "parallelProviders coverages=%@ wall=%.1fms", String(describing: coverages), ms))
        XCTAssertEqual(coverages.count, 4)
        for c in coverages {
            XCTAssertGreaterThan(c, 0.2)
        }
        let spread = (coverages.max() ?? 0) - (coverages.min() ?? 0)
        XCTAssertLessThan(spread, 0.05, "Parallel providers should agree on coverage")
    }

    // MARK: - Region hit at densest must succeed

    func testRegionHitAtSubjectCenter() async throws {
        let provider = VisionPersonSelectionProvider()
        let image = try loadCIImage("person-portrait-studio.jpg")
        let mask = try await provider.selectClass(in: image, class: .person, quality: .preview)
        // Portrait subject is near center.
        let hit = CGPoint(x: image.extent.midX, y: image.extent.midY * 0.65)
        let again = try await provider.selectRegion(in: image, at: hit, quality: .preview)
        XCTAssertEqual(again.semanticClass, .person)
        XCTAssertGreaterThan(matteCoverage(again), 0.2)
        _ = mask
    }

    // MARK: - Batch fixture matrix

    func testDocumentFalsePositivesRejected() async throws {
        let provider = VisionPersonSelectionProvider()
        // Screen text / printed exam — Vision can emit speckles or soft ghosts.
        for name in ["preview-a.jpeg", "preview-b.jpeg", "large-a.jpeg", "large-b.jpeg"] {
            let image = try loadCIImage(name)
            do {
                let mask = try await provider.selectClass(in: image, class: .person, quality: .preview)
                XCTFail("Expected emptyResult for document fixture \(name), got coverage \(matteCoverage(mask))")
            } catch let error as SelectionError {
                XCTAssertEqual(error, .emptyResult, "\(name)")
            }
        }
    }

    func testFixtureMatrixLogsOutcomes() async throws {
        let provider = VisionPersonSelectionProvider()
        let names = [
            "person-portrait-studio.jpg",
            "person-fullbody-street.jpg",
            "person-portrait-2k.jpg",
            "large-a.jpeg",
            "large-b.jpeg",
            "preview-b.jpeg",
            "preview-c.jpeg",
            "luminar-c.jpg",
            "stress-4k.jpg",
            "negative-blank.jpg",
            "synthetic-silhouette.jpg"
        ]
        for name in names {
            let image = try loadCIImage(name)
            let t0 = CFAbsoluteTimeGetCurrent()
            do {
                let mask = try await provider.selectClass(in: image, class: .person, quality: .preview)
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                log(String(format: "matrix.%@ HIT cov=%.3f %.1fms %dx%d",
                           name, matteCoverage(mask), ms,
                           Int(mask.extent.width), Int(mask.extent.height)))
            } catch let error as SelectionError {
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                log(String(format: "matrix.%@ MISS %@ %.1fms", name, String(describing: error), ms))
            } catch {
                XCTFail("Unexpected \(error) on \(name)")
            }
        }
    }

    private func makeGrayMatte(width: Int, height: Int, fill: UInt8) -> CGImage {
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
