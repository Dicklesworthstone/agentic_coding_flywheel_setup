#!/usr/bin/env bash
# ============================================================
# Unit tests for local progress milestones and support summaries
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROGRESS_SH="$REPO_ROOT/scripts/lib/progress.sh"
SUPPORT_SH="$REPO_ROOT/scripts/lib/support.sh"
ONBOARD_SH="$REPO_ROOT/packages/onboard/onboard.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_LOCAL_PROGRESS_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-local-progress-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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

write_file() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path"
}

log_step() { :; }
log_section() { :; }
log_detail() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { :; }

# shellcheck source=../../scripts/lib/progress.sh
source "$PROGRESS_SH"
# shellcheck source=../../scripts/lib/support.sh
source "$SUPPORT_SH"
set -euo pipefail

new_case_dir() {
    local name="$1"
    local case_dir="$ARTIFACT_DIR/$name"
    mkdir -p "$case_dir/home/.acfs" "$case_dir/bundle"
    printf '%s\n' "$case_dir"
}

capture_local_summary() {
    local acfs_home="$1"
    local bundle_dir="$2"
    shift 2 || true

    env "$@" bash -c '
        set -euo pipefail
        log_step() { :; }
        log_section() { :; }
        log_detail() { :; }
        log_success() { :; }
        log_warn() { :; }
        log_error() { :; }
        source "$1"
        _SUPPORT_ACFS_HOME="$2"
        BUNDLE_FILES=()
        capture_local_progress_json "$3"
    ' _ "$SUPPORT_SH" "$acfs_home" "$bundle_dir"
}

capture_checkpoint_summary() {
    local acfs_home="$1"
    local bundle_dir="$2"
    shift 2 || true

    env "$@" bash -c '
        set -euo pipefail
        log_step() { :; }
        log_section() { :; }
        log_detail() { :; }
        log_success() { :; }
        log_warn() { :; }
        log_error() { :; }
        source "$1"
        _SUPPORT_ACFS_HOME="$2"
        BUNDLE_FILES=()
        capture_checkpoint_summary_json "$3"
    ' _ "$SUPPORT_SH" "$acfs_home" "$bundle_dir"
}

assert_no_private_content() {
    local file="$1"
    ! grep -Eq 'ghp_|/home/alice|192\.0\.2\.10|PRIVATE' "$file"
}

test_empty_progress_summary_is_structured() {
    local case_dir acfs_home bundle_dir summary
    case_dir="$(new_case_dir empty)"
    acfs_home="$case_dir/home/.acfs"
    bundle_dir="$case_dir/bundle"
    summary="$bundle_dir/local_progress.json"

    capture_local_summary "$acfs_home" "$bundle_dir" HOME="$case_dir/home" ACFS_HOME="$acfs_home"

    jq -e '
      .schema_version == 1 and
      .status == "empty" and
      .summary.milestone_event_count == 0 and
      .milestones.status == "empty" and
      .onboard_progress.status == "empty" and
      .installer_state.status == "empty" and
      .redaction.raw_values_collected == false and
      .redaction.command_history_collected == false and
      .redaction.network_submission == false
    ' "$summary" >/dev/null || return 1

    pass "empty_progress_summary_is_structured"
}

test_corrupted_progress_fails_closed() {
    local case_dir acfs_home bundle_dir summary token_like
    case_dir="$(new_case_dir corrupted)"
    acfs_home="$case_dir/home/.acfs"
    bundle_dir="$case_dir/bundle"
    summary="$bundle_dir/local_progress.json"
    token_like="ghp_abcdefghijklmnopqrstuvwxyz1234567890ABCD"

    printf '{"events":[{"token":"%s","path":"/home/alice/private"}' "$token_like" > "$acfs_home/local_progress.json"

    capture_local_summary "$acfs_home" "$bundle_dir" HOME="$case_dir/home" ACFS_HOME="$acfs_home"

    jq -e '
      .status == "warn" and
      .milestones.status == "warn" and
      .milestones.source_status == "malformed" and
      .redaction.raw_values_collected == false
    ' "$summary" >/dev/null || return 1
    assert_no_private_content "$summary" || return 1

    pass "corrupted_progress_fails_closed"
}

test_opt_out_suppresses_recording_and_support_marks_skipped() {
    local case_dir acfs_home bundle_dir progress_file summary
    case_dir="$(new_case_dir opt-out)"
    acfs_home="$case_dir/home/.acfs"
    bundle_dir="$case_dir/bundle"
    progress_file="$acfs_home/local_progress.json"
    summary="$bundle_dir/local_progress.json"

    ACFS_LOCAL_PROGRESS=off \
        ACFS_LOCAL_PROGRESS_FILE="$progress_file" \
        local_progress_record_event "onboard" "lesson_started" "started" '{"lesson_index":0}' || return 1
    [[ ! -e "$progress_file" ]] || return 1

    capture_local_summary "$acfs_home" "$bundle_dir" \
        HOME="$case_dir/home" \
        ACFS_HOME="$acfs_home" \
        ACFS_LOCAL_PROGRESS=off

    jq -e '
      .status == "skipped" and
      .milestones.status == "skipped" and
      .milestones.source_status == "opt_out"
    ' "$summary" >/dev/null || return 1

    pass "opt_out_suppresses_recording_and_support_marks_skipped"
}

test_support_summary_redacts_untrusted_progress_fields() {
    local case_dir acfs_home bundle_dir summary token_like
    case_dir="$(new_case_dir redaction)"
    acfs_home="$case_dir/home/.acfs"
    bundle_dir="$case_dir/bundle"
    summary="$bundle_dir/local_progress.json"
    token_like="ghp_abcdefghijklmnopqrstuvwxyz1234567890ABCD"

    write_file "$acfs_home/local_progress.json" <<JSON
{
  "schema_version": 1,
  "events": [
    {
      "timestamp": "2026-05-08T12:00:00Z",
      "source": "onboard",
      "kind": "lesson_started",
      "status": "started",
      "details": {
        "lesson_index": 2,
        "lesson_number": 3,
        "phase_id": "/home/alice/private",
        "token": "$token_like",
        "ip": "192.0.2.10"
      }
    }
  ]
}
JSON

    capture_local_summary "$acfs_home" "$bundle_dir" HOME="$case_dir/home" ACFS_HOME="$acfs_home"

    jq -e '
      .status == "pass" and
      .milestones.event_count == 1 and
      .milestones.latest_event.details.lesson_index == 2 and
      (.milestones.latest_event.details | has("phase_id") | not) and
      (.milestones.latest_event.details | has("token") | not)
    ' "$summary" >/dev/null || return 1
    assert_no_private_content "$summary" || return 1

    pass "support_summary_redacts_untrusted_progress_fields"
}

test_checkpoint_summary_covers_fixture_states() {
    local case_dir acfs_home bundle_dir summary token_like
    token_like="ghp_abcdefghijklmnopqrstuvwxyz1234567890ABCD"

    case_dir="$(new_case_dir checkpoint-missing)"
    acfs_home="$case_dir/home/.acfs"
    bundle_dir="$case_dir/bundle"
    summary="$bundle_dir/checkpoint_summary.json"
    capture_checkpoint_summary "$acfs_home" "$bundle_dir" HOME="$case_dir/home" ACFS_HOME="$acfs_home"
    jq -e '
      .status == "empty" and
      .severity == "needs_state" and
      .next_action == "acfs status --json" and
      .state.source_status == "missing" and
      .redaction.raw_values_collected == false
    ' "$summary" >/dev/null || return 1

    case_dir="$(new_case_dir checkpoint-stale)"
    acfs_home="$case_dir/home/.acfs"
    bundle_dir="$case_dir/bundle"
    summary="$bundle_dir/checkpoint_summary.json"
    write_file "$acfs_home/state.json" <<'JSON'
{
  "schema_version": 3,
  "version": "1.0",
  "mode": "vibe",
  "completed_phases": ["user_setup"],
  "current_phase": "filesystem",
  "current_step": "creating directories",
  "failed_phase": null,
  "failed_step": null,
  "last_updated": 1000
}
JSON
    capture_checkpoint_summary "$acfs_home" "$bundle_dir" \
        HOME="$case_dir/home" \
        ACFS_HOME="$acfs_home" \
        ACFS_SUPPORT_NOW_EPOCH=5000 \
        ACFS_CHECKPOINT_STALE_SECONDS=60
    jq -e '
      .status == "warn" and
      .severity == "stale_checkpoint" and
      .install_status == "running" and
      .next_action == "acfs continue --status" and
      .checkpoint.last_completed_phase == "user_setup" and
      .checkpoint.next_phase == "filesystem" and
      .checkpoint.current_phase == "filesystem" and
      .checkpoint.current_step_present == true and
      .checkpoint.age_seconds == 4000
    ' "$summary" >/dev/null || return 1

    case_dir="$(new_case_dir checkpoint-malformed)"
    acfs_home="$case_dir/home/.acfs"
    bundle_dir="$case_dir/bundle"
    summary="$bundle_dir/checkpoint_summary.json"
    printf '{"failed_error":"%s","target_home":"/home/alice/private"' "$token_like" > "$acfs_home/state.json"
    capture_checkpoint_summary "$acfs_home" "$bundle_dir" HOME="$case_dir/home" ACFS_HOME="$acfs_home"
    jq -e '
      .status == "warn" and
      .severity == "malformed_state" and
      .next_action == "acfs support-bundle" and
      .state.source_status == "malformed" and
      .redaction.raw_errors_collected == false
    ' "$summary" >/dev/null || return 1
    assert_no_private_content "$summary" || return 1

    case_dir="$(new_case_dir checkpoint-future)"
    acfs_home="$case_dir/home/.acfs"
    bundle_dir="$case_dir/bundle"
    summary="$bundle_dir/checkpoint_summary.json"
    write_file "$acfs_home/state.json" <<JSON
{
  "schema_version": 99,
  "version": "9.9.9",
  "mode": "vibe",
  "target_home": "/home/alice/private",
  "completed_phases": ["user_setup"],
  "current_phase": "filesystem",
  "failed_phase": null,
  "failed_error": "$token_like",
  "last_updated": 1000
}
JSON
    capture_checkpoint_summary "$acfs_home" "$bundle_dir" HOME="$case_dir/home" ACFS_HOME="$acfs_home"
    jq -e '
      .status == "warn" and
      .severity == "future_state" and
      .next_action == "acfs support-bundle" and
      .state.source_status == "future_version" and
      .state.schema_version == 99 and
      .state.supported_schema_version == 3 and
      .checkpoint.failed_error_present == true and
      .redaction.resume_command_collected == false
    ' "$summary" >/dev/null || return 1
    assert_no_private_content "$summary" || return 1

    case_dir="$(new_case_dir checkpoint-success)"
    acfs_home="$case_dir/home/.acfs"
    bundle_dir="$case_dir/bundle"
    summary="$bundle_dir/checkpoint_summary.json"
    write_file "$acfs_home/state.json" <<'JSON'
{
  "schema_version": 3,
  "version": "1.0",
  "mode": "vibe",
  "completed_phases": ["user_setup", "filesystem", "finalize"],
  "current_phase": null,
  "failed_phase": null,
  "failed_step": null,
  "last_updated": 1000
}
JSON
    capture_checkpoint_summary "$acfs_home" "$bundle_dir" HOME="$case_dir/home" ACFS_HOME="$acfs_home"
    jq -e '
      .status == "pass" and
      .severity == "healthy" and
      .install_status == "healthy" and
      .next_action == "onboard" and
      .checkpoint.last_completed_phase == "finalize" and
      .checkpoint.next_phase == null
    ' "$summary" >/dev/null || return 1

    pass "checkpoint_summary_covers_fixture_states"
}

test_normal_onboard_path_leaves_useful_milestones() {
    local case_dir acfs_home lessons_dir progress_file output_file
    case_dir="$(new_case_dir normal-onboard)"
    acfs_home="$case_dir/home/.acfs"
    lessons_dir="$case_dir/lessons"
    progress_file="$acfs_home/local_progress.json"
    output_file="$case_dir/onboard.output"
    mkdir -p "$lessons_dir"
    write_file "$lessons_dir/01_intro.md" <<'MD'
# Intro

Welcome to ACFS.
MD

    HOME="$case_dir/home" \
        ACFS_HOME="$acfs_home" \
        ACFS_LESSONS_DIR="$lessons_dir" \
        ACFS_PROGRESS_FILE="$acfs_home/onboard_progress.json" \
        ACFS_LOCAL_PROGRESS_FILE="$progress_file" \
        TERM=dumb \
        bash "$ONBOARD_SH" 1 </dev/null > "$output_file" 2>&1 || return 1

    jq -e '
      .schema_version == 1 and
      ([.events[] | select(.source == "onboard" and .kind == "session_started")] | length) == 1 and
      ([.events[] | select(.source == "onboard" and .kind == "lesson_started" and .details.lesson_number == 1)] | length) == 1
    ' "$progress_file" >/dev/null || return 1

    pass "normal_onboard_path_leaves_useful_milestones"
}

test_normal_helper_path_records_installer_doctor_and_onboard() {
    local case_dir acfs_home progress_file
    case_dir="$(new_case_dir normal-helper)"
    acfs_home="$case_dir/home/.acfs"
    progress_file="$acfs_home/local_progress.json"

    ACFS_LOCAL_PROGRESS_FILE="$progress_file" local_progress_record_installer_phase "cli_tools" "started"
    ACFS_LOCAL_PROGRESS_FILE="$progress_file" local_progress_record_installer_phase "cli_tools" "completed"
    ACFS_LOCAL_PROGRESS_FILE="$progress_file" local_progress_record_doctor_invoked true false false true
    ACFS_LOCAL_PROGRESS_FILE="$progress_file" local_progress_record_onboard_lesson "completed" 0 1

    jq -e '
      (.events | length) == 4 and
      ([.events[] | select(.source == "installer" and .kind == "phase_started" and .details.phase_id == "cli_tools")] | length) == 1 and
      ([.events[] | select(.source == "doctor" and .kind == "doctor_invoked" and .details.deep_mode == true)] | length) == 1 and
      ([.events[] | select(.source == "onboard" and .kind == "lesson_completed" and .details.lesson_number == 1)] | length) == 1
    ' "$progress_file" >/dev/null || return 1

    pass "normal_helper_path_records_installer_doctor_and_onboard"
}

run_test() {
    local name="$1"
    if "$name"; then
        return 0
    fi
    fail "$name"
}

main() {
    command -v jq >/dev/null 2>&1 || {
        echo "jq is required for local progress tests" >&2
        exit 1
    }

    run_test test_empty_progress_summary_is_structured
    run_test test_corrupted_progress_fails_closed
    run_test test_opt_out_suppresses_recording_and_support_marks_skipped
    run_test test_support_summary_redacts_untrusted_progress_fields
    run_test test_checkpoint_summary_covers_fixture_states
    run_test test_normal_onboard_path_leaves_useful_milestones
    run_test test_normal_helper_path_records_installer_doctor_and_onboard

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
