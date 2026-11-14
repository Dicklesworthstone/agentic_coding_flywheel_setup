#!/usr/bin/env bats
#
# Issue #387: a stale installer pin on an OPTIONAL generated module surfaced
# only as a WARN line, while the same failure on a required module was named
# in the final summary box. install.sh now owns record_skipped_tool() (the
# hook generated optional modules already call) and print_summary() lists the
# recorded skips beside the failures. These tests exercise the shipped
# function bodies extracted from install.sh, in the style of
# test_only_module_failure.bats.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    INSTALL_SH="$PROJECT_ROOT/install.sh"

    eval "$(sed -n '/^record_skipped_tool() {$/,/^}$/p' "$INSTALL_SH")"
    eval "$(sed -n '/^print_summary() {$/,/^}$/p' "$INSTALL_SH")"
    [[ "$(type -t record_skipped_tool)" == "function" ]]
    [[ "$(type -t print_summary)" == "function" ]]

    # Globals print_summary reads; colors empty so assertions match plain text.
    RED="" GREEN="" YELLOW="" BLUE="" GRAY="" NC=""
    ACFS_SUCCESS="2" ACFS_WARNING="3"
    HAS_GUM=false
    DRY_RUN=false
    MODE="vibe"
    ACFS_VERSION="test"
    TARGET_USER="tester"
    TARGET_HOME="/home/tester"
    ACFS_SSH_KEY_WARNING=false
    SMOKE_TEST_FAILED=false
    ACFS_PHASE_FAILURES=()
    ACFS_MODULE_FAILURES=()
    ACFS_OPTIONAL_MODULE_SKIPS=()
    ACFS_LAST_MODULE_FAILURE_REASON=""
    check_tailscale_auth() { return 1; }

    STATE_SKIPS=()
    state_tool_skip() { STATE_SKIPS+=("$1"); }
}

@test "record_skipped_tool prefers the module's categorized reason over the generic call-site text" {
    ACFS_LAST_MODULE_FAILURE_REASON="checksum"
    record_skipped_tool "stack.pfr" "verified installer failed"

    [[ ${#ACFS_OPTIONAL_MODULE_SKIPS[@]} -eq 1 ]]
    [[ "${ACFS_OPTIONAL_MODULE_SKIPS[0]}" == "stack.pfr (checksum)" ]]
    # Consumed, so a later module cannot inherit this module's category.
    [[ -z "$ACFS_LAST_MODULE_FAILURE_REASON" ]]
    # The persisted skip marker generated modules relied on is still written.
    [[ ${#STATE_SKIPS[@]} -eq 1 && "${STATE_SKIPS[0]}" == "stack.pfr" ]]
}

@test "record_skipped_tool keeps a specific reason, bounds long verify commands, and dedupes by module" {
    record_skipped_tool "stack.slb" 'verify failed: export PATH="$HOME/go/bin:$PATH" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1'
    record_skipped_tool "stack.slb" "verified installer failed"
    record_skipped_tool "stack.ntm" "verified installer failed"

    [[ ${#ACFS_OPTIONAL_MODULE_SKIPS[@]} -eq 2 ]]
    [[ "${ACFS_OPTIONAL_MODULE_SKIPS[0]}" == 'stack.slb (verify failed: export PATH="$HOME/go/bin:$PATH" && slb >/dev/null'*'...)' ]]
    # Module id + a 72-char-bounded reason stays within a summary-box line.
    local bounded="stack.slb ()"
    (( ${#ACFS_OPTIONAL_MODULE_SKIPS[0]} <= 72 + ${#bounded} ))
    # No categorized reason set: the call-site text is kept verbatim.
    [[ "${ACFS_OPTIONAL_MODULE_SKIPS[1]}" == "stack.ntm (verified installer failed)" ]]
}

@test "record_skipped_tool ignores an empty module id" {
    record_skipped_tool "" "checksum"
    [[ ${#ACFS_OPTIONAL_MODULE_SKIPS[@]} -eq 0 ]]
    [[ ${#STATE_SKIPS[@]} -eq 0 ]]
}

@test "print_summary lists optional skips beside required failures" {
    ACFS_MODULE_FAILURES=("stack.mcp_agent_mail (checksum)")
    ACFS_LAST_MODULE_FAILURE_REASON="checksum"
    record_skipped_tool "stack.pfr" "verified installer failed"

    run print_summary
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Finished With Failures"* ]]
    [[ "$output" == *"stack.mcp_agent_mail (checksum)"* ]]
    [[ "$output" == *"Optional modules skipped"* ]]
    [[ "$output" == *"stack.pfr (checksum)"* ]]
    [[ "$output" == *"acfs update --stack"* ]]
    # The optional block follows the failures block, never displaces it.
    local failures_pos optional_pos
    failures_pos="${output%%COMPLETED WITH FAILURES*}"
    optional_pos="${output%%Optional modules skipped*}"
    (( ${#failures_pos} < ${#optional_pos} ))
}

@test "print_summary keeps the success banner when only optional modules were skipped" {
    record_skipped_tool "stack.pfr" "verified installer failed"

    run print_summary
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Installation Complete"* ]]
    [[ "$output" != *"COMPLETED WITH FAILURES"* ]]
    [[ "$output" == *"Optional modules skipped"* ]]
    [[ "$output" == *"stack.pfr (verified installer failed)"* ]]
}

@test "print_summary prints no optional block when nothing was skipped" {
    run print_summary
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Installation Complete"* ]]
    [[ "$output" != *"Optional modules skipped"* ]]
}

# ------------------------------------------------------------------
# #389: the default install runs the LEGACY stack phase (no category is
# migrated to generated dispatch by default), whose optional call sites were
# `try_step ... || log_warn "X installation may have failed"`. Those never
# reached record_skipped_tool, so the "Optional modules skipped" block above
# stayed empty on exactly the install it was added for.
# ------------------------------------------------------------------

legacy_setup() {
    eval "$(sed -n '/^acfs_module_id_for_verified_installer_tool() {$/,/^}$/p' "$INSTALL_SH")"
    eval "$(sed -n '/^acfs_legacy_module_is_required() {$/,/^}$/p' "$INSTALL_SH")"
    eval "$(sed -n '/^acfs_optional_module_install_failed() {$/,/^}$/p' "$INSTALL_SH")"
    [[ "$(type -t acfs_module_id_for_verified_installer_tool)" == "function" ]]
    [[ "$(type -t acfs_legacy_module_is_required)" == "function" ]]
    [[ "$(type -t acfs_optional_module_install_failed)" == "function" ]]
    WARN_LINES=()
    ERROR_LINES=()
    log_warn() { WARN_LINES+=("$1"); }
    log_error() { ERROR_LINES+=("$1"); }
}

# The legacy stack phase's call sites are all `|| acfs_optional_module_install_failed`,
# but nine of those tools (br, bv, cass, cm, caam, dcg, ru, ubs, ms) are
# `optional: false` in the manifest. Those must land in the failure list the
# exit code reads, never under "Optional modules skipped".
@test "acfs_optional_module_install_failed records a REQUIRED manifest module as a module failure, not an optional skip" {
    legacy_setup
    declare -gA ACFS_MODULE_VERIFIED_INSTALLER_TOOL=(["stack.ultimate_bug_scanner"]="ubs")
    declare -gA ACFS_MODULE_OPTIONAL=(["stack.ultimate_bug_scanner"]="0")
    ACFS_LAST_MODULE_FAILURE_REASON="checksum"

    acfs_optional_module_install_failed "ubs" "UBS"

    [[ ${#ACFS_MODULE_FAILURES[@]} -eq 1 ]]
    [[ "${ACFS_MODULE_FAILURES[0]}" == "stack.ultimate_bug_scanner (checksum)" ]]
    [[ ${#ACFS_OPTIONAL_MODULE_SKIPS[@]} -eq 0 ]]
    [[ ${#STATE_SKIPS[@]} -eq 0 ]]
    [[ ${#WARN_LINES[@]} -eq 0 ]]
    [[ ${#ERROR_LINES[@]} -eq 1 && "${ERROR_LINES[0]}" == *"UBS installation failed"*"stack.ultimate_bug_scanner"*"checksum"* ]]
    # Consumed, like the optional path, so the next module cannot inherit it.
    [[ -z "$ACFS_LAST_MODULE_FAILURE_REASON" ]]
}

@test "acfs_optional_module_install_failed without a categorized reason still names a required module's failure" {
    legacy_setup
    declare -gA ACFS_MODULE_VERIFIED_INSTALLER_TOOL=(["stack.beads_rust"]="br")
    declare -gA ACFS_MODULE_OPTIONAL=(["stack.beads_rust"]="0")
    ACFS_LAST_MODULE_FAILURE_REASON=""

    acfs_optional_module_install_failed "br" "Beads Rust"

    [[ "${ACFS_MODULE_FAILURES[0]}" == "stack.beads_rust (verified installer failed)" ]]
    [[ ${#ACFS_OPTIONAL_MODULE_SKIPS[@]} -eq 0 ]]
}

@test "acfs_optional_module_install_failed stays lenient for a module the loaded index does not classify" {
    legacy_setup
    declare -gA ACFS_MODULE_VERIFIED_INSTALLER_TOOL=(["stack.ultimate_bug_scanner"]="ubs")
    # Index loaded, but this module has no optional entry: never invent a failure.
    declare -gA ACFS_MODULE_OPTIONAL=(["stack.beads_rust"]="0")

    acfs_optional_module_install_failed "ubs" "UBS"
    [[ ${#ACFS_MODULE_FAILURES[@]} -eq 0 ]]
    [[ "${ACFS_OPTIONAL_MODULE_SKIPS[0]}" == "stack.ultimate_bug_scanner (verified installer failed)" ]]

    # No index at all: same lenient path.
    unset ACFS_MODULE_OPTIONAL
    acfs_optional_module_install_failed "br" "Beads Rust"
    [[ ${#ACFS_MODULE_FAILURES[@]} -eq 0 ]]
    [[ ${#ACFS_OPTIONAL_MODULE_SKIPS[@]} -eq 2 ]]
}

@test "acfs_legacy_module_is_required reads only an explicit optional=0 from the index" {
    legacy_setup
    unset ACFS_MODULE_OPTIONAL
    ! acfs_legacy_module_is_required "stack.beads_rust"
    ! acfs_legacy_module_is_required ""
    declare -gA ACFS_MODULE_OPTIONAL=(["stack.beads_rust"]="0" ["stack.power_failure_resumer"]="1")
    acfs_legacy_module_is_required "stack.beads_rust"
    ! acfs_legacy_module_is_required "stack.power_failure_resumer"
    ! acfs_legacy_module_is_required "stack.nosuchmodule"
}

@test "legacy stack phase folds module failures recorded during the phase into its exit status" {
    # The call sites stay `|| helper` (return 0 under set -e), so the phase
    # tail must compare ACFS_MODULE_FAILURES against its entry snapshot.
    local phase
    phase="$(sed -n '/^install_stack_phase() {$/,/^}$/p' "$INSTALL_SH")"
    [[ "$phase" == *'local stack_failures_before=${#ACFS_MODULE_FAILURES[@]}'* ]]
    grep -Eq '^[[:space:]]*if \[\[ "\$stack_phase_rc" -eq 0 \]\] && \(\( \$\{#ACFS_MODULE_FAILURES\[@\]\} > stack_failures_before \)\); then$' <<< "$phase"
    grep -Eq '^[[:space:]]*stack_phase_rc=1$' <<< "$phase"
}

@test "acfs_module_id_for_verified_installer_tool prefers the stack module, then any module, then a synthetic id" {
    legacy_setup
    declare -gA ACFS_MODULE_VERIFIED_INSTALLER_TOOL=(
        ["stack.power_failure_resumer"]="pfr"
        ["utils.xf"]="xf"
        ["agents.grok"]="grok"
        ["stack.slb"]="slb"
    )

    [[ "$(acfs_module_id_for_verified_installer_tool pfr)" == "stack.power_failure_resumer" ]]
    [[ "$(acfs_module_id_for_verified_installer_tool slb stack)" == "stack.slb" ]]
    # Legacy stack sites also install utils.*/agents.* tools: any module wins over a synthetic id.
    [[ "$(acfs_module_id_for_verified_installer_tool xf)" == "utils.xf" ]]
    [[ "$(acfs_module_id_for_verified_installer_tool grok)" == "agents.grok" ]]
    # Unknown tool: synthetic "<category>.<tool>" so the summary still names it.
    [[ "$(acfs_module_id_for_verified_installer_tool nosuchtool)" == "stack.nosuchtool" ]]
    run acfs_module_id_for_verified_installer_tool ""
    [[ "$status" -ne 0 ]]
}

@test "acfs_module_id_for_verified_installer_tool falls back cleanly when the manifest index is not loaded" {
    legacy_setup
    unset ACFS_MODULE_VERIFIED_INSTALLER_TOOL
    [[ "$(acfs_module_id_for_verified_installer_tool pfr)" == "stack.pfr" ]]
}

@test "acfs_optional_module_install_failed keeps the WARN line and records the categorized skip" {
    legacy_setup
    declare -gA ACFS_MODULE_VERIFIED_INSTALLER_TOOL=(["stack.power_failure_resumer"]="pfr")
    ACFS_LAST_MODULE_FAILURE_REASON="checksum"

    acfs_optional_module_install_failed "pfr" "PFR"

    [[ ${#WARN_LINES[@]} -eq 1 && "${WARN_LINES[0]}" == "PFR installation may have failed" ]]
    [[ ${#ACFS_OPTIONAL_MODULE_SKIPS[@]} -eq 1 ]]
    [[ "${ACFS_OPTIONAL_MODULE_SKIPS[0]}" == "stack.power_failure_resumer (checksum)" ]]
    [[ -z "$ACFS_LAST_MODULE_FAILURE_REASON" ]]
    [[ ${#STATE_SKIPS[@]} -eq 1 && "${STATE_SKIPS[0]}" == "stack.power_failure_resumer" ]]
    # Optional skips never touch the failure lists that decide the exit code.
    [[ ${#ACFS_MODULE_FAILURES[@]} -eq 0 && ${#ACFS_PHASE_FAILURES[@]} -eq 0 ]]
}

@test "acfs_optional_module_install_failed without a categorized reason records the generic text" {
    legacy_setup
    unset ACFS_MODULE_VERIFIED_INSTALLER_TOOL
    ACFS_LAST_MODULE_FAILURE_REASON=""

    acfs_optional_module_install_failed "xf" "XF"

    [[ "${ACFS_OPTIONAL_MODULE_SKIPS[0]}" == "stack.xf (verified installer failed)" ]]
}

@test "legacy agent and stack phases route every optional installer failure through acfs_optional_module_install_failed" {
    # Static guard: a new legacy call site written as `|| log_warn "... may have failed"`
    # would silently drop out of the summary again.
    local phase
    phase="$(sed -n -e '/^install_stack_phase() {$/,/^}$/p' -e '/^install_agents_legacy_optional() {$/,/^}$/p' "$INSTALL_SH")"
    [[ -n "$phase" ]]
    run grep -c 'acfs_optional_module_install_failed "' <<< "$phase"
    (( output >= 38 ))
    # The only remaining "may have failed" text belongs to the REQUIRED Agent Mail module.
    run grep -E 'log_warn "[^"]* installation may have failed"' <<< "$phase"
    [[ "$status" -ne 0 ]]
    # Every call site passes a bare checksums.yaml tool key, never a module id.
    run grep -E 'acfs_optional_module_install_failed "[a-z0-9_]*\.' <<< "$phase"
    [[ "$status" -ne 0 ]]
}

@test "verified upstream runner clears a stale failure reason before each tool" {
    # acfs_run_verified_upstream_script_as_target_with_env resets the reason at
    # entry and tags a failing runner as "installer execution" when the
    # security path set nothing, so the summary never blames tool B for tool A.
    local fn
    fn="$(sed -n '/^acfs_run_verified_upstream_script_as_target_with_env() {$/,/^}$/p' "$INSTALL_SH")"
    [[ "$fn" == *'ACFS_LAST_MODULE_FAILURE_REASON=""'* ]]
    [[ "$fn" == *': "${ACFS_LAST_MODULE_FAILURE_REASON:=installer execution}"'* ]]
}

@test "manifest index maps verified-installer tool keys to module ids" {
    local index="$PROJECT_ROOT/scripts/generated/manifest_index.sh"
    [[ -f "$index" ]]
    # shellcheck disable=SC1090
    source "$index"
    [[ "$(declare -p ACFS_MODULE_VERIFIED_INSTALLER_TOOL 2>/dev/null)" == "declare -A"* ]]
    [[ "${ACFS_MODULE_VERIFIED_INSTALLER_TOOL[stack.power_failure_resumer]}" == "pfr" ]]
    [[ "${ACFS_MODULE_VERIFIED_INSTALLER_TOOL[stack.mcp_agent_mail]}" == "mcp_agent_mail" ]]

    legacy_setup
    # Every tool key the legacy agent and stack phases report resolves to a real manifest module.
    local phase tool id
    phase="$(sed -n -e '/^install_stack_phase() {$/,/^}$/p' -e '/^install_agents_legacy_optional() {$/,/^}$/p' "$INSTALL_SH")"
    while IFS= read -r tool; do
        id="$(acfs_module_id_for_verified_installer_tool "$tool")"
        [[ -n "${ACFS_MODULE_CATEGORY[$id]:-}" ]] || {
            echo "legacy tool '$tool' resolved to '$id', which is not a manifest module" >&2
            return 1
        }
    done < <(grep -o 'acfs_optional_module_install_failed "[a-z0-9_]*"' <<< "$phase" | sed -E 's/.*"([a-z0-9_]+)"/\1/' | sort -u)

    # With the real index loaded, every legacy call site lands where the
    # manifest's optional flag says: required modules in the failure list, the
    # rest in the optional-skip list. Guards the 38 sites against the manifest.
    local required_seen=0 optional_seen=0
    while IFS= read -r tool; do
        id="$(acfs_module_id_for_verified_installer_tool "$tool")"
        ACFS_MODULE_FAILURES=()
        ACFS_OPTIONAL_MODULE_SKIPS=()
        acfs_optional_module_install_failed "$tool" "$tool"
        if [[ "${ACFS_MODULE_OPTIONAL[$id]:-}" == "0" ]]; then
            required_seen=$((required_seen + 1))
            [[ ${#ACFS_MODULE_FAILURES[@]} -eq 1 && ${#ACFS_OPTIONAL_MODULE_SKIPS[@]} -eq 0 ]] || {
                echo "required module $id ($tool) was recorded as an optional skip" >&2
                return 1
            }
        else
            optional_seen=$((optional_seen + 1))
            [[ ${#ACFS_MODULE_FAILURES[@]} -eq 0 && ${#ACFS_OPTIONAL_MODULE_SKIPS[@]} -eq 1 ]] || {
                echo "optional module $id ($tool) was recorded as a failure" >&2
                return 1
            }
        fi
    done < <(grep -o 'acfs_optional_module_install_failed "[a-z0-9_]*"' <<< "$phase" | sed -E 's/.*"([a-z0-9_]+)"/\1/' | sort -u)
    # br bv caam cass cm dcg ms ru ubs are required today; the rest optional.
    (( required_seen >= 9 ))
    (( optional_seen >= 25 ))
}
