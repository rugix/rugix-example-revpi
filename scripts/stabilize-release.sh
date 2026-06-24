#!/usr/bin/env bash
#
# Promote the latest build for this branch to a stable Nexigon tag.
#
# Usage:
#   ./scripts/stabilize-release.sh

set -euo pipefail

# shellcheck source=/dev/null
. .env

if [ -z "${NEXIGON_REPOSITORY:-}" ]; then
    echo "[ERROR] NEXIGON_REPOSITORY is not set"
    exit 1
fi

if [ -z "${NEXIGON_PACKAGE:-}" ]; then
    echo "[ERROR] NEXIGON_PACKAGE is not set"
    exit 1
fi

if [ ! -f .release-env ]; then
    echo "[ERROR] .release-env not found; run ./scripts/prepare-release.sh first"
    exit 1
fi

# shellcheck source=/dev/null
. .release-env

NEXIGON_CLI="${NEXIGON_CLI:-nexigon-cli}"
STABLE_TAG=${STABLE_TAG:-"stable"}
PACKAGE_PATH="$NEXIGON_REPOSITORY/$NEXIGON_PACKAGE"

$NEXIGON_CLI repositories versions tag "$PACKAGE_PATH/$FLOATING_TAG" --tag "${STABLE_TAG},reassign"
