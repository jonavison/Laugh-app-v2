import XCTest
import Darwin
@testable import LaughPlayer

final class IncompleteMediaProbeTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-incomplete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testZeroFilledMkvIsIncompleteOrDamaged() throws {
        let url = tempDir.appendingPathComponent("zeros.mkv")
        try Data(repeating: 0, count: 64 * 1024).write(to: url)
        XCTAssertTrue(IncompleteMediaProbe.looksLikeIncompleteOrDamaged(at: url))
    }

    func testValidEbmlHeaderIsNotFlagged() throws {
        let url = tempDir.appendingPathComponent("ok.mkv")
        // EBML magic + padding — enough for the 4-byte check.
        var data = Data([0x1A, 0x45, 0xDF, 0xA3])
        data.append(Data(repeating: 0xAB, count: 60))
        try data.write(to: url)
        XCTAssertFalse(IncompleteMediaProbe.looksLikeIncompleteOrDamaged(at: url))
    }

    /// Garbage where the magic should be — same shape as a truncated/corrupt file,
    /// not only a still-downloading torrent.
    func testCorruptNonZeroHeaderIsFlagged() throws {
        let url = tempDir.appendingPathComponent("corrupt.mkv")
        try Data(repeating: 0x42, count: 64).write(to: url)
        XCTAssertTrue(IncompleteMediaProbe.looksLikeIncompleteOrDamaged(at: url))
    }

    func testFfmpegEbmlFailureStderrIsFlagged() {
        let stderr = """
        Format matroska,webm detected only with low score of 1, misdetection possible!
        0x00 at pos 0 (0x0) invalid as first byte of an EBML number
        EBML header parsing failed
        Error opening input file /tmp/x.mkv.
        """
        XCTAssertTrue(IncompleteMediaProbe.looksLikeIncompleteOrDamaged(ffmpegStderr: stderr))
    }

    func testRemuxNoticeMentionsIncompleteOrDamaged() throws {
        let url = tempDir.appendingPathComponent("zeros.mkv")
        try Data(repeating: 0, count: 1024).write(to: url)
        let notice = PlaybackErrorFormatter.remuxFailedNotice(for: url)
        XCTAssertEqual(notice.kind, .incompleteOrDamaged)
        let lowered = notice.message.lowercased()
        XCTAssertTrue(lowered.contains("damaged") || lowered.contains("missing"))
        XCTAssertTrue(lowered.contains("download"))
    }

    func testStillDownloadingNoticeWhenHollow() throws {
        let url = tempDir.appendingPathComponent("hollow.mkv")
        let size = 8 * 1024 * 1024
        var data = Data(repeating: 0x5A, count: size)
        data.replaceSubrange(0..<4, with: Data([0x1A, 0x45, 0xDF, 0xA3]))
        let holeStart = size / 2
        data.replaceSubrange(holeStart..<(holeStart + 128 * 1024), with: Data(repeating: 0, count: 128 * 1024))
        try data.write(to: url)

        XCTAssertFalse(IncompleteMediaProbe.looksLikeUnreadableContainer(at: url))
        XCTAssertTrue(IncompleteMediaProbe.looksLikeIncompleteDownload(at: url))
        let notice = PlaybackErrorFormatter.stillDownloadingNotice(for: url)
        XCTAssertEqual(notice.kind, .stillDownloading)
        XCTAssertTrue(notice.message.lowercased().contains("download"))
    }

    func testSparsePreallocationIsIncomplete() throws {
        // Logical 50MB with no allocated blocks — classic preallocated torrent stub.
        let url = tempDir.appendingPathComponent("sparse.mkv")
        let fd = open(url.path, O_RDWR | O_CREAT, 0o644)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertEqual(ftruncate(fd, 50 * 1024 * 1024), 0)

        XCTAssertFalse(
            IncompleteMediaProbe.sourcePayloadLooksMaterialized(
                logicalBytes: 50 * 1024 * 1024,
                allocatedBytes: 0
            )
        )
        XCTAssertTrue(
            IncompleteMediaProbe.sourcePayloadLooksMaterialized(
                logicalBytes: 50 * 1024 * 1024,
                allocatedBytes: 50 * 1024 * 1024
            )
        )
        // Mid-download (90%) must still refuse — random torrent pieces leave seek holes.
        XCTAssertFalse(
            IncompleteMediaProbe.sourcePayloadLooksMaterialized(
                logicalBytes: 1_700_000_000,
                allocatedBytes: 1_530_000_000
            )
        )
        XCTAssertTrue(IncompleteMediaProbe.looksLikeSparsePreallocation(at: url))
        XCTAssertTrue(IncompleteMediaProbe.looksLikeIncompleteOrDamaged(at: url))
    }

    func testMidFileZeroSlabIsIncompleteEvenWithValidHeader() throws {
        // Bourne-class failure: header + allocated size look fine, middle is still zeros.
        let url = tempDir.appendingPathComponent("hollow.mkv")
        let size = 8 * 1024 * 1024
        var data = Data(repeating: 0x5A, count: size)
        data.replaceSubrange(0..<4, with: Data([0x1A, 0x45, 0xDF, 0xA3]))
        let holeStart = size / 2
        data.replaceSubrange(holeStart..<(holeStart + 128 * 1024), with: Data(repeating: 0, count: 128 * 1024))
        try data.write(to: url)

        XCTAssertTrue(IncompleteMediaProbe.sampleLooksUnmaterialized(Data(repeating: 0, count: 64 * 1024)))
        XCTAssertFalse(IncompleteMediaProbe.sampleLooksUnmaterialized(Data(repeating: 0x5A, count: 64 * 1024)))
        XCTAssertTrue(IncompleteMediaProbe.looksLikeHollowInterior(at: url))
        XCTAssertTrue(IncompleteMediaProbe.looksLikeIncompleteOrDamaged(at: url))
    }

    func testDenseNonZeroFileIsNotHollow() throws {
        let url = tempDir.appendingPathComponent("dense.mkv")
        var data = Data(repeating: 0x3C, count: 4 * 1024 * 1024)
        data.replaceSubrange(0..<4, with: Data([0x1A, 0x45, 0xDF, 0xA3]))
        try data.write(to: url)
        XCTAssertFalse(IncompleteMediaProbe.looksLikeHollowInterior(at: url))
        XCTAssertFalse(IncompleteMediaProbe.looksLikeIncompleteOrDamaged(at: url))
        XCTAssertEqual(IncompleteMediaProbe.contiguousHeadFraction(at: url), 1, accuracy: 0.001)
    }

    func testContiguousHeadStopsAtFirstHollowSlab() throws {
        let url = tempDir.appendingPathComponent("head-then-hole.mkv")
        let size = 10 * 1024 * 1024
        var data = Data(repeating: 0x5A, count: size)
        data.replaceSubrange(0..<4, with: Data([0x1A, 0x45, 0xDF, 0xA3]))
        // Hollow from ~40% onward.
        let holeStart = Int(Double(size) * 0.40)
        data.replaceSubrange(holeStart..<size, with: Data(repeating: 0, count: size - holeStart))
        try data.write(to: url)

        let head = IncompleteMediaProbe.contiguousHeadFraction(at: url)
        XCTAssertGreaterThanOrEqual(head, 0.38)
        XCTAssertLessThanOrEqual(head, 0.42)
    }

    func testCompleteLookingMp4IsNotFlaggedByRemuxNotice() throws {
        let url = tempDir.appendingPathComponent("ok.mp4")
        // size(4) + "ftyp"
        var data = Data([0x00, 0x00, 0x00, 0x18])
        data.append(contentsOf: Array("ftyp".utf8))
        data.append(Data(repeating: 0, count: 16))
        try data.write(to: url)
        let notice = PlaybackErrorFormatter.remuxFailedNotice(for: url)
        XCTAssertEqual(notice.kind, .remuxFailed)
    }
}
