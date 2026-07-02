# Try Rugix Apps on Revolution Pi

This example shows how to package and install a Docker Compose workload as a
Rugix App on a Revolution Pi. It is intended as a hands-on first test of Rugix
Apps: build or download one app bundle, prepare a RevPi, install the bundle with
`rugix-ctrl`, and then try an update-friendly application running on the device.

The app uses a RevPi DIO module. It reads input states `I_1` through `I_4`,
tracks DIO counter values `Counter_1` through `Counter_4`, writes measurements
to InfluxDB, provisions a Grafana dashboard, and serves a small web UI for
viewing inputs and switching outputs `O_1` through `O_4`.

The demo shows the whole workload installed as a Rugix App generation. Rugix can
replace the Compose file, container images, dashboards, and app metadata without
replacing the base OS. Runtime data stays in the app data directory, and failed
activations can be rolled back.

> [!CAUTION]
> This is a demo app. It exposes local services and uses demo credentials. Try it
> on a trusted network only, and harden the configuration before adapting it for
> production.

## Get the App Bundle

The fastest path is to download a prebuilt bundle from the GitHub releases page:

<https://github.com/rugix/rugix-example-revpi/releases>

Download these two files from the release you want to try:

- `revpi-dio-grafana.rugixb`
- `revpi-dio-grafana.rugixb-hash`

That is all you need for the installation step below.

If you want to build the bundle yourself, install:

- `rugix-bundler`
- `skopeo`
- `podman` or Docker with Buildx/QEMU support for `linux/arm64`

On Debian or Ubuntu, `skopeo` and `podman` are available through apt:

```sh
sudo apt-get update
sudo apt-get install -y skopeo podman
```

Download `rugix-bundler` from the Rugix release used by this repository:

<https://github.com/rugix/rugix/releases/tag/v1.3.0-dev.2>

Put the binary on your `PATH` as `rugix-bundler`, or set `RUGIX_BUNDLER` to its
full path when running the build script.

From the repository root, run:

```sh
apps/revpi-dio-grafana/build.sh
```

The build writes:

```text
apps/revpi-dio-grafana/build/revpi-dio-grafana.rugixb
apps/revpi-dio-grafana/build/revpi-dio-grafana.rugixb-hash
```

The build script packages `docker-compose.yml`, the Grafana configuration, the
Rugix component metadata, and all required container images. During installation,
Rugix loads the bundled images and starts the Compose workload from the installed
app generation.

## Prepare the RevPi

You need a RevPi that has Docker, Docker Compose, `rugix-ctrl`, and the Rugix
Apps runtime services installed. Choose one of these paths.

### Stock RevPi OS

On a stock RevPi OS installation, run the setup script:

```sh
curl -fsSL https://raw.githubusercontent.com/rugix/rugix-example-revpi/main/apps/setup.sh \
    -o setup-rugix-apps.sh
sudo bash setup-rugix-apps.sh
```

The script installs:

- Docker and the Docker Compose plugin.
- `rugix-ctrl`, `rugix-admin`, and `rugix-bundler`.
- Rugix Apps restore and recovery systemd units.
- Runtime component publisher services for Docker, Raspberry Pi, and RevPi
  hardware metadata.
- Rugix Admin, enabled by default on port `8088`.

The script does not convert the stock OS into a Rugix A/B boot-managed system.
It only adds the runtime needed to try Docker-backed Rugix Apps.

### Prebuilt Rugix Apps Image

You can also flash a prebuilt image from this repository's GitHub releases page:

<https://github.com/rugix/rugix-example-revpi/releases>

Use an image artifact named like:

```text
revpi-rugix-apps.img.zst
```

Flash it to the RevPi storage. For example, with `bmaptool`:

```sh
sudo bmaptool copy revpi-rugix-apps.img.zst /dev/sdX
```

Replace `/dev/sdX` with the actual target device. Then boot the RevPi and log in
with:

```text
user: pi
password: revolutionpi
```

The RevPi first-login setup resets those demo credentials to the
machine-specific defaults for the device.

## Configure the DIO Module

Both preparation paths need the same hardware setup.

Attach a RevPi DIO module and configure it in PiCtory. For every input you want
to use as a counter, set the corresponding `InputMode_N` to “Counter, rising
edge” or “Counter, falling edge”. Save the configuration as the start config and
reset the driver.

The app bind-mounts the PiCtory configuration from:

```text
/etc/revpi/config.rsc
```

If that file is missing, the controller container cannot start. The RevPi DIO
supports at most 6 configured counters per module; this demo uses 4.

## Install the App

Copy the bundle and hash to the RevPi:

```sh
scp revpi-dio-grafana.rugixb revpi-dio-grafana.rugixb-hash pi@RevPi.local:/home/pi/
```

If you built the bundle locally, copy the files from
`apps/revpi-dio-grafana/build/`.

Log in and install the app:

```sh
ssh pi@RevPi.local
sudo rugix-ctrl apps install \
    --bundle-hash "$(cat revpi-dio-grafana.rugixb-hash)" \
    revpi-dio-grafana.rugixb
```

After installation, open:

- DIO control UI: `http://<revpi>:8090`
- Grafana: `http://<revpi>:3000`
- InfluxDB: `http://<revpi>:8086`

Demo credentials:

- Grafana: `admin` / `revpi`
- InfluxDB: `revpi` / `revpi-influx-password`

Useful commands on the device:

```sh
sudo rugix-ctrl apps info revpi-dio-grafana
sudo docker ps
sudo docker logs revpi-dio-grafana-dio-controller-1
sudo docker logs revpi-dio-grafana-grafana-1
```

If activation fails, Rugix rolls the app back. Fix the bundle or device setup,
then run the install command again.

## Rugix Admin

If you used the stock-OS setup script or a prebuilt image with Rugix Admin
enabled, Rugix Admin is available at:

```text
http://<revpi>:8088
```

It provides a local web interface for inspecting the Rugix system state and
installed apps. Keep port `8088` reachable only from trusted networks.
