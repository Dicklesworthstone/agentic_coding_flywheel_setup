#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs swarm convergence audit
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWARM_CONVERGENCE_SH="$REPO_ROOT/scripts/lib/swarm_convergence.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_SWARM_CONVERGENCE_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-swarm-convergence-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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
}

write_fixture() {
    local name="$1"
    local path="$ARTIFACT_DIR/$name.json"
    cat > "$path"
    printf '%s\n' "$path"
}

complete_epic_fixture() {
    write_fixture complete_epic <<'JSON'
[
  {
    "id": "bd-epic",
    "title": "EPIC: Swarm operations",
    "description": "## Success criteria\n- Capacity report recommends agent counts.\n- Swarm status view works from local state.",
    "status": "open",
    "dependencies": [
      {"id": "bd-capacity", "title": "Add capacity report", "status": "closed", "dependency_type": "blocks"},
      {"id": "bd-status", "title": "Add swarm status view", "status": "closed", "dependency_type": "blocks"}
    ]
  }
]
JSON
}

complete_issues_fixture() {
    write_fixture complete_issues <<'JSON'
[
  {"id":"bd-capacity","title":"Add capacity report","status":"closed","close_reason":"Implemented capacity report with tests and fixture artifacts.","labels":["capacity","tests"],"comments":[{"text":"Verification: tests passed and artifact logs captured."}]},
  {"id":"bd-status","title":"Add swarm status view","status":"closed","close_reason":"Implemented local swarm status JSON and dashboard evidence.","labels":["swarm","observability"],"comments":[{"text":"Evidence: dashboard and unit tests passed."}]}
]
JSON
}

complete_commits_fixture() {
    write_fixture complete_commits <<'JSON'
[
  {"hash":"abc123","subject":"feat(capacity): close bd-capacity with fixture artifacts"},
  {"hash":"def456","subject":"feat(swarm): close bd-status local state view"}
]
JSON
}

partial_epic_fixture() {
    write_fixture partial_epic <<'JSON'
{
  "id": "bd-epic",
  "title": "EPIC: Partial",
  "success_criteria": [
    "Capacity report recommends agent counts.",
    "Launch profiles prove 10/25/50-agent workflows.",
    "Support bundles include convergence evidence."
  ],
  "status": "open",
  "dependencies": [
    {"id": "bd-capacity", "title": "Add capacity report", "status": "closed", "dependency_type": "blocks"},
    {"id": "bd-launch", "title": "Design launch profile outline", "status": "open", "dependency_type": "blocks"}
  ]
}
JSON
}

partial_issues_fixture() {
    write_fixture partial_issues <<'JSON'
[
  {"id":"bd-capacity","title":"Add capacity report","status":"closed","close_reason":"Implemented capacity report with tests.","labels":["capacity"]},
  {"id":"bd-launch","title":"Design launch profile outline","status":"open","description":"Launch profile sketch without proof yet.","labels":["swarm"]}
]
JSON
}

overbroad_epic_fixture() {
    write_fixture overbroad_epic <<'JSON'
{
  "id": "bd-epic",
  "title": "EPIC: Over broad",
  "description": "## Success criteria\n- RCH policy routes CPU-heavy build commands.",
  "dependencies": [
    {"id":"bd-rch","title":"Add RCH policy tests","status":"closed","dependency_type":"blocks"},
    {"id":"bd-unrelated","title":"Redesign billing page","status":"closed","dependency_type":"blocks"}
  ]
}
JSON
}

overbroad_issues_fixture() {
    write_fixture overbroad_issues <<'JSON'
[
  {"id":"bd-rch","title":"Add RCH policy tests","status":"closed","close_reason":"RCH policy tests passed with CI evidence.","labels":["rch","tests"]},
  {"id":"bd-unrelated","title":"Redesign billing page","status":"closed","close_reason":"Unrelated website work.","labels":["billing"]}
]
JSON
}

run_convergence_json() {
    local name="$1"
    shift
    local output status

    set +e
    output="$(bash "$SWARM_CONVERGENCE_SH" --json "$@" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output.json"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

test_complete_epic_reports_satisfied() {
    local epic issues commits output
    epic="$(complete_epic_fixture)"
    issues="$(complete_issues_fixture)"
    commits="$(complete_commits_fixture)"
    output="$(run_convergence_json complete --epic-file "$epic" --issues-file "$issues" --commits-file "$commits")"

    jq -e '
      .summary.criteria_total == 2 and
      .summary.satisfied == 2 and
      .summary.missing == 0 and
      .advisory_only == true and
      .mutations.creates_beads == false
    ' <<< "$output" >/dev/null || return 1

    pass "complete_epic_reports_satisfied"
}

test_partial_epic_reports_weak_and_missing() {
    local epic issues output
    epic="$(partial_epic_fixture)"
    issues="$(partial_issues_fixture)"
    output="$(run_convergence_json partial --epic-file "$epic" --issues-file "$issues" --commits-file <(printf '[]\n'))"

    jq -e '
      .summary.criteria_total == 3 and
      .summary.satisfied == 1 and
      .summary.weakly_verified == 1 and
      .summary.missing == 1 and
      any(.suggested_bead_titles[]; contains("Support bundles include convergence evidence"))
    ' <<< "$output" >/dev/null || return 1

    pass "partial_epic_reports_weak_and_missing"
}

test_over_broad_epic_graph_is_reported() {
    local epic issues output
    epic="$(overbroad_epic_fixture)"
    issues="$(overbroad_issues_fixture)"
    output="$(run_convergence_json overbroad --epic-file "$epic" --issues-file "$issues" --commits-file <(printf '[]\n'))"

    jq -e '
      .summary.satisfied == 1 and
      .summary.over_broad_children == 1 and
      .over_broad_children[0].bead_id == "bd-unrelated"
    ' <<< "$output" >/dev/null || return 1

    pass "over_broad_epic_graph_is_reported"
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
        echo "jq is required for swarm convergence tests" >&2
        exit 1
    }

    run_test test_complete_epic_reports_satisfied
    run_test test_partial_epic_reports_weak_and_missing
    run_test test_over_broad_epic_graph_is_reported

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
