#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${ROOT_DIR}/Sources/LaughPlayer/codec-tools/bin"
TMP_DIR="$(mktemp -d)"
ARCHIVE="${TMP_DIR}/ffmpeg.zip"
EXTRACT_DIR="${TMP_DIR}/extract"

mkdir -p "${TARGET_DIR}" "${EXTRACT_DIR}"

URL="${FFMPEG_PORTABLE_URL:-https://evermeet.cx/ffmpeg/getrelease/zip}"
echo "[fetch-ffmpeg-portable] Downloading portable ffmpeg from: ${URL}"
curl -L --fail --silent --show-error "${URL}" -o "${ARCHIVE}"

echo "[fetch-ffmpeg-portable] Extracting..."
unzip -q "${ARCHIVE}" -d "${EXTRACT_DIR}"

if [[ ! -f "${EXTRACT_DIR}/ffmpeg" ]]; then
  echo "[fetch-ffmpeg-portable] ERROR: ffmpeg binary not found in archive."
  exit 1
fi

if [[ -f "${TARGET_DIR}/ffmpeg" ]]; then
  chmod u+w "${TARGET_DIR}/ffmpeg" || true
  rm -f "${TARGET_DIR}/ffmpeg"
fi

cp "${EXTRACT_DIR}/ffmpeg" "${TARGET_DIR}/ffmpeg"
chmod +x "${TARGET_DIR}/ffmpeg"

if "${TARGET_DIR}/ffmpeg" -version >/tmp/laugh_ffmpeg_fetch_check.log 2>&1; then
  echo "[fetch-ffmpeg-portable] Installed working portable ffmpeg at ${TARGET_DIR}/ffmpeg"
else
  echo "[fetch-ffmpeg-portable] ERROR: downloaded ffmpeg failed health check."
  cat /tmp/laugh_ffmpeg_fetch_check.log
  exit 1
fi
