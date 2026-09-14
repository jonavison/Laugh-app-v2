#!/usr/bin/env bash
# Create a Sparkle update .zip from a staged LaughPlayer.app (.build or dist).
#
# Usage:
#   ./scripts/build-macos-sparkle-zip.sh [<marketing-version>] [<app-path>]
#
# Default app: .build/LaughPlayer.app (from create-app-bundle / create-pkg)
# Output: .build/sparkle-releases/LaughPlayer <version>.zip
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/sparkle-common.sh"

sparkle_common_init

MARKETING_VERSION="${1:-$(tr -d '[:space:]' < "${ROOT_DIR}/Packaging/RELEASE_VERSION")}"
APP_PATH="${2:-${ROOT_DIR}/.build/LaughPlayer.app}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app: $APP_PATH" >&2
  echo "Run OUT_DIR=.build ./scripts/create-app-bundle.sh first." >&2
  exit 1
fi

ZIP_BASENAME="LaughPlayer ${MARKETING_VERSION}.zip"
OUT_ZIP="${SPARKLE_RELEASES_DIR}/${ZIP_BASENAME}"
mkdir -p "$(dirname "$OUT_ZIP")"
rm -f "$OUT_ZIP"

echo "==> Sparkle zip ${MARKETING_VERSION}"
echo "    app:  $APP_PATH"
echo "    out:  $OUT_ZIP"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUT_ZIP"

echo "==> sign_update"
sign_sparkle_update "$OUT_ZIP"

echo ""
echo "Done: $OUT_ZIP"
echo "Next: ./scripts/generate-laugh-appcast.sh"
