# AGENTS.md — AI Agent Entry Point for fdc-ota

> This file is the authoritative entry point for any AI agent (Claude, Codex, Copilot, etc.).
> It is a map, not an encyclopedia. Follow the links in Quick Navigation for deeper detail.

---

## Project Overview

FDC-OTA is a firmware Over-the-Air update system for Foxtron EV vehicles. It manages ECU firmware delivery across multiple vehicle models (D21F, D31L, TA2, and others) over wireless networks. The system has three deployment targets: **automotive Linux** (aarch64, the primary runtime), **Android IVI** (in-vehicle infotainment, built via Gradle/JNI), and **5G T-Box** (TI AM62XX modem). Vehicle model selection is a **compile-time** decision made via Cargo feature flags — there is no runtime model detection.

---

## Quick Navigation

| Topic | Source of Truth |
|---|---|
| Full architecture & message flow | [docs/architecture.md](docs/architecture.md) |
| Vehicle model feature flags | [docs/vehicle-models.md](docs/vehicle-models.md) |
| Communication protocols (DDS, CAN, UDS, DoIP, DBus, MQTT) | [docs/protocols.md](docs/protocols.md) |
| Development environment & cross-compilation | [docs/development.md](docs/development.md) |
| Known agent failure modes | [docs/pitfalls.md](docs/pitfalls.md) |

---

## Build & Test Commands

```bash
# Build
make build              # aarch64 Linux (requires NXP FSL Auto SDK)
make build-ivi          # Android IVI APK via Gradle
make build-tbox         # T-Box binary for TI AM62XX
make build-for-ci       # CI build — set MODEL=d21f|d31l|ta2

# Lint
make lint               # clippy -D warnings + fmt --check
make lint-for-ci        # All model/feature combinations

# Test
make test               # Workspace tests, excludes ota-xsumo, 600s timeout
make test-for-ci        # Full suite (needs DBus, vcan2, root)

# Single test
cargo test --package ota-host --lib module::test_name
cargo test --package ota-vehicle --lib backend::test_name -- --include-ignored

# Coverage
make coverage-d21f      # HTML report for d21f model
make coverage-d31l      # HTML report for d31l model
make coverage-ta2       # HTML report for ta2 model
make coverage-all       # Run all model coverage reports sequentially
make coverage-for-ci    # Merged LCOV + HTML + JSON per model
```

**Integration test prerequisites:**
```bash
make run-dbus-daemon                                          # DBus daemon
ip link add vcan2 type vcan && ip link set vcan2 up          # Virtual CAN interface
cp ota-host/tests/D21_Routing.toml /etc/uds/Routing.toml    # UDS routing config
```

---

## Workspace Layout

### Crates (`/`)

| Crate | Purpose |
|---|---|
| `ota-host` | Host-side orchestration: coordinates OTA backend, drives state machine, talks to vehicle via DDS/CAN |
| `ota-vehicle` | Vehicle-side coordinator: runs on main ECU, orchestrates all ECU updates via UDS/CAN, talks to host via DDS |
| `ota-ecu` | ECU update client with two platform variants: `ivi` (Android/JNI) and `tbox` (5G modem); default is standard Linux |
| `ota-utils` | Shared utilities: CAN/socketcan, DBus integration, signal handling, upgrade helpers |
| `ota-xsumo` | XSUMO protocol implementation; uses FastDDS; built separately with `fastdds` feature |

### Local Libraries (`lib/`)

| Library | Purpose |
|---|---|
| `dust-dds` | Custom DDS middleware for pub/sub messaging (excluded from workspace; has its own Cargo.toml) |
| `srec` | Motorola S-record file format parser/writer |
| `xsumo` | XSUMO protocol bindings |
| `tbox` | T-Box specific utilities |

---

## Feature Flags

Vehicle model selection is a **compile-time** decision via Cargo features — flags are mutually exclusive and must not be combined.

| Flag | Description |
|---|---|
| `d21f`, `d21m` | D21 vehicle variants |
| `d31l`, `d31l24`, `d31f25`, `d31h`, `d31x` | D31 vehicle variants |
| `ta2` | TA2 vehicle model |
| `p71`, `pe1` | P71/PE1 models |
| `ivi` | Android IVI platform (`ota-ecu` only) |
| `tbox` | T-Box 5G modem platform (`ota-ecu` only) |
| `fastdds` | FastDDS middleware (`ota-xsumo` only) |

---

## Cross-Compilation

| Target | SDK Path |
|---|---|
| `aarch64-unknown-linux-gnu` (main) | `/opt/fsl-auto/40.0/` (NXP FSL Auto 40.0 SDK) |
| TI AM62XX (T-Box) | `/opt/ti-processor-sdk-linux-am62xx-evm-10.01.10.04/` |
| Android IVI | `./gradlew assembleFullRelease` (standard Gradle) |

The `SDK` variable in the Makefile sources the appropriate cross-compilation environment.

---

## CI/CD

GitHub Actions workflows in `.github/workflows/`:

- **`main.yml`** — Runs on every push: lint → test → coverage → build (all models + IVI + tbox) → release (on tags)
- **`test-coverage.yml`** — Runs on PRs: generates per-model coverage and posts a comment (`COVERAGE_THRESHOLD=50`)

CI uses self-hosted runners with the `foxtronevtech/rust:v3.4` Docker image (includes cross-compilation toolchain).

---

## Key Architectural Rules

1. **Vehicle model = compile-time feature flag.** Never use runtime branching (`if cfg!(feature = "d21f")` at runtime logic) for model differences. Model is selected at build time and must be treated as a build dimension, not a runtime parameter.

2. **`ota-xsumo` is outside the main workspace.** `make test` and `make build` do not include it. It requires the `fastdds` feature and its own build invocation.

3. **`dust-dds` is excluded from the workspace** (`exclude = ["lib/dust-dds"]` in root `Cargo.toml`). It is referenced via path dependency by crates that need it.

4. **Domain IDs are fixed:** FDC domain = `1`, IVI domain = `2`. Topic naming convention: `InterfaceName/requ` and `InterfaceName/resp` for RPC pairs.

---

## Coding Conventions

- **Rust edition:** 2021 (workspace-wide, version `1.1.x`)
- **Error handling:** `anyhow` for application-level errors in binaries; `thiserror` for library crate error types
- **Async runtime:** Tokio (multi-thread) throughout
- **Config:** `figment` with TOML files + environment variable overrides
- **Logging:** `tracing` + `tracing-subscriber` with `env-filter`
- **Serialization:** `serde` + `serde_json`; use `serde_repr` for integer-backed enums

---

## Common Agent Pitfalls

See [docs/pitfalls.md](docs/pitfalls.md) for the full, growing list. Critical items:

1. **`make build` without the NXP SDK silently produces no output** — the SDK sourcing step is a no-op if the path doesn't exist. Always check the Docker image or SDK path first.
2. **Integration tests require `-- --include-ignored`** — tests that need vcan2 or DBus are marked `#[ignore]` by default.
3. **Never combine multiple vehicle model feature flags** — they are mutually exclusive; combining them leads to conflicting type definitions.
4. **`ota-xsumo` is excluded from `make test`** — it must be tested separately with `--features fastdds`.
5. **`dust-dds` has its own `Cargo.toml` outside the workspace** — running `cargo` commands at the repo root will not affect it.
6. **Never delete tests to make them pass** — fix the code, not the test. Removing a failing test hides the bug.
7. **Search before writing** — `ota-utils`, `srec`, and other crates likely already have what you need. Duplicating existing logic creates divergence.

---

## Maintenance Rule

When an agent makes a mistake or wrong assumption, add an entry to [docs/pitfalls.md](docs/pitfalls.md) or the relevant doc in `docs/`. Commit with message: `docs: agent pitfall — <short description>`. This file grows over time and becomes more valuable with each correction.
