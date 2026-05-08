#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs rescue advisor
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESCUE_SH="$REPO_ROOT/scripts/lib/rescue.sh"
DOCTOR_SH="$REPO_ROOT/scripts/lib/doctor.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_RESCUE_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-rescue-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

mkdir -p "$ARTIFACT_DIR"

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
    [[ -n "${2:-}" ]] && echo "  Reason: $2"
}

write_json() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path"
}

run_rescue_json() {
    local name="$1"
    shift
    local output status

    set +e
    output="$(bash "$RESCUE_SH" --json "$@" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output.json"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

run_rescue_human() {
    local name="$1"
    shift
    local output status

    set +e
    output="$(bash "$RESCUE_SH" "$@" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output.txt"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

test_no_state_warns_with_status_command() {
    local acfs_home output status
    acfs_home="$ARTIFACT_DIR/no-state/.acfs"
    mkdir -p "$acfs_home"

    output="$(run_rescue_json no_state --acfs-home "$acfs_home")"
    status="$(cat "$ARTIFACT_DIR/no_state.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "warn" and
      .severity == "needs_state" and
      .next_command == "acfs status --json" and
      .sources.state.status == "missing" and
      (.evidence[] | select(test("State file not found")))
    ' <<<"$output" >/dev/null || return 1

    pass "no_state_warns_with_status_command"
}

test_failed_phase_uses_recorded_resume_hint() {
    local acfs_home state_file output status
    acfs_home="$ARTIFACT_DIR/failed/.acfs"
    state_file="$acfs_home/state.json"
    write_json "$state_file" <<'JSON'
{
  "schema_version": 3,
  "version": "1.0",
  "mode": "vibe",
  "completed_phases": ["bootstrap"],
  "failed_phase": "cli_tools",
  "failed_step": "install rch",
  "failed_error": "installer exited 1",
  "resume_hint": "curl -fsSL https://acfs.sh | bash -s -- --resume --yes"
}
JSON

    output="$(run_rescue_json failed_phase --acfs-home "$acfs_home")"
    status="$(cat "$ARTIFACT_DIR/failed_phase.exit")"

    [[ "$status" -eq 2 ]] || return 1
    jq -e '
      .status == "fail" and
      .severity == "blocked" and
      .install_status == "failed" and
      .next_command == "curl -fsSL https://acfs.sh | bash -s -- --resume --yes" and
      .checkpoint.last_completed_phase == "bootstrap" and
      (.evidence[] | select(. == "Failed phase recorded: cli_tools")) and
      (.evidence[] | select(. == "Failed step recorded: install rch"))
    ' <<<"$output" >/dev/null || return 1

    pass "failed_phase_uses_recorded_resume_hint"
}

test_stale_checkpoint_points_to_continue_status() {
    local acfs_home state_file output status
    acfs_home="$ARTIFACT_DIR/stale/.acfs"
    state_file="$acfs_home/state.json"
    write_json "$state_file" <<'JSON'
{
  "schema_version": 3,
  "version": "1.0",
  "mode": "vibe",
  "completed_phases": ["bootstrap"],
  "current_phase": "languages",
  "current_step": "install bun",
  "failed_phase": null,
  "failed_step": null,
  "last_updated": 1000
}
JSON

    output="$(run_rescue_json stale_checkpoint --acfs-home "$acfs_home" --now-epoch 5000 --stale-seconds 60)"
    status="$(cat "$ARTIFACT_DIR/stale_checkpoint.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "warn" and
      .severity == "stale_checkpoint" and
      .install_status == "running" and
      .next_command == "acfs continue --status" and
      .checkpoint.current_phase == "languages" and
      .checkpoint.age_seconds == 4000 and
      (.evidence[] | select(. == "Checkpoint age seconds: 4000"))
    ' <<<"$output" >/dev/null || return 1

    pass "stale_checkpoint_points_to_continue_status"
}

test_malformed_checkpoint_fails_closed() {
    local acfs_home state_file output status
    acfs_home="$ARTIFACT_DIR/malformed/.acfs"
    state_file="$acfs_home/state.json"
    mkdir -p "$acfs_home"
    printf '{"version": "1.0", "completed_phases": [' > "$state_file"

    output="$(run_rescue_json malformed_checkpoint --acfs-home "$acfs_home")"
    status="$(cat "$ARTIFACT_DIR/malformed_checkpoint.exit")"

    [[ "$status" -eq 2 ]] || return 1
    jq -e '
      .status == "fail" and
      .severity == "blocked" and
      .next_command == "acfs support-bundle" and
      .sources.state.status == "malformed" and
      (.evidence[] | select(test("not valid JSON")))
    ' <<<"$output" >/dev/null || return 1

    pass "malformed_checkpoint_fails_closed"
}

test_future_checkpoint_schema_fails_closed() {
    local acfs_home state_file output status
    acfs_home="$ARTIFACT_DIR/future-schema/.acfs"
    state_file="$acfs_home/state.json"
    write_json "$state_file" <<'JSON'
{
  "schema_version": 99,
  "version": "9.9.9",
  "mode": "vibe",
  "completed_phases": ["user_setup"],
  "current_phase": "filesystem",
  "failed_phase": null,
  "failed_step": null,
  "last_updated": 1000
}
JSON

    output="$(run_rescue_json future_checkpoint_schema --acfs-home "$acfs_home")"
    status="$(cat "$ARTIFACT_DIR/future_checkpoint_schema.exit")"

    [[ "$status" -eq 2 ]] || return 1
    jq -e '
      .status == "fail" and
      .severity == "future_state" and
      .next_command == "acfs support-bundle" and
      .sources.state.status == "future_version" and
      .checkpoint.state_schema_version == 99 and
      .checkpoint.supported_state_schema_version == 3 and
      (.evidence[] | select(. == "State schema version recorded: 99"))
    ' <<<"$output" >/dev/null || return 1

    pass "future_checkpoint_schema_fails_closed"
}

test_healthy_state_points_to_onboard() {
    local acfs_home state_file output status
    acfs_home="$ARTIFACT_DIR/healthy/.acfs"
    state_file="$acfs_home/state.json"
    write_json "$state_file" <<'JSON'
{
  "schema_version": 3,
  "version": "1.0",
  "mode": "vibe",
  "completed_phases": ["bootstrap", "languages", "finalize"],
  "current_phase": null,
  "failed_phase": null,
  "failed_step": null,
  "last_updated": "2026-05-08T12:00:00Z"
}
JSON

    output="$(run_rescue_json healthy_state --acfs-home "$acfs_home")"
    status="$(cat "$ARTIFACT_DIR/healthy_state.exit")"

    [[ "$status" -eq 0 ]] || return 1
    jq -e '
      .status == "pass" and
      .severity == "healthy" and
      .install_status == "healthy" and
      .next_command == "onboard" and
      .checkpoint.last_completed_phase == "finalize" and
      .checkpoint.next_phase == null and
      (.evidence[] | select(. == "Finalize phase is marked complete."))
    ' <<<"$output" >/dev/null || return 1

    pass "healthy_state_points_to_onboard"
}

test_support_bundle_hint_includes_latest_report() {
    local acfs_home support_dir bundle_dir output json_output status
    acfs_home="$ARTIFACT_DIR/support/.acfs"
    support_dir="$acfs_home/support"
    bundle_dir="$support_dir/acfs-support-20260508T120000Z"
    mkdir -p "$bundle_dir"
    printf '# Support Report\n' > "$bundle_dir/support-report.md"

    json_output="$(run_rescue_json support_hint --acfs-home "$acfs_home")"
    status="$(cat "$ARTIFACT_DIR/support_hint.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e --arg latest "$bundle_dir" --arg report "$bundle_dir/support-report.md" '
      .support_bundle.command == "acfs support-bundle" and
      .support_bundle.available == true and
      .support_bundle.latest == $latest and
      .support_bundle.report == $report
    ' <<<"$json_output" >/dev/null || return 1

    output="$(run_rescue_human support_hint_human --acfs-home "$acfs_home")"
    grep -Fq "Support bundle command: acfs support-bundle" <<<"$output" || return 1
    grep -Fq "Support report: $bundle_dir/support-report.md" <<<"$output" || return 1
    ! grep -E 'rm -rf|git reset|git clean|delete|overwrite' <<<"$output" >/dev/null || return 1

    pass "support_bundle_hint_includes_latest_report"
}

test_doctor_failure_prefers_support_bundle() {
    local acfs_home doctor_file output status
    acfs_home="$ARTIFACT_DIR/doctor-failure/.acfs"
    doctor_file="$ARTIFACT_DIR/doctor-failure/doctor.json"
    mkdir -p "$acfs_home"
    write_json "$doctor_file" <<'JSON'
{
  "status": "fail",
  "summary": {"pass": 8, "warn": 1, "fail": 2}
}
JSON

    output="$(run_rescue_json doctor_failure --acfs-home "$acfs_home" --doctor-file "$doctor_file")"
    status="$(cat "$ARTIFACT_DIR/doctor_failure.exit")"

    [[ "$status" -eq 2 ]] || return 1
    jq -e '
      .status == "fail" and
      .severity == "doctor_failed" and
      .next_command == "acfs support-bundle" and
      .sources.doctor.status == "valid" and
      (.evidence[] | select(. == "Doctor status: fail"))
    ' <<<"$output" >/dev/null || return 1

    pass "doctor_failure_prefers_support_bundle"
}

test_doctor_dispatches_rescue_subcommand() {
    local acfs_home output status
    acfs_home="$ARTIFACT_DIR/dispatch/.acfs"
    mkdir -p "$acfs_home"

    set +e
    output="$(bash "$DOCTOR_SH" rescue --json --acfs-home "$acfs_home" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/dispatch.output.json"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/dispatch.exit"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '.status == "warn" and .next_command == "acfs status --json"' <<<"$output" >/dev/null || return 1

    pass "doctor_dispatches_rescue_subcommand"
}

run_test() {
    local name="$1"
    if "$name"; then
        :
    else
        fail "$name" "See artifacts under $ARTIFACT_DIR"
    fi
}

main() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "SKIP: jq is required for rescue tests"
        exit 0
    fi

    run_test test_no_state_warns_with_status_command
    run_test test_failed_phase_uses_recorded_resume_hint
    run_test test_stale_checkpoint_points_to_continue_status
    run_test test_malformed_checkpoint_fails_closed
    run_test test_future_checkpoint_schema_fails_closed
    run_test test_healthy_state_points_to_onboard
    run_test test_support_bundle_hint_includes_latest_report
    run_test test_doctor_failure_prefers_support_bundle
    run_test test_doctor_dispatches_rescue_subcommand

    echo
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo "Artifacts: $ARTIFACT_DIR"

    [[ "$TESTS_FAILED" -eq 0 ]]
}

main "$@"
