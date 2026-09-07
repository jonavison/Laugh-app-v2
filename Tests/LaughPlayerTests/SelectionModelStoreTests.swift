import Foundation
import XCTest
@testable import LaughPlayer

final class SelectionModelStoreTests: XCTestCase {
    func testCacheHitSkipsDownload() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-sel-models-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let artifact = SelectionModelArtifact.mobileSAM
        let dir = root.appendingPathComponent(artifact.id, isDirectory: true)
        try seedReadyArtifacts(in: dir)

        let downloader = CountingDownloader()
        let store = SelectionModelStore(
            root: root,
            downloader: downloader,
            unzipHandler: { _, _ in },
            compileHandler: { $0 }
        )
        let url = try await store.ensureAvailable(artifact)
        XCTAssertEqual(url.lastPathComponent, artifact.id)
        XCTAssertEqual(downloader.calls, 0)
        XCTAssertTrue(store.isReady(artifact))
    }

    func testCancelDuringDownloadLeavesNoReadyCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-sel-models-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let artifact = SelectionModelArtifact.mobileSAM
        let downloader = CancellableDownloader()
        let store = SelectionModelStore(root: root, downloader: downloader, unzipHandler: { _, _ in
            XCTFail("should not unzip after cancel")
        })

        do {
            _ = try await store.ensureAvailable(artifact, isCancelled: { true })
            XCTFail("expected cancel")
        } catch let error as SelectionModelStoreError {
            XCTAssertEqual(error, .cancelled)
        }
        XCTAssertFalse(store.isReady(artifact))
    }

    func testDownloadThenCompilePromotesArtifacts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-sel-models-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let artifact = SelectionModelArtifact.mobileSAM
        let downloader = WritingDownloader()
        let store = SelectionModelStore(
            root: root,
            downloader: downloader,
            unzipHandler: { zip, staging in
                XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
                try Self.writeStagingPackages(to: staging)
            },
            compileHandler: { package in
                // Simulate compile: mlpackage → sibling .mlmodelc directory.
                let compiled = package.deletingPathExtension().appendingPathExtension("mlmodelc")
                try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
                try Data([1]).write(to: compiled.appendingPathComponent("model.mil"))
                return compiled
            }
        )

        var lastProgress: Double = 0
        let url = try await store.ensureAvailable(artifact, progress: { lastProgress = $0 })
        XCTAssertEqual(url.lastPathComponent, artifact.id)
        XCTAssertGreaterThanOrEqual(lastProgress, 1)
        XCTAssertTrue(store.isReady(artifact))
        let urls = try store.mobileSAMModelURLs()
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls.encoder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls.decoder.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls.weights.path))
    }

    func testCorruptUnzipRejected() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-sel-models-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let artifact = SelectionModelArtifact.mobileSAM
        let store = SelectionModelStore(root: root, downloader: WritingDownloader()) { _, _ in
            // staging left empty → corrupt
        }
        do {
            _ = try await store.ensureAvailable(artifact)
            XCTFail("expected corrupt")
        } catch let error as SelectionModelStoreError {
            XCTAssertEqual(error, .corruptCache)
        }
        XCTAssertFalse(store.isReady(artifact))
    }

    private func seedReadyArtifacts(in dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in SelectionModelArtifact.mobileSAM.readyRelativePaths {
            let url = dir.appendingPathComponent(name)
            if name.hasSuffix(".json") {
                try Data("{}".utf8).write(to: url)
            } else {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data([1]).write(to: url.appendingPathComponent("model.mil"))
            }
        }
    }

    private static func writeStagingPackages(to staging: URL) throws {
        for name in ["mobile_sam_encoder.mlpackage", "mobile_sam_decoder.mlpackage"] {
            let pkg = staging.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
            try Data([2]).write(to: pkg.appendingPathComponent("Manifest.json"))
        }
        try Data("{}".utf8).write(
            to: staging.appendingPathComponent("mobile_sam_prompt_encoder_weights.json")
        )
    }
}

private final class CountingDownloader: SelectionModelDownloading, @unchecked Sendable {
    private(set) var calls = 0
    func download(
        from remote: URL,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)?,
        isCancelled: @Sendable () -> Bool
    ) async throws {
        calls += 1
    }
}

private final class CancellableDownloader: SelectionModelDownloading, @unchecked Sendable {
    func download(
        from remote: URL,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)?,
        isCancelled: @Sendable () -> Bool
    ) async throws {
        if isCancelled() { throw SelectionModelStoreError.cancelled }
    }
}

private final class WritingDownloader: SelectionModelDownloading, @unchecked Sendable {
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
        try Data([9, 9, 9]).write(to: destination)
        progress?(1)
    }
}
