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
    'show --json --no-auto-import --no-auto-flush -- '*)
        shift 5
        jq -s --rawfile requested <(printf '%s\n' "$@") '
            ($requested | split("\n")[:-1]) as $ids
            | (if length == 1 and (.[0] | type) == "array" then .[0]
               elif length == 1 and (.[0].issues | type) == "array" then .[0].issues
               else . end)
            | map(select(.id as $id | $ids | index($id)))
        ' "$MOCK_ISSUES"
        ;;
    *) echo "Unexpected or mutating br command: $*" >&2; exit 90 ;;
esac
exit "${MOCK_BR_EXIT:-0}"
SH
    cat > "$ARTIFACT_DIR/live-bin/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$*" >> "$MOCK_CALLS"
[[ "$*" == 'log --format=%H %s --all --no-show-signature --no-notes --no-patch --color=never --no-decorate --encoding=UTF-8' ]] || exit 91
cat "$MOCK_GIT_LOG"
exit "${MOCK_GIT_EXIT:-0}"
SH
    chmod +x "$ARTIFACT_DIR/live-bin/br" "$ARTIFACT_DIR/live-bin/git" || return 1
    jq -r '.[] | ("0" * 40) + " " + .subject' "$ARTIFACT_DIR/large-commits.json" \
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
                printf 'br show --json --no-auto-import --no-auto-flush -- bd-capacity bd-status\n'
            fi
            printf 'git log --format=%%H %%s --all --no-show-signature --no-notes --no-patch --color=never --no-decorate --encoding=UTF-8\n'
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

test_git_subjects_survive_delimiters_and_user_config() {
    local work="$ARTIFACT_DIR/git-subjects" mode subject
    mkdir -p "$work" || return 1
    git init -q -b main "$work" || return 1
    local subjects=(
        $'Notes\037bd-proof zirconium tests passed'
        $'Notes\036bd-proof zirconium fixtures passed'
        $'bd-proof zirconium "quotes" \\ tabs\t Unicode Ω verified'
    )
    for subject in "${subjects[@]}" ""; do
        git -C "$work" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false \
            commit -q --allow-empty --allow-empty-message -m "$subject" || return 1
    done
    git -C "$work" -c user.name=Test -c user.email=test@example.invalid \
        notes add -m 'bd-proof forged note evidence, not a commit subject' || return 1
    git -C "$work" config log.showSignature true || return 1
    git -C "$work" config log.showNotes true || return 1
    git -C "$work" config color.ui always || return 1
    git -C "$work" config i18n.logOutputEncoding ISO-8859-1 || return 1
    printf '%s\n' '{"id":"bd-epic","success_criteria":["Zirconium verified"],"dependencies":[{"id":"bd-proof","status":"closed"}]}' \
        > "$work/epic.json"
    printf '[]\n' > "$work/issues.json"
    printf '%s\n' "${subjects[@]}" | jq -R -s 'split("\n")[:-1] | reverse' > "$work/subjects.json" || return 1
    jq 'map({hash:"unused",subject:.})' "$work/subjects.json" > "$work/commits.json" || return 1
    git -C "$work" show-ref > "$work/refs.before" || return 1
    sha256sum "$work/.git/config" > "$work/config.sha256" || return 1
    for mode in json markdown; do
        bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" \
            --issues-file "$work/issues.json" --commits-file "$work/commits.json" > "$work/expected.$mode" || return 1
        (cd "$work" && bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file epic.json --issues-file issues.json) \
            > "$work/actual.$mode" 2> "$work/$mode.stderr" || return 1
        cmp "$work/expected.$mode" "$work/actual.$mode" || return 1
        [[ ! -s "$work/$mode.stderr" ]] || return 1
    done
    jq -e '.summary.satisfied == 1 and (.criteria[0].evidence[0].commit_subjects | length) == 3' \
        "$work/actual.json" >/dev/null || return 1
    git -C "$work" show-ref > "$work/refs.after" || return 1
    cmp "$work/refs.before" "$work/refs.after" || return 1
    sha256sum -c "$work/config.sha256" >/dev/null || return 1
    pass "git_subjects_survive_delimiters_and_user_config"
}

test_large_git_history_keeps_tail_evidence() {
    local work="$ARTIFACT_DIR/git-history" mode
    mkdir -p "$work" || return 1
    printf '%s\n' '{"id":"bd-epic","success_criteria":["Zirconium verified"],"dependencies":[{"id":"bd-proof","status":"closed"}]}' \
        > "$work/epic.json"
    printf '[]\n' > "$work/issues.json"
    # Over 32 MiB of unrelated history followed by the only relevant commit.
    # Its subject also exceeds common per-argument limits. No truncation can
    # satisfy this regression; compare the complete report in both formats.
    jq -n -r '("x" * 1024) as $padding | range(0;32768) | ("0" * 40) + " Unrelated " + tostring + $padding' \
        > "$work/history.log" || return 1
    jq -n '[{hash:("a" * 64),subject:(("z" * 262144) + " bd-proof zirconium tests passed")}]' \
        > "$work/commits.json" || return 1
    jq -r '.[] | .hash + " " + .subject' "$work/commits.json" >> "$work/history.log" || return 1
    [[ $(wc -c < "$work/history.log") -gt 33554432 ]] || return 1
    sha256sum "$work/history.log" > "$work/history.sha256" || return 1
    for mode in json markdown; do
        bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" \
            --issues-file "$work/issues.json" --commits-file "$work/commits.json" > "$work/expected.$mode" || return 1
        PATH="$ARTIFACT_DIR/live-bin:$PATH" MOCK_CALLS="$work/calls" MOCK_GIT_LOG="$work/history.log" \
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" \
            --issues-file "$work/issues.json" > "$work/actual.$mode" 2> "$work/$mode.stderr" || return 1
        cmp "$work/expected.$mode" "$work/actual.$mode" || return 1
        [[ ! -s "$work/$mode.stderr" ]] || return 1
    done
    jq -e '.summary.satisfied == 1' "$work/actual.json" >/dev/null || return 1
    sha256sum -c "$work/history.sha256" >/dev/null || return 1
    pass "large_git_history_keeps_tail_evidence"
}

test_malformed_git_records_never_emit_reports() {
    local work="$ARTIFACT_DIR/git-record-errors" mode bad index=0
    mkdir -p "$work" || return 1
    for bad in '' 'signature chatter' 'bad-hash bd-capacity' \
        '000000000000000000000000000000000000000z bd-capacity'; do
        index=$((index + 1))
        printf '%040d bd-capacity tests passed\n%s\n' 0 "$bad" > "$work/log-$index"
        for mode in json markdown; do
            PATH="$ARTIFACT_DIR/live-bin:$PATH" MOCK_CALLS="$work/calls" MOCK_GIT_LOG="$work/log-$index" \
                expect_input_failure "git-record-$index-$mode" 'malformed git log record' "--$mode" \
                --epic-file "$ARTIFACT_DIR/complete_epic.json" --issues-file "$ARTIFACT_DIR/complete_issues.json" || return 1
        done
    done
    pass "malformed_git_records_never_emit_reports"
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
    printf '%040d Verify bd-child-19999\n' 0 > "$ARTIFACT_DIR/large-children-git.log"
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
    jq -e '. == [{hash:("0" * 40),subject:"Verify bd-child-19999"}]' "$ARTIFACT_DIR/large-children-commits.json" >/dev/null || return 1
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
    show)
        if [[ "$2" == bd-epic ]]; then
            cat "$MOCK_WORK/epic.json"
        else
            [[ "$*" == 'show --json --no-auto-import --no-auto-flush -- bd-archived bd-deferred' ]] || exit 90
            jq '[.[] | select(.id == "bd-archived" or .id == "bd-deferred")]' "$MOCK_WORK/issues.json"
        fi
        ;;
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

test_jsonl_stream_selection_and_late_failures() {
    local work="$ARTIFACT_DIR/jsonl-stream" mode source suffix index=0
    mkdir -p "$work/.beads" || return 1
    cp "$ARTIFACT_DIR/complete_epic.json" "$work/epic.json" || return 1
    cp "$ARTIFACT_DIR/complete_commits.json" "$work/commits.json" || return 1
    jq -c '.[0]' "$ARTIFACT_DIR/complete_issues.json" > "$work/issues.jsonl" || return 1
    jq -nc '("x" * 2048) as $padding | range(0;16384) | {id:("noise-" + tostring),description:$padding}' \
        >> "$work/issues.jsonl" || return 1
    jq -c '.[1]' "$ARTIFACT_DIR/complete_issues.json" >> "$work/issues.jsonl" || return 1
    [[ $(wc -c < "$work/issues.jsonl") -gt 33554432 ]] || return 1
    cp "$work/issues.jsonl" "$work/.beads/issues.jsonl" || return 1
    sha256sum "$work/issues.jsonl" "$work/.beads/issues.jsonl" > "$work/inputs.sha256" || return 1
    for source in file snapshot live; do
        for mode in json markdown; do
            (
                cd "$work" || exit 1
                local args=("--$mode" --epic-file "$work/epic.json" --commits-file "$work/commits.json")
                case "$source" in
                    file) args+=(--issues-file "$work/issues.jsonl") ;;
                    live)
                        cd "$ARTIFACT_DIR" || exit 1
                        export PATH="$ARTIFACT_DIR/live-bin:$PATH" MOCK_CALLS="$work/calls" MOCK_ISSUES="$work/issues.jsonl"
                        ;;
                esac
                bash "$SWARM_CONVERGENCE_SH" "${args[@]}"
            ) > "$work/$source.$mode" 2> "$work/$source.$mode.stderr" || return 1
            cmp "$ARTIFACT_DIR/small.$mode" "$work/$source.$mode" || return 1
            [[ ! -s "$work/$source.$mode.stderr" ]] || return 1
        done
    done
    sha256sum -c "$work/inputs.sha256" >/dev/null || return 1
    # With no selected children, the entire suffix must still be validated.
    printf '{"id":"bd-epic","dependencies":[]}\n' > "$work/empty-epic.json"
    for suffix in '{"id":' '17' '{"issues":[]}'; do
        index=$((index + 1))
        { cat "$work/issues.jsonl"; printf '%s\n' "$suffix"; } > "$work/bad-$index.jsonl"
        for mode in json markdown; do
            expect_input_failure "stream-suffix-$index-$mode" 'issues' "--$mode" \
                --epic-file "$work/empty-epic.json" --issues-file "$work/bad-$index.jsonl" \
                --commits-file "$work/commits.json" || return 1
        done
    done
    pass "jsonl_stream_selection_and_late_failures"
}

test_jsonl_first_value_disambiguation() {
    local work="$ARTIFACT_DIR/jsonl-shapes" mode shape
    mkdir -p "$work" || return 1
    # In a multi-record JSONL stream, "issues" may be an ordinary issue field.
    # In a single object it denotes the legacy envelope. Do not guess early.
    jq '.[0].issues = false' "$ARTIFACT_DIR/complete_issues.json" > "$work/array.json" || return 1
    jq -c '.[]' "$work/array.json" > "$work/records.jsonl" || return 1
    jq '{issues:.,total:length,offset:0,has_more:false}' "$work/array.json" > "$work/wrapper.json" || return 1
    for mode in json markdown; do
        for shape in array.json records.jsonl wrapper.json; do
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$ARTIFACT_DIR/complete_epic.json" \
                --issues-file "$work/$shape" --commits-file "$ARTIFACT_DIR/complete_commits.json" \
                > "$work/$shape.$mode" || return 1
            cmp "$ARTIFACT_DIR/small.$mode" "$work/$shape.$mode" || return 1
        done
        { cat "$work/wrapper.json"; printf '{"id":"extra"}\n'; } > "$work/mixed.json"
        expect_input_failure "stream-mixed-$mode" 'issues' "--$mode" --epic-file "$ARTIFACT_DIR/complete_epic.json" \
            --issues-file "$work/mixed.json" --commits-file "$ARTIFACT_DIR/complete_commits.json" || return 1
    done
    pass "jsonl_first_value_disambiguation"
}

test_native_beads_criteria_and_children() {
    local work="$ARTIFACT_DIR/native-beads" mode source
    mkdir -p "$work/.beads" || return 1
    # br show flattens Issue.acceptance_criteria and places parent-child
    # children in dependents (beads_rust src/format/output.rs::IssueDetails).
    # The checked marker is deliberately varied; only child evidence counts.
    jq '.[0] | .description = "Native Beads epic" |
        .acceptance_criteria = "- [ ] Capacity report recommends agent counts.\n* [X] Swarm status view works from local state." |
        .dependents = [.dependencies[] | .dependency_type = "parent-child"] |
        del(.dependencies)' "$ARTIFACT_DIR/complete_epic.json" > "$work/epic.json" || return 1
    cp "$ARTIFACT_DIR/large-issues.jsonl" "$work/.beads/issues.jsonl" || return 1
    sha256sum "$work/epic.json" "$work/.beads/issues.jsonl" > "$work/input.sha256" || return 1
    for mode in json markdown; do
        for source in json jsonl snapshot live; do
            (
                local args=("--$mode" --commits-file "$ARTIFACT_DIR/complete_commits.json")
                if [[ "$source" == live ]]; then
                    mkdir -p "$work/live" || exit 1
                    cd "$work/live" || exit 1
                    export PATH="$ARTIFACT_DIR/live-bin:$PATH" MOCK_CALLS="$work/calls"
                    export MOCK_EPIC="$work/epic.json" MOCK_ISSUES="$ARTIFACT_DIR/large-issues.json"
                    args+=(--epic bd-epic)
                else
                    cd "$work" || exit 1
                    args+=(--epic-file "$work/epic.json")
                    if [[ "$source" != snapshot ]]; then
                        args+=(--issues-file "$ARTIFACT_DIR/large-issues.$source")
                    fi
                fi
                bash "$SWARM_CONVERGENCE_SH" "${args[@]}"
            ) > "$work/$source.$mode" 2> "$work/$source.$mode.stderr" || return 1
            # The full report must match the original legacy fixture, not just
            # its counts: titles, scores, evidence order and schema included.
            cmp "$ARTIFACT_DIR/small.$mode" "$work/$source.$mode" || return 1
        done
    done
    sha256sum -c "$work/input.sha256" >/dev/null || return 1
    # Exercise Git collection too: a child ID present only in dependents must
    # be considered by the collector, not just by the report filter.
    (
        cd "$work" || exit 1
        PATH="$ARTIFACT_DIR/live-bin:$PATH" MOCK_CALLS="$work/git.calls" \
            MOCK_GIT_LOG="$ARTIFACT_DIR/live-git.log" \
            bash "$SWARM_CONVERGENCE_SH" --json --epic-file "$work/epic.json"
    ) > "$work/git.json" || return 1
    cmp "$ARTIFACT_DIR/small.json" "$work/git.json" || return 1
    pass "native_beads_criteria_and_children"
}

test_acceptance_markdown_and_precedence() {
    local work="$ARTIFACT_DIR/acceptance" index mode
    mkdir -p "$work" || return 1
    # Input text and independently specified expected criteria. Fences include
    # shorter closers, wrong markers and trailing text, plus CRLF and wrapped
    # list items. Ordinary prose remains one criterion rather than vanishing.
    cat > "$work/cases.json" <<'JSON'
[
  {"text":"- [ ] Capacity report recommends agent counts.\n* [X] Swarm status view works from local state.","expected":["Capacity report recommends agent counts.","Swarm status view works from local state."]},
  {"text":"## Acceptance\r\n1. Capacity report recommends\r\n   agent counts.\r\n2) Swarm status view works from local state.\r\n","expected":["Capacity report recommends agent counts.","Swarm status view works from local state."]},
  {"text":"Examples follow:\n````md\n- [x] Not a requirement\n```\n- Still an example\n```` trailing text\n- Still an example\n````\n+ [x] Capacity report recommends agent counts.\n~~~md\n- More examples\n```\n- Wrong closer\n~~~\n- [ ] Swarm status view works from local state.","expected":["Capacity report recommends agent counts.","Swarm status view works from local state."]},
  {"text":"  Capacity report recommends agent counts.\nSwarm status view works from local state.  ","expected":["Capacity report recommends agent counts.\nSwarm status view works from local state."]},
  {"text":"- [ ]\n- [X] Capacity report recommends agent counts.","expected":["Capacity report recommends agent counts."]}
]
JSON
    for index in 0 1 2 3 4; do
        jq --slurpfile cases "$work/cases.json" --argjson index "$index" '
            .[0] | .description = "Native criteria" |
            .acceptance_criteria = $cases[0][$index].text' \
            "$ARTIFACT_DIR/complete_epic.json" > "$work/epic.json" || return 1
        jq --slurpfile cases "$work/cases.json" --argjson index "$index" '
            .success_criteria = $cases[0][$index].expected' "$work/epic.json" > "$work/expected-epic.json" || return 1
        for mode in json markdown; do
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" \
                --issues-file "$ARTIFACT_DIR/complete_issues.json" --commits-file "$ARTIFACT_DIR/complete_commits.json" \
                > "$work/actual-$index.$mode" || return 1
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/expected-epic.json" \
                --issues-file "$ARTIFACT_DIR/complete_issues.json" --commits-file "$ARTIFACT_DIR/complete_commits.json" \
                > "$work/expected-$index.$mode" || return 1
            cmp "$work/expected-$index.$mode" "$work/actual-$index.$mode" || return 1
        done
        jq -e --slurpfile cases "$work/cases.json" --argjson index "$index" \
            '[.criteria[].criterion] == $cases[0][$index].expected' "$work/actual-$index.json" >/dev/null || return 1
    done
    # Native text is a fallback; it cannot replace explicitly selected legacy
    # criteria. Test both explicit-array and description-section precedence.
    for index in description array; do
        jq --arg form "$index" '.[0] | .acceptance_criteria = "Conflicting requirement" |
            if $form == "array" then .success_criteria = ["Capacity report recommends agent counts.","Swarm status view works from local state."] else . end' \
            "$ARTIFACT_DIR/complete_epic.json" > "$work/precedence-$index.json" || return 1
        for mode in json markdown; do
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/precedence-$index.json" \
                --issues-file "$ARTIFACT_DIR/complete_issues.json" --commits-file "$ARTIFACT_DIR/complete_commits.json" \
                > "$work/precedence-$index.output.$mode" || return 1
            cmp "$ARTIFACT_DIR/small.$mode" "$work/precedence-$index.output.$mode" || return 1
        done
    done
    pass "acceptance_markdown_and_precedence"
}

test_native_relations_preserve_selection() {
    local work="$ARTIFACT_DIR/native-selection" mode
    mkdir -p "$work" || return 1
    cat > "$work/epic.json" <<'JSON'
{"id":"bd-epic","title":"Native selection","success_criteria":["Quartz","Xenon"],"dependencies":[
  {"issue_id":"bd-legacy","title":"Quartz override","status":"open"},
  {"id":"bd-legacy","title":"Quartz duplicate","status":"open"}
],"dependents":[
  {"id":"bd-legacy","title":"Must not override","status":"closed","dependency_type":"parent-child"},
  {"id":"bd-native","title":"Quartz native","status":"closed","dependency_type":"parent-child"},
  {"id":"bd-native","title":"Must not duplicate","status":"open","dependency_type":"parent-child"},
  {"id":"bd-downstream","title":"Xenon","status":"closed","dependency_type":"blocks"},
  {"id":"bd-related","title":"Xenon","status":"closed","dependency_type":"related"}
]}
JSON
    cat > "$work/issues.json" <<'JSON'
[
  {"id":"bd-legacy","title":"Quartz stored","status":"closed","close_reason":"tests passed"},
  {"id":"bd-native","title":"Quartz native","status":"closed","close_reason":"tests passed"},
  {"id":"bd-downstream","title":"Xenon","status":"closed","close_reason":"tests passed"},
  {"id":"bd-related","title":"Xenon","status":"closed","close_reason":"tests passed"}
]
JSON
    printf '[]\n' > "$work/commits.json"
    jq '.dependencies += [.dependents[1]] | del(.dependents)' "$work/epic.json" > "$work/legacy-epic.json" || return 1
    for mode in json markdown; do
        bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" \
            --issues-file "$work/issues.json" --commits-file "$work/commits.json" > "$work/native.$mode" || return 1
        bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/legacy-epic.json" \
            --issues-file "$work/issues.json" --commits-file "$work/commits.json" > "$work/legacy.$mode" || return 1
        cmp "$work/legacy.$mode" "$work/native.$mode" || return 1
    done
    jq -e '.summary.child_beads == 3 and .summary.satisfied == 1 and .summary.missing == 1
        and .criteria[1].evidence == []
        and any(.criteria[0].evidence[]; .bead_id == "bd-legacy" and .status == "open" and .title == "Quartz override")' \
        "$work/native.json" >/dev/null || return 1
    pass "native_relations_preserve_selection"
}

test_unverifiable_epics_never_pass() {
    local work="$ARTIFACT_DIR/unverifiable" index=0 body mode
    mkdir -p "$work" || return 1
    printf '[]\n' > "$work/empty.json"
    for body in '{}' '{acceptance_criteria:" "}' '{acceptance_criteria:"## Acceptance\n```md\n- example\n```"}' \
        '{success_criteria:[],acceptance_criteria:"Ignored explicit override"}' ; do
        index=$((index + 1))
        jq -n "{id:\"bd-epic\",title:\"No criteria\"} + $body" > "$work/epic.json" || return 1
        for mode in json markdown; do
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" \
                --issues-file "$work/empty.json" --commits-file "$work/empty.json" > "$work/$index.$mode" || return 1
        done
        jq -e '.schema_version == 1 and .status == "warn" and .summary.criteria_total == 0
            and .summary.satisfied == 0 and .criteria == []
            and .suggested_bead_titles == ["Define acceptance criteria for epic: bd-epic"]' "$work/$index.json" >/dev/null || return 1
        grep -q 'No auditable criteria found' "$work/$index.markdown" || return 1
    done
    # A checkbox on the epic alone must not manufacture child evidence.
    printf '{"id":"bd-epic","acceptance_criteria":"- [X] Capacity recommendations verified"}\n' > "$work/checked.json"
    bash "$SWARM_CONVERGENCE_SH" --json --epic-file "$work/checked.json" \
        --issues-file "$work/empty.json" --commits-file "$work/empty.json" > "$work/checked.output.json" || return 1
    jq -e '.status == "warn" and .summary.missing == 1 and .summary.satisfied == 0
        and .criteria[0].criterion == "Capacity recommendations verified"
        and .criteria[0].evidence == []' "$work/checked.output.json" >/dev/null || return 1
    pass "unverifiable_epics_never_pass"
}

test_malformed_native_fields_never_emit_reports() {
    local index=0 expression mode
    for expression in '.acceptance_criteria = []' '.acceptance_criteria = {}' '.acceptance_criteria = false' \
        '.dependents = {}' '.dependents = [17]' \
        '.dependents = [{dependency_type:"parent-child"}]' \
        '.dependents = [{id:17,dependency_type:"parent-child"}]' \
        '.dependents = [{id:"bd-epic",dependency_type:"parent-child"}]'; do
        index=$((index + 1))
        jq ".[0] | $expression" "$ARTIFACT_DIR/complete_epic.json" > "$ARTIFACT_DIR/bad-native-$index.json" || return 1
        for mode in json markdown; do
            expect_input_failure "bad-native-$index-$mode" 'epic input' "--$mode" \
                --epic-file "$ARTIFACT_DIR/bad-native-$index.json" --issues-file "$ARTIFACT_DIR/complete_issues.json" \
                --commits-file "$ARTIFACT_DIR/complete_commits.json" || return 1
        done
    done
    pass "malformed_native_fields_never_emit_reports"
}

test_large_native_graph_and_real_git() {
    local work="$ARTIFACT_DIR/native-large" mode format before after
    mkdir -p "$work/.beads" || return 1
    jq '.acceptance_criteria = (.success_criteria | map("- [ ] " + .) | join("\n")) |
        .dependents = [.dependencies[] | .dependency_type = "parent-child" | .notes = ("history " * 32)] |
        del(.success_criteria, .dependencies)' "$ARTIFACT_DIR/many-children/epic.json" > "$work/epic.json" || return 1
    [[ $(wc -c < "$work/epic.json") -gt 131072 ]] || return 1
    cp "$ARTIFACT_DIR/many-children/issues.jsonl" "$work/.beads/issues.jsonl" || return 1
    for mode in json markdown; do
        for format in json jsonl; do
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" \
                --issues-file "$ARTIFACT_DIR/many-children/issues.$format" \
                --commits-file "$ARTIFACT_DIR/many-children/commits.json" > "$work/$format.output.$mode" || return 1
            cmp "$ARTIFACT_DIR/many-children/json.output.$mode" "$work/$format.output.$mode" || return 1
        done
    done
    # Real Git evidence for the native graph, with no br/Git mocks. Keep all
    # inputs and reports outside the repository except the tracked snapshot.
    git -C "$work" init -q -b main || return 1
    git -C "$work" add .beads/issues.jsonl || return 1
    git -C "$work" -c user.name=Fixture -c user.email=fixture@example.invalid \
        commit -q -m 'bd-tail zirconium verification tests passed' || return 1
    before="$(git -C "$work" rev-parse HEAD)" || return 1
    sha256sum "$work/.beads/issues.jsonl" > "$work/snapshot.sha256" || return 1
    for mode in json markdown; do
        git -C "$work" status --porcelain=v1 --untracked-files=no > "$work/status.before" || return 1
        (
            cd "$work" || exit 1
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json"
        ) > "$work/git.$mode" 2> "$work/git.$mode.stderr" || return 1
        [[ ! -s "$work/git.$mode.stderr" ]] || return 1
        git -C "$work" status --porcelain=v1 --untracked-files=no > "$work/status.after" || return 1
        cmp "$work/status.before" "$work/status.after" || return 1
    done
    jq -e '.summary.child_beads == 1026 and .summary.criteria_total == 14
        and .summary.satisfied == 13 and .summary.missing == 1
        and .criteria[12].evidence[0].commit_subjects == ["bd-tail zirconium verification tests passed"]' \
        "$work/git.json" >/dev/null || return 1
    after="$(git -C "$work" rev-parse HEAD)" || return 1
    [[ "$before" == "$after" ]] || return 1
    sha256sum -c "$work/snapshot.sha256" >/dev/null || return 1
    pass "large_native_graph_and_real_git"
}

prepare_detail_tools() {
    local work="$1"
    mkdir -p "$work/bin" "$work/live" || return 1
    cat > "$work/bin/br" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
jq -n -c --rawfile args <(printf '%s\n' "$@") '$args | split("\n")[:-1]' >> "$MOCK_WORK/calls.jsonl"
case "$*" in
    'show bd-epic --json --no-auto-import --no-auto-flush') cat "$MOCK_WORK/epic.json"; exit 0 ;;
    'list --json --all --deferred --limit 0 --no-auto-import --no-auto-flush')
        cat "$MOCK_WORK/list.json"; exit "${MOCK_LIST_EXIT:-0}" ;;
esac
[[ "$#" -ge 6 && "$1" == show && "$2" == --json && "$3" == --no-auto-import &&
   "$4" == --no-auto-flush && "$5" == -- ]] || { echo 'unexpected br command' >&2; exit 90; }
shift 5
bytes=0
bad=false
for id in "$@"; do
    bytes=$((bytes + ${#id} + 1))
    [[ "$id" != "${MOCK_BAD_ID:-}" ]] || bad=true
done
(( $# <= 128 && bytes <= 32768 )) || { echo 'unbounded detail request' >&2; exit 91; }
mode=ok
[[ "$bad" == false ]] || mode="${MOCK_DETAIL_MODE:-ok}"
if [[ "$mode" == truncated ]]; then
    printf '[{"id":'
    exit 0
fi
jq --rawfile requested <(printf '%s\n' "$@") --arg mode "$mode" '
    ($requested | split("\n")[:-1]) as $ids
    | [.[] | select(.id as $id | $ids | index($id))]
    | if $mode == "missing" then .[1:]
      elif $mode == "duplicate" then . + [.[0]]
      elif $mode == "unexpected" then . + [{id:"bd-unexpected"}]
      elif $mode == "page" then {issues:.,total:(length + 1),has_more:true,offset:0}
      elif $mode == "comments" then .[0].comments = ["malformed"]
      elif $mode == "revision" then .[0].updated_at = "changed-revision"
      else . end
' "$MOCK_WORK/details.json"
[[ "$mode" != exit ]] || { echo 'detail transport failed' >&2; exit 23; }
SH
    chmod +x "$work/bin/br" || return 1
}

run_detail_audit() {
    local work="$1" mode="$2"
    shift 2
    (
        cd "$work/live" || exit 1
        PATH="$work/bin:$PATH" MOCK_WORK="$work" bash "$SWARM_CONVERGENCE_SH" \
            "--$mode" --epic bd-epic --commits-file "$work/commits.json" "$@"
    )
}

test_live_comment_evidence_matches_full_exports() {
    local work="$ARTIFACT_DIR/live-comments" mode
    prepare_detail_tools "$work" || return 1
    cat > "$work/epic.json" <<'JSON'
{"id":"bd-epic","title":"Comment evidence","acceptance_criteria":"- Zirconium\n- Quartz\n- Xenon","dependents":[
  {"id":"bd-closed","dependency_type":"parent-child"},
  {"id":"bd-open","dependency_type":"parent-child"},
  {"id":"bd-deferred","dependency_type":"parent-child"}
]}
JSON
    cat > "$work/details.json" <<'JSON'
[
  {"id":"bd-closed","title":"Implementation","status":"closed","updated_at":"revision-1","comments":[{"text":"Zirconium tests passed with artifacts."}]},
  {"id":"bd-open","title":"Implementation","status":"open","updated_at":"revision-2","comments":[{"text":"Quartz verification logs captured."}]},
  {"id":"bd-deferred","title":"Implementation","status":"deferred","updated_at":"revision-3","comments":[{"text":"Xenon tests passed."}]},
  {"id":"bd-noise","title":"Zirconium Quartz Xenon tests","status":"closed","comments":[]}
]
JSON
    # Model the real list projection: no comments, even though they exist.
    jq 'map(del(.comments)) | {issues:.,total:length,offset:0,has_more:false}' \
        "$work/details.json" > "$work/list.json" || return 1
    printf '[]\n' > "$work/commits.json"
    sha256sum "$work/epic.json" "$work/list.json" "$work/details.json" "$work/commits.json" > "$work/input.sha256" || return 1
    for mode in json markdown; do
        bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" \
            --issues-file "$work/details.json" --commits-file "$work/commits.json" > "$work/expected.$mode" || return 1
        run_detail_audit "$work" "$mode" > "$work/actual.$mode" 2> "$work/$mode.stderr" || return 1
        cmp "$work/expected.$mode" "$work/actual.$mode" || return 1
        [[ ! -s "$work/$mode.stderr" ]] || return 1
    done
    jq -e '.summary == {criteria_total:3,satisfied:1,weakly_verified:2,missing:0,child_beads:3,over_broad_children:0}
        and .criteria[0].evidence[0].bead_id == "bd-closed"
        and .criteria[1].evidence[0].bead_id == "bd-open"
        and .criteria[2].evidence[0].bead_id == "bd-deferred"' "$work/actual.json" >/dev/null || return 1
    jq -s -e '[.[] | select(.[0] == "show" and .[1] == "--json") | .[5:]] ==
        [["bd-closed","bd-deferred","bd-open"],["bd-closed","bd-deferred","bd-open"]]' "$work/calls.jsonl" >/dev/null || return 1
    sha256sum -c "$work/input.sha256" >/dev/null || return 1
    pass "live_comment_evidence_matches_full_exports"
}

test_live_detail_batches_bound_count_and_bytes() {
    local shape work mode
    for shape in count bytes unicode; do
        work="$ARTIFACT_DIR/detail-batches-$shape"
        prepare_detail_tools "$work" || return 1
        jq -n --arg shape "$shape" '
            (if $shape == "count" then 257 else 40 end) as $count
            | [range(0;$count) | {
                id:("bd-child-" + (10000 + . | tostring) +
                    (if $shape == "bytes" then ("q" * 6000)
                     elif $shape == "unicode" then ("\u03bb" * 3000) else "" end)),
                title:"Implementation",status:"closed",updated_at:"same-revision",
                comments:[{text:("Zirconium tests passed " + ("z" * 4096))}]
            }]' > "$work/details.json" || return 1
        jq 'map(del(.comments))' "$work/details.json" > "$work/list.json" || return 1
        jq '{id:"bd-epic",success_criteria:["Zirconium"],dependents:
            [.[] | {id:.id,dependency_type:"parent-child"}]}' "$work/details.json" > "$work/epic.json" || return 1
        printf '[]\n' > "$work/commits.json"
        [[ $(wc -c < "$work/details.json") -gt 131072 ]] || return 1
        for mode in json markdown; do
            : > "$work/calls.jsonl"
            bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" \
                --issues-file "$work/details.json" --commits-file "$work/commits.json" > "$work/expected.$mode" || return 1
            LC_ALL=C.UTF-8 run_detail_audit "$work" "$mode" > "$work/actual.$mode" 2> "$work/$mode.stderr" || return 1
            cmp "$work/expected.$mode" "$work/actual.$mode" || return 1
            jq -s -e --slurpfile expected "$work/details.json" '
                [.[] | select(.[0] == "show" and .[1] == "--json") | .[5:]] as $batches
                | ($batches | length) > 1
                and all($batches[]; length <= 128 and (map(utf8bytelength + 1) | add) <= 32768)
                and ([$batches[][]] | sort) == ($expected[0] | map(.id) | sort)
            ' "$work/calls.jsonl" >/dev/null || return 1
        done
    done
    pass "live_detail_batches_bound_count_and_bytes"
}

test_live_details_preserve_list_selection_and_overrides() {
    local work="$ARTIFACT_DIR/detail-selection" mode
    prepare_detail_tools "$work" || return 1
    cat > "$work/epic.json" <<'JSON'
{"id":"bd-epic","success_criteria":["Zirconium","Quartz"],"dependencies":[
  {"issue_id":"bd-first","title":"Dependency override","status":"open"},
  {"id":"bd-first"}, {"depends_on_id":"-literal id"}, {"id":"bd-missing"}
]}
JSON
    cat > "$work/details.json" <<'JSON'
[
  {"id":"bd-first","title":"Canonical","status":"closed","comments":[{"text":"Zirconium tests passed"}]},
  {"id":"-literal id","title":"Canonical","status":"closed","comments":[{"text":"Quartz tests passed"}]},
  {"id":"bd-noise","title":"Must not query","comments":[]}
]
JSON
    cat > "$work/list.json" <<'JSON'
[
  {"id":"bd-first","title":"First list record","status":"closed"},
  {"id":"bd-first","title":"Second list record","status":"deferred"},
  {"id":"-literal id","title":"Literal ID","status":"closed"},
  {"id":"bd-noise","title":"Unrelated","status":"closed"}
]
JSON
    jq --slurpfile details "$work/details.json" 'map(. as $row |
        . + {comments: (first($details[0][] | select(.id == $row.id)).comments)})' \
        "$work/list.json" > "$work/expected-issues.json" || return 1
    printf '[]\n' > "$work/commits.json"
    for mode in json markdown; do
        bash "$SWARM_CONVERGENCE_SH" "--$mode" --epic-file "$work/epic.json" \
            --issues-file "$work/expected-issues.json" --commits-file "$work/commits.json" > "$work/expected.$mode" || return 1
        run_detail_audit "$work" "$mode" > "$work/actual.$mode" 2> "$work/$mode.stderr" || return 1
        cmp "$work/expected.$mode" "$work/actual.$mode" || return 1
    done
    jq -s -e '[.[] | select(.[0] == "show" and .[1] == "--json") | .[5:]] ==
        [["-literal id","bd-first"],["-literal id","bd-first"]]' "$work/calls.jsonl" >/dev/null || return 1
    # The legacy duplicate-dependency rule can choose the stronger closed
    # duplicate. It must still use the first stored list record for that ID.
    jq -e '.summary.child_beads == 4 and .criteria[0].status == "satisfied"
        and .criteria[0].evidence[0].title == "First list record"
        and .criteria[1].evidence[0].title == "Literal ID"' "$work/actual.json" >/dev/null || return 1
    pass "live_details_preserve_list_selection_and_overrides"
}

test_failed_live_detail_batches_never_emit_reports() {
    local work="$ARTIFACT_DIR/detail-batches-count" mode failure expected_calls
    for failure in truncated exit missing duplicate unexpected page comments revision; do
        for mode in json markdown; do
            : > "$work/calls.jsonl"
            if MOCK_BAD_ID=bd-child-10128 MOCK_DETAIL_MODE="$failure" run_detail_audit "$work" "$mode" \
                > "$work/failure-$failure-$mode.stdout" 2> "$work/failure-$failure-$mode.stderr"; then
                echo "Unexpected success for detail failure: $failure" >&2
                return 1
            fi
            [[ ! -s "$work/failure-$failure-$mode.stdout" ]] || return 1
            grep -Eq 'live child details|issues input|failed to read issues input' "$work/failure-$failure-$mode.stderr" || return 1
            # A malformed/failed second read stops the third. Revision checks
            # happen when merging the collected details with the list rows.
            expected_calls=2
            [[ "$failure" != revision ]] || expected_calls=3
            jq -s -e --argjson expected "$expected_calls" \
                '[.[] | select(.[0] == "show" and .[1] == "--json")] | length == $expected' \
                "$work/calls.jsonl" >/dev/null || return 1
        done
    done
    # A successful JSON prefix from a failed list command cannot start reads.
    : > "$work/calls.jsonl"
    if MOCK_LIST_EXIT=24 run_detail_audit "$work" json > "$work/list-failure.stdout" 2> "$work/list-failure.stderr"; then
        return 1
    fi
    [[ ! -s "$work/list-failure.stdout" ]] || return 1
    jq -s -e '[.[] | select(.[0] == "show" and .[1] == "--json")] | length == 0' \
        "$work/calls.jsonl" >/dev/null || return 1
    pass "failed_live_detail_batches_never_emit_reports"
}

test_live_detail_ids_validate_before_exec() {
    local work="$ARTIFACT_DIR/detail-invalid-ids" id mode index=0
    prepare_detail_tools "$work" || return 1
    printf '[]\n' > "$work/commits.json"
    for id in '"line\nbreak"' '"nul\u0000byte"' '"tab\tbyte"' '"return\rbyte"' '"del\u007fbyte"' \
        '("z" * 16385)' '("\u03bb" * 8193)' '42'; do
        index=$((index + 1))
        jq -n "[{id:($id),status:\"closed\"}]" > "$work/list.json" || return 1
        jq '{id:"bd-epic",success_criteria:["Zirconium"],dependencies:[.[] | {id:.id}]}' \
            "$work/list.json" > "$work/epic.json" || return 1
        for mode in json markdown; do
            : > "$work/calls.jsonl"
            if run_detail_audit "$work" "$mode" > "$work/bad-$index-$mode.stdout" 2> "$work/bad-$index-$mode.stderr"; then
                return 1
            fi
            [[ ! -s "$work/bad-$index-$mode.stdout" ]] || return 1
            grep -q 'live child details: IDs' "$work/bad-$index-$mode.stderr" || return 1
            jq -s -e '[.[] | select(.[0] == "show" and .[1] == "--json")] | length == 0' \
                "$work/calls.jsonl" >/dev/null || return 1
        done
    done
    pass "live_detail_ids_validate_before_exec"
}

test_empty_and_offline_sources_do_not_read_live_details() {
    local work="$ARTIFACT_DIR/detail-source-isolation" mode
    prepare_detail_tools "$work" || return 1
    printf '{"id":"bd-epic","success_criteria":["Zirconium"],"dependencies":[{"id":"bd-absent"}]}\n' > "$work/epic.json"
    printf '[]\n' > "$work/list.json"
    printf '[]\n' > "$work/commits.json"
    for mode in json markdown; do
        : > "$work/calls.jsonl"
        run_detail_audit "$work" "$mode" > "$work/empty.$mode" || return 1
        jq -s -e '[.[] | select(.[0] == "show" and .[1] == "--json")] | length == 0' \
            "$work/calls.jsonl" >/dev/null || return 1
        # Explicit files and local snapshots remain self-contained. The mock
        # detail file deliberately does not exist, so accidental reads fail.
        (
            cd "$work/live" || exit 1
            PATH="$work/bin:$PATH" MOCK_WORK="$work" bash "$SWARM_CONVERGENCE_SH" "--$mode" \
                --epic-file "$work/epic.json" --issues-file "$work/list.json" --commits-file "$work/commits.json"
        ) > "$work/file.$mode" || return 1
        mkdir -p "$work/offline/.beads" || return 1
        cp "$work/list.json" "$work/offline/.beads/issues.jsonl" || return 1
        (
            cd "$work/offline" || exit 1
            PATH="$work/bin:$PATH" MOCK_WORK="$work" bash "$SWARM_CONVERGENCE_SH" "--$mode" \
                --epic-file "$work/epic.json" --commits-file "$work/commits.json"
        ) > "$work/snapshot.$mode" || return 1
        cmp "$work/empty.$mode" "$work/file.$mode" || return 1
        cmp "$work/empty.$mode" "$work/snapshot.$mode" || return 1
        jq -s -e 'length == 2' "$work/calls.jsonl" >/dev/null || return 1
    done
    pass "empty_and_offline_sources_do_not_read_live_details"
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
    run_test test_git_subjects_survive_delimiters_and_user_config
    run_test test_large_git_history_keeps_tail_evidence
    run_test test_malformed_git_records_never_emit_reports
    run_test test_empty_and_single_issue_jsonl
    run_test test_large_child_id_filters_do_not_use_argv
    run_test test_live_collection_includes_closed_and_deferred_without_sync
    run_test test_incomplete_exports_never_emit_reports
    run_test test_selection_and_evidence_ordering
    run_test test_many_children_complete_reports
    run_test test_jsonl_stream_selection_and_late_failures
    run_test test_jsonl_first_value_disambiguation
    run_test test_native_beads_criteria_and_children
    run_test test_acceptance_markdown_and_precedence
    run_test test_native_relations_preserve_selection
    run_test test_unverifiable_epics_never_pass
    run_test test_malformed_native_fields_never_emit_reports
    run_test test_large_native_graph_and_real_git
    run_test test_live_comment_evidence_matches_full_exports
    run_test test_live_detail_batches_bound_count_and_bytes
    run_test test_live_details_preserve_list_selection_and_overrides
    run_test test_failed_live_detail_batches_never_emit_reports
    run_test test_live_detail_ids_validate_before_exec
    run_test test_empty_and_offline_sources_do_not_read_live_details

    echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    echo "Artifacts: $ARTIFACT_DIR"
    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
