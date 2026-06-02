#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
APP_PATH="${DIST_DIR}/LaughPlayer.app"
PKG_PATH="${DIST_DIR}/LaughPlayer-Installer.pkg"
VERSION="${VERSION:-1.0.0}"
IDENTIFIER="${IDENTIFIER:-com.laughplayer.installer}"

cd "${ROOT_DIR}"

echo "[create-pkg] Building app bundle..."
./scripts/create-app-bundle.sh

echo "[create-pkg] Creating installer package..."
rm -f "${PKG_PATH}"
pkgbuild \
  --root "${DIST_DIR}" \
  --install-location "/Applications" \
  --identifier "${IDENTIFIER}" \
  --version "${VERSION}" \
  "${PKG_PATH}"

echo "[create-pkg] Installer ready: ${PKG_PATH}"
