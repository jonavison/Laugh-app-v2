import Foundation

/// Detects media files that exist on disk but are not yet playable — a torrent still
/// downloading (preallocated / zero-filled before the header piece arrives), or a
/// truncated/corrupt container whose magic bytes never match.
///
/// Performance first: only cheap `stat` + a few small seeks. No ffmpeg smokes on open.
enum IncompleteMediaProbe {
    /// Matroska / WebM EBML magic (`1A 45 DF A3`).
    private static let ebmlMagic: [UInt8] = [0x1A, 0x45, 0xDF, 0xA3]
    private static let riffMagic: [UInt8] = Array("RIFF".utf8)
    private static let ftypMarker: [UInt8] = Array("ftyp".utf8)

    /// Bytes per interior sample. Piece holes are typically ≥256KB; 64KB all-zero is decisive
    /// and stays under a millisecond on SSD / a few ms on HDD.
    static let interiorSampleBytes = 64 * 1024
    /// Skip interior sampling on tiny files (header check is enough).
    private static let interiorSampleMinFileBytes = 2 * 1024 * 1024
    /// ~10 samples × 64KB ≈ 640KB I/O — still milliseconds, far cheaper than an ffmpeg smoke.
    private static let interiorSampleFractions: [Double] = [
        0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90
    ]

    /// True when the container cannot be opened at all (bad / zero magic).
    static func looksLikeUnreadableContainer(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard let expected = expectedMagic(forExtension: ext) else { return false }
        guard let head = readHead(url, count: expected.readLength) else { return true }
        if head.allSatisfy({ $0 == 0 }) { return true }
        return !expected.matches(head)
    }

    /// True when the file is still downloading (sparse allocation or hollow interior zeros)
    /// but may still have a usable header for progressive start.
    static func looksLikeIncompleteDownload(at url: URL) -> Bool {
        looksLikeSparsePreallocation(at: url) || looksLikeHollowInterior(at: url)
    }

    /// Hard fail for open: unreadable header, or incomplete download when callers want a
    /// single combined check. Prefer the split APIs for remux routing.
    static func looksLikeIncompleteOrDamaged(at url: URL) -> Bool {
        looksLikeUnreadableContainer(at: url) || looksLikeIncompleteDownload(at: url)
    }

    /// Approximate on-disk completeness from allocated vs logical size (nil if unknown).
    static func downloadProgressFraction(at url: URL) -> Double? {
        guard let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ]) else { return nil }
        let logical = values.fileSize ?? 0
        guard logical > 0 else { return nil }
        let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
        return min(1, max(0, Double(allocated) / Double(logical)))
    }

    /// Preallocated torrents advertise the full `fileSize` while `fileAllocatedSize` stays
    /// low until pieces land. Remuxing that holey file yields a seek-freezing MP4 with a
    /// full duration header and a sparse payload — never cache a full remux while this is true.
    static func looksLikeSparsePreallocation(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else {
            return false
        }
        let logical = values.fileSize ?? 0
        let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize
        return !sourcePayloadLooksMaterialized(logicalBytes: logical, allocatedBytes: allocated)
    }

    /// Pure policy for tests: allocated ≪ logical ⇒ still downloading / sparse.
    static func sourcePayloadLooksMaterialized(
        logicalBytes: Int,
        allocatedBytes: Int?,
        minimumRatio: Double = 0.98
    ) -> Bool {
        guard logicalBytes > 1_000_000 else { return true }
        guard let allocatedBytes else { return true }
        return Double(allocatedBytes) >= Double(logicalBytes) * minimumRatio
    }

    /// Cheap readiness gate for zero-filled torrent holes that still report full allocation.
    static func looksLikeHollowInterior(at url: URL) -> Bool {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size >= interiorSampleMinFileBytes else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        var offsets: [UInt64] = interiorSampleFractions.map { fraction in
            UInt64(Double(size) * fraction)
        }
        let tail = max(0, size - interiorSampleBytes)
        offsets.append(UInt64(tail))

        for offset in offsets {
            guard let sample = readSample(handle: handle, offset: offset, count: interiorSampleBytes) else {
                return true
            }
            if sampleLooksUnmaterialized(sample) {
                return true
            }
        }
        return false
    }

    /// Fraction of the file (by byte offset) that is contiguous from the start before the
    /// first hollow slab. Used to time-cap progressive remux so AVPlayer never walks a
    /// full-duration timeline full of undownloaded holes (clock advances, picture freezes).
    static func contiguousHeadFraction(at url: URL) -> Double {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size >= interiorSampleMinFileBytes else { return 1 }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }

        // 2% steps ≈ 50 seeks × 64KB — milliseconds on SSD, decisive for torrent heads.
        let step = 0.02
        var fraction = 0.0
        while fraction < 0.999 {
            let offset = UInt64(Double(size) * fraction)
            guard let sample = readSample(handle: handle, offset: offset, count: interiorSampleBytes) else {
                return max(0, fraction - step)
            }
            if sampleLooksUnmaterialized(sample) {
                return max(0, fraction)
            }
            fraction += step
        }
        return 1
    }

    /// True when a slab is effectively empty (preallocated / undownloaded piece).
    static func sampleLooksUnmaterialized(_ data: Data) -> Bool {
        guard !data.isEmpty else { return true }
        return data.allSatisfy { $0 == 0 }
    }

    /// True when ffmpeg's stderr matches a missing/corrupt container-header failure.
    static func looksLikeIncompleteOrDamaged(ffmpegStderr: String) -> Bool {
        let lowered = ffmpegStderr.lowercased()
        if lowered.contains("ebml header parsing failed")
            || lowered.contains("invalid as first byte of an ebml number")
            || lowered.contains("0x00 at pos 0") {
            return true
        }
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

    private static func readSample(handle: FileHandle, offset: UInt64, count: Int) -> Data? {
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
