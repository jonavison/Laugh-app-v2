# LaughPlayer Context Glossary

## Responsiveness

Responsiveness means UI feedback remains effectively immediate during playback and resize interactions across very small displays through 8K+ environments.

## ContentWidthPoints

`ContentWidthPoints` is the canonical sizing basis for responsive layout decisions. It uses logical layout points (not raw pixels) to remain stable across Retina and scaled displays.

## ControlDensityTier

`ControlDensityTier` is the control complexity level selected by available content width:
- Compact: essential controls only.
- Regular: standard controls.
- Spacious: full controls with additional affordances.

## ModularControls

`ModularControls` means controls are progressively disclosed by tier. Compact mode prioritizes core playback operations and omits non-essential controls.

## MaxControlScaleCap

`MaxControlScaleCap` means controls can grow with available space only up to a defined comfort limit, after which control sizing remains stable.

## StrictResponsivenessKPI

`StrictResponsivenessKPI` means target interaction latency is under 50ms, with resize and control interactions tuned to avoid UI-induced playback degradation.

## EmptySurface

`EmptySurface` is the state before any media is loaded. Only drop/open affordances are shown; playback controls and the right settings sheet are not shown.

## VideoMedia

`VideoMedia` is an active video item. Video playback controls are shown; settings use video-oriented tabs.

## PlaybackResume

`PlaybackResume` restores the playhead when the user reopens a **VideoMedia** file after quitting, stopping, or switching away. Positions are keyed by source path (not remux cache), ignored under ~3s, and cleared near the end so finished videos start clean. Explicit handoff times (remux / engine switch) still win over the stored resume.

## ImageMedia

`ImageMedia` is an active still-image item. Image-oriented controls are shown instead of video playback controls. The image stays in the main container (not a separate fullscreen photo mode); the left **MediaLibraryPanel** remains toggleable.

## ImageFolderCarousel

`ImageFolderCarousel` is the bottom filmstrip shown during **ImageMedia** when the open file’s folder contains at least two images. It lists sibling images in that folder (sorted like **LibraryBrowseSort**). Clicking a thumbnail opens that image in the center surface.

## ImageStudioMetaBar

`ImageStudioMetaBar` sits above the filmstrip during **ImageMedia**: favorite + 5-star rating (persisted in `ImageLibraryMetaStore`), centered file name, and trailing Fit % / hide-show carousel / Before-After adjust compare.

## ImageAdjustSettings

`ImageAdjustSettings` is the **Edits** tab in the right **edit sidebar** for **ImageMedia**: display-only develop controls (Core Image graph on `ImageAdjustParameters`) that do not rewrite the file on disk. Tools are listed under outline groups (**Essentials**, **Landscape**, **Creative**, **Portrait**, **Professional**). Each **ImageDevelopTool** is a row that expands into controls when available; unfinished tools stay visible but grayed (“Coming soon”). Interactive drags render a capped **preview** proxy; after settle the surface re-renders at full resolution. The sibling **Presets** tab (Looks / Mood / Film / Saved) applies named looks over the same parameter model. When the current adjusts (or display crop/rotation) are not identity, an **ImageStudioCommitFooter** at the bottom of the sidebar offers **Reset All**, **ImageExport**, and **ImageUserPreset** save. Zoom/rotate/crop stay on the floating image bar; Before/After on **ImageStudioMetaBar** compares identity vs current adjusts via **ImageAdjustSession** presentation.

Opening **ImageMedia** hides the left **MediaLibraryPanel** / folders and docks a full-height right edit column beside a content column of photo + meta bar + **ImageFolderCarousel** (carousel does not extend under the sidebar). Opening Library during **ImageMedia** mirrors video: full folder management fills the window and the current photo moves to the bottom-right mini preview until the panel is closed or expanded.

Tool roadmap (waves, ease, section map): `docs/image-studio-develop-roadmap.md`. Policy: ADR `0004-image-studio-develop-display-only.md`. Selection stack: ADR `0005-smart-selection-protocol.md`.

## ImageAdjustSession

`ImageAdjustSession` is the source of truth for the current **ImageMedia** develop state: raw `ImageAdjustParameters`, which **ImageAdjustSection**s are bypassed, preview→full settle timing, and Before/After presentation (Before exposes identity without clearing edits). Sliders, Presets, and the surface read/write this session; they do not own the parameter values.

## SelectionMask

`SelectionMask` is an on-device selection matte in image pixel space: a single-channel / alpha `CGImage`, extent, confidence, optional `SemanticClass` (person, sky, rock, unknown, …), and `SelectionSource` (Vision / CoreML / point-prompt / brush). It feeds overlay / cutout preview, mask-scoped adjusts, and optional cutout export; it never rewrites the source file. Shared pipelines treat it as an alpha buffer — class labels are advisory metadata, never required for refine / compose / export to run (ADR 0005).

## SelectionProvider

`SelectionProvider` is the protocol for producing a `SelectionMask`. Callers use `selectClass`, `selectRegion(at:)`, or `select(prompt:)` without depending on Vision or CoreML. Accurate path **PR 1 pin:** **MobileSAM** via `MobileSAMSelectionProvider` + SamKit (`SelectionModelStore` download-once cache of encoder/decoder + prompt weights) — chosen for readiness/maturity, not ultimate quality lock. EfficientSAM/SAM2 reconsidered after measurement. Vision person remains fallback / person-tool prompt assist (ADR 0005).

## SelectionPrompt

`SelectionPrompt` is the class-blind point/box input for SAM-class providers (positive/negative points + optional box). Person Auto Select builds it in the tool layer via `SelectionPromptBuilder` from a rough Vision matte; the shared provider must not require Vision types.

## SelectionRefineParameters

`SelectionRefineParameters` is the class-blind edge refine model (Smooth / Feather / Contrast / Shift Edge today; brush / decontaminate later). It applies to any matte’s alpha the same way — sky, rock, hair, or unlabeled. Content-specific starting values come from `SelectionHint` / presets, not branches inside refine.

## SelectionHint

`SelectionHint` is an optional, advisory suggestion attached to a mask or select result (for example “likely sky → higher feather + graduated tone”). It is the only sanctioned place for content-aware defaults. It must not be required by refine, compositing, or export.

## ImageSelectionSession

`ImageSelectionSession` is the source of truth for the current **ImageMedia** selection matte: loading/error/download phase, display mode (Onion Skin / Marching Ants / Overlay / On Black / On White / Black & White / On Layers), `SelectionRefineParameters`, and cache invalidation on image change. It is separate from `ImageAdjustSession`. **Accurate Auto Select Person:** Vision rough matte → `SelectionPrompt` → MobileSAM matte; cancel download or CoreML miss → Vision matte fallback for that attempt. **Debt:** session still hardcodes person — clear in **W3-08d / PR 2**. Brush/decontam (**W3-08b**) waits until SAM edges exist. With a matte active, **F** cycles view modes (video still uses **F** for Fit/Fill). Default view is Marching Ants.

## ImageDevelopTool

`ImageDevelopTool` is one display-only adjust capability in **ImageAdjustSettings** (for example Develop, Vignette, or Color). Each tool is a row under an outline group (**Essentials**, **Landscape**, **Creative**, **Portrait**, **Professional**), expands into controls when implemented, and extends the shared parameter/CI graph. Unfinished tools remain listed but not expandable (“Coming soon”). **Subject Select** expands into selection controls via `ImageSelectionSession` rather than an `ImageAdjustSection`.

## ImageStudioCommitFooter

`ImageStudioCommitFooter` is the bottom bar of the right **edit sidebar** during **ImageMedia**. It appears while **ImageAdjustParameters** differ from identity, display geometry (crop / straighten / rotation) is active, or a **SelectionMask** is present, and holds **Reset All** above **ImageUserPreset** save and **ImageExport**. **Reset All** clears develop adjusts and the current selection matte (crop / straighten / rotation stay with their own Cancel).

## ImageCrop

`ImageCrop` is a display-only geometry edit on **ImageMedia**, entered from the floating image bar (next to Fit / Rotate). Crop mode offers Free / Original / 1:1 / 4:5 / 16:9 aspects, a draggable rectangle on the photo, free straighten by dragging the dimmed area beside the crop (±45°), and Cancel / Apply. **Apply** commits crop + straighten; **Cancel** exits and restores the uncropped original (clears any previously applied crop/straighten). Applied geometry is included in **ImageExport**. It does not rewrite the source file. AI crop is not part of this tool yet.

## ImageExport

`ImageExport` writes a new still of the current **ImageMedia** with the active **ImageAdjustParameters**, display rotation, and **ImageCrop** applied. It never replaces the source file. When a **SelectionMask** exists, **Export Cutout** writes a separate transparent PNG of the subject matte (also never overwrites the source).

## ImageUserPreset

`ImageUserPreset` is a named snapshot of **ImageAdjustParameters** saved from **ImageStudioCommitFooter**. Saved looks appear on the Presets tab and can be reapplied to any image.

## ContextualSettingsTabs

`ContextualSettingsTabs` means the right settings sheet tab set depends on active media kind (for example video tabs vs image tabs).

## QueueDropZone

`QueueDropZone` is the bottom-right drop target used to enqueue videos only. It appears during drag only when something is already playing or in the queue (`currentMediaURL` or a non-empty **Up Next** list). Photos are opened via the main play area, not via queue enqueue.

## MediaLibrary

`MediaLibrary` is the explorer for browsing disk folders and opening videos or images without the system open panel. It has a narrow sidebar for destinations and a wider content area for browsing.

## LibraryRoot

`LibraryRoot` is a top-level folder pinned in the MediaLibrary sidebar (for example Movies or Videos, or a `UserLibraryFolder`). Selecting a root resets browse to that folder’s top level and clears back/forward history for the previous root.

## LibraryFolder

`LibraryFolder` is a subfolder shown in the `LibraryBrowseGrid` — a child of the current browse location, not a sidebar entry. Single-click opens the folder and shows its immediate children in the grid.

## LibraryBrowseGrid

`LibraryBrowseGrid` is the MediaLibrary content area to the right of the sidebar. It shows one directory level at a time: subfolders and media files that are direct children of the current browse location. Presentation follows **LibraryBrowseViewMode** (Gallery by default — larger thumbs and more spacing). Single-click opens a subfolder or selects a media tile; media tiles show a centered play affordance over the file preview. Back and forward controls sit at the top-left; the current path is shown as a breadcrumb at the bottom. Item order follows `LibraryBrowseSort`, Finder-style (folders grouped before files when applicable).

## LibraryBrowseViewMode

`LibraryBrowseViewMode` is how the current browse listing is presented: **Gallery** (large photo tiles), **Grid** (medium tiles), or **List** (name / kind / date rows). The mode is a persisted user preference. **RecentlyViewed** stays list-only.

## LibraryBrowseGalleryScale

`LibraryBrowseGalleryScale` is the discrete tile size for **Gallery** only: small, medium, or large. It is adjusted with a stepped slider and does not apply to Grid or List.

## LibraryBrowseSearch

`LibraryBrowseSearch` is a name filter over the direct children of the current browse location (case-insensitive). Results replace the browse listing until the query is cleared. It does not search nested folders or other roots.

## LibraryKindFilter

`LibraryKindFilter` is a facet on the current browse listing: All, Videos, Images, or Folders. It composes with **LibraryBrowseSearch** (both must match).

## LibraryFavorites

`LibraryFavorites` is a sidebar destination listing still images the user marked favorite (from **ImageStudioMetaBar** / path-keyed favorites). It is not a disk folder and does not include videos in v1.

## LibraryMultiSelect

`LibraryMultiSelect` is selecting multiple browse entries (modifier-click) for batch Trash, Add to Queue, or Play. Plain single-click still opens a folder or media item.

## LibraryBrowseSort

`LibraryBrowseSort` is the ordering policy for items in the `LibraryBrowseGrid`. The user can sort Finder-style by name, date modified, date added, size, or kind, with ascending or descending order. Default is name ascending with folders grouped before files.

## LibraryBrowseNavigation

`LibraryBrowseNavigation` is back/forward history within a selected `LibraryRoot`, plus a bottom breadcrumb showing the current folder path. Breadcrumb segments are clickable to jump to an ancestor folder.

## LibraryMediaTile

`LibraryMediaTile` is a cell for a video or image file in the `LibraryBrowseGrid`. In **Gallery**, tiles are caption-free with tight spacing; hover shows a thin border (no title tooltip). In **Grid**, tiles show a thumbnail with a title underneath. Folder tiles always keep their name visible. Single-click triggers `LibraryMediaSelection` and opens the item in the center player.

## LibraryMediaSelection

`LibraryMediaSelection` is a single-click on a `LibraryMediaTile` in the `LibraryBrowseGrid`; the item opens in the center playback container as `VideoMedia` or `ImageMedia`, not inside the library panel or the settings column. After selection, the `MediaLibraryPanel` auto-hides so playback is unobstructed.

## MediaLibraryPanel

`MediaLibraryPanel` hosts the MediaLibrary UI (sidebar + browse). On **EmptySurface** it fills the main content. During **VideoMedia** or **ImageMedia**, opening Library shows full-window folder management with the current item in a bottom-right mini preview until the panel is closed. The sidebar lists **RecentlyViewed**, **LibraryFavorites**, and `LibraryRoot` folders.

## RecentlyViewed

`RecentlyViewed` is a sidebar entry pinned above `LibraryRoot` folders. Selecting it shows recently opened media as `LibraryMediaTile` items in the `LibraryBrowseGrid` (no subfolders). Single-click plays and auto-hides the panel.

## UserLibraryFolder

`UserLibraryFolder` is a `LibraryRoot` the user added with “Add folder…” and persisted via a security-scoped bookmark. User roots can be removed; built-in roots (Movies, Videos) cannot.

## SystemDecodeStack

`SystemDecodeStack` is macOS-provided demux and decode exposed through AVFoundation (including VideoToolbox hardware decode when the OS accepts the file). In conversation, “native” means this stack—not a separate VideoToolbox-only engine.

## NativePlaybackEngine

`NativePlaybackEngine` is playback through the **SystemDecodeStack** (AVPlayer / AVFoundation).

## CompatibilityRemux

`CompatibilityRemux` is an **AlternateDecoder** step that produces a temporary MP4 the **SystemDecodeStack** can open, preferring stream copy without re-encoding video. Embedded **text** subtitles (for example SRT in MKV) are muxed as `mov_text` so **NativePlaybackEngine** can expose them via `.legible`. Sidecar **.srt** / **.vtt** files play via the native subtitle overlay; ASS/SSA and bitmap (PGS) subs are not offered as a DirectMpv opt-in because **DirectMpv** picture currently blacks out on this macOS.

## AlternateDecoder

`AlternateDecoder` is a secondary path for profiles **SystemDecodeStack** cannot open directly. On direct builds the default is **CompatibilityRemux** via bundled FFmpeg into a temp MP4, then **NativePlaybackEngine** (AVPlayer / Metal). **DirectMpv** is not the picture engine: Homebrew mpv 0.41 cannot embed (`--wid` gone; cocoa-cb always opens its own window), and libmpv’s public render API is still OpenGL, which is deprecated and currently blacks out on this macOS. DirectMpv remains only when remux is unavailable.

## TryThenFailPolicy

`TryThenFailPolicy` means the app attempts playback first and surfaces compatibility messaging only after a real failure (no video track, decode error, or confirmed render failure)—not based on codec name alone.

## CompatibilityFailure

`CompatibilityFailure` is a confirmed playback failure after open (item failed, no frames, or black video with advancing audio), distinct from a predictive codec warning.

## PlaybackProfile

`PlaybackProfile` is the combination that determines whether a file can play (container, video codec, bit depth, pixel format, and audio codec)—not the file extension or fourcc label alone.

## VerifiedPlaybackPath

`VerifiedPlaybackPath` is a specific PlaybackProfile that has been manually test-driven and recorded before we claim it in the support matrix.

## IncrementalCodecRollout

`IncrementalCodecRollout` means adding one VerifiedPlaybackPath at a time (native or AlternateDecoder), with no bulk “codec list” expansion until the previous path is verified.

## PlaybackVerificationRecord

`PlaybackVerificationRecord` is evidence that a path was test-driven: a short fixture clip, a successful play session, and a Cmd+Shift+D debug snapshot attached to the change (commit or PR notes).

## AudioSettings (planned)

`AudioSettings` is the right-settings **Audio** tab: per-file audio controls while `VideoMedia` is active. Planned slices (in order): **AudioTrackPicker**, then **PlaybackEQ** (10-band with presets; Manual preset is default). **OutputSource** and **AudioDelay** are deferred unless a concrete need appears.

## AudioTrackPicker

`AudioTrackPicker` is the control that chooses which embedded audio stream plays in the current file. It is always shown in **AudioSettings** while a video is open: the current stream is selected; if the file has no audio, the control shows **None**. Each entry is labeled with stream details (for example index, language, channel count, codec/bitrate when known). It is not queue order, not subtitle tracks, and not system output device—that is **OutputSource**.

## AudioTrackSwitch

`AudioTrackSwitch` is changing the active stream via **AudioTrackPicker**. The user’s playhead time and play/pause state must be preserved, including when the new stream uses a different audio codec than the previous one. Prefer in-place switch on the active engine (**NativePlaybackEngine** or **DirectMpv**); if that fails, reload the same source from the prior time and restore play state (TryThenFailPolicy for track change, not for whole-file open).

## OutputSource

`OutputSource` is the user’s choice of macOS audio output device (speakers, headphones, interface) for LaughPlayer. Distinct from in-app **PlaybackVolume** on the transport bar. Not in the current **AudioSettings** slice—macOS system settings are sufficient unless a future need appears.

## PlaybackEQ

`PlaybackEQ` is in-app tone shaping (10 bands + named presets). **Manual** is the default preset (flat / user-adjusted bands). EQ state is **global** (persisted app preference, like playback speed)—not per file. v1 applies on **DirectMpv** only; **NativePlaybackEngine** gains EQ in a later slice. The Audio tab shows EQ controls when the active session can apply them, otherwise a short unavailable note. Distinct from codec, container, and **CompatibilityRemux**.

## AudioDelay

`AudioDelay` is a user-controlled lip-sync offset between audio and video. Not in the current **AudioSettings** slice—engines are expected to keep A/V sync; add only if real-world files prove otherwise.

## HybridKeyboardShortcuts

`HybridKeyboardShortcuts` means discoverable commands appear in the menu bar with displayed key equivalents, while core **TransportKeyboardCommand**s also work when the main playback window is key without visiting a menu or a visible control. **TransportKeyboardCommand**s remain available across **ControlDensityTier** levels, including **Compact** when bar controls are hidden.

## TransportKeyboardCommand

`TransportKeyboardCommand` is a keyboard-invoked user action for playback transport: play/pause, seek, **PlaybackVolume**, mute, queue previous/next, and playback speed steps. Distinct from app chrome shortcuts (Preferences, Quit) and from **ContextualSettingsTabs** adjustments unless explicitly mapped. Not the same as choosing a decode engine—that is **PlaybackProfile** routing, not transport.

## GlobalChromeShortcut

`GlobalChromeShortcut` is a keyboard command that works whenever the main playback window is key and **KeyboardFocusGuard** allows it—across **EmptySurface**, **VideoMedia**, and **ImageMedia**. Examples: open file, toggle **MediaLibraryPanel**, toggle the right settings sheet, fullscreen, Preferences, Quit. Does not include **TransportKeyboardCommand**s.

## KeyboardFocusGuard

`KeyboardFocusGuard` means **TransportKeyboardCommand**s and other global shortcuts yield when keyboard focus is in an editable or draggable settings control (slider, text field, pop-up). The control receives the key (for example Space does not toggle play/pause while adjusting **PlaybackEQ**).

## VideoMediaShortcutScope

`VideoMediaShortcutScope` is when **VideoMedia** is active: all **TransportKeyboardCommand**s are enabled. **GlobalChromeShortcut**s remain enabled.

## ImageMediaShortcutScope

`ImageMediaShortcutScope` is when **ImageMedia** is active: **TransportKeyboardCommand**s that imply motion (play/pause, seek, speed) are disabled. Image display commands (zoom, fit) and queue step commands apply when the queue or playback history has items—images may appear in the queue alongside videos. **GlobalChromeShortcut**s remain enabled.

## EmptySurfaceShortcutScope

`EmptySurfaceShortcutScope` is when no media is loaded: only **GlobalChromeShortcut**s are active. **TransportKeyboardCommand**s are disabled with no alert or error sound.

## StandardSeekStep

`StandardSeekStep` is the default **SeekKeyboardCommand** distance on **←** / **→**: ten seconds backward or forward while **VideoMedia** is active.

## FineSeekStep

`FineSeekStep` is the **SeekKeyboardCommand** distance with the Option modifier (**⌥←** / **⌥→**): one second backward or forward.

## RepeatSeekWhileHeld

`RepeatSeekWhileHeld` means holding **←** or **→** repeats **SeekKeyboardCommand** at a capped rate (about five steps per second) instead of a single step per keypress.

## SeekKeyboardCommand

`SeekKeyboardCommand` is a **TransportKeyboardCommand** that moves the playhead by **StandardSeekStep** or **FineSeekStep**. Distinct from queue previous/next and from scrubbing via the seek slider.

## EmbeddedSubtitleTrack

`EmbeddedSubtitleTrack` is a subtitle stream muxed inside the **VideoMedia** container (for example MKV text/ASS tracks, or legible tracks in some MP4/MOV). Exposed via **SubtitleTrackPicker** on **DirectMpv** (all common embed types) or **NativePlaybackEngine** (only when **SystemDecodeStack** exposes `.legible` options).

## CompanionSubtitleFile

`CompanionSubtitleFile` is a sidecar subtitle file on disk associated with the current **VideoMedia** by **CompanionSubtitleDiscovery** rules—not chosen through the load dialog. On **NativePlaybackEngine**, **.srt** / **.vtt** companions are playable via the native subtitle overlay and appear in **SubtitleTrackPicker**; **PrimarySubtitleTrack** stays off until the user enables it. ASS/SSA companions may be listed but are not playable while DirectMpv picture is unavailable. Distinct from **EmbeddedSubtitleTrack** and from user-picked **ExternalSubtitleFile**.

## CompanionSubtitleDiscovery

`CompanionSubtitleDiscovery` is how LaughPlayer finds **CompanionSubtitleFile**s for the open **VideoMedia**: case-insensitive basename match; extensions `.srt`, `.vtt`, `.ass`, `.ssa`; optional language tag (two–three letters or common names such as English) and optional `forced` before the extension. Search locations are the media folder, a sibling flat `Subs/` or `subtitles/` folder, and `Subs/<basename>/` or `subtitles/<basename>/` (Plex-style per-title folder)—not a recursive library-wide scan. Inside a per-title folder only that episode’s files are considered (any subtitle extension; language parsed from names like `2_English.srt`). A flat `Subs/` or `subtitles/` folder beside the video also accepts loose names (e.g. `3_English.srt` for a single movie). The media folder itself still requires basename match so unrelated sidecars are not picked up. All matches are attached; the user chooses among them in **SubtitleTrackPicker**.

## SubtitlesSettings

`SubtitlesSettings` is the right-settings **Subtitles** tab: **PrimarySubtitleTrack** picker, **ExternalSubtitleFile** load (.srt / .vtt on native), delay (−5s to +5s), vertical position, scale, and **SubtitleAppearance**. Sidecar discovery stays automatic — matches appear in **SubtitleTrackPicker**. **SecondarySubtitleTrack** is not shown in Tracks while DirectMpv picture is unavailable. There is no user-facing **ExtendedPlaybackForSubtitles** switch.

## SubtitleTrackPicker

`SubtitleTrackPicker` is the pop-up that chooses which embedded, companion, or loaded subtitle stream is primary or secondary. Distinct from **AudioTrackPicker**, **CompanionSubtitleFile** (auto-discovered), and **ExternalSubtitleFile** (user-picked). Track labels include index, language, and title when known.

## SubtitleTrackSwitch

`SubtitleTrackSwitch` is enabling or changing primary/secondary subtitle streams via the on/off toggles and pickers. Playhead and play/pause state must be preserved. On **DirectMpv**, uses `sid` / `secondary-sid`; on **NativePlaybackEngine**, primary uses `AVMediaSelection` for legible tracks.

## SecondarySubtitleTrack

`SecondarySubtitleTrack` is a second simultaneous subtitle stream (mpv `secondary-sid`). Requires **DirectMpv** and a file or external load that exposes multiple subtitle tracks.

## ExternalSubtitleFile

`ExternalSubtitleFile` is a subtitle file the user explicitly chose via the load dialog (any path). On **NativePlaybackEngine**, **.srt** / **.vtt** files play through the native subtitle overlay; after load, the file name is shown under Tracks. Distinct from **CompanionSubtitleFile**, which is found automatically beside the media.

## SubtitleAppearance

`SubtitleAppearance` is global persisted styling (font size, primary/outline/background colors, border width, background on/off) applied through mpv ASS force-style. Not per-file. Distinct from **PlaybackEQ** and from in-player **SubtitleTrackSwitch**.

## ReservedSubtitleShortcuts

`ReservedSubtitleShortcuts` are keyboard bindings for subtitle track and style controls (**V** / **G** / **S**) not wired in v1—the **Subtitles** tab is the source of truth until shortcuts are implemented without conflicting with other commands.

## GlobalVideoSettingsShortcut

`GlobalVideoSettingsShortcut` is a keyboard command for Video-tab settings (Fit/Fill toggle, window aspect cycle, loop, play-source switch) that works during **VideoMedia** even when the right settings sheet is closed. **⌘1** / **⌘2** / **⌘3** open the sheet if needed, then select the tab. **KeyboardFocusGuard** still applies when a settings control has focus.

## StopKeyboardCommand

`StopKeyboardCommand` is how the user ends the current item. **Esc** while **VideoMedia** is playing pauses only; **Esc** while paused or on **ImageMedia** returns to **EmptySurface** without clearing the playback queue. **⌘.** (Stop and Close) always returns to **EmptySurface** from **VideoMedia** or **ImageMedia**, including while playing. **EmptySurface** ignores stop keys. Queue and playback history stay intact when returning to **EmptySurface** via stop—the **Up Next** list is not wiped.

## ReservedFrameStepShortcuts

`ReservedFrameStepShortcuts` are one-frame back/forward bindings (for example comma and period) intentionally omitted from shortcuts v1 until **ActivePlaybackSession** supports frame-step on both **NativePlaybackEngine** and **DirectMpv**. Listed as “coming soon” in the keyboard shortcuts reference—not bound globally in v1.

## ShortcutCommandFunnel

`ShortcutCommandFunnel` means menu bar items and **HybridKeyboardShortcuts** invoke the same controller methods—scope checks (**VideoMediaShortcutScope**, **KeyboardFocusGuard**) and behavior live in one place, not duplicated across `NSMenuItem` actions and key handling.
