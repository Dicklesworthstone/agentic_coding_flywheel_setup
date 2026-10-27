#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs swarm status collector
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWARM_STATUS_SH="$REPO_ROOT/scripts/lib/swarm_status.sh"
EDITOR_STATUS_SH="${ACFS_EDITOR_STATUS_TEST_SCRIPT:-$REPO_ROOT/scripts/lib/status.sh}"

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
    if [[ -n "${2:-}" ]]; then
        echo "  Reason: $2"
    fi
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
    # Restricted tool PATHs must still exercise the real timeout boundary.
    ln -s "$(command -v timeout)" "$stub_dir/timeout"
    # Healthy coordination fixtures must not depend on the test host exposing
    # PSI. This invokes the real entrypoint and pressure parsers; only kernel
    # observations are replaced in this test process, without a runtime override.
    write_executable "$stub_dir/swarm-status-fixture" '#!/usr/bin/env bash
source "$1"
shift
swarm_status_read_swap_info() {
    printf "SwapTotal: 8388608 kB\nSwapFree: 6291456 kB\n" | swarm_status_parse_swap_info
}
swarm_status_read_memory_psi() {
    printf "some avg10=0.10 avg60=0.20 avg300=0.30 total=1234\nfull avg10=0.00 avg60=0.10 avg300=0.20 total=123\n" | swarm_status_parse_memory_psi
}
swarm_status_main "$@"'
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
    output="$(run_and_capture no_tool_environment env PATH="/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 "$BASH" "$SWARM_STATUS_SH" --json)"
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
  "list --status in_progress --json") echo "{\"issues\":[{\"id\":\"bd-live\",\"title\":\"Live work\",\"assignee\":\"BlueLake\",\"created_at\":\"2026-05-08T00:00:00Z\",\"updated_at\":\"2026-05-08T01:00:00Z\"}],\"total\":1}" ;;
  "list --status open --json") echo "{\"issues\":[{\"id\":\"bd-a\"},{\"id\":\"bd-b\"},{\"id\":\"bd-c\"}],\"total\":3}" ;;
  *) exit 2 ;;
esac'

    write_executable "$stub_dir/bv" '#!/usr/bin/env bash
[[ "$1" == "--robot-next" ]] || exit 2
echo "{\"recommendation\":{\"id\":\"bd-a\"}}"'

    write_executable "$stub_dir/rch" '#!/usr/bin/env bash
case "$*" in
  "status --json") echo "{\"data\":{\"daemon\":{\"daemon\":{\"workers_total\":2,\"workers_healthy\":2,\"slots_total\":12,\"slots_available\":11},\"workers\":[{\"id\":\"w1\",\"status\":\"healthy\",\"used_slots\":1,\"pressure_state\":\"healthy\",\"pressure_telemetry_fresh\":true},{\"id\":\"w2\",\"status\":\"healthy\",\"used_slots\":0,\"pressure_state\":\"healthy\",\"pressure_telemetry_fresh\":true}],\"active_builds\":[{\"id\":1}],\"queued_builds\":[]}}}" ;;
  "queue --json") echo "{\"data\":{\"queue_depth\":0,\"active_builds\":[{\"id\":1}],\"slots_available\":11,\"slots_total\":12,\"workers_total\":2,\"workers_healthy\":2,\"workers_busy\":1,\"workers_offline\":0}}" ;;
  *) exit 2 ;;
esac'

    local output
    output="$(run_and_capture stubbed_tools env PATH="$stub_dir:/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 "$BASH" "$stub_dir/swarm-status-fixture" "$SWARM_STATUS_SH" --json)"
    write_artifact "stubbed_tools.json" "$output"

    jq -e '
      .status == "pass" and
      .host.swap_total_kb == 8388608 and
      .host.swap_free_kb == 6291456 and
      .host.memory_psi_some_avg60 == 0.2 and
      .host.memory_psi_full_avg60 == 0.1 and
      .probes.ntm.available == true and
      .probes.ntm.robot_status_ok == true and
      .probes.ntm.tmux_session_count == 2 and
      .probes.ntm.tmux_window_count == 5 and
      .probes.agent_mail.status == "pass" and
      .probes.agent_mail.healthy == true and
      .probes.beads.ready_count == 1 and
      .probes.beads.in_progress_count == 1 and
      .probes.beads.in_progress_items[0].id == "bd-live" and
      .probes.beads.in_progress_items[0].assignee == "BlueLake" and
      .probes.beads.open_count == 3 and
      .probes.bv.robot_ok == true and
      .probes.rch.status_json_ok == true and
      .probes.rch.queue_json_ok == true and
      .probes.rch.queue_depth == 0 and
      .probes.rch.active_build_count == 1 and
      .probes.rch.workers_total == 2 and
      .probes.rch.workers_healthy == 2 and
      .probes.rch.workers_busy == 1 and
      .probes.rch.workers_offline == 0 and
      .probes.rch.slots_total == 12 and
      .probes.rch.slots_available == 11 and
      .probes.rch.pressure_warning_count == 0 and
      .probes.rch.stale_worker_count == 0
    ' <<<"$output" >/dev/null || return 1
    [[ "$(cat "$ARTIFACT_DIR/stubbed_tools.exit")" -eq 0 ]] || return 1

    pass "stubbed_tools_pass"
}

test_rch_queue_pressure_metrics() {
    local stub_dir
    stub_dir="$(make_stub_dir)"

    write_executable "$stub_dir/rch" '#!/usr/bin/env bash
case "$*" in
  "status --json") cat <<'"'"'JSON'"'"'
{"data":{"daemon":{"daemon":{"workers_total":3,"workers_healthy":2,"slots_total":10,"slots_available":4},"workers":[{"id":"healthy","status":"healthy","used_slots":2,"pressure_state":"healthy","pressure_telemetry_fresh":true},{"id":"stale","status":"healthy","used_slots":0,"pressure_state":"telemetry_gap","pressure_telemetry_fresh":false},{"id":"offline","status":"offline","used_slots":0,"pressure_state":"healthy","pressure_telemetry_fresh":true}],"active_builds":[{"id":1},{"id":2}],"queued_builds":[{"id":3},{"id":4},{"id":5},{"id":6}]}}}
JSON
    ;;
  "queue --json") cat <<'"'"'JSON'"'"'
{"data":{"queue_depth":4,"active_builds":[{"id":1},{"id":2}],"slots_available":3,"slots_total":10,"workers_total":3,"workers_healthy":2,"workers_busy":2,"workers_offline":1}}
JSON
    ;;
  *) exit 2 ;;
esac'

    local output
    output="$(run_and_capture rch_queue_pressure env PATH="$stub_dir:/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 "$BASH" "$SWARM_STATUS_SH" --json)"
    write_artifact "rch_queue_pressure.json" "$output"

    jq -e '
      .probes.rch.available == true and
      .probes.rch.status == "warn" and
      .probes.rch.status_json_ok == true and
      .probes.rch.queue_json_ok == true and
      .probes.rch.queue_depth == 4 and
      .probes.rch.active_build_count == 2 and
      .probes.rch.workers_total == 3 and
      .probes.rch.workers_healthy == 2 and
      .probes.rch.workers_busy == 2 and
      .probes.rch.workers_offline == 1 and
      .probes.rch.slots_available == 3 and
      .probes.rch.slots_total == 10 and
      .probes.rch.pressure_warning_count == 1 and
      .probes.rch.stale_worker_count == 1 and
      any(.probes.rch.warnings[]; contains("elevated pressure")) and
      any(.probes.rch.warnings[]; contains("stale pressure telemetry"))
    ' <<<"$output" >/dev/null || return 1

    pass "rch_queue_pressure_metrics"
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
    output="$(run_and_capture partial_swarm env PATH="$stub_dir:/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 "$BASH" "$SWARM_STATUS_SH" --json)"
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
case "$*" in
  "status --json") echo "{\"data\":{\"daemon\":{\"daemon\":{\"workers_total\":1,\"workers_healthy\":1,\"slots_total\":4,\"slots_available\":4},\"workers\":[{\"id\":\"w1\",\"status\":\"healthy\",\"used_slots\":0,\"pressure_state\":\"healthy\",\"pressure_telemetry_fresh\":true}],\"active_builds\":[],\"queued_builds\":[]}}}" ;;
  "queue --json") echo "{\"data\":{\"queue_depth\":0,\"active_builds\":[],\"slots_available\":4,\"slots_total\":4,\"workers_total\":1,\"workers_healthy\":1,\"workers_busy\":0,\"workers_offline\":0}}" ;;
  *) exit 2 ;;
esac'

    local output
    output="$(run_and_capture resource_pressure env HOME="$ARTIFACT_DIR/pressure-home" PATH="$stub_dir:/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 "$BASH" "$stub_dir/swarm-status-fixture" "$SWARM_STATUS_SH" --json)"
    write_artifact "resource_pressure.json" "$output"

    jq -e '
      .schema_version == 1 and
      .status == "pass" and
      .host.cpu_count == 2 and
      .host.disk_available_kb == 512000 and
      .host.swap_total_kb == 8388608 and
      .host.swap_free_kb == 6291456 and
      .host.memory_psi_some_avg60 == 0.2 and
      .host.memory_psi_full_avg60 == 0.1 and
      .probes.beads.ready_count == 1 and
      .probes.rch.status_json_ok == true and
      .probes.rch.queue_json_ok == true and
      .probes.rch.queue_depth == 0 and
      .probes.rch.slots_available == 4
    ' <<<"$output" >/dev/null || return 1

    pass "resource_pressure_snapshot_records_host_data"
}

run_memory_fixture_json() {
    local name="$1" meminfo="$2" psi="$3"
    printf '%s\n' "$meminfo" > "$ARTIFACT_DIR/$name.meminfo"
    printf '%s\n' "$psi" > "$ARTIFACT_DIR/$name.psi"
    run_and_capture "$name" env PATH="/usr/bin:/bin" "$BASH" -c '
        source "$1"
        swap_fixture="$2"
        psi_fixture="$3"
        swarm_status_read_swap_info() { swarm_status_parse_swap_info < "$swap_fixture"; }
        swarm_status_read_memory_psi() { swarm_status_parse_memory_psi < "$psi_fixture"; }
        swarm_status_collect_host
        swarm_status_emit_json
    ' _ "$SWARM_STATUS_SH" "$ARTIFACT_DIR/$name.meminfo" "$ARTIFACT_DIR/$name.psi"
}

test_memory_pressure_values_and_no_swap() {
    local output psi
    psi=$'some avg10=1.25 avg60=12.345678 avg300=2.50 total=12345\nfull avg10=0.10 avg60=10.01 avg300=0.25 total=100'
    output="$(run_memory_fixture_json pressure_values $'MemTotal: 33554432 kB\nSwapTotal: 8388608 kB\nSwapFree: 1024 kB' "$psi")"
    jq -e '.host.swap_total_kb == 8388608 and .host.swap_free_kb == 1024 and
        .host.memory_psi_some_avg60 == 12.345678 and .host.memory_psi_full_avg60 == 10.01 and
        .host.status == "pass"' <<< "$output" >/dev/null || return 1

    output="$(run_memory_fixture_json no_swap $'SwapTotal: 0 kB\nSwapFree: 0 kB' "$psi")"
    jq -e '.host.swap_total_kb == 0 and .host.swap_free_kb == 0 and .host.status == "pass"' <<< "$output" >/dev/null || return 1

    output="$(run_memory_fixture_json exhausted_swap $'SwapTotal: 8388608 kB\nSwapFree: 0 kB' "$psi")"
    jq -e '.host.swap_total_kb == 8388608 and .host.swap_free_kb == 0 and .host.status == "pass"' <<< "$output" >/dev/null || return 1

    output="$(run_memory_fixture_json exact_integer_limit $'SwapTotal: 9007199254740991 kB\nSwapFree: 9007199254740991 kB' "$psi")"
    jq -e '.host.swap_total_kb == 9007199254740991 and .host.swap_free_kb == 9007199254740991' <<< "$output" >/dev/null || return 1
    pass "memory_pressure_values_and_no_swap"
}

test_invalid_swap_is_unknown() {
    local output input index=0 psi
    psi=$'some avg10=0.00 avg60=0.00 avg300=0.00 total=0\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0'
    local -a invalid=(
        ''
        $'SwapTotal: 1024 kB'
        $'SwapTotal: -1 kB\nSwapFree: 0 kB'
        $'SwapTotal: 1.5 kB\nSwapFree: 0 kB'
        $'SwapTotal: 1e9 kB\nSwapFree: 0 kB'
        $'SwapTotal: 9007199254740992 kB\nSwapFree: 0 kB'
        $'SwapTotal: 1024 kB\nSwapFree: 2048 kB'
        $'SwapTotal: 0 kB\nSwapFree: 1 kB'
        $'SwapTotal: 1024 MB\nSwapFree: 512 kB'
        $'SwapTotal: 1024 kB\nSwapTotal: 2048 kB\nSwapFree: 512 kB'
        $'SwapTotal: 1024 kB\nSwapFree: 512 kB extra'
    )
    for input in "${invalid[@]}"; do
        index=$((index + 1))
        output="$(run_memory_fixture_json "invalid_swap_$index" "$input" "$psi")"
        jq -e '.host.status == "warn" and .host.swap_total_kb == null and .host.swap_free_kb == null and
            .host.memory_psi_some_avg60 == 0 and .host.memory_psi_full_avg60 == 0 and
            any(.host.warnings[]; contains("Swap headroom is unknown"))' <<< "$output" >/dev/null || return 1
    done
    pass "invalid_swap_is_unknown ($index cases)"
}

test_invalid_memory_psi_is_unknown() {
    local output input index=0 some full
    some='some avg10=0.00 avg60=10.00 avg300=0.00 total=100'
    full='full avg10=0.00 avg60=1.00 avg300=0.00 total=10'
    local -a invalid=(
        ''
        "$some"
        "$some"$'\nfull avg10=0.00 avg60=11.00 avg300=0.00 total=10'
        $'some avg10=0.00 avg60=100.01 avg300=0.00 total=100\n'"$full"
        "$some"$'\nfull avg10=0.00 avg60=-1.00 avg300=0.00 total=10'
        "$some"$'\nfull avg10=0.00 avg60=NaN avg300=0.00 total=10'
        "$some"$'\nfull avg10=0.00 avg60=1e1 avg300=0.00 total=10'
        "$some"$'\nfull avg10=0.00 avg60=1.1234567 avg300=0.00 total=10'
        "$some"$'\n'"$full"$'\n'"$full"
        "$some"$'\nfull avg10=0.00 avg60=1.00 avg60=2.00 total=10'
        "$some"$'\nfull avg10=0.00 avg60=1.00 avg300=0.00'
        "$some"$'\nfull avg10=0.00 avg60=1.00 avg300=0.00 other=10'
    )
    for input in "${invalid[@]}"; do
        index=$((index + 1))
        output="$(run_memory_fixture_json "invalid_psi_$index" $'SwapTotal: 1024 kB\nSwapFree: 512 kB' "$input")"
        jq -e '.host.status == "warn" and .host.memory_psi_some_avg60 == null and .host.memory_psi_full_avg60 == null and
            .host.swap_total_kb == 1024 and .host.swap_free_kb == 512 and
            any(.host.warnings[]; contains("Memory PSI is unknown"))' <<< "$output" >/dev/null || return 1
    done
    pass "invalid_memory_psi_is_unknown ($index cases)"
}

test_memory_pressure_read_failures_and_size_bounds() {
    local output oversized psi
    output="$(run_and_capture unreadable_pressure env PATH="/usr/bin:/bin" "$BASH" -c '
        source "$1"
        swarm_status_read_swap_info() { return 1; }
        swarm_status_read_memory_psi() { return 1; }
        swarm_status_collect_host
        swarm_status_emit_json
    ' _ "$SWARM_STATUS_SH")"
    jq -e '.host.status == "warn" and .host.swap_total_kb == null and .host.swap_free_kb == null and
        .host.memory_psi_some_avg60 == null and .host.memory_psi_full_avg60 == null and
        any(.host.warnings[]; contains("Swap headroom is unknown")) and
        any(.host.warnings[]; contains("Memory PSI is unknown"))' <<< "$output" >/dev/null || return 1

    psi=$'some avg10=0.00 avg60=0.00 avg300=0.00 total=0\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0'
    oversized="$(printf '%65537s' '')"
    output="$(run_memory_fixture_json oversized_meminfo $'SwapTotal: 1024 kB\nSwapFree: 512 kB\n'"$oversized" "$psi")"
    jq -e '.host.swap_total_kb == null and .host.swap_free_kb == null and .host.status == "warn"' <<< "$output" >/dev/null || return 1

    oversized="$(printf '%4097s' '')"
    output="$(run_memory_fixture_json oversized_psi $'SwapTotal: 1024 kB\nSwapFree: 512 kB' "$psi"$'\n'"$oversized")"
    jq -e '.host.memory_psi_some_avg60 == null and .host.memory_psi_full_avg60 == null and .host.status == "warn"' <<< "$output" >/dev/null || return 1
    pass "memory_pressure_read_failures_and_size_bounds"
}

test_timeout_becomes_structured_warning() {
    local stub_dir
    stub_dir="$(make_stub_dir)"

    write_executable "$stub_dir/ntm" '#!/usr/bin/env bash
sleep 2
echo "{\"sessions\":[]}"'

    local output
    output="$(run_and_capture timeout_warning env PATH="$stub_dir:/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 "$BASH" "$SWARM_STATUS_SH" --json)"
    write_artifact "timeout_warning.json" "$output"

    jq -e '
      .status == "warn" and
      .probes.ntm.status == "warn" and
      any(.probes.ntm.warnings[]; contains("ntm --robot-status failed or timed out"))
    ' <<<"$output" >/dev/null || return 1

    pass "timeout_becomes_structured_warning"
}

test_rch_queue_timeout_becomes_structured_warning() {
    local stub_dir
    stub_dir="$(make_stub_dir)"

    write_executable "$stub_dir/rch" '#!/usr/bin/env bash
case "$*" in
  "status --json") echo "{\"data\":{\"daemon\":{\"daemon\":{\"workers_total\":1,\"workers_healthy\":1,\"slots_total\":2,\"slots_available\":2},\"workers\":[{\"id\":\"w1\",\"status\":\"healthy\",\"used_slots\":0,\"pressure_state\":\"healthy\",\"pressure_telemetry_fresh\":true}],\"active_builds\":[],\"queued_builds\":[]}}}" ;;
  "queue --json") sleep 2 ;;
  *) exit 2 ;;
esac'

    local output
    output="$(run_and_capture rch_queue_timeout env PATH="$stub_dir:/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 "$BASH" "$SWARM_STATUS_SH" --json)"
    write_artifact "rch_queue_timeout.json" "$output"

    jq -e '
      .status == "warn" and
      .probes.rch.status == "warn" and
      .probes.rch.status_json_ok == true and
      .probes.rch.queue_json_ok == false and
      any(.probes.rch.warnings[]; contains("rch queue --json failed or timed out"))
    ' <<<"$output" >/dev/null || return 1

    pass "rch_queue_timeout_becomes_structured_warning"
}

test_human_output() {
    local output
    output="$(run_and_capture human_output env PATH="/usr/bin:/bin" ACFS_SWARM_STATUS_TIMEOUT=1 "$BASH" "$SWARM_STATUS_SH")"
    write_artifact "human_output.txt" "$output"

    grep -Fq "ACFS Swarm Status" <<<"$output" || return 1
    grep -Fq "Status:" <<<"$output" || return 1
    grep -Fq "memory PSI avg60:" <<<"$output" || return 1
    grep -Fq "Warnings:" <<<"$output" || return 1

    pass "human_output"
}

test_human_memory_pressure_labels() {
    local output
    output="$(run_and_capture human_pressure_labels "$BASH" -c '
        source "$1"
        HOST_SWAP_TOTAL_KB=0
        HOST_SWAP_FREE_KB=0
        swarm_status_emit_human
        HOST_SWAP_TOTAL_KB=1024
        HOST_SWAP_FREE_KB=0
        HOST_MEMORY_PSI_SOME_AVG60=10.250000
        HOST_MEMORY_PSI_FULL_AVG60=2.500000
        swarm_status_emit_human
        HOST_SWAP_TOTAL_KB=null
        HOST_SWAP_FREE_KB=null
        swarm_status_emit_human
    ' _ "$SWARM_STATUS_SH")"
    grep -Fq 'Swap: none configured (0/0 KiB); memory PSI avg60: some=unknown, full=unknown' <<< "$output" || return 1
    grep -Fq 'Swap: 0/1024 KiB free; memory PSI avg60: some=10.250000%, full=2.500000%' <<< "$output" || return 1
    grep -Fq 'Swap: unknown; memory PSI avg60:' <<< "$output" || return 1
    pass "human_memory_pressure_labels"
}

test_editor_collector_uses_calling_bash() {
    local stub_dir jq_bin timeout_bin output
    stub_dir="$(make_stub_dir)"
    jq_bin="$(command -v jq)"
    timeout_bin="$(command -v timeout)" || return 1
    printf '%s\n' '{"completed_phases":["finalize"]}' > "$stub_dir/state.json"
    write_executable "$stub_dir/ntm" '#!/usr/bin/env bash
printf "{}\n"'
    write_executable "$stub_dir/tmux" '#!/usr/bin/env bash
printf "fixture-session\t3\n"'
    write_executable "$stub_dir/older-bash" '#!/usr/bin/env bash
printf "called\n" > "$EDITOR_OLD_BASH_MARKER"
exit 99'

    # Execute the actual editor function and collector. The resolver deliberately
    # offers an unusable older Bash; a modern caller must keep its interpreter.
    output="$(run_and_capture editor_interpreter env \
        PATH="$stub_dir:$(dirname "$BASH"):$PATH" \
        EDITOR_OLD_BASH_MARKER="$stub_dir/older-bash-called" \
        "$BASH" -c '
            source "$1"
            editor_timeout="$4"
            editor_old_bash="$5"
            _status_system_binary_path() {
                case "$1" in
                    bash) printf "%s\n" "$editor_old_bash" ;;
                    timeout) printf "%s\n" "$editor_timeout" ;;
                    date) command -v date ;;
                    *) return 1 ;;
                esac
            }
            _STATUS_LIVE=true
            _status_editor_json "$2" 25 OK "$3"
        ' _ "$EDITOR_STATUS_SH" "$stub_dir/state.json" "$jq_bin" "$timeout_bin" "$stub_dir/older-bash")"

    [[ "$(cat "$ARTIFACT_DIR/editor_interpreter.exit")" == 0 ]] || return 1
    jq -e '.status == "ok" and .sessions.status == "ok" and
        .sessions.session_count == 1 and .sessions.window_count == 3' <<<"$output" >/dev/null || return 1
    [[ ! -e "$stub_dir/older-bash-called" ]] || return 1
    pass "editor_collector_uses_calling_bash"
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
    command -v timeout >/dev/null 2>&1 || {
        echo "timeout is required for swarm status tests" >&2
        exit 1
    }

    run_test test_editor_collector_uses_calling_bash
    if [[ "${1:-}" == "--editor-interpreter-only" ]]; then
        echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
        echo "Artifacts: $ARTIFACT_DIR"
        [[ $TESTS_FAILED -eq 0 ]]
        return
    fi

    run_test test_no_tool_environment_warns
    run_test test_stubbed_tools_pass
    run_test test_rch_queue_pressure_metrics
    run_test test_partial_swarm_records_down_subsystems
    run_test test_resource_pressure_snapshot_records_host_data
    run_test test_memory_pressure_values_and_no_swap
    run_test test_invalid_swap_is_unknown
    run_test test_invalid_memory_psi_is_unknown
    run_test test_memory_pressure_read_failures_and_size_bounds
    run_test test_timeout_becomes_structured_warning
    run_test test_rch_queue_timeout_becomes_structured_warning
    run_test test_human_output
    run_test test_human_memory_pressure_labels

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
