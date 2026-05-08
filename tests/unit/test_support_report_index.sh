#!/usr/bin/env bash
# ============================================================
# Unit tests for support-bundle redacted report index
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPPORT_SH="$REPO_ROOT/scripts/lib/support.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_SUPPORT_REPORT_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-support-report-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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

log_step() { :; }
log_section() { :; }
log_detail() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { :; }

# shellcheck source=../../scripts/lib/support.sh
source "$SUPPORT_SH"

new_bundle() {
    local name="$1"
    local bundle_dir="$ARTIFACT_DIR/$name"
    mkdir -p "$bundle_dir"
    printf '%s\n' "$bundle_dir"
}

write_file() {
    local bundle_dir="$1"
    local relative_path="$2"
    local body="$3"
    mkdir -p "$(dirname "$bundle_dir/$relative_path")"
    printf '%s\n' "$body" > "$bundle_dir/$relative_path"
    record_bundle_file "$relative_path"
}

assert_contains() {
    local file="$1"
    local expected="$2"
    grep -Fq "$expected" "$file"
}

assert_not_contains() {
    local file="$1"
    local unexpected="$2"
    ! grep -Fq "$unexpected" "$file"
}

render_report() {
    local bundle_dir="$1"
    REDACT=true
    write_manifest "$bundle_dir"
    write_support_report_index "$bundle_dir"
    write_manifest "$bundle_dir"
}

test_full_bundle_report_links_present_files_only() {
    local bundle_dir report_file
    bundle_dir="$(new_bundle full)"
    report_file="$bundle_dir/support-report.md"
    BUNDLE_FILES=()
    REDACTION_COUNT=2

    write_file "$bundle_dir" "swarm_status.json" '{"schema_version":1,"status":"warn","warnings":["private path /home/alice/project and token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn were redacted"]}'
    write_file "$bundle_dir" "swarm_timeline.json" '{"schema_version":1,"status":"warn","probes":[{"id":"rch","status":"warn","reason":"queue pressure"}]}'
    write_file "$bundle_dir" "provenance.json" '{"schema_version":1,"status":"pass","summary":{"total":3}}'
    write_file "$bundle_dir" "resource_profile.json" '{"schema_version":1,"status":"pass","mode":"dry-run","redaction":{"paths_redacted":true,"raw_paths_collected":false}}'
    write_file "$bundle_dir" "checkpoint_summary.json" '{"schema_version":1,"status":"warn","severity":"stale_checkpoint","redaction":{"raw_values_collected":false,"raw_paths_collected":false}}'
    write_file "$bundle_dir" "versions.json" '{"bash":"5.2"}'
    write_file "$bundle_dir" "environment.json" '{"shell":"zsh"}'
    write_file "$bundle_dir" "summary.json" '{"schema_version":1,"status":"pass"}'
    write_file "$bundle_dir" "scenario_2/mock_rehearsal.json" '{"enabled":true,"status":"pass"}'

    render_report "$bundle_dir"

    [[ -f "$report_file" ]] || return 1
    assert_contains "$report_file" "[swarm_status.json](swarm_status.json)" || return 1
    assert_contains "$report_file" "[swarm_timeline.json](swarm_timeline.json)" || return 1
    assert_contains "$report_file" "[provenance.json](provenance.json)" || return 1
    assert_contains "$report_file" "[resource_profile.json](resource_profile.json)" || return 1
    assert_contains "$report_file" "[checkpoint_summary.json](checkpoint_summary.json)" || return 1
    assert_contains "$report_file" "[summary.json](summary.json)" || return 1
    assert_contains "$report_file" "[scenario_2/mock_rehearsal.json](scenario_2/mock_rehearsal.json)" || return 1
    assert_not_contains "$report_file" "[doctor.json](doctor.json)" || return 1
    assert_not_contains "$report_file" "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" || return 1
    assert_not_contains "$report_file" "/home/alice/project" || return 1
    jq -e '.files | index("support-report.md")' "$bundle_dir/manifest.json" >/dev/null || return 1
    jq -e '.diagnostics.checkpoint_summary.included == true and .diagnostics.checkpoint_summary.summary.status == "warn"' "$bundle_dir/manifest.json" >/dev/null || return 1

    pass "full_bundle_report_links_present_files_only"
}

test_minimal_bundle_handles_missing_optional_artifacts() {
    local bundle_dir report_file
    bundle_dir="$(new_bundle minimal)"
    report_file="$bundle_dir/support-report.md"
    BUNDLE_FILES=()
    REDACTION_COUNT=0

    write_file "$bundle_dir" "state.json" '{"status":"ok"}'
    render_report "$bundle_dir"

    [[ -f "$report_file" ]] || return 1
    assert_contains "$report_file" "ACFS Support Bundle Report" || return 1
    assert_contains "$report_file" "[state.json](state.json)" || return 1
    assert_not_contains "$report_file" "[swarm_status.json](swarm_status.json)" || return 1

    pass "minimal_bundle_handles_missing_optional_artifacts"
}

test_malformed_optional_json_is_labeled_degraded() {
    local bundle_dir report_file
    bundle_dir="$(new_bundle malformed)"
    report_file="$bundle_dir/support-report.md"
    BUNDLE_FILES=()
    REDACTION_COUNT=0

    write_file "$bundle_dir" "swarm_status.json" '{"schema_version":1,"status":'
    render_report "$bundle_dir"

    assert_contains "$report_file" "[swarm_status.json](swarm_status.json)" || return 1
    assert_contains "$report_file" "malformed" || return 1

    pass "malformed_optional_json_is_labeled_degraded"
}

test_unknown_sensitive_fields_fail_closed() {
    local bundle_dir report_file
    bundle_dir="$(new_bundle sensitive)"
    report_file="$bundle_dir/support-report.md"
    BUNDLE_FILES=()
    REDACTION_COUNT=1

    write_file "$bundle_dir" "custom_diagnostics.json" '{"schema_version":1,"custom_token":"ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn","home_path":"/home/alice/private","safe_metric":7}'
    render_report "$bundle_dir"

    assert_contains "$report_file" "Sensitive Field Review" || return 1
    assert_contains "$report_file" "custom_diagnostics.json" || return 1
    assert_contains "$report_file" "custom_token" || return 1
    assert_contains "$report_file" "home_path" || return 1
    assert_not_contains "$report_file" "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" || return 1
    assert_not_contains "$report_file" "/home/alice/private" || return 1

    pass "unknown_sensitive_fields_fail_closed"
}

test_manifest_redaction_proof_sanitizes_bad_sources() {
    local bundle_dir manifest
    bundle_dir="$(new_bundle proof)"
    manifest="$bundle_dir/manifest.json"
    BUNDLE_FILES=()
    REDACTION_COUNT=0

    write_file "$bundle_dir" "doctor.json" '{"status":'
    write_file "$bundle_dir" "swarm_inventory.json" '{"schema_version":1,"status":"pass","inventory":{"present":true,"raw_hosts_collected":false},"summary":{"hosts_total":2},"redaction":{"paths_redacted":true,"raw_hosts_collected":false},"host":"prod-controller.example.com","path":"/home/alice/private","token":"ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn"}'
    write_file "$bundle_dir" "environment.json" '{"status":"pass","hostname":"prod.example.com","home":"/home/alice","acfs_home":"/home/alice/.acfs"}'
    write_file "$bundle_dir" "provenance.json" '{"status":"pass","token":"ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn"}'
    chmod 000 "$bundle_dir/provenance.json"

    write_manifest "$bundle_dir"
    chmod 600 "$bundle_dir/provenance.json"

    jq -e '
      .diagnostics.doctor.source.malformed == true and
      .diagnostics.doctor.source_status == "malformed" and
      .diagnostics.provenance.source.malformed == true and
      .diagnostics.provenance.source_status == "malformed" and
      .diagnostics.swarm_inventory.included == true and
      .diagnostics.swarm_inventory.records.raw_count == 2 and
      .diagnostics.swarm_inventory.records.sanitized_count == 2 and
      .diagnostics.swarm_inventory.records.raw_values_collected == false and
      .diagnostics.swarm_inventory.raw_hosts_collected == false and
      (.diagnostics.swarm_inventory.redaction.categories | index("token_like_notes")) and
      .diagnostics.environment.redaction.raw_values_collected == false
    ' "$manifest" >/dev/null || return 1

    assert_not_contains "$manifest" "prod-controller.example.com" || return 1
    assert_not_contains "$manifest" "/home/alice/private" || return 1
    assert_not_contains "$manifest" "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" || return 1

    pass "manifest_redaction_proof_sanitizes_bad_sources"
}

test_manifest_redaction_proof_absent_sources_are_count_only() {
    local bundle_dir manifest
    bundle_dir="$(new_bundle absent-proof)"
    manifest="$bundle_dir/manifest.json"
    BUNDLE_FILES=()
    REDACTION_COUNT=0

    write_manifest "$bundle_dir"

    jq -e '
      (.diagnostics | keys | length) >= 8 and
      ([.diagnostics[] | select(
        .proof_schema_version == 1 and
        .included == false and
        .source_status == "missing" and
        .records.raw_count == 0 and
        .records.sanitized_count == 0 and
        .records.raw_values_collected == false and
        .redaction.raw_values_collected == false and
        (.redaction.categories | type) == "array"
      )] | length) == (.diagnostics | keys | length) and
      (.diagnostics.swarm_timeline.redaction.categories | index("agent_mail_bodies")) and
      (.diagnostics.resource_profile.redaction.categories | index("wrapper_commands")) and
      (.diagnostics.environment.redaction.categories | index("hostnames"))
    ' "$manifest" >/dev/null || return 1

    assert_not_contains "$manifest" "/home/" || return 1
    assert_not_contains "$manifest" "ghp_" || return 1

    pass "manifest_redaction_proof_absent_sources_are_count_only"
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
        echo "jq is required for support report tests" >&2
        exit 1
    }

    run_test test_full_bundle_report_links_present_files_only
    run_test test_minimal_bundle_handles_missing_optional_artifacts
    run_test test_malformed_optional_json_is_labeled_degraded
    run_test test_unknown_sensitive_fields_fail_closed
    run_test test_manifest_redaction_proof_sanitizes_bad_sources
    run_test test_manifest_redaction_proof_absent_sources_are_count_only

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
