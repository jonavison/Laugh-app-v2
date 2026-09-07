#!/usr/bin/env bash
# Stress + performance run for smart selection (Vision person).
# Usage: ./scripts/stress-selection.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

LOG_DIR="${ROOT_DIR}/.tmp"
mkdir -p "${LOG_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="${LOG_DIR}/selection-stress-${STAMP}.log"

echo "=== Selection stress ${STAMP} ===" | tee "${LOG}"
echo "Host: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)" | tee -a "${LOG}"
echo "Fixtures:" | tee -a "${LOG}"
ls -lh Tests/LaughPlayerTests/Fixtures/Selection | tee -a "${LOG}"
echo | tee -a "${LOG}"

echo "--- Unit (ImageSelectionTests) ---" | tee -a "${LOG}"
./scripts/test.sh --filter ImageSelectionTests 2>&1 | tee -a "${LOG}"

echo | tee -a "${LOG}"
echo "--- Stress (ImageSelectionStressTests) ---" | tee -a "${LOG}"
./scripts/test.sh --filter ImageSelectionStressTests 2>&1 | tee -a "${LOG}"

echo | tee -a "${LOG}"
echo "--- Extended (ImageSelectionExtendedTests) ---" | tee -a "${LOG}"
./scripts/test.sh --filter ImageSelectionExtendedTests 2>&1 | tee -a "${LOG}"

echo | tee -a "${LOG}"
echo "--- Perf / ext lines ---" | tee -a "${LOG}"
grep -E '\[SEL-PERF\]|\[SEL-EXT\]' "${LOG}" | tee "${LOG_DIR}/selection-perf-${STAMP}.txt" || echo "(no SEL lines)" | tee -a "${LOG}"

if [[ -d "${ROOT_DIR}/.tmp/selection-artifacts" ]]; then
  echo | tee -a "${LOG}"
  echo "Artifacts:" | tee -a "${LOG}"
  ls -lh "${ROOT_DIR}/.tmp/selection-artifacts" | tee -a "${LOG}"
fi

echo | tee -a "${LOG}"
echo "Log: ${LOG}"
echo "Perf extract: ${LOG_DIR}/selection-perf-${STAMP}.txt"
