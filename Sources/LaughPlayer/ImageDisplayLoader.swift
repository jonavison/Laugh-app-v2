import AppKit
import ImageIO

enum ImageDisplayLoader {
    static func recommendedMaxPixelSize() -> CGFloat {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let scale = screen.backingScaleFactor
        return max(screen.frame.width, screen.frame.height) * scale * 2
    }

    static func loadDisplayImage(at url: URL, maxPixelSize: CGFloat? = nil) -> (image: NSImage, pixelSize: CGSize)? {
        let cap = maxPixelSize ?? recommendedMaxPixelSize()

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
           width > 0, height > 0 {
            let pixelSize = CGSize(width: width, height: height)
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: cap,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                return (image, pixelSize)
            }
        }

        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        return (image, image.size)
    }
}
