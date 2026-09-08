import XCTest
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
