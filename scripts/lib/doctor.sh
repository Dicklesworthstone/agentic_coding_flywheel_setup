#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Doctor - System Health Check
# Validates that ACFS installation is complete and working
#
# Uses gum for enhanced terminal UI when available
# ============================================================

ACFS_VERSION="${ACFS_VERSION:-0.1.0}"

# Ensure the doctor is self-contained and doesn't depend on shell rc files
# for PATH setup (e.g., when run from a fresh SSH session or non-zsh shell).
ensure_path() {
    local dir
    local to_add=()

    # Priority order for ACFS tools
    local candidate_dirs=(
        "$HOME/.local/bin"
        "$HOME/.acfs/bin"
        "$HOME/.bun/bin"
        "$HOME/.cargo/bin"
        "$HOME/.atuin/bin"
        "$HOME/go/bin"
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
    )

    for dir in "${candidate_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        # Robust PATH check using exact matching to avoid partial substring hits
        if [[ ":$PATH:" != *":$dir:"* ]]; then
            to_add+=("$dir")
        fi
    done

    if [[ ${#to_add[@]} -gt 0 ]]; then
        local prefix
        prefix=$(IFS=:; echo "${to_add[*]}")
        export PATH="${prefix}:$PATH"
    fi
}
ensure_path

# Check for gum and source gum_ui if available
HAS_GUM=false
if command -v gum &>/dev/null; then
    HAS_GUM=true
fi

# Source gum_ui library if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_acfs_doctor_find_project_path() {
    local rel_path="$1"
    local candidate=""

    for candidate in \
        "$SCRIPT_DIR/../$rel_path" \
        "$SCRIPT_DIR/../../$rel_path" \
        "${ACFS_HOME:-$HOME/.acfs}/$rel_path" \
        "$HOME/.acfs/$rel_path"; do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

_acfs_doctor_find_lib_script() {
    _acfs_doctor_find_project_path "scripts/lib/$1"
}

_acfs_doctor_find_scripts_script() {
    _acfs_doctor_find_project_path "scripts/$1"
}

_acfs_doctor_source_first() {
    local rel_path="$1"
    local candidate=""
    candidate="$(_acfs_doctor_find_lib_script "$rel_path" 2>/dev/null || true)"
    [[ -n "$candidate" ]] || return 1

    # shellcheck source=/dev/null
    source "$candidate"
    return 0
}

# Source output formatting library (for TOON support)
_acfs_doctor_source_first "output.sh" || true

# Global format options (set by argument parsing)
_DOCTOR_OUTPUT_FORMAT=""
_DOCTOR_SHOW_STATS=false

# Source doctor_fix library for --fix functionality
_acfs_doctor_source_first "doctor_fix.sh" || true

# Prefer the installed VERSION file when available.
_acfs_doctor_version_file="$(_acfs_doctor_find_project_path "VERSION" 2>/dev/null || true)"
if [[ -n "$_acfs_doctor_version_file" ]]; then
    ACFS_VERSION="$(cat "$_acfs_doctor_version_file" 2>/dev/null || echo "$ACFS_VERSION")"
fi
unset _acfs_doctor_version_file

# Prefer the installed state file for mode (vibe/safe) when available.
_acfs_doctor_installed_state="$(_acfs_doctor_find_project_path "state.json" 2>/dev/null || true)"
if [[ -z "${ACFS_MODE:-}" ]] && [[ -f "$_acfs_doctor_installed_state" ]]; then
    if command -v jq &>/dev/null; then
        ACFS_MODE="$(jq -r '.mode // empty' "$_acfs_doctor_installed_state" 2>/dev/null || true)"
    fi
    if [[ -z "${ACFS_MODE:-}" ]]; then
        ACFS_MODE="$(sed -n 's/.*"mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_acfs_doctor_installed_state" | head -n 1)"
    fi
    [[ -n "${ACFS_MODE:-}" ]] && export ACFS_MODE
fi
unset _acfs_doctor_installed_state

# Prefer the installed state file for target user (for installs where the target user is not ubuntu).
_acfs_doctor_state_files=()
if [[ -n "${ACFS_STATE_FILE:-}" ]]; then
    _acfs_doctor_state_files+=("$ACFS_STATE_FILE")
fi
if [[ -n "${ACFS_HOME:-}" ]]; then
    _acfs_doctor_state_files+=("$ACFS_HOME/state.json")
fi
_acfs_doctor_installed_state="$(_acfs_doctor_find_project_path "state.json" 2>/dev/null || true)"
if [[ -n "$_acfs_doctor_installed_state" ]]; then
    _acfs_doctor_state_files+=("$_acfs_doctor_installed_state")
fi
_acfs_doctor_state_files+=("$HOME/.acfs/state.json")

TARGET_USER="${TARGET_USER:-}"
if [[ -z "${TARGET_USER:-}" ]]; then
    for _acfs_doctor_state_file in "${_acfs_doctor_state_files[@]}"; do
        [[ -f "$_acfs_doctor_state_file" ]] || continue
        if command -v jq &>/dev/null; then
            TARGET_USER="$(jq -r '.target_user // empty' "$_acfs_doctor_state_file" 2>/dev/null || true)"
        fi
        if [[ -z "${TARGET_USER:-}" ]]; then
            TARGET_USER="$(sed -n 's/.*"target_user"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_acfs_doctor_state_file" | head -n 1)"
        fi
        [[ -n "${TARGET_USER:-}" ]] && break
    done
fi
unset _acfs_doctor_state_files
unset _acfs_doctor_state_file
unset _acfs_doctor_installed_state
if [[ -z "${TARGET_USER:-}" ]]; then
    _acfs_current_user="$(id -un 2>/dev/null || whoami 2>/dev/null || true)"
    if [[ -n "$_acfs_current_user" ]] && [[ "$_acfs_current_user" != "root" ]]; then
        TARGET_USER="$_acfs_current_user"
    fi
    unset _acfs_current_user
fi
TARGET_USER="${TARGET_USER:-ubuntu}"
if [[ ! "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    TARGET_USER="ubuntu"
fi
export TARGET_USER

_acfs_doctor_source_first "gum_ui.sh" || true

# ============================================================
# Fix Suggestion Builder (bd-31ps.5.2)
# ============================================================
# Builds copy-pasteable fix suggestions that respect the current
# install mode (vibe/safe) and pinned ref when known.
# ============================================================

# Build a fix suggestion command for a given module
# Usage: build_fix_suggestion <module_id> [--phase <phase_num>]
# Returns: A copy-pasteable install command
build_fix_suggestion() {
    local module_id="$1"
    shift
    local phase_flag=""

    # Parse optional --phase argument
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --phase)
                phase_flag="--only-phase $2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Base URL
    local base_url="https://agent-flywheel.com/install"

    # Build flags based on current state
    local flags="--yes --force-reinstall"

    # Add mode flag (vibe is default, but explicit is clearer)
    local mode="${ACFS_MODE:-vibe}"
    flags="$flags --mode $mode"

    # Add module/phase selector
    if [[ -n "$phase_flag" ]]; then
        flags="$flags $phase_flag"
    elif [[ -n "$module_id" ]]; then
        flags="$flags --only $module_id"
    fi

    # Build the command
    # Check if we have a pinned ref from state.json
    local ref_env=""
    local state_file=""
    state_file="$(_acfs_doctor_find_project_path "state.json" 2>/dev/null || true)"
    if [[ -f "$state_file" ]]; then
        local pinned_ref=""
        if command -v jq &>/dev/null; then
            pinned_ref=$(jq -r '.pinned_ref // empty' "$state_file" 2>/dev/null) || true
        fi
        if [[ -n "$pinned_ref" && "$pinned_ref" != "main" ]]; then
            ref_env="ACFS_REF=\"$pinned_ref\" "
        fi
    fi

    echo "curl -fsSL $base_url | ${ref_env}bash -s -- $flags"
}

# Shorthand for common fix patterns
fix_for_module() {
    local module_id="$1"
    build_fix_suggestion "$module_id"
}

fix_for_phase() {
    local phase_num="$1"
    build_fix_suggestion "" --phase "$phase_num"
}

agent_mail_doctor_check_json() {
    local description="Agent Mail doctor check"
    local result

    local exit_status=0
    if [[ $# -gt 0 ]]; then
        result="$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "$description" am doctor check --json "$1")" || exit_status=$?
    else
        result="$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "$description" am doctor check --json)" || exit_status=$?
    fi

    if [[ $exit_status -ne 0 ]] || [[ -z "$result" ]] || [[ "$result" == "TIMEOUT" ]]; then
        return 1
    fi

    printf '%s' "$result"
}

agent_mail_doctor_is_healthy() {
    local doctor_json="${1:-}"

    [[ -n "$doctor_json" ]] || return 1

    if command -v jq &>/dev/null; then
        [[ "$(printf '%s' "$doctor_json" | jq -r '.healthy // false' 2>/dev/null)" == "true" ]]
        return $?
    fi

    printf '%s' "$doctor_json" | grep -q '"healthy"[[:space:]]*:[[:space:]]*true'
}

agent_mail_doctor_summary() {
    local doctor_json="${1:-}"
    local summary=""

    [[ -n "$doctor_json" ]] || return 1

    if command -v jq &>/dev/null; then
        summary="$(printf '%s' "$doctor_json" | jq -r '
            [
                .checks[]?
                | select(.status == "fail")
                | "\(.check): \(.detail)"
            ] | join("; ")
        ' 2>/dev/null || true)"
        if [[ -n "$summary" ]]; then
            printf '%s' "$summary"
            return 0
        fi

        summary="$(printf '%s' "$doctor_json" | jq -r '
            [
                .checks[]?
                | select(.status == "warn")
                | "\(.check): \(.detail)"
            ] | join("; ")
        ' 2>/dev/null || true)"
        if [[ -n "$summary" ]]; then
            printf '%s' "$summary"
            return 0
        fi
    fi

    if printf '%s' "$doctor_json" | grep -q '"healthy"[[:space:]]*:[[:space:]]*false'; then
        printf '%s' "doctor check reported unhealthy state"
        return 0
    fi

    return 1
}

# ============================================================
# Manifest-Derived Checks (bd-31ps.5.1)
# ============================================================
# Source generated doctor_checks.sh to get MANIFEST_CHECKS array.
# This provides comprehensive manifest-driven verification for tools
# not already covered by the bespoke check functions below.
# ============================================================
MANIFEST_CHECKS_LOADED=false

# Source at top level (not inside a function) because doctor_checks.sh uses
# "declare -a MANIFEST_CHECKS=(...)" which bash scopes as local inside a
# function.  Top-level sourcing keeps the array globally visible.
_MANIFEST_CHECKS_FILE=""
_MANIFEST_CHECKS_FILE="$(_acfs_doctor_find_project_path "scripts/generated/doctor_checks.sh" 2>/dev/null || true)"

if [[ -n "$_MANIFEST_CHECKS_FILE" ]]; then
    # Save shell options before sourcing (doctor_checks.sh sets -euo pipefail)
    _MANIFEST_SAVED_OPTS=$(set +o)

    # shellcheck source=/dev/null
    if source "$_MANIFEST_CHECKS_FILE" 2>/dev/null; then
        MANIFEST_CHECKS_LOADED=true
    fi

    # Restore original shell options
    eval "$_MANIFEST_SAVED_OPTS" 2>/dev/null
    unset _MANIFEST_SAVED_OPTS
fi
unset _MANIFEST_CHECKS_FILE

# Colors (fallback if gum_ui not loaded)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Color scheme (Catppuccin Mocha)
ACFS_PRIMARY="${ACFS_PRIMARY:-#89b4fa}"
ACFS_SUCCESS="${ACFS_SUCCESS:-#a6e3a1}"
ACFS_WARNING="${ACFS_WARNING:-#f9e2af}"
ACFS_ERROR="${ACFS_ERROR:-#f38ba8}"
ACFS_MUTED="${ACFS_MUTED:-#6c7086}"
ACFS_ACCENT="${ACFS_ACCENT:-#cba6f7}"
ACFS_TEAL="${ACFS_TEAL:-#94e2d5}"

# Counters
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Skipped tools data (bead qup)
declare -ga SKIPPED_TOOLS_DATA=()

# Output modes
JSON_MODE=false
JSON_CHECKS=()

# Deep mode - run functional tests beyond binary existence
# Related: agentic_coding_flywheel_setup-01s
DEEP_MODE=false

# Fix mode - automatically apply safe fixes
# Related: bd-31ps.6.2
FIX_MODE=false
DRY_RUN_MODE=false

# Caching for deep checks - skip slow operations that recently passed
# Related: agentic_coding_flywheel_setup-lz1
NO_CACHE=false
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/acfs/doctor"
CACHE_TTL=300  # 5 minutes

# Per-check timeout (prevents indefinite hangs)
# Related: agentic_coding_flywheel_setup-lz1
DEEP_CHECK_TIMEOUT=15  # seconds

# Print `acfs` CLI help (only used when this script is installed as the `acfs` entrypoint).
print_acfs_help() {
    echo "ACFS - Agentic Coding Flywheel Setup"
    echo ""
    echo "Usage: acfs <command> [options]"
    echo ""
    echo "Commands:"
    echo "  doctor [options]    Check system health and tool status"
    echo "    --json            Output results as JSON"
    echo "    --deep            Run functional tests (auth, connections)"
    echo "  info [options]      Quick system overview (terminal/json/html)"
    echo "  status [options]    Quick one-line health summary"
    echo "  cheatsheet          Command reference (aliases, shortcuts)"
    echo "  changelog [options] Show recent project changes"
    echo "  export-config       Export config for backup/migration"
    echo "  continue [options]  View installation/upgrade progress"
    echo "  dashboard <command> Generate/view a static HTML dashboard"
    echo "  newproj <name>      Create new project with git, br, claude settings"
    echo "  update [options]    Update ACFS tools to latest versions"
    echo "  services-setup      Configure AI agents and cloud services"
    echo "  session <command>   Export/import/share agent sessions"
    echo "  support-bundle      Collect diagnostic data for troubleshooting"
    echo "  version             Show ACFS version"
    echo "  help                Show this help message"
}

resolve_session_lib() {
    local session_script=""
    session_script="$(_acfs_doctor_find_lib_script "session.sh" 2>/dev/null || true)"
    if [[ -n "$session_script" ]]; then
        echo "$session_script"
        return 0
    fi
    return 1
}

print_session_help() {
    echo "Usage: acfs session <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list [--json] [--days N] [--agent NAME] [--limit N]"
    echo "  export <session_path> [--format json|markdown] [--no-sanitize] [--output FILE]"
    echo "  recent [--workspace PATH] [--format json|markdown]"
    echo "  import <file.json> [--dry-run]"
    echo "  convert <native_session_file> --from <claude-code|codex|gemini> --to <claude-code|codex|gemini> [--workspace PATH] [--session-id ID] [--dry-run]"
    echo "  show <id> [--format json|markdown|summary]"
    echo "  list-imported"
    echo ""
    echo "Examples:"
    echo "  acfs session list --days 7"
    echo "  acfs session export ~/.codex/sessions/.../abc.jsonl --output session.json"
    echo "  acfs session convert ~/.codex/sessions/.../abc.jsonl --from codex --to claude-code --workspace /data/projects/foo"
    echo "  acfs session recent --workspace /data/projects/foo"
    echo "  acfs session import session.json --dry-run"
}

acfs_session_recent() {
    local workspace
    workspace="$(pwd)"
    local format="json"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --workspace requires a path" >&2
                    return 1
                fi
                workspace="$2"
                shift 2
                ;;
            --format)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --format requires a value (json or markdown)" >&2
                    return 1
                fi
                format="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    export_recent_session "$workspace" "$format"
}

acfs_session_main() {
    local session_lib
    session_lib="$(resolve_session_lib)" || {
        echo "Error: session.sh not found. Re-run the ACFS installer." >&2
        return 1
    }

    # shellcheck source=/dev/null
    source "$session_lib"

    local subcmd="${1:-}"
    case "$subcmd" in
        help|-h|"")
            print_session_help
            return 0
            ;;
    esac

    if ! check_session_deps; then
        return 1
    fi

    case "$subcmd" in
        list)
            shift
            list_sessions "$@"
            ;;
        export)
            shift
            export_session "$@"
            ;;
        recent)
            shift
            acfs_session_recent "$@"
            ;;
        import)
            shift
            import_session "$@"
            ;;
        convert)
            shift
            convert_session_native "$@"
            ;;
        show)
            shift
            show_session "$@"
            ;;
        list-imported)
            shift
            list_imported_sessions "$@"
            ;;
        *)
            echo "Unknown session command: $subcmd" >&2
            print_session_help
            return 1
            ;;
    esac
}

# Print a section header only in human output mode.
section() {
    if [[ "$JSON_MODE" != "true" ]]; then
        if [[ "$HAS_GUM" == "true" ]]; then
            echo ""
            gum style \
                --foreground "$ACFS_PRIMARY" \
                --bold \
                --border-foreground "$ACFS_MUTED" \
                --border normal \
                --padding "0 2" \
                --margin "0 0 1 0" \
                "󰋊 $1"
        else
            echo ""
            printf "${CYAN}━━━ %s ━━━${NC}\n" "$1"
        fi
    fi
}

# Print a blank line only in human output mode.
blank_line() {
    if [[ "$JSON_MODE" != "true" ]]; then
        echo ""
    fi
}

# Escape a string for safe inclusion in JSON (without surrounding quotes).
json_escape() {
    local s="${1:-}"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

# ============================================================
# Timeout and Caching Helpers (bead lz1)
# ============================================================

# Run a command with timeout, returning special status for timeout
# Usage: run_with_timeout <timeout_seconds> <description> <command> [args...]
# Returns: 0=success, 124=timeout, other=command exit code
# Output: Command stdout (or "TIMEOUT" on timeout)
run_with_timeout() {
    local timeout_secs="$1"
    local description="$2"
    shift 2

    local result
    local status
    result=$(timeout "$timeout_secs" "$@" 2>&1)
    status=$?

    if ((status == 124)); then
        echo "TIMEOUT"
        if [[ "$JSON_MODE" != "true" ]]; then
            # Log timeout warning (non-fatal)
            if [[ "$HAS_GUM" == "true" ]]; then
                gum style --foreground "$ACFS_MUTED" "    ⏱ $description timed out after ${timeout_secs}s" >&2
            else
                echo -e "    ${YELLOW}⏱ $description timed out after ${timeout_secs}s${NC}" >&2
            fi
        fi
        return 124
    fi

    echo "$result"
    return $status
}

# Store a successful check result in cache
# Usage: cache_result <key> <value>
cache_result() {
    local key="$1"
    local value="$2"

    # Skip if caching disabled
    [[ "$NO_CACHE" == "true" ]] && return 0

    mkdir -p "$CACHE_DIR"
    echo "$value" > "$CACHE_DIR/$key"
}

# Get a cached result if it exists and is fresh
# Usage: get_cached_result <key>
# Returns: 0 if cache hit, 1 if miss/expired
# Output: Cached value on hit
get_cached_result() {
    local key="$1"
    local cache_file="$CACHE_DIR/$key"

    # Skip if caching disabled
    [[ "$NO_CACHE" == "true" ]] && return 1

    # Check if cache file exists
    [[ -f "$cache_file" ]] || return 1

    # Check cache age (compatible with both Linux and macOS)
    local file_mtime
    local current_time
    current_time=$(date +%s)

    # Try GNU stat first, fall back to BSD stat
    if file_mtime=$(stat -c %Y "$cache_file" 2>/dev/null); then
        : # GNU stat worked
    elif file_mtime=$(stat -f %m "$cache_file" 2>/dev/null); then
        : # BSD stat worked
    else
        return 1  # Can't determine age, cache miss
    fi

    local age=$((current_time - file_mtime))
    if ((age >= CACHE_TTL)); then
        return 1  # Cache expired
    fi

    cat "$cache_file"
    return 0
}

normalize_config_value() {
    local value="${1-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ ${#value} -ge 2 ]]; then
        local first_char="${value:0:1}"
        local last_char="${value: -1}"
        if [[ ( "$first_char" == '"' && "$last_char" == '"' ) || ( "$first_char" == "'" && "$last_char" == "'" ) ]]; then
            value="${value:1:${#value}-2}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
        fi
    fi

    printf '%s\n' "$value"
}

is_placeholder_secret() {
    local normalized
    normalized="$(normalize_config_value "${1-}")"
    normalized="${normalized,,}"

    case "$normalized" in
        your-token-here|your-token|your_api_key|your-api-key|your_vercel_token|your_supabase_access_token|your_cloudflare_api_token|your_gemini_api_key|your_google_api_key|your_project_id|your_project_location|replace-me|change-me|changeme|"<token>"|"<api-key>"|"<secret>")
            return 0
            ;;
    esac

    return 1
}

has_usable_secret() {
    local normalized
    normalized="$(normalize_config_value "${1-}")"
    [[ -n "${normalized//[[:space:]]/}" ]] && ! is_placeholder_secret "$normalized"
}

read_configured_var_from_file() {
    local var_name="$1"
    local file_path="$2"
    [[ -f "$file_path" ]] || return 1

    local line=""
    local regex="^[[:space:]]*(export[[:space:]]+)?${var_name}[[:space:]]*=(.*)$"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ $regex ]]; then
            local value="${BASH_REMATCH[2]}"
            local first_char="${value:0:1}"
            if [[ "$first_char" != '"' && "$first_char" != "'" ]]; then
                value="${value%%#*}"
            fi
            value="$(normalize_config_value "$value")"
            if [[ -n "${value//[[:space:]]/}" ]]; then
                printf '%s\n' "$value"
                return 0
            fi
        fi
    done < "$file_path"

    return 1
}

get_configured_value() {
    local var_name="$1"
    shift

    local env_value="${!var_name-}"
    if [[ -n "${env_value//[[:space:]]/}" ]] && ! is_placeholder_secret "$env_value"; then
        normalize_config_value "$env_value"
        return 0
    fi

    local file_path=""
    local configured_value=""
    for file_path in "$@"; do
        configured_value="$(read_configured_var_from_file "$var_name" "$file_path" || true)"
        if [[ -n "${configured_value//[[:space:]]/}" ]] && ! is_placeholder_secret "$configured_value"; then
            printf '%s\n' "$configured_value"
            return 0
        fi
    done

    return 1
}

get_configured_secret() {
    local var_name="$1"
    shift

    local env_value="${!var_name-}"
    if has_usable_secret "$env_value"; then
        normalize_config_value "$env_value"
        return 0
    fi

    local file_path=""
    local configured_value=""
    for file_path in "$@"; do
        configured_value="$(read_configured_var_from_file "$var_name" "$file_path" || true)"
        if has_usable_secret "$configured_value"; then
            printf '%s\n' "$configured_value"
            return 0
        fi
    done

    return 1
}

configured_truthy_value() {
    local var_name="$1"
    shift

    local configured_value=""
    configured_value="$(get_configured_value "$var_name" "$@" || true)"
    case "${configured_value,,}" in
        1|true|yes|on)
            return 0
            ;;
    esac

    return 1
}

default_auth_config_files() {
    printf '%s\n' \
        "$HOME/.zshrc.local" \
        "$HOME/.zshrc" \
        "$HOME/.bashrc" \
        "$HOME/.profile"
}

# Run a check with cache support
# Usage: check_with_cache <cache_key> <description> <command> [args...]
# Returns: Command exit status (0 = cache hit counts as success)
check_with_cache() {
    local cache_key="$1"
    local description="$2"
    shift 2

    # Try cache first
    local cached
    if cached=$(get_cached_result "$cache_key"); then
        echo "$cached (cached)"
        return 0
    fi

    # Run actual check with timeout
    local result
    local status
    result=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "$description" "$@")
    status=$?

    # Cache successful results
    if ((status == 0)); then
        cache_result "$cache_key" "$result"
    fi

    echo "$result"
    return $status
}

# Check with [?] (unknown) indicator for timeouts
# This variant of check() handles timeout status specially
# Usage: check_with_timeout_status <id> <label> <status> [details] [fix]
# status can be: pass, warn, fail, timeout
check_with_timeout_status() {
    local id="$1"
    local label="$2"
    local status="$3"
    local details="${4:-}"
    local fix="${5:-}"

    # Convert timeout to special handling
    if [[ "$status" == "timeout" ]]; then
        # Timeouts count as warnings for stats (unknown state, not failed)
        ((WARN_COUNT += 1))

        if [[ "$JSON_MODE" == "true" ]]; then
            local fix_json="null"
            if [[ -n "$fix" ]]; then
                fix_json="\"$(json_escape "$fix")\""
            fi
            JSON_CHECKS+=("{\"id\":\"$(json_escape "$id")\",\"label\":\"$(json_escape "$label")\",\"status\":\"timeout\",\"details\":\"$(json_escape "$details")\",\"fix\":$fix_json}")
            return 0
        fi

        # Display with [?] indicator
        if [[ "$HAS_GUM" == "true" ]]; then
            echo "  $(gum style --foreground "$ACFS_WARNING" --bold "? WAIT") $(gum style "$label")"
            if [[ -n "$fix" ]]; then
                echo "        $(gum style --foreground "$ACFS_MUTED" "Fix:") $(gum style --foreground "$ACFS_ACCENT" --italic "$fix")"
            fi
        else
            echo -e "  ${YELLOW}? WAIT${NC} $label"
            if [[ -n "$fix" ]]; then
                echo -e "        Fix: $fix"
            fi
        fi
        return 0
    fi

    # Delegate to standard check for other statuses
    check "$id" "$label" "$status" "$details" "$fix"
}

# Check result helper
check() {
    local id="$1"
    local label="$2"
    local status="$3"
    local details="${4:-}"
    local fix="${5:-}"

    case "$status" in
        pass) ((PASS_COUNT += 1)) ;;
        warn) ((WARN_COUNT += 1)) ;;
        fail) ((FAIL_COUNT += 1)) ;;
    esac

    if [[ "$JSON_MODE" == "true" ]]; then
        local fix_json="null"
        if [[ -n "$fix" ]]; then
            fix_json="\"$(json_escape "$fix")\""
        fi

        JSON_CHECKS+=("{\"id\":\"$(json_escape "$id")\",\"label\":\"$(json_escape "$label")\",\"status\":\"$(json_escape "$status")\",\"details\":\"$(json_escape "$details")\",\"fix\":$fix_json}")
        return 0
    fi

    if [[ "$HAS_GUM" == "true" ]]; then
        case "$status" in
            pass)
                echo "  $(gum style --foreground "$ACFS_SUCCESS" --bold "✓ PASS") $(gum style --foreground "$ACFS_TEAL" "$label")"
                ;;
            warn)
                echo "  $(gum style --foreground "$ACFS_WARNING" --bold "⚠ WARN") $(gum style "$label")"
                if [[ -n "$fix" ]]; then
                    echo "        $(gum style --foreground "$ACFS_MUTED" "Fix:") $(gum style --foreground "$ACFS_ACCENT" --italic "$fix")"
                fi
                ;;
            fail)
                echo "  $(gum style --foreground "$ACFS_ERROR" --bold "✖ FAIL") $(gum style "$label")"
                if [[ -n "$fix" ]]; then
                    echo "        $(gum style --foreground "$ACFS_MUTED" "Fix:") $(gum style --foreground "$ACFS_ACCENT" --italic "$fix")"
                fi
                ;;
        esac
    else
        case "$status" in
            pass)
                echo -e "  ${GREEN}✓ PASS${NC} $label"
                ;;
            warn)
                echo -e "  ${YELLOW}⚠ WARN${NC} $label"
                if [[ -n "$fix" ]]; then
                    echo -e "        Fix: $fix"
                fi
                ;;
            fail)
                echo -e "  ${RED}✖ FAIL${NC} $label"
                if [[ -n "$fix" ]]; then
                    echo -e "        Fix: $fix"
                fi
                ;;
        esac
    fi

    # Dispatch fix if --fix mode is enabled
    if [[ "$FIX_MODE" == "true" ]] && [[ "$status" != "pass" ]]; then
        if type -t dispatch_fix &>/dev/null; then
            dispatch_fix "$id" "$status" "$fix"
        fi
    fi
}

# Try to retrieve a reasonably informative version line for a command without
# assuming it supports `--version`.
get_version_line() {
    local cmd="$1"

    local version=""
    # UBS has a directory size check that can block --version; bypass it
    if [[ "$cmd" == "ubs" ]]; then
        version=$(UBS_MAX_DIR_SIZE_MB=10000 "$cmd" --version 2>/dev/null | head -n1) || true
    else
        version=$("$cmd" --version 2>/dev/null | head -n1) || true
    fi
    if [[ -z "$version" ]]; then
        version=$("$cmd" -V 2>/dev/null | head -n1) || true
    fi
    if [[ -z "$version" ]]; then
        version=$("$cmd" version 2>/dev/null | head -n1) || true
    fi

    if [[ -z "$version" ]]; then
        version="available"
    fi

    printf '%s' "$version"
}

# Check if command exists
check_command() {
    local id="$1"
    local label="$2"
    local cmd="$3"
    local fix="${4:-}"

    if command -v "$cmd" &>/dev/null; then
        local version
        version=$(get_version_line "$cmd")
        check "$id" "$label ($version)" "pass" "installed"
    else
        check "$id" "$label" "fail" "not found" "$fix"
    fi
}

# Check a command, but treat missing as WARN (optional dependency).
check_optional_command() {
    local id="$1"
    local label="$2"
    local cmd="$3"
    local fix="${4:-}"

    if command -v "$cmd" &>/dev/null; then
        local version
        version=$(get_version_line "$cmd")
        check "$id" "$label ($version)" "pass" "installed"
    else
        check "$id" "$label" "warn" "not found" "$fix"
    fi
}

# Check identity
check_identity() {
    section "Identity"

    # Check user
    local user
    user=$(whoami)
    if [[ "$user" == "$TARGET_USER" ]]; then
        check "identity.user_is_ubuntu" "Logged in as $TARGET_USER" "pass" "whoami=$user"
    else
        check "identity.user_is_ubuntu" "Logged in as $TARGET_USER (currently: $user)" "warn" "whoami=$user" "ssh ${TARGET_USER}@YOUR_SERVER"
    fi

    # Check sudo configuration (passwordless only required in vibe mode)
    if [[ "${ACFS_MODE:-vibe}" == "vibe" ]]; then
        if sudo -n true 2>/dev/null; then
            check "identity.passwordless_sudo" "Passwordless sudo (vibe mode)" "pass"
        else
            check "identity.passwordless_sudo" "Passwordless sudo (vibe mode)" "fail" "requires password" "Re-run ACFS installer with --mode vibe"
        fi
    else
        if command -v sudo &>/dev/null && id -nG 2>/dev/null | grep -qw sudo; then
            check "identity.sudo" "Sudo available (safe mode)" "pass"
        else
            check "identity.sudo" "Sudo available (safe mode)" "fail" "sudo unavailable" "Ensure ${TARGET_USER} is in the sudo group and sudo is installed"
        fi
    fi

    blank_line
}

# Check workspace
check_workspace() {
    section "Workspace"

    if [[ -d "/data/projects" ]] && [[ -w "/data/projects" ]]; then
        check "workspace.data_projects" "/data/projects exists and writable" "pass"
    else
        check "workspace.data_projects" "/data/projects" "fail" "missing or not writable" "sudo mkdir -p /data/projects && sudo chown ${TARGET_USER}:${TARGET_USER} /data/projects"
    fi

    blank_line
}

# Check shell
check_shell() {
    section "Shell"

    check_command "shell.zsh" "zsh" "zsh" "sudo apt install zsh"

    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        check "shell.ohmyzsh" "Oh My Zsh" "pass"
    else
        check "shell.ohmyzsh" "Oh My Zsh" "fail" "not installed" "$(fix_for_module "shell.omz")"
    fi

    local p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ -d "$p10k_dir" ]]; then
        check "shell.p10k" "Powerlevel10k" "pass"
    else
        check "shell.p10k" "Powerlevel10k" "warn" "not installed"
    fi

    # Check plugins
    local plugins_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
    if [[ -d "$plugins_dir/zsh-autosuggestions" ]]; then
        check "shell.plugins.zsh_autosuggestions" "zsh-autosuggestions" "pass"
    else
        check "shell.plugins.zsh_autosuggestions" "zsh-autosuggestions" "warn" "not installed" \
            "git clone https://github.com/zsh-users/zsh-autosuggestions \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    fi

    if [[ -d "$plugins_dir/zsh-syntax-highlighting" ]]; then
        check "shell.plugins.zsh_syntax_highlighting" "zsh-syntax-highlighting" "pass"
    else
        check "shell.plugins.zsh_syntax_highlighting" "zsh-syntax-highlighting" "warn" "not installed" \
            "git clone https://github.com/zsh-users/zsh-syntax-highlighting \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
    fi

    # Check modern CLI tools
    if command -v lsd &>/dev/null; then
        check "shell.lsd_or_eza" "lsd" "pass"
    elif command -v eza &>/dev/null; then
        check "shell.lsd_or_eza" "eza (fallback)" "pass"
    else
        check "shell.lsd_or_eza" "lsd/eza" "warn" "neither installed" "sudo apt install lsd"
    fi

    check_command "shell.atuin" "Atuin" "atuin" "$(fix_for_module "shell.atuin")"
    check_command "shell.fzf" "fzf" "fzf" "sudo apt install fzf"
    check_command "shell.zoxide" "zoxide" "zoxide" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash"
    check_command "shell.direnv" "direnv" "direnv" "sudo apt install direnv"

    blank_line
}

# Check core tools
check_core_tools() {
    section "Core tools"

    check_command "tool.bun" "Bun" "bun" "$(fix_for_module "lang.bun")"
    check_command "tool.uv" "uv" "uv" "$(fix_for_module "lang.uv")"
    check_command "tool.cargo" "Cargo (Rust)" "cargo" "$(fix_for_module "lang.rust")"
    check_command "tool.go" "Go" "go" "sudo apt install golang-go"
    check_command "tool.tmux" "tmux" "tmux" "sudo apt install tmux"
    check_command "tool.rg" "ripgrep" "rg" "sudo apt install ripgrep"
    check_command "tool.gh" "GitHub CLI (gh)" "gh" "sudo apt-get install -y gh"
    check_command "tool.git_lfs" "Git LFS" "git-lfs" "sudo apt-get install -y git-lfs"
    check_command "tool.rsync" "rsync" "rsync" "sudo apt-get install -y rsync"
    check_command "tool.strace" "strace" "strace" "sudo apt-get install -y strace"
    check_command "tool.lsof" "lsof" "lsof" "sudo apt-get install -y lsof"
    check_command "tool.zstd" "zstd" "zstd" "sudo apt-get install -y zstd"
    check_optional_command "tool.cosign" "cosign" "cosign" \
        "COSIGN_VERSION=v2.4.1 && curl -fsSL https://github.com/sigstore/cosign/releases/download/\${COSIGN_VERSION}/cosign-linux-amd64 -o /tmp/cosign && sudo install /tmp/cosign /usr/local/bin/cosign"
    check_command "tool.dig" "dig (dnsutils)" "dig" "sudo apt-get install -y dnsutils"
    check_command "tool.nc" "nc (netcat-openbsd)" "nc" "sudo apt-get install -y netcat-openbsd"
    check_command "tool.sg" "ast-grep" "sg" "cargo install ast-grep --locked"

    blank_line
}

# Check coding agents
check_agents() {
    section "Agents"

    check_command "agent.claude" "Claude Code" "claude" "$(fix_for_module "agents.claude")"
    check_command "agent.codex" "Codex CLI" "codex" "$(fix_for_module "agents.codex")"
    check_command "agent.gemini" "Gemini CLI" "gemini" "$(fix_for_module "agents.gemini")"

    # Check aliases are defined in the zshrc
    local alias_fix
    alias_fix="$(fix_for_module "shell.omz")"
    if grep -q "^alias cc=" ~/.acfs/zsh/acfs.zshrc 2>/dev/null; then
        check "agent.alias.cc" "cc alias" "pass"
    else
        check "agent.alias.cc" "cc alias" "warn" "not in zshrc" "$alias_fix"
    fi

    if grep -q "^alias cod=" ~/.acfs/zsh/acfs.zshrc 2>/dev/null; then
        check "agent.alias.cod" "cod alias" "pass"
    else
        check "agent.alias.cod" "cod alias" "warn" "not in zshrc" "$alias_fix"
    fi

    # gmi is defined as a shell function (not an alias) in acfs.zshrc
    if grep -q "^gmi()" ~/.acfs/zsh/acfs.zshrc 2>/dev/null || grep -q "^alias gmi=" ~/.acfs/zsh/acfs.zshrc 2>/dev/null; then
        check "agent.alias.gmi" "gmi function" "pass"
    else
        check "agent.alias.gmi" "gmi function" "warn" "not in zshrc" "$alias_fix"
    fi

    # Check for PATH conflicts (bead hi7)
    # Claude Code native install should be in ~/.local/bin, not bun/npm
    check_agent_path_conflicts

    blank_line
}

# Check for agent PATH conflicts (bead hi7)
# Native installations should take precedence over package manager versions
check_agent_path_conflicts() {
    local doctor_ci="${ACFS_DOCTOR_CI:-false}"

    local claude_path
    claude_path=$(command -v claude 2>/dev/null) || true

    if [[ -z "$claude_path" ]]; then
        return 0  # Not installed, skip
    fi

    # Native install should be in ~/.local/bin
    if [[ "$claude_path" == "$HOME/.local/bin/claude" ]]; then
        check "agent.path.claude" "Claude Code path" "pass" "native ($claude_path)"
    elif [[ "$claude_path" == *".bun"* ]] || [[ "$claude_path" == *"node_modules"* ]]; then
        if [[ "$doctor_ci" == "true" ]]; then
            check "agent.path.claude" "Claude Code path" "pass" "using bun/npm version (expected in CI): $claude_path"
        else
            # Package manager version - warn about potential conflicts
            check "agent.path.claude" "Claude Code path" "warn" \
                "using bun/npm version ($claude_path)" \
                "Switch to native: acfs update --force --agents-only (removes bun version, installs native)"
        fi
    else
        # Some other path - just note it
        check "agent.path.claude" "Claude Code path" "pass" "$claude_path"
    fi
}

# Check DCG hook registration status
check_dcg_hook_status() {
    if ! command -v dcg &>/dev/null; then
        check "stack.dcg" "DCG" "warn" "not installed" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/main/install.sh | bash && dcg install"
        return
    fi

    local version
    version=$(get_version_line "dcg")

    if ! command -v claude &>/dev/null; then
        check "stack.dcg" "DCG ($version)" "warn" "Claude Code not found for hook registration" \
            "Install Claude Code, then run: dcg install"
        return
    fi

    local settings_file=""
    if [[ -f "$HOME/.claude/settings.json" ]]; then
        settings_file="$HOME/.claude/settings.json"
    elif [[ -f "$HOME/.config/claude/settings.json" ]]; then
        settings_file="$HOME/.config/claude/settings.json"
    fi

    if [[ -z "$settings_file" ]]; then
        check "stack.dcg" "DCG ($version)" "warn" "hook not registered (settings.json missing)" \
            "Run: dcg install"
        return
    fi

    if grep -q "dcg" "$settings_file" 2>/dev/null; then
        check "stack.dcg" "DCG ($version)" "pass" "installed + hook registered"
    else
        check "stack.dcg" "DCG ($version)" "warn" "binary installed but hook not registered" \
            "Run: dcg install"
    fi
}

# Check cloud tools
check_cloud() {
    section "Cloud/DB"

    local doctor_ci="${ACFS_DOCTOR_CI:-false}"

    check_optional_command "cloud.vault" "Vault" "vault"
    check_optional_command "cloud.postgres" "PostgreSQL" "psql"
    check_optional_command "cloud.wrangler" "Wrangler" "wrangler" "bun install -g --trust wrangler@latest"
    check_optional_command "cloud.supabase" "Supabase CLI" "supabase" "acfs update --cloud-only --force"
    check_optional_command "cloud.vercel" "Vercel CLI" "vercel" "bun install -g --trust vercel@latest"

    # Tailscale VPN (bt5)
    if command -v tailscale &>/dev/null; then
        local ts_status
        if command -v jq &>/dev/null; then
            ts_status=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "unknown"' 2>/dev/null || echo "unknown")
        else
            ts_status=$(tailscale status --json 2>/dev/null | sed -n 's/.*"BackendState"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
            ts_status="${ts_status:-unknown}"
        fi
        case "$ts_status" in
            "Running")
                check "network.tailscale" "Tailscale" "pass" "connected"
                ;;
            "NeedsLogin")
                if [[ "$doctor_ci" == "true" ]]; then
                    check "network.tailscale" "Tailscale (needs login)" "pass" "expected in CI"
                else
                    check "network.tailscale" "Tailscale" "warn" "needs login" "Run: sudo tailscale up"
                fi
                ;;
            *)
                if [[ "$doctor_ci" == "true" ]]; then
                    check "network.tailscale" "Tailscale ($ts_status)" "pass" "expected in CI"
                else
                    check "network.tailscale" "Tailscale" "warn" "$ts_status" "Run: sudo tailscale up"
                fi
                ;;
        esac
    else
        if [[ "$doctor_ci" == "true" ]]; then
            check "network.tailscale" "Tailscale (not installed)" "pass" "ok in CI"
        else
            check "network.tailscale" "Tailscale" "warn" "not installed (optional)" "Install: curl --proto '=https' --proto-redir '=https' -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only network.tailscale"
        fi
    fi

    # SSH server installed and running (fixes #161)
    # Fresh installs (WSL, VM, containers) may not have openssh-server
    if command -v sshd &>/dev/null || [[ -f /etc/ssh/sshd_config ]]; then
        if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
            if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
                check "network.ssh_server" "SSH server" "pass" "installed and running"
            else
                check "network.ssh_server" "SSH server" "warn" "installed but not running" \
                    "sudo systemctl enable --now ssh"
            fi
        else
            check "network.ssh_server" "SSH server" "pass" "installed (no systemd)"
        fi
    else
        if [[ "$doctor_ci" == "true" ]]; then
            check "network.ssh_server" "SSH server (not installed)" "pass" "ok in CI"
        else
            check "network.ssh_server" "SSH server" "warn" "not installed" \
                "sudo apt-get install -y openssh-server && sudo systemctl enable --now ssh"
        fi
    fi

    # SSH keepalive configuration (prevents VPN/NAT disconnects)
    # Check both main config and sshd_config.d includes for ClientAliveInterval
    local keepalive_interval=""
    local keepalive_source=""

    # Check main sshd_config (allow leading whitespace, handle commented lines)
    if [[ -f /etc/ssh/sshd_config ]]; then
        keepalive_interval=$(grep -E '^[[:space:]]*ClientAliveInterval[[:space:]]+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | { grep -v '^[[:space:]]*#' || true; } | tail -n1 | awk '{print $2}')
        [[ -n "$keepalive_interval" ]] && keepalive_source="sshd_config"
    fi

    # Check sshd_config.d includes (common on Ubuntu 22.04+)
    if [[ -z "$keepalive_interval" ]] && [[ -d /etc/ssh/sshd_config.d ]]; then
        for conf_file in /etc/ssh/sshd_config.d/*.conf; do
            [[ -f "$conf_file" ]] || continue
            local val
            val=$(grep -E '^[[:space:]]*ClientAliveInterval[[:space:]]+[0-9]+' "$conf_file" 2>/dev/null | { grep -v '^[[:space:]]*#' || true; } | tail -n1 | awk '{print $2}')
            if [[ -n "$val" ]]; then
                keepalive_interval="$val"
                keepalive_source="$(basename "$conf_file")"
                break
            fi
        done
    fi

    keepalive_interval="${keepalive_interval:-0}"
    if [[ "$keepalive_interval" -gt 0 ]] 2>/dev/null; then
        check "network.ssh_keepalive" "SSH keepalive" "pass" "ClientAliveInterval ${keepalive_interval}s (${keepalive_source})"
    else
        if [[ "$doctor_ci" == "true" ]]; then
            check "network.ssh_keepalive" "SSH keepalive (not configured)" "pass" "ok in CI"
        else
            check "network.ssh_keepalive" "SSH keepalive" "warn" "not configured (optional)" "$(fix_for_module "network.ssh_keepalive")"
        fi
    fi

    blank_line
}

# Check Dicklesworthstone stack
check_stack() {
    section "Dicklesworthstone stack"

    check_command "stack.ntm" "NTM" "ntm" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh | bash"
    check_command "stack.slb" "SLB" "slb" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/simultaneous_launch_button/main/scripts/install.sh | bash"

    # UBS - custom check
    if command -v ubs &>/dev/null; then
        local version
        version=$(get_version_line "ubs")
        check "stack.ubs" "UBS ($version)" "pass" "installed"
    else
        check "stack.ubs" "UBS" "fail" "not found" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/main/install.sh | bash"
    fi

    # Beads Viewer - custom check to detect gcloud 'bv' shadowing
    if command -v bv &>/dev/null; then
        local bv_path version
        bv_path=$(command -v bv)
        # Check if the resolved bv is gcloud's BigQuery Visualizer
        if [[ "$bv_path" == *"google-cloud-sdk"* ]]; then
            check "stack.bv" "Beads Viewer" "fail" "SHADOWED by gcloud bv at $bv_path" \
                "gcloud's 'bv' (BigQuery) is masking beads_viewer. Fix: Ensure ~/.local/bin is before gcloud in PATH, or re-run installer."
        else
            version=$(get_version_line "bv")
            # Also warn if gcloud's bv exists anywhere in PATH
            local gcloud_bv
            gcloud_bv=$(type -ap bv 2>/dev/null | grep "google-cloud-sdk" | head -1 || true)
            if [[ -n "$gcloud_bv" ]]; then
                check "stack.bv" "Beads Viewer ($version)" "warn" "gcloud bv exists at $gcloud_bv (but correctly shadowed)" \
                    "beads_viewer is correctly prioritized, but gcloud's bv exists. ACFS zshrc handles this."
            else
                check "stack.bv" "Beads Viewer ($version)" "pass" "installed"
            fi
        fi
    else
        check "stack.bv" "Beads Viewer" "fail" "not found" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh | bash"
    fi

    # CASS - custom check
    if command -v cass &>/dev/null; then
        local version
        version=$(get_version_line "cass")
        check "stack.cass" "CASS ($version)" "pass" "installed"
    else
        check "stack.cass" "CASS" "fail" "not found" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh | bash -s -- --easy-mode"
    fi

    check_command "stack.cm" "CASS Memory" "cm" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh | bash -s -- --easy-mode"
    check_command "stack.caam" "CAAM" "caam" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_account_manager/main/install.sh | bash"

    # Check MCP Agent Mail
    local am_install_fix am_repair_fix am_version am_label
    am_install_fix="Re-run: $(fix_for_module "stack.mcp_agent_mail")"
    am_repair_fix='Run: am doctor repair --yes && am doctor fix --yes'
    am_label="MCP Agent Mail"

    if command -v am &>/dev/null; then
        local am_global_doctor_json am_project_doctor_json am_project_path am_details

        am_version=$(get_version_line "am")
        am_label="MCP Agent Mail ($am_version)"

        if ! curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; then
            check "stack.mcp_agent_mail" "$am_label" "warn" "installed but service is not running" "$am_install_fix"
        elif {
            local am_runtime_dir="/run/user/$(id -u)"
            if [[ -d "$am_runtime_dir" ]]; then
                export XDG_RUNTIME_DIR="$am_runtime_dir"
                if [[ -S "$am_runtime_dir/bus" ]]; then
                    export DBUS_SESSION_BUS_ADDRESS="unix:path=$am_runtime_dir/bus"
                fi
            fi
            command -v systemctl &>/dev/null && systemctl --user show-environment >/dev/null 2>&1 && \
                ! systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1
        }; then
            check "stack.mcp_agent_mail" "$am_label" "warn" \
                "HTTP endpoint is healthy but agent-mail.service is inactive; rerun install/update to migrate off the fallback launcher" \
                "$am_install_fix"
        else
            am_global_doctor_json="$(agent_mail_doctor_check_json || true)"
            if [[ -z "$am_global_doctor_json" ]]; then
                check "stack.mcp_agent_mail" "$am_label" "warn" \
                    "service healthy but doctor check timed out or returned invalid output" \
                    "$am_repair_fix"
            elif ! agent_mail_doctor_is_healthy "$am_global_doctor_json"; then
                am_details="$(agent_mail_doctor_summary "$am_global_doctor_json")"
                check "stack.mcp_agent_mail" "$am_label" "warn" \
                    "${am_details:-global doctor check reported unhealthy state}" \
                    "$am_repair_fix"
            else
                am_project_path="$(git rev-parse --show-toplevel 2>/dev/null || true)"
                if [[ -n "$am_project_path" ]]; then
                    am_project_doctor_json="$(agent_mail_doctor_check_json "$am_project_path" || true)"
                    if [[ -z "$am_project_doctor_json" ]]; then
                        check "stack.mcp_agent_mail" "$am_label" "warn" \
                            "service healthy but current-project doctor check timed out or returned invalid output" \
                            "$am_repair_fix"
                    elif ! agent_mail_doctor_is_healthy "$am_project_doctor_json"; then
                        am_details="$(agent_mail_doctor_summary "$am_project_doctor_json")"
                        check "stack.mcp_agent_mail" "$am_label" "warn" \
                            "current project unhealthy: ${am_details:-project doctor check reported unhealthy state}" \
                            "$am_repair_fix"
                    else
                        check "stack.mcp_agent_mail" "$am_label" "pass" "service healthy; doctor check OK"
                    fi
                else
                    check "stack.mcp_agent_mail" "$am_label" "pass" "service healthy; doctor check OK"
                fi
            fi
        fi
    elif [[ -d "$HOME/mcp_agent_mail" ]]; then
        if [[ -x "$HOME/mcp_agent_mail/am" ]] && ! command -v am &>/dev/null; then
            check "symlink.am" "$am_label" "warn" \
                "binary exists at ~/mcp_agent_mail/am but symlink missing from ~/.local/bin/am" \
                "Fix: ln -sf ~/mcp_agent_mail/am ~/.local/bin/am (or run: acfs doctor --fix)"
        else
            check "stack.mcp_agent_mail" "$am_label" "warn" "install directory present but am CLI is missing" "$am_install_fix"
        fi
    else
        check "stack.mcp_agent_mail" "$am_label" "warn" "not installed" "$am_install_fix"
    fi

    # Check RU (Repo Updater)
    if command -v ru &>/dev/null; then
        local version
        version=$(get_version_line "ru")
        check "stack.ru" "RU ($version)" "pass" "installed"
    else
        check "stack.ru" "RU (Repo Updater)" "warn" "not installed" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/repo_updater/main/install.sh | bash"
    fi

    # Check beads_rust (br) - local-first issue tracker
    # Also check $HOME/.cargo/bin/ explicitly for curl|bash root installs
    # where the target user's cargo bin may not be in the current PATH.
    local _br_bin=""
    if command -v br &>/dev/null; then
        _br_bin="br"
    elif [[ -x "${HOME}/.cargo/bin/br" ]]; then
        _br_bin="${HOME}/.cargo/bin/br"
    elif [[ -n "${TARGET_HOME:-}" && -x "${TARGET_HOME}/.cargo/bin/br" ]]; then
        _br_bin="${TARGET_HOME}/.cargo/bin/br"
    fi
    if [[ -n "$_br_bin" ]]; then
        local version
        version=$(get_version_line "$_br_bin")
        check "stack.beads_rust" "beads_rust ($version)" "pass" "installed"
    else
        check "stack.beads_rust" "beads_rust (br)" "warn" "not installed" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh | bash"
    fi

    # Check meta_skill (ms)
    if command -v ms &>/dev/null; then
        local version
        version=$(get_version_line "ms")
        check "stack.meta_skill" "meta_skill ($version)" "pass" "installed"
    else
        # Detect architecture to give the right install advice
        local _ms_arch _ms_os _ms_fix
        _ms_arch="$(uname -m 2>/dev/null || echo unknown)"
        _ms_os="$(uname -s 2>/dev/null || echo unknown)"
        _ms_fix="Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/meta_skill/main/scripts/install.sh | bash"

        # Pre-built binaries exist for: x86_64-linux, aarch64-darwin, x86_64-darwin
        # ARM64 Linux (aarch64-Linux) does NOT have a pre-built binary yet:
        # https://github.com/Dicklesworthstone/meta_skill/issues/1
        case "${_ms_arch}-${_ms_os}" in
            aarch64-Linux|arm64-Linux)
                # ARM64 Linux binary is not yet published; the install script will 404
                check "stack.meta_skill" "meta_skill (ms)" "warn" \
                    "ARM64 Linux binary not yet available (see https://github.com/Dicklesworthstone/meta_skill/issues/1)" \
                    "Build from source: cargo install --git https://github.com/Dicklesworthstone/meta_skill --force"
                ;;
            x86_64-Linux|x86_64-Darwin|arm64-Darwin|aarch64-Darwin)
                # These platforms have pre-built binaries
                check "stack.meta_skill" "meta_skill (ms)" "warn" "not installed" \
                    "$_ms_fix"
                ;;
            *)
                _ms_fix="meta_skill has no pre-built binary for ${_ms_arch}-${_ms_os}. Build from source: cargo install --git https://github.com/Dicklesworthstone/meta_skill --force"
                check "stack.meta_skill" "meta_skill (ms)" "warn" "not installed" \
                    "$_ms_fix"
                ;;
        esac
    fi

    # Check rch (Remote Compilation Helper)
    # RCH can be installed in several locations: PATH, ~/.local/bin, ~/.cargo/bin, or ~/remote_compilation_helper
    local rch_bin=""
    local rch_version=""

    if command -v rch &>/dev/null; then
        rch_bin="$(command -v rch)"
    elif [[ -x "$HOME/.local/bin/rch" ]]; then
        rch_bin="$HOME/.local/bin/rch"
    elif [[ -x "$HOME/.cargo/bin/rch" ]]; then
        rch_bin="$HOME/.cargo/bin/rch"
    elif [[ -x "$HOME/remote_compilation_helper/rch" ]]; then
        rch_bin="$HOME/remote_compilation_helper/rch"
    fi

    if [[ -n "$rch_bin" ]] && [[ -x "$rch_bin" ]]; then
        rch_version=$("$rch_bin" --version 2>/dev/null | head -n1) || rch_version="installed"
        check "stack.rch" "rch ($rch_version)" "pass" "installed"
    else
        # Also check if RCH config exists (indicates partial/previous install)
        if [[ -f "$HOME/.config/rch/config.toml" ]] || [[ -d "$HOME/remote_compilation_helper" ]]; then
            check "stack.rch" "rch (Remote Compilation Helper)" "warn" "config exists but binary not in PATH" \
                "Add rch to PATH or re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh | bash"
        else
            check "stack.rch" "rch (Remote Compilation Helper)" "warn" "not installed" \
                "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh | bash"
        fi
    fi

    # Check wa (WezTerm Automata) - optional
    if command -v wa &>/dev/null; then
        local version
        version=$(get_version_line "wa")
        check "stack.wezterm_automata" "wezterm_automata ($version)" "pass" "installed"
    else
        check "stack.wezterm_automata" "wezterm_automata (wa)" "skip" "not installed (optional)"
    fi

    # Check brenner (Brenner Bot) - optional
    if command -v brenner &>/dev/null; then
        local version
        version=$(get_version_line "brenner")
        check "stack.brenner_bot" "brenner_bot ($version)" "pass" "installed"
    else
        check "stack.brenner_bot" "brenner_bot" "skip" "not installed (optional)"
    fi

    # Check DCG (Destructive Command Guard)
    check_dcg_hook_status

    # Check acfs-nightly-update timer (systemd user unit)
    # Gracefully handle missing systemd user session (curl|bash installs as
    # root don't have a D-Bus session, so systemctl --user always fails).
    local _nightly_status="unknown"
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        # Try to access the user session; if no D-Bus, fall back to checking
        # the unit file exists on disk instead.
        local _target_home="${TARGET_HOME:-$HOME}"
        local _nightly_unit_file="${_target_home}/.config/systemd/user/acfs-nightly-update.timer"
        if systemctl --user is-enabled acfs-nightly-update.timer &>/dev/null 2>&1; then
            _nightly_status="enabled"
        elif [[ -f "$_nightly_unit_file" ]]; then
            _nightly_status="unit_exists"
        else
            _nightly_status="missing"
        fi
    else
        _nightly_status="no_systemd"
    fi
    case "$_nightly_status" in
        enabled)
            check "acfs.nightly" "Nightly auto-update timer" "pass" "enabled"
            ;;
        unit_exists)
            check "acfs.nightly" "Nightly auto-update timer" "warn" \
                "unit file exists but timer not enabled (no D-Bus user session?)" \
                "loginctl enable-linger \$(whoami) && systemctl --user enable --now acfs-nightly-update.timer"
            ;;
        no_systemd)
            check "acfs.nightly" "Nightly auto-update timer" "skip" \
                "no systemd or no user session (expected for curl|bash root installs)"
            ;;
        *)
            check "acfs.nightly" "Nightly auto-update timer" "warn" \
                "not installed (optional)" \
                "$(fix_for_module "acfs.nightly")"
            ;;
    esac

    blank_line
}

# ============================================================
# Utility Tools Health Checks (bd-2gog)
# ============================================================
# Optional utility tools from the Dicklesworthstone ecosystem.
# These are non-fatal checks (skip status) since utilities are optional.
# ============================================================

check_utilities() {
    section "Utility tools"

    # tru (Token-Optimized Notation)
    if command -v tru &>/dev/null; then
        local version
        version=$(get_version_line "tru")
        check "util.tru" "tru ($version)" "pass" "installed"
    else
        check "util.tru" "tru (token notation)" "skip" "not installed (optional)"
    fi

    # rust_proxy (Transparent Proxy Routing)
    if command -v rust_proxy &>/dev/null; then
        local version
        version=$(get_version_line "rust_proxy")
        check "util.rust_proxy" "rust_proxy ($version)" "pass" "installed"
    else
        check "util.rust_proxy" "rust_proxy (proxy routing)" "skip" "not installed (optional)"
    fi

    # rano (Network Observer for AI CLIs)
    if command -v rano &>/dev/null; then
        local version
        version=$(get_version_line "rano")
        check "util.rano" "rano ($version)" "pass" "installed"
    else
        check "util.rano" "rano (network observer)" "skip" "not installed (optional)"
    fi

    # xf (X/Twitter Archive Search)
    if command -v xf &>/dev/null; then
        local version
        version=$(get_version_line "xf")
        check "util.xf" "xf ($version)" "pass" "installed"
    else
        check "util.xf" "xf (X archive search)" "skip" "not installed (optional)"
    fi

    # mdwb (Markdown Web Browser)
    if command -v mdwb &>/dev/null; then
        local version
        version=$(get_version_line "mdwb")
        check "util.mdwb" "mdwb ($version)" "pass" "installed"
    else
        check "util.mdwb" "mdwb (markdown browser)" "skip" "not installed (optional)"
    fi

    # pt (Process Triage)
    if command -v pt &>/dev/null; then
        local version
        version=$(get_version_line "pt")
        check "util.pt" "pt ($version)" "pass" "installed"
    else
        check "util.pt" "pt (process triage)" "skip" "not installed (optional)"
    fi

    # aadc (ASCII Diagram Corrector)
    if command -v aadc &>/dev/null; then
        local version
        version=$(get_version_line "aadc")
        check "util.aadc" "aadc ($version)" "pass" "installed"
    else
        check "util.aadc" "aadc (ASCII diagram corrector)" "skip" "not installed (optional)"
    fi

    # s2p (Source to Prompt TUI)
    if command -v s2p &>/dev/null; then
        local version
        version=$(get_version_line "s2p")
        check "util.s2p" "s2p ($version)" "pass" "installed"
    else
        check "util.s2p" "s2p (source to prompt)" "skip" "not installed (optional)"
    fi

    # caut (Coding Agent Usage Tracker)
    if command -v caut &>/dev/null; then
        local version
        version=$(get_version_line "caut")
        check "util.caut" "caut ($version)" "pass" "installed"
    else
        check "util.caut" "caut (usage tracker)" "skip" "not installed (optional)"
    fi

    blank_line
}

# ============================================================
# Manifest Supplemental Checks (bd-31ps.5.1)
# ============================================================
# Runs manifest-derived checks for tools NOT already covered by the bespoke
# check functions above.  This fills gaps (lazygit, nvm, apr, jfp, pt, srps,
# all utils.*, acfs.*, base.system.*) without duplicating bespoke output.
# ============================================================

# Returns 0 (true) if the given manifest ID is already verified by a bespoke
# check function; 1 (false) if it needs manifest supplemental coverage.
_is_bespoke_covered() {
    local id="$1"
    local module_id
    module_id=$(_manifest_module_id "$id")

    case "$id" in
        # check_cloud covers the CLI presence check, but we still want the
        # manifest-derived PostgreSQL service health check (db.postgres18.2).
        db.postgres18.1) return 0 ;;
    esac

    case "$module_id" in
        # check_identity
        users.ubuntu.*) return 0 ;;
        # check_workspace
        base.filesystem.[12]) return 0 ;;
        # check_shell
        shell.*) return 0 ;;
        # check_core_tools  (cli.modern.* maps to rg, tmux, fzf, gh, etc.)
        cli.modern.*) return 0 ;;
        # check_core_tools  (languages)
        lang.bun|lang.uv|lang.rust.*|lang.go) return 0 ;;
        # check_shell / check_core_tools  (individual tools)
        tools.atuin|tools.zoxide|tools.ast_grep|tools.vault) return 0 ;;
        # check_agents
        agents.*) return 0 ;;
        # check_cloud / check_ssh
        cloud.wrangler|cloud.supabase|cloud.vercel) return 0 ;;
        network.tailscale|network.ssh_keepalive) return 0 ;;
        # check_stack  (individual stack entries)
        stack.ntm|stack.slb|stack.mcp_agent_mail) return 0 ;;
        stack.ultimate_bug_scanner.*|stack.beads_viewer) return 0 ;;
        stack.beads_rust.*|stack.cass|stack.cm.*|stack.caam) return 0 ;;
        stack.dcg.*|stack.ru|stack.meta_skill.*) return 0 ;;
        stack.brenner_bot|stack.rch|stack.wezterm_automata) return 0 ;;
        # check_stack  (acfs nightly timer — bespoke handles D-Bus gracefully)
        acfs.nightly) return 0 ;;
        # check_utilities (bd-2gog)
        util.*|utils.*) return 0 ;;
    esac
    return 1
}

# Extract the manifest module ID from a check ID by stripping trailing ".N".
# e.g., "stack.automated_plan_reviser.1" → "stack.automated_plan_reviser"
# e.g., "tools.lazygit" → "tools.lazygit" (no change)
_manifest_module_id() {
    local id="$1"
    if [[ "$id" =~ ^(.+)\.[0-9]+$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "$id"
    fi
}

_doctor_run_manifest_check() {
    local run_as="$1"
    local cmd="$2"
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-}"
    local target_path=""

    if [[ -z "$target_home" ]]; then
        if [[ "$target_user" == "root" ]]; then
            target_home="/root"
        else
            target_home="/home/$target_user"
        fi
    fi

    target_path="$target_home/.local/bin:$target_home/.acfs/bin:$target_home/.bun/bin:$target_home/.cargo/bin:$target_home/.atuin/bin:$target_home/go/bin:${PATH:-/usr/local/bin:/usr/bin:/bin}"

    case "$run_as" in
        target_user)
            if [[ "$(id -un 2>/dev/null || true)" == "$target_user" ]]; then
                HOME="$target_home" PATH="$target_path" bash -o pipefail -c "$cmd"
                return $?
            fi
            if [[ $EUID -eq 0 ]] && command -v runuser >/dev/null 2>&1; then
                runuser -u "$target_user" -- env HOME="$target_home" PATH="$target_path" bash -o pipefail -c "$cmd"
                return $?
            fi
            if command -v sudo >/dev/null 2>&1; then
                sudo -n -u "$target_user" env HOME="$target_home" PATH="$target_path" bash -o pipefail -c "$cmd"
                return $?
            fi
            # Absolute fallback
            if [[ $EUID -eq 0 ]]; then
                su "$target_user" -c "env HOME=$(printf '%q' "$target_home") PATH=$(printf '%q' "$target_path") bash -o pipefail -c $(printf '%q' "$cmd")"
                return $?
            fi
            return 1
            ;;
        root)
            if [[ $EUID -eq 0 ]]; then
                bash -o pipefail -c "$cmd"
                return $?
            fi
            if command -v sudo >/dev/null 2>&1; then
                sudo -n env PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}" bash -o pipefail -c "$cmd"
                return $?
            fi
            return 1
            ;;
        current|*)
            bash -o pipefail -c "$cmd"
            ;;
    esac
}

# Run manifest checks that are NOT already covered by bespoke functions.
# Integrates with the standard check() output (JSON/gum/plain) so the results
# are indistinguishable from hand-written checks.  Failed checks include a
# copy-pasteable fix suggestion using `acfs install --only <module>`.
check_manifest_supplemental() {
    [[ "$MANIFEST_CHECKS_LOADED" == "true" ]] || return 0
    [[ ${#MANIFEST_CHECKS[@]} -gt 0 ]] || return 0

    local printed_section=false

    for entry in "${MANIFEST_CHECKS[@]}"; do
        IFS=$'\t' read -r id desc cmd req_flag run_as <<< "$entry"

        # Skip checks already covered by bespoke functions
        _is_bespoke_covered "$id" && continue

        # Print section header on first supplemental check
        if [[ "$printed_section" == "false" ]]; then
            section "Additional Tools (manifest)"
            printed_section=true
        fi

        # Decode printf escapes (\n, \t, \\) embedded by the generator
        cmd="$(printf '%b' "$cmd")"
        run_as="${run_as:-current}"

        # Build a human-readable label from the check command.
        # For most entries the first word is the binary name (curl, lazygit, apr).
        # For shell builtins / operators we fall back to the ID's last segment.
        local tool_name
        tool_name="${cmd%% *}"
        case "$tool_name" in
            test|"["|grep|export|command|bash|sh|cd|systemctl|"[["*)
                tool_name="${id%.[0-9]*}"    # strip trailing .N
                tool_name="${tool_name##*.}" # keep last segment
                ;;
            */*)
                # Path like ~/.bun/bin/bun → basename
                tool_name="${tool_name##*/}"
                ;;
        esac

        # Build per-module fix suggestion for failed/warn checks (bd-31ps.5.2)
        local module_id
        module_id=$(_manifest_module_id "$id")
        local fix
        fix="$(fix_for_module "$module_id")"

        # Execute the check command in the same context the manifest expects.
        if _doctor_run_manifest_check "$run_as" "$cmd" &>/dev/null; then
            check "$id" "$tool_name" "pass" "$desc"
        elif [[ "$req_flag" == "optional" ]]; then
            # Optional tools use "warn" status (not critical failures)
            # Still provide fix suggestion so users know how to install if desired
            check "$id" "$tool_name" "warn" "$desc (optional)" "$fix"
        else
            check "$id" "$tool_name" "fail" "$desc" "$fix"
        fi
    done

    [[ "$printed_section" == "true" ]] && blank_line
}

# ============================================================
# Skipped Tools Display (bead qup)
# ============================================================
# Shows tools the user intentionally skipped during installation.
# These are not failures - they are deliberate choices.

# Load skipped tools from state.json
# Populates SKIPPED_TOOLS_DATA array with "tool:reason" entries
load_skipped_tools() {
    SKIPPED_TOOLS_DATA=()
    local state_file=""
    state_file="$(_acfs_doctor_find_project_path "state.json" 2>/dev/null || true)"

    [[ -f "$state_file" ]] || return 0

    # Use jq if available for reliable parsing
    if command -v jq &>/dev/null; then
        local skipped_json
        skipped_json=$(jq -r '.skipped_tools // empty' "$state_file" 2>/dev/null) || return 0

        # Handle both array format ["tool1","tool2"] and object format {"tool1":"reason"}
        if [[ "$skipped_json" == "["* ]]; then
            # Array format - no reasons stored
            while IFS= read -r tool; do
                [[ -n "$tool" && "$tool" != "null" ]] && SKIPPED_TOOLS_DATA+=("$tool:user choice")
            done < <(jq -r '.skipped_tools[]? // empty' "$state_file" 2>/dev/null)
        elif [[ "$skipped_json" == "{"* ]]; then
            # Object format with reasons
            while IFS= read -r line; do
                [[ -n "$line" ]] && SKIPPED_TOOLS_DATA+=("$line")
            done < <(jq -r '.skipped_tools | to_entries[]? | "\(.key):\(.value)"' "$state_file" 2>/dev/null)
        fi
    else
        # Fallback: basic sed for array format (POSIX-compatible, works on macOS/BSD)
        local skipped
        skipped=$(sed -n 's/.*"skipped_tools"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$state_file" 2>/dev/null | tr -d '", ')
        for tool in $skipped; do
            [[ -n "$tool" ]] && SKIPPED_TOOLS_DATA+=("$tool:user choice")
        done
    fi
}

# Display a skipped tool with [○] indicator
# Usage: check_skipped <id> <label> [reason]
check_skipped() {
    local id="$1"
    local label="$2"
    local reason="${3:-user choice}"

    ((SKIP_COUNT += 1))

    if [[ "$JSON_MODE" == "true" ]]; then
        JSON_CHECKS+=("{\"id\":\"$(json_escape "$id")\",\"label\":\"$(json_escape "$label")\",\"status\":\"skipped\",\"details\":\"$(json_escape "$reason")\",\"fix\":null}")
        return 0
    fi

    if [[ "$HAS_GUM" == "true" ]]; then
        echo "  $(gum style --foreground "$ACFS_MUTED" --bold "○ SKIP") $(gum style --foreground "$ACFS_MUTED" "$label")"
        echo "        $(gum style --foreground "$ACFS_MUTED" --italic "Reason: $reason")"
    else
        echo -e "  ${CYAN}○ SKIP${NC} $label"
        echo -e "        Reason: $reason"
    fi
}

# Show intentionally skipped tools section
show_skipped_tools() {
    load_skipped_tools

    # Skip section if nothing was skipped
    [[ ${#SKIPPED_TOOLS_DATA[@]} -eq 0 ]] && return 0

    section "Intentionally Skipped"

    if [[ "$JSON_MODE" != "true" ]]; then
        if [[ "$HAS_GUM" == "true" ]]; then
            gum style --foreground "$ACFS_MUTED" "  These tools were skipped during installation (not errors)"
        else
            echo -e "  ${CYAN}These tools were skipped during installation (not errors)${NC}"
        fi
        echo ""
    fi

    for entry in "${SKIPPED_TOOLS_DATA[@]}"; do
        local tool="${entry%%:*}"
        local reason="${entry#*:}"
        check_skipped "skipped.$tool" "$tool" "$reason"
    done

    blank_line
}

# ============================================================
# Deep Checks - Functional Tests (bead 01s)
# ============================================================
# These tests go beyond "is the binary installed" to verify
# actual functionality: authentication, connectivity, etc.
#
# Only runs when --deep flag is provided.
# ============================================================

# Deep check counters (separate from main counters for summary)
DEEP_PASS_COUNT=0
DEEP_WARN_COUNT=0
DEEP_FAIL_COUNT=0

# Run all deep/functional checks with formatted output
# Enhanced per bead aqs: Adds counters and summary
# Enhanced per bead lz1: Adds timing
# Usage: run_deep_checks
deep_check_optional_probe() {
    local id="$1"
    local label="$2"
    local binary="$3"
    local fix="$4"
    shift 4

    if ! command -v "$binary" &>/dev/null; then
        check "$id" "$label" "warn" "not installed" "$fix"
        return 0
    fi

    local cache_key="${id//./_}"
    local cached_result=""
    if cached_result=$(get_cached_result "$cache_key"); then
        check "$id" "$label" "pass" "$cached_result (cached)"
        return 0
    fi

    local cmd=""
    local output=""
    local status=0
    local summary=""
    local detail=""
    local last_timeout=false

    for cmd in "$@"; do
        output=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "$label via $cmd" env PATH="$PATH" bash -o pipefail -c "$cmd")
        status=$?

        if ((status == 0)); then
            detail="$(printf '%s\n' "$output" | head -n 1)"
            if [[ -n "$detail" ]]; then
                summary="$cmd: ${detail:0:120}"
            else
                summary="$cmd"
            fi
            cache_result "$cache_key" "$summary"
            check "$id" "$label" "pass" "$summary"
            return 0
        fi

        if ((status == 124)); then
            last_timeout=true
            detail="timed out running: $cmd"
            continue
        fi

        if [[ -z "$detail" ]]; then
            detail="$(printf '%s\n' "$output" | head -n 1)"
            [[ -n "$detail" ]] || detail="command failed: $cmd"
        fi
    done

    if [[ "$last_timeout" == "true" ]]; then
        check_with_timeout_status "$id" "$label" "timeout" "$detail" "$fix"
    else
        check "$id" "$label" "warn" "$detail" "$fix"
    fi
}

deep_check_stack_tools() {
    deep_check_optional_probe \
        "deep.stack.rch" \
        "RCH operational probe" \
        "rch" \
        "Run: rch doctor --fix" \
        "rch doctor" \
        "rch status"

    deep_check_optional_probe \
        "deep.stack.pt" \
        "Process Triage operational probe" \
        "pt" \
        "Run: pt check" \
        "pt check" \
        "pt doctor" \
        "pt --help"

    deep_check_optional_probe \
        "deep.stack.fsfs" \
        "FrankenSearch operational probe" \
        "fsfs" \
        "timed out running: fsfs status" \
        "fsfs status" \
        "fsfs version" \
        "fsfs --help"

    deep_check_optional_probe \
        "deep.stack.sbh" \
        "Storage Ballast Helper operational probe" \
        "sbh" \
        "Run: sbh check" \
        "sbh check" \
        "sbh status" \
        "sbh --help"

    deep_check_optional_probe \
        "deep.stack.casr" \
        "CASR provider probe" \
        "casr" \
        "Run: casr providers" \
        "casr providers" \
        "casr list" \
        "casr --help"

    deep_check_optional_probe \
        "deep.stack.dsr" \
        "DSR operational probe" \
        "dsr" \
        "Run: dsr check --all" \
        "dsr doctor" \
        "dsr check --all" \
        "dsr --help"

    deep_check_optional_probe \
        "deep.stack.ru" \
        "Repo Updater operational probe" \
        "ru" \
        "Run: ru doctor" \
        "ru doctor" \
        "ru list" \
        "ru --help"

    deep_check_optional_probe \
        "deep.stack.asb" \
        "Agent Settings Backup operational probe" \
        "asb" \
        "test -d \"$HOME/.asb\" && asb list" \
        "asb list" \
        "asb help"

    deep_check_optional_probe \
        "deep.stack.pcr" \
        "Post-Compact Reminder operational probe" \
        "claude-post-compact-reminder" \
        "Reinstall PCR or verify Claude settings registration" \
        "printf '{\"session_id\":\"doctor\",\"source\":\"compact\"}\n' | claude-post-compact-reminder"
}

run_deep_checks() {
    section "Deep Checks (Functional Tests)"

    # Track total deep check time (bead lz1)
    local start_time
    start_time=$(date +%s)

    if [[ "$JSON_MODE" != "true" ]]; then
        # Log cache status (bead lz1)
        local cache_status=""
        if [[ "$NO_CACHE" == "true" ]]; then
            cache_status=" (cache disabled)"
        fi
        if [[ "$HAS_GUM" == "true" ]]; then
            gum style --foreground "$ACFS_MUTED" "  Running functional tests...$cache_status"
        else
            echo -e "  ${CYAN}Running functional tests...$cache_status${NC}"
        fi
        echo ""
    fi

    # Capture counts before deep checks to calculate deep-only stats
    local pre_pass=$PASS_COUNT
    local pre_warn=$WARN_COUNT
    local pre_fail=$FAIL_COUNT

    # Agent authentication checks
    deep_check_agent_auth

    # Database connectivity checks
    deep_check_database

    # Cloud CLI checks
    deep_check_cloud

    # tmux responsiveness checks (GitHub issue #20: NTM timeouts / slow tmux)
    deep_check_tmux_performance

    # Network health checks (bead bd-31ps.7.2)
    deep_check_network

    # Notification (ntfy.sh) connectivity check (GitHub issue #131)
    deep_check_notifications

    # Stack tool functional probes for newly integrated tools
    deep_check_stack_tools

    # Calculate deep check specific counts
    DEEP_PASS_COUNT=$((PASS_COUNT - pre_pass))
    DEEP_WARN_COUNT=$((WARN_COUNT - pre_warn))
    DEEP_FAIL_COUNT=$((FAIL_COUNT - pre_fail))
    local deep_total=$((DEEP_PASS_COUNT + DEEP_WARN_COUNT + DEEP_FAIL_COUNT))

    # Calculate elapsed time (bead lz1)
    local end_time elapsed_time
    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))
    DEEP_CHECK_ELAPSED=$elapsed_time  # Export for JSON output

    # Print deep checks summary
    if [[ "$JSON_MODE" != "true" ]]; then
        echo ""
        if [[ "$HAS_GUM" == "true" ]]; then
            local summary_text=""
            if [[ $DEEP_FAIL_COUNT -eq 0 ]]; then
                summary_text="$(gum style --foreground "$ACFS_SUCCESS" --bold "$DEEP_PASS_COUNT/$deep_total") functional tests passed"
                [[ $DEEP_WARN_COUNT -gt 0 ]] && summary_text="$summary_text $(gum style --foreground "$ACFS_WARNING" "($DEEP_WARN_COUNT warnings)")"
            else
                summary_text="$(gum style --foreground "$ACFS_ERROR" --bold "$DEEP_PASS_COUNT/$deep_total") functional tests passed"
                summary_text="$summary_text $(gum style --foreground "$ACFS_ERROR" "($DEEP_FAIL_COUNT failed)")"
            fi
            echo "  $summary_text $(gum style --foreground "$ACFS_MUTED" "in ${elapsed_time}s")"
        else
            if [[ $DEEP_FAIL_COUNT -eq 0 ]]; then
                echo -e "  ${GREEN}$DEEP_PASS_COUNT/$deep_total${NC} functional tests passed in ${elapsed_time}s"
            else
                echo -e "  ${RED}$DEEP_PASS_COUNT/$deep_total${NC} functional tests passed (${RED}$DEEP_FAIL_COUNT failed${NC}) in ${elapsed_time}s"
            fi
        fi
    fi

    blank_line
}

# Deep check: Agent authentication
# Enhanced per bead 325: Check config files, API keys, and low-cost API checks
deep_check_agent_auth() {
    check_claude_auth
    check_codex_auth
    check_gemini_auth
}

# check_claude_auth - Thorough Claude Code authentication check
# Returns via check(): pass (auth OK), warn (partial/skipped), fail (auth broken)
# Related: bead 325
# Fixed: Check correct credentials file (.credentials.json, not config.json)
# Fixed: Removed non-existent --print-system-info flag
check_claude_auth() {
    # Skip if not installed
    if ! command -v claude &>/dev/null; then
        check "deep.agent.claude_auth" "Claude Code" "warn" "not installed" "acfs update --force --agents-only"
        return
    fi

    # Check if binary works
    if ! claude --version &>/dev/null; then
        check "deep.agent.claude_auth" "Claude Code auth" "fail" "binary error" "Reinstall: acfs update --force --agents-only"
        return
    fi

    # Check for credentials file (indicates previous auth)
    # Claude Code stores OAuth credentials in ~/.claude/.credentials.json (note leading dot)
    local creds_file="$HOME/.claude/.credentials.json"
    if [[ ! -f "$creds_file" ]]; then
        check "deep.agent.claude_auth" "Claude Code auth" "warn" "not authenticated" "Run: claude to authenticate"
        return
    fi

    # Verify OAuth token exists in credentials file
    local has_token=false
    if command -v jq &>/dev/null; then
        # Use jq for reliable JSON parsing
        if jq -e '((.claudeAiOauth.accessToken // "") | strings | length) > 0' "$creds_file" >/dev/null 2>&1; then
            has_token=true
        fi
    else
        # Fallback: require a non-empty string token, not just key presence.
        if grep -Eq '"accessToken"[[:space:]]*:[[:space:]]*"[^"]+"' "$creds_file" 2>/dev/null; then
            has_token=true
        fi
    fi

    if [[ "$has_token" == "true" ]]; then
        check "deep.agent.claude_auth" "Claude Code auth" "pass" "OAuth authenticated"
    else
        check "deep.agent.claude_auth" "Claude Code auth" "warn" "credentials file exists but no valid token" "Run: claude to re-authenticate"
    fi
}

# check_codex_auth - Thorough Codex CLI authentication check
# Codex CLI uses OAuth (ChatGPT accounts), NOT OPENAI_API_KEY environment variable.
# Token location: ~/.codex/auth.json (or $CODEEX_HOME/auth.json)
# Returns via check(): pass (auth OK), warn (partial/skipped), fail (auth broken)
# Related: bead 325, ua5 (Codex auth documentation fix)
check_codex_auth() {
    # Skip if not installed
    if ! command -v codex &>/dev/null; then
        check "deep.agent.codex_auth" "Codex CLI" "warn" "not installed" "bun install -g --trust @openai/codex@latest"
        return
    fi

    # Check if binary works
    if ! codex --version &>/dev/null; then
        check "deep.agent.codex_auth" "Codex CLI auth" "fail" "binary error" "Reinstall: bun install -g --trust @openai/codex@latest"
        return
    fi

    # Determine auth.json location (respects CODEEX_HOME if set)
    local auth_file="${CODEEX_HOME:-$HOME/.codex}/auth.json"

    # Check if auth.json exists
    if [[ ! -f "$auth_file" ]]; then
        check "deep.agent.codex_auth" "Codex CLI auth" "warn" "not authenticated" "Run: codex login --device-auth"
        return
    fi

    # Check for OAuth tokens (primary auth method)
    # auth.json structure: { "tokens": { "access_token": "..." }, "OPENAI_API_KEY": null|"..." }
    local has_oauth=false
    local has_api_key=false

    # Check for OAuth tokens.access_token (preferred)
    if command -v jq &>/dev/null; then
        # Use jq if available for reliable JSON parsing
        if jq -e '((.tokens.access_token // .access_token // .accessToken // "") | strings | length) > 0' "$auth_file" >/dev/null 2>&1; then
            has_oauth=true
        fi
        # Check for legacy API key in auth.json
        if jq -e '((.OPENAI_API_KEY // "") | strings | length) > 0' "$auth_file" >/dev/null 2>&1; then
            has_api_key=true
        fi
    else
        # Fallback: require non-empty strings, not just key presence.
        if grep -Eq '"(access(_token|Token))"[[:space:]]*:[[:space:]]*"[^"]+"' "$auth_file" 2>/dev/null; then
            has_oauth=true
        fi
        if grep -q '"OPENAI_API_KEY".*:.*"[^"]\+"' "$auth_file" 2>/dev/null; then
            has_api_key=true
        fi
    fi

    if [[ "$has_oauth" == "true" ]]; then
        check "deep.agent.codex_auth" "Codex CLI auth" "pass" "OAuth authenticated (ChatGPT account)"
    elif [[ "$has_api_key" == "true" ]]; then
        check "deep.agent.codex_auth" "Codex CLI auth" "pass" "API key authenticated (pay-as-you-go)"
    else
        check "deep.agent.codex_auth" "Codex CLI auth" "warn" "not authenticated" "Run: codex login --device-auth"
    fi
}

# check_gemini_auth - Thorough Gemini CLI authentication check
# Returns via check(): pass (auth OK), warn (partial/skipped), fail (auth broken)
# Related: bead 325
# Fixed: Check actual Gemini CLI credential files (oauth_creds.json, google_accounts.json)
check_gemini_auth() {
    # Skip if not installed
    if ! command -v gemini &>/dev/null; then
        check "deep.agent.gemini_auth" "Gemini CLI" "warn" "not installed" "bun install -g --trust @google/gemini-cli@latest"
        return
    fi

    # Check if binary works
    if ! gemini --version &>/dev/null; then
        check "deep.agent.gemini_auth" "Gemini CLI auth" "fail" "binary error" "Reinstall: bun install -g --trust @google/gemini-cli@latest"
        return
    fi

    local gemini_home="${GEMINI_CLI_HOME:-$HOME}"
    local shell_config_files=()
    mapfile -t shell_config_files < <(default_auth_config_files)
    local gemini_config_files=(
        "$gemini_home/.gemini/.env"
        "${shell_config_files[@]}"
    )
    if get_configured_secret "GEMINI_API_KEY" "${gemini_config_files[@]}" >/dev/null; then
        check "deep.agent.gemini_auth" "Gemini CLI auth" "pass" "via GEMINI_API_KEY"
        return
    fi
    if configured_truthy_value "GOOGLE_GENAI_USE_VERTEXAI" "${gemini_config_files[@]}"; then
        if get_configured_secret "GOOGLE_API_KEY" "${gemini_config_files[@]}" >/dev/null; then
            check "deep.agent.gemini_auth" "Gemini CLI auth" "pass" "via GOOGLE_API_KEY (Vertex AI)"
            return
        fi

        local vertex_project=""
        local vertex_location=""
        local service_account_path=""
        vertex_project="$(get_configured_value "GOOGLE_CLOUD_PROJECT" "${gemini_config_files[@]}" || get_configured_value "GOOGLE_CLOUD_PROJECT_ID" "${gemini_config_files[@]}" || true)"
        vertex_location="$(get_configured_value "GOOGLE_CLOUD_LOCATION" "${gemini_config_files[@]}" || true)"
        service_account_path="$(get_configured_value "GOOGLE_APPLICATION_CREDENTIALS" "${gemini_config_files[@]}" || true)"

        if [[ -n "$vertex_project" && -n "$vertex_location" ]]; then
            if [[ -n "$service_account_path" && -f "$service_account_path" ]]; then
                check "deep.agent.gemini_auth" "Gemini CLI auth" "pass" "via GOOGLE_APPLICATION_CREDENTIALS (Vertex AI)"
                return
            fi
            if command -v gcloud &>/dev/null && timeout 5 gcloud auth application-default print-access-token >/dev/null 2>&1; then
                check "deep.agent.gemini_auth" "Gemini CLI auth" "pass" "via gcloud ADC (Vertex AI)"
                return
            fi
        fi
    fi

    # Gemini CLI also stores browser-login state under ~/.gemini/ (or $GEMINI_CLI_HOME/.gemini).
    local google_accounts_file="$gemini_home/.gemini/google_accounts.json"
    local oauth_creds_file="$gemini_home/.gemini/oauth_creds.json"
    local found_auth=false

    if command -v jq &>/dev/null; then
        local gemini_active=""
        local gemini_access_token=""
        local gemini_refresh_token=""

        if [[ -f "$google_accounts_file" ]]; then
            gemini_active="$(jq -r '.active // empty' "$google_accounts_file" 2>/dev/null || true)"
        fi
        if [[ -f "$oauth_creds_file" ]]; then
            gemini_access_token="$(jq -r '.access_token // empty' "$oauth_creds_file" 2>/dev/null || true)"
            gemini_refresh_token="$(jq -r '.refresh_token // empty' "$oauth_creds_file" 2>/dev/null || true)"
        fi

        if [[ -n "$gemini_active" || -n "$gemini_access_token" || -n "$gemini_refresh_token" ]]; then
            found_auth=true
        fi
    else
        if [[ -f "$google_accounts_file" ]] && grep -Eq '"active"[[:space:]]*:[[:space:]]*"[^"]+"' "$google_accounts_file"; then
            found_auth=true
        fi
        if [[ "$found_auth" == "false" ]] && [[ -f "$oauth_creds_file" ]] && \
           grep -Eq '"(access_token|refresh_token)"[[:space:]]*:[[:space:]]*"[^"]+"' "$oauth_creds_file"; then
            found_auth=true
        fi
    fi

    if [[ "$found_auth" == "true" ]]; then
        check "deep.agent.gemini_auth" "Gemini CLI auth" "pass" "authenticated"
    else
        check "deep.agent.gemini_auth" "Gemini CLI auth" "warn" "not authenticated" "Set GEMINI_API_KEY (or Vertex AI env vars), then run gemini"
    fi
}

# Deep check: Database connectivity
# Enhanced per bead azw: PostgreSQL connection and role checks
deep_check_database() {
    check_postgres_connection
    check_postgres_role
}

# check_postgres_connection - Test PostgreSQL connectivity
# Related: bead azw
check_postgres_connection() {
    # Skip if not installed
    if ! command -v psql &>/dev/null; then
        check "deep.db.postgres_connect" "PostgreSQL connection" "warn" "psql not installed" "sudo apt install postgresql-client"
        return
    fi

    # Try to connect to local postgres (5 second timeout, no password prompt)
    # Use -w to avoid password prompts (would hang)
    if timeout 5 psql -w -h localhost -U postgres -c 'SELECT 1' &>/dev/null; then
        check "deep.db.postgres_connect" "PostgreSQL connection" "pass" "localhost:5432"
    elif timeout 5 psql -w -h /var/run/postgresql -U postgres -c 'SELECT 1' &>/dev/null; then
        check "deep.db.postgres_connect" "PostgreSQL connection" "pass" "unix socket"
    else
        # Try connecting as current user
        if timeout 5 psql -w -c 'SELECT 1' &>/dev/null; then
            check "deep.db.postgres_connect" "PostgreSQL connection" "pass" "current user"
        else
            check "deep.db.postgres_connect" "PostgreSQL connection" "warn" "connection failed" "sudo systemctl status postgresql"
        fi
    fi
}

# check_postgres_role - Verify target user role exists in PostgreSQL
# Related: bead azw
# Fixed: Try current user first before postgres user (pg_roles is readable by any authenticated user)
# Fixed: Provide actionable fix message (createuser, not systemctl status)
# Fixed: Use bash variable substitution with validated input (:'var' syntax is unreliable across psql versions)
check_postgres_role() {
    # Skip if not installed
    if ! command -v psql &>/dev/null; then
        return  # Already reported in connection check
    fi

    # Validate target user - PostgreSQL identifiers must match this pattern
    # SECURITY: Prevents SQL injection by validating input before use
    local target_user="${TARGET_USER:-}"
    if [[ -z "$target_user" ]]; then
        check "deep.db.postgres_role" "PostgreSQL role check" "warn" "TARGET_USER not set"
        return
    fi
    if [[ ! "$target_user" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        check "deep.db.postgres_role" "PostgreSQL role check" "fail" "invalid username format"
        return
    fi

    # Try to check if target user role exists
    # pg_roles view is readable by any authenticated user - no superuser required
    # SECURITY: target_user is validated above with regex, safe for bash substitution
    local role_check
    local connect_success=false
    local sql_query="SELECT 1 FROM pg_roles WHERE rolname='$target_user'"

    # Try connecting as current user first (mirrors check_postgres_connection behavior)
    # This works when pg_hba.conf allows peer auth for local users
    if role_check=$(timeout 5 psql -w -tAc "$sql_query" 2>/dev/null) && [[ "$role_check" == "1" ]]; then
        connect_success=true
    # Try localhost with postgres user as fallback
    elif role_check=$(timeout 5 psql -w -h localhost -U postgres -tAc "$sql_query" 2>/dev/null) && [[ "$role_check" == "1" ]]; then
        connect_success=true
    # Try unix socket with postgres user as last resort
    elif role_check=$(timeout 5 psql -w -h /var/run/postgresql -U postgres -tAc "$sql_query" 2>/dev/null) && [[ "$role_check" == "1" ]]; then
        connect_success=true
    fi

    if [[ "$connect_success" == "true" ]]; then
        check "deep.db.postgres_role" "PostgreSQL $target_user role" "pass" "role exists"
    else
        # Connection failed or role missing - provide actionable fix
        check "deep.db.postgres_role" "PostgreSQL $target_user role" "warn" "role missing or connection failed" "sudo -u postgres createuser -s $target_user"
    fi
}

# Deep check: Cloud CLI authentication
# Enhanced per bead azw: Thorough cloud CLI auth checks with proper status handling
# All checks use 10 second timeout to prevent hanging on network issues
deep_check_cloud() {
    check_vault_configured
    check_gh_auth
    check_wrangler_auth
    check_supabase_auth
    check_vercel_auth
}

# Deep check: tmux responsiveness
# Related: GitHub issue #20 (NTM: "context deadline exceeded")
deep_check_tmux_performance() {
    if ! command -v tmux &>/dev/null; then
        check "deep.tmux.present" "tmux responsiveness" "warn" "tmux not installed" "sudo apt install tmux"
        return
    fi

    local timeout_secs=5
    local warn_threshold_ms=1000
    local hint="If NTM shows 'context deadline exceeded', tmux may be slow. Try running NTM outside of tmux (fresh SSH session). Diagnose with: time tmux list-sessions; time tmux list-panes -a; ls -la /tmp/tmux-*."
    if [[ -n "${TMUX:-}" ]]; then
        hint="You are currently inside tmux. If NTM is timing out, try running it outside tmux (new SSH session). Diagnose with: time tmux list-sessions; time tmux list-panes -a; ls -la /tmp/tmux-*."
    fi

    _deep_check_tmux_cmd() {
        local id="$1"
        local label="$2"
        shift 2

        local start_ns end_ns elapsed_ms
        start_ns=$(date +%s%N 2>/dev/null || echo "")

        local output status
        output=$(run_with_timeout "$timeout_secs" "$label" "$@")
        status=$?

        end_ns=$(date +%s%N 2>/dev/null || echo "")
        if [[ "$start_ns" =~ ^[0-9]+$ ]] && [[ "$end_ns" =~ ^[0-9]+$ ]]; then
            elapsed_ms=$(((end_ns - start_ns) / 1000000))
        else
            elapsed_ms=-1
        fi

        if ((status == 124)); then
            check_with_timeout_status "$id" "$label" "timeout" "timed out after ${timeout_secs}s" "$hint"
            return 0
        fi

        if ((status != 0)); then
            if echo "$output" | grep -qiE "no server running|failed to connect to server"; then
                check "$id" "$label (no server)" "pass" "no tmux server running"
                return 0
            fi

            local first_line=""
            first_line="$(printf '%s\n' "$output" | head -n 1)"
            [[ -z "$first_line" ]] && first_line="tmux command failed"
            check "$id" "$label" "warn" "$first_line" "$hint"
            return 0
        fi

        local label_with_timing="$label"
        if ((elapsed_ms >= 0)); then
            label_with_timing="$label (${elapsed_ms}ms)"
        fi

        if ((elapsed_ms >= 0)) && ((elapsed_ms >= warn_threshold_ms)); then
            check "$id" "$label_with_timing" "warn" "slow tmux" "$hint"
        else
            check "$id" "$label_with_timing" "pass" "ok"
        fi
        return 0
    }

    _deep_check_tmux_cmd "deep.tmux.list_sessions" "tmux list-sessions responsiveness" bash -lc "tmux list-sessions >/dev/null"
    _deep_check_tmux_cmd "deep.tmux.list_panes" "tmux list-panes -a responsiveness" bash -lc "tmux list-panes -a -F '#{pane_id}' >/dev/null"
}

# Deep check: Network health
# Related: bead bd-31ps.7.2
# Exposes preflight-style network checks via doctor --deep for ongoing verification.
# Results are WARN (non-fatal) since network issues may be transient.
deep_check_network() {
    check_network_dns
    check_network_github
    check_network_apt_mirror
}

# check_network_dns - DNS resolution check for critical hosts
# Related: bead bd-31ps.7.2
# Tests DNS resolution for hosts required by the installer
check_network_dns() {
    local hosts=(
        "github.com"
        "raw.githubusercontent.com"
    )
    local dns_failures=()
    local dns_ok=true

    for host in "${hosts[@]}"; do
        # Try multiple resolution methods (dig, host, getent)
        local resolved=false
        if command -v dig &>/dev/null; then
            if dig +short +time=5 +tries=1 "$host" 2>/dev/null | grep -qE '^[0-9]'; then
                resolved=true
            fi
        fi
        if [[ "$resolved" == "false" ]] && command -v host &>/dev/null; then
            if timeout 5 host "$host" &>/dev/null; then
                resolved=true
            fi
        fi
        if [[ "$resolved" == "false" ]] && command -v getent &>/dev/null; then
            if timeout 5 getent hosts "$host" &>/dev/null; then
                resolved=true
            fi
        fi

        if [[ "$resolved" == "false" ]]; then
            dns_failures+=("$host")
            dns_ok=false
        fi
    done

    if [[ "$dns_ok" == "true" ]]; then
        check "deep.network.dns" "DNS resolution" "pass" "all hosts resolved"
    else
        local failed_list
        failed_list=$(IFS=", "; echo "${dns_failures[*]}")
        check "deep.network.dns" "DNS resolution" "warn" "failed: $failed_list" "Check /etc/resolv.conf or network settings"
    fi
}

# check_network_github - GitHub connectivity check
# Related: bead bd-31ps.7.2
# Tests HTTP(S) connectivity to GitHub (critical for installer downloads)
check_network_github() {
    if ! command -v curl &>/dev/null; then
        check "deep.network.github" "GitHub connectivity" "warn" "curl not installed"
        return
    fi

    # Test basic HTTPS connectivity to GitHub
    local http_status
    http_status=$(curl -sL --max-time 10 --connect-timeout 5 -o /dev/null -w "%{http_code}" "https://github.com" 2>/dev/null) || http_status="000"

    if [[ "$http_status" == "200" ]] || [[ "$http_status" == "301" ]] || [[ "$http_status" == "302" ]]; then
        check "deep.network.github" "GitHub connectivity" "pass" "github.com reachable (HTTP $http_status)"
    elif [[ "$http_status" == "000" ]]; then
        check "deep.network.github" "GitHub connectivity" "warn" "connection failed" "Check network/firewall settings"
    else
        check "deep.network.github" "GitHub connectivity" "warn" "HTTP $http_status" "Unexpected response; check proxy settings"
    fi

    # Also test raw.githubusercontent.com (used for script downloads)
    http_status=$(curl -sL --max-time 10 --connect-timeout 5 -o /dev/null -w "%{http_code}" "https://raw.githubusercontent.com" 2>/dev/null) || http_status="000"

    if [[ "$http_status" == "200" ]] || [[ "$http_status" == "400" ]]; then
        # Note: raw.githubusercontent.com returns 400 on bare request, which is expected
        check "deep.network.github_raw" "GitHub raw content" "pass" "raw.githubusercontent.com reachable"
    elif [[ "$http_status" == "000" ]]; then
        check "deep.network.github_raw" "GitHub raw content" "warn" "connection failed" "Check network/firewall settings"
    else
        check "deep.network.github_raw" "GitHub raw content" "warn" "HTTP $http_status" "Unexpected response"
    fi
}

# check_network_apt_mirror - APT mirror reachability check
# Related: bead bd-31ps.7.2
# Tests connectivity to the configured APT mirror
check_network_apt_mirror() {
    if ! command -v curl &>/dev/null; then
        return  # Already warned in github check
    fi

    # Detect the primary APT mirror from sources.list
    local mirror_url=""
    if [[ -f /etc/apt/sources.list ]]; then
        mirror_url=$(grep -m1 "^deb http" /etc/apt/sources.list 2>/dev/null | awk '{print $2}' | sed 's|/ubuntu.*||') || true
    fi
    if [[ -z "$mirror_url" ]] && [[ -d /etc/apt/sources.list.d ]]; then
        mirror_url=$(grep -rh "^deb http" /etc/apt/sources.list.d/ 2>/dev/null | head -1 | awk '{print $2}' | sed 's|/ubuntu.*||') || true
    fi

    if [[ -z "$mirror_url" ]]; then
        check "deep.network.apt_mirror" "APT mirror" "warn" "could not detect mirror URL"
        return
    fi

    # Test mirror reachability
    local http_status
    http_status=$(curl -sL --max-time 10 --connect-timeout 5 -o /dev/null -w "%{http_code}" "${mirror_url}/dists/" 2>/dev/null) || http_status="000"

    local mirror_host="${mirror_url#http*://}"
    mirror_host="${mirror_host%%/*}"

    if [[ "$http_status" == "200" ]] || [[ "$http_status" == "301" ]]; then
        check "deep.network.apt_mirror" "APT mirror" "pass" "$mirror_host reachable"
    elif [[ "$http_status" == "000" ]]; then
        check "deep.network.apt_mirror" "APT mirror" "warn" "$mirror_host unreachable" "Check /etc/apt/sources.list or network"
    else
        check "deep.network.apt_mirror" "APT mirror" "warn" "HTTP $http_status from $mirror_host" "May need to switch mirrors"
    fi
}

# deep_check_notifications - Verify ntfy.sh notification configuration and connectivity
# Related: GitHub issue #131
deep_check_notifications() {
    local config_file="${HOME}/.config/acfs/config.yaml"
    local enabled="" topic="" server=""

    # Read config (same logic as notify.sh)
    if [[ -f "$config_file" ]]; then
        enabled=$(grep -E '^\s*ntfy_enabled\s*:' "$config_file" 2>/dev/null | head -1 | \
                  sed -E 's/^\s*ntfy_enabled\s*:\s*//; s/^["'"'"']//; s/["'"'"']$//' | \
                  sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true)
        topic=$(grep -E '^\s*ntfy_topic\s*:' "$config_file" 2>/dev/null | head -1 | \
                sed -E 's/^\s*ntfy_topic\s*:\s*//; s/^["'"'"']//; s/["'"'"']$//' | \
                sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true)
        server=$(grep -E '^\s*ntfy_server\s*:' "$config_file" 2>/dev/null | head -1 | \
                 sed -E 's/^\s*ntfy_server\s*:\s*//; s/^["'"'"']//; s/["'"'"']$//' | \
                 sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true)
    fi

    # Allow env overrides
    enabled="${ACFS_NTFY_ENABLED:-$enabled}"
    topic="${ACFS_NTFY_TOPIC:-$topic}"
    server="${ACFS_NTFY_SERVER:-$server}"
    server="${server:-https://ntfy.sh}"

    # Check configuration state
    if [[ "$enabled" != "true" ]]; then
        check "deep.notifications.ntfy" "ntfy.sh notifications" "warn" "not enabled" "acfs notifications enable"
        return
    fi

    if [[ -z "$topic" ]]; then
        check "deep.notifications.ntfy" "ntfy.sh notifications" "warn" "enabled but no topic set" "acfs notifications enable"
        return
    fi

    # Topic and enabled are set -- test server connectivity
    if ! command -v curl &>/dev/null; then
        check "deep.notifications.ntfy" "ntfy.sh notifications" "warn" "curl not available" "apt install curl"
        return
    fi

    # HEAD request against the server health endpoint (lightweight)
    local http_code
    http_code=$(curl -sL --max-time 5 --connect-timeout 3 -o /dev/null -w "%{http_code}" "${server}/v1/health" 2>/dev/null) || http_code="000"

    if [[ "$http_code" =~ ^2 ]]; then
        check "deep.notifications.ntfy" "ntfy.sh notifications" "pass" "enabled, server reachable (${server})"
    elif [[ "$http_code" == "000" ]]; then
        check "deep.notifications.ntfy" "ntfy.sh notifications" "warn" "server unreachable (${server})" "Check network or acfs notifications set-server <url>"
    else
        check "deep.notifications.ntfy" "ntfy.sh notifications" "warn" "server returned HTTP ${http_code}" "Check server URL: ${server}"
    fi
}

# check_vault_configured - Check if Vault is configured and reachable
# Related: bead azw
check_vault_configured() {
    # Skip if not installed
    if ! command -v vault &>/dev/null; then
        check "deep.cloud.vault_status" "Vault" "warn" "not installed" "Install from https://www.vaultproject.io/"
        return
    fi

    # Check if VAULT_ADDR is set (required for vault to work)
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        # Check common config locations
        if [[ -f "$HOME/.zshrc.local" ]] && grep -q "VAULT_ADDR" "$HOME/.zshrc.local" 2>/dev/null; then
            check "deep.cloud.vault_config" "Vault config" "pass" "VAULT_ADDR in ~/.zshrc.local"
        else
            check "deep.cloud.vault_config" "Vault config" "warn" "VAULT_ADDR not set" "export VAULT_ADDR=https://your-vault-server:8200"
        fi
        return
    fi

    # VAULT_ADDR is set, try to connect
    if timeout 10 vault status &>/dev/null; then
        check "deep.cloud.vault_status" "Vault status" "pass" "connected to $VAULT_ADDR"
    else
        check "deep.cloud.vault_status" "Vault status" "warn" "not reachable" "Check VAULT_ADDR and network"
    fi
}

# check_gh_auth - GitHub CLI authentication check
# Related: bead azw
# Enhanced: Caching support (bead lz1)
check_gh_auth() {
    if ! command -v gh &>/dev/null; then
        check "deep.cloud.gh_auth" "GitHub CLI" "warn" "not installed" "sudo apt install gh"
        return
    fi

    # Try cache first for auth status (bead lz1)
    local cached_result
    if cached_result=$(get_cached_result "gh_auth"); then
        check "deep.cloud.gh_auth" "GitHub CLI auth" "pass" "$cached_result (cached)"
        return
    fi

    # Run with timeout
    local result
    result=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "GitHub CLI auth" gh auth status 2>&1)
    local status=$?

    if ((status == 124)); then
        check_with_timeout_status "deep.cloud.gh_auth" "GitHub CLI auth" "timeout" "check timed out" "Check network, then: gh auth login"
    elif ((status == 0)); then
        # Get the authenticated user for more detail
        local gh_user
        gh_user=$(timeout 5 gh api user --jq '.login' 2>/dev/null) || gh_user="authenticated"
        cache_result "gh_auth" "$gh_user"
        check "deep.cloud.gh_auth" "GitHub CLI auth" "pass" "$gh_user"
    else
        check "deep.cloud.gh_auth" "GitHub CLI auth" "warn" "not authenticated" "gh auth login"
    fi
}

# check_wrangler_auth - Cloudflare Wrangler authentication check
# Related: bead azw
# Enhanced: Caching and timeout support (bead lz1)
check_wrangler_auth() {
    if ! command -v wrangler &>/dev/null; then
        check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare)" "warn" "not installed" "bun install -g --trust wrangler@latest"
        return
    fi

    # Try cache first (bead lz1)
    local cached_result
    if cached_result=$(get_cached_result "wrangler_auth"); then
        check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "pass" "$cached_result (cached)"
        return
    fi

    local shell_config_files=()
    mapfile -t shell_config_files < <(default_auth_config_files)
    if get_configured_secret "CLOUDFLARE_API_TOKEN" "${shell_config_files[@]}" >/dev/null; then
        cache_result "wrangler_auth" "CLOUDFLARE_API_TOKEN"
        check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "pass" "CLOUDFLARE_API_TOKEN set"
        return
    fi

    # Run with timeout
    local result
    result=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "Wrangler auth" wrangler whoami 2>&1)
    local status=$?

    if ((status == 124)); then
        check_with_timeout_status "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "timeout" "check timed out" "Check network, then set CLOUDFLARE_API_TOKEN or run wrangler login from a browser-capable session"
    elif ((status == 0)); then
        # Extract account info from wrangler whoami output
        local wrangler_account="authenticated"
        if echo "$result" | grep -q "Account ID"; then
            wrangler_account="authenticated"
        fi
        cache_result "wrangler_auth" "$wrangler_account"
        check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "pass" "$wrangler_account"
    else
        # A wrangler config file alone does not prove the user is still
        # authenticated, so do not treat it as a pass if `whoami` failed.
        if [[ -f "$HOME/.wrangler/config/default.toml" ]]; then
            check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "warn" "config file present but auth could not be verified" "Set CLOUDFLARE_API_TOKEN or rerun wrangler login from a browser-capable session"
        else
            check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "warn" "not authenticated" "Set CLOUDFLARE_API_TOKEN or run wrangler login from a browser-capable session"
        fi
    fi
}

# check_supabase_auth - Supabase CLI authentication check
# Related: bead azw
check_supabase_auth() {
    if ! command -v supabase &>/dev/null; then
        check "deep.cloud.supabase_auth" "Supabase CLI" "warn" "not installed" "acfs update --cloud-only --force"
        return
    fi

    # Try cache first (bead lz1)
    local cached_result
    if cached_result=$(get_cached_result "supabase_auth"); then
        check "deep.cloud.supabase_auth" "Supabase CLI auth" "pass" "$cached_result (cached)"
        return
    fi

    # Check for SUPABASE_ACCESS_TOKEN (headless auth)
    local shell_config_files=()
    mapfile -t shell_config_files < <(default_auth_config_files)
    if get_configured_secret "SUPABASE_ACCESS_TOKEN" "${shell_config_files[@]}" >/dev/null; then
        cache_result "supabase_auth" "SUPABASE_ACCESS_TOKEN"
        check "deep.cloud.supabase_auth" "Supabase CLI auth" "pass" "SUPABASE_ACCESS_TOKEN set"
        return
    fi

    local token_file=""
    if [[ -f "$HOME/.supabase/access-token" ]]; then
        token_file="$HOME/.supabase/access-token"
    elif [[ -f "$HOME/.config/supabase/access-token" ]]; then
        token_file="$HOME/.config/supabase/access-token"
    fi

    if [[ -n "$token_file" ]] && [[ -s "$token_file" ]]; then
        cache_result "supabase_auth" "access-token file"
        check "deep.cloud.supabase_auth" "Supabase CLI auth" "pass" "access-token file present"
    else
        check "deep.cloud.supabase_auth" "Supabase CLI auth" "warn" "not authenticated" "supabase login --token <token> (or set SUPABASE_ACCESS_TOKEN)"
    fi
}

# check_vercel_auth - Vercel CLI authentication check
# Related: bead azw
check_vercel_auth() {
    if ! command -v vercel &>/dev/null; then
        check "deep.cloud.vercel_auth" "Vercel CLI" "warn" "not installed" "bun install -g --trust vercel@latest"
        return
    fi

    # Try cache first (bead lz1)
    local cached_result
    if cached_result=$(get_cached_result "vercel_auth"); then
        check "deep.cloud.vercel_auth" "Vercel CLI auth" "pass" "$cached_result (cached)"
        return
    fi

    local shell_config_files=()
    mapfile -t shell_config_files < <(default_auth_config_files)
    if get_configured_secret "VERCEL_TOKEN" "${shell_config_files[@]}" >/dev/null; then
        cache_result "vercel_auth" "VERCEL_TOKEN"
        check "deep.cloud.vercel_auth" "Vercel CLI auth" "pass" "VERCEL_TOKEN set"
        return
    fi

    # Run with timeout
    local result
    result=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "Vercel auth" vercel whoami 2>&1)
    local status=$?

    if ((status == 124)); then
        check_with_timeout_status "deep.cloud.vercel_auth" "Vercel CLI auth" "timeout" "check timed out" "Check network, then run vercel login or set VERCEL_TOKEN"
    elif ((status == 0)); then
        local vercel_user
        vercel_user=$(echo "$result" | head -n1 | tr -d ' ')
        [[ -z "$vercel_user" ]] && vercel_user="authenticated"
        cache_result "vercel_auth" "$vercel_user"
        check "deep.cloud.vercel_auth" "Vercel CLI auth" "pass" "$vercel_user"
    else
        local auth_file=""
        if [[ -f "$HOME/.config/vercel/auth.json" ]]; then
            auth_file="$HOME/.config/vercel/auth.json"
        elif [[ -f "$HOME/.vercel/auth.json" ]]; then
            auth_file="$HOME/.vercel/auth.json"
        fi

        if [[ -n "$auth_file" ]] && command -v jq &>/dev/null && jq -e '((.token // .user.email // "") | strings | length) > 0' "$auth_file" >/dev/null 2>&1; then
            cache_result "vercel_auth" "auth file present"
            check "deep.cloud.vercel_auth" "Vercel CLI auth" "pass" "auth file present"
        elif [[ -n "$auth_file" ]] && grep -Eq '"(token|email)"[[:space:]]*:[[:space:]]*"[^"]+"' "$auth_file" 2>/dev/null; then
            cache_result "vercel_auth" "auth file present"
            check "deep.cloud.vercel_auth" "Vercel CLI auth" "pass" "auth file present"
        else
            check "deep.cloud.vercel_auth" "Vercel CLI auth" "warn" "not authenticated" "vercel login (or set VERCEL_TOKEN)"
        fi
    fi
}

# Print summary
print_summary() {
    echo ""

    # Print legend (bead qup)
    local doctor_ci="${ACFS_DOCTOR_CI:-false}"
    if [[ "$doctor_ci" != "true" ]]; then
        if [[ "$HAS_GUM" == "true" ]]; then
            gum style --foreground "$ACFS_MUTED" "  Legend: $(gum style --foreground "$ACFS_SUCCESS" "✓") installed  $(gum style --foreground "$ACFS_MUTED" "○") skipped  $(gum style --foreground "$ACFS_ERROR" "✖") missing  $(gum style --foreground "$ACFS_WARNING" "⚠") warning  $(gum style --foreground "$ACFS_WARNING" "?") timeout"
        else
            echo -e "  Legend: ${GREEN}✓${NC} installed  ${CYAN}○${NC} skipped  ${RED}✖${NC} missing  ${YELLOW}⚠${NC} warning  ${YELLOW}?${NC} timeout"
        fi
    fi
}

# Print JSON output
# Enhanced per bead aqs: Includes deep check summary when --deep is used
print_json() {
    local checks_json
    checks_json=$(printf '%s,' "${JSON_CHECKS[@]}" | sed 's/,$//')

    local os_id="unknown"
    local os_version="unknown"
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_id="${ID:-unknown}"
        os_version="${VERSION_ID:-unknown}"
    fi

    # Build deep summary JSON if deep mode was used
    local deep_summary_json=""
    if [[ "$DEEP_MODE" == "true" ]]; then
        local deep_total=$((DEEP_PASS_COUNT + DEEP_WARN_COUNT + DEEP_FAIL_COUNT))
        deep_summary_json=",
  \"deep_summary\": {\"pass\": $DEEP_PASS_COUNT, \"warn\": $DEEP_WARN_COUNT, \"fail\": $DEEP_FAIL_COUNT, \"total\": $deep_total, \"elapsed_seconds\": ${DEEP_CHECK_ELAPSED:-0}}"
    fi

    local json_output
    json_output=$(cat << EOF
{
  "acfs_version": "$(json_escape "$ACFS_VERSION")",
  "timestamp": "$(json_escape "$(date -Iseconds)")",
  "mode": "$(json_escape "${ACFS_MODE:-vibe}")",
  "deep_mode": $DEEP_MODE,
  "user": "$(json_escape "$(whoami)")",
  "os": {"id": "$(json_escape "$os_id")", "version": "$(json_escape "$os_version")"},
  "checks": [$checks_json],
  "summary": {"pass": $PASS_COUNT, "skip": $SKIP_COUNT, "warn": $WARN_COUNT, "fail": $FAIL_COUNT}$deep_summary_json
}
EOF
)

    # Use output formatting library if available
    if type -t acfs_format_output &>/dev/null; then
        local resolved_format
        resolved_format=$(acfs_resolve_format "$_DOCTOR_OUTPUT_FORMAT")
        acfs_format_output "$json_output" "$resolved_format" "$_DOCTOR_SHOW_STATS"
    else
        # Fallback: direct JSON output
        printf '%s\n' "$json_output"
    fi
}

# Main
main() {
    local invoked_as
    invoked_as="$(basename "${0:-acfs}")"

    # If installed as `acfs`, support subcommands (doctor/update/services-setup/version).
    local subcmd="${1:-}"
    case "$subcmd" in
        doctor|check)
            shift
            ;;
        info|i)
            shift
            local info_script=""
            info_script="$(_acfs_doctor_find_lib_script "info.sh" 2>/dev/null || true)"

            if [[ -n "$info_script" ]]; then
                exec bash "$info_script" "$@"
            fi

            echo "Error: info.sh not found" >&2
            return 1
            ;;
        status)
            shift
            local status_script=""
            status_script="$(_acfs_doctor_find_lib_script "status.sh" 2>/dev/null || true)"

            if [[ -n "$status_script" ]]; then
                exec bash "$status_script" "$@"
            fi

            echo "Error: status.sh not found" >&2
            return 1
            ;;
        dashboard)
            shift
            local dashboard_script=""
            dashboard_script="$(_acfs_doctor_find_lib_script "dashboard.sh" 2>/dev/null || true)"

            if [[ -n "$dashboard_script" ]]; then
                exec bash "$dashboard_script" "$@"
            fi

            echo "Error: dashboard.sh not found" >&2
            return 1
            ;;
        continue|progress)
            shift
            local continue_script=""
            continue_script="$(_acfs_doctor_find_lib_script "continue.sh" 2>/dev/null || true)"

            if [[ -n "$continue_script" ]]; then
                exec bash "$continue_script" "$@"
            fi

            echo "Error: continue.sh not found" >&2
            return 1
            ;;
        changelog|changes|log)
            shift
            local changelog_script=""
            changelog_script="$(_acfs_doctor_find_lib_script "changelog.sh" 2>/dev/null || true)"

            if [[ -n "$changelog_script" ]]; then
                exec bash "$changelog_script" "$@"
            fi

            echo "Error: changelog.sh not found" >&2
            return 1
            ;;
        export-config|export)
            shift
            local export_config_script=""
            export_config_script="$(_acfs_doctor_find_lib_script "export-config.sh" 2>/dev/null || true)"

            if [[ -n "$export_config_script" ]]; then
                exec bash "$export_config_script" "$@"
            fi

            echo "Error: export-config.sh not found" >&2
            return 1
            ;;
        cheatsheet|cs)
            shift
            local cheatsheet_script=""
            cheatsheet_script="$(_acfs_doctor_find_lib_script "cheatsheet.sh" 2>/dev/null || true)"

            if [[ -n "$cheatsheet_script" ]]; then
                exec bash "$cheatsheet_script" "$@"
            fi

            echo "Error: cheatsheet.sh not found" >&2
            return 1
            ;;
        session|sessions)
            shift
            acfs_session_main "$@"
            return $?
            ;;
        update)
            shift
            local update_script=""
            update_script="$(_acfs_doctor_find_lib_script "update.sh" 2>/dev/null || true)"

            if [[ -n "$update_script" ]]; then
                exec bash "$update_script" "$@"
            fi

            echo "Error: update.sh not found" >&2
            return 1
            ;;
        newproj|new-project|new)
            shift
            local newproj_script=""
            newproj_script="$(_acfs_doctor_find_lib_script "newproj.sh" 2>/dev/null || true)"

            if [[ -n "$newproj_script" ]]; then
                exec bash "$newproj_script" "$@"
            fi

            echo "Error: newproj.sh not found" >&2
            return 1
            ;;
        services-setup|services|setup)
            shift
            local services_script=""
            services_script="$(_acfs_doctor_find_scripts_script "services-setup.sh" 2>/dev/null || true)"

            if [[ -n "$services_script" ]]; then
                exec bash "$services_script" "$@"
            fi

            echo "Error: services-setup.sh not found" >&2
            return 1
            ;;
        support-bundle|bundle)
            shift
            local support_script=""
            support_script="$(_acfs_doctor_find_lib_script "support.sh" 2>/dev/null || true)"

            if [[ -n "$support_script" ]]; then
                exec bash "$support_script" "$@"
            fi

            echo "Error: support.sh not found" >&2
            return 1
            ;;
        version|-v|--version)
            local version_file=""
            version_file="$(_acfs_doctor_find_project_path "VERSION" 2>/dev/null || true)"

            if [[ -n "$version_file" ]]; then
                cat "$version_file"
            else
                echo "${ACFS_VERSION:-unknown}"
            fi
            return 0
            ;;
        help|-h)
            print_acfs_help
            return 0
            ;;
        "")
            if [[ "$invoked_as" == "acfs" ]]; then
                print_acfs_help
                return 0
            fi
            ;;
    esac

    # Parse args
    while [[ $# -gt 0 ]]; do
        case $1 in
            --json)
                JSON_MODE=true
                shift
                ;;
            --format|-f)
                shift
                if [[ -z "${1:-}" || "$1" == -* ]]; then
                    echo "Error: --format requires a value (json or toon)" >&2
                    return 1
                fi
                _DOCTOR_OUTPUT_FORMAT="$1"
                JSON_MODE=true
                shift
                ;;
            --format=*)
                _DOCTOR_OUTPUT_FORMAT="${1#*=}"
                if [[ -z "$_DOCTOR_OUTPUT_FORMAT" ]]; then
                    echo "Error: --format requires a value (json or toon)" >&2
                    return 1
                fi
                JSON_MODE=true
                shift
                ;;
            --toon|-t)
                _DOCTOR_OUTPUT_FORMAT="toon"
                JSON_MODE=true
                shift
                ;;
            --stats)
                _DOCTOR_SHOW_STATS=true
                shift
                ;;
            --deep)
                DEEP_MODE=true
                shift
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            --fix)
                FIX_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN_MODE=true
                shift
                ;;
            --help|-h)
                echo "Usage: acfs doctor [--json] [--format <fmt>] [--stats] [--deep] [--no-cache] [--fix] [--dry-run]"
                echo ""
                echo "Options:"
                echo "  --json           Output results as JSON"
                echo "  --format <fmt>   Output format: json or toon (env: ACFS_OUTPUT_FORMAT, TOON_DEFAULT_FORMAT)"
                echo "  --toon, -t       Shorthand for --format toon"
                echo "  --stats          Show token savings statistics (JSON vs TOON bytes)"
                echo "  --deep      Run functional tests (auth, connections)"
                echo "  --no-cache  Skip cache, run all checks fresh"
                echo "  --fix       Automatically apply safe fixes for failed checks"
                echo "  --dry-run   Preview fixes without applying (use with --fix)"
                echo ""
                echo "By default, doctor runs quick existence checks only."
                echo "Use --deep for thorough validation including:"
                echo "  - Agent authentication (claude, codex, gemini)"
                echo "  - Database connectivity (PostgreSQL)"
                echo "  - Cloud CLI authentication (vault, wrangler, etc.)"
                echo ""
                echo "Deep checks are cached for 5 minutes by default."
                echo "Use --no-cache to force fresh deep checks."
                echo ""
                echo "Fix mode applies safe, reversible fixes for common issues:"
                echo "  - PATH ordering in shell config"
                echo "  - Missing ACFS config files"
                echo "  - Missing symlinks for tools"
                echo "  - Missing zsh plugins"
                echo "Use --dry-run to preview fixes before applying."
                echo ""
                echo "Examples:"
                echo "  acfs doctor                   # Quick health check"
                echo "  acfs doctor --deep            # Full functional tests"
                echo "  acfs doctor --deep --no-cache # Force fresh deep checks"
                echo "  acfs doctor --json            # JSON output for tooling"
                echo "  acfs doctor --fix             # Apply safe fixes"
                echo "  acfs doctor --fix --dry-run   # Preview fixes"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ "$JSON_MODE" != "true" ]]; then
        local os_pretty="unknown"
        if [[ -f /etc/os-release ]]; then
            # shellcheck disable=SC1091
            . /etc/os-release
            os_pretty="${PRETTY_NAME:-${ID:-unknown} ${VERSION_ID:-unknown}}"
        fi

        if [[ "$HAS_GUM" == "true" ]]; then
            echo ""
            gum style \
                --border rounded \
                --border-foreground "$ACFS_PRIMARY" \
                --padding "1 2" \
                --margin "0 0 1 0" \
                "$(gum style --foreground "$ACFS_ACCENT" --bold '🩺 ACFS Doctor') $(gum style --foreground "$ACFS_MUTED" "v$ACFS_VERSION")

$(gum style --foreground "$ACFS_MUTED" "User:") $(gum style --foreground "$ACFS_TEAL" "$(whoami)")  $(gum style --foreground "$ACFS_MUTED" "Mode:") $(gum style --foreground "$ACFS_TEAL" "${ACFS_MODE:-vibe}")
$(gum style --foreground "$ACFS_MUTED" "OS:") $(gum style --foreground "$ACFS_TEAL" "$os_pretty")"
        else
            echo ""
            echo "ACFS Doctor v$ACFS_VERSION"
            echo "User: $(whoami)"
            echo "Mode: ${ACFS_MODE:-vibe}"
            echo "OS: $os_pretty"
            echo ""
        fi
    fi

    # Initialize fix mode if enabled
    if [[ "$FIX_MODE" == "true" ]]; then
        if type -t run_doctor_fix &>/dev/null; then
            if [[ "$DRY_RUN_MODE" == "true" ]]; then
                run_doctor_fix --dry-run
            else
                run_doctor_fix
            fi
        else
            echo "Warning: doctor_fix.sh not loaded, --fix unavailable" >&2
            FIX_MODE=false
        fi
    fi

    check_identity
    check_workspace
    check_shell
    check_core_tools
    check_agents
    check_cloud
    check_stack
    check_utilities
    check_manifest_supplemental
    show_skipped_tools

    # Run deep checks if --deep flag was provided
    if [[ "$DEEP_MODE" == "true" ]]; then
        run_deep_checks
    fi

    if [[ "$JSON_MODE" == "true" ]]; then
        print_json
    else
        print_summary
    fi

    # Finalize fix mode if enabled
    if [[ "$FIX_MODE" == "true" ]]; then
        if type -t finalize_doctor_fix &>/dev/null; then
            finalize_doctor_fix
        fi
    fi

    # Exit with appropriate code
    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
