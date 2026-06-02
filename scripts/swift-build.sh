#!/usr/bin/env bash
# Wrapper around `swift build` with clearer messages when SwiftPM is busy or compiling.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

CONFIG="debug"
EXTRA_ARGS=()
for arg in "$@"; do
  case "${arg}" in
    --release|-c)
      CONFIG="release"
      EXTRA_ARGS+=("${arg}")
      ;;
    release)
      CONFIG="release"
      EXTRA_ARGS+=("-c" "release")
      ;;
    *)
      EXTRA_ARGS+=("${arg}")
      ;;
  esac
done

if [[ "${CONFIG}" == "release" ]]; then
  echo "[swift-build] Release build (whole-module optimization). Step 4/7 is often the long compile — typically 30s–3m on a large target."
else
  echo "[swift-build] Debug build..."
fi

if pgrep -f "swift-build.*${ROOT_DIR}" >/dev/null 2>&1 || pgrep -f "swift-frontend.*laugh-app-v2" >/dev/null 2>&1; then
  echo "[swift-build] Another Swift build may already be running for this project. This command will wait for SwiftPM's lock."
fi

if (( ${#EXTRA_ARGS[@]} )); then
  swift build "${EXTRA_ARGS[@]}"
else
  swift build
fi

if [[ "${CONFIG}" == "release" ]]; then
  BIN="${ROOT_DIR}/.build/arm64-apple-macosx/release/LaughPlayer"
else
  BIN="${ROOT_DIR}/.build/arm64-apple-macosx/debug/LaughPlayer"
fi

echo "[swift-build] Done: ${BIN}"
