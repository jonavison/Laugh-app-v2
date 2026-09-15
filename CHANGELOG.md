# Changelog

All notable changes to this project are documented in this file.

Marketing versions use **pre-1.0** semver (`0.y.z`) until LaughPlayer is production-ready — same convention as Smile. Older `1.x` tags were an early packaging mistake, not a claim of 1.0 readiness.

## [Unreleased]

## [0.9.5] - 2026-09-15

Fresh notarized DMG of current `main` (the previous 0.9.4 DMG predated several polish fixes).

### Fixed
- Progressive deep seek no longer pauses on a “Buffering seek…” banner — full remux starts earlier, polls faster, soft-lands on playable tip.
- Library **sidebar** top/bottom scroll overflow fades.
- Playback-bar **SUB** label uses the same grey as the other bar icons.

### Changed
- Remux cache: **12 GiB** folder budget; never retain a full remux **>4 GiB** (huge sources prefer DirectMpv / progressive package only).
- Sparkle update zips host on **GitHub Releases**; site serves `appcast.xml` only (zips exceed GitHub’s 100 MB repo limit).

## [0.9.4] - 2026-09-14

### Fixed
- Episode A→B→C switches no longer copy playhead/duration across files; resume store keys by source identity.
- Native **arm64** ffmpeg + host-arch Sparkle (no Intel/Rosetta Gatekeeper warning).
- Packaging: portable codecs, resource bundle location, DMG install path, post-install registration.

### Added
- File menu Open… / Open Folder…; Window Close; reliable Quit; Dock essentials.
- **Help → Check for Updates…** (Sparkle 2) and About panel for shipped apps.
- Notarized DMG / Sparkle / signing scripts; switch-stress harnesses.

## Prior notes (folded from earlier Unreleased)

### Fixed
- Ship native **arm64** ffmpeg (martin-riedl) instead of Intel evermeet, and thin Sparkle to the host CPU — removes the macOS “Intel-based Apps / Rosetta” warning on Apple Silicon.

### Fixed
- Production builds no longer ship Homebrew-linked `ffmpeg`/`mpv` (they only worked on the build Mac). Packaging now uses portable evermeet ffmpeg and relocates mpv dylibs to `@loader_path`, so MKV remux works for other users.

### Fixed
- Launch crash on clean installs: SPM resource bundle was only under `Contents/Resources/`, while `Bundle.module` looks next to `Contents/` (and otherwise fell back to a machine-local `.build` path). Packaged apps now embed the bundle at the app root and use a resilient `ResourceBundle` locator.

### Fixed
- Installer actually runs post-install scripts (`require-scripts=true`), registers LaughPlayer with Launch Services, and opens Applications so the app is visible after install.
- Ship a drag-to-Applications **DMG** (`create-dmg.sh`) as a clearer install path than the unsigned `.pkg` alone.

### Added
- **About LaughPlayer** in the app menu (system About panel with version, build, and icon).
- **Help → Check for Updates…** via Sparkle 2 for shipped apps (`https://avison-soft.com/laugh/appcast.xml`); packaging embeds Sparkle + Ed25519 public key. Dev builds omit the feed.
- Help → **Laugh on the Web…** opens `avison-soft.com/laugh`.

### Changed
- Marketing version reset to **0.3.0** (pre-production). Packaging scripts read `Packaging/RELEASE_VERSION` instead of hard-coded `1.0.0`.

### Added
- Resume playback where you left off: reopening a video (after quit or switching files) seeks back to the saved playhead. Positions under ~3s or near the end are ignored so finished videos start clean.
- While a **video is playing**, LaughPlayer now prevents idle display/system sleep (same idea as QuickTime / Safari). Pause, images, and the empty library still allow sleep.
- Playback diagnostics you can tail while a file plays: format probe (codec/audio/duration), route, remux/preview, and per-second buffer health (`starving` / `buffering` / `ready` / `full`) via `scripts/watch-playback-logs.sh`.
- Unit tests for format reading (`FFmpegProbeParser`), buffer health, container routing, and media-kind detection. Run with `./scripts/test.sh`.
- Image studio **Black & White** Contrast + Warmth; **Vignette** Midpoint.
- Image studio **ImageExport** / **ImageUserPreset**: footer on the edit sidebar when adjusts are dirty; export writes a new JPEG/PNG (original unchanged); saved looks appear on the Presets tab.
- Image studio Wave 1 develop tools: Whites/Blacks, Hue, Color balance, Split toning, Structure, Denoise, Vignette, Black & White; Mood presets High Key / Super Contrast; Film presets Portra / Fuji / Noir.
- Image studio preview pipeline: capped CI proxy while dragging sliders, full-res settle on background queue (Metal `CIContext` when available).
- Image studio layout: same-folder bottom **ImageFolderCarousel**, toggleable left library while viewing, and right-sidebar **ImageAdjustSettings** (brightness / contrast / saturation, display-only).
- Image toolbar parity with video chrome: Library, queue previous/next, Queue, and Settings.
- Image zoom Actual Size control, plus display-only rotate left/right on the image bar.
- Image **Crop** on the floating bar: Free / Original / 1:1 / 4:5 / 16:9, Cancel / Apply; display-only geometry included in **ImageExport**.
- Image double-click toggles Fit ↔ Actual Size (does not enter fullscreen).

### Changed
- Direct builds open `.mkv` / `.webm` / similar containers with **CompatibilityRemux** then **AVPlayer** (Metal) so picture stays in LaughPlayer. DirectMpv is not the display engine: mpv 0.41 cannot embed, and libmpv’s OpenGL render API blacks out on current macOS. DirectMpv remains only when remux is missing — the former **ExtendedPlaybackForSubtitles** opt-in was removed.
- Removed **Use extended playback for subtitles** from the Subtitles tab (it switched to DirectMpv and blacked out picture). Sidecar/external **.srt** / **.vtt** still work on native playback.
- Progressive remux preview transcodes **AC-3** to stereo AAC (same as E-AC-3) so instant preview is not a 1 KB stub. Long AC-3/E-AC-3 rips skip that preview and wait for stream-copy remux instead of encoding the whole soundtrack.
- Image studio develop state lives in **ImageAdjustSession** (params + section bypass + preview settle + Before/After presentation); sliders are a thin adapter; built-in Looks/Mood/Film recipes moved to `ImageAdjustPreset`.
- **Reset All** sits in **ImageStudioCommitFooter** above Save Preset / Export (footer also when crop/straighten/rotation is active; Reset All clears develop adjusts and display geometry).
- Crop toolbar: three rows — Aspect (picker + quick 1:1/4:5/16:9), Transform (rotate/flip), Cancel / Apply.
- Crop **Cancel** restores the uncropped original (clears applied crop/straighten); **Apply** commits the draft.
- Image studio **Edits** tab uses Luminar-style outline groups (Essentials / Landscape / Creative / Portrait / Professional): expandable tools (Develop, Color, Black & White, Details, Denoise, Vignette) with one-at-a-time accordion; unfinished tools stay grayed as Coming soon.
- Image floating bar uses a leading / centered tools / trailing accessory layout matching the video transport row.
- Image mode keeps the photo in the main container when the library opens (docked sidebar/browse) instead of replacing it with mini-preview overlay.
- Image studio: left library/folders hidden on open, right settings always shown, photo padded (Luminar-like), bottom carousel full-width with edge fades and no scrollbar.
- Opening Library during image studio uses the same pattern as video: full folder-management view, with the open photo in the bottom-right mini preview.
- Image studio meta bar above the carousel: favorite, 5-star rating, file name, Fit %, hide/show filmstrip, and Before/After adjust compare.
- Image tools bar sits under the photo (above meta/filmstrip); sibling switches no longer rebuild the carousel; filmstrip edge fades always draw (AppKit gradient, light/dark).
- Image studio uses a split layout: photo + carousel in the left content column, docked full-height edit sidebar on the right (not a floating settings sheet over the filmstrip).
- Image edit sidebar is layout-pinned (pushes photo/meta/carousel) with shared opaque chrome matching the filmstrip floor.

## [1.2.0] - 2026-06-03

### Added
- Immersive window chrome: frosted title bar matching the settings panel; auto-hides during video/image playback, pinned in library-only mode.
- Hybrid keyboard shortcuts (menus + in-player key monitor) with Help reference (`⌘/`).
- mpv extended playback path, audio track picker, EQ presets, and playback queue popover.
- Library browse sort menu: field options with separator, then ascending/descending; hidden when the folder is empty.

### Changed
- Library content top inset tracks title-bar chrome visibility.
- Mini preview close stops playback instead of expanding to full view.
- `.gitignore` excludes local build artifacts, bundled codec binaries, and `.agents/` tooling.

## [1.1.0]

### Added
- ADR `0003-system-decode-compatibility-remux-not-videotoolbox.md`: affirm **SystemDecodeStack** primary, **CompatibilityRemux** via FFmpeg on direct builds; reject VideoToolbox-only alternate; defer mpv as default alternate.
- Verification checklist `docs/verification/0001-mkv-hevc-10bit.md` for Phase 2 queue priority 1 (MKV + HEVC 10-bit).
- Glossary terms **SystemDecodeStack** and **CompatibilityRemux** in `CONTEXT.md`.
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
- ADRs 0001–0002 and `SUPPORT.md` Phase 2 queue aligned with ADR 0003 engine terminology.
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
