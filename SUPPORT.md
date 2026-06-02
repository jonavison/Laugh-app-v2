# LaughPlayer Support Matrix

This file is the single source of truth for media compatibility in LaughPlayer.

Keep it updated whenever codec detection or playback behavior changes.

## Currently Supported (Expected to Work)

### Video Codecs
- `avc1` (H.264)
- `hvc1` (HEVC)
- `mp4v` (MPEG-4 Part 2)

### Audio Codecs
- `aac` / MPEG-4 AAC

### Containers
- `.mp4`
- `.mov`
- `.m4v`
- `.mkv` (try-then-fail; depends on inner codec)
- `.webm` (try-then-fail)
- `.avi` (try-then-fail)

## Partially Supported / Known Issues

### Video Codecs
- `hev1` (HEVC parameter sets in bitstream)
  - Known issue: some files play audio but show black video.
  - Current behavior: app shows codec warning and unsupported/incompatible messages when playback fails.
  - Workaround: remux to `hvc1` or transcode to `avc1`.

### Containers
- Exotic or legacy containers (`.wmv`, `.flv`, etc.) may open but are not guaranteed.

## Not Supported (Current)

- Unknown / unlisted video fourcc codecs.
- Files with no readable video track.

## Verification policy (agreed)

Before moving a PlaybackProfile from **TODO** to **Currently Supported**:

1. Add or use a short fixture clip for that exact profile (one file per path).
2. Play it in a dev build with the intended engine (**NativePlaybackEngine** or **AlternateDecoder**).
3. Confirm no **CompatibilityFailure** (video visible, audio in sync).
4. Attach a **PlaybackVerificationRecord**: Cmd+Shift+D snapshot (fourcc, tracks, dimensions) in commit or PR notes.

No bulk matrix updates—**IncrementalCodecRollout** only.

## Roadmap (Grill-with-docs, agreed)

**Product goal:** Near-VLC breadth over time, via verified paths—not a longer native fourcc list.

### Phase 1 — Native (AVFoundation first)

- [x] Open more containers via try-then-fail: `.mkv`, `.webm`, `.avi` (and existing `.mp4` / `.mov` / `.m4v`).
- [x] Remove predictive “unsupported codec” alerts based on fourcc alone; only message on **CompatibilityFailure** (banner after real failure).
- [x] Detect render failures (no frames / black frame while audio plays) and show non-blocking banner with remediation hints.
- [ ] Expand debug panel metadata (profile, bit depth) as needed for triage.

### Phase 2 — Alternate decoder (opt-in, incremental)

- [ ] On native failure (or audio-only / black video), show **“Try alternate decoder”** (user opts in; no silent auto-FFmpeg).
- [ ] Integrate FFmpeg-based **AlternateDecoder** for profiles native cannot open.
- [ ] Roll out one **VerifiedPlaybackPath** per change; update this matrix only after **PlaybackVerificationRecord**.

#### Phase 2 rollout queue (verify each before the next)

| Priority | PlaybackProfile (example) | Why |
|----------|---------------------------|-----|
| **1 (next)** | MKV + HEVC 10-bit (x265) | Common personal rips; native fails (e.g. Baraka-style) |
| 2 | MP4 + `hev1` (black video) | Native partial; may need remux hint or alternate |
| 3 | WebM + VP9 | Common web rips |
| 4 | MKV/WebM + AV1 | Growing library share |
| 5 | Legacy AVI / WMV subsets | Lower priority unless fixtures exist |

Native engine will not grow arbitrary codecs; gaps move to **AlternateDecoder** after verification.

## TODO (To Be Supported)

- [ ] Improve `hev1` compatibility path within native engine (render-failure detection).
- [ ] Add richer codec parser (profile, level, bit depth, chroma subsampling).
- [ ] Add in-app compatibility banner with remediation actions (non-blocking).
- [ ] Add one-click conversion helper docs/commands in UI.
- [ ] Add automated compatibility fixtures/tests for representative sample files.

## Debugging Notes

Use `Cmd+Shift+D` in app to inspect:
- window size
- content size
- video size / aspect
- video codec fourcc
- audio codec summary
- playback time/rate
- queue count

## Updating Guidelines

When a new codec is confirmed:
1. Add it under **Currently Supported**.
2. Remove it from **Partially Supported** or **Not Supported**.
3. Add test media fixture notes (if available).
4. Update any related TODO item status.
