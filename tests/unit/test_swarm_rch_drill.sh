#!/usr/bin/env bash
# ============================================================
# RCH outage and local-fallback disaster drills for swarm planning
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWARM_PLAN_SH="$REPO_ROOT/scripts/lib/swarm_plan.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_SWARM_RCH_DRILL_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-swarm-rch-drill-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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

write_capacity_script() {
    local path="$ARTIFACT_DIR/capacity.sh"
    cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<'JSON'
{
  "schema_version": 1,
  "status": "pass",
  "capacity": {
    "recommended_agent_count": 24,
    "safe_agent_count": 32,
    "max_agent_count": 32
  },
  "profile_check": {
    "requested_profile": "fixture",
    "requested_agents": null,
    "status": "pass",
    "reason": "fixture capacity"
  },
  "recommendations": ["Use RCH for CPU-heavy checks before adding more agents."]
}
JSON
EOF
    chmod +x "$path"
    printf '%s\n' "$path"
}

status_fixture_with_rch() {
    local name="$1"
    local rch_json="$2"

    write_fixture "$name" <<JSON
{
  "schema_version": 1,
  "status": "warn",
  "host": {"status": "pass", "cpu_count": 64, "load_1m": 8, "mem_available_kb": 134217728, "disk_available_kb": 314572800, "warnings": []},
  "probes": {
    "agent_mail": {"status": "pass", "available": true, "healthy": true, "warnings": []},
    "beads": {"status": "pass", "available": true, "ready_count": 12, "in_progress_count": 0, "open_count": 20, "warnings": []},
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": $rch_json,
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "tmux_session_count": 1, "tmux_window_count": 4, "warnings": []}
  }
}
JSON
}

run_plan_json() {
    local name="$1"
    local fixture="$2"
    shift 2
    local output status capacity_script

    capacity_script="$(write_capacity_script)"
    set +e
    output="$(ACFS_SWARM_CAPACITY_SCRIPT="$capacity_script" bash "$SWARM_PLAN_SH" --json --status-file "$fixture" "$@" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output.json"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

run_plan_human() {
    local name="$1"
    local fixture="$2"
    shift 2
    local output status capacity_script

    capacity_script="$(write_capacity_script)"
    set +e
    output="$(ACFS_SWARM_CAPACITY_SCRIPT="$capacity_script" bash "$SWARM_PLAN_SH" --status-file "$fixture" "$@" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output.txt"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

assert_no_local_cargo_recommendations() {
    local output="$1"

    jq -e '
      (.rch_policy.examples | all(startswith("rch exec --"))) and
      ([.next_commands[]?, .warnings[]?, (.recommended_action // ""), (.quiesce_advisory.action // ""), (.launch_profile.command // "")]
        | all(test("(^|[[:space:]])cargo[[:space:]]+(test|build|clippy)") | not))
    ' <<<"$output" >/dev/null
}

assert_remediation_commands() {
    local output="$1"

    jq -e '
      (.next_commands[] | select(. == "rch status")) and
      (.next_commands[] | select(. == "rch queue --json")) and
      (.next_commands[] | select(. == "rch workers probe --all"))
    ' <<<"$output" >/dev/null
}

test_rch_unavailable_fails_closed() {
    local fixture output status
    fixture="$(status_fixture_with_rch rch_unavailable '{"status":"fail","available":false,"status_json_ok":false,"queue_json_ok":false,"queue_depth":0,"active_build_count":0,"workers_total":0,"workers_healthy":0,"workers_busy":0,"workers_offline":0,"slots_total":0,"slots_available":0,"pressure_warning_count":0,"stale_worker_count":0,"warnings":["rch command not found"]}')"
    output="$(run_plan_json rch_unavailable "$fixture" --agents 10 --profile balanced --workload standard)"
    status="$(cat "$ARTIFACT_DIR/rch_unavailable.exit")"

    [[ "$status" -eq 2 ]] || return 1
    jq -e '
      .status == "fail" and
      .quiesce_advisory.recommendation == "wait" and
      (.checks[] | select(.id == "rch_pressure" and .status == "fail" and (.summary | contains("unavailable"))))
    ' <<<"$output" >/dev/null || return 1
    assert_remediation_commands "$output" || return 1
    assert_no_local_cargo_recommendations "$output" || return 1

    pass "rch_unavailable_fails_closed"
}

test_busy_rch_scales_down_with_remediation() {
    local fixture output status
    fixture="$(status_fixture_with_rch busy_rch '{"status":"warn","available":true,"status_json_ok":true,"queue_json_ok":true,"queue_depth":6,"active_build_count":4,"workers_total":8,"workers_healthy":8,"workers_busy":5,"workers_offline":0,"slots_total":32,"slots_available":3,"pressure_warning_count":1,"stale_worker_count":0,"warnings":["rch workers are busy"]}')"
    output="$(run_plan_json busy_rch "$fixture" --agents 25 --profile balanced --workload standard)"
    status="$(cat "$ARTIFACT_DIR/busy_rch.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "warn" and
      .recommended_agents == 3 and
      .quiesce_advisory.recommendation == "scale_down" and
      .quiesce_advisory.recommended_agents == 3
    ' <<<"$output" >/dev/null || return 1
    assert_remediation_commands "$output" || return 1
    assert_no_local_cargo_recommendations "$output" || return 1

    pass "busy_rch_scales_down_with_remediation"
}

test_malformed_rch_status_fails_closed() {
    local fixture output status
    fixture="$(status_fixture_with_rch malformed_rch '{"status":"fail","available":true,"status_json_ok":false,"queue_json_ok":false,"queue_depth":0,"active_build_count":0,"workers_total":8,"workers_healthy":8,"workers_busy":0,"workers_offline":0,"slots_total":32,"slots_available":20,"pressure_warning_count":0,"stale_worker_count":0,"warnings":["rch status returned malformed JSON"]}')"
    output="$(run_plan_json malformed_rch "$fixture" --agents 10 --profile balanced --workload standard)"
    status="$(cat "$ARTIFACT_DIR/malformed_rch.exit")"

    [[ "$status" -eq 2 ]] || return 1
    jq -e '
      .status == "fail" and
      .quiesce_advisory.recommendation == "wait" and
      (.checks[] | select(.id == "rch_pressure" and .status == "fail" and (.summary | contains("status JSON failed"))))
    ' <<<"$output" >/dev/null || return 1
    assert_remediation_commands "$output" || return 1
    assert_no_local_cargo_recommendations "$output" || return 1

    pass "malformed_rch_status_fails_closed"
}

test_no_rch_workers_fails_closed() {
    local fixture output status
    fixture="$(status_fixture_with_rch no_workers '{"status":"fail","available":true,"status_json_ok":true,"queue_json_ok":true,"queue_depth":0,"active_build_count":0,"workers_total":0,"workers_healthy":0,"workers_busy":0,"workers_offline":0,"slots_total":0,"slots_available":0,"pressure_warning_count":0,"stale_worker_count":0,"warnings":["no RCH workers registered"]}')"
    output="$(run_plan_json no_workers "$fixture" --agents 10 --profile balanced --workload standard)"
    status="$(cat "$ARTIFACT_DIR/no_workers.exit")"

    [[ "$status" -eq 2 ]] || return 1
    jq -e '
      .status == "fail" and
      .quiesce_advisory.recommendation == "wait" and
      (.checks[] | select(.id == "rch_pressure" and .status == "fail" and (.summary | contains("no workers"))))
    ' <<<"$output" >/dev/null || return 1
    assert_remediation_commands "$output" || return 1
    assert_no_local_cargo_recommendations "$output" || return 1

    pass "no_rch_workers_fails_closed"
}

test_human_output_has_no_local_cargo_recommendation() {
    local fixture output status line trimmed
    fixture="$(status_fixture_with_rch human_busy_rch '{"status":"warn","available":true,"status_json_ok":true,"queue_json_ok":true,"queue_depth":2,"active_build_count":1,"workers_total":8,"workers_healthy":8,"workers_busy":3,"workers_offline":0,"slots_total":32,"slots_available":4,"pressure_warning_count":1,"stale_worker_count":0,"warnings":["rch workers are busy"]}')"
    output="$(run_plan_human human_busy_rch "$fixture" --agents 25 --profile balanced --workload standard)"
    status="$(cat "$ARTIFACT_DIR/human_busy_rch.exit")"

    [[ "$status" -eq 1 ]] || return 1
    [[ "$output" == *"Quiesce: scale_down"* ]] || return 1
    [[ "$output" == *"rch workers probe --all"* ]] || return 1
    while IFS= read -r line; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ "$trimmed" != cargo\ * ]] || return 1
    done <<<"$output"

    pass "human_output_has_no_local_cargo_recommendation"
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
        echo "jq is required for RCH drill tests" >&2
        exit 1
    }

    run_test test_rch_unavailable_fails_closed
    run_test test_busy_rch_scales_down_with_remediation
    run_test test_malformed_rch_status_fails_closed
    run_test test_no_rch_workers_fails_closed
    run_test test_human_output_has_no_local_cargo_recommendation

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
