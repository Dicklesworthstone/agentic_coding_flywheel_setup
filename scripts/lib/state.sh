#!/usr/bin/env bash
# ============================================================
# ACFS State Management Library
#
# Provides phase-granular progress persistence with stable phase IDs.
# Implements state.json v3 schema for robust resume capability.
#
# Schema Version History:
#   v1: Used numeric phase array [1, 2, 3, ...] (legacy, install.sh inline)
#   v2: Uses stable phase IDs ["user_setup", "filesystem", ...]
#   v3: Adds ubuntu_upgrade section for multi-reboot upgrade tracking
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

_ACFS_STATE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! type -t local_progress_record_installer_phase >/dev/null 2>&1 && [[ -f "$_ACFS_STATE_SCRIPT_DIR/progress.sh" ]]; then
    # shellcheck source=progress.sh
    source "$_ACFS_STATE_SCRIPT_DIR/progress.sh" 2>/dev/null || true
fi

# ============================================================
# Color Constants - respect NO_COLOR standard (https://no-color.org/)
# Related: bd-39ye
# ============================================================
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 2 ]]; then
    _STATE_BLUE='\033[0;34m'
    _STATE_GREEN='\033[0;32m'
    _STATE_YELLOW='\033[0;33m'
    _STATE_RED='\033[0;31m'
    _STATE_GRAY='\033[0;90m'
    _STATE_NC='\033[0m'
else
    _STATE_BLUE=''
    _STATE_GREEN=''
    _STATE_YELLOW=''
    _STATE_RED=''
    _STATE_GRAY=''
    _STATE_NC=''
fi

# ============================================================
# State File Schema v3 Documentation
# ============================================================
#
# {
#   "schema_version": 3,                      # Schema version for compatibility
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
#   "ubuntu_upgrade": {                       # Present only while upgrading Ubuntu
#     "enabled": true,
#     "original_version": "24.04",
#     "target_version": "25.10",
#     "current_stage": "upgrading"
#   }
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

state_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

state_is_valid_username() {
    local username="${1:-}"
    [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

state_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

state_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(state_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(state_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

state_getent_passwd_entry() {
  local user="${1-}"
  local getent_bin=""
  local passwd_entry=""
  local passwd_line=""
  local printed_any=false

  getent_bin="$(state_system_binary_path getent 2>/dev/null || true)"
  if [[ -z "$user" ]]; then
    if [[ -n "$getent_bin" ]]; then
      while IFS= read -r passwd_line; do
        printf '%s\n' "$passwd_line"
        printed_any=true
      done < <("$getent_bin" passwd 2>/dev/null || true)
      if [[ "$printed_any" == true ]]; then
        return 0
      fi
    fi

    [[ -r /etc/passwd ]] || return 1
    while IFS= read -r passwd_line; do
      printf '%s\n' "$passwd_line"
    done < /etc/passwd
    return 0
  fi

  if [[ -n "$getent_bin" ]]; then
    passwd_entry="$("$getent_bin" passwd "$user" 2>/dev/null || true)"
  fi

  if [[ -z "$passwd_entry" ]] && [[ -r /etc/passwd ]]; then
    while IFS= read -r passwd_line; do
      [[ "${passwd_line%%:*}" == "$user" ]] || continue
      passwd_entry="$passwd_line"
      break
    done < /etc/passwd
  fi

  [[ -n "$passwd_entry" ]] || return 1
  printf '%s\n' "$passwd_entry"
}

state_passwd_home_from_entry() {
  local passwd_entry="${1:-}"
  local passwd_home=""

  [[ -n "$passwd_entry" ]] || return 1
  IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
  passwd_home="$(state_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
  [[ -n "$passwd_home" ]] || return 1
  printf '%s\n' "$passwd_home"
}

state_resolve_current_home() {
    local current_user=""
    local home_candidate=""
    local passwd_entry=""
    local passwd_home=""

    home_candidate="$(state_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    current_user="$(state_resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        passwd_entry="$(state_getent_passwd_entry "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(state_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi
    fi

    [[ -n "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

state_resolve_target_home() {
    local current_user=""
    local explicit_home=""
    local resolved_home=""
    local target_user="${TARGET_USER:-}"

    explicit_home="$(state_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"

    if [[ -z "$target_user" ]]; then
        if [[ -n "$explicit_home" ]]; then
            printf '%s\n' "$explicit_home"
            return 0
        fi

        resolved_home="$(state_resolve_current_home 2>/dev/null || true)"
        if [[ -n "$resolved_home" ]]; then
            printf '%s\n' "$resolved_home"
        else
            printf '/root\n'
        fi
        return 0
    fi

    state_is_valid_username "$target_user" || return 1

    if [[ "$target_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    local passwd_entry=""
    passwd_entry="$(state_getent_passwd_entry "$target_user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        resolved_home="$(state_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$resolved_home" ]]; then
            printf '%s\n' "$resolved_home"
            return 0
        fi
    fi

    if [[ $EUID -eq 0 ]]; then
        local id_bin=""
        id_bin="$(state_system_binary_path id 2>/dev/null || true)"
        if [[ -n "$id_bin" ]] && ! "$id_bin" "$target_user" >/dev/null 2>&1; then
            if [[ -n "$explicit_home" ]]; then
                printf '%s\n' "$explicit_home"
                return 0
            fi
            printf '/home/%s\n' "$target_user"
            return 0
        fi
    fi

    current_user="$(state_resolve_current_user 2>/dev/null || true)"
    if [[ -z "$current_user" ]] || [[ "$current_user" != "$target_user" ]]; then
        return 1
    fi

    if [[ -n "$explicit_home" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    resolved_home="$(state_resolve_current_home 2>/dev/null || true)"
    if [[ -z "$resolved_home" ]]; then
        return 1
    fi
    printf '%s\n' "$resolved_home"
}

state_get_file() {
    if [[ -n "${ACFS_STATE_FILE:-}" ]]; then
        printf '%s\n' "$ACFS_STATE_FILE"
        return 0
    fi

    if [[ -n "${ACFS_HOME:-}" ]]; then
        printf '%s\n' "${ACFS_HOME}/state.json"
        return 0
    fi

    local state_home
    state_home="$(state_resolve_target_home 2>/dev/null || true)"
    [[ -n "$state_home" ]] || return 1
    printf '%s\n' "${state_home}/.acfs/state.json"
}

# ============================================================
# State File Operations
# ============================================================

# Initialize a new state file with default values
# Usage: state_init
# Returns: 0 on success, 1 on failure
state_init() {
    local state_file
    state_file="$(state_get_file 2>/dev/null || true)"
    if [[ -z "$state_file" ]]; then
        declare -f log_error &>/dev/null && log_error "state_init: unable to resolve state file path"
        return 1
    fi

    local state_dir
    state_dir="$(dirname "$state_file")"
    local resolved_target_home=""
    resolved_target_home="$(state_resolve_target_home 2>/dev/null || true)"
    if [[ -z "$resolved_target_home" ]]; then
        declare -f log_error &>/dev/null && log_error "state_init: unable to resolve target home"
        return 1
    fi

    # Ensure directory exists
    if [[ ! -d "$state_dir" ]]; then
        # Try without sudo first (works for user directories like ~/.acfs)
        # Fall back to sudo for system directories like /var/lib/acfs
        local mkdir_bin=""
        mkdir_bin="$(state_system_binary_path mkdir 2>/dev/null || true)"
        [[ -n "$mkdir_bin" ]] || return 1
        if ! "$mkdir_bin" -p "$state_dir" 2>/dev/null; then
            local sudo_bin=""
            sudo_bin="$(state_system_binary_path sudo 2>/dev/null || true)"
            if [[ $EUID -ne 0 && -n "$sudo_bin" ]]; then
                "$sudo_bin" -n "$mkdir_bin" -p "$state_dir" || return 1
                # Fix ownership so current user can write to it
                local chown_bin=""
                local id_bin=""
                chown_bin="$(state_system_binary_path chown 2>/dev/null || true)"
                id_bin="$(state_system_binary_path id 2>/dev/null || true)"
                if [[ -n "$chown_bin" && -n "$id_bin" ]]; then
                    "$sudo_bin" -n "$chown_bin" "$("$id_bin" -u):$("$id_bin" -g)" "$state_dir" 2>/dev/null || true
                fi
            else
                return 1
            fi
        fi

        # If running as root but targeting a non-root user, ensure the directory
        # is owned by the target user so they can access the state file later.
        # This is critical for `acfs doctor` to work after a failed install.
        if [[ $EUID -eq 0 ]] && [[ -n "${TARGET_USER:-}" ]] && [[ "$TARGET_USER" != "root" ]]; then
            local target_home=""
            target_home="$(state_resolve_target_home 2>/dev/null || true)"
            if [[ -n "$target_home" ]] && [[ "$target_home" != "/" ]] && [[ "$target_home" == /* ]] && [[ "$state_dir" == "$target_home/"* ]]; then
                local target_group=""
                local id_bin=""
                id_bin="$(state_system_binary_path id 2>/dev/null || true)"
                if [[ -n "$id_bin" ]]; then
                    target_group="$("$id_bin" -gn "$TARGET_USER" 2>/dev/null || true)"
                fi
                local chown_bin=""
                chown_bin="$(state_system_binary_path chown 2>/dev/null || true)"
                if [[ -n "$chown_bin" ]]; then
                    if [[ -n "$target_group" ]]; then
                        "$chown_bin" "$TARGET_USER:$target_group" "$state_dir" 2>/dev/null \
                            || "$chown_bin" "$TARGET_USER:$TARGET_USER" "$state_dir" 2>/dev/null \
                            || true
                    else
                        "$chown_bin" "$TARGET_USER" "$state_dir" 2>/dev/null || true
                    fi
                fi
            fi
        fi
    fi

    local now
    now="$(date -Iseconds)"

    local state_version="${ACFS_VERSION:-unknown}"
    local state_target_user="${TARGET_USER:-}"
    if [[ -z "$state_target_user" ]]; then
        state_target_user="$(state_resolve_current_user 2>/dev/null || true)"
    fi
    state_target_user="${state_target_user:-unknown}"

    # Normalize boolean values for JSON
    local skip_pg="false"; [[ "${SKIP_POSTGRES:-false}" == "true" ]] && skip_pg="true"
    local skip_v="false"; [[ "${SKIP_VAULT:-false}" == "true" ]] && skip_v="true"
    local skip_c="false"; [[ "${SKIP_CLOUD:-false}" == "true" ]] && skip_c="true"

    local initial_state
    if command -v jq &>/dev/null; then
        initial_state=$(jq -n \
            --argjson schema_version "$ACFS_STATE_SCHEMA_VERSION" \
            --arg ver "$state_version" \
            --arg user "$state_target_user" \
            --arg home "$resolved_target_home" \
            --arg bin_dir "${ACFS_BIN_DIR:-$resolved_target_home/.local/bin}" \
            --arg ts "$now" \
            --arg mode "${MODE:-${ACFS_MODE:-vibe}}" \
            --argjson skip_pg "$skip_pg" \
            --argjson skip_v "$skip_v" \
            --argjson skip_c "$skip_c" \
            '{
                schema_version: $schema_version,
                version: $ver,
                target_user: $user,
                target_home: $home,
                bin_dir: $bin_dir,
                started_at: $ts,
                last_updated: $ts,
                mode: $mode,
                completed_phases: [],
                failed_phase: null,
                failed_step: null,
                skip_postgres: $skip_pg,
                skip_vault: $skip_v,
                skip_cloud: $skip_c,
                ubuntu_upgrade: {
                    enabled: false,
                    current_stage: "none",
                    upgrade_path: [],
                    completed_upgrades: []
                }
            }')
    else
        # Fallback to heredoc if jq is not yet installed
        initial_state=$(cat <<EOF
{
  "schema_version": $ACFS_STATE_SCHEMA_VERSION,
  "version": "$state_version",
  "target_user": "$state_target_user",
  "target_home": "$resolved_target_home",
  "bin_dir": "${ACFS_BIN_DIR:-$resolved_target_home/.local/bin}",
  "started_at": "$now",
  "last_updated": "$now",
  "mode": "${MODE:-${ACFS_MODE:-vibe}}",
  "completed_phases": [],
  "failed_phase": null,
  "failed_step": null,
  "skip_postgres": $skip_pg,
  "skip_vault": $skip_v,
  "skip_cloud": $skip_c,
  "ubuntu_upgrade": {
    "enabled": false,
    "current_stage": "none",
    "upgrade_path": [],
    "completed_upgrades": []
  }
}
EOF
)
    fi

    if ! state_write_atomic "$state_file" "$initial_state"; then
        return 1
    fi

    state_sync_path_if_enabled "$state_dir"

    return 0
}

# Write state file atomically using temp file + rename
#
# This implements the atomic write pattern to prevent corruption:
#   1. Write to a temp file in the same directory
#   2. Rename temp file to target (atomic on POSIX filesystems)
#
# If the system crashes or SSH disconnects mid-write, the state file
# remains valid because the rename either completes fully or not at all.
# Forced durability sync is intentionally opt-in: external sync/fsync can block
# indefinitely on container overlays or distressed disks, while a stale checkpoint
# is safer than a hung installer.
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

        # If running as root but targeting a non-root user, ensure the directory
        # is owned by the target user so they can access the state file later.
        if [[ $EUID -eq 0 ]] && [[ -n "${TARGET_USER:-}" ]] && [[ "$TARGET_USER" != "root" ]]; then
            local target_home=""
            target_home="$(state_resolve_target_home 2>/dev/null || true)"
            if [[ -n "$target_home" ]] && [[ "$target_home" != "/" ]] && [[ "$target_home" == /* ]] && [[ "$target_dir" == "$target_home/"* ]]; then
                local dir_target_group=""
                if command -v id &>/dev/null; then
                    dir_target_group="$(id -gn "$TARGET_USER" 2>/dev/null || true)"
                fi
                if [[ -n "$dir_target_group" ]]; then
                    chown "$TARGET_USER:$dir_target_group" "$target_dir" 2>/dev/null \
                        || chown "$TARGET_USER:$TARGET_USER" "$target_dir" 2>/dev/null \
                        || true
                else
                    chown "$TARGET_USER" "$target_dir" 2>/dev/null || true
                fi
            fi
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

    # Create temp file in same directory (ensures same filesystem for atomic rename).
    # SECURITY: Never fall back to predictable temp paths (symlink/clobber risk under sudo/root).
    temp_file="$(mktemp "${target_dir}/.state.XXXXXX.tmp" 2>/dev/null)" || {
        if [[ ! -w "$target_dir" ]]; then
            declare -f log_error &>/dev/null && log_error "state_write_atomic: permission denied creating temp file in $target_dir"
            return 2
        fi
        declare -f log_error &>/dev/null && log_error "state_write_atomic: failed to create temp file in $target_dir"
        return 1
    }

    # Write content to temp file
    # Using printf for more reliable output than echo
    printf '%s\n' "$content" > "$temp_file" 2>/dev/null
    local write_err=$?
    if [[ $write_err -ne 0 ]]; then
        rm -f "$temp_file" 2>/dev/null || true

        if [[ ! -w "$target_dir" ]]; then
            declare -f log_error &>/dev/null && log_error "state_write_atomic: permission denied writing temp file in $target_dir"
            return 2
        fi

        declare -f log_error &>/dev/null && log_error "state_write_atomic: failed to write temp file (error $write_err)"
        return 1
    fi

    state_sync_path_if_enabled "$temp_file"

    # Set appropriate permissions before moving (state may include failure context; keep it owner-only).
    chmod 600 "$temp_file" 2>/dev/null || true

    # If the installer is running as root but targeting a non-root user,
    # ensure the file is owned by that user BEFORE the atomic move.
    # This prevents a race window where the file is owned by root/600 and unreadable.
    #
    # Only do this for state files under TARGET_HOME (per-user state) and
    # never for system state under /var/lib/acfs.
    if [[ $EUID -eq 0 ]] && [[ -n "${TARGET_USER:-}" ]] && [[ "$TARGET_USER" != "root" ]]; then
        local target_home=""
        target_home="$(state_resolve_target_home 2>/dev/null || true)"
        if [[ -n "$target_home" ]] && [[ "$target_home" != "/" ]] && [[ "$target_home" == /* ]] && [[ "$temp_file" == "$target_home/"* ]]; then
            local target_group=""
            if command -v id &>/dev/null; then
                target_group="$(id -gn "$TARGET_USER" 2>/dev/null || true)"
            fi

            if [[ -n "$target_group" ]]; then
                chown "$TARGET_USER:$target_group" "$temp_file" 2>/dev/null \
                    || chown "$TARGET_USER:$TARGET_USER" "$temp_file" 2>/dev/null \
                    || true
            else
                chown "$TARGET_USER" "$temp_file" 2>/dev/null || true
            fi
        fi
    fi

    # Atomic rename: on POSIX filesystems, rename() is guaranteed atomic
    # when source and target are on the same filesystem
    mv -f "$temp_file" "$file_path" 2>/dev/null
    local mv_err=$?
    if [[ $mv_err -ne 0 ]]; then
        rm -f "$temp_file" 2>/dev/null || true

        # Check for permission issues
        if [[ ! -w "$target_dir" ]] || [[ -f "$file_path" && ! -w "$file_path" ]]; then
            declare -f log_error &>/dev/null && log_error "state_write_atomic: permission denied on $file_path"
            return 2
        fi

        declare -f log_error &>/dev/null && log_error "state_write_atomic: atomic rename failed (error $mv_err)"
        return 1
    fi

    state_sync_path_if_enabled "$target_dir"

    return 0
}

state_durable_sync_enabled() {
    case "${ACFS_STATE_DURABLE_SYNC:-false}" in
        true|TRUE|1|yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

state_sync_path_if_enabled() {
    local path="${1:-}"
    [[ -n "$path" ]] || return 0
    state_durable_sync_enabled || return 0

    command -v python3 &>/dev/null || return 0
    python3 - "$path" <<'PY' 2>/dev/null || true
import os
import sys

path = sys.argv[1]
flags = os.O_RDONLY
if os.path.isdir(path) and hasattr(os, "O_DIRECTORY"):
    flags |= os.O_DIRECTORY

try:
    fd = os.open(path, flags)
except OSError:
    sys.exit(0)

try:
    os.fsync(fd)
finally:
    os.close(fd)
PY
}

# ============================================================
# Locking
# ============================================================

# Acquire a lock for the state file using flock (FD 200).
# This replaces the former mkdir-based lock which had no PID tracking
# and could leave stale lock directories after crashes.
# FD 200 is consistent with autofix.sh's existing flock pattern.
#
# Usage: _state_acquire_lock
# Returns: 0 on success, 1 on timeout/failure
_state_acquire_lock() {
    local state_file
    state_file="$(state_get_file)" || return 1
    local lock_file="${state_file}.lock"

    # If already locked by this process, track nested callers so an inner
    # state_save cannot release the outer caller's lock early.
    if [[ "${_ACFS_STATE_LOCKED:-}" == "true" ]]; then
        [[ "${_ACFS_STATE_LOCK_FILE:-}" == "$lock_file" ]] || return 1
        _ACFS_STATE_LOCK_DEPTH=$(( ${_ACFS_STATE_LOCK_DEPTH:-1} + 1 ))
        return 0
    fi

    # Ensure parent directory exists
    if ! mkdir -p "$(dirname "$state_file")" 2>/dev/null; then
        # If we can't create the directory, warn but don't fail
        # State operations will fail later with clearer errors
        return 1
    fi

    # If a stale descriptor is present for another state file, close it before
    # opening the descriptor for this lock. A freshly opened descriptor does not
    # receive _ACFS_STATE_LOCK_FILE until after flock succeeds.
    if [[ -n "${ACFS_LOCK_FD:-}" && "${_ACFS_STATE_LOCK_FILE:-}" != "$lock_file" ]]; then
        _state_close_lock_fd
    fi

    # Open lock file on FD 200 (same FD convention as autofix.sh)
    # Using >> to avoid truncating while opening for locking
    if [[ -z "${ACFS_LOCK_FD:-}" ]]; then
        if (exec 200>>"$lock_file") 2>/dev/null; then
            exec 200>>"$lock_file"
            ACFS_LOCK_FD=200
        elif (exec 199>>"$lock_file") 2>/dev/null; then
            exec 199>>"$lock_file"
            ACFS_LOCK_FD=199
        else
            # Lock acquisition not possible, return failure
            return 1
        fi
    fi

    [[ -n "${ACFS_LOCK_FD:-}" ]] || return 1

    local lock_timeout="${ACFS_STATE_LOCK_TIMEOUT:-30}"
    if [[ ! "$lock_timeout" =~ ^[0-9]+$ ]] || [[ "$lock_timeout" -lt 1 ]]; then
        lock_timeout=30
    fi

    # State writes can briefly queue behind durable atomic writes. Wait long
    # enough to preserve resume metadata instead of dropping contended updates.
    if ! flock -w "$lock_timeout" "${ACFS_LOCK_FD}" 2>/dev/null; then
        _state_close_lock_fd
        return 1
    fi

    _ACFS_STATE_LOCKED=true
    _ACFS_STATE_LOCK_DEPTH=1
    _ACFS_STATE_LOCK_FILE="$lock_file"
    return 0
}

_state_close_lock_fd() {
    case "${ACFS_LOCK_FD:-}" in
        199)
            { exec 199>&-; } 2>/dev/null || true
            ;;
        200)
            { exec 200>&-; } 2>/dev/null || true
            ;;
    esac
    unset ACFS_LOCK_FD
    _ACFS_STATE_LOCK_FILE=""
}

# Release the lock
# Usage: _state_release_lock
_state_release_lock() {
    local lock_depth="${_ACFS_STATE_LOCK_DEPTH:-0}"
    if [[ "$lock_depth" -gt 1 ]]; then
        _ACFS_STATE_LOCK_DEPTH=$(( lock_depth - 1 ))
        return 0
    fi

    if [[ -n "${ACFS_LOCK_FD:-}" ]]; then
        flock -u "${ACFS_LOCK_FD}" 2>/dev/null || true
    fi
    _state_close_lock_fd
    _ACFS_STATE_LOCKED=false
    _ACFS_STATE_LOCK_DEPTH=0
}

# Mark state as interrupted by a signal (SIGTERM, SIGINT, SIGHUP).
# Clears current_phase/current_step so resume logic does not see a
# partially-started phase with no failure marker.
#
# Usage: state_mark_interrupted
# Returns: 0 on success, 1 if state file does not exist
state_mark_interrupted() {
    local state_file
    state_file="$(state_get_file)"

    [[ -f "$state_file" ]] || return 1

    # Best-effort: do not let jq absence block signal handling
    command -v jq &>/dev/null || return 0

    local state
    state=$(cat "$state_file" 2>/dev/null) || return 1

    local updated
    updated=$(printf '%s' "$state" | jq '
        .current_phase = null |
        .current_step  = null |
        .interrupted   = true |
        .last_updated  = (now | todate)
    ' 2>/dev/null) || return 1

    state_write_atomic "$state_file" "$updated"
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
        # Uses sed instead of grep -oP for POSIX compatibility (macOS, BSD)
        # The state file is jq-pretty-printed (arrays span lines), so flatten
        # before matching. Array values are returned as one-line JSON with the
        # element quotes intact so callers can test membership against the
        # exact quoted element; scalar values are returned unquoted.
        local simple_key="${key#.}"
        local flat array_value
        flat="$(printf '%s' "$state" | tr '\n\t' '  ')"
        array_value="$(printf '%s' "$flat" | sed -n "s/.*\"${simple_key}\"[[:space:]]*:[[:space:]]*\(\[[^]]*\]\).*/\1/p")"
        if [[ -n "$array_value" ]]; then
            printf '%s\n' "$array_value"
        else
            printf '%s' "$flat" | sed -n "s/.*\"${simple_key}\"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p" | tr -d '"' | head -1
        fi
    fi
}

# ============================================================
# Convenience Functions for install.sh Integration
# ============================================================
# NOTE: Keep a single canonical copy of these helpers in this file.
# Duplicate function definitions later in the file will override earlier ones.

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
#   - May move state file to a timestamped backup if fresh install chosen
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
        if ! state_backup_and_remove; then
            _confirm_resume_log_warn "Failed to move unreadable state file out of the way. Aborting."
            return 2
        fi
        return 1
    fi

    # Extract all resume info in a single jq call (5→1 subprocess spawns)
    # Note: Uses ASCII Unit Separator (0x1f) as delimiter since bash strips null bytes
    local completed_count=0 last_phase="" started_at="" failed_phase="" mode=""
    if command -v jq &>/dev/null; then
        local extracted
        extracted=$(echo "$state" | jq -r '
            [
                (.completed_phases | length | tostring),
                (.completed_phases[-1] // "unknown"),
                (.started_at // "unknown"),
                (.failed_phase // ""),
                (.mode // "unknown")
            ] | join("\u001f")
        ')
        IFS=$'\x1f' read -r completed_count last_phase started_at failed_phase mode <<< "$extracted"
    fi

    # Handle explicit CLI flags first (these override everything)
    if [[ "${ACFS_FORCE_REINSTALL:-}" == "true" ]]; then
        _confirm_resume_log_info "Force reinstall requested. Wiping state..."
        if ! state_backup_and_remove; then
            _confirm_resume_log_warn "Failed to move state file out of the way. Aborting."
            return 2
        fi
        return 1
    fi

    local force_resume_requested=false
    if [[ "${ACFS_FORCE_RESUME:-}" == "true" ]]; then
        force_resume_requested=true
    fi

    # If nothing completed and no failed phase recorded, there is no meaningful resume point.
    if [[ "$force_resume_requested" != "true" ]] && [[ "$completed_count" -eq 0 ]] && [[ -z "$failed_phase" || "$failed_phase" == "null" ]]; then
        return 1
    fi

    local last_phase_name="${ACFS_PHASE_NAMES[$last_phase]:-$last_phase}"
    if [[ "$completed_count" -eq 0 && -n "$failed_phase" && "$failed_phase" != "null" ]]; then
        last_phase_name="${ACFS_PHASE_NAMES[$failed_phase]:-$failed_phase}"
    fi
    local total_phases="${#ACFS_PHASE_IDS[@]}"

    local resume_state=""
    local state_version=""
    if command -v jq &>/dev/null; then
        state_version=$(echo "$state" | jq -r '.version // "unknown"')
    fi
    if [[ -n "${ACFS_VERSION:-}" && -n "$state_version" && "$state_version" != "unknown" ]]; then
        if [[ "$ACFS_VERSION" != "$state_version" ]] && command -v jq &>/dev/null; then
            _confirm_resume_log_warn "Version mismatch: state=$state_version, running=$ACFS_VERSION"
            _confirm_resume_log_info "Finalize will be re-run on resume to deploy updated scripts"
            resume_state=$(echo "$state" | jq --arg ver "$ACFS_VERSION" '
                .completed_phases = (.completed_phases | map(select(. != "finalize"))) |
                .version = $ver
            ')
            state="$resume_state"

            extracted=$(echo "$state" | jq -r '
                [
                    (.completed_phases | length | tostring),
                    (.completed_phases[-1] // "unknown"),
                    (.started_at // "unknown"),
                    (.failed_phase // ""),
                    (.mode // "unknown")
                ] | join("\u001f")
            ')
            IFS=$'\x1f' read -r completed_count last_phase started_at failed_phase mode <<< "$extracted"

            last_phase_name="${ACFS_PHASE_NAMES[$last_phase]:-$last_phase}"
            if [[ "$completed_count" -eq 0 && -n "$failed_phase" && "$failed_phase" != "null" ]]; then
                last_phase_name="${ACFS_PHASE_NAMES[$failed_phase]:-$failed_phase}"
            fi
        fi
    fi

    if [[ "$force_resume_requested" == "true" ]]; then
        local forced_resume_phase="$last_phase_name"
        if [[ -z "$forced_resume_phase" || "$forced_resume_phase" == "unknown" ]]; then
            forced_resume_phase="the beginning"
        fi
        if [[ -n "$resume_state" ]]; then
            state_save "$resume_state"
        fi
        _confirm_resume_log_info "Force resume requested."
        _confirm_resume_log_info "Resuming installation from: $forced_resume_phase"
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

    # Only prompt if --interactive was requested and we have a controlling TTY.
    if [[ "${ACFS_INTERACTIVE:-}" == "true" ]] && (exec 3<>/dev/tty) 2>/dev/null; then
        echo "" >&2
        echo "Options:" >&2
        echo "  [R] Resume from $last_phase_name (default)" >&2
        echo "  [F] Fresh install (wipe state)" >&2
        echo "  [A] Abort" >&2
        echo "" >&2

        local choice
        if [[ "${HAS_GUM:-false}" == "true" ]] && command -v gum &>/dev/null; then
            # Use gum for nicer selection (render UI to the controlling TTY; capture selection on stdout).
            choice=$(gum choose "Resume" "Fresh install" "Abort" < /dev/tty 2> /dev/tty) || choice="Resume"
            case "$choice" in
                "Fresh install")
                    _confirm_resume_log_info "Starting fresh install..."
                    if ! state_backup_and_remove; then
                        _confirm_resume_log_warn "Failed to move state file out of the way. Aborting."
                        return 2
                    fi
                    return 1
                    ;;
                "Abort")
                    _confirm_resume_log_info "Installation aborted."
                    return 2
                    ;;
                *)
                    if [[ -n "$resume_state" ]]; then
                        state_save "$resume_state"
                    fi
                    _confirm_resume_log_info "Resuming installation..."
                    return 0
                    ;;
            esac
        else
            # Fallback to read prompt
            if [[ -t 0 ]]; then
                read -r -p "Choice [R/f/a]: " choice < /dev/tty
            else
                read -r -p "Choice [R/f/a]: " choice < /dev/tty
            fi
            case "${choice,,}" in
                f|fresh)
                    _confirm_resume_log_info "Starting fresh install..."
                    if ! state_backup_and_remove; then
                        _confirm_resume_log_warn "Failed to move state file out of the way. Aborting."
                        return 2
                    fi
                    return 1
                    ;;
                a|abort)
                    _confirm_resume_log_info "Installation aborted."
                    return 2
                    ;;
                *)
                    if [[ -n "$resume_state" ]]; then
                        state_save "$resume_state"
                    fi
                    _confirm_resume_log_info "Resuming installation..."
                    return 0
                    ;;
            esac
        fi
    fi

    # Non-interactive: silent resume (default behavior)
    echo "" >&2
    if [[ -n "$resume_state" ]]; then
        state_save "$resume_state"
    fi
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
        echo -e "${_STATE_BLUE}$msg${_STATE_NC}" >&2
    fi
}

# Helper: Log warning message for confirm_resume
_confirm_resume_log_warn() {
    local msg="$1"
    if [[ "${HAS_GUM:-false}" == "true" ]] && command -v gum &>/dev/null; then
        gum style --foreground "#f9e2af" "$msg" >&2
    else
        echo -e "${_STATE_YELLOW}$msg${_STATE_NC}" >&2
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
#     "upgrade_path": ["25.04", "25.10"],
#     "current_stage": "upgrading",
#     "completed_upgrades": [
#       {"from": "24.04", "to": "25.04", "completed_at": "..."}
#     ],
#     "current_upgrade": {"from": "25.04", "to": "25.10", "started_at": "..."},
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
# Example: state_upgrade_init "24.04" "25.10" '["25.04", "25.10"]'
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

    _state_update_with_jq \
        '
        .ubuntu_upgrade = {
            "enabled": true,
            "started_at": $now,
            "original_version": $orig,
            "target_version": $target,
            "upgrade_path": $path,
            "current_stage": "initializing",
            "completed_upgrades": [],
            "current_upgrade": null,
            "needs_reboot": false,
            "resume_after_reboot": false,
            "last_error": null
        }
        ' \
        --arg now "$now" \
        --arg orig "$original_version" \
        --arg target "$target_version" \
        --argjson path "$upgrade_path"
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

    _state_update_with_jq \
        '
        .ubuntu_upgrade.current_stage = "upgrading" |
        .ubuntu_upgrade.current_upgrade = {
            "from": $from,
            "to": $to,
            "started_at": $now
        }
        ' \
        --arg now "$now" \
        --arg from "$from_version" \
        --arg to "$to_version"
}

# Mark current upgrade step as completed
# Usage: state_upgrade_complete <to_version>
state_upgrade_complete() {
    local to_version="$1"

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    local now
    now="$(date -Iseconds)"

    _state_update_with_jq \
        '
        (.ubuntu_upgrade.current_upgrade.from // "") as $from |
        .ubuntu_upgrade.completed_upgrades = ((.ubuntu_upgrade.completed_upgrades // []) + [{
            "from": $from,
            "to": $to,
            "completed_at": $now
        }]) |
        .ubuntu_upgrade.current_upgrade = null |
        .ubuntu_upgrade.current_stage = "step_complete"
        ' \
        --arg now "$now" \
        --arg to "$to_version"
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
        .ubuntu_upgrade.resume_after_reboot = false |
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

    _state_update_with_jq \
        '
        .ubuntu_upgrade.last_error = $err |
        .ubuntu_upgrade.current_stage = "error"
        ' \
        --arg err "$error_msg"
}

# Mark upgrade sequence as fully completed
# Usage: state_upgrade_mark_complete
state_upgrade_mark_complete() {
    if ! command -v jq &>/dev/null; then
        return 1
    fi

    local now
    now="$(date -Iseconds)"

    _state_update_with_jq \
        '
        .ubuntu_upgrade.current_stage = "completed" |
        .ubuntu_upgrade.completed_at = $now |
        .ubuntu_upgrade.needs_reboot = false |
        .ubuntu_upgrade.resume_after_reboot = false |
        .ubuntu_upgrade.current_upgrade = null
        ' \
        --arg now "$now"
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
    if ! state=$(state_load 2>/dev/null); then
        echo '{"error": "no state"}'
        return 1
    fi

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
# Optimized: Single jq call extracts all fields (was 11 subprocess spawns, now 1)
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

    # Extract all fields in a single jq call (11→1 subprocess spawns)
    # Note: Uses ASCII Unit Separator (0x1f) as delimiter since bash strips null bytes
    # Uses ASCII Record Separator (0x1e) for internal list items to prevent breaking read.
    local extracted
    extracted=$(echo "$state" | jq -r '
        .ubuntu_upgrade as $u |
        [
            ($u.enabled // false | tostring),
            ($u.original_version // ""),
            ($u.target_version // ""),
            ($u.current_stage // ""),
            ($u.completed_upgrades | length | tostring),
            ($u.upgrade_path | length | tostring),
            ($u.completed_upgrades // [] | map("  ✓ \(.from) → \(.to)") | join("\u001e")),
            ($u.current_upgrade.from // ""),
            ($u.current_upgrade.to // ""),
            ($u.last_error // "")
        ] | join("\u001f")
    ')

    # Parse unit-separator-delimited fields
    local enabled original target stage completed_count total_count completed_list current_from current_to error
    IFS=$'\x1f' read -r enabled original target stage completed_count total_count completed_list current_from current_to error <<< "$extracted"

    # Restore newlines in the completed list
    completed_list="${completed_list//[$'\x1e']/$'\n'}"

    if [[ "$enabled" != "true" ]]; then
        echo "No upgrade in progress"
        return 0
    fi

    echo "=== Ubuntu Upgrade Status ==="
    echo "Original: $original → Target: $target"
    echo "Progress: $completed_count/$total_count upgrades completed"
    echo "Stage: $stage"

    # Show completed upgrades
    if [[ "$completed_count" -gt 0 ]] && [[ -n "$completed_list" ]]; then
        echo ""
        echo "Completed upgrades:"
        echo "$completed_list"
    fi

    # Show current upgrade if any
    if [[ -n "$current_from" ]]; then
        echo ""
        echo "Current upgrade: $current_from → $current_to"
    fi

    # Show error if any
    if [[ -n "$error" ]]; then
        echo ""
        echo "Last error: $error"
    fi
}
# Save/update the state file
# Usage: state_save <json_content>
# Returns: 0 on success, 1 on failure
state_save() {
    local content="$1"
    local state_file
    state_file="$(state_get_file)"

    if ! _state_acquire_lock; then
        declare -f log_error &>/dev/null && log_error "state_save: failed to acquire lock"
        return 1
    fi

    local status=0
    if ! state_write_atomic "$state_file" "$content"; then
        declare -f log_error &>/dev/null && log_error "state_save: state_write_atomic failed"
        status=1
    fi

    _state_release_lock
    return $status
}

# Apply a jq mutation while holding the state lock across the full
# read-modify-write cycle. Callers may pass jq arguments after the filter.
_state_update_with_jq() {
    local jq_expr="$1"
    shift

    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required for state_update" >&2
        return 1
    fi

    if ! _state_acquire_lock; then
        return 1
    fi

    local state_file
    state_file="$(state_get_file)" || {
        _state_release_lock
        return 1
    }

    local state
    if ! state=$(state_load); then
        _state_release_lock
        return 1
    fi

    local new_state
    if ! new_state=$(printf '%s' "$state" | jq "$@" "$jq_expr"); then
        _state_release_lock
        return 1
    fi

    local status=0
    if ! state_write_atomic "$state_file" "$new_state"; then
        declare -f log_error &>/dev/null && log_error "state_update: state_write_atomic failed"
        status=1
    fi

    _state_release_lock
    return $status
}

# Update specific fields in state
# Usage: state_update <jq_expression>
# Example: state_update '.current_phase = "cli_tools"'
# Returns: 0 on success, 1 on failure
state_update() {
    local jq_expr="$1"

    _state_update_with_jq "$jq_expr"
}

# Update state with a jq expression plus jq arguments.
# Usage: state_update_with_args <jq_expression> --arg key value [jq flags...]
state_update_with_args() {
    local jq_expr="$1"
    shift

    _state_update_with_jq "$jq_expr" "$@"
}

# Persist the current resume hint while preserving the normal atomic write and
# ownership semantics used for the main state file.
# Usage: state_set_resume_hint <resume_hint>
# Returns: 0 on success, 1 on failure
state_set_resume_hint() {
    local resume_hint="${1-}"

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    if ! _state_acquire_lock; then
        return 1
    fi

    local state
    if ! state=$(state_load); then
        _state_release_lock
        return 1
    fi

    local new_state
    if ! new_state=$(echo "$state" | jq --arg hint "$resume_hint" '
        .resume_hint = (if $hint == "" then null else $hint end)
    '); then
        _state_release_lock
        return 1
    fi

    local save_result=0
    state_save "$new_state" || save_result=$?
    _state_release_lock
    return $save_result
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

    if ! _state_acquire_lock; then
        return 1
    fi

    # Use jq --arg to safely handle steps with quotes/backslashes.
    local state
    if ! state=$(state_load); then
        _state_release_lock
        return 1
    fi

    local start_time
    start_time=$(date +%s)

    local new_state
    if [[ -n "$step" ]]; then
        new_state=$(echo "$state" | jq --arg phase "$phase_id" --arg step "$step" --argjson start "$start_time" '
            .current_phase = $phase |
            .current_step = $step |
            .phase_start_time = $start |
            .failed_phase = null |
            .failed_step = null |
            .failed_error = null
        ') || { _state_release_lock; return 1; }
    else
        new_state=$(echo "$state" | jq --arg phase "$phase_id" --argjson start "$start_time" '
            .current_phase = $phase |
            .current_step = null |
            .phase_start_time = $start |
            .failed_phase = null |
            .failed_step = null |
            .failed_error = null
        ') || { _state_release_lock; return 1; }
    fi

    local save_result=0
    state_save "$new_state" || save_result=$?
    _state_release_lock
    return $save_result
}

# Update the current step within a phase
# Usage: state_step_update <step_description>
state_step_update() {
    local step="$1"

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    if ! _state_acquire_lock; then
        return 1
    fi

    # Use jq's --arg for proper JSON escaping
    local state
    if ! state=$(state_load); then
        _state_release_lock
        return 1
    fi

    local new_state
    if ! new_state=$(echo "$state" | jq --arg step "$step" '.current_step = $step'); then
        _state_release_lock
        return 1
    fi

    local save_result=0
    state_save "$new_state" || save_result=$?
    _state_release_lock
    return $save_result
}

# Mark a phase as completed
# Usage: state_phase_complete <phase_id>
state_phase_complete() {
    local phase_id="$1"

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    if ! _state_acquire_lock; then
        return 1
    fi

    local state
    if ! state=$(state_load); then
        _state_release_lock
        return 1
    fi

    # Calculate duration if start time was recorded
    local start_time duration
    start_time=$(echo "$state" | jq -r '.phase_start_time // empty')
    # Validate start_time is a valid integer before arithmetic to handle corrupted state
    if [[ -n "$start_time" && "$start_time" =~ ^[0-9]+$ ]]; then
        duration=$(($(date +%s) - start_time))
        # Protect against negative duration (clock skew or corrupted timestamp)
        if [[ "$duration" -lt 0 ]]; then
            duration=0
        fi
    else
        duration=0
    fi

    # Add phase to completed list, record duration, clear current
    local new_state
    if ! new_state=$(echo "$state" | jq --arg phase "$phase_id" --argjson dur "$duration" '
        # Preserve insertion order for resume UX while preventing duplicates.
        # NOTE: `unique` sorts arrays, which breaks "last completed phase" reporting.
        .completed_phases = (
          (.completed_phases // []) as $phases |
          if ($phases | index($phase)) == null then $phases + [$phase] else $phases end
        ) |
        .phase_durations[$phase] = $dur |
        .current_phase = null |
        .current_step = null |
        del(.phase_start_time)
    '); then
        _state_release_lock
        return 1
    fi

    local save_result=0
    state_save "$new_state" || save_result=$?
    _state_release_lock
    return $save_result
}

# Mark a phase as failed
# Usage: state_phase_fail <phase_id> <step> <error_message>
state_phase_fail() {
    local phase_id="$1"
    local step="$2"
    local error="$3"

    if ! command -v jq &>/dev/null; then
        return 1
    fi

    if ! _state_acquire_lock; then
        return 1
    fi

    # Use jq's --arg for proper JSON escaping (handles quotes, backslashes, newlines)
    local state
    if ! state=$(state_load); then
        _state_release_lock
        return 1
    fi

    local new_state
    if ! new_state=$(echo "$state" | jq \
        --arg phase "$phase_id" \
        --arg step "$step" \
        --arg err "$error" '
        . as $state |
        ($step == "Execution failed" and ($state.failed_phase // "") == $phase and ($state.failed_step // "") != "") as $preserve_detailed_failure |
        .failed_phase = $phase |
        .failed_step = (if $preserve_detailed_failure then $state.failed_step else $step end) |
        .failed_error = (if $preserve_detailed_failure then ($state.failed_error // $err) else $err end) |
        .current_phase = null |
        .current_step = null
    '); then
        _state_release_lock
        return 1
    fi

    local save_result=0
    state_save "$new_state" || save_result=$?
    _state_release_lock
    return $save_result
}

# Mark a phase as skipped
# Usage: state_phase_skip <phase_id>
state_phase_skip() {
    local phase_id="$1"

    # Best-effort: never abort the installer if we can't persist skip metadata.
    command -v jq &>/dev/null || return 0

    if ! _state_acquire_lock; then
        return 0
    fi

    local state
    state=$(state_load 2>/dev/null) || { _state_release_lock; return 0; }

    local new_state
    new_state=$(echo "$state" | jq --arg phase "$phase_id" '
        # Preserve insertion order while preventing duplicates.
        .skipped_phases = (
          (.skipped_phases // []) as $phases |
          if ($phases | index($phase)) == null then $phases + [$phase] else $phases end
        )
    ' 2>/dev/null) || { _state_release_lock; return 0; }

    state_save "$new_state" 2>/dev/null || true
    _state_release_lock
    return 0
}

# Mark a tool as skipped
# Usage: state_tool_skip <tool_name>
state_tool_skip() {
    local tool="$1"

    # Best-effort: never abort the installer if we can't persist skip metadata.
    command -v jq &>/dev/null || return 0

    if ! _state_acquire_lock; then
        return 0
    fi

    local state
    state=$(state_load 2>/dev/null) || { _state_release_lock; return 0; }

    local new_state
    new_state=$(echo "$state" | jq --arg tool "$tool" '
        # Preserve insertion order while preventing duplicates.
        .skipped_tools = (
          (.skipped_tools // []) as $tools |
          if ($tools | index($tool)) == null then $tools + [$tool] else $tools end
        )
    ' 2>/dev/null) || { _state_release_lock; return 0; }

    state_save "$new_state" 2>/dev/null || true
    _state_release_lock
    return 0
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
        # Fallback: Check for exact match with JSON quote boundaries to avoid
        # false positives (e.g., "base" matching "database"). The completed
        # value is a JSON array string like '["user_setup", "filesystem"]'.
        [[ "$completed" == *"\"$phase_id\""* ]]
    fi
}

# Check if a phase should be skipped
# Usage: state_should_skip_phase <phase_id>
# Returns: 0 if should skip, 1 if should run
state_manifest_phase_to_id() {
    case "${1:-}" in
        1|2) printf '%s\n' "user_setup" ;;
        3) printf '%s\n' "filesystem" ;;
        4) printf '%s\n' "shell_setup" ;;
        5) printf '%s\n' "cli_tools" ;;
        6) printf '%s\n' "languages" ;;
        7) printf '%s\n' "agents" ;;
        8) printf '%s\n' "cloud_db" ;;
        9) printf '%s\n' "stack" ;;
        10) printf '%s\n' "finalize" ;;
        *) return 1 ;;
    esac
}

state_selection_includes_phase() {
    local phase_id="$1"
    local module=""
    local module_phase_num=""
    local module_phase_name=""
    local target_phase=""
    local target_phase_name=""

    if [[ "${ACFS_EFFECTIVE_PLAN+x}" == "x" ]]; then
        if [[ ${#ACFS_EFFECTIVE_PLAN[@]} -gt 0 ]]; then
            for module in "${ACFS_EFFECTIVE_PLAN[@]}"; do
                module_phase_num="${ACFS_MODULE_PHASE[$module]:-}"
                module_phase_name="$(state_manifest_phase_to_id "$module_phase_num" 2>/dev/null || true)"
                if [[ "$module_phase_name" == "$phase_id" ]]; then
                    return 0
                fi
            done
            return 1
        fi
    fi

    if [[ "${ONLY_MODULES+x}" == "x" ]] && [[ ${#ONLY_MODULES[@]} -gt 0 ]]; then
        for module in "${ONLY_MODULES[@]}"; do
            module_phase_num="${ACFS_MODULE_PHASE[$module]:-}"
            module_phase_name="$(state_manifest_phase_to_id "$module_phase_num" 2>/dev/null || true)"
            if [[ "$module_phase_name" == "$phase_id" ]]; then
                return 0
            fi
        done
    fi

    if [[ "${ONLY_PHASES+x}" == "x" ]] && [[ ${#ONLY_PHASES[@]} -gt 0 ]]; then
        for target_phase in "${ONLY_PHASES[@]}"; do
            target_phase_name="$(state_manifest_phase_to_id "$target_phase" 2>/dev/null || true)"
            if [[ "$target_phase_name" == "$phase_id" ]]; then
                return 0
            fi
        done
    fi

    return 1
}

state_has_module_selection() {
    if [[ "${ONLY_MODULES+x}" == "x" ]] && [[ ${#ONLY_MODULES[@]} -gt 0 ]]; then
        return 0
    fi
    if [[ "${ONLY_PHASES+x}" == "x" ]] && [[ ${#ONLY_PHASES[@]} -gt 0 ]]; then
        return 0
    fi
    return 1
}

state_should_skip_phase() {
    local phase_id="$1"

    # Skip if already completed
    if state_is_phase_completed "$phase_id"; then
        # Bug #213: When --only selects a module whose parent phase is already
        # completed, the phase must re-run so the module installer can execute.
        # Check whether any requested module belongs to this phase.
        if state_has_module_selection && state_selection_includes_phase "$phase_id"; then
            return 1
        fi

        return 0
    fi

    # Skip if in skipped_phases
    if command -v jq &>/dev/null; then
        local state
        state=$(state_load) || return 1
        if echo "$state" | jq -e --arg phase "$phase_id" '.skipped_phases | index($phase) != null' &>/dev/null; then
            return 0
        fi
    fi

    # If --only or --only-phase was specified, skip phases that don't match.
    # Uses OR semantics (matching the completed-phases block above): if EITHER
    # a requested module belongs to this phase OR the phase number was explicitly
    # requested, the phase should run.  (Bug #227)
    if state_has_module_selection; then
        if ! state_selection_includes_phase "$phase_id"; then
            return 0  # skip — neither requested modules nor phases match
        fi
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
        # Basic fallback without jq - check first/last non-whitespace chars are braces
        # Note: We can't use ^\{.*\}$ regex because bash regex doesn't match newlines with .
        local trimmed
        trimmed="$(printf '%s' "$content" | tr -d '[:space:]')"
        if [[ "${trimmed:0:1}" != "{" ]] || [[ "${trimmed: -1}" != "}" ]]; then
            echo "State file is not valid JSON (no jq available for detailed check)" >&2
            return 2
        fi

        # Check for schema_version field
        if ! grep -q '"schema_version"' "$state_file"; then
            echo "Legacy v1 state file detected (no schema_version)" >&2
            return 5
        fi

        # Extract version number using sed (POSIX-compatible, works on macOS/BSD)
        local version
        version=$(sed -n 's/.*"schema_version"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$state_file" | head -1)
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
                if ! state_backup_and_remove; then
                    echo "ERROR: Failed to move corrupted state file out of the way; aborting." >&2
                    return 1
                fi
                return 0
            fi

            local response=""
            if [[ -t 0 ]]; then
                read -r -p "Start fresh? [Y/n] " response < /dev/tty
            elif [[ -r /dev/tty ]]; then
                read -r -p "Start fresh? [Y/n] " response < /dev/tty
            else
                echo "ERROR: --yes is required when no TTY is available" >&2
                return 1
            fi
            if [[ "$response" =~ ^[Nn] ]]; then
                return 1
            fi
            if ! state_backup_and_remove; then
                echo "ERROR: Failed to move corrupted state file out of the way; aborting." >&2
                return 1
            fi
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
                if ! state_backup_and_remove; then
                    echo "ERROR: Failed to move invalid state file out of the way; aborting." >&2
                    return 1
                fi
                return 0
            fi

            local response=""
            if [[ -t 0 ]]; then
                read -r -p "Start fresh install? [Y/n] " response < /dev/tty
            elif [[ -r /dev/tty ]]; then
                read -r -p "Start fresh install? [Y/n] " response < /dev/tty
            else
                echo "ERROR: --yes is required when no TTY is available" >&2
                return 1
            fi
            if [[ "$response" =~ ^[Nn] ]]; then
                return 1
            fi
            if ! state_backup_and_remove; then
                echo "ERROR: Failed to move invalid state file out of the way; aborting." >&2
                return 1
            fi
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
                if ! state_backup_and_remove; then
                    echo "ERROR: Failed to move incompatible state file out of the way; aborting." >&2
                    return 1
                fi
                return 0
            fi

            local response=""
            if [[ -t 0 ]]; then
                read -r -p "Start fresh install? [Y/n] " response < /dev/tty
            elif [[ -r /dev/tty ]]; then
                read -r -p "Start fresh install? [Y/n] " response < /dev/tty
            else
                echo "ERROR: --yes is required when no TTY is available" >&2
                return 1
            fi
            if [[ "$response" =~ ^[Nn] ]]; then
                return 1
            fi
            if ! state_backup_and_remove; then
                echo "ERROR: Failed to move incompatible state file out of the way; aborting." >&2
                return 1
            fi
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

                local response=""
                if [[ -t 0 ]]; then
                    read -r -p "Migrate existing state? [Y/n] " response
                elif [[ -r /dev/tty ]]; then
                    read -r -p "Migrate existing state? [Y/n] " response < /dev/tty
                else
                    echo "ERROR: --yes is required when no TTY is available" >&2
                    return 1
                fi
                if [[ "$response" =~ ^[Nn] ]]; then
                    if ! state_backup_and_remove; then
                        echo "ERROR: Failed to move legacy state file out of the way; aborting." >&2
                        return 1
                    fi
                else
                    state_migrate_v1_to_v2
                fi
            else
                echo "Error: jq is required for state migration" >&2
                return 1
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

# Backup and quarantine corrupted state file (move aside)
# Usage: state_backup_and_remove
state_backup_and_remove() {
    local state_file
    state_file="$(state_get_file 2>/dev/null || true)"
    if [[ -z "$state_file" ]]; then
        declare -f log_error &>/dev/null && log_error "state_backup_and_remove: unable to resolve state file path"
        return 1
    fi

    if [[ -f "$state_file" ]]; then
        local expected_user_state=""
        if [[ -n "${ACFS_HOME:-}" ]]; then
            expected_user_state="${ACFS_HOME}/state.json"
        else
            local expected_target_home=""
            expected_target_home="$(state_resolve_target_home 2>/dev/null || true)"
            if [[ -z "$expected_target_home" ]]; then
                declare -f log_error &>/dev/null && log_error "state_backup_and_remove: unable to resolve target home"
                return 1
            fi
            expected_user_state="${expected_target_home}/.acfs/state.json"
        fi
        local expected_system_state="/var/lib/acfs/state.json"

        case "$state_file" in
            "$expected_user_state"|"$expected_system_state") ;;
            *)
                if declare -f log_error &>/dev/null; then
                    log_error "Refusing to move unexpected state file path: $state_file"
                else
                    echo "Refusing to move unexpected state file path: $state_file" >&2
                fi
                echo "Expected: $expected_user_state or $expected_system_state" >&2
                return 1
                ;;
        esac

        local backup_file
        backup_file="${state_file}.backup.$(date +%Y%m%d_%H%M%S)"

        if mv "$state_file" "$backup_file" 2>/dev/null; then
            if declare -f log_warn &>/dev/null; then
                log_warn "Moved state file aside: $backup_file"
            else
                echo "Moved state file aside: $backup_file" >&2
            fi
        else
            if declare -f log_error &>/dev/null; then
                log_error "Failed to move state file to backup: $backup_file"
            else
                echo "Failed to move state file to backup: $backup_file" >&2
            fi
            return 1
        fi
    fi

    return 0
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
        # Uses sed for POSIX compatibility (macOS/BSD don't have grep -oP)
        if grep -q '"schema_version"' "$state_file"; then
            version=$(sed -n 's/.*"schema_version"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$state_file" | head -1)
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
        if ! new_state=$(echo "$state" | jq '
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
        '); then
            return 1
        fi

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
    local_progress_record_installer_phase "$phase_id" "started" 2>/dev/null || true

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
        local_progress_record_installer_phase "$phase_id" "completed" 2>/dev/null || true
        _run_phase_log_success "$display_name" "$duration"
        return 0
    else
        # Failure - record failure state
        local error_msg="Phase '$human_name' failed with exit code $exit_code"
        state_phase_fail "$phase_id" "Execution failed" "$error_msg"
        local_progress_record_installer_phase "$phase_id" "failed" 2>/dev/null || true
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
        echo -e "${_STATE_GRAY}[$display_name] Skipped ($reason)${_STATE_NC}" >&2
    fi
}

# Helper: Log phase start (blue)
_run_phase_log_start() {
    local display_name="$1"

    if [[ "${HAS_GUM:-false}" == "true" ]] && command -v gum &>/dev/null; then
        gum style --foreground "#89b4fa" --bold "[$display_name] Starting..." >&2
    else
        echo -e "${_STATE_BLUE}[$display_name] Starting...${_STATE_NC}" >&2
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
        echo -e "${_STATE_GREEN}$msg${_STATE_NC}" >&2
    fi
}

# Helper: Log phase failure (red)
_run_phase_log_failure() {
    local display_name="$1"
    local exit_code="$2"

    if [[ "${HAS_GUM:-false}" == "true" ]] && command -v gum &>/dev/null; then
        gum style --foreground "#f38ba8" --bold "[$display_name] FAILED (exit code: $exit_code)" >&2
    else
        echo -e "${_STATE_RED}[$display_name] FAILED (exit code: $exit_code)${_STATE_NC}" >&2
    fi
}
