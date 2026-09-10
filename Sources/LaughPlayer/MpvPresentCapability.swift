import Foundation

/// Static present-path capability for in-process DirectMpv picture.
///
/// Distinct from runtime health: this answers “can we create a present path at all?”,
/// not “did drawing stay healthy mid-stream?”.
enum MpvPresentCapability: Equatable {
    /// OpenGL CAOpenGLLayer path — currently blacks out on this macOS; not selectable.
    case openGLDeprecated
    /// libmpv `MPV_RENDER_API_TYPE_SW` → CPU buffer → CALayer. Real picture for PGS routing.
    case softwareBlit
    /// Future: Metal / gpu-next present into Laugh’s surface.
    case metalUnavailable

    /// Present path we actually use for DirectMpv picture today.
    static var preferred: MpvPresentCapability {
        // Software blit is the only proven non-black in-window path until Metal present lands.
        .softwareBlit
    }

    /// True when DirectMpv may be chosen for picture (e.g. bitmap-only subs).
    static var canPresentPicture: Bool {
        preferred == .softwareBlit && MpvPlaybackController.isAvailable()
    }
}
