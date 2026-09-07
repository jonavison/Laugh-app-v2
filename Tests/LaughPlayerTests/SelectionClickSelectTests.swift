import CoreImage
import XCTest
@testable import LaughPlayer

final class SelectionClickSelectTests: XCTestCase {
    func testClickSelectAccumulatesAdditivePoints() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-click-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = RecordingSAMProvider()
        let store = SelectionModelStore(root: root, downloader: NoopDownloader())
        // Seed ready artifacts so session takes SAM path without download.
        try seedReady(store: store, root: root)

        let session = ImageSelectionSession(
            visionProvider: StubVisionProvider(),
            modelStore: store,
            samProvider: recorder,
            allowsModelDownload: false,
            forceVisionOnly: false
        )
        let image = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))

        session.clickSelect(in: image, at: CGPoint(x: 10, y: 10), negative: false, additive: false)
        await waitUntilIdle(session)
        XCTAssertEqual(recorder.lastPrompt?.positivePoints.count, 1)

        session.clickSelect(in: image, at: CGPoint(x: 40, y: 40), negative: true, additive: true)
        await waitUntilIdle(session)
        XCTAssertEqual(recorder.lastPrompt?.positivePoints.count, 1)
        XCTAssertEqual(recorder.lastPrompt?.negativePoints.count, 1)

        session.boxSelect(in: image, box: CGRect(x: 5, y: 5, width: 30, height: 20), additive: false)
        await waitUntilIdle(session)
        XCTAssertNotNil(recorder.lastPrompt?.box)
        XCTAssertEqual(recorder.lastPrompt?.positivePoints.count, 0)
    }

    func testClickSelectModelNotReadyWithoutDownload() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-click-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = ImageSelectionSession(
            visionProvider: StubVisionProvider(),
            modelStore: SelectionModelStore(root: root, downloader: NoopDownloader()),
            samProvider: RecordingSAMProvider(),
            allowsModelDownload: false,
            forceVisionOnly: false
        )
        let image = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))
        session.clickSelect(in: image, at: CGPoint(x: 8, y: 8), negative: false, additive: false)
        await waitUntilIdle(session)
        XCTAssertEqual(session.error, .modelNotReady)
        XCTAssertFalse(session.hasSelection)
    }

    private func waitUntilIdle(_ session: ImageSelectionSession) async {
        // Let the session Task hop onto MainActor and flip `isSelecting`.
        try? await Task.sleep(nanoseconds: 50_000_000)
        for _ in 0..<80 {
            if !session.isSelecting { return }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private func seedReady(store: SelectionModelStore, root: URL) throws {
        let artifact = SelectionModelArtifact.mobileSAM
        let dir = store.cacheDirectory(for: artifact)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in artifact.readyRelativePaths {
            let url = dir.appendingPathComponent(name)
            if name.hasSuffix(".json") {
                try Data("{}".utf8).write(to: url)
            } else {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data([1]).write(to: url.appendingPathComponent("model.mil"))
            }
        }
        _ = root
    }
}

private final class RecordingSAMProvider: SelectionProvider, @unchecked Sendable {
    let providerID = "test.sam"
    private(set) var lastPrompt: SelectionPrompt?
    private let ci = CIContext()

    func selectRegion(in image: CIImage, at point: CGPoint, quality: SelectionQuality) async throws -> SelectionMask {
        try await select(in: image, prompt: .point(point), quality: quality)
    }

    func selectClass(in image: CIImage, class semanticClass: SemanticClass, quality: SelectionQuality) async throws -> SelectionMask {
        _ = semanticClass
        return try await select(in: image, prompt: .point(CGPoint(x: image.extent.midX, y: image.extent.midY)), quality: quality)
    }

    func select(in image: CIImage, prompt: SelectionPrompt, quality: SelectionQuality) async throws -> SelectionMask {
        _ = quality
        lastPrompt = prompt
        let extent = image.extent.integral
        let white = CIImage(color: .white).cropped(to: extent.insetBy(dx: extent.width * 0.3, dy: extent.height * 0.3))
        let composed = white.composited(over: CIImage(color: .black).cropped(to: extent)).cropped(to: extent)
        guard let cg = ci.createCGImage(composed, from: extent) else { throw SelectionError.emptyResult }
        return SelectionMask(
            cgImage: cg,
            extent: extent,
            confidence: 1,
            semanticClass: .unknown,
            source: .coreML(modelID: "test")
        )
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
        guard let cg = ci.createCGImage(CIImage(color: .white).cropped(to: extent), from: extent) else {
            throw SelectionError.emptyResult
        }
        return SelectionMask(
            cgImage: cg,
            extent: extent,
            confidence: 0.5,
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

private final class NoopDownloader: SelectionModelDownloading, @unchecked Sendable {
    func download(
        from remote: URL,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)?,
        isCancelled: @Sendable () -> Bool
    ) async throws {}
}
