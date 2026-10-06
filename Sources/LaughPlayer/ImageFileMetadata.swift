import Foundation
import ImageIO

/// Rich still-image metadata for the left **ImageInfo** sidebar.
/// Built from ImageIO properties + filesystem attributes; empty EXIF groups are omitted.
struct ImageFileMetadata: Equatable {
    struct Row: Equatable {
        var label: String
        var value: String
    }

    struct Section: Equatable {
        var title: String
        var rows: [Row]
    }

    var sections: [Section]

    static func load(from url: URL) -> ImageFileMetadata {
        var sections: [Section] = []

        let fileRows = fileRows(for: url)
        if !fileRows.isEmpty {
            sections.append(Section(title: "File", rows: fileRows))
        }

        let properties = imageProperties(at: url)
        let imageRows = imageRows(from: properties)
        if !imageRows.isEmpty {
            sections.append(Section(title: "Image", rows: imageRows))
        }

        let cameraRows = cameraRows(from: properties)
        if !cameraRows.isEmpty {
            sections.append(Section(title: "Camera", rows: cameraRows))
        }

        let gpsRows = gpsRows(from: properties)
        if !gpsRows.isEmpty {
            sections.append(Section(title: "GPS", rows: gpsRows))
        }

        return ImageFileMetadata(sections: sections)
    }

    // MARK: - File

    private static func fileRows(for url: URL) -> [Row] {
        var rows: [Row] = []
        let name = url.lastPathComponent
        if !name.isEmpty {
            rows.append(Row(label: "Name", value: name))
        }

        let folder = url.deletingLastPathComponent().lastPathComponent
        if !folder.isEmpty, folder != "/" {
            rows.append(Row(label: "Folder", value: folder))
        }

        let badge = MediaKindDetector.formatBadge(for: url)
        rows.append(Row(label: "Format", value: badge.title))

        if let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]) {
            if let size = values.fileSize, size >= 0 {
                rows.append(Row(label: "Size", value: byteCountFormatter.string(fromByteCount: Int64(size))))
            }
            if let created = values.creationDate {
                rows.append(Row(label: "Created", value: dateTimeFormatter.string(from: created)))
            }
            if let modified = values.contentModificationDate {
                rows.append(Row(label: "Modified", value: dateTimeFormatter.string(from: modified)))
            }
        }

        return rows
    }

    // MARK: - ImageIO

    private static func imageProperties(at url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return [:]
        }
        return props
    }

    private static func imageRows(from properties: [CFString: Any]) -> [Row] {
        var rows: [Row] = []

        let width = cgFloat(properties[kCGImagePropertyPixelWidth])
        let height = cgFloat(properties[kCGImagePropertyPixelHeight])
        if let width, let height, width > 0, height > 0 {
            rows.append(Row(label: "Dimensions", value: "\(Int(width)) × \(Int(height))"))
            let megapixels = (width * height) / 1_000_000
            if megapixels >= 0.1 {
                rows.append(Row(label: "Megapixels", value: String(format: "%.1f MP", megapixels)))
            }
            let aspect = width / height
            rows.append(Row(label: "Aspect", value: String(format: "%.3f", aspect)))
        }

        if let colorModel = string(properties[kCGImagePropertyColorModel]) {
            rows.append(Row(label: "Color model", value: colorModel))
        }
        if let depth = int(properties[kCGImagePropertyDepth]) {
            rows.append(Row(label: "Bit depth", value: "\(depth)-bit"))
        }

        let dpiX = cgFloat(properties[kCGImagePropertyDPIWidth])
        let dpiY = cgFloat(properties[kCGImagePropertyDPIHeight])
        if let dpiX, let dpiY, dpiX > 0, dpiY > 0 {
            if abs(dpiX - dpiY) < 0.5 {
                rows.append(Row(label: "DPI", value: String(format: "%.0f", dpiX)))
            } else {
                rows.append(Row(label: "DPI", value: String(format: "%.0f × %.0f", dpiX, dpiY)))
            }
        }

        if let orientation = int(properties[kCGImagePropertyOrientation]),
           let label = orientationLabel(orientation) {
            rows.append(Row(label: "Orientation", value: label))
        }

        return rows
    }

    private static func cameraRows(from properties: [CFString: Any]) -> [Row] {
        let tiff = dictionary(properties[kCGImagePropertyTIFFDictionary])
        let exif = dictionary(properties[kCGImagePropertyExifDictionary])
        let exifAux = dictionary(properties[kCGImagePropertyExifAuxDictionary])

        var rows: [Row] = []

        if let make = string(tiff[kCGImagePropertyTIFFMake]) {
            rows.append(Row(label: "Make", value: make))
        }
        if let model = string(tiff[kCGImagePropertyTIFFModel]) {
            rows.append(Row(label: "Model", value: model))
        }

        let lens = string(exif[kCGImagePropertyExifLensModel])
            ?? string(exifAux[kCGImagePropertyExifLensModel])
            ?? string(exif[kCGImagePropertyExifLensMake])
        if let lens {
            rows.append(Row(label: "Lens", value: lens))
        }

        if let focal = cgFloat(exif[kCGImagePropertyExifFocalLength]), focal > 0 {
            rows.append(Row(label: "Focal length", value: String(format: "%.0f mm", focal)))
        }
        if let aperture = cgFloat(exif[kCGImagePropertyExifFNumber]), aperture > 0 {
            rows.append(Row(label: "Aperture", value: String(format: "ƒ/%.1f", aperture)))
        }
        if let exposure = cgFloat(exif[kCGImagePropertyExifExposureTime]), exposure > 0 {
            rows.append(Row(label: "Shutter", value: formatShutter(exposure)))
        }
        if let iso = firstISO(exif[kCGImagePropertyExifISOSpeedRatings]) {
            rows.append(Row(label: "ISO", value: "\(iso)"))
        }
        if let date = string(exif[kCGImagePropertyExifDateTimeOriginal])
            ?? string(exif[kCGImagePropertyExifDateTimeDigitized]) {
            rows.append(Row(label: "Captured", value: formatExifDate(date)))
        }
        if let flash = int(exif[kCGImagePropertyExifFlash]) {
            rows.append(Row(label: "Flash", value: flashLabel(flash)))
        }

        return rows
    }

    private static func gpsRows(from properties: [CFString: Any]) -> [Row] {
        let gps = dictionary(properties[kCGImagePropertyGPSDictionary])
        guard !gps.isEmpty else { return [] }

        var rows: [Row] = []
        if let lat = coordinate(
            value: gps[kCGImagePropertyGPSLatitude],
            ref: string(gps[kCGImagePropertyGPSLatitudeRef]),
            positiveRef: "N"
        ) {
            rows.append(Row(label: "Latitude", value: lat))
        }
        if let lon = coordinate(
            value: gps[kCGImagePropertyGPSLongitude],
            ref: string(gps[kCGImagePropertyGPSLongitudeRef]),
            positiveRef: "E"
        ) {
            rows.append(Row(label: "Longitude", value: lon))
        }
        if let altitude = cgFloat(gps[kCGImagePropertyGPSAltitude]) {
            let ref = int(gps[kCGImagePropertyGPSAltitudeRef]) ?? 0
            let signed = ref == 1 ? -altitude : altitude
            rows.append(Row(label: "Altitude", value: String(format: "%.0f m", signed)))
        }
        return rows
    }

    // MARK: - Formatting helpers

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// EXIF timestamps are `YYYY:MM:DD HH:MM:SS` — swap date separators only.
    private static func formatExifDate(_ raw: String) -> String {
        let parts = raw.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let datePart = parts.first else { return raw }
        let niceDate = datePart.replacingOccurrences(of: ":", with: "-")
        if parts.count > 1 {
            return "\(niceDate) \(parts[1])"
        }
        return niceDate
    }

    private static func formatShutter(_ seconds: CGFloat) -> String {
        if seconds >= 1 {
            return String(format: "%.1f s", seconds)
        }
        let reciprocal = Int((1 / seconds).rounded())
        guard reciprocal > 1 else { return String(format: "%.3f s", seconds) }
        return "1/\(reciprocal) s"
    }

    private static func orientationLabel(_ value: Int) -> String? {
        switch value {
        case 1: return "Normal"
        case 2: return "Mirrored"
        case 3: return "Rotated 180°"
        case 4: return "Mirrored upright"
        case 5: return "Mirrored 90° CCW"
        case 6: return "Rotated 90° CW"
        case 7: return "Mirrored 90° CW"
        case 8: return "Rotated 90° CCW"
        default: return nil
        }
    }

    private static func flashLabel(_ value: Int) -> String {
        (value & 1) == 1 ? "Fired" : "Did not fire"
    }

    private static func coordinate(value: Any?, ref: String?, positiveRef: String) -> String? {
        guard let degrees = cgFloat(value) else { return nil }
        let hemi = (ref ?? positiveRef).uppercased()
        let signed = hemi == positiveRef ? degrees : -degrees
        return String(format: "%.5f° %@", abs(signed), hemi)
    }

    private static func firstISO(_ value: Any?) -> Int? {
        if let array = value as? [Any], let first = array.first {
            return int(first)
        }
        return int(value)
    }

    private static func dictionary(_ value: Any?) -> [CFString: Any] {
        (value as? [CFString: Any]) ?? [:]
    }

    private static func string(_ value: Any?) -> String? {
        if let s = value as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let s = value as? NSString {
            let trimmed = (s as String).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        if let n = value as? CGFloat { return n }
        if let n = value as? Double { return CGFloat(n) }
        if let n = value as? Float { return CGFloat(n) }
        if let n = value as? Int { return CGFloat(n) }
        if let n = value as? NSNumber { return CGFloat(truncating: n) }
        return nil
    }
}
