#!/bin/bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

policy_rc_d="/usr/sbin/policy-rc.d"
policy_backup=""

if [ -e "${policy_rc_d}" ]; then
    policy_backup="$(mktemp)"
    cp -a "${policy_rc_d}" "${policy_backup}"
fi

cleanup_policy_rc_d() {
    if [ -n "${policy_backup}" ]; then
        cp -a "${policy_backup}" "${policy_rc_d}"
        rm -f "${policy_backup}"
    else
        rm -f "${policy_rc_d}"
    fi
}
trap cleanup_policy_rc_d EXIT

cat > "${policy_rc_d}" <<'EOF'
#!/bin/sh
exit 101
EOF
chmod 755 "${policy_rc_d}"

apt-get -o Dpkg::Use-Pty=0 install -y \
    piserial \
    can-utils \
    python3-can \
    libsocketcan-dev \
    lsof \
    python3-revpimodio2 \
    revpipyload \
    revpi-bluetooth \
    python3-libgpiod \
    python3-yaml \
    python3-schema \
    python3-revpi-device-info \
    python-is-python3 \
    revpi-sos-report \
    rsyslog \
    rfkill \
    opcua-revpi-server \
    mqtt-revpi-client \
    raspberrypi-sys-mods \
    flashrom \
    dphys-swapfile \
    apt-listchanges \
    firmware-realtek \
    revpi-security
