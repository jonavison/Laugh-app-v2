import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import LaughPlayer

/// Subject Select busy reporting: the pipeline says which step it is on, and the panel
/// turns that into a caption (plus a bar for the one step with real progress).
final class SelectionBusyStatusTests: XCTestCase {
    func testIdleHasNoStatusSoTheRowStaysHidden() {
        XCTAssertNil(SelectionBusyStatus.make(phase: .idle))
    }

    func testDownloadReportsPercentAndBarFraction() throws {
        let status = try XCTUnwrap(SelectionBusyStatus.make(phase: .downloading(progress: 0.42)))
        XCTAssertEqual(status.caption, "Downloading MobileSAM… 42%")
        XCTAssertEqual(try XCTUnwrap(status.fraction), 0.42, accuracy: 0.0001)
    }

    func testDownloadFractionIsClamped() throws {
        let over = try XCTUnwrap(SelectionBusyStatus.make(phase: .downloading(progress: 1.8)))
        XCTAssertEqual(over.caption, "Downloading MobileSAM… 100%")
        XCTAssertEqual(try XCTUnwrap(over.fraction), 1, accuracy: 0.0001)

        let under = try XCTUnwrap(SelectionBusyStatus.make(phase: .downloading(progress: -0.5)))
        XCTAssertEqual(try XCTUnwrap(under.fraction), 0, accuracy: 0.0001)
    }

    /// Select stages have no honest percentage, so they narrate without a bar.
    func testSelectStagesNarrateWithoutABar() throws {
        let captions = try [
            ImageSelectionSession.Stage.preparing,
            .findingPeople,
            .cuttingOut(completed: 0, total: 1),
            .refining
        ].map { stage -> String in
            let status = try XCTUnwrap(SelectionBusyStatus.make(phase: .selecting(stage)))
            XCTAssertNil(status.fraction, "\(stage) has no fraction to show")
            return status.caption
        }
        XCTAssertEqual(
            captions,
            ["Preparing…", "Finding people…", "Cutting out the subject…", "Refining edges…"]
        )
    }

    func testGroupCutoutCountsThePersonInFlight() throws {
        func caption(completed: Int, total: Int) throws -> String {
            try XCTUnwrap(
                SelectionBusyStatus.make(
                    phase: .selecting(.cuttingOut(completed: completed, total: total))
                )
            ).caption
        }
        XCTAssertEqual(try caption(completed: 0, total: 3), "Cutting out people (1 of 3)…")
        XCTAssertEqual(try caption(completed: 1, total: 3), "Cutting out people (2 of 3)…")
        // The last completion arrives before the stage moves on — never "4 of 3".
        XCTAssertEqual(try caption(completed: 3, total: 3), "Cutting out people (3 of 3)…")
    }
}

final class SelectionProgressViewTests: XCTestCase {
    func testRowLaysOutWhileBusyAndHidesWhenIdle() {
        let view = SelectionProgressView()
        view.status = SelectionBusyStatus(caption: "Finding people…", fraction: nil)
        view.layoutSubtreeIfNeeded()

        XCTAssertFalse(view.isHidden)
        XCTAssertGreaterThan(view.fittingSize.height, 0, "spinner row should claim height")

        view.status = nil
        XCTAssertTrue(view.isHidden)
    }

    /// The bar is only laid in for statuses that carry a fraction, so the spinner-only
    /// states stay a single compact line.
    func testBarOnlyTakesSpaceWhenThereIsAFraction() {
        let view = SelectionProgressView()
        view.status = SelectionBusyStatus(caption: "Finding people…", fraction: nil)
        view.layoutSubtreeIfNeeded()
        let spinnerOnly = view.fittingSize.height

        view.status = SelectionBusyStatus(caption: "Downloading MobileSAM… 10%", fraction: 0.1)
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(view.fittingSize.height, spinnerOnly)
    }
}

/// Stage progression as the session runs a select.
final class SelectionSessionStageTests: XCTestCase {
    private let extent = CGRect(x: 0, y: 0, width: 200, height: 160)
    private let left = CGRect(x: 20, y: 40, width: 50, height: 80)
    private let right = CGRect(x: 120, y: 30, width: 60, height: 100)

    /// Auto Select must look busy on the click itself, not one hop later — the button
    /// press is exactly when the user is deciding whether anything happened.
    func testSessionIsBusyBeforeTheFirstAwait() {
        let session = ImageSelectionSession(provider: StubPersonProvider(rects: [left], extent: extent))
        session.selectPerson(in: photo())

        XCTAssertTrue(session.isSelecting)
        XCTAssertEqual(session.selectingStage, .preparing)
    }

    func testPerPersonRouteNarratesEachPerson() async throws {
        let vision = StubPersonProvider(rects: [left, right], extent: extent)
        let sam = StubBatchProvider(rects: [left, right], extent: extent)
        let session = ImageSelectionSession(
            visionProvider: vision,
            modelStore: try readyStore(),
            samProvider: sam,
            allowsModelDownload: false
        )

        var stages: [ImageSelectionSession.Stage] = []
        session.onChromeChange = { [weak session] in
            guard let stage = session?.selectingStage else { return }
            if stages.last != stage { stages.append(stage) }
        }

        session.selectPerson(in: photo())
        for _ in 0..<80 where session.isSelecting {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertFalse(session.isSelecting)
        XCTAssertTrue(session.hasSelection, "stub SAM should have produced a matte")
        XCTAssertNil(session.selectingStage, "idle once finished")
        XCTAssertEqual(
            stages,
            [
                .preparing,
                .findingPeople,
                .cuttingOut(completed: 0, total: 2),
                .cuttingOut(completed: 1, total: 2),
                .cuttingOut(completed: 2, total: 2),
                .refining
            ]
        )
    }

    /// Progress callbacks race the run that owns them; a late one must not re-arm the
    /// spinner after the session has gone idle (or moved to a newer select).
    func testStaleProgressDoesNotReviveTheBusyState() async throws {
        let vision = StubPersonProvider(rects: [left], extent: extent)
        let sam = StubBatchProvider(rects: [left], extent: extent)
        let session = ImageSelectionSession(
            visionProvider: vision,
            modelStore: try readyStore(),
            samProvider: sam,
            allowsModelDownload: false
        )

        session.selectPerson(in: photo())
        for _ in 0..<80 where session.isSelecting {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(session.isSelecting)

        // The provider fires its progress callback again after the run finished.
        sam.replayLastProgress()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(session.isSelecting)
        XCTAssertNil(session.selectingStage)
    }

    // MARK: - Helpers

    /// A store whose ready files exist, so the accurate path runs against the stub engine
    /// instead of stopping at `modelNotReady`.
    private func readyStore() throws -> SelectionModelStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-stage-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = SelectionModelStore(root: root, downloader: NoopDownloader())
        let artifact = SelectionModelArtifact.mobileSAM
        let dir = store.cacheDirectory(for: artifact)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in artifact.readyRelativePaths {
            try Data().write(to: dir.appendingPathComponent(name))
        }
        XCTAssertTrue(store.isReady(artifact))
        return store
    }

    private func photo() -> CIImage {
        var image = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.12)).cropped(to: extent)
        for rect in [left, right] {
            image = CIImage(color: CIColor(red: 0.8, green: 0.3, blue: 0.2))
                .cropped(to: rect)
                .composited(over: image)
        }
        return image.cropped(to: extent)
    }
}

/// Vision stand-in that splits people into instances without needing a real photo.
private final class StubPersonProvider: SelectionProvider, PersonInstanceSegmenting, @unchecked Sendable {
    let providerID = "test.vision.stages"
    private let rects: [CGRect]
    private let extent: CGRect
    private let ctx = CIContext(options: [.cacheIntermediates: false])

    init(rects: [CGRect], extent: CGRect) {
        self.rects = rects
        self.extent = extent
    }

    func personInstanceMasks(in image: CIImage, quality: SelectionQuality) async throws -> [SelectionMask] {
        rects.compactMap { StubMask.make(rects: [$0], extent: extent, context: ctx) }
    }

    func selectClass(
        in image: CIImage,
        class semanticClass: SemanticClass,
        quality: SelectionQuality
    ) async throws -> SelectionMask {
        guard let mask = StubMask.make(rects: rects, extent: extent, context: ctx) else {
            throw SelectionError.emptyResult
        }
        return mask
    }

    func selectRegion(in image: CIImage, at point: CGPoint, quality: SelectionQuality) async throws -> SelectionMask {
        try await selectClass(in: image, class: .person, quality: quality)
    }

    func select(in image: CIImage, prompt: SelectionPrompt, quality: SelectionQuality) async throws -> SelectionMask {
        try await selectClass(in: image, class: .person, quality: quality)
    }
}

/// SAM stand-in that reports per-prompt progress the way the CoreML provider does.
private final class StubBatchProvider: SelectionProvider, BatchPromptSelecting, @unchecked Sendable {
    let providerID = "test.sam.stages"
    private let rects: [CGRect]
    private let extent: CGRect
    private let ctx = CIContext(options: [.cacheIntermediates: false])
    private var lastProgress: (@Sendable (Int) -> Void)?
    private var lastCount = 0

    init(rects: [CGRect], extent: CGRect) {
        self.rects = rects
        self.extent = extent
    }

    func select(
        in image: CIImage,
        prompts: [SelectionPrompt],
        quality: SelectionQuality,
        onProgress: @escaping @Sendable (Int) -> Void
    ) async throws -> [SelectionMask?] {
        lastProgress = onProgress
        lastCount = prompts.count
        return prompts.enumerated().map { index, _ in
            defer { onProgress(index + 1) }
            let rect = index < rects.count ? rects[index] : extent
            return StubMask.make(rects: [rect], extent: extent, context: ctx)
        }
    }

    func select(
        in image: CIImage,
        prompts: [SelectionPrompt],
        quality: SelectionQuality
    ) async throws -> [SelectionMask?] {
        try await select(in: image, prompts: prompts, quality: quality, onProgress: { _ in })
    }

    /// Simulates a progress callback that arrives after the run it belonged to finished.
    func replayLastProgress() {
        lastProgress?(lastCount)
    }

    func selectRegion(in image: CIImage, at point: CGPoint, quality: SelectionQuality) async throws -> SelectionMask {
        try await select(in: image, prompt: .point(point), quality: quality)
    }

    func selectClass(
        in image: CIImage,
        class semanticClass: SemanticClass,
        quality: SelectionQuality
    ) async throws -> SelectionMask {
        try await select(in: image, prompt: .point(CGPoint(x: extent.midX, y: extent.midY)), quality: quality)
    }

    func select(in image: CIImage, prompt: SelectionPrompt, quality: SelectionQuality) async throws -> SelectionMask {
        guard let mask = StubMask.make(rects: rects, extent: extent, context: ctx) else {
            throw SelectionError.emptyResult
        }
        return mask
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

private enum StubMask {
    static func make(rects: [CGRect], extent: CGRect, context: CIContext) -> SelectionMask? {
        guard !rects.isEmpty else { return nil }
        var composed = CIImage(color: .black).cropped(to: extent)
        for rect in rects {
            composed = CIImage(color: .white).cropped(to: rect).composited(over: composed)
        }
        guard let cg = context.createCGImage(composed.cropped(to: extent), from: extent) else { return nil }
        return SelectionMask(
            cgImage: cg,
            extent: extent,
            confidence: 0.9,
            semanticClass: .person,
            source: .visionPerson
        )
    }
}
