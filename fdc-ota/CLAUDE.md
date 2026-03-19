# CLAUDE.md

> For AI agent guidance (any agent), see [AGENTS.md](./AGENTS.md).

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FDC-OTA is a firmware Over-the-Air update system for Foxtron EV vehicles. It manages ECU firmware delivery across multiple vehicle models (D21F, D31L, TA2, and others) via wireless networks. The system supports three deployment targets: automotive Linux (aarch64), Android IVI (in-vehicle infotainment), and 5G T-Box.

## Commands

### Build

```bash
make build              # Build all crates for aarch64-unknown-linux-gnu (requires NXP FSL Auto SDK)
make build-ivi          # Build Android IVI APK via Gradle
make build-tbox         # Build T-Box ECU binary for TI AM62XX target
make build-for-ci       # CI build with MODEL env var (d21f/d31l/ta2)
```

### Lint

```bash
make lint               # cargo clippy -- -D warnings + cargo fmt --check
make lint-for-ci        # Full lint across all model/feature combinations
```

### Test

```bash
make test               # Run workspace tests (excludes ota-xsumo, timeout 600s)
make test-for-ci        # Full CI test suite (requires DBus, vcan2, root for network setup)
```

**Running a single test:**
```bash
cargo test --package ota-host --lib module::test_name
cargo test --package ota-vehicle --lib backend::test_name -- --include-ignored
```

**Test prerequisites (for integration tests):**
```bash
make run-dbus-daemon    # Set up DBus daemon
ip link add vcan2 type vcan && ip link set vcan2 up  # Virtual CAN interface
cp ota-host/tests/D21_Routing.toml /etc/uds/Routing.toml  # UDS routing config
```

### Coverage

```bash
make coverage-d21f      # Coverage report for d21f model (HTML, opens browser)
make coverage-d31l      # Coverage report for d31l model
make coverage-ta2       # Coverage report for ta2 model
make coverage-all       # Run all model coverage reports sequentially
make coverage-for-ci    # CI coverage: merged LCOV + HTML + JSON per model
```

## Architecture

The project is a **Cargo workspace** with five primary crates:

### Crates

- **ota-host** — Host-side orchestration service. Manages the entire vehicle update process: coordinates with the OTA backend, drives workflows/state machines, and communicates with the vehicle via DDS/CAN.
- **ota-vehicle** — Vehicle-side coordinator. Runs on the main vehicle ECU and orchestrates updates across all ECUs. Interfaces with the host via DDS and with ECUs via UDS/CAN.
- **ota-ecu** — ECU update client. Has two platform variants: `ivi` (Android in-vehicle infotainment, built via Gradle/JNI) and `tbox` (5G T-Box modem, TI AM62XX target). Default build is for standard Linux ECUs.
- **ota-utils** — Shared utilities: CAN communication (socketcan), DBus integration, signal handling, and upgrade helpers.
- **ota-xsumo** — XSUMO protocol implementation with FastDDS support. Built separately targeting aarch64 with the `fastdds` feature.

### Local Libraries (`lib/`)

- **dust-dds** — Custom DDS (Data Distribution Service) middleware for pub/sub messaging between host, vehicle, and ECUs.
- **srec** — Motorola S-record file format parser/writer.
- **xsumo** — XSUMO protocol bindings.
- **tbox** — T-Box specific utilities.

### Feature Flags

Vehicle model selection is done at compile time via Cargo features:

| Flag | Description |
|------|-------------|
| `d21f`, `d21m` | D21 vehicle variants |
| `d31l`, `d31l24`, `d31f25`, `d31h`, `d31x` | D31 vehicle variants |
| `ta2` | TA2 vehicle model |
| `p71`, `pe1` | P71/PE1 models |
| `ivi` | Android IVI platform (ota-ecu only) |
| `tbox` | T-Box 5G modem platform (ota-ecu only) |
| `fastdds` | FastDDS middleware (ota-xsumo only) |

### Communication Protocols

- **DDS** (via dust-dds) — Primary messaging between host ↔ vehicle ↔ ECUs
- **CAN / vcan** — Vehicle bus communication (vcan1, vcan2, vcan3 for testing)
- **DoIP** — Diagnostic over IP for remote updates
- **UDS** — Unified Diagnostic Services for ECU programming
- **DBus** — System service communication on the vehicle
- **MQTT / AWS IoT** — Cloud backend connectivity

### Cross-Compilation

- **Main target:** `aarch64-unknown-linux-gnu` with NXP FSL Auto 40.0 SDK at `/opt/fsl-auto/40.0/`
- **T-Box target:** TI AM62XX SDK at `/opt/ti-processor-sdk-linux-am62xx-evm-10.01.10.04/`
- **Android IVI:** Built via `./gradlew assembleFullRelease` (standard Gradle Android build)
- The `SDK` variable in Makefile sources the appropriate cross-compilation environment

### CI/CD

GitHub Actions workflows in `.github/workflows/`:
- **main.yml** — Runs on every push: lint → test → coverage → build (all models + IVI + tbox) → release (on tags)
- **test-coverage.yml** — Runs on PRs: generates per-model coverage and posts comment with `COVERAGE_THRESHOLD=50`

CI uses self-hosted runners with the `foxtronevtech/rust:v3.4` Docker image that includes the cross-compilation toolchain.
