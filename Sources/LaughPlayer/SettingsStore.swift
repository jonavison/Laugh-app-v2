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

    private let defaults = UserDefaults.standard
}
