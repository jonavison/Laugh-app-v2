import Foundation

enum PlaybackBackend: String {
    case avfoundation
    case mpv
}

enum DistributionChannel: String {
    case direct
    case appStore
}

enum PlaybackRuntime {
    static var distribution: DistributionChannel {
#if APP_STORE_BUILD
        return .appStore
#else
        return .direct
#endif
    }

    static var preferredBackend: PlaybackBackend {
#if ENABLE_MPV_BACKEND
        return .mpv
#else
        return .avfoundation
#endif
    }

    static var canUseBundledCodecStack: Bool {
        distribution == .direct
    }
}
