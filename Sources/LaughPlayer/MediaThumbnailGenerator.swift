import AppKit
import AVFoundation
import CryptoKit
import Foundation
import ImageIO

/// Shared still/video thumbnails for library browse, folder collage, and image carousel.
/// ImageIO for stills (incl. RAW embedded previews); native AV + bundled ffmpeg for video.
enum MediaThumbnailGenerator {
    private static let memoryCache = NSCache<NSString, NSImage>()
    /// V2: PNG for alpha stills + higher JPEG quality; old JPEG-only cache flattened transparency.
    private static let diskFolderName = "LaughPlayerThumbnailsV2"
    private static let legacyDiskFolderName = "LaughPlayerThumbnails"
    private static let legacyCleanupDefaultsKey = "LaughPlayerThumbnailsV1Cleared"

    /// Minimum decode cap so Gallery @2x (~320pt tiles) stays sharp even when asked for a small maxSide.
    private static let minimumImagePixelCap: CGFloat = 960

    /// Aspect-preserved thumbnail sized for `maxSide` points at `screenScale`.
    static func thumbnail(
        for url: URL,
        kind: DroppedMediaKind,
        maxSide: CGFloat = 200,
        screenScale: CGFloat = defaultScreenScale()
    ) -> NSImage? {
        let scale = sanitizedScale(screenScale)
        let pixelCap = imagePixelCap(for: maxSide, screenScale: scale)
        let key = cacheKey(for: url, pixelCap: pixelCap) as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        let image: NSImage?
        switch kind {
        case .image:
            image = imageThumbnail(for: url, maxSide: maxSide, pixelCap: pixelCap, cacheKey: key as String)
        case .video:
            image = videoThumbnail(for: url, maxSide: max(maxSide * scale, 1), cacheKey: key as String)
        case .unsupported:
            image = nil
        }

        if let image {
            memoryCache.setObject(image, forKey: key)
        }
        return image
    }

    /// Square crop-fill thumb for filmstrips / fixed cells. Preserves alpha (composites with sourceOver).
    static func squareThumbnail(
        for url: URL,
        kind: DroppedMediaKind,
        pointSide: CGFloat,
        screenScale: CGFloat = defaultScreenScale()
    ) -> NSImage? {
        let scale = sanitizedScale(screenScale)
        guard let full = thumbnail(for: url, kind: kind, maxSide: pointSide, screenScale: scale) else {
            return nil
        }
        return cropFill(
            full,
            pointSize: NSSize(width: pointSide, height: pointSide),
            screenScale: scale
        )
    }

    /// Fast pixel size for gallery masonry (no full thumbnail decode when possible).
    static func pixelSize(for url: URL, kind: DroppedMediaKind) -> NSSize? {
        switch kind {
        case .image:
            return imagePixelSize(for: url)
        case .video:
            return NSSize(width: 16, height: 9)
        case .unsupported:
            return nil
        }
    }

    /// Launch migration: drop the V1 JPEG-only disk cache (flattened alpha / soft encodes).
    static func performLaunchMigrations() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyCleanupDefaultsKey) else { return }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let legacy = base.appendingPathComponent(legacyDiskFolderName, isDirectory: true)
        try? FileManager.default.removeItem(at: legacy)
        defaults.set(true, forKey: legacyCleanupDefaultsKey)
    }

    /// Test seam: drop memory entries so the next load exercises disk cache.
    static func clearMemoryCacheForTesting() {
        memoryCache.removeAllObjects()
    }

    /// Test seam: reset the V1 cleanup flag (does not recreate files).
    static func resetLegacyCleanupFlagForTesting() {
        UserDefaults.standard.removeObject(forKey: legacyCleanupDefaultsKey)
    }

    static func defaultScreenScale() -> CGFloat {
        sanitizedScale(NSScreen.main?.backingScaleFactor ?? 2)
    }

    // MARK: - Decode sizing

    private static func sanitizedScale(_ scale: CGFloat) -> CGFloat {
        max(scale, 1)
    }

    private static func imagePixelCap(for maxSide: CGFloat, screenScale: CGFloat) -> CGFloat {
        max(maxSide * screenScale, minimumImagePixelCap)
    }

    private static func imagePixelSize(for url: URL) -> NSSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }
        let width = props[kCGImagePropertyPixelWidth] as? CGFloat
            ?? (props[kCGImagePropertyPixelWidth] as? NSNumber).map { CGFloat(truncating: $0) }
        let height = props[kCGImagePropertyPixelHeight] as? CGFloat
            ?? (props[kCGImagePropertyPixelHeight] as? NSNumber).map { CGFloat(truncating: $0) }
        guard let width, let height, width > 1, height > 1 else { return nil }

        // Honor EXIF orientation so portrait shots aren't laid out as landscape.
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if [5, 6, 7, 8].contains(orientation) {
            return NSSize(width: height, height: width)
        }
        return NSSize(width: width, height: height)
    }

    private static func imageThumbnail(
        for url: URL,
        maxSide: CGFloat,
        pixelCap: CGFloat,
        cacheKey: String
    ) -> NSImage? {
        if let disk = loadDiskCache(cacheKey: cacheKey) {
            return disk
        }

        // ImageIO extracts embedded JPEG previews from NEF/CR2/ARW/DNG and
        // downsamples JPEG/HEIC without loading the full decode on a background thread.
        if let image = imageIOThumbnail(for: url, maxPixelSize: pixelCap) {
            storeDiskCache(image, cacheKey: cacheKey)
            return image
        }

        // Last resort — some exotic formats only open via NSImage.
        guard let source = NSImage(contentsOf: url), source.size.width > 1 else { return nil }
        let down = downsampleThreadSafe(source, maxPixelSide: pixelCap)
        storeDiskCache(down, cacheKey: cacheKey)
        return down
    }

    /// Prefer embedded thumb when present (RAW); otherwise create a scaled decode.
    private static func imageIOThumbnail(for url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        let attempts: [[CFString: Any]] = [
            // RAW / camera files: use embedded preview when available (fast, reliable for .nef).
            [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ],
            // Standard stills without a stored thumb: force a thumbnail decode.
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
        ]

        for options in attempts {
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
               cgImage.width > 1, cgImage.height > 1 {
                return NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
                )
            }
        }
        return nil
    }

    private static func videoThumbnail(for url: URL, maxSide: CGFloat, cacheKey: String) -> NSImage? {
        if let disk = loadDiskCache(cacheKey: cacheKey) {
            return downsampleThreadSafe(disk, maxPixelSide: maxSide)
        }

        if let native = avFoundationThumbnail(for: url) {
            storeDiskCache(native, cacheKey: cacheKey)
            return downsampleThreadSafe(native, maxPixelSide: maxSide)
        }

        if let ffmpeg = ffmpegThumbnail(for: url) {
            storeDiskCache(ffmpeg, cacheKey: cacheKey)
            return downsampleThreadSafe(ffmpeg, maxPixelSide: maxSide)
        }

        return nil
    }

    private static func avFoundationThumbnail(for url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let times: [CMTime] = [
            CMTime(seconds: 1.0, preferredTimescale: 600),
            CMTime(seconds: 0.5, preferredTimescale: 600),
            .zero
        ]
        for time in times {
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        return nil
    }

    private static func ffmpegThumbnail(for url: URL) -> NSImage? {
        guard FFmpegVideoFallback.isAvailable(),
              let ffmpeg = BundledCodecTools.ffmpegExecutablePath() else {
            return nil
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaughPlayerThumbScratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let output = tempDir.appendingPathComponent("\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: output) }

        // Seek before input for speed; retry at 0s if the file is very short.
        let seekPoints = ["1", "0"]
        for seek in seekPoints {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = [
                "-hide_banner",
                "-loglevel", "error",
                "-ss", seek,
                "-i", url.path,
                "-an",
                "-frames:v", "1",
                "-vf", "scale=640:-2",
                "-q:v", "3",
                "-y",
                output.path
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                continue
            }
            guard process.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: output.path),
                  let image = NSImage(contentsOf: output),
                  image.size.width > 1 else {
                continue
            }
            return image
        }
        return nil
    }

    // MARK: - Cache

    private static func cacheKey(for url: URL, pixelCap: CGFloat) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let mod = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        let identity = "\(url.path)|\(mod)|\(size)|\(Int(pixelCap.rounded()))"
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func diskCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent(diskFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func diskCacheURL(cacheKey: String, ext: String) -> URL {
        diskCacheDirectory().appendingPathComponent("\(cacheKey).\(ext)")
    }

    private static func loadDiskCache(cacheKey: String) -> NSImage? {
        for ext in ["png", "jpg"] {
            let url = diskCacheURL(cacheKey: cacheKey, ext: ext)
            guard FileManager.default.fileExists(atPath: url.path),
                  let image = NSImage(contentsOf: url),
                  image.size.width > 1 else {
                continue
            }
            return image
        }
        return nil
    }

    private static func storeDiskCache(_ image: NSImage, cacheKey: String) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)

        if imageHasAlphaChannel(cgImage) {
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: diskCacheURL(cacheKey: cacheKey, ext: "png"), options: .atomic)
            // Avoid stale JPEG from a prior encode of the same key.
            try? FileManager.default.removeItem(at: diskCacheURL(cacheKey: cacheKey, ext: "jpg"))
            return
        }

        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) else {
            return
        }
        try? jpeg.write(to: diskCacheURL(cacheKey: cacheKey, ext: "jpg"), options: .atomic)
        try? FileManager.default.removeItem(at: diskCacheURL(cacheKey: cacheKey, ext: "png"))
    }

    private static func imageHasAlphaChannel(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            return false
        default:
            return true
        }
    }

    // MARK: - Compositing (shared: carousel + any future crop-fill caller)

    /// Aspect-fill into a point-sized bitmap at `screenScale`. Uses sourceOver so alpha stays intact.
    static func cropFill(
        _ image: NSImage,
        pointSize: NSSize,
        screenScale: CGFloat,
        background: NSColor? = nil
    ) -> NSImage {
        let scale = sanitizedScale(screenScale)
        let pixelW = max(1, Int((pointSize.width * scale).rounded()))
        let pixelH = max(1, Int((pointSize.height * scale).rounded()))
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let colorSpace = preferredColorSpace(for: cgImage)
        guard let context = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .high

        if let background {
            context.setFillColor(background.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        } else {
            context.clear(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        }

        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        let fill = max(CGFloat(pixelW) / max(srcW, 1), CGFloat(pixelH) / max(srcH, 1))
        let drawW = srcW * fill
        let drawH = srcH * fill
        let origin = CGPoint(
            x: (CGFloat(pixelW) - drawW) / 2,
            y: (CGFloat(pixelH) - drawH) / 2
        )
        context.draw(cgImage, in: CGRect(origin: origin, size: CGSize(width: drawW, height: drawH)))

        guard let scaled = context.makeImage() else { return image }
        return NSImage(cgImage: scaled, size: pointSize)
    }

    /// Thread-safe resize (no `lockFocus`, safe on utility queues used by the library grid).
    private static func downsampleThreadSafe(_ image: NSImage, maxPixelSide: CGFloat) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = min(maxPixelSide / max(width, 1), maxPixelSide / max(height, 1), 1)
        guard scale < 0.999 else {
            return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        }

        let targetW = max(1, Int((width * scale).rounded()))
        let targetH = max(1, Int((height * scale).rounded()))
        let colorSpace = preferredColorSpace(for: cgImage)
        guard let context = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        guard let scaled = context.makeImage() else {
            return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        }
        return NSImage(cgImage: scaled, size: NSSize(width: targetW, height: targetH))
    }

    private static func preferredColorSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace {
            return space
        }
        return CGColorSpace(name: CGColorSpace.displayP3)
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
    }
}
