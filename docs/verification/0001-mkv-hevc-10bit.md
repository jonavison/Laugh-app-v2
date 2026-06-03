# Playback verification: MKV + HEVC 10-bit (x265)

**Status:** Pending **PlaybackVerificationRecord** — do not move this profile to **Currently Supported** in SUPPORT.md until complete.

**ADR:** [0003](../adr/0003-system-decode-compatibility-remux-not-videotoolbox.md) — expect **CompatibilityRemux** on direct builds, not a VideoToolbox-only path.

## PlaybackProfile

- Container: `.mkv` (Matroska)
- Video: HEVC / x265, 10-bit (typical personal rip; “Baraka-style” native failure)
- Audio: any track present in fixture (often AAC or AC-3)

## Intended engine (direct build)

1. **NativePlaybackEngine** — try open; expect **CompatibilityFailure** or open failure.
2. **AlternateDecoder** — auto **CompatibilityRemux** (`FFmpegVideoFallback`, stream copy + `hvc1` tag).
3. Replay remuxed temp MP4 via **NativePlaybackEngine**.

App Store build: **SystemDecodeStack** only; expect failure messaging without remux.

## Fixture

- One short clip (30–120s) matching this profile.
- Note path in PR/commit (do not commit large binaries to the repo unless the project adds a fixtures policy).

## Verification steps

1. Build direct: `./scripts/build-direct.sh` with `ffmpeg` in `Sources/LaughPlayer/codec-tools/bin/`.
2. Open fixture; confirm video visible and audio in sync after fallback (if native fails first).
3. `Cmd+Shift+D` — capture fourcc, dimensions, tracks, backend/runtime lines.
4. Repeat once after quit/relaunch (cache hit under `LaughPlayerFallback/`).
5. Paste snapshot into commit or PR as **PlaybackVerificationRecord**.

## Pass criteria

- No sustained **CompatibilityFailure** after remux completes.
- Remux method `remux` or `remux-cache` in debug logs; no required heavy transcode.

## On pass

Update [SUPPORT.md](../../SUPPORT.md): add profile under **Currently Supported** (AlternateDecoder path) and mark queue row 1 verified.
