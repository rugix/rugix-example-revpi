#!/bin/bash

set -euo pipefail

install -D -m 644 "${RECIPE_DIR}/files/revpi.toml" /etc/rugix/state/revpi.toml

