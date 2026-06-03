import AVFoundation
import Foundation

/// Chooses native AVFoundation, bundled mpv, or remux **before** attaching a player item.
enum PlaybackRoute: Equatable {
    case nativeAVFoundation
    case directMpv(reason: String)
    case compatibilityRemux(reason: String)
}

enum PlaybackRoutePlanner {
    /// Containers macOS AVFoundation often cannot open reliably; remux to MP4 first.
    private static let remuxContainerExtensions: Set<String> = [
        "mkv", "webm", "avi", "flv", "wmv", "ogv", "rm", "rmvb"
    ]

    /// Video codec tags that should be remuxed (e.g. hev1 → hvc1 in MP4) even inside .mp4.
    private static let remuxVideoCodecTags: Set<String> = [
        "hev1", "1veh", "vp09", "vp9 ", "av01", "av1 ", "theo", "wmv3", "vc1 ", "wvc1"
    ]

    /// Codecs that are fine in MP4/MOV via AVFoundation without remux.
    private static let nativeMP4VideoCodecTags: Set<String> = [
        "avc1", "h264", "x264", "1cva", "mp4v", "hvc1", "1cvh", "1dvh", "dvhe"
    ]

    static func route(for url: URL) async -> PlaybackRoute {
        if url.path.contains("/LaughPlayerFallback/") {
            return .nativeAVFoundation
        }

        let ext = url.pathExtension.lowercased()
        let mpvAvailable = PlaybackRuntime.canUseBundledCodecStack && MpvPlaybackController.isAvailable()
        let remuxAvailable = PlaybackRuntime.canUseBundledCodecStack && FFmpegVideoFallback.isAvailable()

        guard remuxAvailable || mpvAvailable else {
            return .nativeAVFoundation
        }

        if remuxContainerExtensions.contains(ext) {
            if mpvAvailable {
                return .directMpv(reason: "container.\(ext)")
            }
            return .compatibilityRemux(reason: "container.\(ext)")
        }

        var codecTag = FFmpegVideoFallback.probePrimaryVideoCodecTag(for: url)
        if codecTag == nil {
            codecTag = await probeVideoCodecTagViaAVFoundation(url: url)
        }
        if let codecTag {
            let tag = normalizeFourCC(codecTag)
            if remuxVideoCodecTags.contains(tag) {
                if mpvAvailable {
                    return .directMpv(reason: "codec.\(tag)")
                }
                return .compatibilityRemux(reason: "codec.\(tag)")
            }
            if ["mp4", "m4v", "mov"].contains(ext), nativeMP4VideoCodecTags.contains(tag) {
                return .nativeAVFoundation
            }
        }

        if ["mp4", "m4v", "mov"].contains(ext) {
            return .nativeAVFoundation
        }

        if !ext.isEmpty {
            if mpvAvailable {
                return .directMpv(reason: "container.\(ext)")
            }
            return .compatibilityRemux(reason: "container.\(ext)")
        }

        return .nativeAVFoundation
    }

    private static func normalizeFourCC(_ tag: String) -> String {
        let trimmed = tag.lowercased().trimmingCharacters(in: .whitespaces)
        if trimmed.count == 4 { return trimmed }
        return trimmed
    }

    private static func probeVideoCodecTagViaAVFoundation(url: URL) async -> String? {
        let result = await VideoAssetLoader.resolvePlayableAsset(for: url)
        guard case .success(let asset) = result else { return nil }
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }
            let formatDescriptions = try await track.load(.formatDescriptions)
            guard let formatDesc = formatDescriptions.first else { return nil }
            return fourCCString(CMFormatDescriptionGetMediaSubType(formatDesc))
        } catch {
            return nil
        }
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        let n = code.bigEndian
        let chars: [CChar] = [
            CChar((n >> 24) & 0xff),
            CChar((n >> 16) & 0xff),
            CChar((n >> 8) & 0xff),
            CChar(n & 0xff),
            0
        ]
        return String(cString: chars)
    }
}
