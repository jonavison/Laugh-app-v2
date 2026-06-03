#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="LaughPlayer"
APP_DIR="${ROOT_DIR}/dist/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

cd "${ROOT_DIR}"

echo "[create-app-bundle] Preparing codec tools..."
./scripts/bundle-codec-tools.sh

echo "[create-app-bundle] Building release binary..."
swift build -c release

echo "[create-app-bundle] Creating app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp ".build/release/LaughPlayer" "${MACOS_DIR}/LaughPlayer"
chmod +x "${MACOS_DIR}/LaughPlayer"

if [[ -d "Sources/LaughPlayer/codec-tools" ]]; then
  cp -R "Sources/LaughPlayer/codec-tools" "${RESOURCES_DIR}/codec-tools"
fi

SPM_BUNDLE=".build/release/LaughPlayer_LaughPlayer.bundle"
if [[ -d "${SPM_BUNDLE}" ]]; then
  cp -R "${SPM_BUNDLE}" "${RESOURCES_DIR}/LaughPlayer_LaughPlayer.bundle"
fi

if [[ -d "Sources/LaughPlayer/Resources/AccentColor.colorset" ]]; then
  cp -R "Sources/LaughPlayer/Resources/AccentColor.colorset" "${RESOURCES_DIR}/AccentColor.colorset"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>LaughPlayer</string>
  <key>CFBundleExecutable</key>
  <string>LaughPlayer</string>
  <key>CFBundleIdentifier</key>
  <string>com.laughplayer.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>LaughPlayer</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAccentColorName</key>
  <string>AccentColor</string>
</dict>
</plist>
EOF

echo "[create-app-bundle] App bundle ready: ${APP_DIR}"
