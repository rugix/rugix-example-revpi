#!/bin/sh
#
# SPDX-FileCopyrightText: 2026 Silitics GmbH
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -eu

STATE_DIR=${REVPI_STATE_DIR:-/var/lib/revpi}
MARKER="${STATE_DIR}/rugix-first-boot-complete"
FACTORY_RESET_MARKER="${STATE_DIR}/factory-reset"
DEVINFO_DIR="${STATE_DIR}/devinfo"
HOSTNAME_PREFIX_FILE=/usr/share/revpi/hostname
HOSTNAME_PREFIX=RevPi

log() {
    printf "%s\n" "$*"
    logger -t initialize-revpi-identity "$*" 2>/dev/null || true
}

normalise_mac() {
    tr -d '\000' | tr -d ':-' | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'
}

format_mac() {
    sed 's/\(..\)/\1:/g; s/:$//'
}

read_dt_string() {
    tr -d '\000' < "$1"
}

set_hostname() {
    hostname=$1

    if ! printf "%s\n" "$hostname" > /etc/hostname; then
        log "Cannot write /etc/hostname."
        return 1
    fi

    if grep -qE '^127\.0\.1\.1[[:blank:]]+' /etc/hosts; then
        if ! sed -r -i \
            -e "s/^(127\.0\.1\.1[[:blank:]]+).*/\1${hostname}/" \
            /etc/hosts; then
            log "Cannot update /etc/hosts."
            return 1
        fi
    else
        if ! printf "\n127.0.1.1\t%s\n" "$hostname" >> /etc/hosts; then
            log "Cannot append to /etc/hosts."
            return 1
        fi
    fi

    hostname "$hostname" || log "Cannot activate hostname. A reboot may be required."
}

if [ -e "$MARKER" ]; then
    exit 0
fi

mkdir -p "$STATE_DIR" "$DEVINFO_DIR"

# Keep the stock login-time factory-reset flow from changing the password.
touch "$FACTORY_RESET_MARKER"

if [ -f "$HOSTNAME_PREFIX_FILE" ]; then
    HOSTNAME_PREFIX=$(head -n1 "$HOSTNAME_PREFIX_FILE")
    if echo "$HOSTNAME_PREFIX" | grep -Eq '[[:space:]]'; then
        log "Ignoring invalid hostname prefix '${HOSTNAME_PREFIX}'."
        HOSTNAME_PREFIX=RevPi
    fi
fi

hostname_ready=true
if [ -r /proc/device-tree/hat/custom_1 ]; then
    serial=$(read_dt_string /proc/device-tree/hat/custom_1)
    hostname="${HOSTNAME_PREFIX}${serial}"
    if set_hostname "$hostname"; then
        log "Set hostname to ${hostname}."
    else
        log "Could not set hostname to ${hostname}."
        hostname_ready=false
    fi
    printf "%s" "$serial" > "${DEVINFO_DIR}/serial-number"

    if [ -r /proc/device-tree/hat/custom_5 ]; then
        mac=$(normalise_mac < /proc/device-tree/hat/custom_5)
        printf "%s" "$mac" | format_mac > "${DEVINFO_DIR}/base-mac-address"
    fi
else
    log "No RevPi HAT EEPROM found. Leaving hostname unchanged."
fi

# The stock reset removes this temporary rule after it runs. Rugix bypasses that
# flow, so remove it here as well.
rm -f /etc/sudoers.d/051_revpi-factory-reset

if [ "$hostname_ready" != "true" ]; then
    log "Leaving Rugix first-boot marker unset so hostname setup is retried."
    exit 1
fi

touch "$MARKER"
