#!/usr/bin/env bash

set -euo pipefail

NEXIGON_CLI=${NEXIGON_CLI:-nexigon-cli}
NEXIGON_OS_PACKAGE=${NEXIGON_OS_PACKAGE:-revpi-os}
NEXIGON_APP_PACKAGE=${NEXIGON_APP_PACKAGE:-example-app}
ARTIFACT_DIR=${ARTIFACT_DIR:-dist}

require_variable() {
    if [ -z "${!1:-}" ]; then
        echo "[ERROR] $1 is not set" >&2
        exit 1
    fi
}

run_cli() {
    if [ -n "${NEXIGON_CLI_CONFIG:-}" ]; then
        "$NEXIGON_CLI" --config "$NEXIGON_CLI_CONFIG" "$@"
    else
        "$NEXIGON_CLI" "$@"
    fi
}

resolve_or_create_version() {
    local package_name="$1"
    local metadata="$2"
    local package_path="$NEXIGON_REPOSITORY/$package_name"
    local version_info result

    version_info=$(run_cli repositories versions resolve "$package_path/$BUILD_TAG")
    result=$(jq -er '.result' <<<"$version_info")
    case "$result" in
        Found)
            jq -er '.versionId | select(type == "string" and length > 0)' \
                <<<"$version_info"
            ;;
        NotFound)
            run_cli repositories versions create "$package_path" \
                --tag "$BUILD_TAG,locked" \
                --metadata "$metadata" \
                | jq -er '.versionId | select(type == "string" and length > 0)'
            ;;
        *)
            echo "[ERROR] unable to resolve '$package_path/$BUILD_TAG'" >&2
            exit 1
            ;;
    esac
}

asset_metadata() {
    local package_kind="$1"
    local asset_path="$2"
    local filename="$3"
    local bundle_hash sbom_filename sbom_path system_name

    if [[ "$filename" == *.rugixb ]]; then
        if [ ! -f "$asset_path-hash" ]; then
            echo "[ERROR] bundle hash for '$filename' is missing" >&2
            exit 1
        fi
        bundle_hash=$(tr -d '\r\n' <"$asset_path-hash")
        if [ -z "$bundle_hash" ]; then
            echo "[ERROR] bundle hash for '$filename' is empty" >&2
            exit 1
        fi
        if [ "$package_kind" = os ]; then
            system_name=${filename%.rugixb}
            sbom_filename="$system_name.spdx.json"
            sbom_path="$(dirname "$asset_path")/$sbom_filename"
            if [ ! -f "$sbom_path" ]; then
                echo "[ERROR] SBOM for '$filename' is missing" >&2
                exit 1
            fi
            jq -nc \
                --arg bundle_hash "$bundle_hash" \
                --arg sbom "$sbom_filename" \
                --arg version "$BUILD_TAG" \
                '{rugix: {bundleHash: $bundle_hash}, relations: {sbom: [$sbom]}, version: $version}'
        else
            jq -nc \
                --arg bundle_hash "$bundle_hash" \
                --arg version "$BUILD_TAG" \
                '{rugix: {bundleHash: $bundle_hash}, version: $version}'
        fi
    elif [ "$package_kind" = os ] && [[ "$filename" == *.img.zst ]]; then
        system_name=${filename%.img.zst}
        sbom_filename="$system_name.spdx.json"
        sbom_path="$(dirname "$asset_path")/$sbom_filename"
        if [ ! -f "$sbom_path" ]; then
            echo "[ERROR] SBOM for '$filename' is missing" >&2
            exit 1
        fi
        jq -nc --arg sbom "$sbom_filename" '{relations: {sbom: [$sbom]}}'
    fi
}

validate_package_assets() {
    local package_kind="$1"
    local assets_name="$2"
    local -n assets_ref="$assets_name"
    local asset_path filename
    local -A filenames=()

    for asset_path in "${assets_ref[@]}"; do
        filename=$(basename "$asset_path")
        if [ -n "${filenames[$filename]:-}" ]; then
            echo "[ERROR] duplicate asset filename '$filename'" >&2
            exit 1
        fi
        filenames["$filename"]=1
        asset_metadata "$package_kind" "$asset_path" "$filename" >/dev/null
    done
}

upload_package_assets() {
    local version_id="$1"
    local package_kind="$2"
    local assets_name="$3"
    local -n assets_ref="$assets_name"
    local asset_id asset_info asset_path filename metadata version_info
    local -A attached=()

    version_info=$(run_cli repositories versions info "$version_id")
    while IFS= read -r filename; do
        attached["$filename"]=1
    done < <(jq -r '.assets[]?.filename' <<<"$version_info")

    for asset_path in "${assets_ref[@]}"; do
        filename=$(basename "$asset_path")
        if [ -n "${attached[$filename]:-}" ]; then
            echo "[INFO] '$filename' is already attached; skipping"
            continue
        fi

        echo "[INFO] uploading '$filename'"
        asset_info=$(run_cli repositories assets upload "$NEXIGON_REPOSITORY" "$asset_path")
        asset_id=$(jq -er '.assetId | select(type == "string" and length > 0)' \
            <<<"$asset_info")
        metadata=$(asset_metadata "$package_kind" "$asset_path" "$filename")
        if [ -n "$metadata" ]; then
            run_cli repositories versions assets add \
                "$version_id" "$asset_id" "$filename" --metadata "$metadata"
        else
            run_cli repositories versions assets add "$version_id" "$asset_id" "$filename"
        fi
    done
}

tag_version() {
    local version_id="$1"
    local version_info
    local tag_args=()

    if [ -n "${FLOATING_TAG:-}" ]; then
        tag_args+=(--tag "$FLOATING_TAG,reassign")
    fi
    if [ "${PUBLISH_ROLLING:-false}" = true ]; then
        tag_args+=(--tag "rolling,reassign")
    fi
    if [ -n "${GIT_RELEASE_TAG:-}" ]; then
        version_info=$(run_cli repositories versions info "$version_id")
        if ! jq -e --arg tag "$GIT_RELEASE_TAG" \
            '.tags[]? | select(.tag == $tag)' <<<"$version_info" >/dev/null; then
            tag_args+=(--tag "$GIT_RELEASE_TAG,locked")
        fi
    fi
    if [ "${PUBLISH_STABLE:-false}" = true ]; then
        tag_args+=(--tag "stable,reassign")
    fi
    if [ "${#tag_args[@]}" -gt 0 ]; then
        run_cli repositories versions tag "$version_id" "${tag_args[@]}"
    fi
}

require_variable NEXIGON_REPOSITORY
require_variable BUILD_TAG

if [ ! -d "$ARTIFACT_DIR" ]; then
    echo "[ERROR] artifact directory '$ARTIFACT_DIR' does not exist" >&2
    exit 1
fi

for expected_dir in \
    "$ARTIFACT_DIR/revpi-rugix-nexigon" \
    "$ARTIFACT_DIR/revpi-dio-grafana-app"; do
    if [ ! -d "$expected_dir" ]; then
        echo "[ERROR] expected artifact directory '$expected_dir' does not exist" >&2
        exit 1
    fi
done

mapfile -d '' os_assets < <(
    find "$ARTIFACT_DIR/revpi-rugix-nexigon" -type f -print0 \
        | sort -z
)
mapfile -d '' app_assets < <(
    find "$ARTIFACT_DIR/revpi-dio-grafana-app" -type f -print0 | sort -z
)

if [ "${#os_assets[@]}" -eq 0 ]; then
    echo "[ERROR] no RevPi OS assets found" >&2
    exit 1
fi
if [ "${#app_assets[@]}" -eq 0 ]; then
    echo "[ERROR] no example app assets found" >&2
    exit 1
fi

validate_package_assets os os_assets
validate_package_assets app app_assets

source_commit=${GITHUB_SHA:-$(git rev-parse HEAD)}
os_metadata=$(jq -nc \
    --arg image_version "$BUILD_TAG" \
    --arg source_commit "$source_commit" \
    '{imageVersion: $image_version, sourceCommit: $source_commit}')
app_metadata=$(jq -nc \
    --arg version "$BUILD_TAG" \
    --arg source_commit "$source_commit" \
    '{version: $version, sourceCommit: $source_commit}')

os_version_id=$(resolve_or_create_version "$NEXIGON_OS_PACKAGE" "$os_metadata")
app_version_id=$(resolve_or_create_version "$NEXIGON_APP_PACKAGE" "$app_metadata")

upload_package_assets "$os_version_id" os os_assets
upload_package_assets "$app_version_id" app app_assets

tag_version "$os_version_id"
tag_version "$app_version_id"

echo "[INFO] published '$BUILD_TAG' to '$NEXIGON_OS_PACKAGE' and '$NEXIGON_APP_PACKAGE'"
