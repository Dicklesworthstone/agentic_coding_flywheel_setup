#!/usr/bin/env bash
# ============================================================
# Unit tests for the RCH offload policy linter
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LINTER_SH="$REPO_ROOT/scripts/tests/lint_rch_offload_policy.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_RCH_POLICY_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-rch-policy-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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
    local body="$2"
    local path="$ARTIFACT_DIR/$name.md"

    printf '%s\n' "$body" > "$path"
    printf '%s\n' "$name.md"
}

run_linter() {
    bash "$LINTER_SH" --root "$ARTIFACT_DIR" "$@"
}

test_compliant_rch_command_passes() {
    local target output
    target="$(write_fixture compliant 'Run rch exec -- cargo test before committing.')"
    output="$(run_linter "$target")"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/compliant.out"

    grep -Fq "PASS: RCH offload policy examples are compliant." <<<"$output" || return 1

    pass "compliant_rch_command_passes"
}

test_local_cargo_command_fails_with_actionable_location() {
    local target output status
    target="$(write_fixture violation $'Before committing:\n  cargo test --workspace')"

    set +e
    output="$(run_linter "$target" 2>&1)"
    status=$?
    set -e
    printf '%s\n' "$output" > "$ARTIFACT_DIR/violation.out"

    [[ "$status" -eq 1 ]] || return 1
    grep -Fq "VIOLATION: violation.md:2: CPU-heavy Rust command must use RCH" <<<"$output" || return 1
    grep -Fq "Line:   cargo test --workspace" <<<"$output" || return 1
    grep -Fq "Fix: prefix build/test/check/clippy/run examples with 'rch exec --'." <<<"$output" || return 1

    pass "local_cargo_command_fails_with_actionable_location"
}

test_suppressed_explanatory_text_passes() {
    local target output
    target="$(write_fixture explanatory 'Worker-side examples may mention cargo test. # rch-policy: allow')"
    output="$(run_linter "$target")"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/explanatory.out"

    grep -Fq "PASS: RCH offload policy examples are compliant." <<<"$output" || return 1

    pass "suppressed_explanatory_text_passes"
}

test_non_rust_lightweight_command_passes() {
    local target output
    target="$(write_fixture non_rust 'Website checks use bun run test, not RCH.')"
    output="$(run_linter "$target")"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/non-rust.out"

    grep -Fq "PASS: RCH offload policy examples are compliant." <<<"$output" || return 1

    pass "non_rust_lightweight_command_passes"
}

test_help_documents_ci_gate_and_no_worker_requirement() {
    local output
    output="$(bash "$LINTER_SH" --help)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/help.out"

    grep -Fq "Default CI gate:" <<<"$output" || return 1
    grep -Fq "does not require the rch binary or worker fleet" <<<"$output" || return 1

    pass "help_documents_ci_gate_and_no_worker_requirement"
}

run_test() {
    local name="$1"

    if "$name"; then
        return 0
    fi
    fail "$name"
}

main() {
    run_test test_compliant_rch_command_passes
    run_test test_local_cargo_command_fails_with_actionable_location
    run_test test_suppressed_explanatory_text_passes
    run_test test_non_rust_lightweight_command_passes
    run_test test_help_documents_ci_gate_and_no_worker_requirement

    echo ""
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo "Artifacts: $ARTIFACT_DIR"

    [[ "$TESTS_FAILED" -eq 0 ]]
}

main "$@"
