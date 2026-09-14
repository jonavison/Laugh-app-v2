import XCTest
@testable import LaughPlayer

final class RemuxCacheEvictionTests: XCTestCase {
    func testDeletionOrderPrefersOversizeThenPreviewsThenOldestFull() {
        let dir = URL(fileURLWithPath: "/tmp")
        let fourGiB = RemuxCacheEviction.maxFullRemuxRetainBytes
        let entries = [
            RemuxCacheEviction.Entry(
                url: dir.appendingPathComponent("full-new.mp4"),
                byteCount: 100,
                modifiedAt: Date(timeIntervalSince1970: 300),
                isPreview: false
            ),
            RemuxCacheEviction.Entry(
                url: dir.appendingPathComponent("preview-old-preview-x.mp4"),
                byteCount: 10,
                modifiedAt: Date(timeIntervalSince1970: 100),
                isPreview: true
            ),
            RemuxCacheEviction.Entry(
                url: dir.appendingPathComponent("preview-new-preview-y.mp4"),
                byteCount: 10,
                modifiedAt: Date(timeIntervalSince1970: 200),
                isPreview: true
            ),
            RemuxCacheEviction.Entry(
                url: dir.appendingPathComponent("full-old.mp4"),
                byteCount: 100,
                modifiedAt: Date(timeIntervalSince1970: 50),
                isPreview: false
            ),
            RemuxCacheEviction.Entry(
                url: dir.appendingPathComponent("full-huge.mp4"),
                byteCount: fourGiB + 1,
                modifiedAt: Date(timeIntervalSince1970: 400),
                isPreview: false
            )
        ]
        let order = RemuxCacheEviction.deletionOrder(entries).map(\.url.lastPathComponent)
        XCTAssertEqual(
            order,
            [
                "full-huge.mp4",
                "preview-old-preview-x.mp4",
                "preview-new-preview-y.mp4",
                "full-old.mp4",
                "full-new.mp4"
            ]
        )
    }

    func testEnforceBudgetDeletesOldestUntilUnderCapAndProtectsPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemuxCacheEvictionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func write(_ name: String, bytes: Int, age: TimeInterval) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data(repeating: 1, count: bytes).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(age)],
                ofItemAtPath: url.path
            )
            return url
        }

        let keep = try write("keep-me.mp4", bytes: 40, age: -10_000)
        _ = try write("old-preview-a.mp4", bytes: 30, age: -9_000)
        _ = try write("mid.mp4", bytes: 30, age: -5_000)
        _ = try write("new.mp4", bytes: 30, age: -100)

        let report = RemuxCacheEviction.enforceBudget(
            in: root,
            budgetBytes: 70,
            protectPaths: [keep.path]
        )
        XCTAssertGreaterThanOrEqual(report.deletedCount, 2)
        XCTAssertLessThanOrEqual(report.remainingBytes, 70)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("new.mp4").path))
    }

    func testEnforceBudgetDeletesOversizeFullRemuxEvenUnderBudget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemuxCacheEvictionOversize-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let huge = root.appendingPathComponent("huge-film.mp4")
        // Sparse file: set length without writing 5GiB of zeros.
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(RemuxCacheEviction.maxFullRemuxRetainBytes) + 1024)
        try handle.close()

        let small = root.appendingPathComponent("ok-preview-x.mp4")
        try Data(repeating: 2, count: 2048).write(to: small)

        let report = RemuxCacheEviction.enforceBudget(
            in: root,
            budgetBytes: RemuxCacheEviction.defaultBudgetBytes,
            protectPaths: []
        )
        XCTAssertEqual(report.deletedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: huge.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: small.path))
    }

    func testRetainCapHelpers() {
        let cap = RemuxCacheEviction.maxFullRemuxRetainBytes
        XCTAssertTrue(RemuxCacheEviction.shouldRetainFullRemux(byteCount: cap))
        XCTAssertFalse(RemuxCacheEviction.shouldRetainFullRemux(byteCount: cap + 1))
        XCTAssertTrue(RemuxCacheEviction.sourceTooLargeForRetainedRemux(byteCount: cap + 1))
        XCTAssertFalse(RemuxCacheEviction.sourceTooLargeForRetainedRemux(byteCount: cap))
    }

    func testDefaultBudgetAndRetainCaps() {
        XCTAssertEqual(RemuxCacheEviction.defaultBudgetBytes, 12 * 1024 * 1024 * 1024)
        XCTAssertEqual(RemuxCacheEviction.maxFullRemuxRetainBytes, 4 * 1024 * 1024 * 1024)
    }
}
