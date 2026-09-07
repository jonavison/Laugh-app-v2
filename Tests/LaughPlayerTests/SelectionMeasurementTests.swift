import XCTest
@testable import LaughPlayer

/// W3-08e: checked-in measurement suite. Logs `[SEL-MEASURE]` lines for provider comparison.
final class SelectionMeasurementTests: XCTestCase {
    func testVisionProviderMeasurementSummary() async {
        let provider = VisionPersonSelectionProvider()
        let summary = await SelectionMeasurementHarness.runSuite(provider: provider, quality: .preview)
        SelectionMeasurementHarness.logSummary(summary)

        XCTAssertEqual(summary.scores.count, SelectionMeasurementHarness.allFixtures.count)
        XCTAssertGreaterThan(summary.meanPersonCoverage, 0.02, "Vision baseline should find people on portrait fixtures")
        // Soft: negatives may still false-positive on Vision; logged for comparison.
        print("\(SelectionMeasurementHarness.logPrefix) note=visionNegFP=\(summary.negativeFalsePositives)")
    }

    func testMobileSAMMeasurementWhenCached() async throws {
        let store = SelectionModelStore()
        let artifact = SelectionModelArtifact.mobileSAM
        guard store.isReady(artifact) else {
            throw XCTSkip(
                "MobileSAM not cached (no network in harness). Run Auto Select once in-app, or: ensure model under Application Support/LaughPlayer/SelectionModels/\(artifact.id)/"
            )
        }
        let provider = MobileSAMSelectionProvider(store: store)
        let summary = await SelectionMeasurementHarness.runSuite(provider: provider, quality: .accurate)
        SelectionMeasurementHarness.logSummary(summary)
        XCTAssertEqual(summary.providerID, MobileSAMSelectionProvider.id)
        XCTAssertFalse(summary.personScores.isEmpty)
    }

    func testHarnessMetricsOnSyntheticMatte() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let hard = CIImage(color: .white).cropped(to: CGRect(x: 16, y: 16, width: 32, height: 32))
            .composited(over: CIImage(color: .black).cropped(to: extent))
            .cropped(to: extent)
        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let cg = ctx.createCGImage(hard, from: extent) else {
            return XCTFail("cg")
        }
        let mask = SelectionMask(
            cgImage: cg,
            extent: extent,
            confidence: 1,
            semanticClass: .unknown,
            source: .pointPrompt
        )
        let cov = SelectionMeasurementHarness.matteCoverage(mask)
        XCTAssertGreaterThan(cov, 0.15)
        XCTAssertLessThan(cov, 0.4)
        let soft = SelectionMeasurementHarness.boundarySoftness(mask)
        XCTAssertGreaterThanOrEqual(soft, 0)
        XCTAssertLessThanOrEqual(soft, 1)
    }
}
