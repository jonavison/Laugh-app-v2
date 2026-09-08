import Foundation

/// Detects media files that exist on disk but are not yet playable — a torrent still
/// downloading (preallocated / zero-filled before the header piece arrives), or a
/// truncated/corrupt container whose magic bytes never match.
enum IncompleteMediaProbe {
    /// Matroska / WebM EBML magic (`1A 45 DF A3`).
    private static let ebmlMagic: [UInt8] = [0x1A, 0x45, 0xDF, 0xA3]
    private static let riffMagic: [UInt8] = Array("RIFF".utf8)
    private static let ftypMarker: [UInt8] = Array("ftyp".utf8)

    /// True when the on-disk bytes do not yet look like a container of the file's extension.
    /// Covers still-downloading torrents and truncated/corrupt files equally — the bytes
    /// alone cannot tell those apart.
    static func looksLikeIncompleteOrDamaged(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard let expected = expectedMagic(forExtension: ext) else { return false }
        guard let head = readHead(url, count: expected.readLength) else { return false }
        if head.allSatisfy({ $0 == 0 }) { return true }
        return !expected.matches(head)
    }

    /// Alias kept for older call sites.
    static func looksLikeIncompleteDownload(at url: URL) -> Bool {
        looksLikeIncompleteOrDamaged(at: url)
    }

    /// True when ffmpeg's stderr matches a missing/corrupt container-header failure.
    static func looksLikeIncompleteOrDamaged(ffmpegStderr: String) -> Bool {
        let lowered = ffmpegStderr.lowercased()
        if lowered.contains("ebml header parsing failed")
            || lowered.contains("invalid as first byte of an ebml number")
            || lowered.contains("0x00 at pos 0") {
            return true
        }
        // Generic "invalid data" only when paired with an open/header signal, so a
        // complete-but-weird remux failure still gets the generic remux message.
        return lowered.contains("invalid data found when processing input")
            && (lowered.contains("misdetection possible") || lowered.contains("error opening input"))
    }

    static func looksLikeIncompleteDownload(ffmpegStderr: String) -> Bool {
        looksLikeIncompleteOrDamaged(ffmpegStderr: ffmpegStderr)
    }

    // MARK: - Magic

    private struct ExpectedMagic {
        let readLength: Int
        let matches: ([UInt8]) -> Bool
    }

    private static func expectedMagic(forExtension ext: String) -> ExpectedMagic? {
        switch ext {
        case "mkv", "webm", "mka", "mks":
            return ExpectedMagic(readLength: 4) { head in
                Array(head.prefix(4)) == ebmlMagic
            }
        case "avi":
            return ExpectedMagic(readLength: 4) { head in
                Array(head.prefix(4)) == riffMagic
            }
        case "mp4", "m4v", "mov", "m4a":
            // ISO BMFF: 4-byte size then "ftyp".
            return ExpectedMagic(readLength: 8) { head in
                guard head.count >= 8 else { return false }
                return Array(head[4..<8]) == ftypMarker
            }
        default:
            return nil
        }
    }

    private static func readHead(_ url: URL, count: Int) -> [UInt8]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        return [UInt8](data)
    }
}
