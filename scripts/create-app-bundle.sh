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
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "${ROOT_DIR}" rev-list --count HEAD 2>/dev/null || echo 1)}"
BUNDLE_ID="${BUNDLE_ID:-com.laughplayer.app}"
ICON_ICNS="${ROOT_DIR}/Packaging/Resources/AppIcon.icns"
# Ship Sparkle feed into release .app only (Dev bundle omits this).
ENABLE_SPARKLE="${ENABLE_SPARKLE:-1}"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/sparkle-common.sh"

cd "${ROOT_DIR}"

echo "[create-app-bundle] Preparing codec tools..."
./scripts/bundle-codec-tools.sh

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/codec-portability.sh"
codec_assert_portable "${ROOT_DIR}/Sources/LaughPlayer/codec-tools/bin/ffmpeg" "bundled ffmpeg"
codec_assert_native_arch "${ROOT_DIR}/Sources/LaughPlayer/codec-tools/bin/ffmpeg" "bundled ffmpeg"
if [[ -x "${ROOT_DIR}/Sources/LaughPlayer/codec-tools/bin/mpv" ]]; then
  codec_assert_portable "${ROOT_DIR}/Sources/LaughPlayer/codec-tools/bin/mpv" "bundled mpv"
  codec_assert_native_arch "${ROOT_DIR}/Sources/LaughPlayer/codec-tools/bin/mpv" "bundled mpv"
fi

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
pick_writable_app_dir() {
  local candidate="$1"
  if [[ -e "${candidate}" ]] && ! rm -rf "${candidate}" 2>/dev/null; then
    return 1
  fi
  mkdir -p "$(dirname "${candidate}")" 2>/dev/null || return 1
  # Probe write access without leaving junk.
  if ! mkdir -p "${candidate}" 2>/dev/null; then
    return 1
  fi
  rm -rf "${candidate}" 2>/dev/null || return 1
  return 0
}

if ! pick_writable_app_dir "${APP_DIR}"; then
  for ALT_DIR in \
    "${ROOT_DIR}/.build/LaughPlayer.app" \
    "${ROOT_DIR}/.build/pkg-stage/LaughPlayer.app" \
    "/tmp/LaughPlayer-bundle/LaughPlayer.app"
  do
    echo "[create-app-bundle] ${APP_DIR} not writable; trying ${ALT_DIR}"
    if pick_writable_app_dir "${ALT_DIR}"; then
      APP_DIR="${ALT_DIR}"
      CONTENTS_DIR="${APP_DIR}/Contents"
      MACOS_DIR="${CONTENTS_DIR}/MacOS"
      RESOURCES_DIR="${CONTENTS_DIR}/Resources"
      break
    fi
  done
fi
if ! pick_writable_app_dir "${APP_DIR}"; then
  echo "[create-app-bundle] No writable place for LaughPlayer.app (root-owned leftovers?)." >&2
  echo "[create-app-bundle] Remove with: sudo rm -rf ${ROOT_DIR}/.build/LaughPlayer.app ${ROOT_DIR}/dist/LaughPlayer.app" >&2
  exit 1
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
  # Keep the SPM resource bundle under Contents/Resources/ only.
  # Placing it next to Contents/ makes Developer ID codesign fail
  # ("unsealed contents present in the bundle root"). ResourceBundle
  # resolves Contents/Resources/LaughPlayer_LaughPlayer.bundle.
  rm -rf "${APP_DIR}/LaughPlayer_LaughPlayer.bundle" "${RESOURCES_DIR}/LaughPlayer_LaughPlayer.bundle"
  cp -R "${SPM_BUNDLE}" "${RESOURCES_DIR}/LaughPlayer_LaughPlayer.bundle"
  echo "[create-app-bundle] Embedded LaughPlayer_LaughPlayer.bundle (Contents/Resources)"
fi

# Named accent for NSAccentColorName (must be Assets.car — not a raw .colorset folder).
"${ROOT_DIR}/scripts/compile-accent-assets.sh" "${RESOURCES_DIR}"

ICON_PLIST_ENTRIES=""
if [[ -f "${ICON_ICNS}" ]]; then
  cp "${ICON_ICNS}" "${RESOURCES_DIR}/AppIcon.icns"
  ICON_PLIST_ENTRIES=$'  <key>CFBundleIconFile</key>\n  <string>AppIcon</string>\n'
  echo "[create-app-bundle] Installed AppIcon.icns"
else
  echo "[create-app-bundle] WARNING: missing ${ICON_ICNS}" >&2
fi

SPARKLE_PLIST_ENTRIES=""
if [[ "${ENABLE_SPARKLE}" == "1" ]]; then
  stage_embed_sparkle_framework "${APP_DIR}"
  SPARKLE_PLIST_ENTRIES="$(sparkle_info_plist_snippet)"
fi

YEAR="$(date +%Y)"
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
  <string>${BUILD_NUMBER}</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © ${YEAR} Avison. All rights reserved.</string>
${ICON_PLIST_ENTRIES}${SPARKLE_PLIST_ENTRIES}  <key>LSMinimumSystemVersion</key>
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

# Ad-hoc sign for local testing only. Release builds use scripts/sign-laugh-app.sh.
if [[ "${SKIP_ADHOC_SIGN:-0}" != "1" ]] && command -v codesign >/dev/null 2>&1; then
  echo "[create-app-bundle] Ad-hoc codesigning..."
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || true
elif [[ "${SKIP_ADHOC_SIGN:-0}" == "1" ]]; then
  echo "[create-app-bundle] Skipping ad-hoc codesign (Developer ID signing comes next)"
fi

echo "[create-app-bundle] App bundle ready: ${APP_DIR}"
