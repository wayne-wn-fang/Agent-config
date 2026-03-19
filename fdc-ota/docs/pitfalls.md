# Known Agent Failure Modes

This document records mistakes AI agents have made or are prone to making in this codebase.
When an agent makes a new mistake, add an entry here.
Commit convention: `docs: agent pitfall — <short description>`

---

## Build & Environment

### `make build` without the NXP SDK produces no useful output

`make build` sources the NXP FSL Auto SDK at `/opt/fsl-auto/40.0/`. If this path does not exist (i.e., outside the CI Docker image), the source step silently succeeds, but `$CC` will point to the host compiler. The build may succeed as a native binary or fail with linker errors — either way it is not the intended aarch64 artifact.

**Check first:** `echo $CC` or `ls /opt/fsl-auto/40.0/`

---

### `ota-xsumo` is excluded from `make test` and `make build`

`ota-xsumo` is not a workspace member of the standard test or build flows. It requires the `fastdds` feature and a separate build invocation. Running `cargo test` or `cargo build` at the workspace root will not compile or test it.

**How to build/test it separately:**
```bash
cargo build --package ota-xsumo --features fastdds
cargo test --package ota-xsumo --features fastdds
```

---

### `dust-dds` is excluded from the workspace

`lib/dust-dds` has `exclude = ["lib/dust-dds"]` in the root `Cargo.toml`. It is a path dependency only — referenced directly by crates that need it. Running workspace-level commands (`cargo test --workspace`) will not include it.

---

### Private kellnr registry dependencies

Several crates (`uds-*`, `rustdds`, `cmn-dbc`) come from a private Kellnr registry. Without `~/.cargo/config.toml` configured with the registry credentials, `cargo build` fails on the first fetch. This is not a code problem — it is an environment setup problem.

---

## Testing

### Integration tests are silently skipped without `--include-ignored`

Tests that require `vcan2` or a running DBus daemon are annotated `#[ignore]`. Without `-- --include-ignored`, they show up as "ignored" in test output, not "failed." An agent that reads "all tests passed" without noticing the ignored count may miss real failures.

```bash
cargo test --package ota-vehicle --lib -- --include-ignored
```

---

### Integration tests need vcan2 AND DBus AND root

Three things must be true simultaneously for integration tests to run:
1. `vcan2` interface exists and is up (`ip link set vcan2 up`)
2. DBus daemon is running (`make run-dbus-daemon`)
3. `/etc/uds/Routing.toml` exists (copy from `ota-host/tests/D21_Routing.toml`)

Missing any one of these causes tests to fail with environment-specific errors, not assertion failures. Don't debug the test logic until the environment is confirmed.

---

## Feature Flags & Models

### Combining multiple vehicle model feature flags breaks the build

Feature flags like `d21f`, `d31l`, `ta2` are **mutually exclusive**. Combining them (e.g., `--features d21f,d31l`) produces conflicting type definitions and compile errors. Each build targets exactly one model.

---

### Default feature is `d21f` — not "no model"

Both `ota-host` and `ota-vehicle` have `default = ["d21f"]`. If you run `cargo build` or `cargo test` without specifying a model, you get d21f. Use `--no-default-features --features <model>` to build for a different model.

---

### `prod` flag changes behavior — don't assume dev behavior applies to CI

The `prod` flag (implied by `d21f`, `d31l`, `d31l24`) enables production code paths such as certificate validation and secure boot checks. Behavior in `prod` builds may differ from non-`prod` builds. If a test passes locally (non-prod) but fails in CI (prod), this is likely the cause.

---

## Testing Discipline

### Never delete tests to make the test suite pass

If a test is failing, fix the underlying code — do not delete or comment out the test. Tests exist to catch regressions and verify behaviour. Removing a failing test hides the problem rather than solving it. The only legitimate reasons to remove a test are: the feature it covers was intentionally deleted, or the test was demonstrably wrong from the start (in which case fix it, not delete it).

---

## Code Conventions

### Don't use runtime `cfg!` for model branching

Model differences must be handled at compile time via `#[cfg(feature = "...")]` attributes, not `if cfg!(feature = "...")` runtime guards. The latter works syntactically but defeats the purpose of compile-time model selection and can lead to dead code in prod builds.

---

### Prefer existing code over writing new code

Before implementing anything, search the codebase for existing utilities, helpers, and abstractions that already solve the problem. Duplicating logic that already exists in `ota-utils`, `srec`, or other crates creates maintenance burden and divergence. Use `grep`/`Glob` to check before writing.

Common places to look first:
- `ota-utils/src/` — CAN, DBus, signal handling, upgrade helpers
- `lib/srec/` — S-record parsing
- `ota-ecu/src/` — ECU protocol primitives shared across platforms

---

### Error types: `anyhow` in binaries, `thiserror` in libraries

`ota-host` binaries use `anyhow::Result` for ergonomic error propagation. Library crates (`ota-utils`, `ota-ecu`) define their own error types with `thiserror`. Don't add `anyhow` as a dependency to library crates — use `thiserror` and expose typed errors.
