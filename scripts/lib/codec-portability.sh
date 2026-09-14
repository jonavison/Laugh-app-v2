#!/usr/bin/env bash
# Helpers for shipping codec binaries that run on machines without Homebrew.
set -euo pipefail

codec_links_to_homebrew() {
  local path="$1"
  [[ -e "${path}" ]] || return 1
  otool -L "${path}" 2>/dev/null | grep -E '/opt/homebrew|/usr/local/Cellar|/usr/local/opt/' >/dev/null
}

codec_is_system_dylib() {
  local dep="$1"
  [[ "${dep}" == /System/* ]] \
    || [[ "${dep}" == /usr/lib/* ]] \
    || [[ "${dep}" == /Library/Apple/* ]] \
    || [[ "${dep}" == /usr/lib/swift/* ]]
}

# Collect absolute LC_LOAD_DYLIB paths that are not system libraries.
codec_external_deps() {
  local path="$1"
  otool -L "${path}" 2>/dev/null \
    | awk 'NR>1 {print $1}' \
    | while IFS= read -r dep; do
        [[ -z "${dep}" ]] && continue
        [[ "${dep}" == @* ]] && continue
        if codec_is_system_dylib "${dep}"; then
          continue
        fi
        printf '%s\n' "${dep}"
      done
}

codec_assert_portable() {
  local path="$1"
  local label="${2:-$(basename "${path}")}"
  if codec_links_to_homebrew "${path}"; then
    echo "[codec-portability] ERROR: ${label} still links to Homebrew:" >&2
    otool -L "${path}" | grep -E '/opt/homebrew|/usr/local/Cellar|/usr/local/opt/' >&2 || true
    return 1
  fi
}

codec_macho_arch() {
  local path="$1"
  if file "${path}" | grep -q 'arm64'; then
    printf 'arm64'
  elif file "${path}" | grep -q 'x86_64'; then
    printf 'x86_64'
  else
    printf 'unknown'
  fi
}

# Refuse Intel ffmpeg/mpv on Apple Silicon builds (Rosetta sunset warning).
codec_assert_native_arch() {
  local path="$1"
  local label="${2:-$(basename "${path}")}"
  local host expect got
  host="$(uname -m)"
  case "${host}" in
    arm64) expect="arm64" ;;
    x86_64) expect="x86_64" ;;
    *) expect="${host}" ;;
  esac
  got="$(codec_macho_arch "${path}")"
  if [[ "${got}" != "${expect}" ]]; then
    echo "[codec-portability] ERROR: ${label} is ${got}, host is ${expect}." >&2
    echo "  Intel helpers inside an Apple Silicon app trigger macOS Rosetta warnings." >&2
    echo "  Re-run: ./scripts/fetch-ffmpeg-portable.sh && ./scripts/bundle-codec-tools.sh" >&2
    return 1
  fi
}

# Copy a Mach-O and rewrite non-system dylib deps to @loader_path-relative paths
# under lib_dir. Recurses through the dependency closure.
codec_relocate_macho() {
  local binary="$1"
  local lib_dir="$2"
  local queue=("${binary}")
  local seen=()

  mkdir -p "${lib_dir}"

  is_seen() {
    local needle="$1"
    local s
    for s in "${seen[@]+"${seen[@]}"}"; do
      [[ "${s}" == "${needle}" ]] && return 0
    done
    return 1
  }

  while ((${#queue[@]} > 0)); do
    local current="${queue[0]}"
    queue=("${queue[@]:1}")
    [[ -e "${current}" ]] || continue
    if is_seen "${current}"; then
      continue
    fi
    seen+=("${current}")

    chmod u+w "${current}" 2>/dev/null || true

    local dep
    while IFS= read -r dep; do
      [[ -z "${dep}" ]] && continue
      local base
      base="$(basename "${dep}")"
      local dest="${lib_dir}/${base}"

      if [[ ! -f "${dest}" ]]; then
        if [[ -f "${dep}" ]]; then
          cp "${dep}" "${dest}"
          chmod u+w "${dest}" 2>/dev/null || true
        else
          echo "[codec-portability] WARNING: missing dependency ${dep}" >&2
          continue
        fi
      fi

      # Point this Mach-O at the bundled copy.
      if [[ "${current}" == "${lib_dir}"/* ]]; then
        install_name_tool -change "${dep}" "@loader_path/${base}" "${current}" 2>/dev/null || true
      else
        install_name_tool -change "${dep}" "@loader_path/../lib/${base}" "${current}" 2>/dev/null || true
      fi

      queue+=("${dest}")
    done < <(codec_external_deps "${current}")

    if [[ "${current}" == "${lib_dir}"/* ]]; then
      install_name_tool -id "@loader_path/$(basename "${current}")" "${current}" 2>/dev/null || true
    fi
  done

  # Second pass: rewrite deps among copied dylibs that still use absolute paths.
  local lib
  for lib in "${lib_dir}"/*.dylib; do
    [[ -f "${lib}" ]] || continue
    chmod u+w "${lib}" 2>/dev/null || true
    install_name_tool -id "@loader_path/$(basename "${lib}")" "${lib}" 2>/dev/null || true
    while IFS= read -r dep; do
      [[ -z "${dep}" ]] && continue
      local base
      base="$(basename "${dep}")"
      if [[ -f "${lib_dir}/${base}" ]]; then
        install_name_tool -change "${dep}" "@loader_path/${base}" "${lib}" 2>/dev/null || true
      fi
    done < <(codec_external_deps "${lib}")
  done
}

codec_adhoc_sign_tree() {
  local root="$1"
  if ! command -v codesign >/dev/null 2>&1; then
    return 0
  fi
  # Sign dylibs first, then binaries.
  local f
  while IFS= read -r f; do
    codesign --force --sign - "${f}" >/dev/null 2>&1 || true
  done < <(find "${root}" -type f \( -name '*.dylib' -o -perm -111 \) 2>/dev/null)
}
