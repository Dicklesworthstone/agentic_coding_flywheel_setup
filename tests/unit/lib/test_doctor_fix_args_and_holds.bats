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

@test "doctor --only requires a value" {
    run bash "$DOCTOR_SH" --fix --only
    assert_failure 2
    assert_output --partial "--only requires"

    run bash "$DOCTOR_SH" --fix --only=
    assert_failure 2
    assert_output --partial "--only requires"
}

@test "doctor --help documents --yes, --prompt and --only" {
    run bash "$DOCTOR_SH" --help
    assert_success
    assert_output --partial "--yes, -y"
    assert_output --partial "--prompt"
    assert_output --partial "--only <c>"
    assert_output --partial "acfs doctor --fix --yes"
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
