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

struct FFmpegSubtitleStream: Equatable {
    /// 0-based index among subtitle streams only (not absolute ffmpeg stream index).
    let subtitleIndex: Int
    let language: String?
    let title: String?
    let codec: String
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
        parseSubtitleStreams(from: stderr).map(\.codec)
    }

    /// Full subtitle stream catalog from `ffmpeg -i` stderr (language, title, codec).
    static func parseSubtitleStreams(from stderr: String) -> [FFmpegSubtitleStream] {
        let lines = stderr.components(separatedBy: .newlines)
        var streams: [FFmpegSubtitleStream] = []
        var index = 0
        var i = 0
        while i < lines.count {
            let line = lines[i]
            defer { i += 1 }
            guard line.contains("Subtitle:") else { continue }
            guard let range = line.range(of: "Subtitle:") else { continue }
            let after = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            let token = after.split(whereSeparator: { $0 == "," || $0 == "(" }).first.map(String.init) ?? ""
            let codec = token.trimmingCharacters(in: .whitespaces).lowercased()
            guard !codec.isEmpty else { continue }

            var language: String?
            if let open = line.range(of: "Stream #"),
               let langOpen = line[open.upperBound...].firstIndex(of: "("),
               let langClose = line[langOpen...].firstIndex(of: ")") {
                let raw = line[line.index(after: langOpen)..<langClose]
                    .trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty, !raw.contains(":"), raw.count <= 12 {
                    language = String(raw)
                }
            }

            var title: String?
            var j = i + 1
            while j < lines.count {
                let meta = lines[j].trimmingCharacters(in: .whitespaces)
                if meta.hasPrefix("Stream #") { break }
                if meta.lowercased().hasPrefix("title") {
                    if let colon = meta.firstIndex(of: ":") {
                        let value = meta[meta.index(after: colon)...]
                            .trimmingCharacters(in: .whitespaces)
                        if !value.isEmpty { title = value }
                    }
                    break
                }
                if meta.hasPrefix("Metadata:") {
                    j += 1
                    continue
                }
                if !meta.isEmpty, !meta.lowercased().hasPrefix("handler_name"),
                   !meta.lowercased().hasPrefix("duration") {
                    // Keep scanning a few metadata lines for title.
                }
                j += 1
                if j > i + 6 { break }
            }

            streams.append(
                FFmpegSubtitleStream(
                    subtitleIndex: index,
                    language: language,
                    title: title,
                    codec: codec
                )
            )
            index += 1
        }
        return streams
    }

    /// PGS / VobSub / XSUB — bitmap overlays IINA/mpv can draw; AVPlayer remux cannot.
    static func isBitmapSubtitleCodec(_ codec: String) -> Bool {
        let normalized = codec.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        return normalized.contains("pgssub")
            || normalized.contains("hdmvpgs")
            || normalized == "pgs"
            || normalized.contains("dvdsub")
            || normalized.contains("vobsub")
            || normalized.contains("xsub")
            || normalized.contains("dvbsub")
    }

    static func isTextSubtitleCodec(_ codec: String) -> Bool {
        let normalized = codec.lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        if isBitmapSubtitleCodec(normalized) { return false }
        let text: Set<String> = [
            "subrip", "srt", "ass", "ssa", "movtext", "webvtt", "text"
        ]
        return text.contains(where: { normalized == $0 || normalized.contains($0) })
    }

    /// True when the file has embedded bitmap subs and no remuxable text tracks.
    static func hasBitmapSubtitlesOnly(codecs: [String]) -> Bool {
        guard !codecs.isEmpty else { return false }
        let hasBitmap = codecs.contains(where: isBitmapSubtitleCodec)
        let hasText = codecs.contains(where: isTextSubtitleCodec)
        return hasBitmap && !hasText
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

    /// Stream-copy remux of v0+a0 should keep a substantial fraction of the source bytes.
    /// Catastrophic sparse remuxes (incomplete torrent) land well under ~25% (e.g. 146MB of
    /// 1.7GB). Do **not** use a high threshold: dropping commentary/extra audio routinely
    /// yields 50–65% outputs that are still healthy, and a high gate falsely rejects them
    /// then burns 30s+ retrying remux strategies.
    static func remuxPayloadLooksComplete(
        outputBytes: Int,
        sourceBytes: Int,
        minimumRatio: Double = 0.25
    ) -> Bool {
        guard sourceBytes > 1_000_000 else { return outputBytes > 0 }
        guard outputBytes > 0 else { return false }
        return Double(outputBytes) >= Double(sourceBytes) * minimumRatio
    }

    /// Average fps much lower than container tbr ⇒ sparse packets (incomplete remux).
    /// Keep this strict: healthy stream-copies sit at ~1.0; the Jason Bourne poisoned
    /// remux landed at ~0.83 and still froze late in the file.
    static func remuxFrameRateLooksComplete(
        averageFps: Double?,
        containerFps: Double?,
        minimumRatio: Double = 0.90
    ) -> Bool {
        guard let averageFps, let containerFps, containerFps > 1, averageFps > 0 else {
            return true
        }
        return averageFps >= containerFps * minimumRatio
    }

    /// e.g. `11.25 fps, 23.98 tbr` → average frame rate from the primary video line.
    static func parseVideoAverageFps(from stderr: String) -> Double? {
        guard let line = primaryVideoLines(in: stderr).first else { return nil }
        return firstDouble(matching: #"([0-9]+(?:\.[0-9]+)?)\s*fps"#, in: line)
    }

    /// e.g. `11.25 fps, 23.98 tbr` → container timebase rate (nominal fps).
    static func parseVideoContainerFps(from stderr: String) -> Double? {
        guard let line = primaryVideoLines(in: stderr).first else { return nil }
        return firstDouble(matching: #"([0-9]+(?:\.[0-9]+)?)\s*tbr"#, in: line)
    }

    private static func firstDouble(matching pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[capture])
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
