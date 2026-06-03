Bundled codec helper binaries for direct distribution.

Expected paths:

- `codec-tools/bin/ffmpeg`
- `codec-tools/bin/mpv`

These binaries are intentionally not committed to source control in this repository snapshot.

## Developer bundling flow

Run:

```bash
./scripts/bundle-codec-tools.sh
```

This script bundles `ffmpeg` (required) and `mpv` (required for zero-wait MKV/WebM on direct builds) into `codec-tools/bin`.

Both binaries must be **portable** (not linked to Homebrew Cellar paths). `./scripts/bundle-codec-tools.sh` verifies ffmpeg; if mpv fails `mpv --version`, direct builds fall back to FFmpeg remux.
It does **not** install anything automatically.
Provide prebuilt binaries yourself and place them here:

- `Sources/LaughPlayer/codec-tools/bin/ffmpeg` (required)
- `Sources/LaughPlayer/codec-tools/bin/mpv` (optional)

Then build direct distribution:

```bash
./scripts/build-direct.sh
```
