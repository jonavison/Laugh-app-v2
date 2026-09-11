import AppKit
import UniformTypeIdentifiers

/// User-facing still-export settings (options sheet → save panel → write).
struct ImageExportOptions: Equatable, Codable {
    var format: Format
    var resize: ResizeMode
    /// Pixel width for custom resize modes (ignored when `.original`).
    var width: Int
    /// Pixel height for custom resize modes (ignored when `.original`).
    var height: Int
    /// Percent of original longest edge when `resize == .percent` (1…1000).
    var percent: Int
    var sharpen: Sharpen
    var colorSpace: ExportColorSpace
    /// Dots per inch written into image metadata (print apps).
    var resolutionDPI: Double
    /// Lossy quality 1…100 (JPEG / WebP / JPEG-2000).
    var quality: Int

    static let `default` = ImageExportOptions(
        format: .jpeg,
        resize: .original,
        width: 0,
        height: 0,
        percent: 100,
        sharpen: .none,
        colorSpace: .sRGB,
        resolutionDPI: 240,
        quality: 92
    )

    enum Format: String, CaseIterable, Codable {
        case jpeg
        case png
        case tiff
        case jpeg2000
        case pdf
        case webp

        var menuTitle: String {
            switch self {
            case .jpeg: return "JPEG"
            case .png: return "PNG"
            case .tiff: return "TIFF"
            case .jpeg2000: return "JPEG-2000"
            case .pdf: return "PDF"
            case .webp: return "WebP"
            }
        }

        var pathExtension: String {
            switch self {
            case .jpeg: return "jpg"
            case .png: return "png"
            case .tiff: return "tiff"
            case .jpeg2000: return "jp2"
            case .pdf: return "pdf"
            case .webp: return "webp"
            }
        }

        var utType: UTType {
            switch self {
            case .jpeg: return .jpeg
            case .png: return .png
            case .tiff: return .tiff
            case .jpeg2000: return UTType(filenameExtension: "jp2") ?? .jpeg
            case .pdf: return .pdf
            case .webp: return .webP
            }
        }

        var supportsLossyQuality: Bool {
            switch self {
            case .jpeg, .jpeg2000, .webp: return true
            case .png, .tiff, .pdf: return false
            }
        }

        var supportsAlpha: Bool {
            switch self {
            case .png, .tiff, .webp, .pdf: return true
            case .jpeg, .jpeg2000: return false
            }
        }

        static func from(url: URL) -> Format {
            switch url.pathExtension.lowercased() {
            case "png": return .png
            case "tif", "tiff": return .tiff
            case "jp2", "j2k", "jpf", "jpx": return .jpeg2000
            case "pdf": return .pdf
            case "webp": return .webp
            default: return .jpeg
            }
        }
    }

    enum ResizeMode: String, CaseIterable, Codable {
        case original
        case longestEdge
        case width
        case height
        case percent

        var menuTitle: String {
            switch self {
            case .original: return "Original"
            case .longestEdge: return "Longest edge"
            case .width: return "Width"
            case .height: return "Height"
            case .percent: return "Percent"
            }
        }
    }

    enum Sharpen: String, CaseIterable, Codable {
        case none
        case low
        case medium
        case high

        var menuTitle: String {
            switch self {
            case .none: return "None"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            }
        }

        /// CIUnsharpMask intensity / radius, or nil to skip.
        var unsharp: (intensity: Double, radius: Double)? {
            switch self {
            case .none: return nil
            case .low: return (0.35, 1.5)
            case .medium: return (0.55, 2.0)
            case .high: return (0.85, 2.6)
            }
        }
    }

    enum ExportColorSpace: String, CaseIterable, Codable {
        case sRGB
        case displayP3

        var menuTitle: String {
            switch self {
            case .sRGB: return "sRGB"
            case .displayP3: return "Display P3"
            }
        }

        var cgColorSpace: CGColorSpace {
            switch self {
            case .sRGB:
                return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            case .displayP3:
                return CGColorSpace(name: CGColorSpace.displayP3)
                    ?? CGColorSpace(name: CGColorSpace.sRGB)
                    ?? CGColorSpaceCreateDeviceRGB()
            }
        }
    }

    /// Pixel size after resize for a source pixel size.
    func outputPixelSize(sourcePixels: CGSize) -> CGSize {
        ImageExportResize.outputPixelSize(source: sourcePixels, options: self)
    }

    mutating func syncDimensionsFromSource(_ sourcePixels: CGSize) {
        let out = outputPixelSize(sourcePixels: sourcePixels)
        width = max(1, Int(out.width.rounded()))
        height = max(1, Int(out.height.rounded()))
    }

    var clampedQuality: Double {
        Double(min(100, max(1, quality))) / 100.0
    }

    var clampedDPI: Double {
        min(1200, max(36, resolutionDPI))
    }
}

enum ImageExportResize {
    static func outputPixelSize(source: CGSize, options: ImageExportOptions) -> CGSize {
        let sw = max(1, source.width)
        let sh = max(1, source.height)
        switch options.resize {
        case .original:
            return CGSize(width: sw, height: sh)
        case .percent:
            let p = Double(min(1000, max(1, options.percent))) / 100.0
            return CGSize(
                width: max(1, (sw * p).rounded()),
                height: max(1, (sh * p).rounded())
            )
        case .longestEdge:
            let edge = Double(max(1, options.width > 0 ? options.width : Int(max(sw, sh))))
            let longest = max(sw, sh)
            let scale = edge / longest
            return CGSize(
                width: max(1, (sw * scale).rounded()),
                height: max(1, (sh * scale).rounded())
            )
        case .width:
            let tw = Double(max(1, options.width > 0 ? options.width : Int(sw)))
            let scale = tw / sw
            return CGSize(
                width: max(1, tw.rounded()),
                height: max(1, (sh * scale).rounded())
            )
        case .height:
            let th = Double(max(1, options.height > 0 ? options.height : Int(sh)))
            let scale = th / sh
            return CGSize(
                width: max(1, (sw * scale).rounded()),
                height: max(1, th.rounded())
            )
        }
    }
}

enum ImageExportOptionsStore {
    private static let key = "laugh.imageExport.options.v1"

    static func load() -> ImageExportOptions {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ImageExportOptions.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    static func save(_ options: ImageExportOptions) {
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
