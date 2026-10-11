#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs info swarm operations summary
# ============================================================
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INFO_SH="$REPO_ROOT/scripts/lib/info.sh"
DASHBOARD_SH="$REPO_ROOT/scripts/lib/dashboard.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_INFO_SWARM_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-info-swarm-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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

write_swarm_status_script() {
    local name="$1"
    local body="$2"
    local path="$ARTIFACT_DIR/$name.sh"
    printf '%s\n' "$body" > "$path"
    chmod 755 "$path"
    printf '%s\n' "$path"
}

pass_status_script() {
    write_swarm_status_script pass_status '#!/usr/bin/env bash
cat <<'"'"'JSON'"'"'
{
  "schema_version": 1,
  "status": "pass",
  "warnings": [],
  "host": {"cpu_count": 64, "mem_available_kb": 134217728, "disk_available_kb": 209715200},
  "probes": {
    "ntm": {"status": "pass", "tmux_session_count": 3, "tmux_window_count": 12},
    "agent_mail": {"status": "pass", "available": true, "healthy": true},
    "beads": {"status": "pass", "ready_count": 9, "in_progress_count": 0},
    "bv": {"status": "pass", "robot_ok": true},
    "rch": {"status": "pass", "status_json_ok": true}
  }
}
JSON'
}

warn_status_script() {
    write_swarm_status_script warn_status '#!/usr/bin/env bash
cat <<'"'"'JSON'"'"'
{
  "schema_version": 1,
  "status": "warn",
  "warnings": ["ntm uncertain", "active beads"],
  "host": {"cpu_count": 16, "mem_available_kb": 4194304, "disk_available_kb": 31457280},
  "probes": {
    "ntm": {"status": "warn", "tmux_session_count": 1, "tmux_window_count": 4},
    "agent_mail": {"status": "pass", "available": true, "healthy": true},
    "beads": {"status": "pass", "ready_count": 4, "in_progress_count": 2},
    "bv": {"status": "pass", "robot_ok": true},
    "rch": {"status": "warn", "status_json_ok": false}
  }
}
JSON'
}

partial_resource_status_script() {
    write_swarm_status_script partial_resource_status '#!/usr/bin/env bash
cat <<'"'"'JSON'"'"'
{
  "schema_version": 1,
  "status": "pass",
  "warnings": [],
  "host": {"cpu_count": 8, "disk_available_kb": 10485760},
  "probes": {
    "ntm": {"status": "pass", "tmux_session_count": 0, "tmux_window_count": 0},
    "agent_mail": {"status": "pass", "available": true, "healthy": true},
    "beads": {"status": "pass", "ready_count": 1, "in_progress_count": 0},
    "rch": {"status": "pass", "status_json_ok": true}
  }
}
JSON'
}

pressure_status_script() {
    write_swarm_status_script pressure_status '#!/usr/bin/env bash
cat <<'"'"'JSON'"'"'
{
  "schema_version": 1,
  "status": "warn",
  "warnings": ["low memory headroom", "rch queue delayed"],
  "host": {"cpu_count": 8, "mem_available_kb": 1048576, "disk_available_kb": 20971520},
  "probes": {
    "ntm": {"status": "pass", "tmux_session_count": 2, "tmux_window_count": 6},
    "agent_mail": {"status": "pass", "available": true, "healthy": true},
    "beads": {"status": "pass", "ready_count": 2, "in_progress_count": 0},
    "bv": {"status": "pass", "robot_ok": true},
    "rch": {"status": "warn", "status_json_ok": true}
  }
}
JSON'
}

run_info() {
    local status_script="$1"
    shift

    env \
        HOME="$ARTIFACT_DIR/home" \
        TARGET_HOME="$ARTIFACT_DIR/home" \
        ACFS_HOME="$ARTIFACT_DIR/home/.acfs" \
        ACFS_INFO_SWARM_STATUS_SCRIPT="$status_script" \
        ACFS_INFO_SWARM_STATUS_DEADLINE=1 \
        ACFS_INFO_SWARM_STATUS_TIMEOUT=1 \
        bash "$INFO_SH" "$@"
}

test_default_info_does_not_invoke_live_collector() {
    local marker="$ARTIFACT_DIR/default-collector-called" status_script output
    status_script="$ARTIFACT_DIR/default_probe.sh"
    cat > "$status_script" <<'EOF'
#!/usr/bin/env bash
printf called > "$ACFS_INFO_PROBE_MARKER"
printf '%s\n' '{"schema_version":1,"status":"pass","warnings":[],"probes":{},"host":{}}'
EOF
    chmod +x "$status_script"
    output="$(ACFS_INFO_PROBE_MARKER="$marker" run_info "$status_script" --json)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/default-passive.json"
    [[ ! -e "$marker" ]] || return 1
    jq -e '.swarm.status == "unknown" and .swarm.ready_beads == "unknown" and
      (.swarm.next_action | contains("acfs swarm status"))' <<<"$output" >/dev/null || return 1
    pass "default_info_does_not_invoke_live_collector"
}

test_ip_discovery_does_not_create_cache() {
    local fixture_home="$ARTIFACT_DIR/ip-discovery-home" bin_dir="$ARTIFACT_DIR/ip-discovery-bin" output
    mkdir -p "$fixture_home" "$bin_dir"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "203.0.113.23\\n"' > "$bin_dir/hostname"
    chmod +x "$bin_dir/hostname"
    output="$(
        export TARGET_HOME="$fixture_home" ACFS_HOME="$fixture_home/.acfs"
        # shellcheck source=../../scripts/lib/info.sh
        source "$INFO_SH"
        info_get_data_home() { printf '%s\n' "$fixture_home/.acfs"; }
        info_system_binary_path() {
            if [[ "$1" == hostname ]]; then
                printf '%s\n' "$bin_dir/hostname"
            else
                command -v "$1"
            fi
        }
        info_get_ip
    )"
    [[ "$output" == "203.0.113.23" ]] || return 1
    [[ ! -e "$fixture_home/.acfs/cache/ip_address" ]] || return 1
    pass "ip_discovery_does_not_create_cache"
}

test_live_collector_preserves_callers_errexit() {
    local status_script
    status_script="$(pass_status_script)"
    (
        export TARGET_HOME="$ARTIFACT_DIR/home" ACFS_HOME="$ARTIFACT_DIR/home/.acfs"
        export ACFS_INFO_SWARM_STATUS_SCRIPT="$status_script"
        # shellcheck source=../../scripts/lib/info.sh
        source "$INFO_SH"
        set +e
        info_collect_swarm_status_json > "$ARTIFACT_DIR/errexit-disabled.json"
        [[ "$-" != *e* ]] || exit 1
        set -e
        info_collect_swarm_status_json > "$ARTIFACT_DIR/errexit-enabled.json"
        [[ "$-" == *e* ]] || exit 1
    ) || return 1
    pass "live_collector_preserves_callers_errexit"
}

test_sourced_info_resets_live_flag_for_each_call() {
    local marker="$ARTIFACT_DIR/sourced-collector-calls" status_script="$ARTIFACT_DIR/sourced-probe.sh"
    cat > "$status_script" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' called >> "$ACFS_INFO_PROBE_MARKER"
printf '%s\n' '{"schema_version":1,"status":"pass","warnings":[],"probes":{},"host":{}}'
EOF
    chmod +x "$status_script"
    (
        export TARGET_HOME="$ARTIFACT_DIR/home" ACFS_HOME="$ARTIFACT_DIR/home/.acfs"
        export ACFS_INFO_SWARM_STATUS_SCRIPT="$status_script" ACFS_INFO_PROBE_MARKER="$marker"
        # shellcheck source=../../scripts/lib/info.sh
        source "$INFO_SH"
        info_main --json --live > "$ARTIFACT_DIR/sourced-live.json"
        info_main --json > "$ARTIFACT_DIR/sourced-passive.json"
    ) || return 1
    [[ "$(wc -l < "$marker")" -eq 1 ]] || return 1
    jq -e '.swarm.status == "unknown" and .swarm.warning_count == 0' "$ARTIFACT_DIR/sourced-passive.json" >/dev/null || return 1
    pass "sourced_info_resets_live_flag_for_each_call"
}

test_terminal_includes_swarm_panel() {
    local status_script output
    status_script="$(pass_status_script)"
    output="$(run_info "$status_script" --live)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/terminal.txt"

    grep -Fq "Swarm Operations" <<<"$output" || return 1
    grep -Fq "ready=9 in_progress=0" <<<"$output" || return 1
    grep -Fq "Safe to launch or scale a swarm" <<<"$output" || return 1

    pass "terminal_includes_swarm_panel"
}

test_json_includes_swarm_summary() {
    local status_script output
    status_script="$(warn_status_script)"
    output="$(run_info "$status_script" --json --live)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/info.json"

    jq -e '
      .swarm.status == "warn" and
      .swarm.in_progress_beads == "2" and
      .swarm.rch == "warn" and
      .swarm.warning_count == 2 and
      .swarm.next_action == "Review active Beads before launching more agents"
    ' <<<"$output" >/dev/null || return 1

    pass "json_includes_swarm_summary"
}

test_html_includes_dashboard_panel() {
    local status_script output
    status_script="$(pass_status_script)"
    output="$(run_info "$status_script" --html --live)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/info.html"

    grep -Fq "<h2>Swarm Operations</h2>" <<<"$output" || return 1
    grep -Fq "Agent Mail=pass RCH=pass" <<<"$output" || return 1
    grep -Fq "128 GiB mem, 200 GiB disk" <<<"$output" || return 1

    pass "html_includes_dashboard_panel"
}

test_partial_resource_data_is_labeled() {
    local status_script output
    status_script="$(partial_resource_status_script)"
    output="$(run_info "$status_script" --json --live)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/partial-resources.json"

    jq -e '
      .swarm.resources == "unknown mem, 10 GiB disk"
    ' <<<"$output" >/dev/null || return 1

    pass "partial_resource_data_is_labeled"
}

test_pressure_json_keeps_dashboard_decision_visible() {
    local status_script output
    status_script="$(pressure_status_script)"
    output="$(run_info "$status_script" --json --live)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/pressure-info.json"

    jq -e '
      .swarm.status == "warn" and
      .swarm.resources == "1 GiB mem, 20 GiB disk" and
      .swarm.warning_count == 2 and
      .swarm.next_action == "Review swarm warnings before launching more agents"
    ' <<<"$output" >/dev/null || return 1

    pass "pressure_json_keeps_dashboard_decision_visible"
}

test_dashboard_generate_writes_swarm_panel() {
    local status_script output status dashboard_home html_path
    status_script="$(pressure_status_script)"
    dashboard_home="$ARTIFACT_DIR/home/.acfs"
    html_path="$dashboard_home/dashboard/index.html"
    mkdir -p "$dashboard_home"
    printf '{"target_home":"%s","target_user":"ubuntu"}\n' "$ARTIFACT_DIR/home" > "$dashboard_home/state.json"

    set +e
    output="$(env \
        HOME="$ARTIFACT_DIR/home" \
        ACFS_HOME="$dashboard_home" \
        ACFS_INFO_SWARM_STATUS_SCRIPT="$status_script" \
        ACFS_INFO_SWARM_STATUS_DEADLINE=1 \
        ACFS_INFO_SWARM_STATUS_TIMEOUT=1 \
        bash "$DASHBOARD_SH" generate --force 2>&1)"
    status=$?
    set -e
    printf '%s\n' "$output" > "$ARTIFACT_DIR/dashboard-generate.output.txt"

    [[ "$status" -eq 0 ]] || return 1
    [[ -s "$html_path" ]] || return 1
    grep -Fq "<h2>Swarm Operations</h2>" "$html_path" || return 1
    grep -Fq "Agent Mail=pass RCH=warn" "$html_path" || return 1
    grep -Fq "1 GiB mem, 20 GiB disk" "$html_path" || return 1
    grep -Fq "Review swarm warnings before launching more agents" "$html_path" || return 1

    pass "dashboard_generate_writes_swarm_panel"
}

test_missing_collector_is_labeled() {
    local output
    output="$(run_info "$ARTIFACT_DIR/missing-swarm-status.sh" --json --live)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/missing.json"

    jq -e '
      .swarm.status == "unknown" and
      .swarm.next_action == "swarm_status.sh unavailable or timed out" and
      .swarm.ready_beads == "unknown"
    ' <<<"$output" >/dev/null || return 1

    pass "missing_collector_is_labeled"
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
        echo "jq is required for info swarm tests" >&2
        exit 1
    }
    mkdir -p "$ARTIFACT_DIR/home"

    run_test test_terminal_includes_swarm_panel
    run_test test_json_includes_swarm_summary
    run_test test_html_includes_dashboard_panel
    run_test test_partial_resource_data_is_labeled
    run_test test_pressure_json_keeps_dashboard_decision_visible
    run_test test_dashboard_generate_writes_swarm_panel
    run_test test_missing_collector_is_labeled
    run_test test_default_info_does_not_invoke_live_collector
    run_test test_ip_discovery_does_not_create_cache
    run_test test_live_collector_preserves_callers_errexit
    run_test test_sourced_info_resets_live_flag_for_each_call

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
