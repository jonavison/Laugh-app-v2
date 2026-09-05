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
        return (try? JSONDecoder().decode([ImageUserPreset].self, from: data)) ?? []
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
}
