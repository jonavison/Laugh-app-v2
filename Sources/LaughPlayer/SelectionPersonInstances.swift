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

    private static let context: CIContext = {
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
