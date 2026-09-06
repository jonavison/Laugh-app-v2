#!/usr/bin/env bash
# Builds a double-clickable macOS installer (.pkg) that installs LaughPlayer.app
# into /Applications — same install flow as apps like Smile.
#
# Usage:
#   ./scripts/create-pkg.sh
#   VERSION=0.3.1 ./scripts/create-pkg.sh   # optional override
#
# Output:
#   dist/LaughPlayer-Installer.pkg
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_PATH="${DIST_DIR}/LaughPlayer.app"
PAYLOAD_DIR="${DIST_DIR}/pkg-payload"
COMPONENT_PKG="${DIST_DIR}/LaughPlayer-component.pkg"
PKG_PATH="${DIST_DIR}/LaughPlayer-Installer.pkg"
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/Packaging/RELEASE_VERSION")"
fi
IDENTIFIER="${IDENTIFIER:-com.laughplayer.app}"
INSTALLER_ID="${INSTALLER_ID:-com.laughplayer.installer}"

cd "${ROOT_DIR}"
mkdir -p "${DIST_DIR}"

echo "[create-pkg] Building app bundle..."
./scripts/create-app-bundle.sh

# create-app-bundle falls back to .build/ when dist/LaughPlayer.app is not writable (e.g. root-owned).
if [[ ! -d "${APP_PATH}" ]] || [[ -d "${ROOT_DIR}/.build/LaughPlayer.app" \
  && "${ROOT_DIR}/.build/LaughPlayer.app/Contents/MacOS/LaughPlayer" -nt \
     "${APP_PATH}/Contents/MacOS/LaughPlayer" ]]; then
  if [[ -d "${ROOT_DIR}/.build/LaughPlayer.app" ]]; then
    APP_PATH="${ROOT_DIR}/.build/LaughPlayer.app"
    echo "[create-pkg] Using fresh app bundle: ${APP_PATH}"
  fi
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "[create-pkg] Missing app bundle: ${APP_PATH}" >&2
  exit 1
fi

echo "[create-pkg] Staging installer payload..."
rm -rf "${PAYLOAD_DIR}"
mkdir -p "${PAYLOAD_DIR}"
# Only the .app goes into /Applications (not the whole dist folder).
ditto "${APP_PATH}" "${PAYLOAD_DIR}/LaughPlayer.app"

echo "[create-pkg] Building component package..."
rm -f "${COMPONENT_PKG}" "${PKG_PATH}"
pkgbuild \
  --root "${PAYLOAD_DIR}" \
  --install-location "/Applications" \
  --identifier "${IDENTIFIER}" \
  --version "${VERSION}" \
  "${COMPONENT_PKG}"

# Distribution XML gives a proper Installer.app UI (welcome → install → summary).
DIST_XML="${DIST_DIR}/Distribution.xml"
cat > "${DIST_XML}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>LaughPlayer</title>
    <organization>${INSTALLER_ID}</organization>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <options customize="never" require-scripts="false" rootVolumeOnly="true"/>
    <welcome file="welcome.html" mime-type="text/html"/>
    <pkg-ref id="${IDENTIFIER}"/>
    <choices-outline>
        <line choice="default"/>
    </choices-outline>
    <choice id="default" title="LaughPlayer">
        <pkg-ref id="${IDENTIFIER}"/>
    </choice>
    <pkg-ref id="${IDENTIFIER}" version="${VERSION}" onConclusion="none">LaughPlayer-component.pkg</pkg-ref>
</installer-gui-script>
EOF

RESOURCES_DIR="${DIST_DIR}/pkg-resources"
rm -rf "${RESOURCES_DIR}"
mkdir -p "${RESOURCES_DIR}"
cat > "${RESOURCES_DIR}/welcome.html" <<'EOF'
<html>
<body style="font-family: -apple-system, Helvetica, Arial, sans-serif; font-size: 13px; line-height: 1.45;">
  <h2>Install LaughPlayer</h2>
  <p>This package installs <b>LaughPlayer</b> into <code>/Applications</code>.</p>
  <p>After installation, open it from Launchpad or Applications. Drop a video or image to start.</p>
  <p style="color:#666;">Unsigned local build — if macOS blocks it, right-click the app → Open, or allow it in System Settings → Privacy &amp; Security.</p>
</body>
</html>
EOF

echo "[create-pkg] Building product installer..."
if productbuild \
  --distribution "${DIST_XML}" \
  --resources "${RESOURCES_DIR}" \
  --package-path "${DIST_DIR}" \
  "${PKG_PATH}"; then
  :
else
  echo "[create-pkg] productbuild failed; falling back to component pkg only."
  cp "${COMPONENT_PKG}" "${PKG_PATH}"
fi

# Cleanup staging artifacts (keep the final installer + .app).
rm -rf "${PAYLOAD_DIR}" "${RESOURCES_DIR}" "${DIST_XML}" "${COMPONENT_PKG}"

SIZE="$(du -h "${PKG_PATH}" | awk '{print $1}')"
echo "[create-pkg] Installer ready: ${PKG_PATH} (${SIZE})"
echo "[create-pkg] Double-click to install, or:"
echo "  open \"${PKG_PATH}\""
echo "  sudo installer -pkg \"${PKG_PATH}\" -target /"
