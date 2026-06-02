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

`QueueDropZone` is the bottom-right drop target used to enqueue videos only. Photos are opened via the main play area, not via queue enqueue.

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

## NativePlaybackEngine

`NativePlaybackEngine` is playback through macOS AVFoundation using the system’s built-in decoders and renderers.

## AlternateDecoder

`AlternateDecoder` is an optional secondary decode path (planned: FFmpeg) used only when native playback fails or cannot render video.

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
