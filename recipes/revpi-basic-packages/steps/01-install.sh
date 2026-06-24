#!/bin/bash

set -euo pipefail

adduser "${RECIPE_PARAM_USER}" picontrol
systemctl enable avahi-daemon
firewall-offline-cmd --add-service=mdns
sed -i 's/^enable-wide-area=yes/enable-wide-area=no/' /etc/avahi/avahi-daemon.conf

