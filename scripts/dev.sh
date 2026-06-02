#!/usr/bin/env bash
set -euo pipefail

WATCH_MODE="${1:-}"

if [[ "${WATCH_MODE}" == "--watch" ]]; then
  if command -v fswatch >/dev/null 2>&1; then
    echo "Watching Swift sources with fswatch..."
    swift run &
    RUN_PID=$!

    trap 'kill ${RUN_PID} 2>/dev/null || true' EXIT

    fswatch -o Sources Package.swift | while read -r _; do
      echo "Change detected. Restarting app..."
      kill "${RUN_PID}" 2>/dev/null || true
      wait "${RUN_PID}" 2>/dev/null || true
      swift run &
      RUN_PID=$!
    done
  else
    echo "Watch mode requires fswatch. Install with: brew install fswatch"
    exit 1
  fi
else
  swift run
fi
