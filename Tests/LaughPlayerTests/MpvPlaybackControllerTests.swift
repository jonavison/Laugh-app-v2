import XCTest
@testable import LaughPlayer

final class MpvPlaybackControllerTests: XCTestCase {
    func testInProcessOptionsUseLibmpvAndNeverForceAWindow() {
        let options = Dictionary(uniqueKeysWithValues: MpvPlaybackController.inProcessOptions)
        XCTAssertEqual(options["vo"], "libmpv")
        XCTAssertEqual(options["hwdec"], "videotoolbox-copy")
        XCTAssertEqual(options["ao"], "coreaudio")
        XCTAssertEqual(options["video-sync"], "audio")
        XCTAssertEqual(options["force-window"], "no")
        XCTAssertEqual(options["osc"], "no")
        XCTAssertEqual(options["sw-fast"], "yes")
        XCTAssertNotEqual(options["vo"], "gpu")
        XCTAssertFalse(MpvPlaybackController.inProcessOptions.contains(where: { $0.0 == "wid" }))
        XCTAssertEqual(MpvPresentCapability.preferred, .softwareBlit)
    }

    func testLibmpvCandidatePathsIncludeCodecToolsAndHomebrew() {
        let paths = MpvPlaybackController.libmpvDylibPaths()
        XCTAssertTrue(paths.contains { $0.hasSuffix("/codec-tools/lib/libmpv.2.dylib") })
        XCTAssertTrue(paths.contains("/opt/homebrew/lib/libmpv.2.dylib"))
    }

    func testSubtitleOverlayOptionsKeepVideoForPGS() {
        let options = Dictionary(uniqueKeysWithValues: MpvPlaybackController.subtitleOverlayOptions)
        XCTAssertNil(options["vid"], "vid=no cannot render PGS")
        XCTAssertEqual(options["aid"], "no")
        XCTAssertEqual(options["ao"], "null")
        XCTAssertEqual(options["vo"], "libmpv")
        XCTAssertTrue(options["vf"]?.contains("eq=") == true)
        XCTAssertTrue(options["vf"]?.contains("scale=960") == true)
    }
}
