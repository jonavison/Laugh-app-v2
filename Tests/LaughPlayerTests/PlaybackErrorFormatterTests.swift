import XCTest
@testable import LaughPlayer

final class PlaybackErrorFormatterTests: XCTestCase {
    private var tempFileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-playback-error-\(UUID().uuidString).mkv")
        try Data([0x00]).write(to: tempFileURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempFileURL)
        try super.tearDownWithError()
    }

    func testAccessDeniedMessageIsShortAndActionable() {
        let message = PlaybackErrorFormatter.userMessage(
            kind: .accessDenied,
            url: URL(fileURLWithPath: "/Volumes/Drive/movie.mkv"),
            detail: nil
        )
        XCTAssertTrue(message.lowercased().contains("files and folders"))
        XCTAssertFalse(message.contains("AVFoundation"))
        XCTAssertFalse(message.contains("LAUGH_ENABLE_HEAVY_TRANSCODE"))
    }

    func testMissingFileMessage() {
        let message = PlaybackErrorFormatter.userMessage(
            kind: .missingFile,
            url: URL(fileURLWithPath: "/missing/movie.mkv"),
            detail: nil
        )
        XCTAssertTrue(message.lowercased().contains("wasn't found"))
    }

    func testRemuxFailedDoesNotImplyAccess() {
        let message = PlaybackErrorFormatter.userMessage(
            kind: .remuxFailed,
            url: tempFileURL,
            detail: nil
        )
        XCTAssertTrue(message.lowercased().contains("couldn't prepare"))
        XCTAssertFalse(message.lowercased().contains("allow laughplayer"))
    }

    func testClassifyPermissionReasonAsAccess() {
        let kind = PlaybackErrorFormatter.classifyOpenFailure(
            url: tempFileURL,
            reason: "File is not readable",
            probeDetails: "not readable / permission denied",
            error: nil
        )
        XCTAssertEqual(kind, .accessDenied)
    }

    func testClassifyCannotOpenAsUnsupportedNotAccess() {
        let kind = PlaybackErrorFormatter.classifyOpenFailure(
            url: tempFileURL,
            reason: "Cannot Open",
            probeDetails: "candidate0: playable=false videoTracks=0 audioTracks=0",
            error: nil
        )
        XCTAssertEqual(kind, .unsupportedOrUnreadable)
    }

    func testClassifyPOSIXPermissionError() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES), userInfo: [
            NSLocalizedDescriptionKey: "Permission denied"
        ])
        let kind = PlaybackErrorFormatter.classifyOpenFailure(
            url: tempFileURL,
            reason: error.localizedDescription,
            probeDetails: PlaybackErrorFormatter.describe(error),
            error: error
        )
        XCTAssertEqual(kind, .accessDenied)
    }

    func testOpenFailureUsesAccessCopy() {
        let failure = PlaybackErrorFormatter.openFailure(
            url: tempFileURL,
            reason: "File is not readable",
            probeDetails: "permission denied"
        )
        XCTAssertTrue(failure.offersFileAccessSettings)
        XCTAssertTrue(failure.userMessage.lowercased().contains("files and folders"))
    }

    func testMissingFileUnderReadableParent() {
        let missing = tempFileURL.deletingLastPathComponent()
            .appendingPathComponent("definitely-missing-\(UUID().uuidString).mkv")
        XCTAssertTrue(PlaybackErrorFormatter.looksLikeMissingFile(missing))
        XCTAssertFalse(PlaybackErrorFormatter.matchesAccessProbe(url: missing))
    }

    func testRemuxFailedMessageUsesAccessWhenUnreadable() {
        // Simulate the denied-access shape: path absent and parent unlistable.
        let blocked = URL(fileURLWithPath: "/Volumes/LaughNoSuchVolume-\(UUID().uuidString)/movie.mkv")
        let notice = PlaybackErrorFormatter.remuxFailedNotice(for: blocked)
        XCTAssertTrue(notice.offersFileAccessSettings)
        XCTAssertTrue(notice.message.lowercased().contains("files and folders"))
    }
}
