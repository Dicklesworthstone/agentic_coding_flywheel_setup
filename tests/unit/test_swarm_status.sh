#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs swarm status collector
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWARM_STATUS_SH="$REPO_ROOT/scripts/lib/swarm_status.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_SWARM_STATUS_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-swarm-status-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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

write_artifact() {
    local name="$1"
    local content="$2"
    printf '%s\n' "$content" > "$ARTIFACT_DIR/$name"
}

now_ms() {
    local now=""
    now="$(date +%s%3N 2>/dev/null || true)"
    if [[ "$now" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$now"
        return 0
    fi
    now="$(date +%s 2>/dev/null || echo 0)"
    printf '%s000\n' "$now"
}

run_and_capture() {
    local name="$1"
    shift

    local output=""
    local status=0
    local start_ms end_ms
    start_ms="$(now_ms)"

    set +e
    output="$("$@" 2>"$ARTIFACT_DIR/$name.stderr")"
    status=$?
    set -e

    end_ms="$(now_ms)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.stdout"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$((end_ms - start_ms))" > "$ARTIFACT_DIR/$name.duration_ms"
    printf '%s\n' "$output"
}

make_stub_dir() {
    local stub_dir
    stub_dir="$(mktemp -d "$ARTIFACT_DIR/stubs.XXXXXX")"
    printf '%s\n' "$stub_dir"
}

write_executable() {
    local path="$1"
    local body="$2"
    printf '%s\n' "$body" > "$path"
    chmod +x "$path"
}

test_no_tool_environment_warns() {
    local output
    output="$(run_and_capture no_tool_environment env PATH="/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 bash "$SWARM_STATUS_SH" --json)"
    write_artifact "no_tool_environment.json" "$output"

    jq -e '
      .schema_version == 1 and
      .status == "warn" and
      .probes.beads.available == false and
      .probes.bv.available == false and
      .probes.rch.available == false and
      (.warnings | length) > 0
    ' <<<"$output" >/dev/null || return 1
    [[ "$(cat "$ARTIFACT_DIR/no_tool_environment.exit")" -eq 0 ]] || return 1

    pass "no_tool_environment_warns"
}

test_stubbed_tools_pass() {
    local stub_dir
    stub_dir="$(make_stub_dir)"

    write_executable "$stub_dir/ntm" '#!/usr/bin/env bash
[[ "$1" == "--robot-status" ]] || exit 2
echo "{\"sessions\":[{\"name\":\"main\"}]}"'

    write_executable "$stub_dir/tmux" '#!/usr/bin/env bash
[[ "$1" == "list-sessions" ]] || exit 2
printf "main\t3\nworkers\t2\n"'

    write_executable "$stub_dir/am" '#!/usr/bin/env bash
[[ "$1 $2 $3" == "doctor check --json" ]] || exit 2
echo "{\"healthy\":true}"'

    write_executable "$stub_dir/br" '#!/usr/bin/env bash
case "$*" in
  "ready --json") echo "{\"issues\":[{\"id\":\"bd-a\"}],\"total\":1}" ;;
  "list --status in_progress --json") echo "{\"issues\":[],\"total\":0}" ;;
  "list --status open --json") echo "{\"issues\":[{\"id\":\"bd-a\"},{\"id\":\"bd-b\"},{\"id\":\"bd-c\"}],\"total\":3}" ;;
  *) exit 2 ;;
esac'

    write_executable "$stub_dir/bv" '#!/usr/bin/env bash
[[ "$1" == "--robot-next" ]] || exit 2
echo "{\"recommendation\":{\"id\":\"bd-a\"}}"'

    write_executable "$stub_dir/rch" '#!/usr/bin/env bash
[[ "$1 $2" == "status --json" ]] || exit 2
echo "{\"daemon\":{\"running\":true},\"queue\":{\"active\":0}}"'

    local output
    output="$(run_and_capture stubbed_tools env PATH="$stub_dir:/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 bash "$SWARM_STATUS_SH" --json)"
    write_artifact "stubbed_tools.json" "$output"

    jq -e '
      .status == "pass" and
      .probes.ntm.available == true and
      .probes.ntm.robot_status_ok == true and
      .probes.ntm.tmux_session_count == 2 and
      .probes.ntm.tmux_window_count == 5 and
      .probes.agent_mail.status == "pass" and
      .probes.agent_mail.healthy == true and
      .probes.beads.ready_count == 1 and
      .probes.beads.in_progress_count == 0 and
      .probes.beads.open_count == 3 and
      .probes.bv.robot_ok == true and
      .probes.rch.status_json_ok == true
    ' <<<"$output" >/dev/null || return 1
    [[ "$(cat "$ARTIFACT_DIR/stubbed_tools.exit")" -eq 0 ]] || return 1

    pass "stubbed_tools_pass"
}

test_partial_swarm_records_down_subsystems() {
    local stub_dir
    stub_dir="$(make_stub_dir)"

    write_executable "$stub_dir/tmux" '#!/usr/bin/env bash
[[ "$1" == "list-sessions" ]] || exit 2
printf "workers\t4\n"'

    write_executable "$stub_dir/am" '#!/usr/bin/env bash
[[ "$1 $2 $3" == "doctor check --json" ]] || exit 2
echo "database unavailable" >&2
exit 1'

    write_executable "$stub_dir/br" '#!/usr/bin/env bash
case "$*" in
  "ready --json") echo "{\"issues\":[{\"id\":\"bd-ready\"}],\"total\":1}" ;;
  "list --status in_progress --json") echo "{\"issues\":[{\"id\":\"bd-a\"},{\"id\":\"bd-b\"}],\"total\":2}" ;;
  "list --status open --json") echo "{\"issues\":[{\"id\":\"bd-a\"},{\"id\":\"bd-b\"},{\"id\":\"bd-c\"}],\"total\":3}" ;;
  *) exit 2 ;;
esac'

    write_executable "$stub_dir/bv" '#!/usr/bin/env bash
[[ "$1" == "--robot-next" ]] || exit 2
echo "{\"recommendation\":{\"id\":\"bd-ready\"}}"'

    write_executable "$stub_dir/rch" '#!/usr/bin/env bash
[[ "$1 $2" == "status --json" ]] || exit 2
echo "not json"'

    local output
    output="$(run_and_capture partial_swarm env PATH="$stub_dir:/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 bash "$SWARM_STATUS_SH" --json)"
    write_artifact "partial_swarm.json" "$output"

    jq -e '
      .status == "warn" and
      .probes.ntm.status == "warn" and
      .probes.ntm.tmux_available == true and
      .probes.ntm.tmux_session_count == 1 and
      .probes.ntm.tmux_window_count == 4 and
      .probes.agent_mail.available == true and
      .probes.agent_mail.status == "warn" and
      any(.probes.agent_mail.warnings[]; contains("Agent Mail doctor check failed or timed out")) and
      .probes.beads.status == "pass" and
      .probes.beads.ready_count == 1 and
      .probes.beads.in_progress_count == 2 and
      .probes.rch.available == true and
      .probes.rch.status == "warn" and
      any(.probes.rch.warnings[]; contains("invalid JSON")) and
      (.warnings | length) >= 3
    ' <<<"$output" >/dev/null || return 1

    pass "partial_swarm_records_down_subsystems"
}

test_resource_pressure_snapshot_records_host_data() {
    local stub_dir
    stub_dir="$(make_stub_dir)"

    write_executable "$stub_dir/nproc" '#!/usr/bin/env bash
echo 2'

    write_executable "$stub_dir/df" '#!/usr/bin/env bash
cat <<'"'"'DF'"'"'
Filesystem 1K-blocks Used Available Use% Mounted on
/dev/test 1000000 488000 512000 49% /tmp
DF'

    write_executable "$stub_dir/ntm" '#!/usr/bin/env bash
[[ "$1" == "--robot-status" ]] || exit 2
echo "{\"sessions\":[]}"'

    write_executable "$stub_dir/tmux" '#!/usr/bin/env bash
[[ "$1" == "list-sessions" ]] || exit 2
printf "main\t1\n"'

    write_executable "$stub_dir/am" '#!/usr/bin/env bash
[[ "$1 $2 $3" == "doctor check --json" ]] || exit 2
echo "{\"healthy\":true}"'

    write_executable "$stub_dir/br" '#!/usr/bin/env bash
case "$*" in
  "ready --json") echo "{\"issues\":[{\"id\":\"bd-a\"}],\"total\":1}" ;;
  "list --status in_progress --json") echo "{\"issues\":[],\"total\":0}" ;;
  "list --status open --json") echo "{\"issues\":[{\"id\":\"bd-a\"}],\"total\":1}" ;;
  *) exit 2 ;;
esac'

    write_executable "$stub_dir/bv" '#!/usr/bin/env bash
[[ "$1" == "--robot-next" ]] || exit 2
echo "{\"recommendation\":{\"id\":\"bd-a\"}}"'

    write_executable "$stub_dir/rch" '#!/usr/bin/env bash
[[ "$1 $2" == "status --json" ]] || exit 2
echo "{\"daemon\":{\"running\":true},\"queue\":{\"active\":0}}"'

    local output
    output="$(run_and_capture resource_pressure env HOME="$ARTIFACT_DIR/pressure-home" PATH="$stub_dir:/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 bash "$SWARM_STATUS_SH" --json)"
    write_artifact "resource_pressure.json" "$output"

    jq -e '
      .schema_version == 1 and
      .status == "pass" and
      .host.cpu_count == 2 and
      .host.disk_available_kb == 512000 and
      .probes.beads.ready_count == 1 and
      .probes.rch.status_json_ok == true
    ' <<<"$output" >/dev/null || return 1

    pass "resource_pressure_snapshot_records_host_data"
}

test_timeout_becomes_structured_warning() {
    local stub_dir
    stub_dir="$(make_stub_dir)"

    write_executable "$stub_dir/ntm" '#!/usr/bin/env bash
sleep 2
echo "{\"sessions\":[]}"'

    local output
    output="$(run_and_capture timeout_warning env PATH="$stub_dir:/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 bash "$SWARM_STATUS_SH" --json)"
    write_artifact "timeout_warning.json" "$output"

    jq -e '
      .status == "warn" and
      .probes.ntm.status == "warn" and
      any(.probes.ntm.warnings[]; contains("ntm --robot-status failed or timed out"))
    ' <<<"$output" >/dev/null || return 1

    pass "timeout_becomes_structured_warning"
}

test_human_output() {
    local output
    output="$(run_and_capture human_output env PATH="/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 bash "$SWARM_STATUS_SH")"
    write_artifact "human_output.txt" "$output"

    grep -Fq "ACFS Swarm Status" <<<"$output" || return 1
    grep -Fq "Status:" <<<"$output" || return 1
    grep -Fq "Warnings:" <<<"$output" || return 1

    pass "human_output"
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
        echo "jq is required for swarm status tests" >&2
        exit 1
    }

    run_test test_no_tool_environment_warns
    run_test test_stubbed_tools_pass
    run_test test_partial_swarm_records_down_subsystems
    run_test test_resource_pressure_snapshot_records_host_data
    run_test test_timeout_becomes_structured_warning
    run_test test_human_output

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
