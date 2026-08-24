#!/usr/bin/env bash
# ============================================================
# Proof-of-firing tests for the skills/onboarding-summary abort-path fix
# (see: fix(install) "record-and-continue through phase/module failures so
# skills and the summary still land").
#
# These run against the REAL install.sh / scripts/lib/install_helpers.sh /
# scripts/generated/install_stack.sh — sourced and invoked directly, not
# hand-mirrored — so a regression in the actual shipped control flow will
# fail these tests, not just a paraphrase of it.
#
# SCOPE / LIMITATION (read before trusting this as end-to-end proof): these
# tests exercise the record-and-continue phase/module loop and the
# cleanup() EXIT trap fallback in isolation. They never call install.sh's
# own main() — main() requires real root and network access (apt, useradd,
# curl to upstream installers) that this test harness deliberately does not
# grant. The trap LOGIC is proven for real here; a full, real `sudo bash
# install.sh` end-to-end proof on a throwaway VM is still owed and is not
# what this file claims to provide.
#
# Test 1 (module failure, shape of a real installer crashing mid-run):
#   Sources the real install_stack.sh and overrides only acfs_generated_install_stack_ntm
#   to return 1 immediately (module stack.ntm sits directly before
#   stack.meta_skill in the real manifest's "stack" category/phase 9) —
#   the exact shape a real verified-install failure produces. Everything
#   else, including acfs_generated_install_stack_meta_skill, runs unmodified in
#   DRY_RUN=true (its own real, network-free branch). Calls the real
#   acfs_run_generated_category_phase() and the real print_summary()
#   directly and asserts on their actual output/state.
#
# Test 2 (EXIT trap idempotence, 3 scenarios, each a real subprocess):
#   A: normal completion (flag set before exit 0)      -> skills=1 summary=1
#   B: crash bypassing record-and-continue (exit 1)     -> skills=1 summary=1
#   C: benign pre-confirmation exit, e.g. --help (exit 0) -> skills=0 summary=0
#   C is the case that makes this a real test rather than a tautological
#   one: it proves the fallback does NOT fire unconditionally. A trap that
#   always ran would be a new bug wearing the old one's clothes.
# ============================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/acfs-skills-summary-fallback-proof.XXXXXX")"
cleanup_tmproot() { rm -rf "$TMPROOT"; }
trap cleanup_tmproot EXIT

FAIL=0
assert() {
    local desc="$1" cond="$2"
    if [[ "$cond" == "true" ]]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        FAIL=1
    fi
}

# --- Build a sourceable copy of the real install.sh: identical content,
#     minus the trailing `main "$@"` so sourcing it only defines functions
#     and registers the real `trap cleanup EXIT` (no side effects run). ---
SOURCEABLE="$TMPROOT/install_sourceable.sh"
INSTALL_SH="$REPO_ROOT/install.sh"
total_lines="$(wc -l < "$INSTALL_SH")"
last_line="$(tail -n 1 "$INSTALL_SH")"
if [[ "$last_line" != 'main "$@"' ]]; then
    echo "FATAL: install.sh's last line is not the expected \`main \"\$@\"\` invocation (got: $last_line)." >&2
    echo "       This test's assumption about how to build a sourceable copy is stale; update it." >&2
    exit 2
fi
head -n "$((total_lines - 1))" "$INSTALL_SH" > "$SOURCEABLE"
bash -n "$SOURCEABLE" || { echo "FATAL: sourceable copy of install.sh fails bash -n"; exit 2; }

# BASH_SOURCE[0]-relative resolution (SCRIPT_DIR, ACFS_LIB_DIR, etc.) needs
# scripts/, acfs/, checksums.yaml, acfs.manifest.yaml next to the sourceable
# copy — real symlinks to the real files, not copies.
ln -sfn "$REPO_ROOT/scripts" "$TMPROOT/scripts"
ln -sfn "$REPO_ROOT/acfs" "$TMPROOT/acfs"
ln -sfn "$REPO_ROOT/checksums.yaml" "$TMPROOT/checksums.yaml"
ln -sfn "$REPO_ROOT/acfs.manifest.yaml" "$TMPROOT/acfs.manifest.yaml"

# ============================================================
# Test 1: module failure does not stop later modules or the summary
# ============================================================
run_test_1() {
    local workdir="$TMPROOT/test1"
    mkdir -p "$workdir/home"

    TARGET_USER="$(whoami)"
    TARGET_HOME="$HOME"
    MODE="vibe"
    HAS_GUM=false
    YES_MODE=true
    # shellcheck disable=SC1090
    source "$SOURCEABLE"

    detect_environment
    source_generated_installers
    ACFS_HOME="$workdir/home/.acfs"
    ACFS_STATE_FILE="$ACFS_HOME/state.json"
    export ACFS_HOME ACFS_STATE_FILE
    state_init

    declare -f acfs_generated_install_stack_ntm >/dev/null 2>&1 || { echo "FATAL: real acfs_generated_install_stack_ntm not loaded"; exit 2; }
    declare -f acfs_generated_install_stack_meta_skill >/dev/null 2>&1 || { echo "FATAL: real acfs_generated_install_stack_meta_skill not loaded"; exit 2; }

    # The one deliberate fault: shape of "the installer crashed" mid-run.
    acfs_generated_install_stack_ntm() {
        log_error "acfs_generated_install_stack_ntm: SIMULATED CRASH (test-injected fault standing in for a real verified-install failure)"
        return 1
    }

    # This sandbox may already have several real stack.* tools installed;
    # force every module to attempt so the induced failure actually fires
    # (install.sh resets this to false at its own top-level scope during
    # sourcing, so it must be set AFTER sourcing — same as --force).
    export ACFS_FORCE_REINSTALL=true

    DRY_RUN=true
    acfs_generated_ensure_selection || { echo "FATAL: acfs_generated_ensure_selection failed"; exit 2; }

    local category_log="$workdir/category_phase.log"
    local category_rc=0
    # install.sh's own `set -euo pipefail` is now active in this shell
    # (leaked in by sourcing it above), so an intentionally-nonzero return
    # here must be guarded, not just captured via a bare `$?` on the next line.
    test_generated_stack_phase() {
        acfs_run_generated_category_phase "stack" "9"
    }
    run_phase "stack" "8/9 Stack" test_generated_stack_phase > "$category_log" 2>&1 || category_rc=$?

    local meta_skill_ran="false"
    grep -q "stack.meta_skill installed" "$category_log" && meta_skill_ran="true"
    local ntm_recorded="false"
    local f
    for f in "${ACFS_MODULE_FAILURES[@]:-}"; do
        [[ "$f" == stack.ntm* ]] && ntm_recorded="true"
    done
    local failed_phase=""
    local stack_completed="false"
    failed_phase=$(jq -r '.failed_phase // empty' "$ACFS_STATE_FILE")
    jq -e '.completed_phases | index("stack") != null' "$ACFS_STATE_FILE" >/dev/null && stack_completed=true

    assert "1a. induced stack.ntm failure recorded in ACFS_MODULE_FAILURES" "$ntm_recorded"
    assert "1b. real acfs_generated_install_stack_meta_skill still ran despite stack.ntm failing earlier in the same category loop" "$meta_skill_ran"
    assert "1c. generated category reports aggregate failure after finishing later modules" "$([[ $category_rc -ne 0 ]] && echo true || echo false)"
    assert "1d. run_phase persists the generated module failure on its enclosing phase" "$([[ "$failed_phase" == "stack" ]] && echo true || echo false)"
    assert "1e. run_phase does not persist the failed stack phase as completed" "$([[ "$stack_completed" == "false" ]] && echo true || echo false)"

    DRY_RUN=false
    ACFS_SSH_KEY_WARNING=false
    local summary_log="$workdir/summary.log"
    print_summary > "$summary_log" 2>&1 || true

    local names_failure="false"
    grep -q "stack.ntm" "$summary_log" && names_failure="true"
    local says_complete="false"
    grep -q "Installation Complete" "$summary_log" && says_complete="true"
    local says_failures="false"
    grep -q "Finished With Failures" "$summary_log" && says_failures="true"

    assert "2a. print_summary() names the induced failure (stack.ntm)" "$names_failure"
    assert "2b. print_summary() does not claim 'Installation Complete' over a broken run" "$([[ "$says_complete" == "false" ]] && echo true || echo false)"
    assert "2c. print_summary() banner reads 'Finished With Failures'" "$says_failures"
}

# ============================================================
# Test 2: EXIT trap fires exactly once, and only when it should
# ============================================================
run_test_2() {
    local workdir="$TMPROOT/test2"
    mkdir -p "$workdir"

    write_scenario_common() {
        local out="$1" name="$2"
        cat > "$out" <<EOF
set -uo pipefail
TARGET_USER="$(whoami)"
TARGET_HOME="$HOME"
MODE="vibe"
# shellcheck disable=SC1090
source "$SOURCEABLE"
detect_environment
source_generated_installers
export ACFS_FORCE_REINSTALL=true

SKILLS_COUNTER="$workdir/${name}.skills.count"
SUMMARY_COUNTER="$workdir/${name}.summary.count"

# acfs_generated_install_stack_meta_skill: counting stub. Its real body (dry-run-safe
# network install) is exercised for real in Test 1; this test isolates
# only whether cleanup()'s fallback calls the real call site, and how
# many times.
acfs_generated_install_stack_meta_skill() {
    printf 'x' >> "\$SKILLS_COUNTER"
}

# print_summary: counting wrapper around the REAL, unmodified body.
eval "\$(declare -f print_summary | sed '1s/print_summary/__real_print_summary/')"
print_summary() {
    printf 'x' >> "\$SUMMARY_COUNTER"
    __real_print_summary "\$@" >/dev/null 2>&1
}
HAS_GUM=false
EOF
    }

    local scen_a="$workdir/scenario_a.sh"
    write_scenario_common "$scen_a" "scenario_a"
    cat >> "$scen_a" <<'EOF'
# Simulate the real phase-loop's one normal call into the stack category.
# DRY_RUN=true here only keeps the ~25 other real stack.* modules in this
# category network-free (their real paths are covered by Test 1); it has
# no bearing on what Scenario A is proving (the trap's call count).
DRY_RUN=true
acfs_generated_ensure_selection >/dev/null 2>&1
acfs_run_generated_category_phase "stack" "9" >/dev/null 2>&1 || true
# Simulate main()'s own explicit end-of-run call + the flag it sets right
# before that call.
DRY_RUN=false
ACFS_SKILLS_AND_SUMMARY_DONE=1
print_summary
exit 0
EOF

    local scen_b="$workdir/scenario_b.sh"
    write_scenario_common "$scen_b" "scenario_b"
    cat >> "$scen_b" <<'EOF'
DRY_RUN=false
ACFS_INSTALL_RUN_CONFIRMED=1
ACFS_SKILLS_AND_SUMMARY_DONE=0
# Neither function is called here on purpose: simulates a failure that
# bypasses record-and-continue entirely (unhandled set -e exit, signal,
# a bug elsewhere).
exit 1
EOF

    local scen_c="$workdir/scenario_c.sh"
    write_scenario_common "$scen_c" "scenario_c"
    cat >> "$scen_c" <<'EOF'
ACFS_INSTALL_RUN_CONFIRMED=0
ACFS_SKILLS_AND_SUMMARY_DONE=0
exit 0
EOF

    # install.sh's own `set -euo pipefail` leaks into this shell once sourced
    # in run_test_1() (same-process source), so every intentionally-nonzero
    # exit below is explicitly guarded with `|| true`.
    #
    # run_test_1() also `export`s ACFS_GENERATED_SOURCED,
    # ACFS_MANIFEST_INDEX_LOADED and ACFS_GENERATED_SELECTION_READY (that's
    # real install.sh/install_stack.sh behavior, not a test artifact — see
    # source_generated_installers() and acfs_generated_ensure_selection()).
    # Left alone, those would leak into these `bash "$scen_x"` children and
    # make their own detect_environment/source_generated_installers calls
    # silently no-op, leaving ACFS_EFFECTIVE_PLAN (a plain array — bash
    # cannot export arrays to subprocesses) empty while the "already ready"
    # guards report success. `env -u` strips them so each scenario gets a
    # clean, real initialization of its own, matching how a real installer
    # invocation actually starts.
    timeout 60 env -u ACFS_GENERATED_SOURCED -u ACFS_MANIFEST_INDEX_LOADED -u ACFS_GENERATED_SELECTION_READY \
        bash "$scen_a" >/dev/null 2>&1 || true
    timeout 60 env -u ACFS_GENERATED_SOURCED -u ACFS_MANIFEST_INDEX_LOADED -u ACFS_GENERATED_SELECTION_READY \
        bash "$scen_b" >/dev/null 2>&1 || true
    timeout 60 env -u ACFS_GENERATED_SOURCED -u ACFS_MANIFEST_INDEX_LOADED -u ACFS_GENERATED_SELECTION_READY \
        bash "$scen_c" >/dev/null 2>&1 || true

    count_of() { local f="$1"; [[ -f "$f" ]] && wc -c < "$f" || echo 0; }

    local a_skills a_summary b_skills b_summary c_skills c_summary
    a_skills=$(count_of "$workdir/scenario_a.skills.count")
    a_summary=$(count_of "$workdir/scenario_a.summary.count")
    b_skills=$(count_of "$workdir/scenario_b.skills.count")
    b_summary=$(count_of "$workdir/scenario_b.summary.count")
    c_skills=$(count_of "$workdir/scenario_c.skills.count")
    c_summary=$(count_of "$workdir/scenario_c.summary.count")

    echo "Scenario A (nothing failed):        skills_calls=$a_skills  summary_calls=$a_summary"
    echo "Scenario B (crash pre-completion):  skills_calls=$b_skills  summary_calls=$b_summary"
    echo "Scenario C (benign early exit):     skills_calls=$c_skills  summary_calls=$c_summary"

    assert "A1. normal completion: skills installed exactly once (not zero, not twice)" "$([[ "$a_skills" -eq 1 ]] && echo true || echo false)"
    assert "A2. normal completion: summary printed exactly once" "$([[ "$a_summary" -eq 1 ]] && echo true || echo false)"
    assert "B1. crash bypassing record-and-continue: fallback installed skills exactly once" "$([[ "$b_skills" -eq 1 ]] && echo true || echo false)"
    assert "B2. crash bypassing record-and-continue: fallback printed the summary exactly once" "$([[ "$b_summary" -eq 1 ]] && echo true || echo false)"
    assert "C1. benign pre-confirmation exit: fallback did NOT install skills (proves the guard isn't unconditional)" "$([[ "$c_skills" -eq 0 ]] && echo true || echo false)"
    assert "C2. benign pre-confirmation exit: fallback did NOT print a bogus summary" "$([[ "$c_summary" -eq 0 ]] && echo true || echo false)"
}

# ============================================================
# Test 3: success side effects and resume selection are truthful
# ============================================================
run_test_3() {
    local completion_calls=0
    local report_calls=0
    local summary_calls=0
    local webhook_calls=0
    local notification_calls=0

    show_completion() { completion_calls=$((completion_calls + 1)); }
    report_success() { report_calls=$((report_calls + 1)); }
    acfs_summary_emit() { summary_calls=$((summary_calls + 1)); }
    webhook_notify() { webhook_calls=$((webhook_calls + 1)); }
    acfs_notify_install_success() { notification_calls=$((notification_calls + 1)); }

    ACFS_PHASE_FAILURES=("4/9 CLI Tools")
    ACFS_MODULE_FAILURES=("cli.modern (network)")
    SMOKE_TEST_FAILED=false
    acfs_report_success_if_clean 42

    assert "D1. phase/module failure suppresses completion UI" "$([[ $completion_calls -eq 0 ]] && echo true || echo false)"
    assert "D2. phase/module failure suppresses all success integrations" "$([[ $report_calls -eq 0 && $summary_calls -eq 0 && $webhook_calls -eq 0 && $notification_calls -eq 0 ]] && echo true || echo false)"

    ACFS_PHASE_FAILURES=()
    ACFS_MODULE_FAILURES=()
    SMOKE_TEST_FAILED=true
    acfs_report_success_if_clean 42
    assert "D3. smoke-test failure suppresses all success side effects" "$([[ $completion_calls -eq 0 && $report_calls -eq 0 && $summary_calls -eq 0 && $webhook_calls -eq 0 && $notification_calls -eq 0 ]] && echo true || echo false)"

    SMOKE_TEST_FAILED=false
    acfs_report_success_if_clean 42
    assert "D4. clean run emits each success side effect exactly once" "$([[ $completion_calls -eq 1 && $report_calls -eq 1 && $summary_calls -eq 1 && $webhook_calls -eq 1 && $notification_calls -eq 1 ]] && echo true || echo false)"

    ONLY_MODULES=("stack.ntm" "stack.mcp_agent_mail")
    ONLY_PHASES=("9")
    SKIP_MODULES=("stack.cass")
    NO_DEPS=true
    local resume_hint=""
    resume_hint=$(generate_resume_hint "stack" "MCP Agent Mail")
    assert "D5. canonical resume keeps repeated --only selectors" "$([[ "$resume_hint" == *"--only stack.ntm"* && "$resume_hint" == *"--only stack.mcp_agent_mail"* ]] && echo true || echo false)"
    assert "D6. canonical resume keeps phase, skip, and dependency selectors" "$([[ "$resume_hint" == *"--only-phase 9"* && "$resume_hint" == *"--skip stack.cass"* && "$resume_hint" == *"--no-deps"* ]] && echo true || echo false)"

    local generated_categories=""
    local cli_phase_rc=0
    acfs_use_generated_category() { return 0; }
    acfs_run_generated_category_phase() {
        generated_categories+="${generated_categories:+ }$1"
        [[ "$1" != "cli" ]]
    }
    install_cli_tools || cli_phase_rc=$?
    assert "D7. generated CLI failure propagates from install_cli_tools" "$([[ $cli_phase_rc -ne 0 ]] && echo true || echo false)"
    assert "D8. generated CLI failure does not prevent later categories from running" "$([[ "$generated_categories" == "cli network tools" ]] && echo true || echo false)"

    local finalize_body=""
    finalize_body="$(declare -f finalize)"
    assert "D9. finalize does not emit an overall success claim before terminal status is known" "$([[ "$finalize_body" != *'Installation complete!'* && "$finalize_body" == *'Finalization complete'* ]] && echo true || echo false)"

    ONLY_MODULES=()
    ONLY_PHASES=()
    SKIP_MODULES=()
    NO_DEPS=false
}

main() {
    command -v timeout >/dev/null 2>&1 || { echo "timeout(1) is required for this test"; exit 1; }

    echo "== Test 1: module failure does not stop later modules or the summary =="
    run_test_1

    echo
    echo "== Test 2: EXIT trap fires exactly once, and only when it should =="
    run_test_2

    echo
    echo "== Test 3: success reporting and resume selection stay truthful =="
    run_test_3

    echo
    echo "=============================================="
    if [[ "$FAIL" -eq 0 ]]; then
        echo "ALL ASSERTIONS PASSED"
        exit 0
    else
        echo "AT LEAST ONE ASSERTION FAILED"
        exit 1
    fi
}

main "$@"
