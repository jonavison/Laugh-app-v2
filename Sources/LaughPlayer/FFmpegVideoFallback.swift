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

    private static let remuxProfileVersion = "14-sparse-source-not-size"

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

        init(_ open: RemuxOpenStrategy) {
            switch open {
            case .allAudioWithSubs: self = .allAudioWithSubs
            case .allAudioNoSubs: self = .allAudioNoSubs
            case .firstAudioWithTextSubs: self = .firstAudioWithTextSubs
            case .firstAudioNoSubs: self = .firstAudioNoSubs
            case .firstAudioTranscodeAudio: self = .firstAudioTranscodeAudio
            case .progressivePreviewStereo: self = .progressivePreviewStereo
            }
        }
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
    private static let availabilityLock = NSLock()
    private static var cachedAvailability: Bool?

    /// Probe ffmpeg once on a background queue so opening media never blocks the main thread.
    static func warmAvailabilityCache() {
        processQueue.async {
            _ = isAvailable()
        }
    }

    /// Cap `LaughPlayerFallback` size in the background (LRU; previews first).
    static func enforceRemuxCacheBudget(protecting urls: [URL] = []) {
        let protect = Set(urls.map { $0.standardizedFileURL.path })
        DispatchQueue.global(qos: .utility).async {
            let report = RemuxCacheEviction.enforceBudget(protectPaths: protect)
            guard report.deletedCount > 0 else { return }
            let freedGB = Double(report.deletedBytes) / (1024 * 1024 * 1024)
            PlaybackTrace.emit(String(
                format: "[DEBUG-fallback] remux cache eviction deleted=%d freed=%.2fGiB remaining=%.2fGiB",
                report.deletedCount,
                freedGB,
                Double(report.remainingBytes) / (1024 * 1024 * 1024)
            ))
        }
    }

    static func isAvailable() -> Bool {
        availabilityLock.lock()
        if let cachedAvailability {
            availabilityLock.unlock()
            return cachedAvailability
        }
        availabilityLock.unlock()

        let available: Bool
        if DispatchQueue.getSpecific(key: processQueueKey) != nil {
            available = probeAvailabilityUnlocked()
        } else {
            available = onProcessQueue {
                probeAvailabilityUnlocked()
            }
        }

        availabilityLock.lock()
        cachedAvailability = available
        availabilityLock.unlock()
        return available
    }

    private static func probeAvailabilityUnlocked() -> Bool {
        guard BundledCodecTools.ffmpegExecutablePath() != nil else { return false }
        return runUnlocked(arguments: ["-version"]) == 0
    }

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
    /// Set when a remux completed but fps/payload looked like an incomplete torrent rip.
    private static var lastFailureIndicatesIncomplete = false

    /// True when the most recent remux rejection was sparse/incomplete (not a generic ffmpeg fail).
    static func consumeIncompleteRemuxFailure() -> Bool {
        onProcessQueue {
            let value = lastFailureIndicatesIncomplete
            lastFailureIndicatesIncomplete = false
            return value
        }
    }

    private static func noteIncompleteRemuxFailure() {
        _ = onProcessQueue { lastFailureIndicatesIncomplete = true }
    }

    /// Reads the primary video stream codec tag from ffmpeg's header probe (stderr).
    static func probePrimaryVideoCodecTag(for inputURL: URL) -> String? {
        guard isAvailable() else { return nil }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        return FFmpegProbeParser.parse(stderr).videoCodecTag
    }

    static func sourceHasAudioStreams(for inputURL: URL) -> Bool {
        guard isAvailable() else { return true }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        return FFmpegProbeParser.parse(stderr).hasAudio
    }

    static func probePrimaryAudioCodec(for inputURL: URL) -> String? {
        guard isAvailable() else { return nil }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        return FFmpegProbeParser.parse(stderr).audioCodec
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
        guard isAvailable() else { return false }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        let summary = FFmpegProbeParser.parse(stderr)
        guard let codec = summary.audioCodec else { return false }
        return requiresAudioTranscodeForNativePlayback(codec: codec)
    }

    private static func requiresFragmentedAudioTranscode(for inputURL: URL) -> Bool {
        FFmpegProbeParser.needsFragmentedAudioTranscode(audioCodec: probePrimaryAudioCodec(for: inputURL))
    }

    /// Fragmented AC-3/E-AC-3 preview transcodes the *whole* soundtrack to AAC.
    /// For a 2h rip that is slower than waiting for stream-copy remux, and fights the full remux for disk.
    static func shouldSkipProgressivePreview(audioCodec: String?) -> Bool {
        FFmpegProbeParser.needsFragmentedAudioTranscode(audioCodec: audioCodec)
    }

    private static func progressivePreviewStrategy(for inputURL: URL) -> RemuxStrategy {
        RemuxStrategy(RemuxOpenStrategy.progressive(
            needsAudioTranscode: requiresFragmentedAudioTranscode(for: inputURL)
        ))
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

    /// Disk/cache lookup only — never spawns ffmpeg (safe on the main thread).
    /// Still refuses sparse sources and clears ready-flags for missing files.
    static func knownCachedPlayableURL(for inputURL: URL) -> URL? {
        guard sourceReadyForFullRemux(inputURL) else { return nil }
        if let identity = sourceIdentity(for: inputURL) {
            let cachedURL: URL? = onProcessQueue {
                remuxCache[identity]?.outputURL
            }
            if let cachedURL,
               FileManager.default.fileExists(atPath: cachedURL.path),
               isOutputReadyForPlayback(at: cachedURL) {
                return cachedURL
            }
        }
        let outputURL = makeOutputURL(for: inputURL)
        guard FileManager.default.fileExists(atPath: outputURL.path),
              isOutputReadyForPlayback(at: outputURL) else {
            return nil
        }
        return outputURL
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

    /// Waits for a subprocess without pumping the AppKit run loop (`waitUntilExit` re-enters layout).
    private static func waitForTermination(of process: Process) -> Int32 {
        if !process.isRunning {
            return process.terminationStatus
        }
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }
        if process.isRunning {
            semaphore.wait()
        }
        process.terminationHandler = nil
        return process.terminationStatus
    }

    /// Warm the disk cache before the user presses play (library / recents).
    static func prefetchFullRemux(for inputURL: URL) {
        processQueue.async {
            guard isAvailable() else { return }
            guard sourceReadyForFullRemux(inputURL) else { return }
            guard cachedPlayableURL(for: inputURL) == nil else { return }
            let fullURL = makeOutputURL(for: inputURL)
            guard !isBackgroundFullRemuxing(outputURL: fullURL) else { return }
            if FileManager.default.fileExists(atPath: fullURL.path),
               remuxOutputHasVideoStream(at: fullURL),
               (!sourceHasAudioStreams(for: inputURL) || remuxOutputHasAudioStream(at: fullURL)),
               outputLooksHealthy(outputURL: fullURL, inputURL: inputURL) {
                markOutputReadyIfValid(fullURL, inputURL: inputURL)
                storeCache(inputURL: inputURL, outputURL: fullURL)
                return
            }
            if FileManager.default.fileExists(atPath: fullURL.path) {
                try? FileManager.default.removeItem(at: fullURL)
            }
            _ = launchBackgroundFullRemux(inputURL: inputURL, outputURL: fullURL)
        }
    }

    static func probeSourceDurationSec(for inputURL: URL) -> Double? {
        guard isAvailable() else { return nil }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        let summary = FFmpegProbeParser.parse(stderr)
        PlaybackTrace.emit("[DEBUG-format] \(summary.logLine) file=\(inputURL.lastPathComponent)")
        return summary.durationSec
    }

    /// True when the source only has PGS/VobSub-style bitmap subs (IINA shows them; remux cannot).
    static func sourceHasBitmapSubtitlesOnly(at inputURL: URL) -> Bool {
        let codecs = probeSubtitleCodecs(for: inputURL)
        return FFmpegProbeParser.hasBitmapSubtitlesOnly(codecs: codecs)
    }

    static func probeSubtitleCodecs(for inputURL: URL) -> [String] {
        guard isAvailable() else { return [] }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        return FFmpegProbeParser.parseSubtitleCodecs(from: stderr)
    }

    static func probeSubtitleStreams(for inputURL: URL) -> [FFmpegSubtitleStream] {
        guard isAvailable() else { return [] }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        return FFmpegProbeParser.parseSubtitleStreams(from: stderr)
    }

    static func remuxOutputDurationSec(at url: URL) -> Double? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", url.path])
        return FFmpegProbeParser.parse(stderr).durationSec
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
        guard sourceReadyForFullRemux(inputURL) else { return nil }
        let expectingAudio = sourceHasAudioStreams(for: inputURL)
        if let identity = sourceIdentity(for: inputURL) {
            let entry: CacheEntry? = onProcessQueue {
                remuxCache[identity]
            }
            if let entry, entry.sourceIdentity == identity,
               FileManager.default.fileExists(atPath: entry.outputURL.path),
               remuxOutputHasVideoStream(at: entry.outputURL),
               (!expectingAudio || remuxOutputHasAudioStream(at: entry.outputURL)),
               outputLooksHealthy(outputURL: entry.outputURL, inputURL: inputURL) {
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
              outputLooksHealthy(outputURL: outputURL, inputURL: inputURL) else {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            return nil
        }
        storeCache(inputURL: inputURL, outputURL: outputURL)
        markOutputReadyIfValid(outputURL, inputURL: inputURL)
        return outputURL
    }

    /// Cache hit returns immediately; otherwise starts progressive preview only.
    /// Full remux runs after preview attaches (see PlayerViewController) so two ffmpeg
    /// processes are not stream-copying the same 4K source at once.
    static func beginRemux(inputURL: URL) -> RemuxStart {
        guard sourceReadyForRemux(inputURL) else {
            PlaybackTrace.emit(
                "[DEBUG-fallback] refuse remux — unreadable header path=\(inputURL.lastPathComponent)"
            )
            return .failed
        }
        let fullyReady = sourceReadyForFullRemux(inputURL)
        if fullyReady, let cached = cachedPlayableURL(for: inputURL) {
            return .cacheHit(cached)
        }
        let fullURL = makeOutputURL(for: inputURL)
        let previewURL = makePreviewOutputURL(for: inputURL)
        let skipPreview = shouldSkipProgressivePreview(audioCodec: probePrimaryAudioCodec(for: inputURL))
        if skipPreview {
            guard fullyReady else {
                PlaybackTrace.emit(
                    "[DEBUG-fallback] refuse full-only remux while source still downloading path=\(inputURL.lastPathComponent)"
                )
                return .failed
            }
            PlaybackTrace.emit("[DEBUG-fallback] skip progressive preview (would transcode full-length audio) input=\(inputURL.lastPathComponent)")
            _ = launchBackgroundFullRemux(inputURL: inputURL, outputURL: fullURL)
            if waitUntilBackgroundFullRemuxReady(outputURL: fullURL, timeoutSec: 180) {
                storeCache(inputURL: inputURL, outputURL: fullURL)
                return .cacheHit(fullURL)
            }
            return .failed
        }
        if launchProgressiveRemux(inputURL: inputURL, previewURL: previewURL, fullTargetURL: fullURL) {
            return .progressivePreview(preview: previewURL, fullTarget: fullURL)
        }
        guard fullyReady else { return .failed }
        _ = launchBackgroundFullRemux(inputURL: inputURL, outputURL: fullURL)
        if waitUntilBackgroundFullRemuxReady(outputURL: fullURL, timeoutSec: 180) {
            storeCache(inputURL: inputURL, outputURL: fullURL)
            return .cacheHit(fullURL)
        }
        return .failed
    }

    /// Start the full seekable remux once progressive playback is already on screen.
    @discardableResult
    static func ensureBackgroundFullRemux(inputURL: URL, outputURL: URL) -> Bool {
        launchBackgroundFullRemux(inputURL: inputURL, outputURL: outputURL)
    }

    private static func waitUntilBackgroundFullRemuxReady(outputURL: URL, timeoutSec: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSec)
        while Date() < deadline {
            if isOutputReadyForPlayback(at: outputURL) {
                return true
            }
            let stillRunning = onProcessQueue {
                if activeBackgroundFullRemux?.outputURL == outputURL
                    && activeBackgroundFullRemux?.process.isRunning == true {
                    return true
                }
                return activeProcesses.contains { process in
                    guard process.isRunning else { return false }
                    return (process.arguments ?? []).last == outputURL.path
                }
            }
            if !stillRunning {
                return isOutputReadyForPlayback(at: outputURL)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return isOutputReadyForPlayback(at: outputURL)
    }

    static func isRemuxing(outputURL: URL) -> Bool {
        onProcessQueue {
            activeRemux?.outputURL == outputURL && activeRemux?.process.isRunning == true
        }
    }

    /// Sparse remuxes (incomplete torrent) report avg fps ≪ tbr with a full duration header.
    /// Playing them freezes the picture while the clock keeps advancing.
    static func remuxLooksTooSparseForPlayback(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        return !outputFrameRateLooksComplete(outputURL: url)
    }

    /// Cheap readiness for fragmented preview — avoids spawning ffmpeg on every poll.
    /// Byte-level moof readiness is enough to attach: waiting for AVAsset track probes on a
    /// still-growing 4K HEVC fMP4 routinely stalls until the remux finishes (20–30s), which
    /// defeats progressive preview entirely.
    static func isPreviewReadableEnoughForPlayback(url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if FFmpegProbeParser.isPreviewByteReady(
            fileSize: size,
            containsMOOF: fileContainsMOOFAtom(at: url)
        ) {
            return true
        }
        // Incomplete torrent remuxes can finish with a large fMP4 before every poll saw `moof`
        // in the first 512KB (writer flush). A multi-MB file is enough to try attaching.
        return size >= 2 * 1024 * 1024
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

        // Prefer waiting for an in-flight background remux over launching competing
        // strategy retries that delete the same output path mid-write.
        if isBackgroundFullRemuxing(outputURL: outputURL)
            || launchBackgroundFullRemux(inputURL: inputURL, outputURL: outputURL) {
            if waitUntilBackgroundFullRemuxReady(outputURL: outputURL, timeoutSec: 180),
               FileManager.default.fileExists(atPath: outputURL.path),
               remuxOutputHasVideoStream(at: outputURL),
               (!expectingAudio || remuxOutputHasAudioStream(at: outputURL)),
               outputLooksHealthy(outputURL: outputURL, inputURL: inputURL) {
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
                storeCache(inputURL: inputURL, outputURL: outputURL)
                return Result(outputURL: outputURL, method: "remux", elapsedMs: elapsedMs)
            }
        }

        let remuxExit = runRemux(inputURL: inputURL, outputURL: outputURL, fragmented: false)
        if remuxExit == 0,
           FileManager.default.fileExists(atPath: outputURL.path),
           remuxOutputHasVideoStream(at: outputURL),
           (!expectingAudio || remuxOutputHasAudioStream(at: outputURL)),
           outputLooksHealthy(outputURL: outputURL, inputURL: inputURL) {
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
        let includeTextSubs = !probeTextSubtitleStreamIndices(for: inputURL).isEmpty
        return RemuxStrategy(RemuxOpenStrategy.full(
            needsAudioTranscode: requiresAudioTranscodeForNativePlayback(for: inputURL),
            includeTextSubs: includeTextSubs
        ))
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

    /// Reject sparse remuxes that declare a full duration but only copied a fraction of bytes
    /// (classic still-downloading torrent / aborted remux). Those freeze on seek.
    private static func outputPayloadMeetsSource(outputURL: URL, inputURL: URL) -> Bool {
        let sourceBytes = (try? inputURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let outputBytes = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let ok = FFmpegProbeParser.remuxPayloadLooksComplete(
            outputBytes: outputBytes,
            sourceBytes: sourceBytes
        )
        if !ok {
            noteIncompleteRemuxFailure()
            PlaybackTrace.emit(
                "[DEBUG-fallback] remux payload too small outputBytes=\(outputBytes) sourceBytes=\(sourceBytes) path=\(outputURL.lastPathComponent)"
            )
        }
        return ok
    }

    private static func outputLooksHealthy(outputURL: URL, inputURL: URL) -> Bool {
        outputDurationMeetsSource(outputURL: outputURL, inputURL: inputURL)
            && outputPayloadMeetsSource(outputURL: outputURL, inputURL: inputURL)
            && outputFrameRateLooksComplete(outputURL: outputURL)
    }

    /// Sparse remuxes often report avg fps ≪ tbr while duration metadata still looks full.
    private static func outputFrameRateLooksComplete(outputURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: outputURL.path) else { return false }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", outputURL.path])
        let average = FFmpegProbeParser.parseVideoAverageFps(from: stderr)
        let container = FFmpegProbeParser.parseVideoContainerFps(from: stderr)
        let ok = FFmpegProbeParser.remuxFrameRateLooksComplete(
            averageFps: average,
            containerFps: container
        )
        if !ok {
            noteIncompleteRemuxFailure()
            PlaybackTrace.emit(
                "[DEBUG-fallback] remux fps sparse avg=\(average.map { String(format: "%.2f", $0) } ?? "nil") tbr=\(container.map { String(format: "%.2f", $0) } ?? "nil") path=\(outputURL.lastPathComponent)"
            )
        }
        return ok
    }

    private static func markOutputReadyIfValid(_ outputURL: URL, inputURL: URL) {
        let isPreview = outputURL.lastPathComponent.contains("-preview")
        if isPreview {
            let size = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            // Don't spawn ffmpeg probes on a sparse/incomplete preview — byte presence is enough.
            guard size >= 64 * 1024 else { return }
            _ = onProcessQueue {
                readyOutputPaths.insert(outputURL.path)
            }
            return
        }

        let expectingAudio = sourceHasAudioStreams(for: inputURL)
        guard remuxOutputHasVideoStream(at: outputURL),
              (!expectingAudio || remuxOutputHasAudioStream(at: outputURL)) else { return }

        if !outputLooksHealthy(outputURL: outputURL, inputURL: inputURL) {
            PlaybackTrace.emit("[DEBUG-fallback] remux output unhealthy — not marking ready path=\(outputURL.path)")
            try? FileManager.default.removeItem(at: outputURL)
            return
        }

        _ = onProcessQueue {
            readyOutputPaths.insert(outputURL.path)
        }
    }

    /// Readable header is enough to attempt progressive remux. Full remux cache requires
    /// a materialized source (see `sourceReadyForFullRemux`).
    private static func sourceReadyForRemux(_ inputURL: URL) -> Bool {
        !IncompleteMediaProbe.looksLikeUnreadableContainer(at: inputURL)
    }

    private static func sourceReadyForFullRemux(_ inputURL: URL) -> Bool {
        sourceReadyForRemux(inputURL)
            && !IncompleteMediaProbe.looksLikeIncompleteDownload(at: inputURL)
    }

    @discardableResult
    private static func launchBackgroundFullRemux(inputURL: URL, outputURL: URL) -> Bool {
        guard sourceReadyForFullRemux(inputURL) else {
            PlaybackTrace.emit(
                "[DEBUG-fallback] skip background remux — source still downloading path=\(inputURL.lastPathComponent)"
            )
            return false
        }
        guard let bundled = BundledCodecTools.ffmpegExecutablePath() else { return false }
        let alreadyRunning = onProcessQueue {
            activeBackgroundFullRemux?.outputURL == outputURL && activeBackgroundFullRemux?.process.isRunning == true
        }
        if alreadyRunning { return true }

        // Another ffmpeg (blocking strategy remux, leftover process) may already be
        // writing this path — do not delete mid-write or we thrash for 30s+.
        let writingSamePath = onProcessQueue {
            activeProcesses.contains { process in
                guard process.isRunning else { return false }
                let args = process.arguments ?? []
                return args.last == outputURL.path
            }
        }
        if writingSamePath {
            PlaybackTrace.emit("[DEBUG-fallback] background remux deferred — output already being written path=\(outputURL.lastPathComponent)")
            return true
        }

        let expectingAudio = sourceHasAudioStreams(for: inputURL)
        if FileManager.default.fileExists(atPath: outputURL.path),
           remuxOutputHasVideoStream(at: outputURL),
           (!expectingAudio || remuxOutputHasAudioStream(at: outputURL)),
           outputLooksHealthy(outputURL: outputURL, inputURL: inputURL) {
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
        PlaybackTrace.emit("[DEBUG-fallback] background full remux strategy=\(strategy.rawValue) output=\(outputURL.path)")
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
                    PlaybackTrace.emit("[DEBUG-fallback] background full remux finished output=\(outputURL.path)")
                } else {
                    PlaybackTrace.emit("[DEBUG-fallback] background full remux exit=\(finished.terminationStatus)")
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
            PlaybackTrace.emit("[DEBUG-fallback] background full remux launch failed: \(error)")
            return false
        }
    }

    private static func launchProgressiveRemux(inputURL: URL, previewURL: URL, fullTargetURL: URL) -> Bool {
        guard sourceReadyForRemux(inputURL) else { return false }
        guard let bundled = BundledCodecTools.ffmpegExecutablePath() else { return false }

        let incomplete = IncompleteMediaProbe.looksLikeIncompleteDownload(at: inputURL)
        let durationCap = progressiveRemuxDurationCapSec(for: inputURL)
        if incomplete, durationCap == nil {
            PlaybackTrace.emit(
                "[DEBUG-fallback] refuse progressive preview — no contiguous head yet path=\(inputURL.lastPathComponent)"
            )
            return false
        }

        // Reuse only finished *dense* previews of complete sources. Incomplete downloads must
        // never reuse an older full-duration sparse remux (clock advances, picture freezes).
        if FileManager.default.fileExists(atPath: previewURL.path) {
            if incomplete {
                PlaybackTrace.emit(
                    "[DEBUG-fallback] discard stale progressive preview (source still downloading) path=\(previewURL.lastPathComponent)"
                )
                try? FileManager.default.removeItem(at: previewURL)
            } else {
                let size = (try? previewURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                let byteReady = size >= 2 * 1024 * 1024
                    || FFmpegProbeParser.isPreviewByteReady(
                        fileSize: size,
                        containsMOOF: fileContainsMOOFAtom(at: previewURL)
                    )
                if byteReady, !remuxLooksTooSparseForPlayback(at: previewURL) {
                    markOutputReadyIfValid(previewURL, inputURL: inputURL)
                    _ = onProcessQueue {
                        previewFullTargets[previewURL] = fullTargetURL
                    }
                    PlaybackTrace.emit(
                        "[DEBUG-fallback] reuse progressive preview bytes=\(size) path=\(previewURL.lastPathComponent)"
                    )
                    return true
                }
                try? FileManager.default.removeItem(at: previewURL)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bundled)
        let strategy = progressivePreviewStrategy(for: inputURL)
        process.arguments = remuxArguments(
            inputURL: inputURL,
            outputURL: previewURL,
            fragmented: true,
            strategy: strategy,
            maxDurationSec: durationCap
        )
        if let durationCap {
            PlaybackTrace.emit(String(
                format: "[DEBUG-fallback] progressive preview strategy=%@ cap=%.1fs preview=%@",
                strategy.rawValue,
                durationCap,
                previewURL.path
            ))
        } else {
            PlaybackTrace.emit("[DEBUG-fallback] progressive preview strategy=\(strategy.rawValue) preview=\(previewURL.path)")
        }
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
                    PlaybackTrace.emit("[DEBUG-fallback] progressive preview finished output=\(previewURL.path)")
                } else {
                    PlaybackTrace.emit("[DEBUG-fallback] progressive preview exit=\(finished.terminationStatus)")
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
            PlaybackTrace.emit("[DEBUG-fallback] progressive preview launch failed: \(error)")
            return false
        }
    }

    /// Cap progressive remux to the contiguous downloaded head so the MP4 timeline has no holes.
    private static func progressiveRemuxDurationCapSec(for inputURL: URL) -> Double? {
        guard IncompleteMediaProbe.looksLikeIncompleteDownload(at: inputURL) else { return nil }
        let head = IncompleteMediaProbe.contiguousHeadFraction(at: inputURL)
        guard head >= 0.02 else { return nil }
        guard let duration = probeSourceDurationSec(for: inputURL), duration.isFinite, duration > 1 else {
            return nil
        }
        return max(15, duration * head * 0.90)
    }

    private static func remuxArguments(
        inputURL: URL,
        outputURL: URL,
        fragmented: Bool,
        strategy: RemuxStrategy,
        maxDurationSec: Double? = nil
    ) -> [String] {
        var args = [
            "-y", "-nostdin",
            "-strict", "unofficial",
            "-i", inputURL.path,
            "-map", "0:v:0",
            "-map_chapters", "-1"
        ]

        if let maxDurationSec, maxDurationSec.isFinite, maxDurationSec > 1 {
            args += ["-t", String(format: "%.3f", maxDurationSec)]
        }

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
            for subIndex in probeTextSubtitleStreamIndices(for: inputURL) {
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
        let strategies = RemuxOpenStrategy.blockingOrder(
            needsAudioTranscode: requiresAudioTranscodeForNativePlayback(for: inputURL)
        ).map(RemuxStrategy.init)
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
                if hasVideo && hasAudio && outputLooksHealthy(outputURL: outputURL, inputURL: inputURL) {
                    PlaybackTrace.emit("[DEBUG-fallback] remux succeeded with strategy=\(strategy.rawValue)")
                    return 0
                }
                // Stream-copy strategies that map fewer streams cannot grow the payload.
                // Retrying all of them just burns 30s on the same sparse/partial output.
                let sparsePayload = !outputPayloadMeetsSource(outputURL: outputURL, inputURL: inputURL)
                let sparseFps = !outputFrameRateLooksComplete(outputURL: outputURL)
                if hasVideo && hasAudio && (sparsePayload || sparseFps) {
                    PlaybackTrace.emit(
                        "[DEBUG-fallback] remux exit 0 but output sparse — stopping strategy retries strategy=\(strategy.rawValue)"
                    )
                    break
                }
                PlaybackTrace.emit("[DEBUG-fallback] remux exit 0 but output incomplete, trying next strategy")
            }
        }
        if !lastStderr.isEmpty {
            let tail = lastStderr.suffix(1200)
            PlaybackTrace.emit("[DEBUG-fallback] remux failed strategies=\(strategies.map(\.rawValue).joined(separator: ",")) stderr=\(tail)")
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
            let exit = waitForTermination(of: process)
            onProcessQueue { activeProcesses.removeAll { $0 === process } }
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: data, encoding: .utf8) ?? ""
            return CommandResult(exit: exit, stderr: stderr)
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
        enforceRemuxCacheBudget(protecting: [outputURL])
    }

    private static func sourceIdentity(for inputURL: URL) -> String? {
        // Path + logical size only. Sparse mid-download is blocked by
        // `sourceReadyForRemux` (allocated-size probe), not by cache identity — including
        // allocated bytes here churned the output path on every piece and forced remuxes.
        guard let values = try? inputURL.resourceValues(forKeys: [.fileSizeKey]) else {
            return inputURL.path
        }
        let size = values.fileSize ?? 0
        return "\(remuxProfileVersion)|\(inputURL.path)|\(size)"
    }

    private static func makeOutputURL(for inputURL: URL) -> URL {
        makeDerivedOutputURL(for: inputURL, suffix: "")
    }

    private static func makePreviewOutputURL(for inputURL: URL) -> URL {
        makeDerivedOutputURL(for: inputURL, suffix: "-preview")
    }

    private static func makeDerivedOutputURL(for inputURL: URL, suffix: String) -> URL {
        let tempDir = RemuxCacheEviction.cacheDirectory()
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let base = inputURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
        let identity = sourceIdentity(for: inputURL) ?? inputURL.path
        let digest = SHA256.hash(data: Data(identity.utf8))
        let hash = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return tempDir.appendingPathComponent("\(base)\(suffix)-\(hash).mp4")
    }

    private static let textSubtitleCodecs: Set<String> = [
        "subrip", "srt", "ass", "ssa", "mov_text", "webvtt", "text"
    ]

    private static func probeTextSubtitleStreamIndices(for inputURL: URL) -> [Int] {
        guard isAvailable() else { return [] }
        let stderr = runCapturingStderr(arguments: ["-hide_banner", "-i", inputURL.path])
        var indices: [Int] = []
        var subIndex = -1
        for line in stderr.components(separatedBy: .newlines) {
            if line.contains("Subtitle:") {
                subIndex += 1
                let lower = line.lowercased()
                if textSubtitleCodecs.contains(where: { lower.contains($0) }) {
                    indices.append(subIndex)
                }
            }
        }
        return indices
    }

    private static func probeFirstTextSubtitleStreamIndex(for inputURL: URL) -> Int? {
        probeTextSubtitleStreamIndices(for: inputURL).first
    }

    private static func runCapturingStderrUnlocked(arguments: [String]) -> String {
        guard let bundled = BundledCodecTools.ffmpegExecutablePath() else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bundled)
        process.arguments = arguments
        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe
        do {
            activeProcesses.append(process)
            try process.run()
            _ = waitForTermination(of: process)
            activeProcesses.removeAll { $0 === process }
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            activeProcesses.removeAll { $0 === process }
            return ""
        }
    }

    private static func runCapturingStderr(arguments: [String]) -> String {
        if DispatchQueue.getSpecific(key: processQueueKey) != nil {
            return runCapturingStderrUnlocked(arguments: arguments)
        }
        return onProcessQueue {
            runCapturingStderrUnlocked(arguments: arguments)
        }
    }

    @discardableResult
    private static func runUnlocked(arguments: [String]) -> Int32 {
        guard let bundled = BundledCodecTools.ffmpegExecutablePath() else {
            return -1
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bundled)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            activeProcesses.append(process)
            try process.run()
            let exit = waitForTermination(of: process)
            activeProcesses.removeAll { $0 === process }
            return exit
        } catch {
            activeProcesses.removeAll { $0 === process }
            return -1
        }
    }

    @discardableResult
    private static func run(arguments: [String]) -> Int32 {
        if DispatchQueue.getSpecific(key: processQueueKey) != nil {
            return runUnlocked(arguments: arguments)
        }
        return onProcessQueue {
            runUnlocked(arguments: arguments)
        }
    }
}
