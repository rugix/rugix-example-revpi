<!--
SPDX-FileCopyrightText: 2024-2026 KUNBUS GmbH
SPDX-FileCopyrightText: 2026 Silitics GmbH

SPDX-License-Identifier: GPL-2.0-or-later
-->

# Try Rugix OS Images on Revolution Pi

This directory contains the debos workflow for Rugix-managed Revolution Pi
images. It is a practical starting point for trying full-system updates, Rugix
Apps, Rugix Admin, and Nexigon fleet management on real RevPi hardware.

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
- Nexigon integration for provisioning, remote access, and OTA rollout.

The Rugix image layout uses Raspberry Pi `tryboot` for A/B system updates. Updates
are written to the inactive system slot, and the device can fall back if the new
system does not boot. The example image also keeps selected system state
persistent across updates and Rugix factory resets.

The easiest way to start is to flash a prebuilt image from this repository's
GitHub releases page. Build locally only when you want to customize the image or
try the debos workflow itself.

> [!CAUTION]
> This is a demo image. It may expose local services and use demo credentials.
> Its Rugix Ctrl daemon permits unsigned operations and other verification
> bypasses through `dangerously-insecure`.
> Try it on a trusted network only, and harden the configuration before adapting
> it for production.

## Start with a Prebuilt Image

Download the latest release artifacts from:

<https://github.com/rugix/rugix-example-revpi/releases>

For a first test, download the provisioning image and the matching `.bmap` file:

```text
revpi-rugix-nexigon.img.zst
revpi-rugix-nexigon.bmap
```

This image includes:

- Rugix A/B system updates.
- Docker and the Rugix Apps runtime.
- Rugix Admin on port `7492`.
- Nexigon Agent with local provisioning enabled.
- Nexigon remote commands, terminal access, Rugix OTA integration, and Rugix
  Apps management.
- Nexigon forwarding to all TCP ports on the device loopback interface.
- Nexigon remote access to the RevPi Web UI.
- PiCtory dashboard data as a Nexigon device property.

Flash the image to the RevPi storage. With `bmaptool`:

```sh
sudo bmaptool copy revpi-rugix-nexigon.img.zst /dev/sdX
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
http://<revpi>:7492
```

Keep port `7492` reachable only from trusted networks.

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
curl --data "XXXXXX-XXXX" http://DEVICE_ADDRESS:6947/pair
```

Replace `DEVICE_ADDRESS` with the RevPi hostname or IP address.

The provisioning image opens port `6947` for local pairing. After pairing, the
device appears in Nexigon and can use the included remote commands, terminal, and
Rugix OTA integration. The example permits Nexigon users with remote-access
permissions to forward any TCP port on the device loopback interface.

When Nexigon is enabled for a `basic`, `lite`, or `default` image, the build
also exposes the RevPi Web UI through a loopback-only Apache listener. The
corresponding Cockpit configuration accepts proxied browser origins below
`nexigon.dev`, `nexigon.cloud`, and `nexigon.eu`. The `minimal` flavour does not
install the RevPi web stack, so it does not include this export.

Nexigon-enabled images publish selected PiCtory dashboard data from
`/etc/revpi/config.rsc` to the
`com.kunbus.revpi.pictory.configuration` device property. The property is
updated when the configuration changes and only when its value differs.

Inspect the published property on the device with:

```sh
nexigon-agent device properties get \
    com.kunbus.revpi.pictory.configuration | jq
```

When `nexigon` and `rugix_apps` are both enabled, the image also installs the
commands Nexigon Hub uses to deploy, inspect, start, stop, roll back, and remove
Rugix Apps. The deployment command passes
`--insecure-skip-bundle-verification`, matching this example's development-only
security posture and allowing unsigned app bundles. Do not use this setting in
production.

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
    -toutput:revpi-rugix \
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
    -toutput:revpi-rugix-nexigon \
    -tversion:"demo-$(date +%Y%m%d%H%M%S)" \
    revpi.yaml
```

Artifacts are written to `build/`. For a Rugix image, expect files like:

```text
build/revpi-rugix-nexigon.img.zst
build/revpi-rugix-nexigon.bmap
build/revpi-rugix-nexigon.rugixb
build/revpi-rugix-nexigon.rugixb-hash
```

The `.img.zst` file is the flashable image. The `.rugixb` file is a full-system
update bundle that can be installed on an already running Rugix-managed RevPi.

## Common Build Variables

- `flavour`: Image flavour. Default: `default`. Common demo value: `lite`.
- `type`: Image type. Use `rugix` for Rugix-managed images. Default: `rugix`.
- `docker`: Install Docker. Default: `false`.
- `rugix_apps`: Install the Rugix Apps runtime. Default: follows `docker`.
- `rugix_ctrl_daemon`: Install and enable the privileged Rugix Ctrl daemon.
  Default: follows `rugix_admin`.
- `rugix_admin`: Install and enable Rugix Admin and the Rugix Ctrl daemon.
  Default: `false`.
- `rugix_admin_version`: Rugix Admin release tag. Default: `v0.5.0`.
- `rugix_admin_address`: Rugix Admin listen address. This demo defaults to
  `0.0.0.0:7492` so it is reachable from the local network; Rugix Admin itself
  defaults to loopback. Restrict the demo to a trusted network.
- `rugix_daemon_factory_reset`, `rugix_daemon_system_commit`,
  `rugix_daemon_system_reboot`, and `rugix_daemon_app_lifecycle`: Privileged
  daemon operations. Each defaults to the value of `rugix_admin`.
- `rugix_daemon_dangerously_insecure`: Permit bundle installation without
  signature verification and compatibility checks. Default: `true` for this
  example.
- `nexigon`: Install and configure Nexigon integration. Default: `false`.
- `nexigon_agent_version`: Nexigon Agent release to install. Default:
  `v0.6.0`.
- `nexigon_provisioning`: Enable local Nexigon pairing on port `6947`. Default:
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
