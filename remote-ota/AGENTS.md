# AGENTS.md — remote-ota

## Purpose

`remote-ota` is a single-shot Rust tool that triggers and monitors one OTA firmware update
attempt for one FDC vehicle device over AWS IoT Core MQTT. Each invocation connects,
probes the device VIN, launches `remote-updater`, monitors status traffic,
and exits with a deterministic exit code.

This Agent-config directory (`~/Agent-config/remote-ota/`) is the authoritative source
for agent guidance and documentation. Files here are symlinked into every remote-ota
worktree — edit here and all worktrees pick up changes immediately.

---

## Repository Structure

| File | Responsibility |
|------|---------------|
| `src/main.rs` | CLI parsing, MQTT setup, single-shot orchestration, exit-code mapping |
| `src/messages.rs` | Protocol payload building and JSON parsing helpers |
| `src/session.rs` | OTA state machine and timeout handling |
| `src/topics.rs` | MQTT topic construction helpers |

---

## Verification Commands

All three must pass before committing:

```bash
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test
```

---

## Issue Tracking

When you find a bug, risk, or code smell, append to `ISSUES.md` in the working directory:

```
- [ ] [problem description] (location: filename:line_number)
```

Do not create `ISSUES.md` proactively — only write it when an actual issue is found.

---

## Plans

Store implementation plans under `docs/superpowers/plans/`. One file per plan,
e.g. `docs/superpowers/plans/feature-name.md`.

---

## Key Invariants — Agents Must Not Violate

- **Single-shot:** One invocation performs exactly one OTA attempt and then exits.
  Do not add retry loops.
- **VIN safety:** A VIN mismatch must always exit with code `2`.
  Never relax or bypass this check.
- **Dual-topic publishing:** Probe and launch commands must always be published to both
  the legacy (`{sn}`) and IOV (`{sn}/iov/remote-cmd/sreq/run-cmd/v0`) run-cmd topics.
  Never publish to only one.
- **Exit codes:** `0` = success, `1` = general failure, `2` = VIN mismatch.
  Do not change this mapping.
