import CoreML
import Foundation

/// Catalog entry for a download-once, license-checked selection engine artifact (ADR 0005).
struct SelectionModelArtifact: Equatable, Sendable {
    let id: String
    let displayName: String
    /// SPDX-style license id inherited by the conversion.
    let license: String
    let upstreamNote: String
    let remoteURL: URL
    /// Files that must exist under the cache dir for `isReady` (relative paths).
    let readyRelativePaths: [String]

    /// PR 1 pin: MobileSAM via SamKit release zip (encoder + decoder + prompt weights).
    static let mobileSAM = SelectionModelArtifact(
        id: "mobilesam-coreml-v1",
        displayName: "MobileSAM",
        license: "Apache-2.0",
        upstreamNote: "ChaoningZhang/MobileSAM via john-rocky/SamKit v1.0.0 MobileSAM.zip (Apache-2.0).",
        remoteURL: URL(string: "https://github.com/john-rocky/SamKit/releases/download/v1.0.0/MobileSAM.zip")!,
        readyRelativePaths: [
            "mobile_sam_encoder.mlmodelc",
            "mobile_sam_decoder.mlmodelc",
            "mobile_sam_prompt_encoder_weights.json"
        ]
    )

    var encoderCompiledName: String { "mobile_sam_encoder.mlmodelc" }
    var decoderCompiledName: String { "mobile_sam_decoder.mlmodelc" }
    var promptWeightsName: String { "mobile_sam_prompt_encoder_weights.json" }
}

enum SelectionModelStoreError: Error, Equatable {
    case cancelled
    case downloadFailed(String)
    case corruptCache
    case notReady
}

/// Downloads once and caches CoreML selection weights. Network only on explicit ensure / optional Wi‑Fi prefetch.
protocol SelectionModelDownloading: Sendable {
    func download(
        from remote: URL,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)?,
        isCancelled: @Sendable () -> Bool
    ) async throws
}

/// Default downloader using URLSession (streaming to disk).
struct URLSessionSelectionModelDownloader: SelectionModelDownloading {
    func download(
        from remote: URL,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)?,
        isCancelled: @Sendable () -> Bool
    ) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let (bytes, response) = try await URLSession.shared.bytes(from: remote)
        if isCancelled() { throw SelectionModelStoreError.cancelled }

        let expected: Int64?
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw SelectionModelStoreError.downloadFailed("HTTP \(http.statusCode)")
            }
            expected = http.expectedContentLength > 0 ? http.expectedContentLength : nil
        } else {
            expected = nil
        }

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var written: Int64 = 0
        var buffer: [UInt8] = []
        buffer.reserveCapacity(64 * 1024)
        for try await byte in bytes {
            if isCancelled() {
                try? FileManager.default.removeItem(at: destination)
                throw SelectionModelStoreError.cancelled
            }
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: Data(buffer))
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if let expected, expected > 0 {
                    progress?(min(1, Double(written) / Double(expected)))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: Data(buffer))
            written += Int64(buffer.count)
        }
        progress?(1)
        guard written > 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw SelectionModelStoreError.downloadFailed("Empty download")
        }
    }
}

/// Source of truth for on-disk MobileSAM (and future) CoreML artifacts.
final class SelectionModelStore: @unchecked Sendable {
    private let root: URL
    private let downloader: SelectionModelDownloading
    private let fileManager: FileManager
    private let unzipHandler: (URL, URL) throws -> Void
    private let compileHandler: (URL) async throws -> URL

    init(
        root: URL? = nil,
        downloader: SelectionModelDownloading = URLSessionSelectionModelDownloader(),
        fileManager: FileManager = .default,
        unzipHandler: @escaping (URL, URL) throws -> Void = SelectionModelStore.defaultUnzip,
        compileHandler: @escaping (URL) async throws -> URL = SelectionModelStore.defaultCompile
    ) {
        self.fileManager = fileManager
        self.downloader = downloader
        self.unzipHandler = unzipHandler
        self.compileHandler = compileHandler
        if let root {
            self.root = root
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.root = base
                .appendingPathComponent("LaughPlayer", isDirectory: true)
                .appendingPathComponent("SelectionModels", isDirectory: true)
        }
    }

    func cacheDirectory(for artifact: SelectionModelArtifact) -> URL {
        root.appendingPathComponent(artifact.id, isDirectory: true)
    }

    func isReady(_ artifact: SelectionModelArtifact) -> Bool {
        let dir = cacheDirectory(for: artifact)
        return artifact.readyRelativePaths.allSatisfy { rel in
            fileManager.fileExists(atPath: dir.appendingPathComponent(rel).path)
        }
    }

    /// Paths for SamKit `SamModelRef` once ready.
    func mobileSAMModelURLs() throws -> (encoder: URL, decoder: URL, weights: URL) {
        let artifact = SelectionModelArtifact.mobileSAM
        guard isReady(artifact) else { throw SelectionModelStoreError.notReady }
        let dir = cacheDirectory(for: artifact)
        return (
            dir.appendingPathComponent(artifact.encoderCompiledName),
            dir.appendingPathComponent(artifact.decoderCompiledName),
            dir.appendingPathComponent(artifact.promptWeightsName)
        )
    }

    /// Blocking ensure: returns cache directory when compiled artifacts are ready.
    @discardableResult
    func ensureAvailable(
        _ artifact: SelectionModelArtifact,
        progress: (@Sendable (Double) -> Void)? = nil,
        isCancelled: @Sendable () -> Bool = { false }
    ) async throws -> URL {
        let dir = cacheDirectory(for: artifact)
        if isReady(artifact) {
            progress?(1)
            return dir
        }
        if isCancelled() { throw SelectionModelStoreError.cancelled }

        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let zipURL = dir.appendingPathComponent("download.zip")
        let staging = dir.appendingPathComponent("_staging", isDirectory: true)
        if fileManager.fileExists(atPath: staging.path) {
            try fileManager.removeItem(at: staging)
        }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        do {
            try await downloader.download(
                from: artifact.remoteURL,
                to: zipURL,
                progress: { p in progress?(p * 0.7) },
                isCancelled: isCancelled
            )
            if isCancelled() { throw SelectionModelStoreError.cancelled }

            try unzipHandler(zipURL, staging)
            progress?(0.8)
            if isCancelled() { throw SelectionModelStoreError.cancelled }

            try await compileMobileSAMLayout(from: staging, into: dir, progress: progress, isCancelled: isCancelled)
            try? fileManager.removeItem(at: zipURL)
            try? fileManager.removeItem(at: staging)
            progress?(1)
            guard isReady(artifact) else { throw SelectionModelStoreError.corruptCache }
            return dir
        } catch {
            try? fileManager.removeItem(at: zipURL)
            try? fileManager.removeItem(at: staging)
            if let storeError = error as? SelectionModelStoreError {
                throw storeError
            }
            throw SelectionModelStoreError.downloadFailed(String(describing: error))
        }
    }

    /// Best-effort prefetch — callers must gate on Wi‑Fi + idle; never required for correctness.
    func prefetchIfNeeded(_ artifact: SelectionModelArtifact) {
        guard !isReady(artifact) else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            _ = try? await self.ensureAvailable(artifact, progress: nil, isCancelled: { false })
        }
    }

    private func compileMobileSAMLayout(
        from staging: URL,
        into dir: URL,
        progress: (@Sendable (Double) -> Void)?,
        isCancelled: @Sendable () -> Bool
    ) async throws {
        let encoderPkg = findFile(named: "mobile_sam_encoder.mlpackage", under: staging)
            ?? findFile(named: "mobile_sam_encoder.mlmodelc", under: staging)
        let decoderPkg = findFile(named: "mobile_sam_decoder.mlpackage", under: staging)
            ?? findFile(named: "mobile_sam_decoder.mlmodelc", under: staging)
        let weights = findFile(named: "mobile_sam_prompt_encoder_weights.json", under: staging)
        guard let encoderPkg, let decoderPkg, let weights else {
            throw SelectionModelStoreError.corruptCache
        }
        if isCancelled() { throw SelectionModelStoreError.cancelled }

        let encoderCompiled: URL
        if encoderPkg.pathExtension == "mlmodelc" {
            encoderCompiled = encoderPkg
        } else {
            encoderCompiled = try await compileHandler(encoderPkg)
        }
        progress?(0.9)
        if isCancelled() { throw SelectionModelStoreError.cancelled }

        let decoderCompiled: URL
        if decoderPkg.pathExtension == "mlmodelc" {
            decoderCompiled = decoderPkg
        } else {
            decoderCompiled = try await compileHandler(decoderPkg)
        }
        progress?(0.95)

        let encDest = dir.appendingPathComponent(SelectionModelArtifact.mobileSAM.encoderCompiledName)
        let decDest = dir.appendingPathComponent(SelectionModelArtifact.mobileSAM.decoderCompiledName)
        let wDest = dir.appendingPathComponent(SelectionModelArtifact.mobileSAM.promptWeightsName)
        for url in [encDest, decDest, wDest] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.copyItem(at: encoderCompiled, to: encDest)
        try fileManager.copyItem(at: decoderCompiled, to: decDest)
        try fileManager.copyItem(at: weights, to: wDest)
    }

    private func findFile(named name: String, under root: URL) -> URL? {
        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == name { return url }
        }
        return nil
    }

    static func defaultUnzip(zip: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zip.path, "-d", destination.path]
        let err = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SelectionModelStoreError.downloadFailed("unzip failed: \(message)")
        }
    }

    static func defaultCompile(package: URL) async throws -> URL {
        try await MLModel.compileModel(at: package)
    }
}
