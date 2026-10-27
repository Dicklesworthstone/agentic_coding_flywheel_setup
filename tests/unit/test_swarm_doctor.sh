#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs swarm doctor preflight
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWARM_DOCTOR_SH="$REPO_ROOT/scripts/lib/swarm_doctor.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_SWARM_DOCTOR_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-swarm-doctor-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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

write_fixture() {
    local name="$1"
    local path="$ARTIFACT_DIR/$name.json"
    cat > "$path"
    printf '%s\n' "$path"
}

run_doctor_json() {
    local name="$1"
    local fixture="$2"
    local output status

    set +e
    output="$(bash "$SWARM_DOCTOR_SH" --json --status-file "$fixture" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output.json"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

test_pass_fixture_exits_zero() {
    local fixture output status
    fixture="$(write_fixture pass_fixture <<'JSON'
{
  "schema_version": 1,
  "status": "pass",
  "host": {"status": "pass", "cpu_count": 64, "load_1m": 8, "mem_available_kb": 134217728, "disk_available_kb": 209715200, "swap_total_kb": 8388608, "swap_free_kb": 8388608, "memory_psi_some_avg60": 0, "memory_psi_full_avg60": 0, "warnings": []},
  "probes": {
    "agent_mail": {"status": "pass", "available": true, "healthy": true, "warnings": []},
    "beads": {"status": "pass", "available": true, "ready_count": 3, "in_progress_count": 0, "open_count": 7, "warnings": []},
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": {"status": "pass", "available": true, "status_json_ok": true, "warnings": []},
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "tmux_session_count": 2, "tmux_window_count": 8, "warnings": []}
  }
}
JSON
)"
    output="$(run_doctor_json pass_fixture "$fixture")"
    status="$(cat "$ARTIFACT_DIR/pass_fixture.exit")"

    [[ "$status" -eq 0 ]] || return 1
    jq -e '
      .status == "pass" and
      .summary.failed == 0 and
      (.checks | length) == 8 and
      .stale_work.status == "pass" and
      .stale_work.summary.total_candidates == 0
    ' <<<"$output" >/dev/null || return 1

    pass "pass_fixture_exits_zero"
}

run_pressure_case() {
    local name="$1" filter="$2" expected="$3"
    local fixture="$ARTIFACT_DIR/$name.json" output status expected_exit
    case "$expected" in
        pass) expected_exit=0 ;;
        warn) expected_exit=1 ;;
        fail) expected_exit=2 ;;
        *) return 1 ;;
    esac
    jq "$filter" "$ARTIFACT_DIR/pass_fixture.json" > "$fixture" || return 1
    output="$(run_doctor_json "$name" "$fixture")"
    status="$(cat "$ARTIFACT_DIR/$name.exit")"
    [[ "$status" -eq "$expected_exit" ]] || {
        fail "$name" "expected exit $expected_exit, got $status"
        return 1
    }
    jq -e --arg expected "$expected" --argjson exit_code "$expected_exit" '
      .status == $expected and .exit_code == $exit_code and
      any(.checks[]; .id == "resource_pressure" and .status == $expected)
    ' <<<"$output" >/dev/null || return 1
    pass "$name"
}

test_memory_pressure_thresholds() {
    run_pressure_case no_swap '
      .host.swap_total_kb = 0 | .host.swap_free_kb = 0' pass || return 1
    jq -e 'any(.checks[]; .id == "resource_pressure" and
      any(.details[]; contains("No swap is configured")))' \
      "$ARTIFACT_DIR/no_swap.output.json" >/dev/null || return 1
    run_pressure_case swap_below_threshold '
      .host.swap_total_kb = 10000 | .host.swap_free_kb = 1001' pass || return 1
    run_pressure_case swap_at_threshold '
      .host.swap_total_kb = 10000 | .host.swap_free_kb = 1000' warn || return 1
    run_pressure_case swap_exhausted '.host.swap_free_kb = 0' warn || return 1
    run_pressure_case psi_below_threshold '
      .host.memory_psi_some_avg60 = 2 | .host.memory_psi_full_avg60 = 0.99' pass || return 1
    run_pressure_case psi_at_warning '
      .host.memory_psi_some_avg60 = 2 | .host.memory_psi_full_avg60 = 1' warn || return 1
    run_pressure_case psi_below_failure '
      .host.memory_psi_some_avg60 = 12 | .host.memory_psi_full_avg60 = 9.99' warn || return 1
    run_pressure_case psi_at_failure '
      .host.memory_psi_some_avg60 = 12 | .host.memory_psi_full_avg60 = 10' fail || return 1
    run_pressure_case psi_fully_stalled '
      .host.memory_psi_some_avg60 = 100 | .host.memory_psi_full_avg60 = 100' fail || return 1
    run_pressure_case severe_psi_with_missing_swap '
      .host.swap_total_kb = null | .host.swap_free_kb = null |
      .host.memory_psi_some_avg60 = 12 | .host.memory_psi_full_avg60 = 10' fail || return 1
    run_pressure_case severe_psi_with_missing_some '
      .host.memory_psi_some_avg60 = null | .host.memory_psi_full_avg60 = 10' fail || return 1
}

test_missing_or_invalid_pressure_never_passes() {
    run_pressure_case legacy_snapshot '
      del(.host.swap_total_kb, .host.swap_free_kb,
          .host.memory_psi_some_avg60, .host.memory_psi_full_avg60)' warn || return 1
    run_pressure_case unavailable_swap '
      .host.swap_total_kb = null | .host.swap_free_kb = null' warn || return 1
    run_pressure_case unavailable_psi '
      .host.memory_psi_some_avg60 = null | .host.memory_psi_full_avg60 = null' warn || return 1
    run_pressure_case partial_swap '.host.swap_free_kb = null' warn || return 1
    run_pressure_case partial_psi '.host.memory_psi_full_avg60 = null' warn || return 1
    run_pressure_case impossible_swap '.host.swap_free_kb = 8388609' fail || return 1
    run_pressure_case negative_swap '.host.swap_total_kb = -1' fail || return 1
    run_pressure_case fractional_swap '.host.swap_free_kb = 0.5' fail || return 1
    run_pressure_case excessive_swap '.host.swap_total_kb = 9007199254740992' fail || return 1
    run_pressure_case string_swap '.host.swap_total_kb = "8388608"' fail || return 1
    run_pressure_case impossible_psi '.host.memory_psi_full_avg60 = 1' fail || return 1
    run_pressure_case excessive_psi '.host.memory_psi_some_avg60 = 101' fail || return 1
    run_pressure_case negative_psi '.host.memory_psi_full_avg60 = -1' fail || return 1
    run_pressure_case string_psi '.host.memory_psi_some_avg60 = "0"' fail || return 1
    run_pressure_case boolean_psi '.host.memory_psi_some_avg60 = true' fail || return 1
}

test_missing_required_tools_fail() {
    local fixture output status
    fixture="$(write_fixture missing_tools <<'JSON'
{
  "schema_version": 1,
  "status": "warn",
  "host": {"status": "pass", "cpu_count": 8, "load_1m": 1, "mem_available_kb": 33554432, "disk_available_kb": 104857600, "warnings": []},
  "probes": {
    "agent_mail": {"status": "warn", "available": false, "healthy": null, "warnings": ["Agent Mail CLI not found in PATH"]},
    "beads": {"status": "warn", "available": false, "ready_count": null, "in_progress_count": null, "open_count": null, "warnings": ["br not found in PATH"]},
    "bv": {"status": "warn", "available": false, "robot_ok": false, "warnings": ["bv not found in PATH"]},
    "rch": {"status": "warn", "available": false, "status_json_ok": false, "warnings": ["rch not found in PATH"]},
    "ntm": {"status": "warn", "available": false, "robot_status_ok": false, "tmux_available": false, "tmux_session_count": null, "tmux_window_count": null, "warnings": ["ntm not found in PATH"]}
  }
}
JSON
)"
    output="$(run_doctor_json missing_tools "$fixture")"
    status="$(cat "$ARTIFACT_DIR/missing_tools.exit")"

    [[ "$status" -eq 2 ]] || return 1
    jq -e '
      .status == "fail" and
      .summary.failed >= 5 and
      (.next_commands[] | select(. == "bv --robot-next")) and
      (.next_commands[] | select(. == "rch status"))
    ' <<<"$output" >/dev/null || return 1

    pass "missing_required_tools_fail"
}

test_partial_state_warns() {
    local fixture output status
    fixture="$(write_fixture partial_state <<'JSON'
{
  "schema_version": 1,
  "status": "warn",
  "host": {"status": "pass", "cpu_count": 16, "load_1m": 4, "mem_available_kb": 6291456, "disk_available_kb": 62914560, "warnings": []},
  "probes": {
    "agent_mail": {"status": "pass", "available": true, "healthy": true, "warnings": []},
    "beads": {"status": "pass", "available": true, "ready_count": 4, "in_progress_count": 2, "open_count": 11, "warnings": []},
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": {"status": "pass", "available": true, "status_json_ok": true, "warnings": []},
    "ntm": {"status": "warn", "available": true, "robot_status_ok": false, "tmux_available": true, "tmux_session_count": 1, "tmux_window_count": 4, "warnings": ["ntm --robot-status failed or timed out"]}
  }
}
JSON
)"
    output="$(run_doctor_json partial_state "$fixture")"
    status="$(cat "$ARTIFACT_DIR/partial_state.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "warn" and
      (.checks[] | select(.id == "ntm" and .status == "warn")) and
      (.checks[] | select(.id == "active_work" and .status == "warn")) and
      (.next_commands[] | select(. == "br list --status in_progress --json"))
    ' <<<"$output" >/dev/null || return 1

    pass "partial_state_warns"
}

test_stale_beads_warn_with_manual_commands() {
    local fixture output status
    fixture="$(write_fixture stale_beads <<'JSON'
{
  "schema_version": 1,
  "status": "pass",
  "host": {"status": "pass", "cpu_count": 32, "load_1m": 2, "mem_available_kb": 67108864, "disk_available_kb": 157286400, "warnings": []},
  "probes": {
    "agent_mail": {"status": "pass", "available": true, "healthy": true, "warnings": []},
    "beads": {
      "status": "pass",
      "available": true,
      "ready_count": 4,
      "in_progress_count": 1,
      "open_count": 11,
      "warnings": [],
      "in_progress_items": [
        {"id": "bd-old1", "title": "Old in-progress work", "assignee": "BlueLake", "updated_at": "2026-01-01T00:00:00Z"}
      ]
    },
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": {"status": "pass", "available": true, "status_json_ok": true, "warnings": []},
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "tmux_session_count": 1, "tmux_window_count": 3, "warnings": []}
  }
}
JSON
)"
    output="$(run_doctor_json stale_beads "$fixture")"
    status="$(cat "$ARTIFACT_DIR/stale_beads.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "warn" and
      .stale_work.summary.beads == 1 and
      .stale_work.beads[0].id == "bd-old1" and
      .stale_work.beads[0].verify_command == "br show bd-old1 --json" and
      .stale_work.beads[0].if_abandoned_command == "br update bd-old1 --status open" and
      (.checks[] | select(.id == "stale_work" and .status == "warn"))
    ' <<<"$output" >/dev/null || return 1

    pass "stale_beads_warn_with_manual_commands"
}

test_stale_reservations_warn_without_releasing() {
    local fixture output status
    fixture="$(write_fixture stale_reservations <<'JSON'
{
  "schema_version": 1,
  "status": "pass",
  "host": {"status": "pass", "cpu_count": 32, "load_1m": 2, "mem_available_kb": 67108864, "disk_available_kb": 157286400, "warnings": []},
  "probes": {
    "agent_mail": {
      "status": "pass",
      "available": true,
      "healthy": true,
      "warnings": [],
      "file_reservations": [
        {"id": 101, "path_pattern": "scripts/lib/*.sh", "agent_name": "RedStone", "created_ts": "2026-01-01T00:00:00Z", "last_activity_ts": "2026-01-01T00:00:00Z", "expires_ts": "2026-01-01T02:00:00Z"}
      ]
    },
    "beads": {"status": "pass", "available": true, "ready_count": 4, "in_progress_count": 0, "open_count": 11, "warnings": [], "in_progress_items": []},
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": {"status": "pass", "available": true, "status_json_ok": true, "warnings": []},
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "tmux_session_count": 1, "tmux_window_count": 3, "warnings": []}
  }
}
JSON
)"
    output="$(run_doctor_json stale_reservations "$fixture")"
    status="$(cat "$ARTIFACT_DIR/stale_reservations.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "warn" and
      .stale_work.summary.reservations == 1 and
      .stale_work.reservations[0].id == "101" and
      .stale_work.reservations[0].holder == "RedStone" and
      .stale_work.reservations[0].expired == true and
      (.stale_work.reservations[0].if_abandoned_command | contains("release_file_reservations")) and
      (.checks[] | select(.id == "stale_work" and .status == "warn"))
    ' <<<"$output" >/dev/null || return 1

    pass "stale_reservations_warn_without_releasing"
}

test_malformed_reservation_timestamp_warns() {
    local fixture output status
    fixture="$(write_fixture malformed_reservation <<'JSON'
{
  "schema_version": 1,
  "status": "pass",
  "host": {"status": "pass", "cpu_count": 32, "load_1m": 2, "mem_available_kb": 67108864, "disk_available_kb": 157286400, "warnings": []},
  "probes": {
    "agent_mail": {
      "status": "pass",
      "available": true,
      "healthy": true,
      "warnings": [],
      "file_reservations": [
        {"id": 202, "path_pattern": "README.md", "agent_name": "GreenField", "created_ts": "not-a-date"}
      ]
    },
    "beads": {"status": "pass", "available": true, "ready_count": 4, "in_progress_count": 0, "open_count": 11, "warnings": [], "in_progress_items": []},
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": {"status": "pass", "available": true, "status_json_ok": true, "warnings": []},
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "tmux_session_count": 1, "tmux_window_count": 3, "warnings": []}
  }
}
JSON
)"
    output="$(run_doctor_json malformed_reservation "$fixture")"
    status="$(cat "$ARTIFACT_DIR/malformed_reservation.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "warn" and
      .stale_work.summary.total_candidates == 0 and
      .stale_work.summary.malformed_inputs == 1 and
      .stale_work.malformed_inputs[0].type == "reservation" and
      (.checks[] | select(.id == "stale_work" and .status == "warn"))
    ' <<<"$output" >/dev/null || return 1

    pass "malformed_reservation_timestamp_warns"
}

test_human_output_marks_stale_candidates_advisory() {
    local fixture output status
    fixture="$(write_fixture human_stale <<'JSON'
{
  "schema_version": 1,
  "status": "pass",
  "host": {"status": "pass", "cpu_count": 32, "load_1m": 2, "mem_available_kb": 67108864, "disk_available_kb": 157286400, "warnings": []},
  "probes": {
    "agent_mail": {"status": "pass", "available": true, "healthy": true, "warnings": []},
    "beads": {
      "status": "pass",
      "available": true,
      "ready_count": 4,
      "in_progress_count": 1,
      "open_count": 11,
      "warnings": [],
      "in_progress_items": [
        {"id": "bd-old2", "title": "Old in-progress work", "assignee": "BlueLake", "updated_at": "2026-01-01T00:00:00Z"}
      ]
    },
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": {"status": "pass", "available": true, "status_json_ok": true, "warnings": []},
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "tmux_session_count": 1, "tmux_window_count": 3, "warnings": []}
  }
}
JSON
)"

    set +e
    output="$(bash "$SWARM_DOCTOR_SH" --status-file "$fixture" 2>&1)"
    status=$?
    set -e
    printf '%s\n' "$output" > "$ARTIFACT_DIR/human_stale.output.txt"

    [[ "$status" -eq 1 ]] || return 1
    grep -Fq "Stale candidates (advisory only; verify before changing anything):" <<<"$output" || return 1
    grep -Fq "verify: br show bd-old2 --json" <<<"$output" || return 1
    grep -Fq "if abandoned: br update bd-old2 --status open" <<<"$output" || return 1

    pass "human_output_marks_stale_candidates_advisory"
}

test_human_output_lists_next_commands() {
    local fixture output status
    fixture="$(write_fixture human_fail <<'JSON'
{
  "schema_version": 1,
  "status": "warn",
  "host": {"status": "pass", "cpu_count": 8, "load_1m": 1, "mem_available_kb": 33554432, "disk_available_kb": 104857600, "warnings": []},
  "probes": {
    "agent_mail": {"status": "warn", "available": false, "healthy": null, "warnings": []},
    "beads": {"status": "pass", "available": true, "ready_count": 1, "in_progress_count": 0, "open_count": 2, "warnings": []},
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": {"status": "pass", "available": true, "status_json_ok": true, "warnings": []},
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "warnings": []}
  }
}
JSON
)"

    set +e
    output="$(bash "$SWARM_DOCTOR_SH" --status-file "$fixture" 2>&1)"
    status=$?
    set -e
    printf '%s\n' "$output" > "$ARTIFACT_DIR/human_fail.output.txt"

    [[ "$status" -eq 2 ]] || return 1
    grep -Fq "ACFS Swarm Doctor" <<<"$output" || return 1
    grep -Fq "Next commands:" <<<"$output" || return 1
    grep -Fq "mcp-agent-mail doctor check --json" <<<"$output" || return 1

    pass "human_output_lists_next_commands"
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
        echo "jq is required for swarm doctor tests" >&2
        exit 1
    }

    run_test test_pass_fixture_exits_zero
    run_test test_memory_pressure_thresholds
    run_test test_missing_or_invalid_pressure_never_passes
    run_test test_missing_required_tools_fail
    run_test test_partial_state_warns
    run_test test_stale_beads_warn_with_manual_commands
    run_test test_stale_reservations_warn_without_releasing
    run_test test_malformed_reservation_timestamp_warns
    run_test test_human_output_marks_stale_candidates_advisory
    run_test test_human_output_lists_next_commands

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
