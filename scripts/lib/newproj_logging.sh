#!/usr/bin/env bash
# ============================================================
# ACFS newproj TUI Wizard - Logging Infrastructure
# Provides detailed session logging for debugging and troubleshooting
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_NEWPROJ_LOGGING_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_NEWPROJ_LOGGING_SH_LOADED=1

# ============================================================
# Configuration
# ============================================================

# Log levels (matching syslog convention)
readonly ACFS_LOG_DEBUG=0
readonly ACFS_LOG_INFO=1
readonly ACFS_LOG_WARN=2
readonly ACFS_LOG_ERROR=3

# Current log level (can be overridden via env var or --verbose flag)
export ACFS_LOG_LEVEL="${ACFS_LOG_LEVEL:-$ACFS_LOG_INFO}"

newproj_logging_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

newproj_logging_default_state_dir() {
    local state_home=""
    local home_dir=""
    local tmp_dir=""

    state_home="$(newproj_logging_sanitize_abs_nonroot_path "${XDG_STATE_HOME:-}" 2>/dev/null || true)"
    if [[ -n "$state_home" ]]; then
        printf '%s\n' "$state_home"
        return 0
    fi

    home_dir="$(newproj_logging_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    if [[ -n "$home_dir" ]]; then
        printf '%s/.local/state\n' "$home_dir"
        return 0
    fi

    tmp_dir="$(newproj_logging_sanitize_abs_nonroot_path "${TMPDIR:-/tmp}" 2>/dev/null || true)"
    if [[ -z "$tmp_dir" ]]; then
        tmp_dir="/tmp"
    fi
    printf '%s/acfs-state\n' "$tmp_dir"
}

# Log directory (XDG compliant)
export ACFS_LOG_DIR="${ACFS_LOG_DIR:-$(newproj_logging_default_state_dir)/acfs/logs}"

# Session log file (set by init_logging)
export ACFS_SESSION_LOG=""

# Version file location
ACFS_VERSION_FILE="${ACFS_VERSION_FILE:-/etc/acfs/VERSION}"

# Log retention in days
ACFS_LOG_RETENTION_DAYS="${ACFS_LOG_RETENTION_DAYS:-7}"

# ============================================================
# Initialization
# ============================================================

# Allocate a private session directory containing one ordinary .log file.
newproj_logging_create_session() (
    # An exclusively created private directory makes the .log file's parent
    # unique. Keep the existing log namespace and retention selection unchanged.
    umask 077
    local session_dir log_path
    session_dir=$(mktemp -d "$1/newproj_session.XXXXXX") || return 1
    log_path="$session_dir/newproj_$(date +%Y%m%d_%H%M%S)_$$.log"
    : > "$log_path" || return 1
    printf '%s\n' "$log_path"
)

# Initialize logging - call at start of wizard
# Usage: init_logging [--verbose]
init_logging() {
    local verbose=false
    local fallback_log_dir=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)
                verbose=true
                export ACFS_LOG_LEVEL=$ACFS_LOG_DEBUG
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Keep newly created directories and session files private without changing
    # the caller's umask or permissions on an existing user-selected directory.
    if ! (umask 077; mkdir -p "$ACFS_LOG_DIR") 2>/dev/null \
        || ! ACFS_SESSION_LOG=$(newproj_logging_create_session "$ACFS_LOG_DIR" 2>/dev/null); then
        fallback_log_dir="${TMPDIR:-/tmp}"
        echo "Warning: Could not create session log in $ACFS_LOG_DIR, falling back to $fallback_log_dir" >&2
        ACFS_LOG_DIR="$fallback_log_dir"
        export ACFS_LOG_DIR
        ACFS_SESSION_LOG=$(newproj_logging_create_session "$fallback_log_dir" 2>/dev/null) || {
            echo "Error: Could not create temp log file" >&2
            # Still set it to /dev/null so logging functions don't fail, just discard
            ACFS_SESSION_LOG="/dev/null"
        }
    fi
    export ACFS_SESSION_LOG

    # Clean up old logs (non-blocking)
    _cleanup_old_logs &

    # Write session header
    {
        echo "========================================"
        echo "ACFS newproj TUI Wizard Session Log"
        echo "========================================"
        echo "Started: $(date -Iseconds)"
        echo "PID: $$"
        echo "User: $(whoami)"
        echo "Home: ${HOME:-<unset>}"
        echo "Shell: ${SHELL:-unknown}"
        echo "Terminal: ${TERM:-unknown}"
        echo "Terminal size: $(tput cols 2>/dev/null || echo '?')x$(tput lines 2>/dev/null || echo '?')"
        echo "Color support: $(tput colors 2>/dev/null || echo 'unknown')"
        echo "ACFS version: $(cat "$ACFS_VERSION_FILE" 2>/dev/null || echo 'unknown')"
        echo "Working directory: $(pwd)"
        echo "Log level: $(log_level_name "$ACFS_LOG_LEVEL")"
        echo "Has gum: $(command -v gum &>/dev/null && echo 'yes' || echo 'no')"
        echo "Has glow: $(command -v glow &>/dev/null && echo 'yes' || echo 'no')"
        echo "========================================"
        echo ""
    } >> "$ACFS_SESSION_LOG" 2>/dev/null || true

    log_debug "Logging initialized to: $ACFS_SESSION_LOG"

    if [[ "$verbose" == "true" ]]; then
        log_info "Verbose mode enabled (log level: DEBUG)"
    fi
}

# Get human-readable log level name
log_level_name() {
    local level="$1"
    case "$level" in
        0) echo "DEBUG" ;;
        1) echo "INFO" ;;
        2) echo "WARN" ;;
        3) echo "ERROR" ;;
        *) echo "UNKNOWN($level)" ;;
    esac
}

# ============================================================
# Core Logging Functions
# ============================================================

# Internal: Core logging function
# All other log functions call this
_log() {
    local level="$1"      # Level name (DEBUG, INFO, WARN, ERROR)
    local level_num="$2"  # Level number for comparison
    shift 2
    local message="$*"

    # Skip if no log file
    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    # Skip if level is below threshold
    [[ "$level_num" -lt "${ACFS_LOG_LEVEL:-1}" ]] && return 0

    # Get timestamp with milliseconds
    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    # Get caller information (function:line)
    local caller="${FUNCNAME[2]:-main}"
    local line="${BASH_LINENO[1]:-0}"

    # Pad level to 5 chars for alignment
    local padded_level
    printf -v padded_level "%-5s" "$level"

    # Format: [HH:MM:SS.mmm] [LEVEL] [caller:line] message
    echo "[$timestamp] [$padded_level] [$caller:$line] $message" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log at DEBUG level (for detailed debugging information)
log_debug() {
    _log "DEBUG" "$ACFS_LOG_DEBUG" "$@"
}

# Log at INFO level (for general information)
log_info() {
    _log "INFO" "$ACFS_LOG_INFO" "$@"
}

# Log at WARN level (for warnings that don't stop execution)
log_warn() {
    _log "WARN" "$ACFS_LOG_WARN" "$@"
}

# Log at ERROR level (for errors that may affect execution)
log_error() {
    _log "ERROR" "$ACFS_LOG_ERROR" "$@"
}

# ============================================================
# Specialized Logging Functions
# ============================================================

# Agent instructions remain in wizard state and the generated AGENTS.md. Logs
# need only their length to diagnose edits, not a second copy of private policy.
newproj_logging_state_value() {
    local key="$1"
    local value="$2"
    if [[ "$key" == agents_md_custom ]]; then
        printf '[AGENTS.md content omitted; length=%s]' "${#value}"
    else
        printf '%s' "$value"
    fi
}

# Log state changes (always logged regardless of level)
# Usage: log_state "key" "old_value" "new_value"
log_state() {
    local key="$1"
    local old_value="$2"
    local new_value="$3"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    if [[ "$key" == agents_md_custom ]]; then
        old_value=$(newproj_logging_state_value "$key" "$old_value")
        new_value=$(newproj_logging_state_value "$key" "$new_value")
    fi

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    printf '[%s] [STATE] %s: \047%s\047 -> \047%s\047\n' "$timestamp" "$key" "$old_value" "$new_value" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log screen transitions
# Usage: log_screen "ENTER|EXIT|RENDER" "screen_name"
log_screen() {
    local action="$1"  # ENTER, EXIT, RENDER
    local screen="$2"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    printf '[%s] [SCRN ] %s: %s\n' "$timestamp" "$action" "$screen" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log user input (sanitized for security)
# Usage: log_input "field_name" "value"
log_input() {
    local field="$1"
    local value="$2"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    # Sanitize: truncate long inputs, mask potentially sensitive data
    local sanitized="${value:0:100}"
    [[ ${#value} -gt 100 ]] && sanitized="$sanitized...(truncated)"

    # Basic sanitization for common sensitive patterns
    # Mask anything that looks like a token/key/password
    # Detect if sed supports 'I' flag (GNU) or not (BSD/macOS)
    local sed_flags="g"
    if printf 'test' | sed -E 's/test/TEST/gI' >/dev/null 2>&1; then
        sed_flags="gI"
    fi

    # Patterns to match keys: sk-, api_key, apikey, token, password, secret
    # If 'I' flag is not supported, we match exact case (lowercase) to avoid complex regex logic in a logging helper
    # or rely on the fact that most secrets key headers are lowercase.
    # For better portability without I, we could use [sS][kK]... but that's verbose.
    # Given this runs primarily on Ubuntu (GNU), defaulting to gI check is good.
    # If BSD and check fails, we use 'g' which is case-sensitive. This is an acceptable fallback for logging sanitization.
    
    sanitized=$(echo "$sanitized" | sed -E "s/(sk[-_]|api[-_]?key|token|password|secret)[^[:space:]]*/\1***/${sed_flags}")

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    printf '[%s] [INPUT] %s: \047%s\047\n' "$timestamp" "$field" "$sanitized" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log key press events
# Usage: log_key "ENTER|ESC|UP|DOWN|key"
log_key() {
    local key="$1"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    printf '[%s] [KEY  ] %s\n' "$timestamp" "$key" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log validation results
# Usage: log_validation "field" "value" "result" ["error_message"]
log_validation() {
    local field="$1"
    local value="$2"
    local result="$3"  # PASS or FAIL
    local error_msg="${4:-}"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    local msg="$field='$value' -> $result"
    [[ -n "$error_msg" ]] && msg="$msg: $error_msg"
    
    # Sanitize newlines in validation message
    msg="${msg//[$'\r\n']/ }"

    printf '[%s] [VALID] %s\n' "$timestamp" "$msg" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log file operations
# Usage: log_file_op "CREATE|WRITE|DELETE|MKDIR" "path" ["status"]
log_file_op() {
    local operation="$1"
    local path="$2"
    local status="${3:-OK}"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    printf '[%s] [FILE ] %s: %s (%s)\n' "$timestamp" "$operation" "$path" "$status" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log command execution
# Usage: log_cmd "command" "exit_code"
log_cmd() {
    local cmd="$1"
    local exit_code="$2"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    local status="OK"
    [[ "$exit_code" -ne 0 ]] && status="FAIL(exit=$exit_code)"

    # Truncate very long commands
    local short_cmd="${cmd:0:200}"
    [[ ${#cmd} -gt 200 ]] && short_cmd="$short_cmd..."

    printf '[%s] [CMD  ] %s -> %s\n' "$timestamp" "$short_cmd" "$status" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log structured JSON data (for debugging complex state)
# Usage: log_json "label" "json_string"
log_json() {
    local label="$1"
    local json="$2"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    {
        echo "[$timestamp] [JSON ] $label:"
        # Indent each line of JSON for readability
        local indented="    ${json//$'\n'/$'\n    '}"
        echo "$indented"
    } >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log tech stack detection results
# Usage: log_tech_detect "tech" "detected_via" "confidence"
log_tech_detect() {
    local tech="$1"
    local detected_via="$2"
    local confidence="${3:-high}"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    echo "[$timestamp] [TECH ] Detected: $tech (via: $detected_via, confidence: $confidence)" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log navigation actions
# Usage: log_nav "NEXT|BACK|SKIP|CANCEL" ["from_screen"] ["to_screen"]
log_nav() {
    local action="$1"
    local from="${2:-}"
    local to="${3:-}"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    local msg="$action"
    [[ -n "$from" ]] && msg="$msg from=$from"
    [[ -n "$to" ]] && msg="$msg to=$to"

    echo "[$timestamp] [NAV  ] $msg" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# ============================================================
# Session Management
# ============================================================

# Finalize logging - call at end of wizard
# Usage: finalize_logging [exit_code]
finalize_logging() {
    local exit_code="${1:-0}"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    {
        echo ""
        echo "========================================"
        echo "Session completed: $(date -Iseconds)"
        echo "Exit code: $exit_code"
        echo "Duration: $((SECONDS / 60))m $((SECONDS % 60))s"
        echo "========================================"
    } >> "$ACFS_SESSION_LOG" 2>/dev/null || true

    # Show log location on error
    if [[ "$exit_code" -ne 0 ]]; then
        echo "" >&2
        echo "Session log saved to: $ACFS_SESSION_LOG" >&2
        echo "Please include this log when reporting issues." >&2
    fi
}

# Show log file location to user
# Usage: show_log_location
show_log_location() {
    if [[ -n "$ACFS_SESSION_LOG" && -f "$ACFS_SESSION_LOG" ]]; then
        echo "Debug log: $ACFS_SESSION_LOG"
    else
        echo "Debug log: (not initialized)"
    fi
}

# Get the current session log path
# Usage: get_log_path
get_log_path() {
    echo "${ACFS_SESSION_LOG:-}"
}

# ============================================================
# Log Rotation
# ============================================================

# Clean up logs older than retention period
# Called automatically by init_logging
_cleanup_old_logs() {
    [[ -z "$ACFS_LOG_DIR" ]] && return 0
    [[ ! -d "$ACFS_LOG_DIR" ]] && return 0

    # Delete old newproj logs (older than retention days)
    find "$ACFS_LOG_DIR" -name "newproj_*.log" -type f -mtime +"$ACFS_LOG_RETENTION_DAYS" -delete 2>/dev/null || true
}

# List recent session logs
# Usage: list_recent_logs [count]
list_recent_logs() {
    local count="${1:-10}"

    if [[ -d "$ACFS_LOG_DIR" ]]; then
        find "$ACFS_LOG_DIR" -name "newproj_*.log" -type f -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn \
            | head -"$count" \
            | cut -d' ' -f2-
    fi
}

# ============================================================
# Debug Helpers
# ============================================================

# Dump current wizard state to log
# Usage: log_dump_state STATE_ARRAY
log_dump_state() {
    local -n state_ref="$1"
    local key value

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    {
        echo "[$timestamp] [DUMP ] Current wizard state:"
        for key in "${!state_ref[@]}"; do
            value="${state_ref[$key]}"
            if [[ "$key" == agents_md_custom ]]; then
                value=$(newproj_logging_state_value "$key" "$value")
            fi
            echo "    $key = '$value'"
        done
    } >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log environment snapshot (useful for debugging)
# Usage: log_env_snapshot
log_env_snapshot() {
    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    {
        echo "[$timestamp] [ENV  ] Environment snapshot:"
        echo "    PATH=${PATH:-}"
        echo "    TERM=${TERM:-unset}"
        echo "    LANG=${LANG:-unset}"
        echo "    LC_ALL=${LC_ALL:-unset}"
        echo "    HOME=${HOME:-unset}"
        echo "    PWD=${PWD:-unset}"
        echo "    ACFS_LOG_LEVEL=$ACFS_LOG_LEVEL"
    } >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log timing checkpoint
# Usage: log_checkpoint "label"
log_checkpoint() {
    local label="$1"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    echo "[$timestamp] [TIME ] Checkpoint: $label (elapsed: ${SECONDS}s)" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# ============================================================
# Verbose Mode Support
# ============================================================

# Enable verbose/debug mode
# Usage: enable_verbose
enable_verbose() {
    export ACFS_LOG_LEVEL=$ACFS_LOG_DEBUG
    log_info "Verbose mode enabled"
}

# Check if verbose mode is enabled
# Usage: if is_verbose; then ... fi
is_verbose() {
    [[ "${ACFS_LOG_LEVEL:-1}" -eq "$ACFS_LOG_DEBUG" ]]
}
