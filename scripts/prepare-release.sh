#!/usr/bin/env bash
#
# Prepare a Nexigon release and pin its version for build and upload steps.
#
# Usage:
#   ./scripts/prepare-release.sh

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

NEXIGON_CLI="${NEXIGON_CLI:-nexigon-cli}"

TIMESTAMP=$(date +"%Y%m%d%H%M%S")
GIT_COMMIT=$(git rev-parse --short HEAD)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

BUILD_TAG=${BUILD_TAG:-"build-${TIMESTAMP}-${GIT_COMMIT}"}
FLOATING_TAG=${FLOATING_TAG:-"latest-build-${GIT_BRANCH//\//-}"}

VERSION="$BUILD_TAG"

PACKAGE_PATH="$NEXIGON_REPOSITORY/$NEXIGON_PACKAGE"
VERSION_PATH="$PACKAGE_PATH/$BUILD_TAG"

BUILD_VERSION_INFO=$($NEXIGON_CLI repositories versions resolve "$VERSION_PATH")
if [ "$(echo "$BUILD_VERSION_INFO" | jq -r '.result')" = "Found" ]; then
    echo "[INFO] build version already exists, reusing it"
    VERSION_ID=$(echo "$BUILD_VERSION_INFO" | jq -r '.versionId')
else
    echo "[INFO] creating build version"
    VERSION_METADATA=$(jq -nc --arg version "$VERSION" '{imageVersion: $version}')
    VERSION_ID=$($NEXIGON_CLI repositories versions create "$PACKAGE_PATH" \
        --tag "$BUILD_TAG,locked" --tag "$FLOATING_TAG,reassign" \
        --metadata "$VERSION_METADATA" | jq -r '.versionId')
fi

echo "[INFO] BUILD_TAG=$BUILD_TAG"
echo "[INFO] VERSION=$VERSION"
echo "[INFO] VERSION_ID=$VERSION_ID"

cat > .release-env <<EOF
BUILD_TAG=$BUILD_TAG
FLOATING_TAG=$FLOATING_TAG
VERSION=$VERSION
VERSION_ID=$VERSION_ID
EOF

echo "[INFO] wrote .release-env"
