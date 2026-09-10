import AVFoundation
import Foundation

/// Chooses native AVFoundation, bundled mpv, or remux **before** attaching a player item.
enum PlaybackRoute: Equatable {
    case nativeAVFoundation
    case directMpv(reason: String)
    case compatibilityRemux(reason: String)
}

enum PlaybackRoutePlanner {
    struct Inputs: Equatable {
        var pathExtension: String
        var mpvAvailable: Bool
        var remuxAvailable: Bool
        var videoCodecTag: String?
        var hasSidecars: Bool
        /// Open-time EmbeddedSubtitleTrack codecs from ffmpeg probe (empty if unknown).
        var subtitleCodecs: [String] = []
        /// Static present capability (software blit today).
        var presentCapable: Bool = false
    }

    /// Containers macOS AVFoundation often cannot open reliably; remux to MP4 first.
    static let remuxContainerExtensions: Set<String> = [
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
        let presentCapable = MpvPresentCapability.canPresentPicture

        guard remuxAvailable || mpvAvailable else {
            return .nativeAVFoundation
        }

        let subtitleCodecs: [String]
        if IncompleteMediaProbe.looksLikeIncompleteDownload(at: url) {
            // Progressive remux / tip wins until the file is materialized.
            subtitleCodecs = []
        } else if remuxContainerExtensions.contains(ext) || presentCapable {
            subtitleCodecs = FFmpegVideoFallback.probeSubtitleCodecs(for: url)
        } else {
            subtitleCodecs = []
        }

        if remuxContainerExtensions.contains(ext) {
            return route(from: Inputs(
                pathExtension: ext,
                mpvAvailable: mpvAvailable,
                remuxAvailable: remuxAvailable,
                videoCodecTag: nil,
                hasSidecars: false,
                subtitleCodecs: subtitleCodecs,
                presentCapable: presentCapable
            ))
        }

        var codecTag = FFmpegVideoFallback.probePrimaryVideoCodecTag(for: url)
        if codecTag == nil {
            codecTag = await probeVideoCodecTagViaAVFoundation(url: url)
        }
        let hasSidecars = !CompanionSubtitleDiscovery.discover(for: url).isEmpty
        return route(from: Inputs(
            pathExtension: ext,
            mpvAvailable: mpvAvailable,
            remuxAvailable: remuxAvailable,
            videoCodecTag: codecTag,
            hasSidecars: hasSidecars,
            subtitleCodecs: subtitleCodecs,
            presentCapable: presentCapable
        ))
    }

    /// True when open should skip native attach and go straight to remux/mpv planning.
    static func prefersFastRemux(for url: URL) -> Bool {
        remuxContainerExtensions.contains(url.pathExtension.lowercased())
    }

    /// DirectMpv already reads duration from the file; an extra `ffmpeg -i` contends for disk on large rips.
    static func shouldProbeSourceDuration(for route: PlaybackRoute) -> Bool {
        if case .directMpv = route { return false }
        return true
    }

    static func route(from inputs: Inputs) -> PlaybackRoute {
        let ext = inputs.pathExtension.lowercased()
        let mpvAvailable = inputs.mpvAvailable
        let remuxAvailable = inputs.remuxAvailable

        guard remuxAvailable || mpvAvailable else {
            return .nativeAVFoundation
        }

        // Bitmap-only embeds need DirectMpv picture (software blit) — remux cannot carry PGS.
        if BitmapSubtitleRouting.shouldPreferDirectMpv(
            subtitleCodecs: inputs.subtitleCodecs,
            presentCapable: inputs.presentCapable,
            remuxAvailable: remuxAvailable,
            mpvAvailable: mpvAvailable
        ) {
            return .directMpv(reason: "subs.bitmapOnly")
        }

        // Picture is AVPlayer (Metal) by default. Software blit DirectMpv is for bitmap
        // routing (above) or when remux is unavailable.
        if remuxContainerExtensions.contains(ext) {
            if remuxAvailable {
                return .compatibilityRemux(reason: "container.\(ext)")
            }
            if mpvAvailable {
                return .directMpv(reason: "container.\(ext)")
            }
        }

        if let codecTag = inputs.videoCodecTag {
            let tag = normalizeFourCC(codecTag)
            if remuxVideoCodecTags.contains(tag) {
                if remuxAvailable {
                    let suffix = ["mp4", "m4v", "mov"].contains(ext) ? ".mp4" : ""
                    return .compatibilityRemux(reason: "codec.\(tag)\(suffix)")
                }
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
            if remuxAvailable {
                return .compatibilityRemux(reason: "container.\(ext)")
            }
            if mpvAvailable {
                return .directMpv(reason: "container.\(ext)")
            }
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
