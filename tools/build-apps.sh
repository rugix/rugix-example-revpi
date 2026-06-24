#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLER="${RUGIX_BUNDLER:-"${ROOT}/.tools/rugix-bundler"}"
DIST_DIR="${RUGIX_DIST_DIR:-"${ROOT}/dist"}"
PLATFORM="${RUGIX_PLATFORM:-linux/arm64}"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-}"
NO_IMAGES=false
ONLY_APP=""

usage() {
    cat <<'EOF'
Usage: tools/build-apps.sh [OPTIONS]

Options:
  --app NAME          Build one app from apps/NAME.
  --platform VALUE    Image platform for bundled container images, default linux/arm64.
  --no-images         Pack bundles without container image payloads.
  -h, --help          Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app) ONLY_APP="$2"; shift 2 ;;
        --platform) PLATFORM="$2"; shift 2 ;;
        --no-images) NO_IMAGES=true; shift ;;
        --skip-build) NO_IMAGES=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ ! -x "${BUNDLER}" ]]; then
    echo "rugix-bundler not found at ${BUNDLER}" >&2
    echo "run tools/download-rugix-bundler.sh or set RUGIX_BUNDLER" >&2
    exit 1
fi

if [[ -z "${CONTAINER_RUNTIME}" && "${NO_IMAGES}" != true ]]; then
    if command -v podman >/dev/null 2>&1; then
        CONTAINER_RUNTIME="podman"
    elif command -v docker >/dev/null 2>&1; then
        CONTAINER_RUNTIME="docker"
    else
        echo "podman or docker is required unless --no-images is used" >&2
        exit 1
    fi
fi

mkdir -p "${DIST_DIR}"

mapfile -t app_dirs < <(find "${ROOT}/apps" -mindepth 1 -maxdepth 1 -type d ! -name "_*" | sort)
if [[ -n "${ONLY_APP}" ]]; then
    app_dirs=("${ROOT}/apps/${ONLY_APP}")
fi

for app_dir in "${app_dirs[@]}"; do
    name="$(basename "${app_dir}")"
    compose="${app_dir}/docker-compose.yml"
    metadata="${app_dir}/app-meta.json"
    output="${DIST_DIR}/${name}.rugixb"
    hash_output="${DIST_DIR}/${name}.rugixb-hash"

    if [[ ! -d "${app_dir}" ]]; then
        echo "app does not exist: ${name}" >&2
        exit 1
    fi
    if [[ ! -f "${compose}" ]]; then
        echo "missing compose file for ${name}: ${compose}" >&2
        exit 1
    fi
    if [[ ! -f "${metadata}" ]]; then
        echo "missing metadata file for ${name}: ${metadata}" >&2
        exit 1
    fi

    echo "building ${name}"

    cmd=(
        "${BUNDLER}"
        apps pack docker-compose
        --app "${name}"
        --health-check-timeout 240
        --metadata-file app-meta.json
    )
    if [[ "${NO_IMAGES}" == true ]]; then
        cmd+=(--disable-image-bundling)
    else
        cmd+=(--platform "${PLATFORM}" --builder "${CONTAINER_RUNTIME}")
    fi
    if [[ -d "${app_dir}/config" ]]; then
        cmd+=(--include config)
    fi
    cmd+=(docker-compose.yml "${output}")

    (cd "${app_dir}" && "${cmd[@]}")

    "${BUNDLER}" hash "${output}" >"${hash_output}"
    echo "wrote ${output}"
    echo "wrote ${hash_output}"
done
