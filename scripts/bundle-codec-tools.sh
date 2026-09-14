#!/usr/bin/env bash
# Bundles portable ffmpeg (+ optional relocated mpv) into Sources/LaughPlayer/codec-tools/.
#
# Critical: never ship Homebrew-linked binaries. They only run on the build machine
# (MKV remux / DirectMpv break for other users with "Bundled ffmpeg was not found").
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/codec-portability.sh"

TARGET_DIR="${ROOT_DIR}/Sources/LaughPlayer/codec-tools/bin"
LIB_DIR="${ROOT_DIR}/Sources/LaughPlayer/codec-tools/lib"

mkdir -p "${TARGET_DIR}" "${LIB_DIR}"

ensure_portable_ffmpeg() {
  local dest="${TARGET_DIR}/ffmpeg"
  local host_arch
  host_arch="$(uname -m)"
  if [[ -x "${dest}" ]] \
    && ! codec_links_to_homebrew "${dest}" \
    && [[ "$(codec_macho_arch "${dest}")" == "${host_arch}" ]] \
    && "${dest}" -version >/dev/null 2>&1; then
    echo "[bundle-codec-tools] keeping portable ${host_arch} ffmpeg"
    return 0
  fi

  if [[ -x "${dest}" ]] && [[ "$(codec_macho_arch "${dest}")" != "${host_arch}" ]]; then
    echo "[bundle-codec-tools] replacing $(codec_macho_arch "${dest}") ffmpeg with ${host_arch} build..."
  else
    echo "[bundle-codec-tools] fetching portable ${host_arch} ffmpeg..."
  fi
  "${ROOT_DIR}/scripts/fetch-ffmpeg-portable.sh"

  if codec_links_to_homebrew "${dest}"; then
    echo "[bundle-codec-tools] ERROR: ffmpeg still links to Homebrew after portable fetch." >&2
    exit 1
  fi
  codec_assert_native_arch "${dest}" "ffmpeg"
}

bundle_relocated_mpv() {
  local src
  src="$(command -v mpv || true)"
  if [[ -z "${src}" || ! -x "${src}" ]]; then
    echo "[bundle-codec-tools] WARNING: mpv not on PATH — DirectMpv path unavailable."
    return 0
  fi

  local dest="${TARGET_DIR}/mpv"
  rm -f "${dest}"
  cp "${src}" "${dest}"
  chmod +x "${dest}"

  echo "[bundle-codec-tools] relocating mpv + dylibs into codec-tools/lib..."
  codec_relocate_macho "${dest}" "${LIB_DIR}"

  # libmpv for in-process embedding (same dependency tree).
  local libmpv_src=""
  if [[ -f /opt/homebrew/lib/libmpv.2.dylib ]]; then
    libmpv_src="/opt/homebrew/lib/libmpv.2.dylib"
  elif [[ -f /usr/local/lib/libmpv.2.dylib ]]; then
    libmpv_src="/usr/local/lib/libmpv.2.dylib"
  fi
  if [[ -n "${libmpv_src}" ]]; then
    cp "${libmpv_src}" "${LIB_DIR}/libmpv.2.dylib"
    chmod u+w "${LIB_DIR}/libmpv.2.dylib" 2>/dev/null || true
    codec_relocate_macho "${LIB_DIR}/libmpv.2.dylib" "${LIB_DIR}"
    echo "[bundle-codec-tools] bundled + relocated libmpv.2.dylib"
  fi

  codec_adhoc_sign_tree "${ROOT_DIR}/Sources/LaughPlayer/codec-tools"

  if ! "${dest}" --no-config --version >/tmp/laugh_mpv_check.log 2>&1; then
    echo "[bundle-codec-tools] WARNING: relocated mpv failed health check — removing it."
    cat /tmp/laugh_mpv_check.log >&2 || true
    rm -f "${dest}"
    return 0
  fi

  if codec_links_to_homebrew "${dest}"; then
    echo "[bundle-codec-tools] WARNING: mpv still has Homebrew links — removing it."
    otool -L "${dest}" | grep -E '/opt/homebrew|/usr/local/Cellar|/usr/local/opt/' >&2 || true
    rm -f "${dest}"
    return 0
  fi

  echo "[bundle-codec-tools] bundled portable mpv from ${src}"
}

ensure_portable_ffmpeg
bundle_relocated_mpv

codec_assert_portable "${TARGET_DIR}/ffmpeg" "ffmpeg"
codec_assert_native_arch "${TARGET_DIR}/ffmpeg" "ffmpeg"
if ! "${TARGET_DIR}/ffmpeg" -version >/tmp/laugh_ffmpeg_check.log 2>&1; then
  echo "[bundle-codec-tools] ERROR: bundled ffmpeg is not runnable." >&2
  cat /tmp/laugh_ffmpeg_check.log >&2
  exit 1
fi

# Refuse to ship any leftover Homebrew-linked helper in bin/.
for helper in "${TARGET_DIR}"/*; do
  [[ -f "${helper}" && -x "${helper}" ]] || continue
  codec_assert_portable "${helper}" "$(basename "${helper}")"
  codec_assert_native_arch "${helper}" "$(basename "${helper}")"
done

echo "[bundle-codec-tools] output: ${TARGET_DIR}"
otool -L "${TARGET_DIR}/ffmpeg" | head -8
if [[ -x "${TARGET_DIR}/mpv" ]]; then
  echo "[bundle-codec-tools] mpv deps (should not include Homebrew):"
  otool -L "${TARGET_DIR}/mpv" | head -12
fi
