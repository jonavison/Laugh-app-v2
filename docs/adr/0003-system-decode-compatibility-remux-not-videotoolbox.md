# ADR 0003: System decode + compatibility remux (not VideoToolbox replacement)

## Status

Accepted (2026-06-03), amended (2026-06-02) — direct **mpv** path for non-native containers

## Context

LaughPlayer’s near-VLC goal requires container bridging (for example Matroska + HEVC 10-bit) and tag fixes (for example `hev1` → `hvc1`), not a longer native fourcc list. **VideoToolbox** is already used inside **SystemDecodeStack** when macOS accepts a file; calling `VTDecompressionSession` directly does not add VP9/AV1/WebM demux or MKV coverage without reimplementing demux and frame presentation.

A separate question is whether **AlternateDecoder** should be in-player decode (bundled mpv) or pre-play **CompatibilityRemux** (bundled FFmpeg) before AVPlayer.

## Decision

1. **Primary:** **NativePlaybackEngine** = **SystemDecodeStack** (AVFoundation). Do not replace this with a custom VideoToolbox-only pipeline for breadth.
2. **Direct-build alternate (default when mpv is bundled and runnable):** **DirectMpv** — subprocess mpv embedded in the video surface (`MpvPlaybackController`, JSON IPC). Zero-wait open for MKV/WebM and similar containers.
3. **Direct-build fallback:** **CompatibilityRemux** via bundled FFmpeg (`FFmpegVideoFallback`) when mpv is missing, fails to spawn, or IPC ready times out — stream copy to temp MP4, then **SystemDecodeStack**. Heavy transcode stays opt-in (`LAUGH_ENABLE_HEAVY_TRANSCODE`).
4. **App Store:** **SystemDecodeStack** only (no bundled mpv/remux per ADR 0002).

mpv may use VideoToolbox as hwaccel internally; that is not “VideoToolbox instead of FFmpeg.”

## Consequences

- Phase 2 queue items are verified against **DirectMpv** first on direct builds, then **CompatibilityRemux** if mpv is unavailable.
- App Store builds stay **SystemDecodeStack**-only per ADR 0002.
- Bundled mpv must be portable (same constraint as bundled ffmpeg); Homebrew-linked binaries are not supported for ship.

## Alternatives considered

- **VideoToolbox instead of FFmpeg for remaining codecs:** Rejected — no demux/remux; does not match SUPPORT.md Phase 2 profiles.
- **Remux-only forever:** Superseded for direct builds where mpv is bundled — remux adds latency and disk IO on first play.
- **libmpv in-process (v1):** Deferred — subprocess mpv + `--wid` ships first; libmpv if lifecycle/UI limits bite.
- **FFmpeg software decode inside LaughPlayer UI:** Rejected as default — remux-then-native keeps AVPlayer integration when mpv is not used.
