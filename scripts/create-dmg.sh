#!/usr/bin/env bash
# Drag-to-Applications DMG for LaughPlayer (clearer than .pkg for many users).
#
# Usage:
#   ./scripts/create-dmg.sh
#   VERSION=0.9.1 ./scripts/create-dmg.sh
#
# Output:
#   dist/LaughPlayer-<version>.dmg
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
STAGE_OUT="${ROOT_DIR}/.build/pkg-stage"
APP_PATH="${STAGE_OUT}/LaughPlayer.app"
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/Packaging/RELEASE_VERSION")"
fi

VOL_NAME="LaughPlayer ${VERSION}"
DMG_NAME="LaughPlayer-${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
STAGE="${DIST_DIR}/dmg-stage"

cd "${ROOT_DIR}"
mkdir -p "${DIST_DIR}" "${STAGE_OUT}"

SHORT_VER=""
if [[ -d "${APP_PATH}" ]]; then
  SHORT_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true)"
fi
if [[ ! -d "${APP_PATH}" || "${SHORT_VER}" != "${VERSION}" || ! -d "${APP_PATH}/Contents/Resources/LaughPlayer_LaughPlayer.bundle" ]]; then
  echo "[create-dmg] Building app bundle into ${STAGE_OUT}..."
  rm -rf "${APP_PATH}"
  OUT_DIR="${STAGE_OUT}" ./scripts/create-app-bundle.sh
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "[create-dmg] Missing ${APP_PATH}" >&2
  exit 1
fi

SHORT_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true)"
echo "[create-dmg] Staging ${APP_PATH} (CFBundleShortVersionString=${SHORT_VER:-unknown})"
if [[ "${SHORT_VER}" != "${VERSION}" ]]; then
  echo "[create-dmg] ERROR: bundle version ${SHORT_VER:-?} != RELEASE_VERSION ${VERSION}" >&2
  exit 1
fi
if [[ ! -d "${APP_PATH}/Contents/Resources/LaughPlayer_LaughPlayer.bundle" ]]; then
  echo "[create-dmg] ERROR: missing SPM resource bundle under Contents/Resources/" >&2
  exit 1
fi

# Detach leftover volumes from prior runs (paths may contain spaces).
while IFS= read -r mount; do
  [[ -z "$mount" ]] && continue
  echo "[create-dmg] Detaching ${mount}..."
  hdiutil detach "$mount" >/dev/null 2>&1 || hdiutil detach "$mount" -force >/dev/null 2>&1 || true
done < <(mount | awk -F' on | \\(' '/\/Volumes\/LaughPlayer/ {print $2}')

rm -rf "${STAGE}" "${DMG_PATH}"
mkdir -p "${STAGE}"
ditto "${APP_PATH}" "${STAGE}/LaughPlayer.app"
ln -s /Applications "${STAGE}/Applications"

cat > "${STAGE}/How to install.txt" <<EOF
Drag LaughPlayer into the Applications folder.

Then open Applications and double-click LaughPlayer.
Confirm: LaughPlayer → About LaughPlayer → should say ${VERSION}.

Spotlight: search “LaughPlayer” (one word).
EOF

echo "[create-dmg] Creating compressed disk image..."
# Create UDZO directly — avoids a remount/layout step that fails when a
# volume with the same name is already attached or attach output is ambiguous.
hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${STAGE}" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "${DMG_PATH}" >/dev/null

rm -rf "${STAGE}"

SIZE="$(du -h "${DMG_PATH}" | awk '{print $1}')"
echo "[create-dmg] Ready: ${DMG_PATH} (${SIZE})"
echo "[create-dmg] Open it and drag LaughPlayer → Applications."
