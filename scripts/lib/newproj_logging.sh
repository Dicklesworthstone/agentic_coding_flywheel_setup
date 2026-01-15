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

# Log directory (XDG compliant)
export ACFS_LOG_DIR="${ACFS_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/acfs/logs}"

# Session log file (set by init_logging)
export ACFS_SESSION_LOG=""

# Version file location
ACFS_VERSION_FILE="${ACFS_VERSION_FILE:-/etc/acfs/VERSION}"

# Log retention in days
ACFS_LOG_RETENTION_DAYS="${ACFS_LOG_RETENTION_DAYS:-7}"

# ============================================================
# Initialization
# ============================================================

# Initialize logging - call at start of wizard
# Usage: init_logging [--verbose]
init_logging() {
    local verbose=false

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

    # Create log directory
    mkdir -p "$ACFS_LOG_DIR" 2>/dev/null || {
        echo "Warning: Could not create log directory $ACFS_LOG_DIR" >&2
        ACFS_LOG_DIR="/tmp"
    }

    # Generate session log filename with timestamp and PID for uniqueness
    ACFS_SESSION_LOG="$ACFS_LOG_DIR/newproj_$(date +%Y%m%d_%H%M%S)_$$.log"
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
        echo "Home: $HOME"
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

# Log state changes (always logged regardless of level)
# Usage: log_state "key" "old_value" "new_value"
log_state() {
    local key="$1"
    local old_value="$2"
    local new_value="$3"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    echo "[$timestamp] [STATE] $key: '$old_value' -> '$new_value'" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log screen transitions
# Usage: log_screen "ENTER|EXIT|RENDER" "screen_name"
log_screen() {
    local action="$1"  # ENTER, EXIT, RENDER
    local screen="$2"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    echo "[$timestamp] [SCRN ] $action: $screen" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
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
    # Note: Use 'I' flag for case-insensitive matching in GNU sed (not 'i')
    sanitized=$(echo "$sanitized" | sed -E 's/(sk[-_]|api[-_]?key|token|password|secret)[^[:space:]]*/\1***/gI')

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    echo "[$timestamp] [INPUT] $field: '$sanitized'" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
}

# Log key press events
# Usage: log_key "ENTER|ESC|UP|DOWN|key"
log_key() {
    local key="$1"

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    echo "[$timestamp] [KEY  ] $key" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
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

    echo "[$timestamp] [VALID] $msg" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
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

    echo "[$timestamp] [FILE ] $operation: $path ($status)" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
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

    echo "[$timestamp] [CMD  ] $short_cmd -> $status" >> "$ACFS_SESSION_LOG" 2>/dev/null || true
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
        echo "$json" | sed 's/^/    /'
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

    [[ -z "$ACFS_SESSION_LOG" ]] && return 0

    local timestamp
    timestamp=$(date +"%H:%M:%S.%3N" 2>/dev/null || date +"%H:%M:%S")

    {
        echo "[$timestamp] [DUMP ] Current wizard state:"
        for key in "${!state_ref[@]}"; do
            echo "    $key = '${state_ref[$key]}'"
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
        echo "    PATH=${PATH:0:200}..."
        echo "    TERM=$TERM"
        echo "    LANG=$LANG"
        echo "    LC_ALL=${LC_ALL:-unset}"
        echo "    HOME=$HOME"
        echo "    PWD=$PWD"
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
