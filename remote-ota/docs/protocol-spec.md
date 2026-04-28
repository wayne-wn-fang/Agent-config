# remote-ota ↔ remote-updater Bilateral Protocol Specification

**Version:** 0.2.0
**Last Updated:** 2026-04-24
**Status:** Draft

> This document defines the message formats, topic naming, behavioral requirements, and timing contracts exchanged between `remote-ota` and `remote-updater` over AWS IoT Core MQTT.

---

## 1. Topic Contract

All topics are prefixed with the device serial number `{sn}`.

### 1.1 Controller Subscriptions

| Topic | Publisher | Purpose |
|-------|-----------|---------|
| `{sn}` | run-cmd agent | Legacy command responses |
| `{sn}/iov/remote-cmd/vres/run-cmd/v0` | run-cmd agent | New-firmware command responses |
| `{sn}/remote-updater/status` | remote-updater | Status and progress messages |
| `{sn}/public/status/online/v0` | device firmware | Device online status |

> `remote-ota` subscribes to `{sn}/remote-updater/#` and accepts status traffic from matching subtopics.

### 1.2 Controller Publications

| Topic | Receiver | Purpose |
|-------|----------|---------|
| `{sn}` | run-cmd agent | Legacy command delivery |
| `{sn}/iov/remote-cmd/sreq/run-cmd/v0` | run-cmd agent | New command delivery |

Every command is published to both topics.

---

## 2. run-cmd Request Format

```json
{
  "timestamp": "2026-04-24T08:00:00.000000000Z",
  "vehicleId": "SN123456",
  "action": "runCmd",
  "data": {
    "command": "remote-updater --ssid 'TestWifi' --password 'secret123' --auth 4",
    "timeout": 3600
  },
  "message": "AWS IoT console",
  "clientRunCmd": "remote-updater --ssid 'TestWifi' --password 'secret123' --auth 4",
  "cmdtimeout": 3600
}
```

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | ISO 8601 UTC string | Message creation time |
| `vehicleId` | string | Device serial number |
| `action` | string | Always `runCmd` |
| `data.command` | string | New-firmware command string |
| `data.timeout` | number | New-firmware timeout in seconds |
| `message` | string | Legacy fixed value `AWS IoT console` |
| `clientRunCmd` | string | Legacy command string |
| `cmdtimeout` | number | Legacy timeout in seconds |

Command examples:

| Purpose | `command` value |
|---------|-----------------|
| VIN probe | `/sbin/version` |
| Launch OTA | `remote-updater --ssid <ssid> --password <pwd> --auth <n>` |
| Launch OTA with clean | `remote-updater --ssid <ssid> --password <pwd> --auth <n> --clean` |

---

## 3. Accepted Response Formats

### 3.1 `/sbin/version` Response

The run-cmd agent response must include:

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Firmware version string |
| `vincode` | string | Vehicle identification number |

Example:

```json
{
  "version": "1.2.3",
  "vincode": "LSJABCD1234567890"
}
```

### 3.2 `remote-updater` Status Messages

All messages are JSON. The controller classifies them by top-level fields:

| Pattern | Meaning |
|---------|---------|
| `{"type":"auto_exit","status":"Alive"}` | Keepalive |
| `{"type":"auto_exit","result":"UpdateSuccess"}` | Success |
| `{"type":"auto_exit","result":...}` with any non-success result | Failure |
| Any other valid JSON payload | Progress |

Example keepalive:

```json
{
  "type": "auto_exit",
  "status": "Alive"
}
```

Example success:

```json
{
  "type": "auto_exit",
  "result": "UpdateSuccess"
}
```

Example failure:

```json
{
  "type": "auto_exit",
  "result": "UpdateFailed",
  "reason": "download_failed"
}
```

---

## 4. Controller Requirements

| ID | Requirement |
|----|-------------|
| RC-1 | Probe with `/sbin/version` before launching OTA |
| RC-2 | Require exact VIN equality with `--vin` |
| RC-3 | Publish probe and launch commands to both run-cmd topics |
| RC-4 | Accept version responses only while probing and only if they contain `version` and `vincode` |
| RC-5 | Accept updater messages only while awaiting updater start or monitoring updater |
| RC-6 | Start the silence watchdog only after the first updater message arrives |
| RC-7 | Use a 60-second probe timeout |
| RC-8 | Use a 10-second updater-start timeout |
| RC-9 | Use a 5-minute silence timeout after monitoring begins |
| RC-10 | Treat `UpdateSuccess` as definitive success |
| RC-11 | Treat any other `auto_exit` result or malformed JSON updater payload as failure |

Without a per-attempt correlation field, stale but otherwise-valid responses may still be accepted if they arrive during the active phase.

---

## 5. Device Requirements

| ID | Requirement |
|----|-------------|
| RU-1 | Execute `/sbin/version` and return top-level `version` and `vincode` |
| RU-2 | Publish updater status to `{sn}/remote-updater/status` or another `{sn}/remote-updater/#` subtopic |
| RU-3 | Publish at least one updater message within 10 seconds of launch |
| RU-4 | Publish periodic progress or keepalive messages while running |
| RU-5 | Publish `UpdateSuccess` before reboot on successful completion |
| RU-6 | Publish a failure `auto_exit` result before terminating on failure |
| RU-7 | Support optional `--clean` before OTA begins |

---

## 6. Verification

```bash
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test
```