import Foundation

enum BundledCodecTools {
    static func ffmpegExecutablePath() -> String? {
        guard PlaybackRuntime.canUseBundledCodecStack else { return nil }
        return bundledExecutablePath(named: "ffmpeg")
    }

    static func mpvExecutablePath() -> String? {
        guard PlaybackRuntime.canUseBundledCodecStack else { return nil }
        return bundledExecutablePath(named: "mpv")
    }

    private static func bundledExecutablePath(named name: String) -> String? {
        var candidates: [String] = []
        if let mainResource = Bundle.main.resourceURL?.path {
            candidates.append("\(mainResource)/codec-tools/bin/\(name)")
            candidates.append("\(mainResource)/Resources/codec-tools/bin/\(name)")
        }
        if let moduleResource = Bundle.module.resourceURL?.path {
            candidates.append("\(moduleResource)/codec-tools/bin/\(name)")
            candidates.append("\(moduleResource)/Resources/codec-tools/bin/\(name)")
        }
        let cwd = FileManager.default.currentDirectoryPath
        candidates.append("\(cwd)/Sources/LaughPlayer/codec-tools/bin/\(name)")
        candidates.append("\(cwd)/.build/arm64-apple-macosx/debug/LaughPlayer_LaughPlayer.bundle/codec-tools/bin/\(name)")
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func diagnosticSummary(for name: String) -> String {
        var candidates: [String] = []
        if let mainResource = Bundle.main.resourceURL?.path {
            candidates.append("\(mainResource)/codec-tools/bin/\(name)")
            candidates.append("\(mainResource)/Resources/codec-tools/bin/\(name)")
        }
        if let moduleResource = Bundle.module.resourceURL?.path {
            candidates.append("\(moduleResource)/codec-tools/bin/\(name)")
            candidates.append("\(moduleResource)/Resources/codec-tools/bin/\(name)")
        }
        let cwd = FileManager.default.currentDirectoryPath
        candidates.append("\(cwd)/Sources/LaughPlayer/codec-tools/bin/\(name)")
        candidates.append("\(cwd)/.build/arm64-apple-macosx/debug/LaughPlayer_LaughPlayer.bundle/codec-tools/bin/\(name)")

        return candidates
            .map { path in
                let exists = FileManager.default.fileExists(atPath: path)
                let exec = FileManager.default.isExecutableFile(atPath: path)
                return "\(path) [exists=\(exists), exec=\(exec)]"
            }
            .joined(separator: "\n")
    }
}
