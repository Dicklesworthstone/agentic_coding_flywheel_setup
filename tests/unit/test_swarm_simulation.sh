#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs swarm simulation harness
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWARM_SIM_SH="$REPO_ROOT/scripts/lib/swarm_simulation.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_SWARM_SIM_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-swarm-sim-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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

write_status_fixture() {
    local name="$1"
    local path="$ARTIFACT_DIR/$name.status.json"
    cat > "$path"
    printf '%s\n' "$path"
}

high_capacity_status_fixture() {
    write_status_fixture high_capacity <<'JSON'
{
  "schema_version": 1,
  "status": "pass",
  "host": {"status": "pass", "duration_ms": 1, "warnings": [], "cpu_count": 128, "load_1m": 4, "mem_total_kb": 268435456, "mem_available_kb": 251658240, "disk_available_kb": 419430400},
  "probes": {
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "tmux_session_count": 2, "tmux_window_count": 8, "duration_ms": 1, "warnings": []},
    "agent_mail": {"status": "pass", "available": true, "healthy": true, "duration_ms": 1, "warnings": []},
    "beads": {"status": "pass", "available": true, "ready_count": 9, "in_progress_count": 0, "open_count": 20, "duration_ms": 1, "warnings": []},
    "bv": {"status": "pass", "available": true, "robot_ok": true, "duration_ms": 1, "warnings": []},
    "rch": {"status": "pass", "available": true, "status_json_ok": true, "duration_ms": 1, "warnings": []}
  }
}
JSON
}

low_capacity_status_fixture() {
    write_status_fixture low_capacity <<'JSON'
{
  "schema_version": 1,
  "status": "warn",
  "host": {"status": "warn", "duration_ms": 1, "warnings": ["low memory"], "cpu_count": 2, "load_1m": 1, "mem_total_kb": 4194304, "mem_available_kb": 1048576, "disk_available_kb": 20971520},
  "probes": {
    "ntm": {"status": "warn", "available": true, "robot_status_ok": false, "tmux_available": true, "tmux_session_count": 0, "tmux_window_count": 0, "duration_ms": 1, "warnings": []},
    "agent_mail": {"status": "warn", "available": false, "healthy": null, "duration_ms": 1, "warnings": []},
    "beads": {"status": "warn", "available": false, "ready_count": null, "in_progress_count": null, "open_count": null, "duration_ms": 1, "warnings": []},
    "bv": {"status": "warn", "available": false, "robot_ok": false, "duration_ms": 1, "warnings": []},
    "rch": {"status": "warn", "available": false, "status_json_ok": false, "duration_ms": 1, "warnings": []}
  }
}
JSON
}

run_sim_json() {
    local name="$1"
    local fixture="$2"
    shift 2

    local output_file="$ARTIFACT_DIR/$name.output.json"
    local run_artifacts="$ARTIFACT_DIR/$name-artifacts"
    local status=0

    set +e
    env \
        ACFS_CAPACITY_CPU_COUNT=128 \
        ACFS_CAPACITY_MEM_TOTAL_KB=268435456 \
        ACFS_CAPACITY_DISK_AVAILABLE_KB=419430400 \
        ACFS_CAPACITY_RCH_AVAILABLE=true \
        ACFS_CAPACITY_NTM_AVAILABLE=true \
        bash "$SWARM_SIM_SH" --json --status-file "$fixture" --artifact-dir "$run_artifacts" "$@" > "$output_file"
    status=$?
    set -e

    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    cat "$output_file"
}

test_default_10_25_50_scenarios_pass() {
    local fixture output run_dir
    fixture="$(high_capacity_status_fixture)"
    output="$(run_sim_json default_counts "$fixture")"
    run_dir="$(jq -r '.artifact_dir' <<<"$output")"

    jq -e '
      .status == "pass" and
      .summary.total == 3 and
      (.scenarios | map(.scenario.agent_count) == [10,25,50]) and
      all(.scenarios[]; .status == "pass" and (.checks | length) == 7 and .mock_rehearsal == false)
    ' <<<"$output" >/dev/null || return 1

    [[ -f "$run_dir/scenario_10/launch_plan.json" ]] || return 1
    [[ -f "$run_dir/scenario_25/resource_sample.json" ]] || return 1
    [[ -f "$run_dir/scenario_50/timing.json" ]] || return 1
    jq -e '.simulation_only == true and .not_a_provider_factory_test == true' "$run_dir/summary.json" >/dev/null || return 1

    pass "default_10_25_50_scenarios_pass"
}

test_custom_counts_are_supported() {
    local fixture output
    fixture="$(high_capacity_status_fixture)"
    output="$(run_sim_json custom_counts "$fixture" --counts 05,10)"

    jq -e '
      .status == "pass" and
      .summary.total == 2 and
      (.scenarios | map(.scenario.agent_count) == [5,10])
    ' <<<"$output" >/dev/null || return 1

    pass "custom_counts_are_supported"
}

test_duplicate_counts_exit_2() {
    local fixture output status
    fixture="$(high_capacity_status_fixture)"

    set +e
    output="$(bash "$SWARM_SIM_SH" --json --status-file "$fixture" --artifact-dir "$ARTIFACT_DIR/duplicate-artifacts" --counts 01,1 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/duplicate_counts.output.txt"
    [[ "$status" -eq 2 ]] || return 1
    grep -Fq "duplicate agent count: 1" <<<"$output" || return 1

    pass "duplicate_counts_exit_2"
}

test_low_capacity_fails_large_profile() {
    local fixture output status
    fixture="$(low_capacity_status_fixture)"

    set +e
    output="$(env \
        ACFS_CAPACITY_CPU_COUNT=2 \
        ACFS_CAPACITY_MEM_TOTAL_KB=4194304 \
        ACFS_CAPACITY_DISK_AVAILABLE_KB=20971520 \
        ACFS_CAPACITY_RCH_AVAILABLE=false \
        ACFS_CAPACITY_NTM_AVAILABLE=true \
        bash "$SWARM_SIM_SH" --json --status-file "$fixture" --artifact-dir "$ARTIFACT_DIR/low-artifacts" --counts 50)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/low_capacity.output.json"
    [[ "$status" -eq 2 ]] || return 1
    jq -e '.status == "fail" and .summary.failed == 1 and (.scenarios[0].checks[] | select(.id == "resource_pressure" and .status == "fail"))' <<<"$output" >/dev/null || return 1

    pass "low_capacity_fails_large_profile"
}

test_human_output_declares_simulation_only() {
    local fixture output status
    fixture="$(high_capacity_status_fixture)"

    set +e
    output="$(env \
        ACFS_CAPACITY_CPU_COUNT=128 \
        ACFS_CAPACITY_MEM_TOTAL_KB=268435456 \
        ACFS_CAPACITY_DISK_AVAILABLE_KB=419430400 \
        ACFS_CAPACITY_RCH_AVAILABLE=true \
        ACFS_CAPACITY_NTM_AVAILABLE=true \
        bash "$SWARM_SIM_SH" --status-file "$fixture" --artifact-dir "$ARTIFACT_DIR/human-artifacts")"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/human_output.txt"
    [[ "$status" -eq 0 ]] || return 1
    grep -Fq "ACFS Swarm Simulation" <<<"$output" || return 1
    grep -Fq "Simulation only:" <<<"$output" || return 1
    grep -Fq "50 agents: pass" <<<"$output" || return 1

    pass "human_output_declares_simulation_only"
}

test_mock_rehearsal_small_counts_produces_artifacts() {
    local fixture output run_dir
    fixture="$(high_capacity_status_fixture)"
    output="$(run_sim_json mock_rehearsal "$fixture" --mock-rehearsal --counts 2,3 --mock-duration 1)"
    run_dir="$(jq -r '.artifact_dir' <<<"$output")"

    jq -e '
      .status == "pass" and
      .summary.total == 2 and
      (.scenarios | map(.scenario.agent_count) == [2,3]) and
      all(.scenarios[]; .mock_rehearsal == true and .status == "pass")
    ' <<<"$output" >/dev/null || return 1

    [[ -f "$run_dir/scenario_2/mock_launch.log" ]] || return 1
    [[ -f "$run_dir/scenario_2/mock_status_snapshots.json" ]] || return 1
    [[ -f "$run_dir/scenario_2/mock_resource_samples.json" ]] || return 1
    [[ -f "$run_dir/scenario_2/mock_rehearsal.json" ]] || return 1

    jq -e '
      .enabled == true and
      .requested_workers == 2 and
      .launched_workers == 2 and
      .completed_workers == 2 and
      .failed_workers == 0 and
      .safety.no_model_cli == true and
      .safety.no_agent_mail_mutation == true and
      .safety.no_beads_mutation == true and
      .safety.no_cargo_build == true
    ' "$run_dir/scenario_2/mock_rehearsal.json" >/dev/null || return 1
    jq -e '.samples | length == 3' "$run_dir/scenario_2/mock_resource_samples.json" >/dev/null || return 1
    jq -e '.before.schema_version == 1 and .after.schema_version == 1' "$run_dir/scenario_2/mock_status_snapshots.json" >/dev/null || return 1

    pass "mock_rehearsal_small_counts_produces_artifacts"
}

test_mock_rehearsal_high_counts_require_flag() {
    local fixture output status
    fixture="$(high_capacity_status_fixture)"

    set +e
    output="$(bash "$SWARM_SIM_SH" --json --status-file "$fixture" --artifact-dir "$ARTIFACT_DIR/high-count-blocked" --mock-rehearsal --counts 11 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/high_count_blocked.output.txt"
    [[ "$status" -eq 2 ]] || return 1
    grep -Fq "require --allow-high-counts" <<<"$output" || return 1

    pass "mock_rehearsal_high_counts_require_flag"
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
        echo "jq is required for swarm simulation tests" >&2
        exit 1
    }

    run_test test_default_10_25_50_scenarios_pass
    run_test test_custom_counts_are_supported
    run_test test_duplicate_counts_exit_2
    run_test test_low_capacity_fails_large_profile
    run_test test_human_output_declares_simulation_only
    run_test test_mock_rehearsal_small_counts_produces_artifacts
    run_test test_mock_rehearsal_high_counts_require_flag

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
