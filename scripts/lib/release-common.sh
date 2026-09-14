# Shared release packaging helpers for Laugh. Source from other scripts; do not execute directly.

release_common_init() {
  if [[ -n "${RELEASE_COMMON_INIT:-}" ]]; then
    return 0
  fi
  RELEASE_COMMON_INIT=1

  if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
  fi
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  cd "$ROOT"

  export COPYFILE_DISABLE=1

  RELEASE_FILE="$ROOT/Packaging/RELEASE_VERSION"
  ENTITLEMENTS="$ROOT/Packaging/Laugh.entitlements"
  STAGE_OUT="$ROOT/.build/pkg-stage"
  STAGED_APP="$STAGE_OUT/LaughPlayer.app"
  BUNDLE_ID="${LAUGH_BUNDLE_ID:-com.laughplayer.app}"

  if [[ -f "$ROOT/Packaging/release-env.local" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT/Packaging/release-env.local"
    BUNDLE_ID="${LAUGH_BUNDLE_ID:-$BUNDLE_ID}"
  fi

  if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "Missing entitlements: $ENTITLEMENTS" >&2
    exit 1
  fi
}

read_release_version() {
  release_common_init
  if [[ ! -f "$RELEASE_FILE" ]]; then
    echo ""
    return 0
  fi
  local line
  IFS= read -r line <"$RELEASE_FILE" || true
  line="${line//$'\r'/}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  printf '%s' "$line"
}

resolve_codesign_identity() {
  release_common_init
  if [[ -n "${LAUGH_CODESIGN_IDENTITY:-}" ]]; then
    printf '%s' "$LAUGH_CODESIGN_IDENTITY"
    return 0
  fi
  local picked
  picked="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^[[:space:]]*[0-9]*) [A-F0-9]* "\(Developer ID Application:.*\)"$/\1/p' \
    | head -n 1)"
  if [[ -z "$picked" ]]; then
    picked="$(security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/^[[:space:]]*[0-9]*) \(Developer ID Application:.*\)$/\1/p' \
      | head -n 1)"
  fi
  if [[ -z "$picked" ]]; then
    echo "No Developer ID Application identity found. Set LAUGH_CODESIGN_IDENTITY or install the cert in Keychain." >&2
    exit 1
  fi
  printf '%s' "$picked"
}

require_notary_profile() {
  release_common_init
  if [[ -z "${LAUGH_NOTARY_PROFILE:-}" ]]; then
    echo "Set LAUGH_NOTARY_PROFILE (notarytool keychain profile) or pass --skip-notarize." >&2
    echo "Example: xcrun notarytool store-credentials laugh-notary --apple-id YOU --team-id PJPQ2PYK8U --password APP-PASSWORD" >&2
    echo "Or reuse Smile's profile: export LAUGH_NOTARY_PROFILE=smile-notary" >&2
    exit 1
  fi
}

verify_signed_app() {
  local app="$1"
  codesign --verify --deep --strict --verbose=2 "$app"
  echo "==> spctl assess"
  spctl -a -t exec -vv "$app" || true
}

# Apple's timestamp.apple.com is intermittently unreachable; retry codesign when it flakes.
codesign_with_timestamp_retry() {
  local attempts="${LAUGH_CODESIGN_TIMESTAMP_RETRIES:-8}"
  local delay=3
  local n=1
  local err
  while ((n <= attempts)); do
    err="$(mktemp -t laugh-codesign)"
    if codesign "$@" 2>"$err"; then
      cat "$err" >&2 || true
      rm -f "$err"
      return 0
    fi
    cat "$err" >&2 || true
    if grep -q "A timestamp was expected but was not found" "$err"; then
      rm -f "$err"
      echo "    codesign timestamp flake (attempt $n/$attempts); retrying in ${delay}s…" >&2
      sleep "$delay"
      delay=$((delay < 20 ? delay + 2 : delay))
      n=$((n + 1))
      continue
    fi
    rm -f "$err"
    return 1
  done
  echo "codesign failed after $attempts timestamp retries." >&2
  return 1
}
