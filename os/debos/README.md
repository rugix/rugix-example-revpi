<!--
SPDX-FileCopyrightText: 2024-2026 KUNBUS GmbH
SPDX-FileCopyrightText: 2026 Silitics GmbH

SPDX-License-Identifier: GPL-2.0-or-later
-->

# Try Rugix OS Images on Revolution Pi

This directory contains the debos workflow for Rugix-managed Revolution Pi
images. It is a practical starting point for trying full-system updates, Rugix
Apps, Rugix Admin, and optional Nexigon fleet management on real RevPi hardware.

This workflow builds on KUNBUS's REVPI-4862 Rugix integration work for the RevPi
debos workflow, specifically this
[`revolutionpi/debos-build` tree snapshot](https://gitlab.com/revolutionpi/debos-build/-/tree/2664b4968b5c5ef48ccc425c70cf5fafbb701bb4).
This repository uses that work's Rugix image layout, bootstrapping, and bundle
generation changes. It keeps the familiar RevPi flavours and package setup,
then adds:

- A Rugix-compatible partition layout and boot configuration.
- A/B system updates with Raspberry Pi `tryboot`.
- Managed persistent state for selected system files and application data.
- Docker-backed Rugix Apps support.
- Optional Rugix Admin for local device management.
- Optional Nexigon integration for provisioning, remote access, and OTA rollout.

The Rugix image layout uses Raspberry Pi `tryboot` for A/B system updates. Updates
are written to the inactive system slot, and the device can fall back if the new
system does not boot. The example image also keeps selected system state
persistent across updates and Rugix factory resets.

The easiest way to start is to flash a prebuilt image from this repository's
GitHub releases page. Build locally only when you want to customize the image or
try the debos workflow itself.

> [!CAUTION]
> This is a demo image. It may expose local services and use demo credentials.
> Try it on a trusted network only, and harden the configuration before adapting
> it for production.

## Start with a Prebuilt Image

Download the latest release artifacts from:

<https://github.com/rugix/rugix-example-revpi/releases>

For a first test, download the provisioning image and the matching `.bmap` file:

```text
revpi-rugix-apps-nexigon.img.zst
revpi-rugix-apps-nexigon.bmap
```

This image includes:

- Rugix A/B system updates.
- Docker and the Rugix Apps runtime.
- Rugix Admin on port `8088`.
- Nexigon Agent with local provisioning enabled.
- Nexigon remote commands, terminal access, and Rugix OTA integration.

Flash the image to the RevPi storage. With `bmaptool`:

```sh
sudo bmaptool copy revpi-rugix-apps-nexigon.img.zst /dev/sdX
```

Replace `/dev/sdX` with the actual target device. Boot the RevPi and log in with:

```text
user: pi
password: revolutionpi
```

On first boot, the image sets the hostname from the RevPi serial number when it
can read the device's HAT EEPROM. It does not rewrite the `pi` password.

After boot, Rugix Admin is available at:

```text
http://<revpi>:8088
```

Keep port `8088` reachable only from trusted networks.

## Try Nexigon

Rugix handles robust update installation and rollback on the device. It can be
used purely offline or locally, and it can be integrated with other fleet
management systems. Nexigon is the integration chosen for this example because
it provides the most native Rugix workflow and is built by the Rugix authors.
It adds the fleet-management layer around Rugix: remote access, device
inventory, monitoring, audit logging, and OTA rollout orchestration.

Create or sign in to a Nexigon account:

<https://nexigon.cloud>

After creating an organization in Nexigon, open the **Fleet/Devices** page and
click **Add Device**. The provisioning flow shows a pairing key and asks you to
send it to the device. From a machine that can reach the RevPi, run:

```sh
curl --data "XXXXXX-XXXX" http://DEVICE_ADDRESS:51337/pair
```

Replace `DEVICE_ADDRESS` with the RevPi hostname or IP address.

The provisioning image opens port `51337` for local pairing. After pairing, the
device appears in Nexigon and can use the included remote commands, terminal, and
Rugix OTA integration.

## Try Rugix Apps

The prebuilt provisioning image includes the Docker-backed Rugix Apps runtime.
You can install the RevPi DIO Grafana app bundle from this repository without
building a new OS image.

Follow the [app walkthrough](../../apps/revpi-dio-grafana/README.md).

That guide shows how to download or build the app bundle and install it with:

```sh
sudo rugix-ctrl apps install \
    --bundle-hash "$(cat revpi-dio-grafana.rugixb-hash)" \
    revpi-dio-grafana.rugixb
```

## Build an Image Locally

Local builds are useful when you want to change the image contents, bake in a
Nexigon deployment token, adjust the output name, or generate your own update
bundle.

Install Podman on the build machine. The build needs Linux container support and
enough free disk space for the temporary image, build container, and generated
artifacts. The `run-debos` helper builds and runs a container based on
`docker.io/godebos/debos:v1.1.6`, installs the small build-side tools needed by
this workflow, and then invokes `debos` inside the container.

From the repository root:

```sh
cd os/debos
```

Build a Rugix image with Docker-backed Rugix Apps and Rugix Admin:

```sh
./run-debos \
    -tflavour:lite \
    -tdocker:true \
    -trugix_apps:true \
    -trugix_admin:true \
    -toutput:revpi-rugix-apps \
    revpi.yaml
```

Build the provisioning image used for the recommended first test:

```sh
./run-debos \
    -tflavour:lite \
    -tdocker:true \
    -trugix_apps:true \
    -trugix_admin:true \
    -tnexigon:true \
    -tnexigon_provisioning:true \
    -toutput:revpi-rugix-apps-nexigon \
    -tversion:"demo-$(date +%Y%m%d%H%M%S)" \
    revpi.yaml
```

Artifacts are written to `build/`. For a Rugix image, expect files like:

```text
build/revpi-rugix-apps-nexigon.img.zst
build/revpi-rugix-apps-nexigon.bmap
build/revpi-rugix-apps-nexigon.rugixb
build/revpi-rugix-apps-nexigon.rugixb-hash
```

The `.img.zst` file is the flashable image. The `.rugixb` file is a full-system
update bundle that can be installed on an already running Rugix-managed RevPi.

## Common Build Variables

- `flavour`: Image flavour. Default: `default`. Common demo value: `lite`.
- `type`: Image type. Use `rugix` for Rugix-managed images. Default: `rugix`.
- `docker`: Install Docker. Default: `false`.
- `rugix_apps`: Install the Rugix Apps runtime. Default: follows `docker`.
- `rugix_admin`: Install and enable Rugix Admin. Default: `false`.
- `nexigon`: Install and configure Nexigon integration. Default: `false`.
- `nexigon_provisioning`: Enable local Nexigon pairing on port `51337`. Default:
  `false`.
- `version`: Version embedded in `/etc/rugix/system-build-info.json` when
  Nexigon is enabled. Default: the output name.
- `rugix_bundle`: Generate a Rugix system update bundle for Rugix images.
  Default: `true`.
- `gen_sbom`: Generate a SPDX SBOM with `syft`. Default: `false`.
- `gen_vuln_report`: Generate a vulnerability report with `grype`; this also
  enables SBOM generation. Default: `false`.

The underlying RevPi build still supports the usual `minimal`, `basic`, `lite`,
and `default` flavours from the upstream debos workflow.
