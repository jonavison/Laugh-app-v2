import AppKit
import CoreImage
import UniformTypeIdentifiers

/// Writes a new still of the current **ImageMedia** with develop parameters applied.
/// Never replaces the source file.
enum ImageExportWriter {
    enum Format {
        case jpeg
        case png

        var utType: UTType {
            switch self {
            case .jpeg: return .jpeg
            case .png: return .png
            }
        }

        var pathExtension: String {
            switch self {
            case .jpeg: return "jpg"
            case .png: return "png"
            }
        }

        static func from(url: URL) -> Format {
            let ext = url.pathExtension.lowercased()
            if ext == "png" { return .png }
            return .jpeg
        }
    }

    static func suggestedFileName(for source: URL) -> String {
        let base = source.deletingPathExtension().lastPathComponent
        let stem = base.hasSuffix("-edited") ? base : "\(base)-edited"
        return "\(stem).jpg"
    }

    static func renderCGImage(
        sourceURL: URL,
        parameters: ImageAdjustParameters,
        quarterTurns: Int,
        cropNormalized: CGRect? = nil,
        straightenRadians: CGFloat = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false
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

        let context: CIContext
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            context = CIContext(options: [.cacheIntermediates: false])
        }
        let extent = ciImage.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }
        return context.createCGImage(ciImage, from: extent)
    }

    static func write(_ image: CGImage, to url: URL, format: Format) throws {
        let type = format.utType.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.92
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
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
