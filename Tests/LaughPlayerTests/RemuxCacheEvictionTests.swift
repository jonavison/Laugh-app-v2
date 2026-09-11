import XCTest
@testable import LaughPlayer

final class RemuxCacheEvictionTests: XCTestCase {
    func testDeletionOrderPrefersPreviewsThenOldest() {
        let dir = URL(fileURLWithPath: "/tmp")
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
            )
        ]
        let order = RemuxCacheEviction.deletionOrder(entries).map(\.url.lastPathComponent)
        XCTAssertEqual(
            order,
            [
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

    func testDefaultBudgetIsTwelveGibibytes() {
        XCTAssertEqual(RemuxCacheEviction.defaultBudgetBytes, 12 * 1024 * 1024 * 1024)
    }
}
