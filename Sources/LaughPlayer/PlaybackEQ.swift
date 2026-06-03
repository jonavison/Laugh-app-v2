import Foundation

enum PlaybackEQPreset: String, CaseIterable {
    case manual
    case flat
    case bassBoost
    case trebleBoost
    case voice

    var displayTitle: String {
        switch self {
        case .manual: return "Manual"
        case .flat: return "Flat"
        case .bassBoost: return "Bass Boost"
        case .trebleBoost: return "Treble Boost"
        case .voice: return "Voice"
        }
    }

    /// Ten band gains in dB (31 Hz … 16 kHz).
    var bandGains: [Float] {
        switch self {
        case .manual, .flat:
            return Array(repeating: 0, count: PlaybackEQ.bandCount)
        case .bassBoost:
            return [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]
        case .trebleBoost:
            return [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]
        case .voice:
            return [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]
        }
    }
}

enum PlaybackEQ {
    static let bandCount = 10
    static let bandLabels = ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    static let minGain: Float = -12
    static let maxGain: Float = 12

    static func lavfiSuperequalizerFilter(gains: [Float]) -> String {
        let clamped = gains.prefix(bandCount).map { min(max($0, minGain), maxGain) }
        let params = clamped.enumerated().map { "\($0.offset + 1)b=\($0.element)" }.joined(separator: ":")
        return "lavfi=[superequalizer=\(params)]"
    }
}
