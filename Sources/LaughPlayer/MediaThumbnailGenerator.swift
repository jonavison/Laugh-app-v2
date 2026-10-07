import AppKit
import AVFoundation
import CryptoKit
import Foundation
import ImageIO

/// Shared still/video thumbnails for library browse, folder collage, and image carousel.
/// ImageIO for stills + RAW embedded JPEGs (never CIRAW — demosaic starves the UI).
enum MediaThumbnailGenerator {
    private static let memoryCache = NSCache<NSString, NSImage>()
    /// V6: ImageIO+letterbox-crop for RAW; drop V5 CIRAW-corrupt / hung thumbs.
    private static let diskFolderName = "LaughPlayerThumbnailsV6"
    private static let legacyDiskFolderName = "LaughPlayerThumbnails"
    private static let legacyV2DiskFolderName = "LaughPlayerThumbnailsV2"
    private static let legacyV3DiskFolderName = "LaughPlayerThumbnailsV3"
    private static let legacyV4DiskFolderName = "LaughPlayerThumbnailsV4"
    private static let legacyV5DiskFolderName = "LaughPlayerThumbnailsV5"
    private static let legacyCleanupDefaultsKey = "LaughPlayerThumbnailsV1Cleared"
    private static let legacyV2CleanupDefaultsKey = "LaughPlayerThumbnailsV2Cleared"
    private static let legacyV3CleanupDefaultsKey = "LaughPlayerThumbnailsV3Cleared"
    private static let legacyV4CleanupDefaultsKey = "LaughPlayerThumbnailsV4Cleared"
    private static let legacyV5CleanupDefaultsKey = "LaughPlayerThumbnailsV5Cleared"

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

    /// Launch migration: drop legacy thumb caches that baked in grey RAW/EXIF previews.
    static func performLaunchMigrations() {
        let defaults = UserDefaults.standard
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let legacyFolders: [(key: String, folder: String)] = [
            (legacyCleanupDefaultsKey, legacyDiskFolderName),
            (legacyV2CleanupDefaultsKey, legacyV2DiskFolderName),
            (legacyV3CleanupDefaultsKey, legacyV3DiskFolderName),
            (legacyV4CleanupDefaultsKey, legacyV4DiskFolderName),
            (legacyV5CleanupDefaultsKey, legacyV5DiskFolderName)
        ]
        for entry in legacyFolders where !defaults.bool(forKey: entry.key) {
            let url = base.appendingPathComponent(entry.folder, isDirectory: true)
            try? FileManager.default.removeItem(at: url)
            defaults.set(true, forKey: entry.key)
        }
    }

    /// True when a large edge band is flat *and* differs from the photo body
    /// (truncated NEF preview / camera letterbox). Solid images are not flagged.
    static func hasUniformEdgeBand(_ image: CGImage) -> Bool {
        let trimmed = removingUniformEdgeBands(image)
        return trimmed.width != image.width || trimmed.height != image.height
    }

    /// Crops flat grey/white letterbox / truncated bands. Used for camera RAW previews.
    static func removingUniformEdgeBands(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        guard width >= 8, height >= 16 else { return image }
        let bodyY = height / 3
        let bodyH = max(4, height / 3)
        guard let body = bandStats(image, y: bodyY, bandHeight: bodyH) else { return image }

        let row = max(2, height / 40)
        let maxTrim = height / 3
        var bottomTrim = 0
        while bottomTrim + row <= maxTrim {
            guard let edge = bandStats(image, y: bottomTrim, bandHeight: row),
                  edge.isUniform,
                  colorDistance(edge.mean, body.mean) > 28
            else { break }
            bottomTrim += row
        }
        var topTrim = 0
        while topTrim + row <= maxTrim {
            guard let edge = bandStats(image, y: height - topTrim - row, bandHeight: row),
                  edge.isUniform,
                  colorDistance(edge.mean, body.mean) > 28
            else { break }
            topTrim += row
        }
        guard bottomTrim > 0 || topTrim > 0 else { return image }
        let cropH = height - bottomTrim - topTrim
        guard cropH >= 8 else { return image }
        // CGImage cropping uses bottom-left origin.
        let rect = CGRect(x: 0, y: bottomTrim, width: width, height: cropH)
        return image.cropping(to: rect) ?? image
    }

    /// Test seam: drop memory entries so the next load exercises disk cache.
    static func clearMemoryCacheForTesting() {
        memoryCache.removeAllObjects()
    }

    /// Test seam: reset the V1 cleanup flag (does not recreate files).
    static func resetLegacyCleanupFlagForTesting() {
        UserDefaults.standard.removeObject(forKey: legacyCleanupDefaultsKey)
        UserDefaults.standard.removeObject(forKey: legacyV2CleanupDefaultsKey)
        UserDefaults.standard.removeObject(forKey: legacyV3CleanupDefaultsKey)
        UserDefaults.standard.removeObject(forKey: legacyV4CleanupDefaultsKey)
        UserDefaults.standard.removeObject(forKey: legacyV5CleanupDefaultsKey)
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

    /// ImageIO thumbnail. RAW uses embedded JPEG only (`IfAbsent`) — `Always` / CIRAW hang.
    private static func imageIOThumbnail(for url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        let isRAW = MediaKindDetector.isCameraRAW(url)
        var attempts: [[CFString: Any]] = []
        let common: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false
        ]
        if isRAW {
            var ifAbsent = common
            ifAbsent[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
            attempts = [ifAbsent]
        } else {
            var always = common
            always[kCGImageSourceCreateThumbnailFromImageAlways] = true
            attempts = [always]
        }

        for options in attempts {
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  cgImage.width > 1, cgImage.height > 1
            else { continue }
            // Letterbox crop is RAW-only — transparent PNG corners look like “flat bands”.
            let cleaned = isRAW ? removingUniformEdgeBands(cgImage) : cgImage
            return ImageStudioCISource.displayNSImage(from: cleaned)
        }
        return nil
    }

    private struct BandStats {
        let mean: (r: Int, g: Int, b: Int)
        let isUniform: Bool
    }

    private static func bandStats(_ image: CGImage, y: Int, bandHeight: Int) -> BandStats? {
        let width = image.width
        let height = image.height
        guard bandHeight > 0, y >= 0, y + bandHeight <= height else { return nil }

        var data = [UInt8](repeating: 0, count: width * bandHeight * 4)
        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: bandHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.interpolationQuality = .none
        ctx.draw(
            image,
            in: CGRect(x: 0, y: -CGFloat(y), width: CGFloat(width), height: CGFloat(height))
        )

        let step = max(1, width / 24)
        var samples: [(Int, Int, Int)] = []
        samples.reserveCapacity((width / step) * max(1, bandHeight / 4))
        for row in stride(from: 0, to: bandHeight, by: max(1, bandHeight / 4)) {
            for col in stride(from: 0, to: width, by: step) {
                let i = (row * width + col) * 4
                samples.append((Int(data[i]), Int(data[i + 1]), Int(data[i + 2])))
            }
        }
        guard samples.count >= 8 else { return nil }

        let meanR = samples.reduce(0) { $0 + $1.0 } / samples.count
        let meanG = samples.reduce(0) { $0 + $1.1 } / samples.count
        let meanB = samples.reduce(0) { $0 + $1.2 } / samples.count
        var outlier = 0
        for sample in samples {
            if abs(sample.0 - meanR) > 12 || abs(sample.1 - meanG) > 12 || abs(sample.2 - meanB) > 12 {
                outlier += 1
            }
        }
        return BandStats(
            mean: (meanR, meanG, meanB),
            isUniform: Double(outlier) / Double(samples.count) < 0.08
        )
    }

    private static func colorDistance(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Int {
        abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
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
            return ImageStudioCISource.displayNSImage(from: cgImage)
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
