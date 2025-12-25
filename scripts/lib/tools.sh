#!/usr/bin/env bash
# ============================================================
# ACFS Installer - Tool Classification Library
#
# Classifies tools as CRITICAL vs RECOMMENDED to determine
# installation failure behavior.
#
# CRITICAL tools: Installation fails if these fail
#   - Foundational tools that other tools depend on
#   - Runtime managers and language toolchains
#
# RECOMMENDED tools: Installation continues with warning if fail
#   - Shell enhancements and optional utilities
#   - User-facing tools that can be installed manually later
#
# Related beads:
#   - agentic_coding_flywheel_setup-v8a: Classify tools
#   - agentic_coding_flywheel_setup-4jr: Checksum mismatch handling
#   - agentic_coding_flywheel_setup-5zm: Error reporting
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_TOOLS_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_TOOLS_SH_LOADED=1

# ============================================================
# Tool Classification Constants
# ============================================================

# CRITICAL_TOOLS: Installation MUST succeed for these
#
# Rationale for each:
#   - git: Version control foundation, everything depends on this
#   - curl: Network operations, required for all downloads
#   - bun: JavaScript runtime & package manager, many tools need it
#   - uv: Python package manager, Python tools depend on this
#   - go: Go compiler, builds lazygit and other Go-based tools
#   - zsh: Target shell, all shell config depends on this
#   - mise/rustup: Runtime managers that other installs depend on
#
readonly CRITICAL_TOOLS=(
    "git"
    "curl"
    "bun"
    "uv"
    "go"
    "zsh"
    "mise"
    "rustup"
    "cargo"
)

# RECOMMENDED_TOOLS: Continue with warning if these fail
#
# These enhance the experience but the system works without them.
# Users can install them manually later if needed.
#
readonly RECOMMENDED_TOOLS=(
    # Shell enhancements
    "ohmyzsh"
    "powerlevel10k"
    "zoxide"
    "atuin"
    "fzf"
    "direnv"
    
    # Modern CLI replacements
    "eza"
    "lsd"
    "bat"
    "ripgrep"
    "fd"
    "delta"
    
    # Development tools
    "lazygit"
    "lazydocker"
    "jq"
    "yq"
    "gh"
    "neovim"
    "tmux"
    "starship"
    
    # Coding agents (can install manually)
    "claude"
    "claude_code"
    "codex"
    "gemini"
    
    # Cloud tools
    "vault"
    "wrangler"
    "supabase"
    "convex"
    "vercel"
    "fly"
    "docker"
    
    # Dicklesworthstone stack
    "ntm"
    "mcp_agent_mail"
    "ubs"
    "bv"
    "cass"
    "cm"
    "caam"
    "slb"
    
    # Database
    "postgres"
    "postgresql"
    "psql"
)

# ============================================================
# Classification Functions
# ============================================================

# is_critical_tool - Check if a tool is classified as CRITICAL
#
# Arguments:
#   $1 - Tool name (e.g., "bun", "go", "lazygit")
#
# Returns:
#   0 if CRITICAL (installation must succeed)
#   1 if not CRITICAL (can be skipped)
#
# Example:
#   if is_critical_tool "bun"; then
#       echo "Bun is critical!"
#   fi
#
is_critical_tool() {
    local tool="$1"
    local critical

    # Normalize tool name (lowercase, strip common suffixes)
    # Using tr for portability (works in bash 3.x and zsh)
    tool="$(echo "$tool" | tr '[:upper:]' '[:lower:]')"
    tool="${tool%-cli}"  # strip -cli suffix
    tool="${tool%_cli}"  # strip _cli suffix

    for critical in "${CRITICAL_TOOLS[@]}"; do
        if [[ "${tool}" == "${critical}" ]]; then
            return 0
        fi
    done

    return 1
}

# is_recommended_tool - Check if a tool is classified as RECOMMENDED
#
# Arguments:
#   $1 - Tool name
#
# Returns:
#   0 if RECOMMENDED (can be skipped with warning)
#   1 if not in RECOMMENDED list (may still be CRITICAL or unknown)
#
is_recommended_tool() {
    local tool="$1"
    local recommended

    # Normalize tool name (lowercase, strip common suffixes)
    # Using tr for portability (works in bash 3.x and zsh)
    tool="$(echo "$tool" | tr '[:upper:]' '[:lower:]')"
    tool="${tool%-cli}"
    tool="${tool%_cli}"

    for recommended in "${RECOMMENDED_TOOLS[@]}"; do
        if [[ "${tool}" == "${recommended}" ]]; then
            return 0
        fi
    done

    return 1
}

# get_tool_classification - Get the classification of a tool
#
# Arguments:
#   $1 - Tool name
#
# Outputs:
#   "critical" if CRITICAL
#   "recommended" if RECOMMENDED
#   "unknown" if not classified
#
get_tool_classification() {
    local tool="$1"

    if is_critical_tool "$tool"; then
        echo "critical"
    elif is_recommended_tool "$tool"; then
        echo "recommended"
    else
        echo "unknown"
    fi
}

# ============================================================
# Failure Handling Functions
# ============================================================

# Track skipped tools during installation
declare -g SKIPPED_TOOLS=()

# handle_tool_failure - Handle a tool installation failure
#
# Based on tool classification:
#   - CRITICAL: Log error and exit with failure
#   - RECOMMENDED: Log warning and continue
#   - UNKNOWN: Treat as RECOMMENDED (safer default)
#
# Arguments:
#   $1 - Tool name
#   $2 - Error message/details
#
# Environment:
#   ACFS_STRICT_MODE - If set to "true", treat all failures as critical
#   ACFS_INTERACTIVE - If "false", auto-skip RECOMMENDED tools
#
# Returns:
#   0 for RECOMMENDED tools (continues)
#   Exits with code 1 for CRITICAL tools
#
handle_tool_failure() {
    local tool="$1"
    local error="${2:-Installation failed}"
    local classification

    classification="$(get_tool_classification "$tool")"

    # Strict mode treats all failures as critical
    if [[ "${ACFS_STRICT_MODE:-false}" == "true" ]]; then
        classification="critical"
    fi

    case "$classification" in
        critical)
            # Log error using logging.sh if available, otherwise echo
            if declare -f log_error &>/dev/null; then
                log_error "CRITICAL tool failed: $tool"
                log_error "$error"
                log_error "Installation cannot continue without $tool."
            else
                echo -e "\033[0;31mCRITICAL tool failed: $tool\033[0m" >&2
                echo -e "\033[0;31m$error\033[0m" >&2
                echo -e "\033[0;31mInstallation cannot continue without $tool.\033[0m" >&2
            fi
            exit 1
            ;;

        recommended|unknown)
            # Log warning and continue
            if declare -f log_warn &>/dev/null; then
                log_warn "Optional tool failed: $tool"
                log_warn "$error"
                log_warn "Continuing without $tool (can be installed manually later)"
            else
                echo -e "\033[0;33mOptional tool failed: $tool\033[0m" >&2
                echo -e "\033[0;33m$error\033[0m" >&2
                echo -e "\033[0;33mContinuing without $tool\033[0m" >&2
            fi
            SKIPPED_TOOLS+=("$tool")
            return 0
            ;;
    esac
}

# get_skipped_tools - Get list of tools that were skipped
#
# Outputs:
#   Newline-separated list of skipped tool names
#
get_skipped_tools() {
    printf '%s\n' "${SKIPPED_TOOLS[@]}"
}

# count_skipped_tools - Get count of skipped tools
#
# Outputs:
#   Number of skipped tools
#
count_skipped_tools() {
    echo "${#SKIPPED_TOOLS[@]}"
}

# has_skipped_tools - Check if any tools were skipped
#
# Returns:
#   0 if tools were skipped
#   1 if no tools were skipped
#
has_skipped_tools() {
    [[ ${#SKIPPED_TOOLS[@]} -gt 0 ]]
}

# ============================================================
# Non-Interactive Mode Behavior
# ============================================================

# should_auto_skip_on_failure - Determine if tool should auto-skip
#
# In non-interactive mode (CI, agents):
#   - CRITICAL tools: Never auto-skip (abort instead)
#   - RECOMMENDED tools: Auto-skip with warning
#
# Arguments:
#   $1 - Tool name
#
# Environment:
#   ACFS_INTERACTIVE - "true" for interactive, "false" for non-interactive
#
# Returns:
#   0 if should auto-skip
#   1 if should abort (or prompt in interactive mode)
#
should_auto_skip_on_failure() {
    local tool="$1"

    # CRITICAL tools never auto-skip
    if is_critical_tool "$tool"; then
        return 1
    fi

    # In non-interactive mode, RECOMMENDED tools auto-skip
    if [[ "${ACFS_INTERACTIVE:-true}" == "false" ]]; then
        return 0
    fi

    # In interactive mode, prompt user (caller handles this)
    return 1
}

# ============================================================
# Enhanced Skipped Tools Tracking
# Related: agentic_coding_flywheel_setup-8z5
# ============================================================

# Associative array to store skipped tool details (tool -> "reason|url")
declare -g -A SKIPPED_TOOL_DETAILS=()

# Record a skipped tool with details
#
# Arguments:
#   $1 - Tool name
#   $2 - Reason for skipping (e.g., "checksum mismatch", "network error")
#   $3 - Installer URL (optional)
#
record_skipped_tool() {
    local tool="$1"
    local reason="${2:-Installation failed}"
    local url="${3:-}"

    SKIPPED_TOOLS+=("$tool")
    SKIPPED_TOOL_DETAILS["$tool"]="$reason|$url"
}

# Get the reason a tool was skipped
get_skip_reason() {
    local tool="$1"
    local details="${SKIPPED_TOOL_DETAILS[$tool]:-}"
    echo "${details%%|*}"
}

# Get the installer URL for a skipped tool
get_skip_url() {
    local tool="$1"
    local details="${SKIPPED_TOOL_DETAILS[$tool]:-}"
    echo "${details#*|}"
}

# ============================================================
# Summary Report
# ============================================================

# Colors for output (will be overridden if logging.sh is sourced)
_TOOLS_YELLOW="${ACFS_YELLOW:-\033[0;33m}"
_TOOLS_CYAN="${ACFS_BLUE:-\033[0;36m}"
_TOOLS_DIM="\033[2m"
_TOOLS_NC="${ACFS_NC:-\033[0m}"

# report_skipped_tools - Print comprehensive summary of skipped tools
#
# This is the main post-install report function showing:
#   - Which tools were skipped
#   - Why they were skipped
#   - Installer URLs for manual installation
#   - Alternative solutions (acfs update)
#
# Call this at the end of installation.
#
report_skipped_tools() {
    if ! has_skipped_tools; then
        return 0
    fi

    local count
    count="$(count_skipped_tools)"

    echo "" >&2
    echo -e "${_TOOLS_YELLOW}============================================================${_TOOLS_NC}" >&2
    echo -e "${_TOOLS_YELLOW}  ⚠ SKIPPED TOOLS SUMMARY${_TOOLS_NC}" >&2
    echo -e "${_TOOLS_YELLOW}============================================================${_TOOLS_NC}" >&2
    echo "" >&2
    echo "The following $count tool(s) were skipped during installation:" >&2
    echo "" >&2

    local tool reason url
    for tool in "${SKIPPED_TOOLS[@]}"; do
        reason="$(get_skip_reason "$tool")"
        url="$(get_skip_url "$tool")"

        echo -e "  → ${_TOOLS_CYAN}$tool${_TOOLS_NC}: $reason" >&2
        if [[ -n "$url" ]]; then
            echo -e "    ${_TOOLS_DIM}$url${_TOOLS_NC}" >&2
        fi
    done

    echo "" >&2
    echo "------------------------------------------------------------" >&2
    echo "" >&2
    echo "You can install these tools manually:" >&2
    echo "" >&2

    for tool in "${SKIPPED_TOOLS[@]}"; do
        url="$(get_skip_url "$tool")"
        if [[ -n "$url" ]]; then
            echo "  # Install $tool" >&2
            echo "  curl -fsSL \"$url\" | bash" >&2
            echo "" >&2
        else
            echo "  # $tool - check documentation for install command" >&2
            echo "" >&2
        fi
    done

    echo "Or wait for ACFS to update checksums and run:" >&2
    echo -e "  ${_TOOLS_CYAN}acfs update --stack${_TOOLS_NC}" >&2
    echo "" >&2
    echo "To see current status:" >&2
    echo -e "  ${_TOOLS_CYAN}acfs doctor${_TOOLS_NC}" >&2
    echo "" >&2
}

# print_skipped_tools_summary - Alias for backwards compatibility
#
# Call report_skipped_tools() instead for the full enhanced output.
#
print_skipped_tools_summary() {
    report_skipped_tools
}

# Helper: JSON escape string
_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}" # escape backslashes
    s="${s//\"/\\\"}" # escape quotes
    s="${s//$'\n'/\\n}" # escape newlines
    s="${s//$'\r'/\\r}" # escape CR
    s="${s//$'\t'/\\t}" # escape tabs
    printf '%s' "$s"
}

# get_skipped_tools_json - Get skipped tools as JSON for state persistence
#
# Returns JSON array suitable for state.json:
# [{"name": "tool", "reason": "why", "url": "https://..."}]
#
get_skipped_tools_json() {
    if ! has_skipped_tools; then
        echo "[]"
        return 0
    fi

    local json="["
    local first=true
    local tool reason url

    for tool in "${SKIPPED_TOOLS[@]}"; do
        reason="$(get_skip_reason "$tool")"
        url="$(get_skip_url "$tool")"

        # Escape strings
        reason="$(_json_escape "$reason")"
        url="$(_json_escape "$url")"

        if [[ "$first" == "true" ]]; then
            first=false
        else
            json+=","
        fi

        json+="{\"name\":\"$tool\",\"reason\":\"$reason\""
        if [[ -n "$url" ]]; then
            json+=",\"url\":\"$url\""
        fi
        json+="}"
    done

    json+="]"
    echo "$json"
}
