# LaughPlayer

Native macOS video player focused on:
- correct aspect-ratio playback
- aspect-ratio-locked window resizing (toggleable)
- drag-and-drop play/queue behavior
- explicit codec compatibility messaging

## Distribution Modes

- **Direct build**: supports bundled codec helper tools in `Sources/LaughPlayer/codec-tools/bin` (`ffmpeg`, `mpv`).
- **App Store build**: native AVFoundation decoder path only.

Build helpers:

- `./scripts/build-direct.sh` (auto-bundles codec tools first)
- `./scripts/build-appstore.sh`
- `./scripts/bundle-codec-tools.sh` (bundles `ffmpeg` required, `mpv` optional)
- `./scripts/create-app-bundle.sh` (creates `dist/LaughPlayer.app`; embeds Sparkle for shipped updates)
- `./scripts/create-pkg.sh` or `pnpm run pkg` (creates `dist/LaughPlayer-Installer.pkg`)
- `./scripts/create-dmg.sh` (drag-to-Applications `dist/LaughPlayer-<version>.dmg` — clearest install UX)
- `./scripts/build-macos-release.sh` (Developer ID sign + notarize + DMG; needs `Packaging/release-env.local`)


Note: codec bundling does not auto-install dependencies. Provide prebuilt binaries in `Sources/LaughPlayer/codec-tools/bin/`.

## Menus & updates

- **LaughPlayer → About LaughPlayer** — system About panel (version + build + icon).
- **Help → Check for Updates…** — Sparkle 2 (shipped `.app` only; feed `https://avison-soft.com/laugh/appcast.xml`).
- Dev app (`DevLaughPlayer.app`) has no update feed on purpose.

## Codec strategy

- **Primary:** AVFoundation (**SystemDecodeStack** — includes VideoToolbox when macOS accepts the file).
- **Direct builds:** **CompatibilityRemux** via bundled FFmpeg on failure; see `docs/adr/0003-system-decode-compatibility-remux-not-videotoolbox.md`.
- **Support matrix:** `SUPPORT.md`; Phase 2 verification checklists under `docs/verification/`.

## Documentation Rule

This project follows a strict documentation rule:

- Every functional/code change must update `CHANGELOG.md`.
- Any media compatibility change must also update `SUPPORT.md`.

If code and docs conflict, update docs in the same change.
