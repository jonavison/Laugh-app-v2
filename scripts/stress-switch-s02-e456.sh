#!/usr/bin/env bash
# Duration isolation on S02 E04→E05→E06 (skips deep A-return resume).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S02="${1:-/Users/wizmac/Downloads/The Lord of the Rings The Rings of Power (2022) S02 (1080p AMZN WEB-DL x265 10bit EAC3 Atmos 5.1 Celdra)}"
pick() { find "$S02" -maxdepth 1 -type f -name "*S02E${1}*" | head -1; }

A="$(pick 04)"
B="$(pick 05)"
C="$(pick 06)"
EXPECT_A="$(/opt/homebrew/bin/ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$A")"
EXPECT_B="$(/opt/homebrew/bin/ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$B")"
EXPECT_C="$(/opt/homebrew/bin/ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$C")"

APP="${ROOT_DIR}/.build/DevLaughPlayer.app"
BIN="${APP}/Contents/MacOS/LaughPlayer"
RUN_ID="e456-$(date +%H%M%S)"
LOG_DIR="${ROOT_DIR}/.build/switch-stress"
mkdir -p "$LOG_DIR"
REPORT="${LOG_DIR}/report-${RUN_ID}.txt"
say() { echo "$*" | tee -a "$REPORT"; }
: >"$REPORT"
say "=== E04→E05→E06 duration stress ${RUN_ID} ==="
say "A=$(basename "$A") ${EXPECT_A}"
say "B=$(basename "$B") ${EXPECT_B}"
say "C=$(basename "$C") ${EXPECT_C}"

(cd "$ROOT_DIR" && ./scripts/assemble-dev-app.sh debug) >/dev/null
killall LaughPlayer 2>/dev/null || true
sleep 0.5
START_ISO="$(date '+%Y-%m-%d %H:%M:%S')"
env \
  LAUGH_SWITCH_STRESS=1 \
  LAUGH_SWITCH_SKIP_A_RETURN=1 \
  LAUGH_SWITCH_MEDIA_B="$B" \
  LAUGH_SWITCH_MEDIA_C="$C" \
  LAUGH_SWITCH_EXPECT_A="$EXPECT_A" \
  LAUGH_SWITCH_EXPECT_B="$EXPECT_B" \
  LAUGH_SWITCH_EXPECT_C="$EXPECT_C" \
  "$BIN" "$A" >/dev/null 2>&1 &
PID=$!
say "pid=$PID start=$START_ISO"

deadline=$((SECONDS + 180))
while (( SECONDS < deadline )); do
  if ! kill -0 "$PID" 2>/dev/null; then
    say "FAIL: exited early"
    break
  fi
  if /usr/bin/log show \
    --predicate "subsystem == \"com.laughplayer.dev\" AND processID == ${PID} AND eventMessage CONTAINS \"[DEBUG-switchstress] DONE\"" \
    --start "$START_ISO" --style compact 2>/dev/null | grep -q DONE; then
    say "DONE seen"
    break
  fi
  sleep 1
done

DUMP="${LOG_DIR}/logs-${RUN_ID}.txt"
/usr/bin/log show \
  --predicate "subsystem == \"com.laughplayer.dev\" AND processID == ${PID}" \
  --start "$START_ISO" --style compact 2>/dev/null >"$DUMP" || true
fail=$(grep -c '\[DEBUG-switchstress\] FAIL' "$DUMP" || true)
pass=$(grep -c '\[DEBUG-switchstress\] PASS' "$DUMP" || true)
done_n=$(grep -c '\[DEBUG-switchstress\] DONE' "$DUMP" || true)
say "fail=$fail pass=$pass done=$done_n dump=$DUMP"
rg -n 'DEBUG-switchstress' "$DUMP" | tee -a "$REPORT" | tail -50
kill "$PID" 2>/dev/null || killall LaughPlayer 2>/dev/null || true
if (( done_n >= 1 && fail == 0 && pass >= 1 )); then
  say "RESULT=PASS"
  exit 0
fi
say "RESULT=FAIL"
exit 1
