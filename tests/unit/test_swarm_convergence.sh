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

    if output="$(bash "$SWARM_CONVERGENCE_SH" --json "$@" 2> "$ARTIFACT_DIR/$name.stderr")"; then
        status=0
    else
        status=$?
    fi

    printf '%s\n' "$output" > "$ARTIFACT_DIR/$name.output.json"
    printf '%s\n' "$status" > "$ARTIFACT_DIR/$name.exit"
    printf '%s\n' "$output"
    return "$status"
}

test_complete_epic_reports_satisfied() {
    local epic issues commits output
    epic="$(complete_epic_fixture)"
    issues="$(complete_issues_fixture)"
    commits="$(complete_commits_fixture)"
    output="$(run_convergence_json complete --epic-file "$epic" --issues-file "$issues" --commits-file "$commits")" || return 1

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
    output="$(run_convergence_json partial --epic-file "$epic" --issues-file "$issues" --commits-file <(printf '[]\n'))" || return 1

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
    output="$(run_convergence_json overbroad --epic-file "$epic" --issues-file "$issues" --commits-file <(printf '[]\n'))" || return 1

    jq -e '
      .summary.satisfied == 1 and
      .summary.over_broad_children == 1 and
      .over_broad_children[0].bead_id == "bd-unrelated"
    ' <<< "$output" >/dev/null || return 1

    pass "over_broad_epic_graph_is_reported"
}

test_small_report_schema_and_input_equivalence() {
    local epic issues commits expected actual format mode
    epic="$(complete_epic_fixture)"
    issues="$(complete_issues_fixture)"
    commits="$(complete_commits_fixture)"
    expected="$ARTIFACT_DIR/expected-small.json"
    # Full schema/evidence snapshot, not just the summary counts.
    cat > "$expected" <<'JSON'
{
  "schema_version":1,"status":"pass","advisory_only":true,
  "mutations":{"creates_beads":false,"updates_beads":false,"closes_beads":false,"sends_agent_mail":false},
  "epic":{"id":"bd-epic","title":"EPIC: Swarm operations","status":"open"},
  "summary":{"criteria_total":2,"satisfied":2,"weakly_verified":0,"missing":0,"child_beads":2,"over_broad_children":0},
  "criteria":[
    {"criterion":"Capacity report recommends agent counts.","status":"satisfied","evidence":[{"bead_id":"bd-capacity","title":"Add capacity report","status":"closed","match_score":1,"commit_subjects":["feat(capacity): close bd-capacity with fixture artifacts"]}],"suggested_bead_title":null},
    {"criterion":"Swarm status view works from local state.","status":"satisfied","evidence":[{"bead_id":"bd-status","title":"Add swarm status view","status":"closed","match_score":2,"commit_subjects":["feat(swarm): close bd-status local state view"]}],"suggested_bead_title":null}
  ],
  "over_broad_children":[],"suggested_bead_titles":[]
}
JSON
    jq '.[0]' "$epic" > "$ARTIFACT_DIR/epic-object.json" || return 1
    jq '{issues:.}' "$issues" > "$ARTIFACT_DIR/issues-wrapper.json" || return 1
    jq -c '.[]' "$issues" > "$ARTIFACT_DIR/issues-jsonl.json" || return 1
    jq '{issues:.}' "$commits" > "$ARTIFACT_DIR/commits-wrapper.json" || return 1
    for mode in json markdown; do
        bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$epic" --issues-file "$issues" --commits-file "$commits" \
            > "$ARTIFACT_DIR/small.$mode" || return 1
        for format in wrapper jsonl; do
            actual="$ARTIFACT_DIR/small-$format.$mode"
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$ARTIFACT_DIR/epic-object.json" \
                --issues-file "$ARTIFACT_DIR/issues-$format.json" --commits-file "$ARTIFACT_DIR/commits-wrapper.json" \
                > "$actual" || return 1
            cmp "$ARTIFACT_DIR/small.$mode" "$actual" || return 1
        done
    done
    jq -e -s 'length == 2 and .[0] == .[1]' "$expected" "$ARTIFACT_DIR/small.json" >/dev/null || return 1
    pass "small_report_schema_and_input_equivalence"
}

prepare_large_fixtures() {
    local epic issues commits
    epic="$(complete_epic_fixture)"
    issues="$(complete_issues_fixture)"
    commits="$(complete_commits_fixture)"
    # >4 MiB of issues exceeds the usual 2 MiB Linux ARG_MAX, while epic
    # and commits each exceed Linux's 128 KiB single-argument limit. Relevant
    # issues are last so an implementation cannot pass by truncating input.
    jq '.[0].description += ("\n## History\n" + ("archived " * 40000))' "$epic" \
        > "$ARTIFACT_DIR/large-epic.json" || return 1
    jq '[range(0;4096) | {id:("noise-" + tostring),title:"Unrelated history",description:("history " * 128)}] + .' "$issues" \
        > "$ARTIFACT_DIR/large-issues.json" || return 1
    jq '. + [{hash:"unrelated",subject:("archived " * 40000)}]' "$commits" \
        > "$ARTIFACT_DIR/large-commits.json" || return 1
    [[ $(wc -c < "$ARTIFACT_DIR/large-issues.json") -gt 4194304 ]] || return 1
    [[ $(wc -c < "$ARTIFACT_DIR/large-epic.json") -gt 131072 ]] || return 1
    [[ $(wc -c < "$ARTIFACT_DIR/large-commits.json") -gt 131072 ]] || return 1
}

test_large_file_inputs_are_equivalent_and_read_only() {
    local mode format
    prepare_large_fixtures || return 1
    jq -c '.[]' "$ARTIFACT_DIR/large-issues.json" > "$ARTIFACT_DIR/large-issues.jsonl" || return 1
    sha256sum "$ARTIFACT_DIR/large-epic.json" "$ARTIFACT_DIR/large-issues.json" \
        "$ARTIFACT_DIR/large-issues.jsonl" "$ARTIFACT_DIR/large-commits.json" \
        > "$ARTIFACT_DIR/large-inputs.sha256" || return 1
    for mode in json markdown; do
        for format in json jsonl; do
            bash "$SWARM_CONVERGENCE_SH" "--$mode" \
                --epic-file "$ARTIFACT_DIR/large-epic.json" \
                --issues-file "$ARTIFACT_DIR/large-issues.$format" \
                --commits-file "$ARTIFACT_DIR/large-commits.json" \
                > "$ARTIFACT_DIR/large-$format.$mode.output" 2> "$ARTIFACT_DIR/large-$format.$mode.stderr" || return 1
            cmp "$ARTIFACT_DIR/small.$mode" "$ARTIFACT_DIR/large-$format.$mode.output" || return 1
        done
    done
    sha256sum -c "$ARTIFACT_DIR/large-inputs.sha256" >/dev/null || return 1
    pass "large_file_inputs_are_equivalent_and_read_only"
}

prepare_live_tools() {
    mkdir -p "$ARTIFACT_DIR/live-bin" || return 1
    cat > "$ARTIFACT_DIR/live-bin/br" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'br %s\n' "$*" >> "$MOCK_CALLS"
case "$*" in
    'show bd-epic --json --no-auto-import --no-auto-flush') cat "$MOCK_EPIC" ;;
    'list --json --all --deferred --limit 0 --no-auto-import --no-auto-flush') cat "$MOCK_ISSUES"; exit "${MOCK_BR_LIST_EXIT:-0}" ;;
    *) echo "Unexpected or mutating br command: $*" >&2; exit 90 ;;
esac
exit "${MOCK_BR_EXIT:-0}"
SH
    cat > "$ARTIFACT_DIR/live-bin/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$*" >> "$MOCK_CALLS"
[[ "$*" == 'log --format=%H%x1f%s%x1e --all' ]] || exit 91
cat "$MOCK_GIT_LOG"
exit "${MOCK_GIT_EXIT:-0}"
SH
    chmod +x "$ARTIFACT_DIR/live-bin/br" "$ARTIFACT_DIR/live-bin/git" || return 1
    jq -j '.[] | .hash + "\u001f" + .subject + "\u001e"' "$ARTIFACT_DIR/large-commits.json" \
        > "$ARTIFACT_DIR/live-git.log" || return 1
}

test_large_live_export_and_beads_snapshot() {
    local source work calls
    prepare_live_tools || return 1
    for source in live snapshot; do
        work="$ARTIFACT_DIR/$source-work"
        calls="$ARTIFACT_DIR/$source.calls"
        : > "$calls"
        mkdir -p "$work" || return 1
        if [[ "$source" == snapshot ]]; then
            mkdir -p "$work/.beads" || return 1
            cp "$ARTIFACT_DIR/large-issues.jsonl" "$work/.beads/issues.jsonl" || return 1
        fi
        (
            cd "$work" || exit 1
            PATH="$ARTIFACT_DIR/live-bin:$PATH" MOCK_CALLS="$calls" \
                MOCK_EPIC="$ARTIFACT_DIR/large-epic.json" MOCK_ISSUES="$ARTIFACT_DIR/large-issues.json" \
                MOCK_GIT_LOG="$ARTIFACT_DIR/live-git.log" \
                bash "$SWARM_CONVERGENCE_SH" --epic bd-epic --json
        ) > "$ARTIFACT_DIR/$source.output.json" 2> "$ARTIFACT_DIR/$source.stderr" || return 1
        cmp "$ARTIFACT_DIR/small.json" "$ARTIFACT_DIR/$source.output.json" || return 1
        {
            printf 'br show bd-epic --json --no-auto-import --no-auto-flush\n'
            if [[ "$source" == live ]]; then
                printf 'br list --json --all --deferred --limit 0 --no-auto-import --no-auto-flush\n'
            fi
            printf 'git log --format=%%H%%x1f%%s%%x1e --all\n'
        } > "$ARTIFACT_DIR/$source.expected-calls"
        cmp "$ARTIFACT_DIR/$source.expected-calls" "$calls" || return 1
        if [[ "$source" == snapshot ]]; then
            cmp "$ARTIFACT_DIR/large-issues.jsonl" "$work/.beads/issues.jsonl" || return 1
        fi
    done
    pass "large_live_export_and_beads_snapshot"
}

expect_input_failure() {
    local name="$1" kind="$2"
    shift 2
    if bash "$SWARM_CONVERGENCE_SH" "$@" > "$ARTIFACT_DIR/$name.stdout" 2> "$ARTIFACT_DIR/$name.stderr"; then
        echo "Unexpected success: $name" >&2
        return 1
    fi
    [[ ! -s "$ARTIFACT_DIR/$name.stdout" ]] || return 1
    grep -qi "$kind" "$ARTIFACT_DIR/$name.stderr" || return 1
}

test_malformed_inputs_never_emit_reports() {
    local epic issues commits kind mode bad
    epic="$(complete_epic_fixture)"
    issues="$(complete_issues_fixture)"
    commits="$(complete_commits_fixture)"
    # Include a valid prefix: jq must consume/validate the entire stream.
    printf '{"id":"bd-capacity"}\n{"id":' > "$ARTIFACT_DIR/truncated.json"
    printf 'null\n' > "$ARTIFACT_DIR/null.json"
    printf '[]\n[]\n' > "$ARTIFACT_DIR/multiple.json"
    printf '[17]\n' > "$ARTIFACT_DIR/scalar-list.json"
    printf '{"issues":false,"dependencies":false}\n' > "$ARTIFACT_DIR/bad-wrapper.json"
    : > "$ARTIFACT_DIR/empty.json"
    for mode in json markdown; do
        for kind in epic issues commits; do
            for bad in truncated null multiple scalar-list bad-wrapper absent; do
                local args=("--$mode" --epic-file "$epic" --issues-file "$issues" --commits-file "$commits")
                args+=("--$kind-file" "$ARTIFACT_DIR/$bad.json")
                expect_input_failure "bad-$kind-$bad-$mode" "$kind" "${args[@]}" || return 1
            done
        done
        for kind in epic commits; do
            expect_input_failure "empty-$kind-$mode" "$kind" "--$mode" --epic-file "$epic" \
                --issues-file "$issues" --commits-file "$commits" "--$kind-file" "$ARTIFACT_DIR/empty.json" || return 1
        done
        # Valid JSON with an invalid evidence field must also fail atomically.
        printf '[{"subject":17}]\n' > "$ARTIFACT_DIR/bad-evidence.json"
        expect_input_failure "bad-evidence-$mode" 'report' "--$mode" --epic-file "$epic" \
            --issues-file "$issues" --commits-file "$ARTIFACT_DIR/bad-evidence.json" || return 1
    done
    pass "malformed_inputs_never_emit_reports"
}

test_live_collection_failures_never_emit_reports() {
    local source work
    for source in epic issues git snapshot; do
        work="$ARTIFACT_DIR/failing-$source-work"
        mkdir -p "$work" || return 1
        if [[ "$source" == snapshot ]]; then
            mkdir -p "$work/.beads" || return 1
            cp "$ARTIFACT_DIR/truncated.json" "$work/.beads/issues.jsonl" || return 1
        fi
        if (
            cd "$work" || exit 1
            export PATH="$ARTIFACT_DIR/live-bin:$PATH" MOCK_CALLS="$ARTIFACT_DIR/failing-$source.calls"
            export MOCK_EPIC="$ARTIFACT_DIR/complete_epic.json" MOCK_ISSUES="$ARTIFACT_DIR/complete_issues.json"
            export MOCK_GIT_LOG="$ARTIFACT_DIR/live-git.log"
            case "$source" in
                epic) export MOCK_BR_EXIT=23 ;;
                issues) export MOCK_BR_LIST_EXIT=25 ;;
                git) export MOCK_GIT_EXIT=24 ;;
            esac
            bash "$SWARM_CONVERGENCE_SH" --epic bd-epic --markdown
        ) > "$ARTIFACT_DIR/failing-$source.stdout" 2> "$ARTIFACT_DIR/failing-$source.stderr"; then
            return 1
        fi
        [[ ! -s "$ARTIFACT_DIR/failing-$source.stdout" && -s "$ARTIFACT_DIR/failing-$source.stderr" ]] || return 1
    done
    pass "live_collection_failures_never_emit_reports"
}

test_real_git_collection_is_read_only() {
    local work="$ARTIFACT_DIR/real-git-work" mode
    mkdir -p "$work/.beads" || return 1
    cp "$ARTIFACT_DIR/large-issues.jsonl" "$work/.beads/issues.jsonl" || return 1
    git init -q "$work" || return 1
    git -C "$work" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false \
        commit -q --allow-empty -m 'feat(capacity): close bd-capacity with fixture artifacts' || return 1
    git -C "$work" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false \
        commit -q --allow-empty -m 'feat(swarm): close bd-status local state view' || return 1
    git -C "$work" rev-parse HEAD > "$ARTIFACT_DIR/real-git-head.before" || return 1
    git -C "$work" status --porcelain > "$ARTIFACT_DIR/real-git-status.before" || return 1
    for mode in json markdown; do
        (
            cd "$work" || exit 1
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$ARTIFACT_DIR/large-epic.json"
        ) > "$ARTIFACT_DIR/real-git.$mode" 2> "$ARTIFACT_DIR/real-git.$mode.stderr" || return 1
        cmp "$ARTIFACT_DIR/small.$mode" "$ARTIFACT_DIR/real-git.$mode" || return 1
    done
    git -C "$work" rev-parse HEAD > "$ARTIFACT_DIR/real-git-head.after" || return 1
    git -C "$work" status --porcelain > "$ARTIFACT_DIR/real-git-status.after" || return 1
    cmp "$ARTIFACT_DIR/real-git-head.before" "$ARTIFACT_DIR/real-git-head.after" || return 1
    cmp "$ARTIFACT_DIR/real-git-status.before" "$ARTIFACT_DIR/real-git-status.after" || return 1
    cmp "$ARTIFACT_DIR/large-issues.jsonl" "$work/.beads/issues.jsonl" || return 1
    pass "real_git_collection_is_read_only"
}

test_empty_and_single_issue_jsonl() {
    local issues mode format
    for mode in json markdown; do
        for format in empty single; do
            issues="$ARTIFACT_DIR/$format-issue.jsonl"
            if [[ "$format" == empty ]]; then
                : > "$issues"
            else
                jq -c '.[0]' "$ARTIFACT_DIR/complete_issues.json" > "$issues" || return 1
            fi
            jq -s '.' "$issues" > "$ARTIFACT_DIR/$format-issue-array.json" || return 1
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$ARTIFACT_DIR/complete_epic.json" \
                --issues-file "$issues" --commits-file "$ARTIFACT_DIR/complete_commits.json" \
                > "$ARTIFACT_DIR/$format-issue.$mode" || return 1
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$ARTIFACT_DIR/complete_epic.json" \
                --issues-file "$ARTIFACT_DIR/$format-issue-array.json" --commits-file "$ARTIFACT_DIR/complete_commits.json" \
                > "$ARTIFACT_DIR/$format-issue-array.$mode" || return 1
            cmp "$ARTIFACT_DIR/$format-issue.$mode" "$ARTIFACT_DIR/$format-issue-array.$mode" || return 1
        done
    done
    pass "empty_and_single_issue_jsonl"
}

test_large_child_id_filters_do_not_use_argv() {
    local work="$ARTIFACT_DIR/large-children-work"
    mkdir -p "$work/.beads" || return 1
    jq -n '{id:"bd-epic",dependencies:[range(0;20000) | {id:("bd-child-" + tostring)}]}' \
        > "$ARTIFACT_DIR/large-children-epic.json" || return 1
    printf '{"id":"bd-child-19999"}\n' > "$work/.beads/issues.jsonl"
    printf 'hash\037Verify bd-child-19999\036' > "$ARTIFACT_DIR/large-children-git.log"
    (
        cd "$work" || exit 1
        export PATH="$ARTIFACT_DIR/live-bin:$PATH" MOCK_CALLS="$ARTIFACT_DIR/large-children.calls"
        export MOCK_GIT_LOG="$ARTIFACT_DIR/large-children-git.log"
        # Exercise collectors independently of the audit scoring algorithm.
        # shellcheck source=/dev/null
        source "$SWARM_CONVERGENCE_SH" --help >/dev/null
        epic_json="$(cat "$ARTIFACT_DIR/large-children-epic.json")"
        swarm_convergence_collect_issues_json "$(command -v jq)" "$epic_json" \
            > "$ARTIFACT_DIR/large-children-issues.json" || exit 1
        swarm_convergence_collect_commits_json "$(command -v jq)" "$epic_json" \
            > "$ARTIFACT_DIR/large-children-commits.json" || exit 1
    ) || return 1
    jq -e '. == [{id:"bd-child-19999"}]' "$ARTIFACT_DIR/large-children-issues.json" >/dev/null || return 1
    jq -e '. == [{hash:"hash",subject:"Verify bd-child-19999"}]' "$ARTIFACT_DIR/large-children-commits.json" >/dev/null || return 1
    pass "large_child_id_filters_do_not_use_argv"
}

test_live_collection_includes_closed_and_deferred_without_sync() {
    local work="$ARTIFACT_DIR/live-completeness" mode
    mkdir -p "$work/bin" || return 1
    cat > "$work/epic.json" <<'JSON'
{"id":"bd-epic","title":"Archive acceptance","success_criteria":["Archived checks passed.","Deferred deployment rehearsed."],"dependencies":[{"id":"bd-archived"},{"id":"bd-deferred"}]}
JSON
    # More than a historical default page, with the actual evidence at the end.
    jq -n '[range(0;80) | {id:("noise-" + tostring),status:"open",title:"Unrelated"}] + [
        {id:"bd-archived",title:"Archive",status:"closed",close_reason:"Archived checks passed with tests."},
        {id:"bd-deferred",title:"Deployment",status:"deferred",close_reason:"Deferred deployment rehearsed."}
    ]' > "$work/issues.json" || return 1
    printf '[]\n' > "$work/commits.json"
    printf 'unchanged\n' > "$work/store-state"
    cat > "$work/bin/br" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for flag in --no-auto-import --no-auto-flush; do
    if [[ " $* " != *" $flag "* ]]; then
        printf 'implicit synchronization\n' > "$MOCK_WORK/store-state"
    fi
done
case "$1" in
    show) cat "$MOCK_WORK/epic.json" ;;
    list)
        jq --arg flags " $* " '
            map(select(.status != "closed" or ($flags | contains(" --all "))))
            | map(select(.status != "deferred" or ($flags | contains(" --deferred "))))
            | . as $all
            | (if ($flags | contains(" --limit 0 ")) then . else .[:50] end)
            | {issues:.,total:($all | length),offset:0,has_more:(length < ($all | length))}
        ' "$MOCK_WORK/issues.json"
        ;;
    *) echo "Unexpected or mutating command: $*" >&2; exit 90 ;;
esac
SH
    chmod +x "$work/bin/br" || return 1
    for mode in json markdown; do
        bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" \
            --issues-file "$work/issues.json" --commits-file "$work/commits.json" \
            > "$work/expected.$mode" || return 1
        (
            cd "$work" || exit 1
            PATH="$work/bin:$PATH" MOCK_WORK="$work" bash "$SWARM_CONVERGENCE_SH" \
                --epic bd-epic "--$mode" --commits-file "$work/commits.json"
        ) > "$work/actual.$mode" 2> "$work/$mode.stderr" || return 1
        cmp "$work/expected.$mode" "$work/actual.$mode" || return 1
        [[ $(cat "$work/store-state") == unchanged ]] || return 1
    done
    jq -e '.summary.satisfied == 1 and .summary.weakly_verified == 1 and .summary.missing == 0
        and .criteria[0].evidence[0].bead_id == "bd-archived"
        and .criteria[1].evidence[0].status == "deferred"' "$work/actual.json" >/dev/null || return 1
    pass "live_collection_includes_closed_and_deferred_without_sync"
}

test_incomplete_exports_never_emit_reports() {
    local mode source metadata name work
    local epic="$ARTIFACT_DIR/complete_epic.json"
    local issues="$ARTIFACT_DIR/complete_issues.json"
    local commits="$ARTIFACT_DIR/complete_commits.json"
    local index=0
    for metadata in \
        '{has_more:true}' '{has_more:"false"}' '{has_more:null}' \
        '{offset:1}' '{offset:-1}' '{offset:"0"}' '{offset:null}' \
        '{total:3}' '{total:1}' '{total:"2"}' '{total:null}'; do
        index=$((index + 1))
        jq "{issues:.} + $metadata" "$issues" > "$ARTIFACT_DIR/incomplete-$index.json" || return 1
        for mode in json markdown; do
            for source in file live snapshot; do
                name="incomplete-$index-$mode-$source"
                work="$ARTIFACT_DIR/$name"
                mkdir -p "$work" || return 1
                if [[ "$source" == snapshot ]]; then
                    mkdir -p "$work/.beads" || return 1
                    cp "$ARTIFACT_DIR/incomplete-$index.json" "$work/.beads/issues.jsonl" || return 1
                fi
                (
                    cd "$work" || exit 1
                    export PATH="$ARTIFACT_DIR/live-bin:$PATH" MOCK_CALLS="$work/calls"
                    export MOCK_ISSUES="$ARTIFACT_DIR/incomplete-$index.json"
                    args=("--$mode" --epic-file "$epic" --commits-file "$commits")
                    if [[ "$source" == file ]]; then
                        args+=(--issues-file "$MOCK_ISSUES")
                    fi
                    expect_input_failure "$name" 'incomplete export' "${args[@]}"
                ) || return 1
            done
        done
    done
    # Complete modern envelopes and unpaginated legacy wrappers are equivalent.
    for metadata in '{total:2,offset:0,limit:0,has_more:false}' '{total:2,offset:0,limit:50,has_more:false}' '{}'; do
        jq "{issues:.} + $metadata" "$issues" > "$ARTIFACT_DIR/complete-envelope.json" || return 1
        for mode in json markdown; do
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$epic" \
                --issues-file "$ARTIFACT_DIR/complete-envelope.json" --commits-file "$commits" \
                > "$ARTIFACT_DIR/complete-envelope.output.$mode" || return 1
            cmp "$ARTIFACT_DIR/small.$mode" "$ARTIFACT_DIR/complete-envelope.output.$mode" || return 1
        done
    done
    pass "incomplete_exports_never_emit_reports"
}

test_selection_and_evidence_ordering() {
    local work="$ARTIFACT_DIR/selection" mode
    mkdir -p "$work/.beads" || return 1
    cat > "$work/epic.json" <<'JSON'
[
  {"id":"bd-epic","title":"Selection","success_criteria":["Quartz pipeline tests","Cobalt","Xenon"],"dependencies":[
    {"id":"bd-1","title":"Quartz `override`","status":"open"},
    {"issue_id":"bd-10"},
    {"depends_on_id":"bd-2"},
    {"id":"bd-10","title":"Other Quartz","status":"open"},
    {"id":"","issue_id":"bd-skip"},
    {"id":"bd-missing","title":"Cobalt placeholder"},
    {"id":"bd-unrelated","title":"Billing","status":"closed"}
  ]},
  {"id":"ignored-epic","success_criteria":["Not selected"]}
]
JSON
    cat > "$work/issues.json" <<'JSON'
[
  {"id":"bd-10","title":"Quartz pipeline","status":"closed","close_reason":"tests verified"},
  {"id":"bd-10","title":"Not first","status":"open"},
  {"id":"bd-1","title":"Not the override","status":"closed","close_reason":"tests verified"},
  {"id":"bd-2","title":"Quartz pipeline","status":"closed","close_reason":"tests verified"},
  {"id":"bd-skip","title":"Xenon","status":"closed","close_reason":"tests verified"},
  {"id":"unselected","title":"Xenon","status":"closed","close_reason":"tests verified"}
]
JSON
    cat > "$work/commits.json" <<'JSON'
[
  {"hash":"a","subject":"Quartz tests bd-10 first `proof`"},
  {"hash":"b","subject":"Quartz bd-1 second"},
  {"hash":"c","subject":"bd-1 third"},
  {"hash":"d","subject":"bd-1 fourth"},
  {"hash":"e","subject":"bd-2 proof"}
]
JSON
    jq -c '.[]' "$work/issues.json" > "$work/.beads/issues.jsonl" || return 1
    for mode in json markdown; do
        bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" \
            --issues-file "$work/issues.json" --commits-file "$work/commits.json" \
            > "$work/file.$mode" || return 1
        (
            cd "$work" || exit 1
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" --commits-file "$work/commits.json"
        ) > "$work/snapshot.$mode" || return 1
        cmp "$work/file.$mode" "$work/snapshot.$mode" || return 1
    done
    jq -e '
        .schema_version == 1 and .epic.id == "bd-epic" and .status == "warn"
        and .summary == {criteria_total:3,satisfied:1,weakly_verified:1,missing:1,child_beads:6,over_broad_children:1}
        and [.criteria[0].evidence[].bead_id] == ["bd-10","bd-2","bd-1"]
        and [.criteria[0].evidence[].match_score] == [3,3,2]
        and [.criteria[0].evidence[].status] == ["closed","closed","open"]
        and .criteria[0].evidence[0].title == "Quartz pipeline"
        and .criteria[0].evidence[2].commit_subjects == ["Quartz tests bd-10 first \u0027proof\u0027","Quartz bd-1 second","bd-1 third"]
        and .criteria[1].evidence[0].status == "unknown"
        and .over_broad_children == [{bead_id:"bd-unrelated",title:"Billing",status:"closed"}]
        and .suggested_bead_titles == ["Add evidence for epic criterion: Xenon"]
        and all(.. | objects; (has("_scores") or has("_proofy")) | not)
    ' "$work/file.json" >/dev/null || return 1
    pass "selection_and_evidence_ordering"
}

test_many_children_complete_reports() {
    local work="$ARTIFACT_DIR/many-children" mode format
    mkdir -p "$work/.beads" || return 1
    jq -n '
        ["quartz","cobalt","amber","bronze","cedar","violet","magenta","silver","copper","indigo","sienna","topaz"] as $terms
        | {id:"bd-epic",title:"Large graph",success_criteria:($terms + ["zirconium","hafnium"]),
           dependencies:([range(0;1024) | {id:("bd-leaf-" + tostring)}] + [{id:"bd-tail"},{id:"bd-unrelated",title:"Billing"}])}
    ' > "$work/epic.json" || return 1
    jq -n '
        ["quartz","cobalt","amber","bronze","cedar","violet","magenta","silver","copper","indigo","sienna","topaz"] as $terms
        | [range(0;1024) | {id:("noise-" + tostring),title:"Unrelated history"}]
          + [range(0;1024) | {id:("bd-leaf-" + tostring),title:$terms[. % 12],
              status:(if ((. / 12 | floor) % 3) == 0 then "closed" else "open" end),
              close_reason:"tests verified",description:("history " * 512)}]
          + [{id:"bd-tail",title:"zirconium",status:"closed",close_reason:"tests verified"}]
    ' > "$work/issues.json" || return 1
    printf '[]\n' > "$work/commits.json"
    [[ $(wc -c < "$work/issues.json") -gt 4194304 ]] || return 1
    jq -c '.[]' "$work/issues.json" > "$work/issues.jsonl" || return 1
    cp "$work/issues.jsonl" "$work/.beads/issues.jsonl" || return 1
    sha256sum "$work/epic.json" "$work/issues.json" "$work/issues.jsonl" "$work/.beads/issues.jsonl" \
        > "$work/inputs.sha256" || return 1
    # Exercise complete reports, not just the collectors. No timing gate: the
    # corpus must be fully audited on slower CI hosts too, never truncated.
    for mode in json markdown; do
        for format in json jsonl; do
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" \
                --issues-file "$work/issues.$format" --commits-file "$work/commits.json" \
                > "$work/$format.output.$mode" || return 1
        done
        (
            cd "$work" || exit 1
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" --commits-file "$work/commits.json"
        ) > "$work/snapshot.output.$mode" || return 1
        cmp "$work/json.output.$mode" "$work/jsonl.output.$mode" || return 1
        cmp "$work/json.output.$mode" "$work/snapshot.output.$mode" || return 1
    done
    jq -e '
        .summary == {criteria_total:14,satisfied:13,weakly_verified:0,missing:1,child_beads:1026,over_broad_children:1}
        and .status == "warn"
        and all(.criteria[:12][]; .status == "satisfied" and (.evidence | length) == 6
            and all(.evidence[]; .match_score == 1 and .status == "closed"))
        and .criteria[12].evidence == [{bead_id:"bd-tail",title:"zirconium",status:"closed",match_score:1,commit_subjects:[]}]
        and .criteria[13].status == "missing"
        and .over_broad_children == [{bead_id:"bd-unrelated",title:"Billing",status:"unknown"}]
    ' "$work/json.output.json" >/dev/null || return 1
    sha256sum -c "$work/inputs.sha256" >/dev/null || return 1
    pass "many_children_complete_reports"
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
    run_test test_small_report_schema_and_input_equivalence
    run_test test_large_file_inputs_are_equivalent_and_read_only
    run_test test_large_live_export_and_beads_snapshot
    run_test test_malformed_inputs_never_emit_reports
    run_test test_live_collection_failures_never_emit_reports
    run_test test_real_git_collection_is_read_only
    run_test test_empty_and_single_issue_jsonl
    run_test test_large_child_id_filters_do_not_use_argv
    run_test test_live_collection_includes_closed_and_deferred_without_sync
    run_test test_incomplete_exports_never_emit_reports
    run_test test_selection_and_evidence_ordering
    run_test test_many_children_complete_reports

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
