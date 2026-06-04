#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

TARGET_DIR="${ROOT_DIR}/Sources/LaughPlayer/codec-tools/bin"

echo "[setup-codec-tools] LaughPlayer codec toolchain setup"
echo ""

need_ffmpeg=false
if [[ ! -x "${TARGET_DIR}/ffmpeg" ]]; then
  need_ffmpeg=true
elif ! "${TARGET_DIR}/ffmpeg" -version >/dev/null 2>&1; then
  need_ffmpeg=true
fi

if [[ "${need_ffmpeg}" == true ]]; then
  echo "[setup-codec-tools] Installing portable ffmpeg (evermeet.cx)..."
  ./scripts/fetch-ffmpeg-portable.sh
else
  echo "[setup-codec-tools] ffmpeg already OK"
fi

if ! command -v brew >/dev/null; then
  echo "[setup-codec-tools] Homebrew not found."
  echo "  Install Homebrew for extended MKV/mpv playback: https://brew.sh"
  echo "  Without mpv, the app still plays via FFmpeg remux + AVPlayer."
  ./scripts/bundle-codec-tools.sh
  exit 0
fi

echo "[setup-codec-tools] Ensuring mpv formula is installed (pulls libass, ffmpeg libs, etc.)..."
if ! brew list mpv --formula >/dev/null 2>&1; then
  brew install mpv
else
  brew reinstall mpv || brew install mpv
fi

echo "[setup-codec-tools] Bundling into Sources/LaughPlayer/codec-tools/ (keeps portable ffmpeg if already OK)..."
./scripts/bundle-codec-tools.sh

if [[ -x "${TARGET_DIR}/mpv" ]] && "${TARGET_DIR}/mpv" --no-config --version >/dev/null 2>&1; then
  echo ""
  echo "[setup-codec-tools] Done — ffmpeg and mpv are portable and runnable."
else
  echo ""
  echo "[setup-codec-tools] Done — ffmpeg OK; mpv missing or not portable."
  echo "  Playback still works (FFmpeg remux). Extended mpv path unavailable until mpv bundles cleanly."
fi
