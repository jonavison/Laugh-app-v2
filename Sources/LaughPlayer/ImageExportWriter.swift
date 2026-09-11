import AppKit
import CoreImage
import UniformTypeIdentifiers

/// Writes a new still of the current **ImageMedia** with develop parameters applied.
/// Never replaces the source file.
enum ImageExportWriter {
    /// Legacy alias used by cutout + older call sites.
    typealias Format = ImageExportOptions.Format

    static func suggestedFileName(for source: URL, format: ImageExportOptions.Format = .jpeg) -> String {
        let base = source.deletingPathExtension().lastPathComponent
        let stem = base.hasSuffix("-edited") ? base : "\(base)-edited"
        return "\(stem).\(format.pathExtension)"
    }

    static func suggestedCutoutFileName(for source: URL) -> String {
        let base = source.deletingPathExtension().lastPathComponent
        let stem = base.hasSuffix("-cutout") ? base : "\(base)-cutout"
        return "\(stem).png"
    }

    /// Pixel size after crop / rotate / flip / straighten (develop adjusts do not change size).
    static func geometryPixelSize(
        sourceURL: URL,
        quarterTurns: Int,
        cropNormalized: CGRect? = nil,
        straightenRadians: CGFloat = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false
    ) -> CGSize? {
        let loaded = ImageDisplayLoader.loadDisplayImage(at: sourceURL, maxPixelSize: 16_000)
        guard let nsImage = loaded?.image,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgSource = bitmap.cgImage
        else { return nil }

        var ciImage = CIImage(cgImage: cgSource)
        ciImage = rotated(ciImage, quarterTurns: quarterTurns)
        ciImage = flipped(ciImage, horizontal: flipHorizontal, vertical: flipVertical)
        ciImage = straightened(ciImage, radians: straightenRadians)
        if let cropNormalized, !ImageCropGeometry.isIdentity(cropNormalized) {
            let size = CGSize(width: ciImage.extent.width, height: ciImage.extent.height)
            let pixel = ImageCropGeometry.pixelRect(normalized: cropNormalized, imageSize: size)
            let cropInExtent = pixel.offsetBy(dx: ciImage.extent.minX, dy: ciImage.extent.minY)
            ciImage = ciImage.cropped(to: cropInExtent)
        }
        let extent = ciImage.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }
        return CGSize(width: extent.width, height: extent.height)
    }

    static func renderCGImage(
        sourceURL: URL,
        parameters: ImageAdjustParameters,
        quarterTurns: Int,
        cropNormalized: CGRect? = nil,
        straightenRadians: CGFloat = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        exportOptions: ImageExportOptions = .default
    ) -> CGImage? {
        let loaded = ImageDisplayLoader.loadDisplayImage(at: sourceURL, maxPixelSize: 16_000)
        guard let nsImage = loaded?.image,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgSource = bitmap.cgImage
        else { return nil }

        var ciImage = CIImage(cgImage: cgSource)
        ciImage = rotated(ciImage, quarterTurns: quarterTurns)
        ciImage = flipped(ciImage, horizontal: flipHorizontal, vertical: flipVertical)
        ciImage = straightened(ciImage, radians: straightenRadians)
        if let cropNormalized, !ImageCropGeometry.isIdentity(cropNormalized) {
            let size = CGSize(width: ciImage.extent.width, height: ciImage.extent.height)
            let pixel = ImageCropGeometry.pixelRect(normalized: cropNormalized, imageSize: size)
            let cropInExtent = pixel.offsetBy(dx: ciImage.extent.minX, dy: ciImage.extent.minY)
            ciImage = ciImage.cropped(to: cropInExtent)
            if ciImage.extent.origin != .zero {
                ciImage = ciImage.transformed(
                    by: CGAffineTransform(translationX: -ciImage.extent.minX, y: -ciImage.extent.minY)
                )
            }
        }
        if let adjusted = parameters.applying(to: ciImage) {
            ciImage = adjusted
        }

        let sourceExtent = ciImage.extent.integral
        let sourcePixels = CGSize(width: sourceExtent.width, height: sourceExtent.height)
        let target = exportOptions.outputPixelSize(sourcePixels: sourcePixels)
        ciImage = scaled(ciImage, to: target)
        ciImage = sharpened(ciImage, amount: exportOptions.sharpen)

        let context = makeCIContext()
        let extent = ciImage.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }
        guard let rendered = context.createCGImage(
            ciImage,
            from: extent,
            format: .RGBA8,
            colorSpace: exportOptions.colorSpace.cgColorSpace,
            deferred: false
        ) else { return nil }
        return rendered
    }

    /// Alpha PNG cutout of the subject matte. Writes a new file only — never overwrites the source.
    static func renderCutoutCGImage(
        sourceURL: URL,
        parameters: ImageAdjustParameters,
        selectionMask: SelectionMask,
        quarterTurns: Int,
        cropNormalized: CGRect? = nil,
        straightenRadians: CGFloat = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        refine: SelectionRefineParameters = .identity
    ) -> CGImage? {
        let loaded = ImageDisplayLoader.loadDisplayImage(at: sourceURL, maxPixelSize: 16_000)
        guard let nsImage = loaded?.image,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgSource = bitmap.cgImage
        else { return nil }

        var ciImage = CIImage(cgImage: cgSource)
        let sourceExtent = ciImage.extent
        var maskCI = selectionMask.ciImageMatching(extent: sourceExtent)

        ciImage = rotated(ciImage, quarterTurns: quarterTurns)
        maskCI = rotated(maskCI, quarterTurns: quarterTurns)
        ciImage = flipped(ciImage, horizontal: flipHorizontal, vertical: flipVertical)
        maskCI = flipped(maskCI, horizontal: flipHorizontal, vertical: flipVertical)
        ciImage = straightened(ciImage, radians: straightenRadians)
        maskCI = straightened(maskCI, radians: straightenRadians)
        if let cropNormalized, !ImageCropGeometry.isIdentity(cropNormalized) {
            let size = CGSize(width: ciImage.extent.width, height: ciImage.extent.height)
            let pixel = ImageCropGeometry.pixelRect(normalized: cropNormalized, imageSize: size)
            let cropInExtent = pixel.offsetBy(dx: ciImage.extent.minX, dy: ciImage.extent.minY)
            ciImage = ciImage.cropped(to: cropInExtent)
            maskCI = maskCI.cropped(to: cropInExtent)
            if ciImage.extent.origin != .zero {
                let t = CGAffineTransform(
                    translationX: -ciImage.extent.minX,
                    y: -ciImage.extent.minY
                )
                ciImage = ciImage.transformed(by: t)
                maskCI = maskCI.transformed(by: t)
            }
        }
        if let adjusted = parameters.applying(to: ciImage) {
            ciImage = adjusted
        }

        let cutoutMask = SelectionMask(
            cgImage: selectionMask.cgImage,
            extent: maskCI.extent,
            confidence: selectionMask.confidence,
            semanticClass: selectionMask.semanticClass,
            source: selectionMask.source
        )
        let context = makeCIContext()
        let maskExtent = maskCI.extent.integral
        guard let maskCG = context.createCGImage(maskCI, from: maskExtent) else { return nil }
        let alignedMask = SelectionMask(
            cgImage: maskCG,
            extent: maskExtent,
            confidence: cutoutMask.confidence,
            semanticClass: cutoutMask.semanticClass,
            source: cutoutMask.source
        )
        ciImage = SelectionCompositor.cutoutWithAlpha(image: ciImage, mask: alignedMask, refine: refine)

        let extent = ciImage.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }
        return context.createCGImage(
            ciImage,
            from: extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            deferred: false
        )
    }

    static func write(_ image: CGImage, to url: URL, format: Format) throws {
        var options = ImageExportOptions.default
        options.format = format
        try write(image, to: url, options: options)
    }

    static func write(_ image: CGImage, to url: URL, options: ImageExportOptions) throws {
        switch options.format {
        case .pdf:
            try writePDF(image, to: url, dpi: options.clampedDPI)
        case .jpeg, .png, .tiff, .jpeg2000, .webp:
            try writeImageIO(image, to: url, options: options)
        }
    }

    private static func writeImageIO(_ image: CGImage, to url: URL, options: ImageExportOptions) throws {
        let type = options.format.utType.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: options.clampedDPI,
            kCGImagePropertyDPIHeight: options.clampedDPI
        ]
        if options.format.supportsLossyQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = options.clampedQuality
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func writePDF(_ image: CGImage, to url: URL, dpi: Double) throws {
        let widthPt = CGFloat(image.width) * (72.0 / max(dpi, 1))
        let heightPt = CGFloat(image.height) * (72.0 / max(dpi, 1))
        var mediaBox = CGRect(x: 0, y: 0, width: widthPt, height: heightPt)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.beginPDFPage(nil)
        context.interpolationQuality = .high
        context.draw(image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
    }

    private static func makeCIContext() -> CIContext {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }

    private static func scaled(_ image: CIImage, to target: CGSize) -> CIImage {
        let extent = image.extent
        let sw = extent.width
        let sh = extent.height
        guard sw > 1, sh > 1 else { return image }
        let sx = target.width / sw
        let sy = target.height / sh
        if abs(sx - 1) < 0.000_5, abs(sy - 1) < 0.000_5 {
            return image
        }

        // Uniform scales use Lanczos; non-uniform (rare) falls back to affine.
        if abs(sx - sy) < 0.000_5, let filter = CIFilter(name: "CILanczosScaleTransform") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(sx, forKey: kCIInputScaleKey)
            filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
            if var out = filter.outputImage {
                if out.extent.origin != .zero {
                    out = out.transformed(
                        by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY)
                    )
                }
                return out
            }
        }

        var out = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        if out.extent.origin != .zero {
            out = out.transformed(
                by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY)
            )
        }
        return out
    }

    private static func sharpened(_ image: CIImage, amount: ImageExportOptions.Sharpen) -> CIImage {
        guard let unsharp = amount.unsharp,
              let filter = CIFilter(name: "CIUnsharpMask")
        else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(unsharp.radius, forKey: kCIInputRadiusKey)
        filter.setValue(unsharp.intensity, forKey: kCIInputIntensityKey)
        return filter.outputImage ?? image
    }

    private static func rotated(_ image: CIImage, quarterTurns: Int) -> CIImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return image }
        let radians = CGFloat(turns) * (.pi / 2)
        var transformed = image.transformed(by: CGAffineTransform(rotationAngle: radians))
        let extent = transformed.extent
        transformed = transformed.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
        return transformed
    }

    private static func flipped(
        _ image: CIImage,
        horizontal: Bool,
        vertical: Bool
    ) -> CIImage {
        guard horizontal || vertical else { return image }
        let extent = image.extent
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: extent.midX, y: extent.midY)
        transform = transform.scaledBy(x: horizontal ? -1 : 1, y: vertical ? -1 : 1)
        transform = transform.translatedBy(x: -extent.midX, y: -extent.midY)
        var out = image.transformed(by: transform)
        out = out.cropped(to: out.extent.integral)
        if out.extent.origin != .zero {
            out = out.transformed(
                by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY)
            )
        }
        return out
    }

    private static func straightened(_ image: CIImage, radians: CGFloat) -> CIImage {
        let angle = ImageCropGeometry.clampStraightenRadians(radians)
        guard !ImageCropGeometry.isIdentityStraighten(angle) else { return image }
        let extent = image.extent
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: extent.midX, y: extent.midY)
        transform = transform.rotated(by: angle)
        transform = transform.translatedBy(x: -extent.midX, y: -extent.midY)
        var out = image.transformed(by: transform)
        out = out.cropped(to: out.extent.integral)
        if out.extent.origin != .zero {
            out = out.transformed(
                by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY)
            )
        }
        return out
    }
}
