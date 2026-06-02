# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added
- Playback runtime/distribution abstraction (`PlaybackRuntime`, `PlaybackEngine`, `PlaybackEngineFactory`) with backend metadata in debug info.
- Bundled codec tool discovery (`BundledCodecTools`) and direct/app-store build scripts:
  - `scripts/build-direct.sh`
  - `scripts/build-appstore.sh`
  - `scripts/bundle-codec-tools.sh`
- ADR `0002-dual-distribution-codec-strategy.md` documenting direct vs App Store codec approach.
- Docked **MediaLibraryPanel** (Cursor-style): folders on the left, media list on the right; playback opens in the center container.
- **UserLibraryFolder** support: add/remove custom folders via +/−; paths persist with security-scoped bookmarks.
- Library scans videos and images under each **LibraryFolder** (up to 500 items); built-in Movies and ~/Videos roots remain.
- Library transport control toggles the panel; center content resizes when the panel is open. Settings stay on the right only.

### Changed
- FFmpeg fallback now prefers bundled codec tools in direct builds before system PATH tools.
- Compatibility failure messaging now distinguishes direct-build bundled-tools missing vs App Store native-only behavior.
- Drag-and-drop onto the main play area dismisses the settings sheet only (library panel stays available).

### Added
- Initial native AppKit-based LaughPlayer app structure.
- Aspect-ratio lock preference and window aspect management.
- Drag-and-drop support with bottom-right queue drop zone.
- In-window open-video action and playback diagnostics.
- Unsupported codec user messaging and compatibility warnings.
- `Cmd+Shift+D` playback debug info panel (window/video/audio/runtime details).
- `SUPPORT.md` as media compatibility source of truth.
- Documentation policy in `README.md` requiring changelog/support updates.
- `CONTEXT.md` glossary for responsiveness language (`ContentWidthPoints`, control density tiers, modular controls, strict KPI).
- Responsive 3-tier playback controls (Compact/Regular/Spacious) with modular control visibility by content width points.
- Core custom controls: play/pause, seek, volume, timeline label, and spacious-tier media metadata labels.
- UI interaction timing logs (`[DEBUG-ui]`) for play/pause, seek, volume, and tier-layout updates.
- Two-row transport layout: top row (`Previous`, `Play/Pause`, `Next`, conditional `Queue`, `Settings`) and bottom row (`Current Time`, seek bar, `Total Time`, volume).
- Queue visibility behavior: `Queue` button is hidden when there are no queued videos.
- Right-side in-player settings sheet opened from playback `Settings`, with top tabs: `VIDEO`, `AUDIO`, `SUBTITLES`.
- Right-edge hover behavior added: moving mouse over the right-side hot zone opens the settings sheet.
- Settings sheet visibility behavior updated: remains open until outside click or re-clicking the `Settings` button.
- Opening a video now auto-shows both playback controls and the right settings panel by default.

### Added
- Phase 1 codec policy: try-then-fail for additional containers; `PlaybackRenderMonitor` for black/missing video detection; non-blocking `CompatibilityBannerView` on confirmed failures only.

### Changed
- Removed preemptive unsupported-codec modals and proactive `hev1` warnings; failures use compatibility banner instead of blocking alerts when playback partially works.
- Fixed `.mkv` / `.webm` open path: `VideoAssetLoader` sets Matroska/WebM MIME hints for AVFoundation; open panel lists matroska types; security-scoped file access for opened URLs.
- MKV open failures: async `resolvePlayableAsset` probes readability/playable tracks before playback; clearer errors for “Cannot Open” (including HEVC 10-bit MKV) with ffmpeg remux guidance.

### Documented (grill-with-docs, codec expansion)
- Codec roadmap: Phase 1 native AVFoundation (more containers, try-then-fail, failure-only alerts); Phase 2 opt-in alternate decoder (FFmpeg) on real failure.
- Glossary terms: NativePlaybackEngine, AlternateDecoder, TryThenFailPolicy, CompatibilityFailure.

### Documented (grill-with-docs)
- Empty vs video vs image UI states: playback controls and settings sheet only when media is loaded; empty surface shows drop/open only.
- Image drops open Image mode with image controls; queue zone remains video-only; settings tabs are contextual by media kind.

### Added
- `MediaKind.swift` for video/image detection from file extension and UTType.
- Image playback surface with zoom/fit controls and IMAGE/FIT settings tabs.
- Empty surface on launch: drop zone + open hint only (no playback bar, no settings sheet).

### Changed
- Main drop routes by media type (video → playback controls, image → image controls).
- Queue drop zone accepts videos only; photos rejected with guidance.
- Right-edge hover opens settings only when media is loaded (not on empty surface).
- Removed auto-open settings sheet on video load.
- Playback bar restyled like Music.app: centered floating bar, rounded translucent chrome, SF Symbol transport controls, and responsive width (360–560pt) instead of full window width.
- Right settings panel flush to window edge (full height top-to-bottom), no rounded border; playback bar and queue stay above the panel in z-order.
- Settings tab titles (VIDEO / AUDIO / SUBTITLES and IMAGE / FIT) centered in the right panel.

### Changed
- Switched video rendering path to `AVPlayerLayer`-backed surface for better reliability in audio-only/black-video symptom cases.
