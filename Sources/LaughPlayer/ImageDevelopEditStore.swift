import CoreGraphics
import Foundation

/// Saved per-image develop document (ADR 0006). Parameters + display geometry; never rewrites the source file.
struct ImageDevelopEdit: Equatable, Codable {
    var parameters: ImageAdjustParameters
    /// 0…3 quarter turns clockwise.
    var rotationQuarterTurns: Int
    var flipHorizontal: Bool
    var flipVertical: Bool
    /// Normalized crop in post-rotation space; nil = full frame.
    var cropNormalized: CodableNormalizedRect?
    var straightenRadians: Double

    static let identity = ImageDevelopEdit(
        parameters: .identity,
        rotationQuarterTurns: 0,
        flipHorizontal: false,
        flipVertical: false,
        cropNormalized: nil,
        straightenRadians: 0
    )

    var isIdentity: Bool {
        parameters.isIdentity
            && ((rotationQuarterTurns % 4) + 4) % 4 == 0
            && !flipHorizontal
            && !flipVertical
            && ImageCropGeometry.isIdentity(cropNormalized?.cgRect)
            && ImageCropGeometry.isIdentityStraighten(CGFloat(straightenRadians))
    }

    init(
        parameters: ImageAdjustParameters,
        rotationQuarterTurns: Int = 0,
        flipHorizontal: Bool = false,
        flipVertical: Bool = false,
        cropNormalized: CGRect? = nil,
        straightenRadians: CGFloat = 0
    ) {
        self.parameters = parameters
        self.rotationQuarterTurns = ((rotationQuarterTurns % 4) + 4) % 4
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
        if let cropNormalized, !ImageCropGeometry.isIdentity(cropNormalized) {
            self.cropNormalized = CodableNormalizedRect(cropNormalized)
        } else {
            self.cropNormalized = nil
        }
        self.straightenRadians = ImageCropGeometry.isIdentityStraighten(straightenRadians)
            ? 0
            : Double(ImageCropGeometry.clampStraightenRadians(straightenRadians))
    }
}

/// Codable wrapper for normalized crop rectangles.
struct CodableNormalizedRect: Equatable, Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.size.width)
        height = Double(rect.size.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// In-app store of **ImageDevelopEdit** documents keyed by absolute path (UserDefaults).
enum ImageDevelopEditStore {
    private static let key = "ImageDevelopEdits"
    private static var defaults: UserDefaults { .standard }
    private static var cached: [String: ImageDevelopEdit]?

    static func edit(forPath path: String) -> ImageDevelopEdit? {
        all()[normalizedPath(path)]
    }

    static func hasEdit(forPath path: String) -> Bool {
        guard let edit = edit(forPath: path) else { return false }
        return !edit.isIdentity
    }

    /// Paths that currently have a non-identity saved edit.
    static func editedPaths() -> Set<String> {
        Set(all().compactMap { path, edit in
            edit.isIdentity ? nil : path
        })
    }

    static func save(_ edit: ImageDevelopEdit, forPath path: String) {
        saveMany([normalizedPath(path): edit])
    }

    /// One decode / one encode for a batch stamp.
    static func saveMany(_ edits: [String: ImageDevelopEdit]) {
        var map = all()
        for (path, edit) in edits {
            let keyPath = normalizedPath(path)
            if edit.isIdentity {
                map.removeValue(forKey: keyPath)
            } else {
                map[keyPath] = edit
            }
        }
        persist(map)
    }

    static func remove(forPath path: String) {
        removeMany(forPaths: [path])
    }

    static func removeMany(forPaths paths: [String]) {
        var map = all()
        for path in paths {
            map.removeValue(forKey: normalizedPath(path))
        }
        persist(map)
    }

    /// Test seam — wipe all develop documents from the shared defaults.
    static func removeAllForTesting() {
        cached = nil
        defaults.removeObject(forKey: key)
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func all() -> [String: ImageDevelopEdit] {
        if let cached { return cached }
        guard let data = defaults.data(forKey: key) else {
            cached = [:]
            return [:]
        }
        if let map = try? JSONDecoder().decode([String: ImageDevelopEdit].self, from: data) {
            cached = map
            return map
        }
        let migrated = migrated(from: data)
        cached = migrated
        return migrated
    }

    private static func persist(_ map: [String: ImageDevelopEdit]) {
        cached = map
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: key)
    }

    /// Lenient migrate when newer `ImageAdjustParameters` fields are missing.
    private static func migrated(from data: Data) -> [String: ImageDevelopEdit] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: ImageDevelopEdit] = [:]
        for (path, value) in root {
            guard let obj = value as? [String: Any],
                  let paramsObj = obj["parameters"],
                  let paramsData = try? JSONSerialization.data(withJSONObject: paramsObj),
                  let parameters = try? ImageAdjustParameters.decodingLenient(from: paramsData)
            else { continue }
            let turns = obj["rotationQuarterTurns"] as? Int ?? 0
            let flipH = obj["flipHorizontal"] as? Bool ?? false
            let flipV = obj["flipVertical"] as? Bool ?? false
            let straighten = obj["straightenRadians"] as? Double ?? 0
            var crop: CGRect?
            if let cropObj = obj["cropNormalized"] as? [String: Any],
               let x = cropObj["x"] as? Double,
               let y = cropObj["y"] as? Double,
               let w = cropObj["width"] as? Double,
               let h = cropObj["height"] as? Double {
                crop = CGRect(x: x, y: y, width: w, height: h)
            }
            let edit = ImageDevelopEdit(
                parameters: parameters,
                rotationQuarterTurns: turns,
                flipHorizontal: flipH,
                flipVertical: flipV,
                cropNormalized: crop,
                straightenRadians: CGFloat(straighten)
            )
            if !edit.isIdentity {
                result[normalizedPath(path)] = edit
            }
        }
        if !result.isEmpty {
            persist(result)
        }
        return result
    }
}
