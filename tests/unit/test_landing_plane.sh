#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs landing-plane closeout assistant
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LANDING_PLANE_SH="$REPO_ROOT/scripts/lib/landing_plane.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_LANDING_PLANE_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-landing-plane-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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
    return 0
}

write_status_file() {
    local name="$1"
    local body="$2"
    local path="$ARTIFACT_DIR/$name.status"

    printf '%s\n' "$body" > "$path"
    printf '%s\n' "$path"
}

run_landing_json() {
    local status_file="$1"
    local in_progress_json="$2"
    local reservations_json="$3"
    local mail_sent="$4"
    local gates_passed="$5"

    env \
        ACFS_LAND_GIT_STATUS_FILE="$status_file" \
        ACFS_LAND_IN_PROGRESS_JSON="$in_progress_json" \
        ACFS_LAND_RESERVATIONS_JSON="$reservations_json" \
        ACFS_LAND_MAIL_SENT="$mail_sent" \
        ACFS_LAND_GATES_PASSED="$gates_passed" \
        ACFS_LAND_AGENT_NAME="SilentPeak" \
        ACFS_LAND_PROJECT_KEY="/data/projects/agentic_coding_flywheel_setup" \
        bash "$LANDING_PLANE_SH" --json
}

assert_no_forbidden_copy() {
    local output="$1"

    if grep -Eq '(^|[[:space:]])bv($|[[:space:]])|(^|[[:space:]])bd($|[[:space:]])|git reset|git clean|rm -rf|(^|[[:space:]])cargo (build|test|clippy)' <<<"$output"; then
        printf '%s\n' "$output" > "$ARTIFACT_DIR/forbidden-output.json"
        return 1
    fi
}

test_clean_session_passes() {
    local status_file output
    status_file="$(write_status_file clean "")"
    output="$(run_landing_json "$status_file" '{"issues":[]}' '{"active":[]}' true true)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/clean.json"

    jq -e '
      .status == "pass" and
      (.changed_files | length) == 0 and
      .quality_gates.status == "pass" and
      .beads.status == "pass" and
      .beads.sync_status == "clean" and
      .agent_mail.status == "pass" and
      .reservations.status == "pass" and
      (.next_commands | length) == 0
    ' <<<"$output" >/dev/null || return 1
    assert_no_forbidden_copy "$output" || return 1

    pass "clean_session_passes"
}

test_dirty_session_prints_exact_gates_and_staging() {
    local status_file output
    status_file="$(write_status_file dirty $' M scripts/lib/foo.sh\n?? tests/unit/test_foo.sh\n M .beads/beads.db')"
    output="$(run_landing_json "$status_file" '{"issues":[{"id":"bd-r86ef"}]}' '{"active":[]}' false false)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/dirty.json"

    jq -e '
      .status == "warn" and
      (.changed_files | index("scripts/lib/foo.sh")) != null and
      (.changed_files | index("tests/unit/test_foo.sh")) != null and
      .quality_gates.status == "warn" and
      .beads.sync_status == "needs_sync" and
      (.beads.in_progress_ids | index("bd-r86ef")) != null and
      any(.next_commands[]; startswith("shellcheck ") and contains("scripts/lib/foo.sh") and contains("tests/unit/test_foo.sh")) and
      any(.next_commands[]; . == "shellcheck install.sh scripts/**/*.sh") and
      any(.next_commands[]; startswith("ubs ")) and
      any(.next_commands[]; startswith("git add -- ")) and
      any(.next_commands[]; . == "br sync --flush-only") and
      any(.next_commands[]; contains("send_message("))
    ' <<<"$output" >/dev/null || return 1
    assert_no_forbidden_copy "$output" || return 1

    pass "dirty_session_prints_exact_gates_and_staging"
}

test_missing_gate_scenario_warns() {
    local status_file output
    status_file="$(write_status_file missing_gate ' M apps/web/app/page.tsx')"
    output="$(run_landing_json "$status_file" '{"issues":[]}' '{"active":[]}' true false)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/missing-gate.json"

    jq -e '
      .status == "warn" and
      .quality_gates.status == "warn" and
      (.quality_gates.web_files | index("apps/web/app/page.tsx")) != null and
      any(.next_commands[]; . == "cd apps/web && bun run type-check && bun run lint") and
      any(.next_commands[]; . == "cd apps/web && bun run build") and
      any(.next_commands[]; startswith("ubs "))
    ' <<<"$output" >/dev/null || return 1
    assert_no_forbidden_copy "$output" || return 1

    pass "missing_gate_scenario_warns"
}

test_active_reservations_are_called_out() {
    local status_file output
    status_file="$(write_status_file active_reservations "")"
    output="$(run_landing_json "$status_file" '{"issues":[]}' '{"active":[{"path_pattern":"scripts/lib/landing_plane.sh"},{"path_pattern":"tests/unit/test_landing_plane.sh"}]}' true true)"
    printf '%s\n' "$output" > "$ARTIFACT_DIR/active-reservations.json"

    jq -e '
      .status == "warn" and
      .reservations.status == "warn" and
      .reservations.active_count == 2 and
      (.reservations.paths | index("scripts/lib/landing_plane.sh")) != null and
      any(.next_commands[]; contains("release_file_reservations("))
    ' <<<"$output" >/dev/null || return 1
    assert_no_forbidden_copy "$output" || return 1

    pass "active_reservations_are_called_out"
}

run_test() {
    local name="$1"

    if "$name"; then
        return 0
    fi
    fail "$name"
}

main() {
    run_test test_clean_session_passes
    run_test test_dirty_session_prints_exact_gates_and_staging
    run_test test_missing_gate_scenario_warns
    run_test test_active_reservations_are_called_out

    echo ""
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo "Artifacts: $ARTIFACT_DIR"

    [[ "$TESTS_FAILED" -eq 0 ]]
}

main "$@"
