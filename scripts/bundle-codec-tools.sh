#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${ROOT_DIR}/Sources/LaughPlayer/codec-tools/bin"

mkdir -p "${TARGET_DIR}"

copy_if_exists() {
  local src="$1"
  local name="$2"
  if [[ -x "${src}" ]]; then
    local dest="${TARGET_DIR}/${name}"
    rm -f "${dest}"
    cp "${src}" "${dest}"
    chmod +x "${dest}"
    echo "[bundle-codec-tools] bundled ${name} from ${src}"
  fi
}

copy_if_exists "$(command -v ffmpeg || true)" "ffmpeg"
copy_if_exists "$(command -v mpv || true)" "mpv"

if [[ ! -x "${TARGET_DIR}/ffmpeg" ]]; then
  echo "[bundle-codec-tools] ERROR: ffmpeg was not bundled."
  echo "This project no longer auto-installs dependencies."
  echo "Place a bundled ffmpeg binary at: Sources/LaughPlayer/codec-tools/bin/ffmpeg"
  echo "Tip: run ./scripts/fetch-ffmpeg-portable.sh to fetch a standalone build."
  exit 1
fi

if ! "${TARGET_DIR}/ffmpeg" -version >/tmp/laugh_ffmpeg_check.log 2>&1; then
  echo "[bundle-codec-tools] ERROR: bundled ffmpeg is not runnable."
  echo "-------- ffmpeg check output --------"
  cat /tmp/laugh_ffmpeg_check.log
  echo "-------------------------------------"
  echo "Replace it with a standalone ffmpeg binary (not one linked to Homebrew Cellar paths)."
  exit 1
fi

if [[ ! -x "${TARGET_DIR}/mpv" ]]; then
  echo "[bundle-codec-tools] WARNING: mpv was not bundled."
  echo "Optional path: Sources/LaughPlayer/codec-tools/bin/mpv"
fi

echo "[bundle-codec-tools] output: ${TARGET_DIR}"
