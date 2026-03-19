# Vehicle Models & Feature Flags

## Overview

Vehicle model selection in fdc-ota is **compile-time only**. There is no runtime model detection. Each build targets exactly one vehicle model via a Cargo feature flag. Model flags are mutually exclusive — combining them results in conflicting type definitions and will not build correctly.

## Feature Flag Reference

### ota-host feature flags

| Feature | Implies | Vehicle / Description |
|---|---|---|
| `d21f` *(default)* | `bsp40`, `fpd1`, `prod` | D21 production variant |
| `d21m` | `bsp40`, `fpd1` | D21 engineering/prototype variant |
| `d31f25` | `bsp40`, `fpd1` | D31 F25 variant |
| `d31h` | `bsp40`, `fpd1` | D31 H variant |
| `d31l` | `bsp36`, `prod` | D31L production variant |
| `d31l24` | `bsp36`, `fpd1`, `prod` | D31L 2024 model year |
| `d31x` | `bsp36`, `fpd1` | D31X variant |
| `p71` | `bsp40`, `fpd1` | P71 model |
| `pe1` | `bsp40`, `fpd1` | PE1 model |
| `ta2` | `bsp40`, `fpt2` | TA2 model (uses FPT2 platform) |

### ota-vehicle feature flags

| Feature | Implies | Notes |
|---|---|---|
| `d21f` *(default)* | `prod` | D21 production |
| `d21m` | — | |
| `d31f25` | — | |
| `d31h` | — | |
| `d31l` | `prod` | |
| `d31l24` | `prod` | |
| `d31x` | — | |
| `p71` | — | |
| `pe1` | — | |
| `ta2` | — | |

### Platform flags (ota-ecu only)

| Feature | Description |
|---|---|
| `ivi` | Android IVI build (JNI, built via Gradle) |
| `tbox` | 5G T-Box build (TI AM62XX target) |

### Infrastructure flags

| Feature | Description | Used by |
|---|---|---|
| `fastdds` | FastDDS middleware support | `ota-xsumo` only |
| `bsp36` | NXP BSP 36 (older SDK) | `ota-host` internal |
| `bsp40` | NXP BSP 40 (current SDK) | `ota-host` internal |
| `fpd1` | FPD1 platform | `ota-host` internal |
| `fpt2` | FPT2 platform (TA2) | `ota-host` internal |
| `prod` | Production mode (enables production-only code paths) | `ota-host`, `ota-vehicle` |

## Compile-Time Model Selection Pattern

Models are selected by passing `--no-default-features --features <model>` to cargo:

```bash
# Build for d31l
cargo build --package ota-host --no-default-features --features d31l

# Build for ta2
cargo build --package ota-vehicle --no-default-features --features ta2

# CI build (Makefile uses MODEL env var)
MODEL=d31l make build-for-ci
```

The Makefile `build-for-ci` target handles this automatically when `MODEL` is set.

## Topology and ECU Configuration

Each vehicle model has an associated topology configuration that maps model features to the actual ECUs present. Topology files live in:
- `ota-host/tests/` — routing and topology configs used in tests (e.g., `D21_Routing.toml`)
- `/etc/uds/Routing.toml` — runtime location on-vehicle

The `prod` flag gates production-specific code paths (e.g., certificate validation, secure boot checks) that would fail in development/lab environments.

## Adding a New Vehicle Model

1. Add the feature to `ota-host/Cargo.toml` and `ota-vehicle/Cargo.toml` (with appropriate `bsp` and platform sub-features)
2. Add `#[cfg(feature = "new_model")]` guards around model-specific code
3. Add to `lint-for-ci` and `build-for-ci` Makefile targets
4. Add a coverage target `coverage-<model>` in the Makefile
5. Update `docs/vehicle-models.md` (this file)
