#!/usr/bin/env bash
# Builds a release LaughPlayer.app into dist/ (direct / codec-capable).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="LaughPlayer"
# Prefer a writable staging path (avoids leftover root-owned dist/LaughPlayer.app from old installs).
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/dist}"
APP_DIR="${OUT_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/Packaging/RELEASE_VERSION")"
fi
BUNDLE_ID="${BUNDLE_ID:-com.laughplayer.app}"

cd "${ROOT_DIR}"

echo "[create-app-bundle] Preparing codec tools..."
./scripts/bundle-codec-tools.sh

echo "[create-app-bundle] Building release binary..."
./scripts/swift-build.sh release

BIN=""
for candidate in \
  ".build/arm64-apple-macosx/release/LaughPlayer" \
  ".build/release/LaughPlayer"
do
  if [[ -x "${candidate}" ]]; then
    BIN="${candidate}"
    break
  fi
done
if [[ -z "${BIN}" ]]; then
  echo "[create-app-bundle] Missing release binary." >&2
  exit 1
fi

echo "[create-app-bundle] Creating app bundle from ${BIN}..."
mkdir -p "${OUT_DIR}"
if [[ -e "${APP_DIR}" ]] && ! rm -rf "${APP_DIR}" 2>/dev/null; then
  ALT_DIR="${ROOT_DIR}/.build/LaughPlayer.app"
  echo "[create-app-bundle] ${APP_DIR} not writable; using ${ALT_DIR}"
  APP_DIR="${ALT_DIR}"
  CONTENTS_DIR="${APP_DIR}/Contents"
  MACOS_DIR="${CONTENTS_DIR}/MacOS"
  RESOURCES_DIR="${CONTENTS_DIR}/Resources"
  rm -rf "${APP_DIR}"
fi
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN}" "${MACOS_DIR}/LaughPlayer"
chmod +x "${MACOS_DIR}/LaughPlayer"

if [[ -d "Sources/LaughPlayer/codec-tools" ]]; then
  cp -R "Sources/LaughPlayer/codec-tools" "${RESOURCES_DIR}/codec-tools"
fi

SPM_BUNDLE=""
for candidate in \
  ".build/arm64-apple-macosx/release/LaughPlayer_LaughPlayer.bundle" \
  ".build/release/LaughPlayer_LaughPlayer.bundle"
do
  if [[ -d "${candidate}" ]]; then
    SPM_BUNDLE="${candidate}"
    break
  fi
done
if [[ -n "${SPM_BUNDLE}" ]]; then
  cp -R "${SPM_BUNDLE}" "${RESOURCES_DIR}/LaughPlayer_LaughPlayer.bundle"
fi

# Named accent for NSAccentColorName (must be Assets.car — not a raw .colorset folder).
"${ROOT_DIR}/scripts/compile-accent-assets.sh" "${RESOURCES_DIR}"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
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
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>LaughPlayer</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
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

# Ad-hoc sign so Gatekeeper is slightly happier for local install testing.
if command -v codesign >/dev/null 2>&1; then
  echo "[create-app-bundle] Ad-hoc codesigning..."
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || true
fi

echo "[create-app-bundle] App bundle ready: ${APP_DIR}"
