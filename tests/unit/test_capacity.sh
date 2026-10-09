#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs capacity report
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CAPACITY_SH="$REPO_ROOT/scripts/lib/capacity.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_CAPACITY_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-capacity-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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

run_capacity_json() {
    ACFS_CAPACITY_CPU_COUNT="$1" \
    ACFS_CAPACITY_MEM_TOTAL_KB="$2" \
    ACFS_CAPACITY_DISK_AVAILABLE_KB="$3" \
    ACFS_CAPACITY_RCH_AVAILABLE="$4" \
    ACFS_CAPACITY_NTM_AVAILABLE="$5" \
    bash "$CAPACITY_SH" --json "${@:6}"
}

write_fixture_artifact() {
    local name="$1"
    local cpu_count="$2"
    local mem_total_kb="$3"
    local disk_available_kb="$4"
    local rch_available="$5"
    local ntm_available="$6"
    shift 6

    {
        echo "test=$name"
        echo "cpu_count=$cpu_count"
        echo "mem_total_kb=$mem_total_kb"
        echo "disk_available_kb=$disk_available_kb"
        echo "rch_available=$rch_available"
        echo "ntm_available=$ntm_available"
        printf 'args='
        printf ' %q' "$@"
        printf '\n'
    } > "$ARTIFACT_DIR/${name}.fixture"
}

write_output_artifact() {
    local name="$1"
    local extension="$2"
    local content="$3"

    printf '%s\n' "$content" > "$ARTIFACT_DIR/${name}.${extension}"
}

run_capacity_json_fixture() {
    local name="$1"
    local cpu_count="$2"
    local mem_total_kb="$3"
    local disk_available_kb="$4"
    local rch_available="$5"
    local ntm_available="$6"
    shift 6

    write_fixture_artifact "$name" "$cpu_count" "$mem_total_kb" "$disk_available_kb" "$rch_available" "$ntm_available" "$@"

    local output
    output="$(run_capacity_json "$cpu_count" "$mem_total_kb" "$disk_available_kb" "$rch_available" "$ntm_available" "$@")"
    write_output_artifact "$name" "json" "$output"
    printf '%s\n' "$output"
}

make_resource_profile_fake_bin() {
    local name="$1"
    local fake_bin="$ARTIFACT_DIR/$name-bin"
    mkdir -p "$fake_bin"

    cat > "$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "--user show-environment" ]]; then
    echo "PATH=/usr/bin:/bin"
    exit 0
fi
exit 1
EOF
    chmod +x "$fake_bin/systemctl"

    cat > "$fake_bin/systemd-run" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ACFS_FAKE_SYSTEMD_RUN_LOG:?}"
while [[ $# -gt 0 && "$1" == --* ]]; do
    shift
done
exec "$@"
EOF
    chmod +x "$fake_bin/systemd-run"

    printf '%s\n' "$fake_bin"
}

make_resource_profile_failing_systemd_bin() {
    local name="$1"
    local fake_bin="$ARTIFACT_DIR/$name-bin"
    mkdir -p "$fake_bin"

    cat > "$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$fake_bin/systemctl"

    cat > "$fake_bin/systemd-run" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ACFS_FAKE_SYSTEMD_RUN_LOG:?}"
exit 99
EOF
    chmod +x "$fake_bin/systemd-run"

    printf '%s\n' "$fake_bin"
}

test_high_capacity_json() {
    local output
    output="$(run_capacity_json_fixture high_capacity_json 64 268435456 314572800 true true --profile 25-agents --recommend-ntm)"

    jq -e '
      .schema_version == 1 and
      .host.cpu_count == 64 and
      .host.mem_total_mib == 262144 and
      .tools.rch.available == true and
      .capacity.safe_agent_count == 64 and
      .capacity.recommended_agent_count == 44 and
      .profile_check.status == "pass" and
      .ntm.agent_count == 44 and
      (.ntm.profiles | length) == 4 and
      (.ntm.profiles[] | select(.agents == 25 and .status == "pass" and (.command | contains("ntm spawn myproject --label swarm-25")))) and
      (.ntm.profiles[] | select(.agents == 50 and .status == "warn" and (.rch_policy | contains("rch exec --"))))
    ' <<<"$output" >/dev/null || return 1

    pass "high_capacity_json"
}

test_profile_warns_above_recommended() {
    local output
    output="$(run_capacity_json_fixture profile_warns_above_recommended 64 268435456 314572800 true true --profile 50)"

    jq -e '.profile_check.status == "warn" and .profile_check.requested_agents == 50' <<<"$output" >/dev/null || return 1

    pass "profile_warns_above_recommended"
}

test_small_host_fails_oversized_profile() {
    local output
    output="$(run_capacity_json_fixture small_host_fails_oversized_profile 2 4194304 15728640 false false --profile 10)"

    jq -e '
      .status == "fail" and
      .tools.rch.available == false and
      .capacity.safe_agent_count == 0 and
      .profile_check.status == "fail"
    ' <<<"$output" >/dev/null || return 1

    pass "small_host_fails_oversized_profile"
}

test_heavy_workload_capacity() {
    local output
    output="$(run_capacity_json_fixture heavy_workload_capacity 16 67108864 209715200 true true --workload heavy --profile 8)"

    jq -e '
      .assumptions.workload == "heavy" and
      .assumptions.per_agent_mib == 4096 and
      .assumptions.cpu_milli_per_agent == 2000 and
      .capacity.cpu_limited_agents == 8 and
      .capacity.safe_agent_count == 8 and
      .profile_check.status == "warn"
    ' <<<"$output" >/dev/null || return 1

    pass "heavy_workload_capacity"
}

test_low_disk_fails_capacity() {
    local output
    output="$(run_capacity_json_fixture low_disk_fails_capacity 16 67108864 4096 true true --profile 1)"

    jq -e '
      .status == "fail" and
      .capacity.disk_limited_agents == 0 and
      .capacity.safe_agent_count == 0 and
      .profile_check.status == "fail"
    ' <<<"$output" >/dev/null || return 1

    pass "low_disk_fails_capacity"
}

test_invalid_workload_exits_2() {
    local output status

    set +e
    output="$(bash "$CAPACITY_SH" --workload impossible 2>&1)"
    status=$?
    set -e
    write_output_artifact "invalid_workload_exits_2" "stderr" "$output"

    [[ "$status" -eq 2 ]] || return 1
    grep -Fq "unsupported workload" <<<"$output" || return 1

    pass "invalid_workload_exits_2"
}

test_human_output() {
    local output
    output="$(
        ACFS_CAPACITY_CPU_COUNT=8 \
        ACFS_CAPACITY_MEM_TOTAL_KB=33554432 \
        ACFS_CAPACITY_DISK_AVAILABLE_KB=104857600 \
        ACFS_CAPACITY_RCH_AVAILABLE=true \
        ACFS_CAPACITY_NTM_AVAILABLE=false \
        bash "$CAPACITY_SH" --workload standard --profile 5 --recommend-ntm
    )"
    write_fixture_artifact human_output 8 33554432 104857600 true false --workload standard --profile 5 --recommend-ntm
    write_output_artifact "human_output" "txt" "$output"

    grep -Fq "ACFS Capacity Report" <<<"$output" || return 1
    grep -Fq "Recommended agents:" <<<"$output" || return 1
    grep -Fq "Profile Check" <<<"$output" || return 1
    grep -Fq "Launch Profiles" <<<"$output" || return 1
    grep -Fq "25 agents:" <<<"$output" || return 1
    grep -Fq "Agent Mail:" <<<"$output" || return 1

    pass "human_output"
}

test_resource_profile_dry_run_json_is_read_only() {
    local root output
    root="$ARTIFACT_DIR/resource-dry-run-home"
    output="$(
        ACFS_RESOURCE_PROFILE_HOME="$root" \
        bash "$CAPACITY_SH" --json --resource-profile
    )"
    write_output_artifact "resource_profile_dry_run" "json" "$output"

    jq -e '
      .mode == "dry-run" and
      .opt_in == true and
      .safety.no_hard_memory_limits_by_default == true and
      .safety.direct_agent_aliases_unchanged == true and
      .safety.rch_remains_preferred_build_path == true and
      ([.classes[].properties[] | select(startswith("MemoryMax="))] | length) == 0 and
      (.wrappers[] | select(.name == "acfs-scope")) and
      (.actions[] | select(contains("would write")))
    ' <<<"$output" >/dev/null || return 1
    [[ ! -e "$root/bin/acfs-scope" ]] || return 1

    pass "resource_profile_dry_run_json_is_read_only"
}

test_resource_profile_apply_writes_opt_in_wrappers() {
    local root fake_bin output log_file
    root="$ARTIFACT_DIR/resource-apply-home"
    fake_bin="$(make_resource_profile_fake_bin resource-apply)"
    log_file="$ARTIFACT_DIR/resource-apply-systemd-run.log"

    output="$(
        ACFS_RESOURCE_PROFILE_HOME="$root" \
        ACFS_CAPACITY_BIN_DIR="$fake_bin" \
        ACFS_FAKE_SYSTEMD_RUN_LOG="$log_file" \
        bash "$CAPACITY_SH" --json --resource-profile --apply-resource-profile
    )"
    write_output_artifact "resource_profile_apply" "json" "$output"

    jq -e '
      .mode == "applied" and
      .systemd.systemd_run_available == true and
      .systemd.user_manager_available == true and
      (.managed_files | index("'"$root"'/bin/acfs-scope")) and
      (.wrappers[] | select(.name == "ccs" and (.command | contains("claude"))))
    ' <<<"$output" >/dev/null || return 1

    [[ -x "$root/bin/acfs-scope" ]] || return 1
    [[ -x "$root/bin/ccs" ]] || return 1
    [[ -x "$root/bin/cods" ]] || return 1
    [[ -x "$root/bin/gmis" ]] || return 1
    [[ -x "$root/bin/acfs-local-build" ]] || return 1
    grep -Fq "export PATH=\"$root/bin:" "$root/acfs-resource-profile.sh" || return 1
    jq -e '.mode == "applied"' "$root/profile.json" >/dev/null || return 1
    ! grep -R "MemoryMax=" "$root" >/dev/null 2>&1 || return 1
    ! grep -R -E "pkill|killall|loginctl[[:space:]]+kill|systemctl[[:space:]]+--user[[:space:]]+stop" "$root/bin" >/dev/null 2>&1 || return 1

    ACFS_FAKE_SYSTEMD_RUN_LOG="$log_file" \
    PATH="$fake_bin:$root/bin:/usr/bin:/bin" \
    "$root/bin/acfs-scope" agent -- true
    grep -Fq -- "--slice=acfs-agent.slice" "$log_file" || return 1

    pass "resource_profile_apply_writes_opt_in_wrappers"
}

test_resource_profile_apply_is_idempotent() {
    local root fake_bin first_output second_output first_hash second_hash line_count
    root="$ARTIFACT_DIR/resource-idempotent-home"
    fake_bin="$(make_resource_profile_fake_bin resource-idempotent)"

    first_output="$(
        ACFS_RESOURCE_PROFILE_HOME="$root" \
        ACFS_CAPACITY_BIN_DIR="$fake_bin" \
        bash "$CAPACITY_SH" --json --resource-profile --apply-resource-profile
    )"
    first_hash="$(sha256sum "$root/bin/acfs-scope" | awk '{print $1}')"
    second_output="$(
        ACFS_RESOURCE_PROFILE_HOME="$root" \
        ACFS_CAPACITY_BIN_DIR="$fake_bin" \
        bash "$CAPACITY_SH" --json --resource-profile --apply-resource-profile
    )"
    second_hash="$(sha256sum "$root/bin/acfs-scope" | awk '{print $1}')"
    write_output_artifact "resource_profile_idempotent_first" "json" "$first_output"
    write_output_artifact "resource_profile_idempotent_second" "json" "$second_output"

    line_count="$(grep -Fc "export PATH=\"$root/bin:" "$root/acfs-resource-profile.sh")"

    [[ "$first_hash" == "$second_hash" ]] || return 1
    [[ "$line_count" -eq 1 ]] || return 1
    jq -e '.mode == "applied" and .status == "pass"' <<<"$first_output" >/dev/null || return 1
    jq -e '.mode == "applied" and .status == "pass"' <<<"$second_output" >/dev/null || return 1
    jq -e '.mode == "applied" and .status == "pass"' "$root/profile.json" >/dev/null || return 1

    pass "resource_profile_apply_is_idempotent"
}

test_resource_profile_partial_failure_reports_error() {
    local root fake_bin output status stderr_file
    root="$ARTIFACT_DIR/resource-partial-failure-home"
    fake_bin="$(make_resource_profile_fake_bin resource-partial-failure)"
    stderr_file="$ARTIFACT_DIR/resource_profile_partial_failure.stderr"
    mkdir -p "$root/bin" "$root/acfs-resource-profile.sh"

    set +e
    output="$(
        ACFS_RESOURCE_PROFILE_HOME="$root" \
        ACFS_CAPACITY_BIN_DIR="$fake_bin" \
        bash "$CAPACITY_SH" --json --resource-profile --apply-resource-profile 2>"$stderr_file"
    )"
    status=$?
    set -e
    write_output_artifact "resource_profile_partial_failure" "json" "$output"

    [[ "$status" -ne 0 ]] || return 1
    jq -e '
      .mode == "error" and
      .status == "fail" and
      .partial_apply_possible == true and
      (.remediation | length) >= 3 and
      (.actions[] | select(contains("failed")))
    ' <<<"$output" >/dev/null || return 1
    [[ -x "$root/bin/acfs-scope" ]] || return 1
    jq -e '.mode != "applied" and .status != "pass"' "$root/profile.json" >/dev/null || return 1

    pass "resource_profile_partial_failure_reports_error"
}

test_resource_profile_no_systemd_writes_safe_fallback_wrappers() {
    local root fake_bin output log_file wrapper_output
    root="$ARTIFACT_DIR/resource-no-systemd-home"
    fake_bin="$(make_resource_profile_failing_systemd_bin resource-no-systemd)"
    log_file="$ARTIFACT_DIR/resource-no-systemd-systemd-run.log"

    output="$(
        ACFS_RESOURCE_PROFILE_HOME="$root" \
        ACFS_CAPACITY_SYSTEMD_RUN_AVAILABLE=false \
        ACFS_CAPACITY_SYSTEMD_USER_AVAILABLE=false \
        bash "$CAPACITY_SH" --json --resource-profile --apply-resource-profile
    )"
    write_output_artifact "resource_profile_no_systemd" "json" "$output"

    jq -e '
      .mode == "applied" and
      .systemd.systemd_run_available == false and
      .systemd.user_manager_available == false and
      .safety.limited_to_acfs_owned_files == true and
      ([.classes[].properties[] | select(startswith("MemoryMax="))] | length) == 0
    ' <<<"$output" >/dev/null || return 1
    grep -Fq 'exec "$@"' "$root/bin/acfs-scope" || return 1
    ! grep -R -E "pkill|killall|loginctl[[:space:]]+kill|systemctl[[:space:]]+--user[[:space:]]+stop" "$root/bin" >/dev/null 2>&1 || return 1

    wrapper_output="$(
        ACFS_FAKE_SYSTEMD_RUN_LOG="$log_file" \
        PATH="$fake_bin:$root/bin:/usr/bin:/bin" \
        "$root/bin/acfs-scope" support -- printf 'fallback-ok'
    )"
    [[ "$wrapper_output" == "fallback-ok" ]] || return 1
    [[ ! -s "$log_file" ]] || return 1

    pass "resource_profile_no_systemd_writes_safe_fallback_wrappers"
}

test_resource_profile_disable_writes_marker_without_deleting_wrappers() {
    local root fake_bin output
    root="$ARTIFACT_DIR/resource-disable-home"
    fake_bin="$(make_resource_profile_fake_bin resource-disable)"

    ACFS_RESOURCE_PROFILE_HOME="$root" \
    ACFS_CAPACITY_BIN_DIR="$fake_bin" \
    bash "$CAPACITY_SH" --json --resource-profile --apply-resource-profile >/dev/null

    output="$(
        ACFS_RESOURCE_PROFILE_HOME="$root" \
        ACFS_CAPACITY_BIN_DIR="$fake_bin" \
        bash "$CAPACITY_SH" --json --resource-profile --disable-resource-profile
    )"
    write_output_artifact "resource_profile_disable" "json" "$output"

    jq -e '.mode == "disabled"' <<<"$output" >/dev/null || return 1
    jq -e '.mode == "disabled"' "$root/profile.json" >/dev/null || return 1
    grep -Fq "resource profile disabled" "$root/acfs-resource-profile.sh" || return 1
    [[ -x "$root/bin/acfs-scope" ]] || return 1

    pass "resource_profile_disable_writes_marker_without_deleting_wrappers"
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
        echo "jq is required for capacity tests" >&2
        exit 1
    }

    run_test test_high_capacity_json
    run_test test_profile_warns_above_recommended
    run_test test_small_host_fails_oversized_profile
    run_test test_heavy_workload_capacity
    run_test test_low_disk_fails_capacity
    run_test test_invalid_workload_exits_2
    run_test test_human_output
    run_test test_resource_profile_dry_run_json_is_read_only
    run_test test_resource_profile_apply_writes_opt_in_wrappers
    run_test test_resource_profile_apply_is_idempotent
    run_test test_resource_profile_partial_failure_reports_error
    run_test test_resource_profile_no_systemd_writes_safe_fallback_wrappers
    run_test test_resource_profile_disable_writes_marker_without_deleting_wrappers

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
