# RevPi DIO Grafana App

This Rugix App turns a Revolution Pi with a RevPi DIO module into a small local
counter and output-control dashboard. It reads DIO input states and DIO counter
values with `revpimodio2`, writes state, counter, and rate metrics to InfluxDB
2, serves a small local control UI, and provisions a Grafana dashboard from
versioned JSON files.

It is based on the Grafana/InfluxDB idea from the Revolution Pi tutorial, but it
does not require a RevPi AIO module. The default setup reads direct input states
`I_1` through `I_4`, counter values `Counter_1` through `Counter_4`, and exposes
output controls for `O_1` through `O_4`.

## Hardware Setup

Use PiCtory on the RevPi to add your RevPi DIO module. For the inputs you want
to count, set `InputMode_N` to `Counter, rising edge` or
`Counter, falling edge`. Save the configuration as the start config and reset
the driver.

The app bind-mounts the PiCtory configuration file into the controller
container.
On current RevPi images, `/etc/revpi/config.rsc` may be a symlink to the real
file under PiCtory's project directory; Docker resolves that host-side symlink
when mounting the file. If your image stores the active config somewhere else,
set `REVPI_CONFIG_RSC_HOST` before installing or starting the app.

The DIO module does the counting and exposes signed 32-bit values named
`Counter_1`, `Counter_2`, and so on in the process image. The controller reads
those values and calculates a display rate from counter deltas.

The local web UI controls the outputs listed in `DIO_OUTPUT_NAMES`. When outputs
are configured, the controller opens `revpimodio2` with `shared_procimg=True` so
output writes are applied directly instead of continuously rewriting the whole
output process image. If the app should be read-only, set `DIO_OUTPUT_NAMES` to
an empty value before building or installing the bundle; in that mode it opens
`revpimodio2` in monitoring mode.

If your PiCtory input names differ from the defaults, edit `DIO_INPUT_NAMES` in
`docker-compose.yml` before building the bundle. If you configure different
counters or outputs, edit `DIO_COUNTER_NAMES` or `DIO_OUTPUT_NAMES` as well.

The RevPi DIO supports at most 6 configured counters per module. The app's
default four-counter setup stays inside that limit.

By default, the app does not reset hardware counters. Set
`RESET_COUNTERS_ON_START=true` in `docker-compose.yml` only if each app start
should reset the configured counter IOs through `revpimodio2.reset()`.

Do not enable counter reset while another process controls DIO outputs from the
same process image.

## Build the App Bundle

From the `rugix-example-revpi` repository root:

```sh
tools/download-rugix-bundler.sh
tools/build-apps.sh --app revpi-dio-grafana --platform linux/arm64
```

The bundle and hash are written to:

```text
dist/revpi-dio-grafana.rugixb
dist/revpi-dio-grafana.rugixb-hash
```

The Docker Compose file is the single source of image information. The bundler
copies registry images with Skopeo, builds the local controller image from the
Compose `build:` entry with Podman by default, and rewrites the packaged Compose
file to Rugix-owned bundle-local image tags with `pull_policy: never`. During
installation, Rugix loads the shipped image tarballs before starting Compose, so
activation uses the bundled images and does not pull from registries.

If you need the packaged Compose file to keep the original `image:` references,
pass `--disable-pinning` to `rugix-bundler apps pack docker-compose`. The images
are still bundled, but they are stored under the original Compose references
instead of Rugix-owned content tags.

For CI or a quick local syntax check without bundling images:

```sh
tools/build-apps.sh --app revpi-dio-grafana --no-images
```

Do not install a `--no-images` bundle on a stock device unless all referenced
images already exist locally or the Compose file is allowed to pull them.

## Install on a Rugix-Native RevPi

Build and flash a RevPi image that includes Docker and the Rugix Apps recovery
units:

```sh
./run-bakery bake image revpi-lite-apps
```

After the device is booted and configured in PiCtory, copy the app bundle to the
RevPi and install it:

```sh
scp dist/revpi-dio-grafana.rugixb dist/revpi-dio-grafana.rugixb-hash pi@RevPi.local:/home/pi/
ssh pi@RevPi.local
sudo rugix-ctrl apps install \
    --bundle-hash "$(cat revpi-dio-grafana.rugixb-hash)" \
    revpi-dio-grafana.rugixb
```

Open Grafana at `http://<revpi>:3000` and log in with `admin` / `revpi`.
InfluxDB is available at `http://<revpi>:8086` with user `revpi` and password
`revpi-influx-password`. The local DIO control UI is available at
`http://<revpi>:8090`.

## Install on a Stock Revolution Pi Image

The stock image needs Docker, `rugix-ctrl`, and the Rugix Apps recovery units
before it can install app bundles:

```sh
ssh pi@RevPi.local
curl -fsSLO https://raw.githubusercontent.com/rugix/rugix/main/installer/install-rugix-ctrl-apps-runtime.sh
sudo bash install-rugix-ctrl-apps-runtime.sh
```

Then install the bundle in the same way:

```sh
scp dist/revpi-dio-grafana.rugixb dist/revpi-dio-grafana.rugixb-hash pi@RevPi.local:/home/pi/
ssh pi@RevPi.local
sudo rugix-ctrl apps install \
    --bundle-hash "$(cat revpi-dio-grafana.rugixb-hash)" \
    revpi-dio-grafana.rugixb
```

## Update and Migration Story

Rugix Apps installs every update as a new immutable generation. The app keeps
InfluxDB, Grafana runtime data, and the controller's last-seen counter state in
`RUGIX_APP_DATA_DIR`, so app updates can replace the container images, compose
file, and dashboards without deleting collected data.

InfluxDB 2 does not have a relational schema. The controller treats measurements
and field types as a versioned contract:

- On startup, it creates the configured bucket if it is missing.
- It writes a `revpi_app_schema` marker with `APP_SCHEMA_VERSION`.
- Incompatible measurement or field changes should use a new measurement name
  or a higher schema version instead of changing field types in place.
- Local rate-calculation state in `dio-controller/state.json` has its own
  `schemaVersion` and is migrated by the controller process at startup. Updates
  from older bundles also read the previous `logger/state.json` location once.
  This state is not the source of truth for counts; the DIO counter values are.

Grafana dashboards are provisioned from `config/grafana/dashboards`. Updating
the Rugix App bundle updates these JSON files; Grafana reloads provisioned
dashboards from the new generation.

The included dashboard queries the default bucket `revpi_dio`. If you change
`INFLUX_BUCKET` in `docker-compose.yml`, update the dashboard JSON at the same
time.

## Useful Commands

```sh
sudo rugix-ctrl apps info revpi-dio-grafana
sudo rugix-ctrl apps rollback revpi-dio-grafana
sudo docker ps
sudo docker logs revpi-dio-grafana-dio-controller-1
sudo docker logs revpi-dio-grafana-grafana-1
```

If activation fails and Rugix rolls the app back, Docker removes the compose
containers. Re-run `sudo rugix-ctrl apps install ...` after rebuilding the
bundle, or temporarily run `sudo docker compose` from an extracted generation
directory if you need to inspect a failing container before rollback.

If the controller reports that it can not read `config.rsc`, check that PiCtory
has written the start configuration:

```sh
ls -l /etc/revpi/config.rsc
```

If that path is not the active config on your image, install with an override:

```sh
sudo REVPI_CONFIG_RSC_HOST=/path/to/config.rsc rugix-ctrl apps install \
    --bundle-hash "$(cat revpi-dio-grafana.rugixb-hash)" \
    revpi-dio-grafana.rugixb
```
