#!/bin/bash

set -euo pipefail

mkdir -p /etc/revpi
cat > /etc/revpi/image-release <<EOF
BUILD_ID="$(date --iso-8601)"
IMAGE_ID="rugix-revpi"
IMAGE_VERSION="${RUGIX_SYSTEM_RELEASE_VERSION:-unknown}"
EOF

systemctl mask revpi-firstboot-resize-fs.service || true
rm -rf \
    /var/cache/apt/archives/*.deb \
    /var/cache/apt/*.bin \
    /var/lib/apt/lists/* \
    /tmp/* \
    /var/tmp/*

rm -f /etc/ssh/ssh_host_*_key*
printf "uninitialized\n" > /etc/machine-id
rm -f /var/lib/dbus/machine-id
rm -f /var/lib/systemd/random-seed
rm -f /var/lib/systemd/credential.secret

