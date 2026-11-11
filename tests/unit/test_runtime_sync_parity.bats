#!/usr/bin/env bats
#
# Issue #387: install.sh's runtime install (install_asset calls) and
# scripts/lib/update.sh's runtime sync (file_pairs) are two hand-maintained
# lists of the same ~/.acfs runtime. holds.sh was in the update list but not
# the install list, so the `acfs hold` remediation printed by the checksum
# error did not exist on a fresh install. These tests pin the two lists to
# each other for every scripts/lib/*.sh runtime library so they cannot drift
# apart again, and check holds.sh specifically.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    INSTALL_SH="$PROJECT_ROOT/install.sh"
    UPDATE_SH="$PROJECT_ROOT/scripts/lib/update.sh"
    GENERATE_TS="$PROJECT_ROOT/packages/manifest/src/generate.ts"
    DRIFT_SH="$PROJECT_ROOT/scripts/check-manifest-drift.sh"
}

# scripts/lib/*.sh sources that install.sh copies into the runtime.
_install_lib_sources() {
    grep -o 'install_asset "scripts/lib/[^"]*\.sh"' "$INSTALL_SH" \
        | sed 's/install_asset "//; s/"$//' | sort -u
}

# scripts/lib/*.sh sources in update.sh's file_pairs (repo side of "src:dst").
_update_lib_sources() {
    awk '
        /^    local -a file_pairs=\(/ { capture = 1; next }
        capture && /^    \)/ { exit }
        capture && /^ *"scripts\/lib\/[^":]*\.sh:/ {
            gsub(/"/, ""); sub(/^ +/, ""); sub(/:.*$/, ""); print
        }
    ' "$UPDATE_SH" | sort -u
}

@test "install.sh installs holds.sh into the runtime (acfs hold works on a fresh install)" {
    run grep -F 'install_asset "scripts/lib/holds.sh" "$ACFS_HOME/scripts/lib/holds.sh"' "$INSTALL_SH"
    [[ "$status" -eq 0 ]]
    # install_asset refuses anything outside the internal checksum ledger, so
    # the file must be a ledger member in every enumeration of that set.
    # Either quote style: the generator is formatted with double quotes now.
    grep -Eq "[\"']scripts/lib/holds\\.sh[\"']," "$GENERATE_TS"
    grep -Eq '^        scripts/lib/holds\.sh$' "$INSTALL_SH"
    grep -Eq '^    scripts/lib/holds\.sh$' "$DRIFT_SH"
    grep -Fq '[scripts/lib/holds.sh]=' "$PROJECT_ROOT/scripts/generated/internal_checksums.sh"
}

@test "every scripts/lib runtime library synced by update.sh is installed by install.sh" {
    local missing=""
    local src
    while IFS= read -r src; do
        [[ -n "$src" ]] || continue
        # The newproj wizard screens are installed by install.sh through a
        # loop over scripts/lib/newproj_screens/*.sh, not per-file calls.
        [[ "$src" == scripts/lib/newproj_screens/* ]] && continue
        if ! _install_lib_sources | grep -Fxq "$src"; then
            missing+="$src "
        fi
    done < <(_update_lib_sources)
    [[ -z "$missing" ]] || {
        echo "synced by update.sh but never installed by install.sh: $missing" >&2
        return 1
    }
}

@test "doctor runtime always includes the shared login-shell validator" {
    grep -Fq 'install_asset "scripts/lib/user.sh" "$ACFS_HOME/scripts/lib/user.sh"' "$INSTALL_SH"
    grep -Fq '"scripts/lib/user.sh:scripts/lib/user.sh"' "$UPDATE_SH"
    grep -Fq 'source "$user_lib"' "$PROJECT_ROOT/scripts/lib/doctor.sh"
    grep -Fq 'user_login_shell_configured "$TARGET_USER"' "$PROJECT_ROOT/scripts/lib/doctor.sh"
}

@test "every scripts/lib runtime library installed by install.sh is synced by update.sh" {
    local missing=""
    local src
    while IFS= read -r src; do
        [[ -n "$src" ]] || continue
        if ! _update_lib_sources | grep -Fxq "$src"; then
            missing+="$src "
        fi
    done < <(_install_lib_sources)
    [[ -z "$missing" ]] || {
        echo "installed by install.sh but never refreshed by acfs update: $missing" >&2
        return 1
    }
}

@test "the parity helpers see both lists (guards against a silent empty comparison)" {
    local install_count update_count
    install_count="$(_install_lib_sources | wc -l | tr -d ' ')"
    update_count="$(_update_lib_sources | wc -l | tr -d ' ')"
    (( install_count > 40 ))
    (( update_count > 40 ))
    _install_lib_sources | grep -Fxq "scripts/lib/security.sh"
    _update_lib_sources | grep -Fxq "scripts/lib/security.sh"
}

@test "install.sh admits CHANGELOG.md as inert data and deploys it for acfs changelog" {
    # install_asset refuses anything outside the internal checksum ledger
    # unless it is declared inert rendered data; CHANGELOG.md is deliberately
    # outside the ledger so a changelog edit cannot break bootstrap.
    eval "$(sed -n '/^_acfs_internal_asset_is_rendered_data()/,/^}$/p' "$INSTALL_SH")"
    _acfs_internal_asset_is_rendered_data "CHANGELOG.md"
    _acfs_internal_asset_is_rendered_data "acfs/onboard/lessons/00_welcome.md"
    run _acfs_internal_asset_is_rendered_data "packages/x/CHANGELOG.md"
    [ "$status" -ne 0 ]
    run _acfs_internal_asset_is_rendered_data "scripts/lib/doctor.sh"
    [ "$status" -ne 0 ]
    grep -Fq 'install_asset "CHANGELOG.md" "$ACFS_HOME/CHANGELOG.md"' "$INSTALL_SH"
    grep -Fq '"CHANGELOG.md:CHANGELOG.md"' "$UPDATE_SH"
}

# Exercise the real finalizer and selectors while recording deployment
# transports. Fixtures live beneath BATS_TEST_TMPDIR; no host setup runs.
_run_finalize_selection() {
    local selection_kind="$1" mode="$2"
    shift 2
    local body
    body=$(cat <<'FINALIZE_TEST'
fixture="$(mktemp -d "$3/finalize.XXXXXX")"
TARGET_HOME="$fixture/home"
TARGET_USER=fixture
ACFS_HOME="$TARGET_HOME/.acfs"
ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
ACFS_STATE_FILE="$ACFS_HOME/state.json"
ACFS_ASSETS_DIR="$fixture/assets"
ACFS_GENERATED_DIR="$fixture/generated"
ACFS_BOOTSTRAP_DIR="$fixture/no-bootstrap"
MODE="$5"
SUDO=fixture_privileged
ACFS_CLAUDE_RETENTION_DAYS=3650
ACFS_CLAUDE_RETENTION_JQ_FILTER='.'
EVENTS="$fixture/events"
mkdir -p "$ACFS_HOME" "$ACFS_BIN_DIR" "$ACFS_ASSETS_DIR/onboard/lessons" "$ACFS_GENERATED_DIR"
printf 'fixture lesson\n' > "$ACFS_ASSETS_DIR/onboard/lessons/00_welcome.md"
printf '# fixture ledger\n' > "$ACFS_GENERATED_DIR/internal_checksums.sh"
printf '#!/bin/sh\nexit 99\n' > "$ACFS_BIN_DIR/agy-locked"
chmod 755 "$ACFS_BIN_DIR/agy-locked"
: > "$EVENTS"
eval "$(sed -n '/^acfs_selection_filters_active() {$/,/^}$/p' "$2")"
eval "$(sed -n '/^should_run_module() {$/,/^}$/p' "$2")"
eval "$(sed -n '/^acfs_legacy_module_selected() {$/,/^}$/p' "$1")"
# JSON heredocs contain unindented closing braces; the next section marks
# the end of this function without truncating those literal payloads.
eval "$(awk '/^finalize\(\) \{$/ { capture=1 } capture && /^# =/ { exit } capture { print }' "$1")"
declare -a ONLY_MODULES=() ONLY_PHASES=() SKIP_MODULES=() SKIP_TAGS=() SKIP_CATEGORIES=()
declare -A ACFS_EFFECTIVE_RUN=()
selection_kind="$4"
shift 5
if [[ "$selection_kind" == subset ]]; then
    ONLY_MODULES=("$@")
    for module in "$@"; do ACFS_EFFECTIVE_RUN["$module"]=1; done
fi
trace() { printf '%s\n' "$*" >> "$EVENTS"; }
set_phase() { :; }
log_step() { :; }
log_detail() { trace "detail:$*"; }
log_success() { trace "success:$*"; }
log_warn() { trace "warning:$*"; }
log_error() { trace "error:$*"; }
acfs_use_generated_category() { return 1; }
try_step() {
    trace "step:$1"
    [[ "$1" != "${FAIL_FINALIZE_STEP:-}" ]]
}
try_step_optional() { try_step "$@"; }
run_as_target() {
    trace "target:$*"
    if [[ "$1" == tee ]]; then cat >/dev/null; fi
    return 0
}
fixture_privileged() { trace "privileged:$*"; }
acfs_merge_existing_json_config_as_target() { trace "merge:$*"; }
acfs_finalize_nightly_timer() { :; }
state_load() { :; }
result=0
finalize || result=$?
cat "$EVENTS"
exit "$result"
FINALIZE_TEST
)
    run env FAIL_FINALIZE_STEP="${FAIL_FINALIZE_STEP:-}" /bin/bash -p -euo pipefail -c "$body" \
        finalize-selection "$INSTALL_SH" "$PROJECT_ROOT/scripts/lib/install_helpers.sh" \
        "$BATS_TEST_TMPDIR" "$selection_kind" "$mode" "$@"
}

@test "doctor-only finalization deploys shared runtime without unselected commands or agent settings" {
    _run_finalize_selection subset vibe acfs.doctor
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"step:Creating bin directory ("* ]]
    [[ "$output" == *"step:Installing acfs CLI"* ]]
    [[ "$output" == *"step:Installing global acfs wrapper"* ]]
    [[ "$output" == *"step:Installing holds.sh"* ]]
    [[ "$output" == *"step:Installing generated script: internal_checksums.sh"* ]]
    [[ "$output" != *"step:Installing tmux config"* ]]
    [[ "$output" != *"step:Installing onboard script"* ]]
    [[ "$output" != *"step:Installing acfs-update"* ]]
    [[ "$output" != *"step:Installing DCG hook"* ]]
    [[ "$output" != *"Configuring workspace trust"* ]]
    [[ "$output" != *"Configuring Claude Code session retention"* ]]
    [[ "$output" != *"--acfs-prime-settings"* ]]
    [[ "$output" == *"success:Finalization complete"* ]]
}

@test "onboard and update selections install their own public commands" {
    _run_finalize_selection subset safe acfs.onboard
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"step:Installing onboard script"* ]]
    [[ "$output" == *"step:Linking global onboard command"* ]]
    [[ "$output" != *"step:Installing acfs-update"* ]]
    [[ "$output" != *"step:Installing acfs CLI"* ]]
    [[ "$output" != *"step:Installing global acfs wrapper"* ]]

    _run_finalize_selection subset safe acfs.update
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"step:Installing acfs-update"* ]]
    [[ "$output" == *"step:Linking global acfs-update command"* ]]
    [[ "$output" != *"step:Installing onboard script"* ]]
    [[ "$output" != *"step:Installing acfs CLI"* ]]
    [[ "$output" != *"step:Installing global acfs wrapper"* ]]
}

@test "tmux and individual agent settings follow resolved module selection" {
    _run_finalize_selection subset vibe cli.modern agents.antigravity acfs.doctor
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"step:Installing tmux config"* ]]
    [[ "$output" == *"target:tmux source-file "* ]]
    [[ "$output" == *"--acfs-prime-settings"* ]]
    [[ "$output" != *"Configuring workspace trust"* ]]
    [[ "$output" != *"Configuring Claude Code session retention"* ]]
    [[ "$output" != *"step:Installing DCG hook"* ]]

    _run_finalize_selection subset vibe agents.claude acfs.doctor
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Configuring workspace trust"* ]]
    [[ "$output" == *"Configuring Claude Code session retention"* ]]
    [[ "$output" != *"step:Installing DCG hook"* ]]
    [[ "$output" != *"--acfs-prime-settings"* ]]

    _run_finalize_selection subset vibe stack.dcg acfs.doctor
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"step:Installing DCG hook"* ]]
    [[ "$output" != *"Configuring Claude Code session retention"* ]]
}

@test "safe mode retains selected Claude history and guard without enabling workspace trust" {
    _run_finalize_selection subset safe agents.claude stack.dcg acfs.doctor
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"step:Installing DCG hook"* ]]
    [[ "$output" == *"Configuring Claude Code session retention"* ]]
    [[ "$output" != *"Configuring workspace trust"* ]]
    [[ "$output" != *"--acfs-prime-settings"* ]]
}

@test "unfiltered finalization retains the full command and agent configuration path" {
    _run_finalize_selection default vibe
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"step:Installing tmux config"* ]]
    [[ "$output" == *"step:Installing onboard script"* ]]
    [[ "$output" == *"step:Installing acfs-update"* ]]
    [[ "$output" == *"step:Installing acfs CLI"* ]]
    [[ "$output" == *"step:Installing DCG hook"* ]]
    [[ "$output" == *"Configuring workspace trust"* ]]
    [[ "$output" == *"Configuring Claude Code session retention"* ]]
    [[ "$output" == *"--acfs-prime-settings"* ]]
    [[ "$output" == *"success:Finalization complete"* ]]
}

@test "selected command deployment failure stops finalization before success" {
    FAIL_FINALIZE_STEP='Installing acfs CLI' _run_finalize_selection subset safe acfs.doctor
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"step:Installing acfs CLI"* ]]
    [[ "$output" != *"step:Installing global acfs wrapper"* ]]
    [[ "$output" != *"success:Finalization complete"* ]]
}
