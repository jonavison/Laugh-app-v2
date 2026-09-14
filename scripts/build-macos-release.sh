#!/usr/bin/env bash
# Build, Developer ID sign, notarize, and package Laugh as a drag-to-Applications DMG.
#
# Usage:
#   ./scripts/build-macos-release.sh [--skip-notarize] [--dmg-only]
#
# Output:
#   dist/LaughPlayer-<version>.dmg
#   ~/Desktop/LaughPlayer-<version>.dmg (copy)
#
# First-time setup: Packaging/release-env.example → Packaging/release-env.local
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/release-common.sh"

SKIP_NOTARIZE=0
SKIP_TO_DMG=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    --dmg-only) SKIP_TO_DMG=1 ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--skip-notarize] [--dmg-only]" >&2
      exit 1
      ;;
  esac
done

release_common_init
VERSION="$(read_release_version)"
if [[ -z "$VERSION" ]]; then
  echo "Set Packaging/RELEASE_VERSION first." >&2
  exit 1
fi

OUT_DMG="$ROOT/dist/LaughPlayer-${VERSION}.dmg"
DESKTOP_DMG="${HOME}/Desktop/LaughPlayer-${VERSION}.dmg"

echo "==> Laugh ${VERSION}"
echo "    bundle id: $BUNDLE_ID"
echo "    staged:    $STAGED_APP"
echo "    output:    $OUT_DMG"

if [[ "$SKIP_TO_DMG" -eq 0 ]]; then
  echo "==> Build app bundle (no ad-hoc sign)"
  rm -rf "$STAGED_APP"
  mkdir -p "$STAGE_OUT"
  SKIP_ADHOC_SIGN=1 OUT_DIR="$STAGE_OUT" BUNDLE_ID="$BUNDLE_ID" \
    "$ROOT/scripts/create-app-bundle.sh"

  echo "==> Developer ID sign"
  "$SCRIPT_DIR/sign-laugh-app.sh" "$STAGED_APP"

  if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
    echo "==> Notarize app"
    "$SCRIPT_DIR/notarize-laugh-artifact.sh" "$STAGED_APP"
  else
    echo "==> Skipping notarization (--skip-notarize)"
  fi
else
  if [[ ! -d "$STAGED_APP" ]]; then
    echo "Missing staged app for --dmg-only: $STAGED_APP" >&2
    exit 1
  fi
  echo "==> --dmg-only: using existing $STAGED_APP"
fi

echo "==> Build DMG from signed app"
VERSION="$VERSION" "$ROOT/scripts/create-dmg.sh"

if [[ ! -f "$OUT_DMG" ]]; then
  echo "Missing DMG: $OUT_DMG" >&2
  exit 1
fi

IDENTITY="$(resolve_codesign_identity)"
echo "==> Sign DMG"
codesign_with_timestamp_retry --force --sign "$IDENTITY" --timestamp "$OUT_DMG"

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  echo "==> Notarize DMG"
  "$SCRIPT_DIR/notarize-laugh-artifact.sh" "$OUT_DMG"
fi

cp -f "$OUT_DMG" "$DESKTOP_DMG"
echo "==> Ready: $DESKTOP_DMG"
echo "    Drag LaughPlayer → Applications. Quarantine should clear after Gatekeeper checks notarization."
