import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Builds AVURLAsset / AVPlayerItem with container hints so macOS opens more formats (e.g. .mkv).
enum VideoAssetLoader {
    enum ResolveResult {
        case success(AVURLAsset)
        case failure(PlaybackOpenFailure)
    }

    static func makePlayerItem(for url: URL) -> AVPlayerItem {
        AVPlayerItem(asset: makeAsset(for: url, mimeHint: mimeType(forExtension: url.pathExtension.lowercased())))
    }

    static func makeAsset(for url: URL) -> AVURLAsset {
        makeAsset(for: url, mimeHint: mimeType(forExtension: url.pathExtension.lowercased()))
    }

    /// Tries multiple AVURLAsset configurations and returns the first macOS reports as playable.
    static func resolvePlayableAsset(for url: URL) async -> ResolveResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(PlaybackErrorFormatter.openFailure(
                url: url,
                reason: "File not found.",
                probeDetails: "path missing"
            ))
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return .failure(PlaybackErrorFormatter.openFailure(
                url: url,
                reason: "File is not readable (check volume permissions).",
                probeDetails: "not readable"
            ))
        }

        let candidates = makeAssetCandidates(for: url)
        var probeLog: [String] = []

        for (index, asset) in candidates.enumerated() {
            var playable = false
            var videoTrackCount = 0
            var audioTrackCount = 0
            var errors: [String] = []

            do {
                playable = try await asset.load(.isPlayable)
            } catch {
                errors.append("isPlayable=\(PlaybackErrorFormatter.describe(error))")
            }

            do {
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                videoTrackCount = videoTracks.count
            } catch {
                errors.append("videoTracks=\(PlaybackErrorFormatter.describe(error))")
            }

            do {
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                audioTrackCount = audioTracks.count
            } catch {
                errors.append("audioTracks=\(PlaybackErrorFormatter.describe(error))")
            }

            probeLog.append(
                "candidate\(index): playable=\(playable) videoTracks=\(videoTrackCount) audioTracks=\(audioTrackCount)"
            )
            if !errors.isEmpty {
                probeLog.append("candidate\(index): errors=\(errors.joined(separator: ","))")
            }

            // Be permissive: some containers report partial probing errors but still play via AVPlayerItem.
            if playable || videoTrackCount > 0 {
                return .success(asset)
            }
        }

        return .failure(PlaybackErrorFormatter.openFailure(
            url: url,
            reason: "Cannot Open",
            probeDetails: probeLog.joined(separator: "; ")
        ))
    }

    static func openPanelContentTypes() -> [UTType] {
        var types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .audiovisualContent]
        let extensions = ["mkv", "webm", "avi", "wmv", "flv", "ogv", "m4v", "mp4", "mov"]
        for ext in extensions {
            if let type = UTType(filenameExtension: ext),
               !types.contains(where: { $0.identifier == type.identifier }) {
                types.append(type)
            }
        }
        if let matroska = UTType("org.matroska.mkv") {
            types.append(matroska)
        }
        return types
    }

    private static func makeAssetCandidates(for url: URL) -> [AVURLAsset] {
        let ext = url.pathExtension.lowercased()
        var mimeHints: [String?] = [mimeType(forExtension: ext), nil]
        if ext == "mkv" {
            mimeHints = ["video/x-matroska", "video/matroska", nil]
        }
        return mimeHints.map { makeAsset(for: url, mimeHint: $0) }
    }

    private static func makeAsset(for url: URL, mimeHint: String?) -> AVURLAsset {
        var options: [String: Any] = [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ]
        if let mimeHint {
            options["AVURLAssetOverrideMIMETypeKey"] = mimeHint
        }
        return AVURLAsset(url: url, options: options)
    }

    private static func mimeType(forExtension ext: String) -> String? {
        switch ext {
        case "mkv":
            return "video/x-matroska"
        case "webm":
            return "video/webm"
        case "avi":
            return "video/x-msvideo"
        case "wmv":
            return "video/x-ms-wmv"
        case "flv":
            return "video/x-flv"
        case "ogv":
            return "video/ogg"
        case "mpeg", "mpg":
            return "video/mpeg"
        case "ts", "m2ts":
            return "video/mp2t"
        default:
            guard let type = UTType(filenameExtension: ext),
                  let mime = type.preferredMIMEType else {
                return nil
            }
            return mime
        }
    }
}
