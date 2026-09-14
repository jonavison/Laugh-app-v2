#!/usr/bin/env bash
# Fetches a portable static ffmpeg for the current Mac architecture.
# Apple Silicon must NOT ship evermeet (Intel-only) — that triggers Rosetta warnings.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${ROOT_DIR}/Sources/LaughPlayer/codec-tools/bin"
TMP_DIR="$(mktemp -d)"
ARCHIVE="${TMP_DIR}/ffmpeg.zip"
EXTRACT_DIR="${TMP_DIR}/extract"

cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

mkdir -p "${TARGET_DIR}" "${EXTRACT_DIR}"

HOST_ARCH="$(uname -m)"
case "${HOST_ARCH}" in
  arm64)
    DEFAULT_URL="https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip"
    EXPECT_ARCH="arm64"
    ;;
  x86_64)
    DEFAULT_URL="https://evermeet.cx/ffmpeg/getrelease/zip"
    EXPECT_ARCH="x86_64"
    ;;
  *)
    echo "[fetch-ffmpeg-portable] ERROR: unsupported arch ${HOST_ARCH}" >&2
    exit 1
    ;;
esac

URL="${FFMPEG_PORTABLE_URL:-${DEFAULT_URL}}"
echo "[fetch-ffmpeg-portable] arch=${HOST_ARCH} url=${URL}"
curl -L --fail --silent --show-error "${URL}" -o "${ARCHIVE}"

echo "[fetch-ffmpeg-portable] Extracting..."
unzip -q "${ARCHIVE}" -d "${EXTRACT_DIR}"

FFMPEG_SRC="$(find "${EXTRACT_DIR}" -type f -name ffmpeg | head -n 1 || true)"
if [[ -z "${FFMPEG_SRC}" || ! -f "${FFMPEG_SRC}" ]]; then
  echo "[fetch-ffmpeg-portable] ERROR: ffmpeg binary not found in archive." >&2
  find "${EXTRACT_DIR}" -maxdepth 3 -type f | head -20 >&2 || true
  exit 1
fi

ARCH_LINE="$(file "${FFMPEG_SRC}")"
if ! grep -q "${EXPECT_ARCH}" <<<"${ARCH_LINE}"; then
  echo "[fetch-ffmpeg-portable] ERROR: expected ${EXPECT_ARCH} binary, got:" >&2
  echo "  ${ARCH_LINE}" >&2
  exit 1
fi

if [[ -f "${TARGET_DIR}/ffmpeg" ]]; then
  chmod u+w "${TARGET_DIR}/ffmpeg" || true
  rm -f "${TARGET_DIR}/ffmpeg"
fi

cp "${FFMPEG_SRC}" "${TARGET_DIR}/ffmpeg"
chmod +x "${TARGET_DIR}/ffmpeg"

if "${TARGET_DIR}/ffmpeg" -version >/tmp/laugh_ffmpeg_fetch_check.log 2>&1; then
  echo "[fetch-ffmpeg-portable] Installed ${EXPECT_ARCH} ffmpeg at ${TARGET_DIR}/ffmpeg"
  file "${TARGET_DIR}/ffmpeg"
else
  echo "[fetch-ffmpeg-portable] ERROR: downloaded ffmpeg failed health check." >&2
  cat /tmp/laugh_ffmpeg_fetch_check.log >&2
  exit 1
fi
