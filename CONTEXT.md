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

## ImageMedia

`ImageMedia` is an active still-image item. Image-oriented controls are shown instead of video playback controls.

## ContextualSettingsTabs

`ContextualSettingsTabs` means the right settings sheet tab set depends on active media kind (for example video tabs vs image tabs).

## QueueDropZone

`QueueDropZone` is the bottom-right drop target used to enqueue videos only. It appears during drag only when something is already playing or in the queue (`currentMediaURL` or a non-empty **Up Next** list). Photos are opened via the main play area, not via queue enqueue.

## MediaLibrary

`MediaLibrary` is a docked left-side explorer for browsing disk folders and opening videos or images without the system open panel. It has a narrow sidebar for roots and a wider content area for browsing.

## LibraryRoot

`LibraryRoot` is a top-level folder pinned in the MediaLibrary sidebar (for example Movies or Videos, or a `UserLibraryFolder`). Selecting a root resets browse to that folder’s top level and clears back/forward history for the previous root.

## LibraryFolder

`LibraryFolder` is a subfolder shown in the `LibraryBrowseGrid` — a child of the current browse location, not a sidebar entry. Single-click opens the folder and shows its immediate children in the grid.

## LibraryBrowseGrid

`LibraryBrowseGrid` is the MediaLibrary content area to the right of the sidebar. It shows one directory level at a time: subfolders and media files that are direct children of the current browse location. Single-click opens a subfolder or selects a media tile; media tiles show a centered play affordance over the file preview. Back and forward controls sit at the top-left; the current path is shown as a breadcrumb at the bottom. Item order follows `LibraryBrowseSort`, Finder-style (folders grouped before files when applicable).

## LibraryBrowseSort

`LibraryBrowseSort` is the ordering policy for items in the `LibraryBrowseGrid`. The user can sort Finder-style by name, date modified, date added, size, or kind, with ascending or descending order. Default is name ascending with folders grouped before files.

## LibraryBrowseNavigation

`LibraryBrowseNavigation` is back/forward history within a selected `LibraryRoot`, plus a bottom breadcrumb showing the current folder path. Breadcrumb segments are clickable to jump to an ancestor folder.

## LibraryMediaTile

`LibraryMediaTile` is a grid cell for a video or image file in the `LibraryBrowseGrid`. It shows a real thumbnail preview (video poster frame or image preview) with a centered play button. Single-click triggers `LibraryMediaSelection` and opens the item in the center player.

## LibraryMediaSelection

`LibraryMediaSelection` is a single-click on a `LibraryMediaTile` in the `LibraryBrowseGrid`; the item opens in the center playback container as `VideoMedia` or `ImageMedia`, not inside the library panel or the settings column. After selection, the `MediaLibraryPanel` auto-hides so playback is unobstructed.

## MediaLibraryPanel

`MediaLibraryPanel` is the docked left region that hosts the MediaLibrary UI (sidebar + browse grid), toggled via the Library control. It is not a slide-over sheet. Fixed width ~360pt (sidebar ~88pt + grid ~272pt). The sidebar lists `RecentlyViewed` and `LibraryRoot` folders only.

## RecentlyViewed

`RecentlyViewed` is a sidebar entry pinned above `LibraryRoot` folders. Selecting it shows recently opened media as `LibraryMediaTile` items in the `LibraryBrowseGrid` (no subfolders). Single-click plays and auto-hides the panel.

## UserLibraryFolder

`UserLibraryFolder` is a `LibraryRoot` the user added with “Add folder…” and persisted via a security-scoped bookmark. User roots can be removed; built-in roots (Movies, Videos) cannot.

## SystemDecodeStack

`SystemDecodeStack` is macOS-provided demux and decode exposed through AVFoundation (including VideoToolbox hardware decode when the OS accepts the file). In conversation, “native” means this stack—not a separate VideoToolbox-only engine.

## NativePlaybackEngine

`NativePlaybackEngine` is playback through the **SystemDecodeStack** (AVPlayer / AVFoundation).

## CompatibilityRemux

`CompatibilityRemux` is an **AlternateDecoder** step that produces a temporary MP4 the **SystemDecodeStack** can open, preferring stream copy without re-encoding video. Embedded **text** subtitles (for example SRT in MKV) are muxed as `mov_text` so **NativePlaybackEngine** can expose them via `.legible`; bitmap/image subs and sidecar-only files still require **DirectMpv** or **ExtendedPlaybackForSubtitles**.

## AlternateDecoder

`AlternateDecoder` is a secondary path for profiles **SystemDecodeStack** cannot open directly. On direct builds the default is **DirectMpv** (bundled subprocess mpv) for non-native containers and codecs when mpv is runnable; **CompatibilityRemux** via bundled FFmpeg remains the fallback when mpv is missing or fails.

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

`CompanionSubtitleFile` is a sidecar subtitle file on disk associated with the current **VideoMedia** by **CompanionSubtitleDiscovery** rules—not chosen through the load dialog. On **DirectMpv**, every discovered file is auto-attached and appears in **SubtitleTrackPicker** (language inferred from filename when present); **PrimarySubtitleTrack** stays off until the user enables it. On **NativePlaybackEngine**, companions are listed but not playable until the user chooses **ExtendedPlaybackForSubtitles**. Distinct from **EmbeddedSubtitleTrack** and from user-picked **ExternalSubtitleFile**.

## CompanionSubtitleDiscovery

`CompanionSubtitleDiscovery` is how LaughPlayer finds **CompanionSubtitleFile**s for the open **VideoMedia**: case-insensitive basename match; extensions `.srt`, `.vtt`, `.ass`, `.ssa`; optional language tag (two–three letters or common names such as English) and optional `forced` before the extension. Search locations are the media folder, a sibling flat `Subs/` or `subtitles/` folder, and `Subs/<basename>/` or `subtitles/<basename>/` (Plex-style per-title folder)—not a recursive library-wide scan. All matches are attached; the user chooses among them in **SubtitleTrackPicker**.

## ExtendedPlaybackForSubtitles

`ExtendedPlaybackForSubtitles` is reloading the current **VideoMedia** on **DirectMpv** at the same playhead so **CompanionSubtitleFile**s or full **SubtitlesSettings** can apply, without changing the user’s default **PlaybackRoute** for files that play natively. Offered from **SubtitlesSettings** when sidecars exist but the active session is **NativePlaybackEngine**, or when the user wants to retry **DirectMpv** after **CompatibilityRemux** fallback. Play/pause state and playhead time are preserved.

## SubtitlesSettings

`SubtitlesSettings` is the right-settings **Subtitles** tab: track pickers with on/off toggles, **CompanionSubtitleFile** discovery, **ExtendedPlaybackForSubtitles**, manual **ExternalSubtitleFile** load, delay (−5s to +5s), vertical position, scale, and **SubtitleAppearance** (font size/color, border width/color, background on/off + color). **PrimarySubtitleTrack** and **SecondarySubtitleTrack** default off until the user enables them. Full subtitle controls apply on **DirectMpv**; **NativePlaybackEngine** supports embedded **SubtitleTrackPicker** only—companions and extended controls show an unavailable note or **ExtendedPlaybackForSubtitles** when sidecars exist.

## SubtitleTrackPicker

`SubtitleTrackPicker` is the pop-up that chooses which embedded, companion, or loaded subtitle stream is primary or secondary. Distinct from **AudioTrackPicker**, **CompanionSubtitleFile** (auto-discovered), and **ExternalSubtitleFile** (user-picked). Track labels include index, language, and title when known.

## SubtitleTrackSwitch

`SubtitleTrackSwitch` is enabling or changing primary/secondary subtitle streams via the on/off toggles and pickers. Playhead and play/pause state must be preserved. On **DirectMpv**, uses `sid` / `secondary-sid`; on **NativePlaybackEngine**, primary uses `AVMediaSelection` for legible tracks.

## SecondarySubtitleTrack

`SecondarySubtitleTrack` is a second simultaneous subtitle stream (mpv `secondary-sid`). Requires **DirectMpv** and a file or external load that exposes multiple subtitle tracks.

## ExternalSubtitleFile

`ExternalSubtitleFile` is a subtitle file the user explicitly chose via the load dialog (any path), added to the current **DirectMpv** session. Distinct from **CompanionSubtitleFile**, which is found automatically beside the media. After load, the track appears in **SubtitleTrackPicker**.

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
