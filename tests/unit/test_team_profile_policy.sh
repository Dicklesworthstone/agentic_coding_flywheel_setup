#!/usr/bin/env bash
# ============================================================
# Unit tests for redacted team profile policy design contract
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POLICY_DOC="$REPO_ROOT/docs/operations/team-profile-schema.md"
TESTS_PASSED=0
TESTS_FAILED=0

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

require_text() {
    local needle="$1"

    grep -Fq "$needle" "$POLICY_DOC"
}

test_policy_doc_exists() {
    [[ -s "$POLICY_DOC" ]] || return 1
    pass "policy_doc_exists"
}

test_schema_and_required_fields_are_defined() {
    require_text "acfs.team-profile.v1" || return 1
    require_text "schemaVersion" || return 1
    require_text "profileId" || return 1
    require_text "providerDefaults" || return 1
    require_text "install.modules" || return 1
    require_text "shellPreferences" || return 1
    require_text "lessonChoices" || return 1
    require_text "serviceAccounts" || return 1
    pass "schema_and_required_fields_are_defined"
}

test_secret_slots_replace_secret_values() {
    require_text "secretSlot" || return 1
    require_text "secret://acfs/team/" || return 1
    require_text '"allowSecretValues": false' || return 1
    require_text '"secretSlotsRequired": true' || return 1
    require_text "Profiles are not a credential vault" || return 1
    pass "secret_slots_replace_secret_values"
}

test_forbidden_fields_and_value_checks_are_stable() {
    require_text "Forbidden Field And Value Checks" || return 1
    require_text "team_profile_secret_material_refused" || return 1
    require_text "team_profile_forbidden_field" || return 1
    require_text "token apiKey secret password privateKey" || return 1
    require_text "PEM or OpenSSH private-key blocks" || return 1
    require_text "raw IPv4 or IPv6 addresses" || return 1
    pass "forbidden_fields_and_value_checks_are_stable"
}

test_compatibility_checks_cover_manifest_and_architecture() {
    require_text "Compatibility Checks" || return 1
    require_text "team_profile_manifest_mismatch" || return 1
    require_text "team_profile_checksums_mismatch" || return 1
    require_text "team_profile_arch_unsupported" || return 1
    require_text "team_profile_ubuntu_unsupported" || return 1
    require_text "install.modules.noDeps" || return 1
    pass "compatibility_checks_cover_manifest_and_architecture"
}

test_import_diff_is_dry_run_first() {
    require_text "Import must be dry-run first" || return 1
    require_text "safeDefaults" || return 1
    require_text "installerCommand" || return 1
    require_text "dependencyClosure" || return 1
    require_text "secretSlots" || return 1
    require_text "No-TTY mode" || return 1
    require_text "team_profile_no_tty_confirmation_required" || return 1
    pass "import_diff_is_dry_run_first"
}

test_profile_doc_has_no_literal_secret_samples() {
    ! grep -Eq 'gh[pousr]_[A-Za-z0-9_]{20,}' "$POLICY_DOC" || return 1
    ! grep -Eq 'sk-[A-Za-z0-9]{20,}' "$POLICY_DOC" || return 1
    ! grep -Eq 'BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY' "$POLICY_DOC" || return 1
    ! grep -Eq 'Bearer [A-Za-z0-9._~+/-]{20,}' "$POLICY_DOC" || return 1
    pass "profile_doc_has_no_literal_secret_samples"
}

run_all_tests() {
    local test_name=""
    local tests=(
        test_policy_doc_exists
        test_schema_and_required_fields_are_defined
        test_secret_slots_replace_secret_values
        test_forbidden_fields_and_value_checks_are_stable
        test_compatibility_checks_cover_manifest_and_architecture
        test_import_diff_is_dry_run_first
        test_profile_doc_has_no_literal_secret_samples
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

run_all_tests
