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

# Run the authored installer phases with the real manifest resolver. Only
# package/network/account transports are inert; selectors, phase routing and
# module failure handling execute unchanged. Every writable path is private.
_run_authored_phase_selection() {
    local selection_kind="$1" phase="$2"
    shift 2
    local body
    body=$(cat <<'AUTHORED_TEST'
fixture="$(mktemp -d "$3/authored.XXXXXX")"
TARGET_HOME="$fixture/home"
TARGET_USER=fixture
ACFS_HOME="$TARGET_HOME/.acfs"
ACFS_LOG_DIR="$ACFS_HOME/logs"
ACFS_BIN_DIR="$TARGET_HOME/.local/bin"
ACFS_LIB_DIR="$fixture/no-libraries"
ACFS_DISTRO_FAMILY=arch
ACFS_MANIFEST_INDEX_LOADED=true
ACFS_MODULE_FAILURES=()
ACFS_OPTIONAL_MODULE_SKIPS=()
ACFS_SAVED_SELECTION_ACTIVE=false
ONLY_MODULES=(); ONLY_PHASES=(); SKIP_MODULES=(); SKIP_TAGS=(); SKIP_CATEGORIES=()
ACFS_SAVED_SELECTION_MODULES=(); ACFS_SAVED_REQUESTED_MODULES=()
NO_DEPS=true
MODE=vibe
SKIP_CLOUD=false
SUDO=fixture_privileged
EVENTS="$fixture/events"
mkdir -p "$ACFS_BIN_DIR" "$TARGET_HOME/.bun/bin" "$ACFS_HOME"
: > "$EVENTS"
# Existing unrelated tools must not authorize configuration changes.
printf '#!/bin/sh\nexit 99\n' > "$ACFS_BIN_DIR/dcg"
chmod 755 "$ACFS_BIN_DIR/dcg"
printf '#!/bin/sh\nexit 99\n' > "$TARGET_HOME/.bun/bin/bun"
chmod 755 "$TARGET_HOME/.bun/bin/bun"
source "$2/scripts/lib/install_helpers.sh"
source "$2/scripts/generated/manifest_index.sh"
for helper in acfs_legacy_module_selected acfs_legacy_module_is_required acfs_try_module_step acfs_module_id_for_verified_installer_tool acfs_optional_module_install_failed setup_filesystem; do
    eval "$(sed -n "/^${helper}() {$/,/^}$/p" "$1")"
done
# Whole regions retain embedded heredocs, which contain column-zero braces.
eval "$(sed -n '/^setup_shell() {$/,/^_target_has_nvm_node() {$/p' "$1" | sed '$d')"
eval "$(sed -n '/^install_agents_phase() {$/,/^acfs_postgres_run_as_owner() {$/p' "$1" | sed '$d')"
eval "$(sed -n '/^install_cloud_db_legacy_cloud() {$/,/^install_cloud_db() {$/p' "$1" | sed '$d')"
eval "$(sed -n '/^install_stack_phase() {$/,/^acfs_resolve_existing_config_write_path() {$/p' "$1" | sed '$d')"
selection_kind="$4"
phase="$5"
shift 5
case "$selection_kind" in
    only) ONLY_MODULES=("$@") ;;
    saved)
        ACFS_SAVED_SELECTION_ACTIVE=true
        ACFS_SAVED_SELECTION_MODULES=("$@")
        ACFS_SAVED_REQUESTED_MODULES=("$@")
        ;;
    skip) SKIP_MODULES=("$@") ;;
    defaults) ;;
    *) exit 98 ;;
esac
# Keep resolver warnings (for example --no-deps) separate from mutation events.
# Retain diagnostics in the fixture and replay them if resolution itself fails.
selection_rc=0
acfs_resolve_selection >"$fixture/selection.log" 2>&1 || selection_rc=$?
if (( selection_rc != 0 )); then
    cat "$fixture/selection.log" >&2
    exit "$selection_rc"
fi
trace() { printf '%s\n' "$*" >> "$EVENTS"; }
set_phase() { :; }
log_step() { :; }
log_info() { :; }
log_detail() { :; }
log_success() { :; }
log_warn() { :; }
log_error() { trace "error:$*"; }
acfs_use_generated_category() { [[ ",${GENERATED_CATEGORIES:-}," == *",$1,"* ]]; }
acfs_run_generated_category_phase() { trace "generated:$1:$2"; }
try_step() { trace "step:$1"; shift; "$@"; }
try_step_optional() { try_step "$@"; }
fixture_privileged() { trace "privileged:$*"; }
acfs_arch_pkg_install() { trace "packages:$*"; }
acfs_arch_pkg_install_each() { trace "packages-each:$*"; }
acfs_should_skip_module() { return 1; }
acfs_verify_module() { trace "verify:$1"; [[ "$1" != "${FAIL_MODULE:-}" ]]; }
acfs_run_verification_command() { return 0; }
acfs_run_verified_upstream_script_as_target() { trace "upstream:$1"; [[ "$1" != "${FAIL_TOOL:-}" ]]; }
acfs_run_verified_upstream_script_as_target_with_env() { acfs_run_verified_upstream_script_as_target "$@"; }
acfs_early_system_binary_path() { return 1; }
acfs_ensure_primary_bin_dir() { trace primary-bin; }
acfs_note_bun_global_bin_mismatch() { :; }
acfs_warn_bun_global_binary_missing() { :; }
acfs_link_primary_bin_command() { trace "link:$*"; }
install_asset() { trace "asset:$1"; }
acfs_chown_tree() { trace "chown:$*"; }
acfs_chown_target_home() { trace "chown-home:$*"; }
acfs_install_workspace_template() { trace "workspace-template:$*"; }
set_default_shell() { trace login-shell; }
install_agy_locked_launchers() { trace agy-launcher; }
install_tailscale() { trace tailscale; [[ "${FAIL_TOOL:-}" != tailscale ]]; }
install_github_cli() { trace github-cli; }
install_supabase_cli_release() { trace supabase; }
run_as_target() {
    trace "target:$*"
    if [[ "$1" == tee ]]; then cat >/dev/null; fi
    return 0
}
_smoke_run_as_target() { return 0; }
command_exists() { return 1; }
binary_installed() {
    case "$1" in
        gum|rg|tmux|fzf|direnv|jq|git-lfs|lsof|dig|strace|rsync|zstd|gh|minisign|sqlite3|nc) return 0 ;;
        *) [[ ",${PRESENT_BINARIES:-}," == *",$1,"* ]] ;;
    esac
}
binary_path() { binary_installed "$1" && printf '/usr/bin/true\n'; }
getent() { [[ "$1" == group && "$2" == docker ]]; }
pacman() { return 0; }
result=0
case "$phase" in
    filesystem) setup_filesystem || result=$? ;;
    shell) setup_shell || result=$? ;;
    cli) install_cli_tools || result=$? ;;
    agents) install_agents_phase || result=$? ;;
    cloud) install_cloud_db_legacy_cloud || result=$? ;;
    stack) install_stack_phase || result=$? ;;
    selection)
        for module in "${ACFS_MODULES_IN_ORDER[@]}"; do
            if acfs_legacy_module_selected "$module"; then trace "selected:$module"; fi
        done
        ;;
    *) exit 97 ;;
esac
cat "$EVENTS"
exit "$result"
AUTHORED_TEST
)
    run env FAIL_TOOL="${FAIL_TOOL:-}" FAIL_MODULE="${FAIL_MODULE:-}" \
        PRESENT_BINARIES="${PRESENT_BINARIES:-}" GENERATED_CATEGORIES="${GENERATED_CATEGORIES:-}" \
        /bin/bash -p -euo pipefail -c "$body" authored-selection \
        "${ACFS_AUTHORED_TEST_INSTALL_SH:-$INSTALL_SH}" "$PROJECT_ROOT" "$BATS_TEST_TMPDIR" "$selection_kind" "$phase" "$@"
}

@test "authored filesystem skip-only selection does not create or modify directories" {
    _run_authored_phase_selection skip filesystem base.filesystem
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
}

@test "authored Tailscale-only installs never provision CLI packages or Docker privileges" {
    for kind in only saved; do
        _run_authored_phase_selection "$kind" cli network.tailscale
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"tailscale"* ]]
        [[ "$output" != *"packages:"* && "$output" != *"privileged:"* ]]
        [[ "$output" != *"verify:cli.modern"* && "$output" != *"lazygit"* && "$output" != *"lazydocker"* ]]
    done
}

@test "authored CLI and individual developer tools retain independent positive installers" {
    _run_authored_phase_selection only cli cli.modern
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"packages:ripgrep tmux"* && "$output" == *"usermod -aG docker fixture"* ]]
    [[ "$output" != *"lazygit"* && "$output" != *"lazydocker"* && "$output" != *"tailscale"* ]]

    for tool in lazygit lazydocker; do
        _run_authored_phase_selection only cli "tools.$tool"
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"packages:$tool"* ]]
        [[ "$output" != *"packages:ripgrep"* && "$output" != *"usermod"* && "$output" != *"tailscale"* ]]
    done
}

@test "mixed generated CLI and authored networking honor the same selection" {
    GENERATED_CATEGORIES=cli _run_authored_phase_selection only cli tools.lazygit
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"generated:cli:5"* && "$output" == *"packages:lazygit"* ]]
    [[ "$output" != *"tailscale"* && "$output" != *"usermod"* ]]
}

@test "authored shell package and login choices do not overwrite unrelated shell configuration" {
    _run_authored_phase_selection only shell shell.zsh
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"packages:zsh git"* ]]
    [[ "$output" != *"asset:"* && "$output" != *"login-shell"* ]]

    _run_authored_phase_selection only shell shell.login
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"login-shell"* ]]
    [[ "$output" != *"packages:"* && "$output" != *"asset:"* ]]

    _run_authored_phase_selection only shell shell.omz
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"asset:acfs/zsh/acfs.zshrc"* ]]
    [[ "$output" != *"packages:"* && "$output" != *"login-shell"* ]]
}

@test "authored stack subset avoids unrelated upstream installers and existing tool hooks" {
    for kind in only saved; do
        PRESENT_BINARIES=ntm,claude _run_authored_phase_selection "$kind" stack stack.beads_rust
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"upstream:br"* ]]
        [[ "$(printf '%s\n' "$output" | grep -c '^upstream:')" -eq 1 ]]
        [[ "$output" != *"target:"* && "$output" != *"asset:"* && "$output" != *"Registering DCG"* ]]
    done
}

@test "authored selected module failures remain failures" {
    FAIL_TOOL=br _run_authored_phase_selection only stack stack.beads_rust
    [[ "$status" -ne 0 && "$output" == *"upstream:br"* ]]
    FAIL_TOOL=tailscale _run_authored_phase_selection only cli network.tailscale
    [[ "$status" -ne 0 && "$output" == *"tailscale"* ]]
    FAIL_TOOL=omp _run_authored_phase_selection only agents agents.omp
    [[ "$status" -ne 0 && "$output" == *"upstream:omp"* ]]
}

@test "optional authored coding agents install in their manifest phase without other agents" {
    for agent in grok omp opencode; do
        _run_authored_phase_selection only agents "agents.$agent"
        [[ "$status" -eq 0 ]]
        [[ "$output" == *"upstream:$agent"* ]]
        [[ "$(printf '%s\n' "$output" | grep -c '^upstream:')" -eq 1 ]]
        [[ "$output" != *"agy-launcher"* && "$output" != *"verify:agents.claude"* && "$output" != *"verify:agents.codex"* ]]
    done
}

@test "authored cloud subset does not install unrelated provider CLIs" {
    _run_authored_phase_selection only cloud cloud.vercel
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"vercel@latest"* ]]
    [[ "$output" != *"supabase"* && "$output" != *"wrangler"* ]]
}

@test "authored default selection excludes manifest opt-in tools without CLI filters" {
    _run_authored_phase_selection defaults selection
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"selected:stack.beads_rust"* ]]
    [[ "$output" != *"selected:agents.grok"* && "$output" != *"selected:agents.omp"* && "$output" != *"selected:agents.opencode"* ]]
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
