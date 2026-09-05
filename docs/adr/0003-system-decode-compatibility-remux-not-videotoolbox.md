# ADR 0003: System decode + compatibility remux (not VideoToolbox replacement)

## Status

Accepted (2026-06-03), amended (2026-08-24) — picture via remux + AVPlayer; DirectMpv is not the display engine

## Context

LaughPlayer’s near-VLC goal requires container bridging (for example Matroska + HEVC 10-bit) and tag fixes (for example `hev1` → `hvc1`), not a longer native fourcc list. **VideoToolbox** is already used inside **SystemDecodeStack** when macOS accepts a file; calling `VTDecompressionSession` directly does not add VP9/AV1/WebM demux or MKV coverage without reimplementing demux and frame presentation.

A separate question is whether **AlternateDecoder** should be in-player decode (bundled mpv) or pre-play **CompatibilityRemux** (bundled FFmpeg) before AVPlayer.

## Decision

1. **Primary / picture:** **NativePlaybackEngine** = **SystemDecodeStack** (AVPlayer, Metal). This is the 2026 display tool for LaughPlayer.
2. **Direct-build alternate:** **CompatibilityRemux** via bundled FFmpeg (`FFmpegVideoFallback`) — stream copy to temp MP4, then **SystemDecodeStack**. Heavy transcode stays opt-in (`LAUGH_ENABLE_HEAVY_TRANSCODE`).
3. **DirectMpv** is not used for picture. macOS mpv 0.41 removed `--wid`; cocoa-cb / macvk always opens its own window. libmpv’s public render API is still OpenGL (`CAOpenGLLayer`), which Apple deprecated and which currently presents black video here. DirectMpv remains an opt-in path (**ExtendedPlaybackForSubtitles**) until libmpv exposes a Metal / gpu-next render context.
4. **App Store:** **SystemDecodeStack** only (no bundled mpv/remux per ADR 0002).

mpv may use VideoToolbox as hwaccel internally; that is not “VideoToolbox instead of FFmpeg.”

## Consequences

- Phase 2 queue items are verified against **CompatibilityRemux** + **NativePlaybackEngine** on direct builds.
- App Store builds stay **SystemDecodeStack**-only per ADR 0002.
- First-open remux costs disk and time on large rips; that is accepted until libmpv can present into a Metal surface.

## Alternatives considered

- **VideoToolbox instead of FFmpeg for remaining codecs:** Rejected — no demux/remux; does not match SUPPORT.md Phase 2 profiles.
- **Subprocess mpv + `--wid`:** Dead on macOS mpv 0.41 — cocoa-cb always creates its own window.
- **In-process libmpv + OpenGL render API:** Rejected as the picture engine — OpenGL is deprecated; current macOS presents black video. Keep the code only for opt-in subtitle sessions until a Metal render API exists (~mpv 0.42 / gpu-next in libmpv).
- **libmpv software blit:** Possible but CPU-heavy; not the default while remux + AVPlayer already works.
