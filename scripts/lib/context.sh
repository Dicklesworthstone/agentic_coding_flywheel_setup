#!/usr/bin/env bash
# ============================================================
# ACFS Installer - Error Context Tracking Library
# Provides phase/step tracking and try_step() wrapper
# Part of EPIC: Per-Phase Error Reporting (bead qqo)
# ============================================================

# Guard against double-sourcing
if [[ -n "${ACFS_CONTEXT_LOADED:-}" ]]; then
    return 0
fi
export ACFS_CONTEXT_LOADED=1

# ============================================================
# Error Context Global Variables
# Track exactly where failures occur for debugging and resume
# ============================================================

# Current execution context
export CURRENT_PHASE=""           # e.g., "5" or "install_cli"
export CURRENT_PHASE_NAME=""      # e.g., "CLI Tools Installation"
export CURRENT_PHASE_NUMBER=0     # e.g., 5
export CURRENT_STEP=""            # e.g., "Installing ripgrep"
export CURRENT_STEP_NUMBER=0      # Step within phase

# Error tracking
export LAST_ERROR=""              # Last error message (truncated)
export LAST_ERROR_CODE=0          # Last exit code
export LAST_ERROR_OUTPUT=""       # Full error output
export LAST_ERROR_TIMESTAMP=""    # When error occurred
export LAST_ERROR_PHASE=""        # Phase where error occurred
export LAST_ERROR_STEP=""         # Step where error occurred

# Statistics
export TOTAL_STEPS_EXECUTED=0     # Count of try_step calls
export TOTAL_STEPS_FAILED=0       # Count of failures

# Configuration
export TRY_STEP_VERBOSE="${TRY_STEP_VERBOSE:-0}"  # Set to 1 for debug output
export MAX_ERROR_LENGTH=500       # Max chars to store in LAST_ERROR

# ============================================================
# JSON Escaping Helper
# ============================================================

# Escape a string for safe inclusion in JSON
# Handles: backslash, quotes, newlines, tabs, carriage returns
# Usage: escaped=$(_json_escape "$string")
_json_escape() {
    local s="$1"
    # Order matters: escape backslashes first
    s="${s//\\/\\\\}"      # \ -> \\
    s="${s//\"/\\\"}"      # " -> \"
    s="${s//$'\n'/\\n}"    # newline -> \n
    s="${s//$'\r'/\\r}"    # carriage return -> \r
    s="${s//$'\t'/\\t}"    # tab -> \t
    printf '%s' "$s"
}

# ============================================================
# Phase Management Functions
# ============================================================

# Set the current phase context
# Usage: set_phase "phase_id" "Phase Display Name" [phase_number]
set_phase() {
    local phase_id="$1"
    local phase_name="${2:-$phase_id}"
    local phase_number="${3:-0}"

    CURRENT_PHASE="$phase_id"
    CURRENT_PHASE_NAME="$phase_name"
    CURRENT_PHASE_NUMBER="$phase_number"
    CURRENT_STEP=""
    CURRENT_STEP_NUMBER=0

    if [[ "$TRY_STEP_VERBOSE" == "1" ]]; then
        echo "[CONTEXT] Phase: $phase_id ($phase_name) #$phase_number" >&2
    fi
}

# Get current phase info as JSON (for state.json)
# Usage: get_phase_json
get_phase_json() {
    # Escape JSON special characters in strings
    local escaped_phase escaped_phase_name escaped_step
    escaped_phase=$(_json_escape "$CURRENT_PHASE")
    escaped_phase_name=$(_json_escape "$CURRENT_PHASE_NAME")
    escaped_step=$(_json_escape "$CURRENT_STEP")

    cat <<EOF
{
  "phase_id": "$escaped_phase",
  "phase_name": "$escaped_phase_name",
  "phase_number": $CURRENT_PHASE_NUMBER,
  "current_step": "$escaped_step",
  "step_number": $CURRENT_STEP_NUMBER
}
EOF
}

# ============================================================
# try_step() Function
# Wrapper for individual operations within a phase
# ============================================================

# Execute a command with error tracking and context
# Usage: try_step "description" command [args...]
#
# Examples:
#   try_step "Installing ripgrep" sudo apt-get install -y ripgrep
#   try_step "Downloading script" curl -fsSL https://example.com/install.sh
#   try_step "Running installer" bash -c 'curl -fsSL url | bash'
#
# Returns: Exit code of the command (0 = success, non-zero = failure)
# Side effects:
#   - Updates CURRENT_STEP
#   - On failure: sets LAST_ERROR, LAST_ERROR_CODE, etc.
#   - Increments TOTAL_STEPS_EXECUTED
try_step() {
    local description="$1"
    shift

    # Update context
    ((CURRENT_STEP_NUMBER += 1))
    CURRENT_STEP="$description"
    ((TOTAL_STEPS_EXECUTED += 1))

    if [[ "$TRY_STEP_VERBOSE" == "1" ]]; then
        echo "[TRY_STEP] $CURRENT_PHASE/$CURRENT_STEP_NUMBER: $description" >&2
    fi

    # Create temp file for capturing output
    local temp_output
    temp_output=$(mktemp "${TMPDIR:-/tmp}/acfs_context.XXXXXX" 2>/dev/null) || temp_output="/tmp/acfs_context_output.$$"
    trap 'rm -f "$temp_output"' RETURN

    # Execute command, capturing both stdout and stderr
    local exit_code=0
    if "$@" > "$temp_output" 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi

    # Handle failure
    if [[ $exit_code -ne 0 ]]; then
        _handle_step_failure "$description" "$exit_code" "$temp_output"
    fi

    return $exit_code
}

# Execute a command string with try_step (for complex/piped commands)
# Usage: try_step_eval "description" "command string"
#
# Examples:
#   try_step_eval "Installing bun" "curl -fsSL https://bun.sh/install | bash"
#   try_step_eval "Checking status" "git status && git diff"
try_step_eval() {
    local description="$1"
    local command_str="$2"

    # Update context
    ((CURRENT_STEP_NUMBER += 1))
    CURRENT_STEP="$description"
    ((TOTAL_STEPS_EXECUTED += 1))

    if [[ "$TRY_STEP_VERBOSE" == "1" ]]; then
        echo "[TRY_STEP_EVAL] $CURRENT_PHASE/$CURRENT_STEP_NUMBER: $description" >&2
        echo "[TRY_STEP_EVAL] Command: $command_str" >&2
    fi

    # Create temp file for capturing output
    local temp_output
    temp_output=$(mktemp "${TMPDIR:-/tmp}/acfs_context.XXXXXX" 2>/dev/null) || temp_output="/tmp/acfs_context_output.$$"
    trap 'rm -f "$temp_output"' RETURN

    # Execute command string via bash -c
    local exit_code=0
    if bash -c "$command_str" > "$temp_output" 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi

    # Handle failure
    if [[ $exit_code -ne 0 ]]; then
        _handle_step_failure "$description" "$exit_code" "$temp_output"
    fi

    return $exit_code
}

# Internal: Handle step failure
# Sets all the LAST_ERROR_* variables
_handle_step_failure() {
    local description="$1"
    local exit_code="$2"
    local output_file="$3"

    ((TOTAL_STEPS_FAILED += 1))

    # Capture full output
    LAST_ERROR_OUTPUT=""
    if [[ -f "$output_file" ]]; then
        LAST_ERROR_OUTPUT=$(cat "$output_file")
    fi

    # Truncate for LAST_ERROR (keep it manageable)
    if [[ ${#LAST_ERROR_OUTPUT} -gt $MAX_ERROR_LENGTH ]]; then
        LAST_ERROR="${LAST_ERROR_OUTPUT:0:$MAX_ERROR_LENGTH}... [truncated]"
    else
        LAST_ERROR="$LAST_ERROR_OUTPUT"
    fi

    LAST_ERROR_CODE=$exit_code
    LAST_ERROR_TIMESTAMP=$(date -Iseconds)
    LAST_ERROR_PHASE="$CURRENT_PHASE"
    LAST_ERROR_STEP="$description"

    if [[ "$TRY_STEP_VERBOSE" == "1" ]]; then
        echo "[TRY_STEP] FAILED: $description (exit code $exit_code)" >&2
        echo "[TRY_STEP] Error: $LAST_ERROR" >&2
    fi
}

# ============================================================
# Error Query Functions
# ============================================================

# Check if there's a recorded error
# Usage: has_error && echo "Error occurred"
has_error() {
    [[ $LAST_ERROR_CODE -ne 0 ]]
}

# Get error info as JSON (for state.json or reporting)
# Usage: get_error_json
get_error_json() {
    # Escape JSON special characters using helper function
    local escaped_error escaped_phase escaped_step escaped_timestamp
    escaped_error=$(_json_escape "$LAST_ERROR")
    escaped_phase=$(_json_escape "$LAST_ERROR_PHASE")
    escaped_step=$(_json_escape "$LAST_ERROR_STEP")
    escaped_timestamp=$(_json_escape "$LAST_ERROR_TIMESTAMP")

    cat <<EOF
{
  "code": $LAST_ERROR_CODE,
  "message": "$escaped_error",
  "phase": "$escaped_phase",
  "step": "$escaped_step",
  "timestamp": "$escaped_timestamp"
}
EOF
}

# Get a one-line error summary
# Usage: get_error_summary
get_error_summary() {
    if has_error; then
        echo "[$LAST_ERROR_PHASE] $LAST_ERROR_STEP failed (exit $LAST_ERROR_CODE): ${LAST_ERROR:0:100}"
    else
        echo "No error"
    fi
}

# ============================================================
# Context Reset Functions
# ============================================================

# Clear all error state (e.g., after successful recovery)
# Usage: clear_error
clear_error() {
    LAST_ERROR=""
    LAST_ERROR_CODE=0
    LAST_ERROR_OUTPUT=""
    LAST_ERROR_TIMESTAMP=""
    LAST_ERROR_PHASE=""
    LAST_ERROR_STEP=""
}

# Reset all context (for testing or fresh start)
# Usage: reset_context
reset_context() {
    CURRENT_PHASE=""
    CURRENT_PHASE_NAME=""
    CURRENT_PHASE_NUMBER=0
    CURRENT_STEP=""
    CURRENT_STEP_NUMBER=0
    TOTAL_STEPS_EXECUTED=0
    TOTAL_STEPS_FAILED=0
    clear_error
}

# ============================================================
# Statistics Functions
# ============================================================

# Get execution statistics
# Usage: get_stats_json
get_stats_json() {
    cat <<EOF
{
  "total_steps": $TOTAL_STEPS_EXECUTED,
  "failed_steps": $TOTAL_STEPS_FAILED,
  "success_rate": $(awk "BEGIN {printf \"%.1f\", ($TOTAL_STEPS_EXECUTED > 0 ? ($TOTAL_STEPS_EXECUTED - $TOTAL_STEPS_FAILED) / $TOTAL_STEPS_EXECUTED * 100 : 100)}")
}
EOF
}

# Print a summary of execution
# Usage: print_context_summary
print_context_summary() {
    echo "=== Execution Context Summary ==="
    echo "Phase: $CURRENT_PHASE_NAME (#$CURRENT_PHASE_NUMBER)"
    echo "Last step: $CURRENT_STEP (#$CURRENT_STEP_NUMBER)"
    echo "Total steps: $TOTAL_STEPS_EXECUTED (failed: $TOTAL_STEPS_FAILED)"
    if has_error; then
        echo ""
        echo "Last error:"
        echo "  Phase: $LAST_ERROR_PHASE"
        echo "  Step: $LAST_ERROR_STEP"
        echo "  Code: $LAST_ERROR_CODE"
        echo "  Time: $LAST_ERROR_TIMESTAMP"
        echo "  Message: ${LAST_ERROR:0:200}"
    fi
    echo "================================="
}
