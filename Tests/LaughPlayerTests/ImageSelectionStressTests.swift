import AppKit
import CoreImage
import XCTest
@testable import LaughPlayer

/// Hard / stress coverage for the smart-selection stack: real fixtures, timing budgets,
/// cancellation, concurrency, compositor, and cutout export.
final class ImageSelectionStressTests: XCTestCase {
    private static let logPrefix = "[SEL-PERF]"

    // MARK: - Fixtures

    private static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Selection", isDirectory: true)
    }

    private func fixtureURL(_ name: String) -> URL {
        Self.fixturesDir.appendingPathComponent(name)
    }

    private func loadCIImage(_ name: String) throws -> CIImage {
        let url = fixtureURL(name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture \(name) at \(url.path)")
        guard let ns = NSImage(contentsOf: url),
              let tiff = ns.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage
        else {
            throw SelectionError.invalidImage
        }
        return CIImage(cgImage: cg)
    }

    private func log(_ message: String) {
        print("\(Self.logPrefix) \(message)")
    }

    private func timed<T>(
        _ label: String,
        budgetMs: Double? = nil,
        softBudget: Bool = true,
        body: () async throws -> T
    ) async rethrows -> (T, Double) {
        let start = CFAbsoluteTimeGetCurrent()
        let value = try await body()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if let budgetMs {
            let verdict = ms <= budgetMs ? "OK" : (softBudget ? "SOFT-MISS" : "HARD-MISS")
            log(String(format: "%@ %.1fms (budget %.0fms) [%@]", label, ms, budgetMs, verdict))
            if !softBudget {
                XCTAssertLessThanOrEqual(ms, budgetMs, "\(label) exceeded hard budget")
            }
        } else {
            log(String(format: "%@ %.1fms", label, ms))
        }
        return (value, ms)
    }

    // MARK: - Protocol / class matrix

    func testAllNonPersonClassesThrow() async {
        let provider = VisionPersonSelectionProvider()
        let image = try! loadCIImage("person-portrait-studio.jpg")
        for cls in SemanticClass.allCases where cls != .person {
            do {
                _ = try await provider.selectClass(in: image, class: cls, quality: .preview)
                XCTFail("Expected unsupportedClass for \(cls)")
            } catch let error as SelectionError {
                XCTAssertEqual(error, .unsupportedClass(cls))
            } catch {
                XCTFail("Wrong error for \(cls): \(error)")
            }
        }
    }

    // MARK: - Positive person path

    func testPersonPortraitPreviewAndAccurate() async throws {
        let provider = VisionPersonSelectionProvider()
        let image = try loadCIImage("person-portrait-studio.jpg")

        // Warm-up (model compile / first Vision hit) — excluded from budget.
        _ = try? await provider.selectClass(in: image, class: .person, quality: .preview)

        let (preview, previewMs) = try await timed("portrait.preview", budgetMs: 250) {
            try await provider.selectClass(in: image, class: .person, quality: .preview)
        }
        XCTAssertEqual(preview.semanticClass, .person)
        XCTAssertEqual(preview.source, .visionPerson)
        XCTAssertGreaterThan(preview.cgImage.width, 8)
        XCTAssertGreaterThan(matteCoverage(preview), 0.02, "Expected meaningful person coverage")

        let (accurate, accurateMs) = try await timed("portrait.accurate", budgetMs: 800) {
            try await provider.selectClass(in: image, class: .person, quality: .accurate)
        }
        XCTAssertEqual(accurate.semanticClass, .person)
        XCTAssertGreaterThan(matteCoverage(accurate), 0.02)
        log(String(format: "portrait.ratio accurate/preview=%.2fx coverage preview=%.3f accurate=%.3f",
                   accurateMs / max(previewMs, 1),
                   matteCoverage(preview),
                   matteCoverage(accurate)))
    }

    func testPointMissIgnoresOpaqueBlackAlpha() async throws {
        // Regression: empty matte pixels are often (0,0,0,255). Sampling must ignore alpha.
        let provider = VisionPersonSelectionProvider()
        let image = try loadCIImage("person-fullbody-street.jpg")
        let mask = try await provider.selectClass(in: image, class: .person, quality: .preview)
        XCTAssertLessThan(matteCoverage(mask), 0.5, "Fixture should leave empty background")

        do {
            _ = try await provider.selectRegion(
                in: image,
                at: CGPoint(x: image.extent.minX + 4, y: image.extent.maxY - 4),
                quality: .preview
            )
            // If Vision matte bleeds into this corner, try the opposite corner.
            _ = try await provider.selectRegion(
                in: image,
                at: CGPoint(x: image.extent.maxX - 4, y: image.extent.minY + 4),
                quality: .preview
            )
            XCTFail("Expected at least one background corner to pointMiss")
        } catch let error as SelectionError {
            XCTAssertEqual(error, .pointMiss)
        }
    }

    func testPersonFullBodyAndPointHitMiss() async throws {
        let provider = VisionPersonSelectionProvider()
        let image = try loadCIImage("person-fullbody-street.jpg")
        let mask = try await provider.selectClass(in: image, class: .person, quality: .preview)
        XCTAssertGreaterThan(matteCoverage(mask), 0.01)

        // Sample densest region of the matte for a hit.
        let hit = densestPoint(in: mask, imageExtent: image.extent) ?? CGPoint(x: image.extent.midX, y: image.extent.midY)
        let hitMask = try await provider.selectRegion(in: image, at: hit, quality: .preview)
        XCTAssertEqual(hitMask.semanticClass, .person)

        // Prefer an empty matte cell for miss; fall back to corner.
        let miss = emptiestPoint(in: mask, imageExtent: image.extent)
            ?? CGPoint(x: image.extent.minX + 2, y: image.extent.minY + 2)
        do {
            _ = try await provider.selectRegion(in: image, at: miss, quality: .preview)
            XCTFail("Expected pointMiss at empty matte sample \(miss)")
        } catch let error as SelectionError {
            XCTAssertEqual(error, .pointMiss)
        }
    }

    func testPerson2KPreviewCapsWorkingExtent() async throws {
        let provider = VisionPersonSelectionProvider()
        let image = try loadCIImage("person-portrait-2k.jpg")
        XCTAssertGreaterThan(max(image.extent.width, image.extent.height), VisionPersonSelectionProvider.previewMaxEdge)

        let (mask, _) = try await timed("portrait2k.preview", budgetMs: 400) {
            try await provider.selectClass(in: image, class: .person, quality: .preview)
        }
        let longest = max(mask.extent.width, mask.extent.height)
        XCTAssertLessThanOrEqual(longest, VisionPersonSelectionProvider.previewMaxEdge + 1)
        XCTAssertGreaterThan(matteCoverage(mask), 0.02)
    }

    // MARK: - Negatives (must not invent people)

    func testNegativesDoNotInventPeople() async throws {
        let provider = VisionPersonSelectionProvider()
        let names = [
            "negative-blank.jpg",
            "negative-gradient.jpg",
            "synthetic-silhouette.jpg",
            "preview-a.jpeg", // document photo of a screen
            "preview-b.jpeg", // ebook text
            "large-a.jpeg",   // printed exam photo
            "luminar-a.jpg",  // film-noise abstract
            "stress-4k.jpg"   // landscape panorama
        ]
        for name in names {
            let image = try loadCIImage(name)
            let (result, ms): (Result<SelectionMask, Error>, Double) = await timed("negative.\(name)") {
                do {
                    return .success(try await provider.selectClass(in: image, class: .person, quality: .preview))
                } catch {
                    return .failure(error)
                }
            }
            switch result {
            case .success(let mask):
                XCTFail("False-positive person matte on \(name) coverage=\(matteCoverage(mask)) ms=\(ms)")
            case .failure(let error as SelectionError):
                XCTAssertTrue(
                    error == .emptyResult || error == .invalidImage,
                    "Unexpected SelectionError on \(name): \(error)"
                )
            case .failure(let error):
                XCTFail("Unexpected error on \(name): \(error)")
            }
        }
    }

    // MARK: - Compositor + export

    func testOverlayAndCutoutDifferAndCutoutHasAlpha() async throws {
        let provider = VisionPersonSelectionProvider()
        let image = try loadCIImage("person-portrait-studio.jpg")
        let mask = try await provider.selectClass(in: image, class: .person, quality: .preview)
        let appearance = NSAppearance(named: .darkAqua)!

        let overlay = SelectionCompositor.apply(image: image, mask: mask, mode: .overlay, appearance: appearance)
        let cutout = SelectionCompositor.apply(image: image, mask: mask, mode: .onLayers, appearance: appearance)
        let alpha = SelectionCompositor.cutoutWithAlpha(image: image, mask: mask)

        XCTAssertEqual(overlay.extent.integral, image.extent.integral)
        XCTAssertEqual(cutout.extent.integral, image.extent.integral)
        XCTAssertEqual(alpha.extent.integral, image.extent.integral)

        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let overlayCG = ctx.createCGImage(overlay, from: overlay.extent.integral),
              let cutoutCG = ctx.createCGImage(cutout, from: cutout.extent.integral),
              let alphaCG = ctx.createCGImage(alpha, from: alpha.extent.integral, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB(), deferred: false)
        else {
            return XCTFail("Failed to render compositor outputs")
        }
        XCTAssertNotEqual(fingerprint(overlayCG), fingerprint(cutoutCG), "Overlay and cutout should differ")
        XCTAssertTrue(hasTransparentPixels(alphaCG), "Alpha cutout should contain transparency")
    }

    func testExportCutoutPNGRoundTrip() async throws {
        let image = try loadCIImage("person-portrait-studio.jpg")
        let provider = VisionPersonSelectionProvider()
        let mask = try await provider.selectClass(in: image, class: .person, quality: .accurate)

        let sourceURL = fixtureURL("person-portrait-studio.jpg")
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-cutout-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: dest) }

        let (cg, ms) = try await timed("export.cutout", budgetMs: 1500) {
            guard let rendered = ImageExportWriter.renderCutoutCGImage(
                sourceURL: sourceURL,
                parameters: .identity,
                selectionMask: mask,
                quarterTurns: 0
            ) else {
                throw SelectionError.emptyResult
            }
            try ImageExportWriter.write(rendered, to: dest, format: .png)
            return rendered
        }
        _ = ms
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertGreaterThan(cg.width, 8)
        XCTAssertTrue(hasTransparentPixels(cg))
    }

    // MARK: - Session stress

    func testSessionRapidSelectClearAndTokenSwitch() async {
        let provider = DelayedSelectionProvider(delayMs: 80, backing: VisionPersonSelectionProvider())
        let session = ImageSelectionSession(provider: provider)
        let image = try! loadCIImage("person-portrait-studio.jpg")

        var changeCount = 0
        session.onChange = { _ in changeCount += 1 }

        session.setSourceToken("img-a")
        session.selectPerson(in: image)
        session.selectPerson(in: image) // supersede
        session.setSourceToken("img-b") // cancel in-flight

        // Allow delayed work to finish.
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline && session.isSelecting {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(session.hasSelection, "Token switch must clear selection")
        XCTAssertNil(session.error)
        log("session.tokenSwitch changeEvents=\(changeCount)")
    }

    func testSessionSettlesToAccurate() async throws {
        let session = ImageSelectionSession(provider: VisionPersonSelectionProvider())
        let image = try loadCIImage("person-portrait-studio.jpg")
        session.setSourceToken("settle-test")

        let expectAccurate = expectation(description: "accurate settle")
        expectAccurate.assertForOverFulfill = false
        session.onChange = { quality in
            if quality == .accurate, session.hasSelection {
                expectAccurate.fulfill()
            }
        }
        session.selectPerson(in: image)
        await fulfillment(of: [expectAccurate], timeout: 5)
        XCTAssertEqual(session.currentQuality, .accurate)
        XCTAssertTrue(session.hasSelection)
    }

    func testSessionDisplayModeToggleDoesNotDropMask() async throws {
        let session = ImageSelectionSession(provider: VisionPersonSelectionProvider())
        let image = try loadCIImage("person-fullbody-street.jpg")
        session.setSourceToken("display-mode")
        session.selectPerson(in: image)

        let expectMask = expectation(description: "mask")
        expectMask.assertForOverFulfill = false
        session.onChange = { _ in
            if session.hasSelection { expectMask.fulfill() }
        }
        await fulfillment(of: [expectMask], timeout: 5)
        session.setDisplayMode(.onLayers)
        XCTAssertTrue(session.hasSelection)
        XCTAssertEqual(session.currentDisplayMode, .onLayers)
        session.setDisplayMode(.overlay)
        XCTAssertEqual(session.currentDisplayMode, .overlay)
    }

    // MARK: - Concurrency / soak

    func testConcurrentSelectsAcrossFixtures() async throws {
        let provider = VisionPersonSelectionProvider()
        let names = [
            "person-portrait-studio.jpg",
            "person-fullbody-street.jpg",
            "person-portrait-2k.jpg",
            "negative-blank.jpg",
            "stress-4k.jpg",
            "luminar-b.jpg"
        ]
        let images = try names.map { try loadCIImage($0) }

        let start = CFAbsoluteTimeGetCurrent()
        await withTaskGroup(of: (String, Result<SelectionMask, Error>, Double).self) { group in
            for (name, image) in zip(names, images) {
                group.addTask {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    let result: Result<SelectionMask, Error>
                    do {
                        result = .success(try await provider.selectClass(in: image, class: .person, quality: .preview))
                    } catch {
                        result = .failure(error)
                    }
                    return (name, result, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
                }
            }
            for await (name, result, ms) in group {
                switch result {
                case .success(let mask):
                    log(String(format: "concurrent.%@ OK coverage=%.3f %.1fms", name, matteCoverage(mask), ms))
                case .failure(let error):
                    log(String(format: "concurrent.%@ ERR %@ %.1fms", name, String(describing: error), ms))
                }
            }
        }
        log(String(format: "concurrent.totalWall %.1fms", (CFAbsoluteTimeGetCurrent() - start) * 1000))
    }

    func testSequentialSoakTenPassesOnPortrait() async throws {
        let provider = VisionPersonSelectionProvider()
        let image = try loadCIImage("person-portrait-studio.jpg")
        var times: [Double] = []
        for i in 0..<10 {
            let (_, ms) = try await timed("soak.\(i)") {
                try await provider.selectClass(in: image, class: .person, quality: .preview)
            }
            times.append(ms)
        }
        let avg = times.reduce(0, +) / Double(times.count)
        let maxMs = times.max() ?? 0
        let minMs = times.min() ?? 0
        log(String(format: "soak.summary n=10 avg=%.1fms min=%.1fms max=%.1fms", avg, minMs, maxMs))
        // Soft budget after warm-up: median-ish via avg.
        XCTAssertLessThan(avg, 400, "Average preview soak too slow")
    }

    // MARK: - Helpers

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

    private func densestPoint(in mask: SelectionMask, imageExtent: CGRect) -> CGPoint? {
        let matched = mask.ciImageMatching(extent: imageExtent)
        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let cg = ctx.createCGImage(matched, from: imageExtent.integral) else { return nil }
        let w = cg.width
        let h = cg.height
        let block = 16
        var best = 0
        var bestRect = CGRect.zero
        guard let gray = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        gray.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = gray.data else { return nil }
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h)
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                var sum = 0
                let yMax = min(y + block, h)
                let xMax = min(x + block, w)
                for yy in y..<yMax {
                    for xx in x..<xMax {
                        sum += Int(buf[yy * w + xx])
                    }
                }
                if sum > best {
                    best = sum
                    bestRect = CGRect(x: x, y: y, width: xMax - x, height: yMax - y)
                }
                x += block
            }
            y += block
        }
        guard best > 0 else { return nil }
        // CGImage is top-left; CIImage extent is bottom-left — convert.
        let cx = bestRect.midX
        let cy = CGFloat(h) - bestRect.midY
        return CGPoint(x: imageExtent.minX + cx, y: imageExtent.minY + cy)
    }

    private func emptiestPoint(in mask: SelectionMask, imageExtent: CGRect) -> CGPoint? {
        let matched = mask.ciImageMatching(extent: imageExtent)
        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let cg = ctx.createCGImage(matched, from: imageExtent.integral) else { return nil }
        let w = cg.width
        let h = cg.height
        let block = 16
        var best = Int.max
        var bestRect = CGRect.zero
        guard let gray = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        gray.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = gray.data else { return nil }
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h)
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                var sum = 0
                let yMax = min(y + block, h)
                let xMax = min(x + block, w)
                for yy in y..<yMax {
                    for xx in x..<xMax {
                        sum += Int(buf[yy * w + xx])
                    }
                }
                if sum < best {
                    best = sum
                    bestRect = CGRect(x: x, y: y, width: xMax - x, height: yMax - y)
                }
                x += block
            }
            y += block
        }
        guard best < 32 * block * block else { return nil }
        let cx = bestRect.midX
        let cy = CGFloat(h) - bestRect.midY
        return CGPoint(x: imageExtent.minX + cx, y: imageExtent.minY + cy)
    }

    private func fingerprint(_ image: CGImage) -> UInt64 {
        let w = min(image.width, 32)
        let h = min(image.height, 32)
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
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var hash: UInt64 = 0xcbf29ce484222325
        for b in data {
            hash ^= UInt64(b)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    private func hasTransparentPixels(_ image: CGImage) -> Bool {
        let w = min(image.width, 64)
        let h = min(image.height, 64)
        var data = [UInt8](repeating: 255, count: w * h * 4)
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
        for i in stride(from: 3, to: data.count, by: 4) where data[i] < 250 {
            return true
        }
        return false
    }
}

// MARK: - Delayed provider (cancellation stress)

private final class DelayedSelectionProvider: SelectionProvider, @unchecked Sendable {
    let providerID = "test.delayed"
    private let delayMs: UInt64
    private let backing: SelectionProvider

    init(delayMs: UInt64, backing: SelectionProvider) {
        self.delayMs = delayMs
        self.backing = backing
    }

    func selectRegion(in image: CIImage, at point: CGPoint, quality: SelectionQuality) async throws -> SelectionMask {
        try await Task.sleep(nanoseconds: delayMs * 1_000_000)
        return try await backing.selectRegion(in: image, at: point, quality: quality)
    }

    func selectClass(in image: CIImage, class semanticClass: SemanticClass, quality: SelectionQuality) async throws -> SelectionMask {
        try await Task.sleep(nanoseconds: delayMs * 1_000_000)
        return try await backing.selectClass(in: image, class: semanticClass, quality: quality)
    }

    func select(in image: CIImage, prompt: SelectionPrompt, quality: SelectionQuality) async throws -> SelectionMask {
        try await Task.sleep(nanoseconds: delayMs * 1_000_000)
        return try await backing.select(in: image, prompt: prompt, quality: quality)
    }
}
