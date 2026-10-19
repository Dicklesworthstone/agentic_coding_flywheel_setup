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
    if [[ -n "${2:-}" ]]; then
        echo "  Reason: $2"
    fi
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
  "resume_hint": "bash /tmp/acfs-rescue-install.sh --resume --yes"
}
JSON

    output="$(run_rescue_json failed_phase --acfs-home "$acfs_home")"
    status="$(cat "$ARTIFACT_DIR/failed_phase.exit")"

    [[ "$status" -eq 2 ]] || return 1
    jq -e '
      .status == "fail" and
      .severity == "blocked" and
      .install_status == "failed" and
      .next_command == "bash /tmp/acfs-rescue-install.sh --resume --yes" and
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

test_invalid_checkpoint_shapes_never_look_healthy() {
    local case_name="" value="" home="" output="" status=""
    while IFS='|' read -r case_name value; do
        home="$ARTIFACT_DIR/invalid-$case_name/.acfs"
        mkdir -p "$home"
        printf '%s\n' "$value" > "$home/state.json"
        output="$(run_rescue_json "invalid_$case_name" --acfs-home "$home")"
        status="$(cat "$ARTIFACT_DIR/invalid_$case_name.exit")"
        if [[ "$status" == 2 ]] && jq -e '.status == "fail" and .sources.state.status == "malformed" and .next_command == "acfs support-bundle"' <<< "$output" >/dev/null; then
            pass "invalid checkpoint $case_name cannot become healthy"
        else fail "invalid checkpoint $case_name cannot become healthy"; fi
    done <<'CASES'
phase_string|{"schema_version":3,"completed_phases":"finalize"}
schema_wrap|{"schema_version":"18446744073709551619","completed_phases":["finalize"]}
schema_fraction|{"schema_version":3.5,"completed_phases":["finalize"]}
schema_boolean|{"schema_version":true,"completed_phases":["finalize"]}
current_boolean|{"schema_version":3,"completed_phases":["finalize"],"current_phase":false}
phase_object|{"schema_version":3,"completed_phases":[{"phase":"finalize"}]}
array_root|[{"schema_version":3,"completed_phases":["finalize"]}]
two_documents|{"schema_version":3,"completed_phases":["finalize"]} {"schema_version":3,"completed_phases":[]}
CASES
}

test_timing_options_are_literal_bounded_decimals() {
    local home="$ARTIFACT_DIR/timing-input/.acfs" value="" output="" status="" index=0
    write_json "$home/state.json" <<'JSON'
{"schema_version":3,"completed_phases":[],"current_phase":"languages","last_updated":1000}
JSON
    cp "$home/state.json" "$ARTIFACT_DIR/timing-state.before"
    for value in 'RESCUE_EVIDENCE[$(printf unsafe_fixture_executed >&2)0]' '1+1' '-1' '9223372036854775808' ''; do
        index=$((index + 1))
        output="$(run_rescue_json "bad_timing_$index" --acfs-home "$home" --now-epoch 5000 --stale-seconds "$value")"
        status="$(cat "$ARTIFACT_DIR/bad_timing_$index.exit")"
        if [[ "$status" == 2 ]] && [[ "$output" != *unsafe_fixture_executed* ]] && cmp -s "$home/state.json" "$ARTIFACT_DIR/timing-state.before"; then
            pass "invalid timing input $index is rejected without evaluation or mutation"
        else fail "invalid timing input $index is rejected without evaluation or mutation"; fi
    done
    output="$(run_rescue_json decimal_timing --acfs-home "$home" --now-epoch 0005000 --stale-seconds 00060)"
    status="$(cat "$ARTIFACT_DIR/decimal_timing.exit")"
    if [[ "$status" == 1 ]] && jq -e '.severity == "stale_checkpoint" and .checkpoint.age_seconds == 4000' <<< "$output" >/dev/null; then
        pass "leading-zero timing values are decimal seconds"
    else fail "leading-zero timing values are decimal seconds"; fi
}

test_transcript_only_max_bytes_is_explained_in_checkpoint_mode() {
    local home="$ARTIFACT_DIR/max-bytes-checkpoint/.acfs" log="$ARTIFACT_DIR/max-bytes-transcript.log"
    local args_text="" output="" status="" index=0
    local -a args=()
    mkdir -p "$home"
    # GH #455: the help lists --max-bytes, but only transcript mode reads it.
    for args_text in '--json --max-bytes 1024 --stale-seconds 600' '--max-bytes=1024 --json' '--max-bytes 1024'; do
        index=$((index + 1))
        read -r -a args <<< "$args_text"
        set +e
        output="$(bash "$RESCUE_SH" --acfs-home "$home" "${args[@]}" 2>&1)"
        status=$?
        set -e
        if [[ "$status" == 2 && "$output" == *"--max-bytes only applies with --log-file"* && "$output" != *"unknown rescue option"* ]]; then
            pass "checkpoint-mode --max-bytes form $index names the transcript-only option"
        else fail "checkpoint-mode --max-bytes form $index names the transcript-only option" "status=$status output=$output"; fi
    done
    printf '%s\n' '=== ACFS Install Log ===' 'No space left on device' > "$log"
    set +e
    output="$(bash "$RESCUE_SH" --json --max-bytes 1024 --log-file "$log" 2>/dev/null)"
    status=$?
    set -e
    if [[ "$status" == 1 ]] && jq -e '.schema == "acfs.installer-transcript.v1" and .primary_cause == "disk"' <<< "$output" >/dev/null; then
        pass "--max-bytes before --log-file still reaches transcript mode"
    else fail "--max-bytes before --log-file still reaches transcript mode" "status=$status output=$output"; fi
    output="$(bash "$RESCUE_SH" --help)"
    if [[ "$output" == *"acfs rescue --log-file PATH [--max-bytes N] [--json]"* && "$output" == *"Transcript mode"* ]]; then
        pass "rescue help separates transcript-only options"
    else fail "rescue help separates transcript-only options"; fi
}

test_invalid_doctor_counters_do_not_clear_warnings() {
    local home="$ARTIFACT_DIR/invalid-doctor/.acfs" value="" index=0 output="" status=""
    write_json "$home/state.json" <<'JSON'
{"schema_version":3,"completed_phases":["finalize"]}
JSON
    for value in '"18446744073709551616"' '-1' '0.5' '"1+1"' 'true'; do
        index=$((index + 1))
        printf '{"summary":{"fail":%s,"warn":0}}\n' "$value" > "$ARTIFACT_DIR/invalid-doctor/doctor.json"
        output="$(run_rescue_json "bad_doctor_$index" --acfs-home "$home" --doctor-file "$ARTIFACT_DIR/invalid-doctor/doctor.json")"
        status="$(cat "$ARTIFACT_DIR/bad_doctor_$index.exit")"
        if [[ "$status" == 1 ]] && jq -e '.status == "warn" and .sources.doctor.status == "malformed" and .next_command == "acfs doctor --json"' <<< "$output" >/dev/null; then
            pass "invalid doctor counter $index remains unknown evidence"
        else fail "invalid doctor counter $index remains unknown evidence"; fi
    done
}

test_option_like_search_paths_remain_paths() {
    local probe="$ARTIFACT_DIR/path-probe" output=""
    mkdir -p "$probe/-delete" "$probe/-exec"
    output="$(bash -c '
        source "$1"
        cd "$2" || exit 2
        find() { printf "%s\n" "$1"; }
        rescue_latest_support_path -delete
        rescue_latest_summary_file -exec
    ' _ "$RESCUE_SH" "$probe")"
    if [[ "$output" == "$probe/-delete"$'\n'"$probe/-exec" ]]; then
        pass "search helpers prefix relative option-like directories before find"
    else fail "search helpers prefix relative option-like directories before find" "$output"; fi
    mkdir -p "$probe/-true/support-only" "$probe/support-outside"
    output="$(bash -c 'source "$1"; cd "$2" || exit 2; rescue_latest_support_path -true' _ "$RESCUE_SH" "$probe")"
    if [[ "$output" == "$probe/-true/support-only" ]]; then
        pass "native find stays inside the option-like directory"
    else fail "native find stays inside the option-like directory" "$output"; fi
}

test_option_like_json_filename_is_literal() {
    local probe="$ARTIFACT_DIR/json-filename" output="" actual=0
    mkdir -p "$probe/.acfs"
    printf '%s\n' '{"schema_version":3,"completed_phases":["finalize"]}' > "$probe/-r"
    output="$(bash -c 'cd "$2" || exit 2; bash "$1" --json --state-file -r --acfs-home "$2/.acfs"' _ "$RESCUE_SH" "$probe" </dev/null)" || actual=$?
    if [[ "$actual" == 0 ]] && jq -e '.status == "pass" and .sources.state.status == "valid"' <<< "$output" >/dev/null; then
        pass "native jq reads an option-like state filename as a file"
    else fail "native jq reads an option-like state filename as a file"; fi
    output="$(bash -c 'source "$1"; cd "$2" || exit 2; rescue_file_mtime_epoch -r' _ "$RESCUE_SH" "$probe")" || output=""
    if [[ "$output" =~ ^[0-9]+$ ]]; then
        pass "native stat reads an option-like state filename as a file"
    else fail "native stat reads an option-like state filename as a file"; fi
}

test_integer_json_notation_and_failure_precedence() {
    local home="$ARTIFACT_DIR/integer-notation/.acfs" output=""
    write_json "$home/state.json" <<'JSON'
{"schema_version":99.0,"completed_phases":["finalize"]}
JSON
    output="$(run_rescue_json future_notation --acfs-home "$home")"
    if [[ "$(cat "$ARTIFACT_DIR/future_notation.exit")" == 2 ]] && jq -e '.severity == "future_state" and .checkpoint.state_schema_version == 99' <<< "$output" >/dev/null; then
        pass "integer-valued future JSON schema cannot skip the version guard"
    else fail "integer-valued future JSON schema cannot skip the version guard"; fi
    write_json "$home/state.json" <<'JSON'
{"schema_version":3,"completed_phases":["finalize"]}
JSON
    write_json "$ARTIFACT_DIR/integer-notation/doctor.json" <<'JSON'
{"summary":{"fail":1e1,"warn":0}}
JSON
    output="$(run_rescue_json doctor_notation --acfs-home "$home" --doctor-file "$ARTIFACT_DIR/integer-notation/doctor.json")"
    if [[ "$(cat "$ARTIFACT_DIR/doctor_notation.exit")" == 2 ]] && jq -e '.severity == "doctor_failed"' <<< "$output" >/dev/null; then
        pass "integer-valued doctor counters are normalized before comparison"
    else fail "integer-valued doctor counters are normalized before comparison"; fi
    write_json "$home/state.json" <<'JSON'
{"schema_version":3,"completed_phases":[],"failed_phase":"agents"}
JSON
    printf '{bad-report\n' > "$ARTIFACT_DIR/integer-notation/doctor.json"
    output="$(run_rescue_json failed_precedence --acfs-home "$home" --doctor-file "$ARTIFACT_DIR/integer-notation/doctor.json")"
    if [[ "$(cat "$ARTIFACT_DIR/failed_precedence.exit")" == 2 ]] && jq -e '.severity == "blocked" and .install_status == "failed" and .sources.doctor.status == "malformed"' <<< "$output" >/dev/null; then
        pass "invalid doctor evidence does not replace a persisted installer failure"
    else fail "invalid doctor evidence does not replace a persisted installer failure"; fi
}

test_doctor_decision_uses_validated_snapshot() {
    local probe="$ARTIFACT_DIR/snapshot-probe" output=""
    mkdir -p "$probe"
    printf '%s\n' '{"summary":{"fail":2,"warn":0}}' > "$probe/doctor.json"
    cat > "$probe/jq" <<'SCRIPT'
#!/usr/bin/env bash
# Fault injection changes the producer file when field extraction begins;
# parsing still delegates to the actual system jq with unchanged arguments.
if [[ "${1:-}" == -r && "${2:-}" == '.status'* ]]; then
    printf '%s\n' '{"summary":{"fail":"18446744073709551616","warn":0}}' > "$ACFS_SNAPSHOT_DOCTOR_FILE"
fi
exec /usr/bin/jq "$@"
SCRIPT
    chmod +x "$probe/jq"
    output="$(ACFS_SNAPSHOT_DOCTOR_FILE="$probe/doctor.json" bash -c '
        source "$1"
        probe="$2"
        rescue_jq() { printf "%s/jq\n" "$probe"; }
        RESCUE_DOCTOR_FILE="$probe/doctor.json"
        RESCUE_INSTALL_STATUS=healthy; RESCUE_STATUS=pass
        rescue_analyze_doctor
        printf "%s|%s\n" "$RESCUE_STATUS" "$RESCUE_SEVERITY"
    ' _ "$RESCUE_SH" "$probe")"
    if [[ "$output" == 'fail|doctor_failed' ]] && grep -Fq '18446744073709551616' "$probe/doctor.json"; then
        pass "doctor decision keeps validated failure counters when producer file changes"
    else fail "doctor decision keeps validated failure counters when producer file changes" "$output"; fi
}

test_active_phase_beats_previous_finalize() {
    local home="$ARTIFACT_DIR/active-after-finalize/.acfs" output=""
    write_json "$home/state.json" <<'JSON'
{"schema_version":3,"completed_phases":["user_setup","finalize"],"current_phase":{"id":"agents"},"last_updated":1000}
JSON
    output="$(run_rescue_json active_after_finalize --acfs-home "$home" --now-epoch 5000 --stale-seconds 60)"
    if [[ "$(cat "$ARTIFACT_DIR/active_after_finalize.exit")" == 1 ]] &&
        jq -e '.status == "warn" and .install_status == "running" and .severity == "stale_checkpoint" and
            .checkpoint.current_phase == "agents" and .next_command == "acfs continue --status"' <<< "$output" >/dev/null; then
        pass "active checkpoint takes precedence over finalize from a previous run"
    else fail "active checkpoint takes precedence over finalize from a previous run"; fi
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
    run_test test_invalid_checkpoint_shapes_never_look_healthy
    run_test test_timing_options_are_literal_bounded_decimals
    run_test test_transcript_only_max_bytes_is_explained_in_checkpoint_mode
    run_test test_invalid_doctor_counters_do_not_clear_warnings
    run_test test_option_like_search_paths_remain_paths
    run_test test_option_like_json_filename_is_literal
    run_test test_integer_json_notation_and_failure_precedence
    run_test test_doctor_decision_uses_validated_snapshot
    run_test test_active_phase_beats_previous_finalize

    echo
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo "Artifacts: $ARTIFACT_DIR"

    [[ "$TESTS_FAILED" -eq 0 ]]
}

main "$@"
