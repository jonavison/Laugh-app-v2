import CoreGraphics
import CoreImage
import Foundation
import Metal

/// Per-person segmentation, kept out of `SelectionProvider` because it is person-specific
/// tool-layer knowledge (ADR 0005): the engine stays class-blind and prompt-driven.
/// Conformers return one matte per detected person, or `[]` when unavailable.
protocol PersonInstanceSegmenting: AnyObject {
    func personInstanceMasks(in image: CIImage, quality: SelectionQuality) async throws -> [SelectionMask]
}

/// A person-instance selection: one matte per person plus the union the user sees.
///
/// The union is a *view* over `instances`, not a replacement for them — a later picker
/// ("3 people detected, tap one") needs the individual boundaries, and re-separating them
/// out of a merged matte is not possible.
struct SelectionPersonInstances {
    /// Precedence order: later instances win contested pixels (see `precedenceOrdered`).
    let instances: [SelectionMask]
    /// Union of the already-matted instances.
    let combined: SelectionMask

    static let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    /// Unions per-instance mattes. Matting has already run per instance, so overlapping
    /// people never reach the boundary stage as one ambiguous edge.
    static func combining(_ instances: [SelectionMask], extent: CGRect) -> SelectionPersonInstances? {
        guard let first = instances.first else { return nil }
        guard instances.count > 1 else {
            return SelectionPersonInstances(instances: instances, combined: first)
        }

        let target = extent.integral
        var union = first.ciImageMatching(extent: target)
        for instance in instances.dropFirst() {
            let next = instance.ciImageMatching(extent: target)
            guard let merged = CIFilter(name: "CIMaximumCompositing", parameters: [
                kCIInputImageKey: next,
                kCIInputBackgroundImageKey: union
            ])?.outputImage else { continue }
            union = merged.cropped(to: target)
        }

        guard let cg = context.createCGImage(union, from: target) else { return nil }
        let combined = SelectionMask(
            cgImage: cg,
            extent: target,
            confidence: instances.map(\.confidence).max() ?? first.confidence,
            semanticClass: .person,
            source: first.source
        )
        return SelectionPersonInstances(instances: instances, combined: combined)
    }

    /// Confines each instance to what the merged person matte calls a person.
    ///
    /// Vision's per-instance masks come back soft, and they cover occluders at half strength
    /// — measured: plant leaves across a subject at ~0.5. Mid-grey reads as subject to
    /// everything downstream (the negative sampler skips it, the gate passes it), so a plant
    /// stayed in the selection. The merged matte is crisp about the same pixels, so
    /// intersecting keeps the per-person split and restores its judgement.
    static func narrowed(
        _ instances: [SelectionMask],
        to merged: SelectionMask,
        extent: CGRect,
        context: CIContext
    ) -> [SelectionMask] {
        let target = extent.integral
        let mergedCI = merged.ciImageMatching(extent: target)
        return instances.map { instance in
            guard let intersected = CIFilter(name: "CIMultiplyCompositing", parameters: [
                kCIInputImageKey: instance.ciImageMatching(extent: target),
                kCIInputBackgroundImageKey: mergedCI
            ])?.outputImage?.cropped(to: target) else { return instance }
            // If the merged matte disagrees about this person entirely, keep the instance:
            // losing a subject is worse than keeping an occluder.
            guard coverage(of: intersected, extent: target, context: context) >= minimumResidualCoverage,
                  let cg = context.createCGImage(intersected, from: target)
            else { return instance }
            return SelectionMask(
                cgImage: cg,
                extent: target,
                confidence: instance.confidence,
                semanticClass: instance.semanticClass,
                source: instance.source
            )
        }
    }

    /// Smallest residual worth prompting for, as a fraction of the frame. Below this it is
    /// segmenter fringe around the people already found, not a person of their own.
    static let minimumResidualCoverage = 0.004

    /// What the merged person matte covers but no instance claims.
    ///
    /// `VNGeneratePersonInstanceMaskRequest` reports a limited number of instances and can
    /// drop one outright — measured: 2 instances on a 3-person photo, with the third clearly
    /// present in the merged matte. Instances decide *how* to split people; the merged matte
    /// stays the authority on *where* they are, so the difference is a subject to prompt for.
    static func residualSubject(
        merged: SelectionMask,
        instances: [SelectionMask],
        extent: CGRect,
        context: CIContext
    ) -> SelectionMask? {
        guard let union = combining(instances, extent: extent) else { return nil }
        let target = extent.integral
        let longEdge = max(target.width, target.height)
        // Instance boundaries are coarser than the merged matte, so grow what counts as
        // claimed before differencing — otherwise every silhouette leaves a rim behind.
        let claimed = union.combined
            .ciImageMatching(extent: target)
            .clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: max(4.0, longEdge * 0.003)])
            .cropped(to: target)
        guard let unclaimed = CIFilter(name: "CIMultiplyCompositing", parameters: [
            kCIInputImageKey: merged.ciImageMatching(extent: target),
            kCIInputBackgroundImageKey: claimed.applyingFilter("CIColorInvert")
        ])?.outputImage?.cropped(to: target) else { return nil }

        // Open the difference so slivers along shared boundaries cannot pose as a person.
        let opening = max(3.0, longEdge * 0.004)
        let cleaned = unclaimed
            .clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: opening])
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: opening])
            .cropped(to: target)

        guard coverage(of: cleaned, extent: target, context: context) >= minimumResidualCoverage,
              let cg = context.createCGImage(cleaned, from: target)
        else { return nil }
        return SelectionMask(
            cgImage: cg,
            extent: target,
            confidence: merged.confidence,
            semanticClass: .person,
            source: merged.source
        )
    }

    private static func coverage(of matte: CIImage, extent: CGRect, context: CIContext) -> Double {
        let average = matte.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            average,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return Double(pixel[0]) / 255.0
    }

    /// Occlusion default: sort by matte footprint so the nearest (largest) subject lands
    /// last and wins pixels two instances both claim. Vision reports confidence per
    /// observation, not per instance, so there is no per-person score to sort on.
    ///
    /// Heuristic, not a guarantee — worth re-checking on real group photos where a
    /// background subject is closer to the camera plane than their box area suggests.
    static func precedenceOrdered<T>(_ items: [T], boxes: (T) -> CGRect?) -> [T] {
        items.enumerated()
            .sorted { lhs, rhs in
                let l = boxes(lhs.element).map { $0.width * $0.height } ?? 0
                let r = boxes(rhs.element).map { $0.width * $0.height } ?? 0
                if l == r { return lhs.offset < rhs.offset }
                return l < r
            }
            .map(\.element)
    }
}
