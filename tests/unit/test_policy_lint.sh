#!/usr/bin/env bash
# ============================================================
# Unit tests for ACFS guidance/template policy lint
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POLICY_LINT_SH="$REPO_ROOT/scripts/lib/policy_lint.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_POLICY_LINT_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-policy-lint-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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

write_fixture() {
    local path="$1"
    local body="$2"

    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$body" > "$path"
}

assert_policy_present() {
    local json_file="$1"
    local policy_id="$2"

    jq -e --arg policy_id "$policy_id" '.violations[] | select(.policy_id == $policy_id)' "$json_file" >/dev/null
}

assert_policy_in_human_output() {
    local human_file="$1"
    local policy_id="$2"

    grep -Fq "$policy_id" "$human_file"
}

test_valid_agents_policy_passes() {
    local fixture="$ARTIFACT_DIR/valid/AGENTS.md"
    local output="$ARTIFACT_DIR/valid.json"
    local human_output="$ARTIFACT_DIR/valid.human"

    write_fixture "$fixture" '# AGENTS.md

Use `main` for all work. The legacy mirror uses `git push origin main:master`.

Never run `rm -rf`, `git reset --hard`, or `git clean -fd`.
Use Bun for JavaScript workflows. Never use npm, yarn, or pnpm.
Use `bv --robot-triage` or `br ready --json`; bare `bv` opens the TUI and should be avoided.
Use `rch exec -- cargo test` for Rust test runs.
Before editing, reserve files with Agent Mail using `file_reservation_paths`.
'

    bash "$POLICY_LINT_SH" --json --file "$fixture" > "$output" || return 1
    jq -e '.status == "pass" and .summary.violations == 0 and .summary.files_scanned == 1' "$output" >/dev/null || return 1
    bash "$POLICY_LINT_SH" --file "$fixture" > "$human_output" || return 1
    grep -Fq "PASS: ACFS policy lint" "$human_output" || return 1

    pass "valid_agents_policy_passes"
}

test_detects_stale_master_guidance() {
    local fixture="$ARTIFACT_DIR/master/README.md"
    local output="$ARTIFACT_DIR/master.json"

    write_fixture "$fixture" '# Setup

The default branch is master.
Run `git push origin master` after committing.
'

    if bash "$POLICY_LINT_SH" --json --file "$fixture" > "$output"; then
        return 1
    fi
    assert_policy_present "$output" "branch.main_not_master" || return 1

    pass "detects_stale_master_guidance"
}

test_detects_destructive_cleanup_example() {
    local fixture="$ARTIFACT_DIR/destructive/README.md"
    local output="$ARTIFACT_DIR/destructive.json"

    write_fixture "$fixture" '# Cleanup

After tests, run `rm -rf /tmp/acfs-build-output`.
'

    if bash "$POLICY_LINT_SH" --json --file "$fixture" > "$output"; then
        return 1
    fi
    assert_policy_present "$output" "filesystem.no_destructive_cleanup" || return 1

    pass "detects_destructive_cleanup_example"
}

test_detects_js_package_manager_drift() {
    local fixture="$ARTIFACT_DIR/package-manager/README.md"
    local output="$ARTIFACT_DIR/package-manager.json"

    write_fixture "$fixture" '# Web

Run `npm install` and then `yarn test`.
'

    if bash "$POLICY_LINT_SH" --json --file "$fixture" > "$output"; then
        return 1
    fi
    assert_policy_present "$output" "toolchain.bun_only" || return 1

    pass "detects_js_package_manager_drift"
}

test_detects_bare_bv_example() {
    local fixture="$ARTIFACT_DIR/bv/README.md"
    local output="$ARTIFACT_DIR/bv.json"

    write_fixture "$fixture" '# Issues

```bash
bv
```
'

    if bash "$POLICY_LINT_SH" --json --file "$fixture" > "$output"; then
        return 1
    fi
    assert_policy_present "$output" "beads.robot_bv_only" || return 1

    pass "detects_bare_bv_example"
}

test_detects_local_cpu_heavy_cargo_example() {
    local fixture="$ARTIFACT_DIR/cargo/README.md"
    local output="$ARTIFACT_DIR/cargo.json"

    write_fixture "$fixture" '# Rust

Run `cargo test --all-targets` before committing.
'

    if bash "$POLICY_LINT_SH" --json --file "$fixture" > "$output"; then
        return 1
    fi
    assert_policy_present "$output" "builds.rch_for_cpu_heavy" || return 1

    pass "detects_local_cpu_heavy_cargo_example"
}

test_detects_missing_agent_mail_reservation_guidance() {
    local fixture="$ARTIFACT_DIR/missing-mail/AGENTS.md"
    local output="$ARTIFACT_DIR/missing-mail.json"

    write_fixture "$fixture" '# AGENTS.md

Agents should edit code carefully.
Use `main`, Bun, and `bv --robot-triage`.
'

    if bash "$POLICY_LINT_SH" --json --file "$fixture" > "$output"; then
        return 1
    fi
    assert_policy_present "$output" "coordination.agent_mail_reservation" || return 1

    pass "detects_missing_agent_mail_reservation_guidance"
}

test_policy_matrix_reports_expected_policy_ids() {
    local fixture="$ARTIFACT_DIR/matrix/AGENTS.md"
    local output="$ARTIFACT_DIR/matrix.json"
    local human_output="$ARTIFACT_DIR/matrix.human"
    local policy_id=""

    write_fixture "$fixture" '# AGENTS.md

Agents should edit code carefully before editing files.
The default branch is master.
Run `rm -rf /tmp/acfs-build-output` after experiments.
Use `npm install` before website checks.
```bash
bv
cargo test --all-targets
```
'

    if bash "$POLICY_LINT_SH" --json --file "$fixture" > "$output"; then
        return 1
    fi
    if bash "$POLICY_LINT_SH" --file "$fixture" > "$human_output"; then
        return 1
    fi

    for policy_id in \
        "branch.main_not_master" \
        "filesystem.no_destructive_cleanup" \
        "toolchain.bun_only" \
        "beads.robot_bv_only" \
        "builds.rch_for_cpu_heavy" \
        "coordination.agent_mail_reservation"
    do
        assert_policy_present "$output" "$policy_id" || return 1
        assert_policy_in_human_output "$human_output" "$policy_id" || return 1
    done

    jq -e '
      .status == "fail" and
      .summary.files_scanned == 1 and
      ([.violations[].policy_id] | unique | length) == 6
    ' "$output" >/dev/null || return 1

    pass "policy_matrix_reports_expected_policy_ids"
}

run_test() {
    local name="$1"

    if "$name"; then
        return 0
    fi

    fail "$name" "see $ARTIFACT_DIR for fixtures and outputs"
}

main() {
    run_test test_valid_agents_policy_passes
    run_test test_detects_stale_master_guidance
    run_test test_detects_destructive_cleanup_example
    run_test test_detects_js_package_manager_drift
    run_test test_detects_bare_bv_example
    run_test test_detects_local_cpu_heavy_cargo_example
    run_test test_detects_missing_agent_mail_reservation_guidance
    run_test test_policy_matrix_reports_expected_policy_ids

    echo ""
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
