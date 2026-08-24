#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs swarm inventory
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWARM_INV_SH="$REPO_ROOT/scripts/lib/swarm_inventory.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_SWARM_INV_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-swarm-inventory-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

mkdir -p "$ARTIFACT_DIR"

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
    [[ -n "${2:-}" ]] && echo "  Reason: $2"
    return 0
}

write_fixture() {
    local name="$1"
    local path="$ARTIFACT_DIR/$name.json"
    cat > "$path"
    printf '%s\n' "$path"
}

sample_inventory_fixture() {
    write_fixture sample_inventory <<'JSON'
{
  "schema_version": 1,
  "updated_at": "2026-05-08T00:00:00Z",
  "defaults": {
    "workload": "standard",
    "stale_after_hours": 24,
    "support_bundle_detail": "redacted"
  },
  "fleet_note": "benign unknown top-level field",
  "hosts": [
    {
      "id": "local",
      "display_name": "Local ACFS host",
      "role": "swarm-controller",
      "status": "active",
      "manual_tags": ["primary", "ntm"],
      "last_probe_at": "2099-01-01T00:00:00Z",
      "probe_source": "manual",
      "resources": {"cpu_count": 64, "mem_total_mib": 262144, "disk_available_mib": 524288},
      "capacity": {"workload": "standard", "recommended_agents": 25, "safe_agents": 44, "source": "acfs capacity --json --recommend-ntm"},
      "rch": {"worker": false, "controller": true, "workers_total": 8, "workers_healthy": 8},
      "ntm": {"can_launch": true, "preferred_labels": ["swarm-25"]},
      "ru": {"can_sync_repos": true},
      "notes": "operator note",
      "rack": "a1"
    },
    {
      "id": "rch-worker-a",
      "display_name": "RCH worker A",
      "role": "rch-worker",
      "status": "active",
      "last_probe_at": "2099-01-01T00:00:00Z",
      "resources": {"cpu_count": 32, "mem_total_mib": 131072, "disk_available_mib": 262144},
      "capacity": {"workload": "heavy", "recommended_agents": 0, "safe_agents": 0, "source": "reserved for RCH"},
      "rch": {"worker": true, "controller": false, "slots_total": 12, "slots_available": 10},
      "ntm": {"can_launch": false, "preferred_labels": []},
      "ru": {"can_sync_repos": false}
    },
    {
      "id": "disabled-staging",
      "display_name": "Disabled staging host",
      "role": "disabled",
      "status": "disabled",
      "last_probe_at": null,
      "resources": {},
      "capacity": {"recommended_agents": 20, "safe_agents": 30},
      "rch": {},
      "ntm": {"can_launch": false},
      "ru": {"can_sync_repos": false}
    }
  ]
}
JSON
}

empty_inventory_fixture() {
    write_fixture empty_inventory <<'JSON'
{
  "schema_version": 1,
  "updated_at": "2026-05-08T00:00:00Z",
  "defaults": {"workload": "standard", "stale_after_hours": 24},
  "hosts": []
}
JSON
}

sensitive_inventory_fixture() {
    write_fixture sensitive_inventory <<'JSON'
{
  "schema_version": 1,
  "updated_at": "2026-05-08T00:00:00Z",
  "defaults": {"workload": "standard", "stale_after_hours": 24},
  "hosts": [
    {
      "id": "local",
      "hostname": "secret.internal",
      "sshUser": "ubuntu",
      "sshUsername": "ubuntu",
      "providerId": "provider-secret",
      "provider_account_id": "acct-secret",
      "role": "swarm-controller",
      "status": "active",
      "last_probe_at": null,
      "resources": {},
      "capacity": {},
      "rch": {},
      "ntm": {},
      "ru": {}
    }
  ]
}
JSON
}

duplicate_inventory_fixture() {
    write_fixture duplicate_inventory <<'JSON'
{
  "schema_version": 1,
  "updated_at": "2026-05-08T00:00:00Z",
  "defaults": {"workload": "standard", "stale_after_hours": 24},
  "hosts": [
    {"id":"local","role":"swarm-controller","status":"active","last_probe_at":null,"resources":{},"capacity":{},"rch":{},"ntm":{},"ru":{}},
    {"id":"local","role":"swarm-worker","status":"active","last_probe_at":null,"resources":{},"capacity":{},"rch":{},"ntm":{},"ru":{}}
  ]
}
JSON
}

stale_inventory_fixture() {
    write_fixture stale_inventory <<'JSON'
{
  "schema_version": 1,
  "updated_at": "2026-05-08T00:00:00Z",
  "defaults": {"workload": "standard", "stale_after_hours": 24},
  "hosts": [
    {
      "id": "old-controller",
      "role": "swarm-controller",
      "status": "active",
      "last_probe_at": "2000-01-01T00:00:00Z",
      "resources": {},
      "capacity": {"recommended_agents": 25, "safe_agents": 44},
      "rch": {},
      "ntm": {"can_launch": true},
      "ru": {}
    }
  ]
}
JSON
}

role_boundary_inventory_fixture() {
    write_fixture role_boundary_inventory <<'JSON'
{
  "schema_version": 1,
  "updated_at": "2026-05-08T00:00:00Z",
  "defaults": {"workload": "standard", "stale_after_hours": 24},
  "hosts": [
    {
      "id": "support-host",
      "role": "support",
      "status": "active",
      "last_probe_at": "2099-01-01T00:00:00Z",
      "resources": {},
      "capacity": {"recommended_agents": 4, "safe_agents": 6},
      "rch": {},
      "ntm": {"can_launch": true},
      "ru": {}
    },
    {
      "id": "rch-worker-b",
      "role": "rch-worker",
      "status": "active",
      "last_probe_at": "2099-01-01T00:00:00Z",
      "resources": {},
      "capacity": {"recommended_agents": 99, "safe_agents": 120},
      "rch": {"worker": true},
      "ntm": {"can_launch": true},
      "ru": {}
    },
    {
      "id": "disabled-but-active-status",
      "role": "disabled",
      "status": "active",
      "last_probe_at": "2099-01-01T00:00:00Z",
      "resources": {},
      "capacity": {"recommended_agents": 30, "safe_agents": 40},
      "rch": {},
      "ntm": {"can_launch": true},
      "ru": {}
    }
  ]
}
JSON
}

invalid_stale_hours_fixture() {
    local name="$1"
    local stale_hours_json="$2"
    write_fixture "$name" <<JSON
{
  "schema_version": 1,
  "updated_at": "2026-05-08T00:00:00Z",
  "defaults": {"workload": "standard", "stale_after_hours": $stale_hours_json},
  "hosts": []
}
JSON
}

invalid_structure_fixture() {
    write_fixture invalid_structure <<'JSON'
{
  "schema_version": 1,
  "defaults": {"stale_after_hours": 24},
  "hosts": [42]
}
JSON
}

run_inventory_json() {
    local name="$1"
    shift
    local output status

    set +e
    output="$(bash "$SWARM_INV_SH" --json "$@" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output.json"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

test_report_summarizes_launch_targets() {
    local inventory output
    inventory="$(sample_inventory_fixture)"
    output="$(run_inventory_json report report --inventory "$inventory")"
    [[ "$(cat "$ARTIFACT_DIR/report.exit")" -eq 0 ]] || return 1

    jq -e '
      .status == "pass" and
      .summary.hosts_total == 3 and
      .summary.active == 2 and
      .summary.disabled == 1 and
      .summary.rch_workers == 1 and
      .summary.recommended_agents_total == 25 and
      .summary.safe_agents_total == 44 and
      .summary.unknown_field_count == 2 and
      (.recommended_launch_targets | length == 1) and
      .recommended_launch_targets[0].id == "local"
    ' <<< "$output" >/dev/null || return 1

    pass "report_summarizes_launch_targets"
}

test_empty_inventory_warns_without_failing_validation() {
    local inventory output
    inventory="$(empty_inventory_fixture)"
    output="$(run_inventory_json empty report --inventory "$inventory")"
    [[ "$(cat "$ARTIFACT_DIR/empty.exit")" -eq 1 ]] || return 1

    jq -e '
      .status == "warn" and
      .summary.hosts_total == 0 and
      (.warnings[0] | contains("inventory has no hosts")) and
      (.next_commands | index("acfs swarm inventory import --input hosts.inventory.json"))
    ' <<< "$output" >/dev/null || return 1

    pass "empty_inventory_warns_without_failing_validation"
}

test_stale_probes_warn_and_block_launch_targets() {
    local inventory output
    inventory="$(stale_inventory_fixture)"
    output="$(run_inventory_json stale report --inventory "$inventory")"
    [[ "$(cat "$ARTIFACT_DIR/stale.exit")" -eq 1 ]] || return 1

    jq -e '
      .status == "warn" and
      .summary.hosts_total == 1 and
      .summary.stale_probe_count == 1 and
      .summary.recommended_agents_total == 0 and
      .summary.safe_agents_total == 0 and
      (.recommended_launch_targets | length == 0) and
      (.warnings[] | contains("old-controller") and contains("stale probe"))
    ' <<< "$output" >/dev/null || return 1

    pass "stale_probes_warn_and_block_launch_targets"
}

test_role_boundaries_exclude_rch_worker_and_disabled_hosts() {
    local inventory output
    inventory="$(role_boundary_inventory_fixture)"
    output="$(run_inventory_json role-boundaries report --inventory "$inventory")"
    [[ "$(cat "$ARTIFACT_DIR/role-boundaries.exit")" -eq 0 ]] || return 1

    jq -e '
      .status == "pass" and
      .summary.hosts_total == 3 and
      .summary.active == 3 and
      .summary.disabled == 1 and
      .summary.rch_workers == 1 and
      .summary.recommended_agents_total == 4 and
      .summary.safe_agents_total == 6 and
      .role_counts.support == 1 and
      .role_counts["rch-worker"] == 1 and
      .role_counts.disabled == 1 and
      (.recommended_launch_targets | length == 1) and
      .recommended_launch_targets[0].id == "support-host"
    ' <<< "$output" >/dev/null || return 1

    pass "role_boundaries_exclude_rch_worker_and_disabled_hosts"
}

test_import_export_preserve_unknown_fields() {
    local inventory imported exported output
    inventory="$(sample_inventory_fixture)"
    imported="$ARTIFACT_DIR/imported/hosts.inventory.json"
    exported="$ARTIFACT_DIR/exported.inventory.json"

    output="$(run_inventory_json import import --input "$inventory" --output "$imported")"
    [[ "$(cat "$ARTIFACT_DIR/import.exit")" -eq 0 ]] || return 1
    jq -e '.status == "pass" and .summary.imported_hosts == 3 and .summary.unknown_field_count == 2' <<< "$output" >/dev/null || return 1
    jq -e '.fleet_note == "benign unknown top-level field" and .hosts[0].rack == "a1"' "$imported" >/dev/null || return 1

    output="$(run_inventory_json export export --inventory "$imported" --output "$exported")"
    [[ "$(cat "$ARTIFACT_DIR/export.exit")" -eq 0 ]] || return 1
    jq -e '.status == "pass" and .summary.exported_hosts == 3 and .summary.unknown_field_count == 2' <<< "$output" >/dev/null || return 1
    jq -e '.fleet_note == "benign unknown top-level field" and .hosts[0].rack == "a1"' "$exported" >/dev/null || return 1

    pass "import_export_preserve_unknown_fields"
}

test_import_replaces_destination_atomically() {
    local inventory imported inode_before inode_after output
    inventory="$(sample_inventory_fixture)"
    imported="$ARTIFACT_DIR/atomic.inventory.json"
    printf '%s\n' '{"sentinel":"old"}' > "$imported"
    inode_before="$(ls -di "$imported")"
    inode_before="${inode_before%%[[:space:]]*}"

    output="$(run_inventory_json atomic-import import --input "$inventory" --output "$imported")"
    [[ "$(cat "$ARTIFACT_DIR/atomic-import.exit")" -eq 0 ]] || return 1
    jq -e '.status == "pass" and .summary.imported_hosts == 3' <<< "$output" >/dev/null || return 1

    inode_after="$(ls -di "$imported")"
    inode_after="${inode_after%%[[:space:]]*}"
    [[ -n "$inode_before" && -n "$inode_after" && "$inode_before" != "$inode_after" ]] || return 1
    jq -e '.schema_version == 1 and (.hosts | length) == 3' "$imported" >/dev/null || return 1

    pass "import_replaces_destination_atomically"
}

test_durable_write_uses_narrow_gnu_sync_with_portable_fallback() {
    local helper_body atomic_body
    helper_body="$(sed -n '/^swarm_inventory_sync_path()/,/^}/p' "$SWARM_INV_SH")"
    atomic_body="$(sed -n '/^swarm_inventory_atomic_write()/,/^}/p' "$SWARM_INV_SH")"

    [[ "$helper_body" == *'"$sync_bin" --version'* ]] || return 1
    [[ "$helper_body" == *'"$sync_bin" "$path"'* ]] || return 1
    grep -Fxq '        "$sync_bin"' <<< "$helper_body" || return 1
    [[ "$atomic_body" == *'swarm_inventory_sync_path "$sync_bin" "$temp_file"'* ]] || return 1
    [[ "$atomic_body" == *'swarm_inventory_sync_path "$sync_bin" "$parent_dir"'* ]] || return 1

    pass "durable_write_uses_narrow_gnu_sync_with_portable_fallback"
}

test_privileged_execution_uses_fixed_interpreter_and_path() {
    [[ "$(sed -n '1p' "$SWARM_INV_SH")" == '#!/bin/bash' ]] || return 1
    grep -Fq 'readonly SWARM_INV_PRIVILEGED_PATH="/usr/sbin:/usr/bin:/sbin:/bin"' "$SWARM_INV_SH" || return 1
    grep -Fq 'export PATH="$SWARM_INV_PRIVILEGED_PATH"' "$SWARM_INV_SH" || return 1

    pass "privileged_execution_uses_fixed_interpreter_and_path"
}

test_validate_rejects_invalid_stale_after_hours() {
    local case_name stale_hours_json inventory output
    while IFS='|' read -r case_name stale_hours_json; do
        inventory="$(invalid_stale_hours_fixture "invalid-stale-$case_name" "$stale_hours_json")"
        output="$(run_inventory_json "invalid-stale-$case_name" validate --inventory "$inventory")"
        [[ "$(cat "$ARTIFACT_DIR/invalid-stale-$case_name.exit")" -eq 2 ]] || return 1
        jq -e '
          .status == "fail" and
          (.errors[] | select(.code == "invalid_stale_after_hours" and .path == "defaults.stale_after_hours"))
        ' <<< "$output" >/dev/null || return 1
    done <<'CASES'
string|"24"
zero|0
fractional|1.5
CASES

    pass "validate_rejects_invalid_stale_after_hours"
}

test_validate_reports_nonobject_host_without_crashing() {
    local inventory output
    inventory="$(invalid_structure_fixture)"
    output="$(run_inventory_json invalid-structure validate --inventory "$inventory")"
    [[ "$(cat "$ARTIFACT_DIR/invalid-structure.exit")" -eq 2 ]] || return 1
    jq -e '
      .status == "fail" and
      (.errors[] | select(.code == "invalid_host" and .path == "hosts[0]"))
    ' <<< "$output" >/dev/null || return 1

    pass "validate_reports_nonobject_host_without_crashing"
}

test_validate_rejects_sensitive_fields() {
    local inventory output
    inventory="$(sensitive_inventory_fixture)"
    output="$(run_inventory_json sensitive validate --inventory "$inventory")"
    [[ "$(cat "$ARTIFACT_DIR/sensitive.exit")" -eq 2 ]] || return 1

    jq -e '
      .status == "fail" and
      (.errors[] | select(.code == "forbidden_sensitive_field" and .path == "hosts[0].hostname")) and
      (.forbidden_sensitive_field_paths | index("hosts[0].hostname")) and
      (.forbidden_sensitive_field_paths | index("hosts[0].sshUser")) and
      (.forbidden_sensitive_field_paths | index("hosts[0].sshUsername")) and
      (.forbidden_sensitive_field_paths | index("hosts[0].providerId")) and
      (.forbidden_sensitive_field_paths | index("hosts[0].provider_account_id"))
    ' <<< "$output" >/dev/null || return 1

    pass "validate_rejects_sensitive_fields"
}

test_duplicate_ids_write_validate_artifacts() {
    local inventory artifact_dir output
    inventory="$(duplicate_inventory_fixture)"
    artifact_dir="$ARTIFACT_DIR/duplicate-artifacts"
    output="$(run_inventory_json duplicate validate --inventory "$inventory" --artifact-dir "$artifact_dir")"
    [[ "$(cat "$ARTIFACT_DIR/duplicate.exit")" -eq 2 ]] || return 1

    jq -e '.status == "fail" and (.errors[] | select(.code == "duplicate_host_id"))' <<< "$output" >/dev/null || return 1
    [[ -f "$artifact_dir/swarm_inventory.validate.error.json" ]] || return 1
    [[ -f "$artifact_dir/swarm_inventory.validate.log" ]] || return 1
    jq -e '.error_code == "duplicate_host_id"' "$artifact_dir/swarm_inventory.validate.error.json" >/dev/null || return 1

    pass "duplicate_ids_write_validate_artifacts"
}

test_malformed_import_export_write_error_artifacts() {
    local inventory import_artifact_dir export_artifact_dir output
    inventory="$ARTIFACT_DIR/malformed-import-export.json"
    import_artifact_dir="$ARTIFACT_DIR/import-artifacts"
    export_artifact_dir="$ARTIFACT_DIR/export-artifacts"
    printf '{not valid json\n' > "$inventory"

    output="$(run_inventory_json malformed-import import --input "$inventory" --output "$ARTIFACT_DIR/unused-import.json" --artifact-dir "$import_artifact_dir")"
    [[ "$(cat "$ARTIFACT_DIR/malformed-import.exit")" -eq 2 ]] || return 1
    jq -e '.status == "fail" and .error_code == "malformed_json"' <<< "$output" >/dev/null || return 1
    [[ -f "$import_artifact_dir/swarm_inventory.import.error.json" ]] || return 1
    [[ -f "$import_artifact_dir/swarm_inventory.import.log" ]] || return 1
    jq -e '.operation == "import" and .error_code == "malformed_json"' "$import_artifact_dir/swarm_inventory.import.error.json" >/dev/null || return 1

    output="$(run_inventory_json malformed-export export --inventory "$inventory" --output "$ARTIFACT_DIR/unused-export.json" --artifact-dir "$export_artifact_dir")"
    [[ "$(cat "$ARTIFACT_DIR/malformed-export.exit")" -eq 2 ]] || return 1
    jq -e '.status == "fail" and .error_code == "malformed_json"' <<< "$output" >/dev/null || return 1
    [[ -f "$export_artifact_dir/swarm_inventory.export.error.json" ]] || return 1
    [[ -f "$export_artifact_dir/swarm_inventory.export.log" ]] || return 1
    jq -e '.operation == "export" and .error_code == "malformed_json"' "$export_artifact_dir/swarm_inventory.export.error.json" >/dev/null || return 1

    pass "malformed_import_export_write_error_artifacts"
}

test_malformed_report_writes_error_artifacts() {
    local inventory artifact_dir output
    inventory="$ARTIFACT_DIR/malformed.json"
    artifact_dir="$ARTIFACT_DIR/malformed-artifacts"
    printf '{not valid json\n' > "$inventory"

    output="$(run_inventory_json malformed report --inventory "$inventory" --artifact-dir "$artifact_dir")"
    [[ "$(cat "$ARTIFACT_DIR/malformed.exit")" -eq 2 ]] || return 1
    jq -e '.status == "fail" and .error_code == "malformed_json"' <<< "$output" >/dev/null || return 1
    [[ -f "$artifact_dir/swarm_inventory.report.error.json" ]] || return 1
    [[ -f "$artifact_dir/swarm_inventory.report.log" ]] || return 1

    pass "malformed_report_writes_error_artifacts"
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
        echo "jq is required for swarm inventory tests" >&2
        exit 1
    }

    run_test test_report_summarizes_launch_targets
    run_test test_empty_inventory_warns_without_failing_validation
    run_test test_stale_probes_warn_and_block_launch_targets
    run_test test_role_boundaries_exclude_rch_worker_and_disabled_hosts
    run_test test_import_export_preserve_unknown_fields
    run_test test_import_replaces_destination_atomically
    run_test test_durable_write_uses_narrow_gnu_sync_with_portable_fallback
    run_test test_privileged_execution_uses_fixed_interpreter_and_path
    run_test test_validate_rejects_invalid_stale_after_hours
    run_test test_validate_reports_nonobject_host_without_crashing
    run_test test_validate_rejects_sensitive_fields
    run_test test_duplicate_ids_write_validate_artifacts
    run_test test_malformed_import_export_write_error_artifacts
    run_test test_malformed_report_writes_error_artifacts

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
