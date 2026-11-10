#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
: "${NEXIGON:=false}"

args=(
    -tflavour:lite
    -ttype:rugix
    -tdocker:true
    -trugix_apps:true
    -trugix_admin:true
    -tgen_sbom:true
    -toutput:"${OUTPUT}"
    -tversion:"${VERSION}"
)
if [ "${NEXIGON}" = "true" ]; then
    args+=(
        -tnexigon:true
        -tnexigon_provisioning:true
    )
fi

./run-debos "${args[@]}" revpi.yaml
