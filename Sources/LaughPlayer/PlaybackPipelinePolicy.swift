import AVFoundation

/// Hardens AVPlayer for long local-file sessions.
/// Spatialization of multi-channel AAC on Bluetooth head-tracked routes has been observed
/// to tear down the audio queue while the clock keeps advancing (frozen picture + silence).
enum PlaybackPipelinePolicy {
    static func configure(_ player: AVPlayer) {
        player.allowsExternalPlayback = false
    }

    static func configure(_ item: AVPlayerItem) {
        // Empty set = never spatialize. Keeps 5.1 as discrete channels / simple downmix.
        item.allowedAudioSpatializationFormats = []
    }
}
