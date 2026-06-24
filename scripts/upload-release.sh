#!/usr/bin/env bash
#
# Upload build artifacts to Nexigon Hub for the version pinned by
# prepare-release.sh.
#
# Usage:
#   ./scripts/upload-release.sh

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

if [ -z "${VERSION_ID:-}" ]; then
    PACKAGE_PATH="$NEXIGON_REPOSITORY/$NEXIGON_PACKAGE"
    VERSION_PATH="$PACKAGE_PATH/$BUILD_TAG"
    BUILD_VERSION_INFO=$($NEXIGON_CLI repositories versions resolve "$VERSION_PATH")
    if [ "$(echo "$BUILD_VERSION_INFO" | jq -r '.result')" = "Found" ]; then
        VERSION_ID=$(echo "$BUILD_VERSION_INFO" | jq -r '.versionId')
    else
        echo "[ERROR] version '$BUILD_TAG' not found; run ./scripts/prepare-release.sh first"
        exit 1
    fi
fi

echo "[INFO] uploading to version $VERSION_ID (tag: $BUILD_TAG)"

for build_dir in build/*; do
    SYSTEM_NAME=$(basename "$build_dir")
    IMG_PATH="$build_dir/system.img"
    BUNDLE_PATH="$build_dir/system.rugixb"
    BUNDLE_HASH_PATH="$build_dir/system.rugixb-hash"
    SBOM_PATH="$build_dir/sbom.cdx.json"
    INFO_PATH="$build_dir/system-build-info.json"
    if [ ! -e "$IMG_PATH.xz" ] && [ ! -e "$BUNDLE_PATH" ]; then
        echo "[WARN] skipping '$SYSTEM_NAME', no image or bundle found"
        continue
    fi
    if [ ! -e "$INFO_PATH" ]; then
        echo "[ERROR] build info not found for '$SYSTEM_NAME' at $INFO_PATH"
        exit 1
    fi
    BAKED_VERSION=$(jq -r '.release.version' "$INFO_PATH")
    if [ "$BAKED_VERSION" != "$VERSION" ]; then
        echo "[ERROR] version mismatch for '$SYSTEM_NAME': build info has '$BAKED_VERSION' but .release-env has '$VERSION'"
        echo "[ERROR] the image was likely built with a different version; rebuild with ./scripts/build-release.sh"
        exit 1
    fi
    SBOM_FILENAME="$SYSTEM_NAME.cdx.json"
    if [ -e "$IMG_PATH.xz" ]; then
        echo "[INFO] uploading '$SYSTEM_NAME' image"
        asset_info=$($NEXIGON_CLI repositories assets upload "$NEXIGON_REPOSITORY" "$IMG_PATH.xz")
        asset_id=$(echo "$asset_info" | jq -r '.assetId')
        img_metadata=$(jq -nc --arg sbom "$SBOM_FILENAME" '{relations: {sbom: [$sbom]}}')
        $NEXIGON_CLI repositories versions assets add "$VERSION_ID" "$asset_id" "$SYSTEM_NAME.img.xz" \
            --metadata "$img_metadata"
    fi
    BUNDLE_HASH=""
    if [ -e "$BUNDLE_HASH_PATH" ]; then
        BUNDLE_HASH=$(cat "$BUNDLE_HASH_PATH")
    fi
    if [ -e "$BUNDLE_PATH" ]; then
        echo "[INFO] uploading '$SYSTEM_NAME' bundle"
        asset_info=$($NEXIGON_CLI repositories assets upload "$NEXIGON_REPOSITORY" "$BUNDLE_PATH")
        asset_id=$(echo "$asset_info" | jq -r '.assetId')
        bundle_metadata=$(jq -nc \
            --arg bundleHash "$BUNDLE_HASH" \
            --arg version "$VERSION" \
            --arg sbom "$SBOM_FILENAME" \
            '{rugix: {bundleHash: $bundleHash}, relations: {sbom: [$sbom]}, version: $version}')
        $NEXIGON_CLI repositories versions assets add "$VERSION_ID" "$asset_id" "$SYSTEM_NAME.rugixb" \
            --metadata "$bundle_metadata"
    fi
    if [ -e "$BUNDLE_HASH_PATH" ]; then
        echo "[INFO] uploading '$SYSTEM_NAME' bundle hash"
        asset_info=$($NEXIGON_CLI repositories assets upload "$NEXIGON_REPOSITORY" "$BUNDLE_HASH_PATH")
        asset_id=$(echo "$asset_info" | jq -r '.assetId')
        $NEXIGON_CLI repositories versions assets add "$VERSION_ID" "$asset_id" "$SYSTEM_NAME.rugixb-hash"
    fi
    if [ -e "$SBOM_PATH" ]; then
        echo "[INFO] uploading '$SYSTEM_NAME' SBOM"
        asset_info=$($NEXIGON_CLI repositories assets upload "$NEXIGON_REPOSITORY" "$SBOM_PATH")
        asset_id=$(echo "$asset_info" | jq -r '.assetId')
        $NEXIGON_CLI repositories versions assets add "$VERSION_ID" "$asset_id" "$SBOM_FILENAME"
    fi
    if [ -e "$INFO_PATH" ]; then
        echo "[INFO] uploading '$SYSTEM_NAME' build info"
        asset_info=$($NEXIGON_CLI repositories assets upload "$NEXIGON_REPOSITORY" "$INFO_PATH")
        asset_id=$(echo "$asset_info" | jq -r '.assetId')
        $NEXIGON_CLI repositories versions assets add "$VERSION_ID" "$asset_id" "$SYSTEM_NAME.build-info.json"
    fi
done
