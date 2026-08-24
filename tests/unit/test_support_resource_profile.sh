#!/usr/bin/env bash
# ============================================================
# Unit tests for support-bundle sanitized evidence
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPPORT_SH="$REPO_ROOT/scripts/lib/support.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_SUPPORT_RESOURCE_PROFILE_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-support-resource-profile-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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

test_support_capture_resource_profile_sanitizes_paths() {
    local home_dir bundle_dir profile_home output token_like
    home_dir="$ARTIFACT_DIR/home"
    bundle_dir="$ARTIFACT_DIR/bundle"
    token_like="ghp_abcdefghijklmnopqrstuvwxyz1234567890ABCD"
    profile_home="$ARTIFACT_DIR/profile-$token_like"
    mkdir -p "$home_dir" "$bundle_dir"

    output="$(env \
        HOME="$home_dir" \
        ACFS_RESOURCE_PROFILE_HOME="$profile_home" \
        SUPPORT_SH="$SUPPORT_SH" \
        REPO_ROOT="$REPO_ROOT" \
        BUNDLE_DIR="$bundle_dir" \
        bash -lc '
            set -euo pipefail
            log_step() { :; }
            log_section() { :; }
            log_detail() { :; }
            log_success() { :; }
            log_warn() { :; }
            log_error() { :; }
            # shellcheck source=../../scripts/lib/support.sh
            source "$SUPPORT_SH"
            _SUPPORT_ACFS_HOME=""
            _SUPPORT_SCRIPT_DIR="$REPO_ROOT/scripts/lib"
            SUPPORT_TARGET_HOME="$HOME"
            RESOURCE_PROFILE_TIMEOUT=5
            BUNDLE_FILES=()
            capture_resource_profile_json "$BUNDLE_DIR"
            write_manifest "$BUNDLE_DIR"
            printf "%s\n" "${BUNDLE_FILES[*]}"
        ')"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/resource-profile.files"

    [[ -f "$bundle_dir/resource_profile.json" ]] || return 1
    [[ -f "$bundle_dir/manifest.json" ]] || return 1
    grep -qw "resource_profile.json" <<<"$output" || return 1

    jq -e '
      .schema_version == 1 and
      .mode == "dry-run" and
      .status == "pass" and
      .capture.status == "pass" and
      .safety.limited_to_acfs_owned_files == true and
      .redaction.paths_redacted == true and
      .redaction.raw_paths_collected == false and
      .redaction.secrets_collected == false and
      (.managed_file_count | type == "number") and
      (.wrappers[] | select(.name == "acfs-scope" and .command_present == false)) and
      (.wrappers[] | select(.name == "ccs" and .command_present == true))
    ' "$bundle_dir/resource_profile.json" >/dev/null || return 1

    ! grep -Fq "$profile_home" "$bundle_dir/resource_profile.json" || return 1
    ! grep -Fq "$token_like" "$bundle_dir/resource_profile.json" || return 1

    jq -e '
      .diagnostics.resource_profile.included == true and
      .diagnostics.resource_profile.summary.status == "pass" and
      .diagnostics.resource_profile.summary.mode == "dry-run" and
      .diagnostics.resource_profile.summary.paths_redacted == true and
      .diagnostics.resource_profile.summary.raw_paths_collected == false
    ' "$bundle_dir/manifest.json" >/dev/null || return 1
    ! grep -Fq "$profile_home" "$bundle_dir/manifest.json" || return 1
    ! grep -Fq "$token_like" "$bundle_dir/manifest.json" || return 1

    pass "support_capture_resource_profile_sanitizes_paths"
}

# Compliant inventory: no forbidden sensitive field names, so the fail-closed
# validator in swarm_inventory.sh (44c2074b) lets the report summarize it.
write_inventory_fixture() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<'JSON'
{
  "schema_version": 1,
  "updated_at": "2026-05-08T00:00:00Z",
  "defaults": {"workload": "standard", "stale_after_hours": 24},
  "hosts": [
    {
      "id": "controller-1",
      "display_name": "prod-controller.example.com",
      "role": "swarm-controller",
      "status": "active",
      "last_probe_at": "2099-01-01T00:00:00Z",
      "resources": {"cpu_count": 64, "mem_total_mib": 262144, "disk_available_mib": 524288},
      "capacity": {"workload": "standard", "recommended_agents": 25, "safe_agents": 44},
      "rch": {"worker": false, "controller": true, "workers_total": 8, "workers_healthy": 8},
      "ntm": {"can_launch": true, "preferred_labels": ["swarm-25"]},
      "ru": {"can_sync_repos": true}
    },
    {
      "id": "rch-worker-a",
      "role": "rch-worker",
      "status": "active",
      "last_probe_at": "2099-01-01T00:00:00Z",
      "resources": {},
      "capacity": {"recommended_agents": 0, "safe_agents": 0},
      "rch": {"worker": true, "controller": false},
      "ntm": {"can_launch": false},
      "ru": {"can_sync_repos": false}
    },
    {
      "id": "disabled-staging",
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

# Sensitive-laden inventory: contains forbidden field names (ssh_user,
# ssh_key_path, provider_id, public_endpoint) and secret-shaped values, so the
# validator refuses to summarize it and the capture must fail CLOSED with no
# raw values anywhere in the bundle.
write_sensitive_inventory_fixture() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path" <<'JSON'
{
  "schema_version": 1,
  "updated_at": "2026-05-08T00:00:00Z",
  "defaults": {"workload": "standard", "stale_after_hours": 24},
  "hosts": [
    {
      "id": "controller-1",
      "display_name": "prod-controller.example.com",
      "role": "swarm-controller",
      "status": "active",
      "last_probe_at": "2099-01-01T00:00:00Z",
      "resources": {"cpu_count": 64, "mem_total_mib": 262144, "disk_available_mib": 524288},
      "capacity": {"workload": "standard", "recommended_agents": 25, "safe_agents": 44},
      "rch": {"worker": false, "controller": true, "workers_total": 8, "workers_healthy": 8},
      "ntm": {"can_launch": true, "preferred_labels": ["swarm-25"]},
      "ru": {"can_sync_repos": true},
      "notes": "operator note ghp_abcdefghijklmnopqrstuvwxyz1234567890ABCD /home/alice/private",
      "ssh_user": "ubuntu",
      "ssh_key_path": "/home/alice/.ssh/id_rsa",
      "provider_id": "provider-123",
      "public_endpoint": "192.0.2.10"
    },
    {
      "id": "rch-worker-a",
      "role": "rch-worker",
      "status": "active",
      "last_probe_at": "2099-01-01T00:00:00Z",
      "resources": {},
      "capacity": {"recommended_agents": 0, "safe_agents": 0},
      "rch": {"worker": true, "controller": false},
      "ntm": {"can_launch": false},
      "ru": {"can_sync_repos": false}
    },
    {
      "id": "disabled-staging",
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

test_support_capture_swarm_inventory_redacts_raw_hosts() {
    local home_dir acfs_home bundle_dir inventory_path output
    home_dir="$ARTIFACT_DIR/inventory-home"
    acfs_home="$home_dir/.acfs"
    bundle_dir="$ARTIFACT_DIR/inventory-bundle"
    inventory_path="$acfs_home/swarm/hosts.inventory.json"
    mkdir -p "$home_dir" "$bundle_dir"
    write_inventory_fixture "$inventory_path"

    output="$(env \
        HOME="$home_dir" \
        SUPPORT_SH="$SUPPORT_SH" \
        REPO_ROOT="$REPO_ROOT" \
        BUNDLE_DIR="$bundle_dir" \
        ACFS_HOME="$acfs_home" \
        bash -lc '
            set -euo pipefail
            log_step() { :; }
            log_section() { :; }
            log_detail() { :; }
            log_success() { :; }
            log_warn() { :; }
            log_error() { :; }
            # shellcheck source=../../scripts/lib/support.sh
            source "$SUPPORT_SH"
            _SUPPORT_ACFS_HOME="$ACFS_HOME"
            _SUPPORT_SCRIPT_DIR="$REPO_ROOT/scripts/lib"
            SUPPORT_TARGET_HOME="$HOME"
            SWARM_INVENTORY_TIMEOUT=5
            BUNDLE_FILES=()
            capture_swarm_inventory_json "$BUNDLE_DIR"
            write_manifest "$BUNDLE_DIR"
            printf "%s\n" "${BUNDLE_FILES[*]}"
        ')"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/swarm-inventory.files"

    [[ -f "$bundle_dir/swarm_inventory.json" ]] || return 1
    [[ -f "$bundle_dir/manifest.json" ]] || return 1
    grep -qw "swarm_inventory.json" <<<"$output" || return 1

    jq -e '
      .schema_version == 1 and
      .status == "pass" and
      .inventory.present == true and
      .summary.hosts_total == 3 and
      .summary.active == 2 and
      .summary.disabled == 1 and
      .summary.recommended_agents_total == 25 and
      .summary.safe_agents_total == 44 and
      .summary.rch_workers == 1 and
      .role_counts["swarm-controller"] == 1 and
      .role_counts["rch-worker"] == 1 and
      .role_counts.disabled == 1 and
      .status_counts.active == 2 and
      .status_counts.disabled == 1 and
      .redaction.paths_redacted == true and
      .redaction.raw_hosts_collected == false and
      .redaction.raw_hostnames_collected == false and
      .redaction.raw_ip_addresses_collected == false and
      .redaction.ssh_users_collected == false and
      .redaction.ssh_key_paths_collected == false and
      .redaction.provider_ids_collected == false and
      .redaction.repo_paths_collected == false and
      .redaction.home_paths_collected == false and
      .redaction.token_like_notes_collected == false
    ' "$bundle_dir/swarm_inventory.json" >/dev/null || return 1

    ! grep -Eq 'prod-controller\.example\.com|192\.0\.2\.10|ubuntu|id_rsa|provider-123|/home/alice|ghp_abcdefghijklmnopqrstuvwxyz' "$bundle_dir/swarm_inventory.json" || return 1

    jq -e '
      .diagnostics.swarm_inventory.included == true and
      .diagnostics.swarm_inventory.status == "pass" and
      .diagnostics.swarm_inventory.paths_redacted == true and
      .diagnostics.swarm_inventory.raw_hosts_collected == false
    ' "$bundle_dir/manifest.json" >/dev/null || return 1
    ! grep -Eq 'prod-controller\.example\.com|192\.0\.2\.10|ubuntu|id_rsa|provider-123|/home/alice|ghp_abcdefghijklmnopqrstuvwxyz' "$bundle_dir/manifest.json" || return 1

    pass "support_capture_swarm_inventory_redacts_raw_hosts"
}

test_support_capture_swarm_inventory_fails_closed_on_sensitive_fields() {
    local home_dir acfs_home bundle_dir inventory_path
    home_dir="$ARTIFACT_DIR/sensitive-inventory-home"
    acfs_home="$home_dir/.acfs"
    bundle_dir="$ARTIFACT_DIR/sensitive-inventory-bundle"
    inventory_path="$acfs_home/swarm/hosts.inventory.json"
    mkdir -p "$home_dir" "$bundle_dir"
    write_sensitive_inventory_fixture "$inventory_path"

    env \
        HOME="$home_dir" \
        SUPPORT_SH="$SUPPORT_SH" \
        REPO_ROOT="$REPO_ROOT" \
        BUNDLE_DIR="$bundle_dir" \
        ACFS_HOME="$acfs_home" \
        bash -lc '
            set -euo pipefail
            log_step() { :; }
            log_section() { :; }
            log_detail() { :; }
            log_success() { :; }
            log_warn() { :; }
            log_error() { :; }
            # shellcheck source=../../scripts/lib/support.sh
            source "$SUPPORT_SH"
            _SUPPORT_ACFS_HOME="$ACFS_HOME"
            _SUPPORT_SCRIPT_DIR="$REPO_ROOT/scripts/lib"
            SUPPORT_TARGET_HOME="$HOME"
            SWARM_INVENTORY_TIMEOUT=5
            BUNDLE_FILES=()
            # Real bundle flow tolerates capture failure (support.sh calls
            # this with `|| true`) and still writes the manifest.
            capture_swarm_inventory_json "$BUNDLE_DIR" || true
            write_manifest "$BUNDLE_DIR"
        ' >/dev/null || return 1

    [[ -f "$bundle_dir/swarm_inventory.json" ]] || return 1
    [[ -f "$bundle_dir/manifest.json" ]] || return 1

    # The inventory validator (fail-closed since 44c2074b) refuses to
    # summarize an inventory carrying forbidden sensitive fields: status must
    # be fail, counts must stay zero, and only field PATHS may be echoed.
    jq -e '
      .schema_version == 1 and
      .status == "fail" and
      .capture.status == "fail" and
      .summary.hosts_total == 0 and
      .diagnostics.error_code == "forbidden_sensitive_field" and
      (.diagnostics.redacted_field_paths | index("hosts[0].ssh_user") != null) and
      .redaction.paths_redacted == true and
      .redaction.raw_hosts_collected == false and
      .redaction.secrets_collected == false
    ' "$bundle_dir/swarm_inventory.json" >/dev/null || return 1

    ! grep -Eq 'prod-controller\.example\.com|192\.0\.2\.10|ubuntu|id_rsa|provider-123|/home/alice|ghp_abcdefghijklmnopqrstuvwxyz' "$bundle_dir/swarm_inventory.json" || return 1

    jq -e '
      .diagnostics.swarm_inventory.included == true and
      .diagnostics.swarm_inventory.status == "fail" and
      .diagnostics.swarm_inventory.raw_hosts_collected == false
    ' "$bundle_dir/manifest.json" >/dev/null || return 1
    ! grep -Eq 'prod-controller\.example\.com|192\.0\.2\.10|ubuntu|id_rsa|provider-123|/home/alice|ghp_abcdefghijklmnopqrstuvwxyz' "$bundle_dir/manifest.json" || return 1

    pass "support_capture_swarm_inventory_fails_closed_on_sensitive_fields"
}

test_support_capture_swarm_inventory_absent_is_structured() {
    local home_dir acfs_home bundle_dir
    home_dir="$ARTIFACT_DIR/inventory-absent-home"
    acfs_home="$home_dir/.acfs"
    bundle_dir="$ARTIFACT_DIR/inventory-absent-bundle"
    mkdir -p "$acfs_home" "$bundle_dir"

    env \
        HOME="$home_dir" \
        SUPPORT_SH="$SUPPORT_SH" \
        REPO_ROOT="$REPO_ROOT" \
        BUNDLE_DIR="$bundle_dir" \
        ACFS_HOME="$acfs_home" \
        bash -lc '
            set -euo pipefail
            log_step() { :; }
            log_section() { :; }
            log_detail() { :; }
            log_success() { :; }
            log_warn() { :; }
            log_error() { :; }
            # shellcheck source=../../scripts/lib/support.sh
            source "$SUPPORT_SH"
            _SUPPORT_ACFS_HOME="$ACFS_HOME"
            _SUPPORT_SCRIPT_DIR="$REPO_ROOT/scripts/lib"
            SUPPORT_TARGET_HOME="$HOME"
            BUNDLE_FILES=()
            capture_swarm_inventory_json "$BUNDLE_DIR"
            write_manifest "$BUNDLE_DIR"
        '

    jq -e '
      .status == "skipped" and
      .inventory.present == false and
      .redaction.paths_redacted == true and
      .redaction.raw_hosts_collected == false
    ' "$bundle_dir/swarm_inventory.json" >/dev/null || return 1
    jq -e '
      .diagnostics.swarm_inventory.included == false and
      .diagnostics.swarm_inventory.status == "skipped" and
      .diagnostics.swarm_inventory.paths_redacted == true and
      .diagnostics.swarm_inventory.raw_hosts_collected == false
    ' "$bundle_dir/manifest.json" >/dev/null || return 1

    pass "support_capture_swarm_inventory_absent_is_structured"
}

test_support_capture_swarm_inventory_malformed_is_sanitized() {
    local home_dir acfs_home bundle_dir inventory_path
    home_dir="$ARTIFACT_DIR/inventory-malformed-home"
    acfs_home="$home_dir/.acfs"
    bundle_dir="$ARTIFACT_DIR/inventory-malformed-bundle"
    inventory_path="$acfs_home/swarm/hosts.inventory.json"
    mkdir -p "$(dirname "$inventory_path")" "$bundle_dir"
    printf '{not valid json in %s\n' "$inventory_path" > "$inventory_path"

    env \
        HOME="$home_dir" \
        SUPPORT_SH="$SUPPORT_SH" \
        REPO_ROOT="$REPO_ROOT" \
        BUNDLE_DIR="$bundle_dir" \
        ACFS_HOME="$acfs_home" \
        bash -lc '
            set -euo pipefail
            log_step() { :; }
            log_section() { :; }
            log_detail() { :; }
            log_success() { :; }
            log_warn() { :; }
            log_error() { :; }
            # shellcheck source=../../scripts/lib/support.sh
            source "$SUPPORT_SH"
            _SUPPORT_ACFS_HOME="$ACFS_HOME"
            _SUPPORT_SCRIPT_DIR="$REPO_ROOT/scripts/lib"
            SUPPORT_TARGET_HOME="$HOME"
            BUNDLE_FILES=()
            capture_swarm_inventory_json "$BUNDLE_DIR" || true
            write_manifest "$BUNDLE_DIR"
        '

    jq -e '
      .status == "fail" and
      .inventory.present == true and
      .inventory.path_collected == false and
      .redaction.paths_redacted == true and
      .redaction.raw_hosts_collected == false
    ' "$bundle_dir/swarm_inventory.json" >/dev/null || return 1
    ! grep -Fq "$inventory_path" "$bundle_dir/swarm_inventory.json" || return 1
    jq -e '
      .diagnostics.swarm_inventory.included == true and
      .diagnostics.swarm_inventory.status == "fail" and
      .diagnostics.swarm_inventory.paths_redacted == true and
      .diagnostics.swarm_inventory.raw_hosts_collected == false
    ' "$bundle_dir/manifest.json" >/dev/null || return 1
    ! grep -Fq "$inventory_path" "$bundle_dir/manifest.json" || return 1

    pass "support_capture_swarm_inventory_malformed_is_sanitized"
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
        echo "jq is required for support resource profile tests" >&2
        exit 1
    }

    run_test test_support_capture_resource_profile_sanitizes_paths
    run_test test_support_capture_swarm_inventory_redacts_raw_hosts
    run_test test_support_capture_swarm_inventory_fails_closed_on_sensitive_fields
    run_test test_support_capture_swarm_inventory_absent_is_structured
    run_test test_support_capture_swarm_inventory_malformed_is_sanitized

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
