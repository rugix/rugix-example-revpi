#!/usr/bin/env bash
#
# Run a system image in QEMU with the version pinned by prepare-release.sh.
#
# Usage:
#   ./scripts/run-release.sh <system>

set -euo pipefail

if [ ! -f .release-env ]; then
    echo "[ERROR] .release-env not found; run ./scripts/prepare-release.sh first"
    exit 1
fi

# shellcheck source=/dev/null
. .release-env

if [ $# -ne 1 ]; then
    echo "[ERROR] expected exactly one system"
    echo "usage: $0 <system>"
    exit 1
fi

system="$1"

echo "[INFO] running '$system' (version: $VERSION)"
./run-bakery run "$system" --release-version "$VERSION"
