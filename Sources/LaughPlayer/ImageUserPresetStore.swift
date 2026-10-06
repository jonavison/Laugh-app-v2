import Foundation

/// Named snapshot of `ImageAdjustParameters` saved from the image studio sidebar.
struct ImageUserPreset: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var parameters: ImageAdjustParameters

    init(id: UUID = UUID(), name: String, parameters: ImageAdjustParameters) {
        self.id = id
        self.name = name
        self.parameters = parameters
    }
}

enum ImageUserPresetStore {
    private static let key = "ImageUserPresets"

    static func all() -> [ImageUserPreset] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        if let presets = try? JSONDecoder().decode([ImageUserPreset].self, from: data) {
            return presets
        }
        // Older payloads omit Wave 2+ keys — merge onto identity and re-persist.
        let migrated = migratedPresets(from: data)
        if !migrated.isEmpty {
            persist(migrated)
        }
        return migrated
    }

    /// Saves a new preset, or replaces an existing one with the same name (case-insensitive).
    @discardableResult
    static func save(name: String, parameters: ImageAdjustParameters) -> ImageUserPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? "Untitled" : trimmed
        var presets = all()
        if let index = presets.firstIndex(where: { $0.name.compare(label, options: .caseInsensitive) == .orderedSame }) {
            presets[index].parameters = parameters
            persist(presets)
            return presets[index]
        }
        let preset = ImageUserPreset(name: label, parameters: parameters)
        presets.append(preset)
        persist(presets)
        return preset
    }

    static func delete(id: UUID) {
        persist(all().filter { $0.id != id })
    }

    private static func persist(_ presets: [ImageUserPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Forward-compatible decode for presets saved before newer `ImageAdjustParameters` fields existed.
    private static func migratedPresets(from data: Data) -> [ImageUserPreset] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let idString = item["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let name = item["name"] as? String,
                  let paramsObj = item["parameters"]
            else { return nil }
            guard let paramsData = try? JSONSerialization.data(withJSONObject: paramsObj),
                  let parameters = try? ImageAdjustParameters.decodingLenient(from: paramsData)
            else { return nil }
            return ImageUserPreset(id: id, name: name, parameters: parameters)
        }
    }
}
