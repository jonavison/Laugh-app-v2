#!/usr/bin/env bash
# Assembles a debug .app bundle so macOS treats LaughPlayer as a real GUI app (windows show reliably).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

CONFIG="${1:-debug}"
if [[ "${CONFIG}" == "release" ]]; then
  BUILD_DIR=".build/arm64-apple-macosx/release"
  ./scripts/swift-build.sh release >&2
else
  BUILD_DIR=".build/arm64-apple-macosx/debug"
  if [[ -x "${BUILD_DIR}/LaughPlayer" ]] \
    && find Sources Package.swift -name '*.swift' -newer "${BUILD_DIR}/LaughPlayer" -print -quit 2>/dev/null | grep -q .; then
    echo "[assemble-dev-app] Sources changed — rebuilding" >&2
  fi
  ./scripts/swift-build.sh >&2
fi

BIN="${BUILD_DIR}/LaughPlayer"
SPM_BUNDLE="${BUILD_DIR}/LaughPlayer_LaughPlayer.bundle"
APP_DIR="${ROOT_DIR}/.build/DevLaughPlayer.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
DEV_VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/Packaging/RELEASE_VERSION")-dev"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/sparkle-common.sh"

if [[ ! -x "${BIN}" ]]; then
  echo "[assemble-dev-app] Missing binary: ${BIN}" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

cp "${BIN}" "${MACOS}/LaughPlayer"
chmod +x "${MACOS}/LaughPlayer"

if [[ -d "Sources/LaughPlayer/codec-tools" ]]; then
  cp -R "Sources/LaughPlayer/codec-tools" "${RESOURCES}/codec-tools"
fi

if [[ -d "${SPM_BUNDLE}" ]]; then
  # Contents/Resources only — app-root .bundle breaks Developer ID codesign.
  rm -rf "${APP_DIR}/LaughPlayer_LaughPlayer.bundle" "${RESOURCES}/LaughPlayer_LaughPlayer.bundle"
  cp -R "${SPM_BUNDLE}" "${RESOURCES}/LaughPlayer_LaughPlayer.bundle"
fi

# Binary links Sparkle — embed the framework (no SUFeedURL → updates stay disabled).
stage_embed_sparkle_framework "${APP_DIR}"

# Named accent for NSAccentColorName (must be Assets.car — not a raw .colorset folder).
./scripts/compile-accent-assets.sh "${RESOURCES}"

ICON_PLIST_ENTRIES=""
if [[ -f "${ROOT_DIR}/Packaging/Resources/AppIcon.icns" ]]; then
  cp "${ROOT_DIR}/Packaging/Resources/AppIcon.icns" "${RESOURCES}/AppIcon.icns"
  ICON_PLIST_ENTRIES=$'  <key>CFBundleIconFile</key>\n  <string>AppIcon</string>\n'
fi

cat > "${CONTENTS}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>LaughPlayer</string>
  <key>CFBundleExecutable</key>
  <string>LaughPlayer</string>
  <key>CFBundleIdentifier</key>
  <string>com.laughplayer.dev</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>LaughPlayer</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${DEV_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>1</string>
${ICON_PLIST_ENTRIES}  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSBackgroundOnly</key>
  <false/>
  <key>LSUIElement</key>
  <false/>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Video</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.movie</string>
        <string>public.video</string>
        <string>public.mpeg-4</string>
        <string>com.apple.quicktime-movie</string>
      </array>
    </dict>
  </array>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAccentColorName</key>
  <string>AccentColor</string>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || true
fi

echo "[assemble-dev-app] Ready: ${APP_DIR}" >&2
