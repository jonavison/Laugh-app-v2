Bundled codec helper binaries for direct distribution.

Expected paths:

- `codec-tools/bin/ffmpeg`
- `codec-tools/lib/libmpv.2.dylib`
- `codec-tools/bin/mpv` (optional leftover binary; playback uses libmpv)

These binaries are intentionally not committed to source control in this repository snapshot.

## Developer bundling flow

Run:

```bash
./scripts/bundle-codec-tools.sh
```

This script bundles `ffmpeg` (required) and `libmpv` (required for zero-wait MKV/WebM on direct builds) into `codec-tools/`.

This script bundles `ffmpeg` (required) and `libmpv` (required for zero-wait MKV/WebM on direct builds) into `codec-tools/`. `./scripts/bundle-codec-tools.sh` verifies ffmpeg; DirectMpv needs `codec-tools/lib/libmpv.2.dylib`.
It does **not** install anything automatically.
Provide prebuilt binaries yourself and place them here:

- `Sources/LaughPlayer/codec-tools/bin/ffmpeg` (required)
- `Sources/LaughPlayer/codec-tools/lib/libmpv.2.dylib` (required for DirectMpv)

Then build direct distribution:

```bash
./scripts/build-direct.sh
```
