import AppKit
import Sparkle

/// In-app updates via Sparkle (shipped `.app` only — not `swift run` / Dev builds without feed).
@MainActor
enum LaughSparkleUpdater {
    private static var controller: SPUStandardUpdaterController?

    static var isAvailable: Bool {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return false }
        // Dev / SPM-run bundles omit SUFeedURL on purpose.
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return false }
        guard Bundle.main.bundleIdentifier == "com.laughplayer.app" else { return false }
        return true
    }

    static func install(into delegate: SPUUpdaterDelegate) {
        guard isAvailable else { return }
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
    }

    static func checkForUpdates() {
        guard let controller else { return }
        controller.checkForUpdates(nil)
    }
}
