#!/usr/bin/env bash
# ============================================================
# ACFS State Management Library
#
# Provides phase-granular progress persistence with stable phase IDs.
# Implements state.json v2 schema for robust resume capability.
#
# Schema Version History:
#   v1: Used numeric phase array [1, 2, 3, ...] (legacy, install.sh inline)
#   v2: Uses stable phase IDs ["user_setup", "filesystem", ...] (this module)
#
# Related beads:
#   - agentic_coding_flywheel_setup-5zt: Design state.json v2 schema
#   - agentic_coding_flywheel_setup-uxc: Implement init_state() and save_state()
#   - agentic_coding_flywheel_setup-aa1: Implement atomic state file writes
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_STATE_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_STATE_SH_LOADED=1

# ============================================================
# State File Schema v2 Documentation
# ============================================================
#
# {
#   "schema_version": 2,                      # Schema version for compatibility
#   "version": "0.1.0",                       # ACFS version that created this state
#   "mode": "vibe",                           # Installation mode (vibe|safe)
#   "started_at": "2025-01-15T10:30:00Z",     # When installation started
#   "last_updated": "2025-01-15T10:42:00Z",   # Last state update timestamp
#   "completed_phases": ["user_setup", ...],  # Phases that completed successfully
#   "current_phase": "cli_tools",             # Phase currently in progress (null if idle)
#   "current_step": "Installing ripgrep",     # Step within current phase (null if idle)
#   "failed_phase": null,                     # Phase where failure occurred (null if no failure)
#   "failed_step": null,                      # Step where failure occurred (null if no failure)
#   "failed_error": null,                     # Error message from failure (null if no failure)
#   "skipped_tools": ["ntm", "bv"],           # Tools user chose to skip
#   "skipped_phases": ["postgres", "vault"],  # Phases user chose to skip
#   "phase_durations": {                      # Timing data (seconds per phase)
#     "user_setup": 12,
#     "apt_packages": 45
#   },
#   "target_user": "ubuntu",                  # User ACFS is installing for
#   "skip_postgres": false,                   # CLI flag values for reference
#   "skip_vault": false,
#   "skip_cloud": false
# }
#
# Design Decision: Track Phase IDs, Not Numbers
# ---------------------------------------------
# Problem: If we store completed_phases: [1, 2, 3, 4, 5] and later ACFS
# reorders phases or adds a new phase 3, the resume logic would skip
# the wrong phases.
#
# Solution: Use stable string identifiers that never change meaning.
# If we rename a phase, we update the ID mapping, not the stored data.
#
# ============================================================

# ============================================================
# Phase ID Constants
# ============================================================
# These IDs are stable identifiers that should never change meaning.
# Order may change, but the ID always refers to the same logical phase.
#
# Mapping from current install.sh phase numbers to stable IDs:
#   Phase 1: User normalization    → user_setup
#   Phase 2: Filesystem setup      → filesystem
#   Phase 3: Shell setup           → shell_setup
#   Phase 4: CLI tools             → cli_tools
#   Phase 5: Language runtimes     → languages
#   Phase 6: Coding agents         → agents
#   Phase 7: Cloud & database      → cloud_db
#   Phase 8: Dicklesworthstone     → stack
#   Phase 9: Final wiring          → finalize

# Canonical ordered list of phase IDs (defines execution order)
readonly ACFS_PHASE_IDS=(
    "user_setup"
    "filesystem"
    "shell_setup"
    "cli_tools"
    "languages"
    "agents"
    "cloud_db"
    "stack"
    "finalize"
)

# Human-readable phase names for display
# Note: Must use -g for global scope when sourced from inside a function
declare -gA ACFS_PHASE_NAMES=(
    [user_setup]="User Normalization"
    [filesystem]="Filesystem Setup"
    [shell_setup]="Shell Setup"
    [cli_tools]="CLI Tools"
    [languages]="Language Runtimes"
    [agents]="Coding Agents"
    [cloud_db]="Cloud & Database Tools"
    [stack]="Dicklesworthstone Stack"
    [finalize]="Final Wiring"
)

# Current schema version
# v2: Stable phase IDs (original)
# v3: Added ubuntu_upgrade section for multi-reboot upgrade tracking
readonly ACFS_STATE_SCHEMA_VERSION=3

# ============================================================
# State File Location
# ============================================================
# ACFS_STATE_FILE should be set by the caller (typically install.sh)
# Default location: ~/.acfs/state.json

state_get_file() {
    echo "${ACFS_STATE_FILE:-${ACFS_HOME:-$HOME/.acfs}/state.json}"
}

# ============================================================
# State File Operations
# ============================================================

# Initialize a new state file with default values
# Usage: state_init
# Returns: 0 on success, 1 on failure
state_init() {
    local state_file
    state_file="$(state_get_file)"

    local state_dir
    state_dir="$(dirname "$state_file")"

    # Ensure directory exists
    if [[ ! -d "$state_dir" ]]; then
        mkdir -p "$state_dir" || return 1
    fi

    local now
    now="$(date -Iseconds)"

    # Create initial state JSON
    local initial_state
    initial_state=$(cat <<EOF
{
  "schema_version": ${ACFS_STATE_SCHEMA_VERSION},
  "version": "${ACFS_VERSION:-0.1.0}",
  "mode": "${MODE:-vibe}",
  "started_at": "${now}",
  "last_updated": "${now}",
  "completed_phases": [],
  "current_phase": null,
  "current_step": null,
  "failed_phase": null,
  "failed_step": null,
  "failed_error": null,
  "skipped_tools": [],
  "skipped_phases": [],
  "phase_durations": {},
  "target_user": "${TARGET_USER:-ubuntu}",
  "skip_postgres": ${SKIP_POSTGRES:-false},
  "skip_vault": ${SKIP_VAULT:-false},
  "skip_cloud": ${SKIP_CLOUD:-false}
}
EOF
)

    # Write atomically (beads-aa1: atomic writes)
    state_write_atomic "$state_file" "$initial_state"
}

# Write state file atomically using temp file + rename
#
# This implements the atomic write pattern to prevent corruption:
#   1. Write to a temp file in the same directory
#   2. Sync to disk (flush filesystem buffers)
#   3. Rename temp file to target (atomic on POSIX filesystems)
#
# If the system crashes or SSH disconnects mid-write, the state file
# remains valid because the rename either completes fully or not at all.
#
# Usage: state_write_atomic <file_path> <content>
#
# Returns:
#   0 - Success
#   1 - Disk full or write error
#   2 - Permission denied
#   3 - Invalid arguments
#
# Related: agentic_coding_flywheel_setup-aa1
state_write_atomic() {
    local file_path="$1"
    local content="$2"
    local temp_file
    local target_dir

    # Validate arguments
    if [[ -z "$file_path" ]]; then
        declare -f log_error &>/dev/null && log_error "state_write_atomic: file path required"
        return 3
    fi
    if [[ -z "$content" ]]; then
        declare -f log_error &>/dev/null && log_error "state_write_atomic: content required"
        return 3
    fi

    target_dir="$(dirname "$file_path")"

    # Ensure target directory exists
    if [[ ! -d "$target_dir" ]]; then
        if ! mkdir -p "$target_dir" 2>/dev/null; then
            declare -f log_error &>/dev/null && log_error "state_write_atomic: cannot create directory $target_dir"
            return 2
        fi
    fi

    # Check disk space before attempting write (require at least 1MB free)
    local available_kb
    # Use -P for POSIX portability (prevents line wrapping on long device names)
    # Use -k for 1K blocks
    available_kb=$(df -kP "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -n "$available_kb" ]] && [[ "$available_kb" -lt 1024 ]]; then
        declare -f log_error &>/dev/null && log_error "state_write_atomic: insufficient disk space (${available_kb}KB available, 1024KB minimum)"
        return 1
    fi

    # Create temp file in same directory (ensures same filesystem for atomic rename)
    # Use mktemp with template for unique, secure temp file
    temp_file="$(mktemp "${target_dir}/.state.XXXXXX.tmp" 2>/dev/null)" || {
        # Fallback to PID-based naming if mktemp fails
        temp_file="${file_path}.tmp.$$.$RANDOM"
    }

    # Write content to temp file
    # Using printf for more reliable output than echo
    if ! printf '%s\n' "$content" > "$temp_file" 2>/dev/null; then
        local write_err=$?
        rm -f "$temp_file" 2>/dev/null

        # Detect disk full condition
        # ENOSPC is error code 28, but bash may not preserve it
        if [[ $write_err -ne 0 ]]; then
            # Check if we can write a small test file
            if ! echo "test" > "${target_dir}/.disktest.$$" 2>/dev/null; then
                rm -f "${target_dir}/.disktest.$$" 2>/dev/null
                declare -f log_error &>/dev/null && log_error "state_write_atomic: disk full or write error"
                return 1
            fi
            rm -f "${target_dir}/.disktest.$$" 2>/dev/null
        fi

        declare -f log_error &>/dev/null && log_error "state_write_atomic: failed to write temp file"
        return 1
    fi

    # Sync temp file to disk before rename for durability
    # This ensures data reaches the physical disk, not just OS buffers
    if command -v sync &>/dev/null; then
        # Try to sync just this file (Linux-specific), fall back to global sync
        sync "$temp_file" 2>/dev/null || sync 2>/dev/null || true
    fi

    # Set appropriate permissions before moving (readable by user, readable by group/others)
    chmod 644 "$temp_file" 2>/dev/null || true

    # Atomic rename: on POSIX filesystems, rename() is guaranteed atomic
    # when source and target are on the same filesystem
    if ! mv -f "$temp_file" "$file_path" 2>/dev/null; then
        local mv_err=$?
        rm -f "$temp_file" 2>/dev/null

        # Check for permission issues
        if [[ ! -w "$target_dir" ]] || [[ -f "$file_path" && ! -w "$file_path" ]]; then
            declare -f log_error &>/dev/null && log_error "state_write_atomic: permission denied on $file_path"
            return 2
        fi

        declare -f log_error &>/dev/null && log_error "state_write_atomic: atomic rename failed (error $mv_err)"
        return 1
    fi

    # Optional: sync the directory entry to ensure the rename is durable
    if command -v sync &>/dev/null; then
        sync "$target_dir" 2>/dev/null || true
    fi

    return 0
}

# Load existing state file
# Usage: state_load
# Outputs: JSON content to stdout
# Returns: 0 on success, 1 if file doesn't exist or is invalid
state_load() {
    local state_file
    state_file="$(state_get_file)"

    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    # Read and validate JSON
    local content
    if ! content=$(cat "$state_file" 2>/dev/null); then
        return 1
    fi

    # Basic JSON validation
    if command -v jq &>/dev/null; then
        if ! printf '%s' "$content" | jq empty >/dev/null 2>&1; then
            return 1
        fi
    else
        # Trim leading/trailing whitespace and ensure it looks like JSON object
        local trimmed
        trimmed="$(printf '%s' "$content" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        if [[ -z "$trimmed" ]] || [[ "${trimmed:0:1}" != "{" ]] || [[ "${trimmed: -1}" != "}" ]]; then
            return 1
        fi
    fi

    echo "$content"
}

# Get a value from state using jq
# Usage: state_get <key>
# Example: state_get ".current_phase"
# Returns: 0 and prints value, or 1 if not found
state_get() {
    local key="$1"
    local state

    if ! state=$(state_load); then
        return 1
    fi

    # Use jq if available, fallback to grep-based extraction
    if command -v jq &>/dev/null; then
        echo "$state" | jq -r "$key // empty"
    else
        # Basic fallback for simple keys (no nested paths)
        # This is a simplified parser - prefer having jq installed
        local simple_key="${key#.}"
        echo "$state" | grep -oP "\"${simple_key}\"\s*:\s*\K[^,}]+" | tr -d '"' | head -1
    fi
}

# Save/update the state file
# Usage: state_save <json_content>
# Returns: 0 on success, 1 on failure
state_save() {
    local content="$1"
    local state_file
    state_file="$(state_get_file)"

    # Update last_updated timestamp
    if command -v jq &>/dev/null; then
        local now
        now="$(date -Iseconds)"
        content=$(echo "$content" | jq --arg ts "$now" '.last_updated = $ts')
    fi

    state_write_atomic "$state_file" "$content"
}

# Update specific fields in state
# Usage: state_update <jq_expression>
# Example: state_update '.current_phase = "cli_tools"'
# Returns: 0 on success, 1 on failure
state_update() {
    local jq_expr="$1"

    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required for state_update" >&2
        return 1
    fi

    local state
    if ! state=$(state_load); then
        return 1
    fi

    local new_state
    if ! new_state=$(echo "$state" | jq "$jq_expr"); then
        return 1
    fi

    state_save "$new_state"
}

# ============================================================
# Phase Lifecycle Functions
# ============================================================

# Mark a phase as starting
# Usage: state_phase_start <phase_id> [step_description]
state_phase_start() {
    local phase_id="$1"
    local step="${2:-}"

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    # Use jq --arg to safely handle steps with quotes/backslashes.
    local state
    state=$(state_load) || return 1

    local start_time
    start_time=$(date +%s)

    local new_state
    if [[ -n "$step" ]]; then
        new_state=$(echo "$state" | jq --arg phase "$phase_id" --arg step "$step" --argjson start "$start_time" '
            .current_phase = $phase |
            .current_step = $step |
            .phase_start_time = $start
        ') || return 1
    else
        new_state=$(echo "$state" | jq --arg phase "$phase_id" --argjson start "$start_time" '
            .current_phase = $phase |
            .current_step = null |
            .phase_start_time = $start
        ') || return 1
    fi

    state_save "$new_state"
}

# Update the current step within a phase
# Usage: state_step_update <step_description>
state_step_update() {
    local step="$1"

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    # Use jq's --arg for proper JSON escaping
    local state
    state=$(state_load) || return 1

    local new_state
    new_state=$(echo "$state" | jq --arg step "$step" '.current_step = $step')

    state_save "$new_state"
}

# Mark a phase as completed
# Usage: state_phase_complete <phase_id>
state_phase_complete() {
    local phase_id="$1"

    if command -v jq &>/dev/null; then
        local state
        state=$(state_load) || return 1

        # Calculate duration if start time was recorded
        local start_time duration
        start_time=$(echo "$state" | jq -r '.phase_start_time // empty')
        if [[ -n "$start_time" ]]; then
            duration=$(($(date +%s) - start_time))
        else
            duration=0
        fi

        # Add phase to completed list, record duration, clear current
        local new_state
        new_state=$(echo "$state" | jq --arg phase "$phase_id" --argjson dur "$duration" '
            .completed_phases = ((.completed_phases // []) + [$phase] | unique) |
            .phase_durations[$phase] = $dur |
            .current_phase = null |
            .current_step = null |
            del(.phase_start_time)
        ')

        state_save "$new_state"
    fi
}

# Mark a phase as failed
# Usage: state_phase_fail <phase_id> <step> <error_message>
state_phase_fail() {
    local phase_id="$1"
    local step="$2"
    local error="$3"

    if command -v jq &>/dev/null; then
        # Use jq's --arg for proper JSON escaping (handles quotes, backslashes, newlines)
        local state
        state=$(state_load) || return 1

        local new_state
        new_state=$(echo "$state" | jq \
            --arg phase "$phase_id" \
            --arg step "$step" \
            --arg err "$error" '
            .failed_phase = $phase |
            .failed_step = $step |
            .failed_error = $err |
            .current_phase = null |
            .current_step = null
        ')

        state_save "$new_state"
    fi
}

# Mark a phase as skipped
# Usage: state_phase_skip <phase_id>
state_phase_skip() {
    local phase_id="$1"

    if command -v jq &>/dev/null; then
        state_update ".skipped_phases = ((.skipped_phases // []) + [\"$phase_id\"] | unique)"
    fi
}

# Mark a tool as skipped
# Usage: state_tool_skip <tool_name>
state_tool_skip() {
    local tool="$1"

    if command -v jq &>/dev/null; then
        state_update ".skipped_tools = ((.skipped_tools // []) + [\"$tool\"] | unique)"
    fi
}

# ============================================================
# Query Functions
# ============================================================

# Check if a phase has been completed
# Usage: state_is_phase_completed <phase_id>
# Returns: 0 if completed, 1 if not
state_is_phase_completed() {
    local phase_id="$1"
    local completed

    if ! completed=$(state_get ".completed_phases"); then
        return 1
    fi

    # Check if phase_id is in the completed list
    if command -v jq &>/dev/null; then
        local state
        state=$(state_load) || return 1
        echo "$state" | jq -e --arg phase "$phase_id" '.completed_phases | index($phase) != null' &>/dev/null
    else
        [[ "$completed" == *"$phase_id"* ]]
    fi
}

# Check if a phase should be skipped
# Usage: state_should_skip_phase <phase_id>
# Returns: 0 if should skip, 1 if should run
state_should_skip_phase() {
    local phase_id="$1"

    # Skip if already completed
    if state_is_phase_completed "$phase_id"; then
        return 0
    fi

    # Skip if in skipped_phases
    if command -v jq &>/dev/null; then
        local state
        state=$(state_load) || return 1
        echo "$state" | jq -e --arg phase "$phase_id" '.skipped_phases | index($phase) != null' &>/dev/null
        return $?
    fi

    return 1
}

# Get list of phases that still need to run
# Usage: state_get_pending_phases
# Outputs: One phase ID per line
state_get_pending_phases() {
    for phase_id in "${ACFS_PHASE_IDS[@]}"; do
        if ! state_should_skip_phase "$phase_id"; then
            echo "$phase_id"
        fi
    done
}

# Get the phase where installation failed (if any)
# Usage: state_get_failed_phase
# Outputs: Phase ID or empty
state_get_failed_phase() {
    state_get ".failed_phase"
}

# ============================================================
# State Validation
# ============================================================
# Validates state files to handle corruption and incompatibility.
# Related beads: agentic_coding_flywheel_setup-d09

# Validate state file structure and content
# Usage: state_validate
# Returns:
#   0 - Valid state file
#   1 - File doesn't exist (fresh install)
#   2 - Corrupted JSON (cannot parse)
#   3 - Missing required fields
#   4 - Unknown/future schema version
#   5 - Legacy v1 schema (needs migration decision)
state_validate() {
    local state_file
    state_file="$(state_get_file)"

    # Case 1: No state file exists - fresh install
    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    # Case 2: Check if file is empty or unreadable
    if [[ ! -s "$state_file" ]] || [[ ! -r "$state_file" ]]; then
        echo "State file is empty or unreadable: $state_file" >&2
        return 2
    fi

    # Case 3: Check JSON syntax
    local content
    if ! content=$(cat "$state_file" 2>/dev/null); then
        echo "Cannot read state file: $state_file" >&2
        return 2
    fi

    # Basic JSON validation - check for proper structure
    # (not just matching braces, but actual JSON parse if jq available)
    if command -v jq &>/dev/null; then
        if ! echo "$content" | jq empty 2>/dev/null; then
            echo "Corrupted JSON in state file: $state_file" >&2
            return 2
        fi

        # Get schema version
        local version
        version=$(echo "$content" | jq -r '.schema_version // empty')

        # Case 5: Legacy v1 (no schema_version or schema_version=1)
        if [[ -z "$version" ]] || [[ "$version" == "1" ]]; then
            echo "Legacy v1 state file detected" >&2
            return 5
        fi

        # Case 4: Future schema version
        if [[ "$version" -gt "$ACFS_STATE_SCHEMA_VERSION" ]]; then
            echo "State file has newer schema (v$version) than supported (v$ACFS_STATE_SCHEMA_VERSION)" >&2
            return 4
        fi

        # v2 is acceptable (will be auto-upgraded to v3 on next write)
        # v3 is current

        # Case 3: Check required fields for v2
        local has_version has_mode has_completed
        has_version=$(echo "$content" | jq -r 'has("version")')
        has_mode=$(echo "$content" | jq -r 'has("mode")')
        has_completed=$(echo "$content" | jq -r 'has("completed_phases")')

        if [[ "$has_version" != "true" ]] || [[ "$has_mode" != "true" ]] || [[ "$has_completed" != "true" ]]; then
            echo "State file missing required fields (version, mode, completed_phases)" >&2
            return 3
        fi

        # Validate completed_phases is an array
        local is_array
        is_array=$(echo "$content" | jq -r '.completed_phases | type == "array"')
        if [[ "$is_array" != "true" ]]; then
            echo "State file has invalid completed_phases (not an array)" >&2
            return 3
        fi

    else
        # Basic fallback without jq - just check for opening/closing braces
        if [[ ! "$content" =~ ^\{.*\}$ ]]; then
            echo "State file is not valid JSON (no jq available for detailed check)" >&2
            return 2
        fi

        # Check for schema_version field
        if ! grep -q '"schema_version"' "$state_file"; then
            echo "Legacy v1 state file detected (no schema_version)" >&2
            return 5
        fi

        # Extract version number
        local version
        version=$(grep -oP '"schema_version"\s*:\s*\K[0-9]+' "$state_file" || echo "")
        if [[ -z "$version" ]] || [[ "$version" == "1" ]]; then
            return 5
        fi
        if [[ "$version" -gt "$ACFS_STATE_SCHEMA_VERSION" ]]; then
            return 4
        fi
    fi

    return 0
}

# Handle invalid state file with user interaction
# Usage: state_handle_invalid <validation_code>
# Returns: 0 if handled (fresh start), 1 if should abort
state_handle_invalid() {
    local code="$1"
    local state_file
    state_file="$(state_get_file)"

    case "$code" in
        1)
            # No state file - nothing to handle
            return 0
            ;;
        2)
            # Corrupted JSON
            echo ""
            echo "WARNING: The installation state file is corrupted."
            echo "File: $state_file"
            echo ""
            echo "Options:"
            echo "  1. Start fresh (backup and remove corrupted file)"
            echo "  2. Abort and investigate"
            echo ""

            # In non-interactive mode (YES_MODE), default to fresh start
            if [[ "${YES_MODE:-false}" == "true" ]]; then
                echo "Non-interactive mode: starting fresh install"
                state_backup_and_remove
                return 0
            fi

            read -r -p "Start fresh? [Y/n] " response
            if [[ "$response" =~ ^[Nn] ]]; then
                return 1
            fi
            state_backup_and_remove
            return 0
            ;;
        3)
            # Missing required fields
            echo ""
            echo "WARNING: State file is missing required fields."
            echo "File: $state_file"
            echo ""
            echo "This may be from a very old or manually edited install."
            echo ""

            if [[ "${YES_MODE:-false}" == "true" ]]; then
                echo "Non-interactive mode: starting fresh install"
                state_backup_and_remove
                return 0
            fi

            read -r -p "Start fresh install? [Y/n] " response
            if [[ "$response" =~ ^[Nn] ]]; then
                return 1
            fi
            state_backup_and_remove
            return 0
            ;;
        4)
            # Future schema version
            echo ""
            echo "WARNING: State file uses a newer schema version."
            echo "File: $state_file"
            echo ""
            echo "This ACFS version may be older than the one that created this state."
            echo "Consider upgrading ACFS or starting fresh."
            echo ""

            if [[ "${YES_MODE:-false}" == "true" ]]; then
                echo "Non-interactive mode: starting fresh install"
                state_backup_and_remove
                return 0
            fi

            read -r -p "Start fresh install? [Y/n] " response
            if [[ "$response" =~ ^[Nn] ]]; then
                return 1
            fi
            state_backup_and_remove
            return 0
            ;;
        5)
            # Legacy v1 schema
            echo ""
            echo "Found state file from previous ACFS version (v1 schema)."
            echo "File: $state_file"
            echo ""

            if command -v jq &>/dev/null; then
                echo "Options:"
                echo "  1. Migrate state to v2 (preserve progress)"
                echo "  2. Start fresh (discard previous progress)"
                echo ""

                if [[ "${YES_MODE:-false}" == "true" ]]; then
                    echo "Non-interactive mode: migrating to v2"
                    state_migrate_v1_to_v2
                    return 0
                fi

                read -r -p "Migrate existing state? [Y/n] " response
                if [[ "$response" =~ ^[Nn] ]]; then
                    state_backup_and_remove
                else
                    state_migrate_v1_to_v2
                fi
            else
                echo "jq is required for migration. Starting fresh."
                state_backup_and_remove
            fi
            return 0
            ;;
        *)
            # Unknown code
            echo "Unknown validation result: $code" >&2
            return 1
            ;;
    esac
}

# Backup and remove corrupted state file
# Usage: state_backup_and_remove
state_backup_and_remove() {
    local state_file
    state_file="$(state_get_file)"

    if [[ -f "$state_file" ]]; then
        local backup_file
        backup_file="${state_file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$state_file" "$backup_file" 2>/dev/null || true
        echo "Backed up state to: $backup_file"
        rm -f "$state_file"
        echo "Removed corrupted state file"
    fi
}

# Convenience function to validate and handle state
# Usage: state_ensure_valid
# Returns: 0 if state is valid or fresh, 1 if should abort
state_ensure_valid() {
    local code
    state_validate
    code=$?

    if [[ $code -eq 0 ]]; then
        return 0  # Valid state
    fi

    state_handle_invalid "$code"
}

# ============================================================
# Backwards Compatibility
# ============================================================

# Check schema version and migrate if needed
# Usage: state_check_version
# Returns: 0 if current or migrated, 1 if incompatible
state_check_version() {
    local state_file
    state_file="$(state_get_file)"

    if [[ ! -f "$state_file" ]]; then
        return 0  # No state file, fresh install
    fi

    local state
    if ! state=$(state_load); then
        return 1
    fi

    local version
    if command -v jq &>/dev/null; then
        version=$(echo "$state" | jq -r '.schema_version // 1')
    else
        # Fallback: if no schema_version field, assume v1
        if grep -q '"schema_version"' "$state_file"; then
            version=$(grep -oP '"schema_version"\s*:\s*\K[0-9]+' "$state_file")
        else
            version=1
        fi
    fi

    case "$version" in
        1)
            # Legacy v1 schema - offer fresh start or migration
            echo "Detected legacy state.json (v1). A fresh install is recommended." >&2
            return 2  # Special return code for "needs migration decision"
            ;;
        2|3)
            return 0  # Current versions (v2 is compatible with v3)
            ;;
        *)
            echo "Unknown state.json schema version: $version" >&2
            return 1
            ;;
    esac
}

# Migrate v1 state to v2 (best effort)
# Usage: state_migrate_v1_to_v2
# Returns: 0 on success
state_migrate_v1_to_v2() {
    local state
    if ! state=$(state_load); then
        return 1
    fi

    if command -v jq &>/dev/null; then
        # Convert numeric array to string array
        local new_state
        new_state=$(echo "$state" | jq '
            .schema_version = 2 |
            .completed_phases = (
                .completed_phases // [] |
                map(
                    if . == 1 then "user_setup"
                    elif . == 2 then "filesystem"
                    elif . == 3 then "shell_setup"
                    elif . == 4 then "cli_tools"
                    elif . == 5 then "languages"
                    elif . == 6 then "agents"
                    elif . == 7 then "cloud_db"
                    elif . == 8 then "stack"
                    elif . == 9 then "finalize"
                    else .
                    end
                )
            ) |
            .current_phase = null |
            .current_step = null |
            .failed_phase = null |
            .failed_step = null |
            .failed_error = null |
            .skipped_tools = [] |
            .skipped_phases = [] |
            .phase_durations = {}
        ')

        state_save "$new_state"
    else
        echo "Error: jq is required for state migration" >&2
        return 1
    fi
}

# ============================================================
# Display Functions
# ============================================================

# Print state summary for resume prompt
# Usage: state_print_summary
state_print_summary() {
    local state
    if ! state=$(state_load); then
        echo "No installation state found."
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        echo "State file exists but jq is needed for detailed summary."
        return 0
    fi

    local version mode started completed current failed
    version=$(echo "$state" | jq -r '.version // "unknown"')
    mode=$(echo "$state" | jq -r '.mode // "unknown"')
    started=$(echo "$state" | jq -r '.started_at // "unknown"')
    completed=$(echo "$state" | jq -r '.completed_phases | length')
    current=$(echo "$state" | jq -r '.current_phase // "none"')
    failed=$(echo "$state" | jq -r '.failed_phase // "none"')

    echo "=== ACFS Installation State ==="
    echo "Version: $version (mode: $mode)"
    echo "Started: $started"
    echo "Completed phases: $completed/${#ACFS_PHASE_IDS[@]}"

    if [[ "$failed" != "none" && "$failed" != "null" ]]; then
        local failed_step failed_error
        failed_step=$(echo "$state" | jq -r '.failed_step // "unknown"')
        failed_error=$(echo "$state" | jq -r '.failed_error // "unknown"')
        echo "FAILED at: $failed ($failed_step)"
        echo "Error: $failed_error"
    elif [[ "$current" != "none" && "$current" != "null" ]]; then
        echo "In progress: $current"
    fi

    echo ""
    echo "Completed:"
    echo "$state" | jq -r '.completed_phases[]' 2>/dev/null | while read -r phase; do
        local name="${ACFS_PHASE_NAMES[$phase]:-$phase}"
        local dur
        dur=$(echo "$state" | jq -r --arg p "$phase" '.phase_durations[$p] // 0')
        if [[ "$dur" -gt 0 ]]; then
            echo "  [x] $name (${dur}s)"
        else
            echo "  [x] $name"
        fi
    done

    echo ""
    echo "Pending:"
    for phase in "${ACFS_PHASE_IDS[@]}"; do
        if ! state_is_phase_completed "$phase"; then
            local name="${ACFS_PHASE_NAMES[$phase]:-$phase}"
            echo "  [ ] $name"
        fi
    done
}

# ============================================================
# Phase Execution Wrapper
# ============================================================
# This is the main entry point for executing installation phases.
# It handles skip logic, state tracking, timing, and error capture.
#
# Related beads:
#   - agentic_coding_flywheel_setup-yaj: Implement run_phase() wrapper

# Run a phase with state tracking and skip logic
# Usage: run_phase <phase_id> <display_name> <function_name> [args...]
# Example: run_phase "cli_tools" "5/10 CLI Tools" install_cli_tools
# Returns: 0 on success, 1 on failure
run_phase() {
    local phase_id="$1"
    local display_name="$2"
    local phase_func="$3"
    shift 3 || true

    # Validate phase_id is known
    local valid_phase=false
    for p in "${ACFS_PHASE_IDS[@]}"; do
        if [[ "$p" == "$phase_id" ]]; then
            valid_phase=true
            break
        fi
    done

    if [[ "$valid_phase" != "true" ]]; then
        echo "Warning: Unknown phase ID '$phase_id' - proceeding anyway" >&2
    fi

    # Get human-readable name for logging
    local human_name="${ACFS_PHASE_NAMES[$phase_id]:-$phase_id}"

    # Check if phase should be skipped (already completed or user-skipped)
    if state_should_skip_phase "$phase_id"; then
        if state_is_phase_completed "$phase_id"; then
            _run_phase_log_skip "$display_name" "already completed"
        else
            _run_phase_log_skip "$display_name" "user skipped"
        fi
        return 0
    fi

    # Record phase start
    state_phase_start "$phase_id" "Starting $human_name"

    # Execute the phase function
    _run_phase_log_start "$display_name"
    local start_time
    start_time=$(date +%s)

    # Execute and capture exit code correctly
    # (can't use "if ! cmd; then exit_code=$?" because $? would be 0 from the negation)
    local exit_code=0
    "$phase_func" "$@" || exit_code=$?

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ $exit_code -eq 0 ]]; then
        # Success - mark phase as completed
        state_phase_complete "$phase_id"
        _run_phase_log_success "$display_name" "$duration"
        return 0
    else
        # Failure - record failure state
        local error_msg="Phase '$human_name' failed with exit code $exit_code"
        state_phase_fail "$phase_id" "Execution failed" "$error_msg"
        _run_phase_log_failure "$display_name" "$exit_code"
        return 1
    fi
}

# Helper: Log phase skip (gray, muted)
_run_phase_log_skip() {
    local display_name="$1"
    local reason="$2"

    if [[ "${HAS_GUM:-false}" == "true" ]] && command -v gum &>/dev/null; then
        gum style --foreground "#6c7086" "[$display_name] Skipped ($reason)" >&2
    else
        echo -e "\033[0;90m[$display_name] Skipped ($reason)\033[0m" >&2
    fi
}

# Helper: Log phase start (blue)
_run_phase_log_start() {
    local display_name="$1"

    if [[ "${HAS_GUM:-false}" == "true" ]] && command -v gum &>/dev/null; then
        gum style --foreground "#89b4fa" --bold "[$display_name] Starting..." >&2
    else
        echo -e "\033[0;34m[$display_name] Starting...\033[0m" >&2
    fi
}

# Helper: Log phase success (green)
_run_phase_log_success() {
    local display_name="$1"
    local duration="$2"

    local msg="[$display_name] Complete"
    if [[ "$duration" -gt 0 ]]; then
        msg="$msg (${duration}s)"
    fi

    if [[ "${HAS_GUM:-false}" == "true" ]] && command -v gum &>/dev/null; then
        gum style --foreground "#a6e3a1" --bold "$msg" >&2
    else
        echo -e "\033[0;32m$msg\033[0m" >&2
    fi
}

# Helper: Log phase failure (red)
_run_phase_log_failure() {
    local display_name="$1"
    local exit_code="$2"

    if [[ "${HAS_GUM:-false}" == "true" ]] && command -v gum &>/dev/null; then
        gum style --foreground "#f38ba8" --bold "[$display_name] FAILED (exit code: $exit_code)" >&2
    else
        echo -e "\033[0;31m[$display_name] FAILED (exit code: $exit_code)\033[0m" >&2
    fi
}

# ============================================================
# Convenience Functions for install.sh Integration
# ============================================================

# Initialize state for a new or resumed installation
# Usage: init_installation_state
# Returns: 0 on success, 1 if state is corrupted/incompatible
init_installation_state() {
    local state_file
    state_file="$(state_get_file)"

    # Check for existing state
    if [[ -f "$state_file" ]]; then
        state_check_version
        local check_result=$?

        case $check_result in
            0)
                # State is current version, load it
                return 0
                ;;
            2)
                # Legacy v1 state - needs migration decision
                return 2
                ;;
            *)
                # Corrupted or unknown - needs fresh start
                return 1
                ;;
        esac
    fi

    # No state file - initialize fresh
    state_init
}

# Check if we're resuming a previous installation
# Usage: is_resume_installation
# Returns: 0 if resuming, 1 if fresh install
is_resume_installation() {
    local state_file
    state_file="$(state_get_file)"

    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    # Check if any phases are completed
    if command -v jq &>/dev/null; then
        local state
        if state=$(state_load 2>/dev/null); then
            local completed_count
            completed_count=$(echo "$state" | jq -r '.completed_phases | length')
            [[ "$completed_count" -gt 0 ]]
            return $?
        fi
    fi

    return 1
}

# Get the total number of phases
get_total_phases() {
    echo "${#ACFS_PHASE_IDS[@]}"
}

# Get the count of completed phases
get_completed_phase_count() {
    if ! command -v jq &>/dev/null; then
        echo "0"
        return
    fi

    local state
    if state=$(state_load 2>/dev/null); then
        echo "$state" | jq -r '.completed_phases | length'
    else
        echo "0"
    fi
}

# Get the next phase that needs to run
# Usage: get_next_pending_phase
# Outputs: Phase ID or empty if all complete
get_next_pending_phase() {
    for phase_id in "${ACFS_PHASE_IDS[@]}"; do
        if ! state_should_skip_phase "$phase_id"; then
            echo "$phase_id"
            return 0
        fi
    done
    echo ""
}

# ============================================================
# Resume Confirmation (bead 4xi)
# ============================================================
# When ACFS detects a previous incomplete installation, this function
# determines whether to resume, start fresh, or abort.
#
# Design Decision: Silent Resume by Default
# ------------------------------------------
# Users who run ./install.sh on a partially-installed system generally
# WANT to resume. Forcing an interactive prompt every time creates friction,
# especially for agentic workflows that run non-interactively.
#
# Behavior:
#   - Default (no flags, no TTY): Silent resume with status message
#   - --resume flag: Explicit resume intent, no prompt
#   - --force-reinstall flag: Fresh install, wipe state
#   - --interactive flag + TTY: Show prompt for user choice
#
# CLI Flags (set these before calling confirm_resume):
#   ACFS_FORCE_RESUME=true      - Force resume without prompts
#   ACFS_FORCE_REINSTALL=true   - Force fresh install
#   ACFS_INTERACTIVE=true       - Enable interactive prompts
# ============================================================

# Confirm whether to resume a previous installation
#
# Usage: confirm_resume
#
# Returns:
#   0 - Resume (continue from last completed phase)
#   1 - Fresh install (wipe state and start over)
#   2 - Abort (exit installation)
#
# Side effects:
#   - May delete state file if fresh install chosen
#   - Prints status messages to stderr
#
# Related: agentic_coding_flywheel_setup-4xi
confirm_resume() {
    local state_file
    state_file="$(state_get_file)"

    # If no state file, nothing to resume - proceed with fresh install
    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    # Load state to extract resume info
    local state
    if ! state=$(state_load 2>/dev/null); then
        # State file exists but can't be loaded (corrupted?)
        _confirm_resume_log_warn "State file exists but is unreadable. Starting fresh."
        rm -f "$state_file" 2>/dev/null || true
        return 1
    fi

    # Check for completed phases
    local completed_count
    if command -v jq &>/dev/null; then
        completed_count=$(echo "$state" | jq -r '.completed_phases | length')
    else
        completed_count=0
    fi

    # If no phases completed, nothing to resume
    if [[ "$completed_count" -eq 0 ]]; then
        return 1
    fi

    # Extract resume info
    local last_phase="" started_at="" failed_phase="" mode=""
    if command -v jq &>/dev/null; then
        # Get the last completed phase
        last_phase=$(echo "$state" | jq -r '.completed_phases[-1] // "unknown"')
        started_at=$(echo "$state" | jq -r '.started_at // "unknown"')
        failed_phase=$(echo "$state" | jq -r '.failed_phase // empty')
        mode=$(echo "$state" | jq -r '.mode // "unknown"')
    fi

    local last_phase_name="${ACFS_PHASE_NAMES[$last_phase]:-$last_phase}"
    local total_phases="${#ACFS_PHASE_IDS[@]}"

    # Handle explicit CLI flags first (these override everything)
    if [[ "${ACFS_FORCE_REINSTALL:-}" == "true" ]]; then
        _confirm_resume_log_info "Force reinstall requested. Wiping state..."
        rm -f "$state_file" 2>/dev/null || true
        return 1
    fi

    if [[ "${ACFS_FORCE_RESUME:-}" == "true" ]]; then
        _confirm_resume_log_info "Resuming installation from: $last_phase_name"
        _confirm_resume_log_info "Progress: $completed_count/$total_phases phases completed"
        return 0
    fi

    # Default behavior: silent resume with status
    # Show clear status so user knows what's happening
    echo "" >&2
    _confirm_resume_log_info "Previous installation detected"
    _confirm_resume_log_info "  Started: $started_at"
    _confirm_resume_log_info "  Mode: $mode"
    _confirm_resume_log_info "  Progress: $completed_count/$total_phases phases"
    _confirm_resume_log_info "  Last completed: $last_phase_name"

    if [[ -n "$failed_phase" && "$failed_phase" != "null" ]]; then
        local failed_name="${ACFS_PHASE_NAMES[$failed_phase]:-$failed_phase}"
        _confirm_resume_log_warn "  Previous failure at: $failed_name"
    fi

    # Only prompt if --interactive flag AND stdin is a TTY
    if [[ "${ACFS_INTERACTIVE:-}" == "true" ]] && [[ -t 0 ]]; then
        echo "" >&2
        echo "Options:" >&2
        echo "  [R] Resume from $last_phase_name (default)" >&2
        echo "  [F] Fresh install (wipe state)" >&2
        echo "  [A] Abort" >&2
        echo "" >&2

        local choice
        if [[ "${HAS_GUM:-false}" == "true" ]] && command -v gum &>/dev/null; then
            # Use gum for nicer selection
            choice=$(gum choose "Resume" "Fresh install" "Abort" 2>/dev/null) || choice="Resume"
            case "$choice" in
                "Fresh install")
                    _confirm_resume_log_info "Starting fresh install..."
                    rm -f "$state_file" 2>/dev/null || true
                    return 1
                    ;;
                "Abort")
                    _confirm_resume_log_info "Installation aborted."
                    return 2
                    ;;
                *)
                    _confirm_resume_log_info "Resuming installation..."
                    return 0
                    ;;
            esac
        else
            # Fallback to read prompt
            read -r -p "Choice [R/f/a]: " choice
            case "${choice,,}" in
                f|fresh)
                    _confirm_resume_log_info "Starting fresh install..."
                    rm -f "$state_file" 2>/dev/null || true
                    return 1
                    ;;
                a|abort)
                    _confirm_resume_log_info "Installation aborted."
                    return 2
                    ;;
                *)
                    _confirm_resume_log_info "Resuming installation..."
                    return 0
                    ;;
            esac
        fi
    fi

    # Non-interactive: silent resume (default behavior)
    echo "" >&2
    _confirm_resume_log_info "Resuming installation (use --force-reinstall for fresh start)"
    echo "" >&2
    return 0
}

# Helper: Log info message for confirm_resume
_confirm_resume_log_info() {
    local msg="$1"
    if [[ "${HAS_GUM:-false}" == "true" ]] && command -v gum &>/dev/null; then
        gum style --foreground "#89b4fa" "$msg" >&2
    else
        echo -e "\033[0;34m$msg\033[0m" >&2
    fi
}

# Helper: Log warning message for confirm_resume
_confirm_resume_log_warn() {
    local msg="$1"
    if [[ "${HAS_GUM:-false}" == "true" ]] && command -v gum &>/dev/null; then
        gum style --foreground "#f9e2af" "$msg" >&2
    else
        echo -e "\033[0;33m$msg\033[0m" >&2
    fi
}

# Parse CLI flags and set resume/reinstall globals
# Usage: parse_resume_flags "$@"
# Sets: ACFS_FORCE_RESUME, ACFS_FORCE_REINSTALL, ACFS_INTERACTIVE
#
# Flags recognized:
#   --resume           Force resume without prompts
#   --force-reinstall  Force fresh install, wipe state
#   --interactive      Enable interactive prompts
parse_resume_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --resume)
                export ACFS_FORCE_RESUME=true
                ;;
            --force-reinstall)
                export ACFS_FORCE_REINSTALL=true
                ;;
            --interactive)
                export ACFS_INTERACTIVE=true
                ;;
        esac
        shift
    done
}

# ============================================================
# Ubuntu Upgrade State Tracking
# ============================================================
# These functions track multi-reboot Ubuntu upgrade progress.
# The upgrade state is stored in a separate section of state.json
# to keep it isolated from installation phase state.
#
# Schema v3 adds the ubuntu_upgrade section:
# {
#   "ubuntu_upgrade": {
#     "enabled": true,
#     "started_at": "2025-01-15T10:00:00Z",
#     "original_version": "24.04",
#     "target_version": "25.10",
#     "upgrade_path": ["24.10", "25.04", "25.10"],
#     "current_stage": "upgrading",
#     "completed_upgrades": [
#       {"from": "24.04", "to": "24.10", "completed_at": "..."}
#     ],
#     "current_upgrade": {"from": "24.10", "to": "25.04", "started_at": "..."},
#     "needs_reboot": false,
#     "resume_after_reboot": true,
#     "last_error": null
#   }
# }
#
# Related beads: agentic_coding_flywheel_setup-2yd
# ============================================================

# Initialize upgrade state when starting an upgrade sequence
# Usage: state_upgrade_init <original_version> <target_version> <upgrade_path_json>
# Example: state_upgrade_init "24.04" "25.10" '["24.10", "25.04", "25.10"]'
state_upgrade_init() {
    local original_version="$1"
    local target_version="$2"
    local upgrade_path="$3"  # JSON array string

    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required for state_upgrade_init" >&2
        return 1
    fi

    local now
    now="$(date -Iseconds)"

    # Initialize the ubuntu_upgrade section
    state_update "
        .ubuntu_upgrade = {
            \"enabled\": true,
            \"started_at\": \"$now\",
            \"original_version\": \"$original_version\",
            \"target_version\": \"$target_version\",
            \"upgrade_path\": $upgrade_path,
            \"current_stage\": \"initializing\",
            \"completed_upgrades\": [],
            \"current_upgrade\": null,
            \"needs_reboot\": false,
            \"resume_after_reboot\": false,
            \"last_error\": null
        }
    "
}

# Mark current upgrade step as starting
# Usage: state_upgrade_start <from_version> <to_version>
state_upgrade_start() {
    local from_version="$1"
    local to_version="$2"

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    local now
    now="$(date -Iseconds)"

    state_update "
        .ubuntu_upgrade.current_stage = \"upgrading\" |
        .ubuntu_upgrade.current_upgrade = {
            \"from\": \"$from_version\",
            \"to\": \"$to_version\",
            \"started_at\": \"$now\"
        }
    "
}

# Mark current upgrade step as completed
# Usage: state_upgrade_complete <to_version>
state_upgrade_complete() {
    local to_version="$1"

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    local state
    state=$(state_load) || return 1

    local now
    now="$(date -Iseconds)"

    # Move current_upgrade to completed_upgrades
    local from_version
    from_version=$(echo "$state" | jq -r '.ubuntu_upgrade.current_upgrade.from // ""')

    state_update "
        .ubuntu_upgrade.completed_upgrades += [{
            \"from\": \"$from_version\",
            \"to\": \"$to_version\",
            \"completed_at\": \"$now\"
        }] |
        .ubuntu_upgrade.current_upgrade = null |
        .ubuntu_upgrade.current_stage = \"step_complete\"
    "
}

# Mark that system needs reboot before continuing
# Usage: state_upgrade_needs_reboot
state_upgrade_needs_reboot() {
    if ! command -v jq &>/dev/null; then
        return 1
    fi

    state_update "
        .ubuntu_upgrade.needs_reboot = true |
        .ubuntu_upgrade.resume_after_reboot = true |
        .ubuntu_upgrade.current_stage = \"awaiting_reboot\"
    "
}

# Clear reboot flags after successful resume
# Usage: state_upgrade_resumed
state_upgrade_resumed() {
    if ! command -v jq &>/dev/null; then
        return 1
    fi

    state_update "
        .ubuntu_upgrade.needs_reboot = false |
        .ubuntu_upgrade.current_stage = \"resumed\"
    "
}

# Check if upgrade sequence is complete
# Usage: state_upgrade_is_complete
# Returns: 0 if complete, 1 if not complete or not upgrading
state_upgrade_is_complete() {
    if ! command -v jq &>/dev/null; then
        return 1
    fi

    local state
    state=$(state_load) || return 1

    # Check if ubuntu_upgrade section exists and is enabled
    local enabled
    enabled=$(echo "$state" | jq -r '.ubuntu_upgrade.enabled // false')
    if [[ "$enabled" != "true" ]]; then
        return 1  # Not in upgrade mode
    fi

    # Check if current stage is completed
    local stage
    stage=$(echo "$state" | jq -r '.ubuntu_upgrade.current_stage // ""')
    if [[ "$stage" == "completed" ]]; then
        return 0
    fi

    # Check if all upgrades in path are completed
    local path_count completed_count
    path_count=$(echo "$state" | jq -r '.ubuntu_upgrade.upgrade_path | length')
    completed_count=$(echo "$state" | jq -r '.ubuntu_upgrade.completed_upgrades | length')

    if [[ "$completed_count" -ge "$path_count" ]]; then
        return 0
    fi

    return 1
}

# Get current upgrade stage
# Usage: state_upgrade_get_stage
# Outputs: not_started | initializing | upgrading | awaiting_reboot | resumed | step_complete | completed | error
state_upgrade_get_stage() {
    if ! command -v jq &>/dev/null; then
        echo "not_started"
        return 0
    fi

    local state
    if ! state=$(state_load 2>/dev/null); then
        echo "not_started"
        return 0
    fi

    local enabled
    enabled=$(echo "$state" | jq -r '.ubuntu_upgrade.enabled // false')
    if [[ "$enabled" != "true" ]]; then
        echo "not_started"
        return 0
    fi

    local stage
    stage=$(echo "$state" | jq -r '.ubuntu_upgrade.current_stage // "not_started"')
    echo "$stage"
}

# Record an error during upgrade
# Usage: state_upgrade_set_error <error_message>
state_upgrade_set_error() {
    local error_msg="$1"

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    # Use jq's --arg for proper JSON escaping (handles quotes, backslashes, newlines)
    local state
    state=$(state_load) || return 1

    local new_state
    new_state=$(echo "$state" | jq --arg err "$error_msg" '
        .ubuntu_upgrade.last_error = $err |
        .ubuntu_upgrade.current_stage = "error"
    ')

    state_save "$new_state"
}

# Mark upgrade sequence as fully completed
# Usage: state_upgrade_mark_complete
state_upgrade_mark_complete() {
    if ! command -v jq &>/dev/null; then
        return 1
    fi

    local now
    now="$(date -Iseconds)"

    state_update "
        .ubuntu_upgrade.current_stage = \"completed\" |
        .ubuntu_upgrade.completed_at = \"$now\" |
        .ubuntu_upgrade.needs_reboot = false |
        .ubuntu_upgrade.resume_after_reboot = false
    "
}

# Clean up upgrade state after completion
# Usage: state_upgrade_cleanup
# This removes the ubuntu_upgrade section entirely
state_upgrade_cleanup() {
    if ! command -v jq &>/dev/null; then
        return 1
    fi

    state_update "del(.ubuntu_upgrade)"
}

# Check if we're in the middle of an upgrade
# Usage: state_upgrade_in_progress
# Returns: 0 if upgrade is in progress, 1 if not
state_upgrade_in_progress() {
    local stage
    stage=$(state_upgrade_get_stage)

    case "$stage" in
        initializing|upgrading|awaiting_reboot|resumed|step_complete)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Get the next version to upgrade to
# Usage: state_upgrade_get_next_version
# Outputs: next version string or empty if no more upgrades
state_upgrade_get_next_version() {
    if ! command -v jq &>/dev/null; then
        return 1
    fi

    local state
    state=$(state_load) || return 1

    local completed_count
    completed_count=$(echo "$state" | jq -r '.ubuntu_upgrade.completed_upgrades | length')

    # Get the next item in upgrade_path based on completed count
    echo "$state" | jq -r ".ubuntu_upgrade.upgrade_path[$completed_count] // empty"
}

# Get upgrade progress summary
# Usage: state_upgrade_get_progress
# Outputs: JSON object with progress info
state_upgrade_get_progress() {
    if ! command -v jq &>/dev/null; then
        echo '{"error": "jq required"}'
        return 1
    fi

    local state
    state=$(state_load) || {
        echo '{"error": "no state"}'
        return 1
    }

    echo "$state" | jq '
        {
            enabled: (.ubuntu_upgrade.enabled // false),
            stage: (.ubuntu_upgrade.current_stage // "not_started"),
            original: (.ubuntu_upgrade.original_version // null),
            target: (.ubuntu_upgrade.target_version // null),
            completed_count: ((.ubuntu_upgrade.completed_upgrades // []) | length),
            total_count: ((.ubuntu_upgrade.upgrade_path // []) | length),
            needs_reboot: (.ubuntu_upgrade.needs_reboot // false),
            last_error: (.ubuntu_upgrade.last_error // null)
        }
    '
}

# Print upgrade status for user display
# Usage: state_upgrade_print_status
state_upgrade_print_status() {
    if ! command -v jq &>/dev/null; then
        echo "Upgrade status unavailable (jq required)"
        return 1
    fi

    local state
    if ! state=$(state_load 2>/dev/null); then
        echo "No upgrade in progress"
        return 0
    fi

    local enabled
    enabled=$(echo "$state" | jq -r '.ubuntu_upgrade.enabled // false')
    if [[ "$enabled" != "true" ]]; then
        echo "No upgrade in progress"
        return 0
    fi

    local original target stage completed_count total_count
    original=$(echo "$state" | jq -r '.ubuntu_upgrade.original_version')
    target=$(echo "$state" | jq -r '.ubuntu_upgrade.target_version')
    stage=$(echo "$state" | jq -r '.ubuntu_upgrade.current_stage')
    completed_count=$(echo "$state" | jq -r '.ubuntu_upgrade.completed_upgrades | length')
    total_count=$(echo "$state" | jq -r '.ubuntu_upgrade.upgrade_path | length')

    echo "=== Ubuntu Upgrade Status ==="
    echo "Original: $original → Target: $target"
    echo "Progress: $completed_count/$total_count upgrades completed"
    echo "Stage: $stage"

    # Show completed upgrades
    if [[ "$completed_count" -gt 0 ]]; then
        echo ""
        echo "Completed upgrades:"
        echo "$state" | jq -r '.ubuntu_upgrade.completed_upgrades[] | "  ✓ \(.from) → \(.to)"'
    fi

    # Show current upgrade if any
    local current
    current=$(echo "$state" | jq -r '.ubuntu_upgrade.current_upgrade // empty')
    if [[ -n "$current" ]]; then
        local from to
        from=$(echo "$state" | jq -r '.ubuntu_upgrade.current_upgrade.from')
        to=$(echo "$state" | jq -r '.ubuntu_upgrade.current_upgrade.to')
        echo ""
        echo "Current upgrade: $from → $to"
    fi

    # Show error if any
    local error
    error=$(echo "$state" | jq -r '.ubuntu_upgrade.last_error // empty')
    if [[ -n "$error" ]]; then
        echo ""
        echo "Last error: $error"
    fi
}
