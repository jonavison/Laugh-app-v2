import AppKit
import CoreImage

/// Thread-safe camera-RAW demosaic — **last resort only** (export / missing embedded JPEG).
///
/// Filmstrip and normal viewing must use ImageIO embedded previews. CIRAW on a shared
/// queue starved the UI for minutes and painted rainbow / white-band garbage into NEFs.
enum ImageRAWDecoder {
    private static let queue = DispatchQueue(label: "ch.laugh.raw-decode")
    private static let context: CIContext = {
        CIContext(options: [
            .cacheIntermediates: false,
            .highQualityDownsample: true
        ])
    }()

    /// Demosaic `url` scaled to `maxPixelSize` on the long edge.
    static func demosaic(
        at url: URL,
        maxPixelSize: CGFloat,
        draft: Bool
    ) -> (image: NSImage, nativeSize: CGSize)? {
        queue.sync {
            demosaicLocked(at: url, maxPixelSize: maxPixelSize, draft: draft)
        }
    }

    private static func demosaicLocked(
        at url: URL,
        maxPixelSize: CGFloat,
        draft: Bool
    ) -> (image: NSImage, nativeSize: CGSize)? {
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }
        filter.isDraftModeEnabled = draft
        let native = filter.nativeSize
        guard native.width > 1, native.height > 1 else { return nil }
        let longEdge = max(native.width, native.height)
        filter.scaleFactor = Float(min(1, maxPixelSize / longEdge))
        guard let ciImage = filter.outputImage else { return nil }
        let extent = ciImage.extent.integral
        guard extent.width > 1, extent.height > 1 else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let cgImage = context.createCGImage(
            ciImage,
            from: extent,
            format: .RGBA8,
            colorSpace: colorSpace,
            deferred: false
        ) else {
            return nil
        }
        let cleaned = MediaThumbnailGenerator.removingUniformEdgeBands(cgImage)
        let image = ImageStudioCISource.displayNSImage(from: cleaned)
        return (image, native)
    }
}
