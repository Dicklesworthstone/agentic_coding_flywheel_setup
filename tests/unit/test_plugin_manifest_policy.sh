#!/usr/bin/env bash
# ============================================================
# Unit tests for plugin manifest policy design contract
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POLICY_DOC="$REPO_ROOT/docs/operations/plugin-manifest-contract.md"

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
    [[ -n "${2:-}" ]] && echo "  Reason: $2"
}

require_text() {
    local needle="$1"

    grep -Fq "$needle" "$POLICY_DOC"
}

test_policy_doc_exists() {
    [[ -s "$POLICY_DOC" ]] || return 1
    pass "policy_doc_exists"
}

test_schema_and_required_fields_are_defined() {
    require_text "acfs.plugin-package.v1" || return 1
    require_text "schemaVersion" || return 1
    require_text "packageId" || return 1
    require_text "independently trusted digest" || return 1
    require_text "capabilities.allowed" || return 1
    require_text "capabilities.reviewRequired" || return 1
    require_text "capabilities.disallowed" || return 1
    require_text "modules[]" || return 1
    pass "schema_and_required_fields_are_defined"
}

test_declarative_install_kinds_are_bounded() {
    require_text "Install Kinds" || return 1
    require_text '`verified_installer`' || return 1
    require_text '`release_artifact`' || return 1
    require_text '`copy_asset`' || return 1
    require_text '`manual_step`' || return 1
    require_text "Raw shell arrays" || return 1
    require_text '`fallback_url` is forbidden' || return 1
    pass "declarative_install_kinds_are_bounded"
}

test_trust_policy_preserves_first_party_boundaries() {
    require_text "Module ID And Merge Rules" || return 1
    require_text "plugin.<package_slug>.<module_name>" || return 1
    require_text "must not reuse any first-party ACFS module ID" || return 1
    require_text "generated function collision" || return 1
    require_text "cannot alter first-party module fields" || return 1
    require_text "scripts/generated/*" || return 1
    pass "trust_policy_preserves_first_party_boundaries"
}

test_checksums_yaml_remains_trust_root() {
    require_text 'Relationship To `checksums.yaml`' || return 1
    require_text "verified_installer.tool" || return 1
    require_text "verified_installer.url" || return 1
    require_text "./scripts/lib/security.sh --update-checksums" || return 1
    require_text "plugin_verified_installer_checksum_required" || return 1
    pass "checksums_yaml_remains_trust_root"
}

test_review_required_and_disallowed_behavior_are_explicit() {
    require_text "Review-Required Capabilities" || return 1
    require_text "root_run_as" || return 1
    require_text "systemd_user_service" || return 1
    require_text "cross-plugin dependencies" || return 1
    require_text "Disallowed Behavior" || return 1
    require_text "plugin_disallowed_behavior" || return 1
    require_text "arbitrary shell" || return 1
    pass "review_required_and_disallowed_behavior_are_explicit"
}

test_module_selection_and_offline_pack_compatibility_are_defined() {
    require_text "Compatibility With Module Selection" || return 1
    require_text "Required first-party modules stay locked" || return 1
    require_text "Dependency closure" || return 1
    require_text "Compatibility With Offline Packs" || return 1
    require_text "plugin_offline_policy_incompatible" || return 1
    require_text '`metadata_only`, `live_required`, or `prohibited`' || return 1
    pass "module_selection_and_offline_pack_compatibility_are_defined"
}

test_forbidden_fields_and_error_codes_are_stable() {
    require_text "Forbidden Field And Value Checks" || return 1
    require_text "token apiKey api_key secret password" || return 1
    require_text "PEM or OpenSSH private-key blocks" || return 1
    require_text "plugin_secret_material_refused" || return 1
    require_text "plugin_module_collision" || return 1
    require_text "plugin_generated_function_collision" || return 1
    require_text "plugin_review_required" || return 1
    pass "forbidden_fields_and_error_codes_are_stable"
}

test_policy_doc_has_no_literal_secret_samples() {
    ! grep -Eq 'gh[pousr]_[A-Za-z0-9_]{20,}' "$POLICY_DOC" || return 1
    ! grep -Eq 'sk-[A-Za-z0-9]{20,}' "$POLICY_DOC" || return 1
    ! grep -Eq 'BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY' "$POLICY_DOC" || return 1
    ! grep -Eq 'Bearer [A-Za-z0-9._~+/-]{20,}' "$POLICY_DOC" || return 1
    pass "policy_doc_has_no_literal_secret_samples"
}

run_all_tests() {
    local test_name=""
    local tests=(
        test_policy_doc_exists
        test_schema_and_required_fields_are_defined
        test_declarative_install_kinds_are_bounded
        test_trust_policy_preserves_first_party_boundaries
        test_checksums_yaml_remains_trust_root
        test_review_required_and_disallowed_behavior_are_explicit
        test_module_selection_and_offline_pack_compatibility_are_defined
        test_forbidden_fields_and_error_codes_are_stable
        test_policy_doc_has_no_literal_secret_samples
    )

    for test_name in "${tests[@]}"; do
        if ! "$test_name"; then
            fail "$test_name" "Policy doc missing required contract text or contains forbidden samples"
        fi
    done

    echo ""
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"

    [[ "$TESTS_FAILED" -eq 0 ]]
}

run_all_tests "$@"
