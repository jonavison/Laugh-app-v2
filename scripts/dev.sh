#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

LOGS_MODE=false
WATCH_MODE=false
for arg in "$@"; do
  case "${arg}" in
    --watch) WATCH_MODE=true ;;
    --logs) LOGS_MODE=true ;;
  esac
done

APP_DIR="${ROOT_DIR}/.build/DevLaughPlayer.app"
APP_BIN="${APP_DIR}/Contents/MacOS/LaughPlayer"

launch_dev_app() {
  local wait_for_quit="${1:-false}"

  echo "Preparing bundled codec tools..."
  ./scripts/bundle-codec-tools.sh

  echo "Building and assembling dev app bundle..."
  ./scripts/assemble-dev-app.sh debug

  if [[ ! -x "${APP_BIN}" ]]; then
    echo "Dev app binary missing: ${APP_BIN}" >&2
    exit 1
  fi

  killall LaughPlayer 2>/dev/null || true
  sleep 0.2

  if [[ "${LOGS_MODE}" == "true" ]]; then
    echo "Running LaughPlayer in foreground (stderr logs below). Quit the window to exit."
    exec "${APP_BIN}"
  fi

  echo "Launching ${APP_DIR}"
  if [[ "${wait_for_quit}" == "true" ]]; then
    echo "Close the LaughPlayer window to return to this terminal."
    open -n -W "${APP_DIR}"
  else
    open -n "${APP_DIR}"
    echo "LaughPlayer is running in the background (Dock). Use killall LaughPlayer to stop."
  fi
}

if [[ "${WATCH_MODE}" == "true" ]]; then
  if ! command -v fswatch >/dev/null 2>&1; then
    echo "Watch mode requires fswatch. Install with: brew install fswatch"
    exit 1
  fi

  launch_dev_app false

  echo "Watching Swift sources with fswatch..."
  fswatch -o Sources Package.swift scripts | while read -r _; do
    echo "Change detected. Rebuilding and relaunching..."
    killall LaughPlayer 2>/dev/null || true
    sleep 0.2
    ./scripts/assemble-dev-app.sh debug
    open -n "${APP_DIR}"
  done
else
  launch_dev_app true
fi
