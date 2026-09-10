import Foundation

/// Resolves the OpenSubtitles.com consumer Api-Key and User-Agent for anonymous API calls.
///
/// Create a free consumer at https://www.opensubtitles.com/en/consumers, then either:
/// - export `OPENSUBTITLES_API_KEY=…`, or
/// - write the key (one line) to `Packaging/opensubtitles-api-key.local` (gitignored).
enum OpenSubtitlesConfig {
    static let envKeyName = "OPENSUBTITLES_API_KEY"
    static let localKeyFileName = "opensubtitles-api-key.local"

    /// Prefer env, then the gitignored Packaging file next to RELEASE_VERSION.
    static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        packagingDirectory: URL? = nil
    ) -> String? {
        if let fromEnv = environment[envKeyName]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fromEnv.isEmpty {
            return fromEnv
        }
        let packaging = packagingDirectory ?? defaultPackagingDirectory()
        let fileURL = packaging.appendingPathComponent(localKeyFileName)
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            return trimmed
        }
        return nil
    }

    static var hasApiKey: Bool { apiKey() != nil }

    static func userAgent(version: String? = nil) -> String {
        let ver = version ?? marketingVersion()
        return "LaughPlayer v\(ver)"
    }

    static func missingKeyMessage() -> String {
        """
        OpenSubtitles Api-Key is not configured. Create a free consumer at opensubtitles.com/en/consumers, then set OPENSUBTITLES_API_KEY or write the key to Packaging/opensubtitles-api-key.local.
        """
    }

    static func marketingVersion() -> String {
        if let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !short.isEmpty {
            return short.replacingOccurrences(of: "-dev", with: "")
        }
        let packaging = defaultPackagingDirectory().appendingPathComponent("RELEASE_VERSION")
        if let raw = try? String(contentsOf: packaging, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "0.0.0"
    }

    private static func defaultPackagingDirectory() -> URL {
        // Dev: repo Packaging/ next to Sources/. Bundled app: fall back to cwd Packaging/.
        let module = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // OpenSubtitlesConfig.swift
            .deletingLastPathComponent() // LaughPlayer
            .deletingLastPathComponent() // Sources
        let repoPackaging = module.appendingPathComponent("Packaging")
        if FileManager.default.fileExists(atPath: repoPackaging.path) {
            return repoPackaging
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Packaging")
    }
}
