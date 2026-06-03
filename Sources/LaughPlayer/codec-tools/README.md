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

This script bundles `ffmpeg` (required) and `mpv` (optional) into `codec-tools/bin`.
It does **not** install anything automatically.
Provide prebuilt binaries yourself and place them here:

- `Sources/LaughPlayer/codec-tools/bin/ffmpeg` (required)
- `Sources/LaughPlayer/codec-tools/bin/mpv` (optional)

Then build direct distribution:

```bash
./scripts/build-direct.sh
```
