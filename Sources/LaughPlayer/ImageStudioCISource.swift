import AppKit
import CoreImage
import CoreGraphics

/// Makes a still safe for Metal `CIContext` (ADR 0004 display graph).
///
/// `CIImage(cgImage:)` on 24-bit RGB, indexed, CMYK, or 16-bit sources can render as
/// colored stripe bars once any develop/geometry filter runs. The filmstrip blit
/// already redraws into 8-bit premul RGBA, which is why thumbs look fine.
enum ImageStudioCISource {
    static func ciImage(from cgImage: CGImage) -> CIImage {
        CIImage(cgImage: rgba8Premultiplied(cgImage))
    }

    /// Bitmap `NSImageView` can draw without YCbCr / 24-bit stripe artefacts.
    static func displayNSImage(from cgImage: CGImage) -> NSImage {
        let safe = rgba8Premultiplied(cgImage)
        return NSImage(cgImage: safe, size: NSSize(width: safe.width, height: safe.height))
    }

    static func displayNSImage(from image: NSImage) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        return displayNSImage(from: cgImage)
    }

    static func rgba8Premultiplied(_ image: CGImage) -> CGImage {
        if isMetalSafeRGBA8(image) { return image }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return image }
        let space = preferredRGBColorSpace(for: image)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    static func isMetalSafeRGBA8(_ image: CGImage) -> Bool {
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32 else { return false }
        guard image.colorSpace?.model == .rgb else { return false }
        let order = image.bitmapInfo.intersection(.byteOrderMask)
        if !order.isEmpty, order != .byteOrder32Little {
            return false
        }
        switch image.alphaInfo {
        case .premultipliedLast, .premultipliedFirst:
            return true
        default:
            return false
        }
    }

    private static func preferredRGBColorSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb {
            return space
        }
        return CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
    }
}
