# Remote OTA Known Issues Design

## Goal

Refactor the OTA flow so the runtime semantics match the documented behavior for VIN verification, MQTT delivery guarantees, timeout management, and per-attempt message correlation while also removing the `--fail-stop`, `--repeat`, and `--cooldown` control paths.

## Scope

This design covers these fixes from the known-issues list:

- `C-2`: Replace substring VIN matching with exact parsed matching.
- `H-1`: Publish commands with QoS 1 instead of QoS 0.
- `H-2`: Start the silence watchdog only after the first `remote-updater` message.
- `H-3`: Treat VIN mismatch as fatal and non-retryable.
- `H-4`: Add an explicit probe timeout.
- `H-5`: Add a per-attempt correlation ID so stale MQTT traffic cannot satisfy the current OTA attempt.
- Remove CLI and runtime support for `--fail-stop`, `--repeat`, and `--cooldown`.

This design does not address `C-1`, `M-1`, or `M-2`.

## Constants

- Probe timeout: 60 seconds.
- Updater start timeout: 10 seconds.
- Updater silence timeout: 5 minutes.

The implementation should express these as dedicated constants, for example `PROBE_TIMEOUT`, `UPDATER_START_TIMEOUT`, and `SILENCE_TIMEOUT`.

## Current Problems

The current implementation in `src/main.rs` mixes transport I/O, state tracking, retry policy, and timeout behavior inside one spawned receive task plus an outer `tokio::select!`. That creates five structural problems:

1. Session state is implicit. A single `launched` boolean controls both VIN verification and post-launch monitoring.
2. Failure semantics are flattened into `Result<(), ()>`, so VIN mismatch, probe timeout, and updater failure are indistinguishable to the caller.
3. The silence watchdog is tied to generic notifications instead of the updater lifecycle, so it can start too early.
4. Message parsing is string-based, which makes VIN validation unsafe and brittle.
5. There is no end-to-end freshness signal linking device responses to the current controller attempt, so stale broker traffic can be misclassified as current progress or success.

## Proposed Architecture

Introduce a dedicated session module, `src/session.rs`, responsible for one OTA attempt over a fresh MQTT connection.

`main` remains the owner of the MQTT connection, topic subscription setup, and spawned AWS event-loop task. The session owns only attempt-local state and message-processing decisions. It receives the AWS client handle needed for publishing and the receiver stream needed for consuming MQTT packets, then returns a terminal outcome when the attempt completes.

The receiver is created by `main` after subscribing to the required topics and is passed into the session. The session does not manage topic subscriptions.

### Responsibilities by Module

#### `src/main.rs`

- Parse CLI arguments.
- Initialize tracing.
- Create the AWS IoT client and subscribe to topics.
- Own the outer AWS event-loop task lifetime for the current attempt.
- Run exactly one OTA attempt and exit.
- Return exit code `0` on successful outcomes, exit code `1` on general failures, and exit code `2` on VIN mismatch.
- Remove the `--fail-stop`, `--repeat`, and `--cooldown` flags, parser fields, helper methods, and related docs/logging.

#### `README.md`

- Update the project overview so it describes `remote-ota` as a single-shot OTA trigger-and-monitor tool.
- Remove any architecture or usage text that implies looped execution or a `src/lib.rs` layout that does not exist.
- Document the current CLI surface after removing `--fail-stop`, `--repeat`, and `--cooldown`.
- Add or refresh a minimal usage example that shows one invocation performing one OTA attempt.

#### `docs/protocol-spec.md`

- Align the controller-side behavioral contract with the new single-shot execution model.
- Remove any protocol text that implies CLI-controlled retry behavior.
- Replace any mention of a user-facing `--probe-timeout` flag with a fixed controller-side 60-second probe timeout unless the implementation later chooses to expose that as a real CLI option.
- Ensure the controller requirements match the new outcome model: success, general failure, and VIN mismatch as a distinct fatal failure.
- Define a required top-level `attemptId` field that the controller generates once per invocation, the run-cmd agent echoes in `/sbin/version` responses, and `remote-updater` echoes in every status payload.

#### `src/session.rs`

- Own the single-iteration state machine.
- Translate MQTT packets into session state transitions.
- Send probe and launch commands with QoS 1 to both legacy and new topics.
- Apply a 60-second probe timeout during VIN verification.
- Start updater silence monitoring only after the first `remote-updater` message.
- Reset the updater silence watchdog only on `remote-updater` topic traffic.
- Ignore version responses and updater status payloads whose `attemptId` does not exactly match the current session.
- Return a structured outcome to the caller.

Recommended interface shape:

- `OtaSession::new(args: &Args, topics: Topics, legacy_topic: String, receiver: Receiver, client: AWSIoTAsyncClient) -> OtaSession`
- `OtaSession::run(self) -> IterationOutcome`

The exact signature may vary to match SDK ownership constraints, but the division of responsibility must remain the same: `main` owns connection setup, and the session owns per-attempt packet handling and state transitions.

#### `src/messages.rs`

- Continue owning protocol-specific payload construction and classification.
- Replace substring VIN matching with exact extraction/parsing of `vincode`.
- Extract and validate the top-level `attemptId` used for attempt correlation.
- Keep `remote-updater` classification as a pure function.

#### `src/topics.rs`

- Remains unchanged unless a small cleanup is needed for topic passing.

The session uses these existing topic names already present in the codebase:

- Legacy command topic: `{sn}`
- Legacy updater status wildcard: `{sn}/remote-updater/#`
- Newer-firmware run-cmd request topic: `{sn}/iov/remote-cmd/sreq/run-cmd/v0`
- Newer-firmware run-cmd response topic: `{sn}/iov/remote-cmd/vres/run-cmd/v0`
- Online status topic: `{sn}/public/status/online/v0`

## Session Model

The session owns a phase enum and an outcome enum.

It also owns a stable per-invocation attempt identifier, `attemptId`, generated by the controller before the first publish. Every accepted version response and every accepted `remote-updater` status payload must carry that same top-level `attemptId` value.

## Correlation Contract

The controller generates one opaque string, `attemptId`, for each invocation and uses it for both freshness and attribution.

- Probe `runCmd` request: include top-level `attemptId` in the JSON payload.
- Launch `runCmd` request: include the same top-level `attemptId` in the JSON payload.
- Launch shell command: append `--attempt-id <attemptId>` so `remote-updater` can echo the identifier directly.
- `/sbin/version` response: the run-cmd agent must echo the request `attemptId` as a top-level JSON field alongside `version` and `vincode`.
- `remote-updater` status payloads: every message must include the same top-level `attemptId`.

Controller-side handling rules:

- A version response with a missing or non-matching `attemptId` is ignored as stale or unrelated traffic.
- A `remote-updater` status payload with a missing or non-matching `attemptId` is ignored as stale or unrelated traffic.
- Only payloads whose `attemptId` exactly matches the current session are allowed to drive phase transitions or terminal outcomes.

This replaces the earlier queue-drain and PubAck freshness-barrier approach. Freshness is established by explicit end-to-end correlation, not by broker timing assumptions.

### Phases

- `Probing`: waiting for a valid `/sbin/version` response.
- `AwaitingUpdaterStart`: VIN matched and launch command sent, but no `remote-updater` message seen yet.
- `MonitoringUpdater`: first `remote-updater` message received; silence watchdog active.
- `Finished`: terminal state entered immediately before returning an outcome.

### Outcomes

Use a domain-specific result instead of `Result<(), ()>`.

- `IterationOutcome::Success(SuccessKind)`
- `IterationOutcome::Failure(FailureKind)`
- `IterationOutcome::FatalFailure(FatalFailureKind)`

Recommended variants:

- `SuccessKind::Reported`
- `SuccessKind::SilentReboot`
- `FailureKind::ProbeTimeout`
- `FailureKind::UpdaterFailed`
- `FailureKind::SessionAborted`
- `FatalFailureKind::VinMismatch`

The distinction between `SuccessKind::Reported` and `SuccessKind::SilentReboot` exists for logging and operator visibility. Both are successful attempt outcomes, but they should produce different log messages so the operator can tell whether success was explicit or inferred from reboot silence.

`main` should treat these outcomes as follows:

- `Success`: exit the program successfully.
- `Failure`: exit the program unsuccessfully with exit code `1`.
- `FatalFailure::VinMismatch`: exit the program unsuccessfully with exit code `2` and a VIN-mismatch-specific log message.

## Runtime Flow

1. Build a fresh session for the single OTA attempt after MQTT connection setup and topic subscription.
2. Generate one `attemptId` for that invocation and attach it to both the probe and launch publish plans.
3. On `ConnAck`, immediately publish the `/sbin/version` probe to both command topics using QoS 1.
4. While in `Probing`, accept only version-response messages whose top-level `attemptId` matches the session attempt.
5. Parse the accepted response payload and extract `vincode` exactly.
6. If the VIN matches `--vin`, publish the `remote-updater` command to both command topics using QoS 1, append `--attempt-id <attemptId>` to the launched shell command, and transition to `AwaitingUpdaterStart`.
7. If the VIN does not match, return `FatalFailure::VinMismatch`.
8. If no valid correlated version response arrives within 60 seconds, return `Failure::ProbeTimeout`.
9. While in `AwaitingUpdaterStart`, ignore silence timing. The watchdog is not running yet.
10. If no correlated `remote-updater` status message arrives within 10 seconds of launching the updater, return `Failure::UpdaterFailed`.
11. While in `AwaitingUpdaterStart`, ignore late version responses and all non-`remote-updater` publish traffic for state-transition purposes; they must not reset the updater-start timeout.
12. On the first correlated `remote-updater` topic message, transition to `MonitoringUpdater` and start the 5-minute silence timer.
13. While in `MonitoringUpdater`, classify each correlated `remote-updater` payload.
14. `UpdateSuccess` returns `Success::Reported`.
15. Any `auto_exit` payload that is not `Alive` and does not report `UpdateSuccess` returns `Failure::UpdaterFailed`.
16. Progress or keepalive on correlated `remote-updater` topics resets the silence timer.
17. Unrecognized non-`auto_exit` correlated `remote-updater` payloads are treated as progress for timeout-reset purposes and logged at debug level.
18. Non-matching or missing `attemptId` payloads are ignored rather than treated as progress or failure.
19. Five minutes of silence after monitoring begins returns `Success::SilentReboot`.

On every terminal path, the session transitions to `Finished`, returns its `IterationOutcome`, and lets `main` tear down the attempt-scoped tasks.

## Parsing Changes

`messages.rs` should stop using `contains(vin)` for validation.

Preferred API shape:

- `extract_vincode(message: &str) -> Option<String>`
- `extract_attempt_id(message: &str) -> Option<String>`
- `vin_matches(message: &str, vin: &str) -> bool` implemented via exact comparison on extracted VIN

Behavioral rules:

- Non-JSON or malformed JSON payloads are not version responses.
- Missing `vincode` means no match.
- Missing `attemptId` means the payload is not attributable to the current attempt.
- Extra fields are ignored.
- Matching is strict string equality.
- Only the top-level `vincode` field is considered authoritative.
- Only the top-level `attemptId` field is considered authoritative.

## CLI And Documentation Changes

The CLI contract changes in these ways:

- Remove `--fail-stop` from the parser and help output.
- Remove `--repeat` from the parser and help output.
- Remove `--cooldown` from the parser and help output.
- Remove `fail_stop()` helper logic from `Args` and eliminate repeat/cooldown loop logic entirely.
- Update `docs/remote-ota.md`, `README.md`, `docs/protocol-spec.md`, and any user-facing references so the tool is documented as a single-shot OTA trigger and monitor.
- Update the command construction so `remote-updater` is launched with `--attempt-id <attemptId>`.

Updated execution behavior:

- The program performs one OTA attempt per invocation.
- VIN mismatch terminates immediately as a distinct failure mode.
- There is no user-configurable retry, cooldown, or stop-on-failure mode.
- `Success::Reported` and `Success::SilentReboot` are both treated as successful executions.
- `ProbeTimeout`, `UpdaterFailed`, and `SessionAborted` are terminal failures for that invocation.
- Exit code `0` means success, exit code `1` means general failure, and exit code `2` means VIN mismatch.
- Freshness is determined by `attemptId`, not by queued-message draining or MQTT PubAck ordering.

Documentation-specific expectations:

- `README.md` should describe how to run one OTA attempt and what each exit code means.
- `docs/protocol-spec.md` should describe the controller-side 60-second probe timeout as a behavioral contract, not a required CLI flag.
- `docs/protocol-spec.md` should stop referring to `Err(())` and `Ok(())` as the public contract and instead describe the observable behavior in terms of success, failure, and VIN mismatch termination.

## Error Handling

- AWS connection setup can remain unrecoverable for now.
- Non-UTF-8 payloads remain logged and ignored.
- Session panics, task-join failures, or event-loop termination are all mapped to `Failure::SessionAborted`.
- Fatal and non-fatal failures must be logged distinctly.
- The 5-minute silence outcome remains classified as success because the current product behavior treats updater silence after startup as an expected reboot indicator, not as an unknown failure.
- Correlation mismatches are logged at debug level and ignored; they must not reset timers or complete the session.

## Testing Strategy

### `src/messages.rs`

Add or update unit tests for:

- Exact VIN hit.
- Substring false positive rejection.
- Missing `vincode` rejection.
- Exact attempt-id extraction.
- Missing attempt-id rejection for correlation checks.
- Malformed JSON rejection.
- Existing `remote-updater` classification behavior.

Recommended explicit case:

- Response VIN `ABCDEFG1234567890` must not match expected VIN `ABCDEFG123`.

### `src/session.rs`

Add unit tests around phase transitions and outcomes by feeding synthetic packets or abstracted events.

Required coverage:

- Probe timeout returns failure.
- VIN mismatch returns fatal failure.
- Matching VIN sends launch and enters `AwaitingUpdaterStart`.
- Version responses with non-matching attempt IDs are ignored.
- Silence watchdog does not start before first updater message.
- First updater message starts monitoring.
- Updater success returns reported success.
- Updater failure returns failure.
- Updater messages with non-matching attempt IDs are ignored.
- Silence after monitoring starts returns silent reboot success.

### Verification

Required verification commands after implementation:

- `cargo test`
- `cargo clippy --all-targets --all-features -- -D warnings`
- `cargo fmt --all -- --check`

## Tradeoffs

This design intentionally introduces a new module, explicit outcome types, and a protocol-level correlation field instead of doing another local timing workaround in `main.rs`. That is more coordination work up front, but it fixes the root issue: the current state machine is implicit and broker timing alone cannot distinguish stale messages from current-attempt traffic. Removing `--fail-stop`, `--repeat`, and `--cooldown` also simplifies the top-level control flow so the binary behaves as a single, deterministic OTA attempt per invocation. The added module boundary should also make future fixes such as `M-1` and `M-2` easier to implement without growing `main.rs` further.

## Non-Goals

- Do not change TLS/authentication handling.
- Do not address password redaction in logs.
- Do not redefine `--clean` behavior beyond its effect on the launched updater command.