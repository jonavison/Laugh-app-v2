#!/usr/bin/env bash
# Tail LaughPlayer format / route / buffer traces while a video plays.
# Rebuild and relaunch the app first so traces are present:
#   ./scripts/dev.sh --logs
# or launch the Dock app, then run this script in another terminal.
set -euo pipefail

echo "Watching LaughPlayer playback traces (format, route, buffer, remux)."
echo "Open a video in LaughPlayer. Ctrl+C to stop."
echo

/usr/bin/log stream --style compact --level debug --predicate \
  'subsystem == "com.laughplayer.dev" OR (process == "LaughPlayer" AND eventMessage CONTAINS "[DEBUG-")'
