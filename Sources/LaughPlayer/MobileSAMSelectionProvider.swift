import CoreImage
import Foundation
import Metal
@preconcurrency import SAMKit

/// Class-blind MobileSAM provider: prompt → coarse SAM mask → CI photo-edge polish (ADR 0005 / W3-08c).
/// No `semanticClass` branching. Missing weights surface as `SelectionError.modelNotReady`.
final class MobileSAMSelectionProvider: SelectionProvider, BatchPromptSelecting, @unchecked Sendable {
    static let id = "coreml.mobilesam"
    var providerID: String { Self.id }

    private let store: SelectionModelStore
    private let applyPolish: Bool
    private let lock = NSLock()
    private var session: SamSession?

    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    init(store: SelectionModelStore = SelectionModelStore(), applyPolish: Bool = true) {
        self.store = store
        self.applyPolish = applyPolish
    }

    func selectRegion(
        in image: CIImage,
        at point: CGPoint,
        quality: SelectionQuality
    ) async throws -> SelectionMask {
        try await select(in: image, prompt: .point(point), quality: quality)
    }

    func selectClass(
        in image: CIImage,
        class semanticClass: SemanticClass,
        quality: SelectionQuality
    ) async throws -> SelectionMask {
        // Class-agnostic engine: semantic labels are caller metadata, not routing.
        _ = semanticClass
        let extent = image.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)
        return try await select(in: image, prompt: .point(center), quality: quality)
    }

    func select(
        in image: CIImage,
        prompt: SelectionPrompt,
        quality: SelectionQuality
    ) async throws -> SelectionMask {
        guard !prompt.isEmpty else { throw SelectionError.emptyResult }
        guard let mask = try await select(in: image, prompts: [prompt], quality: quality).first,
              let mask
        else { throw SelectionError.emptyResult }
        return mask
    }

    /// Several prompts, one image encode. The encoder dominates MobileSAM's cost, so N
    /// prompts (one per person) run as one encode plus N cheap decodes. Each mask is
    /// matted individually — overlapping people never reach the boundary stage as a single
    /// ambiguous edge.
    func select(
        in image: CIImage,
        prompts: [SelectionPrompt],
        quality: SelectionQuality
    ) async throws -> [SelectionMask?] {
        try await select(in: image, prompts: prompts, quality: quality, onProgress: { _ in })
    }

    func select(
        in image: CIImage,
        prompts: [SelectionPrompt],
        quality: SelectionQuality,
        onProgress: @escaping @Sendable (Int) -> Void
    ) async throws -> [SelectionMask?] {
        guard !prompts.isEmpty else { return [] }

        let extent = image.extent.integral
        guard extent.width > 1, extent.height > 1 else {
            throw SelectionError.invalidImage
        }

        guard store.isReady(SelectionModelArtifact.mobileSAM) else {
            throw SelectionError.modelNotReady
        }

        guard let cgImage = ciContext.createCGImage(image, from: extent) else {
            throw SelectionError.invalidImage
        }

        let session = try loadSession()
        let results: [SamResult?] = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try session.setImage(cgImage)
                    let options = SamOptions(
                        multimaskOutput: quality == .accurate,
                        returnLogits: false,
                        maskThreshold: 0.0,
                        maxMasks: quality == .accurate ? 3 : 1
                    )
                    let results: [SamResult?] = prompts.map { prompt in
                        guard !prompt.isEmpty else { return nil }
                        return try? session.predict(
                            points: Self.samPoints(from: prompt),
                            box: prompt.box.flatMap(Self.samBox(from:)),
                            options: options
                        )
                    }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        // Matting is per person and runs after the shared encode, so report as each lands.
        return results.enumerated().map { index, result in
            defer { onProgress(index + 1) }
            guard let best = result?.masks.max(by: { $0.score < $1.score }) else { return nil }
            return finish(rawMask: best.cgImage, score: best.score, photo: image, extent: extent)
        }
    }

    /// Scale → canonicalise → per-instance matting → `SelectionMask`.
    private func finish(
        rawMask: CGImage,
        score: Float,
        photo image: CIImage,
        extent: CGRect
    ) -> SelectionMask? {
        var maskCI = CIImage(cgImage: rawMask)
        // SamKit often returns model-resolution mattes — scale to photo extent.
        if abs(maskCI.extent.width - extent.width) > 1
            || abs(maskCI.extent.height - extent.height) > 1
        {
            let sx = extent.width / max(maskCI.extent.width, 1)
            let sy = extent.height / max(maskCI.extent.height, 1)
            maskCI = maskCI.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }
        if maskCI.extent.origin != extent.origin {
            maskCI = maskCI.transformed(
                by: CGAffineTransform(
                    translationX: extent.minX - maskCI.extent.minX,
                    y: extent.minY - maskCI.extent.minY
                )
            )
        }
        maskCI = maskCI.cropped(to: extent)
        // SamKit hands back coverage in alpha over mid-grey RGB. Every downstream step
        // (polish, preview blend, ants contour) reads luminance, so canonicalise first.
        maskCI = SelectionMatteNormalization.opaqueCoverage(
            matte: maskCI,
            extent: extent,
            context: ciContext
        )

        if applyPolish {
            maskCI = SelectionMattePrecision.refine(mask: maskCI, photo: image, extent: extent)
        }

        guard let outCG = ciContext.createCGImage(maskCI, from: extent) else { return nil }
        if Self.isEffectivelyEmpty(outCG) { return nil }

        return SelectionMask(
            cgImage: outCG,
            extent: extent,
            confidence: score,
            semanticClass: .unknown,
            source: .coreML(modelID: SelectionModelArtifact.mobileSAM.id)
        )
    }

    private func loadSession() throws -> SamSession {
        lock.lock()
        defer { lock.unlock() }
        if let session { return session }
        let urls = try store.mobileSAMModelURLs()
        let ref = SamModelRef(
            encoderURL: urls.encoder,
            decoderURL: urls.decoder,
            inputSize: 1024,
            modelType: .mobileSam,
            promptEncoderWeightsURL: urls.weights
        )
        let created = try SamSession(model: ref, config: .bestAvailable)
        session = created
        return created
    }

    private static func samPoints(from prompt: SelectionPrompt) -> [SamPoint] {
        var points: [SamPoint] = []
        for p in prompt.positivePoints {
            points.append(SamPoint(x: p.x, y: p.y, label: .positive))
        }
        for p in prompt.negativePoints {
            points.append(SamPoint(x: p.x, y: p.y, label: .negative))
        }
        return points
    }

    private static func samBox(from rect: CGRect) -> SamBox? {
        guard !rect.isNull, !rect.isEmpty, rect.width > 1, rect.height > 1 else { return nil }
        return SamBox(
            x0: Float(rect.minX),
            y0: Float(rect.minY),
            x1: Float(rect.maxX),
            y1: Float(rect.maxY)
        )
    }

    private static func isEffectivelyEmpty(_ image: CGImage) -> Bool {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return true }
        let bytesPerRow = w
        var data = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &data,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return true }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Sample a sparse grid — empty mattes stay near zero.
        let stepX = max(1, w / 32)
        let stepY = max(1, h / 32)
        var lit = 0
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                if data[y * w + x] > 24 { lit += 1 }
                x += stepX
            }
            y += stepY
        }
        return lit < 3
    }
}
