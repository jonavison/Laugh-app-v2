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
        let isRAW = MediaKindDetector.isCameraRAW(url)

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = cgFloat(properties[kCGImagePropertyPixelWidth]),
           let height = cgFloat(properties[kCGImagePropertyPixelHeight]),
           width > 0, height > 0 {
            let pixelSize = CGSize(width: width, height: height)
            let sourceLongEdge = max(width, height)
            let targetLongEdge = min(cap, sourceLongEdge)

            // Camera RAW: never call ImageIO Always / CIRAW on the hot path — both can hang
            // for minutes on NEF. Prefer the embedded JPEG and crop letterbox bands.
            if isRAW {
                if let image = rawEmbeddedPreview(from: source, maxPixelSize: cap) {
                    let long = longEdge(of: image)
                    switch tier {
                    case .scrub:
                        return (image, pixelSize)
                    case .quick where long >= min(targetLongEdge * 0.35, 320):
                        return (image, pixelSize)
                    case .fit where long >= min(targetLongEdge * 0.45, 640):
                        return (image, pixelSize)
                    case .quick, .fit:
                        break
                    }
                }
                // Last resort only for fit when the embedded preview is tiny / missing.
                if tier == .fit,
                   let raw = ImageRAWDecoder.demosaic(at: url, maxPixelSize: cap, draft: false) {
                    return (raw.image, raw.nativeSize)
                }
                if let image = rawEmbeddedPreview(from: source, maxPixelSize: cap) {
                    return (image, pixelSize)
                }
                return nil
            }

            switch tier {
            case .scrub:
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
                if let image = thumbnailImage(
                    from: source,
                    maxPixelSize: min(cap, 1024),
                    fromFullImage: true
                ) {
                    return (image, pixelSize)
                }

            case .fit:
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
        let display = ImageStudioCISource.displayNSImage(from: image)
        return (display, display.size)
    }

    /// Embedded camera JPEG from NEF/CR2/ARW — fast. Crops grey/white letterbox bands.
    private static func rawEmbeddedPreview(
        from source: CGImageSource,
        maxPixelSize: CGFloat
    ) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              cgImage.width > 1, cgImage.height > 1
        else {
            return nil
        }
        let cleaned = MediaThumbnailGenerator.removingUniformEdgeBands(cgImage)
        return ImageStudioCISource.displayNSImage(from: cleaned)
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
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false
        ]
        if fromFullImage {
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
        } else {
            options[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
        }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return ImageStudioCISource.displayNSImage(from: cgImage)
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
