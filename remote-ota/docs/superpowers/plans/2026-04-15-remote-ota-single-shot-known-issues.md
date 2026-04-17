# Remote OTA Single-Shot Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `remote-ota` from a retry-loop OTA runner into a single-shot OTA tool while fixing known issues around exact VIN matching, QoS, watchdog timing, probe timeout, and stale-message attribution.

**Architecture:** Extract a dedicated `session` module that owns the per-attempt state machine and returns explicit outcomes. Add a controller-generated `attemptId` that is attached to probe and launch requests and must be echoed by both `/sbin/version` responses and `remote-updater` status payloads. Keep `main.rs` focused on CLI parsing, MQTT setup, one session run, and exit-code mapping; keep `messages.rs` focused on pure payload parsing and classification.

**Tech Stack:** Rust 2021, tokio, clap, aws-iot-device-sdk-rust, rumqttc, serde_json, tracing

---

Repo workflow note: do not include files under `docs/` in task commits. Leave documentation changes uncommitted unless explicitly requested.

Correlation note: the earlier queue-drain and PubAck freshness barriers are superseded by the `attemptId` protocol contract. New implementation work should remove those timing-based barriers instead of extending them.

### Task 1: Harden VIN Parsing In `messages.rs`

**Files:**
- Modify: `src/messages.rs`
- Test: `src/messages.rs`

- [ ] **Step 1: Write the failing parsing tests**

```rust
#[test]
fn extract_vincode_returns_exact_top_level_value() {
    let msg = r#"{"version":"1.2.3","vincode":"LSJABCD1234567890"}"#;
    assert_eq!(extract_vincode(msg).as_deref(), Some("LSJABCD1234567890"));
}

#[test]
fn vin_match_rejects_substring_false_positive() {
    let msg = r#"{"version":"1.2.3","vincode":"ABCDEFG1234567890"}"#;
    assert!(!vin_matches(msg, "ABCDEFG123"));
}

#[test]
fn malformed_json_is_not_a_version_response() {
    assert!(!is_version_response("not-json"));
    assert_eq!(extract_vincode("not-json"), None);
}
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `cargo test messages::tests::extract_vincode_returns_exact_top_level_value messages::tests::vin_match_rejects_substring_false_positive messages::tests::malformed_json_is_not_a_version_response -- --nocapture`

Expected: FAIL because `extract_vincode` does not exist and `vin_matches` still uses substring matching.

- [ ] **Step 3: Implement exact VIN extraction and matching**

```rust
pub fn extract_vincode(message: &str) -> Option<String> {
    let value: Value = serde_json::from_str(message).ok()?;
    value.get(FIELD_VINCODE)?.as_str().map(ToOwned::to_owned)
}

pub fn is_version_response(message: &str) -> bool {
    let value: Value = match serde_json::from_str(message) {
        Ok(value) => value,
        Err(_) => return false,
    };

    value.get(FIELD_VERSION).and_then(Value::as_str).is_some()
        && value.get(FIELD_VINCODE).and_then(Value::as_str).is_some()
}

pub fn vin_matches(message: &str, vin: &str) -> bool {
    extract_vincode(message).as_deref() == Some(vin)
}
```

- [ ] **Step 4: Run all `messages.rs` tests to verify they pass**

Run: `cargo test messages::tests -- --nocapture`

Expected: PASS for the new VIN parsing cases and the existing updater classification cases.

- [ ] **Step 5: Commit the parsing change**

```bash
git add src/messages.rs
git commit -m "fix: parse version VIN exactly"
```

### Task 1A: Add Attempt Correlation Parsing In `messages.rs`

**Files:**
- Modify: `src/messages.rs`
- Test: `src/messages.rs`

- [ ] **Step 1: Write the failing attempt-id parsing tests**

```rust
#[test]
fn extract_attempt_id_returns_top_level_value() {
    let msg = r#"{"attemptId":"attempt-123","version":"1.2.3","vincode":"VIN123"}"#;
    assert_eq!(extract_attempt_id(msg).as_deref(), Some("attempt-123"));
}

#[test]
fn extract_attempt_id_ignores_nested_value() {
    let msg = r#"{"data":{"attemptId":"nested"},"version":"1.2.3","vincode":"VIN123"}"#;
    assert_eq!(extract_attempt_id(msg), None);
}

#[test]
fn build_run_cmd_msg_includes_attempt_id() {
    let msg = build_run_cmd_msg("SN123", "/sbin/version", 60, "attempt-123");
    assert_eq!(msg["attemptId"], "attempt-123");
}
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `cargo test messages::tests::extract_attempt_id_returns_top_level_value messages::tests::extract_attempt_id_ignores_nested_value messages::tests::build_run_cmd_msg_includes_attempt_id -- --nocapture`

Expected: FAIL because `extract_attempt_id` and the new builder argument do not exist yet.

- [ ] **Step 3: Implement attempt-id extraction and builder support**

Implementation requirements:

- Add a top-level `attemptId` constant and extraction helper.
- Update `build_run_cmd_msg` so both probe and launch requests include the controller-generated `attemptId`.
- Keep matching strict and top-level only.

- [ ] **Step 4: Re-run `messages.rs` tests**

Run: `cargo test messages::tests -- --nocapture`

Expected: PASS for VIN parsing, updater classification, and attempt-id parsing.

- [ ] **Step 5: Commit the parsing change**

```bash
git add src/messages.rs
git commit -m "feat: add protocol attempt correlation"
```

### Task 2: Introduce The Session State Machine Module

**Files:**
- Create: `src/session.rs`
- Modify: `src/main.rs`
- Test: `src/session.rs`

- [ ] **Step 1: Write failing state-machine tests in the new session module**

```rust
#[test]
fn probe_timeout_returns_failure() {
    let mut session = OtaSession::new_for_test("EXPECTEDVIN");
    let outcome = session.on_probe_timeout();
    assert_eq!(outcome, IterationOutcome::Failure(FailureKind::ProbeTimeout));
}

#[test]
fn first_updater_message_starts_monitoring() {
    let mut session = OtaSession::new_for_test("EXPECTEDVIN");
    session.mark_launch_sent();

    session.on_remote_updater_message(r#"{"type":"progress","percent":1}"#);

    assert_eq!(session.phase(), SessionPhase::MonitoringUpdater);
}

#[test]
fn vin_mismatch_returns_fatal_failure() {
    let mut session = OtaSession::new_for_test("EXPECTEDVIN");
    let outcome = session.on_version_response(r#"{"version":"1.0","vincode":"OTHER"}"#);
    assert_eq!(outcome, Some(IterationOutcome::FatalFailure(FatalFailureKind::VinMismatch)));
}

#[test]
fn updater_success_returns_reported_success() {
    let mut session = OtaSession::launched_for_test("EXPECTEDVIN");
    let outcome = session.on_remote_updater_message(r#"{"type":"auto_exit","result":"UpdateSuccess"}"#);
    assert_eq!(outcome, Some(IterationOutcome::Success(SuccessKind::Reported)));
}

#[test]
fn updater_failure_returns_failure() {
    let mut session = OtaSession::launched_for_test("EXPECTEDVIN");
    let outcome = session.on_remote_updater_message(r#"{"type":"auto_exit","result":"UpdateFailed"}"#);
    assert_eq!(outcome, Some(IterationOutcome::Failure(FailureKind::UpdaterFailed)));
}

#[test]
fn silence_timeout_is_ignored_before_first_updater_message() {
    let mut session = OtaSession::awaiting_updater_for_test("EXPECTEDVIN");
    assert_eq!(session.on_silence_timeout(), None);
}

#[test]
fn updater_start_timeout_returns_failure() {
    let mut session = OtaSession::awaiting_updater_for_test("EXPECTEDVIN");
    assert_eq!(
        session.on_updater_start_timeout(),
        Some(IterationOutcome::Failure(FailureKind::UpdaterFailed))
    );
}

#[test]
fn silence_after_monitoring_returns_silent_reboot_success() {
    let mut session = OtaSession::monitoring_for_test("EXPECTEDVIN");
    assert_eq!(
        session.on_silence_timeout(),
        Some(IterationOutcome::Success(SuccessKind::SilentReboot))
    );
}

#[test]
fn unrecognized_non_auto_exit_payload_resets_silence_timer_as_progress() {
    let mut session = OtaSession::monitoring_for_test("EXPECTEDVIN");
    let outcome = session.on_remote_updater_message(r#"{"type":"mystery","payload":"x"}"#);
    assert_eq!(outcome, None);
    assert!(session.silence_timer_was_reset_for_test());
}

#[test]
fn unknown_auto_exit_payload_returns_failure() {
    let mut session = OtaSession::monitoring_for_test("EXPECTEDVIN");
    let outcome = session.on_remote_updater_message(r#"{"type":"auto_exit","result":"InstallFailed"}"#);
    assert_eq!(outcome, Some(IterationOutcome::Failure(FailureKind::UpdaterFailed)));
}

#[test]
fn malformed_updater_payload_returns_failure() {
    let mut session = OtaSession::monitoring_for_test("EXPECTEDVIN");
    let outcome = session.on_remote_updater_message("not-json");
    assert_eq!(outcome, Some(IterationOutcome::Failure(FailureKind::UpdaterFailed)));
}
```

- [ ] **Step 2: Run the targeted session tests to verify they fail**

Run: `cargo test session::tests -- --nocapture`

Expected: FAIL because `src/session.rs` and the session types do not exist yet.

- [ ] **Step 3: Implement the session domain types and transitions**

```rust
const PROBE_TIMEOUT: Duration = Duration::from_secs(60);
const UPDATER_START_TIMEOUT: Duration = Duration::from_secs(10);
const SILENCE_TIMEOUT: Duration = Duration::from_secs(300);

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IterationOutcome {
    Success(SuccessKind),
    Failure(FailureKind),
    FatalFailure(FatalFailureKind),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionPhase {
    Probing,
    AwaitingUpdaterStart,
    MonitoringUpdater,
    Finished,
}

pub struct OtaSession {
    phase: SessionPhase,
    expected_vin: String,
}
```

Implementation requirements:

- Keep the state-transition logic testable without requiring a live MQTT broker.
- Expose small helpers for test-only driving of version responses, updater messages, and timeouts.
- Treat a missing first updater status message after 10 seconds as `Failure(FailureKind::UpdaterFailed)`.
- Treat unrecognized non-`auto_exit` updater payloads as progress for timeout-reset purposes.
- Treat unknown `auto_exit` updater payloads as failures to preserve fail-closed OTA behavior.
- Ignore payloads whose top-level `attemptId` is missing or does not match the current session.

- [ ] **Step 4: Re-run the session tests to verify the model works**

Run: `cargo test session::tests -- --nocapture`

Expected: PASS for timeout, VIN mismatch, updater monitoring start, updater success, updater failure, and silent-reboot cases.

- [ ] **Step 5: Commit the session model change**

```bash
git add src/session.rs
git commit -m "refactor: add OTA session state machine"
```

### Task 3: Wire `main.rs` To Single-Shot Execution

**Files:**
- Modify: `src/main.rs`
- Modify: `src/session.rs`
- Test: `src/session.rs`

- [ ] **Step 1: Write a failing integration-oriented test for single-shot outcomes**

```rust
#[test]
fn session_aborted_maps_to_general_failure() {
    assert_eq!(exit_code_for_outcome(&IterationOutcome::Failure(FailureKind::SessionAborted)), 1);
}

#[test]
fn vin_mismatch_maps_to_exit_code_two() {
    assert_eq!(exit_code_for_outcome(&IterationOutcome::FatalFailure(FatalFailureKind::VinMismatch)), 2);
}

#[test]
fn publish_plan_uses_both_topics_with_qos_1() {
    let plan = build_probe_publish_plan("SN123");
    assert_eq!(plan.qos, QoS::AtLeastOnce);
    assert_eq!(plan.topics, vec!["SN123".to_string(), "SN123/iov/remote-cmd/sreq/run-cmd/v0".to_string()]);
}
```

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `cargo test session_aborted_maps_to_general_failure vin_mismatch_maps_to_exit_code_two -- --nocapture`

Expected: FAIL because exit-code mapping and single-shot main-path helpers do not exist yet.

- [ ] **Step 3: Replace the retry loop with one attempt and QoS 1 publishing**

```rust
fn exit_code_for_outcome(outcome: &IterationOutcome) -> i32 {
    match outcome {
        IterationOutcome::Success(_) => 0,
        IterationOutcome::Failure(_) => 1,
        IterationOutcome::FatalFailure(FatalFailureKind::VinMismatch) => 2,
    }
}
```

Implementation checklist:

- Remove `repeat`, `fail_stop`, and `cooldown` from `Args`.
- Remove `fail_stop()` helper.
- Generate one `attemptId` per invocation and thread it through the session and publish plans.
- Append `--attempt-id <attemptId>` to the launched `remote-updater` command.
- Publish probe and launch messages with `QoS::AtLeastOnce`.
- Create the MQTT receiver after subscription and pass it into `OtaSession`.
- Start probe send on `ConnAck`.
- Return a process exit code based on the single attempt outcome.
- Map task-join failure and event-loop termination to `FailureKind::SessionAborted`.
- Ensure probe timeout, updater-start timeout, and monitoring silence timeout are driven only by relevant session activity, not by arbitrary MQTT packets.
- Remove the queue-drain and PubAck freshness barriers; freshness must come from `attemptId` matching instead.

Concrete control-flow target:

```rust
let (client, eventloop_stuff) = AWSIoTAsyncClient::new(settings).await.unwrap();
subscribe_required_topics(&client, &topics, &legacy_topic).await?;

let receiver = client.get_receiver().await;
let listen_task = tokio::spawn(async move {
    async_event_loop_listener(eventloop_stuff).await.unwrap();
});

let outcome = OtaSession::new(&args, topics, legacy_topic, receiver, client).run().await;
listen_task.abort();
std::process::exit(exit_code_for_outcome(&outcome));
```

Session-run responsibilities:

- wait for `ConnAck`, then send the probe to both command topics
- enforce `PROBE_TIMEOUT` only during `Probing`, without unrelated packets resetting it
- ignore version responses whose `attemptId` does not match the current session
- enforce `UPDATER_START_TIMEOUT` after launch until the first correlated updater status message arrives
- ignore silence timeouts before the first updater message
- switch to monitoring on the first correlated updater message and enforce `SILENCE_TIMEOUT`, with resets only from correlated updater progress/alive traffic
- convert join failures or receiver termination into `FailureKind::SessionAborted`

- [ ] **Step 4: Run the full test suite for the refactored control flow**

Run: `cargo test -- --nocapture`

Expected: PASS for `messages.rs`, `session.rs`, and any new exit-code or main-path tests.

- [ ] **Step 5: Commit the single-shot control-flow change**

```bash
git add src/main.rs
git commit -m "refactor: run OTA as single-shot command"
```

### Task 4: Update Product Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/protocol-spec.md`
- Modify: `docs/remote-ota.md`

- [ ] **Step 1: Write the documentation deltas**

Required edits:

- `README.md`: remove the incorrect `src/lib.rs` reference, describe `remote-ota` as a single-shot tool, and add one usage example.
- `docs/protocol-spec.md`: remove references to retry-loop semantics, remove `--probe-timeout` as a required CLI flag, replace `Ok(())` and `Err(())` with observable success/failure behavior, and document the fixed 60-second probe timeout.
- `docs/remote-ota.md`: remove `--repeat`, `--fail-stop`, and `--cooldown` from the goals, CLI section, main-loop diagrams, and narrative descriptions.

- [ ] **Step 2: Review the docs for consistency against the spec**

Run: `rg -n "fail-stop|repeat|cooldown|--probe-timeout|Ok\(\)|Err\(\)|src/lib.rs" README.md docs/protocol-spec.md docs/remote-ota.md`

Expected: no stale references that contradict the single-shot design, except where historical context is explicitly intended.

Run: `rg -n "single-shot|single shot|one OTA attempt|exit code 0|exit code 1|exit code 2|60-second probe timeout" README.md docs/protocol-spec.md docs/remote-ota.md`

Expected: each document contains positive language describing the new single-shot behavior, outcome semantics, and fixed probe-timeout contract.

- [ ] **Step 3: Leave documentation changes uncommitted per repo preference**

Do not create a commit for `docs/` changes unless the user explicitly asks for one.

### Task 5: Run Final Verification

**Files:**
- Modify: `src/main.rs`
- Modify: `src/messages.rs`
- Create: `src/session.rs`
- Modify: `README.md`
- Modify: `docs/protocol-spec.md`
- Modify: `docs/remote-ota.md`

- [ ] **Step 1: Run formatting check**

Run: `cargo fmt --all -- --check`

Expected: PASS

- [ ] **Step 2: Run clippy with warnings denied**

Run: `cargo clippy --all-targets --all-features -- -D warnings`

Expected: PASS

- [ ] **Step 3: Run the full test suite**

Run: `cargo test`

Expected: PASS

- [ ] **Step 4: Review git status before handoff**

Run: `git status --short`

Expected:

- code changes committed task-by-task
- documentation changes still uncommitted under `docs/` and `README.md` only if following repo preference strictly

- [ ] **Step 5: Run one manual exit-code smoke check**

Run a controlled invocation against a safe test setup with a known VIN mismatch and verify the shell reports exit code `2`.

Expected: the program terminates after one attempt and the shell reports `2`.

- [ ] **Step 6: Prepare handoff summary**

Summarize:

- exact exit-code behavior
- exact single-shot CLI surface
- QoS 1 behavior
- VIN exact-match behavior
- remaining uncommitted docs changes