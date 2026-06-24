#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${RUGIX_GITHUB_REPO:-rugix/rugix}"
VERSION="${RUGIX_VERSION:-latest}"
TOOLS_DIR="${RUGIX_TOOLS_DIR:-"${ROOT}/.tools"}"
DOWNLOAD_DIR="${TOOLS_DIR}/downloads"

case "$(uname -s)" in
    Linux) os="unknown-linux-musl" ;;
    Darwin) os="apple-darwin" ;;
    *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    armv7l) arch="armv7" ;;
    arm*) arch="arm" ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

triple="${arch}-${os}"
api="https://api.github.com/repos/${REPO}/releases"
if [[ "${VERSION}" == "latest" ]]; then
    release_url="${api}/latest"
else
    release_url="${api}/tags/${VERSION}"
fi

mkdir -p "${DOWNLOAD_DIR}"
release_json="$(curl -fsSL "${release_url}")"

read -r tag asset_name asset_url asset_digest < <(
    RELEASE_JSON="${release_json}" TRIPLE="${triple}" python3 - <<'PY'
import json
import os

release = json.loads(os.environ["RELEASE_JSON"])
triple = os.environ["TRIPLE"]
wanted = f"binaries-{triple}.tar"
for asset in release.get("assets", []):
    if asset.get("name") == wanted:
        print(
            release["tag_name"],
            asset["name"],
            asset["browser_download_url"],
            asset.get("digest", ""),
        )
        break
else:
    names = ", ".join(a.get("name", "") for a in release.get("assets", []))
    raise SystemExit(
        f"no asset {wanted!r} in release {release.get('tag_name')}; assets: {names}"
    )
PY
)

archive="${DOWNLOAD_DIR}/${asset_name}"
extract_dir="${TOOLS_DIR}/rugix-${tag}-${triple}"
bundler_link="${TOOLS_DIR}/rugix-bundler"

if [[ ! -f "${archive}" ]]; then
    echo "downloading ${asset_url}"
    curl -fL "${asset_url}" -o "${archive}"
fi

if [[ "${asset_digest}" == sha256:* ]]; then
    expected="${asset_digest#sha256:}"
    echo "${expected}  ${archive}" | sha256sum -c -
fi

rm -rf "${extract_dir}"
mkdir -p "${extract_dir}"
tar -xf "${archive}" -C "${extract_dir}"

bundler="$(find "${extract_dir}" -type f -name rugix-bundler -perm -111 | head -n 1)"
if [[ -z "${bundler}" ]]; then
    echo "rugix-bundler not found in ${archive}" >&2
    exit 1
fi

ln -sfn "${bundler}" "${bundler_link}"
echo "installed ${bundler_link}"
"${bundler_link}" --version
