#!/bin/bash

set -euo pipefail

apt-get update -y
apt-get install -y ca-certificates

suite="$(
    . /etc/os-release
    printf "%s" "${VERSION_CODENAME:-${DEBIAN_CODENAME:-}}"
)"
if [[ -z "${suite}" ]]; then
    echo "failed to determine Debian suite from /etc/os-release" >&2
    exit 1
fi

install -D -m 644 "${RECIPE_DIR}/files/debian.sources.list" /etc/apt/sources.list
install -D -m 644 "${RECIPE_DIR}/files/revpi.sources" /etc/apt/sources.list.d/_revpi.sources
install -D -m 644 "${RECIPE_DIR}/files/raspi.sources" /etc/apt/sources.list.d/raspi.sources
sed -i -e "s/SUITE/${suite}/g" \
    /etc/apt/sources.list \
    /etc/apt/sources.list.d/_revpi.sources \
    /etc/apt/sources.list.d/raspi.sources

apt-get update -y
apt-get install -y revpi-repo
rm -f /etc/apt/sources.list.d/_revpi.sources /usr/share/keyrings/_revpi-keyring.gpg

apt-get install -y raspberrypi-archive-keyring
sed -i -e 's,_raspberrypi-archive-keyring.gpg,raspberrypi-archive-keyring.pgp,g' \
    /etc/apt/sources.list.d/raspi.sources
rm -f /usr/share/keyrings/_raspberrypi-archive-keyring.gpg
