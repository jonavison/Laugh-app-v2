import XCTest
@testable import LaughPlayer

final class MpvPlaybackControllerTests: XCTestCase {
    func testInProcessOptionsUseLibmpvAndNeverForceAWindow() {
        let options = Dictionary(uniqueKeysWithValues: MpvPlaybackController.inProcessOptions)
        XCTAssertEqual(options["vo"], "libmpv")
        XCTAssertEqual(options["hwdec"], "auto-copy")
        XCTAssertEqual(options["force-window"], "no")
        XCTAssertEqual(options["osc"], "no")
        XCTAssertNotEqual(options["vo"], "gpu")
        XCTAssertFalse(MpvPlaybackController.inProcessOptions.contains(where: { $0.0 == "wid" }))
    }

    func testLibmpvCandidatePathsIncludeCodecToolsAndHomebrew() {
        let paths = MpvPlaybackController.libmpvDylibPaths()
        XCTAssertTrue(paths.contains { $0.hasSuffix("/codec-tools/lib/libmpv.2.dylib") })
        XCTAssertTrue(paths.contains("/opt/homebrew/lib/libmpv.2.dylib"))
    }

    func testTerminateRunningProcessesIsSafeWithoutAHelperProcess() {
        MpvPlaybackController.terminateRunningProcesses()
    }
}
