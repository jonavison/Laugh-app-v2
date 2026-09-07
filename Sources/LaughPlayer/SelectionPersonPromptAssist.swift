import CoreImage
import Foundation

/// Tool-layer person prompt assist: Vision rough matte → SAM `SelectionPrompt`.
/// Keeps person specificity out of the shared session / provider substrate (W3-08d).
enum SelectionPersonPromptAssist {
    static func buildPrompt(
        using visionProvider: SelectionProvider,
        image: CIImage
    ) async throws -> SelectionPrompt {
        let rough = try await visionProvider.selectClass(in: image, class: .person, quality: .preview)
        return SelectionPromptBuilder.fromRoughMask(rough, imageExtent: image.extent)
    }
}
