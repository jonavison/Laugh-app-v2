#!/usr/bin/env bash
# Shared Sparkle paths and helpers for LaughPlayer. Source from release scripts.

sparkle_common_init() {
  if [[ -n "${SPARKLE_COMMON_INIT:-}" ]]; then
    return 0
  fi
  SPARKLE_COMMON_INIT=1

  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  SPARKLE_ARTIFACTS="$ROOT/.build/artifacts/sparkle/Sparkle"
  SPARKLE_BIN="$SPARKLE_ARTIFACTS/bin"
  SPARKLE_XCFRAMEWORK="$SPARKLE_ARTIFACTS/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
  SPARKLE_PUBLIC_KEY_FILE="$ROOT/Packaging/sparkle/public-ed-key.txt"
  SPARKLE_FEED_URL="${LAUGH_SPARKLE_FEED_URL:-https://avison-soft.com/laugh/appcast.xml}"
  SPARKLE_DOWNLOAD_URL_PREFIX="${LAUGH_SPARKLE_DOWNLOAD_URL_PREFIX:-https://avison-soft.com/laugh/}"
  SPARKLE_RELEASES_DIR="${LAUGH_SPARKLE_RELEASES_DIR:-$ROOT/.build/sparkle-releases}"
  SPARKLE_PRIVATE_KEY_FILE="${LAUGH_SPARKLE_PRIVATE_KEY_FILE:-}"

  if [[ -f "$ROOT/Packaging/release-env.local" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT/Packaging/release-env.local"
    SPARKLE_FEED_URL="${LAUGH_SPARKLE_FEED_URL:-$SPARKLE_FEED_URL}"
    SPARKLE_DOWNLOAD_URL_PREFIX="${LAUGH_SPARKLE_DOWNLOAD_URL_PREFIX:-$SPARKLE_DOWNLOAD_URL_PREFIX}"
    SPARKLE_PRIVATE_KEY_FILE="${LAUGH_SPARKLE_PRIVATE_KEY_FILE:-$SPARKLE_PRIVATE_KEY_FILE}"
  fi
}

ensure_sparkle_artifacts() {
  sparkle_common_init
  if [[ -d "$SPARKLE_BIN" && -d "$SPARKLE_XCFRAMEWORK" ]]; then
    return 0
  fi
  echo "==> Fetch Sparkle artifacts (swift build --product LaughPlayer)"
  (cd "$ROOT" && swift build -c release --product LaughPlayer >/dev/null)
  if [[ ! -d "$SPARKLE_BIN" || ! -d "$SPARKLE_XCFRAMEWORK" ]]; then
    echo "Sparkle artifacts missing under .build/artifacts/sparkle" >&2
    exit 1
  fi
}

read_sparkle_public_key() {
  sparkle_common_init
  if [[ ! -f "$SPARKLE_PUBLIC_KEY_FILE" ]]; then
    echo ""
    return 0
  fi
  tr -d '[:space:]' <"$SPARKLE_PUBLIC_KEY_FILE"
}

require_sparkle_public_key() {
  local key
  key="$(read_sparkle_public_key)"
  if [[ -z "$key" ]]; then
    echo "Missing Sparkle public key: $SPARKLE_PUBLIC_KEY_FILE" >&2
    echo "Run ./scripts/sparkle-generate-keys.sh once, then commit public-ed-key.txt." >&2
    exit 1
  fi
  printf '%s' "$key"
}

stage_embed_sparkle_framework() {
  local app="$1"
  sparkle_common_init
  ensure_sparkle_artifacts

  if [[ ! -d "$SPARKLE_XCFRAMEWORK" ]]; then
    echo "Missing Sparkle.framework: $SPARKLE_XCFRAMEWORK" >&2
    exit 1
  fi

  local frameworks_dir="$app/Contents/Frameworks"
  local main_bin="$app/Contents/MacOS/LaughPlayer"
  mkdir -p "$frameworks_dir"
  rsync -a --delete "$SPARKLE_XCFRAMEWORK" "$frameworks_dir/"

  # Drop foreign CPU slices so Gatekeeper doesn't warn about Intel/Rosetta
  # support ending (Sparkle ships as macos-arm64_x86_64 by default).
  thin_sparkle_framework_to_host "$frameworks_dir/Sparkle.framework"

  install_name_tool -add_rpath @executable_path/../Frameworks "$main_bin" 2>/dev/null || true
  install_name_tool -change \
    @rpath/Sparkle.framework/Versions/B/Sparkle \
    @executable_path/../Frameworks/Sparkle.framework/Versions/B/Sparkle \
    "$main_bin" 2>/dev/null || true

  echo "[create-app-bundle] Embedded Sparkle.framework"
}

thin_sparkle_framework_to_host() {
  local framework="$1"
  local host_arch
  host_arch="$(uname -m)"
  [[ -d "${framework}" ]] || return 0

  local thinned=0
  while IFS= read -r -d '' bin; do
    local info
    info="$(file "${bin}" 2>/dev/null || true)"
    if grep -q 'universal binary' <<<"${info}" && grep -q "${host_arch}" <<<"${info}"; then
      local tmp="${bin}.thin.$$"
      if lipo "${bin}" -thin "${host_arch}" -output "${tmp}" 2>/dev/null; then
        mv "${tmp}" "${bin}"
        thinned=$((thinned + 1))
      else
        rm -f "${tmp}" 2>/dev/null || true
      fi
    fi
  done < <(find "${framework}" -type f \( -perm -111 -o -name '*.dylib' \) -print0)

  if (( thinned > 0 )); then
    echo "[create-app-bundle] Thinned Sparkle to ${host_arch} (${thinned} binaries)"
  fi
}

sparkle_info_plist_snippet() {
  sparkle_common_init
  local public_key
  public_key="$(read_sparkle_public_key)"
  if [[ -z "$public_key" ]]; then
    echo ""
    return 0
  fi
  cat <<PLIST
  <key>SUFeedURL</key>
  <string>${SPARKLE_FEED_URL}</string>
  <key>SUPublicEDKey</key>
  <string>${public_key}</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
PLIST
}

sign_sparkle_update() {
  local artifact="$1"
  sparkle_common_init
  ensure_sparkle_artifacts
  if [[ -n "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
    "$SPARKLE_BIN/sign_update" "$artifact" -f "$SPARKLE_PRIVATE_KEY_FILE"
  else
    "$SPARKLE_BIN/sign_update" "$artifact"
  fi
}
