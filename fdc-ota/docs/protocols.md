# Communication Protocols

## DDS (Data Distribution Service)

**Library:** `dust-dds` (custom, local at `lib/dust-dds/`; excluded from workspace)
**Also used:** `rustdds` (v0.11.6-rc.1, kellnr registry) in `ota-vehicle`

### Domain IDs

| Domain | ID | Used by |
|---|---|---|
| FDC (main) | `1` | ota-host ↔ ota-vehicle |
| IVI | `2` | ota-host ↔ ota-ecu (IVI) |

### Topic Naming

- **RPC pairs:** `InterfaceName/requ` (request writer → reader) and `InterfaceName/resp` (response writer → reader)
- A *Stub* is the caller side (writes `/requ`, reads `/resp`)
- A *Skeleton* is the server side (reads `/requ`, writes `/resp`)
- An *Eavesdropper* passively reads `/resp` for observability

### DDS Type Names (registered with the middleware)

| Rust type | DDS type name | Used for |
|---|---|---|
| `BinaryData` | `"BinaryData"` | Binary RPC payloads |
| `Message` (idl.rs) | `"FDCMessenger::Message"` | Structured host↔vehicle messages |
| `TboxMessage` | `"Messenger::Message"` | T-Box messages |

### IDL / Type Definitions

- `ota-host/src/dds/idl.rs` — `Message` type for FDC domain
- `ota-host/src/auto/ivi_tbox_protocol.rs` — `TboxMessage` type for IVI/T-Box domain

### QoS Profiles

| Profile | Durability | History | Reliability |
|---|---|---|---|
| Binary RPC reader | Volatile | KeepLast(1) | Reliable |
| Binary RPC writer | TransientLocal | KeepLast(1) | Reliable |
| Message reader/writer | TransientLocal | KeepLast(1) | Reliable, max 20 samples |

---

## CAN / vCAN

**Library:** `socketcan` v3.5.0
**DBC parsing:** `can-dbc` (ota-host, ota-utils), `cmn-dbc` (kellnr registry, workspace dep)

### Interface Naming

| Interface | Use |
|---|---|
| `vcan1` | Vehicle bus simulation |
| `vcan2` | Integration test bus (required for `#[ignore]` tests) |
| `vcan3` | Additional simulation bus |

### Setup for Tests

```bash
ip link add vcan2 type vcan
ip link set vcan2 up
# or via Makefile:
# (done automatically by make test-for-ci)
```

CAN signal definitions live in `ota-utils/src/signal/` (module structure mirroring DBC logical channels).

---

## UDS (Unified Diagnostic Services)

**Libraries:** `uds-app`, `uds-client`, `uds-fdc`, `uds-utils` (all from kellnr registry, v0.31.1)

UDS is used for ECU programming (flash sequences). Key service IDs in use:
- `0x10` — DiagnosticSessionControl
- `0x27` — SecurityAccess
- `0x34` — RequestDownload
- `0x36` — TransferData
- `0x37` — RequestTransferExit
- `0x31` — RoutineControl (erase, checksum)

### Routing Configuration

- **Test config:** `ota-host/tests/D21_Routing.toml`
- **Runtime config:** `/etc/uds/Routing.toml` (must be present for integration tests)

```bash
cp ota-host/tests/D21_Routing.toml /etc/uds/Routing.toml
```

---

## DoIP (Diagnostics over IP)

**Module:** `ota-host/src/doip.rs`

DoIP provides a TCP/IP transport for UDS messages, enabling remote ECU diagnostics and programming. Used primarily by `ota-host` for remote (off-vehicle) ECU update scenarios.

- Client connects to vehicle gateway via TCP (port 13400 standard)
- Wraps UDS payloads in DoIP frames
- Relationship to UDS: DoIP is the transport layer; UDS is the application layer

---

## DBus

**Library:** `zbus` v4.4.0, tokio-backed
**Module:** `ota-utils` (integration helpers)

DBus is used for system-level IPC on the vehicle Linux environment. `ota-vehicle` and `ota-ecu` communicate with system services (e.g., power management, network manager) via DBus.

### Test Setup

```bash
make run-dbus-daemon    # Starts a session DBus daemon for integration tests
```

Without a running DBus daemon, any test exercising DBus code paths will fail.

---

## MQTT / AWS IoT

**Library:** `rumqttc` v0.15.0 (in `ota-host`)
**Also:** `aws-iot-device-sdk-rust` v0.3.0

`ota-host` connects to the cloud backend via MQTT over TLS, using AWS IoT Core.

### Topic Patterns / RPC Schema

The cloud RPC uses a JSON request/response schema over MQTT. The schema types are defined in `ota-host/src/dds/schema.rs`:

| Operation | Request type | Response type |
|---|---|---|
| Connect (get manifest) | `ConnectRequ` | `ConnectResp` |
| Download (trigger/poll) | `DownloadRequ` | `DownloadResp` |
| Upgrade (begin flash) | `UpgradeRequ` | `UpgradeResp` |
| Result (report outcome) | `ResultRequ` | `ResultResp` |
| Guardian (ECU readiness) | `GuardianRequ` | `GuardianResp` |

Connection configuration is loaded via `figment` from TOML + environment variables (see `ota-host/src/config.rs`).
