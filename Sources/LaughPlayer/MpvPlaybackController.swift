import AppKit
import Foundation
import LibmpvEmbed

/// In-process libmpv. macOS mpv 0.41 dropped `--wid`; cocoa-cb always opens its own window.
final class MpvPlaybackController: @unchecked Sendable {
    enum LoadResult: Equatable {
        case success
        case failed(String)
    }

    /// Options that keep video inside LaughPlayer (libmpv render API, no cocoa-cb window).
    static let inProcessOptions: [(String, String)] = [
        ("config", "no"),
        ("terminal", "no"),
        ("vo", "libmpv"),
        ("force-window", "no"),
        ("osc", "no"),
        ("osd-level", "0"),
        ("keep-open", "yes"),
        ("idle", "yes"),
        ("hwdec", "auto-copy"),
        ("stop-screensaver", "yes"),
        ("sub-auto", "no"),
        ("sub-visibility", "yes"),
        ("input-default-bindings", "no"),
        ("input-vo-keyboard", "no"),
        ("audio-display", "no"),
        ("vd-lavc-dr", "no")
    ]

    var onTimeUpdate: ((Double, Double) -> Void)?
    var onPauseChanged: ((Bool) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onReady: (() -> Void)?

    private var embed: OpaquePointer?
    private weak var renderLayer: MpvOpenGLLayer?
    private let ipcQueue = DispatchQueue(label: "mpv-embed")
    private var isReady = false
    private var lastDuration: Double = 0
    private var lastTimePos: Double = 0
    private var terminated = false
    private static var cachedAvailable: Bool?
    private static let availabilityLock = NSLock()

    static func libmpvDylibPaths() -> [String] {
        var candidates: [String] = []
        if let mainResource = Bundle.main.resourceURL?.path {
            candidates.append("\(mainResource)/codec-tools/lib/libmpv.2.dylib")
        }
        if let moduleResource = Bundle.module.resourceURL?.path {
            candidates.append("\(moduleResource)/codec-tools/lib/libmpv.2.dylib")
        }
        let cwd = FileManager.default.currentDirectoryPath
        candidates.append("\(cwd)/Sources/LaughPlayer/codec-tools/lib/libmpv.2.dylib")
        candidates.append("/opt/homebrew/lib/libmpv.2.dylib")
        candidates.append("/usr/local/lib/libmpv.2.dylib")
        return candidates
    }

    static func warmAvailabilityCache() {
        DispatchQueue.global(qos: .utility).async {
            _ = isAvailable()
        }
    }

    static func terminateRunningProcesses() {
        // libmpv runs in-process; there is no helper process to kill.
    }

    static func isAvailable() -> Bool {
        availabilityLock.lock()
        defer { availabilityLock.unlock() }
        if let cachedAvailable { return cachedAvailable }
        for path in libmpvDylibPaths() where FileManager.default.fileExists(atPath: path) {
            if mpv_embed_load(path) == 0 {
                cachedAvailable = true
                return true
            }
        }
        cachedAvailable = false
        return false
    }

    var isRunning: Bool {
        ipcQueue.sync { embed != nil && !terminated }
    }

    func terminate() {
        ipcQueue.sync { terminateUnlocked() }
    }

    /// Loads `url` and draws into `renderLayer`. Completion runs on the main queue.
    func load(url: URL, renderLayer: MpvOpenGLLayer, completion: @escaping @MainActor (LoadResult) -> Void) {
        ipcQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(.failed("controller deallocated")) }
                return
            }
            self.terminateUnlocked()
            self.terminated = false
            self.isReady = false
            self.lastDuration = 0
            self.lastTimePos = 0

            guard Self.isAvailable() else {
                DispatchQueue.main.async { completion(.failed("libmpv not available")) }
                return
            }

            guard let created = mpv_embed_create() else {
                DispatchQueue.main.async { completion(.failed("mpv_create failed")) }
                return
            }
            self.embed = created

            for (name, value) in Self.inProcessOptions {
                _ = name.withCString { nameC in
                    value.withCString { valueC in
                        mpv_embed_set_option(created, nameC, valueC)
                    }
                }
            }
            if let fontDirectory = SubtitleFont.bundledFontsDirectoryURL?.path {
                _ = "sub-fonts-dir".withCString { nameC in
                    fontDirectory.withCString { valueC in
                        mpv_embed_set_option(created, nameC, valueC)
                    }
                }
            }

            let initStatus = mpv_embed_initialize(created)
            guard initStatus >= 0 else {
                self.terminateUnlocked()
                DispatchQueue.main.async { completion(.failed("mpv_initialize failed")) }
                return
            }

            _ = mpv_embed_observe(created, 1, "time-pos", 1)
            _ = mpv_embed_observe(created, 2, "duration", 1)
            _ = mpv_embed_observe(created, 3, "pause", 0)
            self.installHooksUnlocked()

            let mediaPath = url.path
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    completion(.failed("controller deallocated"))
                    return
                }
                self.attachRenderLayer(renderLayer) { [weak self] attached in
                    guard let self else {
                        completion(.failed("controller deallocated"))
                        return
                    }
                    guard attached else {
                        self.terminate()
                        completion(.failed("OpenGL render context failed"))
                        return
                    }
                    self.ipcQueue.async {
                        let loadStatus = mediaPath.withCString { pathC in
                            mpv_embed_command3(created, "loadfile", pathC, "replace")
                        }
                        guard loadStatus >= 0 else {
                            self.terminateUnlocked()
                            DispatchQueue.main.async { completion(.failed("loadfile failed")) }
                            return
                        }

                        let readyDeadline = CFAbsoluteTimeGetCurrent() + 8
                        while CFAbsoluteTimeGetCurrent() < readyDeadline {
                            mpv_embed_drain_events(created)
                            if !self.isReady, self.lastDuration > 0 {
                                self.isReady = true
                            }
                            if self.isReady { break }
                            if self.terminated || self.embed == nil {
                                DispatchQueue.main.async { completion(.failed("mpv exited early")) }
                                return
                            }
                            Thread.sleep(forTimeInterval: 0.02)
                        }

                        guard self.isReady else {
                            self.terminateUnlocked()
                            DispatchQueue.main.async { completion(.failed("mpv ready timeout")) }
                            return
                        }
                        PlaybackTrace.emit("[DEBUG-mpv] in-process libmpv render attached path=\(mediaPath)")
                        DispatchQueue.main.async { completion(.success) }
                    }
                }
            }
        }
    }

    func play() { setFlag("pause", value: 0) }
    func pause() { setFlag("pause", value: 1) }

    var isPaused: Bool {
        ipcQueue.sync {
            guard let embed else { return true }
            var flag: Int32 = 1
            guard mpv_embed_get_flag(embed, "pause", &flag) >= 0 else { return true }
            return flag != 0
        }
    }

    func seek(to seconds: Double, exact: Bool = false) {
        let mode = exact ? "absolute" : "absolute+keyframes"
        let value = String(seconds)
        ipcQueue.async { [weak self] in
            guard let embed = self?.embed else { return }
            _ = value.withCString { valueC in
                mode.withCString { modeC in
                    mpv_embed_command3(embed, "seek", valueC, modeC)
                }
            }
        }
    }

    func setSpeed(_ rate: Float) {
        setDouble("speed", value: Double(rate))
    }

    func setVolume(_ linear0to1: Float) {
        setDouble("volume", value: Double(max(0, min(1, linear0to1)) * 100))
    }

    func currentTimeSec() -> Double {
        if lastTimePos.isFinite { return max(0, lastTimePos) }
        return max(0, getDouble("time-pos") ?? 0)
    }

    func durationSec() -> Double {
        if lastDuration.isFinite, lastDuration > 0 { return lastDuration }
        let duration = getDouble("duration") ?? 0
        if duration.isFinite, duration > 0 { lastDuration = duration }
        return lastDuration
    }

    func videoCodecTag() -> String? { getString("video-codec") }
    func containerFormat() -> String? { getString("file-format") }

    func audioTracks() -> [AudioTrackInfo] {
        AudioTrackCatalog.tracks(fromMpvTrackList: getNodeJSON("track-list"))
    }

    func selectedAudioTrackID() -> Int? {
        if let aid = getDouble("aid"), aid >= 0 {
            return Int(aid)
        }
        return AudioTrackCatalog.selectedMpvTrackID(fromMpvTrackList: getNodeJSON("track-list"))
    }

    func setAudioTrackID(_ trackID: Int) -> Bool {
        ipcQueue.sync {
            guard let embed else { return false }
            let ok = mpv_embed_set_double(embed, "aid", Double(trackID)) >= 0
            _ = mpv_embed_set_flag(embed, "mute", 0)
            return ok
        }
    }

    func disableAudioTrack() -> Bool {
        ipcQueue.sync {
            guard let embed else { return false }
            let ok = mpv_embed_set_string(embed, "aid", "no") >= 0
            _ = mpv_embed_set_flag(embed, "mute", 1)
            return ok
        }
    }

    func isAudioTrackDisabled() -> Bool {
        if let aid = getString("aid"), aid == "no" { return true }
        if let aid = getDouble("aid"), aid < 0 { return true }
        return false
    }

    func applyPlaybackEQ(gains: [Float]) {
        let filter = PlaybackEQ.lavfiSuperequalizerFilter(gains: gains)
        ipcQueue.async { [weak self] in
            guard let embed = self?.embed else { return }
            _ = mpv_embed_command3(embed, "af", "remove", "@*")
            _ = filter.withCString { filterC in
                mpv_embed_command3(embed, "af", "add", filterC)
            }
        }
    }

    func clearPlaybackEQ() {
        ipcQueue.async { [weak self] in
            guard let embed = self?.embed else { return }
            _ = mpv_embed_command3(embed, "af", "remove", "@*")
        }
    }

    func subtitleTracks() -> [SubtitleTrackInfo] {
        SubtitleTrackCatalog.tracks(fromMpvTrackList: getNodeJSON("track-list"))
    }

    func selectedSubtitleTrackID(secondary: Bool = false) -> Int? {
        let property = secondary ? "secondary-sid" : "sid"
        if let sid = getDouble(property), sid >= 0 { return Int(sid) }
        return SubtitleTrackCatalog.selectedMpvTrackID(
            fromMpvTrackList: getNodeJSON("track-list"),
            secondary: secondary
        )
    }

    func setSubtitleTrackID(_ trackID: Int, secondary: Bool = false) -> Bool {
        let property = secondary ? "secondary-sid" : "sid"
        return ipcQueue.sync {
            guard let embed else { return false }
            return mpv_embed_set_double(embed, property, Double(trackID)) >= 0
        }
    }

    func disableSubtitleTrack(secondary: Bool = false) -> Bool {
        let property = secondary ? "secondary-sid" : "sid"
        return ipcQueue.sync {
            guard let embed else { return false }
            return mpv_embed_set_string(embed, property, "no") >= 0
        }
    }

    func isSubtitleTrackDisabled(secondary: Bool = false) -> Bool {
        let property = secondary ? "secondary-sid" : "sid"
        if let sid = getString(property), sid == "no" { return true }
        if let sid = getDouble(property), sid < 0 { return true }
        return false
    }

    func addExternalSubtitle(url: URL, select: Bool = true) -> Bool {
        ipcQueue.sync {
            guard let embed else { return false }
            return url.path.withCString { pathC in
                if select {
                    return mpv_embed_command3(embed, "sub-add", pathC, "select")
                }
                return mpv_embed_command2(embed, "sub-add", pathC)
            } >= 0
        }
    }

    func prepareSubtitleTracks(companionURLs: [URL]) {
        ipcQueue.sync {
            guard let embed else { return }
            _ = mpv_embed_set_string(embed, "secondary-sid", "no")
            for (index, url) in companionURLs.enumerated() {
                _ = url.path.withCString { pathC in
                    if index == 0 {
                        return mpv_embed_command3(embed, "sub-add", pathC, "select")
                    }
                    return mpv_embed_command2(embed, "sub-add", pathC)
                }
            }
            _ = mpv_embed_set_flag(embed, "sub-visibility", 1)
            if !companionURLs.isEmpty {
                nudgeSubtitleDisplayUnlocked()
            }
        }
    }

    func applySubtitleAppearance(from store: SettingsStore, refreshTrack: Bool = false) async {
        await withCheckedContinuation { continuation in
            applySubtitleAppearance(from: store, refreshTrack: refreshTrack) {
                continuation.resume()
            }
        }
    }

    func applySubtitleAppearance(
        from store: SettingsStore,
        refreshTrack: Bool,
        completion: @escaping @Sendable () -> Void
    ) {
        let style = SubtitleAppearanceStyle.assForceStyle(from: store)
        let fontColor = SubtitleAppearanceStyle.mpvSubColorString(from: store.subtitleFontColor)
        let borderColor = SubtitleAppearanceStyle.mpvSubColorString(from: store.subtitleBorderColor)
        let subPos = SubtitleAppearanceStyle.mpvSubPos(fromUserPosition: store.subtitlePosition)
        let fontScale = store.subtitleScale
            * (store.subtitleFontSize / SubtitleAppearanceStyle.defaultFontSize)
        let backColor = SubtitleAppearanceStyle.mpvSubColorString(from: store.subtitleBackgroundColor)
        let borderStyle = store.subtitleBackgroundEnabled ? "background-box" : "outline-and-shadow"
        let fontSize = store.subtitleFontSize
        let borderWidth = store.subtitleBorderWidth
        let delaySec = store.subtitleDelaySec
        let backgroundEnabled = store.subtitleBackgroundEnabled

        ipcQueue.async { [weak self] in
            guard let self, let embed = self.embed else {
                DispatchQueue.main.async(execute: completion)
                return
            }

            let trackID = refreshTrack ? self.selectedSubtitleTrackIDOnQueue(secondary: false) : nil
            _ = mpv_embed_set_string(embed, "sub-ass-override", "yes")
            _ = mpv_embed_set_string(embed, "sub-font", SubtitleFont.assFontName)
            _ = mpv_embed_set_string(embed, "sub-ass-force-style", style)
            _ = mpv_embed_set_string(embed, "sub-color", fontColor)
            _ = mpv_embed_set_string(embed, "sub-outline-color", borderColor)
            _ = mpv_embed_set_double(embed, "sub-font-size", fontSize)
            _ = mpv_embed_set_double(embed, "sub-outline-size", borderWidth)
            _ = mpv_embed_set_string(embed, "sub-border-style", borderStyle)
            if backgroundEnabled {
                _ = mpv_embed_set_string(embed, "sub-back-color", backColor)
            }
            _ = mpv_embed_set_double(embed, "sub-delay", delaySec)
            _ = mpv_embed_set_double(embed, "sub-pos", subPos)
            _ = mpv_embed_set_double(embed, "sub-scale", fontScale)
            _ = mpv_embed_set_double(embed, "secondary-sub-delay", delaySec)
            _ = mpv_embed_set_double(embed, "secondary-sub-pos", subPos)
            _ = mpv_embed_set_double(embed, "secondary-sub-scale", fontScale)
            if let trackID {
                _ = mpv_embed_set_string(embed, "sid", "no")
                usleep(80_000)
                _ = mpv_embed_set_double(embed, "sid", Double(trackID))
            }
            self.nudgeSubtitleDisplayUnlocked()
            DispatchQueue.main.async(execute: completion)
        }
    }

    func requestRenderRefresh() {
        DispatchQueue.main.async { [weak self] in
            self?.renderLayer?.setNeedsDisplay()
        }
    }

    func setEmbeddingWindowID(_ wid: Int) {
        requestRenderRefresh()
    }

    // MARK: - Private

    private func attachRenderLayer(
        _ layer: MpvOpenGLLayer,
        completion: @escaping (Bool) -> Void
    ) {
        renderLayer = layer
        layer.onDraw = { [weak self] fbo, width, height in
            guard let embed = self?.embed else { return }
            _ = mpv_embed_render_gl(embed, fbo, width, height)
            mpv_embed_report_swap(embed)
        }
        layer.onContextReady = { [weak self] in
            guard let self, let embed = self.embed else {
                completion(false)
                return
            }
            let status = mpv_embed_create_gl(embed)
            guard status >= 0 else {
                completion(false)
                return
            }
            mpv_embed_set_gl_update(embed, { ctx in
                guard let ctx else { return }
                let controller = Unmanaged<MpvPlaybackController>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async {
                    controller.renderLayer?.setNeedsDisplay()
                }
            }, Unmanaged.passUnretained(self).toOpaque())
            layer.setNeedsDisplay()
            completion(true)
        }
        layer.setNeedsDisplay()
    }

    private func installHooksUnlocked() {
        guard let embed else { return }
        var hooks = MpvEmbedHooks()
        hooks.ctx = Unmanaged.passUnretained(self).toOpaque()
        hooks.on_wakeup = { ctx in
            guard let ctx else { return }
            let controller = Unmanaged<MpvPlaybackController>.fromOpaque(ctx).takeUnretainedValue()
            controller.ipcQueue.async {
                guard let embed = controller.embed else { return }
                mpv_embed_drain_events(embed)
            }
        }
        hooks.on_file_loaded = { ctx in
            guard let ctx else { return }
            let controller = Unmanaged<MpvPlaybackController>.fromOpaque(ctx).takeUnretainedValue()
            controller.isReady = true
            DispatchQueue.main.async { controller.onReady?() }
        }
        hooks.on_end_file_eof = { ctx in
            guard let ctx else { return }
            let controller = Unmanaged<MpvPlaybackController>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { controller.onPlaybackEnded?() }
        }
        hooks.on_time_pos = { ctx, value in
            guard let ctx else { return }
            let controller = Unmanaged<MpvPlaybackController>.fromOpaque(ctx).takeUnretainedValue()
            controller.lastTimePos = value
            controller.notifyTime()
        }
        hooks.on_duration = { ctx, value in
            guard let ctx else { return }
            let controller = Unmanaged<MpvPlaybackController>.fromOpaque(ctx).takeUnretainedValue()
            if value > 0 {
                controller.lastDuration = value
                controller.isReady = true
            }
            controller.notifyTime()
        }
        hooks.on_pause = { ctx, paused in
            guard let ctx else { return }
            let controller = Unmanaged<MpvPlaybackController>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { controller.onPauseChanged?(paused != 0) }
        }
        mpv_embed_set_hooks(embed, hooks)
    }

    private func notifyTime() {
        let current = lastTimePos
        let duration = lastDuration
        DispatchQueue.main.async { [weak self] in
            self?.onTimeUpdate?(current, duration)
        }
    }

    private func selectedSubtitleTrackIDOnQueue(secondary: Bool) -> Int? {
        let property = secondary ? "secondary-sid" : "sid"
        if let sid = getDoubleUnlocked(property), sid >= 0 { return Int(sid) }
        return SubtitleTrackCatalog.selectedMpvTrackID(
            fromMpvTrackList: getNodeJSONUnlocked("track-list"),
            secondary: secondary
        )
    }

    private func nudgeSubtitleDisplayUnlocked() {
        guard let embed else { return }
        _ = mpv_embed_set_flag(embed, "sub-visibility", 0)
        _ = mpv_embed_set_flag(embed, "sub-visibility", 1)
    }

    private func setFlag(_ name: String, value: Int32) {
        ipcQueue.async { [weak self] in
            guard let embed = self?.embed else { return }
            _ = name.withCString { nameC in
                let flag = value
                return mpv_embed_set_flag(embed, nameC, flag)
            }
        }
    }

    private func setDouble(_ name: String, value: Double) {
        ipcQueue.async { [weak self] in
            guard let embed = self?.embed else { return }
            _ = name.withCString { nameC in
                mpv_embed_set_double(embed, nameC, value)
            }
        }
    }

    private func getDouble(_ name: String) -> Double? {
        ipcQueue.sync { getDoubleUnlocked(name) }
    }

    private func getDoubleUnlocked(_ name: String) -> Double? {
        guard let embed else { return nil }
        var value: Double = 0
        let status = name.withCString { nameC in
            mpv_embed_get_double(embed, nameC, &value)
        }
        return status >= 0 ? value : nil
    }

    private func getString(_ name: String) -> String? {
        ipcQueue.sync {
            guard let embed else { return nil }
            return name.withCString { nameC -> String? in
                guard let cString = mpv_embed_get_string(embed, nameC) else { return nil }
                defer { mpv_embed_free(UnsafeMutableRawPointer(cString)) }
                return String(cString: cString)
            }
        }
    }

    private func getNodeJSON(_ name: String) -> Any? {
        ipcQueue.sync { getNodeJSONUnlocked(name) }
    }

    private func getNodeJSONUnlocked(_ name: String) -> Any? {
        guard let embed else { return nil }
        return name.withCString { nameC -> Any? in
            guard let cString = mpv_embed_get_node_json(embed, nameC) else { return nil }
            defer { mpv_embed_free_buffer(UnsafeMutableRawPointer(cString)) }
            let json = String(cString: cString)
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
    }

    private func terminateUnlocked() {
        terminated = true
        let layer = renderLayer
        let current = embed
        embed = nil
        isReady = false
        renderLayer = nil
        if let current {
            let teardownGL = {
                layer?.onDraw = nil
                layer?.onContextReady = nil
                mpv_embed_destroy_gl(current)
            }
            if Thread.isMainThread {
                teardownGL()
            } else {
                DispatchQueue.main.sync(execute: teardownGL)
            }
            mpv_embed_destroy(current)
        }
    }
}
