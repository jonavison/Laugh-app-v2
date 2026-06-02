#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[build-appstore] Building App Store compatible distribution (native decoder only)..."
swift build -c release -Xswiftc -DAPP_STORE_BUILD -Xswiftc -DNO_BUNDLED_CODECS

echo "[build-appstore] Done."
echo "Binary: .build/release/LaughPlayer"
