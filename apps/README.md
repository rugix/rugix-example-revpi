# Rugix Apps for Revolution Pi

This directory contains Rugix App examples that can be built into `.rugixb`
application bundles independently from the base RevPi image.

## Examples

| App | Purpose |
| --- | --- |
| `revpi-dio-grafana` | Read RevPi DIO hardware counter values, store them in InfluxDB 2, and visualize state, counts, and rates in Grafana. |

## Build

From the repository root:

```sh
tools/download-rugix-bundler.sh
tools/build-apps.sh --app revpi-dio-grafana --platform linux/arm64
```

For a fast structural build without bundled container images:

```sh
tools/build-apps.sh --app revpi-dio-grafana --no-images
```
