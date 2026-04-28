# remote-ota

**Version:** 0.3.0
**Last Updated:** 2026-04-24
**Binary:** `remote-ota`
**Crate:** `remote-ota`

---

## 1. Overview

`remote-ota` is a single-shot Rust program that triggers one OTA firmware update attempt for one FDC vehicle device over AWS IoT Core MQTT. Each invocation performs the full controller flow once:

1. connect to AWS IoT Core over mTLS
2. probe the device with `/sbin/version`
3. verify the returned VIN exactly matches `--vin`
4. launch `remote-updater`
5. monitor updater status until success, failure, or timeout
6. exit with a deterministic process status

This tool does not retry. One process run maps to one OTA attempt.

---

## 2. Design Goals

| ID | Goal | Description |
|---|---|---|
| G1 | Deterministic execution | One invocation performs one OTA attempt and exits |
| G2 | Device safety | Exact VIN matching prevents sending OTA commands to the wrong vehicle |
| G3 | Backward compatibility | Commands are still published to both legacy and IOV run-cmd topics |
| G4 | Simple runtime model | Session phase, topic routing, and timeouts determine controller behavior |
| G5 | Operator visibility | Structured logging and explicit exit codes make CI and lab usage predictable |

---

## 3. Functional Requirements

### FR-1 Connection Setup

- User must supply Root CA, device certificate, and private key paths.
- Program connects to `data.iot.cloud.foxtronev.com:8883` with TLS 1.2+ mTLS.
- Client ID is supplied by `--client-id`.

### FR-2 VIN Probe

- After connection and subscription setup, the controller publishes `/sbin/version` at QoS 1 to both run-cmd topics.
- The controller starts a fixed 60-second probe timeout after the probe is published.
- A version response is considered only while the session is in the probing phase.
- The `vincode` field must match `--vin` exactly.
- VIN mismatch is fatal and exits with code `2`.

### FR-3 OTA Launch

- On VIN match, the controller publishes the `remote-updater` launch command at QoS 1 to both run-cmd topics.
- The launch command includes SSID, password, auth type, and optional `--clean`.
- The controller waits up to 10 seconds for the first `remote-updater` message after launch.

### FR-4 OTA Monitoring

- The controller subscribes to `{sn}/remote-updater/#`.
- The 5-minute silence watchdog starts only after the first updater message arrives.
- Any accepted updater message resets the watchdog.
- Outcome mapping:

| Message characteristics | Outcome |
|------------------------|---------|
| `auto_exit` + `status = Alive` | Keepalive, continue monitoring |
| `auto_exit` + `result = UpdateSuccess` | Exit success |
| `auto_exit` + any other `result` | Exit general failure |
| Silence for 5 minutes after monitoring starts | Exit success, assumed reboot |

### FR-5 Message Acceptance

- The controller accepts `/sbin/version` responses based on session phase, topic, and payload shape.
- The controller accepts `remote-updater` status payloads based on session phase, topic, and payload shape.
- Without a per-attempt correlation field, stale but otherwise-valid traffic may be accepted if it arrives during the active phase.

### FR-6 Exit Codes

| Exit code | Meaning |
|----------|---------|
| `0` | OTA succeeded |
| `1` | General failure: probe timeout, updater failure, session abort, or no updater start |
| `2` | VIN mismatch |

---

## 4. CLI Surface

```bash
remote-ota [OPTIONS]
```

### Required Arguments

| Flag | Type | Description |
|------|------|-------------|
| `--client-id` | `String` | AWS IoT client ID |
| `--root-ca` | `String` | Path to root CA certificate |
| `--certificate` | `String` | Path to device certificate |
| `--private` | `String` | Path to device private key |
| `--ssid` | `String` | T-BOX Wi-Fi SSID |
| `--password` | `String` | Wi-Fi password |
| `--sn` | `String` | FDC device serial number |
| `--vin` | `String` | Expected vehicle identification number |

### Optional Arguments

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--auth` | `u8` | `4` | Wi-Fi authentication type |
| `--timeout` | `u32` | `3600` | Max seconds for `remote-updater` execution on device |
| `--clean` | `bool` | `false` | Clean OTA files and restart OTA service before updating |

---

## 5. MQTT and Protocol Summary

### Published Topics

| Topic | Purpose |
|-------|---------|
| `{sn}` | Legacy run-cmd delivery |
| `{sn}/iov/remote-cmd/sreq/run-cmd/v0` | New-firmware run-cmd delivery |

### Subscribed Topics

| Topic | Purpose |
|-------|---------|
| `{sn}` | Legacy run-cmd responses |
| `{sn}/iov/remote-cmd/vres/run-cmd/v0` | New-firmware run-cmd responses |
| `{sn}/remote-updater/#` | `remote-updater` status and progress messages |
| `{sn}/public/status/online/v0` | Device online status |

### run-cmd Payload Shape

```json
{
  "timestamp": "2026-04-24T08:00:00.000000000Z",
  "vehicleId": "SN123456",
  "action": "runCmd",
  "data": {
    "command": "remote-updater --ssid 'TestWifi' --password 'secret123' --auth 4 --clean",
    "timeout": 3600
  },
  "message": "AWS IoT console",
  "clientRunCmd": "remote-updater --ssid 'TestWifi' --password 'secret123' --auth 4 --clean",
  "cmdtimeout": 3600
}
```

---

## 6. Module Responsibilities

### `src/main.rs`

- parse CLI arguments
- initialize `tracing`
- create AWS IoT client and subscribe to required topics
- build probe and launch publish plans
- run exactly one OTA session
- map session outcomes to process exit codes

### `src/session.rs`

- own the per-attempt state machine
- enforce probe, updater-start, and silence timeouts
- evaluate version responses and updater status messages by phase
- return one terminal outcome

### `src/messages.rs`

- build run-cmd payloads
- parse exact `vincode`
- classify `remote-updater` status payloads

### `src/topics.rs`

- construct fixed MQTT topic strings from `sn`

---

## 7. Verification

Project verification commands:

```bash
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test
```