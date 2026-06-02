import AVFoundation
import Foundation

protocol PlaybackEngine {
    var backend: PlaybackBackend { get }
    func resolveVideoAsset(for url: URL) async -> VideoAssetLoader.ResolveResult
}

struct AVFoundationEngine: PlaybackEngine {
    let backend: PlaybackBackend = .avfoundation

    func resolveVideoAsset(for url: URL) async -> VideoAssetLoader.ResolveResult {
        await VideoAssetLoader.resolvePlayableAsset(for: url)
    }
}

struct MpvEngine: PlaybackEngine {
    let backend: PlaybackBackend = .mpv

    func resolveVideoAsset(for url: URL) async -> VideoAssetLoader.ResolveResult {
        // Until libmpv surface is fully integrated, keep compatibility behavior via AVFoundation probing.
        await VideoAssetLoader.resolvePlayableAsset(for: url)
    }
}

enum PlaybackEngineFactory {
    static func make() -> PlaybackEngine {
        switch PlaybackRuntime.preferredBackend {
        case .mpv:
            return MpvEngine()
        case .avfoundation:
            return AVFoundationEngine()
        }
    }
}
