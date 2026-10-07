import XCTest
@testable import LaughPlayer

final class ImageBatchSelectionTests: XCTestCase {
    private let a = URL(fileURLWithPath: "/tmp/batch/a.jpg")
    private let b = URL(fileURLWithPath: "/tmp/batch/b.jpg")
    private let c = URL(fileURLWithPath: "/tmp/batch/c.jpg")
    private var siblings: [URL] { [a, b, c] }

    func testToggleAddsAndRemoves() {
        var selection = ImageBatchSelection()
        selection.toggle(b, siblings: siblings)
        XCTAssertEqual(selection.orderedURLs, [b])
        selection.toggle(b, siblings: siblings)
        XCTAssertTrue(selection.isEmpty)
    }

    func testToggleKeepsFilmstripOrder() {
        var selection = ImageBatchSelection()
        selection.toggle(c, siblings: siblings)
        selection.toggle(a, siblings: siblings)
        XCTAssertEqual(selection.orderedURLs.map(\.lastPathComponent), ["a.jpg", "c.jpg"])
        XCTAssertTrue(selection.isActive)
    }

    func testSelectRangeFromAnchor() {
        var selection = ImageBatchSelection()
        selection.toggle(a, siblings: siblings)
        selection.selectRange(to: c, siblings: siblings)
        XCTAssertEqual(selection.orderedURLs, [a, b, c])
        XCTAssertTrue(selection.isActive)
    }

    func testReplaceUsesSiblingOrderThenExtras() {
        var selection = ImageBatchSelection()
        let extra = URL(fileURLWithPath: "/tmp/other/z.jpg")
        selection.replace(with: [c, extra, a], preferredOrder: siblings)
        XCTAssertEqual(selection.orderedURLs, [a, c, extra])
        XCTAssertTrue(selection.isActive)
    }

    func testRemoveDropsMemberAndDeactivatesBelowTwo() {
        var selection = ImageBatchSelection()
        selection.replace(with: [a, b, c], preferredOrder: siblings)
        selection.remove(b)
        XCTAssertEqual(selection.orderedURLs, [a, c])
        XCTAssertTrue(selection.isActive)
        selection.remove(c)
        XCTAssertEqual(selection.orderedURLs, [a])
        XCTAssertFalse(selection.isActive)
    }
}

final class ImageBatchLookApplyTests: XCTestCase {
    private let key = "ImageDevelopEdits"
    private var previousData: Data?

    override func setUp() {
        super.setUp()
        previousData = UserDefaults.standard.data(forKey: key)
        ImageDevelopEditStore.removeAllForTesting()
    }

    override func tearDown() {
        if let previousData {
            UserDefaults.standard.set(previousData, forKey: key)
        } else {
            ImageDevelopEditStore.removeAllForTesting()
        }
        super.tearDown()
    }

    func testApplyStampsParametersAndPreservesGeometry() {
        let path = "/tmp/batch-apply/photo.jpg"
        ImageDevelopEditStore.save(
            ImageDevelopEdit(
                parameters: ImageAdjustParameters(exposure: 0.1),
                rotationQuarterTurns: 2,
                flipHorizontal: true,
                cropNormalized: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
            ),
            forPath: path
        )

        let result = ImageBatchLookApply.apply(
            parameters: ImageAdjustParameters(exposure: 0.8, vignette: 0.4),
            toPaths: [path]
        )
        XCTAssertEqual(result.appliedCount, 1)
        XCTAssertEqual(result.replacedCount, 1)

        let loaded = ImageDevelopEditStore.edit(forPath: path)
        XCTAssertEqual(loaded?.parameters.exposure ?? 0, 0.8, accuracy: 0.0001)
        XCTAssertEqual(loaded?.parameters.vignette ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(loaded?.rotationQuarterTurns, 2)
        XCTAssertEqual(loaded?.flipHorizontal, true)
        XCTAssertEqual(loaded?.cropNormalized?.width ?? 0, 0.5, accuracy: 0.0001)
    }

    func testExistingEditCount() {
        let pathA = "/tmp/batch-apply/a.jpg"
        let pathB = "/tmp/batch-apply/b.jpg"
        ImageDevelopEditStore.save(
            ImageDevelopEdit(parameters: ImageAdjustParameters(contrast: 1.2)),
            forPath: pathA
        )
        XCTAssertEqual(ImageBatchLookApply.existingEditCount(in: [pathA, pathB]), 1)
    }

    func testApplyMixesDryAndWetPerPath() {
        let path = "/tmp/batch-apply/mix.jpg"
        ImageDevelopEditStore.save(
            ImageDevelopEdit(parameters: ImageAdjustParameters(exposure: 0.2)),
            forPath: path
        )
        ImageBatchLookApply.apply(
            parameters: ImageAdjustParameters(exposure: 0.8),
            toPaths: [path],
            dryByPath: [path: ImageAdjustParameters(exposure: 0.2)],
            mixByPath: [path: 0.5]
        )
        let loaded = ImageDevelopEditStore.edit(forPath: path)
        XCTAssertEqual(loaded?.parameters.exposure ?? 0, 0.5, accuracy: 0.0001)
    }
}

final class ImageAdjustParametersMixTests: XCTestCase {
    func testMixedAmountZeroAndOne() {
        let dry = ImageAdjustParameters(exposure: -0.4, saturation: 0.8)
        let wet = ImageAdjustParameters(exposure: 0.6, saturation: 1.4)
        XCTAssertEqual(ImageAdjustParameters.mixed(from: dry, to: wet, amount: 0), dry)
        XCTAssertEqual(ImageAdjustParameters.mixed(from: dry, to: wet, amount: 1), wet)
    }

    func testMixedAmountHalfwayLerpsScalars() {
        let dry = ImageAdjustParameters(exposure: 0, vignette: 0)
        let wet = ImageAdjustParameters(exposure: 1, vignette: 0.4)
        let mixed = ImageAdjustParameters.mixed(from: dry, to: wet, amount: 0.5)
        XCTAssertEqual(mixed.exposure, 0.5, accuracy: 0.0001)
        XCTAssertEqual(mixed.vignette, 0.2, accuracy: 0.0001)
    }
}

final class ImageBatchSessionStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ImageBatchSessionStore.removeAllForTesting()
    }

    override func tearDown() {
        ImageBatchSessionStore.removeAllForTesting()
        super.tearDown()
    }

    func testSaveLoadRoundTrip() {
        let pathA = "/tmp/batch-session/a.jpg"
        let pathB = "/tmp/batch-session/b.jpg"
        let record = ImageBatchSessionRecord(
            orderedPaths: [pathA, pathB],
            wetParameters: ImageAdjustParameters(exposure: 0.4, vignette: 0.3),
            mixByPath: [pathA: 1, pathB: 0.4],
            dryByPath: [
                pathA: .identity,
                pathB: ImageAdjustParameters(exposure: 0.1)
            ]
        )
        ImageBatchSessionStore.save(record)
        let loaded = ImageBatchSessionStore.load()
        XCTAssertEqual(loaded?.orderedPaths, [pathA, pathB])
        XCTAssertEqual(loaded?.wetParameters.exposure ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(loaded?.wetParameters.vignette ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(loaded?.mixByPath[pathB] ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(loaded?.dryByPath[pathB]?.exposure ?? 0, 0.1, accuracy: 0.0001)
    }

    func testSaveFewerThanTwoPathsClears() {
        ImageBatchSessionStore.save(
            ImageBatchSessionRecord(
                orderedPaths: ["/tmp/batch-session/only.jpg"],
                wetParameters: .identity,
                mixByPath: [:],
                dryByPath: [:]
            )
        )
        XCTAssertNil(ImageBatchSessionStore.load())
    }

    func testClearRemovesSession() {
        ImageBatchSessionStore.save(
            ImageBatchSessionRecord(
                orderedPaths: ["/tmp/batch-session/a.jpg", "/tmp/batch-session/b.jpg"],
                wetParameters: .identity,
                mixByPath: [:],
                dryByPath: [:]
            )
        )
        ImageBatchSessionStore.clear()
        XCTAssertNil(ImageBatchSessionStore.load())
    }
}
