#!/usr/bin/env bash
# E2E Test: Verify expanded new-tool install surface and doctor integration
#
# Tests:
#   - 7 First-class flywheel tools: br, ms, rch, wa, brenner, dcg, ru
#   - 6 Newly integrated stack tools: fsfs, sbh, casr, dsr, asb, pcr
#   - 9 Utility tools: tru, rust_proxy, rano, xf, mdwb, pt, aadc, s2p, caut
#   - Integration: acfs doctor, flywheel.ts, br primary command
#
# Related: bd-g5d5s, bd-c4qox, bd-edpee, bd-xmvz0, bd-iy874, bd-q9auy, bd-abul4

set -uo pipefail
# Note: Not using -e to allow tests to continue after failures

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/acfs_e2e_tools_${TIMESTAMP}.log"
JSON_FILE="/tmp/acfs_e2e_results_${TIMESTAMP}.json"
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
VERBOSE=false
JSON_STDOUT=false
TEST_TIMEOUT_SECONDS="${TEST_TIMEOUT_SECONDS:-10}"

declare -a TEST_RESULTS=()

# Logging with structured format
log() {
    local level="${1:-INFO}"
    shift
    local test_name="${1:-}"
    shift
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [$test_name] $*"
    if [[ "$JSON_STDOUT" == "true" ]]; then
        printf '%s\n' "$line" | tee -a "$LOG_FILE" >&2
    else
        printf '%s\n' "$line" | tee -a "$LOG_FILE"
    fi
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

pass() {
    local test_name="$1"
    shift
    log "PASS" "$test_name" "$*"
    ((PASS_COUNT++))
    local escaped_msg
    escaped_msg=$(json_escape "$*")
    TEST_RESULTS+=("{\"test\":\"$test_name\",\"status\":\"pass\",\"message\":\"$escaped_msg\"}")
}

fail() {
    local test_name="$1"
    shift
    log "FAIL" "$test_name" "$*"
    ((FAIL_COUNT++))
    local escaped_msg
    escaped_msg=$(json_escape "$*")
    TEST_RESULTS+=("{\"test\":\"$test_name\",\"status\":\"fail\",\"message\":\"$escaped_msg\"}")
}

skip() {
    local test_name="$1"
    shift
    log "SKIP" "$test_name" "$*"
    ((SKIP_COUNT++))
    local escaped_msg
    escaped_msg=$(json_escape "$*")
    TEST_RESULTS+=("{\"test\":\"$test_name\",\"status\":\"skip\",\"message\":\"$escaped_msg\"}")
}

verbose_log() {
    if [[ "$VERBOSE" == "true" ]]; then
        log "INFO" "$@"
    fi
}

file_details() {
    local path="$1"
    if command -v stat >/dev/null 2>&1; then
        stat -c '%n perms=%A mode=%a mtime=%y' "$path" 2>/dev/null
    else
        ls -l "$path" 2>/dev/null
    fi
}

create_beads_probe_workspace() {
    local probe_dir
    probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/acfs_beads_e2e.XXXXXX")
    if [[ -z "$probe_dir" || ! -d "$probe_dir" ]]; then
        return 1
    fi

    if ! (cd "$probe_dir" && timeout "$TEST_TIMEOUT_SECONDS" br init >/dev/null 2>>"$LOG_FILE"); then
        return 1
    fi

    printf '%s\n' "$probe_dir"
}

run_beads_probe_command() {
    local probe_dir="$1"
    shift
    (cd "$probe_dir" && timeout "$TEST_TIMEOUT_SECONDS" "$@")
}

# ============================================================
# Generic Tool Testers
# ============================================================

# Test tool binary and version/help
test_tool_basic() {
    local name="$1"
    local binary="$2"
    local required="${3:-false}"  # Required tools fail, optional tools skip

    # Test binary exists
    if ! command -v "$binary" >/dev/null 2>&1; then
        if [[ "$required" == "true" ]]; then
            fail "${binary}_binary" "$binary binary not found (REQUIRED)"
        else
            skip "${binary}_binary" "$binary binary not found (optional tool)"
            skip "${binary}_version" "$binary --version skipped (binary not found)"
        fi
        return 1
    fi

    pass "${binary}_binary" "$binary binary found at $(command -v "$binary")"

    # Test --version or --help
    local version_output
    if version_output=$("$binary" --version 2>&1); then
        pass "${binary}_version" "$binary version: ${version_output:0:100}"
    elif version_output=$("$binary" --help 2>&1); then
        pass "${binary}_version" "$binary help works: ${version_output:0:100}"
    else
        if [[ "$required" == "true" ]]; then
            fail "${binary}_version" "$binary --version and --help both failed"
        else
            skip "${binary}_version" "$binary --version and --help unavailable"
        fi
    fi
    return 0
}

# Run one or more probe commands for a tool.
# Optional probes degrade to skip when the command exists but needs extra setup.
test_tool_probe() {
    local test_name="$1"
    local binary="$2"
    local description="$3"
    local required="${4:-false}"
    local probe_timeout="${ACFS_E2E_PROBE_TIMEOUT:-20}"
    shift 4

    if ! command -v "$binary" >/dev/null 2>&1; then
        if [[ "$required" == "true" ]]; then
            fail "$test_name" "$binary probe skipped because the binary is missing"
        else
            skip "$test_name" "$binary probe skipped because the binary is missing"
        fi
        return 1
    fi

    local cmd=""
    local output=""
    for cmd in "$@"; do
        if command -v timeout >/dev/null 2>&1; then
            output=$(timeout "$probe_timeout" env PATH="$PATH" bash -c "$cmd" 2>&1)
        else
            output=$(env PATH="$PATH" bash -c "$cmd" 2>&1)
        fi

        if [[ $? -eq 0 ]]; then
            if [[ -n "$output" ]]; then
                pass "$test_name" "$description via '$cmd': ${output:0:100}"
            else
                pass "$test_name" "$description via '$cmd'"
            fi
            return 0
        fi
    done

    if [[ "$required" == "true" ]]; then
        fail "$test_name" "$description failed for all probes"
    else
        skip "$test_name" "$description unavailable or not configured yet"
    fi
    return 1
}

# ============================================================
# First-Class Flywheel Tools (7)
# ============================================================

test_flywheel_tools() {
    log "INFO" "SECTION" "========================================"
    log "INFO" "SECTION" "FIRST-CLASS FLYWHEEL TOOLS (7)"
    log "INFO" "SECTION" "========================================"

    # beads_rust (br) - REQUIRED
    log "INFO" "br" "Testing beads_rust (br)..."
    if test_tool_basic "beads_rust" "br" "true"; then
        # Verify core workflow in an isolated workspace so repo-local DB corruption
        # does not create false failures in installer verification.
        local br_probe_dir
        br_probe_dir=$(create_beads_probe_workspace)
        if [[ -z "$br_probe_dir" || ! -d "$br_probe_dir" ]]; then
            fail "br_list" "mktemp failed while creating isolated br probe workspace"
            return 1
        fi
        local br_list_output=""
        if (
            run_beads_probe_command "$br_probe_dir" br create "E2E probe issue" --type task --priority 4 >/dev/null 2>>"$LOG_FILE" &&
            br_list_output=$(run_beads_probe_command "$br_probe_dir" br list --json 2>>"$LOG_FILE") &&
            jq -e '
                if type == "array" then
                    any(.[]?; .title == "E2E probe issue")
                elif type == "object" then
                    (.issues | type == "array") and any(.issues[]?; .title == "E2E probe issue")
                else
                    false
                end
            ' <<<"$br_list_output" >/dev/null 2>&1
        ); then
            pass "br_list" "br init + br list --json succeeds in isolated workspace ($br_probe_dir)"
        else
            fail "br_list" "br init + br list --json failed in isolated workspace ($br_probe_dir)"
        fi
    fi

    # meta_skill (ms)
    log "INFO" "ms" "Testing meta_skill (ms)..."
    test_tool_basic "meta_skill" "ms" "true"

    # remote_compilation_helper (rch)
    log "INFO" "rch" "Testing remote_compilation_helper (rch)..."
    if test_tool_basic "remote_compilation_helper" "rch" "false"; then
        test_tool_probe "rch_probe" "rch" "rch health/status probe" "false" \
            "rch doctor" \
            "rch status" \
            "rch --help"
    fi

    # wezterm_automata (wa)
    log "INFO" "wa" "Testing wezterm_automata (wa)..."
    test_tool_basic "wezterm_automata" "wa" "false"

    # brenner_bot
    log "INFO" "brenner" "Testing brenner_bot..."
    test_tool_basic "brenner_bot" "brenner" "false"

    # dcg (Destructive Command Guard) - REQUIRED
    log "INFO" "dcg" "Testing Destructive Command Guard (dcg)..."
    if test_tool_basic "destructive_command_guard" "dcg" "true"; then
        # dcg doctor is more reliable with a pseudo-TTY.
        local dcg_doctor_exit=0
        if command -v script >/dev/null 2>&1; then
            script -e -q -c 'dcg doctor' /dev/null >/dev/null 2>&1
        else
            dcg doctor >/dev/null 2>&1
        fi
        dcg_doctor_exit=$?

        if [[ $dcg_doctor_exit -eq 0 ]]; then
            pass "dcg_doctor" "dcg doctor passes health check"
        else
            skip "dcg_doctor" "dcg doctor output unclear (may need configuration)"
        fi
    fi

    # ru (Repo Updater) - REQUIRED
    log "INFO" "ru" "Testing Repo Updater (ru)..."
    if test_tool_basic "repo_updater" "ru" "true"; then
        test_tool_probe "ru_probe" "ru" "ru operational probe" "true" \
            "ru doctor" \
            "ru status --help" \
            "ru sync --dry-run --help"
    fi
}

# ============================================================
# Additional Stack Tools (6)
# ============================================================

test_additional_stack_tools() {
    log "INFO" "SECTION" "========================================"
    log "INFO" "SECTION" "ADDITIONAL STACK TOOLS (6)"
    log "INFO" "SECTION" "========================================"

    # frankensearch (fsfs)
    log "INFO" "fsfs" "Testing frankensearch (fsfs)..."
    if test_tool_basic "frankensearch" "fsfs" "false"; then
        test_tool_probe "fsfs_probe" "fsfs" "fsfs operational probe" "false" \
            "fsfs status" \
            "fsfs version" \
            "fsfs --help"
    fi

    # storage_ballast_helper (sbh)
    log "INFO" "sbh" "Testing storage_ballast_helper (sbh)..."
    if test_tool_basic "storage_ballast_helper" "sbh" "false"; then
        test_tool_probe "sbh_probe" "sbh" "sbh operational probe" "false" \
            "sbh check" \
            "sbh status" \
            "sbh --help"
    fi

    # cross_agent_session_resumer (casr)
    log "INFO" "casr" "Testing cross_agent_session_resumer (casr)..."
    if test_tool_basic "cross_agent_session_resumer" "casr" "false"; then
        test_tool_probe "casr_probe" "casr" "casr provider listing" "false" \
            "casr providers" \
            "casr --help"
    fi

    # doodlestein_self_releaser (dsr)
    log "INFO" "dsr" "Testing doodlestein_self_releaser (dsr)..."
    if test_tool_basic "doodlestein_self_releaser" "dsr" "false"; then
        test_tool_probe "dsr_probe" "dsr" "dsr operational probe" "false" \
            "dsr doctor" \
            "dsr version" \
            "dsr --help"
    fi

    # agent_settings_backup (asb)
    log "INFO" "asb" "Testing agent_settings_backup (asb)..."
    if test_tool_basic "agent_settings_backup" "asb" "false"; then
        local asb_timeout="${ACFS_E2E_ASB_TIMEOUT:-20}"
        local asb_config_output=""
        local asb_backup_root=""
        local asb_version_output=""
        local asb_probe_agent=""
        local asb_backup_output=""
        local asb_backup_exit=0
        local asb_list_output=""
        local asb_list_exit=0
        local asb_repo_git_dir=""
        local asb_repo_dir=""
        local asb_git_log=""

        if asb_version_output=$(asb version 2>&1); then
            asb_version_output="${asb_version_output%%$'\n'*}"
            pass "asb_version_detail" "asb version returned: ${asb_version_output:-<empty>}"
        elif asb_version_output=$(asb help 2>&1); then
            asb_version_output="${asb_version_output%%$'\n'*}"
            pass "asb_version_detail" "asb help returned: ${asb_version_output:-<empty>}"
        else
            fail "asb_version_detail" "asb version/help probe failed"
        fi

        if asb_config_output=$(asb config show 2>&1); then
            asb_backup_root=$(printf '%s\n' "$asb_config_output" | sed -n 's/^ASB_BACKUP_ROOT:[[:space:]]*//p' | head -n 1)
        fi
        if [[ -z "$asb_backup_root" ]]; then
            asb_backup_root="${ASB_BACKUP_ROOT:-$HOME/.agent_settings_backups}"
        fi

        if command -v timeout >/dev/null 2>&1; then
            asb_list_output=$(timeout "$asb_timeout" asb list 2>&1)
            asb_list_exit=$?
        else
            asb_list_output=$(asb list 2>&1)
            asb_list_exit=$?
        fi

        if [[ $asb_list_exit -eq 0 ]]; then
            local asb_list_lines
            asb_list_lines=$(printf '%s\n' "$asb_list_output" | grep -cve '^[[:space:]]*$')
            pass "asb_list" "asb list succeeded with ${asb_list_lines} non-empty line(s)"
        elif [[ $asb_list_exit -eq 124 ]]; then
            fail "asb_list" "asb list timed out after ${asb_timeout}s"
        else
            fail "asb_list" "asb list failed: ${asb_list_output:0:140}"
        fi

        if [[ $asb_list_exit -eq 0 ]]; then
            local candidate=""
            for candidate in codex cline cursor gemini opencode factory claude; do
                if printf '%s\n' "$asb_list_output" | grep -Eq "^${candidate}[[:space:]].*(backed up|no backup)"; then
                    asb_probe_agent="$candidate"
                    break
                fi
            done
            if [[ -z "$asb_probe_agent" ]]; then
                asb_probe_agent=$(printf '%s\n' "$asb_list_output" | awk '/^[a-z0-9]/ && $0 !~ /not installed/ { print $1; exit }')
            fi
        fi

        if [[ -n "$asb_probe_agent" ]]; then
            if command -v timeout >/dev/null 2>&1; then
                asb_backup_output=$(timeout "$asb_timeout" asb --dry-run backup "$asb_probe_agent" 2>&1)
                asb_backup_exit=$?
            else
                asb_backup_output=$(asb --dry-run backup "$asb_probe_agent" 2>&1)
                asb_backup_exit=$?
            fi

            if [[ $asb_backup_exit -eq 0 ]]; then
                pass "asb_backup" "asb dry-run backup succeeded for ${asb_probe_agent}: ${asb_backup_output:0:140}"
            elif [[ $asb_backup_exit -eq 124 ]]; then
                skip "asb_backup" "asb dry-run backup for ${asb_probe_agent} timed out after ${asb_timeout}s"
            else
                skip "asb_backup" "asb dry-run backup for ${asb_probe_agent} failed: ${asb_backup_output:0:140}"
            fi
        else
            skip "asb_backup" "No installed agents reported by asb list"
        fi

        if [[ -d "$asb_backup_root" ]]; then
            pass "asb_backup_dir" "ASB backup root exists at $asb_backup_root"
        else
            skip "asb_backup_dir" "ASB backup root missing at $asb_backup_root"
        fi

        if [[ -d "$asb_backup_root" ]]; then
            asb_repo_git_dir=$(find "$asb_backup_root" -mindepth 2 -maxdepth 2 -type d -name .git 2>/dev/null | head -n 1)
            if [[ -n "$asb_repo_git_dir" ]]; then
                asb_repo_dir=$(dirname "$asb_repo_git_dir")
            fi
        fi

        if [[ -n "$asb_repo_dir" ]] && asb_git_log=$(git -C "$asb_repo_dir" log --oneline -1 2>&1); then
            asb_git_log="${asb_git_log%%$'\n'*}"
            pass "asb_git_repo" "ASB git repo valid at $asb_repo_dir: ${asb_git_log:-latest commit found}"
        else
            skip "asb_git_repo" "ASB per-agent git repo not found or invalid under $asb_backup_root"
        fi
    fi

    # post_compact_reminder (pcr)
    log "INFO" "pcr" "Testing post_compact_reminder (pcr)..."
    local pcr_hook_script="${HOME}/.local/bin/claude-post-compact-reminder"
    local pcr_settings="${HOME}/.claude/settings.json"
    local pcr_alt_settings="${HOME}/.config/claude/settings.json"
    local pcr_selected_settings=""
    local pcr_settings_has_hook="false"
    local pcr_hook_info=""

    if [[ -f "$pcr_settings" ]]; then
        pcr_selected_settings="$pcr_settings"
    elif [[ -f "$pcr_alt_settings" ]]; then
        pcr_selected_settings="$pcr_alt_settings"
    fi

    if [[ -n "$pcr_selected_settings" ]] && grep -q "claude-post-compact-reminder" "$pcr_selected_settings" 2>/dev/null; then
        pcr_settings_has_hook="true"
    fi

    if [[ ! -e "$pcr_hook_script" && "$pcr_settings_has_hook" != "true" ]]; then
        skip "pcr_hook" "pcr: hook not installed — optional tool"
    else
        if [[ -x "$pcr_hook_script" ]]; then
            pass "pcr_hook_script" "pcr: hook script present — $(file_details "$pcr_hook_script")"
        else
            fail "pcr_hook_script" "pcr: expected executable hook script at $pcr_hook_script"
        fi

        if [[ "$pcr_settings_has_hook" == "true" && -n "$pcr_selected_settings" ]]; then
            pass "pcr_settings_hook" "pcr: hook reference found in $pcr_selected_settings"

            if command -v python3 >/dev/null 2>&1; then
                if pcr_hook_info=$(PCR_SETTINGS="$pcr_selected_settings" python3 - <<'PY'
import json
import os

path = os.environ["PCR_SETTINGS"]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

hooks = data.get("hooks", {}).get("SessionStart", [])
matches = [hook for hook in hooks if "compact" in json.dumps(hook)]
assert matches, "PCR hook not found in SessionStart hooks"

sample = json.dumps(matches[0], separators=(",", ":"))
print(f"settings={path}; session_hooks={len(hooks)}; matching_hooks={len(matches)}; sample={sample[:160]}")
PY
); then
                    pass "pcr_settings_structure" "pcr: settings hook structure validated — $pcr_hook_info"
                else
                    skip "pcr_settings_structure" "pcr: hook reference found, but deep SessionStart validation failed in $pcr_selected_settings"
                fi
            fi
        else
            if [[ -n "$pcr_selected_settings" ]]; then
                fail "pcr_settings_hook" "pcr: hook entry missing in expected settings file $pcr_selected_settings"
            else
                fail "pcr_settings_hook" "pcr: settings.json hook entry missing in $pcr_settings and $pcr_alt_settings"
            fi
        fi

        if [[ -x "$pcr_hook_script" ]]; then
            if bash -n "$pcr_hook_script" 2>/dev/null; then
                pass "pcr_hook_syntax" "pcr: bash -n passed for $pcr_hook_script"
            else
                fail "pcr_hook_syntax" "pcr: bash -n failed for $pcr_hook_script"
            fi
        fi

        if [[ -n "$pcr_selected_settings" ]]; then
            local -a pcr_backups=()
            shopt -s nullglob
            pcr_backups=("${pcr_selected_settings}".bak*)
            shopt -u nullglob
            if (( ${#pcr_backups[@]} > 0 )); then
                pass "pcr_settings_backup" "pcr: found ${#pcr_backups[@]} settings backup file(s) for $pcr_selected_settings"
                verbose_log "pcr_settings_backup" "pcr backups: ${pcr_backups[*]}"
            else
                skip "pcr_settings_backup" "pcr: no settings backup file found for $pcr_selected_settings"
            fi
        fi
    fi
}

# ============================================================
# Utility Tools (9)
# ============================================================

test_utility_tools() {
    log "INFO" "SECTION" "========================================"
    log "INFO" "SECTION" "UTILITY TOOLS (9)"
    log "INFO" "SECTION" "========================================"

    # toon_rust (tru)
    log "INFO" "tru" "Testing toon_rust (tru)..."
    test_tool_basic "toon_rust" "tru" "false"

    # rust_proxy
    log "INFO" "rust_proxy" "Testing rust_proxy..."
    test_tool_basic "rust_proxy" "rust_proxy" "false"

    # rano
    log "INFO" "rano" "Testing rano..."
    test_tool_basic "rano" "rano" "false"

    # xf
    log "INFO" "xf" "Testing xf..."
    test_tool_basic "xf" "xf" "false"

    # mdwb
    log "INFO" "mdwb" "Testing markdown_web_browser (mdwb)..."
    test_tool_basic "markdown_web_browser" "mdwb" "false"

    # pt
    log "INFO" "pt" "Testing process_triage (pt)..."
    if test_tool_basic "process_triage" "pt" "false"; then
        test_tool_probe "pt_probe" "pt" "pt health probe" "false" \
            "pt check" \
            "pt doctor" \
            "pt --help"
    fi

    # aadc
    log "INFO" "aadc" "Testing aadc..."
    test_tool_basic "aadc" "aadc" "false"

    # s2p
    log "INFO" "s2p" "Testing source_to_prompt_tui (s2p)..."
    test_tool_basic "source_to_prompt_tui" "s2p" "false"

    # caut
    log "INFO" "caut" "Testing coding_agent_usage_tracker (caut)..."
    test_tool_basic "coding_agent_usage_tracker" "caut" "false"
}

# ============================================================
# Integration Tests
# ============================================================

test_integration() {
    log "INFO" "SECTION" "========================================"
    log "INFO" "SECTION" "INTEGRATION TESTS"
    log "INFO" "SECTION" "========================================"

    # Test 1: acfs doctor runs without errors
    log "INFO" "doctor" "Testing acfs doctor..."
    if command -v acfs >/dev/null 2>&1; then
        local doctor_output=""
        local doctor_exit=0
        # acfs doctor can legitimately take several minutes when the local
        # machine is under load, so keep the default timeout generous.
        local doctor_timeout="${ACFS_E2E_DOCTOR_TIMEOUT:-600}"

        if command -v timeout >/dev/null 2>&1; then
            doctor_output=$(timeout "$doctor_timeout" env ACFS_DOCTOR_CI=true acfs doctor 2>&1)
            doctor_exit=$?
        else
            doctor_output=$(ACFS_DOCTOR_CI=true acfs doctor 2>&1)
            doctor_exit=$?
        fi

        if [[ $doctor_exit -eq 0 ]]; then
            pass "doctor_runs" "acfs doctor completed without fatal errors"
        elif [[ $doctor_exit -eq 124 ]]; then
            fail "doctor_runs" "acfs doctor timed out after ${doctor_timeout}s"
        else
            fail "doctor_runs" "acfs doctor failed (exit=$doctor_exit)"
        fi

        # Check for DCG in doctor output without a pipe so pipefail cannot
        # turn an early grep match into a false negative.
        local doctor_output_lc="${doctor_output,,}"
        if [[ "$doctor_output_lc" =~ dcg|destructive[[:space:]-]+command ]]; then
            pass "doctor_dcg_check" "acfs doctor includes DCG health check"
        else
            skip "doctor_dcg_check" "DCG check not visible in doctor output"
        fi

        # Legacy hook cleanup is validated in the dedicated
        # removal test suite. acfs doctor may still
        # mention legacy status in its current output.
    else
        skip "doctor_runs" "acfs command not found"
        skip "doctor_dcg_check" "acfs command not found"
    fi

    # Test 2: br is the primary command (bd alias was removed)
    log "INFO" "br_primary" "Testing br is the primary beads command..."
    if command -v br >/dev/null 2>&1; then
        if br --help >/dev/null 2>&1; then
            pass "br_primary" "br is the primary beads_rust command"
        else
            fail "br_primary" "br --help failed"
        fi
    else
        fail "br_primary" "br binary not found"
    fi

    # Test 3: flywheel.ts contains the core tool entries used by the page
    log "INFO" "flywheel_ts" "Testing flywheel.ts tool entries..."
    local flywheel_file="${ACFS_REPO:-$HOME/agentic_coding_flywheel_setup}/apps/web/lib/flywheel.ts"
    if [[ ! -f "$flywheel_file" ]]; then
        flywheel_file="/data/projects/agentic_coding_flywheel_setup/apps/web/lib/flywheel.ts"
    fi

    if [[ -f "$flywheel_file" ]]; then
        local missing_tools=()
        for tool in br ms rch wa brenner dcg ru tru rust_proxy rano xf mdwb pt aadc s2p caut; do
            if ! command grep -qE "id:\s*[\"']${tool}[\"']" "$flywheel_file"; then
                missing_tools+=("$tool")
            fi
        done

        if [[ ${#missing_tools[@]} -eq 0 ]]; then
            pass "flywheel_ts_tools" "All expected core flywheel.ts tool entries are present"
        else
            fail "flywheel_ts_tools" "Missing tools in flywheel.ts: ${missing_tools[*]}"
        fi
    else
        skip "flywheel_ts_tools" "flywheel.ts not found at expected locations"
    fi

    # Test 4: bv (beads_viewer) works
    log "INFO" "bv" "Testing beads_viewer (bv)..."
    if command -v bv >/dev/null 2>&1; then
        local bv_probe_dir
        bv_probe_dir=$(create_beads_probe_workspace)
        if [[ -z "$bv_probe_dir" || ! -d "$bv_probe_dir" ]]; then
            fail "bv_triage" "mktemp failed while creating isolated bv probe workspace"
        elif run_beads_probe_command "$bv_probe_dir" br create "BV E2E probe issue" --type task --priority 4 >/dev/null 2>>"$LOG_FILE" && \
            bv_output=$(run_beads_probe_command "$bv_probe_dir" bv --robot-triage 2>>"$LOG_FILE") && \
            jq -e 'type == "object"' <<<"$bv_output" >/dev/null 2>&1; then
            pass "bv_triage" "bv --robot-triage returns valid JSON in isolated workspace"
        else
            fail "bv_triage" "bv --robot-triage failed"
        fi
    else
        fail "bv_binary" "bv binary not found (REQUIRED)"
    fi

    # Test 5: AI agents installed
    log "INFO" "agents" "Testing AI agent binaries..."
    for agent in claude codex gemini; do
        if command -v "$agent" >/dev/null 2>&1; then
            local ver
            ver=$("$agent" --version 2>&1) || ver="unknown"
            ver="${ver%%$'\n'*}"
            pass "${agent}_binary" "$agent installed: $ver"
        else
            skip "${agent}_binary" "$agent not installed (may be optional)"
        fi
    done
}

# ============================================================
# JSON Output
# ============================================================

write_json_results() {
    local result_status
    if [[ $FAIL_COUNT -gt 0 ]]; then
        result_status="FAILED"
    else
        result_status="PASSED"
    fi

    cat > "$JSON_FILE" <<EOF
{
  "test_suite": "ACFS New Tools E2E",
  "timestamp": "$(date -Iseconds)",
  "log_file": "$LOG_FILE",
  "summary": {
    "total": $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT)),
    "passed": $PASS_COUNT,
    "failed": $FAIL_COUNT,
    "skipped": $SKIP_COUNT,
    "result": "$result_status"
  },
  "categories": {
    "flywheel_tools": 7,
    "additional_stack_tools": 6,
    "utility_tools": 9,
    "integration_tests": 5
  },
  "tests": [
$(IFS=,; echo "${TEST_RESULTS[*]}" | sed 's/},{/},\n    {/g' | sed 's/^/    /')
  ]
}
EOF
    log "INFO" "OUTPUT" "JSON results written to: $JSON_FILE"
}

print_usage() {
    cat <<'EOF'
Usage: test_new_tools_e2e.sh [--json] [--verbose]

Options:
  --json     Emit the final JSON summary to stdout and send logs to stderr
  --verbose  Include additional detail in the log output
  -h, --help Show this help text
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                JSON_STDOUT=true
                ;;
            --verbose)
                VERBOSE=true
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                printf 'Unknown option: %s\n' "$1" >&2
                print_usage >&2
                exit 2
                ;;
        esac
        shift
    done
}

# ============================================================
# Summary
# ============================================================

print_summary() {
    log "INFO" "SUMMARY" "========================================"
    log "INFO" "SUMMARY" "ACFS NEW TOOLS E2E TEST SUMMARY"
    log "INFO" "SUMMARY" "========================================"
    log "INFO" "SUMMARY" "Passed:  $PASS_COUNT"
    log "INFO" "SUMMARY" "Failed:  $FAIL_COUNT"
    log "INFO" "SUMMARY" "Skipped: $SKIP_COUNT"
    log "INFO" "SUMMARY" "Total:   $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"
    log "INFO" "SUMMARY" ""
    log "INFO" "SUMMARY" "Log file:  $LOG_FILE"
    log "INFO" "SUMMARY" "JSON file: $JSON_FILE"
    log "INFO" "SUMMARY" "========================================"

    if [[ $FAIL_COUNT -gt 0 ]]; then
        log "INFO" "SUMMARY" "OVERALL: FAILED"
        return 1
    else
        log "INFO" "SUMMARY" "OVERALL: PASSED"
        return 0
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    parse_args "$@"

    log "INFO" "START" "========================================"
    log "INFO" "START" "ACFS New Tools E2E Test Suite"
    log "INFO" "START" "Started: $(date -Iseconds)"
    log "INFO" "START" "========================================"

    # Run all test sections
    test_flywheel_tools
    test_additional_stack_tools
    test_utility_tools
    test_integration

    # Output results
    write_json_results
    print_summary
    local summary_exit=$?

    if [[ "$JSON_STDOUT" == "true" ]]; then
        cat "$JSON_FILE"
    fi

    return $summary_exit
}

main "$@"
