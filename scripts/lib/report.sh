#!/usr/bin/env bash
# ============================================================
# ACFS Failure Reporting Library
#
# Provides structured failure reporting with pretty terminal output
# and JSON logging for tooling.
#
# Related beads:
#   - agentic_coding_flywheel_setup-5zm: Implement report_failure()
#   - agentic_coding_flywheel_setup-fkf: EPIC: Per-Phase Error Reporting
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_REPORT_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_REPORT_SH_LOADED=1

# ============================================================
# Configuration
# ============================================================

# Colors (may be overridden by caller)
REPORT_RED="${REPORT_RED:-\033[0;31m}"
REPORT_GREEN="${REPORT_GREEN:-\033[0;32m}"
REPORT_YELLOW="${REPORT_YELLOW:-\033[0;33m}"
REPORT_BLUE="${REPORT_BLUE:-\033[0;34m}"
REPORT_GRAY="${REPORT_GRAY:-\033[0;90m}"
REPORT_BOLD="${REPORT_BOLD:-\033[1m}"
REPORT_NC="${REPORT_NC:-\033[0m}"

# Log file for JSON output
ACFS_LOG_FILE="${ACFS_LOG_FILE:-/var/log/acfs/install.log}"

# ============================================================
# Log helpers
# ============================================================

_acfs_report_sudo_binary_path() {
    local candidate=""

    for candidate in \
        /usr/bin/sudo \
        /bin/sudo \
        /usr/local/bin/sudo \
        /usr/local/sbin/sudo \
        /usr/sbin/sudo \
        /sbin/sudo
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

_acfs_report_sudo() {
    local sudo_bin=""

    sudo_bin="$(_acfs_report_sudo_binary_path 2>/dev/null || true)"
    [[ -n "$sudo_bin" ]] || return 1
    "$sudo_bin" -n "$@"
}

_acfs_append_log_entry() {
    local entry="$1"
    local log_file="$ACFS_LOG_FILE"
    local log_dir
    log_dir="$(dirname "$log_file")"

    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            if _acfs_report_sudo_binary_path >/dev/null 2>&1; then
                _acfs_report_sudo mkdir -p "$log_dir" 2>/dev/null || return 0
            else
                return 0
            fi
        }
    fi

    if [[ -w "$log_file" || ( -e "$log_file" && -w "$log_dir" ) || ( ! -e "$log_file" && -w "$log_dir" ) ]]; then
        printf '%s\n' "$entry" >> "$log_file" 2>/dev/null || true
        return 0
    fi

    if _acfs_report_sudo_binary_path >/dev/null 2>&1; then
        printf '%s\n' "$entry" | _acfs_report_sudo tee -a "$log_file" >/dev/null 2>&1 || true
    fi
}

# ============================================================
# Box Drawing
# ============================================================

# Draw a box around text (ASCII fallback)
# Usage: draw_box <title> <...lines>
draw_box() {
    local title="$1"
    shift
    local lines=("$@")
    local width=60

    {
        # Top border
        echo -n "+"
        printf '%.0s-' $(seq 1 $((width - 2)))
        echo "+"

        # Title
        echo "| ${title}"
        echo -n "+"
        printf '%.0s-' $(seq 1 $((width - 2)))
        echo "+"

        # Content lines
        for line in "${lines[@]}"; do
            echo "| ${line}"
        done

        # Bottom border
        echo -n "+"
        printf '%.0s-' $(seq 1 $((width - 2)))
        echo "+"
    } >&2
}

# Draw a fancy box using gum (if available)
# Usage: draw_box_gum <title> <content>
draw_box_gum() {
    local title="$1"
    local content="$2"

    if command -v gum &>/dev/null; then
        {
            # Prepend title if provided
            local full_content
            if [[ -n "$title" ]]; then
                full_content="${title}\n\n${content}"
            else
                full_content="$content"
            fi

            echo -e "$full_content" | gum style \
                --border double \
                --border-foreground 196 \
                --padding "1 2" \
                --margin "1" \
                --width 66
        } >&2
    else
        {
            # Fallback to simple box
            if [[ -n "$title" ]]; then
                echo "=== $title ==="
            fi
            echo "$content"
        } >&2
    fi
}

# ============================================================
# Failure Report Functions
# ============================================================

report_build_resume_command() {
    local failed_phase="${1:-}"
    local failed_step="${2:-}"
    local resume_cmd=""

    if type -t generate_resume_hint &>/dev/null; then
        resume_cmd="$(generate_resume_hint "$failed_phase" "$failed_step" 2>/dev/null || true)"
        if [[ -n "$resume_cmd" ]]; then
            printf '%s\n' "$resume_cmd"
            return 0
        fi
    fi

    local install_url=""
    local install_url_q=""
    local curl_cmd="curl -q -fsSL"
    local local_install=""
    local resume_arg=""
    local resume_arg_q=""
    local resume_ref=""
    local resume_ref_pinned_from_commit=false
    local -a resume_args=(--resume)

    if command -v curl &>/dev/null && curl --help all 2>/dev/null | grep -q -- '--proto'; then
        curl_cmd="curl -q --proto '=https' --proto-redir '=https' -fsSL"
    fi

    if [[ "${MODE:-vibe}" != "vibe" ]]; then
        resume_args+=(--mode "$MODE")
    fi
    if [[ "${YES_MODE:-false}" == "true" ]]; then
        resume_args+=(--yes)
    fi
    if [[ "${STRICT_MODE:-false}" == "true" || "${ACFS_STRICT_MODE:-false}" == "true" ]]; then
        resume_args+=(--strict)
    fi
    [[ "${SKIP_POSTGRES:-false}" == "true" ]] && resume_args+=(--skip-postgres)
    [[ "${SKIP_VAULT:-false}" == "true" ]] && resume_args+=(--skip-vault)
    [[ "${SKIP_CLOUD:-false}" == "true" ]] && resume_args+=(--skip-cloud)
    [[ "${SKIP_PREFLIGHT:-false}" == "true" ]] && resume_args+=(--skip-preflight)
    [[ "${SKIP_UBUNTU_UPGRADE:-false}" == "true" ]] && resume_args+=(--skip-ubuntu-upgrade)

    if [[ -n "${ACFS_COMMIT_SHA_FULL:-}" ]]; then
        resume_ref="$ACFS_COMMIT_SHA_FULL"
        resume_ref_pinned_from_commit=true
    elif [[ -n "${ACFS_REF_INPUT:-}" && "${ACFS_REF_INPUT}" != "main" ]]; then
        resume_ref="$ACFS_REF_INPUT"
    elif [[ -n "${ACFS_REF:-}" && "${ACFS_REF}" != "main" ]]; then
        resume_ref="$ACFS_REF"
    fi
    if [[ -n "$resume_ref" ]]; then
        resume_args+=(--ref "$resume_ref")
    fi

    if [[ "${ACFS_CHECKSUMS_REF_EXPLICIT:-false}" == "true" && -n "${ACFS_CHECKSUMS_REF:-}" ]]; then
        resume_args+=(--checksums-ref "$ACFS_CHECKSUMS_REF")
    elif [[ "$resume_ref_pinned_from_commit" == "true" && -n "${ACFS_CHECKSUMS_REF:-}" && "$ACFS_CHECKSUMS_REF" != "main" ]]; then
        resume_args+=(--checksums-ref "$ACFS_CHECKSUMS_REF")
    fi
    if [[ "${ACFS_VERIFIED_BOOTSTRAP_SOURCE:-}" == "local_archive" ]] \
        && [[ -n "${ACFS_BOOTSTRAP_ORIGINAL_ARCHIVE_PATH:-}" ]]; then
        resume_args+=(--bootstrap-archive "$ACFS_BOOTSTRAP_ORIGINAL_ARCHIVE_PATH")
    fi

    # Keep this fallback in parity with install.sh's canonical resume builder.
    # Standalone report tests source this file without the installer, so guard
    # each optional array before expanding it under nounset.
    local selection=""
    if [[ "${ONLY_MODULES+x}" == "x" ]]; then
        for selection in "${ONLY_MODULES[@]}"; do
            resume_args+=(--only "$selection")
        done
    fi
    if [[ "${ONLY_PHASES+x}" == "x" ]]; then
        for selection in "${ONLY_PHASES[@]}"; do
            resume_args+=(--only-phase "$selection")
        done
    fi
    if [[ "${SKIP_MODULES+x}" == "x" ]]; then
        for selection in "${SKIP_MODULES[@]}"; do
            resume_args+=(--skip "$selection")
        done
    fi
    [[ "${NO_DEPS:-false}" == "true" ]] && resume_args+=(--no-deps)

    local logical_streamed=false
    if [[ -z "${SCRIPT_DIR:-}" ]] \
        || [[ "${ACFS_VERIFIED_BOOTSTRAP_SOURCE:-}" == "remote" ]] \
        || [[ "${ACFS_VERIFIED_BOOTSTRAP_SOURCE:-}" == "local_archive" ]]; then
        logical_streamed=true
    fi

    if [[ "$logical_streamed" != "true" ]]; then
        local_install="${SCRIPT_DIR%/}/install.sh"
        printf -v local_install '%q' "$local_install"
        resume_cmd="bash -p $local_install"
    else
        if [[ -n "${ACFS_COMMIT_SHA_FULL:-}" ]]; then
            install_url="https://raw.githubusercontent.com/${ACFS_REPO_OWNER:-Dicklesworthstone}/${ACFS_REPO_NAME:-agentic_coding_flywheel_setup}/${ACFS_COMMIT_SHA_FULL}/install.sh"
        elif [[ -n "${ACFS_REF_INPUT:-}" && "${ACFS_REF_INPUT}" != "main" ]]; then
            install_url="https://raw.githubusercontent.com/${ACFS_REPO_OWNER:-Dicklesworthstone}/${ACFS_REPO_NAME:-agentic_coding_flywheel_setup}/${ACFS_REF_INPUT}/install.sh"
        elif [[ -n "${ACFS_RAW:-}" ]]; then
            install_url="${ACFS_RAW%/}/install.sh"
        else
            install_url="https://acfs.sh"
        fi
        printf -v install_url_q '%q' "$install_url"
        resume_cmd="${curl_cmd} ${install_url_q} | bash -p -s --"
    fi

    for resume_arg in "${resume_args[@]}"; do
        printf -v resume_arg_q '%q' "$resume_arg"
        resume_cmd="${resume_cmd} ${resume_arg_q}"
    done

    printf '%s\n' "$resume_cmd"
}

# Report installation failure with full context
# Usage: report_failure [phase_num] [total_phases]
# Uses global variables: CURRENT_PHASE, CURRENT_PHASE_NAME, CURRENT_STEP,
#                        LAST_ERROR, LAST_ERROR_OUTPUT
report_failure() {
    local phase_num="${1:-?}"
    local total_phases="${2:-10}"

    # Get phase info from globals or state
    local phase="${CURRENT_PHASE:-unknown}"
    local phase_name="${CURRENT_PHASE_NAME:-Unknown Phase}"
    local step="${CURRENT_STEP:-unknown step}"
    local error="${LAST_ERROR:-Unknown error}"
    local error_output="${LAST_ERROR_OUTPUT:-}"
    local state_failed_phase=""
    local state_failed_step=""
    local state_failed_error=""

    if [[ -n "${ACFS_STATE_FILE:-}" && -r "${ACFS_STATE_FILE:-}" ]] && command -v jq &>/dev/null; then
        state_failed_phase="$(jq -r '.failed_phase // empty' "$ACFS_STATE_FILE" 2>/dev/null || true)"
        state_failed_step="$(jq -r '.failed_step // empty' "$ACFS_STATE_FILE" 2>/dev/null || true)"
        state_failed_error="$(jq -r '.failed_error // empty' "$ACFS_STATE_FILE" 2>/dev/null || true)"
    fi

    if [[ ( -z "$phase" || "$phase" == "unknown" ) && -n "$state_failed_phase" ]]; then
        phase="$state_failed_phase"
    fi
    if [[ ( -z "$phase_name" || "$phase_name" == "Unknown Phase" ) && -n "$phase" && "$phase" != "unknown" ]]; then
        local mapped_phase_name=""
        if declare -p ACFS_PHASE_NAMES >/dev/null 2>&1; then
            mapped_phase_name="${ACFS_PHASE_NAMES[$phase]:-}"
        fi
        if [[ -n "$mapped_phase_name" ]]; then
            phase_name="$mapped_phase_name"
        else
            phase_name="$phase"
        fi
    fi
    if [[ ( -z "$step" || "$step" == "unknown step" || "$step" == "Execution failed" ) && -n "$state_failed_step" ]]; then
        step="$state_failed_step"
    fi
    if [[ ( -z "$error" || "$error" == "Unknown error" ) && -n "$state_failed_error" ]]; then
        error="$state_failed_error"
    fi

    # Truncate error output if too long
    local max_error_lines=5
    if [[ $(echo "$error_output" | wc -l) -gt $max_error_lines ]]; then
        error_output=$(echo "$error_output" | head -n "$max_error_lines")
        error_output+=$'\n... (truncated)'
    fi

    # Get suggested fix from errors.sh if available
    local suggested_fix="Unknown error - check logs for details"
    if type -t get_suggested_fix &>/dev/null; then
        local matched_fix=""
        if type -t get_error_pattern &>/dev/null && get_error_pattern "$error" >/dev/null 2>&1; then
            matched_fix="$(get_suggested_fix "$error" 2>/dev/null || true)"
        elif [[ -n "$error_output" ]] && type -t get_error_pattern &>/dev/null && get_error_pattern "$error_output" >/dev/null 2>&1; then
            matched_fix="$(get_suggested_fix "$error_output" 2>/dev/null || true)"
        else
            matched_fix="$(get_suggested_fix "$error" 2>/dev/null || true)"
        fi
        [[ -n "$matched_fix" ]] && suggested_fix="$matched_fix"
    fi

    local resume_cmd=""
    resume_cmd="$(report_build_resume_command "$phase" "$step")"

    # Terminal output (stderr to keep stdout clean for piping)
    {
        echo ""
        if command -v gum &>/dev/null; then
            report_failure_gum "$phase_num" "$total_phases" "$phase_name" "$step" "$error" "$suggested_fix" "$resume_cmd"
        else
            report_failure_plain "$phase_num" "$total_phases" "$phase_name" "$step" "$error" "$error_output" "$suggested_fix" "$resume_cmd"
        fi
    } >&2

    # JSON logging
    report_failure_json "$phase_num" "$total_phases" "$phase" "$phase_name" "$step" "$error" "$error_output" "$suggested_fix"
}

# Plain text failure report
report_failure_plain() {
    local phase_num="$1"
    local total_phases="$2"
    local phase_name="$3"
    local step="$4"
    local error="$5"
    local error_output="$6"
    local suggested_fix="$7"
    local resume_cmd="$8"

    echo -e "${REPORT_RED}${REPORT_BOLD}"
    echo "================================================================"
    echo "  INSTALLATION FAILED"
    echo "================================================================${REPORT_NC}"
    echo ""
    echo -e "${REPORT_BOLD}Phase ${phase_num}/${total_phases}: ${phase_name}${REPORT_NC}"
    echo -e "Failed at: ${REPORT_YELLOW}${step}${REPORT_NC}"
    echo ""
    echo -e "${REPORT_BOLD}Error:${REPORT_NC}"
    echo -e "  ${REPORT_RED}${error}${REPORT_NC}"

    if [[ -n "$error_output" && "$error_output" != "$error" ]]; then
        echo ""
        echo -e "${REPORT_GRAY}Output:${REPORT_NC}"
        while IFS= read -r line; do
            echo "  $line"
        done <<< "$error_output"
    fi

    echo ""
    echo -e "${REPORT_BOLD}Suggested Fix:${REPORT_NC}"
    local rendered_fix
    rendered_fix="$(printf '%b' "$suggested_fix")"
    while IFS= read -r line; do
        echo "  $line"
    done <<< "$rendered_fix"

    echo ""
    echo -e "${REPORT_BOLD}To Resume:${REPORT_NC}"
    echo -e "  ${REPORT_BLUE}${resume_cmd}${REPORT_NC}"

    echo ""
    echo -e "${REPORT_GRAY}Full log: ${ACFS_LOG_FILE}${REPORT_NC}"
    echo ""
    echo -e "${REPORT_RED}================================================================${REPORT_NC}"
}

# Gum-styled failure report
report_failure_gum() {
    local phase_num="$1"
    local total_phases="$2"
    local phase_name="$3"
    local step="$4"
    local error="$5"
    local suggested_fix="$6"
    local resume_cmd="$7"

    # Header
    gum style \
        --foreground 196 \
        --bold \
        --border double \
        --border-foreground 196 \
        --padding "0 2" \
        --margin "1 0" \
        "  INSTALLATION FAILED"

    # Phase info
    echo ""
    gum style --bold "Phase ${phase_num}/${total_phases}: ${phase_name}"
    gum style --foreground 208 "Failed at: ${step}"

    # Error
    echo ""
    gum style --bold "Error:"
    gum style --foreground 196 "  ${error}"

    # Suggested fix
    echo ""
    gum style --bold "Suggested Fix:"
    echo "$suggested_fix" | gum format

    # Resume command
    echo ""
    gum style --bold "To Resume:"
    gum style --foreground 33 "  ${resume_cmd}"

    # Log location
    echo ""
    gum style --faint "Full log: ${ACFS_LOG_FILE}"
}

# JSON failure report (appends to log file)
report_failure_json() {
    local phase_num="$1"
    local total_phases="$2"
    local phase="$3"
    local phase_name="$4"
    local step="$5"
    local error="$6"
    local error_output="$7"
    local suggested_fix="$8"

    # Ensure log directory exists
    local log_dir
    log_dir=$(dirname "$ACFS_LOG_FILE")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || true
    fi

    # Normalize numeric fields for JSON (avoid jq failures / invalid JSON when unknown).
    local phase_num_json="$phase_num"
    local total_phases_json="$total_phases"
    [[ "$phase_num_json" =~ ^[0-9]+$ ]] || phase_num_json="null"
    [[ "$total_phases_json" =~ ^[0-9]+$ ]] || total_phases_json="null"

    # Generate JSON (prefer jq for proper escaping; fall back to manual escaping)
    local json_entry=""
    if command -v jq &>/dev/null; then
        json_entry=$(jq -n \
            --arg type "failure" \
            --arg timestamp "$(date -Iseconds)" \
            --argjson phase_num "$phase_num_json" \
            --argjson total_phases "$total_phases_json" \
            --arg phase "$phase" \
            --arg phase_name "$phase_name" \
            --arg step "$step" \
            --arg error "$error" \
            --arg error_output "$error_output" \
            --arg suggested_fix "$suggested_fix" \
            --arg version "${ACFS_VERSION:-0.1.0}" \
            --arg mode "${MODE:-unknown}" \
            '{
                type: $type,
                timestamp: $timestamp,
                version: $version,
                mode: $mode,
                phase: {
                    number: $phase_num,
                    total: $total_phases,
                    id: $phase,
                    name: $phase_name
                },
                failure: {
                    step: $step,
                    error: $error,
                    output: $error_output,
                    suggested_fix: $suggested_fix
                }
            }' 2>/dev/null) || json_entry=""
    fi

    if [[ -z "$json_entry" ]]; then
        # Manual JSON without jq (basic escaping for all string fields)
        local timestamp
        timestamp="$(date -Iseconds)"

        local escaped_timestamp="${timestamp//\\/\\\\}"
        escaped_timestamp="${escaped_timestamp//\"/\\\"}"
        escaped_timestamp="${escaped_timestamp//$'\n'/\\n}"
        escaped_timestamp="${escaped_timestamp//$'\r'/\\r}"
        escaped_timestamp="${escaped_timestamp//$'\t'/\\t}"

        local escaped_version="${ACFS_VERSION:-0.1.0}"
        escaped_version="${escaped_version//\\/\\\\}"
        escaped_version="${escaped_version//\"/\\\"}"
        escaped_version="${escaped_version//$'\n'/\\n}"
        escaped_version="${escaped_version//$'\r'/\\r}"
        escaped_version="${escaped_version//$'\t'/\\t}"

        local escaped_mode="${MODE:-unknown}"
        escaped_mode="${escaped_mode//\\/\\\\}"
        escaped_mode="${escaped_mode//\"/\\\"}"
        escaped_mode="${escaped_mode//$'\n'/\\n}"
        escaped_mode="${escaped_mode//$'\r'/\\r}"
        escaped_mode="${escaped_mode//$'\t'/\\t}"

        local escaped_phase="${phase//\\/\\\\}"
        escaped_phase="${escaped_phase//\"/\\\"}"
        escaped_phase="${escaped_phase//$'\n'/\\n}"
        escaped_phase="${escaped_phase//$'\r'/\\r}"
        escaped_phase="${escaped_phase//$'\t'/\\t}"

        local escaped_phase_name="${phase_name//\\/\\\\}"
        escaped_phase_name="${escaped_phase_name//\"/\\\"}"
        escaped_phase_name="${escaped_phase_name//$'\n'/\\n}"
        escaped_phase_name="${escaped_phase_name//$'\r'/\\r}"
        escaped_phase_name="${escaped_phase_name//$'\t'/\\t}"

        local escaped_step="${step//\\/\\\\}"
        escaped_step="${escaped_step//\"/\\\"}"
        escaped_step="${escaped_step//$'\n'/\\n}"
        escaped_step="${escaped_step//$'\r'/\\r}"
        escaped_step="${escaped_step//$'\t'/\\t}"

        local escaped_error="${error//\\/\\\\}"
        escaped_error="${escaped_error//\"/\\\"}"
        escaped_error="${escaped_error//$'\n'/\\n}"
        escaped_error="${escaped_error//$'\r'/\\r}"
        escaped_error="${escaped_error//$'\t'/\\t}"

        local escaped_output="${error_output//\\/\\\\}"
        escaped_output="${escaped_output//\"/\\\"}"
        escaped_output="${escaped_output//$'\n'/\\n}"
        escaped_output="${escaped_output//$'\r'/\\r}"
        escaped_output="${escaped_output//$'\t'/\\t}"

        local escaped_fix="${suggested_fix//\\/\\\\}"
        escaped_fix="${escaped_fix//\"/\\\"}"
        escaped_fix="${escaped_fix//$'\n'/\\n}"
        escaped_fix="${escaped_fix//$'\r'/\\r}"
        escaped_fix="${escaped_fix//$'\t'/\\t}"

        json_entry=$(cat <<EOF
{"type":"failure","timestamp":"${escaped_timestamp}","version":"${escaped_version}","mode":"${escaped_mode}","phase":{"number":${phase_num_json},"total":${total_phases_json},"id":"${escaped_phase}","name":"${escaped_phase_name}"},"failure":{"step":"${escaped_step}","error":"${escaped_error}","output":"${escaped_output}","suggested_fix":"${escaped_fix}"}}
EOF
)
    fi

    # Append to log file
    _acfs_append_log_entry "$json_entry"
}

# ============================================================
# Success Report
# ============================================================

# Report successful installation completion
# Usage: report_success [phase_count] [total_time_seconds]
report_success() {
    local phase_count="${1:-9}"
    local total_time="${2:-0}"
    local total_phases=""

    # Format time
    local time_str
    if [[ $total_time -gt 0 ]]; then
        local mins=$((total_time / 60))
        local secs=$((total_time % 60))
        if [[ $mins -gt 0 ]]; then
            time_str="${mins}m ${secs}s"
        else
            time_str="${secs}s"
        fi
    else
        time_str="unknown"
    fi

    if declare -p ACFS_PHASE_IDS >/dev/null 2>&1; then
        total_phases="${#ACFS_PHASE_IDS[@]}"
    fi
    if [[ -z "$total_phases" ]]; then
        total_phases="$phase_count"
    fi

    # Terminal output (stderr to keep stdout clean for piping)
    {
        echo ""
        if command -v gum &>/dev/null; then
            gum style \
                --foreground 46 \
                --bold \
                --border double \
                --border-foreground 46 \
                --padding "1 2" \
                --margin "1 0" \
                "  INSTALLATION COMPLETE!" \
                "" \
                "  Total time: ${time_str}" \
                "  Phases installed: ${phase_count}/${total_phases}" \
                "" \
                "  Next steps:" \
                "    1. Log out and back in (or run: source ~/.zshrc)" \
                "    2. Run: onboard" \
                "    3. Start coding with: cc, cod, or agy" \
                "" \
                "  Logs: ${ACFS_LOG_FILE}"
        else
            echo -e "${REPORT_GREEN}${REPORT_BOLD}"
            echo "================================================================"
            echo "  INSTALLATION COMPLETE!"
            echo "================================================================${REPORT_NC}"
            echo ""
            echo "  Total time: ${time_str}"
            echo "  Phases installed: ${phase_count}/${total_phases}"
            echo ""
            echo "  Next steps:"
            echo "    1. Log out and back in (or run: source ~/.zshrc)"
            echo "    2. Run: onboard"
            echo "    3. Start coding with: cc, cod, or agy"
            echo ""
            echo "  Logs: ${ACFS_LOG_FILE}"
            echo ""
            echo -e "${REPORT_GREEN}================================================================${REPORT_NC}"
        fi
    } >&2

    # Log success
    local json_entry
    if command -v jq &>/dev/null; then
        json_entry=$(jq -n \
            --arg type "success" \
            --arg timestamp "$(date -Iseconds)" \
            --argjson phases "$phase_count" \
            --argjson duration "$total_time" \
            --arg version "${ACFS_VERSION:-0.1.0}" \
            --arg mode "${MODE:-unknown}" \
            '{type: $type, timestamp: $timestamp, version: $version, mode: $mode, phases: $phases, duration: $duration}')
    else
        json_entry="{\"type\":\"success\",\"timestamp\":\"$(date -Iseconds)\",\"version\":\"${ACFS_VERSION:-0.1.0}\",\"mode\":\"${MODE:-unknown}\",\"phases\":${phase_count},\"duration\":${total_time}}"
    fi
    _acfs_append_log_entry "$json_entry"
}

# ============================================================
# Warning Report
# ============================================================

# Report a warning (non-fatal issue)
# Usage: report_warning <message> [details]
report_warning() {
    local message="$1"
    local details="${2:-}"

    # Terminal output (stderr to keep stdout clean for piping)
    {
        echo ""
        if command -v gum &>/dev/null; then
            gum style \
                --foreground 208 \
                --bold \
                "Warning: ${message}"
            if [[ -n "$details" ]]; then
                gum style --faint "  ${details}"
            fi
            gum style --faint "  Installer will continue. Re-run with --resume to retry failed steps."
        else
            echo -e "${REPORT_YELLOW}${REPORT_BOLD}Warning:${REPORT_NC} ${message}"
            if [[ -n "$details" ]]; then
                echo -e "  ${REPORT_GRAY}${details}${REPORT_NC}"
            fi
            echo -e "  ${REPORT_GRAY}Installer will continue. Re-run with --resume to retry failed steps.${REPORT_NC}"
        fi
    } >&2
}

# ============================================================
# Skip Report
# ============================================================

# Report skipped tools/phases summary at end of install
# Usage: report_skipped_tools
# Uses global: state.json data
report_skipped_summary() {
    local skipped_tools=""
    local skipped_phases=""

    # Get from state if available
    if type -t state_get &>/dev/null; then
        skipped_tools=$(state_get ".skipped_tools" 2>/dev/null || echo "")
        skipped_phases=$(state_get ".skipped_phases" 2>/dev/null || echo "")
    fi

    # Also check global variables
    if [[ -z "$skipped_tools" ]]; then
        skipped_tools="${SKIPPED_TOOLS:-}"
    fi

    if [[ -z "$skipped_tools" && -z "$skipped_phases" ]]; then
        return 0  # Nothing skipped
    fi

    # Terminal output (stderr to keep stdout clean for piping)
    {
        echo ""
        if command -v gum &>/dev/null; then
            gum style --foreground 208 --bold "Skipped Items:"
        else
            echo -e "${REPORT_YELLOW}${REPORT_BOLD}Skipped Items:${REPORT_NC}"
        fi

        if [[ -n "$skipped_tools" && "$skipped_tools" != "[]" && "$skipped_tools" != "null" ]]; then
            echo "  Tools: $skipped_tools"
        fi

        if [[ -n "$skipped_phases" && "$skipped_phases" != "[]" && "$skipped_phases" != "null" ]]; then
            echo "  Phases: $skipped_phases"
        fi

        echo ""
        echo "These items can be installed later with: acfs update --force"
    } >&2
}
