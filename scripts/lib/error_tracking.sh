#!/usr/bin/env bash
# ============================================================
# ACFS Error Tracking Library
#
# Provides error context tracking and step execution wrappers
# to capture exactly where failures occur during installation.
#
# Related beads:
#   - agentic_coding_flywheel_setup-qqo: Create error context tracking
#   - agentic_coding_flywheel_setup-fkf: EPIC: Per-Phase Error Reporting
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_ERROR_TRACKING_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_ERROR_TRACKING_SH_LOADED=1

# ============================================================
# Global Error Context Variables
# ============================================================
# These are updated as installation progresses to provide
# context when errors occur.

# Current phase being executed (e.g., "shell_setup", "cli_tools")
CURRENT_PHASE="${CURRENT_PHASE:-}"

# Human-readable name of current phase (e.g., "Shell Setup")
CURRENT_PHASE_NAME="${CURRENT_PHASE_NAME:-}"

# Current step within the phase (e.g., "Installing ripgrep")
CURRENT_STEP="${CURRENT_STEP:-}"

# Last error message captured
LAST_ERROR="${LAST_ERROR:-}"

# Exit code from last failed command
LAST_ERROR_CODE="${LAST_ERROR_CODE:-0}"

# Output captured from last failed command (truncated)
LAST_ERROR_OUTPUT="${LAST_ERROR_OUTPUT:-}"

# Timestamp when error occurred
LAST_ERROR_TIME="${LAST_ERROR_TIME:-}"

# Maximum length of error output to store (prevents huge logs)
ERROR_OUTPUT_MAX_LENGTH="${ERROR_OUTPUT_MAX_LENGTH:-2000}"
if [[ ! "$ERROR_OUTPUT_MAX_LENGTH" =~ ^[0-9]+$ ]] || [[ "$ERROR_OUTPUT_MAX_LENGTH" -lt 1 ]]; then
    ERROR_OUTPUT_MAX_LENGTH=2000
fi

# Enable/disable verbose error output
ERROR_VERBOSE="${ERROR_VERBOSE:-false}"

# ============================================================
# Phase Management
# ============================================================

# Set the current phase context
# Usage: set_phase <phase_id> [phase_name]
# Example: set_phase "cli_tools" "CLI Tools"
set_phase() {
    local phase_id="$1"
    local phase_name="${2:-$phase_id}"

    CURRENT_PHASE="$phase_id"
    CURRENT_PHASE_NAME="$phase_name"
    CURRENT_STEP=""
    LAST_ERROR=""
    LAST_ERROR_CODE=0
    LAST_ERROR_OUTPUT=""

    # Update state file if state functions are available
    if type -t state_phase_start &>/dev/null; then
        # Best-effort: state tracking requires a valid state file (and usually jq).
        # Never let state tracking abort the installer under `set -e`.
        state_phase_start "$phase_id" || true
    fi
}

# Clear phase context (call at phase completion)
# Usage: clear_phase
clear_phase() {
    local completed_phase="$CURRENT_PHASE"
    CURRENT_PHASE=""
    CURRENT_PHASE_NAME=""
    CURRENT_STEP=""

    # Update state file if state functions are available
    if [[ -n "$completed_phase" ]] && type -t state_phase_complete &>/dev/null; then
        # Best-effort: never abort phase completion on state write errors.
        state_phase_complete "$completed_phase" || true
    fi
}

# ============================================================
# Step Execution with Error Capture
# ============================================================

# Execute a command with error tracking
# Usage: try_step "description" command [args...]
# Returns: Command exit code
#
# On success: Returns 0, clears error state
# On failure: Returns exit code, sets LAST_ERROR_*, updates state
#
# Example:
#   try_step "Installing ripgrep" sudo apt-get install -y ripgrep
#   try_step "Building project" make -j4
#
try_step() {
    local description="$1"
    shift

    # Update step context
    CURRENT_STEP="$description"

    # Update state file if available
    if type -t state_step_update &>/dev/null; then
        # Best-effort: state writes can fail early (no state file yet) or if jq is missing.
        state_step_update "$description" || true
    fi

    # Log step start if logging available
    if type -t log_detail &>/dev/null; then
        log_detail "$description..."
    fi

    # Create temp file for output capture
    local output_file
    output_file=$(mktemp "${TMPDIR:-/tmp}/acfs_step.XXXXXX" 2>/dev/null) || output_file=""

    local exit_code=0

    # Execute command with output capture
    # We use process substitution to capture both stdout and stderr
    if [[ -n "$output_file" ]]; then
        if [[ "$ERROR_VERBOSE" == "true" ]]; then
            # Verbose mode: show output in real-time AND capture it
            if (
                set -o pipefail
                "$@" 2>&1 | tee "$output_file"
                # Prefer the command's exit code over tee's (output capture is best-effort).
                exit "${PIPESTATUS[0]}"
            ); then
                exit_code=0
            else
                exit_code=$?
            fi
        else
            # Normal mode: capture silently, show on error
            if "$@" > "$output_file" 2>&1; then
                exit_code=0
            else
                exit_code=$?
            fi
        fi
    else
        # If we cannot safely create a temp file, run without capture rather than
        # falling back to predictable /tmp paths (symlink attack risk under sudo/root).
        if "$@"; then
            exit_code=0
        else
            exit_code=$?
        fi
    fi

    if [[ $exit_code -eq 0 ]]; then
        # Success - clear error state
        LAST_ERROR=""
        LAST_ERROR_CODE=0
        LAST_ERROR_OUTPUT=""
        if [[ -n "$output_file" ]]; then
            rm -f "$output_file" 2>/dev/null || true
        fi
        return 0
    fi

    # Failure - capture error context
    LAST_ERROR="$description failed with exit code $exit_code"
    LAST_ERROR_CODE=$exit_code
    LAST_ERROR_TIME=$(date -Iseconds)

    # Capture and truncate output without slurping arbitrarily large logs into RAM.
    if [[ -n "$output_file" && -f "$output_file" ]]; then
        local max_len
        max_len="${ERROR_OUTPUT_MAX_LENGTH}"
        if [[ ! "$max_len" =~ ^[0-9]+$ ]] || [[ "$max_len" -lt 1 ]]; then
            max_len=2000
        fi
        local captured
        captured="$(head -c "$((max_len + 1))" "$output_file" 2>/dev/null || printf '')"

        if [[ ${#captured} -gt $max_len ]]; then
            captured="${captured:0:$max_len}"
            LAST_ERROR_OUTPUT="${captured}... [truncated]"
        else
            LAST_ERROR_OUTPUT="$captured"
        fi
    else
        LAST_ERROR_OUTPUT="(command output unavailable: mktemp failed)"
    fi

    if [[ -n "$output_file" ]]; then
        rm -f "$output_file" 2>/dev/null || true
    fi

    # Update state file with failure info
    if type -t state_phase_fail &>/dev/null; then
        state_phase_fail "$CURRENT_PHASE" "$description" "$LAST_ERROR" || true
    fi

    # Log error if logging available
    if type -t log_error &>/dev/null; then
        log_error "$description failed (exit $exit_code)"
        # Print captured output to help debug failures
        if [[ -n "$LAST_ERROR_OUTPUT" ]]; then
            echo "  Error output:" >&2
            echo "$LAST_ERROR_OUTPUT" | head -50 | sed 's/^/    /' >&2
        fi
    fi

    return "$exit_code"
}

# Execute a command string with try_step semantics (for pipelines/compound commands)
# Usage: try_step_eval "description" "command string"
try_step_eval() {
    local description="$1"
    local command_str="${2:-}"

    if [[ -z "$command_str" ]]; then
        if type -t log_error &>/dev/null; then
            log_error "try_step_eval: missing command string for: $description"
        fi
        return 1
    fi

    try_step "$description" bash -e -o pipefail -c "$command_str"
}

# Execute a command that can fail without aborting
# Usage: try_step_optional "description" command [args...]
# Returns: Command exit code (but doesn't update error state on failure)
#
# Use for non-critical steps that shouldn't stop installation
try_step_optional() {
    local description="$1"
    shift

    CURRENT_STEP="$description"

    if type -t log_detail &>/dev/null; then
        log_detail "$description (optional)..."
    fi

    local exit_code=0
    "$@" >/dev/null 2>&1 || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        if type -t log_warn &>/dev/null; then
            log_warn "$description failed (non-critical)"
        fi
    fi

    return "$exit_code"
}

# Execute a command with retry on failure
# Usage: try_step_retry <max_attempts> <delay_seconds> "description" command [args...]
# Returns: 0 on eventual success, last exit code on failure
#
# Example:
#   try_step_retry 3 5 "Downloading package" curl -fsSL https://example.com/file
#
try_step_retry() {
    local max_attempts="$1"
    local delay="$2"
    local description="$3"
    shift 3

    local attempt=1
    local exit_code=0

    while [[ $attempt -le $max_attempts ]]; do
        CURRENT_STEP="$description (attempt $attempt/$max_attempts)"

        if type -t state_step_update &>/dev/null; then
            state_step_update "$CURRENT_STEP" || true
        fi

        if [[ $attempt -gt 1 ]] && type -t log_detail &>/dev/null; then
            log_detail "Retrying $description (attempt $attempt/$max_attempts)..."
        fi

        # Execute command
        exit_code=0
        "$@" >/dev/null 2>&1 || exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            return 0
        fi

        # Don't sleep after last attempt
        if [[ $attempt -lt $max_attempts ]]; then
            sleep "$delay"
        fi

        attempt=$((attempt + 1))
    done

    # All attempts failed
    LAST_ERROR="$description failed after $max_attempts attempts"
    LAST_ERROR_CODE=$exit_code
    LAST_ERROR_TIME=$(date -Iseconds)

    if type -t state_phase_fail &>/dev/null; then
        state_phase_fail "$CURRENT_PHASE" "$description" "$LAST_ERROR" || true
    fi

    if type -t log_error &>/dev/null; then
        log_error "$description failed after $max_attempts attempts (exit $exit_code)"
    fi

    return $exit_code
}

# ============================================================
# Error Reporting
# ============================================================

# Get current error context as a formatted string
# Usage: get_error_context
# Outputs: Multi-line error context report
get_error_context() {
    if [[ -z "$LAST_ERROR" ]]; then
        echo "No error recorded"
        return 0
    fi

    echo "=== Error Context ==="
    echo "Phase: ${CURRENT_PHASE:-unknown} (${CURRENT_PHASE_NAME:-unknown})"
    echo "Step: ${CURRENT_STEP:-unknown}"
    echo "Error: $LAST_ERROR"
    echo "Exit Code: $LAST_ERROR_CODE"
    echo "Time: ${LAST_ERROR_TIME:-unknown}"

    if [[ -n "$LAST_ERROR_OUTPUT" ]]; then
        echo ""
        echo "=== Output ==="
        echo "$LAST_ERROR_OUTPUT"
    fi
}

# Get error context as JSON
# Usage: get_error_context_json
# Outputs: JSON object with error context
get_error_context_json() {
    if ! command -v jq &>/dev/null; then
        # Fallback without jq - emit valid JSON with proper escaping and nulls.
        _acfs_json_escape() {
            local s="$1"
            s="${s//\\/\\\\}"      # \ -> \\
            s="${s//\"/\\\"}"      # " -> \"
            s="${s//$'\n'/\\n}"    # newline -> \n
            s="${s//$'\r'/\\r}"    # carriage return -> \r
            s="${s//$'\t'/\\t}"    # tab -> \t
            printf '%s' "$s"
        }

        _acfs_json_string_or_null() {
            local s="${1:-}"
            if [[ -z "$s" ]]; then
                printf 'null'
                return 0
            fi
            printf '"%s"' "$(_acfs_json_escape "$s")"
        }

        local exit_code=0
        if [[ "${LAST_ERROR_CODE:-}" =~ ^[0-9]+$ ]]; then
            exit_code="$LAST_ERROR_CODE"
        fi

        printf '{\n'
        printf '  "phase": %s,\n' "$(_acfs_json_string_or_null "${CURRENT_PHASE:-}")"
        printf '  "phase_name": %s,\n' "$(_acfs_json_string_or_null "${CURRENT_PHASE_NAME:-}")"
        printf '  "step": %s,\n' "$(_acfs_json_string_or_null "${CURRENT_STEP:-}")"
        printf '  "error": %s,\n' "$(_acfs_json_string_or_null "${LAST_ERROR:-}")"
        printf '  "exit_code": %s,\n' "$exit_code"
        printf '  "time": %s,\n' "$(_acfs_json_string_or_null "${LAST_ERROR_TIME:-}")"
        printf '  "output": %s\n' "$(_acfs_json_string_or_null "${LAST_ERROR_OUTPUT:-}")"
        printf '}\n'
        return 0
    fi

    # Use jq for proper JSON encoding
    local exit_code_num=0
    if [[ "${LAST_ERROR_CODE:-}" =~ ^[0-9]+$ ]]; then
        exit_code_num="$LAST_ERROR_CODE"
    fi
    jq -n \
        --arg phase "${CURRENT_PHASE:-}" \
        --arg phase_name "${CURRENT_PHASE_NAME:-}" \
        --arg step "${CURRENT_STEP:-}" \
        --arg error "${LAST_ERROR:-}" \
        --argjson exit_code "$exit_code_num" \
        --arg time "${LAST_ERROR_TIME:-}" \
        --arg output "${LAST_ERROR_OUTPUT:-}" \
        '{
            phase: (if $phase == "" then null else $phase end),
            phase_name: (if $phase_name == "" then null else $phase_name end),
            step: (if $step == "" then null else $step end),
            error: (if $error == "" then null else $error end),
            exit_code: $exit_code,
            time: (if $time == "" then null else $time end),
            output: (if $output == "" then null else $output end)
        }'
}

# Check if there's an active error
# Usage: has_error && handle_error
# Returns: 0 if error exists, 1 if no error
has_error() {
    [[ -n "$LAST_ERROR" ]] && [[ "$LAST_ERROR_CODE" -ne 0 ]]
}

# Clear error state (use after handling an error)
# Usage: clear_error
clear_error() {
    LAST_ERROR=""
    LAST_ERROR_CODE=0
    LAST_ERROR_OUTPUT=""
    LAST_ERROR_TIME=""
}

# ============================================================
# Convenience Wrappers
# ============================================================

# Run a phase with automatic context management (lightweight version)
#
# NOTE: For full phase execution with skip logic, state tracking, and timing,
# use state.sh's run_phase() instead. This lightweight version only handles
# error context management and is NOT recommended for normal use.
#
# Usage: _run_phase_context_only <phase_id> <phase_name> <function_to_run> [args...]
# Returns: Function exit code
#
# Example:
#   _run_phase_context_only "cli_tools" "CLI Tools" install_cli_tools
#
_run_phase_context_only() {
    local phase_id="$1"
    local phase_name="$2"
    local func="$3"
    shift 3

    set_phase "$phase_id" "$phase_name"

    # Execute and capture exit code correctly
    # (can't use "if ! cmd; then exit_code=$?" because $? would be 0 from the negation)
    local exit_code=0
    "$func" "$@" || exit_code=$?

    if (( exit_code != 0 )); then
        # Error state already set by try_step calls within the function
        return "$exit_code"
    fi

    clear_phase
    return 0
}

# Check if a phase should be skipped (already completed or explicitly skipped)
# Usage: should_skip_phase <phase_id> && return 0
# Returns: 0 if should skip, 1 if should run
should_skip_phase() {
    local phase_id="$1"

    # Check state file if available
    if type -t state_should_skip_phase &>/dev/null; then
        # state_should_skip_phase is expected to return 0 (skip) or 1 (run).
        # Under `set -e`, a 1 return must not abort the caller.
        local code=0
        state_should_skip_phase "$phase_id" || code=$?
        return "$code"
    fi

    return 1  # Default: don't skip
}

# ============================================================
# Automatic Retry for Transient Network Errors
# ============================================================
# Related bead: agentic_coding_flywheel_setup-nna

# Retry delays: Immediate, then 5s, then 15s (total max wait: 20s)
# Rationale:
# - Immediate (0s): Many transient errors clear instantly (TCP reset, DNS hiccup)
# - 5s wait: Enough for most CDN/routing issues
# - 15s wait: Handles rate limiting, brief outages
RETRY_DELAYS=(0 5 15)

# Check if an error is a retryable network error
# Usage: is_retryable_error <exit_code> [stderr_output]
# Returns: 0 if retryable (should retry), 1 if not retryable
#
# Retryable curl exit codes:
#   6  - Could not resolve host (DNS failure)
#   7  - Failed to connect (server down, network issue)
#   28 - Operation timeout
#   35 - SSL connect error
#   52 - Empty reply from server
#   56 - Network receive error
#
# Non-retryable:
#   - HTTP 4xx errors (not network issues)
#   - Checksum mismatches (content verification failed)
#   - Script execution errors
#
is_retryable_error() {
    local exit_code="$1"
    local stderr="${2:-}"

    # Curl exit codes for transient network issues
    case "$exit_code" in
        6)  return 0 ;;  # Could not resolve host
        7)  return 0 ;;  # Failed to connect to host
        28) return 0 ;;  # Operation timeout
        35) return 0 ;;  # SSL connect error
        52) return 0 ;;  # Empty reply from server
        56) return 0 ;;  # Network receive error
    esac

    # Check stderr for common transient messages
    if [[ -n "$stderr" ]]; then
        # Lowercase comparison
        local stderr_lower="${stderr,,}"
        if [[ "$stderr_lower" =~ (timeout|timed.out|connection.refused|temporarily.unavailable|network.unreachable|no.route.to.host|reset.by.peer) ]]; then
            return 0
        fi
    fi

    return 1  # Not retryable
}

# Execute a command with exponential backoff retry for transient errors
# Usage: retry_with_backoff "description" command [args...]
# Returns: 0 on success, last exit code on failure after all retries
#
# Features:
# - Only retries if is_retryable_error() returns true
# - Uses RETRY_DELAYS array for backoff timing
# - Captures stderr to determine if error is retryable
# - Clear logging of retry attempts
#
# Example:
#   retry_with_backoff "Fetching installer script" curl -fsSL https://example.com/install.sh
#
retry_with_backoff() {
    local description="$1"
    shift

    local max_attempts=${#RETRY_DELAYS[@]}
    local exit_code=0
    local stderr_file
    local stdout_file
    local stderr_content=""

    stderr_file=$(mktemp "${TMPDIR:-/tmp}/acfs_retry_stderr.XXXXXX" 2>/dev/null) || stderr_file=""
    stdout_file=$(mktemp "${TMPDIR:-/tmp}/acfs_retry_stdout.XXXXXX" 2>/dev/null) || stdout_file=""

    local use_temp_files="true"
    if [[ -z "$stderr_file" || -z "$stdout_file" ]]; then
        use_temp_files="false"
        # Best-effort cleanup if only one temp file was created.
        [[ -n "$stderr_file" ]] && rm -f -- "$stderr_file" 2>/dev/null || true
        [[ -n "$stdout_file" ]] && rm -f -- "$stdout_file" 2>/dev/null || true
        stderr_file=""
        stdout_file=""
    fi

    for ((attempt=0; attempt < max_attempts; attempt++)); do
        local delay=${RETRY_DELAYS[$attempt]}

        # Wait before retry (except first attempt)
        if ((attempt > 0)); then
            if type -t log_info &>/dev/null; then
                log_info "Retry $attempt/$((max_attempts-1)) for $description (waited ${delay}s)..."
            else
                echo "  [retry] Attempt $((attempt+1))/$max_attempts for $description (waited ${delay}s)..." >&2
            fi
            sleep "$delay"
        fi

        stderr_content=""
        if [[ "$use_temp_files" == "true" ]]; then
            # Execute command, capturing stdout and stderr separately
            if "$@" > "$stdout_file" 2> "$stderr_file"; then
                exit_code=0
            else
                exit_code=$?
            fi
            stderr_content="$(head -c "$((ERROR_OUTPUT_MAX_LENGTH + 1))" "$stderr_file" 2>/dev/null || printf '')"
            if [[ ${#stderr_content} -gt $ERROR_OUTPUT_MAX_LENGTH ]]; then
                stderr_content="${stderr_content:0:$ERROR_OUTPUT_MAX_LENGTH}"
            fi
        else
            # Fallback: capture combined output in-memory.
            #
            # This is only used if mktemp fails; we avoid predictable /tmp paths.
            # Output is only emitted on success to preserve the usual quiet-on-failure behavior.
            local combined_output=""
            exit_code=0
            combined_output="$("$@" 2>&1)" || exit_code=$?
            stderr_content="$combined_output"

            if [[ $exit_code -eq 0 ]]; then
                if ((attempt > 0)); then
                    if type -t log_info &>/dev/null; then
                        log_info "$description succeeded on retry $attempt"
                    else
                        echo "  [retry] $description succeeded on retry $attempt" >&2
                    fi
                fi
                printf '%s' "$combined_output"
                return 0
            fi
        fi

        if [[ $exit_code -eq 0 ]]; then
            # Success
            if ((attempt > 0)); then
                if type -t log_info &>/dev/null; then
                    log_info "$description succeeded on retry $attempt"
                else
                    echo "  [retry] $description succeeded on retry $attempt" >&2
                fi
            fi
            # Output the captured stdout
            cat "$stdout_file"
            rm -f -- "$stderr_file" "$stdout_file" 2>/dev/null || true
            return 0
        fi

        # Check if error is retryable
        if ! is_retryable_error "$exit_code" "$stderr_content"; then
            # Not a transient network error - don't retry
            if type -t log_warn &>/dev/null; then
                log_warn "$description failed with non-retryable error (exit $exit_code)"
            else
                echo "  [retry] $description failed with non-retryable error (exit $exit_code)" >&2
            fi
            # Set error context for callers (e.g. try_step_with_backoff)
            LAST_ERROR="$description failed with non-retryable error (exit $exit_code)"
            LAST_ERROR_CODE=$exit_code
            LAST_ERROR_TIME=$(date -Iseconds)
            if [[ "$use_temp_files" == "true" ]]; then
                local captured
                captured="$(head -c "$((ERROR_OUTPUT_MAX_LENGTH + 1))" "$stderr_file" 2>/dev/null || printf '')"
                if [[ ${#captured} -gt $ERROR_OUTPUT_MAX_LENGTH ]]; then
                    captured="${captured:0:$ERROR_OUTPUT_MAX_LENGTH}"
                    LAST_ERROR_OUTPUT="${captured}... [truncated]"
                else
                    LAST_ERROR_OUTPUT="$captured"
                fi
            else
                LAST_ERROR_OUTPUT="$stderr_content"
            fi
            # Output stderr for debugging
            if [[ -n "$stderr_content" ]]; then
                echo "$stderr_content" >&2
            fi
            if [[ "$use_temp_files" == "true" ]]; then
                rm -f -- "$stderr_file" "$stdout_file" 2>/dev/null || true
            fi
            return "$exit_code"
        fi

        # Retryable error - will loop and retry (unless this was last attempt)
        if ((attempt == max_attempts - 1)); then
            # Last attempt failed
            if type -t log_warn &>/dev/null; then
                log_warn "$description failed on final attempt (exit $exit_code)"
            fi
        fi
    done

    # All attempts exhausted
    if type -t log_error &>/dev/null; then
        log_error "$description failed after $max_attempts attempts (exit $exit_code)"
    else
        echo "  [retry] $description failed after $max_attempts attempts (exit $exit_code)" >&2
    fi

    # Set error context
    LAST_ERROR="$description failed after $max_attempts retry attempts"
    LAST_ERROR_CODE=$exit_code
    LAST_ERROR_TIME=$(date -Iseconds)
    if [[ "$use_temp_files" == "true" ]]; then
        local captured
        captured="$(head -c "$((ERROR_OUTPUT_MAX_LENGTH + 1))" "$stderr_file" 2>/dev/null || printf '')"
        if [[ ${#captured} -gt $ERROR_OUTPUT_MAX_LENGTH ]]; then
            captured="${captured:0:$ERROR_OUTPUT_MAX_LENGTH}"
            LAST_ERROR_OUTPUT="${captured}... [truncated]"
        else
            LAST_ERROR_OUTPUT="$captured"
        fi
    else
        LAST_ERROR_OUTPUT="$stderr_content"
    fi

    if [[ "$use_temp_files" == "true" ]]; then
        rm -f -- "$stderr_file" "$stdout_file" 2>/dev/null || true
    fi
    return "$exit_code"
}

# Wrapper that combines retry with step tracking
# Usage: try_step_with_backoff "description" command [args...]
# Returns: 0 on success, exit code on failure
#
# This is like try_step but uses retry_with_backoff for transient errors
#
try_step_with_backoff() {
    local description="$1"
    shift

    # Update step context
    CURRENT_STEP="$description"

    if type -t state_step_update &>/dev/null; then
        state_step_update "$description" || true
    fi

    if type -t log_detail &>/dev/null; then
        log_detail "$description..."
    fi

    local exit_code=0
    if retry_with_backoff "$description" "$@"; then
        # Success
        LAST_ERROR=""
        LAST_ERROR_CODE=0
        LAST_ERROR_OUTPUT=""
        return 0
    fi
    exit_code=$?

    # Failure - error context already set by retry_with_backoff
    if type -t state_phase_fail &>/dev/null; then
        state_phase_fail "$CURRENT_PHASE" "$description" "$LAST_ERROR" || true
    fi

    return "$exit_code"
}

# Fetch URL with automatic retry for transient errors
# Usage: fetch_with_retry <url> [curl_options...]
# Returns: 0 on success (outputs content to stdout), exit code on failure
#
# Example:
#   script_content=$(fetch_with_retry "https://example.com/install.sh") || exit 1
#   echo "$script_content" | bash
#
fetch_with_retry() {
    local url="$1"
    shift

    local -a curl_args=(-fsSL)
    if command -v curl &>/dev/null && curl --help all 2>/dev/null | grep -q -- '--proto'; then
        curl_args=(--proto '=https' --proto-redir '=https' -fsSL)
    fi

    retry_with_backoff "Fetching $url" curl "${curl_args[@]}" "$@" "$url"
}
