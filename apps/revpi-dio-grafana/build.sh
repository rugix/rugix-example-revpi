#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLER="${RUGIX_BUNDLER:-rugix-bundler}"
BUILD_DIR="${APP_DIR}/build"
PLATFORM="${RUGIX_PLATFORM:-linux/arm64}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-}"

if [[ -z "${CONTAINER_RUNTIME}" ]]; then
    if command -v podman >/dev/null 2>&1; then
        CONTAINER_RUNTIME="podman"
    elif command -v docker >/dev/null 2>&1; then
        CONTAINER_RUNTIME="docker"
    else
        echo "podman or docker is required" >&2
        exit 1
    fi
fi

mkdir -p "${BUILD_DIR}"

output="${BUILD_DIR}/revpi-dio-grafana.rugixb"
hash_output="${BUILD_DIR}/revpi-dio-grafana.rugixb-hash"

cd "${APP_DIR}"
"${BUNDLER}" apps pack docker-compose \
    --app revpi-dio-grafana \
    --health-check-timeout 240 \
    --platform "${PLATFORM}" \
    --builder "${CONTAINER_RUNTIME}" \
    --include config \
    --components components \
    docker-compose.yml \
    "${output}"

"${BUNDLER}" hash "${output}" >"${hash_output}"
echo "wrote ${output}"
echo "wrote ${hash_output}"
