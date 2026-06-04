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
    /// Flat bar thickness for sliders in the Subtitles settings tab.
    static let settingsSliderTrackHeight: CGFloat = 7

    static let defaultDelaySec: Double = 0
    static let defaultPosition: Double = 0
    static let defaultScale: Double = 1
    static let defaultFontSize: Double = 36
    static let defaultBorderWidth: Double = 2
    static let defaultFontColor: NSColor = .white
    static let defaultBorderColor: NSColor = .black
    static let defaultBackgroundEnabled: Bool = true
    static let defaultBackgroundColor: NSColor = NSColor.black.withAlphaComponent(0.65)

    static let delayMin: Double = -5
    static let delayMax: Double = 5
    /// User-facing position: 0 = bottom of screen, 100 = top.
    static let positionMin: Double = 0
    static let positionMax: Double = 100

    /// mpv `sub-pos`: 100 = bottom, 0 = top (inverse of user position).
    static func mpvSubPos(fromUserPosition user: Double) -> Double {
        let clamped = max(positionMin, min(positionMax, user))
        return positionMax - clamped
    }

    static func positionLabel(for userPosition: Double) -> String {
        let p = max(positionMin, min(positionMax, userPosition))
        if p <= 2 { return "Bottom" }
        if p >= 98 { return "Top" }
        return String(format: "%.0f%%", p)
    }
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
        let borderStyle = store.subtitleBackgroundEnabled ? 3 : 1
        return [
            "Fontname=\(SubtitleFont.assFontName)",
            "FontSize=\(Int(round(store.subtitleFontSize)))",
            "PrimaryColour=\(font)",
            "OutlineColour=\(border)",
            "BackColour=\(background)",
            "Outline=\(max(0, outline))",
            "BorderStyle=\(borderStyle)"
        ].joined(separator: ",")
    }

    private static func assBGRHex(from color: NSColor, alphaByte: Int = 0x00) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "&H%02X%02X%02X%02X", alphaByte, b, g, r)
    }

    /// mpv `sub-color` / `sub-outline-color` / `sub-back-color` (#AARRGGBB).
    static func mpvSubColorString(from color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let a = Int(round(rgb.alphaComponent * 255))
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X%02X", a, r, g, b)
    }
}

enum NativeSubtitleAppearance {
    /// Text-style rules for AVFoundation legible subtitles (`mov_text`, etc.).
    static func makeRules(from store: SettingsStore) -> [AVTextStyleRule] {
        var rules: [AVTextStyleRule] = []

        let relativeSize = max(
            50,
            min(400, store.subtitleFontSize * store.subtitleScale / SubtitleAppearanceStyle.defaultFontSize * 100.0)
        )
        if let rule = AVTextStyleRule(textMarkupAttributes: [
            kCMTextMarkupAttribute_RelativeFontSize as String: NSNumber(value: relativeSize)
        ]) {
            rules.append(rule)
        }

        if let components = argbComponents(from: store.subtitleFontColor),
           let rule = AVTextStyleRule(textMarkupAttributes: [
               kCMTextMarkupAttribute_ForegroundColorARGB as String: components
           ]) {
            rules.append(rule)
        }

        if store.subtitleBackgroundEnabled,
           let components = argbComponents(from: store.subtitleBackgroundColor),
           let rule = AVTextStyleRule(textMarkupAttributes: [
               kCMTextMarkupAttribute_BackgroundColorARGB as String: components
           ]) {
            rules.append(rule)
        }

        let verticalPosition = max(0, min(100, store.subtitlePosition))
        if let rule = AVTextStyleRule(textMarkupAttributes: [
            "TextPositionPercentageRelativeToVideoHeight": NSNumber(value: verticalPosition)
        ]) {
            rules.append(rule)
        }

        return rules
    }

    static func usesCustomStyling(from store: SettingsStore) -> Bool {
        if stylingDiffers(store.subtitlePosition, from: SubtitleAppearanceStyle.defaultPosition, epsilon: 2) { return true }
        if stylingDiffers(store.subtitleScale, from: SubtitleAppearanceStyle.defaultScale) { return true }
        if stylingDiffers(store.subtitleFontSize, from: SubtitleAppearanceStyle.defaultFontSize) { return true }
        if stylingDiffers(store.subtitleBorderWidth, from: SubtitleAppearanceStyle.defaultBorderWidth, epsilon: 0.5) {
            return true
        }
        if !colorsMatch(store.subtitleFontColor, SubtitleAppearanceStyle.defaultFontColor) { return true }
        if !colorsMatch(store.subtitleBorderColor, SubtitleAppearanceStyle.defaultBorderColor) { return true }
        if store.subtitleBackgroundEnabled != SubtitleAppearanceStyle.defaultBackgroundEnabled { return true }
        if !colorsMatch(store.subtitleBackgroundColor, SubtitleAppearanceStyle.defaultBackgroundColor) { return true }
        return false
    }

    private static func stylingDiffers(_ value: Double, from baseline: Double, epsilon: Double = 0.05) -> Bool {
        abs(value - baseline) > epsilon
    }

    private static func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let a = lhs.usingColorSpace(.sRGB) ?? lhs
        let b = rhs.usingColorSpace(.sRGB) ?? rhs
        return abs(a.redComponent - b.redComponent) < 0.02
            && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
            && abs(a.alphaComponent - b.alphaComponent) < 0.02
    }

    private static func argbComponents(from color: NSColor, alphaOverride: Double? = nil) -> [NSNumber]? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let alpha = alphaOverride ?? rgb.alphaComponent
        return [
            NSNumber(value: alpha),
            NSNumber(value: rgb.redComponent),
            NSNumber(value: rgb.greenComponent),
            NSNumber(value: rgb.blueComponent)
        ]
    }
}
