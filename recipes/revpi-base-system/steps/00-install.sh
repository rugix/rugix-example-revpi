#!/bin/bash

set -euo pipefail

BOOT_DIR="${RUGIX_LAYER_DIR}/roots/boot"

apt-get install -y init udev kmod
apt-get install -y linux-base
apt-get install -y raspi-firmware
apt-get install -y initramfs-tools
apt-get install -y \
    linux-image-revpi-v8 \
    revpi-base-files \
    revpi-firmware \
    revpi-tools

install -D -m 644 "${RECIPE_DIR}/files/cmdline.txt" /boot/firmware/cmdline.txt
install -D -m 644 "${RECIPE_DIR}/files/config.txt" /boot/firmware/config.txt

if [ -f /boot/firmware/overlays/revpi-dt-blob.dtbo ]; then
    cp /boot/firmware/overlays/revpi-dt-blob.dtbo /boot/firmware/dt-blob.bin
fi

mkdir -p "${BOOT_DIR}"
cp -rp /boot/firmware/. "${BOOT_DIR}/"

