import AppKit
import CoreImage
import ImageIO

enum ImageDisplayLoader {
    /// Fit-quality decode for the surface (screen long edge @ backing scale).
    static func recommendedMaxPixelSize() -> CGFloat {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let scale = screen.backingScaleFactor
        return max(screen.frame.width, screen.frame.height) * scale
    }

    /// First-paint decode — small so sibling steps feel instant.
    static func quickPreviewMaxPixelSize() -> CGFloat {
        min(1024, recommendedMaxPixelSize())
    }

    /// Hold-to-scrub decode — intentionally soft so key-repeat never fights ImageIO.
    static func scrubPreviewMaxPixelSize() -> CGFloat {
        min(320, recommendedMaxPixelSize())
    }

    /// Shared GPU context for RAW demosaic (CIRAWFilter).
    private static let rawCIContext: CIContext = {
        CIContext(options: [
            .cacheIntermediates: false,
            .highQualityDownsample: true
        ])
    }()

    /// Metadata-only size read (no pixel decode). RAW reports sensor size, not the JPEG preview.
    static func pixelSize(at url: URL) -> CGSize? {
        if MediaKindDetector.isCameraRAW(url),
           let native = CIRAWFilter(imageURL: url)?.nativeSize,
           native.width > 1, native.height > 1 {
            return native
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = cgFloat(properties[kCGImagePropertyPixelWidth]),
              let height = cgFloat(properties[kCGImagePropertyPixelHeight]),
              width > 0, height > 0
        else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    static func loadScrubPreview(at url: URL) -> (image: NSImage, pixelSize: CGSize)? {
        loadDisplayImage(at: url, maxPixelSize: scrubPreviewMaxPixelSize(), tier: .scrub)
    }

    static func loadQuickPreview(at url: URL) -> (image: NSImage, pixelSize: CGSize)? {
        loadDisplayImage(at: url, maxPixelSize: quickPreviewMaxPixelSize(), tier: .quick)
    }

    static func loadDisplayImage(at url: URL, maxPixelSize: CGFloat? = nil) -> (image: NSImage, pixelSize: CGSize)? {
        loadDisplayImage(at: url, maxPixelSize: maxPixelSize, tier: .fit)
    }

    private enum DecodeTier {
        /// Soft hold-to-scrub: embedded thumb OK.
        case scrub
        /// First paint: embedded OK if large enough, else downsample full image.
        case quick
        /// Viewing quality: always decode from full pixels at the screen cap.
        case fit
    }

    private static func loadDisplayImage(
        at url: URL,
        maxPixelSize: CGFloat?,
        tier: DecodeTier
    ) -> (image: NSImage, pixelSize: CGSize)? {
        let cap = maxPixelSize ?? recommendedMaxPixelSize()

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = cgFloat(properties[kCGImagePropertyPixelWidth]),
           let height = cgFloat(properties[kCGImagePropertyPixelHeight]),
           width > 0, height > 0 {
            let pixelSize = CGSize(width: width, height: height)
            let sourceLongEdge = max(width, height)
            let targetLongEdge = min(cap, sourceLongEdge)

            switch tier {
            case .scrub:
                // Fast: accept embedded camera thumbs even when tiny.
                if let image = thumbnailImage(
                    from: source,
                    maxPixelSize: cap,
                    fromFullImage: false
                ) {
                    return (image, pixelSize)
                }
                if let image = thumbnailImage(
                    from: source,
                    maxPixelSize: min(cap, 480),
                    fromFullImage: true
                ) {
                    return (image, pixelSize)
                }

            case .quick:
                // Prefer embedded only when it’s actually useful (≥ ~half the requested preview).
                if let image = thumbnailImage(
                    from: source,
                    maxPixelSize: cap,
                    fromFullImage: false
                ), longEdge(of: image) >= min(targetLongEdge * 0.45, 480) {
                    return (image, pixelSize)
                }
                if let image = thumbnailImage(
                    from: source,
                    maxPixelSize: min(cap, 1024),
                    fromFullImage: true
                ) {
                    return (image, pixelSize)
                }

            case .fit:
                // RAW: demosaic sensor data (CIRAWFilter). ImageIO IfAbsent/Always often
                // returns the camera JPEG preview on NEF/CR2/ARW and looks soft forever.
                if MediaKindDetector.isCameraRAW(url),
                   let raw = loadRAWDemosaic(at: url, maxPixelSize: cap) {
                    return raw
                }
                // JPEG/HEIC/PNG: always decode from full pixels — never IfAbsent embedded thumbs.
                if let image = thumbnailImage(
                    from: source,
                    maxPixelSize: cap,
                    fromFullImage: true
                ) {
                    return (image, pixelSize)
                }
            }
        }

        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        return (image, image.size)
    }

    /// Full RAW processor output scaled to `maxPixelSize`. `pixelSize` is native sensor size.
    private static func loadRAWDemosaic(
        at url: URL,
        maxPixelSize: CGFloat
    ) -> (image: NSImage, pixelSize: CGSize)? {
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }
        filter.isDraftModeEnabled = false
        let native = filter.nativeSize
        guard native.width > 1, native.height > 1 else { return nil }
        let longEdge = max(native.width, native.height)
        filter.scaleFactor = Float(min(1, maxPixelSize / longEdge))
        guard let ciImage = filter.outputImage else { return nil }
        let extent = ciImage.extent.integral
        guard extent.width > 1, extent.height > 1,
              let cgImage = rawCIContext.createCGImage(ciImage, from: extent)
        else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return (image, native)
    }

    /// - Parameter fromFullImage: `true` uses Always (decode/downsample source pixels).
    ///   `false` uses IfAbsent (may return a tiny embedded EXIF/HEIC preview).
    private static func thumbnailImage(
        from source: CGImageSource,
        maxPixelSize: CGFloat,
        fromFullImage: Bool
    ) -> NSImage? {
        var options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if fromFullImage {
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
        } else {
            options[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
        }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func longEdge(of image: NSImage) -> CGFloat {
        max(image.size.width, image.size.height)
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        if let n = value as? CGFloat { return n }
        if let n = value as? Double { return CGFloat(n) }
        if let n = value as? Int { return CGFloat(n) }
        if let n = value as? NSNumber { return CGFloat(truncating: n) }
        return nil
    }
}
