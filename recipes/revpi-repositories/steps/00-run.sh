#!/bin/bash

set -euo pipefail

install -d -m 755 "${RUGIX_ROOT_DIR}/usr/share/keyrings"
gpg --dearmor \
    < "${RECIPE_DIR}/files/revpi-archive-key.asc" \
    > "${RUGIX_ROOT_DIR}/usr/share/keyrings/_revpi-keyring.gpg"
gpg --dearmor \
    < "${RECIPE_DIR}/files/raspberrypi-archive-key.asc" \
    > "${RUGIX_ROOT_DIR}/usr/share/keyrings/_raspberrypi-archive-keyring.gpg"
chmod 644 \
    "${RUGIX_ROOT_DIR}/usr/share/keyrings/_revpi-keyring.gpg" \
    "${RUGIX_ROOT_DIR}/usr/share/keyrings/_raspberrypi-archive-keyring.gpg"

