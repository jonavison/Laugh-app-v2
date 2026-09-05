#!/usr/bin/env bash
# Compile AccentColor into Assets.car so NSAccentColorName resolves (raw .colorset copy does not).
# Usage: compile-accent-assets.sh <ResourcesDir>
set -euo pipefail

RESOURCES_DIR="${1:?Resources directory required}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLORSET="${ROOT_DIR}/Sources/LaughPlayer/Resources/AccentColor.colorset"

if [[ ! -d "${COLORSET}" ]]; then
  echo "[compile-accent-assets] No AccentColor.colorset — skipping" >&2
  exit 0
fi

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

if ! xcrun --find actool >/dev/null 2>&1; then
  echo "[compile-accent-assets] WARNING: actool unavailable — system accent may stay blue" >&2
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/laugh-accent.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

mkdir -p "${WORK}/Accent.xcassets"
cp -R "${COLORSET}" "${WORK}/Accent.xcassets/AccentColor.colorset"

xcrun actool \
  --compile "${RESOURCES_DIR}" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --output-partial-info-plist "${WORK}/assetcatalog_generated_info.plist" \
  "${WORK}/Accent.xcassets" >/dev/null

if [[ -f "${RESOURCES_DIR}/Assets.car" ]]; then
  echo "[compile-accent-assets] Wrote ${RESOURCES_DIR}/Assets.car" >&2
else
  echo "[compile-accent-assets] WARNING: Assets.car not produced" >&2
fi
