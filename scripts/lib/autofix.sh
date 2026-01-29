#!/bin/bash
# ACFS Auto-Fix Change Recording and Undo System
# Tracks all auto-fix actions with selective undo capability
# Implements crash-safe persistence with fsync, integrity verification, and automatic rollback

# Prevent multiple sourcing
[[ -n "${_ACFS_AUTOFIX_SOURCED:-}" ]] && return 0
_ACFS_AUTOFIX_SOURCED=1

# =============================================================================
# State Directory Configuration
# =============================================================================

ACFS_STATE_DIR="${ACFS_STATE_DIR:-$HOME/.acfs/autofix}"
ACFS_CHANGES_FILE="${ACFS_STATE_DIR}/changes.jsonl"
ACFS_UNDOS_FILE="${ACFS_STATE_DIR}/undos.jsonl"
ACFS_BACKUPS_DIR="${ACFS_STATE_DIR}/backups"
ACFS_LOCK_FILE="${ACFS_STATE_DIR}/.lock"
ACFS_INTEGRITY_FILE="${ACFS_STATE_DIR}/.integrity"

# In-memory change records
declare -A ACFS_CHANGE_RECORDS  # id -> JSON record
declare -a ACFS_CHANGE_ORDER    # Ordered list of change IDs

# Session management
ACFS_SESSION_ID=""
ACFS_AUTOFIX_INITIALIZED=false

# =============================================================================
# Logging Helpers (avoid dependency on logging.sh)
# =============================================================================

_autofix_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        ERROR) echo "[$timestamp] ERROR: $message" >&2 ;;
        WARN)  echo "[$timestamp] WARN:  $message" >&2 ;;
        INFO)  echo "[$timestamp] INFO:  $message" >&2 ;;
        DEBUG) [[ "${ACFS_DEBUG:-}" == "true" ]] && echo "[$timestamp] DEBUG: $message" || true ;;
    esac
}

log_error() { _autofix_log ERROR "$@"; }
log_warn()  { _autofix_log WARN "$@"; }
log_info()  { _autofix_log INFO "$@"; }
log_debug() { _autofix_log DEBUG "$@"; }

# =============================================================================
# Crash-Safe I/O Functions
# =============================================================================

# Explicitly sync a file to disk
fsync_file() {
    local file_path="$1"

    # Method 1: Use Python for true fsync (most reliable)
    # Pass path via sys.argv to avoid shell injection with special characters
    if command -v python3 &>/dev/null; then
        python3 - "$file_path" <<'PYEOF' 2>/dev/null && return 0
import os, sys
file_path = sys.argv[1]
fd = os.open(file_path, os.O_RDONLY)
os.fsync(fd)
os.close(fd)
# Also sync the directory to ensure filename is durable
dir_fd = os.open(os.path.dirname(file_path), os.O_RDONLY)
os.fsync(dir_fd)
os.close(dir_fd)
PYEOF
    fi

    # Method 2: Use dd with fsync flag
    if dd --help 2>&1 | grep -q 'fsync'; then
        dd if=/dev/null of="$file_path" oflag=append,fsync conv=notrunc bs=1 count=0 2>/dev/null
        return $?
    fi

    # Method 3: Fallback to sync (less precise, syncs everything)
    sync
    return 0
}

# Sync a directory's metadata
fsync_directory() {
    local dir_path="$1"

    # Pass path via sys.argv to avoid shell injection with special characters
    if command -v python3 &>/dev/null; then
        python3 - "$dir_path" <<'PYEOF' 2>/dev/null && return 0
import os, sys
dir_path = sys.argv[1]
fd = os.open(dir_path, os.O_RDONLY)
os.fsync(fd)
os.close(fd)
PYEOF
    fi

    sync
    return 0
}

# Atomically write content to a file with fsync
write_atomic() {
    local target_file="$1"
    local content="$2"

    local target_dir
    target_dir=$(dirname "$target_file")
    local temp_file
    temp_file=$(mktemp -p "$target_dir" ".tmp.XXXXXX")

    # Write content to temp file
    printf '%s\n' "$content" > "$temp_file"

    # Sync temp file content to disk
    if ! fsync_file "$temp_file"; then
        log_warn "Failed to fsync temp file: $temp_file"
    fi

    # Atomic rename
    mv "$temp_file" "$target_file"

    # Sync directory to ensure rename is durable
    if ! fsync_directory "$target_dir"; then
        log_warn "Failed to fsync directory: $target_dir"
    fi

    return 0
}

# Atomically append to a file with fsync
append_atomic() {
    local target_file="$1"
    local content="$2"

    local target_dir
    target_dir=$(dirname "$target_file")
    local temp_file
    temp_file=$(mktemp -p "$target_dir" ".tmp.XXXXXX")

    # Copy existing content + new line to temp
    if [[ -f "$target_file" ]]; then
        cat "$target_file" > "$temp_file" || { rm -f "$temp_file"; return 1; }
    fi
    printf '%s\n' "$content" >> "$temp_file" || { rm -f "$temp_file"; return 1; }

    # Sync and rename
    fsync_file "$temp_file"
    mv "$temp_file" "$target_file"
    fsync_directory "$target_dir"

    return 0
}

# =============================================================================
# Integrity Verification
# =============================================================================

# Compute checksum for a change record (excluding the checksum field itself)
compute_record_checksum() {
    local record="$1"

    # Remove the record_checksum field before computing
    local record_without_checksum
    record_without_checksum=$(echo "$record" | jq -c 'del(.record_checksum)')

    echo "$record_without_checksum" | sha256sum | cut -d' ' -f1
}

# Verify integrity of the state files
verify_state_integrity() {
    log_debug "[INTEGRITY] Verifying state file integrity..."

    local errors=0

    # Check changes file
    if [[ -f "$ACFS_CHANGES_FILE" ]]; then
        local line_num=0
        while IFS= read -r line; do
            ((line_num++))

            # Skip empty lines
            [[ -z "$line" ]] && continue

            # Verify JSON is valid
            if ! echo "$line" | jq -e . >/dev/null 2>&1; then
                log_error "[INTEGRITY] Invalid JSON at line $line_num in changes.jsonl"
                ((errors++))
                continue
            fi

            # Verify record checksum if present
            local stored_checksum
            stored_checksum=$(echo "$line" | jq -r '.record_checksum // empty')
            if [[ -n "$stored_checksum" ]]; then
                local computed_checksum
                computed_checksum=$(compute_record_checksum "$line")
                if [[ "$stored_checksum" != "$computed_checksum" ]]; then
                    log_error "[INTEGRITY] Checksum mismatch at line $line_num"
                    log_error "  Stored:   $stored_checksum"
                    log_error "  Computed: $computed_checksum"
                    ((errors++))
                fi
            fi
        done < "$ACFS_CHANGES_FILE"
    fi

    # Check undos file
    if [[ -f "$ACFS_UNDOS_FILE" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if ! echo "$line" | jq -e . >/dev/null 2>&1; then
                log_error "[INTEGRITY] Invalid JSON in undos.jsonl"
                ((errors++))
            fi
        done < "$ACFS_UNDOS_FILE"
    fi

    # Verify backup files match their recorded checksums
    if [[ -f "$ACFS_CHANGES_FILE" ]]; then
        local backup_infos
        backup_infos=$(jq -s '[.[].backups[]? | select(. != null)]' "$ACFS_CHANGES_FILE" 2>/dev/null)
        if [[ -n "$backup_infos" ]] && [[ "$backup_infos" != "[]" ]]; then
            local backup_info backup_path expected_checksum actual_checksum
            while IFS= read -r backup_info; do
                backup_path=$(echo "$backup_info" | jq -r '.backup')
                expected_checksum=$(echo "$backup_info" | jq -r '.checksum')

                if [[ -f "$backup_path" ]]; then
                    actual_checksum=$(sha256sum "$backup_path" | cut -d' ' -f1)
                    if [[ "$actual_checksum" != "$expected_checksum" ]]; then
                        log_error "[INTEGRITY] Backup file corrupted: $backup_path"
                        ((errors++))
                    fi
                else
                    log_warn "[INTEGRITY] Backup file missing: $backup_path"
                fi
            done < <(echo "$backup_infos" | jq -c '.[]')
        fi
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "[INTEGRITY] Found $errors integrity errors"
        return 1
    fi

    log_debug "[INTEGRITY] All state files verified OK"
    return 0
}

# Attempt to repair corrupted state files
repair_state_files() {
    log_info "[REPAIR] Attempting to repair state files..."

    local repaired=0

    # Repair changes file - keep only valid JSON lines
    if [[ -f "$ACFS_CHANGES_FILE" ]]; then
        local temp_file
        temp_file=$(mktemp)
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if echo "$line" | jq -e . >/dev/null 2>&1; then
                echo "$line" >> "$temp_file"
            else
                log_warn "[REPAIR] Discarding invalid line: ${line:0:50}..."
                ((++repaired))
            fi
        done < "$ACFS_CHANGES_FILE"

        if [[ $repaired -gt 0 ]]; then
            mv "$temp_file" "$ACFS_CHANGES_FILE"
            fsync_file "$ACFS_CHANGES_FILE"
            log_info "[REPAIR] Removed $repaired invalid lines from changes.jsonl"
        else
            rm -f "$temp_file"
        fi
    fi

    # Same for undos file
    if [[ -f "$ACFS_UNDOS_FILE" ]]; then
        local temp_file repaired_undos=0
        temp_file=$(mktemp)
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if echo "$line" | jq -e . >/dev/null 2>&1; then
                echo "$line" >> "$temp_file"
            else
                log_warn "[REPAIR] Discarding invalid undo line: ${line:0:50}..."
                ((++repaired_undos))
            fi
        done < "$ACFS_UNDOS_FILE"

        if [[ $repaired_undos -gt 0 ]]; then
            mv "$temp_file" "$ACFS_UNDOS_FILE"
            fsync_file "$ACFS_UNDOS_FILE"
            log_info "[REPAIR] Removed $repaired_undos invalid lines from undos.jsonl"
        else
            rm -f "$temp_file"
        fi
    fi

    log_info "[REPAIR] State file repair complete"
}

# Update the integrity checkpoint file
update_integrity_file() {
    local changes_checksum=""
    local undos_checksum=""
    local backup_count=0

    if [[ -f "$ACFS_CHANGES_FILE" ]]; then
        changes_checksum=$(sha256sum "$ACFS_CHANGES_FILE" | cut -d' ' -f1)
    fi

    if [[ -f "$ACFS_UNDOS_FILE" ]]; then
        undos_checksum=$(sha256sum "$ACFS_UNDOS_FILE" | cut -d' ' -f1)
    fi

    if [[ -d "$ACFS_BACKUPS_DIR" ]]; then
        backup_count=$(find "$ACFS_BACKUPS_DIR" -type f 2>/dev/null | wc -l)
    fi

    local integrity_record
    integrity_record=$(jq -n \
        --arg ts "$(date -Iseconds)" \
        --arg changes "$changes_checksum" \
        --arg undos "$undos_checksum" \
        --argjson backups "$backup_count" \
        '{
            timestamp: $ts,
            changes_file_checksum: $changes,
            undos_file_checksum: $undos,
            backup_file_count: $backups
        }')

    write_atomic "$ACFS_INTEGRITY_FILE" "$integrity_record"
}

# =============================================================================
# State Initialization
# =============================================================================

# Initialize state directory
init_autofix_state() {
    mkdir -p "$ACFS_STATE_DIR" || { log_error "Failed to create state directory: $ACFS_STATE_DIR"; return 1; }
    mkdir -p "$ACFS_BACKUPS_DIR" || { log_error "Failed to create backups directory: $ACFS_BACKUPS_DIR"; return 1; }
    touch "$ACFS_CHANGES_FILE" || { log_error "Failed to create changes file: $ACFS_CHANGES_FILE"; return 1; }
    touch "$ACFS_UNDOS_FILE" || { log_error "Failed to create undos file: $ACFS_UNDOS_FILE"; return 1; }

    # Verify integrity on startup
    if ! verify_state_integrity; then
        log_warn "[AUTO-FIX] State integrity check failed, repairing..."
        repair_state_files
    fi

    ACFS_AUTOFIX_INITIALIZED=true
}

# =============================================================================
# Session Management
# =============================================================================

# Start a new auto-fix session
start_autofix_session() {
    if [[ "$ACFS_AUTOFIX_INITIALIZED" != "true" ]]; then
        init_autofix_state
    fi

    ACFS_SESSION_ID="sess_$(date +%Y%m%d_%H%M%S)_$$"
    log_info "[AUTO-FIX] Starting session: $ACFS_SESSION_ID"

    # Acquire lock (prevent concurrent modifications)
    exec 200>"$ACFS_LOCK_FILE"
    if ! flock -n 200; then
        log_error "Another ACFS process is running auto-fix operations"
        return 1
    fi

    # Write session start marker
    write_atomic "$ACFS_STATE_DIR/.session" "{\"id\": \"$ACFS_SESSION_ID\", \"start\": \"$(date -Iseconds)\", \"pid\": $$}"

    # Reset in-memory state
    ACFS_CHANGE_RECORDS=()
    ACFS_CHANGE_ORDER=()

    return 0
}

# End auto-fix session
end_autofix_session() {
    log_info "[AUTO-FIX] Ending session: $ACFS_SESSION_ID (${#ACFS_CHANGE_ORDER[@]} changes)"

    # Update integrity file
    update_integrity_file

    # Remove session marker
    rm -f "$ACFS_STATE_DIR/.session"

    # Release lock
    flock -u 200 2>/dev/null || true
}

# =============================================================================
# Backup Functions
# =============================================================================

# Create a verified backup of a file with fsync
create_backup() {
    local original_path="$1"
    local _reason="${2:-autofix}"  # Reserved for future use in backup metadata

    if [[ ! -e "$original_path" ]]; then
        echo ""  # Return empty if file doesn't exist
        return 0
    fi

    local filename
    filename=$(basename "$original_path")
    local backup_name="${filename}.${ACFS_SESSION_ID}.backup"
    local backup_path="${ACFS_BACKUPS_DIR}/${backup_name}"

    # Copy with metadata preservation
    cp -p "$original_path" "$backup_path"

    # Explicit fsync to ensure backup is durable
    if ! fsync_file "$backup_path"; then
        log_error "Failed to fsync backup file: $backup_path"
        rm -f "$backup_path"
        return 1
    fi

    # Compute checksum for verification
    local checksum
    checksum=$(sha256sum "$backup_path" | cut -d' ' -f1)

    # Verify backup by comparing checksums
    local original_checksum
    original_checksum=$(sha256sum "$original_path" | cut -d' ' -f1)
    if [[ "$checksum" != "$original_checksum" ]]; then
        log_error "Backup verification failed: checksum mismatch"
        log_error "  Original: $original_checksum"
        log_error "  Backup:   $checksum"
        rm -f "$backup_path"
        return 1
    fi

    log_debug "[BACKUP] Created: $backup_path (checksum: ${checksum:0:16}...)"

    # Return JSON with backup info (compact for embedding in records)
    jq -cn \
        --arg orig "$original_path" \
        --arg back "$backup_path" \
        --arg sum "$checksum" \
        --arg ts "$(date -Iseconds)" \
        '{original: $orig, backup: $back, checksum: $sum, created_at: $ts}'
}

# Verify a backup file's integrity
verify_backup_integrity() {
    local backup_json="$1"

    local backup_path
    backup_path=$(echo "$backup_json" | jq -r '.backup')
    local expected_checksum
    expected_checksum=$(echo "$backup_json" | jq -r '.checksum')

    if [[ ! -f "$backup_path" ]]; then
        log_error "Backup file missing: $backup_path"
        return 1
    fi

    local actual_checksum
    actual_checksum=$(sha256sum "$backup_path" | cut -d' ' -f1)
    if [[ "$actual_checksum" != "$expected_checksum" ]]; then
        log_error "Backup corrupted: $backup_path"
        log_error "  Expected: $expected_checksum"
        log_error "  Actual:   $actual_checksum"
        return 1
    fi

    log_debug "[VERIFY] Backup OK: $backup_path"
    return 0
}

# =============================================================================
# Change Recording
# =============================================================================

# Record a change with all metadata
record_change() {
    local category="$1"
    local description="$2"
    local undo_command="$3"
    local requires_root="${4:-false}"
    local severity="${5:-info}"
    local files_json="${6:-[]}"  # JSON array of affected files
    local backups_json="${7:-[]}"  # JSON array from create_backup
    local depends_on="${8:-[]}"  # JSON array of dependency change IDs

    # Ensure state is initialized
    if [[ "$ACFS_AUTOFIX_INITIALIZED" != "true" ]]; then
        init_autofix_state || return 1
    fi

    # Generate unique ID
    local seq_num=0
    if [[ -f "$ACFS_CHANGES_FILE" ]]; then
        seq_num=$(wc -l < "$ACFS_CHANGES_FILE" 2>/dev/null) || seq_num=0
    fi
    local change_id
    change_id="chg_$(printf '%04d' $((seq_num + 1)))"
    local timestamp
    timestamp=$(date -Iseconds)

    # Build JSON record (without checksum first) - compact for JSONL
    local record
    record=$(jq -cn \
        --arg id "$change_id" \
        --arg ts "$timestamp" \
        --arg cat "$category" \
        --arg desc "$description" \
        --arg undo "$undo_command" \
        --argjson root "$requires_root" \
        --arg sev "$severity" \
        --argjson files "$files_json" \
        --argjson backups "$backups_json" \
        --argjson deps "$depends_on" \
        --arg sess "$ACFS_SESSION_ID" \
        '{
          id: $id,
          timestamp: $ts,
          category: $cat,
          description: $desc,
          undo_command: $undo,
          undo_requires_root: $root,
          severity: $sev,
          files_affected: $files,
          backups: $backups,
          depends_on: $deps,
          session_id: $sess,
          reversible: true,
          undone: false
        }')

    # Compute and add record checksum (compact for JSONL)
    local record_checksum
    record_checksum=$(compute_record_checksum "$record")
    record=$(echo "$record" | jq -c --arg sum "$record_checksum" '. + {record_checksum: $sum}')

    # Store in memory (temporarily disable nounset for associative array access)
    local nounset_was_set=false
    case "$-" in
        *u*) nounset_was_set=true ;;
    esac
    set +u
    ACFS_CHANGE_RECORDS["$change_id"]="$record"
    ACFS_CHANGE_ORDER+=("$change_id")
    if [[ "$nounset_was_set" == "true" ]]; then
        set -u
    fi

    # Persist atomically with fsync
    append_atomic "$ACFS_CHANGES_FILE" "$record"

    log_info "[AUTO-FIX] [$change_id] $description"

    echo "$change_id"  # Return ID for reference
}

# =============================================================================
# Undo Functions
# =============================================================================

# Undo a specific change
undo_change() {
    local change_id="$1"
    local force="${2:-false}"
    local skip_deps="${3:-false}"

    # Load from file if not in memory
    if [[ -z "${ACFS_CHANGE_RECORDS["$change_id"]:-}" ]]; then
        local record
        record=$(grep -F "\"id\":\"$change_id\"" "$ACFS_CHANGES_FILE" | tail -1)
        if [[ -z "$record" ]]; then
            log_error "Unknown change ID: $change_id"
            return 1
        fi
        ACFS_CHANGE_RECORDS["$change_id"]="$record"
    fi

    local record="${ACFS_CHANGE_RECORDS["$change_id"]}"

    # Verify record integrity
    local stored_checksum
    stored_checksum=$(echo "$record" | jq -r '.record_checksum // empty')
    if [[ -n "$stored_checksum" ]]; then
        local computed_checksum
        computed_checksum=$(compute_record_checksum "$record")
        if [[ "$stored_checksum" != "$computed_checksum" ]]; then
            log_error "Record integrity check failed for $change_id"
            if [[ "$force" != "true" ]]; then
                return 1
            fi
            log_warn "Forcing undo despite integrity failure"
        fi
    fi

    # Check if already undone
    if [[ $(echo "$record" | jq -r '.undone') == "true" ]]; then
        log_warn "Change $change_id has already been undone"
        return 0
    fi

    # Check dependencies (things that depend on this must be undone first)
    if [[ "$skip_deps" != "true" ]]; then
        local dependents
        dependents=$(grep -e "\"depends_on\".*$change_id" "$ACFS_CHANGES_FILE" 2>/dev/null | jq -r '.id' 2>/dev/null || true)
        for dep in $dependents; do
            local dep_undone
            dep_undone=$(grep "\"id\":\"$dep\"" "$ACFS_CHANGES_FILE" | tail -1 | jq -r '.undone')
            if [[ "$dep_undone" != "true" ]]; then
                log_error "Cannot undo $change_id: $dep depends on it and hasn't been undone"
                log_error "Undo $dep first, or use --force"
                if [[ "$force" != "true" ]]; then
                    return 1
                fi
            fi
        done
    fi

    local undo_cmd
    undo_cmd=$(echo "$record" | jq -r '.undo_command')
    local requires_root
    requires_root=$(echo "$record" | jq -r '.undo_requires_root')
    local description
    description=$(echo "$record" | jq -r '.description')

    log_info "[UNDO] Reverting: $description"

    # Verify backups are intact
    local backup
    while IFS= read -r backup; do
        [[ -z "$backup" ]] && continue
        if ! verify_backup_integrity "$backup"; then
            if [[ "$force" != "true" ]]; then
                log_error "Backup verification failed. Use --force to override."
                return 1
            fi
            log_warn "Forcing undo despite backup verification failure"
        fi
    done < <(echo "$record" | jq -c '.backups[]?' 2>/dev/null)

    # Execute undo
    local undo_exit_code=0
    if [[ "$requires_root" == "true" ]]; then
        sudo bash -c "$undo_cmd" || undo_exit_code=$?
    else
        bash -c "$undo_cmd" || undo_exit_code=$?
    fi

    if [[ $undo_exit_code -ne 0 ]]; then
        log_error "Undo command failed with exit code $undo_exit_code"
        return 1
    fi

    # Mark as undone (append to file atomically)
    local undo_record
    undo_record=$(jq -cn \
        --arg id "$change_id" \
        --arg ts "$(date -Iseconds)" \
        --argjson code "$undo_exit_code" \
        '{undone: $id, timestamp: $ts, exit_code: $code}')

    append_atomic "$ACFS_UNDOS_FILE" "$undo_record"

    log_info "[UNDO] Successfully reverted: $change_id"
    return 0
}

# Rollback all changes on failure
rollback_all_on_failure() {
    local exit_code="$1"

    if [[ "$exit_code" -eq 0 ]]; then
        return 0
    fi

    if [[ ${#ACFS_CHANGE_ORDER[@]} -eq 0 ]]; then
        return 0
    fi

    echo ""
    log_warn "========================================================================"
    log_warn "  INSTALLATION FAILED! Rolling back auto-fix changes..."
    log_warn "========================================================================"
    echo ""

    local rollback_failed=0

    # Undo in reverse order
    for ((i=${#ACFS_CHANGE_ORDER[@]}-1; i>=0; i--)); do
        local change_id="${ACFS_CHANGE_ORDER[$i]}"
        local record="${ACFS_CHANGE_RECORDS["$change_id"]}"
        local desc
        desc=$(echo "$record" | jq -r '.description')

        log_info "Rolling back: $desc"
        if ! undo_change "$change_id" true true; then
            log_warn "  Failed to rollback $change_id (continuing anyway)"
            ((rollback_failed++))
        fi
    done

    echo ""
    if [[ $rollback_failed -eq 0 ]]; then
        log_info "Rollback complete. System restored to pre-installation state."
    else
        log_warn "Rollback completed with $rollback_failed failures."
        log_warn "  Some changes may not have been reverted."
        log_warn "  Check: $ACFS_CHANGES_FILE"
    fi
}

# =============================================================================
# Undo Summary and Display
# =============================================================================

# Print summary of all changes made
print_undo_summary() {
    local change_count=${#ACFS_CHANGE_ORDER[@]}

    if [[ $change_count -eq 0 ]]; then
        return 0
    fi

    echo ""
    echo "========================================================================"
    echo "  ACFS Auto-Fix Summary"
    echo "========================================================================"
    echo "  Session: $ACFS_SESSION_ID"
    echo "  Changes: $change_count"
    echo "========================================================================"
    echo ""

    printf "%-10s %-12s %-50s\n" "ID" "Category" "Description"
    printf "%-10s %-12s %-50s\n" "----------" "------------" "--------------------------------------------------"

    for change_id in "${ACFS_CHANGE_ORDER[@]}"; do
        local record="${ACFS_CHANGE_RECORDS["$change_id"]}"
        local desc
        desc=$(echo "$record" | jq -r '.description' | cut -c1-50)
        local cat
        cat=$(echo "$record" | jq -r '.category')
        printf "%-10s %-12s %-50s\n" "$change_id" "$cat" "$desc"
    done

    echo ""
    echo "------------------------------------------------------------------------"
    echo " Undo Commands:"
    echo "   Single change:  acfs undo <change_id>"
    echo "   All changes:    acfs undo --all"
    echo "   List changes:   acfs undo --list"
    echo "   Dry run:        acfs undo --dry-run <change_id>"
    echo "   By category:    acfs undo --category nvm"
    echo "   Verify state:   acfs undo --verify"
    echo "------------------------------------------------------------------------"
    echo ""
    echo "State directory: $ACFS_STATE_DIR"
    echo ""
}

# =============================================================================
# ACFS Undo Command Implementation
# =============================================================================

# Implementation of "acfs undo" subcommand
acfs_undo_command() {
    local dry_run=false
    local force=false
    local all=false
    local list_only=false
    local verify_only=false
    local category=""
    local change_ids=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; shift ;;
            --force) force=true; shift ;;
            --all) all=true; shift ;;
            --list) list_only=true; shift ;;
            --verify) verify_only=true; shift ;;
            --category)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "--category requires a value"
                    return 1
                fi
                category="$2"
                shift 2
                ;;
            chg_*) change_ids+=("$1"); shift ;;
            *) log_error "Unknown option: $1"; return 1 ;;
        esac
    done

    # Initialize if needed
    if [[ "$ACFS_AUTOFIX_INITIALIZED" != "true" ]]; then
        init_autofix_state
    fi

    # Verify mode
    if [[ "$verify_only" == "true" ]]; then
        echo "Verifying state file integrity..."
        if verify_state_integrity; then
            echo "All state files OK"
            return 0
        else
            echo "Integrity errors found (see above)"
            return 1
        fi
    fi

    # List mode
    if [[ "$list_only" == "true" ]]; then
        if [[ ! -f "$ACFS_CHANGES_FILE" ]] || [[ ! -s "$ACFS_CHANGES_FILE" ]]; then
            echo "No recorded changes found."
            return 0
        fi
        echo "Recorded changes:"
        # Get list of undone change IDs from the undos file
        local undone_ids=""
        if [[ -f "$ACFS_UNDOS_FILE" ]] && [[ -s "$ACFS_UNDOS_FILE" ]]; then
            undone_ids=$(jq -r '.undone // empty' "$ACFS_UNDOS_FILE" 2>/dev/null | sort -u | tr '\n' '|' | sed 's/|$//')
        fi
        # Display changes with correct undo status by cross-referencing with undos file
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local change_id category desc status
            change_id=$(echo "$line" | jq -r '.id')
            category=$(echo "$line" | jq -r '.category')
            desc=$(echo "$line" | jq -r '.description')
            # Check if this change_id is in the undone list
            if [[ -n "$undone_ids" ]] && echo "$change_id" | grep -qE "^($undone_ids)$"; then
                status="undone"
            else
                status="active"
            fi
            printf "%s\t%s\t%s\t%s\n" "$change_id" "$category" "$desc" "$status"
        done < "$ACFS_CHANGES_FILE" | column -t -s $'\t'
        return 0
    fi

    # Build list of changes to undo
    if [[ "$all" == "true" ]]; then
        mapfile -t change_ids < <(jq -r '.id' "$ACFS_CHANGES_FILE" | sort -r)
    elif [[ -n "$category" ]]; then
        mapfile -t change_ids < <(jq -r "select(.category == \"$category\") | .id" "$ACFS_CHANGES_FILE" | sort -r)
    fi

    if [[ ${#change_ids[@]} -eq 0 ]]; then
        log_error "No changes specified. Use --list to see available changes."
        return 1
    fi

    # Dry run mode
    if [[ "$dry_run" == "true" ]]; then
        echo "Dry run: Would undo the following changes:"
        for change_id in "${change_ids[@]}"; do
            local record
            record=$(grep -F "\"id\":\"$change_id\"" "$ACFS_CHANGES_FILE" | tail -1)
            local desc
            desc=$(echo "$record" | jq -r '.description')
            local undo
            undo=$(echo "$record" | jq -r '.undo_command')
            echo "  $change_id: $desc"
            echo "    Command: $undo"
        done
        return 0
    fi

    # Actually undo
    local failed=0
    for change_id in "${change_ids[@]}"; do
        if ! undo_change "$change_id" "$force"; then
            ((failed++))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        log_warn "$failed undo operations failed"
        return 1
    fi

    log_info "All requested changes have been undone"
    return 0
}

# =============================================================================
# Cleanup Functions
# =============================================================================

# Remove backups older than N days
cleanup_old_backups() {
    local days="${1:-30}"

    log_info "Cleaning up backups older than $days days..."

    local deleted=0
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((deleted++))
    done < <(find "$ACFS_BACKUPS_DIR" -type f -mtime +"$days" -print0 2>/dev/null)

    log_info "Deleted $deleted old backup files"

    # Update integrity file after cleanup
    update_integrity_file
}

# =============================================================================
# Exported Functions for Use by Other Scripts
# =============================================================================

# These are the main entry points for other ACFS scripts:
# - start_autofix_session: Call at start of installation
# - end_autofix_session: Call at end of installation
# - create_backup: Create a backup before modifying a file
# - record_change: Record a change with undo information
# - rollback_all_on_failure: Call in EXIT trap to rollback on failure
# - print_undo_summary: Display summary of changes at end
# - acfs_undo_command: Handle "acfs undo" subcommand
