#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Silitics GmbH
#
# SPDX-License-Identifier: GPL-2.0-or-later

set -euo pipefail

RUGIX_VERSION="${RUGIX_VERSION:-v1.3.0-dev.2}"
RUGIX_TRIPLE="${RUGIX_TRIPLE:-}"
RUGIX_BINARY_URL="${RUGIX_BINARY_URL:-}"
RUGIX_ADMIN_ADDRESS="${RUGIX_ADMIN_ADDRESS:-0.0.0.0:8088}"
RUGIX_INSTALL_DOCKER="${RUGIX_INSTALL_DOCKER:-true}"
RUGIX_INSTALL_ADMIN="${RUGIX_INSTALL_ADMIN:-true}"
RUGIX_START_SERVICES="${RUGIX_START_SERVICES:-true}"
DOCKER_INSTALL_URL="https://test.docker.com"

APT_UPDATED=0
SUDO=()

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Install the Docker-backed Rugix Apps runtime on a stock RevPi system.

This installs:
  - Docker and the Docker Compose plugin
  - rugix-ctrl, rugix-admin, and rugix-bundler
  - Rugix Apps restore and recovery systemd units
  - Docker, Raspberry Pi, and RevPi component publisher services
  - the Rugix Admin systemd unit, enabled by default

It does not convert the OS into a Rugix A/B boot-managed image.

Options:
  --admin-address ADDRESS      Rugix Admin listen address
                               default: ${RUGIX_ADMIN_ADDRESS}
  --rugix-version VERSION      Rugix release to install
                               default: ${RUGIX_VERSION}
  --rugix-triple TRIPLE        Rugix binary archive target triple
                               default: detected from uname -m
  --rugix-binary-url URL       Full Rugix binary archive URL
  --no-admin                   Do not install or enable Rugix Admin
  --no-docker                  Do not install Docker
  --no-start                   Enable services but do not start them now
  -h, --help                   Show this help

Environment variables with matching names can also be used:
  RUGIX_VERSION, RUGIX_TRIPLE, RUGIX_BINARY_URL, RUGIX_ADMIN_ADDRESS,
  RUGIX_INSTALL_DOCKER, RUGIX_INSTALL_ADMIN, RUGIX_START_SERVICES
EOF
}

log() {
    printf '[setup] %s\n' "$*"
}

warn() {
    printf '[setup] WARNING: %s\n' "$*" >&2
}

die() {
    printf '[setup] ERROR: %s\n' "$*" >&2
    exit 1
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --admin-address)
                [ "$#" -ge 2 ] || die "--admin-address requires a value"
                RUGIX_ADMIN_ADDRESS="$2"
                shift 2
                ;;
            --rugix-version)
                [ "$#" -ge 2 ] || die "--rugix-version requires a value"
                RUGIX_VERSION="$2"
                shift 2
                ;;
            --rugix-triple)
                [ "$#" -ge 2 ] || die "--rugix-triple requires a value"
                RUGIX_TRIPLE="$2"
                shift 2
                ;;
            --rugix-binary-url)
                [ "$#" -ge 2 ] || die "--rugix-binary-url requires a value"
                RUGIX_BINARY_URL="$2"
                shift 2
                ;;
            --no-admin)
                RUGIX_INSTALL_ADMIN=false
                shift
                ;;
            --no-docker)
                RUGIX_INSTALL_DOCKER=false
                shift
                ;;
            --no-start)
                RUGIX_START_SERVICES=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
    done
}

bool_is_true() {
    case "$1" in
        true|1|yes|on)
            return 0
            ;;
        false|0|no|off)
            return 1
            ;;
        *)
            die "invalid boolean value: $1"
            ;;
    esac
}

validate_admin_address() {
    [ -n "${RUGIX_ADMIN_ADDRESS}" ] || die "RUGIX_ADMIN_ADDRESS must not be empty"
    case "${RUGIX_ADMIN_ADDRESS}" in
        *\"*|*$'\n'*|*$'\r'*)
            die "invalid Rugix Admin address: ${RUGIX_ADMIN_ADDRESS}"
            ;;
    esac
}

rugix_admin_port() {
    local port="${RUGIX_ADMIN_ADDRESS##*:}"

    case "${port}" in
        ""|*[!0-9]*)
            die "can not determine Rugix Admin TCP port from RUGIX_ADMIN_ADDRESS=${RUGIX_ADMIN_ADDRESS}"
            ;;
    esac
    if [ "${port}" -lt 1 ] || [ "${port}" -gt 65535 ]; then
        die "invalid Rugix Admin TCP port in RUGIX_ADMIN_ADDRESS=${RUGIX_ADMIN_ADDRESS}"
    fi

    printf '%s\n' "${port}"
}

setup_privileges() {
    if [ "${EUID}" -eq 0 ]; then
        SUDO=()
        return
    fi

    command -v sudo >/dev/null 2>&1 || die "this installer needs root privileges and sudo is not available"

    log "Requesting sudo privileges"
    sudo -v
    SUDO=(sudo)
}

require_live_system() {
    command -v apt-get >/dev/null 2>&1 || die "apt-get is required"
    command -v systemctl >/dev/null 2>&1 || die "systemctl is required"
    [ -d /run/systemd/system ] || die "systemd does not appear to be running"
}

apt_install() {
    if [ "${APT_UPDATED}" -eq 0 ]; then
        log "Updating apt package lists"
        "${SUDO[@]}" apt-get update
        APT_UPDATED=1
    fi

    log "Installing apt packages: $*"
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

detect_rugix_triple() {
    case "$(uname -m)" in
        aarch64|arm64)
            printf 'aarch64-unknown-linux-musl\n'
            ;;
        x86_64|amd64)
            printf 'x86_64-unknown-linux-musl\n'
            ;;
        *)
            die "unsupported architecture $(uname -m); set RUGIX_TRIPLE"
            ;;
    esac
}

backup_if_different() {
    local source="$1"
    local target="$2"

    if [ -e "${target}" ] && ! cmp -s "${source}" "${target}"; then
        local backup="${target}.bak.$(date +%Y%m%d%H%M%S)"
        "${SUDO[@]}" cp -a "${target}" "${backup}"
        log "Backed up ${target} to ${backup}"
    fi
}

install_from_stdin() {
    local mode="$1"
    local target="$2"
    local tmp

    tmp="$(mktemp)"
    cat >"${tmp}"
    backup_if_different "${tmp}" "${target}"
    "${SUDO[@]}" install -D -m "${mode}" "${tmp}" "${target}"
    rm -f "${tmp}"
}

install_prerequisites() {
    apt_install ca-certificates curl fdisk kmod
}

install_docker() {
    if bool_is_true "${RUGIX_INSTALL_DOCKER}"; then
        if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
            local tmpdir
            tmpdir="$(mktemp -d)"

            log "Installing Docker using ${DOCKER_INSTALL_URL}"
            curl -fsSL "${DOCKER_INSTALL_URL}" -o "${tmpdir}/install-docker.sh"
            "${SUDO[@]}" sh "${tmpdir}/install-docker.sh"
            rm -rf "${tmpdir}"

            if ! docker compose version >/dev/null 2>&1; then
                log "Installing Docker Compose plugin"
                apt_install docker-compose-plugin
            fi
        else
            log "Docker and Docker Compose plugin are already installed"
        fi
    else
        log "Skipping Docker installation; expecting existing Docker and Docker Compose plugin"
    fi

    if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
        if ! bool_is_true "${RUGIX_INSTALL_DOCKER}"; then
            die "Docker and the Docker Compose plugin are required; rerun without --no-docker or install them first"
        fi

        local tmpdir
        tmpdir="$(mktemp -d)"

        log "Retrying Docker installation using ${DOCKER_INSTALL_URL}"
        curl -fsSL "${DOCKER_INSTALL_URL}" -o "${tmpdir}/install-docker.sh"
        "${SUDO[@]}" sh "${tmpdir}/install-docker.sh"
        rm -rf "${tmpdir}"

        if ! docker compose version >/dev/null 2>&1; then
            log "Installing Docker Compose plugin"
            apt_install docker-compose-plugin
        fi
    fi

    command -v docker >/dev/null 2>&1 || die "docker is not installed"
    docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is not installed"

    "${SUDO[@]}" systemctl enable docker.service
}

install_rugix_binaries() {
    if [ -z "${RUGIX_TRIPLE}" ]; then
        RUGIX_TRIPLE="$(detect_rugix_triple)"
    fi
    if [ -z "${RUGIX_BINARY_URL}" ]; then
        RUGIX_BINARY_URL="https://github.com/rugix/rugix/releases/download/${RUGIX_VERSION}/binaries-${RUGIX_TRIPLE}.tar"
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"

    log "Downloading Rugix binaries from ${RUGIX_BINARY_URL}"
    curl -fsSL "${RUGIX_BINARY_URL}" -o "${tmpdir}/rugix-binaries.tar"
    tar -xf "${tmpdir}/rugix-binaries.tar" -C "${tmpdir}"

    local binary
    for binary in rugix-ctrl rugix-admin rugix-bundler; do
        [ -f "${tmpdir}/${binary}" ] || die "Rugix archive is missing ${binary}"
        "${SUDO[@]}" install -m 0755 "${tmpdir}/${binary}" "/usr/bin/${binary}"
    done

    rm -rf "${tmpdir}"
}

install_runtime_files() {
    log "Installing Rugix Apps runtime files"

    install_from_stdin 0755 /usr/libexec/rugix/rugix-docker-runtime-components <<'__RUGIX_DOCKER_RUNTIME_COMPONENTS__'
#!/usr/bin/env bash
set -euo pipefail

COMPONENTS_DIR="${RUGIX_COMPONENTS_DIR:-/run/rugix/components}"
OUTPUT_FILE="${RUGIX_DOCKER_COMPONENT_FILE:-${COMPONENTS_DIR}/docker.toml}"

tmp=""

prepare_output_file() {
    local output_dir output_name
    output_dir="$(dirname "${OUTPUT_FILE}")"
    output_name="$(basename "${OUTPUT_FILE}")"
    mkdir -p "${output_dir}"
    tmp="$(mktemp "${output_dir}/.${output_name}.tmp.XXXXXX")"
}

cleanup() {
    if [[ -n "${tmp}" ]]; then
        rm -f "${tmp}"
    fi
}
trap cleanup EXIT

toml_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

is_component_version() {
    [[ "$1" =~ ^[0-9]+(\.[0-9]+)*(-[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*)?(\+[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*)?$ ]]
}

normalize_component_version() {
    local version="${1#v}"
    if is_component_version "${version}"; then
        printf '%s\n' "${version}"
    fi
}

append_runtime_capability() {
    local id="$1"
    local raw_version="${2:-}"
    local version=""

    if [[ -n "${raw_version}" ]]; then
        version="$(normalize_component_version "${raw_version}" || true)"
    fi

    printf '\n[[provides]]\nid = "%s"\n' "${id}" >>"${tmp}"
    if [[ -n "${version}" ]]; then
        printf 'version = "%s"\n' "${version}" >>"${tmp}"
    elif [[ -n "${raw_version}" ]]; then
        printf 'value = "%s"\n' "$(toml_escape "${raw_version}")" >>"${tmp}"
    fi
}

docker_version="$(docker version --format '{{.Server.Version}}' 2>/dev/null || docker version --format '{{.Client.Version}}' 2>/dev/null || true)"
compose_available=0
compose_version=""
if docker compose version >/dev/null 2>&1; then
    compose_available=1
    compose_version="$(docker compose version --short 2>/dev/null || true)"
fi
docker_component_version="$(normalize_component_version "${docker_version}" || true)"

if [[ -z "${docker_version}" && "${compose_available}" != "1" ]]; then
    rm -f "${OUTPUT_FILE}"
    exit 0
fi

prepare_output_file

cat >"${tmp}" <<EOF
# Generated by rugix-docker-runtime-components. Do not edit.
id = "runtime.docker"
EOF

if [[ -n "${docker_component_version}" ]]; then
    printf 'version = "%s"\n' "${docker_component_version}" >>"${tmp}"
elif [[ -n "${docker_version}" ]]; then
    append_runtime_capability "runtime.docker" "${docker_version}"
fi

if [[ "${compose_available}" == "1" ]]; then
    append_runtime_capability "runtime.docker-compose" "${compose_version}"
fi

chmod 0644 "${tmp}"
mv "${tmp}" "${OUTPUT_FILE}"
tmp=""
__RUGIX_DOCKER_RUNTIME_COMPONENTS__

    install_from_stdin 0755 /usr/libexec/rugix/rugix-rpi-components <<'__RUGIX_RPI_COMPONENTS__'
#!/bin/sh

set -eu

COMPONENTS_DIR="${RUGIX_COMPONENTS_DIR:-/run/rugix/components}"
OUTPUT_FILE="${RUGIX_RPI_COMPONENT_FILE:-${COMPONENTS_DIR}/rpi.toml}"

tmp=""

prepare_output_file() {
    output_dir="$(dirname "${OUTPUT_FILE}")"
    output_name="$(basename "${OUTPUT_FILE}")"
    mkdir -p "${output_dir}"
    tmp="$(mktemp "${output_dir}/.${output_name}.tmp.XXXXXX")"
}

cleanup() {
    if [ -n "${tmp}" ]; then
        rm -f "${tmp}"
    fi
}
trap cleanup EXIT

toml_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

append_value_capability() {
    if [ -n "$2" ]; then
        printf '\n[[provides]]\nid = "%s"\nvalue = "%s"\n' \
            "$1" "$(toml_escape "$2")" >>"${tmp}"
    fi
}

read_device_tree_string() {
    if [ -r "$1" ]; then
        tr -d '\000' <"$1" | sed -n '1p'
    fi
}

read_device_tree_list() {
    if [ -r "$1" ]; then
        tr '\000' ',' <"$1" | sed 's/,$//'
    fi
}

read_cpuinfo_field() {
    if [ -r /proc/cpuinfo ]; then
        awk -F: -v key="$1" '
            $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
                sub(/^[[:space:]]+/, "", $2)
                print $2
                exit
            }
        ' /proc/cpuinfo
    fi
}

model="$(read_device_tree_string /proc/device-tree/model || true)"
compatible="$(read_device_tree_list /proc/device-tree/compatible || true)"
revision="$(read_cpuinfo_field Revision || true)"

case "${model},${compatible}" in
    *"Raspberry Pi"* | *RevPi* | *"Revolution Pi"* | *raspberrypi*)
        ;;
    *)
        rm -f "${OUTPUT_FILE}"
        exit 0
        ;;
esac

prepare_output_file

cat >"${tmp}" <<'EOF'
# Generated by rugix-rpi-components. Do not edit.
id = "hardware.rpi"
EOF

append_value_capability "hardware.rpi.model" "${model}"
append_value_capability "hardware.rpi.revision" "${revision}"

chmod 0644 "${tmp}"
mv "${tmp}" "${OUTPUT_FILE}"
tmp=""
__RUGIX_RPI_COMPONENTS__

    install_from_stdin 0755 /usr/libexec/rugix/rugix-revpi-components <<'__RUGIX_REVPI_COMPONENTS__'
#!/bin/sh

set -eu

COMPONENTS_DIR="${RUGIX_COMPONENTS_DIR:-/run/rugix/components}"
OUTPUT_FILE="${RUGIX_REVPI_COMPONENT_FILE:-${COMPONENTS_DIR}/revpi.toml}"
MODINFO="${MODINFO:-modinfo}"

tmp=""

prepare_output_file() {
    output_dir="$(dirname "${OUTPUT_FILE}")"
    output_name="$(basename "${OUTPUT_FILE}")"
    mkdir -p "${output_dir}"
    tmp="$(mktemp "${output_dir}/.${output_name}.tmp.XXXXXX")"
}

cleanup() {
    if [ -n "${tmp}" ]; then
        rm -f "${tmp}"
    fi
}
trap cleanup EXIT

toml_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

append_value_capability() {
    if [ -n "$2" ]; then
        printf '\n[[provides]]\nid = "%s"\nvalue = "%s"\n' \
            "$1" "$(toml_escape "$2")" >>"${tmp}"
    fi
}

is_component_version() {
    printf '%s\n' "$1" \
        | grep -Eq '^[0-9]+(\.[0-9]+)*(-[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*)?(\+[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*)?$'
}

append_version_capability() {
    if [ -z "$2" ]; then
        printf '\n[[provides]]\nid = "%s"\n' "$1" >>"${tmp}"
    elif is_component_version "$2"; then
        printf '\n[[provides]]\nid = "%s"\nversion = "%s"\n' "$1" "$2" >>"${tmp}"
    else
        append_value_capability "$1" "$2"
    fi
}

read_null_terminated_file() {
    if [ -r "$1" ]; then
        tr -d '\000' <"$1" | sed -n '1p'
    fi
}

hex_to_dec() {
    if [ -z "$1" ]; then
        return 0
    fi

    awk -v hex="$1" '
        BEGIN {
            gsub(/^0x/, "", hex)
            gsub(/^0X/, "", hex)
            dec = 0
            for (i = 1; i <= length(hex); i++) {
                c = toupper(substr(hex, i, 1))
                if (c >= "0" && c <= "9") {
                    v = c + 0
                } else {
                    v = index("ABCDEF", c)
                    if (v == 0) {
                        exit 1
                    }
                    v += 9
                }
                dec = dec * 16 + v
            }
            printf "%d\n", dec
        }
    '
}

hat_product_version() {
    product_ver="$(read_null_terminated_file /proc/device-tree/hat/product_ver || true)"
    product_ver_dec="$(hex_to_dec "${product_ver}" || true)"
    if [ -n "${product_ver_dec}" ]; then
        printf '%d.%d\n' "$((product_ver_dec / 100))" "$((product_ver_dec % 100))"
    fi
}

hat_product_id_revision() {
    product_id="$(read_null_terminated_file /proc/device-tree/hat/product_id || true)"
    product_revision="$(read_null_terminated_file /proc/device-tree/hat/custom_2 || true)"
    product_id_dec="$(hex_to_dec "${product_id}" || true)"
    product_revision_dec="$(hex_to_dec "${product_revision}" || true)"
    if [ -n "${product_id_dec}" ] && [ -n "${product_revision_dec}" ]; then
        printf 'PR%dR%02d\n' "$((product_id_dec + 100000))" "${product_revision_dec}"
    fi
}

modinfo_field() {
    printf '%s\n' "${modinfo_output}" \
        | awk -v key="$1" '
            index($0, key ":") == 1 {
                sub(/^[^:]*:[[:space:]]*/, "", $0)
                print
                exit
            }
        '
}

vendor="$(read_null_terminated_file /proc/device-tree/hat/vendor || true)"
product="$(read_null_terminated_file /proc/device-tree/hat/product || true)"
product_version="$(hat_product_version || true)"
product_id_revision="$(hat_product_id_revision || true)"
modinfo_output=""
picontrol_version=""
picontrol_active=0

if command -v "${MODINFO}" >/dev/null 2>&1; then
    modinfo_output="$("${MODINFO}" piControl 2>/dev/null || true)"
    picontrol_version="$(modinfo_field version || true)"
fi

if [ -d /sys/module/piControl ] || [ -e /dev/piControl0 ]; then
    picontrol_active=1
fi

case "${product}" in
    RevPi* | *"RevPi "* | *"Revolution Pi"*)
        ;;
    *)
        if [ -z "${modinfo_output}" ] && [ "${picontrol_active}" != "1" ]; then
            rm -f "${OUTPUT_FILE}"
            exit 0
        fi
        ;;
esac

prepare_output_file

cat >"${tmp}" <<'EOF'
# Generated by rugix-revpi-components. Do not edit.
id = "hardware.revpi"
EOF

case "${product}" in
    RevPi* | *"RevPi "* | *"Revolution Pi"*)
        append_value_capability "hardware.revpi.vendor" "${vendor}"
        append_value_capability "hardware.revpi.model" "${product}"
        append_version_capability "hardware.revpi.version" "${product_version}"
        append_value_capability "hardware.revpi.id" "${product_id_revision}"
        ;;
esac

if [ -n "${modinfo_output}" ]; then
    append_version_capability "kernel.module.picontrol" "${picontrol_version}"
fi

if [ "${picontrol_active}" = "1" ]; then
    append_version_capability "runtime.revpi.picontrol" "${picontrol_version}"
fi

chmod 0644 "${tmp}"
mv "${tmp}" "${OUTPUT_FILE}"
tmp=""
__RUGIX_REVPI_COMPONENTS__

    install_from_stdin 0644 /usr/lib/systemd/system/rugix-apps-recover.service <<'__RUGIX_APPS_RECOVER_SERVICE__'
[Unit]
Description=Recover interrupted Rugix app transitions
After=multi-user.target rugix-apps-restore-units.service docker.service rugix-docker-runtime-components.service rugix-rpi-components.service rugix-revpi-components.service
Wants=rugix-apps-restore-units.service rugix-docker-runtime-components.service rugix-rpi-components.service rugix-revpi-components.service

[Service]
Type=oneshot
ExecStart=/usr/bin/rugix-ctrl apps recover
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
__RUGIX_APPS_RECOVER_SERVICE__

    install_from_stdin 0644 /usr/lib/systemd/system/rugix-apps-restore-units.service <<'__RUGIX_APPS_RESTORE_UNITS_SERVICE__'
[Unit]
Description=Restore Rugix app units into systemd
After=local-fs.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/bin/rugix-ctrl apps service-manager systemd restore-units
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
__RUGIX_APPS_RESTORE_UNITS_SERVICE__

    install_from_stdin 0644 /usr/lib/systemd/system/rugix-docker-runtime-components.service <<'__RUGIX_DOCKER_RUNTIME_COMPONENTS_SERVICE__'
[Unit]
Description=Publish Docker runtime component metadata for Rugix
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/libexec/rugix/rugix-docker-runtime-components

[Install]
WantedBy=multi-user.target
__RUGIX_DOCKER_RUNTIME_COMPONENTS_SERVICE__

    install_from_stdin 0644 /usr/lib/systemd/system/rugix-revpi-components.service <<'__RUGIX_REVPI_COMPONENTS_SERVICE__'
[Unit]
Description=Publish RevPi hardware component metadata for Rugix
After=local-fs.target systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/usr/libexec/rugix/rugix-revpi-components

[Install]
WantedBy=multi-user.target
__RUGIX_REVPI_COMPONENTS_SERVICE__

    install_from_stdin 0644 /usr/lib/systemd/system/rugix-rpi-components.service <<'__RUGIX_RPI_COMPONENTS_SERVICE__'
[Unit]
Description=Publish Raspberry Pi hardware component metadata for Rugix
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/rugix/rugix-rpi-components

[Install]
WantedBy=multi-user.target
__RUGIX_RPI_COMPONENTS_SERVICE__

    install_from_stdin 0644 /etc/rugix/state/docker.toml <<'__RUGIX_DOCKER_STATE__'
[[persist]]
directory = "/var/lib/containerd"

[[persist]]
directory = "/var/lib/docker"
__RUGIX_DOCKER_STATE__
}

install_rugix_admin_service() {
    if ! bool_is_true "${RUGIX_INSTALL_ADMIN}"; then
        log "Skipping Rugix Admin service"
        return
    fi

    validate_admin_address

    local tmp
    tmp="$(mktemp)"

    cat >"${tmp}" <<EOF
[Unit]
Description=Rugix Admin
ConditionFileIsExecutable=/usr/bin/rugix-admin

[Service]
ExecStart=/usr/bin/rugix-admin --address ${RUGIX_ADMIN_ADDRESS}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    log "Installing Rugix Admin service"
    backup_if_different "${tmp}" /usr/lib/systemd/system/rugix-admin.service
    "${SUDO[@]}" install -D -m 0644 "${tmp}" /usr/lib/systemd/system/rugix-admin.service
    rm -f "${tmp}"
}

configure_rugix_admin_firewall() {
    if ! bool_is_true "${RUGIX_INSTALL_ADMIN}"; then
        return
    fi
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        warn "firewall-cmd not found; skipping Rugix Admin firewall rule"
        return
    fi
    if ! "${SUDO[@]}" firewall-cmd --state >/dev/null 2>&1; then
        warn "firewalld is not running; skipping Rugix Admin firewall rule"
        return
    fi

    local port zone
    port="$(rugix_admin_port)"
    zone="$("${SUDO[@]}" firewall-cmd --get-default-zone)"

    log "Opening Rugix Admin firewall port ${port}/tcp in firewalld zone ${zone}"
    if ! "${SUDO[@]}" firewall-cmd --zone="${zone}" --query-port="${port}/tcp" >/dev/null 2>&1; then
        "${SUDO[@]}" firewall-cmd --zone="${zone}" --add-port="${port}/tcp" >/dev/null
    fi
    if ! "${SUDO[@]}" firewall-cmd --permanent --zone="${zone}" --query-port="${port}/tcp" >/dev/null 2>&1; then
        "${SUDO[@]}" firewall-cmd --permanent --zone="${zone}" --add-port="${port}/tcp" >/dev/null
    fi
}

enable_services() {
    log "Enabling Rugix Apps runtime services"

    "${SUDO[@]}" systemctl daemon-reload
    "${SUDO[@]}" systemctl enable \
        rugix-docker-runtime-components.service \
        rugix-rpi-components.service \
        rugix-revpi-components.service \
        rugix-apps-restore-units.service \
        rugix-apps-recover.service

    if bool_is_true "${RUGIX_INSTALL_ADMIN}"; then
        "${SUDO[@]}" systemctl enable rugix-admin.service
    fi
}

start_services() {
    if ! bool_is_true "${RUGIX_START_SERVICES}"; then
        log "Skipping service startup"
        return
    fi

    log "Starting Docker and publishing Rugix runtime components"
    "${SUDO[@]}" systemctl start docker.service
    "${SUDO[@]}" systemctl restart rugix-rpi-components.service
    "${SUDO[@]}" systemctl restart rugix-revpi-components.service
    "${SUDO[@]}" systemctl restart rugix-docker-runtime-components.service

    if ! "${SUDO[@]}" systemctl start rugix-apps-restore-units.service; then
        warn "could not restore existing Rugix app systemd units; continuing"
    fi

    if bool_is_true "${RUGIX_INSTALL_ADMIN}"; then
        "${SUDO[@]}" systemctl restart rugix-admin.service
    fi
}

print_summary() {
    log "Installed Rugix Apps runtime"
    log "Rugix Ctrl: $(rugix-ctrl --version)"
    log "Docker: $(docker --version)"
    log "Docker Compose: $(docker compose version)"
    log "Install app bundles with: sudo rugix-ctrl apps install <bundle.rugixb>"
}

main() {
    parse_args "$@"
    if bool_is_true "${RUGIX_INSTALL_ADMIN}"; then
        validate_admin_address
    fi
    setup_privileges
    require_live_system

    install_prerequisites
    install_docker
    install_rugix_binaries
    install_runtime_files
    install_rugix_admin_service
    configure_rugix_admin_firewall
    enable_services
    start_services
    print_summary
}

main "$@"
