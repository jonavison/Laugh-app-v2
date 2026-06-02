#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[build-direct] Building direct distribution (bundled codec capable)..."
./scripts/bundle-codec-tools.sh
./scripts/swift-build.sh release

echo "[build-direct] Done."
echo "Binary: .build/arm64-apple-macosx/release/LaughPlayer"
