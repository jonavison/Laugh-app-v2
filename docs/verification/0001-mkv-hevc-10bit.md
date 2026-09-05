# Playback verification: MKV + HEVC 10-bit (x265)

**Status:** Pending **PlaybackVerificationRecord** — do not move this profile to **Currently Supported** in SUPPORT.md until complete.

**ADR:** [0003](../adr/0003-system-decode-compatibility-remux-not-videotoolbox.md) — expect **CompatibilityRemux** then **NativePlaybackEngine** on direct builds.

## PlaybackProfile

- Container: `.mkv` (Matroska)
- Video: HEVC / x265, 10-bit (typical personal rip; “Baraka-style” native failure)
- Audio: any track present in fixture (often AAC or AC-3)

## Intended engine (direct build)

1. **PlaybackRoutePlanner** — `.compatibilityRemux(reason: container.mkv)` when FFmpeg remux is available.
2. **CompatibilityRemux** — stream-copy temp MP4, then **SystemDecodeStack** / AVPlayer in `PlayerSurfaceView`.
3. **Fallback** — if remux is missing, **DirectMpv** (opt-in picture path; OpenGL, not the default).

App Store build: **SystemDecodeStack** only; expect failure messaging without mpv/remux.

## Fixture

- One short clip (30–120s) matching this profile.
- Note path in PR/commit (do not commit large binaries to the repo unless the project adds a fixtures policy).

## Prerequisites

- Runnable bundled mpv at `Sources/LaughPlayer/codec-tools/bin/mpv` (see `./scripts/bundle-codec-tools.sh`; must not depend on Homebrew Cellar paths).
- Runnable bundled ffmpeg (for fallback verification).

## Verification steps

1. Build direct: `./scripts/build-direct.sh` with portable `mpv` and `ffmpeg` in `codec-tools/bin/`.
2. Open fixture; confirm video visible immediately (debug log contains `[DEBUG-route] planned mpv` and `[DEBUG-mpv] playback started`, **not** `[DEBUG-route] planned remux` on first open).
3. `Cmd+Shift+D` — confirm `Playback backend: mpv`.
4. Exercise transport: play/pause, seek, speed, volume, queue next/previous if applicable.
5. Quit and relaunch; open same file again (still mpv path).
6. (Optional) Rename/remove mpv binary temporarily; confirm remux fallback still plays.
7. Paste snapshot into commit or PR as **PlaybackVerificationRecord**.

## Pass criteria

- No sustained **CompatibilityFailure** on first open with mpv bundled.
- No remux log on first open when mpv is available.
- Transport controls work under mpv backend.

## On pass

Update [SUPPORT.md](../../SUPPORT.md): add profile under **Currently Supported** (DirectMpv path) and mark queue row 1 verified.
