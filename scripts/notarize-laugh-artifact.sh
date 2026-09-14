#!/usr/bin/env bash
# Submit a signed artifact to Apple notarization and staple the ticket.
#
# Usage:
#   ./scripts/notarize-laugh-artifact.sh <LaughPlayer.app|*.zip|*.dmg>
#
# Environment:
#   LAUGH_NOTARY_PROFILE   notarytool keychain profile (required)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/release-common.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <LaughPlayer.app|*.zip|*.dmg>" >&2
  exit 1
fi

ARTIFACT="$1"
if [[ ! -e "$ARTIFACT" ]]; then
  echo "Artifact not found: $ARTIFACT" >&2
  exit 1
fi

release_common_init
require_notary_profile

SUBMIT_PATH="$ARTIFACT"
STAPLE_TARGET="$ARTIFACT"
WORK_DIR="$ROOT/.build/notarize"
ZIP_PATH=""

cleanup() {
  if [[ -n "$ZIP_PATH" && -f "$ZIP_PATH" ]]; then
    rm -f "$ZIP_PATH"
  fi
}
trap cleanup EXIT

if [[ "$ARTIFACT" == *.app ]]; then
  mkdir -p "$WORK_DIR"
  ZIP_PATH="$WORK_DIR/$(basename "$ARTIFACT" .app).zip"
  echo "==> Zip app for notarization: $ZIP_PATH"
  ditto -c -k --keepParent "$ARTIFACT" "$ZIP_PATH"
  SUBMIT_PATH="$ZIP_PATH"
  STAPLE_TARGET="$ARTIFACT"
fi

echo "==> notarytool submit ($LAUGH_NOTARY_PROFILE)"
SUBMIT_OUTPUT="$(xcrun notarytool submit "$SUBMIT_PATH" \
  --keychain-profile "$LAUGH_NOTARY_PROFILE" 2>&1)"
printf '%s\n' "$SUBMIT_OUTPUT"

SUBMISSION_ID="$(printf '%s\n' "$SUBMIT_OUTPUT" | awk '/^  id: / { print $2; exit }')"
if [[ -z "$SUBMISSION_ID" ]]; then
  echo "Could not parse notarization submission id." >&2
  exit 1
fi

echo "==> Waiting for Apple notarization (submission $SUBMISSION_ID)"
NOTARY_TIMEOUT_SEC="${LAUGH_NOTARY_TIMEOUT_SEC:-1200}"
NOTARY_POLL_SEC="${LAUGH_NOTARY_POLL_SEC:-30}"
deadline=$((SECONDS + NOTARY_TIMEOUT_SEC))
STATUS=""

while (( SECONDS < deadline )); do
  INFO="$(xcrun notarytool info "$SUBMISSION_ID" --keychain-profile "$LAUGH_NOTARY_PROFILE" 2>&1)"
  STATUS="$(printf '%s\n' "$INFO" | awk -F': ' '/^  status: / { print $2; exit }')"
  printf '    status: %s\n' "${STATUS:-unknown}"

  case "$STATUS" in
    Accepted)
      break
      ;;
    Invalid|Rejected)
      echo "Notarization failed ($STATUS)." >&2
      xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$LAUGH_NOTARY_PROFILE" >&2 || true
      exit 1
      ;;
  esac
  sleep "$NOTARY_POLL_SEC"
done

if [[ "${STATUS:-}" != "Accepted" ]]; then
  echo "Notarization still in progress after ${NOTARY_TIMEOUT_SEC}s." >&2
  echo "Check later:" >&2
  echo "  xcrun notarytool info $SUBMISSION_ID --keychain-profile $LAUGH_NOTARY_PROFILE" >&2
  echo "Then staple:" >&2
  echo "  xcrun stapler staple \"$STAPLE_TARGET\"" >&2
  exit 1
fi

if [[ "$STAPLE_TARGET" == *.app ]]; then
  echo "==> stapler staple app"
  xcrun stapler staple "$STAPLE_TARGET"
  verify_signed_app "$STAPLE_TARGET"
elif [[ "$STAPLE_TARGET" == *.dmg ]]; then
  echo "==> stapler staple dmg"
  xcrun stapler staple "$STAPLE_TARGET"
  echo "==> spctl assess dmg"
  spctl -a -t open --context context:primary-signature -v "$STAPLE_TARGET" || true
else
  echo "Submitted $SUBMIT_PATH (no stapling for zip-only artifacts)." >&2
fi

echo "Done: notarized $ARTIFACT"
