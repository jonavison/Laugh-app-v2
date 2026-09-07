import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import LaughPlayer

/// Per-person prompting: Vision splits the group, SAM is prompted once per person, and the
/// union the user sees is a view over mattes that stay individually addressable.
/// Logs `[SEL-INSTANCE]` lines.
final class SelectionPersonInstanceTests: XCTestCase {
    private let extent = CGRect(x: 0, y: 0, width: 320, height: 240)
    /// Left subject is smaller than the right one, so precedence order is observable.
    private let left = CGRect(x: 30, y: 60, width: 70, height: 110)
    private let right = CGRect(x: 170, y: 40, width: 110, height: 160)

    private func log(_ message: String) {
        print("[SEL-INSTANCE] \(message)")
    }

    // MARK: - Prompt planning (no model required)

    func testEachPersonGetsATightBoxAndTheOthersAsNegatives() async throws {
        let segmenter = StubInstanceSegmenter(rects: [left, right], extent: extent)
        let plans = try await SelectionPersonPromptAssist.buildInstancePlans(
            using: segmenter,
            image: photo(rects: [left, right])
        )

        XCTAssertEqual(plans.count, 2, "one plan per person")
        for plan in plans {
            let box = try XCTUnwrap(plan.prompt.box)
            // Prompts live in top-left-origin space (SelectionCoordinateConventionTests).
            let (ciOwn, ciOther) = subjects(for: box)
            let own = flipped(ciOwn)
            let other = flipped(ciOther)

            XCTAssertTrue(box.insetBy(dx: -4, dy: -4).contains(own), "box should wrap its own person")
            XCTAssertFalse(
                box.contains(CGPoint(x: other.midX, y: other.midY)),
                "a per-person box must not reach across to the neighbour"
            )
            XCTAssertFalse(plan.prompt.positivePoints.isEmpty)
            for point in plan.prompt.positivePoints {
                XCTAssertTrue(own.insetBy(dx: -2, dy: -2).contains(point), "positives belong to this person")
            }
            let onNeighbour = plan.prompt.negativePoints.filter { other.contains($0) }
            XCTAssertFalse(
                onNeighbour.isEmpty,
                "the neighbour should be marked as background for this person"
            )
            log("box=\(box.integral) positives=\(plan.prompt.positivePoints.count) neighbourNegatives=\(onNeighbour.count)")
        }
    }

    /// Occlusion default: nearest (largest footprint) last, so it wins contested pixels.
    func testPlansAreOrderedNearestLast() async throws {
        let segmenter = StubInstanceSegmenter(rects: [right, left], extent: extent)
        let plans = try await SelectionPersonPromptAssist.buildInstancePlans(
            using: segmenter,
            image: photo(rects: [left, right])
        )
        let areas = plans.compactMap { $0.prompt.box.map { $0.width * $0.height } }
        XCTAssertEqual(areas.count, 2)
        XCTAssertLessThan(areas[0], areas[1], "largest footprint should sort last")
    }

    func testNoInstancesMeansNoPlansSoCallersFallBackToOnePrompt() async throws {
        let segmenter = StubInstanceSegmenter(rects: [], extent: extent)
        let plans = try await SelectionPersonPromptAssist.buildInstancePlans(
            using: segmenter,
            image: photo(rects: [])
        )
        XCTAssertTrue(plans.isEmpty)
    }

    /// Vision's instance request reports a limited number of people and can drop one
    /// outright — measured on a real 3-person photo where it returned 2. The merged matte
    /// still sees them, so the person it left out must come back as their own plan.
    func testPersonMissedByTheInstanceRequestIsRecoveredFromTheMergedMatte() async throws {
        let missed = CGRect(x: 130, y: 90, width: 60, height: 90)
        let segmenter = StubInstanceSegmenter(
            rects: [left, right],
            extent: extent,
            mergedRects: [left, right, missed]
        )
        let plans = try await SelectionPersonPromptAssist.buildInstancePlans(
            using: segmenter,
            image: photo(rects: [left, right, missed])
        )

        XCTAssertEqual(plans.count, 3, "the dropped person should be prompted for too")
        let recovered = try XCTUnwrap(
            plans.first { plan in
                guard let box = plan.prompt.box else { return false }
                return box.contains(CGPoint(x: missed.midX, y: extent.height - missed.midY))
            },
            "no plan covers the person the instance request missed"
        )
        XCTAssertFalse(recovered.prompt.positivePoints.isEmpty)
    }

    /// The recovered residual must be a person, not the fringe left over between two
    /// instances whose boundaries disagree with the merged matte by a few pixels.
    func testSliverBetweenInstancesIsNotMistakenForAPerson() async throws {
        let segmenter = StubInstanceSegmenter(
            rects: [left, right],
            extent: extent,
            mergedRects: [left, right, CGRect(x: left.maxX, y: left.minY, width: 3, height: left.height)]
        )
        let plans = try await SelectionPersonPromptAssist.buildInstancePlans(
            using: segmenter,
            image: photo(rects: [left, right])
        )
        XCTAssertEqual(plans.count, 2, "a 3px sliver is not a person")
    }

    func testUnionKeepsInstancesAddressable() throws {
        let masks = [
            try mask(rects: [left]),
            try mask(rects: [right])
        ]
        let result = try XCTUnwrap(SelectionPersonInstances.combining(masks, extent: extent))
        XCTAssertEqual(result.instances.count, 2, "union must not replace the individuals")

        let ctx = CIContext(options: [.cacheIntermediates: false])
        let raster = SelectionMeasurementHarness.binaryRaster(
            result.combined.ciImageMatching(extent: extent),
            extent: extent,
            context: ctx
        )
        XCTAssertGreaterThan(coverage(raster, in: left), 0.95, "union should contain the first person")
        XCTAssertGreaterThan(coverage(raster, in: right), 0.95, "union should contain the second person")
    }

    // MARK: - Against the real engine

    /// The point of per-instance prompting: one box per person keeps them separable, where a
    /// single box drawn around the whole group returns one merged blob.
    func testPerInstancePromptsKeepPeopleSeparableUnlikeOneGroupBox() async throws {
        let store = SelectionModelStore()
        guard store.isReady(SelectionModelArtifact.mobileSAM) else {
            throw XCTSkip("MobileSAM not cached — run Auto Select once in-app first.")
        }
        let provider = MobileSAMSelectionProvider(store: store)
        let image = photo(rects: [left, right])
        let segmenter = StubInstanceSegmenter(rects: [left, right], extent: extent)
        let plans = try await SelectionPersonPromptAssist.buildInstancePlans(using: segmenter, image: image)
        XCTAssertEqual(plans.count, 2)

        let masks = try await provider.select(in: image, prompts: plans.map(\.prompt), quality: .accurate)
        XCTAssertEqual(masks.count, 2, "results stay positionally aligned with prompts")

        let ctx = CIContext(options: [.cacheIntermediates: false])
        var instances: [SelectionMask] = []
        for (plan, mask) in zip(plans, masks) {
            let mask = try XCTUnwrap(mask)
            instances.append(mask)
            let raster = SelectionMeasurementHarness.binaryRaster(
                mask.ciImageMatching(extent: extent),
                extent: extent,
                context: ctx
            )
            let box = try XCTUnwrap(plan.prompt.box)
            let (own, other) = subjects(for: box)
            let ownCoverage = coverage(raster, in: own)
            let leakage = coverage(raster, in: other)
            log(String(format: "instance own=%.3f leakedIntoNeighbour=%.3f", ownCoverage, leakage))
            XCTAssertGreaterThan(ownCoverage, 0.85, "each instance should cover its own person")
            XCTAssertLessThan(leakage, 0.15, "an instance must not absorb the neighbour")
        }

        let union = try XCTUnwrap(SelectionPersonInstances.combining(instances, extent: extent))
        let unionRaster = SelectionMeasurementHarness.binaryRaster(
            union.combined.ciImageMatching(extent: extent),
            extent: extent,
            context: ctx
        )
        XCTAssertGreaterThan(coverage(unionRaster, in: left), 0.85, "union covers everyone")
        XCTAssertGreaterThan(coverage(unionRaster, in: right), 0.85, "union covers everyone")
        XCTAssertEqual(union.instances.count, 2)
    }

    /// Batching exists to pay for one image encode instead of N. It must not change results.
    func testBatchedPromptsMatchOneAtATime() async throws {
        let store = SelectionModelStore()
        guard store.isReady(SelectionModelArtifact.mobileSAM) else {
            throw XCTSkip("MobileSAM not cached — run Auto Select once in-app first.")
        }
        let provider = MobileSAMSelectionProvider(store: store)
        let image = photo(rects: [left, right])
        let segmenter = StubInstanceSegmenter(rects: [left, right], extent: extent)
        let prompts = try await SelectionPersonPromptAssist
            .buildInstancePlans(using: segmenter, image: image)
            .map(\.prompt)

        // First call pays for session load and model warm-up; that would swamp the timings.
        _ = try await provider.select(in: image, prompt: prompts[0], quality: .accurate)

        let batchStart = CFAbsoluteTimeGetCurrent()
        let batched = try await provider.select(in: image, prompts: prompts, quality: .accurate)
        let batchMs = (CFAbsoluteTimeGetCurrent() - batchStart) * 1000

        let loopStart = CFAbsoluteTimeGetCurrent()
        var individual: [SelectionMask] = []
        for prompt in prompts {
            individual.append(try await provider.select(in: image, prompt: prompt, quality: .accurate))
        }
        let loopMs = (CFAbsoluteTimeGetCurrent() - loopStart) * 1000
        log(String(format: "%d prompts batched=%.0fms looped=%.0fms", prompts.count, batchMs, loopMs))

        let ctx = CIContext(options: [.cacheIntermediates: false])
        for (batchedMask, singleMask) in zip(batched, individual) {
            let batchedMask = try XCTUnwrap(batchedMask)
            let a = SelectionMeasurementHarness.binaryRaster(
                batchedMask.ciImageMatching(extent: extent), extent: extent, context: ctx
            )
            let b = SelectionMeasurementHarness.binaryRaster(
                singleMask.ciImageMatching(extent: extent), extent: extent, context: ctx
            )
            let score = SelectionMeasurementHarness.accuracy(
                prediction: a,
                truth: b,
                width: Int(extent.width),
                height: Int(extent.height)
            )
            log(String(format: "batched vs single iou=%.4f", score.iou))
            XCTAssertGreaterThan(score.iou, 0.98, "batching must not change the matte")
        }
    }

    /// One person is the common case and it was measured on the previous group-wide route,
    /// so the instance route has to hold that ground before it earns being the default.
    func testSinglePersonFixturesDoNotRegress() async throws {
        let store = SelectionModelStore()
        guard store.isReady(SelectionModelArtifact.mobileSAM) else {
            throw XCTSkip("MobileSAM not cached — run Auto Select once in-app first.")
        }
        let vision = VisionPersonSelectionProvider()
        let provider = MobileSAMSelectionProvider(store: store)

        for fixture in SelectionMeasurementHarness.personFixtures {
            let image = try SelectionMeasurementHarness.loadCIImage(named: fixture)
            let plans = try await SelectionPersonPromptAssist.buildInstancePlans(using: vision, image: image)
            guard !plans.isEmpty else {
                log("\(fixture) no instances — merged route stays in charge")
                continue
            }
            let instanceMasks = try await provider
                .select(in: image, prompts: plans.map(\.prompt), quality: .accurate)
                .compactMap { $0 }
            let instances = try XCTUnwrap(
                SelectionPersonInstances.combining(instanceMasks, extent: image.extent.integral)
            )

            let merged = try await SelectionPersonPromptAssist.buildPlan(using: vision, image: image)
            let mergedMask = try await provider.select(in: image, prompt: merged.prompt, quality: .accurate)

            let instanceAgreement = SelectionMeasurementHarness.edgeAgreement(
                mask: instances.combined, photo: image
            )
            let mergedAgreement = SelectionMeasurementHarness.edgeAgreement(mask: mergedMask, photo: image)
            log(String(
                format: "%@ people=%d instanceEdgeAgree=%.4f mergedEdgeAgree=%.4f",
                fixture, plans.count, instanceAgreement, mergedAgreement
            ))
            XCTAssertGreaterThan(
                instanceAgreement,
                mergedAgreement * 0.7,
                "\(fixture): per-person route should not sit worse on photo edges"
            )
        }
    }

    // MARK: - Helpers

    /// Which subject a per-person prompt belongs to, and who its neighbour is. Returned in
    /// CI space; pass through `flipped` to compare against prompt geometry.
    private func subjects(for box: CGRect) -> (own: CGRect, other: CGRect) {
        let l = flipped(left)
        return box.contains(CGPoint(x: l.midX, y: l.midY)) ? (left, right) : (right, left)
    }

    /// CI space (bottom-left origin) → prompt space (top-left origin).
    private func flipped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: extent.height - rect.maxY, width: rect.width, height: rect.height)
    }

    private func photo(rects: [CGRect]) -> CIImage {
        var image = CIImage(color: CIColor(red: 0.12, green: 0.14, blue: 0.16)).cropped(to: extent)
        for rect in rects {
            let subject = CIImage(color: CIColor(red: 0.85, green: 0.32, blue: 0.24)).cropped(to: rect)
            image = subject.composited(over: image)
        }
        return image.cropped(to: extent)
    }

    private func mask(rects: [CGRect]) throws -> SelectionMask {
        var image = CIImage(color: .black).cropped(to: extent)
        for rect in rects {
            image = CIImage(color: .white).cropped(to: rect).composited(over: image)
        }
        let ctx = CIContext(options: [.cacheIntermediates: false])
        guard let cg = ctx.createCGImage(image.cropped(to: extent), from: extent) else {
            throw XCTSkip("could not render mask")
        }
        return SelectionMask(
            cgImage: cg,
            extent: extent,
            confidence: 0.9,
            semanticClass: .person,
            source: .visionPerson
        )
    }

    /// Lit fraction inside a CI-space rect; rasters are top-down, so the row range flips.
    private func coverage(_ raster: [UInt8], in rect: CGRect) -> Double {
        let width = Int(extent.width)
        let height = Int(extent.height)
        var lit = 0
        var total = 0
        for row in max(0, height - Int(rect.maxY))..<min(height, height - Int(rect.minY)) {
            for x in max(0, Int(rect.minX))..<min(width, Int(rect.maxX)) {
                if raster[row * width + x] > 127 { lit += 1 }
                total += 1
            }
        }
        return total == 0 ? 0 : Double(lit) / Double(total)
    }
}

/// Stands in for Vision so per-person planning is testable without needing a photo Vision
/// agrees contains people. `instanceRects` are the per-instance masks; `mergedRects` is what
/// the merged person matte sees, which is how a dropped instance gets recovered.
private final class StubInstanceSegmenter: SelectionProvider, PersonInstanceSegmenting, @unchecked Sendable {
    let providerID = "test.vision.instances"
    private let instanceRects: [CGRect]
    private let mergedRects: [CGRect]
    private let extent: CGRect
    private let ctx = CIContext(options: [.cacheIntermediates: false])

    init(rects: [CGRect], extent: CGRect, mergedRects: [CGRect]? = nil) {
        self.instanceRects = rects
        self.mergedRects = mergedRects ?? rects
        self.extent = extent
    }

    func personInstanceMasks(in image: CIImage, quality: SelectionQuality) async throws -> [SelectionMask] {
        _ = image
        _ = quality
        return instanceRects.compactMap { mask(rects: [$0]) }
    }

    func selectClass(in image: CIImage, class semanticClass: SemanticClass, quality: SelectionQuality) async throws -> SelectionMask {
        _ = image
        _ = quality
        guard semanticClass == .person else { throw SelectionError.unsupportedClass(semanticClass) }
        guard let merged = mask(rects: mergedRects) else { throw SelectionError.emptyResult }
        return merged
    }

    func selectRegion(in image: CIImage, at point: CGPoint, quality: SelectionQuality) async throws -> SelectionMask {
        _ = point
        return try await selectClass(in: image, class: .person, quality: quality)
    }

    func select(in image: CIImage, prompt: SelectionPrompt, quality: SelectionQuality) async throws -> SelectionMask {
        _ = prompt
        return try await selectClass(in: image, class: .person, quality: quality)
    }

    private func mask(rects: [CGRect]) -> SelectionMask? {
        guard !rects.isEmpty else { return nil }
        var composed = CIImage(color: .black).cropped(to: extent)
        for rect in rects {
            composed = CIImage(color: .white).cropped(to: rect).composited(over: composed)
        }
        guard let cg = ctx.createCGImage(composed.cropped(to: extent), from: extent) else { return nil }
        return SelectionMask(
            cgImage: cg,
            extent: extent,
            confidence: 0.9,
            semanticClass: .person,
            source: .visionPerson
        )
    }
}
