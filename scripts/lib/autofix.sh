#!/bin/bash
# ACFS Auto-Fix Change Recording and Undo System
# Tracks all auto-fix actions with selective undo capability
# Implements crash-safe persistence with fsync, integrity verification, and automatic rollback

# Prevent multiple sourcing
[[ -n "${_ACFS_AUTOFIX_SOURCED:-}" ]] && return 0
_ACFS_AUTOFIX_SOURCED=1

# This library can be invoked directly for privileged repair and undo work, not
# only through install.sh. Never let a root caller's PATH select the journal,
# backup, or rollback utilities used below. Non-root callers retain their PATH
# so target-user version-manager checks can still find user-installed tools.
if [[ -z "${AUTOFIX_PRIVILEGED_PATH:-}" ]]; then
    readonly AUTOFIX_PRIVILEGED_PATH="/usr/sbin:/usr/bin:/sbin:/bin"
fi
if [[ "$EUID" -eq 0 ]]; then
    export PATH="$AUTOFIX_PRIVILEGED_PATH"
fi

# =============================================================================
# State Directory Configuration
# =============================================================================

autofix_sanitize_abs_nonroot_path() {
    local path="${1:-}"

    [[ -n "$path" ]] || return 1
    [[ "$path" == /* ]] || return 1
    [[ ! "$path" =~ [[:cntrl:]] ]] || return 1

    path="${path%/}"
    [[ -n "$path" && "$path" != "/" ]] || return 1
    [[ "$path" != *//* ]] || return 1
    [[ "$path" != */./* && "$path" != */. ]] || return 1
    [[ "$path" != */../* && "$path" != */.. ]] || return 1

    printf '%s\n' "$path"
}

autofix_validate_target_user() {
    local user="${1:-}"
    [[ -n "$user" ]] || return 1
    [[ "$user" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

autofix_system_binary_path() {
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
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

autofix_set_private_mode() {
    local mode="${1:-}"
    local target_path="${2:-}"
    local chmod_bin=""

    [[ "$mode" == "600" || "$mode" == "700" ]] || return 1
    [[ -n "$target_path" ]] || return 1
    chmod_bin="$(autofix_system_binary_path chmod 2>/dev/null || true)"
    [[ -n "$chmod_bin" ]] || return 1
    "$chmod_bin" "$mode" "$target_path"
}

autofix_state_path_has_symlink_component() {
    local target_path="${1:-}"
    local runtime_home=""
    local trusted_prefix="/"
    local relative_path=""
    local current_path=""
    local component=""
    local -a components=()

    [[ "$(autofix_sanitize_abs_nonroot_path "$target_path" 2>/dev/null || true)" == "$target_path" ]] || return 0

    runtime_home="$(autofix_runtime_home 2>/dev/null || true)"
    if [[ -n "$runtime_home" ]]; then
        case "$target_path" in
            "$runtime_home"|"$runtime_home"/*)
                trusted_prefix="$runtime_home"
                ;;
        esac
    fi
    if [[ "$trusted_prefix" == "/" ]]; then
        case "$target_path" in
            /tmp|/tmp/*)
                # /tmp itself is a system-controlled symlink on some platforms;
                # callers only control descendants beneath this boundary.
                trusted_prefix="/tmp"
                ;;
        esac
    fi

    [[ ! -L "$trusted_prefix" || "$trusted_prefix" == "/tmp" ]] || return 0
    relative_path="${target_path#"$trusted_prefix"}"
    relative_path="${relative_path#/}"
    current_path="$trusted_prefix"
    IFS='/' read -r -a components <<< "$relative_path"
    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        if [[ "$current_path" == "/" ]]; then
            current_path="/$component"
        else
            current_path="$current_path/$component"
        fi
        [[ ! -L "$current_path" ]] || return 0
    done

    return 1
}

autofix_state_layout_is_safe() {
    ! autofix_state_path_has_symlink_component "$ACFS_STATE_DIR" || return 1
    [[ -d "$ACFS_STATE_DIR" && ! -L "$ACFS_STATE_DIR" ]] || return 1
    [[ -d "$ACFS_BACKUPS_DIR" && ! -L "$ACFS_BACKUPS_DIR" ]] || return 1

    local state_file=""
    for state_file in \
        "$ACFS_CHANGES_FILE" \
        "$ACFS_UNDOS_FILE" \
        "$ACFS_LOCK_FILE" \
        "$ACFS_INTEGRITY_FILE"
    do
        if [[ -e "$state_file" || -L "$state_file" ]]; then
            [[ -f "$state_file" && ! -L "$state_file" ]] || return 1
        fi
    done

    return 0
}

autofix_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(autofix_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(autofix_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

autofix_getent_passwd_entry() {
  local user="${1-}"
  local getent_bin=""
  local passwd_entry=""
  local passwd_line=""
  local printed_any=false

  getent_bin="$(autofix_system_binary_path getent 2>/dev/null || true)"
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

  autofix_validate_target_user "$user" || return 1

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

  if [[ -z "$passwd_entry" ]]; then
    local dscl_bin=""
    dscl_bin="$(autofix_system_binary_path dscl 2>/dev/null || true)"
    if [[ -n "$dscl_bin" ]]; then
      local dscl_home=""
      local dscl_output=""
      dscl_output="$("$dscl_bin" . -read "/Users/$user" NFSHomeDirectory 2>/dev/null || true)"
      if [[ "$dscl_output" == NFSHomeDirectory:* ]]; then
        dscl_home="${dscl_output#NFSHomeDirectory:}"
        dscl_home="${dscl_home#"${dscl_home%%[![:space:]]*}"}"
      fi
      if [[ -n "$dscl_home" ]]; then
        passwd_entry="${user}:*:::${user}:${dscl_home}:/bin/zsh"
      fi
    fi
  fi

  if [[ -z "$passwd_entry" ]]; then
    local py_bin=""
    py_bin="$(autofix_system_binary_path python3 2>/dev/null || true)"
    if [[ -n "$py_bin" ]]; then
      local py_home=""
      py_home="$("$py_bin" -c 'import pwd, sys; print(pwd.getpwnam(sys.argv[1]).pw_dir)' "$user" 2>/dev/null || true)"
      if [[ -n "$py_home" ]]; then
        passwd_entry="${user}:*:::${user}:${py_home}:/bin/zsh"
      fi
    fi
  fi

  [[ -n "$passwd_entry" ]] || return 1
  printf '%s\n' "$passwd_entry"
}

autofix_passwd_home_from_entry() {
  local passwd_entry="${1:-}"
  local passwd_home=""

  [[ -n "$passwd_entry" ]] || return 1
  IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
  passwd_home="$(autofix_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
  [[ -n "$passwd_home" ]] || return 1
  printf '%s\n' "$passwd_home"
}

autofix_lookup_passwd_home() {
    local user="${1:-}"
    local passwd_entry=""
    local passwd_home=""

    [[ -n "$user" ]] || return 1

    passwd_entry="$(autofix_getent_passwd_entry "$user" 2>/dev/null || true)"
    passwd_home="$(autofix_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1

    printf '%s\n' "$passwd_home"
}

autofix_home_for_user() {
    local user="${1:-}"
    local expected_home="${2:-}"
    local passwd_home=""

    autofix_validate_target_user "$user" || [[ "$user" == "root" ]] || return 1

    expected_home="$(autofix_sanitize_abs_nonroot_path "$expected_home" 2>/dev/null || true)"

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    passwd_home="$(autofix_lookup_passwd_home "$user" 2>/dev/null || true)"
    if [[ -n "$passwd_home" ]]; then
        printf '%s\n' "$passwd_home"
        return 0
    fi

    if [[ "$(autofix_resolve_current_user 2>/dev/null || true)" == "$user" ]]; then
        passwd_home="$(autofix_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
        if [[ -n "$passwd_home" ]] && { [[ -z "$expected_home" ]] || [[ "$passwd_home" == "$expected_home" ]]; }; then
            printf '%s\n' "$passwd_home"
            return 0
        fi
    fi

    return 1
}

autofix_resolve_current_home() {
    local resolved_home=""
    local current_user=""
    local home_candidate=""

    home_candidate="$(autofix_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"

    current_user="$(autofix_resolve_current_user 2>/dev/null || true)"
    if [[ -n "$current_user" ]]; then
        resolved_home="$(autofix_home_for_user "$current_user" 2>/dev/null || true)"
        if [[ -n "$resolved_home" ]]; then
            printf '%s\n' "$resolved_home"
            return 0
        fi
    fi

    [[ -n "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}
autofix_runtime_home() {
    local current_user=""
    local explicit_home=""
    local runtime_home=""
    local sudo_user="${SUDO_USER:-}"
    local target_user="${TARGET_USER:-}"

    explicit_home="$(autofix_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"
    if [[ "$target_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$target_user" ]]; then
        autofix_validate_target_user "$target_user" || return 1
        runtime_home="$(autofix_home_for_user "$target_user" "$explicit_home" 2>/dev/null || true)"
        if [[ -n "$runtime_home" ]]; then
            printf '%s\n' "$runtime_home"
            return 0
        fi
        current_user="$(autofix_resolve_current_user 2>/dev/null || true)"
        if [[ -n "$explicit_home" && "$target_user" == "$current_user" ]]; then
            printf '%s\n' "$explicit_home"
            return 0
        fi
        return 1
    fi

    if [[ -n "$explicit_home" && -z "$sudo_user" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    if [[ -n "$sudo_user" ]]; then
        autofix_validate_target_user "$sudo_user" || return 1
        runtime_home="$(autofix_home_for_user "$sudo_user" "$explicit_home" 2>/dev/null || true)"
        if [[ -n "$runtime_home" ]]; then
            printf '%s\n' "$runtime_home"
            return 0
        fi
        return 1
    fi

    autofix_resolve_current_home
}

autofix_refresh_state_paths() {
    local runtime_home=""
    local state_dir=""

    state_dir="$(autofix_sanitize_abs_nonroot_path "${ACFS_STATE_DIR:-}" 2>/dev/null || true)"
    if [[ -z "$state_dir" ]]; then
        runtime_home="$(autofix_runtime_home 2>/dev/null || true)"
        if [[ -n "$runtime_home" ]]; then
            state_dir="$runtime_home/.acfs/autofix"
        else
            local id_bin=""
            local current_uid="unknown"
            id_bin="$(autofix_system_binary_path id 2>/dev/null || true)"
            if [[ -n "$id_bin" ]]; then
                current_uid="$("$id_bin" -u 2>/dev/null || true)"
            fi
            [[ "$current_uid" =~ ^[0-9]+$ ]] || current_uid="unknown"
            state_dir="/tmp/acfs-autofix.$current_uid"
        fi
    fi

    ACFS_STATE_DIR="$state_dir"
    ACFS_CHANGES_FILE="${ACFS_STATE_DIR}/changes.jsonl"
    ACFS_UNDOS_FILE="${ACFS_STATE_DIR}/undos.jsonl"
    ACFS_BACKUPS_DIR="${ACFS_STATE_DIR}/backups"
    ACFS_LOCK_FILE="${ACFS_STATE_DIR}/.lock"
    ACFS_INTEGRITY_FILE="${ACFS_STATE_DIR}/.integrity"
}

autofix_refresh_state_paths

# In-memory change records
if declare -gA _acfs_test_assoc &>/dev/null; then
    unset _acfs_test_assoc 2>/dev/null || true
    declare -gA ACFS_CHANGE_RECORDS=()
    declare -ga ACFS_CHANGE_ORDER=()
else
    declare -A ACFS_CHANGE_RECORDS=() 2>/dev/null || ACFS_CHANGE_RECORDS=()
    declare -a ACFS_CHANGE_ORDER=() 2>/dev/null || ACFS_CHANGE_ORDER=()
fi

# Session management
ACFS_SESSION_ID=""
ACFS_AUTOFIX_INITIALIZED=false
ACFS_AUTOFIX_LOCK_FD=""

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

autofix_iso8601_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ"
}

# =============================================================================
# Crash-Safe I/O Functions
# =============================================================================

# Explicitly sync a file to disk
fsync_file() {
    local file_path="$1"

    [[ -f "$file_path" ]] || return 1

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

    # Method 2: Ask GNU sync to flush this path when supported.
    if sync "$file_path" 2>/dev/null; then
        return 0
    fi

    # Method 3: Use dd with fsync conversion. This is only a fallback for
    # minimal environments without Python where path-specific sync is absent.
    if dd --help 2>&1 | grep -q 'fsync'; then
        dd if=/dev/null of="$file_path" oflag=append conv=notrunc,fsync bs=1 count=0 2>/dev/null && return 0
    fi

    # Method 4: Fallback to global sync (less precise, syncs everything)
    sync 2>/dev/null || true
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

autofix_remove_temp_file() {
    local temp_file="${1:-}"
    local rm_bin=""

    [[ -n "$temp_file" ]] || return 0
    rm_bin="$(autofix_system_binary_path rm 2>/dev/null || true)"
    [[ -n "$rm_bin" ]] || return 1
    "$rm_bin" -f -- "$temp_file" 2>/dev/null
}

autofix_sync_backup_path() {
    local target_path="$1"
    local path_type=""
    local entry=""
    local dir_entry=""
    local parent_dir=""

    path_type="$(autofix_detect_path_type "$target_path" 2>/dev/null || true)"

    case "$path_type" in
        file)
            if ! fsync_file "$target_path"; then
                return 1
            fi
            parent_dir="$(dirname "$target_path")"
            fsync_directory "$parent_dir"
            return $?
            ;;
        symlink)
            parent_dir="$(dirname "$target_path")"
            fsync_directory "$parent_dir"
            return $?
            ;;
        directory)
            while IFS= read -r -d '' entry; do
                if ! fsync_file "$entry"; then
                    return 1
                fi
            done < <(find -P "$target_path" -type f -print0 2>/dev/null)

            while IFS= read -r -d '' dir_entry; do
                if ! fsync_directory "$dir_entry"; then
                    return 1
                fi
            done < <(find -P "$target_path" -depth -type d -print0 2>/dev/null)

            parent_dir="$(dirname "$target_path")"
            fsync_directory "$parent_dir"
            return $?
            ;;
    esac

    return 1
}

autofix_cleanup_failed_backup_path() {
    local backup_path="$1"
    local backup_parent=""
    local backups_dir=""
    local rm_bin=""

    [[ "$(autofix_sanitize_abs_nonroot_path "$backup_path" 2>/dev/null || true)" == "$backup_path" ]] || return 1
    backups_dir="$(autofix_sanitize_abs_nonroot_path "${ACFS_BACKUPS_DIR:-}" 2>/dev/null || true)"
    [[ -n "$backups_dir" && "$backup_path" == "$backups_dir/"* ]] || return 1
    backup_parent="$(dirname "$backup_path")"
    rm_bin="$(autofix_system_binary_path rm 2>/dev/null || true)"
    [[ -n "$rm_bin" ]] || return 1

    if autofix_path_exists "$backup_path"; then
        if ! "$rm_bin" -rf "$backup_path"; then
            log_error "Failed to remove incomplete backup path: $backup_path"
            return 1
        fi
    fi

    if ! fsync_directory "$backup_parent"; then
        log_warn "Failed to sync backup parent after cleanup: $backup_parent"
    fi

    return 0
}

autofix_copy_backup_path() {
    local path_type="${1:-}"
    local original_path="${2:-}"
    local backup_path="${3:-}"
    local cp_bin=""

    cp_bin="$(autofix_system_binary_path cp 2>/dev/null || true)"
    [[ -n "$cp_bin" ]] || return 1
    if [[ "$path_type" == "directory" || "$path_type" == "symlink" ]]; then
        "$cp_bin" -a "$original_path" "$backup_path"
    else
        "$cp_bin" -p "$original_path" "$backup_path"
    fi
}

# Atomically write content to a file with fsync
write_atomic() {
    local target_file="$1"
    local content="$2"

    local target_dir
    target_dir=$(dirname "$target_file")
    local temp_file
    temp_file=$(mktemp -p "$target_dir" ".tmp.XXXXXX" 2>/dev/null) || {
        log_error "Failed to create temp file for atomic write: $target_file"
        return 1
    }
    if ! autofix_set_private_mode 600 "$temp_file"; then
        log_error "Failed to secure temp file permissions: $temp_file"
        autofix_remove_temp_file "$temp_file"
        return 1
    fi

    # Write content to temp file
    if ! printf '%s\n' "$content" > "$temp_file"; then
        log_error "Failed to write temp file: $temp_file"
        autofix_remove_temp_file "$temp_file"
        return 1
    fi

    # Sync temp file content to disk
    if ! fsync_file "$temp_file"; then
        log_warn "Failed to fsync temp file: $temp_file"
    fi

    # Atomic rename
    if ! mv "$temp_file" "$target_file"; then
        log_error "Failed to move temp file into place: $target_file"
        autofix_remove_temp_file "$temp_file"
        return 1
    fi

    # Sync directory to ensure rename is durable
    if ! fsync_directory "$target_dir"; then
        log_warn "Failed to fsync directory: $target_dir"
    fi

    autofix_remove_temp_file "$temp_file"
    return 0
}

# Atomically append to a file with fsync
append_atomic() {
    local target_file="$1"
    local content="$2"

    local target_dir
    target_dir=$(dirname "$target_file")
    local temp_file
    temp_file=$(mktemp -p "$target_dir" ".tmp.XXXXXX" 2>/dev/null) || {
        log_error "Failed to create temp file for atomic append: $target_file"
        return 1
    }
    if ! autofix_set_private_mode 600 "$temp_file"; then
        log_error "Failed to secure append temp file permissions: $temp_file"
        autofix_remove_temp_file "$temp_file"
        return 1
    fi

    # Copy existing content + new line to temp
    if [[ -f "$target_file" ]]; then
        cat "$target_file" > "$temp_file" || {
            log_error "Failed to copy existing content to temp file: $temp_file"
            autofix_remove_temp_file "$temp_file"
            return 1
        }
    fi
    if ! printf '%s\n' "$content" >> "$temp_file"; then
        log_error "Failed to append content to temp file: $temp_file"
        autofix_remove_temp_file "$temp_file"
        return 1
    fi

    # Sync and rename
    if ! fsync_file "$temp_file"; then
        log_warn "Failed to fsync temp file: $temp_file"
    fi

    if ! mv "$temp_file" "$target_file"; then
        log_error "Failed to move temp file into place: $target_file"
        autofix_remove_temp_file "$temp_file"
        return 1
    fi

    if ! fsync_directory "$target_dir"; then
        log_warn "Failed to fsync directory: $target_dir"
    fi

    autofix_remove_temp_file "$temp_file"
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
    if ! record_without_checksum=$(printf '%s' "$record" | jq -c 'del(.record_checksum)'); then
        return 1
    fi

    autofix_path_fingerprint "$record_without_checksum"
}

autofix_add_record_checksum() {
    local record="${1:-}"
    local record_checksum=""

    printf '%s' "$record" | jq -e 'type == "object"' >/dev/null 2>&1 || return 1
    record_checksum="$(compute_record_checksum "$record")" || return 1
    [[ "$record_checksum" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s' "$record" | jq -c --arg sum "$record_checksum" '.record_checksum = $sum'
}

autofix_record_checksum_is_valid() {
    local record="${1:-}"
    local stored_checksum=""
    local computed_checksum=""

    stored_checksum="$(printf '%s' "$record" | jq -r '.record_checksum // empty' 2>/dev/null || true)"
    [[ "$stored_checksum" =~ ^[0-9a-f]{64}$ ]] || return 1
    computed_checksum="$(compute_record_checksum "$record")" || return 1
    [[ "$stored_checksum" == "$computed_checksum" ]]
}

autofix_change_record_schema_is_valid() {
    local record="${1:-}"
    local expected_id="${2:-}"

    printf '%s' "$record" | jq -e --arg expected_id "$expected_id" '
        type == "object" and
        (.id | type == "string" and test("^chg_[0-9]{1,18}$")) and
        ($expected_id == "" or .id == $expected_id) and
        (.timestamp | type == "string" and length > 0) and
        (.category | type == "string" and length > 0) and
        (.description | type == "string" and length > 0) and
        (.undo_command | type == "string") and
        (.undo_requires_root | type == "boolean") and
        (.severity | type == "string" and length > 0) and
        (.files_affected | type == "array" and all(.[]; type == "string" and length > 0)) and
        (.post_checksums | type == "array") and
        (.depends_on |
            type == "array" and
            all(.[]; type == "string" and test("^chg_[0-9]{1,18}$"))) and
        (.backups |
            type == "array" and
            all(.[]?;
                type == "object" and
                (.original | type == "string" and length > 0) and
                (.backup | type == "string" and length > 0) and
                (.path_type as $path_type | (["file", "directory", "symlink"] | index($path_type)) != null) and
                (.checksum | type == "string" and test("^[0-9a-f]{64}$"))
            )
        ) and
        (.session_id | type == "string" and length > 0) and
        (.reversible | type == "boolean") and
        (.undone | type == "boolean")
    ' >/dev/null 2>&1
}

autofix_undo_record_schema_is_valid() {
    local record="${1:-}"

    printf '%s' "$record" | jq -e '
        type == "object" and
        (.timestamp | type == "string" and length > 0) and
        (.undone | type == "string" and test("^chg_[0-9]{1,18}$")) and
        (
            (.status == "pending" and ((has("exit_code") | not) or .exit_code == null)) or
            (.status == "applied" and .exit_code == 0) or
            (.status == "failed" and
                (.exit_code | type == "number" and floor == . and . >= 1 and . <= 255))
        )
    ' >/dev/null 2>&1
}

autofix_path_fingerprint() {
    local input="${1:-}"
    local hash_bin=""
    local hash_output=""

    hash_bin="$(autofix_system_binary_path sha256sum 2>/dev/null || true)"
    if [[ -n "$hash_bin" ]]; then
        hash_output="$(printf '%s' "$input" | "$hash_bin")" || return 1
        [[ "$hash_output" == *[[:space:]]* ]] || return 1
        hash_output="${hash_output%%[[:space:]]*}"
        [[ "$hash_output" =~ ^[0-9a-f]{64}$ ]] || return 1
        printf '%s\n' "$hash_output"
        return 0
    fi

    hash_bin="$(autofix_system_binary_path shasum 2>/dev/null || true)"
    if [[ -n "$hash_bin" ]]; then
        hash_output="$(printf '%s' "$input" | "$hash_bin" -a 256)" || return 1
        [[ "$hash_output" == *[[:space:]]* ]] || return 1
        hash_output="${hash_output%%[[:space:]]*}"
        [[ "$hash_output" =~ ^[0-9a-f]{64}$ ]] || return 1
        printf '%s\n' "$hash_output"
        return 0
    fi

    return 1
}

autofix_detect_path_type() {
    local target_path="$1"

    if [[ -L "$target_path" ]]; then
        printf 'symlink\n'
        return 0
    fi

    if [[ -d "$target_path" ]]; then
        printf 'directory\n'
        return 0
    fi

    if [[ -f "$target_path" ]]; then
        printf 'file\n'
        return 0
    fi

    if [[ -e "$target_path" ]]; then
        printf 'other\n'
        return 0
    fi

    printf 'missing\n'
    return 1
}

autofix_path_exists() {
    local target_path="$1"
    [[ -e "$target_path" || -L "$target_path" ]]
}

autofix_trim_leading_whitespace() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    printf '%s\n' "$value"
}

autofix_is_manual_undo_command() {
    local undo_command=""

    undo_command="$(autofix_trim_leading_whitespace "${1:-}")"
    [[ -z "$undo_command" || "$undo_command" == \#* ]]
}

autofix_manual_undo_instructions() {
    local undo_command=""

    undo_command="$(autofix_trim_leading_whitespace "${1:-}")"
    undo_command="${undo_command#\#}"
    autofix_trim_leading_whitespace "$undo_command"
}

autofix_normalize_backups_json() {
    local backups_json="${1:-[]}"

    printf '%s' "$backups_json" | jq -c '
        (if . == null then []
         elif type == "array" then .
         elif type == "object" then [.]
         else error("backups must be an array or object")
         end) as $normalized
        | if all($normalized[]?;
              type == "object" and
              (.original | type == "string" and length > 0) and
              (.backup | type == "string" and length > 0) and
              (.path_type as $path_type | (["file", "directory", "symlink"] | index($path_type)) != null) and
              (.checksum | type == "string" and test("^[0-9a-f]{64}$"))
          ) then
              $normalized
          else
              error("backup entries must contain complete verified metadata")
          end
    ' 2>/dev/null
}

autofix_record_is_reversible() {
    local record_json="$1"
    local undo_command=""
    local reversible="true"

    undo_command="$(printf '%s' "$record_json" | jq -r '.undo_command // ""' 2>/dev/null || true)"
    if autofix_is_manual_undo_command "$undo_command"; then
        return 1
    fi

    reversible="$(printf '%s' "$record_json" | jq -r '.reversible // true' 2>/dev/null || printf 'true\n')"
    [[ "$reversible" == "true" ]]
}

autofix_backup_restore_command() {
    local backup_json="$1"
    local original_path=""
    local backup_path=""
    local backups_dir=""
    local parent_dir=""
    local path_type=""
    local restore_command=""
    local rm_bin=""
    local mkdir_bin=""
    local cp_bin=""

    if ! printf '%s' "$backup_json" | jq -e '
        type == "object" and
        (.original | type == "string" and length > 0) and
        (.backup | type == "string" and length > 0) and
        (.path_type as $path_type | (["file", "directory", "symlink"] | index($path_type)) != null) and
        (.checksum | type == "string" and test("^[0-9a-f]{64}$"))
    ' >/dev/null 2>&1; then
        return 1
    fi

    original_path="$(printf '%s' "$backup_json" | jq -r '.original // empty' 2>/dev/null || true)"
    backup_path="$(printf '%s' "$backup_json" | jq -r '.backup // empty' 2>/dev/null || true)"
    path_type="$(printf '%s' "$backup_json" | jq -r '.path_type // empty' 2>/dev/null || true)"

    [[ "$(autofix_sanitize_abs_nonroot_path "$original_path" 2>/dev/null || true)" == "$original_path" ]] || return 1
    [[ "$(autofix_sanitize_abs_nonroot_path "$backup_path" 2>/dev/null || true)" == "$backup_path" ]] || return 1
    backups_dir="$(autofix_sanitize_abs_nonroot_path "${ACFS_BACKUPS_DIR:-}" 2>/dev/null || true)"
    [[ -n "$backups_dir" ]] || return 1
    [[ "$backup_path" == "$backups_dir/"* ]] || return 1

    # A restore must never target the backup store itself or one of its parents:
    # removing either would destroy the only recovery copy before cp can run.
    [[ "$original_path" != "$backups_dir" ]] || return 1
    [[ "$original_path" != "$backups_dir/"* ]] || return 1
    [[ "$backups_dir" != "$original_path/"* ]] || return 1

    verify_backup_integrity "$backup_json" >/dev/null 2>&1 || return 1

    rm_bin="$(autofix_system_binary_path rm 2>/dev/null || true)"
    mkdir_bin="$(autofix_system_binary_path mkdir 2>/dev/null || true)"
    cp_bin="$(autofix_system_binary_path cp 2>/dev/null || true)"
    [[ -n "$rm_bin" && -n "$mkdir_bin" && -n "$cp_bin" ]] || return 1

    parent_dir="${original_path%/*}"
    [[ -n "$parent_dir" ]] || parent_dir="/"
    if [[ "$path_type" == "directory" ]]; then
        printf -v restore_command '%q -rf %q && %q -p %q && %q -a %q %q' \
            "$rm_bin" "$original_path" "$mkdir_bin" "$parent_dir" "$cp_bin" "$backup_path" "$original_path"
    else
        printf -v restore_command '%q -f %q && %q -p %q && %q -a %q %q' \
            "$rm_bin" "$original_path" "$mkdir_bin" "$parent_dir" "$cp_bin" "$backup_path" "$original_path"
    fi
    printf '%s\n' "$restore_command"
}

autofix_run_restore_command() {
    local restore_command="${1:-}"
    local bash_bin=""
    local env_bin=""

    [[ -n "$restore_command" ]] || return 1

    bash_bin="$(autofix_system_binary_path bash 2>/dev/null || true)"
    env_bin="$(autofix_system_binary_path env 2>/dev/null || true)"
    [[ -n "$bash_bin" && -n "$env_bin" ]] || return 1

    "$env_bin" -i \
        PATH="$AUTOFIX_PRIVILEGED_PATH" \
        HOME="${HOME:-/}" \
        USER="${USER:-}" \
        LOGNAME="${LOGNAME:-${USER:-}}" \
        LANG="${LANG:-C.UTF-8}" \
        "$bash_bin" --noprofile --norc -p -c "$restore_command"
}

autofix_undo_status_map_json() {
    if [[ -f "$ACFS_UNDOS_FILE" ]] && [[ -s "$ACFS_UNDOS_FILE" ]]; then
        local undo_record=""
        while IFS= read -r undo_record; do
            [[ -n "$undo_record" ]] || continue
            autofix_record_checksum_is_valid "$undo_record" || return 1
            autofix_undo_record_schema_is_valid "$undo_record" || return 1
        done < "$ACFS_UNDOS_FILE"

        jq -s -c '
            reduce .[] as $entry ({};
                if ((($entry.undone? // "") | tostring | length) > 0) then
                    .[$entry.undone] = ($entry.status // "applied")
                else
                    .
                end
            )
        ' "$ACFS_UNDOS_FILE" 2>/dev/null
        return $?
    fi

    printf '{}\n'
}

autofix_change_undo_status() {
    local change_id="$1"
    local undo_statuses_json="{}"
    local undo_status=""

    [[ -n "$change_id" ]] || return 1
    undo_statuses_json="$(autofix_undo_status_map_json)" || return 1
    undo_status="$(printf '%s' "$undo_statuses_json" | jq -r --arg id "$change_id" '.[$id] // empty' 2>/dev/null || true)"
    printf '%s\n' "$undo_status"
}

autofix_undone_ids_json() {
    local undo_statuses_json="{}"

    undo_statuses_json="$(autofix_undo_status_map_json)" || return 1
    printf '%s' "$undo_statuses_json" | jq -c '[to_entries[] | select(.value == "applied") | .key]' 2>/dev/null
}

autofix_journals_are_trusted() {
    local change_record=""

    if [[ -f "$ACFS_CHANGES_FILE" && -s "$ACFS_CHANGES_FILE" ]]; then
        while IFS= read -r change_record; do
            [[ -n "$change_record" ]] || continue
            autofix_record_checksum_is_valid "$change_record" || return 1
            autofix_change_record_schema_is_valid "$change_record" || return 1
        done < "$ACFS_CHANGES_FILE"
        jq -s -e 'map(.id) | length == (unique | length)' \
            "$ACFS_CHANGES_FILE" >/dev/null 2>&1 || return 1
    fi

    autofix_undo_status_map_json >/dev/null || return 1
    if [[ -f "$ACFS_UNDOS_FILE" && -s "$ACFS_UNDOS_FILE" ]]; then
        [[ -f "$ACFS_CHANGES_FILE" ]] || return 1
        jq -s -e --slurpfile changes "$ACFS_CHANGES_FILE" '
            all(.[]; .undone as $id | any($changes[]; .id == $id))
        ' "$ACFS_UNDOS_FILE" >/dev/null 2>&1 || return 1
    fi

    return 0
}

autofix_active_backup_paths() {
    local active_backups_json="[]"
    local backup_record=""
    local undone_ids_json="[]"

    autofix_journals_are_trusted || return 1
    [[ -f "$ACFS_CHANGES_FILE" ]] || return 0
    [[ -s "$ACFS_CHANGES_FILE" ]] || return 0

    undone_ids_json="$(autofix_undone_ids_json)" || return 1
    printf '%s' "$undone_ids_json" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    active_backups_json="$(jq -s -c --argjson undone "$undone_ids_json" '
        [
          .[]
          | select((.id // "") as $id | (($undone | index($id)) | not))
          | .backups[]
        ]
    ' "$ACFS_CHANGES_FILE" 2>/dev/null)" || return 1

    while IFS= read -r backup_record; do
        [[ -n "$backup_record" ]] || continue
        verify_backup_integrity "$backup_record" >/dev/null 2>&1 || return 1
    done < <(printf '%s' "$active_backups_json" | jq -c '.[]' 2>/dev/null)

    printf '%s' "$active_backups_json" | jq -r '[.[].backup] | unique[]' 2>/dev/null
}

autofix_backup_entry_count() (
    local -a backup_entries=()

    [[ -d "$ACFS_BACKUPS_DIR" ]] || {
        printf '0\n'
        return 0
    }

    shopt -s dotglob nullglob
    backup_entries=("$ACFS_BACKUPS_DIR"/*)
    printf '%s\n' "${#backup_entries[@]}"
)

# Verify integrity of the state files
verify_state_integrity() {
    log_debug "[INTEGRITY] Verifying state file integrity..."

    local errors=0
    local actual_backup_count=0

    actual_backup_count="$(autofix_backup_entry_count)"

    if [[ -f "$ACFS_INTEGRITY_FILE" ]]; then
        local actual_changes_checksum=""
        local actual_undos_checksum=""
        local expected_backup_count=""
        local expected_changes_checksum=""
        local expected_undos_checksum=""

        if ! jq -e '
            type == "object" and
            (.timestamp | type == "string" and length > 0) and
            (.changes_file_checksum | type == "string" and test("^[0-9a-f]{64}$")) and
            (.undos_file_checksum | type == "string" and test("^[0-9a-f]{64}$")) and
            (.backup_file_count as $count | ($count | type) == "number" and $count >= 0 and ($count | floor) == $count)
        ' "$ACFS_INTEGRITY_FILE" >/dev/null 2>&1; then
            log_error "[INTEGRITY] Integrity checkpoint is malformed"
            ((errors++)) || true
        else
            expected_changes_checksum="$(jq -r '.changes_file_checksum' "$ACFS_INTEGRITY_FILE")"
            expected_undos_checksum="$(jq -r '.undos_file_checksum' "$ACFS_INTEGRITY_FILE")"
            expected_backup_count="$(jq -r '.backup_file_count' "$ACFS_INTEGRITY_FILE")"
            actual_changes_checksum="$(calculate_backup_checksum "$ACFS_CHANGES_FILE" 2>/dev/null || true)"
            actual_undos_checksum="$(calculate_backup_checksum "$ACFS_UNDOS_FILE" 2>/dev/null || true)"
            if [[ -z "$actual_changes_checksum" || "$actual_changes_checksum" != "$expected_changes_checksum" ]]; then
                log_error "[INTEGRITY] changes.jsonl does not match its integrity checkpoint"
                ((errors++)) || true
            fi
            if [[ -z "$actual_undos_checksum" || "$actual_undos_checksum" != "$expected_undos_checksum" ]]; then
                log_error "[INTEGRITY] undos.jsonl does not match its integrity checkpoint"
                ((errors++)) || true
            fi
            if [[ "$actual_backup_count" != "$expected_backup_count" ]]; then
                log_error "[INTEGRITY] Backup entry count does not match its integrity checkpoint"
                ((errors++)) || true
            fi
        fi
    elif [[ -s "$ACFS_CHANGES_FILE" || -s "$ACFS_UNDOS_FILE" || "$actual_backup_count" != "0" ]]; then
        log_error "[INTEGRITY] Integrity checkpoint is missing for non-empty autofix state"
        ((errors++)) || true
    fi

    # Check changes file
    if [[ -f "$ACFS_CHANGES_FILE" ]]; then
        local line_num=0
        while IFS= read -r line; do
            ((line_num++)) || true

            # Skip empty lines
            [[ -z "$line" ]] && continue

            # Verify JSON is valid
            if ! echo "$line" | jq -e . >/dev/null 2>&1; then
                log_error "[INTEGRITY] Invalid JSON at line $line_num in changes.jsonl"
                ((errors++)) || true
                continue
            fi

            if ! autofix_record_checksum_is_valid "$line"; then
                log_error "[INTEGRITY] Missing or invalid record checksum at line $line_num in changes.jsonl"
                ((errors++)) || true
            elif ! autofix_change_record_schema_is_valid "$line"; then
                log_error "[INTEGRITY] Invalid change record schema at line $line_num in changes.jsonl"
                ((errors++)) || true
            fi
        done < "$ACFS_CHANGES_FILE"

        if ! jq -s -e 'map(.id) | length == (unique | length)' \
            "$ACFS_CHANGES_FILE" >/dev/null 2>&1; then
            log_error "[INTEGRITY] changes.jsonl contains duplicate or unreadable change IDs"
            ((errors++)) || true
        fi
    fi

    # Check undos file
    if [[ -f "$ACFS_UNDOS_FILE" ]]; then
        local undo_line_num=0
        while IFS= read -r line; do
            ((undo_line_num++)) || true
            [[ -z "$line" ]] && continue
            if ! echo "$line" | jq -e . >/dev/null 2>&1; then
                log_error "[INTEGRITY] Invalid JSON at line $undo_line_num in undos.jsonl"
                ((errors++)) || true
                continue
            fi
            if ! autofix_record_checksum_is_valid "$line"; then
                log_error "[INTEGRITY] Missing or invalid record checksum at line $undo_line_num in undos.jsonl"
                ((errors++)) || true
            elif ! autofix_undo_record_schema_is_valid "$line"; then
                log_error "[INTEGRITY] Invalid undo record schema at line $undo_line_num in undos.jsonl"
                ((errors++)) || true
            fi
        done < "$ACFS_UNDOS_FILE"

        if [[ -s "$ACFS_UNDOS_FILE" ]]; then
            if [[ ! -f "$ACFS_CHANGES_FILE" ]] ||
               ! jq -s -e --slurpfile changes "$ACFS_CHANGES_FILE" '
                    all(.[]; .undone as $id | any($changes[]; .id == $id))
               ' "$ACFS_UNDOS_FILE" >/dev/null 2>&1; then
                log_error "[INTEGRITY] undos.jsonl references an unknown change ID"
                ((errors++)) || true
            fi
        fi
    fi

    # Verify active backup paths match their recorded checksums
    if [[ -f "$ACFS_CHANGES_FILE" ]]; then
        local backup_infos
        local undone_ids_json="[]"
        if ! undone_ids_json="$(autofix_undone_ids_json)"; then
            log_error "[INTEGRITY] Cannot determine applied undo state from undos.jsonl"
            ((errors++)) || true
            undone_ids_json="[]"
        fi
        if ! backup_infos=$(jq -s --argjson undone "$undone_ids_json" '
            [
              .[]
              | select((.id // "") as $id | (($undone | index($id)) | not))
              | (.backups // [] | if type == "array" then . elif type == "object" then [.] else error("invalid backups") end)[]
            ]
        ' "$ACFS_CHANGES_FILE" 2>/dev/null); then
            log_error "[INTEGRITY] Cannot build the active backup inventory from changes.jsonl"
            ((errors++)) || true
            backup_infos="[]"
        fi
        if [[ -n "$backup_infos" ]] && [[ "$backup_infos" != "[]" ]]; then
            local backup_info
            while IFS= read -r backup_info; do
                if ! verify_backup_integrity "$backup_info"; then
                    ((errors++)) || true
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

    local managed_lock=false
    local managed_lock_fd=""
    if [[ -z "${ACFS_AUTOFIX_LOCK_FD:-}" ]]; then
        autofix_refresh_state_paths
        if autofix_state_path_has_symlink_component "$ACFS_STATE_DIR"; then
            log_error "[REPAIR] Refusing autofix state beneath a symlinked path component"
            return 1
        fi
        if ! mkdir -p "$ACFS_STATE_DIR" 2>/dev/null; then
            log_error "[REPAIR] Cannot create autofix state directory"
            return 1
        fi
        if [[ ! -d "$ACFS_STATE_DIR" || -L "$ACFS_STATE_DIR" ]]; then
            log_error "[REPAIR] Refusing unsafe autofix state directory"
            return 1
        fi
        if ! mkdir -p "$ACFS_BACKUPS_DIR" 2>/dev/null; then
            log_error "[REPAIR] Cannot create autofix backup directory"
            return 1
        fi
        if ! autofix_state_layout_is_safe; then
            log_error "[REPAIR] Refusing unsafe autofix state path types"
            return 1
        fi
        if ! autofix_set_private_mode 700 "$ACFS_STATE_DIR"; then
            log_error "[REPAIR] Cannot secure autofix state directory"
            return 1
        fi
        if ! autofix_set_private_mode 700 "$ACFS_BACKUPS_DIR"; then
            log_error "[REPAIR] Cannot secure autofix backup directory"
            return 1
        fi
        exec {managed_lock_fd}>"$ACFS_LOCK_FILE" 2>/dev/null || managed_lock_fd=""
        if [[ -n "$managed_lock_fd" ]] && ! autofix_set_private_mode 600 "$ACFS_LOCK_FILE"; then
            { exec {managed_lock_fd}>&-; } 2>/dev/null || true
            log_error "[REPAIR] Cannot secure autofix lock file"
            return 1
        fi
        if [[ -n "$managed_lock_fd" ]] && flock -n "$managed_lock_fd" 2>/dev/null; then
            managed_lock=true
        else
            if [[ -n "$managed_lock_fd" ]]; then
                { exec {managed_lock_fd}>&-; } 2>/dev/null || true
            fi
            log_error "[REPAIR] Cannot repair state files: another process holds the autofix lock"
            return 1
        fi
    fi

    if ! autofix_state_layout_is_safe; then
        log_error "[REPAIR] Refusing unsafe autofix state path types"
        if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
            flock -u "$managed_lock_fd" 2>/dev/null || true
            { exec {managed_lock_fd}>&-; } 2>/dev/null || true
        fi
        return 1
    fi

    local repaired=0

    # Repair changes file - keep only valid JSON lines with valid record checksums
    if [[ -f "$ACFS_CHANGES_FILE" ]]; then
        local temp_file
        temp_file=$(mktemp -p "$(dirname "$ACFS_CHANGES_FILE")" ".tmp.XXXXXX" 2>/dev/null) || {
            log_error "Failed to create temp file for changes repair"
            if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
                flock -u "$managed_lock_fd" 2>/dev/null || true
                { exec {managed_lock_fd}>&-; } 2>/dev/null || true
            fi
            return 1
        }
        if ! autofix_set_private_mode 600 "$temp_file"; then
            log_error "[REPAIR] Failed to secure changes repair temp file"
            autofix_remove_temp_file "$temp_file"
            if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
                flock -u "$managed_lock_fd" 2>/dev/null || true
                { exec {managed_lock_fd}>&-; } 2>/dev/null || true
            fi
            return 1
        fi
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if echo "$line" | jq -e . >/dev/null 2>&1; then
                if ! autofix_record_checksum_is_valid "$line"; then
                    log_warn "[REPAIR] Discarding untrusted change record: ${line:0:50}..."
                    ((++repaired))
                    continue
                fi
                if ! printf '%s\n' "$line" >> "$temp_file"; then
                    log_error "[REPAIR] Failed to rewrite repaired changes journal"
                    autofix_remove_temp_file "$temp_file"
                    if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
                        flock -u "$managed_lock_fd" 2>/dev/null || true
                        { exec {managed_lock_fd}>&-; } 2>/dev/null || true
                    fi
                    return 1
                fi
            else
                log_warn "[REPAIR] Discarding invalid line: ${line:0:50}..."
                ((++repaired))
            fi
        done < "$ACFS_CHANGES_FILE"

        if [[ $repaired -gt 0 ]]; then
            if ! mv "$temp_file" "$ACFS_CHANGES_FILE"; then
                log_error "[REPAIR] Failed to replace changes journal with repaired copy"
                autofix_remove_temp_file "$temp_file"
                if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
                    flock -u "$managed_lock_fd" 2>/dev/null || true
                    { exec {managed_lock_fd}>&-; } 2>/dev/null || true
                fi
                return 1
            fi
            if ! fsync_file "$ACFS_CHANGES_FILE"; then
                log_error "[REPAIR] Failed to sync repaired changes journal"
                if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
                    flock -u "$managed_lock_fd" 2>/dev/null || true
                    { exec {managed_lock_fd}>&-; } 2>/dev/null || true
                fi
                return 1
            fi
            log_info "[REPAIR] Removed $repaired invalid lines from changes.jsonl"
        else
            autofix_remove_temp_file "$temp_file"
        fi
    fi

    # Same for undos file
    if [[ -f "$ACFS_UNDOS_FILE" ]]; then
        local temp_file repaired_undos=0
        temp_file=$(mktemp -p "$(dirname "$ACFS_UNDOS_FILE")" ".tmp.XXXXXX" 2>/dev/null) || {
            log_error "Failed to create temp file for undos repair"
            if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
                flock -u "$managed_lock_fd" 2>/dev/null || true
                { exec {managed_lock_fd}>&-; } 2>/dev/null || true
            fi
            return 1
        }
        if ! autofix_set_private_mode 600 "$temp_file"; then
            log_error "[REPAIR] Failed to secure undo repair temp file"
            autofix_remove_temp_file "$temp_file"
            if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
                flock -u "$managed_lock_fd" 2>/dev/null || true
                { exec {managed_lock_fd}>&-; } 2>/dev/null || true
            fi
            return 1
        fi
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if echo "$line" | jq -e . >/dev/null 2>&1; then
                if ! autofix_record_checksum_is_valid "$line"; then
                    log_warn "[REPAIR] Discarding untrusted undo record: ${line:0:50}..."
                    ((++repaired_undos))
                    continue
                fi
                if ! printf '%s\n' "$line" >> "$temp_file"; then
                    log_error "[REPAIR] Failed to rewrite repaired undo journal"
                    autofix_remove_temp_file "$temp_file"
                    if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
                        flock -u "$managed_lock_fd" 2>/dev/null || true
                        { exec {managed_lock_fd}>&-; } 2>/dev/null || true
                    fi
                    return 1
                fi
            else
                log_warn "[REPAIR] Discarding invalid undo line: ${line:0:50}..."
                ((++repaired_undos))
            fi
        done < "$ACFS_UNDOS_FILE"

        if [[ $repaired_undos -gt 0 ]]; then
            if ! mv "$temp_file" "$ACFS_UNDOS_FILE"; then
                log_error "[REPAIR] Failed to replace undo journal with repaired copy"
                autofix_remove_temp_file "$temp_file"
                if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
                    flock -u "$managed_lock_fd" 2>/dev/null || true
                    { exec {managed_lock_fd}>&-; } 2>/dev/null || true
                fi
                return 1
            fi
            if ! fsync_file "$ACFS_UNDOS_FILE"; then
                log_error "[REPAIR] Failed to sync repaired undo journal"
                if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
                    flock -u "$managed_lock_fd" 2>/dev/null || true
                    { exec {managed_lock_fd}>&-; } 2>/dev/null || true
                fi
                return 1
            fi
            log_info "[REPAIR] Removed $repaired_undos invalid lines from undos.jsonl"
        else
            autofix_remove_temp_file "$temp_file"
        fi
    fi

    if ! update_integrity_file; then
        log_error "[REPAIR] Failed to reconcile the integrity checkpoint"
        if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
            flock -u "$managed_lock_fd" 2>/dev/null || true
            { exec {managed_lock_fd}>&-; } 2>/dev/null || true
        fi
        return 1
    fi

    if ! verify_state_integrity; then
        log_error "[REPAIR] State remains unsafe after repairing recoverable journal damage"
        if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
            flock -u "$managed_lock_fd" 2>/dev/null || true
            { exec {managed_lock_fd}>&-; } 2>/dev/null || true
        fi
        return 1
    fi

    if [[ "$managed_lock" == "true" && -n "$managed_lock_fd" ]]; then
        flock -u "$managed_lock_fd" 2>/dev/null || true
        { exec {managed_lock_fd}>&-; } 2>/dev/null || true
    fi

    log_info "[REPAIR] State file repair complete"
}

# Update the integrity checkpoint file
update_integrity_file() {
    local changes_checksum=""
    local undos_checksum=""
    local backup_count=0

    if [[ -f "$ACFS_CHANGES_FILE" ]]; then
        changes_checksum="$(calculate_backup_checksum "$ACFS_CHANGES_FILE")" || {
            log_error "Failed to checksum changes journal"
            return 1
        }
    fi

    if [[ -f "$ACFS_UNDOS_FILE" ]]; then
        undos_checksum="$(calculate_backup_checksum "$ACFS_UNDOS_FILE")" || {
            log_error "Failed to checksum undo journal"
            return 1
        }
    fi

    backup_count="$(autofix_backup_entry_count)"

    local integrity_record
    integrity_record=$(jq -n \
        --arg ts "$(autofix_iso8601_timestamp)" \
        --arg changes "$changes_checksum" \
        --arg undos "$undos_checksum" \
        --argjson backups "$backup_count" \
        '{
            timestamp: $ts,
            changes_file_checksum: $changes,
            undos_file_checksum: $undos,
            backup_file_count: $backups
        }') || {
        log_error "Failed to build integrity checkpoint"
        return 1
    }

    write_atomic "$ACFS_INTEGRITY_FILE" "$integrity_record"
}

# =============================================================================
# State Initialization
# =============================================================================

# Initialize state directory
init_autofix_state() {
    local chmod_failed=0

    ACFS_AUTOFIX_INITIALIZED=false
    autofix_refresh_state_paths
    if autofix_state_path_has_symlink_component "$ACFS_STATE_DIR"; then
        log_error "Refusing autofix state beneath a symlinked path component"
        return 1
    fi
    mkdir -p "$ACFS_STATE_DIR" || { log_error "Failed to create state directory: $ACFS_STATE_DIR"; return 1; }
    if [[ ! -d "$ACFS_STATE_DIR" || -L "$ACFS_STATE_DIR" ]]; then
        log_error "Refusing unsafe autofix state directory"
        return 1
    fi
    mkdir -p "$ACFS_BACKUPS_DIR" || { log_error "Failed to create backups directory: $ACFS_BACKUPS_DIR"; return 1; }
    if ! autofix_state_layout_is_safe; then
        log_error "Refusing unsafe autofix state path types"
        return 1
    fi
    autofix_set_private_mode 700 "$ACFS_STATE_DIR" || chmod_failed=1
    autofix_set_private_mode 700 "$ACFS_BACKUPS_DIR" || chmod_failed=1
    if (( chmod_failed != 0 )); then
        log_error "Failed to secure autofix state directory permissions"
        return 1
    fi
    touch "$ACFS_CHANGES_FILE" || { log_error "Failed to create changes file: $ACFS_CHANGES_FILE"; return 1; }
    touch "$ACFS_UNDOS_FILE" || { log_error "Failed to create undos file: $ACFS_UNDOS_FILE"; return 1; }
    autofix_set_private_mode 600 "$ACFS_CHANGES_FILE" || chmod_failed=1
    autofix_set_private_mode 600 "$ACFS_UNDOS_FILE" || chmod_failed=1
    if (( chmod_failed != 0 )); then
        log_error "Failed to secure autofix journal permissions"
        return 1
    fi

    # Verify integrity on startup
    if ! verify_state_integrity; then
        log_warn "[AUTO-FIX] State integrity check failed, repairing..."
        if ! repair_state_files; then
            log_error "[AUTO-FIX] Failed to repair corrupted state files"
            return 1
        fi
        if ! verify_state_integrity; then
            log_error "[AUTO-FIX] State files remain corrupt after repair"
            return 1
        fi
    fi

    if [[ ! -f "$ACFS_INTEGRITY_FILE" ]] && ! update_integrity_file; then
        log_error "[AUTO-FIX] Failed to create initial integrity checkpoint"
        return 1
    fi

    ACFS_AUTOFIX_INITIALIZED=true
}

# =============================================================================
# Session Management
# =============================================================================

autofix_release_session_lock() {
    local lock_fd="${ACFS_AUTOFIX_LOCK_FD:-}"

    if [[ -n "$lock_fd" ]]; then
        flock -u "$lock_fd" 2>/dev/null || true
        { exec {lock_fd}>&-; } 2>/dev/null || true
        ACFS_AUTOFIX_LOCK_FD=""
    fi
}

autofix_session_active() {
    [[ -n "${ACFS_AUTOFIX_LOCK_FD:-}" && -n "${ACFS_SESSION_ID:-}" ]]
}

autofix_ensure_session() {
    local result_var="${1:-}"

    [[ -n "$result_var" ]] || return 1

    if autofix_session_active; then
        printf -v "$result_var" 'false'
        return 0
    fi

    if ! start_autofix_session; then
        return 1
    fi

    printf -v "$result_var" 'true'
    return 0
}

autofix_finalize_managed_session() {
    local session_owned="${1:-false}"

    if [[ "$session_owned" == "true" ]]; then
        end_autofix_session
        return $?
    fi

    return 0
}

# Start a new auto-fix session
start_autofix_session() {
    autofix_refresh_state_paths
    if [[ "$ACFS_AUTOFIX_INITIALIZED" != "true" ]]; then
        if ! init_autofix_state; then
            log_error "Failed to initialize autofix state"
            return 1
        fi
    fi

    if ! autofix_state_layout_is_safe; then
        log_error "Refusing unsafe autofix state path types"
        return 1
    fi

    ACFS_SESSION_ID="sess_$(date +%Y%m%d_%H%M%S)_$$"
    log_info "[AUTO-FIX] Starting session: $ACFS_SESSION_ID"

    # Acquire lock (prevent concurrent modifications)
    # Ask Bash to allocate an unused descriptor so callers' open FDs are never
    # overwritten and the descriptor number never needs to be reparsed by eval.
    ACFS_AUTOFIX_LOCK_FD=""
    exec {ACFS_AUTOFIX_LOCK_FD}>"$ACFS_LOCK_FILE" 2>/dev/null || ACFS_AUTOFIX_LOCK_FD=""
    if [[ -n "$ACFS_AUTOFIX_LOCK_FD" ]]; then
        if ! autofix_set_private_mode 600 "$ACFS_LOCK_FILE"; then
            log_error "Could not secure autofix lock file"
            autofix_release_session_lock
            ACFS_SESSION_ID=""
            return 1
        fi
        if ! flock -n "$ACFS_AUTOFIX_LOCK_FD"; then
            log_error "Another ACFS process is running auto-fix operations"
            autofix_release_session_lock
            ACFS_SESSION_ID=""
            return 1
        fi
    else
        log_error "Could not acquire autofix lock; aborting to avoid concurrent state corruption"
        ACFS_SESSION_ID=""
        return 1
    fi

    # Verify state integrity while holding the exclusive lock
    if ! verify_state_integrity; then
        log_warn "[AUTO-FIX] State integrity check failed, repairing..."
        if ! repair_state_files; then
            log_error "[AUTO-FIX] Failed to repair corrupted state files"
            autofix_release_session_lock
            ACFS_SESSION_ID=""
            return 1
        fi
        if ! verify_state_integrity; then
            log_error "[AUTO-FIX] State files remain corrupt after repair"
            autofix_release_session_lock
            ACFS_SESSION_ID=""
            return 1
        fi
    fi

    if autofix_path_exists "$ACFS_STATE_DIR/.session"; then
        # The exclusive flock above is the concurrency authority. A marker can
        # survive an interrupted run, and its numeric pid can later be reused
        # by an unrelated live process; kill -0 cannot prove ownership. Since
        # this process holds the lock, atomically replacing the orphaned marker
        # below is safe and avoids a permanent false refusal.
        log_warn "Replacing orphaned autofix session marker while holding the exclusive lock"
    fi

    # Write session start marker
    local session_ts=""
    session_ts="$(autofix_iso8601_timestamp)"
    if ! write_atomic "$ACFS_STATE_DIR/.session" "{\"id\": \"$ACFS_SESSION_ID\", \"start\": \"$session_ts\", \"pid\": $$}"; then
        log_error "Failed to persist autofix session marker"
        autofix_release_session_lock
        ACFS_SESSION_ID=""
        return 1
    fi

    # Reset in-memory state
    ACFS_CHANGE_RECORDS=()
    ACFS_CHANGE_ORDER=()

    return 0
}

# End auto-fix session
end_autofix_session() {
    local finalize_failed=0

    log_info "[AUTO-FIX] Ending session: $ACFS_SESSION_ID (${#ACFS_CHANGE_ORDER[@]} changes)"

    # Update integrity file
    if ! update_integrity_file; then
        log_error "Failed to update autofix integrity checkpoint"
        finalize_failed=1
    fi

    # Remove session marker only after durable finalization succeeds.
    if (( finalize_failed == 0 )); then
        if ! rm -f "$ACFS_STATE_DIR/.session"; then
            log_error "Failed to remove autofix session marker"
            finalize_failed=1
        fi
    fi

    autofix_release_session_lock

    if (( finalize_failed != 0 )); then
        return 1
    fi

    ACFS_SESSION_ID=""
    return 0
}

# =============================================================================
# Backup Functions
# =============================================================================

# Calculate a deterministic checksum for a file or directory path
calculate_backup_checksum() {
    local target_path="$1"
    local path_type=""
    local symlink_target=""
    local hash_bin=""
    local hash_output=""
    local python_bin=""
    local readlink_bin=""

    path_type="$(autofix_detect_path_type "$target_path" 2>/dev/null || true)"

    if [[ "$path_type" == "symlink" ]]; then
        readlink_bin="$(autofix_system_binary_path readlink 2>/dev/null || true)"
        [[ -n "$readlink_bin" ]] || return 1
        symlink_target="$("$readlink_bin" "$target_path" 2>/dev/null || true)"
        [[ -n "$symlink_target" ]] || return 1
        autofix_path_fingerprint "symlink:$symlink_target"
        return 0
    fi

    if [[ -f "$target_path" ]]; then
        hash_bin="$(autofix_system_binary_path sha256sum 2>/dev/null || true)"
        if [[ -n "$hash_bin" ]]; then
            hash_output="$("$hash_bin" "$target_path" 2>/dev/null)" || return 1
            [[ "$hash_output" == *[[:space:]]* ]] || return 1
            hash_output="${hash_output%%[[:space:]]*}"
            [[ "$hash_output" =~ ^[0-9a-f]{64}$ ]] || return 1
            printf '%s\n' "$hash_output"
            return 0
        fi
        hash_bin="$(autofix_system_binary_path shasum 2>/dev/null || true)"
        if [[ -n "$hash_bin" ]]; then
            hash_output="$("$hash_bin" -a 256 "$target_path" 2>/dev/null)" || return 1
            [[ "$hash_output" == *[[:space:]]* ]] || return 1
            hash_output="${hash_output%%[[:space:]]*}"
            [[ "$hash_output" =~ ^[0-9a-f]{64}$ ]] || return 1
            printf '%s\n' "$hash_output"
            return 0
        fi
        return 1
    fi

    if [[ -d "$target_path" ]]; then
        python_bin="$(autofix_system_binary_path python3 2>/dev/null || true)"
        if [[ -n "$python_bin" ]]; then
            "$python_bin" - "$target_path" <<'PYEOF' 2>/dev/null
import hashlib
import os
import stat
import sys

root = sys.argv[1]
h = hashlib.sha256()


def add_field(value):
    h.update(len(value).to_bytes(8, "big"))
    h.update(value)


def visit(path, relative):
    metadata = os.lstat(path)
    mode = stat.S_IMODE(metadata.st_mode)
    relative_bytes = os.fsencode(relative)

    if stat.S_ISLNK(metadata.st_mode):
        h.update(b"L")
        add_field(relative_bytes)
        add_field(str(mode).encode("ascii"))
        add_field(os.fsencode(os.readlink(path)))
        return

    if stat.S_ISDIR(metadata.st_mode):
        h.update(b"D")
        add_field(relative_bytes)
        add_field(str(mode).encode("ascii"))
        with os.scandir(path) as directory:
            entries = sorted(directory, key=lambda entry: os.fsencode(entry.name))
        for entry in entries:
            child_relative = entry.name if not relative else os.path.join(relative, entry.name)
            visit(entry.path, child_relative)
        return

    if stat.S_ISREG(metadata.st_mode):
        h.update(b"F")
        add_field(relative_bytes)
        add_field(str(mode).encode("ascii"))
        add_field(str(metadata.st_size).encode("ascii"))
        with open(path, "rb") as source:
            while True:
                chunk = source.read(65536)
                if not chunk:
                    break
                h.update(chunk)
        return

    raise RuntimeError(f"unsupported path type while checksumming: {path!r}")


visit(root, "")
print(h.hexdigest())
PYEOF
            return $?
        fi
        return 1
    fi

    return 1
}

# Create a verified backup of a file with fsync
create_backup() {
    local original_path="$1"
    local _reason="${2:-autofix}"  # Reserved for future use in backup metadata
    local filename=""
    local full_path_fingerprint=""
    local path_type=""
    local path_fingerprint=""
    local backup_prefix=""
    local backup_index=1
    local backup_path=""

    if [[ "$(autofix_sanitize_abs_nonroot_path "$original_path" 2>/dev/null || true)" != "$original_path" ]]; then
        log_error "Refusing unsafe backup source path: $original_path"
        return 1
    fi
    local backups_dir=""
    backups_dir="$(autofix_sanitize_abs_nonroot_path "${ACFS_BACKUPS_DIR:-}" 2>/dev/null || true)"
    if [[ -z "$backups_dir" || ! -d "$backups_dir" || -L "$backups_dir" ]]; then
        log_error "Refusing unsafe backup destination directory"
        return 1
    fi
    if [[ "$original_path" == "$backups_dir" || "$original_path" == "$backups_dir/"* || "$backups_dir" == "$original_path/"* ]]; then
        log_error "Refusing backup source that overlaps the autofix backup store: $original_path"
        return 1
    fi

    if ! autofix_path_exists "$original_path"; then
        echo ""  # Return empty if file doesn't exist
        return 0
    fi

    filename=$(basename "$original_path")
    path_type="$(autofix_detect_path_type "$original_path" 2>/dev/null || true)"
    case "$path_type" in
        file|directory|symlink) ;;
        *)
            log_error "Refusing unsupported backup source type: $original_path"
            return 1
            ;;
    esac
    if ! full_path_fingerprint="$(autofix_path_fingerprint "$original_path")"; then
        log_error "Failed to fingerprint backup source path: $original_path"
        return 1
    fi
    path_fingerprint="${full_path_fingerprint:0:12}"
    backup_prefix="${filename}.${path_fingerprint}.${ACFS_SESSION_ID}"
    backup_path="${ACFS_BACKUPS_DIR}/${backup_prefix}.${backup_index}.backup"
    while autofix_path_exists "$backup_path"; do
        backup_index=$((backup_index + 1))
        backup_path="${ACFS_BACKUPS_DIR}/${backup_prefix}.${backup_index}.backup"
    done

    # Copy with metadata preservation through a trusted system binary.
    if ! autofix_copy_backup_path "$path_type" "$original_path" "$backup_path"; then
        log_error "Failed to create $path_type backup: $original_path"
        if ! autofix_cleanup_failed_backup_path "$backup_path"; then
            log_error "Failed to clean up incomplete backup path after copy failure: $backup_path"
        fi
        return 1
    fi

    # Explicit fsync to ensure backup is durable
    if ! autofix_sync_backup_path "$backup_path"; then
        log_error "Failed to fsync backup path: $backup_path"
        if ! autofix_cleanup_failed_backup_path "$backup_path"; then
            log_error "Failed to clean up incomplete backup path after sync failure: $backup_path"
        fi
        return 1
    fi

    # Compute checksum for verification
    local checksum
    checksum=$(calculate_backup_checksum "$backup_path") || {
        log_error "Failed to compute checksum for backup: $backup_path"
        if ! autofix_cleanup_failed_backup_path "$backup_path"; then
            log_error "Failed to clean up incomplete backup path after backup checksum failure: $backup_path"
        fi
        return 1
    }

    # Verify backup by comparing checksums
    local original_checksum
    original_checksum=$(calculate_backup_checksum "$original_path") || {
        log_error "Failed to compute checksum for original path: $original_path"
        if ! autofix_cleanup_failed_backup_path "$backup_path"; then
            log_error "Failed to clean up incomplete backup path after original checksum failure: $backup_path"
        fi
        return 1
    }
    if [[ "$checksum" != "$original_checksum" ]]; then
        log_error "Backup verification failed: checksum mismatch"
        log_error "  Original: $original_checksum"
        log_error "  Backup:   $checksum"
        if ! autofix_cleanup_failed_backup_path "$backup_path"; then
            log_error "Failed to clean up incomplete backup path after checksum mismatch: $backup_path"
        fi
        return 1
    fi

    log_debug "[BACKUP] Created: $backup_path (checksum: ${checksum:0:16}...)"

    # Return JSON with backup info (compact for embedding in records)
    jq -cn \
        --arg orig "$original_path" \
        --arg back "$backup_path" \
        --arg type "$path_type" \
        --arg sum "$checksum" \
        --arg ts "$(date -Iseconds)" \
        '{original: $orig, backup: $back, path_type: $type, checksum: $sum, created_at: $ts}'
}

# Verify a backup file's integrity
verify_backup_integrity() {
    local backup_json="$1"

    local backup_path=""
    local backups_dir=""
    local expected_path_type=""
    local expected_checksum=""

    if ! printf '%s' "$backup_json" | jq -e '
        type == "object" and
        (.backup | type == "string" and length > 0) and
        (.path_type as $path_type | (["file", "directory", "symlink"] | index($path_type)) != null) and
        (.checksum | type == "string" and test("^[0-9a-f]{64}$"))
    ' >/dev/null 2>&1; then
        log_error "Backup metadata is malformed"
        return 1
    fi

    backup_path=$(echo "$backup_json" | jq -r '.backup')
    expected_path_type=$(echo "$backup_json" | jq -r '.path_type')
    expected_checksum=$(echo "$backup_json" | jq -r '.checksum')
    [[ "$(autofix_sanitize_abs_nonroot_path "$backup_path" 2>/dev/null || true)" == "$backup_path" ]] || return 1
    backups_dir="$(autofix_sanitize_abs_nonroot_path "${ACFS_BACKUPS_DIR:-}" 2>/dev/null || true)"
    [[ -n "$backups_dir" && "$backup_path" == "$backups_dir/"* ]] || return 1

    if ! autofix_path_exists "$backup_path"; then
        log_error "Backup file missing: $backup_path"
        return 1
    fi

    local actual_path_type=""
    actual_path_type="$(autofix_detect_path_type "$backup_path" 2>/dev/null || true)"
    if [[ "$actual_path_type" != "$expected_path_type" ]]; then
        log_error "Backup type mismatch: $backup_path"
        log_error "  Expected: $expected_path_type"
        log_error "  Actual:   ${actual_path_type:-missing}"
        return 1
    fi

    local actual_checksum
    actual_checksum=$(calculate_backup_checksum "$backup_path") || {
        log_error "Failed to checksum backup path: $backup_path"
        return 1
    }
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

autofix_files_json() {
    if [[ $# -eq 0 ]]; then
        printf '[]\n'
        return 0
    fi

    jq -cn '$ARGS.positional' --args "$@"
}

autofix_calculate_post_checksums_json() {
    local files_json="${1:-[]}"
    local backups_json="${2:-[]}"
    local -a paths=()
    local path=""

    if ! printf '%s' "$files_json" | jq -e \
        'type == "array" and all(.[]; type == "string" and length > 0)' >/dev/null 2>&1; then
        log_error "Invalid affected-files JSON while recording post-fix checksums"
        return 1
    fi
    if ! printf '%s' "$backups_json" | jq -e \
        'type == "array" and all(.[]; type == "object")' >/dev/null 2>&1; then
        log_error "Invalid backup JSON while recording post-fix checksums"
        return 1
    fi

    # Extract paths from files_json
    while IFS= read -r path; do
        [[ -n "$path" ]] && paths+=("$path")
    done < <(printf '%s' "$files_json" | jq -r 'if type == "array" then .[] elif type == "string" then . else empty end' 2>/dev/null)

    # Extract original paths from backups_json
    while IFS= read -r path; do
        [[ -n "$path" ]] && paths+=("$path")
    done < <(printf '%s' "$backups_json" | jq -r '(.[]? // .) | select(type == "object" and (.original? != null)) | .original' 2>/dev/null)

    if [[ ${#paths[@]} -eq 0 ]]; then
        printf '[]\n'
        return 0
    fi

    local -A seen_paths=()
    local -a unique_paths=()
    local p=""
    for p in "${paths[@]}"; do
        [[ -n "$p" ]] || continue
        [[ -n "${seen_paths[$p]+present}" ]] && continue
        seen_paths["$p"]=1
        unique_paths+=("$p")
    done

    local -a entries=()
    for p in "${unique_paths[@]}"; do
        local p_type=""
        local p_sum=""
        p_type="$(autofix_detect_path_type "$p" 2>/dev/null || true)"
        if [[ "$p_type" == "missing" || -z "$p_type" ]]; then
            entries+=("{\"path\":$(printf '%s' "$p" | jq -R .),\"checksum\":null,\"path_type\":\"missing\"}")
        else
            p_sum="$(calculate_backup_checksum "$p" 2>/dev/null || true)"
            if [[ -n "$p_sum" ]]; then
                entries+=("{\"path\":$(printf '%s' "$p" | jq -R .),\"checksum\":$(printf '%s' "$p_sum" | jq -R .),\"path_type\":$(printf '%s' "$p_type" | jq -R .)}")
            else
                log_error "Cannot record a trustworthy post-fix checksum for: $p"
                return 1
            fi
        fi
    done

    if [[ ${#entries[@]} -gt 0 ]]; then
        printf '%s\n' "${entries[@]}" | jq -e -s -c '.' 2>/dev/null
    else
        printf '[]\n'
    fi
}

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
    local reversible="${9:-}"

    [[ -n "$category" && -n "$description" && -n "$severity" ]] || {
        log_error "Change category, description, and severity must be non-empty"
        return 1
    }
    [[ "$requires_root" == "true" || "$requires_root" == "false" ]] || {
        log_error "undo_requires_root must be a boolean"
        return 1
    }
    if ! printf '%s' "$depends_on" | jq -e \
        'type == "array" and all(.[]; type == "string" and test("^chg_[0-9]{1,18}$"))' >/dev/null 2>&1; then
        log_error "Invalid change dependency metadata"
        return 1
    fi

    backups_json="$(autofix_normalize_backups_json "$backups_json")" || {
        log_error "Invalid backups JSON supplied for change: $description"
        return 1
    }
    if [[ -z "$reversible" ]]; then
        if autofix_is_manual_undo_command "$undo_command"; then
            reversible="false"
        else
            reversible="true"
        fi
    fi
    [[ "$reversible" == "true" || "$reversible" == "false" ]] || {
        log_error "reversible must be a boolean"
        return 1
    }

    # Ensure state is initialized
    if [[ "$ACFS_AUTOFIX_INITIALIZED" != "true" ]]; then
        init_autofix_state || return 1
    fi
    if ! autofix_session_active; then
        log_error "record_change requested without an active autofix session lock"
        return 1
    fi

    # Generate unique ID based on max sequence number to avoid collisions after journal repair
    local max_seq=0
    if [[ -f "$ACFS_CHANGES_FILE" ]]; then
        local parsed_max
        parsed_max=$(jq -r '.id // empty' "$ACFS_CHANGES_FILE" 2>/dev/null | sed -n 's/^chg_\([0-9]\{1,18\}\)$/\1/p' | sort -n | tail -1 || true)
        if [[ -n "$parsed_max" && "$parsed_max" =~ ^[0-9]+$ ]]; then
            max_seq=$((10#$parsed_max))
        else
            local line_cnt
            line_cnt=$(wc -l < "$ACFS_CHANGES_FILE" 2>/dev/null || true)
            [[ "$line_cnt" =~ ^[0-9]+$ ]] && max_seq=$((10#$line_cnt))
        fi
    fi
    for existing_id in "${ACFS_CHANGE_ORDER[@]}"; do
        if [[ "$existing_id" =~ ^chg_([0-9]{1,18})$ ]]; then
            local in_mem_seq=$((10#${BASH_REMATCH[1]}))
            if (( in_mem_seq > max_seq )); then
                max_seq=$in_mem_seq
            fi
        fi
    done
    if (( max_seq >= 999999999999999999 )); then
        log_error "Change ID sequence is exhausted"
        return 1
    fi
    local change_id
    change_id="chg_$(printf '%04d' $((max_seq + 1)))"
    local timestamp
    timestamp=$(autofix_iso8601_timestamp)

    # Compute post-fix checksums for affected files
    local post_checksums_json="[]"
    if ! post_checksums_json="$(autofix_calculate_post_checksums_json "$files_json" "$backups_json")"; then
        log_error "Failed to capture post-fix state for change: $description"
        return 1
    fi

    # Build JSON record (without checksum first) - compact for JSONL
    local record
    if ! record=$(jq -cn \
        --arg id "$change_id" \
        --arg ts "$timestamp" \
        --arg cat "$category" \
        --arg desc "$description" \
        --arg undo "$undo_command" \
        --argjson root "$requires_root" \
        --arg sev "$severity" \
        --argjson files "$files_json" \
        --argjson post_sums "$post_checksums_json" \
        --argjson backups "$backups_json" \
        --argjson deps "$depends_on" \
        --arg sess "$ACFS_SESSION_ID" \
        --argjson reversible "$reversible" \
        '{
          id: $id,
          timestamp: $ts,
          category: $cat,
          description: $desc,
          undo_command: $undo,
          undo_requires_root: $root,
          severity: $sev,
          files_affected: $files,
          post_checksums: $post_sums,
          backups: $backups,
          depends_on: $deps,
          session_id: $sess,
          reversible: $reversible,
          undone: false
        }'); then
        log_error "Failed to build change record: $description"
        return 1
    fi

    # Compute and add record checksum (compact for JSONL)
    if ! record="$(autofix_add_record_checksum "$record")"; then
        log_error "Failed to finalize change record: $description"
        return 1
    fi

    # Persist atomically with fsync before mutating in-memory session state
    if ! append_atomic "$ACFS_CHANGES_FILE" "$record"; then
        log_error "Failed to persist change record: $description"
        return 1
    fi

    # Store in memory
    if [[ "$(declare -p ACFS_CHANGE_RECORDS 2>/dev/null)" == *"declare -A"* || "$(declare -p ACFS_CHANGE_RECORDS 2>/dev/null)" == *"declare -gA"* ]]; then
        ACFS_CHANGE_RECORDS["$change_id"]="$record"
    fi
    ACFS_CHANGE_ORDER+=("$change_id")

    log_info "[AUTO-FIX] [$change_id] $description"

    echo "$change_id"  # Return ID for reference
}

# =============================================================================
# Undo Functions
# =============================================================================

# Check whether a change has already been undone
is_change_undone() {
    local change_id="$1"
    local undo_status=""

    if ! undo_status="$(autofix_change_undo_status "$change_id" 2>/dev/null)"; then
        log_error "Cannot determine undo status for $change_id from the undo journal"
        return 1
    fi
    [[ "$undo_status" == "applied" ]]
}

autofix_append_failed_undo_record() {
    local change_id="$1"
    local undo_exit_code="${2:-1}"
    local failed_record=""

    [[ "$undo_exit_code" =~ ^[0-9]+$ ]] || undo_exit_code=1
    if ! failed_record=$(jq -cn \
        --arg id "$change_id" \
        --arg ts "$(autofix_iso8601_timestamp)" \
        --argjson code "$undo_exit_code" \
        --arg status "failed" \
        '{undone: $id, timestamp: $ts, exit_code: $code, status: $status}'); then
        return 1
    fi
    failed_record="$(autofix_add_record_checksum "$failed_record")" || return 1

    append_atomic "$ACFS_UNDOS_FILE" "$failed_record"
}

# Undo a specific change
undo_change() {
    local change_id="$1"
    local force="${2:-false}"
    local skip_deps="${3:-false}"

    if [[ -z "${ACFS_AUTOFIX_LOCK_FD:-}" ]]; then
        log_error "Undo requested without active auto-fix lock"
        return 1
    fi
    if [[ ! "$change_id" =~ ^chg_[0-9]{1,18}$ ]]; then
        log_error "Invalid change ID: $change_id"
        return 1
    fi

    # Load change record directly from journal
    local record=""
    record=$(jq -c --arg id "$change_id" 'select(.id == $id)' \
        "$ACFS_CHANGES_FILE" 2>/dev/null | tail -1)
    if [[ -z "$record" ]]; then
        log_error "Unknown change ID: $change_id"
        return 1
    fi

    # --force may override anti-clobber and backup availability checks, but it
    # must never turn untrusted journal bytes into an executable shell command.
    if ! autofix_record_checksum_is_valid "$record"; then
        log_error "Record integrity check failed for $change_id"
        return 1
    fi
    if ! autofix_change_record_schema_is_valid "$record" "$change_id"; then
        log_error "Change record schema check failed for $change_id"
        return 1
    fi

    local undo_status=""
    if ! undo_status="$(autofix_change_undo_status "$change_id" 2>/dev/null)"; then
        log_error "Cannot determine undo status for $change_id from the undo journal"
        return 1
    fi

    # Check if already undone or stuck in an incomplete prior attempt
    if [[ "$undo_status" == "applied" ]]; then
        log_warn "Change $change_id has already been undone"
        return 0
    fi
    if [[ "$undo_status" == "pending" ]]; then
        log_error "Change $change_id has a pending undo record without completion"
        log_error "Inspect the prior undo attempt before retrying this change"
        return 1
    fi
    if [[ "$undo_status" == "failed" ]]; then
        log_warn "Retrying previously failed undo attempt for $change_id"
    fi

    # Check dependencies (things that depend on this must be undone first)
    if [[ "$skip_deps" != "true" ]]; then
        local dependents
        if ! dependents=$(jq -r --arg id "$change_id" \
            'select((.depends_on // []) | index($id)) | .id' \
            "$ACFS_CHANGES_FILE" 2>/dev/null); then
            log_error "Cannot evaluate dependencies for $change_id from the change journal"
            return 1
        fi
        for dep in $dependents; do
            if ! is_change_undone "$dep"; then
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

    if ! autofix_record_is_reversible "$record"; then
        local manual_instructions=""
        manual_instructions="$(autofix_manual_undo_instructions "$undo_cmd")"
        log_error "Change $change_id is not automatically reversible"
        if [[ -n "$manual_instructions" ]]; then
            log_error "Manual undo instructions: $manual_instructions"
        fi
        return 1
    fi

    # Verify backups are intact. --force is only an anti-clobber override; it
    # must never delete a target when its recovery copy is absent or corrupt.
    if ! printf '%s' "$record" | jq -e '
        (.backups // []) |
        type == "array" and
        all(.[];
            type == "object" and
            (.backup | type == "string" and length > 0) and
            (.path_type as $path_type | (["file", "directory", "symlink"] | index($path_type)) != null) and
            (.checksum | type == "string" and test("^[0-9a-f]{64}$"))
        )
    ' >/dev/null 2>&1; then
        log_error "Change $change_id contains malformed backup metadata"
        return 1
    fi
    local backup
    while IFS= read -r backup; do
        [[ -z "$backup" ]] && continue
        if ! verify_backup_integrity "$backup"; then
            log_error "Backup verification failed; refusing an unrecoverable undo"
            return 1
        fi
    done < <(echo "$record" | jq -c '(.backups // [])[]' 2>/dev/null)

    # Verify post-fix checksums before undoing to prevent overwriting subsequent user edits
    local post_checksums_json="[]"
    if ! printf '%s' "$record" | jq -e '
        def affected_paths:
            [
                ((.files_affected // []) |
                    if type == "array" then .[]
                    elif type == "string" then .
                    else error("invalid files_affected")
                    end),
                ((.backups // []) |
                    if type == "array" then .[]
                    elif type == "object" then .
                    else error("invalid backups")
                    end |
                    select(type == "object") |
                    .original? // empty)
            ] | map(select(type == "string" and length > 0)) | unique | sort;
        (.post_checksums // null) as $post |
        affected_paths as $expected |
        if ($expected | length) == 0 then
            (($post // []) | type == "array" and length == 0)
        else
            ($post | type == "array") and
            (($post | length) == ([$post[].path] | unique | length)) and
            (([$post[].path] | unique | sort) == $expected) and
            all($post[];
                . as $entry |
                type == "object" and
                (.path | type == "string" and length > 0) and
                (
                    (.path_type == "missing" and .checksum == null) or
                    ((["file", "directory", "symlink"] | index($entry.path_type)) != null and
                     (.checksum | type == "string" and test("^[0-9a-f]{64}$")))
                )
            )
        end
    ' >/dev/null 2>&1; then
        log_error "Change $change_id has no complete, trustworthy post-fix snapshot"
        if [[ "$force" != "true" ]]; then
            log_error "Refusing an anti-clobber check bypass. Use --force to override."
            return 1
        fi
        log_warn "Forcing undo without a complete post-fix snapshot"
    else
        post_checksums_json=$(printf '%s' "$record" | jq -c '.post_checksums // []')
    fi
    if [[ "$post_checksums_json" != "[]" ]]; then
        local post_entry=""
        while IFS= read -r post_entry; do
            [[ -z "$post_entry" ]] && continue
            local target_path="" expected_post_sum="" expected_post_type=""
            target_path=$(echo "$post_entry" | jq -r '.path // empty')
            expected_post_sum=$(echo "$post_entry" | jq -r '.checksum // empty')
            expected_post_type=$(echo "$post_entry" | jq -r '.path_type // empty')
            if [[ -z "$target_path" || -z "$expected_post_type" ]]; then
                log_error "Change $change_id contains an invalid post-fix snapshot entry"
                if [[ "$force" != "true" ]]; then
                    return 1
                fi
                log_warn "Forcing undo despite invalid post-fix snapshot metadata"
                continue
            fi

            local actual_type="" actual_sum=""
            actual_type="$(autofix_detect_path_type "$target_path" 2>/dev/null || true)"
            if [[ "$expected_post_type" == "missing" ]]; then
                if [[ "$actual_type" != "missing" && -n "$actual_type" ]]; then
                    log_error "Target path exists but was expected missing after auto-fix: $target_path"
                    if [[ "$force" != "true" ]]; then
                        log_error "Refusing to overwrite subsequent changes without --force."
                        return 1
                    fi
                    log_warn "Forcing undo despite target path creation: $target_path"
                fi
            else
                if [[ "$actual_type" == "missing" || -z "$actual_type" ]]; then
                    log_error "Target file missing since auto-fix: $target_path"
                    if [[ "$force" != "true" ]]; then
                        log_error "Refusing to restore missing target without --force."
                        return 1
                    fi
                    log_warn "Forcing undo despite missing target file: $target_path"
                elif [[ -z "$expected_post_sum" || "$expected_post_sum" == "null" ]]; then
                    log_error "Post-fix checksum is missing for: $target_path"
                    if [[ "$force" != "true" ]]; then
                        log_error "Refusing an anti-clobber check bypass. Use --force to override."
                        return 1
                    fi
                    log_warn "Forcing undo without a post-fix checksum for: $target_path"
                else
                    actual_sum=$(calculate_backup_checksum "$target_path" 2>/dev/null || true)
                    if [[ "$actual_sum" != "$expected_post_sum" ]]; then
                        log_error "Target file has been modified since auto-fix was applied: $target_path"
                        log_error "  Post-fix checksum: $expected_post_sum"
                        log_error "  Current on disk:   $actual_sum"
                        if [[ "$force" != "true" ]]; then
                            log_error "Refusing to clobber later user edits. Use --force to override."
                            return 1
                        fi
                        log_warn "Forcing undo despite subsequent file modifications: $target_path"
                    fi
                fi
            fi
        done < <(echo "$post_checksums_json" | jq -c '.[]' 2>/dev/null)
    fi

    # Record durable intent before executing the undo command so later persistence
    # failures leave an explicit pending state instead of a silent split-brain.
    local pending_record=""
    if ! pending_record=$(jq -cn \
        --arg id "$change_id" \
        --arg ts "$(autofix_iso8601_timestamp)" \
        --arg status "pending" \
        '{undone: $id, timestamp: $ts, status: $status}'); then
        log_error "Failed to build pending undo record for $change_id"
        return 1
    fi
    if ! pending_record="$(autofix_add_record_checksum "$pending_record")"; then
        log_error "Failed to checksum pending undo record for $change_id"
        return 1
    fi

    if ! append_atomic "$ACFS_UNDOS_FILE" "$pending_record"; then
        log_error "Failed to persist pending undo record for $change_id"
        return 1
    fi

    # Execute undo under sanitized environment
    local undo_exit_code=0
    local bash_bin="" env_bin=""
    bash_bin="$(autofix_system_binary_path bash 2>/dev/null || true)"
    if [[ -z "$bash_bin" ]]; then
        log_error "Unable to locate bash for undo command"
        if ! autofix_append_failed_undo_record "$change_id" 127; then
            log_error "Failed to persist failed undo record for $change_id; undo state remains pending"
        fi
        return 1
    fi
    env_bin="$(autofix_system_binary_path env 2>/dev/null || true)"
    if [[ -z "$env_bin" ]]; then
        log_error "Unable to locate env for undo command"
        if ! autofix_append_failed_undo_record "$change_id" 127; then
            log_error "Failed to persist failed undo record for $change_id; undo state remains pending"
        fi
        return 1
    fi

    local rollback_path="$AUTOFIX_PRIVILEGED_PATH"
    if [[ "$EUID" -ne 0 && "$requires_root" != "true" ]]; then
        rollback_path="/usr/local/sbin:/usr/local/bin:$rollback_path"
        if [[ -d "/opt/homebrew/bin" ]]; then
            rollback_path="/opt/homebrew/bin:/opt/homebrew/sbin:$rollback_path"
        fi
    fi
    local rollback_env_args=(
        -i
        PATH="$rollback_path"
        HOME="${HOME:-/}"
        USER="${USER:-}"
        LOGNAME="${LOGNAME:-${USER:-}}"
        LANG="${LANG:-C.UTF-8}"
    )
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
        rollback_env_args+=(
            XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR"
            DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
        )
    fi
    rollback_env_args+=(
        "$bash_bin"
        --noprofile
        --norc
        -p
        -c "$undo_cmd"
    )

    if [[ "$requires_root" == "true" ]]; then
        local sudo_bin=""
        if [[ $EUID -ne 0 ]]; then
            sudo_bin="$(autofix_system_binary_path sudo 2>/dev/null || true)"
            if [[ -z "$sudo_bin" ]]; then
                log_error "Undo command requires root but sudo is unavailable"
                if ! autofix_append_failed_undo_record "$change_id" 127; then
                    log_error "Failed to persist failed undo record for $change_id; undo state remains pending"
                fi
                return 1
            fi
            "$sudo_bin" -n "$env_bin" "${rollback_env_args[@]}" || undo_exit_code=$?
        else
            "$env_bin" "${rollback_env_args[@]}" || undo_exit_code=$?
        fi
    else
        "$env_bin" "${rollback_env_args[@]}" || undo_exit_code=$?
    fi

    if [[ $undo_exit_code -ne 0 ]]; then
        if ! autofix_append_failed_undo_record "$change_id" "$undo_exit_code"; then
            log_error "Undo command failed with exit code $undo_exit_code"
            log_error "Failed to persist failed undo record for $change_id; undo state remains pending"
            return 1
        fi
        log_error "Undo command failed with exit code $undo_exit_code"
        return 1
    fi

    # Mark as undone (append completion after the pending intent entry)
    local undo_record
    if ! undo_record=$(jq -cn \
        --arg id "$change_id" \
        --arg ts "$(autofix_iso8601_timestamp)" \
        --argjson code "$undo_exit_code" \
        --arg status "applied" \
        '{undone: $id, timestamp: $ts, exit_code: $code, status: $status}'); then
        log_error "Failed to build undo record for $change_id"
        return 1
    fi
    local updated_record=""
    if ! undo_record="$(autofix_add_record_checksum "$undo_record")"; then
        log_error "Failed to checksum undo record for $change_id"
        return 1
    fi
    if ! updated_record=$(printf '%s' "$record" | jq -c 'del(.record_checksum) | .undone = true'); then
        log_error "Failed to update in-memory undo state for $change_id"
        return 1
    fi
    if ! updated_record="$(autofix_add_record_checksum "$updated_record")"; then
        log_error "Failed to checksum in-memory undo state for $change_id"
        return 1
    fi

    if ! append_atomic "$ACFS_UNDOS_FILE" "$undo_record"; then
        log_error "Undo completed but failed to persist completion for $change_id"
        log_error "Undo state remains pending; inspect before retrying this change"
        return 1
    fi

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
        local record=""
        record=$(jq -c --arg id "$change_id" 'select(.id == $id)' \
            "$ACFS_CHANGES_FILE" 2>/dev/null | tail -1)
        local desc
        desc=$(echo "$record" | jq -r '.description')

        log_info "Rolling back: $desc"
        if ! undo_change "$change_id" true true; then
            log_warn "  Failed to rollback $change_id (continuing anyway)"
            ((rollback_failed++)) || true
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
    local undo_statuses_json="{}"

    if [[ $change_count -eq 0 ]]; then
        return 0
    fi

    if ! undo_statuses_json="$(autofix_undo_status_map_json)"; then
        log_error "Cannot summarize changes because the undo journal is malformed"
        return 1
    fi

    echo ""
    echo "========================================================================"
    echo "  ACFS Auto-Fix Summary"
    echo "========================================================================"
    echo "  Session: $ACFS_SESSION_ID"
    echo "  Changes: $change_count"
    echo "========================================================================"
    echo ""

    printf "%-10s %-12s %-10s %-50s\n" "ID" "Category" "Status" "Description"
    printf "%-10s %-12s %-10s %-50s\n" "----------" "------------" "----------" "--------------------------------------------------"

    for change_id in "${ACFS_CHANGE_ORDER[@]}"; do
        local record=""
        record=$(jq -c --arg id "$change_id" 'select(.id == $id)' \
            "$ACFS_CHANGES_FILE" 2>/dev/null | tail -1)
        local desc
        desc=$(echo "$record" | jq -r '.description' | cut -c1-50)
        local cat
        cat=$(echo "$record" | jq -r '.category')
        local status="active"
        local undo_status=""
        undo_status="$(printf '%s' "$undo_statuses_json" | jq -r --arg id "$change_id" '.[$id] // empty' 2>/dev/null || true)"
        if [[ "$undo_status" == "applied" ]]; then
            status="undone"
        elif [[ "$undo_status" == "pending" ]]; then
            status="pending"
        elif ! autofix_record_is_reversible "$record"; then
            status="manual"
        fi
        printf "%-10s %-12s %-10s %-50s\n" "$change_id" "$cat" "$status" "$desc"
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
    local everything=false
    local list_only=false
    local verify_only=false
    local category=""
    local change_ids=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; shift ;;
            --force) force=true; shift ;;
            --all) all=true; shift ;;
            --everything) all=true; everything=true; shift ;;
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
            chg_*)
                if [[ ! "$1" =~ ^chg_[0-9]{1,18}$ ]]; then
                    log_error "Invalid change ID: $1"
                    return 1
                fi
                change_ids+=("$1")
                shift
                ;;
            *) log_error "Unknown option: $1"; return 1 ;;
        esac
    done

    # Initialize if needed
    if [[ "$ACFS_AUTOFIX_INITIALIZED" != "true" ]]; then
        init_autofix_state || return 1
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
        local undone_ids_json="[]"
        local undo_statuses_json="{}"
        local list_output=""
        if ! undone_ids_json="$(autofix_undone_ids_json)" ||
           ! undo_statuses_json="$(autofix_undo_status_map_json)"; then
            log_error "Cannot list changes because the undo journal is malformed"
            return 1
        fi
        list_output="$(jq -r --argjson undone "$undone_ids_json" --argjson undo_statuses "$undo_statuses_json" '
            [
              .id,
              .category,
              (
                (.id // "") as $id
                | ($undo_statuses[$id] // "") as $undo_state
                | ((.undo_command // "") | gsub("^\\s+"; "")) as $undo
                | if ($undone | index($id)) then "undone"
                  elif ($undo_state == "pending") then "pending"
                  elif (((.reversible // true) == false) or ($undo == "") or ($undo | startswith("#"))) then "manual"
                  else "active"
                  end
              ),
              .description
            ] | @tsv
        ' "$ACFS_CHANGES_FILE")"
        if command -v column >/dev/null 2>&1; then
            printf '%s\n' "$list_output" | column -t -s $'\t'
        else
            printf '%s\n' "$list_output"
        fi
        return 0
    fi

    # Build list of changes to undo
    local undone_ids_json="[]"
    local undo_statuses_json="{}"
    if ! undone_ids_json="$(autofix_undone_ids_json)" ||
       ! undo_statuses_json="$(autofix_undo_status_map_json)"; then
        log_error "Cannot select changes because the undo journal is malformed"
        return 1
    fi
    if [[ "$all" == "true" ]]; then
        # --all is documented as "undo the last session"; without a session
        # filter it silently reverted every change ever recorded, across
        # sessions (including root-level sshd_config edits). --everything
        # keeps the old behaviour for deliberate full rollbacks.
        local undo_session_filter=""
        if [[ "$everything" != "true" ]]; then
            undo_session_filter="$(jq -r 'select((.session_id // "") != "") | .session_id' "$ACFS_CHANGES_FILE" 2>/dev/null | tail -n 1 || true)"
        fi
        change_ids=()
        while IFS= read -r _cid; do
            [[ -n "$_cid" ]] && change_ids+=("$_cid")
        done < <(jq -r --argjson undone "$undone_ids_json" --argjson undo_statuses "$undo_statuses_json" --arg sess "$undo_session_filter" 'select((.id // "") as $id | (($undone | index($id)) | not) and (($undo_statuses[$id] // "") != "pending")) | select($sess == "" or (.session_id // "") == $sess) | .id' "$ACFS_CHANGES_FILE" | sort -r)
        if [[ -n "$undo_session_filter" ]]; then
            log_info "Undoing changes from the most recent fix session ($undo_session_filter); use --everything to include earlier sessions"
        fi
    elif [[ -n "$category" ]]; then
        change_ids=()
        while IFS= read -r _cid; do
            [[ -n "$_cid" ]] && change_ids+=("$_cid")
        done < <(jq -r --argjson undone "$undone_ids_json" --argjson undo_statuses "$undo_statuses_json" --arg category "$category" 'select((.id // "") as $id | (($undone | index($id)) | not) and (($undo_statuses[$id] // "") != "pending")) | select(.category == $category) | .id' "$ACFS_CHANGES_FILE" | sort -r)
    fi

    if [[ ${#change_ids[@]} -eq 0 ]]; then
        log_error "No changes specified. Use --list to see available changes."
        return 1
    fi

    # Dry run mode
    if [[ "$dry_run" == "true" ]]; then
        echo "Dry run: Would undo the following changes:"
        for change_id in "${change_ids[@]}"; do
            local record=""
            record=$(jq -c --arg id "$change_id" 'select(.id == $id)' \
                "$ACFS_CHANGES_FILE" 2>/dev/null | tail -1)
            if [[ -z "$record" ]] ||
               ! autofix_record_checksum_is_valid "$record" ||
               ! autofix_change_record_schema_is_valid "$record" "$change_id"; then
                log_error "Cannot preview an unknown or malformed change: $change_id"
                return 1
            fi
            local desc
            desc=$(echo "$record" | jq -r '.description')
            local undo
            undo=$(echo "$record" | jq -r '.undo_command')
            echo "  $change_id: $desc"
            if autofix_record_is_reversible "$record"; then
                echo "    Command: $undo"
            else
                local instructions=""
                instructions="$(autofix_manual_undo_instructions "$undo")"
                echo "    Manual: ${instructions:-No automatic undo available}"
            fi
        done
        return 0
    fi

    # Actually undo
    if ! start_autofix_session; then
        log_error "Failed to start undo session"
        return 1
    fi

    local failed=0
    for change_id in "${change_ids[@]}"; do
        if ! undo_change "$change_id" "$force"; then
            failed=$((failed + 1))
        fi
    done

    if ! end_autofix_session; then
        log_error "Failed to finalize undo session"
        return 1
    fi

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
    local backup_entry=""
    local active_backup_paths=""
    local cleanup_candidates_file=""
    local -A active_backup_set=()
    local find_bin=""
    local mktemp_bin=""
    local session_owned=false

    if [[ ! "$days" =~ ^[0-9]{1,4}$ ]] || (( 10#$days < 1 || 10#$days > 3650 )); then
        log_error "Backup retention days must be an integer between 1 and 3650"
        return 1
    fi

    if ! autofix_ensure_session session_owned; then
        log_error "Cannot clean up backups without an exclusive autofix session"
        return 1
    fi
    if ! autofix_state_layout_is_safe; then
        log_error "Refusing backup cleanup for an unsafe autofix state layout"
        autofix_finalize_managed_session "$session_owned" >/dev/null 2>&1 || true
        return 1
    fi

    find_bin="$(autofix_system_binary_path find 2>/dev/null || true)"
    mktemp_bin="$(autofix_system_binary_path mktemp 2>/dev/null || true)"
    if [[ -z "$find_bin" || -z "$mktemp_bin" ]]; then
        log_error "Cannot clean up backups because find or mktemp is unavailable"
        autofix_finalize_managed_session "$session_owned" >/dev/null 2>&1 || true
        return 1
    fi

    log_info "Cleaning up backups older than $days days..."

    if ! active_backup_paths="$(autofix_active_backup_paths)"; then
        log_error "Cannot determine active backups; refusing cleanup"
        autofix_finalize_managed_session "$session_owned" >/dev/null 2>&1 || true
        return 1
    fi
    while IFS= read -r backup_entry; do
        [[ -n "$backup_entry" ]] || continue
        active_backup_set["$backup_entry"]=1
    done <<< "$active_backup_paths"

    local deleted=0
    local cleanup_failed=0
    cleanup_candidates_file="$("$mktemp_bin" "$ACFS_STATE_DIR/.cleanup-candidates.XXXXXX" 2>/dev/null || true)"
    if [[ -z "$cleanup_candidates_file" ]] ||
       ! autofix_set_private_mode 600 "$cleanup_candidates_file"; then
        log_error "Failed to create a private backup-cleanup inventory"
        autofix_remove_temp_file "$cleanup_candidates_file" >/dev/null 2>&1 || true
        autofix_finalize_managed_session "$session_owned" >/dev/null 2>&1 || true
        return 1
    fi
    if ! "$find_bin" "$ACFS_BACKUPS_DIR" -mindepth 1 -maxdepth 1 \
        -mtime +"$days" -print0 > "$cleanup_candidates_file" 2>/dev/null; then
        log_error "Failed to enumerate old backup entries; refusing cleanup"
        autofix_remove_temp_file "$cleanup_candidates_file" >/dev/null 2>&1 || true
        autofix_finalize_managed_session "$session_owned" >/dev/null 2>&1 || true
        return 1
    fi
    while IFS= read -r -d '' backup_entry; do
        if [[ -n "${active_backup_set[$backup_entry]:-}" ]]; then
            continue
        fi
        if ! autofix_cleanup_failed_backup_path "$backup_entry"; then
            log_error "Failed to remove old backup entry: $backup_entry"
            cleanup_failed=1
            continue
        fi
        ((deleted++)) || true
    done < "$cleanup_candidates_file"
    if ! autofix_remove_temp_file "$cleanup_candidates_file"; then
        log_error "Failed to remove backup-cleanup inventory: $cleanup_candidates_file"
        cleanup_failed=1
    fi

    log_info "Deleted $deleted old backup entries"

    # Update integrity file after cleanup
    if ! update_integrity_file; then
        cleanup_failed=1
    fi
    if ! autofix_finalize_managed_session "$session_owned"; then
        cleanup_failed=1
    fi

    (( cleanup_failed == 0 ))
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
