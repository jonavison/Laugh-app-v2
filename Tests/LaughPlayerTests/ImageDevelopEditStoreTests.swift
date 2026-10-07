import XCTest
@testable import LaughPlayer

final class ImageDevelopEditStoreTests: XCTestCase {
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

    func testSaveLoadAndHasEdit() {
        let path = "/tmp/laugh-develop-test/photo.jpg"
        XCTAssertFalse(ImageDevelopEditStore.hasEdit(forPath: path))

        let edit = ImageDevelopEdit(
            parameters: ImageAdjustParameters(exposure: 0.35, vignette: 0.2),
            rotationQuarterTurns: 1,
            flipHorizontal: true,
            cropNormalized: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            straightenRadians: 0.05
        )
        ImageDevelopEditStore.save(edit, forPath: path)

        XCTAssertTrue(ImageDevelopEditStore.hasEdit(forPath: path))
        let loaded = ImageDevelopEditStore.edit(forPath: path)
        XCTAssertEqual(loaded?.parameters.exposure ?? 0, 0.35, accuracy: 0.0001)
        XCTAssertEqual(loaded?.parameters.vignette ?? 0, 0.2, accuracy: 0.0001)
        XCTAssertEqual(loaded?.rotationQuarterTurns, 1)
        XCTAssertEqual(loaded?.flipHorizontal, true)
        XCTAssertEqual(loaded?.cropNormalized?.width ?? 0, 0.8, accuracy: 0.0001)
        XCTAssertEqual(loaded?.straightenRadians ?? 0, 0.05, accuracy: 0.0001)
        XCTAssertTrue(ImageDevelopEditStore.editedPaths().contains(
            URL(fileURLWithPath: path).standardizedFileURL.path
        ))
    }

    func testIdentitySaveRemovesDocument() {
        let path = "/tmp/laugh-develop-test/clean.jpg"
        ImageDevelopEditStore.save(
            ImageDevelopEdit(parameters: ImageAdjustParameters(exposure: 0.5)),
            forPath: path
        )
        XCTAssertTrue(ImageDevelopEditStore.hasEdit(forPath: path))

        ImageDevelopEditStore.save(.identity, forPath: path)
        XCTAssertFalse(ImageDevelopEditStore.hasEdit(forPath: path))
        XCTAssertNil(ImageDevelopEditStore.edit(forPath: path))
    }

    func testRemoveClearsPath() {
        let path = "/tmp/laugh-develop-test/clear.jpg"
        ImageDevelopEditStore.save(
            ImageDevelopEdit(parameters: ImageAdjustParameters(contrast: 1.2)),
            forPath: path
        )
        ImageDevelopEditStore.remove(forPath: path)
        XCTAssertFalse(ImageDevelopEditStore.hasEdit(forPath: path))
    }

    func testRemoveManyClearsListedPaths() {
        let keep = "/tmp/laugh-develop-test/keep.jpg"
        let dropA = "/tmp/laugh-develop-test/drop-a.jpg"
        let dropB = "/tmp/laugh-develop-test/drop-b.jpg"
        ImageDevelopEditStore.save(
            ImageDevelopEdit(parameters: ImageAdjustParameters(saturation: 1.2)),
            forPath: keep
        )
        ImageDevelopEditStore.save(
            ImageDevelopEdit(parameters: ImageAdjustParameters(saturation: 1.3)),
            forPath: dropA
        )
        ImageDevelopEditStore.save(
            ImageDevelopEdit(parameters: ImageAdjustParameters(saturation: 1.4)),
            forPath: dropB
        )
        ImageDevelopEditStore.removeMany(forPaths: [dropA, dropB])
        XCTAssertTrue(ImageDevelopEditStore.hasEdit(forPath: keep))
        XCTAssertFalse(ImageDevelopEditStore.hasEdit(forPath: dropA))
        XCTAssertFalse(ImageDevelopEditStore.hasEdit(forPath: dropB))
    }

    func testPathNormalizationMatchesStandardizedURL() {
        let path = "/tmp/laugh-develop-test/./norm.jpg"
        ImageDevelopEditStore.save(
            ImageDevelopEdit(parameters: ImageAdjustParameters(saturation: 1.3)),
            forPath: path
        )
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        XCTAssertTrue(ImageDevelopEditStore.hasEdit(forPath: standardized))
    }

    func testSaveManyWritesOnceAndDropsIdentity() {
        let keep = "/tmp/laugh-develop-test/batch-keep.jpg"
        let drop = "/tmp/laugh-develop-test/batch-drop.jpg"
        ImageDevelopEditStore.save(
            ImageDevelopEdit(parameters: ImageAdjustParameters(saturation: 1.1)),
            forPath: drop
        )
        ImageDevelopEditStore.saveMany([
            keep: ImageDevelopEdit(parameters: ImageAdjustParameters(saturation: 1.4)),
            drop: .identity
        ])
        XCTAssertTrue(ImageDevelopEditStore.hasEdit(forPath: keep))
        XCTAssertFalse(ImageDevelopEditStore.hasEdit(forPath: drop))
        XCTAssertEqual(
            ImageDevelopEditStore.edit(forPath: keep)?.parameters.saturation ?? 0,
            1.4,
            accuracy: 0.0001
        )
    }
}
