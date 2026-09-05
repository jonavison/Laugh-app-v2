#!/usr/bin/env bash
# Format playback smoke test for LaughPlayer (direct / codec-capable build).
#
# Generates short synthetic fixtures (ffmpeg), opens each in the dev app, and
# asserts on playback traces (route + ready/started vs CompatibilityFailure).
#
# Usage:
#   ./scripts/format-smoke-test.sh              # generate + build + run all
#   ./scripts/format-smoke-test.sh --generate   # fixtures only
#   ./scripts/format-smoke-test.sh --probe-only # fixtures + remux/probe checks (no GUI)
#   ./scripts/format-smoke-test.sh --skip-build # reuse existing DevLaughPlayer.app
#   ./scripts/format-smoke-test.sh --timeout 25
#
# Exit: 0 if all cases pass; 1 if any fail; 2 on setup error.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

FIXTURE_DIR="${ROOT_DIR}/.build/format-fixtures"
REPORT_DIR="${ROOT_DIR}/.build/format-smoke"
APP_DIR="${ROOT_DIR}/.build/DevLaughPlayer.app"
APP_BIN="${APP_DIR}/Contents/MacOS/LaughPlayer"
BUNDLED_FFMPEG="${ROOT_DIR}/Sources/LaughPlayer/codec-tools/bin/ffmpeg"
HOST_FFMPEG="$(command -v ffmpeg || true)"

GENERATE_ONLY=false
PROBE_ONLY=false
SKIP_BUILD=false
TIMEOUT_SEC=20
SETTLE_SEC=1.2

for arg in "$@"; do
  case "${arg}" in
    --generate) GENERATE_ONLY=true ;;
    --probe-only) PROBE_ONLY=true ;;
    --skip-build) SKIP_BUILD=true ;;
    --timeout)
      shift_next=1
      ;;
    --timeout=*)
      TIMEOUT_SEC="${arg#--timeout=}"
      ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
  esac
done

# Support `--timeout N` (next argv).
args=("$@")
for i in "${!args[@]}"; do
  if [[ "${args[$i]}" == "--timeout" && $((i + 1)) -lt ${#args[@]} ]]; then
    TIMEOUT_SEC="${args[$((i + 1))]}"
  fi
done

mkdir -p "${FIXTURE_DIR}" "${REPORT_DIR}"

log()  { printf '[format-smoke] %s\n' "$*"; }
fail() { printf '[format-smoke] ERROR: %s\n' "$*" >&2; exit 2; }

pick_ffmpeg() {
  if [[ -x "${BUNDLED_FFMPEG}" ]]; then
    echo "${BUNDLED_FFMPEG}"
  elif [[ -n "${HOST_FFMPEG}" ]]; then
    echo "${HOST_FFMPEG}"
  else
    fail "ffmpeg not found (bundled or host)."
  fi
}

FFMPEG="$(pick_ffmpeg)"
log "Using ffmpeg: ${FFMPEG}"

# name|relative_path|ffmpeg_args|expected_route_substr|notes
# expected_route_substr matched against [DEBUG-route] line (native|remux|mpv) — empty = any success.
CASES=(
  "mp4_h264_aac|mp4_h264_aac.mp4|-c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 128k|native|Baseline MP4 H.264+AAC"
  "mov_h264_aac|mov_h264_aac.mov|-c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 128k|native|QuickTime H.264+AAC"
  "m4v_h264_aac|m4v_h264_aac.m4v|-c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 128k|native|M4V H.264+AAC"
  "mp4_hevc_aac|mp4_hevc_hvc1_aac.mp4|-c:v libx265 -tag:v hvc1 -pix_fmt yuv420p -c:a aac -b:a 128k|native|MP4 HEVC tagged hvc1"
  "mp4_hev1_aac|mp4_hev1_aac.mp4|-c:v libx265 -tag:v hev1 -pix_fmt yuv420p -c:a aac -b:a 128k|remux|MP4 HEVC hev1 (remux path)"
  "mkv_h264_aac|mkv_h264_aac.mkv|-c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 128k|remux|MKV H.264"
  "mkv_hevc10_aac|mkv_hevc10_aac.mkv|-c:v libx265 -pix_fmt yuv420p10le -c:a aac -b:a 128k|remux|MKV HEVC 10-bit (priority profile)"
  "webm_vp9_opus|webm_vp9_opus.webm|-c:v libvpx-vp9 -b:v 400k -c:a libopus -b:a 96k|remux|WebM VP9+Opus"
  "webm_av1_opus|webm_av1_opus.webm|-c:v libsvtav1 -b:v 400k -c:a libopus -b:a 96k|remux|WebM AV1+Opus"
  "avi_mpeg4_mp3|avi_mpeg4_mp3.avi|-c:v mpeg4 -q:v 5 -c:a libmp3lame -b:a 128k|remux|AVI MPEG-4+MP3"
  "mpegts_h264_aac|mpegts_h264_aac.ts|-c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 128k -f mpegts|remux|MPEG-TS"
  "flv_h264_aac|flv_h264_aac.flv|-c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 128k|remux|FLV"
  "3gp_h264_aac|3gp_h264_aac.3gp|-c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -c:a aac -b:a 96k -f 3gp|remux|3GP"
  "mpg_mpeg2_mp2|mpg_mpeg2_mp2.mpg|-c:v mpeg2video -q:v 5 -c:a mp2 -b:a 192k|remux|MPEG program stream"
)

generate_fixtures() {
  log "Generating fixtures → ${FIXTURE_DIR}"
  local name rel args expected notes out src_v src_a
  # Shared short test pattern + sine (2s).
  for entry in "${CASES[@]}"; do
    IFS='|' read -r name rel args expected notes <<<"${entry}"
    out="${FIXTURE_DIR}/${rel}"
    if [[ -f "${out}" && -s "${out}" ]]; then
      log "  skip (exists): ${rel}"
      continue
    fi
    log "  encode: ${rel} — ${notes}"
    # shellcheck disable=SC2086
    if ! "${FFMPEG}" -y -hide_banner -loglevel error \
      -f lavfi -i "testsrc2=size=640x360:rate=24:duration=2" \
      -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=2" \
      -shortest \
      ${args} \
      "${out}" 2>"${REPORT_DIR}/encode-${name}.err"; then
      log "  WARN: encode failed for ${name} (see encode-${name}.err) — skipping case"
      rm -f "${out}"
    fi
  done
}

probe_fixture() {
  local file="$1"
  "${FFMPEG}" -hide_banner -i "${file}" 2>&1 | head -40
}

# Remux/probe preflight without GUI — catches broken fixtures early.
run_probe_only() {
  local pass=0 failc=0 skip=0
  local report="${REPORT_DIR}/probe-report.txt"
  : >"${report}"
  log "Probe/remux preflight (no GUI)"
  for entry in "${CASES[@]}"; do
    IFS='|' read -r name rel args expected notes <<<"${entry}"
    local file="${FIXTURE_DIR}/${rel}"
    if [[ ! -f "${file}" ]]; then
      echo "SKIP ${name} (missing fixture)" | tee -a "${report}"
      skip=$((skip + 1))
      continue
    fi
    local probe_out="${REPORT_DIR}/probe-${name}.txt"
    if ! "${FFMPEG}" -hide_banner -i "${file}" -f null - 2>"${probe_out}"; then
      echo "FAIL ${name} ffmpeg cannot decode fixture" | tee -a "${report}"
      failc=$((failc + 1))
      continue
    fi
    # For remux-expected containers, exercise stream-copy remux like the app.
    if [[ "${expected}" == "remux" ]]; then
      local remux_out="${REPORT_DIR}/remux-${name}.mp4"
      if ! "${FFMPEG}" -y -hide_banner -loglevel error \
        -i "${file}" -c copy -movflags +faststart "${remux_out}" 2>>"${probe_out}"; then
        # Some codecs (vp9/av1/opus/theora) need limited remux or fail copy into mp4 — try video copy + aac.
        if ! "${FFMPEG}" -y -hide_banner -loglevel error \
          -i "${file}" -c:v copy -c:a aac -b:a 128k -movflags +faststart "${remux_out}" 2>>"${probe_out}"; then
          echo "WARN ${name} remux copy failed (app may still play via mpv/transcode)" | tee -a "${report}"
          # Still count as probe pass if source decodes.
        fi
      fi
    fi
    echo "PASS ${name} (${notes})" | tee -a "${report}"
    pass=$((pass + 1))
  done
  log "Probe summary: pass=${pass} fail=${failc} skip=${skip}"
  [[ "${failc}" -eq 0 ]]
}

ensure_app() {
  if [[ "${SKIP_BUILD}" == "true" && -x "${APP_BIN}" ]]; then
    log "Reusing existing app: ${APP_DIR}"
    return
  fi
  log "Bundling codec tools + assembling DevLaughPlayer.app"
  ./scripts/bundle-codec-tools.sh
  ./scripts/assemble-dev-app.sh debug
  [[ -x "${APP_BIN}" ]] || fail "Missing app binary: ${APP_BIN}"
}

kill_app() {
  killall LaughPlayer 2>/dev/null || true
  sleep 0.35
}

wait_for_log_line() {
  local log_file="$1"
  local pattern="$2"
  local timeout="$3"
  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    if grep -qE "${pattern}" "${log_file}" 2>/dev/null; then
      return 0
    fi
    sleep 0.15
  done
  return 1
}

# Slice of the log after a byte offset (robust vs mid-line CASE markers).
log_slice_from() {
  local log_file="$1"
  local offset="$2"
  if [[ ! -f "${log_file}" ]]; then
    echo ""
    return
  fi
  # dd skip is more reliable than line counts when stdout interleaves.
  dd if="${log_file}" bs=1 skip="${offset}" 2>/dev/null || true
}

# Run one GUI case in an isolated app process (avoids open-queue races).
# Uses Unified Logging (PlaybackTrace) because Swift print() is block-buffered when piped.
run_one_gui_case() {
  local name="$1"
  local file="$2"
  local expected="$3"
  local notes="$4"
  local master_log="$5"
  local base
  base="$(basename "${file}")"
  local case_log="${REPORT_DIR}/case-${name}.log"
  : >"${case_log}"

  kill_app

  # Stream PlaybackTrace (+ any [DEBUG- print bridged to unified log) for this case.
  /usr/bin/log stream --style compact --level debug --predicate \
    'subsystem == "com.laughplayer.dev"' \
    >"${case_log}" 2>&1 &
  local log_pid=$!
  if ! wait_for_log_line "${case_log}" 'Filtering the log data' 8; then
    sleep 0.8
  fi

  open "${APP_DIR}"
  # Wait until the app process is up (bundle launch).
  local launch_deadline=$((SECONDS + 25))
  while (( SECONDS < launch_deadline )); do
    if pgrep -x LaughPlayer >/dev/null 2>&1; then
      break
    fi
    sleep 0.15
  done
  if ! pgrep -x LaughPlayer >/dev/null 2>&1; then
    kill "${log_pid}" 2>/dev/null || true
    printf 'TIMEOUT\t%s\t\t?\t%s\tapp launch timeout\n' "${name}" "${notes}"
    cat "${case_log}" >>"${master_log}" 2>/dev/null || true
    return 1
  fi
  sleep 0.8

  printf '\n===CASE %s %s file=%s===\n' "${name}" "$(date +%s)" "${base}" >>"${case_log}"
  if ! open -b com.laughplayer.dev "${file}" 2>/dev/null; then
    open -a "${APP_DIR}" "${file}" || true
  fi

  local deadline=$((SECONDS + TIMEOUT_SEC))
  local status="TIMEOUT"
  local route_seen=""
  local audio_seen="?"
  local detail=""
  local saw_load=false

  while (( SECONDS < deadline )); do
    # Fresh case log per process — search the whole file (basename-scoped).
    local slice
    slice="$(tr -d '\r' <"${case_log}" 2>/dev/null || true)"

    if echo "${slice}" | grep -F "Loading video:" | grep -qF "${base}"; then
      saw_load=true
    fi
    if [[ "${saw_load}" != "true" ]]; then
      sleep 0.2
      continue
    fi

    local route_line
    route_line="$(echo "${slice}" | grep '\[DEBUG-route\]' | grep -F "${base}" | tail -1 || true)"
    if [[ -n "${route_line}" ]]; then
      route_seen="$(echo "${route_line}" | sed -E 's/.*\[DEBUG-route\] //; s/ path=.*//; s/ file=.*//')"
    fi

    if echo "${slice}" | grep '\[DEBUG-format\]' | grep -qF "${base}"; then
      local fmt
      fmt="$(echo "${slice}" | grep '\[DEBUG-format\]' | grep -F "${base}" | tail -1 || true)"
      if echo "${fmt}" | grep -qi 'audio=none'; then
        audio_seen="none"
      elif echo "${fmt}" | grep -qi 'audio='; then
        audio_seen="$(echo "${fmt}" | sed -E 's/.*audio=([^ ]+).*/\1/')"
      fi
    fi

    local after_load
    after_load="$(echo "${slice}" | awk -v f="${base}" '
      index($0, "Loading video:") && index($0, f) { hit=1 }
      hit { print }
    ')"

    local fail_line
    fail_line="$(echo "${after_load}" | grep -E 'CompatibilityFailure|native open failed|item failed before commit|item failed while waiting|timed out waiting for readyToPlay|\[DEBUG-mpv\] load failed|AVPlayerItem\.failed' | tail -1 || true)"
    if [[ -n "${fail_line}" ]]; then
      status="FAIL"
      detail="${fail_line}"
      break
    fi

    if echo "${after_load}" | grep -Eq '\[DEBUG-playback\] Ready to play|\[DEBUG-mpv\] playback started|\[DEBUG-playback\] start_play'; then
      status="PASS"
      detail="$(echo "${after_load}" | grep -E 'Ready to play|playback started|start_play' | tail -1)"
      sleep "${SETTLE_SEC}"
      slice="$(tr -d '\r' <"${case_log}" 2>/dev/null || true)"
      after_load="$(echo "${slice}" | awk -v f="${base}" '
        index($0, "Loading video:") && index($0, f) { hit=1 }
        hit { print }
      ')"
      if echo "${after_load}" | grep -Eq 'CompatibilityFailure|AVPlayerItem\.failed'; then
        status="FAIL"
        detail="$(echo "${after_load}" | grep -E 'CompatibilityFailure|AVPlayerItem\.failed' | tail -1)"
      elif echo "${after_load}" | grep -q 'start_play'; then
        detail="$(echo "${after_load}" | grep 'start_play' | tail -1)"
      fi
      route_line="$(echo "${slice}" | grep '\[DEBUG-route\]' | grep -F "${base}" | tail -1 || true)"
      if [[ -n "${route_line}" ]]; then
        route_seen="$(echo "${route_line}" | sed -E 's/.*\[DEBUG-route\] //; s/ path=.*//; s/ file=.*//')"
      fi
      if echo "${slice}" | grep '\[DEBUG-format\]' | grep -qF "${base}"; then
        fmt="$(echo "${slice}" | grep '\[DEBUG-format\]' | grep -F "${base}" | tail -1 || true)"
        if echo "${fmt}" | grep -qi 'audio=none'; then
          audio_seen="none"
        elif echo "${fmt}" | grep -qi 'audio='; then
          audio_seen="$(echo "${fmt}" | sed -E 's/.*audio=([^ ]+).*/\1/')"
        fi
      fi
      break
    fi
    sleep 0.2
  done

  kill "${log_pid}" 2>/dev/null || true
  wait "${log_pid}" 2>/dev/null || true
  kill_app

  {
    echo
    echo "----- ${name} (${status}) -----"
    cat "${case_log}"
  } >>"${master_log}"

  if [[ "${status}" == "TIMEOUT" && "${saw_load}" != "true" ]]; then
    detail="never saw Loading video for ${base}"
  fi

  if [[ "${status}" == "PASS" && -n "${expected}" ]]; then
    case "${expected}" in
      native)
        if ! echo "${route_seen}" | grep -qi 'planned native'; then
          detail="${detail} | route=${route_seen:-none} (wanted native)"
        fi
        ;;
      remux)
        if ! echo "${route_seen}" | grep -qi 'planned remux\|planned mpv\|forced mpv'; then
          detail="${detail} | route=${route_seen:-none} (wanted remux/mpv)"
        fi
        ;;
    esac
  fi

  if [[ "${status}" == "PASS" && "${audio_seen}" == "none" ]]; then
    status="FAIL"
    detail="${detail} | audio track missing"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${status}" "${name}" "${route_seen}" "${audio_seen}" "${notes}" "${detail}"
  [[ "${status}" == "PASS" ]]
}

run_gui_smoke() {
  local master_log="${REPORT_DIR}/app-stderr.log"
  local summary="${REPORT_DIR}/summary.txt"
  local results_tsv="${REPORT_DIR}/results.tsv"
  : >"${master_log}"
  : >"${summary}"
  printf 'status\tname\troute\taudio\tnotes\tdetail\n' >"${results_tsv}"

  local pass=0 failc=0 skip=0
  for entry in "${CASES[@]}"; do
    IFS='|' read -r name rel args expected notes <<<"${entry}"
    local file="${FIXTURE_DIR}/${rel}"
    if [[ ! -f "${file}" ]]; then
      log "SKIP ${name} (no fixture)"
      echo "SKIP ${name}" >>"${summary}"
      printf 'SKIP\t%s\t\t\t%s\tmissing fixture\n' "${name}" "${notes}" >>"${results_tsv}"
      skip=$((skip + 1))
      continue
    fi

    log "Open ${rel} (expect route~${expected:-any}) [isolated process]"
    local row
    if row="$(run_one_gui_case "${name}" "${file}" "${expected}" "${notes}" "${master_log}")"; then
      pass=$((pass + 1))
      log "  PASS ${name} $(echo "${row}" | cut -f3,4 | tr '\t' ' ')"
      echo "PASS ${name} — ${notes}" >>"${summary}"
    else
      failc=$((failc + 1))
      local st
      st="$(echo "${row}" | cut -f1)"
      log "  ${st:-FAIL} ${name}: $(echo "${row}" | cut -f6)"
      echo "${st:-FAIL} ${name}: $(echo "${row}" | cut -f6)" >>"${summary}"
    fi
    echo "${row}" >>"${results_tsv}"
  done

  kill_app

  {
    echo
    echo "======== SUMMARY ========"
    echo "pass=${pass} fail=${failc} skip=${skip}"
    echo "report: ${summary}"
    echo "log:    ${master_log}"
    echo "tsv:    ${results_tsv}"
  } | tee -a "${summary}"

  [[ "${failc}" -eq 0 ]]
}

# --- main ---
generate_fixtures

if [[ "${GENERATE_ONLY}" == "true" ]]; then
  log "Fixtures ready in ${FIXTURE_DIR}"
  exit 0
fi

if [[ "${PROBE_ONLY}" == "true" ]]; then
  run_probe_only
  exit $?
fi

ensure_app
# Always run decode/remux preflight first (fast fail).
run_probe_only || log "WARN: probe preflight had failures (continuing GUI smoke)"
run_gui_smoke
exit $?
