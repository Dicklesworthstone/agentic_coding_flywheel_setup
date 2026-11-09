#!/usr/bin/env bats

# doctor.sh: fix-mode argument forwarding (#401) and version-hold reporting (#403)
#
# #401 `acfs doctor --fix --yes` dropped --yes in doctor.sh's argument loop
#      (`*) shift`), so run_doctor_fix never saw it and every warning-level
#      fixer stayed unreachable from the CLI while the hint kept pointing at
#      that exact command.
# #403 every unexpired hold was a WARN with the hint `acfs unhold <tool>`,
#      including the "stale installer pin" holds security.sh tells users to
#      create, so doctor could never be clean while a pin was stale and its
#      one suggestion undid the mitigation.
#
# doctor.sh ends in `main "$@"`; the holds tests load its functions by
# stripping that line (same technique as test_doctor_distro_family.bats).

load '../test_helper'

setup() {
    common_setup
    DOCTOR_SH="$PROJECT_ROOT/scripts/lib/doctor.sh"
    [[ -f "$DOCTOR_SH" ]] || fail "doctor.sh not found at $DOCTOR_SH"
    export HOME="$(create_temp_dir)"
    export TARGET_HOME="$HOME"
    unset TARGET_USER ACFS_HOME
}

teardown() {
    common_teardown
}

load_doctor_functions() {
    local last_line=""
    last_line="$(tail -n 1 "$DOCTOR_SH")"
    [[ "$last_line" == 'main "$@"' ]] \
        || fail "doctor.sh no longer ends in 'main \"\$@\"' (got: $last_line)"
    # shellcheck disable=SC1090
    source <(sed '$d' "$DOCTOR_SH") >/dev/null 2>&1 || true
}

# ============================================================
# #401 — fix-mode options reach run_doctor_fix
# ============================================================

@test "doctor rejects unknown options instead of silently dropping them" {
    run bash "$DOCTOR_SH" --fix --yess --dry-run --json
    assert_failure 2
    assert_output --partial "unknown option '--yess'"
}

@test "doctor still refuses unimplemented prompting" {
    run bash "$DOCTOR_SH" --fix --dry-run --prompt
    assert_failure 2
    assert_output --partial "is not supported yet"
}

@test "doctor --help documents targeted repairs and warning opt-in" {
    run bash "$DOCTOR_SH" --help
    assert_success
    assert_output --partial "--yes, -y"
    refute_output --partial "--prompt"
    assert_output --partial "--only <selectors>"
    assert_output --partial "dotted IDs match exactly"
    assert_output --partial "acfs doctor --fix --yes"
}

@test "doctor refuses --only without fix mode and missing selector values" {
    run bash "$DOCTOR_SH" --only path --json
    assert_failure 2
    assert_output --partial "--only requires --fix"
    run bash "$DOCTOR_SH" --fix --only --json
    assert_failure 2
    assert_output --partial "--only requires a check ID or category"
}

@test "doctor --fix --yes forwards --yes to run_doctor_fix" {
    # Dry-run keeps the run read-only; the fix log records which tier of
    # fixes the run was allowed to apply, which is exactly what #401 lost.
    export DOCTOR_FIX_LOG="$HOME/doctor-fix.log"
    run bash "$DOCTOR_SH" --fix --dry-run --yes --json
    [[ -f "$DOCTOR_FIX_LOG" ]] || fail "doctor fix log was not written at $DOCTOR_FIX_LOG"
    run grep -F "warning-level fixes enabled (--yes)" "$DOCTOR_FIX_LOG"
    assert_success
    run grep -F "warning left as-is" "$DOCTOR_FIX_LOG"
    assert_failure
}

@test "doctor --fix without --yes keeps warning-level fixes off" {
    export DOCTOR_FIX_LOG="$HOME/doctor-fix.log"
    run bash "$DOCTOR_SH" --fix --dry-run --json
    [[ -f "$DOCTOR_FIX_LOG" ]] || fail "doctor fix log was not written at $DOCTOR_FIX_LOG"
    run grep -F "warning-level fixes disabled" "$DOCTOR_FIX_LOG"
    assert_success
}

# ============================================================
# Repair execution and undo lifecycle
# ============================================================

# Exercise the actual doctor command, dispatcher, PATH repair and undo journal
# in a private home. Only host diagnostics and account discovery are replaced;
# these tests must never repair the machine running the suite.
run_isolated_doctor_repair() {
    # The installed doctor does not enable errexit. Bats' own errexit must not
    # hide missing error propagation in the actual command.
    set +e
    local scenario="$1"
    shift
    local fixture_home="$HOME"
    load_doctor_functions
    HOME="$fixture_home"
    TARGET_HOME="$fixture_home"
    ACFS_HOME="$fixture_home/.acfs"
    SCRIPT_DIR="$PROJECT_ROOT/scripts/lib"
    unset _ACFS_AUTOFIX_SOURCED _ACFS_DOCTOR_FIX_LOADED
    # shellcheck source=../../../scripts/lib/doctor_fix.sh
    source "$PROJECT_ROOT/scripts/lib/doctor_fix.sh"
    doctor_fix_runtime_home() { printf '%s\n' "$HOME"; }
    doctor_fix_runtime_acfs_home() { printf '%s\n' "$HOME/.acfs"; }
    doctor_fix_runtime_user() { id -un; }
    doctor_runtime_home() { printf '%s\n' "$HOME"; }
    JSON_MODE=false
    FIX_MODE=false
    DRY_RUN_MODE=false
    DEEP_MODE=false
    HAS_GUM=false
    QUIET_MODE=false
    FIX_ARGS=()
    JSON_CHECKS=()
    PASS_COUNT=0; WARN_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
    DOCTOR_FIX_LOG="$HOME/doctor-fix.log"
    ACFS_STATE_DIR="$HOME/.acfs/autofix"
    ACFS_CHANGES_FILE="$ACFS_STATE_DIR/changes.jsonl"
    ACFS_UNDOS_FILE="$ACFS_STATE_DIR/undos.jsonl"
    ACFS_BACKUPS_DIR="$ACFS_STATE_DIR/backups"
    ACFS_LOCK_FILE="$ACFS_STATE_DIR/.lock"
    ACFS_INTEGRITY_FILE="$ACFS_STATE_DIR/.integrity"
    ACFS_AUTOFIX_INITIALIZED=false
    check_identity() { : > "$HOME/checks-ran"; check identity.user "Identity" pass; }
    check_ubuntu_archive_suites() { :; }
    check_workspace() { :; }
    check_shell() { check path.local_bin "Local PATH" warn "missing PATH entries"; }
    check_core_tools() { :; }
    check_agents() { :; }
    check_credential_sources() { :; }
    check_cloud() { :; }
    check_stack() { :; }
    check_service_binary_drift() { :; }
    check_utilities() { :; }
    check_updates_health() { :; }
    check_manifest_supplemental() { :; }
    show_skipped_tools() { :; }
    run_deep_checks() { :; }
    case "$scenario" in
        init-failure)
            start_autofix_session() { printf 'session locked\n' >&2; return 73; }
            ;;
        finalization-failure)
            end_autofix_session() { printf 'journal unavailable\n' >&2; return 74; }
            ;;
        missing-helper)
            unset -f run_doctor_fix
            ;;
        missing-selection-helper)
            unset -f doctor_fix_validate_selection
            ;;
        repair-failure)
            fix_path_ordering() { printf 'repair failed\n'; return 75; }
            ;;
        counted-repair-failure)
            fix_path_ordering() { FIX_FAILED=$((FIX_FAILED + 1)); return 75; }
            ;;
        scoped-findings)
            check_shell() {
                check path.local_bin "Local PATH" warn "missing PATH entries"
                check path.local_binary "Similar check ID" fail "must remain untouched" "manual PATH inspection"
                check shell.ohmyzsh "Unrelated shell failure" fail "missing shell prerequisite" "manual shell inspection"
            }
            ;;
        scoped-timeout)
            run_deep_checks() {
                check_with_timeout_status deep.cloud.vercel_auth "Vercel auth" timeout "probe timed out" "retry later"
            }
            ;;
        healthy-selection)
            check_shell() {
                check path.local_bin "Local PATH" pass
                check_skipped path.optional "Optional PATH" "intentionally skipped"
                check shell.fixture_missing "Unrelated warning" warn "missing shell prerequisite" "manual shell inspection"
            }
            ;;
    esac
    main doctor --fix "$@" > "$HOME/result.out" 2> "$HOME/result.err"
}

@test "doctor JSON repair applies the real PATH fix and records its undo" {
    printf '# existing shell configuration\n' > "$HOME/.zshrc"
    run run_isolated_doctor_repair normal --yes --json
    assert_success
    run grep -F '# ACFS PATH ordering (added by doctor --fix)' "$HOME/.zshrc"
    assert_success
    run jq -e '.checks | any(.id == "path.local_bin" and .status == "warn")' "$HOME/result.out"
    assert_success
    run jq -se 'length > 0' "$HOME/.acfs/autofix/changes.jsonl"
    assert_success
    run grep -F 'Applied: 1' "$HOME/result.err"
    assert_success
}

@test "doctor JSON dry-run previews the real repair without changing shell files" {
    printf '# preserve this configuration\n' > "$HOME/.zshrc"
    run run_isolated_doctor_repair normal --yes --dry-run --json
    assert_success
    run cat "$HOME/.zshrc"
    assert_output '# preserve this configuration'
    run jq -e '.summary.warn == 1' "$HOME/result.out"
    assert_success
    run grep -F 'fix.path.ordering' "$HOME/result.err"
    assert_success
    [[ ! -e "$HOME/.acfs/autofix/changes.jsonl" ]]
}

@test "doctor text repair still applies the PATH fix and records its undo" {
    printf '# existing text-mode configuration\n' > "$HOME/.zshrc"
    run run_isolated_doctor_repair normal --yes
    assert_success
    run grep -F '# ACFS PATH ordering (added by doctor --fix)' "$HOME/.zshrc"
    assert_success
    run jq -se 'length > 0' "$HOME/.acfs/autofix/changes.jsonl"
    assert_success
    run grep -F 'Applied: 1' "$HOME/result.out"
    assert_success
}

@test "doctor JSON repair preserves the warning-level opt-in" {
    printf '# leave warning alone\n' > "$HOME/.zshrc"
    run run_isolated_doctor_repair normal --json
    assert_success
    run cat "$HOME/.zshrc"
    assert_output '# leave warning alone'
    run grep -F 'warning left as-is' "$HOME/result.err"
    assert_success
    run jq -e '.summary.warn == 1' "$HOME/result.out"
    assert_success
}

@test "doctor aborts repairs when the undo session cannot start" {
    printf '# unchanged after session failure\n' > "$HOME/.zshrc"
    run run_isolated_doctor_repair init-failure --yes
    assert_failure
    run cat "$HOME/.zshrc"
    assert_output '# unchanged after session failure'
    run grep -F 'Failed to start autofix session' "$HOME/result.err"
    assert_success
    [[ ! -e "$HOME/.acfs/autofix/changes.jsonl" ]]
    [[ ! -e "$HOME/checks-ran" ]]
}

@test "doctor fails when repair support is unavailable" {
    run run_isolated_doctor_repair missing-helper --json
    assert_failure
    run grep -F -- '--fix unavailable' "$HOME/result.err"
    assert_success
    [[ ! -s "$HOME/result.out" ]]
}

@test "doctor propagates undo finalization failure even when checks have no failures" {
    run run_isolated_doctor_repair finalization-failure --json
    assert_failure
    run jq -e '.summary.fail == 0' "$HOME/result.out"
    assert_success
    run grep -F 'Failed to finalize autofix session' "$HOME/result.err"
    assert_success
}

@test "doctor records repair failure and keeps structured output valid" {
    run run_isolated_doctor_repair repair-failure --yes --json
    assert_failure
    run jq -e '.summary.fail == 0 and (.checks | length == 2) and .fixes.failed == 1 and .fixes.finalized' "$HOME/result.out"
    assert_success
    run grep -F 'repair failed' "$HOME/result.err"
    assert_success
    run grep -F 'Failed:  1' "$HOME/result.err"
    assert_success
}

@test "doctor does not count an already recorded repair failure twice" {
    run run_isolated_doctor_repair counted-repair-failure --yes --json
    assert_failure
    run jq -e '.summary.fail == 0' "$HOME/result.out"
    assert_success
    run grep -F 'Failed:  1' "$HOME/result.err"
    assert_success
}

@test "scoped JSON repair changes only the exact check and retains unrelated failures" {
    printf '# targeted repair\n' > "$HOME/.zshrc"
    run run_isolated_doctor_repair scoped-findings --yes --only path.local_bin --json
    assert_failure 1
    run grep -F '# ACFS PATH ordering (added by doctor --fix)' "$HOME/.zshrc"
    assert_success
    run jq -e '.summary.fail == 2 and (.checks | length == 4) and .fixes.selectors == ["path.local_bin"] and .fixes.applied == 1 and .fixes.filtered == 2 and .fixes.manual == 0 and .fixes.selection_valid and .fixes.finalized' "$HOME/result.out"
    assert_success
    run jq -se 'length == 1' "$HOME/.acfs/autofix/changes.jsonl"
    assert_success
}

@test "scoped category preview selects its findings without changing files" {
    printf '# preview remains read-only\n' > "$HOME/.zshrc"
    run run_isolated_doctor_repair scoped-findings --yes --only=path --dry-run --json
    assert_failure 1
    run cat "$HOME/.zshrc"
    assert_output '# preview remains read-only'
    run jq -e '.summary.fail == 2 and .fixes.dry_run and .fixes.planned == 2 and .fixes.filtered == 1 and .fixes.applied == 0' "$HOME/result.out"
    assert_success
    [[ ! -e "$HOME/.acfs/autofix/changes.jsonl" ]]
}

@test "scoped repeated selectors union and deduplicate before repair" {
    run run_isolated_doctor_repair scoped-findings --yes --only path.local_bin --only=shell,path.local_bin --dry-run --json
    assert_failure 1
    run jq -e '.fixes.selectors == ["path.local_bin", "shell"] and .fixes.planned == 1 and .fixes.manual == 1 and .fixes.filtered == 1' "$HOME/result.out"
    assert_success
}

@test "mixed known and unknown selectors prevent every repair" {
    printf '# preserve on selection error\n' > "$HOME/.zshrc"
    run run_isolated_doctor_repair scoped-findings --yes --only path.local_bin,path.typo --json
    assert_failure 2
    run cat "$HOME/.zshrc"
    assert_output '# preserve on selection error'
    run jq -e '.fixes.selection_valid == false and .fixes.applied == 0 and .fixes.planned == 0 and .summary.fail == 2' "$HOME/result.out"
    assert_success
    [[ ! -s "$HOME/.acfs/autofix/changes.jsonl" ]]
    run grep -F 'no repairs applied' "$HOME/result.err"
    assert_success
}

@test "malformed selector lists abort before diagnostics or repair sessions" {
    run run_isolated_doctor_repair normal --yes --only 'path,,shell' --json
    assert_failure 2
    [[ ! -e "$HOME/checks-ran" ]]
    [[ ! -e "$HOME/.acfs/autofix/changes.jsonl" ]]
}

@test "targeted repairs fail closed when the installed fixer lacks selection support" {
    run run_isolated_doctor_repair missing-selection-helper --yes --only path --json
    assert_failure 2
    [[ ! -e "$HOME/checks-ran" ]]
    [[ ! -e "$HOME/.acfs/autofix/changes.jsonl" ]]
    run grep -F 'targeted repairs are unavailable' "$HOME/result.err"
    assert_success
}

@test "targeted warning repairs still require yes" {
    printf '# warning is advisory\n' > "$HOME/.zshrc"
    run run_isolated_doctor_repair normal --only path.local_bin --json
    assert_success
    run cat "$HOME/.zshrc"
    assert_output '# warning is advisory'
    run jq -e '.fixes.selection_valid and .fixes.applied == 0 and .fixes.warning_fixes_enabled == false and .summary.warn == 1' "$HOME/result.out"
    assert_success
}

@test "healthy and intentionally skipped selected checks are valid no-ops" {
    run run_isolated_doctor_repair healthy-selection --yes --only path.local_bin,path.optional --dry-run --json
    assert_success
    run jq -e '.fixes.selection_valid and .fixes.planned == 0 and .fixes.filtered == 1 and .summary.skip == 1' "$HOME/result.out"
    assert_success
}

@test "timed out deep checks are selectable but never repaired" {
    run run_isolated_doctor_repair scoped-timeout --deep --yes --only deep.cloud.vercel_auth --dry-run --json
    assert_success
    run jq -e '.fixes.selection_valid and .fixes.planned == 0 and .fixes.manual == 0 and (.checks | any(.id == "deep.cloud.vercel_auth" and .status == "timeout"))' "$HOME/result.out"
    assert_success
}

@test "JSON fix report includes journal finalization failure" {
    run run_isolated_doctor_repair finalization-failure --only path --json
    assert_failure 1
    run jq -e '.fixes.selection_valid and .fixes.finalized == false' "$HOME/result.out"
    assert_success
}

# ============================================================
# #403 — holds are reported, not flagged
# ============================================================

run_updates_health_json() {
    load_doctor_functions
    JSON_MODE=true
    HAS_GUM=false
    JSON_CHECKS=()
    PASS_COUNT=0; WARN_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
    section() { :; }
    doctor_runtime_home() { printf '%s\n' "$HOME"; }
    _acfs_doctor_find_lib_script() { printf '%s\n' "$PROJECT_ROOT/scripts/lib/$1"; }
    check_updates_health
    printf '%s\n' "${JSON_CHECKS[@]}"
}

@test "an unexpired hold passes and does not suggest unholding" {
    export ACFS_HOLDS_FILE="$HOME/.acfs/holds.yaml"
    source_lib "holds"
    acfs_holds_add ubs current henry "stale installer pin: upstream installer changed after ACFS 0.9.0 checksum pin" "2099-01-02"

    run run_updates_health_json
    assert_success
    assert_output --partial '"id":"updates.holds.ubs"'
    assert_output --partial '"status":"pass"'
    assert_output --partial 'until 2099-01-02'
    assert_output --partial "no longer reports a checksum mismatch for ubs"
    refute_output --partial '"fix":"acfs unhold ubs"'
}

@test "a hold with no expiry warns and asks for an end date" {
    export ACFS_HOLDS_FILE="$HOME/.acfs/holds.yaml"
    source_lib "holds"
    acfs_holds_add br current henry "0.5.2 cannot read existing beads DBs"

    run run_updates_health_json
    assert_success
    assert_output --partial '"id":"updates.holds.br"'
    assert_output --partial '"status":"warn"'
    assert_output --partial 'indefinitely'
    assert_output --partial 'acfs hold br --reason'
}

@test "an expired hold still warns" {
    export ACFS_HOLDS_FILE="$HOME/.acfs/holds.yaml"
    mkdir -p "$HOME/.acfs"
    cat > "$ACFS_HOLDS_FILE" <<'EOF'
holds:
  cass:
    held_version: "current"
    owner: "henry"
    reason: "old"
    expiry: "2000-01-01"
EOF

    run run_updates_health_json
    assert_success
    assert_output --partial '"id":"updates.holds.cass"'
    assert_output --partial '"status":"warn"'
    assert_output --partial 'EXPIRED'
    assert_output --partial 'acfs unhold cass'
}

# ============================================================
# #448 — nightly skips are visible
# ============================================================

write_nightly_state() {
    mkdir -p "$HOME/.acfs"
    printf '1\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" > "$HOME/.acfs/nightly-update.state"
}

@test "a nightly that keeps skipping warns and points at a manual update" {
    local now
    now=$(date +%s)
    write_nightly_state skipped load "$now" $((now - 5 * 86400)) $((now - 4 * 86400)) 2026-10-13 4 3 0

    run run_updates_health_json
    assert_success
    assert_output --partial '"id":"updates.nightly_runs","label":"Nightly update runs","status":"warn","details":"retry budget exhausted (load); 4 skipped night(s) since last full success"'
    assert_output --partial '"fix":"ACFS_NIGHTLY_MAX_RETRIES=0 ~/.acfs/scripts/nightly-update.sh  # resource-checked retry; acfs update --yes skips the load gate"'
}

@test "a nightly that ran passes, an unreadable record warns, no record is silent" {
    local now
    now=$(date +%s)
    write_nightly_state success none "$now" "$now" 0 - 0 1 0
    run run_updates_health_json
    assert_success
    assert_output --partial '"id":"updates.nightly_runs","label":"Nightly update runs","status":"pass","details":"last recorded update completed successfully"'

    printf 'not a record\n' > "$HOME/.acfs/nightly-update.state"
    run run_updates_health_json
    assert_success
    assert_output --partial '"id":"updates.nightly_runs","label":"Nightly update runs","status":"warn","details":"execution record unreadable or invalid; inspect local update logs"'
    assert_output --partial 'nightly-update.state.bad'

    rm -f "$HOME/.acfs/nightly-update.state"
    run run_updates_health_json
    assert_success
    refute_output --partial 'updates.nightly_runs'
}

@test "doctor never sources a nightly wrapper without the health API marker" {
    # Pre-API wrappers ran the whole update when sourced.
    local now old_lib="$HOME/old-lib"
    now=$(date +%s)
    write_nightly_state skipped load "$now" 0 "$now" 2026-10-13 1 3 0
    mkdir -p "$old_lib"
    printf '#!/usr/bin/env bash\ntouch "%s/sourced"\n' "$HOME" > "$old_lib/nightly_update.sh"

    load_doctor_functions
    JSON_MODE=true
    HAS_GUM=false
    JSON_CHECKS=()
    PASS_COUNT=0; WARN_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0
    _acfs_doctor_find_lib_script() { printf '%s\n' "$old_lib/$1"; }
    _acfs_doctor_find_scripts_script() { return 1; }
    check_nightly_health "$HOME/.acfs/nightly-update.state"

    [[ ! -e "$HOME/sourced" ]] || fail "doctor sourced a wrapper without the health API marker"
    [[ "${JSON_CHECKS[*]}" == *'"status":"warn","details":"execution record present but no nightly health reader is deployed"'* ]] \
        || fail "unexpected checks: ${JSON_CHECKS[*]}"
}
