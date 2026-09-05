import AppKit
import AVFoundation
import CryptoKit
import Foundation
import ImageIO

/// Library / browse thumbnails: ImageIO for stills (incl. RAW embedded previews),
/// native AV + bundled ffmpeg for video.
enum MediaThumbnailGenerator {
    private static let memoryCache = NSCache<NSString, NSImage>()
    private static let diskFolderName = "LaughPlayerThumbnails"

    static func thumbnail(for url: URL, kind: DroppedMediaKind, maxSide: CGFloat = 200) -> NSImage? {
        let key = cacheKey(for: url) as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        let image: NSImage?
        switch kind {
        case .image:
            image = imageThumbnail(for: url, maxSide: maxSide, cacheKey: key as String)
        case .video:
            image = videoThumbnail(for: url, maxSide: maxSide, cacheKey: key as String)
        case .unsupported:
            image = nil
        }

        if let image {
            memoryCache.setObject(image, forKey: key)
        }
        return image
    }

    private static func imageThumbnail(for url: URL, maxSide: CGFloat, cacheKey: String) -> NSImage? {
        if let disk = loadDiskCache(cacheKey: cacheKey) {
            return disk
        }

        // ImageIO extracts embedded JPEG previews from NEF/CR2/ARW/DNG and
        // downsamples JPEG/HEIC without loading the full decode on a background thread.
        let pixelCap = max(maxSide * 2, 320)
        if let image = imageIOThumbnail(for: url, maxPixelSize: pixelCap) {
            storeDiskCache(image, cacheKey: cacheKey)
            return image
        }

        // Last resort — some exotic formats only open via NSImage.
        guard let source = NSImage(contentsOf: url), source.size.width > 1 else { return nil }
        let down = downsampleThreadSafe(source, maxSide: maxSide)
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
            return downsampleThreadSafe(disk, maxSide: maxSide)
        }

        if let native = avFoundationThumbnail(for: url) {
            storeDiskCache(native, cacheKey: cacheKey)
            return downsampleThreadSafe(native, maxSide: maxSide)
        }

        if let ffmpeg = ffmpegThumbnail(for: url) {
            storeDiskCache(ffmpeg, cacheKey: cacheKey)
            return downsampleThreadSafe(ffmpeg, maxSide: maxSide)
        }

        return nil
    }

    private static func avFoundationThumbnail(for url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
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
                "-vf", "scale=320:-2",
                "-q:v", "4",
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

    private static func cacheKey(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let mod = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        let identity = "\(url.path)|\(mod)|\(size)"
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func diskCacheURL(cacheKey: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent(diskFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("\(cacheKey).jpg")
    }

    private static func loadDiskCache(cacheKey: String) -> NSImage? {
        let url = diskCacheURL(cacheKey: cacheKey)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func storeDiskCache(_ image: NSImage, cacheKey: String) {
        let url = diskCacheURL(cacheKey: cacheKey)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
            return
        }
        try? jpeg.write(to: url, options: .atomic)
    }

    /// Thread-safe resize (no `lockFocus`, safe on utility queues used by the library grid).
    private static func downsampleThreadSafe(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = min(maxSide / max(width, 1), maxSide / max(height, 1), 1)
        guard scale < 0.999 else {
            return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        }

        let targetW = max(1, Int((width * scale).rounded()))
        let targetH = max(1, Int((height * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        guard let scaled = context.makeImage() else {
            return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        }
        return NSImage(cgImage: scaled, size: NSSize(width: targetW, height: targetH))
    }
}
