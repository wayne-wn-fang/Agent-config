# remote-ota ↔ remote-updater Bilateral Protocol Specification

**Version:** 0.1.0  
**Last Updated:** 2026-04-17  
**Status:** Draft — review required before remote-updater implementation begins

> This document defines all message formats, topic naming, behavioral requirements, and timing contracts exchanged between `remote-ota` (the control side) and `remote-updater` (the device side) over AWS IoT Core MQTT. **Both implementations must strictly conform to this specification. Any change to either side requires a corresponding update here.**

---

## 1. System Topology

```
┌─────────────────────┐        MQTT / mTLS        ┌─────────────────────────────┐
│  remote-ota  │ ◄────────────────────────► │    AWS IoT Core Broker      │
│  (test host / CI)   │                            │  data.iot.cloud.foxtronev   │
└─────────────────────┘                            └──────────────┬──────────────┘
                                                                   │ MQTT / mTLS
                                                   ┌──────────────▼──────────────┐
                                                   │       FDC T-BOX             │
                                                   │  ┌─────────────────────┐    │
                                                   │  │  run-cmd agent      │    │
                                                   │  │  /sbin/version      │    │
                                                   │  │  remote-updater     │    │
                                                   │  └─────────────────────┘    │
                                                   └─────────────────────────────┘
```

**Participants:**

| Role | Description |
|------|-------------|
| `remote-ota` | Runs on test host or CI; triggers OTA and validates the outcome |
| `run-cmd agent` | Resident service on the device; receives run-cmd commands and executes shell commands |
| `/sbin/version` | Device binary that outputs firmware version and VIN |
| `remote-updater` | OTA executor on the device; launched by the run-cmd agent; downloads and flashes firmware |

---

## 2. MQTT Connection Contract

| Item | Specification |
|------|--------------|
| Broker | `data.iot.cloud.foxtronev.com:8883` |
| Transport | TLS 1.2+, mutual certificate authentication (mTLS) |
| Credentials | Root CA PEM, Device Certificate PEM, Private Key PEM |
| Keep-alive | rumqttc default (60 seconds) |
| Clean session | true (re-subscribe on every connection) |

**QoS Rules:**

| Message type | Publisher | QoS | Rationale |
|-------------|-----------|-----|-----------|
| run-cmd request | remote-ota | **QoS 1** | Silent loss causes the OTA to hang with no feedback |
| /sbin/version response | run-cmd agent | QoS 0 | Probe can be resent; loss is not fatal |
| remote-updater status | remote-updater | **QoS 1** | Lost status messages cause incorrect outcome classification |

---

## 3. Topic Naming Contract

All topics are prefixed with the device serial number `{sn}`.

### 3.1 remote-ota Subscriptions (device → controller)

| Topic | Publisher | Purpose |
|-------|-----------|---------|
| `{sn}` | run-cmd agent | Legacy command responses (old firmware) |
| `{sn}/remote-updater/status` | remote-updater | Status and progress messages |
| `{sn}/public/status/online/v0` | Device firmware | Device online status |
| `{sn}/iov/remote-cmd/vres/run-cmd/v0` | run-cmd agent | New-firmware command responses |

> **Note:** remote-ota subscribes to `{sn}/remote-updater/#` (wildcard). remote-updater **must** publish to `{sn}/remote-updater/status`.

### 3.2 remote-ota Publications (controller → device)

| Topic | Receiver | Purpose |
|-------|----------|---------|
| `{sn}` | run-cmd agent | Legacy command delivery (old firmware) |
| `{sn}/iov/remote-cmd/sreq/run-cmd/v0` | run-cmd agent | New command delivery (new firmware) |

> **Dual-topic publishing:** Every command must be published to both topics simultaneously to support both firmware generations.

---

## 4. Message Format Contract

### 4.1 run-cmd Request (remote-ota → run-cmd agent)

```json
{
  "timestamp": "2026-04-10T08:00:00.000000000Z",
  "attemptId": "SN123456-1712812800000000000",
  "vehicleId": "{sn}",
  "action": "runCmd",
  "data": {
    "command": "<shell command>",
    "timeout": 14400
  },
  "message": "AWS IoT console",
  "clientRunCmd": "<shell command>",
  "cmdtimeout": 14400
}
```

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | ISO 8601 UTC string | Message creation time; regenerated on every publish |
| `attemptId` | string | Controller-generated per-invocation correlation ID; must be echoed by all accepted responses and status messages |
| `vehicleId` | string | Device serial number (same as `{sn}`) |
| `action` | string | Always `"runCmd"` |
| `data.command` | string | Read by new firmware |
| `data.timeout` | number (seconds) | Read by new firmware |
| `message` | string | Always `"AWS IoT console"` (legacy) |
| `clientRunCmd` | string | Read by old firmware; identical to `data.command` |
| `cmdtimeout` | number (seconds) | Read by old firmware; identical to `data.timeout` |

**Command examples:**

| Purpose | `command` value |
|---------|----------------|
| VIN probe | `/sbin/version` |
| Launch OTA (basic) | `remote-updater --ssid <ssid> --password <pwd> --auth <n> --attempt-id <attemptId>` |
| Launch OTA (with clean) | `remote-updater --ssid <ssid> --password <pwd> --auth <n> --attempt-id <attemptId> --clean` |

---

### 4.2 /sbin/version Response (device → remote-ota)

The run-cmd agent executes `/sbin/version` and wraps the output as a response published to `{sn}` or `{sn}/iov/remote-cmd/vres/run-cmd/v0`.

The response JSON **must contain all** of the following fields:

| Field | Type | Description |
|-------|------|-------------|
| `attemptId` | string | Exact echo of the controller-provided request `attemptId` |
| `version` | string | Firmware version string |
| `vincode` | string | Vehicle identification number (VIN) — **must be the exact 17-character VIN** |

**Valid example:**
```json
{
  "attemptId": "SN123456-1712812800000000000",
  "version": "1.2.3",
  "vincode": "LSJABCD1234567890"
}
```

---

### 4.3 remote-updater Status Messages (remote-updater → remote-ota)

Publish topic: `{sn}/remote-updater/status`

All messages are JSON with a `type` field used for classification.

#### 4.3.1 Progress

```json
{
  "attemptId": "SN123456-1712812800000000000",
  "type": "progress",
  "stage": "<stage>",
  "percent": 42,
  "message": "<human readable description>"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `attemptId` | string | Exact echo of the current OTA attempt identifier |
| `type` | string | Always `"progress"` |
| `stage` | string | Current stage, e.g. `"downloading"`, `"flashing"`, `"verifying"` |
| `percent` | number (0–100) | Progress percentage; use `-1` if unavailable |
| `message` | string | Human-readable description (optional) |

> **Timing requirement:** remote-updater **must** publish at least one progress message (or alive ping) every **5 seconds**. The remote-ota silence watchdog is set to 300 seconds (= 60 missed messages).

#### 4.3.2 Alive Ping (Keepalive)

Sent when there is no specific progress to report, to keep the watchdog from firing:

```json
{
  "attemptId": "SN123456-1712812800000000000",
  "type": "auto_exit",
  "status": "Alive",
  "message": "still running"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `attemptId` | string | Exact echo of the current OTA attempt identifier |
| `type` | string | Always `"auto_exit"` |
| `status` | string | Always `"Alive"` |

> **Important:** `type = "auto_exit"` + `status = "Alive"` carries keepalive semantics and **does not mean the process is about to exit**. This is a legacy naming convention; both sides must be aware of it.

#### 4.3.3 UpdateSuccess (Successful Exit)

```json
{
  "attemptId": "SN123456-1712812800000000000",
  "type": "auto_exit",
  "result": "UpdateSuccess",
  "message": "OTA complete, rebooting"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `attemptId` | string | Exact echo of the current OTA attempt identifier |
| `type` | string | Always `"auto_exit"` |
| `result` | string | Always `"UpdateSuccess"` |

> remote-updater must trigger a reboot immediately after sending this message. remote-ota treats receipt of this message as definitive OTA success.

#### 4.3.4 UpdateFailed (Failure Exit)

```json
{
  "attemptId": "SN123456-1712812800000000000",
  "type": "auto_exit",
  "result": "UpdateFailed",
  "reason": "<error description>",
  "stage": "<failed stage>"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `attemptId` | string | Exact echo of the current OTA attempt identifier |
| `type` | string | Always `"auto_exit"` |
| `result` | string | Must **not** be `"UpdateSuccess"` or coexist with `"Alive"`; use `"UpdateFailed"` for clarity |
| `reason` | string | Error description (optional, for log diagnostics) |
| `stage` | string | Stage where failure occurred (optional) |

> **Important:** Any `result` value that is not `"UpdateSuccess"` and does not coexist with `"Alive"` is classified as failure by remote-ota. Using `"UpdateFailed"` explicitly is strongly recommended.

---

## 5. remote-ota Behavioral Requirements

| ID | Requirement |
|----|-------------|
| RC-1 | After connecting, send the `/sbin/version` probe and wait for a correlated response before proceeding |
| RC-2 | VIN comparison must use exact equality; mismatch terminates immediately without retry |
| RC-3 | Generate one opaque `attemptId` per invocation and include it in every probe and launch run-cmd request |
| RC-4 | Accept only `/sbin/version` responses and `remote-updater` status payloads whose top-level `attemptId` exactly matches the current invocation |
| RC-5 | Start the silence watchdog only after the first correlated `remote-updater` message has arrived |
| RC-6 | Watchdog counts down 300 seconds; reset on every correlated `remote-updater` message received |
| RC-7 | Apply a fixed 60-second probe timeout; on expiry exit with general failure |
| RC-8 | Publish all run-cmd requests at QoS 1, to both legacy and sreq topics simultaneously |
| RC-9 | On receipt of correlated `UpdateSuccess`, exit successfully immediately without waiting for the watchdog |
| RC-10 | On receipt of correlated `UpdateFailed`, exit with general failure immediately without waiting for the watchdog |
| RC-11 | If no correlated `remote-updater` status payload arrives within 10 seconds of launch, exit with general failure |
| RC-12 | Default value of `--timeout` is 14400 (4 hours); this value is forwarded to the device as the run-cmd execution limit |

---

## 6. remote-updater Behavioral Requirements

| ID | Requirement |
|----|-------------|
| RU-1 | Publish the first `progress` message within 10 seconds of startup; must not be silent longer than that |
| RU-2 | Publish at least one `progress` or alive ping message every **5 seconds** |
| RU-3 | Publish all status messages to `{sn}/remote-updater/status` at QoS 1 |
| RU-4 | On successful completion, publish `UpdateSuccess` before triggering reboot; this message must not be omitted |
| RU-5 | On any failure exit, publish `UpdateFailed` (with `reason` and `stage`) before terminating |
| RU-6 | When `--clean` is supplied, complete the cleanup before starting OTA; if cleanup fails, publish `UpdateFailed` (reason: `"clean_failed"`) and exit |
| RU-7 | On Wi-Fi connection failure, publish `UpdateFailed` (reason: `"wifi_connection_failed"`) and exit |
| RU-8 | On duplicate launch command (idempotency): must not start a second OTA process. **Implementation: launch via `systemd-run --user -u "remote-updater" remote-updater ...`; systemd enforces unit name uniqueness at the OS level and will reject a duplicate start.** |
| RU-9 | The `type` field must only use `"progress"` or `"auto_exit"`; other values risk misclassification by remote-ota |
| RU-10 | `status = "Alive"` in an alive ping means the process is still running; this message must not be sent once an exit has been decided |
| RU-11 | Echo the controller-provided `attemptId` in every status message for the current OTA process |

---

## 7. Timing Contract

```
[remote-ota]                          [remote-updater / device]

Connect ──────────────────────────────────►
◄── ConnAck ──────────────────────────────
Publish /sbin/version (QoS 1) ────────────►
◄── version response (attemptId + vincode) ──
Publish remote-updater cmd (QoS 1) ───────►
                                        [start remote-updater]
                                        [first progress within ≤10 seconds]
◄── progress (attemptId + type: progress) ─  ← start watchdog
◄── progress / alive (matching attemptId) ─  ← each message resets watchdog
◄── ... (up to 4 hours) ──────────────────
◄── auto_exit + UpdateSuccess ────────────  ← remote-ota exits successfully
                                        [trigger reboot]
```

**Timeout behavior:**

| Phase | Timeout setting | Action on expiry |
|-------|----------------|-----------------|
| Probe (waiting for VIN response) | fixed 60 seconds | general failure |
| Waiting for first correlated `remote-updater` message | fixed 10 seconds | general failure |
| Monitoring (consecutive silence) | 300 seconds (= 60 missed messages) | success — assumed reboot |
| run-cmd execution limit | `--timeout` (default 14400s) | Device-side run-cmd agent forcibly terminates |

---

## 8. Error Handling Contract

### remote-ota side

| Scenario | Handling |
|----------|----------|
| VIN mismatch | Terminate immediately, no retry (non-recoverable) |
| Probe timeout | Exit with general failure |
| Missing first correlated updater message after launch | Exit with general failure |
| Correlated `UpdateFailed` received | Exit with general failure |
| Correlation mismatch or missing `attemptId` | Ignore as stale or unrelated traffic |
| 300-second silence after monitoring starts | Exit successfully — assumed successful reboot |
| Local MQTT / event-loop failure | Exit with general failure |
| recv_task panic | Exit with general failure |

### remote-updater side

| Scenario | Required message | Recommended `reason` value |
|----------|-----------------|---------------------------|
| Wi-Fi connection failure | `UpdateFailed` | `"wifi_connection_failed"` |
| Firmware download failure | `UpdateFailed` | `"download_failed"` |
| Flash failure | `UpdateFailed` | `"flash_failed"` |
| Verification failure | `UpdateFailed` | `"verification_failed"` |
| `--clean` failure | `UpdateFailed` | `"clean_failed"` |
| run-cmd timeout (forcibly killed) | (cannot send) | — |

---

## 9. `--clean` Semantics

The `--clean` flag instructs remote-updater to perform the following steps **before** starting the OTA flow:

1. Delete OTA-related temporary files from the device
2. Restart the OTA service

**Behavioral rules:**
- `--clean` is a launch-time flag for the single OTA attempt
- If cleanup fails, remote-updater must publish `UpdateFailed` (reason: `"clean_failed"`) and exit; it must **not** proceed with OTA after a failed cleanup

---

## 10. Known Limitations and Open Items

| ID | Item | Status |
|----|------|--------|
| L-1 | `remote-ota` now requires run-cmd agent and `remote-updater` support for `attemptId`; mixed old/new deployments will time out rather than match stale traffic | Accepted rollout requirement |
| L-2 | C-1: `--password` redaction must remain enforced in controller logs | Implemented in controller; keep under review |
| L-3 | `online_vres` topic is subscribed but never handled; purpose undecided | Pending decision |
| L-4 | 300-second silence interpreted as success is an uncertain outcome — known product trade-off | Accepted |
| L-5 | `--silence-timeout` is not exposed as a CLI parameter | Recommended for future addition |
| L-6 | RU-8 idempotency is guaranteed at OS level via `systemd-run --user -u "remote-updater"`; run-cmd agent must use this invocation form | Decided |
