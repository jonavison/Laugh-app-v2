#!/usr/bin/env bash
# W3-08e selection measurement harness.
# Usage:
#   ./scripts/measure-selection.sh              # Vision baseline (no network)
#   ./scripts/measure-selection.sh mobilesam    # MobileSAM if weights already cached
#
# Re-run for a new SelectionProvider conformer:
#   1. Add a case in SelectionMeasurementTests (or pass provider in a new test)
#   2. ./scripts/measure-selection.sh
#   3. Diff [SEL-MEASURE] summary lines (personCov / soft / personMs / negFP)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

PROVIDER="${1:-vision}"
LOG_DIR="${ROOT_DIR}/.tmp"
mkdir -p "${LOG_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="${LOG_DIR}/selection-measure-${STAMP}.log"

echo "=== Selection measure provider=${PROVIDER} ${STAMP} ===" | tee "${LOG}"

FILTER="SelectionMeasurementTests"
case "${PROVIDER}" in
  vision)
    FILTER="SelectionMeasurementTests/testVisionProviderMeasurementSummary"
    ;;
  mobilesam|sam)
    FILTER="SelectionMeasurementTests/testMobileSAMMeasurementWhenCached"
    ;;
  all)
    FILTER="SelectionMeasurementTests"
    ;;
  *)
    echo "Unknown provider '${PROVIDER}' (vision|mobilesam|all)" | tee -a "${LOG}"
    exit 2
    ;;
esac

if [[ -x "${ROOT_DIR}/scripts/test.sh" ]]; then
  ./scripts/test.sh --filter "${FILTER}" 2>&1 | tee -a "${LOG}"
else
  swift test --filter "${FILTER}" 2>&1 | tee -a "${LOG}"
fi

echo | tee -a "${LOG}"
echo "--- Comparable lines ---" | tee -a "${LOG}"
grep -E '\[SEL-MEASURE\]' "${LOG}" | tee "${LOG_DIR}/selection-measure-${STAMP}.txt" || {
  echo "(no SEL-MEASURE lines — check filter / skip)" | tee -a "${LOG}"
}

echo | tee -a "${LOG}"
echo "Log: ${LOG}"
echo "Extract: ${LOG_DIR}/selection-measure-${STAMP}.txt"
