import Foundation

struct SidecarSubtitleCue: Equatable {
    let startSec: Double
    let endSec: Double
    let text: String
}

enum SidecarSubtitleLoader {
    static func isNativeRenderableSidecar(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["srt", "vtt", "webvtt"].contains(ext)
    }

    static func load(from url: URL) -> [SidecarSubtitleCue] {
        let ext = url.pathExtension.lowercased()
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        switch ext {
        case "srt":
            return parseSRT(contents)
        case "vtt", "webvtt":
            return parseVTT(contents)
        default:
            return []
        }
    }

    static func text(at timeSec: Double, in cues: [SidecarSubtitleCue]) -> String {
        guard timeSec.isFinite else { return "" }
        var lines: [String] = []
        for cue in cues where timeSec >= cue.startSec && timeSec < cue.endSec {
            lines.append(cue.text)
        }
        return lines.joined(separator: "\n")
    }

    private static func parseSRT(_ contents: String) -> [SidecarSubtitleCue] {
        let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SidecarSubtitleCue] = []
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard lines.count >= 2 else { continue }
            let timeLineIndex = lines.firstIndex(where: { $0.contains("-->") }) ?? 1
            guard timeLineIndex < lines.count else { continue }
            let parts = lines[timeLineIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1]) else { continue }
            let text = lines[(timeLineIndex + 1)...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            cues.append(SidecarSubtitleCue(startSec: start, endSec: end, text: text))
        }
        return cues.sorted { $0.startSec < $1.startSec }
    }

    private static func parseVTT(_ contents: String) -> [SidecarSubtitleCue] {
        let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SidecarSubtitleCue] = []
        for block in blocks {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("WEBVTT") || trimmed.hasPrefix("NOTE") { continue }
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard !lines.isEmpty else { continue }
            let timeLineIndex: Int
            if lines[0].contains("-->") {
                timeLineIndex = 0
            } else if lines.count > 1, lines[1].contains("-->") {
                timeLineIndex = 1
            } else {
                continue
            }
            let parts = lines[timeLineIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1]) else { continue }
            let text = lines[(timeLineIndex + 1)...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            cues.append(SidecarSubtitleCue(startSec: start, endSec: end, text: text))
        }
        return cues.sorted { $0.startSec < $1.startSec }
    }

    private static func parseTimestamp(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutSettings = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed
        let normalized = withoutSettings.replacingOccurrences(of: ",", with: ".")
        let segments = normalized.split(separator: ":").map(String.init)
        guard segments.count == 3,
              let hours = Double(segments[0]),
              let minutes = Double(segments[1]),
              let seconds = Double(segments[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}
