import AppKit
import Foundation

enum VideoFitMode: String {
    case fit
    case fill
}

enum WindowAspectPreset: String {
    case auto
    case widescreen
    case standard
    case ultrawide
    case square

    var displayTitle: String {
        switch self {
        case .auto: return "Auto"
        case .widescreen: return "16:9"
        case .standard: return "4:3"
        case .ultrawide: return "21:9"
        case .square: return "1:1"
        }
    }

    var aspectRatio: CGFloat? {
        switch self {
        case .auto: return nil
        case .widescreen: return 16.0 / 9.0
        case .standard: return 4.0 / 3.0
        case .ultrawide: return 21.0 / 9.0
        case .square: return 1.0
        }
    }

    static let selectablePresets: [WindowAspectPreset] = [.auto, .widescreen, .standard, .ultrawide, .square]
}

final class SettingsStore {
    static let shared = SettingsStore()

    private enum Keys {
        static let lockAspectRatioEnabled = "LockAspectRatioEnabled"
        static let videoFitMode = "VideoFitMode"
        static let windowAspectPreset = "WindowAspectPreset"
        static let playbackSpeed = "PlaybackSpeed"
        static let loopPlaybackEnabled = "LoopPlaybackEnabled"
        static let playbackEQPreset = "PlaybackEQPreset"
        static let playbackEQBands = "PlaybackEQBands"
        static let subtitleDelaySec = "SubtitleDelaySec"
        static let subtitlePosition = "SubtitlePosition"
        static let subtitleScale = "SubtitleScale"
        static let subtitleFontSize = "SubtitleFontSize"
        static let subtitleFontColor = "SubtitleFontColor"
        static let subtitleBorderWidth = "SubtitleBorderWidth"
        static let subtitleBorderColor = "SubtitleBorderColor"
        static let subtitleBackgroundEnabled = "SubtitleBackgroundEnabled"
        static let subtitleBackgroundColor = "SubtitleBackgroundColor"
    }

    var lockAspectRatioEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.lockAspectRatioEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.lockAspectRatioEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.lockAspectRatioEnabled)
        }
    }

    var videoFitMode: VideoFitMode {
        get {
            guard let raw = defaults.string(forKey: Keys.videoFitMode),
                  let mode = VideoFitMode(rawValue: raw) else {
                return .fit
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.videoFitMode)
        }
    }

    var windowAspectPreset: WindowAspectPreset {
        get {
            guard let raw = defaults.string(forKey: Keys.windowAspectPreset),
                  let preset = WindowAspectPreset(rawValue: raw) else {
                return .auto
            }
            return preset
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.windowAspectPreset)
        }
    }

    var playbackSpeed: Float {
        get {
            let stored = defaults.float(forKey: Keys.playbackSpeed)
            return stored > 0 ? stored : 1.0
        }
        set {
            defaults.set(newValue, forKey: Keys.playbackSpeed)
        }
    }

    var loopPlaybackEnabled: Bool {
        get { defaults.bool(forKey: Keys.loopPlaybackEnabled) }
        set { defaults.set(newValue, forKey: Keys.loopPlaybackEnabled) }
    }

    var playbackEQPreset: PlaybackEQPreset {
        get {
            guard let raw = defaults.string(forKey: Keys.playbackEQPreset),
                  let preset = PlaybackEQPreset(rawValue: raw) else {
                return .manual
            }
            return preset
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.playbackEQPreset)
        }
    }

    var playbackEQBands: [Float] {
        get {
            guard let stored = defaults.array(forKey: Keys.playbackEQBands) as? [Double],
                  stored.count == PlaybackEQ.bandCount else {
                return PlaybackEQPreset.manual.bandGains
            }
            return stored.map { Float($0) }
        }
        set {
            let values = newValue.prefix(PlaybackEQ.bandCount).map { Double($0) }
            defaults.set(Array(values), forKey: Keys.playbackEQBands)
        }
    }

    var subtitleDelaySec: Double {
        get {
            if defaults.object(forKey: Keys.subtitleDelaySec) == nil { return 0 }
            return defaults.double(forKey: Keys.subtitleDelaySec)
        }
        set {
            defaults.set(
                max(SubtitleAppearanceStyle.delayMin, min(SubtitleAppearanceStyle.delayMax, newValue)),
                forKey: Keys.subtitleDelaySec
            )
        }
    }

    var subtitlePosition: Double {
        get {
            if defaults.object(forKey: Keys.subtitlePosition) == nil { return 100 }
            return defaults.double(forKey: Keys.subtitlePosition)
        }
        set {
            defaults.set(
                max(SubtitleAppearanceStyle.positionMin, min(SubtitleAppearanceStyle.positionMax, newValue)),
                forKey: Keys.subtitlePosition
            )
        }
    }

    var subtitleScale: Double {
        get {
            let stored = defaults.double(forKey: Keys.subtitleScale)
            return stored > 0 ? stored : 1.0
        }
        set {
            defaults.set(
                max(SubtitleAppearanceStyle.scaleMin, min(SubtitleAppearanceStyle.scaleMax, newValue)),
                forKey: Keys.subtitleScale
            )
        }
    }

    var subtitleFontSize: Double {
        get {
            let stored = defaults.double(forKey: Keys.subtitleFontSize)
            return stored > 0 ? stored : 36
        }
        set {
            defaults.set(
                max(SubtitleAppearanceStyle.fontSizeMin, min(SubtitleAppearanceStyle.fontSizeMax, newValue)),
                forKey: Keys.subtitleFontSize
            )
        }
    }

    var subtitleFontColor: NSColor {
        get { color(forKey: Keys.subtitleFontColor) ?? .white }
        set { saveColor(newValue, forKey: Keys.subtitleFontColor) }
    }

    var subtitleBorderWidth: Double {
        get { defaults.double(forKey: Keys.subtitleBorderWidth) }
        set {
            defaults.set(
                max(SubtitleAppearanceStyle.borderWidthMin, min(SubtitleAppearanceStyle.borderWidthMax, newValue)),
                forKey: Keys.subtitleBorderWidth
            )
        }
    }

    var subtitleBorderColor: NSColor {
        get { color(forKey: Keys.subtitleBorderColor) ?? .black }
        set { saveColor(newValue, forKey: Keys.subtitleBorderColor) }
    }

    var subtitleBackgroundEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.subtitleBackgroundEnabled) == nil { return true }
            return defaults.bool(forKey: Keys.subtitleBackgroundEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.subtitleBackgroundEnabled) }
    }

    var subtitleBackgroundColor: NSColor {
        get { color(forKey: Keys.subtitleBackgroundColor) ?? NSColor.black.withAlphaComponent(0.65) }
        set { saveColor(newValue, forKey: Keys.subtitleBackgroundColor) }
    }

    private func color(forKey key: String) -> NSColor? {
        guard let data = defaults.data(forKey: key),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) else {
            return nil
        }
        return color
    }

    private func saveColor(_ color: NSColor, forKey key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) {
            defaults.set(data, forKey: key)
        }
    }

    private let defaults = UserDefaults.standard
}
