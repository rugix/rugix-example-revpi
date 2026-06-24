#!/usr/bin/env bash
#
# Build system images and update bundles with the version pinned by
# prepare-release.sh.
#
# Usage:
#   ./scripts/build-release.sh <system> [<system> ...]

set -euo pipefail

if [ ! -f .release-env ]; then
    echo "[ERROR] .release-env not found; run ./scripts/prepare-release.sh first"
    exit 1
fi

# shellcheck source=/dev/null
. .release-env

if [ $# -eq 0 ]; then
    echo "[ERROR] no systems specified"
    echo "usage: $0 <system> [<system> ...]"
    exit 1
fi

for system in "$@"; do
    echo "[INFO] building image for '$system' (version: $VERSION)"
    ./run-bakery bake image "$system" --release-version "$VERSION" --enable-mixin nexigon
    echo "[INFO] building bundle for '$system' (version: $VERSION)"
    ./run-bakery bake bundle "$system" --release-version "$VERSION" --enable-mixin nexigon
    IMG_PATH="build/$system/system.img"
    if [ -e "$IMG_PATH" ]; then
        echo "[INFO] compressing '$system' image"
        xz -T0 -f "$IMG_PATH"
    fi
done
