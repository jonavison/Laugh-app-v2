import Foundation

/// Stamps develop parameters into saved **ImageDevelopEdit** documents (ADR 0006).
enum ImageBatchLookApply {
    struct Result: Equatable {
        var appliedCount: Int
        var replacedCount: Int
    }

    /// How many targets already have a non-identity saved edit (for replace confirm).
    static func existingEditCount(in paths: [String]) -> Int {
        paths.reduce(0) { count, path in
            count + (ImageDevelopEditStore.hasEdit(forPath: path) ? 1 : 0)
        }
    }

    /// Writes `parameters` (the wet look) into each path’s saved document; geometry on each target is preserved.
    /// Optional per-path mix: 0 keeps `dryByPath` (identity if missing), 1 is fully wet.
    @discardableResult
    static func apply(
        parameters: ImageAdjustParameters,
        toPaths paths: [String],
        dryByPath: [String: ImageAdjustParameters] = [:],
        mixByPath: [String: Double] = [:]
    ) -> Result {
        var applied = 0
        var replaced = 0
        var updates: [String: ImageDevelopEdit] = [:]
        for path in paths {
            let previous = ImageDevelopEditStore.edit(forPath: path)
            if let previous, !previous.isIdentity {
                replaced += 1
            }
            let geometry = previous ?? .identity
            let mix = mixByPath[path] ?? 1
            let dry = dryByPath[path] ?? .identity
            let mixed = ImageAdjustParameters.mixed(from: dry, to: parameters, amount: mix)
            let next = ImageDevelopEdit(
                parameters: mixed,
                rotationQuarterTurns: geometry.rotationQuarterTurns,
                flipHorizontal: geometry.flipHorizontal,
                flipVertical: geometry.flipVertical,
                cropNormalized: geometry.cropNormalized?.cgRect,
                straightenRadians: CGFloat(geometry.straightenRadians)
            )
            updates[path] = next
            applied += 1
        }
        ImageDevelopEditStore.saveMany(updates)
        return Result(appliedCount: applied, replacedCount: replaced)
    }
}
