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
        /// Fragmented preview MP4 growing on disk; full-quality remux runs in parallel.
        case progressivePreview(preview: URL, fullTarget: URL)
        case failed
    }

    private struct CacheEntry {
        let outputURL: URL
        let sourceIdentity: String
    }

    private static let remuxProfileVersion = "8-chunked-progressive"

    private enum RemuxStrategy: String {
        /// All audio streams + all text subs (slow; many sidecar-like sub tracks).
        case allAudioWithSubs
        /// Stream copy without subtitles.
        case allAudioNoSubs
        /// First audio + first text subtitle (subrip/ass only).
        case firstAudioWithTextSubs
        /// First audio stream only — typical fix for AMZN Atmos MKV with commentary tracks.
        case firstAudioNoSubs
        /// Keep video stream copy; transcode first audio to stereo AAC when stream copy won't decode.
        case firstAudioTranscodeAudio
        /// Fragmented fMP4 with stereo AAC — E-AC-3 cannot be fragmented stream-copied.
        case progressivePreviewStereo
    }

    /// Codecs that need AAC downmix/transcode for native MP4 playback (not E-AC-3 — that stream-copies fine).
    private static let audioTranscodeCodecs: Set<String> = [
        "truehd", "mlp", "dts", "dtshd", "opus", "vorbis",
        "flac", "pcm_s16le", "pcm_s24le", "pcm_f32le"
    ]

    static func probeEmbeddedSubtitleStreams(for inputURL: URL) -> [String] {
        guard isAvailable() else { return [] }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        return parseEmbeddedSubtitleLines(from: stderr)
    }

    private static func parseEmbeddedSubtitleLines(from stderr: String) -> [String] {
        var lines: [String] = []
        for line in stderr.components(separatedBy: .newlines) where line.contains("Subtitle:") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let range = trimmed.range(of: "Subtitle:") {
                lines.append(String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces))
            }
        }
        return lines
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
    private static var activeBackgroundFullRemux: ActiveRemux?
    private static var previewFullTargets: [URL: URL] = [:]
    private static var readyOutputPaths: Set<String> = []
    private static var remuxCache: [String: CacheEntry] = [:]

    /// Minimum bytes before attempting to open a fragmented preview MP4.
    private static let progressivePlayableMinBytes = 64 * 1024

    static func isAvailable() -> Bool {
        run(arguments: ["-version"]) == 0
    }

    /// Reads the primary video stream codec tag from ffmpeg's header probe (stderr).
    static func probePrimaryVideoCodecTag(for inputURL: URL) -> String? {
        guard isAvailable() else { return nil }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        return parseVideoCodecTag(from: stderr)
    }

    static func sourceHasAudioStreams(for inputURL: URL) -> Bool {
        guard isAvailable() else { return true }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        return stderr.contains("Audio:")
    }

    static func probePrimaryAudioCodec(for inputURL: URL) -> String? {
        guard isAvailable() else { return nil }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        return parsePrimaryAudioCodec(from: stderr)
    }

    static func requiresAudioTranscodeForNativePlayback(for inputURL: URL) -> Bool {
        guard let codec = probePrimaryAudioCodec(for: inputURL) else { return false }
        return requiresAudioTranscodeForNativePlayback(codec: codec)
    }

    static func requiresAudioTranscodeForNativePlayback(codec: String) -> Bool {
        let normalized = codec.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        if audioTranscodeCodecs.contains(normalized) { return true }
        return audioTranscodeCodecs.contains(codec.lowercased())
    }

    /// Skip fragmented remux when audio must be transcoded — blocking remux is more reliable.
    static func shouldPreferBlockingRemux(for inputURL: URL) -> Bool {
        guard sourceHasAudioStreams(for: inputURL),
              let codec = probePrimaryAudioCodec(for: inputURL) else { return false }
        return requiresAudioTranscodeForNativePlayback(codec: codec)
    }

    private static func requiresFragmentedAudioTranscode(for inputURL: URL) -> Bool {
        guard let codec = probePrimaryAudioCodec(for: inputURL) else { return false }
        let normalized = codec.lowercased().replacingOccurrences(of: "-", with: "")
        return normalized == "eac3" || normalized == "ec3"
    }

    private static func progressivePreviewStrategy(for inputURL: URL) -> RemuxStrategy {
        if requiresFragmentedAudioTranscode(for: inputURL) {
            return .progressivePreviewStereo
        }
        return .firstAudioNoSubs
    }

    /// Full-quality remux destination paired with an in-flight fragmented preview.
    static func fullRemuxTarget(forPreview previewURL: URL) -> URL? {
        onProcessQueue {
            previewFullTargets[previewURL]
        }
    }

    /// Cheap check — true only after remux process exited successfully (no ffmpeg spawn).
    static func isOutputReadyForPlayback(at url: URL) -> Bool {
        onProcessQueue {
            readyOutputPaths.contains(url.path)
        }
    }

    static func isFullRemuxReady(at fullURL: URL) -> Bool {
        isOutputReadyForPlayback(at: fullURL)
    }

    static func isPreviewRemuxComplete(at previewURL: URL) -> Bool {
        isOutputReadyForPlayback(at: previewURL)
    }

    static func isBackgroundFullRemuxing(outputURL: URL) -> Bool {
        onProcessQueue {
            activeBackgroundFullRemux?.outputURL == outputURL
                && activeBackgroundFullRemux?.process.isRunning == true
        }
    }

    /// Warm the disk cache before the user presses play (library / recents).
    static func prefetchFullRemux(for inputURL: URL) {
        guard isAvailable() else { return }
        guard cachedPlayableURL(for: inputURL) == nil else { return }
        let fullURL = makeOutputURL(for: inputURL)
        guard !isBackgroundFullRemuxing(outputURL: fullURL) else { return }
        if FileManager.default.fileExists(atPath: fullURL.path),
           remuxOutputHasVideoStream(at: fullURL),
           (!sourceHasAudioStreams(for: inputURL) || remuxOutputHasAudioStream(at: fullURL)),
           outputDurationMeetsSource(outputURL: fullURL, inputURL: inputURL) {
            markOutputReadyIfValid(fullURL, inputURL: inputURL)
            storeCache(inputURL: inputURL, outputURL: fullURL)
            return
        }
        if FileManager.default.fileExists(atPath: fullURL.path) {
            try? FileManager.default.removeItem(at: fullURL)
        }
        _ = launchBackgroundFullRemux(inputURL: inputURL, outputURL: fullURL)
    }

    static func probeSourceDurationSec(for inputURL: URL) -> Double? {
        guard isAvailable() else { return nil }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        return parseDurationSec(from: stderr)
    }

    static func remuxOutputDurationSec(at url: URL) -> Double? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", url.path])
        return parseDurationSec(from: stderr)
    }

    private static func parseDurationSec(from stderr: String) -> Double? {
        guard let range = stderr.range(of: "Duration:") else { return nil }
        let after = stderr[range.upperBound...]
        guard let comma = after.firstIndex(of: ",") else { return nil }
        let timeToken = after[..<comma].trimmingCharacters(in: .whitespaces)
        let parts = timeToken.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func remuxOutputHasAudioStream(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", url.path])
        return stderr.contains("Audio:")
    }

    /// MP4 fourcc tag for stream-copy remux (`hvc1` for HEVC, `avc1` for H.264). Wrong tag makes ffmpeg fail.
    static func suggestedVideoTag(for inputURL: URL) -> String? {
        videoRemuxTag(for: inputURL)
    }

    private static func videoRemuxTag(for inputURL: URL) -> String? {
        guard isAvailable() else { return nil }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        return videoRemuxTag(from: stderr)
    }

    private static func videoRemuxTag(from stderr: String) -> String? {
        for line in stderr.components(separatedBy: .newlines) where line.contains("Video:") {
            let lower = line.lowercased()
            if lower.contains("hevc") || lower.contains("h265") || lower.contains("dvhe") || lower.contains("dvh1") {
                return "hvc1"
            }
            if lower.contains("h264") || lower.contains("avc") {
                return "avc1"
            }
        }
        return nil
    }

    private static func appendVideoCopyOptions(to args: inout [String], inputURL: URL, transcodeAudio: Bool) {
        if transcodeAudio {
            args += ["-c:v", "copy"]
        } else {
            args += ["-c", "copy"]
        }
        if let tag = videoRemuxTag(for: inputURL) {
            args += ["-tag:v", tag]
        }
    }

    private static func remuxOutputHasVideoStream(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", url.path])
        return stderr.contains("Video:")
    }

    static func terminateRunningProcesses() {
        onProcessQueue {
            for process in activeProcesses where process.isRunning {
                process.terminate()
            }
            activeProcesses.removeAll()
            activeRemux = nil
            activeBackgroundFullRemux = nil
            previewFullTargets.removeAll()
            readyOutputPaths.removeAll()
        }
    }

    static func cachedPlayableURL(for inputURL: URL) -> URL? {
        let expectingAudio = sourceHasAudioStreams(for: inputURL)
        if let identity = sourceIdentity(for: inputURL) {
            let entry: CacheEntry? = onProcessQueue {
                remuxCache[identity]
            }
            if let entry, entry.sourceIdentity == identity,
               FileManager.default.fileExists(atPath: entry.outputURL.path),
               remuxOutputHasVideoStream(at: entry.outputURL),
               (!expectingAudio || remuxOutputHasAudioStream(at: entry.outputURL)),
               outputDurationMeetsSource(outputURL: entry.outputURL, inputURL: inputURL) {
                markOutputReadyIfValid(entry.outputURL, inputURL: inputURL)
                return entry.outputURL
            }
            if entry != nil {
                _ = onProcessQueue { remuxCache.removeValue(forKey: identity) }
            }
        }

        let outputURL = makeOutputURL(for: inputURL)
        guard FileManager.default.fileExists(atPath: outputURL.path),
              remuxOutputHasVideoStream(at: outputURL),
              (!expectingAudio || remuxOutputHasAudioStream(at: outputURL)),
              outputDurationMeetsSource(outputURL: outputURL, inputURL: inputURL) else {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            return nil
        }
        storeCache(inputURL: inputURL, outputURL: outputURL)
        markOutputReadyIfValid(outputURL, inputURL: inputURL)
        return outputURL
    }

    /// Cache hit returns immediately; otherwise starts preview + parallel full remux.
    static func beginRemux(inputURL: URL) -> RemuxStart {
        if let cached = cachedPlayableURL(for: inputURL) {
            return .cacheHit(cached)
        }
        let fullURL = makeOutputURL(for: inputURL)
        let previewURL = makePreviewOutputURL(for: inputURL)
        _ = launchBackgroundFullRemux(inputURL: inputURL, outputURL: fullURL)
        if launchProgressiveRemux(inputURL: inputURL, previewURL: previewURL, fullTargetURL: fullURL) {
            return .progressivePreview(preview: previewURL, fullTarget: fullURL)
        }
        return .failed
    }

    static func isRemuxing(outputURL: URL) -> Bool {
        onProcessQueue {
            activeRemux?.outputURL == outputURL && activeRemux?.process.isRunning == true
        }
    }

    /// Cheap readiness for fragmented preview — avoids spawning ffmpeg on every poll.
    static func isPreviewReadableEnoughForPlayback(url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size >= progressivePlayableMinBytes else { return false }
        guard fileContainsMOOFAtom(at: url) else { return false }

        let asset = AVURLAsset(url: url)
        if let videoTracks = try? await asset.loadTracks(withMediaType: .video), !videoTracks.isEmpty {
            return true
        }
        if let playable = try? await asset.load(.isPlayable), playable { return true }
        return false
    }

    private static func fileContainsMOOFAtom(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let readLength = min(max(fileSize, 0), 512 * 1024)
        guard readLength > 0 else { return false }
        guard let data = try? handle.read(upToCount: readLength) else { return false }
        return data.range(of: Data("moof".utf8)) != nil
    }

    /// True when fragmented output is large enough for AVPlayer to start with required tracks.
    static func isReadableEnoughForPlayback(url: URL, expectingAudio: Bool) async -> Bool {
        await isPreviewReadableEnoughForPlayback(url: url)
    }

    static func isUsableRemuxOutput(at url: URL, expectingAudio: Bool) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard remuxOutputHasVideoStream(at: url) else { return false }
        if expectingAudio, !remuxOutputHasAudioStream(at: url) { return false }

        let asset = AVURLAsset(url: url)
        if let videoTracks = try? await asset.loadTracks(withMediaType: .video), !videoTracks.isEmpty {
            return true
        }
        return remuxOutputHasVideoStream(at: url)
    }

    /// Blocking remux (safety net / transcode path).
    static func convertToPlayable(inputURL: URL) -> Result? {
        let expectingAudio = sourceHasAudioStreams(for: inputURL)
        if let cached = cachedPlayableURL(for: inputURL),
           remuxOutputHasVideoStream(at: cached),
           (!expectingAudio || remuxOutputHasAudioStream(at: cached)) {
            return Result(outputURL: cached, method: "remux-cache", elapsedMs: 0)
        }
        invalidateCache(for: inputURL)

        let outputURL = makeOutputURL(for: inputURL)
        let start = CFAbsoluteTimeGetCurrent()
        let remuxExit = runRemux(inputURL: inputURL, outputURL: outputURL, fragmented: false)
        if remuxExit == 0,
           FileManager.default.fileExists(atPath: outputURL.path),
           remuxOutputHasVideoStream(at: outputURL),
           (!expectingAudio || remuxOutputHasAudioStream(at: outputURL)) {
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

    private static func fullRemuxStrategy(for inputURL: URL) -> RemuxStrategy {
        if probeFirstTextSubtitleStreamIndex(for: inputURL) != nil {
            return .firstAudioWithTextSubs
        }
        return .firstAudioNoSubs
    }

    private static func outputDurationMeetsSource(
        outputURL: URL,
        inputURL: URL,
        minimumRatio: Double = 0.92
    ) -> Bool {
        guard let sourceDur = probeSourceDurationSec(for: inputURL), sourceDur > 60 else {
            return true
        }
        guard let outputDur = remuxOutputDurationSec(at: outputURL), outputDur > 0 else { return false }
        return outputDur >= sourceDur * minimumRatio
    }

    private static func markOutputReadyIfValid(_ outputURL: URL, inputURL: URL) {
        let expectingAudio = sourceHasAudioStreams(for: inputURL)
        guard remuxOutputHasVideoStream(at: outputURL),
              (!expectingAudio || remuxOutputHasAudioStream(at: outputURL)) else { return }

        let isPreview = outputURL.lastPathComponent.contains("-preview")
        if !isPreview, !outputDurationMeetsSource(outputURL: outputURL, inputURL: inputURL) {
            print("[DEBUG-fallback] remux output too short — not marking ready path=\(outputURL.path)")
            return
        }

        _ = onProcessQueue {
            readyOutputPaths.insert(outputURL.path)
        }
    }

    @discardableResult
    private static func launchBackgroundFullRemux(inputURL: URL, outputURL: URL) -> Bool {
        guard let bundled = BundledCodecTools.ffmpegExecutablePath() else { return false }
        let alreadyRunning = onProcessQueue {
            activeBackgroundFullRemux?.outputURL == outputURL && activeBackgroundFullRemux?.process.isRunning == true
        }
        if alreadyRunning { return true }

        let expectingAudio = sourceHasAudioStreams(for: inputURL)
        if FileManager.default.fileExists(atPath: outputURL.path),
           remuxOutputHasVideoStream(at: outputURL),
           (!expectingAudio || remuxOutputHasAudioStream(at: outputURL)),
           outputDurationMeetsSource(outputURL: outputURL, inputURL: inputURL) {
            markOutputReadyIfValid(outputURL, inputURL: inputURL)
            storeCache(inputURL: inputURL, outputURL: outputURL)
            return true
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bundled)
        let strategy = fullRemuxStrategy(for: inputURL)
        process.arguments = remuxArguments(
            inputURL: inputURL,
            outputURL: outputURL,
            fragmented: false,
            strategy: strategy
        )
        print("[DEBUG-fallback] background full remux strategy=\(strategy.rawValue) output=\(outputURL.path)")
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { finished in
            processQueue.async {
                activeProcesses.removeAll { $0 === finished }
                if activeBackgroundFullRemux?.process === finished {
                    activeBackgroundFullRemux = nil
                }
                if finished.terminationStatus == 0,
                   FileManager.default.fileExists(atPath: outputURL.path) {
                    markOutputReadyIfValid(outputURL, inputURL: inputURL)
                    storeCache(inputURL: inputURL, outputURL: outputURL)
                    print("[DEBUG-fallback] background full remux finished output=\(outputURL.path)")
                } else {
                    print("[DEBUG-fallback] background full remux exit=\(finished.terminationStatus)")
                }
            }
        }

        do {
            try process.run()
            onProcessQueue {
                activeProcesses.append(process)
                activeBackgroundFullRemux = ActiveRemux(process: process, inputURL: inputURL, outputURL: outputURL)
            }
            return true
        } catch {
            print("[DEBUG-fallback] background full remux launch failed: \(error)")
            return false
        }
    }

    private static func launchProgressiveRemux(inputURL: URL, previewURL: URL, fullTargetURL: URL) -> Bool {
        guard let bundled = BundledCodecTools.ffmpegExecutablePath() else { return false }
        if FileManager.default.fileExists(atPath: previewURL.path) {
            try? FileManager.default.removeItem(at: previewURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bundled)
        let strategy = progressivePreviewStrategy(for: inputURL)
        process.arguments = remuxArguments(
            inputURL: inputURL,
            outputURL: previewURL,
            fragmented: true,
            strategy: strategy
        )
        print("[DEBUG-fallback] progressive preview strategy=\(strategy.rawValue) preview=\(previewURL.path)")
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { finished in
            processQueue.async {
                activeProcesses.removeAll { $0 === finished }
                if activeRemux?.process === finished {
                    activeRemux = nil
                }
                if finished.terminationStatus == 0,
                   FileManager.default.fileExists(atPath: previewURL.path) {
                    markOutputReadyIfValid(previewURL, inputURL: inputURL)
                    print("[DEBUG-fallback] progressive preview finished output=\(previewURL.path)")
                } else {
                    print("[DEBUG-fallback] progressive preview exit=\(finished.terminationStatus)")
                }
                previewFullTargets.removeValue(forKey: previewURL)
            }
        }

        do {
            try process.run()
            onProcessQueue {
                activeProcesses.append(process)
                activeRemux = ActiveRemux(process: process, inputURL: inputURL, outputURL: previewURL)
                previewFullTargets[previewURL] = fullTargetURL
            }
            return true
        } catch {
            print("[DEBUG-fallback] progressive preview launch failed: \(error)")
            return false
        }
    }

    private static func remuxArguments(
        inputURL: URL,
        outputURL: URL,
        fragmented: Bool,
        strategy: RemuxStrategy
    ) -> [String] {
        var args = [
            "-y", "-nostdin",
            "-strict", "unofficial",
            "-i", inputURL.path,
            "-map", "0:v:0",
            "-map_chapters", "-1"
        ]

        switch strategy {
        case .allAudioWithSubs, .allAudioNoSubs:
            args += ["-map", "0:a?"]
        case .firstAudioNoSubs, .firstAudioTranscodeAudio, .firstAudioWithTextSubs, .progressivePreviewStereo:
            args += ["-map", "0:a:0?"]
        }

        switch strategy {
        case .firstAudioTranscodeAudio, .progressivePreviewStereo:
            appendVideoCopyOptions(to: &args, inputURL: inputURL, transcodeAudio: true)
            args += ["-c:a", "aac", "-ac", "2", "-b:a", "192k"]
        default:
            appendVideoCopyOptions(to: &args, inputURL: inputURL, transcodeAudio: false)
        }

        switch strategy {
        case .allAudioWithSubs:
            args += ["-map", "0:s?", "-c:s", "mov_text"]
        case .firstAudioWithTextSubs:
            if let subIndex = probeFirstTextSubtitleStreamIndex(for: inputURL) {
                args += ["-map", "0:s:\(subIndex)", "-c:s", "mov_text"]
            }
        default:
            break
        }

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
            "-strict", "unofficial",
            "-i", inputURL.path,
            "-map", "0:v:0",
            "-map", "0:a:0?",
            "-map", "0:s:0?",
            "-map_chapters", "-1",
            "-threads", "2",
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-ac", "2",
            "-c:s", "mov_text",
            "-movflags", "+faststart",
            outputURL.path
        ]
    }

    @discardableResult
    private static func runRemux(inputURL: URL, outputURL: URL, fragmented: Bool) -> Int32 {
        var strategies: [RemuxStrategy] = [
            .firstAudioWithTextSubs,
            .firstAudioNoSubs,
            .allAudioNoSubs,
            .firstAudioTranscodeAudio,
            .allAudioWithSubs
        ]
        if requiresAudioTranscodeForNativePlayback(for: inputURL) {
            strategies = [.firstAudioTranscodeAudio, .firstAudioWithTextSubs, .firstAudioNoSubs, .allAudioNoSubs]
        }
        var lastExit: Int32 = -1
        var lastStderr = ""
        for strategy in strategies {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            let result = runCapturingExit(
                arguments: remuxArguments(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    fragmented: fragmented,
                    strategy: strategy
                )
            )
            lastExit = result.exit
            if !result.stderr.isEmpty {
                lastStderr = result.stderr
            }
            if result.exit == 0, FileManager.default.fileExists(atPath: outputURL.path) {
                let expectingAudio = sourceHasAudioStreams(for: inputURL)
                let hasVideo = remuxOutputHasVideoStream(at: outputURL)
                let hasAudio = !expectingAudio || remuxOutputHasAudioStream(at: outputURL)
                if hasVideo && hasAudio {
                    print("[DEBUG-fallback] remux succeeded with strategy=\(strategy.rawValue)")
                    return 0
                }
                print("[DEBUG-fallback] remux exit 0 but output incomplete, trying next strategy")
            }
        }
        if !lastStderr.isEmpty {
            let tail = lastStderr.suffix(1200)
            print("[DEBUG-fallback] remux failed strategies=\(strategies.map(\.rawValue).joined(separator: ",")) stderr=\(tail)")
        }
        return lastExit
    }

    private struct CommandResult {
        let exit: Int32
        let stderr: String
    }

    private static func runCapturingExit(arguments: [String]) -> CommandResult {
        guard let bundled = BundledCodecTools.ffmpegExecutablePath() else {
            return CommandResult(exit: -1, stderr: "ffmpeg not bundled")
        }
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
            let stderr = String(data: data, encoding: .utf8) ?? ""
            return CommandResult(exit: process.terminationStatus, stderr: stderr)
        } catch {
            onProcessQueue { activeProcesses.removeAll { $0 === process } }
            return CommandResult(exit: -1, stderr: error.localizedDescription)
        }
    }

    private static func invalidateCache(for inputURL: URL) {
        guard let identity = sourceIdentity(for: inputURL) else { return }
        _ = onProcessQueue {
            remuxCache.removeValue(forKey: identity)
        }
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
        return "\(remuxProfileVersion)|\(inputURL.path)|\(mod)|\(size)"
    }

    private static func makeOutputURL(for inputURL: URL) -> URL {
        makeDerivedOutputURL(for: inputURL, suffix: "")
    }

    private static func makePreviewOutputURL(for inputURL: URL) -> URL {
        makeDerivedOutputURL(for: inputURL, suffix: "-preview")
    }

    private static func makeDerivedOutputURL(for inputURL: URL, suffix: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("LaughPlayerFallback", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let base = inputURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
        let identity = sourceIdentity(for: inputURL) ?? inputURL.path
        let digest = SHA256.hash(data: Data(identity.utf8))
        let hash = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return tempDir.appendingPathComponent("\(base)\(suffix)-\(hash).mp4")
    }

    private static func parsePrimaryAudioCodec(from stderr: String) -> String? {
        for line in stderr.components(separatedBy: .newlines) where line.contains("Audio:") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let audioRange = trimmed.range(of: "Audio:") else { continue }
            let after = trimmed[audioRange.upperBound...]
            let codecToken = after.split(separator: ",").first.map(String.init) ?? ""
            let codec = codecToken.trimmingCharacters(in: .whitespaces)
            if !codec.isEmpty { return codec.lowercased() }
        }
        return nil
    }

    private static let textSubtitleCodecs: Set<String> = [
        "subrip", "srt", "ass", "ssa", "mov_text", "webvtt", "text"
    ]

    private static func probeFirstTextSubtitleStreamIndex(for inputURL: URL) -> Int? {
        guard isAvailable() else { return nil }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        var subIndex = -1
        for line in stderr.components(separatedBy: .newlines) {
            if line.contains("Subtitle:") {
                subIndex += 1
                let lower = line.lowercased()
                if textSubtitleCodecs.contains(where: { lower.contains($0) }) {
                    return subIndex
                }
            }
        }
        return nil
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
