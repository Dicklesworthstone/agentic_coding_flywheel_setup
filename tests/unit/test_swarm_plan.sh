#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs swarm plan advisor
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWARM_PLAN_SH="$REPO_ROOT/scripts/lib/swarm_plan.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_SWARM_PLAN_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-swarm-plan-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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
    local name="$1"
    local path="$ARTIFACT_DIR/$name-capacity.sh"
    cat > "$path"
    chmod +x "$path"
    printf '%s\n' "$path"
}

run_plan_json() {
    local name="$1"
    local fixture="$2"
    shift 2
    local output status capacity_script

    capacity_script="${ACFS_TEST_CAPACITY_SCRIPT:?missing test capacity script}"
    set +e
    output="$(ACFS_SWARM_CAPACITY_SCRIPT="$capacity_script" bash "$SWARM_PLAN_SH" --json --status-file "$fixture" "$@" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output.json"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

healthy_status_fixture() {
    write_fixture healthy_status <<'JSON'
{
  "schema_version": 1,
  "status": "pass",
  "host": {"status": "pass", "cpu_count": 64, "load_1m": 8, "mem_available_kb": 134217728, "disk_available_kb": 314572800, "warnings": []},
  "probes": {
    "agent_mail": {"status": "pass", "available": true, "healthy": true, "warnings": []},
    "beads": {"status": "pass", "available": true, "ready_count": 12, "in_progress_count": 0, "open_count": 20, "warnings": []},
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": {"status": "pass", "available": true, "status_json_ok": true, "queue_json_ok": true, "queue_depth": 0, "active_build_count": 0, "workers_total": 8, "workers_healthy": 8, "workers_busy": 0, "workers_offline": 0, "slots_total": 32, "slots_available": 24, "pressure_warning_count": 0, "stale_worker_count": 0, "warnings": []},
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "tmux_session_count": 2, "tmux_window_count": 8, "warnings": []}
  }
}
JSON
}

busy_rch_status_fixture() {
    write_fixture busy_rch_status <<'JSON'
{
  "schema_version": 1,
  "status": "warn",
  "host": {"status": "pass", "cpu_count": 64, "load_1m": 12, "mem_available_kb": 134217728, "disk_available_kb": 314572800, "warnings": []},
  "probes": {
    "agent_mail": {"status": "pass", "available": true, "healthy": true, "warnings": []},
    "beads": {"status": "pass", "available": true, "ready_count": 12, "in_progress_count": 1, "open_count": 20, "warnings": []},
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": {"status": "warn", "available": true, "status_json_ok": true, "queue_json_ok": true, "queue_depth": 7, "active_build_count": 6, "workers_total": 8, "workers_healthy": 8, "workers_busy": 5, "workers_offline": 0, "slots_total": 32, "slots_available": 4, "pressure_warning_count": 2, "stale_worker_count": 0, "warnings": ["rch reports 2 worker(s) with elevated pressure"]},
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "tmux_session_count": 3, "tmux_window_count": 10, "warnings": []}
  }
}
JSON
}

missing_agent_mail_status_fixture() {
    write_fixture missing_agent_mail_status <<'JSON'
{
  "schema_version": 1,
  "status": "warn",
  "host": {"status": "pass", "cpu_count": 32, "load_1m": 4, "mem_available_kb": 67108864, "disk_available_kb": 157286400, "warnings": []},
  "probes": {
    "agent_mail": {"status": "warn", "available": false, "healthy": null, "warnings": ["Agent Mail CLI not found in PATH"]},
    "beads": {"status": "pass", "available": true, "ready_count": 5, "in_progress_count": 0, "open_count": 12, "warnings": []},
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": {"status": "pass", "available": true, "status_json_ok": true, "queue_json_ok": true, "queue_depth": 0, "active_build_count": 0, "workers_total": 8, "workers_healthy": 8, "workers_busy": 0, "workers_offline": 0, "slots_total": 32, "slots_available": 20, "pressure_warning_count": 0, "stale_worker_count": 0, "warnings": []},
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "tmux_session_count": 1, "tmux_window_count": 4, "warnings": []}
  }
}
JSON
}

high_load_status_fixture() {
    write_fixture high_load_status <<'JSON'
{
  "schema_version": 1,
  "status": "warn",
  "host": {"status": "warn", "cpu_count": 16, "load_1m": 24, "mem_available_kb": 67108864, "disk_available_kb": 157286400, "warnings": ["host load is high"]},
  "probes": {
    "agent_mail": {"status": "pass", "available": true, "healthy": true, "warnings": []},
    "beads": {"status": "pass", "available": true, "ready_count": 5, "in_progress_count": 0, "open_count": 12, "warnings": []},
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": {"status": "pass", "available": true, "status_json_ok": true, "queue_json_ok": true, "queue_depth": 0, "active_build_count": 0, "workers_total": 8, "workers_healthy": 8, "workers_busy": 0, "workers_offline": 0, "slots_total": 32, "slots_available": 20, "pressure_warning_count": 0, "stale_worker_count": 0, "warnings": []},
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "tmux_session_count": 1, "tmux_window_count": 4, "warnings": []}
  }
}
JSON
}

low_memory_status_fixture() {
    write_fixture low_memory_status <<'JSON'
{
  "schema_version": 1,
  "status": "warn",
  "host": {"status": "warn", "cpu_count": 32, "load_1m": 4, "mem_available_kb": 2097152, "disk_available_kb": 157286400, "warnings": ["available memory is low"]},
  "probes": {
    "agent_mail": {"status": "pass", "available": true, "healthy": true, "warnings": []},
    "beads": {"status": "pass", "available": true, "ready_count": 5, "in_progress_count": 0, "open_count": 12, "warnings": []},
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": {"status": "pass", "available": true, "status_json_ok": true, "queue_json_ok": true, "queue_depth": 0, "active_build_count": 0, "workers_total": 8, "workers_healthy": 8, "workers_busy": 0, "workers_offline": 0, "slots_total": 32, "slots_available": 20, "pressure_warning_count": 0, "stale_worker_count": 0, "warnings": []},
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "tmux_session_count": 1, "tmux_window_count": 4, "warnings": []}
  }
}
JSON
}

stale_work_status_fixture() {
    write_fixture stale_work_status <<'JSON'
{
  "schema_version": 1,
  "status": "warn",
  "host": {"status": "pass", "cpu_count": 32, "load_1m": 4, "mem_available_kb": 67108864, "disk_available_kb": 157286400, "warnings": []},
  "probes": {
    "agent_mail": {"status": "pass", "available": true, "healthy": true, "warnings": []},
    "beads": {"status": "pass", "available": true, "ready_count": 5, "in_progress_count": 2, "stale_in_progress_count": 1, "open_count": 12, "warnings": []},
    "bv": {"status": "pass", "available": true, "robot_ok": true, "warnings": []},
    "rch": {"status": "pass", "available": true, "status_json_ok": true, "queue_json_ok": true, "queue_depth": 0, "active_build_count": 0, "workers_total": 8, "workers_healthy": 8, "workers_busy": 0, "workers_offline": 0, "slots_total": 32, "slots_available": 20, "pressure_warning_count": 0, "stale_worker_count": 0, "warnings": []},
    "ntm": {"status": "pass", "available": true, "robot_status_ok": true, "tmux_available": true, "tmux_session_count": 1, "tmux_window_count": 4, "warnings": []}
  }
}
JSON
}

capacity_script_with_safe_count() {
    local safe="$1"
    local recommended="$2"
    local status="$3"
    local reason="$4"

    write_capacity_script capacity <<JSON
#!/usr/bin/env bash
set -euo pipefail
cat <<'CAPACITY'
{
  "schema_version": 1,
  "status": "$status",
  "capacity": {
    "recommended_agent_count": $recommended,
    "safe_agent_count": $safe,
    "max_agent_count": $safe
  },
  "profile_check": {
    "requested_profile": "fixture",
    "requested_agents": null,
    "status": "$status",
    "reason": "$reason"
  },
  "recommendations": ["Start at the recommended tier, then increase only after status/doctor checks stay clean."]
}
CAPACITY
JSON
}

test_healthy_ten_agents_passes_with_launch_command() {
    local fixture output status
    fixture="$(healthy_status_fixture)"
    ACFS_TEST_CAPACITY_SCRIPT="$(capacity_script_with_safe_count 64 44 pass "Requested count is within the recommended tier")"
    export ACFS_TEST_CAPACITY_SCRIPT

    output="$(run_plan_json healthy_ten "$fixture" --agents 10 --profile balanced --workload standard)"
    status="$(cat "$ARTIFACT_DIR/healthy_ten.exit")"

    [[ "$status" -eq 0 ]] || return 1
    jq -e '
      .status == "pass" and
      .recommendation == "launch" and
      .launch_profile.recommended == true and
      .launch_profile.agent_count == 10 and
      (.launch_profile.command | startswith("ntm spawn myproject")) and
      .quiesce_advisory.recommendation == "proceed" and
      .quiesce_advisory.recommended_agents == 10 and
      .safety.read_only == true and
      .safety.launches_agents == false
    ' <<<"$output" >/dev/null || return 1

    pass "healthy_ten_agents_passes_with_launch_command"
}

test_busy_rch_warns_and_scales_down() {
    local fixture output status
    fixture="$(busy_rch_status_fixture)"
    ACFS_TEST_CAPACITY_SCRIPT="$(capacity_script_with_safe_count 64 44 pass "Requested count is within the recommended tier")"
    export ACFS_TEST_CAPACITY_SCRIPT

    output="$(run_plan_json busy_rch "$fixture" --agents 25 --profile codex-heavy --workload standard)"
    status="$(cat "$ARTIFACT_DIR/busy_rch.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "warn" and
      .recommendation == "defer_or_reduce" and
      .recommended_agents == 4 and
      .quiesce_advisory.recommendation == "scale_down" and
      .quiesce_advisory.recommended_agents == 4 and
      .launch_profile.agent_count == 4 and
      (.checks[] | select(.id == "rch_pressure" and .status == "warn")) and
      (.checks[] | select(.id == "active_work" and .status == "warn")) and
      (.next_commands[] | select(. == "rch workers probe --all"))
    ' <<<"$output" >/dev/null || return 1

    pass "busy_rch_warns_and_scales_down"
}

test_low_capacity_blocks_large_profile() {
    local fixture output status
    fixture="$(healthy_status_fixture)"
    ACFS_TEST_CAPACITY_SCRIPT="$(capacity_script_with_safe_count 8 6 fail "Requested count exceeds the safe maximum")"
    export ACFS_TEST_CAPACITY_SCRIPT

    output="$(run_plan_json low_capacity "$fixture" --agents 50 --profile balanced --workload heavy)"
    status="$(cat "$ARTIFACT_DIR/low_capacity.exit")"

    [[ "$status" -eq 2 ]] || return 1
    jq -e '
      .status == "fail" and
      .recommendation == "block" and
      .quiesce_advisory.recommendation == "wait" and
      .launch_profile.recommended == false and
      .launch_profile.command == null and
      (.checks[] | select(.id == "host_capacity" and .status == "fail")) and
      (.examples[] | select(.requested_agents == 50 and .status == "fail"))
    ' <<<"$output" >/dev/null || return 1

    pass "low_capacity_blocks_large_profile"
}

test_missing_agent_mail_blocks_launch_command() {
    local fixture output status
    fixture="$(missing_agent_mail_status_fixture)"
    ACFS_TEST_CAPACITY_SCRIPT="$(capacity_script_with_safe_count 32 24 pass "Requested count is within the recommended tier")"
    export ACFS_TEST_CAPACITY_SCRIPT

    output="$(run_plan_json missing_agent_mail "$fixture" --agents 10 --profile review-heavy --workload light)"
    status="$(cat "$ARTIFACT_DIR/missing_agent_mail.exit")"

    [[ "$status" -eq 2 ]] || return 1
    jq -e '
      .status == "fail" and
      .quiesce_advisory.recommendation == "wait" and
      .launch_profile.command == null and
      (.checks[] | select(.id == "coordination_health" and .status == "fail")) and
      (.next_commands[] | select(. == "mcp-agent-mail doctor check --json")) and
      ([.examples[] | select(.status == "fail" and .recommendation == "block")] | length) == 3
    ' <<<"$output" >/dev/null || return 1

    pass "missing_agent_mail_blocks_launch_command"
}

test_high_load_quiesce_waits() {
    local fixture output status
    fixture="$(high_load_status_fixture)"
    ACFS_TEST_CAPACITY_SCRIPT="$(capacity_script_with_safe_count 32 24 pass "Requested count is within the recommended tier")"
    export ACFS_TEST_CAPACITY_SCRIPT

    output="$(run_plan_json high_load "$fixture" --agents 10 --profile balanced --workload standard)"
    status="$(cat "$ARTIFACT_DIR/high_load.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "warn" and
      .quiesce_advisory.recommendation == "wait" and
      (.checks[] | select(.id == "host_pressure" and .status == "warn")) and
      any(.quiesce_advisory.reasons[]; contains("Host load"))
    ' <<<"$output" >/dev/null || return 1

    pass "high_load_quiesce_waits"
}

test_low_memory_quiesce_waits() {
    local fixture output status
    fixture="$(low_memory_status_fixture)"
    ACFS_TEST_CAPACITY_SCRIPT="$(capacity_script_with_safe_count 32 24 pass "Requested count is within the recommended tier")"
    export ACFS_TEST_CAPACITY_SCRIPT

    output="$(run_plan_json low_memory "$fixture" --agents 10 --profile balanced --workload standard)"
    status="$(cat "$ARTIFACT_DIR/low_memory.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "warn" and
      .quiesce_advisory.recommendation == "wait" and
      (.checks[] | select(.id == "host_pressure" and .status == "warn")) and
      any(.quiesce_advisory.reasons[]; contains("Available memory"))
    ' <<<"$output" >/dev/null || return 1

    pass "low_memory_quiesce_waits"
}

test_stale_work_quiesce_waits() {
    local fixture output status
    fixture="$(stale_work_status_fixture)"
    ACFS_TEST_CAPACITY_SCRIPT="$(capacity_script_with_safe_count 32 24 pass "Requested count is within the recommended tier")"
    export ACFS_TEST_CAPACITY_SCRIPT

    output="$(run_plan_json stale_work "$fixture" --agents 10 --profile balanced --workload standard)"
    status="$(cat "$ARTIFACT_DIR/stale_work.exit")"

    [[ "$status" -eq 1 ]] || return 1
    jq -e '
      .status == "warn" and
      .quiesce_advisory.recommendation == "wait" and
      (.checks[] | select(.id == "active_work" and .status == "warn" and (.details[] | contains("stale_work_count=1")))) and
      (.next_commands[] | select(. == "acfs swarm doctor --stale-hours 12"))
    ' <<<"$output" >/dev/null || return 1

    pass "stale_work_quiesce_waits"
}

test_status_file_replay_ignores_live_status_script() {
    local fixture output status bad_status_script
    fixture="$(healthy_status_fixture)"
    ACFS_TEST_CAPACITY_SCRIPT="$(capacity_script_with_safe_count 64 44 pass "Requested count is within the recommended tier")"
    export ACFS_TEST_CAPACITY_SCRIPT
    bad_status_script="$ARTIFACT_DIR/bad-swarm-status.sh"
    printf '#!/usr/bin/env bash\nexit 99\n' > "$bad_status_script"
    chmod +x "$bad_status_script"

    set +e
    output="$(ACFS_SWARM_STATUS_SCRIPT="$bad_status_script" ACFS_SWARM_CAPACITY_SCRIPT="$ACFS_TEST_CAPACITY_SCRIPT" bash "$SWARM_PLAN_SH" --json --status-file "$fixture" --agents 10 --profile docs-heavy --workload standard 2>&1)"
    status=$?
    set -e
    printf '%s\n' "$output" > "$ARTIFACT_DIR/status_file_replay.output.json"

    [[ "$status" -eq 0 ]] || return 1
    jq -e '.status == "pass" and .inputs.swarm_status_file != null' <<<"$output" >/dev/null || return 1

    pass "status_file_replay_ignores_live_status_script"
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
        echo "jq is required for swarm plan tests" >&2
        exit 1
    }

    run_test test_healthy_ten_agents_passes_with_launch_command
    run_test test_busy_rch_warns_and_scales_down
    run_test test_low_capacity_blocks_large_profile
    run_test test_missing_agent_mail_blocks_launch_command
    run_test test_high_load_quiesce_waits
    run_test test_low_memory_quiesce_waits
    run_test test_stale_work_quiesce_waits
    run_test test_status_file_replay_ignores_live_status_script

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
