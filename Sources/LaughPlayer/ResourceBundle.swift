import Foundation

/// SPM resource bundle locator that works for both `swift run` and packaged `.app`s.
///
/// SwiftPM’s generated `Bundle.module` only checks
/// `Bundle.main.bundleURL/LaughPlayer_LaughPlayer.bundle` (plus a machine-local
/// `.build/...` fallback). Packaging used to put the bundle only under
/// `Contents/Resources/`, which made clean installs crash on launch when
/// `.build` was absent.
enum ResourceBundle {
    static let name = "LaughPlayer_LaughPlayer.bundle"

    static let bundle: Bundle = {
        var candidates: [URL] = [
            Bundle.main.bundleURL.appendingPathComponent(name),
        ]
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(name))
        }
        candidates.append(
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(name)
        )

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        candidates.append(contentsOf: [
            cwd.appendingPathComponent(".build/arm64-apple-macosx/debug/\(name)"),
            cwd.appendingPathComponent(".build/arm64-apple-macosx/release/\(name)"),
            cwd.appendingPathComponent(".build/debug/\(name)"),
            cwd.appendingPathComponent(".build/release/\(name)"),
        ])

        for url in candidates {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        // Never fatal — fall back to the app bundle (Assets.car / codec-tools live there).
        return Bundle.main
    }()
}
