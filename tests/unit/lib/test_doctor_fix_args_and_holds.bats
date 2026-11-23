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

doctor_hook_context_fixture() {
    unset _ACFS_DOCTOR_FIX_LOADED
    source "${DOCTOR_FIX_TEST_LIBRARY:-$PROJECT_ROOT/scripts/lib/doctor_fix.sh}"
    HOOK_FIXTURE="$BATS_TEST_TMPDIR/hook-context"
    mkdir -p "$HOOK_FIXTURE/target/.local/bin" "$HOOK_FIXTURE/caller-config"
    TARGET_HOME="$HOOK_FIXTURE/target"
    TARGET_USER=acfs_hook_target
    HOOK_CURRENT_USER=acfs_hook_caller
    HOOK_TRANSPORT=available
    HOOK_RECORD_FAILURE=false
    export CLAUDE_CONFIG_DIR="$HOOK_FIXTURE/caller-config"
    export BASH_ENV="$HOOK_FIXTURE/caller-startup"
    printf 'printf startup > "%s/startup-ran"\n' "$HOOK_FIXTURE" > "$BASH_ENV"
    DOCTOR_FIX_LOG="$HOOK_FIXTURE/doctor.log"
    DOCTOR_FIX_DRY_RUN=false
    FIX_APPLIED=0 FIX_FAILED=0 FIX_SKIPPED=0
    FIXES_DRY_RUN=() FIXES_APPLIED=()
    doctor_fix_runtime_home() { printf '%s\n' "$TARGET_HOME"; }
    doctor_fix_runtime_user() { printf '%s\n' "$TARGET_USER"; }
    doctor_fix_current_user() { printf '%s\n' "$HOOK_CURRENT_USER"; }
    doctor_fix_runtime_path() { printf '%s:/usr/bin:/bin\n' "$TARGET_HOME/.local/bin"; }
    doctor_fix_binary_path() { printf '%s/.local/bin/%s\n' "$TARGET_HOME" "$1"; }
    doctor_fix_system_binary_path() {
        case "$1" in
            sudo|runuser)
                [[ "$HOOK_TRANSPORT" == available ]] || return 1
                printf '%s/transport\n' "$HOOK_FIXTURE"
                ;;
            *) PATH=/usr/sbin:/usr/bin:/sbin:/bin command -v "$1" ;;
        esac
    }
    record_change() {
        printf '%s\n' "$3" > "$HOOK_FIXTURE/undo-command"
        [[ "$HOOK_RECORD_FAILURE" != true ]]
    }
    # Only the OS account-switch boundary is simulated. Production env
    # construction, probe, installer, rollback command and counters run intact.
    cat > "$HOOK_FIXTURE/transport" <<EOF
#!/bin/bash -p
printf '%s\\n' "\$*" >> "$HOOK_FIXTURE/transport.log"
[[ "\${1:-}" != -n ]] || shift
[[ "\${1:-}" == -u && "\${2:-}" == acfs_hook_target ]] || exit 71
shift 2
[[ "\${1:-}" != -- ]] || shift
exec "\$@"
EOF
    cat > "$TARGET_HOME/.local/bin/dcg" <<EOF
#!/bin/bash
config=\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}
printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "\$1" "\$HOME" "\${USER-}" "\$config" "\${BASH_ENV-<unset>}" >> "$HOOK_FIXTURE/events"
case "\$1" in
    doctor) printf '{"hook_installed":false,"checks":[]}\\n' ;;
    install) mkdir -p -- "\$config"; printf 'hook installed\\n' > "\$config/hook-fixture" ;;
    uninstall) printf 'hook rollback\\n' > "\$config/rollback-fixture" ;;
    *) exit 72 ;;
esac
EOF
    chmod +x "$HOOK_FIXTURE/transport" "$TARGET_HOME/.local/bin/dcg"
}

@test "doctor hook context: cross-account probe and repair discard caller configuration and startup hooks" {
    doctor_hook_context_fixture
    fix_dcg_hook stack.dcg
    [[ "$FIX_APPLIED" -eq 1 && "$FIX_FAILED" -eq 0 ]]
    [[ -f "$TARGET_HOME/.claude/hook-fixture" ]] || fail "target hook was not installed"
    [[ ! -e "$HOOK_FIXTURE/caller-config/hook-fixture" ]] || fail "caller Claude configuration was changed"
    [[ ! -e "$HOOK_FIXTURE/startup-ran" ]] || fail "caller shell startup executed during target repair"
    [[ "$(wc -l < "$HOOK_FIXTURE/transport.log")" -eq 2 ]]
    run awk -F '\t' -v home="$TARGET_HOME" '
        $2 != home || $3 != "acfs_hook_target" || $4 != home "/.claude" || $5 != "<unset>" { exit 1 }
        END { if (NR != 2) exit 1 }
    ' "$HOOK_FIXTURE/events"
    assert_success
}

@test "doctor hook context: unavailable account transport refuses repair without caller fallback" {
    doctor_hook_context_fixture
    HOOK_TRANSPORT=missing
    if fix_dcg_hook stack.dcg; then fail "cross-account repair ran without a transport"; fi
    [[ "$FIX_FAILED" -eq 1 && "$FIX_APPLIED" -eq 0 ]]
    [[ ! -e "$HOOK_FIXTURE/events" ]] || fail "target executable ran as the caller"
    [[ ! -e "$HOOK_FIXTURE/undo-command" ]]
}

@test "doctor hook context: journal failure rolls back in the same target account and configuration" {
    doctor_hook_context_fixture
    HOOK_RECORD_FAILURE=true
    if fix_dcg_hook stack.dcg; then fail "journal failure was reported as a successful repair"; fi
    [[ "$FIX_FAILED" -eq 1 && "$FIX_APPLIED" -eq 0 ]]
    [[ -f "$TARGET_HOME/.claude/rollback-fixture" ]] || fail "target hook rollback did not run"
    [[ ! -e "$HOOK_FIXTURE/caller-config/hook-fixture" ]]
    [[ ! -e "$HOOK_FIXTURE/caller-config/rollback-fixture" ]]
    [[ "$(wc -l < "$HOOK_FIXTURE/transport.log")" -eq 3 ]]
    run awk -F '\t' -v home="$TARGET_HOME" '
        $2 != home || $3 != "acfs_hook_target" || $4 != home "/.claude" || $5 != "<unset>" { exit 1 }
        END { if (NR != 3) exit 1 }
    ' "$HOOK_FIXTURE/events"
    assert_success
}

@test "doctor hook context: same-account custom Claude directory survives repair and serialized undo" {
    doctor_hook_context_fixture
    TARGET_USER="$(id -un)"
    HOOK_CURRENT_USER="$TARGET_USER"
    HOOK_TRANSPORT=missing
    mkdir -p "$HOOK_FIXTURE/working directory"
    cd "$HOOK_FIXTURE/working directory"
    export CLAUDE_CONFIG_DIR="custom Claude configuration"
    fix_dcg_hook stack.dcg
    [[ -f "$PWD/$CLAUDE_CONFIG_DIR/hook-fixture" ]]
    [[ ! -e "$HOOK_FIXTURE/transport.log" ]]
    [[ ! -e "$HOOK_FIXTURE/startup-ran" ]]
    doctor_fix_run_rollback_command "$(cat "$HOOK_FIXTURE/undo-command")" false
    [[ -f "$PWD/$CLAUDE_CONFIG_DIR/rollback-fixture" ]] || fail "undo lost the custom Claude config directory"
}

@test "doctor hook context: same-account undo refuses a different replay actor despite forged USER" {
    doctor_hook_context_fixture
    # Account discovery represents an earlier repair by the journal's owner;
    # the undo below deliberately runs as the actual, different test account.
    HOOK_CURRENT_USER="$TARGET_USER"
    HOOK_TRANSPORT=missing
    fix_dcg_hook stack.dcg
    [[ -f "$HOOK_FIXTURE/caller-config/hook-fixture" ]]
    export USER="$TARGET_USER" LOGNAME="$TARGET_USER"
    run doctor_fix_run_rollback_command "$(cat "$HOOK_FIXTURE/undo-command")" false
    assert_failure
    assert_output --partial "Refusing DCG undo as a different account"
    [[ ! -e "$HOOK_FIXTURE/caller-config/rollback-fixture" ]]
    [[ "$(wc -l < "$HOOK_FIXTURE/events")" -eq 2 ]] || fail "undo executed the target binary under a different account"
}

@test "doctor hook context: multiline Claude directories cannot become environment assignments" {
    doctor_hook_context_fixture
    TARGET_USER="$(id -un)"
    HOOK_CURRENT_USER="$TARGET_USER"
    export CLAUDE_CONFIG_DIR="$HOOK_FIXTURE/custom"$'\nRU_NON_INTERACTIVE=1'
    if fix_dcg_hook stack.dcg; then fail "multiline path was accepted as installer assignments"; fi
    [[ "$FIX_FAILED" -eq 1 && "$FIX_APPLIED" -eq 0 ]]
    [[ ! -e "$HOOK_FIXTURE/events" ]]
    [[ ! -e "$HOOK_FIXTURE/undo-command" ]]
}

@test "doctor hook context: dry-run probes only the target account and never installs a hook" {
    doctor_hook_context_fixture
    DOCTOR_FIX_DRY_RUN=true
    fix_dcg_hook stack.dcg
    [[ ${#FIXES_DRY_RUN[@]} -eq 1 && "$FIX_APPLIED" -eq 0 ]]
    [[ ! -e "$TARGET_HOME/.claude/hook-fixture" ]]
    [[ ! -e "$HOOK_FIXTURE/caller-config/hook-fixture" ]]
    [[ ! -e "$HOOK_FIXTURE/undo-command" ]]
    [[ "$(wc -l < "$HOOK_FIXTURE/transport.log")" -eq 1 ]]
    [[ "$(cut -f 1 "$HOOK_FIXTURE/events")" == doctor ]]
}

doctor_agent_mail_context_fixture() {
    unset _ACFS_DOCTOR_FIX_LOADED
    source "${DOCTOR_FIX_TEST_LIBRARY:-$PROJECT_ROOT/scripts/lib/doctor_fix.sh}"
    MAIL_FIXTURE="$BATS_TEST_TMPDIR/mail-context"
    mkdir -p "$MAIL_FIXTURE/target/mcp_agent_mail" "$MAIL_FIXTURE/target/.local/bin" \
        "$MAIL_FIXTURE/caller/storage" "$MAIL_FIXTURE/caller/project"
    TARGET_HOME="$MAIL_FIXTURE/target"
    TARGET_USER=acfs_mail_target
    MAIL_CURRENT_USER=acfs_mail_caller
    MAIL_TRANSPORT=available
    export STORAGE_ROOT="$MAIL_FIXTURE/caller/storage"
    export DATABASE_URL="sqlite:///$MAIL_FIXTURE/caller/caller.sqlite3"
    export XDG_CONFIG_HOME="$MAIL_FIXTURE/caller/config" XDG_DATA_HOME="$MAIL_FIXTURE/caller/data"
    export BASH_ENV="$MAIL_FIXTURE/caller/startup"
    printf 'printf startup > "%s/startup-ran"\n' "$MAIL_FIXTURE" > "$BASH_ENV"
    DOCTOR_FIX_LOG="$MAIL_FIXTURE/doctor.log"
    DOCTOR_FIX_DRY_RUN=false
    FIX_APPLIED=0 FIX_FAILED=0 FIX_SKIPPED=0
    FIXES_DRY_RUN=() FIXES_APPLIED=()
    doctor_fix_runtime_home() { printf '%s\n' "$TARGET_HOME"; }
    doctor_fix_runtime_user() { printf '%s\n' "$TARGET_USER"; }
    doctor_fix_current_user() { printf '%s\n' "$MAIL_CURRENT_USER"; }
    doctor_fix_runtime_path() { printf '%s:/usr/bin:/bin\n' "$TARGET_HOME/.local/bin"; }
    doctor_fix_system_binary_path() {
        case "$1" in
            sudo|runuser)
                [[ "$MAIL_TRANSPORT" != missing ]] || return 1
                printf '%s/transport\n' "$MAIL_FIXTURE"
                ;;
            timeout) printf '%s/timeout\n' "$MAIL_FIXTURE" ;;
            *) PATH=/usr/sbin:/usr/bin:/sbin:/bin command -v "$1" ;;
        esac
    }
    doctor_fix_source_stack_lib() { return 0; }
    _stack_configure_agent_mail_service() { printf service >> "$MAIL_FIXTURE/service-calls"; return 75; }
    doctor_fix_system_curl() { return 0; }
    agent_mail_fix_readiness_ready() { return 0; }
    record_change() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$MAIL_FIXTURE/changes"; }
    # Simulate only the account transport and systemd service. Probe, drain,
    # repair, follow-up fix, environment and timeout dispatch remain real.
    cat > "$MAIL_FIXTURE/transport" <<EOF
#!/bin/bash -p
[[ ! -f "$MAIL_FIXTURE/deny-transport" ]] || exit 71
printf '%s\\n' "\$*" >> "$MAIL_FIXTURE/transport.log"
[[ "\${1:-}" != -n ]] || shift
[[ "\${1:-}" == -u && "\${2:-}" == acfs_mail_target ]] || exit 72
shift 2
[[ "\${1:-}" != -- ]] || shift
exec "\$@"
EOF
    cat > "$MAIL_FIXTURE/timeout" <<EOF
#!/bin/bash -p
printf '%s\\n' "\$*" >> "$MAIL_FIXTURE/deadlines"
[[ "\${1:-}" != --kill-after=5s ]] || shift
case "\${1:-}" in 15s|60s) shift ;; *) exit 74 ;; esac
exec /usr/bin/timeout --kill-after=1s 0.2s "\$@"
EOF
    cat > "$TARGET_HOME/mcp_agent_mail/am" <<EOF
#!/bin/bash
storage=\${STORAGE_ROOT:-\$HOME/.mcp_agent_mail_git_mailbox_repo}
database=\${DATABASE_URL:-sqlite:///\$storage/storage.sqlite3}
config=\${XDG_CONFIG_HOME:-\$HOME/.config}
data=\${XDG_DATA_HOME:-\$HOME/.local/share}
operation=\${2:---version}
printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' \
    "\$operation" "\$HOME" "\${USER-}" "\$PWD" "\$storage" "\$database" "\$config" "\$data" "\${BASH_ENV-<unset>}" >> "$MAIL_FIXTURE/events"
if [[ -f "$MAIL_FIXTURE/hang-\$operation" ]]; then sleep 5; exit 75; fi
case "\${1:-}:\$operation" in
    --version:*) printf 'am 1.0.0\\n' ;;
    doctor:drain)
        if [[ -f "$MAIL_FIXTURE/live-owner" ]]; then
            printf '{"safe_to_mutate":false}\\n'
        else
            printf '{"safe_to_mutate":true}\\n'
        fi ;;
    doctor:repair|doctor:fix)
        mkdir -p -- "\$storage"
        printf '%s\\n' "\$database" > "\$storage/\$operation-ran" ;;
    doctor:check) printf '{"healthy":true}\\n' ;;
    *) exit 76 ;;
esac
EOF
    chmod +x "$MAIL_FIXTURE/transport" "$MAIL_FIXTURE/timeout" "$TARGET_HOME/mcp_agent_mail/am"
    ln -s "$TARGET_HOME/mcp_agent_mail/am" "$TARGET_HOME/.local/bin/am"
    cd "$MAIL_FIXTURE/caller/project"
}

@test "doctor mail context: drain and repair use the target account mailbox and never caller startup" {
    doctor_agent_mail_context_fixture
    fix_mcp_agent_mail stack.mcp_agent_mail
    [[ "$FIX_APPLIED" -eq 2 && "$FIX_FAILED" -eq 0 ]]
    [[ -f "$TARGET_HOME/.mcp_agent_mail_git_mailbox_repo/repair-ran" ]]
    [[ -f "$TARGET_HOME/.mcp_agent_mail_git_mailbox_repo/fix-ran" ]]
    [[ ! -e "$STORAGE_ROOT/repair-ran" && ! -e "$STORAGE_ROOT/fix-ran" ]]
    [[ ! -e "$MAIL_FIXTURE/startup-ran" ]]
    run awk -F '\t' -v home="$TARGET_HOME" '
        $2 != home || $3 != "acfs_mail_target" || $4 != home ||
        $5 != home "/.mcp_agent_mail_git_mailbox_repo" ||
        $6 != "sqlite:///" home "/.mcp_agent_mail_git_mailbox_repo/storage.sqlite3" ||
        $7 != home "/.config" || $8 != home "/.local/share" || $9 != "<unset>" { exit 1 }
        END { if (NR != 5) exit 1 }
    ' "$MAIL_FIXTURE/events"
    assert_success
    [[ "$(wc -l < "$MAIL_FIXTURE/changes")" -eq 2 ]]
    run grep -F 'Manual rollback required: restore Agent Mail' "$MAIL_FIXTURE/changes"
    assert_success
}

@test "doctor mail context: missing account transport refuses all repair side effects" {
    doctor_agent_mail_context_fixture
    MAIL_TRANSPORT=missing
    if fix_mcp_agent_mail stack.mcp_agent_mail; then fail "mail repair ran without an account transport"; fi
    [[ "$FIX_FAILED" -eq 1 && "$FIX_APPLIED" -eq 0 ]]
    [[ ! -e "$MAIL_FIXTURE/events" && ! -e "$MAIL_FIXTURE/changes" && ! -e "$MAIL_FIXTURE/service-calls" ]]
}

@test "doctor mail context: rejected account transport refuses all repair side effects" {
    doctor_agent_mail_context_fixture
    touch "$MAIL_FIXTURE/deny-transport"
    if fix_mcp_agent_mail stack.mcp_agent_mail; then fail "mail repair ignored account switch failure"; fi
    [[ "$FIX_FAILED" -eq 1 && "$FIX_APPLIED" -eq 0 ]]
    [[ ! -e "$MAIL_FIXTURE/events" && ! -e "$MAIL_FIXTURE/changes" && ! -e "$MAIL_FIXTURE/service-calls" ]]
}

@test "doctor mail context: same-account explicit mailbox overrides and relative paths remain intentional" {
    doctor_agent_mail_context_fixture
    TARGET_USER="$(id -un)"
    MAIL_CURRENT_USER="$TARGET_USER"
    MAIL_TRANSPORT=missing
    export STORAGE_ROOT='custom mailbox $(touch must-not-run)'
    export DATABASE_URL="sqlite:///$PWD/custom database.sqlite3"
    fix_mcp_agent_mail stack.mcp_agent_mail
    [[ -f "$PWD/$STORAGE_ROOT/repair-ran" && -f "$PWD/$STORAGE_ROOT/fix-ran" ]]
    [[ "$(cat "$PWD/$STORAGE_ROOT/repair-ran")" == "$DATABASE_URL" ]]
    [[ ! -e "$MAIL_FIXTURE/transport.log" && ! -e "$MAIL_FIXTURE/startup-ran" && ! -e "$PWD/must-not-run" ]]
    run awk -F '\t' -v cwd="$PWD" -v config="$XDG_CONFIG_HOME" -v data="$XDG_DATA_HOME" '
        $4 != cwd || $7 != config || $8 != data || $9 != "<unset>" { exit 1 }
        END { if (NR != 5) exit 1 }
    ' "$MAIL_FIXTURE/events"
    assert_success
}

@test "doctor mail context: cleared public-handoff selectors also discard the foreign working directory" {
    doctor_agent_mail_context_fixture
    # Public dispatch has already changed identity and removed foreign
    # selectors, while retaining its original working directory.
    TARGET_USER="$(id -un)"
    MAIL_CURRENT_USER="$TARGET_USER"
    MAIL_TRANSPORT=missing
    export HOME="$TARGET_HOME"
    unset DATABASE_URL STORAGE_ROOT XDG_CONFIG_HOME XDG_DATA_HOME BASH_ENV
    printf 'AM_FOREIGN_PROJECT_CONFIG=1\n' > "$PWD/.env"
    fix_mcp_agent_mail stack.mcp_agent_mail
    [[ -f "$TARGET_HOME/.mcp_agent_mail_git_mailbox_repo/repair-ran" ]]
    [[ ! -e "$MAIL_FIXTURE/transport.log" ]]
    run awk -F '\t' -v home="$TARGET_HOME" '
        $2 != home || $4 != home || $9 != "<unset>" { exit 1 }
        END { if (NR != 5) exit 1 }
    ' "$MAIL_FIXTURE/events"
    assert_success
}

@test "doctor mail context: drain has a deadline and a timed out attestation never enables mutation" {
    doctor_agent_mail_context_fixture
    touch "$MAIL_FIXTURE/hang-drain"
    run agent_mail_fix_safe_to_mutate "$TARGET_HOME/mcp_agent_mail/am"
    assert_failure 2
    [[ "$(cut -f 1 "$MAIL_FIXTURE/events")" == drain ]]
    run grep -F -- '--kill-after=5s 15s' "$MAIL_FIXTURE/deadlines"
    assert_success
    [[ ! -e "$TARGET_HOME/.mcp_agent_mail_git_mailbox_repo/repair-ran" ]]
}

@test "doctor mail context: timed out database repair never starts the follow-up mutating fix" {
    doctor_agent_mail_context_fixture
    touch "$MAIL_FIXTURE/hang-repair"
    if fix_mcp_agent_mail stack.mcp_agent_mail; then fail "timed out database repair reported success"; fi
    [[ "$FIX_FAILED" -eq 1 && "$FIX_APPLIED" -eq 0 ]]
    run grep -F -- '--kill-after=5s 60s' "$MAIL_FIXTURE/deadlines"
    assert_success
    [[ "$(cut -f 1 "$MAIL_FIXTURE/events")" == $'drain\nrepair' ]]
    [[ ! -e "$MAIL_FIXTURE/changes" ]]
}

@test "doctor mail context: dry-run runs no Agent Mail payload or service mutation" {
    doctor_agent_mail_context_fixture
    DOCTOR_FIX_DRY_RUN=true
    fix_mcp_agent_mail stack.mcp_agent_mail
    [[ "$FIX_APPLIED" -eq 0 && "$FIX_FAILED" -eq 0 && ${#FIXES_DRY_RUN[@]} -eq 1 ]]
    [[ ! -e "$MAIL_FIXTURE/events" && ! -e "$MAIL_FIXTURE/changes" && ! -e "$MAIL_FIXTURE/service-calls" ]]
}

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
    source "${DOCTOR_FIX_TEST_LIBRARY:-$PROJECT_ROOT/scripts/lib/doctor_fix.sh}"
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
        failed-command|optional-failed-command)
            check_shell() { :; }
            mkdir -p "$HOME/.local/bin"
            local binary=""
            for binary in codex claude dcg am ru; do
                printf '#!/bin/bash\nprintf "fixture version 1.0\\n"\nexit 42\n' > "$HOME/.local/bin/$binary"
                chmod +x "$HOME/.local/bin/$binary"
            done
            DOCTOR_VERSION_TIMEOUT=5
            # Never touch a real service/hook or invoke an installer if the
            # regression routes a known broken launcher to the wrong fixer.
            fix_dcg_hook() { printf 'dcg hook\n' >> "$HOME/unrelated-repair-ran"; }
            fix_mcp_agent_mail() { printf 'agent mail service\n' >> "$HOME/unrelated-repair-ran"; }
            doctor_fix_run_verified_installer() { printf 'verified installer\n' >> "$HOME/unrelated-repair-ran"; return 91; }
            doctor_fix_run_verified_installer_with_env() { printf 'verified installer\n' >> "$HOME/unrelated-repair-ran"; return 91; }
            if [[ "$scenario" == optional-failed-command ]]; then
                check_stack() { check_optional_command stack.ru RU ru "repair-ru --keep-config"; }
            else
                check_agents() {
                    check_command agent.codex Codex codex "repair-codex --keep-config"
                    check_command agent.claude Claude claude "repair-claude --keep-config"
                }
                check_stack() {
                    check_command stack.dcg DCG dcg "repair-dcg --keep-config"
                    check_command stack.mcp_agent_mail "Agent Mail" am "repair-am --keep-config"
                }
            fi
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

@test "broken installed commands remain manual repairs with original hints and no mutations" {
    run run_isolated_doctor_repair failed-command --yes --json
    assert_failure 1
    run jq -e '.summary.fail == 4 and .fixes.applied == 0 and .fixes.failed == 0 and .fixes.manual == 4 and .fixes.planned == 0 and .fixes.finalized' "$HOME/result.out"
    assert_success
    run jq -e '.checks | any(.id == "agent.codex" and .status == "fail" and .fix == "repair-codex --keep-config")' "$HOME/result.out"
    assert_success
    run grep -F 'repair-codex --keep-config' "$HOME/result.err"
    assert_success
    run grep -F 'already installed' "$HOME/result.err"
    assert_failure
    [[ ! -e "$HOME/unrelated-repair-ran" ]]
    [[ ! -s "$HOME/.acfs/autofix/changes.jsonl" ]]
    run cat "$HOME/.local/bin/codex"
    assert_output $'#!/bin/bash\nprintf "fixture version 1.0\\n"\nexit 42'
}

@test "broken command repair previews report manual work without claiming no fixes needed" {
    run run_isolated_doctor_repair failed-command --yes --dry-run --json
    assert_failure 1
    run jq -e '.fixes.dry_run and .fixes.manual == 4 and .fixes.applied == 0 and .fixes.planned == 0' "$HOME/result.out"
    assert_success
    run grep -F 'Manual fixes needed:' "$HOME/result.err"
    assert_success
    run grep -F 'No fixes needed.' "$HOME/result.err"
    assert_failure
    [[ ! -e "$HOME/unrelated-repair-ran" ]]
    [[ ! -e "$HOME/.acfs/autofix/changes.jsonl" ]]
}

@test "broken command manual repairs respect exact selection" {
    run run_isolated_doctor_repair failed-command --yes --only agent.codex --json
    assert_failure 1
    run jq -e '.summary.fail == 4 and .fixes.manual == 1 and .fixes.filtered == 3 and .fixes.applied == 0 and .fixes.selection_valid and .fixes.finalized' "$HOME/result.out"
    assert_success
    run grep -F 'repair-codex --keep-config' "$HOME/result.err"
    assert_success
    run grep -F 'repair-claude --keep-config' "$HOME/result.err"
    assert_failure
    [[ ! -e "$HOME/unrelated-repair-ran" ]]
}

@test "invalid selection cannot report broken command manual repairs as dispatched" {
    run run_isolated_doctor_repair failed-command --yes --only agent.codex,agent.typo --json
    assert_failure 2
    run jq -e '.summary.fail == 4 and .fixes.manual == 0 and .fixes.applied == 0 and .fixes.selection_valid == false' "$HOME/result.out"
    assert_success
    [[ ! -e "$HOME/unrelated-repair-ran" ]]
}

@test "optional broken command manual repairs retain warning opt-in" {
    run run_isolated_doctor_repair optional-failed-command --only stack.ru --json
    assert_success
    run jq -e '.summary.warn == 1 and .fixes.manual == 0 and .fixes.applied == 0 and .fixes.warning_fixes_enabled == false' "$HOME/result.out"
    assert_success
    [[ ! -e "$HOME/unrelated-repair-ran" ]]

    run run_isolated_doctor_repair optional-failed-command --yes --only stack.ru --json
    assert_success
    run jq -e '.summary.warn == 1 and .fixes.manual == 1 and .fixes.applied == 0 and .fixes.failed == 0 and .fixes.warning_fixes_enabled' "$HOME/result.out"
    assert_success
    run grep -F 'repair-ru --keep-config' "$HOME/result.err"
    assert_success
    [[ ! -e "$HOME/unrelated-repair-ran" ]]
}

@test "broken command repair signals reset for the next invocation" {
    SCRIPT_DIR="$PROJECT_ROOT/scripts/lib"
    unset _ACFS_AUTOFIX_SOURCED _ACFS_DOCTOR_FIX_LOADED
    # shellcheck source=../../../scripts/lib/doctor_fix.sh
    source "${DOCTOR_FIX_TEST_LIBRARY:-$PROJECT_ROOT/scripts/lib/doctor_fix.sh}"
    doctor_fix_runtime_user() { id -un; }
    DOCTOR_FIX_LOG="$HOME/doctor-fix.log"
    run_doctor_fix --dry-run >/dev/null
    doctor_fix_mark_failed_command agent.codex
    dispatch_fix agent.codex fail "repair-codex" >/dev/null
    [[ "$FIX_MANUAL" -eq 1 ]]

    run_doctor_fix --dry-run >/dev/null
    # An ordinary missing-command finding must reach its installer again;
    # the prior run's known-broken policy cannot turn it into manual work.
    fix_stack_install() { printf '%s\n' "$1" > "$HOME/missing-command-dispatched"; }
    dispatch_fix agent.codex fail "install-codex" >/dev/null
    [[ "$FIX_MANUAL" -eq 0 ]]
    run cat "$HOME/missing-command-dispatched"
    assert_output agent.codex
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
