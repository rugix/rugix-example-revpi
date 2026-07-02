# Rugix Example Integration for Revolution Pi

This repository provides examples that you can adapt to integrate
[Rugix](https://rugix.org) into a [Revolution Pi](https://revolutionpi.com/)
(RevPi) system. Rugix is a toolkit for building embedded Linux systems and
safely updating them in the field. The provided examples cover both
fault-tolerant application updates and full OS updates. They also provide an
optional ready-made [Nexigon](https://nexigon.cloud) integration for
orchestrating fleet-wide OTA updates and remote device access.

The [app example](./apps/revpi-dio-grafana) packages a Docker Compose workload
as a Rugix App bundle. It reads RevPi DIO inputs and counters, exposes a small
Python web UI for viewing inputs and controlling outputs, writes measurements to
InfluxDB, and includes a Grafana dashboard.

The [debos example](./os/debos) shows how to build a Rugix-managed RevPi OS image from the
RevPi debos workflow. Beyond the standard workflow, it provides recipes for the Rugix Apps
runtime, Rugix A/B system updates, and optional integrations with Rugix Admin and
[Nexigon](https://nexigon.cloud) for device management at scale.

By adopting this stack for your device you get:

- CI/CD-compatible declarative image building pipeline.
- Fault tolerant A/B system updates with Raspberry Pi's `tryboot` mechanism.
- SBOM generation for compliance, e.g., with the Cyber Resilience Act.
- Fault-tolerant [application updates](https://rugix.org/docs/ctrl/application-management/), e.g., of Docker Compose stacks.
- [Managed system state](https://rugix.org/docs/ctrl/state-management/) for robustness and easy factory resets.
- Integration with [Nexigon](https://nexigon.cloud) for end-to-end device management.

> [!NOTE]
> **Support:** This repository is subject to [Tier 3: Example Integrations](https://rugix.org/support-commitment/#tier-example-integration) of our Support Commitment.

## Quick Start

If you want to start hands-on, pick the path that matches what you want to try:

- **Application updates on a stock RevPi:** start with the
  [app example](apps/revpi-dio-grafana/README.md) to build and
  install a Rugix App bundle for a Docker Compose application without
  replacing the base OS.
- **Custom image with debos:** start with the [dobos example](os/debos/README.md)
  when you want to build a custom OS image with RevPi's debos workflow and Rugix for
  system and application updates.

If you prefer to learn more about Rugix first, continue reading.

## Application and System Updates

For application updates, Rugix lets you update workloads independently from the
base OS. This matters because applications typically evolve at a different
cadence than the base OS and different devices may need to run different
applications on top of it. By separating both, you gain flexibility and reduce
maintenance effort. Rugix provides an efficient, secure, and safe mechanism for
installing and orchestrating application workloads (automated rollback in case
of failures, cryptographic signature verification, compatibility checks, delta
delivery). It can update anything from standalone binary services to full Docker
Compose stacks. This repository provides an example of a monitoring and control
app for RevPi built with Docker Compose, Python, InfluxDB 2, and Grafana. It can
be installed on a stock RevPi OS (needs runtime installation) as well as on
custom images built with support for Rugix Apps.

For system updates, Rugix lets you update the complete OS atomically with
automatic rollback in case anything goes wrong. If not handled carefully, a
failed OS update may leave the device in an unbootable state, requiring an
on-site visit or return trip to the manufacturer. The custom image example
provides Rugix A/B system updates, where the new system is written to an
inactive slot and the device automatically falls back if it does not boot.

If you are new to Rugix, check out the [Rugix website](https://rugix.org/) for
more introduction.

> [!IMPORTANT]
> While application updates are useful make sure that you can always update the
> base OS on production devices.

## Repository Structure

The repository is split into application examples and OS image examples:

- [`apps/revpi-dio-grafana`](apps/revpi-dio-grafana/README.md): Rugix App
  example and app-bundle build entry point.
- [`os/debos`](os/debos/README.md): image build using RevPi's debos workflow,
  with Rugix A/B system updates, managed state, Rugix Apps support, optional
  Rugix Admin, and optional Nexigon integration.

## Commercial Support

Rugix has been created and is maintained by [Silitics](https://silitics.com). Looking for commercial support? [We're here to help.](https://rugix.org/commercial-support) Need a fleet management solution? Check out [Nexigon](https://nexigon.cloud), by the creators of Rugix.

## Licensing

This repository contains files under multiple licenses. Files derived from or
based on the KUNBUS Revolution Pi debos workflow are licensed under
GPL-2.0-or-later as indicated by their SPDX headers and the REUSE metadata in
`os/debos`. Other original Rugix/Silitics material is licensed under either MIT or Apache
2.0 at your option, unless a file states a different license. Check the SPDX
headers for the authoritative per-file license.

---

Made with ❤️ for OSS by [Silitics](https://www.silitics.com)
