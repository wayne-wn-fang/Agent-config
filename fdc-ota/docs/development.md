# Development Environment

## Rust Toolchain

The workspace pins its Rust toolchain in `rust-toolchain.toml`. Always use the toolchain specified there — do not override it with `rustup override set` unless intentionally testing a different version.

Workspace edition: **2021**. Workspace version: **1.1.x** (see `Cargo.toml`).

---

## Cross-Compilation Setup

### Main Target: aarch64 (NXP FSL Auto SDK)

**Target triple:** `aarch64-unknown-linux-gnu`
**SDK path:** `/opt/fsl-auto/40.0/`

The Makefile sources the SDK environment before each cross-compilation step. If the SDK is not present at that path, the source step silently succeeds but the build will fail or produce native binaries.

```bash
# The Makefile does this internally:
source /opt/fsl-auto/40.0/environment-setup-aarch64-fsl-linux
```

To verify the SDK is active:
```bash
echo $CC    # should show aarch64-fsl-linux-gcc or similar
```

### T-Box Target: TI AM62XX

**SDK path:** `/opt/ti-processor-sdk-linux-am62xx-evm-10.01.10.04/`
**Build command:** `make build-tbox`

Same pattern as NXP — the Makefile sources the TI SDK environment before building `ota-ecu` with the `tbox` feature.

### Android IVI

**Build system:** Gradle (standard Android)
**Build command:** `make build-ivi` (runs `./gradlew assembleFullRelease`)
**Files:** `build.gradle`, `settings.gradle`, `gradle.properties`, `gradlew` at repo root; Android sources under `android/`

The IVI build does not require a cross-compilation SDK in the same sense — the Android NDK is managed by the Gradle/Android toolchain.

---

## Docker / CI Environment

**CI Docker image:** `foxtronevtech/rust:v3.4`

This image includes:
- The NXP FSL Auto 40.0 SDK
- The TI AM62XX SDK
- The Android SDK/NDK
- Rust toolchain matching `rust-toolchain.toml`
- All system libraries needed for integration tests

**CI runners:** Self-hosted GitHub Actions runners.

Running `make build` or `make test-for-ci` outside this Docker image will likely fail due to missing SDK paths or system libraries.

---

## Integration Test Prerequisites

Integration tests that exercise real protocol stacks are marked `#[ignore]` by default and require:

### 1. DBus Daemon

```bash
make run-dbus-daemon
# Sets DBUS_SESSION_BUS_ADDRESS in the environment
```

### 2. Virtual CAN Interface

```bash
ip link add vcan2 type vcan
ip link set vcan2 up
# Requires root / CAP_NET_ADMIN
```

### 3. UDS Routing Config

```bash
cp ota-host/tests/D21_Routing.toml /etc/uds/Routing.toml
# /etc/uds/ must exist; requires root for write
```

### Running Ignored Tests

```bash
cargo test --package ota-vehicle --lib -- --include-ignored
```

Without `--include-ignored`, integration tests are silently skipped (they report as ignored, not failed).

---

## Coverage Workflow

Coverage uses `cargo-llvm-cov` (integrated via `make coverage-*` targets).

```bash
make coverage-d21f      # Generates HTML report (opens browser) + LCOV
make coverage-for-ci    # Per-model: merged LCOV + HTML + JSON output
```

Coverage reports are output to `target/coverage/`. The CI workflow (`test-coverage.yml`) posts coverage as a PR comment when coverage is below `COVERAGE_THRESHOLD=50`.

Coverage targets require the same prerequisites as integration tests (DBus, vcan2) to include integration test coverage.

---

## Local Kellnr Registry

Some dependencies (`uds-app`, `uds-client`, `uds-fdc`, `uds-utils`, `rustdds`, `cmn-dbc`) are hosted on a private Kellnr registry. Cargo must be configured to authenticate with this registry to build from scratch. Check your `~/.cargo/config.toml` for the `[registries.kellnr]` entry. Without access to this registry, `cargo build` will fail with a registry fetch error.

---

## Repo Layout Quick Reference

```
fdc-ota/
├── ota-host/       # Host orchestrator crate
├── ota-vehicle/    # Vehicle coordinator crate
├── ota-ecu/        # ECU client crate (Linux/IVI/T-Box variants)
├── ota-utils/      # Shared utilities crate
├── ota-xsumo/      # XSUMO protocol crate (separate build)
├── lib/
│   ├── dust-dds/   # Custom DDS middleware (excluded from workspace)
│   ├── srec/       # S-record parser/writer
│   ├── xsumo/      # XSUMO protocol bindings
│   └── tbox/       # T-Box utilities
├── android/        # Android IVI application sources
├── cmn/            # Common/shared non-Rust resources
├── data/           # Static data files
├── scripts/        # Build and utility scripts
├── .github/
│   └── workflows/
│       ├── main.yml           # Push: lint → test → coverage → build → release
│       └── test-coverage.yml  # PR: per-model coverage + comment
├── Cargo.toml      # Workspace root
├── Makefile        # All build/test/coverage targets
├── rust-toolchain.toml
├── AGENTS.md       # AI agent entry point (this repo's system of record)
└── CLAUDE.md       # Claude Code-specific settings
```
