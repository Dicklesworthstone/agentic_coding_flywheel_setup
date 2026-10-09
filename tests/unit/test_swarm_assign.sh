#!/usr/bin/env bash
# ============================================================
# Unit tests for acfs swarm assignment planner
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SWARM_ASSIGN_SH="$REPO_ROOT/scripts/lib/swarm_assign.sh"

TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_SWARM_ASSIGN_TEST_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-swarm-assign-test-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

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

triage_fixture() {
    write_fixture triage <<'JSON'
{
  "triage": {
    "recommendations": [
      {"id": "bd-impl", "score": 0.30, "unblocks": 2, "blocked_by": [], "action": "Start work on this issue"},
      {"id": "bd-review", "score": 0.20, "unblocks": 0, "blocked_by": [], "action": "Start review"},
      {"id": "bd-test", "score": 0.15, "unblocks": 1, "blocked_by": [], "action": "Add tests"},
      {"id": "bd-docs", "score": 0.10, "unblocks": 0, "blocked_by": [], "action": "Write docs"}
    ]
  }
}
JSON
}

empty_ready_fixture() {
    write_fixture empty_ready <<'JSON'
[]
JSON
}

single_ready_fixture() {
    write_fixture single_ready <<'JSON'
[
  {"id":"bd-impl","title":"Implement swarm planner core","status":"open","priority":1,"issue_type":"feature","estimated_minutes":90,"labels":["swarm","coordination"]}
]
JSON
}

many_ready_fixture() {
    write_fixture many_ready <<'JSON'
[
  {"id":"bd-impl","title":"Implement swarm planner core","status":"open","priority":1,"issue_type":"feature","estimated_minutes":90,"labels":["swarm","coordination"],"description":"Do not leak /home/alice/private or ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn from descriptions."},
  {"id":"bd-review","title":"Audit launch planner regression","status":"open","priority":1,"issue_type":"bug","estimated_minutes":45,"labels":["quality","review","bug"]},
  {"id":"bd-test","title":"Add planner fixture tests","status":"open","priority":2,"issue_type":"task","estimated_minutes":60,"labels":["tests","swarm"]},
  {"id":"bd-docs","title":"Document swarm assignment workflow","status":"open","priority":2,"issue_type":"task","estimated_minutes":30,"labels":["docs","swarm"]}
]
JSON
}

blocked_ready_fixture() {
    write_fixture blocked_ready <<'JSON'
[
  {"id":"bd-open","title":"Ready implementation","status":"open","priority":2,"issue_type":"feature","labels":["swarm"]},
  {"id":"bd-blocked","title":"Blocked implementation","status":"open","priority":0,"issue_type":"feature","labels":["swarm"],"blocked":true},
  {"id":"bd-waiting","title":"Waiting on dependency","status":"open","priority":0,"issue_type":"feature","labels":["swarm"],"blocked_by":["bd-parent"]},
  {"id":"bd-progress","title":"Already claimed","status":"in_progress","priority":0,"issue_type":"feature","labels":["swarm"]}
]
JSON
}

ready_without_labels_fixture() {
    write_fixture ready_without_labels <<'JSON'
[
  {"id":"bd-0g01c","title":"Add capacity calibration from rehearsal and build telemetry","status":"open","priority":2,"issue_type":"feature","estimated_minutes":150}
]
JSON
}

run_assign_json() {
    local name="$1"
    shift
    local output status

    set +e
    output="$(bash "$SWARM_ASSIGN_SH" --json "$@" 2>&1)"
    status=$?
    set -e

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output.json"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
}

test_empty_ready_set() {
    local ready output
    ready="$(empty_ready_fixture)"
    output="$(run_assign_json empty --ready-file "$ready" --agents 3 --profile balanced)"

    jq -e '
      .summary.ready_count == 0 and
      .summary.assigned_count == 0 and
      .summary.idle_count == 3 and
      .advisory_only == true and
      .mutations.claims_reservations == false
    ' <<< "$output" >/dev/null || return 1

    pass "empty_ready_set"
}

test_more_agents_than_beads() {
    local ready output
    ready="$(single_ready_fixture)"
    output="$(run_assign_json more_agents --ready-file "$ready" --agents 3 --profile balanced)"

    jq -e '
      .summary.assigned_count == 1 and
      .summary.idle_count == 2 and
      .assignments[0].bead_id == "bd-impl" and
      .assignments[0].agent_mail_thread_id == "bd-impl" and
      (.assignments[0].reservation_surfaces | index("scripts/lib/swarm_*.sh"))
    ' <<< "$output" >/dev/null || return 1

    pass "more_agents_than_beads"
}

test_more_beads_than_agents() {
    local ready triage output
    ready="$(many_ready_fixture)"
    triage="$(triage_fixture)"
    output="$(run_assign_json more_beads --ready-file "$ready" --triage-file "$triage" --agents 2 --profile balanced)"

    jq -e '
      .summary.assigned_count == 2 and
      .summary.unassigned_ready_count == 2 and
      (.assignments[] | select(.bead_id == "bd-impl" and .dependency_position.unblocks == 2))
    ' <<< "$output" >/dev/null || return 1
    ! grep -Fq "/home/alice/private" <<< "$output" || return 1
    ! grep -Fq "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn" <<< "$output" || return 1

    pass "more_beads_than_agents"
}

test_mixed_labels_match_roles() {
    local ready triage output
    ready="$(many_ready_fixture)"
    triage="$(triage_fixture)"
    output="$(run_assign_json mixed --ready-file "$ready" --triage-file "$triage" --roles implementation,review,testing,docs)"

    jq -e '
      .summary.assigned_count == 4 and
      (.assignments[] | select(.role == "implementation" and .bead_id == "bd-impl")) and
      (.assignments[] | select(.role == "review" and .bead_id == "bd-review")) and
      (.assignments[] | select(.role == "testing" and .bead_id == "bd-test")) and
      (.assignments[] | select(.role == "documentation" and .bead_id == "bd-docs"))
    ' <<< "$output" >/dev/null || return 1

    pass "mixed_labels_match_roles"
}

test_blocked_issues_excluded() {
    local ready output
    ready="$(blocked_ready_fixture)"
    output="$(run_assign_json blocked --ready-file "$ready" --roles implementation:3)"

    jq -e '
      .summary.ready_count == 1 and
      .summary.assigned_count == 1 and
      .summary.excluded_count == 3 and
      .assignments[0].bead_id == "bd-open" and
      ([.assignments[].bead_id] | index("bd-blocked") | not) and
      ([.assignments[].bead_id] | index("bd-waiting") | not) and
      ([.assignments[].bead_id] | index("bd-progress") | not)
    ' <<< "$output" >/dev/null || return 1

    pass "blocked_issues_excluded"
}

test_triage_metadata_enriches_ready_payload() {
    local ready triage output
    ready="$(ready_without_labels_fixture)"
    triage="$(write_fixture triage_labels <<'JSON'
{
  "triage": {
    "recommendations": [
      {"id":"bd-0g01c","title":"Add capacity calibration from rehearsal and build telemetry","type":"feature","priority":2,"labels":["capacity","performance","rch","swarm"],"score":0.50,"unblocks":1}
    ]
  }
}
JSON
)"
    output="$(run_assign_json triage_labels --ready-file "$ready" --triage-file "$triage" --agents 1)"

    jq -e '
      .assignments[0].labels == ["capacity","performance","rch","swarm"] and
      (.assignments[0].reservation_surfaces | index("scripts/lib/capacity.sh")) and
      .assignments[0].dependency_position.unblocks == 1
    ' <<< "$output" >/dev/null || return 1

    pass "triage_metadata_enriches_ready_payload"
}

# bv writes "labels": null (and may write "blocked_by": null) for unlabeled
# beads; that is real bv output, not invalid input.
test_null_triage_arrays_are_accepted() {
    local ready triage output
    ready="$(ready_without_labels_fixture)"
    triage="$(write_fixture triage_null_labels <<'JSON'
{
  "triage": {
    "recommendations": [
      {"id":"bd-0g01c","title":"Unlabeled bead","type":"task","priority":2,"labels":null,"blocked_by":null,"score":0.40,"unblocks":0}
    ]
  }
}
JSON
)"
    output="$(run_assign_json triage_null_labels --ready-file "$ready" --triage-file "$triage" --agents 1)"
    [[ "$(cat "$ARTIFACT_DIR/triage_null_labels.exit")" == 0 ]] || return 1
    jq -e '.assignments | length == 1' <<< "$output" >/dev/null || return 1

    pass "null_triage_arrays_are_accepted"
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
        echo "jq is required for swarm assignment tests" >&2
        exit 1
    }

    run_test test_empty_ready_set
    run_test test_more_agents_than_beads
    run_test test_more_beads_than_agents
    run_test test_mixed_labels_match_roles
    run_test test_blocked_issues_excluded
    run_test test_triage_metadata_enriches_ready_payload
    run_test test_null_triage_arrays_are_accepted

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
