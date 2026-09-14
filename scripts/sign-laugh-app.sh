#!/usr/bin/env bash
# Developer ID sign a staged LaughPlayer.app (nested code → codecs → Sparkle → app).
#
# Usage:
#   ./scripts/sign-laugh-app.sh [path/to/LaughPlayer.app]
#
# Environment (optional — see Packaging/release-env.example):
#   LAUGH_CODESIGN_IDENTITY   Developer ID Application identity name
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/release-common.sh"

release_common_init

APP="${1:-$STAGED_APP}"
if [[ ! -d "$APP" ]]; then
  echo "App bundle not found: $APP" >&2
  echo "Run OUT_DIR=.build/pkg-stage ./scripts/create-app-bundle.sh first, or pass the .app path." >&2
  exit 1
fi

IDENTITY="$(resolve_codesign_identity)"
echo "==> Signing with: $IDENTITY"
echo "==> App: $APP"

sign_nested() {
  local target="$1"
  codesign_with_timestamp_retry --force --options runtime --timestamp --sign "$IDENTITY" "$target"
}

sign_framework_deep() {
  local root="$1"
  while IFS= read -r -d '' bin; do
    echo "      code: ${bin#"$APP"/}"
    codesign_with_timestamp_retry --force --options runtime --timestamp --sign "$IDENTITY" "$bin"
  done < <(find "$root" -type f \( -perm -111 -o -name '*.dylib' \) -print0 | sort -rz)
  while IFS= read -r -d '' bundle; do
    echo "      bundle: ${bundle#"$APP"/}"
    codesign_with_timestamp_retry --force --options runtime --timestamp --sign "$IDENTITY" "$bundle"
  done < <(find "$root" \( -type d -name '*.app' -o -type d -name '*.xpc' \) -print0 | sort -rz)
  echo "      root: ${root#"$APP"/}"
  codesign_with_timestamp_retry --force --options runtime --timestamp --sign "$IDENTITY" "$root"
}

sign_code() {
  local target="$1"
  codesign_with_timestamp_retry --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    "$target"
}

bundle_has_signed_code() {
  local bundle="$1"
  find "$bundle" -type f \( -perm -111 -o -name '*.dylib' \) -print -quit | grep -q .
}

# Codec helpers live under Resources and inside the SPM resource bundle (app root).
echo "    sign codec-tools binaries/dylibs"
while IFS= read -r -d '' item; do
  echo "      ${item#"$APP"/}"
  sign_nested "$item"
done < <(find "$APP" \( -path '*/codec-tools/bin/*' -o -path '*/codec-tools/lib/*' \) \
  -type f \( -perm -111 -o -name '*.dylib' \) -print0 | sort -rz)

# Bottom-up: Sparkle.framework needs every nested Mach-O signed for notarization.
while IFS= read -r -d '' fw; do
  echo "    sign framework (deep): ${fw#"$APP"/}"
  sign_framework_deep "$fw"
done < <(find "$APP" -name '*.framework' -print0)

# Other nested bundles/dylibs with code (non-framework), including app-root SPM bundle.
while IFS= read -r -d '' item; do
  if [[ "$item" == *.framework ]] || [[ "$item" == *.framework/* ]]; then
    continue
  fi
  if [[ "$item" == */codec-tools/* ]]; then
    continue
  fi
  if [[ "$item" == *.bundle ]]; then
    # SPM resource bundles are flat folders (no Info.plist) — only their Mach-Os
    # are signed (via codec-tools walk). codesign rejects the wrapper itself.
    if [[ ! -f "$item/Contents/Info.plist" && ! -f "$item/Info.plist" ]]; then
      echo "    skip flat resource bundle: ${item#"$APP"/}"
      continue
    fi
    if ! bundle_has_signed_code "$item"; then
      echo "    skip resource bundle: ${item#"$APP"/}"
      continue
    fi
  fi
  echo "    sign nested: ${item#"$APP"/}"
  sign_nested "$item"
done < <(find "$APP" \( -name '*.bundle' -o -name '*.dylib' \) -print0 | sort -rz)

MAIN_BIN="$APP/Contents/MacOS/LaughPlayer"
if [[ ! -f "$MAIN_BIN" ]]; then
  echo "Missing main executable: $MAIN_BIN" >&2
  exit 1
fi

echo "    sign main binary"
sign_code "$MAIN_BIN"

echo "    sign app bundle"
sign_code "$APP"

verify_signed_app "$APP"
echo "Done: signed $APP"
