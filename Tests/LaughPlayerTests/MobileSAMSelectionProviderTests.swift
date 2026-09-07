import CoreImage
import Foundation
import XCTest
@testable import LaughPlayer

final class MobileSAMSelectionProviderTests: XCTestCase {
    func testModelNotReadyFallsThrough() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-sam-provider-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SelectionModelStore(root: root, downloader: NoopDownloader())
        let provider = MobileSAMSelectionProvider(store: store)
        let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))

        do {
            _ = try await provider.select(in: image, prompt: .point(CGPoint(x: 32, y: 32)), quality: .preview)
            XCTFail("expected modelNotReady")
        } catch let error as SelectionError {
            XCTAssertEqual(error, .modelNotReady)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testEmptyPromptRejected() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-sam-provider-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SelectionModelStore(root: root, downloader: NoopDownloader())
        // Seed ready so we don't stop at modelNotReady before empty check… actually empty is checked first.
        let provider = MobileSAMSelectionProvider(store: store)
        let image = CIImage(color: .green).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 32))

        do {
            _ = try await provider.select(in: image, prompt: .empty, quality: .preview)
            XCTFail("expected emptyResult")
        } catch let error as SelectionError {
            XCTAssertEqual(error, .emptyResult)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testPromptPointFactory() {
        let p = SelectionPrompt.point(CGPoint(x: 10, y: 20))
        XCTAssertEqual(p.positivePoints, [CGPoint(x: 10, y: 20)])
        XCTAssertTrue(p.negativePoints.isEmpty)
        XCTAssertNil(p.box)
        XCTAssertFalse(p.isEmpty)
        XCTAssertTrue(SelectionPrompt.empty.isEmpty)
    }

    func testSelectRegionRoutesThroughPromptContract() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("laugh-sam-provider-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SelectionModelStore(root: root, downloader: NoopDownloader())
        let provider = MobileSAMSelectionProvider(store: store)
        let image = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 40))

        do {
            _ = try await provider.selectRegion(in: image, at: CGPoint(x: 5, y: 5), quality: .preview)
            XCTFail("expected modelNotReady")
        } catch let error as SelectionError {
            XCTAssertEqual(error, .modelNotReady)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}

private final class NoopDownloader: SelectionModelDownloading, @unchecked Sendable {
    func download(
        from remote: URL,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)?,
        isCancelled: @Sendable () -> Bool
    ) async throws {}
}
