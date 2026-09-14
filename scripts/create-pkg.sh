#!/usr/bin/env bash
# Builds a double-clickable macOS installer (.pkg) that installs LaughPlayer.app
# into /Applications.
#
# Usage:
#   ./scripts/create-pkg.sh
#   VERSION=0.9.1 ./scripts/create-pkg.sh
#
# Output:
#   dist/LaughPlayer-Installer.pkg
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
# Dedicated writable staging dir — never reuse a root-owned .build/LaughPlayer.app leftover.
STAGE_OUT="${ROOT_DIR}/.build/pkg-stage"
APP_PATH="${STAGE_OUT}/LaughPlayer.app"
PAYLOAD_DIR="${DIST_DIR}/pkg-payload"
SCRIPTS_DIR="${DIST_DIR}/pkg-scripts"
COMPONENT_PKG="${DIST_DIR}/LaughPlayer-component.pkg"
PKG_PATH="${DIST_DIR}/LaughPlayer-Installer.pkg"
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/Packaging/RELEASE_VERSION")"
fi
IDENTIFIER="${IDENTIFIER:-com.laughplayer.app}"
INSTALLER_ID="${INSTALLER_ID:-com.laughplayer.installer}"

cd "${ROOT_DIR}"
mkdir -p "${DIST_DIR}" "${STAGE_OUT}"

echo "[create-pkg] Building app bundle into ${STAGE_OUT}..."
rm -rf "${APP_PATH}"
OUT_DIR="${STAGE_OUT}" ./scripts/create-app-bundle.sh

if [[ ! -d "${APP_PATH}" ]]; then
  echo "[create-pkg] Missing app bundle: ${APP_PATH}" >&2
  exit 1
fi

SHORT_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true)"
ICON_FILE="${APP_PATH}/Contents/Resources/AppIcon.icns"
echo "[create-pkg] Packaging ${APP_PATH} (CFBundleShortVersionString=${SHORT_VER:-unknown})"
if [[ "${SHORT_VER}" != "${VERSION}" ]]; then
  echo "[create-pkg] ERROR: bundle version ${SHORT_VER:-?} != RELEASE_VERSION ${VERSION}" >&2
  exit 1
fi
if [[ ! -d "${APP_PATH}/Contents/Resources/LaughPlayer_LaughPlayer.bundle" ]]; then
  echo "[create-pkg] ERROR: missing SPM resource bundle under Contents/Resources/" >&2
  exit 1
fi
if [[ ! -f "${ICON_FILE}" ]]; then
  echo "[create-pkg] WARNING: AppIcon.icns missing from bundle" >&2
fi

echo "[create-pkg] Staging installer payload..."
rm -rf "${PAYLOAD_DIR}" "${SCRIPTS_DIR}"
mkdir -p "${PAYLOAD_DIR}" "${SCRIPTS_DIR}"
ditto "${APP_PATH}" "${PAYLOAD_DIR}/LaughPlayer.app"

# postinstall MUST run — Distribution options require-scripts=true below.
cat > "${SCRIPTS_DIR}/postinstall" <<'POST'
#!/bin/bash
# Runs as root after LaughPlayer.app is copied to /Applications.
set -euo pipefail
APP="/Applications/LaughPlayer.app"
LS="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ ! -d "$APP" ]]; then
  echo "postinstall: missing $APP" >&2
  exit 1
fi

# Prefer root:admin ownership like a normal Applications install.
chown -R root:wheel "$APP" 2>/dev/null || true
chmod -R a+rX "$APP" 2>/dev/null || true

"$LS" -f "$APP" >/dev/null 2>&1 || true

# Remove junk users sometimes drag into Applications.
rm -f /Applications/LaughPlayer-Installer.pkg 2>/dev/null || true
rm -f /Applications/LaughPlayer-*.pkg 2>/dev/null || true

CONSOLE_USER="$(stat -f%Su /dev/console 2>/dev/null || true)"
if [[ -n "${CONSOLE_USER}" && "${CONSOLE_USER}" != "root" ]]; then
  # Show Applications and highlight LaughPlayer so the user can see it.
  sudo -u "${CONSOLE_USER}" open /Applications >/dev/null 2>&1 || true
  sudo -u "${CONSOLE_USER}" open -R "$APP" >/dev/null 2>&1 || true
fi

exit 0
POST
chmod 755 "${SCRIPTS_DIR}/postinstall"

echo "[create-pkg] Building component package..."
rm -f "${COMPONENT_PKG}" "${PKG_PATH}"
pkgbuild \
  --root "${PAYLOAD_DIR}" \
  --install-location "/Applications" \
  --scripts "${SCRIPTS_DIR}" \
  --identifier "${IDENTIFIER}" \
  --version "${VERSION}" \
  "${COMPONENT_PKG}"

DIST_XML="${DIST_DIR}/Distribution.xml"
cat > "${DIST_XML}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>LaughPlayer ${VERSION}</title>
    <organization>${INSTALLER_ID}</organization>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <options customize="never" require-scripts="true" rootVolumeOnly="true"/>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
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
cat > "${RESOURCES_DIR}/welcome.html" <<EOF
<html>
<body style="font-family: -apple-system, Helvetica, Arial, sans-serif; font-size: 13px; line-height: 1.45;">
  <h2>Install LaughPlayer ${VERSION}</h2>
  <p>Installs <b>LaughPlayer.app</b> into <code>/Applications</code>.</p>
  <p>After install, Finder opens Applications and selects <b>LaughPlayer</b> (under <b>L</b>).</p>
  <p>If macOS blocks this installer: right-click the <code>.pkg</code> → <b>Open</b> → Open.</p>
</body>
</html>
EOF

cat > "${RESOURCES_DIR}/conclusion.html" <<EOF
<html>
<body style="font-family: -apple-system, Helvetica, Arial, sans-serif; font-size: 13px; line-height: 1.45;">
  <h2>LaughPlayer ${VERSION} installed</h2>
  <p>Look in <b>Applications</b> for <b>LaughPlayer</b> (one word).</p>
  <p>Launchpad may hide unsigned apps — use Finder → Applications, or Spotlight search <b>LaughPlayer</b>.</p>
  <p>Confirm: menu <b>LaughPlayer → About LaughPlayer</b> should show <b>${VERSION}</b>.</p>
  <p>Prefer drag-and-drop? Use the <b>LaughPlayer ${VERSION}.dmg</b> instead.</p>
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

rm -rf "${PAYLOAD_DIR}" "${SCRIPTS_DIR}" "${RESOURCES_DIR}" "${DIST_XML}" "${COMPONENT_PKG}"

SIZE="$(du -h "${PKG_PATH}" | awk '{print $1}')"
echo "[create-pkg] Installer ready: ${PKG_PATH} (${SIZE})"
echo "[create-pkg] Also consider: ./scripts/create-dmg.sh"
