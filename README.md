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
- `./scripts/create-app-bundle.sh` (creates `dist/LaughPlayer.app`)
- `./scripts/create-pkg.sh` or `pnpm run pkg` (creates `dist/LaughPlayer-Installer.pkg`)

Note: codec bundling does not auto-install dependencies. Provide prebuilt binaries in `Sources/LaughPlayer/codec-tools/bin/`.

## Documentation Rule

This project follows a strict documentation rule:

- Every functional/code change must update `CHANGELOG.md`.
- Any media compatibility change must also update `SUPPORT.md`.

If code and docs conflict, update docs in the same change.
