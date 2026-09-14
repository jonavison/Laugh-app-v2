#!/usr/bin/env bash
# One-time Sparkle Ed25519 key setup for LaughPlayer.
#
# Creates a Keychain signing key (default) and writes the public key to
# Packaging/sparkle/public-ed-key.txt (safe to commit).
#
# Optional export for CI or another Mac:
#   LAUGH_SPARKLE_EXPORT_PRIVATE_KEY=1 ./scripts/sparkle-generate-keys.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/sparkle-common.sh"

ensure_sparkle_artifacts

PUBLIC_OUT="$ROOT/Packaging/sparkle/public-ed-key.txt"
PRIVATE_OUT="$ROOT/Packaging/sparkle/ed25519-private-key.pem"
mkdir -p "$(dirname "$PUBLIC_OUT")"

if ! "$SPARKLE_BIN/generate_keys" -p >/dev/null 2>&1; then
  echo "==> Generate Sparkle Ed25519 key (Keychain)"
  "$SPARKLE_BIN/generate_keys"
else
  echo "==> Sparkle key already in Keychain; printing public key"
fi

PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" -p | tr -d '[:space:]')"
if [[ -z "$PUBLIC_KEY" ]]; then
  echo "Failed to read Sparkle public key." >&2
  exit 1
fi

printf '%s\n' "$PUBLIC_KEY" >"$PUBLIC_OUT"
echo "Wrote public key: $PUBLIC_OUT"
echo "Commit this file. Keep the Keychain private key on this Mac."

if [[ "${LAUGH_SPARKLE_EXPORT_PRIVATE_KEY:-0}" == "1" ]]; then
  "$SPARKLE_BIN/generate_keys" -x "$PRIVATE_OUT"
  echo "Exported private key: $PRIVATE_OUT (gitignored — store securely)"
  echo "Set LAUGH_SPARKLE_PRIVATE_KEY_FILE in Packaging/release-env.local for sign_update."
fi

echo ""
echo "Feed URL default: https://avison-soft.com/laugh/appcast.xml"
echo "Override with LAUGH_SPARKLE_FEED_URL in release-env.local if needed."
