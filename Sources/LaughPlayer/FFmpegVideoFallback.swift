import Foundation
import CryptoKit

enum FFmpegVideoFallback {
    struct Result {
        let outputURL: URL
        let method: String
        let elapsedMs: Double
    }

    private struct CacheEntry {
        let outputURL: URL
        let sourceIdentity: String
    }

    private static var allowHeavyTranscode: Bool {
        ProcessInfo.processInfo.environment["LAUGH_ENABLE_HEAVY_TRANSCODE"] == "1"
    }
    private static let processQueue = DispatchQueue(label: "ffmpeg-fallback-processes")
    private static var activeProcesses: [Process] = []
    private static var remuxCache: [String: CacheEntry] = [:]

    static func isAvailable() -> Bool {
        run(arguments: ["-version"]) == 0
    }

    static func terminateRunningProcesses() {
        processQueue.sync {
            for process in activeProcesses where process.isRunning {
                process.terminate()
            }
            activeProcesses.removeAll()
        }
    }

    /// Returns a previously remuxed playable file for this source, if the source file is unchanged.
    static func cachedPlayableURL(for inputURL: URL) -> URL? {
        guard let identity = sourceIdentity(for: inputURL) else { return nil }
        let entry: CacheEntry? = processQueue.sync {
            remuxCache[identity]
        }
        guard let entry, entry.sourceIdentity == identity else { return nil }
        guard FileManager.default.fileExists(atPath: entry.outputURL.path) else {
            _ = processQueue.sync { remuxCache.removeValue(forKey: identity) }
            return nil
        }
        return entry.outputURL
    }

    static func convertToPlayable(inputURL: URL) -> Result? {
        if let cached = cachedPlayableURL(for: inputURL) {
            print("[DEBUG-fallback] cache hit input=\(inputURL.path) output=\(cached.path)")
            return Result(outputURL: cached, method: "remux-cache", elapsedMs: 0)
        }

        let outputURL = makeOutputURL(for: inputURL)
        let start = CFAbsoluteTimeGetCurrent()
        print("[DEBUG-fallback] ffmpeg remux attempt input=\(inputURL.path) output=\(outputURL.path)")
        let remuxExit = run(arguments: [
            "-y",
            "-nostdin",
            "-i", inputURL.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-map", "0:s?",
            "-c", "copy",
            "-tag:v", "hvc1",
            outputURL.path
        ])
        if remuxExit != 0 {
            print("[DEBUG-fallback] remux exit code=\(remuxExit) (may have been cancelled during a media switch)")
        }
        if remuxExit == 0, FileManager.default.fileExists(atPath: outputURL.path) {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print(String(format: "[DEBUG-fallback] remux success in %.2fms", elapsedMs))
            if let identity = sourceIdentity(for: inputURL) {
                processQueue.sync {
                    remuxCache[identity] = CacheEntry(outputURL: outputURL, sourceIdentity: identity)
                }
            }
            return Result(outputURL: outputURL, method: "remux", elapsedMs: elapsedMs)
        }

        guard allowHeavyTranscode else {
            print("[DEBUG-fallback] remux failed; heavy transcode disabled")
            return nil
        }

        print("[DEBUG-fallback] remux failed, trying transcode")
        let transcodeStart = CFAbsoluteTimeGetCurrent()
        let transcodeExit = run(arguments: [
            "-y",
            "-nostdin",
            "-i", inputURL.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-threads", "2",
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-movflags", "+faststart",
            outputURL.path
        ])
        if transcodeExit == 0, FileManager.default.fileExists(atPath: outputURL.path) {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - transcodeStart) * 1000
            print(String(format: "[DEBUG-fallback] transcode success in %.2fms", elapsedMs))
            if let identity = sourceIdentity(for: inputURL) {
                processQueue.sync {
                    remuxCache[identity] = CacheEntry(outputURL: outputURL, sourceIdentity: identity)
                }
            }
            return Result(outputURL: outputURL, method: "transcode", elapsedMs: elapsedMs)
        }

        print("[DEBUG-fallback] transcode failed")
        return nil
    }

    private static func sourceIdentity(for inputURL: URL) -> String? {
        guard let values = try? inputURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return inputURL.path
        }
        let mod = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values.fileSize ?? 0
        return "\(inputURL.path)|\(mod)|\(size)"
    }

    private static func makeOutputURL(for inputURL: URL) -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LaughPlayerFallback", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let base = inputURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
        let identity = sourceIdentity(for: inputURL) ?? inputURL.path
        let digest = SHA256.hash(data: Data(identity.utf8))
        let hash = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return tempDir.appendingPathComponent("\(base)-\(hash).mp4")
    }

    @discardableResult
    private static func run(arguments: [String]) -> Int32 {
        guard let bundled = BundledCodecTools.ffmpegExecutablePath() else {
            return -1
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bundled)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            processQueue.sync {
                activeProcesses.append(process)
            }
            try process.run()
            process.waitUntilExit()
            processQueue.sync {
                activeProcesses.removeAll { $0 === process }
            }
            return process.terminationStatus
        } catch {
            processQueue.sync {
                activeProcesses.removeAll { $0 === process }
            }
            return -1
        }
    }
}
