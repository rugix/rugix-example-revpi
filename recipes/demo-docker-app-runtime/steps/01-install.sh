#!/bin/bash

set -euo pipefail

curl -fsSL https://test.docker.com -o /tmp/install-docker.sh
sh /tmp/install-docker.sh

install -D -m 644 "${RECIPE_DIR}/files/rugix-apps-restore-units.service" -t /usr/lib/systemd/system/
install -D -m 644 "${RECIPE_DIR}/files/rugix-apps-recover.service" -t /usr/lib/systemd/system/

mkdir -p /etc/rugix/state
cat >/etc/rugix/state/docker.toml <<EOF
[[persist]]
directory = "/var/lib/containerd"

[[persist]]
directory = "/var/lib/docker"
EOF

systemctl enable docker
systemctl enable rugix-apps-restore-units.service
systemctl enable rugix-apps-recover.service
