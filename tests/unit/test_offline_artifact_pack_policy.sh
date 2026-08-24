#!/usr/bin/env bash
# ============================================================
# Unit tests for the verified installer entrypoint-cache policy contract
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POLICY_DOC="$REPO_ROOT/docs/operations/offline-artifact-pack.md"
CURRENT_POLICY="$(
    awk '
        /^<!-- CURRENT-CONTRACT:BEGIN -->$/ { in_contract = 1; next }
        /^<!-- CURRENT-CONTRACT:END -->$/ { in_contract = 0; found_end = 1; next }
        in_contract { print }
        END { if (!found_end) exit 1 }
    ' "$POLICY_DOC"
)"

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
    grep -Fq -- "$needle" <<<"$CURRENT_POLICY"
}

forbid_text() {
    local needle="$1"
    ! grep -Fq -- "$needle" <<<"$CURRENT_POLICY"
}

require_doc_text() {
    local needle="$1"
    grep -Fq -- "$needle" "$POLICY_DOC"
}

test_authoritative_contract_is_bounded() {
    [[ -s "$POLICY_DOC" ]] || return 1
    [[ -n "$CURRENT_POLICY" ]] || return 1
    require_doc_text '<!-- CURRENT-CONTRACT:BEGIN -->' || return 1
    require_doc_text '<!-- CURRENT-CONTRACT:END -->' || return 1
    pass "authoritative_contract_is_bounded"
}

test_public_interface_is_entrypoint_cache_only() {
    require_text "acfs installer-cache build" || return 1
    require_text "--verified-installer-cache" || return 1
    require_text "ACFS_VERIFIED_INSTALLER_CACHE" || return 1
    require_text "acfs-installer-cache/" || return 1
    forbid_text "acfs offline-pack build" || return 1
    forbid_text "--offline-pack" || return 1
    forbid_text "ACFS_OFFLINE_PACK" || return 1
    pass "public_interface_is_entrypoint_cache_only"
}

test_capability_boundary_requires_network() {
    require_text "not an offline or air-gapped installation bundle" || return 1
    require_text '"executionNetworkMode": "required"' || return 1
    require_text '"transitiveClosure": "not_bundled"' || return 1
    require_text '"bootstrap": "not_bundled"' || return 1
    require_text "still needs network access for normal installer execution" || return 1
    require_text "no live entrypoint fallback" || return 1
    pass "capability_boundary_requires_network"
}

test_manifest_schema_and_layout_are_current() {
    require_text "acfs.verified-installer-entrypoint-cache.v1" || return 1
    require_text '"generatedBy": "acfs installer-cache build"' || return 1
    require_text '"packMode": "entrypoint-cache"' || return 1
    require_text '"packScope": "verified_installer_entrypoints"' || return 1
    require_text "manifest.json" || return 1
    require_text "checksums.yaml" || return 1
    require_text "acfs.manifest.yaml" || return 1
    require_text "artifacts/" || return 1
    require_text "provenance/" || return 1
    forbid_text "acfs.offline-artifact-pack.v1" || return 1
    forbid_text "acfs-offline-pack/" || return 1
    pass "manifest_schema_and_layout_are_current"
}

test_trust_root_and_target_binding_are_explicit() {
    require_text '"verifiedInstallerPolicy": "must_match_checksums_yaml"' || return 1
    require_text '`checksums.yaml` remains the canonical trust boundary' || return 1
    require_text 'packed and currently installed `checksums.yaml`' || return 1
    require_text 'packed and currently installed `acfs.manifest.yaml`' || return 1
    require_text 'Both bounded provenance files' || return 1
    require_text 'exact match with the target host' || return 1
    require_text '`x86_64` or `aarch64`' || return 1
    require_text '16 MiB' || return 1
    pass "trust_root_and_target_binding_are_explicit"
}

test_builder_publication_and_diagnostics_are_fail_closed() {
    require_text 'private, same-parent staging directory' || return 1
    require_text '`manifest.json` last as the acceptance marker' || return 1
    require_text 'no-clobber' || return 1
    require_text 'refuses a non-empty output directory' || return 1
    require_text '`--best-effort` is diagnostic only' || return 1
    require_text '`packMode: "diagnostic"`' || return 1
    require_text 'empty `failures` array' || return 1
    pass "builder_publication_and_diagnostics_are_fail_closed"
}

test_compatibility_and_failure_codes_are_stable() {
    require_text 'pack_missing_manifest' || return 1
    require_text 'pack_malformed_manifest' || return 1
    require_text 'pack_schema_unsupported' || return 1
    require_text 'pack_expired' || return 1
    require_text 'pack_arch_unsupported' || return 1
    require_text 'pack_ubuntu_unsupported' || return 1
    require_text 'pack_path_escape' || return 1
    require_text 'pack_hash_mismatch' || return 1
    require_text 'pack_checksums_mismatch' || return 1
    require_text 'pack_unbundled_required_module' || return 1
    pass "compatibility_and_failure_codes_are_stable"
}

test_refusal_proof_is_non_vacuous() {
    require_text 'zero live entrypoint fetches' || return 1
    require_text 'empty executable stdout' || return 1
    require_text 'mutation-sensitive refusals' || return 1
    require_text 'A network-enabled test cannot' || return 1
    pass "refusal_proof_is_non_vacuous"
}

test_true_offline_is_explicit_future_work() {
    require_text "Future True-Offline Work" || return 1
    require_text "resolved transitive artifact graph" || return 1
    require_text "closed-world inventory" || return 1
    require_text "secret scanning" || return 1
    require_text "outbound networking denied" || return 1
    require_text "mutation-sensitive end-to-end install" || return 1
    require_doc_text "Historical full-offline proposal (superseded" || return 1
    require_doc_text "not current behavior or a public CLI contract" || return 1
    pass "true_offline_is_explicit_future_work"
}

run_all_tests() {
    local test_name=""
    local tests=(
        test_authoritative_contract_is_bounded
        test_public_interface_is_entrypoint_cache_only
        test_capability_boundary_requires_network
        test_manifest_schema_and_layout_are_current
        test_trust_root_and_target_binding_are_explicit
        test_builder_publication_and_diagnostics_are_fail_closed
        test_compatibility_and_failure_codes_are_stable
        test_refusal_proof_is_non_vacuous
        test_true_offline_is_explicit_future_work
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
