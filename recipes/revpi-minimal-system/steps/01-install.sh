#!/bin/bash

set -euo pipefail

cp -a "${RECIPE_DIR}/files/defaults/." /
cp -a "${RECIPE_DIR}/files/networkmanager-wifi-disabled/." /

dpkg-reconfigure -fnoninteractive tzdata

printf "%s\n" "${RECIPE_PARAM_HOSTNAME}" > /etc/hostname
sed -i -e "s/REVPIHOSTNAME/${RECIPE_PARAM_HOSTNAME}/g" /etc/hosts
sed -i -e '1s/$/ \\4 \\6/' /etc/issue

mkdir -p /var/lib/systemd/rfkill
echo 1 > /var/lib/systemd/rfkill/platform-fe300000.mmcnr:wlan
echo 1 > /var/lib/systemd/rfkill/platform-fe300000.mmc:wlan
echo 1 > /var/lib/systemd/rfkill/platform-soc:bluetooth
echo 1 > /var/lib/systemd/rfkill/platform-1001100000.mmc:wlan

mkdir -p /etc/revpi
cat >> /etc/machine-info <<EOF
CHASSIS="embedded"
HARDWARE_VENDOR="KUNBUS GmbH"
EOF

systemctl enable NetworkManager
systemctl enable systemd-timesyncd
