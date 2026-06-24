# Rugix Example Integration for Revolution Pi

This repository provides a template for building ready-to-flash
[Revolution Pi](https://revolutionpi.com/) system images with
[Rugix](https://rugix.org). It adapts the official Kunbus Trixie image
pipeline to Rugix Bakery and uses Rugix' Raspberry Pi tryboot target for A/B
system updates.

The Kunbus-specific pieces are based on the official
[debos-build](https://gitlab.com/revolutionpi/debos-build) pipeline, which
Kunbus documents as the source for custom RevPi images. The older
[imagebakery](https://github.com/RevolutionPi/imagebakery) repository is
deprecated.

Kunbus' current `debos-build` `master` defaults to Debian Trixie with the
password `revolutionpi`, so this template follows that current upstream
pipeline directly.

With this template you get:

- CI/CD-compatible declarative image builds with Rugix Bakery.
- A/B system updates through Raspberry Pi tryboot.
- Kunbus RevPi kernel, firmware, boot configuration, and apt repositories.
- Kunbus package groups for lite and default RevPi images.
- Managed persistent state for RevPi configuration, PiCtory, RevPiPyLoad,
  NetworkManager, CODESYS RevPi data, and MQTT/OPC UA settings.
- Rugix SSH host-key hydration through `core/ssh`.
- Optional [Nexigon](https://nexigon.cloud) integration for fleet-wide OTA
  orchestration and remote access.

If you are new to Rugix, start with the
[Getting Started Guide](https://rugix.org/docs/getting-started/).

> [!NOTE]
> **Support:** This repository is an example integration. Review the recipes,
> credentials, and update policy before using it in production.

## Quick Start

The build runs in a container and requires Linux or macOS with Docker or Podman
installed.

Clone this repository and enter it:

```sh
git clone https://github.com/rugix/rugix-example-revpi.git
cd rugix-example-revpi
```

Pick one of the available systems:

- `revpi-lite`: Trixie, Kunbus lite package set, no desktop GUI.
- `revpi-lite-apps`: `revpi-lite` base plus Docker and Rugix Apps recovery
  services for the app bundle examples in `apps/`.
- `revpi-default`: Trixie, lite base plus the GUI packages from Kunbus'
  default flavour.

Build an image and update bundle:

```sh
./run-bakery bake bundle revpi-lite
```

or:

```sh
./run-bakery bake bundle revpi-default
```

The image and update bundle are written to `build/<system>/`. Flash
`system.img` to the target boot medium and boot the RevPi. The default user is
`pi` with password `revolutionpi`, matching Kunbus' current debos default.

To install an update, transfer the update bundle (`system.rugixb`) to the device
and run:

```sh
rugix-ctrl update install --insecure-skip-bundle-verification system.rugixb
```

The example uses `--insecure-skip-bundle-verification` because bundles are not
signed by default. For production, configure
[signed updates](https://rugix.org/docs/ctrl/updates/signed-updates/).

## Rugix Apps Example

The `apps/` directory contains a self-contained Rugix App example for a RevPi
with a DIO module:

- `apps/revpi-dio-grafana`: reads DIO input states and DIO counter values
  configured in PiCtory with `revpimodio2`, writes samples to InfluxDB 2, and
  provisions a Grafana dashboard.

Build the app bundle:

```sh
tools/download-rugix-bundler.sh
tools/build-apps.sh --app revpi-dio-grafana --platform linux/arm64
```

For Rugix-native devices, build `revpi-lite-apps` to get Docker and the Rugix
Apps recovery services in the base image:

```sh
./run-bakery bake image revpi-lite-apps
```

For stock Revolution Pi images, use the shared Rugix Ctrl Apps runtime
installer from the main Rugix repository:

```sh
curl -fsSLO https://raw.githubusercontent.com/rugix/rugix/main/installer/install-rugix-ctrl-apps-runtime.sh
sudo bash install-rugix-ctrl-apps-runtime.sh
```

See `apps/revpi-dio-grafana/README.md` for the complete tutorial.

## How It Works

The base layer starts from `core/debian-trixie`, installs the official
Revolution Pi and Raspberry Pi apt repositories, then installs the RevPi kernel,
firmware, boot files, and packages used by Kunbus' debos recipes.

The Trixie layer also installs the beta warning MOTD from Kunbus' current
`debos-build` `master`, because that is part of the upstream Trixie pipeline at
the time this template was created.

The Rugix system target is `rpi-tryboot`. Rugix Bakery creates the A/B partition
layout and patches the boot command line for `rugix-ctrl`; the RevPi recipes add
the hardware-specific `/boot/firmware/config.txt`, firmware files, initramfs
support, and Kunbus userspace integrations.

## Included Kunbus Package Groups

`revpi-base-system` installs the boot-critical pieces:

- `init`, `udev`, `kmod`, `linux-base`, `raspi-firmware`,
  `initramfs-tools`
- `linux-image-revpi-v8`, `revpi-base-files`, `revpi-firmware`,
  `revpi-tools`

`revpi-minimal-system` installs the minimal image packages used by Kunbus,
including NetworkManager, SSH, RevPi NetworkManager configuration, firmware,
console setup, time synchronization, and wireless support.

`revpi-basic-packages` adds the common RevPi services:

- `picontrol`, `pitest`, PiCtory Apache integration, RevPi webserver firewall
  integration, Cockpit RevPi integration, Modbus client/server, Avahi, and
  common troubleshooting tools.

`revpi-lite-packages` adds the lite image package set:

- serial/CAN tooling, RevPiPyLoad, `python3-revpimodio2`, Bluetooth support,
  RevPi device info, RevPi SOS report, OPC UA server, MQTT client, security
  package, flashrom, swap configuration, and firmware additions.

`revpi-default-packages` adds the GUI/default image extras:

- `chromium`, `revpi-ui`, and `revpicommander`.

## Persistent State

The recipe `revpi-rugix-state` installs `/etc/rugix/state/revpi.toml` to keep
runtime RevPi data across immutable system updates. It persists:

- `/etc/revpi` and `/etc/revpipyload`
- `/etc/NetworkManager/system-connections` and `/var/lib/NetworkManager`
- `/var/lib/systemd/rfkill`
- `/var/lib/revpipyload`
- `/var/opt/codesys/PlcLogic/revpi`
- RevPiPyLoad, MQTT, and OPC UA default configuration files
- `/root` and `/home/pi`

SSH host keys are handled by Rugix' `core/ssh` recipe instead. Its
`hydrate-ssh-host-keys.service` stores generated host keys in Rugix-managed SSH
state and hydrates `/etc/ssh` during boot. Adjust this file if your application
stores additional mutable state.

## Nexigon Integration

This repository ships with an optional Nexigon mixin in `mixins/nexigon.toml`.
The release scripts build systems with `--enable-mixin nexigon`, upload the
generated artifacts to Nexigon Hub, and promote builds with tags.

To use it, copy `env.template` to `.env` and fill in:

```sh
NEXIGON_HUB_URL="https://eu.nexigon.cloud"
NEXIGON_TOKEN=<device-deployment-token>
NEXIGON_REPOSITORY=<repository-id>
NEXIGON_PACKAGE=<package-name>
```

Then run:

```sh
./scripts/prepare-release.sh
./scripts/build-release.sh revpi-lite revpi-default
./scripts/upload-release.sh
./scripts/stabilize-release.sh
```

The scripts require `nexigon-cli` and `jq`. Set
`NEXIGON_CLI=/path/to/nexigon-cli` if the CLI is not on `PATH`.

## Recipe Reference

### revpi-repositories

Installs temporary bootstrap apt sources and vendored archive keys for the
Revolution Pi and Raspberry Pi repositories, installs `revpi-repo` and
`raspberrypi-archive-keyring`, then switches apt to the packaged keyrings.
The Debian/RevPi suite is read from `/etc/os-release` in the base system.

### revpi-base-system

Installs the RevPi kernel, firmware, initramfs support, RevPi base files, and
boot configuration. It copies `/boot/firmware` into the Rugix boot root so the
Rugix-generated tryboot image contains the Kunbus firmware assets.

### revpi-minimal-system

Applies Kunbus' minimal image configuration: hostname, locale, keyboard,
timezone, NetworkManager defaults, disabled Wi-Fi/Bluetooth rfkill state, RevPi
machine metadata, and enabled SSH/NetworkManager/time synchronization services.

Parameter:

- `hostname`: default `RevPi`.

### revpi-default-user

Creates the default RevPi user, sets the password, assigns the usual Raspberry
Pi/RevPi groups, and installs sudo rules including access to
`revpi-factory-reset`.

Parameters:

- `user`: default `pi`.
- `password`: default `revolutionpi`.

### revpi-basic-packages

Installs PiCtory, piControl, RevPi web services, Cockpit integration, Modbus
services, Avahi, and base troubleshooting tools. The default user is added to
the `picontrol` group.

### revpi-lite-packages

Installs the Kunbus lite package set and applies the matching service defaults:
mask Raspi config/cpufreq services, disable `dphys-swapfile`, set swap size to
512 MiB, and use `multi-user.target`.

### demo-docker-app-runtime

Installs Docker, persists Docker state, and enables the Rugix Apps recovery
services required by Docker Compose app bundles.

### revpi-default-packages

Installs the default image GUI additions: Chromium, RevPi UI, and
RevPiCommander.

### revpi-trixie-motd

Installs the beta warning MOTD from Kunbus' current Trixie debos pipeline. This
recipe is included by the base layer.

### revpi-rugix-state

Installs Rugix state configuration for RevPi runtime data and generated
identity files.

### revpi-image-prep

Cleans transient build artifacts and resets generated machine identity before
the image is cloned.

## Licensing

This project is licensed under either
[MIT](https://github.com/rugix/rugix/blob/main/LICENSE-MIT) or
[Apache 2.0](https://github.com/rugix/rugix/blob/main/LICENSE-APACHE) at your
option.
