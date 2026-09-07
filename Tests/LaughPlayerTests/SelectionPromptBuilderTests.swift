import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import LaughPlayer

final class SelectionPromptBuilderTests: XCTestCase {
    func testSamplesInteriorPositivesAndExteriorNegatives() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let mask = try makeRectMask(
            on: CGRect(x: 16, y: 16, width: 32, height: 32),
            extent: extent
        )
        let prompt = SelectionPromptBuilder.fromRoughMask(
            mask,
            imageExtent: extent,
            positiveCount: 3,
            negativeCount: 2
        )
        XCTAssertFalse(prompt.positivePoints.isEmpty)
        XCTAssertNotNil(prompt.box)
        for p in prompt.positivePoints {
            XCTAssertTrue(prompt.box!.contains(p) || prompt.box!.insetBy(dx: -2, dy: -2).contains(p))
        }
        XCTAssertFalse(prompt.negativePoints.isEmpty)
        for n in prompt.negativePoints {
            XCTAssertFalse(CGRect(x: 16, y: 16, width: 32, height: 32).insetBy(dx: 4, dy: 4).contains(n))
        }
    }

    /// A person is a solid body with thin structures hanging off it — hair, arms, a strand
    /// against a dark background. Positives sampled in those thin parts make SAM return an
    /// edge-ish region and drop the body: measured 47% of a real subject's interior lost.
    /// Positives must land in the deep core.
    func testPositivesAvoidThinStructuresAndLandInTheBody() throws {
        let extent = CGRect(x: 0, y: 0, width: 240, height: 240)
        let body = CGRect(x: 80, y: 20, width: 90, height: 90)
        // Tall thin "hair" column on top of the body, wide enough to pass a small
        // neighbourhood test but nowhere near deep enough to prompt from.
        let hair = CGRect(x: 100, y: 110, width: 26, height: 110)
        let mask = try makeMask(on: [body, hair], extent: extent)

        let prompt = SelectionPromptBuilder.fromRoughMask(mask, imageExtent: extent, positiveCount: 4)
        XCTAssertFalse(prompt.positivePoints.isEmpty)
        // Prompt space is top-left origin, so flip the CI-space rects to compare.
        let bodyTopLeft = CGRect(x: body.minX, y: extent.height - body.maxY, width: body.width, height: body.height)
        for point in prompt.positivePoints {
            XCTAssertTrue(
                bodyTopLeft.insetBy(dx: -1, dy: -1).contains(point),
                "positive \(point) should sit in the body, not the thin structure"
            )
        }
    }

    func testEmptyMaskFallsBackToCenterPoint() throws {
        let extent = CGRect(x: 0, y: 0, width: 40, height: 40)
        let blank = CIImage(color: .black).cropped(to: extent)
        let cg = try renderGray(blank, extent: extent)
        let mask = SelectionMask(
            cgImage: cg,
            extent: extent,
            confidence: 0,
            semanticClass: .unknown,
            source: .visionPerson
        )
        let prompt = SelectionPromptBuilder.fromRoughMask(mask, imageExtent: extent)
        XCTAssertEqual(prompt.positivePoints.count, 1)
        XCTAssertEqual(prompt.positivePoints[0].x, extent.midX, accuracy: 0.5)
        XCTAssertEqual(prompt.positivePoints[0].y, extent.midY, accuracy: 0.5)
    }

    private func makeRectMask(on rect: CGRect, extent: CGRect) throws -> SelectionMask {
        try makeMask(on: [rect], extent: extent)
    }

    private func makeMask(on rects: [CGRect], extent: CGRect) throws -> SelectionMask {
        var composed = CIImage(color: .black).cropped(to: extent)
        for rect in rects {
            composed = CIImage(color: .white).cropped(to: rect).composited(over: composed)
        }
        composed = composed.cropped(to: extent)
        let cg = try renderGray(composed, extent: extent)
        return SelectionMask(
            cgImage: cg,
            extent: extent,
            confidence: 1,
            semanticClass: .person,
            source: .visionPerson
        )
    }

    private func renderGray(_ image: CIImage, extent: CGRect) throws -> CGImage {
        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let cg = ctx.createCGImage(image, from: extent) else {
            throw NSError(domain: "test", code: 1)
        }
        return cg
    }
}

final class ImageSelectionSessionFallbackTests: XCTestCase {
    func testCancelDownloadUsesVisionFallback() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-session-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let vision = StubVisionProvider()
        let store = SelectionModelStore(
            root: root,
            downloader: SlowDownloader(),
            unzipHandler: { _, _ in }
        )
        let session = ImageSelectionSession(
            visionProvider: vision,
            modelStore: store,
            samProvider: MobileSAMSelectionProvider(store: store)
        )

        let image = CIImage(color: .cyan).cropped(to: CGRect(x: 0, y: 0, width: 48, height: 48))
        let selectTask = Task {
            session.selectPerson(in: image)
        }
        // Allow download to start, then cancel.
        try await Task.sleep(nanoseconds: 50_000_000)
        session.cancelModelDownload()
        // Wait for completion.
        for _ in 0..<40 {
            if !session.isSelecting { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        _ = selectTask
        XCTAssertFalse(session.isSelecting)
        XCTAssertTrue(session.didUseVisionFallback || session.hasSelection)
        if session.hasSelection {
            XCTAssertEqual(session.currentMask?.source, .visionPerson)
            XCTAssertTrue(session.didUseVisionFallback)
        }
    }
}

private final class StubVisionProvider: SelectionProvider, @unchecked Sendable {
    let providerID = "test.vision"
    private let ci = CIContext()

    func selectRegion(in image: CIImage, at point: CGPoint, quality: SelectionQuality) async throws -> SelectionMask {
        try await selectClass(in: image, class: .person, quality: quality)
    }

    func selectClass(in image: CIImage, class semanticClass: SemanticClass, quality: SelectionQuality) async throws -> SelectionMask {
        _ = semanticClass
        _ = quality
        let extent = image.extent.integral
        let white = CIImage(color: .white).cropped(to: extent.insetBy(dx: extent.width * 0.25, dy: extent.height * 0.25))
        let black = CIImage(color: .black).cropped(to: extent)
        let composed = white.composited(over: black).cropped(to: extent)
        guard let cg = ci.createCGImage(composed, from: extent) else { throw SelectionError.emptyResult }
        return SelectionMask(
            cgImage: cg,
            extent: extent,
            confidence: 0.9,
            semanticClass: .person,
            source: .visionPerson
        )
    }

    func select(in image: CIImage, prompt: SelectionPrompt, quality: SelectionQuality) async throws -> SelectionMask {
        if let p = prompt.positivePoints.first {
            return try await selectRegion(in: image, at: p, quality: quality)
        }
        return try await selectClass(in: image, class: .person, quality: quality)
    }
}

private final class SlowDownloader: SelectionModelDownloading, @unchecked Sendable {
    func download(
        from remote: URL,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)?,
        isCancelled: @Sendable () -> Bool
    ) async throws {
        for i in 0..<20 {
            if isCancelled() { throw SelectionModelStoreError.cancelled }
            progress?(Double(i) / 20)
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        if isCancelled() { throw SelectionModelStoreError.cancelled }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([1]).write(to: destination)
        progress?(1)
    }
}
