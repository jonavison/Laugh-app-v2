#!/usr/bin/env bash
# In-app seek stress (LAUGH_SEEK_STRESS=1). No Accessibility / osascript required.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${ROOT_DIR}/.build/DevLaughPlayer.app"
BIN="${APP}/Contents/MacOS/LaughPlayer"
MEDIA="${MEDIA_PATH:-/Users/wizmac/Downloads/The Jason Bourne Collection 2004-2016 1080p BluRay HEVC x265 5.1 BONE/The Bourne Identity 2002 1080p BluRay HEVC x265 5.1 BONE.mkv}"
RUN_ID="${1:-$(date +%Y%m%d-%H%M%S)}"
LOG_DIR="${ROOT_DIR}/.build/seek-stress"
mkdir -p "${LOG_DIR}"
REPORT="${LOG_DIR}/report-${RUN_ID}.txt"
START_EPOCH="$(date +%s)"
START_ISO="$(date -r "${START_EPOCH}" '+%Y-%m-%d %H:%M:%S')"

say() { echo "$*" | tee -a "${REPORT}"; }

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

# Wait until current PID emits needle after START_ISO (avoids stale prior-run matches).
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
    # Process died early?
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

  local freezes stuck ok_playing done_line rate1
  freezes=$(grep -c 'freeze_watchdog detected' "${dump}" || true)
  stuck=$(grep -c 'FAIL stuck-paused' "${dump}" || true)
  ok_playing=$(grep -c 'OK playing after' "${dump}" || true)
  done_line=$(grep -c '\[DEBUG-seekstress\] DONE' "${dump}" || true)
  rate1=$(grep -c 'rate=1.00' "${dump}" || true)

  say "=== SCORE run=${RUN_ID} pid=${pid} ==="
  say "freeze_detected=${freezes} stuck_paused=${stuck} ok_playing=${ok_playing} done=${done_line} rate1_lines=${rate1}"
  say "log_dump=${dump}"

  if (( freezes > 0 )); then say "FAIL: freeze_watchdog detections"; return 1; fi
  if (( stuck > 0 )); then say "FAIL: stuck paused after seek burst"; return 1; fi
  if (( done_line < 1 )); then say "FAIL: harness did not finish"; return 1; fi
  if (( ok_playing < 3 )); then say "FAIL: too few OK playing checkpoints (${ok_playing})"; return 1; fi
  say "PASS: seek stress clean"
  return 0
}

main() {
  : >"${REPORT}"
  say "=== in-app seek stress ${RUN_ID} start $(date) ==="
  say "media=${MEDIA}"

  (cd "${ROOT_DIR}" && ./scripts/assemble-dev-app.sh debug) >/dev/null
  say "app assembled"

  if [[ ! -f "${MEDIA}" ]]; then
    say "FAIL: media missing"
    exit 2
  fi

  killall LaughPlayer 2>/dev/null || true
  sleep 0.5

  LAUGH_SEEK_STRESS=1 "${BIN}" "${MEDIA}" >/dev/null 2>&1 &
  local app_pid=$!
  # Refresh start bound after launch so we don't race the binary boot.
  START_EPOCH="$(date +%s)"
  START_ISO="$(date -r "${START_EPOCH}" '+%Y-%m-%d %H:%M:%S')"
  say "launched pid=${app_pid} start=${START_ISO}"
  sleep 1.5
  dismiss_tcc_and_allow

  if wait_for_pid_log "${app_pid}" "Ready to play" 60; then
    say "Ready to play observed"
  else
    say "WARN: Ready to play not seen"
  fi

  if wait_for_pid_log "${app_pid}" "[DEBUG-seekstress] starting" 45; then
    say "Harness started"
  else
    say "FAIL: harness did not start"
    kill "${app_pid}" 2>/dev/null || killall LaughPlayer 2>/dev/null || true
    exit 1
  fi

  if wait_for_pid_log "${app_pid}" "[DEBUG-seekstress] DONE" 180; then
    say "Harness DONE"
  else
    say "WARN: DONE not seen within 180s — scoring anyway"
  fi

  sleep 2
  if score_logs "${app_pid}"; then
    say "RESULT=PASS"
    exit 0
  else
    say "RESULT=FAIL"
    exit 1
  fi
}

main "$@"
