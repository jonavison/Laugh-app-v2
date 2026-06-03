# ADR 0003: System decode + compatibility remux (not VideoToolbox replacement)

## Status

Accepted (2026-06-03)

## Context

LaughPlayer’s near-VLC goal requires container bridging (for example Matroska + HEVC 10-bit) and tag fixes (for example `hev1` → `hvc1`), not a longer native fourcc list. **VideoToolbox** is already used inside **SystemDecodeStack** when macOS accepts a file; calling `VTDecompressionSession` directly does not add VP9/AV1/WebM demux or MKV coverage without reimplementing demux and frame presentation.

A separate question is whether **AlternateDecoder** should be in-player decode (bundled mpv) or pre-play **CompatibilityRemux** (bundled FFmpeg) before AVPlayer.

## Decision

1. **Primary:** **NativePlaybackEngine** = **SystemDecodeStack** (AVFoundation). Do not replace this with a custom VideoToolbox-only pipeline for breadth.
2. **Direct-build alternate (now):** **CompatibilityRemux** via bundled FFmpeg (`FFmpegVideoFallback`) — stream copy to temp MP4, then **SystemDecodeStack**. Heavy transcode stays opt-in (`LAUGH_ENABLE_HEAVY_TRANSCODE`).
3. **In-player alternate (later, optional):** Bundled **mpv** remains a stub (`MpvEngine`); not the default path until a **VerifiedPlaybackPath** and ADR update justify the integration cost. mpv may use VideoToolbox as hwaccel internally; that is not “VideoToolbox instead of FFmpeg.”

## Consequences

- Phase 2 queue items (MKV HEVC 10-bit, VP9, AV1) are verified against **CompatibilityRemux** + replay, not against a new VT API surface.
- App Store builds stay **SystemDecodeStack**-only per ADR 0002.
- Future mpv work is a deliberate fork from remux-only; document verification before switching defaults.

## Alternatives considered

- **VideoToolbox instead of FFmpeg for remaining codecs:** Rejected — no demux/remux; does not match SUPPORT.md Phase 2 profiles.
- **mpv as primary alternate now:** Rejected for now — higher integration and distribution cost; remux-first already unblocks many “native fails” cases.
- **FFmpeg software decode inside LaughPlayer UI:** Rejected as default — remux-then-native keeps AVPlayer integration and UI consistency.
