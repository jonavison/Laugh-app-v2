import Foundation

/// Parsed `ffmpeg -i` header probe (stderr). Does not spawn ffmpeg.
struct FFmpegProbeSummary: Equatable {
    var durationSec: Double?
    var videoCodecName: String?
    var videoCodecTag: String?
    var audioCodec: String?
    var subtitleCodecs: [String]

    var hasAudio: Bool { audioCodec != nil }
    var hasVideo: Bool { videoCodecName != nil || videoCodecTag != nil }

    var logLine: String {
        let duration = durationSec.map { String(format: "%.2fs", $0) } ?? "unknown"
        let video = videoCodecName ?? "none"
        let tag = videoCodecTag ?? "none"
        let audio = audioCodec ?? "none"
        let subs = subtitleCodecs.isEmpty ? "none" : subtitleCodecs.joined(separator: "+")
        return "video=\(video) tag=\(tag) audio=\(audio) duration=\(duration) subs=\(subs)"
    }
}

enum FFmpegProbeParser {
    private static let videoProfileNames: Set<String> = [
        "high", "main", "base", "low", "simple", "baseline"
    ]

    static func parse(_ stderr: String) -> FFmpegProbeSummary {
        FFmpegProbeSummary(
            durationSec: parseDurationSec(from: stderr),
            videoCodecName: parseVideoCodecName(from: stderr),
            videoCodecTag: parseVideoCodecTag(from: stderr),
            audioCodec: parsePrimaryAudioCodec(from: stderr),
            subtitleCodecs: parseSubtitleCodecs(from: stderr)
        )
    }

    static func parseDurationSec(from stderr: String) -> Double? {
        guard let range = stderr.range(of: "Duration:") else { return nil }
        let after = stderr[range.upperBound...]
        guard let comma = after.firstIndex(of: ",") else { return nil }
        let timeToken = after[..<comma].trimmingCharacters(in: .whitespaces)
        let parts = timeToken.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    static func parsePrimaryAudioCodec(from stderr: String) -> String? {
        for line in stderr.components(separatedBy: .newlines) where line.contains("Audio:") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let audioRange = trimmed.range(of: "Audio:") else { continue }
            let after = trimmed[audioRange.upperBound...].trimmingCharacters(in: .whitespaces)
            let token = after.split(whereSeparator: { $0 == "," || $0 == "(" }).first.map(String.init) ?? ""
            let codec = token.trimmingCharacters(in: .whitespaces).lowercased()
            if !codec.isEmpty { return codec }
        }
        return nil
    }

    static func parseVideoCodecName(from stderr: String) -> String? {
        for line in primaryVideoLines(in: stderr) {
            guard let range = line.range(of: "Video:") else { continue }
            let after = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            let token = after.split(whereSeparator: { $0 == "," || $0 == "(" }).first.map(String.init) ?? ""
            let name = token.trimmingCharacters(in: .whitespaces).lowercased()
            if !name.isEmpty { return name }
        }
        return nil
    }

    static func parseVideoCodecTag(from stderr: String) -> String? {
        for line in primaryVideoLines(in: stderr) {
            if let fourcc = fourCCFromHexParen(in: line) {
                return fourcc
            }
            var candidates: [String] = []
            var search = line[...]
            while let open = search.firstIndex(of: "("),
                  let close = search[open...].firstIndex(of: ")") {
                let inner = search[search.index(after: open)..<close]
                let token = inner.trimmingCharacters(in: .whitespaces).lowercased()
                if token.count == 4,
                   token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
                   !videoProfileNames.contains(token) {
                    candidates.append(token)
                }
                search = search[search.index(after: close)...]
            }
            if let tag = candidates.last { return tag }
        }
        return nil
    }

    static func parseSubtitleCodecs(from stderr: String) -> [String] {
        var codecs: [String] = []
        for line in stderr.components(separatedBy: .newlines) where line.contains("Subtitle:") {
            guard let range = line.range(of: "Subtitle:") else { continue }
            let after = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            let token = after.split(whereSeparator: { $0 == "," || $0 == "(" }).first.map(String.init) ?? ""
            let codec = token.trimmingCharacters(in: .whitespaces).lowercased()
            if !codec.isEmpty { codecs.append(codec) }
        }
        return codecs
    }

    /// Fragmented fMP4 preview cannot stream-copy these audio codecs.
    static func needsFragmentedAudioTranscode(audioCodec: String?) -> Bool {
        guard let audioCodec else { return false }
        let normalized = audioCodec.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        return normalized == "eac3" || normalized == "ec3" || normalized == "ac3"
    }

    static func isPreviewByteReady(fileSize: Int, containsMOOF: Bool) -> Bool {
        fileSize >= 64 * 1024 && containsMOOF
    }

    private static func primaryVideoLines(in stderr: String) -> [String] {
        stderr.components(separatedBy: .newlines).filter { line in
            line.contains("Video:") && !line.contains("attached pic")
        }
    }

    private static func fourCCFromHexParen(in line: String) -> String? {
        var search = line[...]
        while let open = search.firstIndex(of: "("),
              let close = search[open...].firstIndex(of: ")") {
            let inner = search[search.index(after: open)..<close]
            if let slash = inner.firstIndex(of: "/") {
                let left = inner[..<slash].trimmingCharacters(in: .whitespaces).lowercased()
                if left.count == 4, left.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                    return left
                }
            }
            search = search[search.index(after: close)...]
        }
        return nil
    }
}
