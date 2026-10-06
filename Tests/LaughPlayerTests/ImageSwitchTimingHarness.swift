import XCTest
@testable import LaughPlayer

/// Timing harness for sibling image switches — prints ms so we can rank bottlenecks.
final class ImageSwitchTimingHarness: XCTestCase {
    private static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Selection", isDirectory: true)
    }

    func testRankSwitchCostsOnFixtures() throws {
        let fixtures = Self.fixturesDir
        let images = try FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil)
            .filter { MediaKindDetector.kind(for: $0) == .image }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertGreaterThanOrEqual(images.count, 2)

        let a = try XCTUnwrap(images.first)
        let b = try XCTUnwrap(images.dropFirst().first)

        func ms(_ block: () -> Void) -> Double {
            let t0 = CFAbsoluteTimeGetCurrent()
            block()
            return (CFAbsoluteTimeGetCurrent() - t0) * 1000
        }

        var decodeTotal = 0.0
        var previewTotal = 0.0
        var metaTotal = 0.0
        let rounds = 5
        for _ in 0..<rounds {
            previewTotal += ms {
                XCTAssertNotNil(ImageDisplayLoader.loadQuickPreview(at: a))
                XCTAssertNotNil(ImageDisplayLoader.loadQuickPreview(at: b))
            }
            decodeTotal += ms {
                XCTAssertNotNil(ImageDisplayLoader.loadDisplayImage(at: a))
                XCTAssertNotNil(ImageDisplayLoader.loadDisplayImage(at: b))
            }
            metaTotal += ms {
                _ = ImageFileMetadata.load(from: a)
                _ = ImageFileMetadata.load(from: b)
            }
        }

        let scan = ms {
            for _ in 0..<rounds {
                _ = MediaLibraryScanner.imageFiles(in: fixtures)
            }
        }

        let stressURL = fixtures.appendingPathComponent("stress-4k.jpg")
        let stressPreview = FileManager.default.fileExists(atPath: stressURL.path)
            ? ms { XCTAssertNotNil(ImageDisplayLoader.loadQuickPreview(at: stressURL)) }
            : -1
        let stressDecode = FileManager.default.fileExists(atPath: stressURL.path)
            ? ms { XCTAssertNotNil(ImageDisplayLoader.loadDisplayImage(at: stressURL)) }
            : -1

        print(String(format: "[DEBUG-switch] preview_pair_avg_ms=%.1f decode_pair_avg_ms=%.1f meta_pair_avg_ms=%.1f scan_%dx_ms=%.1f stress4k_preview_ms=%.1f stress4k_ms=%.1f",
                     previewTotal / Double(rounds),
                     decodeTotal / Double(rounds),
                     metaTotal / Double(rounds),
                     rounds,
                     scan,
                     stressPreview,
                     stressDecode))

        // Soft budget: metadata should not dominate a pair switch on fixtures.
        XCTAssertLessThan(metaTotal / Double(rounds), 80, "ImageFileMetadata.load too slow on fixtures")
    }
}
