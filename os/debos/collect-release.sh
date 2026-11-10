#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

rm -rf dist
mkdir -p dist
for src in build/"${OUTPUT}".* build/packages_"${OUTPUT}".csv; do
    if [ -e "${src}" ]; then
        cp "${src}" dist/
    fi
done
sbom=build/sbom-"${OUTPUT}".json
if [ ! -e "${sbom}" ]; then
    echo "expected SPDX SBOM '${sbom}' was not generated" >&2
    exit 1
fi
cp "${sbom}" dist/"${OUTPUT}".spdx.json
