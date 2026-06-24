#!/bin/bash

set -euo pipefail

mkdir -p /etc/rugix/state
cat >/etc/rugix/state/containers.toml <<EOF
[[persist]]
directory = "/var/lib/containers"
EOF

