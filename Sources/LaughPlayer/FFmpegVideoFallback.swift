import AVFoundation
import Foundation
import CryptoKit

/// Domain: **CompatibilityRemux** — stream-copy (or opt-in transcode) to a temp MP4 for **SystemDecodeStack** replay. See ADR 0003.
enum FFmpegVideoFallback {
    struct Result {
        let outputURL: URL
        let method: String
        let elapsedMs: Double
    }

    enum RemuxStart: Equatable {
        case cacheHit(URL)
        case progressive(URL)
        case failed
    }

    private struct CacheEntry {
        let outputURL: URL
        let sourceIdentity: String
    }

    private struct ActiveRemux {
        let process: Process
        let inputURL: URL
        let outputURL: URL
    }

    static var isHeavyTranscodeEnabled: Bool {
        ProcessInfo.processInfo.environment["LAUGH_ENABLE_HEAVY_TRANSCODE"] == "1"
    }

    private static var allowHeavyTranscode: Bool {
        isHeavyTranscodeEnabled
    }

    private static let processQueueKey = DispatchSpecificKey<Void>()
    private static let processQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "ffmpeg-fallback-processes")
        queue.setSpecific(key: processQueueKey, value: ())
        return queue
    }()

    /// Runs `work` on `processQueue`, inlining when already on that queue (avoids dispatch_sync deadlock).
    private static func onProcessQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: processQueueKey) != nil {
            return work()
        }
        return processQueue.sync(execute: work)
    }
    private static var activeProcesses: [Process] = []
    private static var activeRemux: ActiveRemux?
    private static var remuxCache: [String: CacheEntry] = [:]

    /// Minimum bytes muxed before we ask AVFoundation to open a fragmented MP4.
    private static let progressivePlayableMinBytes = 512 * 1024

    static func isAvailable() -> Bool {
        run(arguments: ["-version"]) == 0
    }

    /// Reads the primary video stream codec tag from ffmpeg's header probe (stderr).
    static func probePrimaryVideoCodecTag(for inputURL: URL) -> String? {
        guard isAvailable() else { return nil }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        return parseVideoCodecTag(from: stderr)
    }

    static func terminateRunningProcesses() {
        onProcessQueue {
            for process in activeProcesses where process.isRunning {
                process.terminate()
            }
            activeProcesses.removeAll()
            activeRemux = nil
        }
    }

    static func cachedPlayableURL(for inputURL: URL) -> URL? {
        guard let identity = sourceIdentity(for: inputURL) else { return nil }
        let entry: CacheEntry? = onProcessQueue {
            remuxCache[identity]
        }
        guard let entry, entry.sourceIdentity == identity else { return nil }
        guard FileManager.default.fileExists(atPath: entry.outputURL.path) else {
            _ = onProcessQueue { remuxCache.removeValue(forKey: identity) }
            return nil
        }
        return entry.outputURL
    }

    /// Cache hit returns immediately; otherwise starts fragmented remux and returns the growing output path.
    static func beginRemux(inputURL: URL) -> RemuxStart {
        if let cached = cachedPlayableURL(for: inputURL) {
            return .cacheHit(cached)
        }
        let outputURL = makeOutputURL(for: inputURL)
        if launchProgressiveRemux(inputURL: inputURL, outputURL: outputURL) {
            return .progressive(outputURL)
        }
        return .failed
    }

    static func isRemuxing(outputURL: URL) -> Bool {
        onProcessQueue {
            activeRemux?.outputURL == outputURL && activeRemux?.process.isRunning == true
        }
    }

    /// True when fragmented output is large enough for AVPlayer to start.
    static func isReadableEnoughForPlayback(url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size >= progressivePlayableMinBytes else { return false }

        let asset = AVURLAsset(url: url)
        if let playable = try? await asset.load(.isPlayable), playable { return true }
        if let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty { return true }
        return false
    }

    /// Blocking remux (safety net / transcode path).
    static func convertToPlayable(inputURL: URL) -> Result? {
        if let cached = cachedPlayableURL(for: inputURL) {
            return Result(outputURL: cached, method: "remux-cache", elapsedMs: 0)
        }

        let outputURL = makeOutputURL(for: inputURL)
        let start = CFAbsoluteTimeGetCurrent()
        let remuxExit = runRemux(inputURL: inputURL, outputURL: outputURL, fragmented: false)
        if remuxExit == 0, FileManager.default.fileExists(atPath: outputURL.path) {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            storeCache(inputURL: inputURL, outputURL: outputURL)
            return Result(outputURL: outputURL, method: "remux", elapsedMs: elapsedMs)
        }

        guard allowHeavyTranscode else { return nil }

        let transcodeStart = CFAbsoluteTimeGetCurrent()
        let transcodeExit = run(arguments: transcodeArguments(inputURL: inputURL, outputURL: outputURL))
        if transcodeExit == 0, FileManager.default.fileExists(atPath: outputURL.path) {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - transcodeStart) * 1000
            storeCache(inputURL: inputURL, outputURL: outputURL)
            return Result(outputURL: outputURL, method: "transcode", elapsedMs: elapsedMs)
        }
        return nil
    }

    private static func launchProgressiveRemux(inputURL: URL, outputURL: URL) -> Bool {
        guard let bundled = BundledCodecTools.ffmpegExecutablePath() else { return false }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bundled)
        process.arguments = remuxArguments(inputURL: inputURL, outputURL: outputURL, fragmented: true)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { finished in
            processQueue.async {
                activeProcesses.removeAll { $0 === finished }
                if activeRemux?.process === finished {
                    activeRemux = nil
                }
                if finished.terminationStatus == 0,
                   FileManager.default.fileExists(atPath: outputURL.path) {
                    storeCache(inputURL: inputURL, outputURL: outputURL)
                    print("[DEBUG-fallback] progressive remux finished output=\(outputURL.path)")
                } else {
                    print("[DEBUG-fallback] progressive remux exit=\(finished.terminationStatus)")
                }
            }
        }

        do {
            try process.run()
            onProcessQueue {
                activeProcesses.append(process)
                activeRemux = ActiveRemux(process: process, inputURL: inputURL, outputURL: outputURL)
            }
            print("[DEBUG-fallback] progressive remux started output=\(outputURL.path)")
            return true
        } catch {
            print("[DEBUG-fallback] progressive remux launch failed: \(error)")
            return false
        }
    }

    private static func remuxArguments(inputURL: URL, outputURL: URL, fragmented: Bool) -> [String] {
        var args = [
            "-y", "-nostdin",
            "-i", inputURL.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-c", "copy",
            "-tag:v", "hvc1"
        ]
        if fragmented {
            args += ["-movflags", "frag_keyframe+empty_moov+default_base_moof"]
        } else {
            args += ["-movflags", "+faststart"]
        }
        args.append(outputURL.path)
        return args
    }

    private static func transcodeArguments(inputURL: URL, outputURL: URL) -> [String] {
        [
            "-y", "-nostdin",
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
        ]
    }

    @discardableResult
    private static func runRemux(inputURL: URL, outputURL: URL, fragmented: Bool) -> Int32 {
        run(arguments: remuxArguments(inputURL: inputURL, outputURL: outputURL, fragmented: fragmented))
    }

    private static func storeCache(inputURL: URL, outputURL: URL) {
        guard let identity = sourceIdentity(for: inputURL) else { return }
        onProcessQueue {
            remuxCache[identity] = CacheEntry(outputURL: outputURL, sourceIdentity: identity)
        }
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

    private static func parseVideoCodecTag(from stderr: String) -> String? {
        for line in stderr.components(separatedBy: .newlines) where line.contains("Video:") {
            var candidates: [String] = []
            var search = line[...]
            while let open = search.firstIndex(of: "("),
                  let close = search[open...].firstIndex(of: ")") {
                let inner = search[search.index(after: open)..<close]
                let token = inner.trimmingCharacters(in: .whitespaces)
                if token.count == 4, token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                    candidates.append(token.lowercased())
                }
                search = search[search.index(after: close)...]
            }
            if let tag = candidates.last { return tag }
        }
        return nil
    }

    private static func runCapturingStderr(arguments: [String]) -> String {
        guard let bundled = BundledCodecTools.ffmpegExecutablePath() else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bundled)
        process.arguments = arguments
        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe
        do {
            onProcessQueue { activeProcesses.append(process) }
            try process.run()
            process.waitUntilExit()
            onProcessQueue { activeProcesses.removeAll { $0 === process } }
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            onProcessQueue { activeProcesses.removeAll { $0 === process } }
            return ""
        }
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
            onProcessQueue {
                activeProcesses.append(process)
            }
            try process.run()
            process.waitUntilExit()
            onProcessQueue {
                activeProcesses.removeAll { $0 === process }
            }
            return process.terminationStatus
        } catch {
            onProcessQueue {
                activeProcesses.removeAll { $0 === process }
            }
            return -1
        }
    }
}
