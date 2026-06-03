import AppKit
import Foundation

/// Subprocess mpv with JSON IPC and Cocoa `--wid` embedding.
final class MpvPlaybackController: @unchecked Sendable {
    enum LoadResult: Equatable {
        case success
        case failed(String)
    }

    var onTimeUpdate: ((Double, Double) -> Void)?
    var onPauseChanged: ((Bool) -> Void)?
    var onPlaybackEnded: (() -> Void)?
    var onReady: (() -> Void)?

    private var process: Process?
    private var socketPath: String?
    private var readSource: DispatchSourceRead?
    private var readFD: Int32 = -1
    private var writeFD: Int32 = -1
    private let ipcQueue = DispatchQueue(label: "mpv-ipc")
    private var readBuffer = Data()
    private var requestID: Int = 1
    private var pendingReplies: [Int: [String: Any]] = [:]
    private var isReady = false
    private var lastDuration: Double = 0
    private var lastTimePos: Double = 0
    private var terminated = false

    private static var cachedAvailable: Bool?
    private static let availabilityLock = NSLock()

    static func isAvailable() -> Bool {
        availabilityLock.lock()
        defer { availabilityLock.unlock() }
        if let cachedAvailable { return cachedAvailable }
        guard let path = BundledCodecTools.mpvExecutablePath() else {
            cachedAvailable = false
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--no-config", "--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            cachedAvailable = process.terminationStatus == 0
        } catch {
            cachedAvailable = false
        }
        return cachedAvailable ?? false
    }

    var isRunning: Bool {
        ipcQueue.sync { process?.isRunning == true }
    }

    func terminate() {
        ipcQueue.sync { terminateUnlocked() }
    }

    /// Loads `url` embedded at `wid`. `completion` is called on the main queue.
    func load(url: URL, wid: Int, completion: @escaping @MainActor (LoadResult) -> Void) {
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

            guard let executable = BundledCodecTools.mpvExecutablePath() else {
                DispatchQueue.main.async { completion(.failed("mpv not bundled")) }
                return
            }

            let socket = FileManager.default.temporaryDirectory
                .appendingPathComponent("LaughPlayer-mpv-\(UUID().uuidString).sock")
                .path
            try? FileManager.default.removeItem(atPath: socket)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = [
                "--no-terminal",
                "--keep-open=no",
                "--force-window=no",
                "--hwdec=auto",
                "--vo=gpu",
                "--pause",
                "--input-ipc-server=\(socket)",
                "--wid=\(wid)",
                url.path
            ]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice

            do {
                try proc.run()
            } catch {
                DispatchQueue.main.async { completion(.failed("spawn failed: \(error.localizedDescription)")) }
                return
            }

            self.process = proc
            self.socketPath = socket

            guard self.waitForSocket(path: socket, timeoutSec: 3) else {
                self.terminateUnlocked()
                DispatchQueue.main.async { completion(.failed("IPC socket timeout")) }
                return
            }

            guard self.connectIPC(path: socket) else {
                self.terminateUnlocked()
                DispatchQueue.main.async { completion(.failed("IPC connect failed")) }
                return
            }

            self.observePropertiesUnlocked()
            self.sendCommandUnlocked(["set_property", "pause", true], reply: false)

            let readyDeadline = CFAbsoluteTimeGetCurrent() + 4
            while CFAbsoluteTimeGetCurrent() < readyDeadline {
                if self.isReady { break }
                if self.process?.isRunning != true {
                    DispatchQueue.main.async { completion(.failed("mpv exited early")) }
                    return
                }
                Thread.sleep(forTimeInterval: 0.05)
            }

            guard self.isReady else {
                self.terminateUnlocked()
                DispatchQueue.main.async { completion(.failed("mpv ready timeout")) }
                return
            }

            DispatchQueue.main.async { completion(.success) }
        }
    }

    func play() { send(["set_property", "pause", false]) }
    func pause() { send(["set_property", "pause", true]) }

    var isPaused: Bool {
        (getPropertyBool("pause") ?? true)
    }

    func seek(to seconds: Double, exact: Bool = false) {
        let mode = exact ? "absolute" : "absolute+keyframes"
        send(["seek", seconds, mode])
    }

    func setSpeed(_ rate: Float) {
        send(["set_property", "speed", Double(rate)])
    }

    func setVolume(_ linear0to1: Float) {
        let mpvVolume = Double(max(0, min(1, linear0to1)) * 100)
        send(["set_property", "volume", mpvVolume])
    }

    func currentTimeSec() -> Double {
        if lastTimePos.isFinite { return max(0, lastTimePos) }
        return max(0, getPropertyDouble("time-pos") ?? 0)
    }

    func durationSec() -> Double {
        if lastDuration.isFinite, lastDuration > 0 { return lastDuration }
        let d = getPropertyDouble("duration") ?? 0
        if d.isFinite, d > 0 { lastDuration = d }
        return lastDuration
    }

    func videoCodecTag() -> String? { getPropertyString("video-codec") }
    func containerFormat() -> String? { getPropertyString("container-filename") }

    func audioTracks() -> [AudioTrackInfo] {
        AudioTrackCatalog.tracks(fromMpvTrackList: getPropertyValue("track-list"))
    }

    func selectedAudioTrackID() -> Int? {
        if let aid = getPropertyDouble("aid"), aid >= 0 {
            return Int(aid)
        }
        return AudioTrackCatalog.selectedMpvTrackID(fromMpvTrackList: getPropertyValue("track-list"))
    }

    func setAudioTrackID(_ trackID: Int) -> Bool {
        ipcQueue.sync {
            guard writeFD >= 0 else { return false }
            let id = nextRequestIDUnlocked()
            pendingReplies.removeValue(forKey: id)
            sendCommandUnlocked(["set_property", "aid", trackID], requestID: id, reply: true)
            sendCommandUnlocked(["set_property", "mute", false], reply: false)
            guard waitForCommandSuccessUnlocked(requestID: id, timeout: 0.6) else { return false }
            if let current = getPropertyDoubleUnlocked("aid"), Int(current) == trackID {
                return true
            }
            return false
        }
    }

    func disableAudioTrack() -> Bool {
        ipcQueue.sync {
            guard writeFD >= 0 else { return false }
            let id = nextRequestIDUnlocked()
            pendingReplies.removeValue(forKey: id)
            sendCommandUnlocked(["set_property", "aid", "no"], requestID: id, reply: true)
            sendCommandUnlocked(["set_property", "mute", true], reply: false)
            return waitForCommandSuccessUnlocked(requestID: id, timeout: 0.6)
        }
    }

    func isAudioTrackDisabled() -> Bool {
        if let aid = getPropertyString("aid"), aid == "no" { return true }
        if let aid = getPropertyDouble("aid"), aid < 0 { return true }
        return false
    }

    func applyPlaybackEQ(gains: [Float]) {
        let filter = PlaybackEQ.lavfiSuperequalizerFilter(gains: gains)
        ipcQueue.sync {
            guard writeFD >= 0 else { return }
            sendCommandUnlocked(["af", "remove", "@*"], reply: false)
            sendCommandUnlocked(["af", "add", filter], reply: false)
        }
    }

    func clearPlaybackEQ() {
        ipcQueue.sync {
            guard writeFD >= 0 else { return }
            sendCommandUnlocked(["af", "remove", "@*"], reply: false)
        }
    }

    func setEmbeddingWindowID(_ wid: Int) {
        send(["set_property", "wid", wid])
    }

    // MARK: - IPC

    private func send(_ command: [Any]) {
        ipcQueue.async { [weak self] in
            self?.sendCommandUnlocked(command, reply: false)
        }
    }

    private func getPropertyDouble(_ name: String) -> Double? {
        ipcQueue.sync {
            guard writeFD >= 0 else { return nil }
            let id = nextRequestIDUnlocked()
            pendingReplies.removeValue(forKey: id)
            sendCommandUnlocked(["get_property", name], requestID: id, reply: true)
            return waitForNumericReplyUnlocked(requestID: id, timeout: 0.4)
        }
    }

    private func getPropertyBool(_ name: String) -> Bool? {
        guard let value = getPropertyDouble(name) else { return nil }
        return value != 0
    }

    private func getPropertyString(_ name: String) -> String? {
        ipcQueue.sync {
            guard writeFD >= 0 else { return nil }
            let id = nextRequestIDUnlocked()
            pendingReplies.removeValue(forKey: id)
            sendCommandUnlocked(["get_property", name], requestID: id, reply: true)
            return waitForStringReplyUnlocked(requestID: id, timeout: 0.4)
        }
    }

    private func getPropertyValue(_ name: String) -> Any? {
        ipcQueue.sync {
            guard writeFD >= 0 else { return nil }
            let id = nextRequestIDUnlocked()
            pendingReplies.removeValue(forKey: id)
            sendCommandUnlocked(["get_property", name], requestID: id, reply: true)
            return waitForAnyReplyUnlocked(requestID: id, timeout: 0.6)
        }
    }

    private func getPropertyDoubleUnlocked(_ name: String) -> Double? {
        guard writeFD >= 0 else { return nil }
        let id = nextRequestIDUnlocked()
        pendingReplies.removeValue(forKey: id)
        sendCommandUnlocked(["get_property", name], requestID: id, reply: true)
        return waitForNumericReplyUnlocked(requestID: id, timeout: 0.4)
    }

    private func nextRequestIDUnlocked() -> Int {
        requestID += 1
        return requestID
    }

    private func terminateUnlocked() {
        terminated = true
        tearDownIPCUnlocked()
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        isReady = false
        if let socketPath {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        socketPath = nil
    }

    private func tearDownIPCUnlocked() {
        readSource?.cancel()
        readSource = nil
        if readFD >= 0 { close(readFD) }
        if writeFD >= 0, writeFD != readFD { close(writeFD) }
        readFD = -1
        writeFD = -1
        readBuffer.removeAll()
        pendingReplies.removeAll()
    }

    private func waitForSocket(path: String, timeoutSec: Double) -> Bool {
        let deadline = CFAbsoluteTimeGetCurrent() + timeoutSec
        while CFAbsoluteTimeGetCurrent() < deadline {
            if FileManager.default.fileExists(atPath: path) { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }

    private func connectIPC(path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPath = MemoryLayout.size(ofValue: addr.sun_path) - 1
        let copied = path.withCString { cString in
            strncpy(&addr.sun_path.0, cString, maxPath)
        }
        guard copied != nil else {
            close(fd)
            return false
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, length) == 0
            }
        }
        guard connected else {
            close(fd)
            return false
        }
        readFD = fd
        writeFD = fd
        startReadLoopUnlocked()
        return true
    }

    private func startReadLoopUnlocked() {
        let source = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: ipcQueue)
        source.setEventHandler { [weak self] in
            self?.drainSocketUnlocked()
        }
        source.resume()
        readSource = source
    }

    private func drainSocketUnlocked() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let readCount = read(readFD, &buffer, buffer.count)
            if readCount <= 0 { break }
            readBuffer.append(buffer, count: readCount)
        }
        while let newlineRange = readBuffer.firstRange(of: Data([0x0a])) {
            let lineData = readBuffer.subdata(in: readBuffer.startIndex..<newlineRange.lowerBound)
            readBuffer.removeSubrange(readBuffer.startIndex...newlineRange.lowerBound)
            guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else { continue }
            handleLineUnlocked(line)
        }
    }

    private func handleLineUnlocked(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let requestID = json["request_id"] as? Int {
            pendingReplies[requestID] = json
        }

        if let event = json["event"] as? String {
            switch event {
            case "file-loaded":
                isReady = true
                DispatchQueue.main.async { [weak self] in self?.onReady?() }
            case "end-file":
                let reason = (json["reason"] as? String) ?? ""
                if reason == "eof" {
                    DispatchQueue.main.async { [weak self] in self?.onPlaybackEnded?() }
                }
            default:
                break
            }
        }

        if json["event"] as? String == "property-change", let name = json["name"] as? String {
            switch name {
            case "time-pos":
                if let value = json["data"] as? NSNumber {
                    lastTimePos = value.doubleValue
                    notifyTimeUnlocked()
                }
            case "duration":
                if let value = json["data"] as? NSNumber, value.doubleValue > 0 {
                    lastDuration = value.doubleValue
                    notifyTimeUnlocked()
                }
            case "pause":
                if let value = json["data"] as? NSNumber {
                    DispatchQueue.main.async { [weak self] in
                        self?.onPauseChanged?(value.boolValue)
                    }
                }
            default:
                break
            }
        }
    }

    private func notifyTimeUnlocked() {
        let current = lastTimePos
        let duration = lastDuration
        DispatchQueue.main.async { [weak self] in
            self?.onTimeUpdate?(current, duration)
        }
    }

    private func observePropertiesUnlocked() {
        for (index, prop) in ["time-pos", "duration", "pause"].enumerated() {
            sendCommandUnlocked(["observe_property", index + 1, prop], reply: false)
        }
    }

    private func sendCommandUnlocked(_ command: [Any], requestID: Int? = nil, reply: Bool) {
        var payload: [String: Any] = ["command": command]
        if let requestID { payload["request_id"] = requestID }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        guard let bytes = line.data(using: .utf8), writeFD >= 0 else { return }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = write(writeFD, base, raw.count)
        }
        if reply {
            _ = fsync(writeFD)
        }
    }

    private func waitForNumericReplyUnlocked(requestID: Int, timeout: Double) -> Double? {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            drainSocketUnlocked()
            if let reply = pendingReplies.removeValue(forKey: requestID) {
                if let error = reply["error"] as? String, error != "success" { return nil }
                if let data = reply["data"] as? NSNumber { return data.doubleValue }
                if let data = reply["data"] as? String, let value = Double(data) { return value }
                return nil
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    private func waitForStringReplyUnlocked(requestID: Int, timeout: Double) -> String? {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            drainSocketUnlocked()
            if let reply = pendingReplies.removeValue(forKey: requestID) {
                if let error = reply["error"] as? String, error != "success" { return nil }
                if let data = reply["data"] as? String { return data }
                return nil
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    private func waitForAnyReplyUnlocked(requestID: Int, timeout: Double) -> Any? {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            drainSocketUnlocked()
            if let reply = pendingReplies.removeValue(forKey: requestID) {
                if let error = reply["error"] as? String, error != "success" { return nil }
                return reply["data"]
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    private func waitForCommandSuccessUnlocked(requestID: Int, timeout: Double) -> Bool {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            drainSocketUnlocked()
            if let reply = pendingReplies.removeValue(forKey: requestID) {
                if let error = reply["error"] as? String { return error == "success" }
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }
}
