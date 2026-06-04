import AVFoundation
import AppKit
import Foundation

/// One selectable embedded or external subtitle stream in the current file.
struct SubtitleTrackInfo: Equatable {
    enum BackendID: Equatable {
        case avFoundation(optionIndex: Int)
        case mpv(trackID: Int)
        case externalMpv(trackID: Int, path: String)
    }

    let backendID: BackendID
    let displayIndex: Int
    let language: String?
    let title: String?
    let codec: String?

    var menuTitle: String {
        var parts = ["#\(displayIndex)"]
        if let language, !language.isEmpty {
            parts.append(language)
        }
        if let title, !title.isEmpty {
            parts.append(title)
        }
        if let codec, !codec.isEmpty {
            parts.append(codec)
        }
        if case .externalMpv(_, let path) = backendID {
            parts.append((path as NSString).lastPathComponent)
        }
        return parts.joined(separator: " · ")
    }
}

enum SubtitleTrackPickerOption {
    static let noneMenuTitle = "None"
}

enum MpvJSONValue {
    static func int(from value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Double { return Int(value) }
        return nil
    }
}

enum SubtitleTrackCatalog {
    static func tracks(from asset: AVAsset) async throws -> [SubtitleTrackInfo] {
        guard let group = try await asset.loadMediaSelectionGroup(for: .legible), !group.options.isEmpty else {
            return []
        }
        let selectable = primaryLegibleOptions(in: group)
        return selectable.enumerated().map { displayIndex, entry in
            let option = entry.option
            let rawLanguage = option.locale?.identifier ?? option.displayName
            let language = AudioTrackLanguageDisplay.displayName(for: rawLanguage)
            let title: String? = option.hasMediaCharacteristic(.containsOnlyForcedSubtitles) ? "Forced" : nil
            return SubtitleTrackInfo(
                backendID: .avFoundation(optionIndex: entry.optionIndex),
                displayIndex: displayIndex + 1,
                language: language,
                title: title,
                codec: nil
            )
        }
    }

    /// macOS often lists each embedded text stream twice (full + forced). Keep one entry per stream for the picker.
    private static func primaryLegibleOptions(in group: AVMediaSelectionGroup) -> [(optionIndex: Int, option: AVMediaSelectionOption)] {
        var result: [(Int, AVMediaSelectionOption)] = []
        var index = 0
        while index < group.options.count {
            let option = group.options[index]
            let isForced = option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
            if isForced {
                if result.isEmpty || result.last?.1.locale != option.locale {
                    result.append((index, option))
                }
                index += 1
                continue
            }
            result.append((index, option))
            let nextIndex = index + 1
            if nextIndex < group.options.count,
               group.options[nextIndex].hasMediaCharacteristic(.containsOnlyForcedSubtitles) {
                index = nextIndex + 1
            } else {
                index += 1
            }
        }
        if result.isEmpty {
            return group.options.enumerated().map { ($0.offset, $0.element) }
        }
        return result
    }

    static func tracks(fromMpvTrackList data: Any?) -> [SubtitleTrackInfo] {
        guard let list = data as? [[String: Any]] else { return [] }
        var result: [SubtitleTrackInfo] = []
        var subIndex = 0
        for entry in list {
            guard (entry["type"] as? String) == "sub" else { continue }
            guard let id = MpvJSONValue.int(from: entry["id"]) else { continue }
            subIndex += 1
            let lang = (entry["lang"] as? String) ?? (entry["language"] as? String)
            let title = entry["title"] as? String
            let codec = entry["codec"] as? String
            let external = (entry["external"] as? Bool) == true
                || (entry["external"] as? NSNumber)?.boolValue == true
            let path = entry["external-filename"] as? String ?? entry["filename"] as? String
            let backend: SubtitleTrackInfo.BackendID
            if external, let path, !path.isEmpty {
                backend = .externalMpv(trackID: id, path: path)
            } else {
                backend = .mpv(trackID: id)
            }
            result.append(
                SubtitleTrackInfo(
                    backendID: backend,
                    displayIndex: subIndex,
                    language: AudioTrackLanguageDisplay.displayName(for: lang),
                    title: title,
                    codec: codec
                )
            )
        }
        return result
    }

    static func selectedMpvTrackID(fromMpvTrackList data: Any?, secondary: Bool) -> Int? {
        guard let list = data as? [[String: Any]] else { return nil }
        let key = secondary ? "secondary-selected" : "selected"
        for entry in list {
            guard (entry["type"] as? String) == "sub" else { continue }
            let selected = (entry[key] as? Bool) == true
                || (entry[key] as? NSNumber)?.boolValue == true
            if selected, let id = MpvJSONValue.int(from: entry["id"]) { return id }
        }
        return nil
    }
}

enum NativeSubtitleSelection {
    @MainActor
    static func disableSubtitles(on playerItem: AVPlayerItem) async -> Bool {
        do {
            let asset = playerItem.asset
            if let group = try await asset.loadMediaSelectionGroup(for: .legible) {
                playerItem.select(nil, in: group)
            }
            return true
        } catch {
            return false
        }
    }

    @MainActor
    static func isSubtitlesDisabled(for playerItem: AVPlayerItem) async -> Bool {
        do {
            let asset = playerItem.asset
            guard let group = try await asset.loadMediaSelectionGroup(for: .legible) else {
                return true
            }
            return playerItem.currentMediaSelection.selectedMediaOption(in: group) == nil
        } catch {
            return true
        }
    }

    @MainActor
    static func select(track: SubtitleTrackInfo, on playerItem: AVPlayerItem) async -> Bool {
        guard case .avFoundation(let optionIndex) = track.backendID else { return false }
        if playerItem.status != .readyToPlay {
            for _ in 0..<40 where playerItem.status != .readyToPlay {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        guard playerItem.status == .readyToPlay else { return false }
        do {
            let asset = playerItem.asset
            guard let group = try await asset.loadMediaSelectionGroup(for: .legible),
                  optionIndex >= 0, optionIndex < group.options.count else {
                return false
            }
            let option = group.options[optionIndex]
            for attempt in 0..<5 {
                playerItem.select(option, in: group)
                if playerItem.currentMediaSelection.selectedMediaOption(in: group) === option {
                    return true
                }
                if attempt < 4 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            return false
        } catch {
            return false
        }
    }

    @MainActor
    static func selectedOptionIndex(for playerItem: AVPlayerItem) async -> Int? {
        do {
            let asset = playerItem.asset
            guard let group = try await asset.loadMediaSelectionGroup(for: .legible),
                  let selected = playerItem.currentMediaSelection.selectedMediaOption(in: group),
                  let index = group.options.firstIndex(of: selected) else {
                return nil
            }
            return index
        } catch {
            return nil
        }
    }
}

enum SubtitleAppearanceStyle {
    static let delayMin: Double = -5
    static let delayMax: Double = 5
    static let positionMin: Double = 0
    static let positionMax: Double = 100
    static let scaleMin: Double = 0.5
    static let scaleMax: Double = 2.0
    static let fontSizeMin: Double = 12
    static let fontSizeMax: Double = 72
    static let borderWidthMin: Double = 0
    static let borderWidthMax: Double = 8

    static func assForceStyle(from store: SettingsStore) -> String {
        let font = assBGRHex(from: store.subtitleFontColor)
        let border = assBGRHex(from: store.subtitleBorderColor)
        let background = store.subtitleBackgroundEnabled
            ? assBGRHex(from: store.subtitleBackgroundColor, alphaByte: 0x80)
            : "&H00000000"
        let outline = Int(round(store.subtitleBorderWidth))
        return [
            "FontSize=\(Int(round(store.subtitleFontSize)))",
            "PrimaryColour=\(font)",
            "OutlineColour=\(border)",
            "BackColour=\(background)",
            "Outline=\(max(0, outline))",
            "BorderStyle=1"
        ].joined(separator: ",")
    }

    private static func assBGRHex(from color: NSColor, alphaByte: Int = 0x00) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "&H%02X%02X%02X%02X", alphaByte, b, g, r)
    }
}
