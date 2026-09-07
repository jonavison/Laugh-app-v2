import CoreImage
import Foundation

/// Tool-layer person prompt assist: Vision rough matte → SAM `SelectionPrompt`.
/// Keeps person specificity out of the shared session / provider substrate (W3-08d).
enum SelectionPersonPromptAssist {
    /// The prompt plus the rough matte it came from. The rough matte is retained because
    /// it is the only part of the pipeline that knows what a *person* is — SAM is
    /// class-blind and will happily swallow an occluder that sits inside the prompt box.
    struct Plan {
        let prompt: SelectionPrompt
        let rough: SelectionMask
    }

    static func buildPlan(
        using visionProvider: SelectionProvider,
        image: CIImage
    ) async throws -> Plan {
        let rough = try await visionProvider.selectClass(in: image, class: .person, quality: .preview)
        return Plan(
            prompt: SelectionPromptBuilder.fromRoughMask(rough, imageExtent: image.extent),
            rough: rough
        )
    }

    static func buildPrompt(
        using visionProvider: SelectionProvider,
        image: CIImage
    ) async throws -> SelectionPrompt {
        try await buildPlan(using: visionProvider, image: image).prompt
    }

    /// One plan per detected person: a tight box and interior positives from *that* person's
    /// matte, with the other people as negatives. A shared box across a group is what makes
    /// SAM return one merged blob (and swallow whatever sits between the subjects).
    ///
    /// Returned in `SelectionPersonInstances` precedence order. Empty when Vision has no
    /// per-instance masks to offer, which is the caller's cue to use `buildPlan`.
    static func buildInstancePlans(
        using segmenter: PersonInstanceSegmenting,
        image: CIImage
    ) async throws -> [Plan] {
        let instances = try await segmenter.personInstanceMasks(in: image, quality: .preview)
        guard !instances.isEmpty else { return [] }

        let extent = image.extent.integral
        var plans: [Plan] = []
        for (index, instance) in instances.enumerated() {
            let others = instances.enumerated().filter { $0.offset != index }.map(\.element)
            let exclusion = SelectionPersonInstances.combining(others, extent: extent)?.combined
            let prompt = SelectionPromptBuilder.fromRoughMask(
                instance,
                imageExtent: extent,
                exclusion: exclusion
            )
            // A prompt with no box means the matte had no on-pixels at this extent.
            guard prompt.box != nil else { continue }
            plans.append(Plan(prompt: prompt, rough: instance))
        }
        return SelectionPersonInstances.precedenceOrdered(plans) { $0.prompt.box }
    }
}
