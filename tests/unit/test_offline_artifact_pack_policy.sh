#!/usr/bin/env bash
# ============================================================
# Unit tests for offline artifact pack policy design contract
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POLICY_DOC="$REPO_ROOT/docs/operations/offline-artifact-pack.md"

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

test_manifest_schema_and_layout_are_defined() {
    require_text "acfs.offline-artifact-pack.v1" || return 1
    require_text "acfs-offline-pack/" || return 1
    require_text "manifest.json" || return 1
    require_text "artifacts/" || return 1
    require_text "provenance/" || return 1
    require_text "schemaVersion" || return 1
    require_text "generatedAt" || return 1
    require_text "expiresAt" || return 1
    require_text "targets" || return 1
    require_text "modules" || return 1
    require_text "artifacts" || return 1
    pass "manifest_schema_and_layout_are_defined"
}

test_trust_policy_preserves_checksums_yaml() {
    require_text 'policy.verifiedInstallerPolicy: "must_match_checksums_yaml"' || return 1
    require_text 'Relationship To `checksums.yaml`' || return 1
    require_text "verifiedInstallerKey" || return 1
    require_text "checksumsYamlSha256" || return 1
    require_text "./scripts/lib/security.sh --update-checksums" || return 1
    require_text "no upstream script runs unless" || return 1
    pass "trust_policy_preserves_checksums_yaml"
}

test_bundling_policies_cover_live_and_prohibited_modules() {
    require_text '`bundled`' || return 1
    require_text '`metadata_only`' || return 1
    require_text '`live_required`' || return 1
    require_text '`prohibited`' || return 1
    require_text "OAuth/device-login steps" || return 1
    require_text "provider VPS creation" || return 1
    require_text "SSH private keys" || return 1
    pass "bundling_policies_cover_live_and_prohibited_modules"
}

test_compatibility_and_failure_codes_are_stable() {
    require_text "pack_expired" || return 1
    require_text "pack_arch_unsupported" || return 1
    require_text "pack_ubuntu_unsupported" || return 1
    require_text "pack_hash_mismatch" || return 1
    require_text "pack_checksums_mismatch" || return 1
    require_text "pack_live_auth_required" || return 1
    require_text "pack_provider_interaction_required" || return 1
    pass "compatibility_and_failure_codes_are_stable"
}

test_builder_and_consumer_requirements_are_actionable() {
    require_text "Builder Requirements" || return 1
    require_text "Consumer Requirements" || return 1
    require_text 'generate `manifest.json` deterministically' || return 1
    require_text "verify the pack before reading any executable artifact" || return 1
    require_text "refuse live fallback" || return 1
    require_text 'keep normal `checksums.yaml` verification enabled' || return 1
    pass "builder_and_consumer_requirements_are_actionable"
}

test_redaction_rules_refuse_secret_material() {
    require_text "Support And Redaction" || return 1
    require_text "private keys" || return 1
    require_text "provider tokens" || return 1
    require_text "raw hostnames" || return 1
    require_text "raw IP addresses" || return 1
    require_text "pack_secret_material_refused" || return 1
    pass "redaction_rules_refuse_secret_material"
}

run_all_tests() {
    local test_name=""
    local tests=(
        test_policy_doc_exists
        test_manifest_schema_and_layout_are_defined
        test_trust_policy_preserves_checksums_yaml
        test_bundling_policies_cover_live_and_prohibited_modules
        test_compatibility_and_failure_codes_are_stable
        test_builder_and_consumer_requirements_are_actionable
        test_redaction_rules_refuse_secret_material
    )

    for test_name in "${tests[@]}"; do
        if ! "$test_name"; then
            fail "$test_name" "Policy doc missing required contract text"
        fi
    done

    echo ""
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"

    [[ "$TESTS_FAILED" -eq 0 ]]
}

run_all_tests "$@"
