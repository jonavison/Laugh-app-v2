#!/usr/bin/env bash
# Generate appcast.xml from Sparkle release zips for LaughPlayer.
#
# Usage:
#   ./scripts/generate-laugh-appcast.sh [<releases-directory>]
#
# Default: .build/sparkle-releases/
# Copy appcast.xml + zips to advision-web/public/laugh/ when publishing.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/sparkle-common.sh"

RELEASES_DIR="${1:-}"
sparkle_common_init
ensure_sparkle_artifacts
require_sparkle_public_key >/dev/null

if [[ -z "$RELEASES_DIR" ]]; then
  RELEASES_DIR="$SPARKLE_RELEASES_DIR"
fi

if [[ ! -d "$RELEASES_DIR" ]]; then
  echo "Releases directory not found: $RELEASES_DIR" >&2
  exit 1
fi

shopt -s nullglob
zips=("$RELEASES_DIR"/*.zip)
shopt -u nullglob
if [[ ${#zips[@]} -eq 0 ]]; then
  echo "No .zip files in $RELEASES_DIR — run ./scripts/build-macos-sparkle-zip.sh first." >&2
  exit 1
fi

echo "==> generate_appcast"
echo "    dir:     $RELEASES_DIR"
echo "    prefix:  $SPARKLE_DOWNLOAD_URL_PREFIX"

"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "$SPARKLE_DOWNLOAD_URL_PREFIX" \
  "$RELEASES_DIR"

echo ""
echo "Done: $RELEASES_DIR/appcast.xml"
echo "Publish to avison-soft.com/laugh/ (appcast.xml + zip)."
