#!/usr/bin/env bash
# In-app A→B→C switch / resume / duration stress on Rings of Power S02.
# Usage:
#   ./scripts/stress-switch-playback.sh
#   ./scripts/stress-switch-playback.sh /path/to/S02/folder
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${ROOT_DIR}/.build/DevLaughPlayer.app"
BIN="${APP}/Contents/MacOS/LaughPlayer"
S02_DIR="${1:-/Users/wizmac/Downloads/The Lord of the Rings The Rings of Power (2022) S02 (1080p AMZN WEB-DL x265 10bit EAC3 Atmos 5.1 Celdra)}"
RUN_ID="${2:-$(date +%Y%m%d-%H%M%S)}"
LOG_DIR="${ROOT_DIR}/.build/switch-stress"
mkdir -p "${LOG_DIR}"
REPORT="${LOG_DIR}/report-${RUN_ID}.txt"
START_EPOCH="$(date +%s)"
START_ISO="$(date -r "${START_EPOCH}" '+%Y-%m-%d %H:%M:%S')"

say() { echo "$*" | tee -a "${REPORT}"; }

pick_ep() {
  local ep="$1"
  local match
  match="$(find "${S02_DIR}" -maxdepth 1 -type f -name "*S02E${ep}*" -print | head -1)"
  if [[ -z "${match}" ]]; then
    echo "missing S02E${ep} in ${S02_DIR}" >&2
    exit 2
  fi
  printf '%s' "${match}"
}

ffprobe_dur() {
  local f="$1"
  /opt/homebrew/bin/ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$f" 2>/dev/null \
    || ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$f"
}

dismiss_tcc_and_allow() {
  /usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "System Events"
  repeat with p in {"SecurityAgent", "UserNotificationCenter", "coreautha", "LaughPlayer"}
    if exists process p then
      try
        tell process p
          repeat with w in windows
            try
              if exists button "Allow" of w then click button "Allow" of w
              if exists button "OK" of w then click button "OK" of w
              if exists button "Open" of w then click button "Open" of w
            end try
          end repeat
        end tell
      end try
    end if
  end repeat
end tell
APPLESCRIPT
}

wait_for_pid_log() {
  local pid="$1"
  local needle="$2"
  local timeout_s="${3:-180}"
  local deadline=$((SECONDS + timeout_s))
  while (( SECONDS < deadline )); do
    dismiss_tcc_and_allow
    if /usr/bin/log show \
      --predicate "subsystem == \"com.laughplayer.dev\" AND processID == ${pid} AND eventMessage CONTAINS \"${needle}\"" \
      --start "${START_ISO}" --style compact 2>/dev/null \
      | /usr/bin/grep -F "${needle}" >/dev/null; then
      return 0
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      say "WARN: LaughPlayer pid=${pid} exited early"
      return 1
    fi
    sleep 1
  done
  return 1
}

score_logs() {
  local pid="$1"
  local dump="${LOG_DIR}/logs-${RUN_ID}.txt"
  /usr/bin/log show \
    --predicate "subsystem == \"com.laughplayer.dev\" AND processID == ${pid}" \
    --start "${START_ISO}" --style compact 2>/dev/null >"${dump}" || true

  local fail_n ok_n pass done_line
  fail_n=$(grep -c '\[DEBUG-switchstress\] FAIL' "${dump}" || true)
  ok_n=$(grep -c '\[DEBUG-switchstress\] OK' "${dump}" || true)
  pass=$(grep -c '\[DEBUG-switchstress\] PASS' "${dump}" || true)
  done_line=$(grep -c '\[DEBUG-switchstress\] DONE' "${dump}" || true)

  say "=== SCORE run=${RUN_ID} pid=${pid} ==="
  say "fail=${fail_n} ok=${ok_n} pass_line=${pass} done=${done_line}"
  say "log_dump=${dump}"
  rg -n 'DEBUG-switchstress|DEBUG-resume|Ready to play|DEBUG-route|DEBUG-mpv\] playback started' "${dump}" \
    | tail -80 | tee -a "${REPORT}" || true

  if (( done_line < 1 )); then say "FAIL: harness did not finish"; return 1; fi
  if (( fail_n > 0 )); then say "FAIL: ${fail_n} switchstress failures"; return 1; fi
  if (( pass < 1 )); then say "FAIL: no PASS line"; return 1; fi
  say "PASS: switch/resume/duration stress clean"
  return 0
}

main() {
  : >"${REPORT}"
  say "=== switch stress ${RUN_ID} start $(date) ==="
  say "dir=${S02_DIR}"

  MEDIA_A="$(pick_ep 01)"
  MEDIA_B="$(pick_ep 02)"
  MEDIA_C="$(pick_ep 03)"
  EXPECT_A="$(ffprobe_dur "${MEDIA_A}")"
  EXPECT_B="$(ffprobe_dur "${MEDIA_B}")"
  EXPECT_C="$(ffprobe_dur "${MEDIA_C}")"

  say "A=$(basename "${MEDIA_A}") expect=${EXPECT_A}"
  say "B=$(basename "${MEDIA_B}") expect=${EXPECT_B}"
  say "C=$(basename "${MEDIA_C}") expect=${EXPECT_C}"

  (cd "${ROOT_DIR}" && ./scripts/assemble-dev-app.sh debug) | tee -a "${REPORT}"
  say "app assembled"

  killall LaughPlayer 2>/dev/null || true
  sleep 0.5

  START_EPOCH="$(date +%s)"
  START_ISO="$(date -r "${START_EPOCH}" '+%Y-%m-%d %H:%M:%S')"

  env \
    LAUGH_SWITCH_STRESS=1 \
    LAUGH_SWITCH_MEDIA_B="${MEDIA_B}" \
    LAUGH_SWITCH_MEDIA_C="${MEDIA_C}" \
    LAUGH_SWITCH_EXPECT_A="${EXPECT_A}" \
    LAUGH_SWITCH_EXPECT_B="${EXPECT_B}" \
    LAUGH_SWITCH_EXPECT_C="${EXPECT_C}" \
    "${BIN}" "${MEDIA_A}" >/dev/null 2>&1 &
  local app_pid=$!
  say "launched pid=${app_pid} start=${START_ISO}"
  sleep 1.5
  dismiss_tcc_and_allow

  if wait_for_pid_log "${app_pid}" "Ready to play" 90 \
    || wait_for_pid_log "${app_pid}" "[DEBUG-mpv] playback started" 90; then
    say "First playback observed"
  else
    say "WARN: first ready not seen"
  fi

  if wait_for_pid_log "${app_pid}" "[DEBUG-switchstress] starting" 60; then
    say "Harness started"
  else
    say "FAIL: harness did not start"
    kill "${app_pid}" 2>/dev/null || killall LaughPlayer 2>/dev/null || true
    exit 1
  fi

  if wait_for_pid_log "${app_pid}" "[DEBUG-switchstress] DONE" 180; then
    say "Harness DONE"
  else
    if ! kill -0 "${app_pid}" 2>/dev/null; then
      say "FAIL: LaughPlayer exited before harness DONE"
    else
      say "WARN: DONE not seen within 180s — scoring anyway"
    fi
  fi

  sleep 2
  if score_logs "${app_pid}"; then
    say "RESULT=PASS"
    kill "${app_pid}" 2>/dev/null || killall LaughPlayer 2>/dev/null || true
    exit 0
  else
    say "RESULT=FAIL"
    kill "${app_pid}" 2>/dev/null || killall LaughPlayer 2>/dev/null || true
    exit 1
  fi
}

main "$@"
