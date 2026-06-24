#!/bin/bash

set -euo pipefail

if [ -f /etc/sos/sos.conf ]; then
    sed -i -e 's,\(tmp-dir\) =.*,\1 = /var/tmp,g' /etc/sos/sos.conf
fi

systemctl mask raspi-config.service cpufrequtils.service || true
systemctl disable regenerate_ssh_host_keys.service || true
systemctl disable dphys-swapfile || true

if [ -f /etc/dphys-swapfile ]; then
    sed -i -e 's/^#\(CONF_SWAPSIZE\)=.*/\1=512/g' /etc/dphys-swapfile
fi

systemctl set-default multi-user.target
