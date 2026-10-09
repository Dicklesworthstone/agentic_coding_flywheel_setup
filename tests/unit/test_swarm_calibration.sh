#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs swarm capacity calibration
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWARM_CAL_SH="$REPO_ROOT/scripts/lib/swarm_calibration.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_SWARM_CAL_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-swarm-cal-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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
    return 0
}

write_scenario() {
    local run_dir="$1"
    local count="$2"
    local observed="$3"
    local capacity_status="$4"
    local recommended="$5"
    local safe="$6"
    local timing_ms="$7"
    local mock_enabled="${8:-false}"
    local scenario_dir="$run_dir/scenario_$count"

    mkdir -p "$scenario_dir"

    cat > "$scenario_dir/summary.json" <<JSON
{
  "schema_version": 1,
  "scenario": {"agent_count": $count, "workload": "standard", "artifact_dir": "$scenario_dir"},
  "mock_rehearsal": $mock_enabled,
  "status": "$observed",
  "checks": [],
  "artifacts": {
    "capacity": "$scenario_dir/capacity.json",
    "resource_sample": "$scenario_dir/resource_sample.json",
    "timing": "$scenario_dir/timing.json",
    "mock_rehearsal": "$scenario_dir/mock_rehearsal.json",
    "summary": "$scenario_dir/summary.json"
  }
}
JSON

    cat > "$scenario_dir/capacity.json" <<JSON
{
  "schema_version": 1,
  "status": "pass",
  "assumptions": {"workload": "standard"},
  "capacity": {
    "recommended_agent_count": $recommended,
    "safe_agent_count": $safe,
    "max_agent_count": $safe
  },
  "profile_check": {
    "requested_agents": $count,
    "status": "$capacity_status",
    "reason": "fixture capacity profile"
  }
}
JSON

    cat > "$scenario_dir/resource_sample.json" <<JSON
{
  "schema_version": 1,
  "agent_count": $count,
  "capacity": {
    "recommended_agent_count": $recommended,
    "safe_agent_count": $safe,
    "profile_status": "$capacity_status"
  },
  "pressure": {"status": "$observed", "reason": "fixture pressure"}
}
JSON

    cat > "$scenario_dir/timing.json" <<JSON
{"schema_version": 1, "start_ms": 1000, "end_ms": $((1000 + timing_ms)), "duration_ms": $timing_ms}
JSON

    cat > "$scenario_dir/mock_rehearsal.json" <<JSON
{
  "schema_version": 1,
  "enabled": $mock_enabled,
  "requested_workers": $count,
  "completed_workers": $count,
  "failed_workers": 0,
  "status": "$observed",
  "timing": {"duration_ms": $timing_ms},
  "safety": {
    "no_model_cli": true,
    "no_agent_mail_mutation": true,
    "no_beads_mutation": true,
    "no_cargo_build": true
  }
}
JSON

    cat > "$scenario_dir/telemetry.json" <<JSON
{
  "schema_version": 1,
  "status": "pass",
  "host": {"cpu_count": 64, "load_1m": 3, "mem_total_kb": 268435456, "mem_available_kb": 251658240},
  "probes": {
    "rch": {
      "status": "pass",
      "available": true,
      "queue_depth": 0,
      "active_build_count": 0,
      "slots_total": 8,
      "slots_available": 8,
      "workers_healthy": 8,
      "duration_ms": 12
    }
  }
}
JSON
}

write_rch_timing_fixture() {
    local path="$ARTIFACT_DIR/rch-timing.json"
    cat > "$path" <<'JSON'
{
  "queue_depth": 2,
  "active_build_count": 1,
  "slots_total": 8,
  "slots_available": 6,
  "workers_total": 8,
  "workers_healthy": 7,
  "duration_ms": 55,
  "builds": [
    {"duration_ms": 1000},
    {"duration_ms": 3000}
  ]
}
JSON
    printf '%s\n' "$path"
}

run_cal_json() {
    local name="$1"
    shift
    local output status

    set +e
    output="$(bash "$SWARM_CAL_SH" --json "$@" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output.json"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

test_fast_host_reports_conservative_with_rch_timing() {
    local run_dir rch_file output
    run_dir="$ARTIFACT_DIR/fast-host"
    mkdir -p "$run_dir"
    write_scenario "$run_dir" 10 pass pass 44 64 10 false
    write_scenario "$run_dir" 25 pass pass 44 64 15 false
    write_scenario "$run_dir" 50 pass warn 44 64 20 true
    rch_file="$(write_rch_timing_fixture)"

    output="$(run_cal_json fast --artifact-dir "$run_dir" --rch-file "$rch_file")"
    [[ "$(cat "$ARTIFACT_DIR/fast.exit")" -eq 0 ]] || return 1

    jq -e '
      .status == "pass" and
      .calibration.posture == "conservative" and
      .summary.valid_scenarios == 3 and
      .summary.max_passing_agents == 50 and
      .summary.rehearsal_scenarios == 1 and
      .rch.status == "present" and
      .rch.queue_depth == 2 and
      .rch.build_duration_ms == 2000 and
      (.scenarios[] | select(.agent_count == 50 and .classification == "model_conservative"))
    ' <<< "$output" >/dev/null || return 1

    pass "fast_host_reports_conservative_with_rch_timing"
}

test_constrained_host_warns_when_recommended_tier_fails() {
    local run_dir output
    run_dir="$ARTIFACT_DIR/constrained-host"
    mkdir -p "$run_dir"
    write_scenario "$run_dir" 10 fail pass 10 12 25 true

    output="$(run_cal_json constrained --artifact-dir "$run_dir")"
    [[ "$(cat "$ARTIFACT_DIR/constrained.exit")" -eq 1 ]] || return 1

    jq -e '
      .status == "warn" and
      .calibration.posture == "too_aggressive" and
      .summary.valid_scenarios == 1 and
      .scenarios[0].classification == "model_too_aggressive" and
      (.next_commands | index("acfs capacity --json --recommend-ntm"))
    ' <<< "$output" >/dev/null || return 1

    pass "constrained_host_warns_when_recommended_tier_fails"
}

test_missing_rch_data_is_optional() {
    local run_dir output
    run_dir="$ARTIFACT_DIR/missing-rch"
    mkdir -p "$run_dir"
    write_scenario "$run_dir" 10 pass pass 10 16 8 false

    output="$(run_cal_json missing_rch --artifact-dir "$run_dir")"
    [[ "$(cat "$ARTIFACT_DIR/missing_rch.exit")" -eq 0 ]] || return 1

    jq -e '
      .status == "pass" and
      .calibration.posture == "aligned" and
      .rch.status == "missing" and
      .rch.provided == false and
      (.rch.warnings[0] | test("No --rch-file provided"))
    ' <<< "$output" >/dev/null || return 1

    pass "missing_rch_data_is_optional"
}

test_malformed_artifact_files_emit_warnings() {
    local run_dir bad_dir output
    run_dir="$ARTIFACT_DIR/malformed"
    bad_dir="$run_dir/scenario_25"
    mkdir -p "$run_dir" "$bad_dir"
    write_scenario "$run_dir" 10 pass pass 10 16 8 false
    write_scenario "$run_dir" 25 pass pass 25 32 10 false
    printf '{not valid json\n' > "$bad_dir/capacity.json"

    output="$(run_cal_json malformed --artifact-dir "$run_dir")"
    [[ "$(cat "$ARTIFACT_DIR/malformed.exit")" -eq 1 ]] || return 1

    jq -e '
      .status == "warn" and
      .summary.valid_scenarios == 1 and
      .summary.malformed_files == 1 and
      any(.warnings[]; contains("capacity.json is malformed JSON")) and
      (.scenarios[] | select(.agent_count == 25 and .valid == false and .classification == "invalid_artifact"))
    ' <<< "$output" >/dev/null || return 1

    pass "malformed_artifact_files_emit_warnings"
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
        echo "jq is required for swarm calibration tests" >&2
        exit 1
    }

    run_test test_fast_host_reports_conservative_with_rch_timing
    run_test test_constrained_host_warns_when_recommended_tier_fails
    run_test test_missing_rch_data_is_optional
    run_test test_malformed_artifact_files_emit_warnings

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
