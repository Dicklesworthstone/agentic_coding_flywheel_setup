#!/bin/bash
# ACFS Auto-Fix: Existing Installation Handling
# Handles upgrade, clean reinstall, or abort for existing ACFS installations
# Integrates with change recording system from autofix.sh

# Prevent multiple sourcing
[[ -n "${_ACFS_AUTOFIX_EXISTING_SOURCED:-}" ]] && return 0
_ACFS_AUTOFIX_EXISTING_SOURCED=1

# Source the core autofix module
_AUTOFIX_EXISTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=autofix.sh
source "${_AUTOFIX_EXISTING_DIR}/autofix.sh"

ACFS_CLEAN_RELOCATED_STATE_ORIG="${ACFS_CLEAN_RELOCATED_STATE_ORIG:-}"
ACFS_CLEAN_RELOCATED_STATE_NEW="${ACFS_CLEAN_RELOCATED_STATE_NEW:-}"

# =============================================================================
# Runtime Path Helpers
# =============================================================================

autofix_existing_runtime_home() {
    local runtime_home=""

    if declare -f autofix_runtime_home >/dev/null 2>&1; then
        runtime_home="$(autofix_runtime_home 2>/dev/null || true)"
    fi
    runtime_home="$(autofix_sanitize_abs_nonroot_path "$runtime_home" 2>/dev/null || true)"
    if [[ -n "$runtime_home" ]]; then
        printf '%s\n' "$runtime_home"
        return 0
    fi

    if [[ -n "${TARGET_USER:-}${TARGET_HOME:-}${SUDO_USER:-}" ]]; then
        return 1
    fi

    runtime_home="$(autofix_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    if [[ -n "$runtime_home" ]]; then
        printf '%s\n' "$runtime_home"
        return 0
    fi

    return 1
}

autofix_existing_acfs_home() {
    local acfs_home=""
    local runtime_home=""

    runtime_home="$(autofix_existing_runtime_home 2>/dev/null || true)"
    if [[ -n "$runtime_home" ]]; then
        printf '%s/.acfs\n' "$runtime_home"
        return 0
    fi

    acfs_home="$(autofix_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
    if [[ -n "$acfs_home" ]]; then
        printf '%s\n' "$acfs_home"
        return 0
    fi

    return 1
}

autofix_existing_installation_markers() {
    local runtime_home=""

    runtime_home="$(autofix_existing_runtime_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1

    printf '%s\n' \
        "$runtime_home/.acfs_installed" \
        "$runtime_home/.acfs" \
        "$runtime_home/.config/acfs" \
        "/usr/local/bin/acfs" \
        "$runtime_home/.local/bin/acfs"
}

autofix_existing_artifacts() {
    local runtime_home=""
    local acfs_home=""

    runtime_home="$(autofix_existing_runtime_home 2>/dev/null || true)"
    acfs_home="$(autofix_existing_acfs_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1
    [[ -n "$acfs_home" ]] || return 1

    printf '%s\n' \
        "$acfs_home" \
        "$runtime_home/.acfs_installed" \
        "$runtime_home/.config/acfs" \
        "/usr/local/bin/acfs" \
        "$runtime_home/.local/bin/acfs"
}

autofix_existing_shell_configs() {
    local runtime_home=""

    runtime_home="$(autofix_existing_runtime_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1

    printf '%s\n' \
        "$runtime_home/.bashrc" \
        "$runtime_home/.zshrc" \
        "$runtime_home/.zprofile" \
        "$runtime_home/.profile" \
        "$runtime_home/.bash_profile"
}

autofix_existing_shell_config_edit_path() {
    local config_path="$1"
    local path_type=""
    local edit_path=""

    path_type="$(autofix_detect_path_type "$config_path" 2>/dev/null || true)"
    case "$path_type" in
        file)
            printf '%s\n' "$config_path"
            return 0
            ;;
        symlink)
            edit_path="$(readlink -f "$config_path" 2>/dev/null || true)"
            edit_path="$(autofix_sanitize_abs_nonroot_path "$edit_path" 2>/dev/null || true)"
            if [[ -n "$edit_path" && -f "$edit_path" ]]; then
                printf '%s\n' "$edit_path"
                return 0
            fi
            ;;
    esac

    return 1
}

autofix_existing_shell_config_files_json() {
    local config_path="$1"
    local edit_path="$2"

    jq -cn --arg config "$config_path" --arg edit "$edit_path" '
        [$config, $edit]
        | map(select(length > 0))
        | unique
    '
}

autofix_existing_sed_literal() {
    # This is used in sed's default BRE mode with | as the delimiter.
    # Do not escape literal parentheses: \(...\) is a BRE capture group.
    printf '%s' "$1" | sed 's/[][\\.^$*|]/\\&/g'
}

autofix_existing_shell_config_has_path_fragment() {
    local config_path="${1:-}"
    local fragment="${2:-}"

    [[ -n "$config_path" && -n "$fragment" && -f "$config_path" ]] || return 1
    awk -v fragment="$fragment" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*(export[[:space:]]+)?PATH[[:space:]]*=/ && index($0, fragment) { found=1; exit }
        END { exit(found ? 0 : 1) }
    ' "$config_path" 2>/dev/null
}

autofix_existing_shell_config_needs_path_update() {
    local config_path="${1:-}"

    [[ -n "$config_path" && -f "$config_path" ]] || return 1

    if autofix_existing_shell_config_has_path_fragment "$config_path" '.local/bin' &&
       autofix_existing_shell_config_has_path_fragment "$config_path" '.atuin/bin'; then
        return 1
    fi

    return 0
}

autofix_existing_mv_undo_command() {
    local source_path="$1"
    local dest_path="$2"
    local undo_command=""

    printf -v undo_command 'mv %q %q' "$source_path" "$dest_path"
    printf '%s\n' "$undo_command"
}

autofix_existing_mv_undo_with_optional_dir_cleanup_command() {
    local source_path="$1"
    local dest_path="$2"
    local acfs_home="$3"
    local acfs_home_existed="${4:-false}"
    local config_dir_existed="${5:-false}"
    local undo_command=""

    undo_command="$(autofix_existing_mv_undo_command "$source_path" "$dest_path" 2>/dev/null || true)"
    [[ -n "$undo_command" ]] || return 1

    if [[ "$config_dir_existed" != "true" ]]; then
        printf -v undo_command '%s && { rmdir %q 2>/dev/null || true; }' "$undo_command" "$acfs_home/config"
    fi
    if [[ "$acfs_home_existed" != "true" ]]; then
        printf -v undo_command '%s && { rmdir %q 2>/dev/null || true; }' "$undo_command" "$acfs_home"
    fi

    printf '%s\n' "$undo_command"
}

autofix_existing_rmdir_undo_with_optional_parent_cleanup_command() {
    local dir_path="$1"
    local parent_dir="$2"
    local parent_dir_existed="${3:-false}"
    local undo_command=""

    printf -v undo_command 'rmdir %q 2>/dev/null || true' "$dir_path"
    if [[ "$parent_dir_existed" != "true" ]]; then
        printf -v undo_command '%s; rmdir %q 2>/dev/null || true' "$undo_command" "$parent_dir"
    fi

    printf '%s\n' "$undo_command"
}

autofix_existing_remove_dir_if_empty() {
    local dir_path="$1"
    local parent_dir=""

    [[ -d "$dir_path" ]] || return 0
    if rmdir "$dir_path" 2>/dev/null; then
        parent_dir="$(dirname "$dir_path")"
        fsync_directory "$parent_dir" >/dev/null 2>&1 || true
    fi
}

autofix_existing_cleanup_created_config_dirs() {
    local acfs_home="$1"
    local acfs_home_existed="${2:-false}"
    local config_dir_existed="${3:-false}"

    if [[ "$config_dir_existed" != "true" ]]; then
        autofix_existing_remove_dir_if_empty "$acfs_home/config"
    fi
    if [[ "$acfs_home_existed" != "true" ]]; then
        autofix_existing_remove_dir_if_empty "$acfs_home"
    fi
}

autofix_existing_cleanup_created_local_bin_dirs() {
    local local_bin_dir="$1"
    local local_bin_dir_existed="${2:-false}"
    local local_dir="$3"
    local local_dir_existed="${4:-false}"

    if [[ "$local_bin_dir_existed" != "true" ]]; then
        autofix_existing_remove_dir_if_empty "$local_bin_dir"
    fi
    if [[ "$local_dir_existed" != "true" ]]; then
        autofix_existing_remove_dir_if_empty "$local_dir"
    fi
}

autofix_existing_restore_from_backup() {
    local backup_json="$1"
    local target_path="${2:-}"
    local restore_command=""
    local restored_path=""

    restore_command="$(autofix_backup_restore_command "$backup_json" 2>/dev/null || true)"
    if [[ -z "$restore_command" ]]; then
        log_error "[RESTORE] Missing restore command${target_path:+ for $target_path}"
        return 1
    fi

    if ! bash -c "$restore_command"; then
        log_error "[RESTORE] Failed to restore${target_path:+ $target_path} from backup"
        return 1
    fi

    restored_path="$target_path"
    if [[ -z "$restored_path" ]]; then
        restored_path="$(printf '%s' "$backup_json" | jq -r '.original // empty' 2>/dev/null || true)"
    fi
    if [[ -n "$restored_path" ]]; then
        if ! autofix_path_exists "$restored_path"; then
            log_error "[RESTORE] Restored path is missing after restore: $restored_path"
            return 1
        fi
        if ! autofix_sync_backup_path "$restored_path"; then
            log_error "[RESTORE] Failed to fsync restored path: $restored_path"
            return 1
        fi
    fi

    return 0
}

autofix_existing_cleanup_failed_installation_backup_dir() {
    local backup_dir="$1"
    local backup_parent=""

    [[ -n "$backup_dir" ]] || return 1
    backup_parent="$(dirname "$backup_dir")"

    if autofix_path_exists "$backup_dir"; then
        if ! rm -rf "$backup_dir"; then
            log_error "[CLEAN] Failed to remove incomplete installation backup dir: $backup_dir"
            return 1
        fi
    fi

    if ! fsync_directory "$backup_parent"; then
        log_warn "[CLEAN] Failed to sync installation backup parent after cleanup: $backup_parent"
    fi

    return 0
}

autofix_existing_cleanup_temp_paths() {
    local path=""

    for path in "$@"; do
        if [[ -n "$path" ]]; then
            rm -f -- "$path" 2>/dev/null || true
        fi
    done
}

autofix_existing_cleanup_failed_installation_backup_if_needed() {
    local should_cleanup="${1:-false}"
    local backup_dir="${2:-}"

    if [[ "$should_cleanup" == "true" && -n "$backup_dir" ]]; then
        autofix_existing_cleanup_failed_installation_backup_dir "$backup_dir" || true
    fi
}

autofix_existing_rollback_changes_since() {
    local start_index="${1:-0}"
    local i=0
    local rollback_failed=0
    local change_id=""

    if (( start_index < 0 )); then
        start_index=0
    fi
    if (( start_index >= ${#ACFS_CHANGE_ORDER[@]} )); then
        return 0
    fi

    for ((i=${#ACFS_CHANGE_ORDER[@]}-1; i>=start_index; i--)); do
        change_id="${ACFS_CHANGE_ORDER[$i]}"
        if ! undo_change "$change_id" true true >/dev/null 2>&1; then
            log_warn "[ROLLBACK] Failed to undo $change_id"
            ((rollback_failed++)) || true
        fi
    done

    [[ $rollback_failed -eq 0 ]]
}

autofix_existing_restore_journal_file_from_backup() {
    local journal_path="$1"
    local backup_path="${2:-}"
    local journal_existed="${3:-false}"
    local journal_dir=""

    [[ -n "$journal_path" ]] || return 1
    journal_dir="$(dirname "$journal_path")"

    if [[ "$journal_existed" == "true" ]]; then
        if [[ -z "$backup_path" || ! -f "$backup_path" ]]; then
            log_error "[ROLLBACK] Missing backup while restoring journal: $journal_path"
            return 1
        fi
        if ! cp -p "$backup_path" "$journal_path"; then
            log_error "[ROLLBACK] Failed to restore journal from backup: $journal_path"
            return 1
        fi
        if ! fsync_file "$journal_path"; then
            log_warn "[ROLLBACK] Failed to sync restored journal: $journal_path"
        fi
    else
        if autofix_path_exists "$journal_path"; then
            if ! rm -f "$journal_path"; then
                log_error "[ROLLBACK] Failed to remove restored-new journal: $journal_path"
                return 1
            fi
        fi
    fi

    if ! fsync_directory "$journal_dir"; then
        log_warn "[ROLLBACK] Failed to sync journal directory after restore: $journal_dir"
    fi

    return 0
}

autofix_existing_drop_changes_since() {
    local start_index="${1:-0}"
    local i=0
    local change_id=""
    local changes_dir=""
    local undos_dir=""
    local changes_tmp=""
    local undos_tmp=""
    local changes_backup=""
    local undos_backup=""
    local drop_ids_json="[]"
    local changes_existed=false
    local undos_existed=false
    local -a dropped_ids=()

    if (( start_index < 0 )); then
        start_index=0
    fi
    if (( start_index >= ${#ACFS_CHANGE_ORDER[@]} )); then
        return 0
    fi

    changes_dir="$(dirname "$ACFS_CHANGES_FILE")"
    undos_dir="$(dirname "$ACFS_UNDOS_FILE")"
    changes_tmp="$(mktemp -p "$changes_dir" ".tmp.XXXXXX" 2>/dev/null)" || {
        log_error "[ROLLBACK] Failed to create temp file while pruning change journal"
        return 1
    }
    undos_tmp="$(mktemp -p "$undos_dir" ".tmp.XXXXXX" 2>/dev/null)" || {
        autofix_existing_cleanup_temp_paths "$changes_tmp"
        log_error "[ROLLBACK] Failed to create temp file while pruning undo journal"
        return 1
    }

    for ((i=start_index; i<${#ACFS_CHANGE_ORDER[@]}; i++)); do
        dropped_ids+=("${ACFS_CHANGE_ORDER[$i]}")
    done

    if ! drop_ids_json="$(printf '%s\n' "${dropped_ids[@]}" | jq -R . | jq -s '.')"; then
        log_error "[ROLLBACK] Failed to serialize dropped change IDs for journal pruning"
        autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
        return 1
    fi

    : > "$changes_tmp" || {
        log_error "[ROLLBACK] Failed to initialize pruned change journal"
        autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
        return 1
    }
    if [[ -f "$ACFS_CHANGES_FILE" ]] && [[ ${#dropped_ids[@]} -gt 0 ]]; then
        if ! jq -c --argjson dropped_ids "$drop_ids_json" \
            'select((.id // "") as $id | ($dropped_ids | index($id) | not))' \
            "$ACFS_CHANGES_FILE" > "$changes_tmp"; then
            log_error "[ROLLBACK] Failed to rewrite change journal while pruning aborted changes"
            autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
            return 1
        fi
    fi

    : > "$undos_tmp" || {
        log_error "[ROLLBACK] Failed to initialize pruned undo journal"
        autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
        return 1
    }
    if [[ -f "$ACFS_UNDOS_FILE" ]] && [[ ${#dropped_ids[@]} -gt 0 ]]; then
        if ! jq -c --argjson dropped_ids "$drop_ids_json" \
            'select((.undone // "") as $id | ($dropped_ids | index($id) | not))' \
            "$ACFS_UNDOS_FILE" > "$undos_tmp"; then
            log_error "[ROLLBACK] Failed to rewrite undo journal while pruning aborted changes"
            autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
            return 1
        fi
    fi

    if [[ -f "$ACFS_CHANGES_FILE" ]]; then
        changes_existed=true
        changes_backup="$(mktemp -p "$changes_dir" ".orig.XXXXXX" 2>/dev/null)" || {
            log_error "[ROLLBACK] Failed to create backup file for change journal pruning"
            autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
            return 1
        }
        if ! cp -p "$ACFS_CHANGES_FILE" "$changes_backup"; then
            log_error "[ROLLBACK] Failed to back up change journal before pruning"
            autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
            return 1
        fi
        if ! fsync_file "$changes_backup"; then
            log_warn "[ROLLBACK] Failed to sync change journal backup before pruning"
        fi
    fi

    if [[ -f "$ACFS_UNDOS_FILE" ]]; then
        undos_existed=true
        undos_backup="$(mktemp -p "$undos_dir" ".orig.XXXXXX" 2>/dev/null)" || {
            log_error "[ROLLBACK] Failed to create backup file for undo journal pruning"
            autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
            return 1
        }
        if ! cp -p "$ACFS_UNDOS_FILE" "$undos_backup"; then
            log_error "[ROLLBACK] Failed to back up undo journal before pruning"
            autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
            return 1
        fi
        if ! fsync_file "$undos_backup"; then
            log_warn "[ROLLBACK] Failed to sync undo journal backup before pruning"
        fi
    fi

    if ! fsync_file "$changes_tmp"; then
        log_error "[ROLLBACK] Failed to sync pruned change journal"
        autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
        return 1
    fi
    if ! mv "$changes_tmp" "$ACFS_CHANGES_FILE"; then
        log_error "[ROLLBACK] Failed to replace change journal with pruned state"
        autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
        return 1
    fi
    if ! fsync_directory "$changes_dir"; then
        log_warn "[ROLLBACK] Failed to sync change journal directory after pruning"
    fi

    if ! fsync_file "$undos_tmp"; then
        log_error "[ROLLBACK] Failed to sync pruned undo journal"
        if ! autofix_existing_restore_journal_file_from_backup "$ACFS_CHANGES_FILE" "$changes_backup" "$changes_existed"; then
            log_error "[ROLLBACK] Failed to restore change journal after undo journal sync failure"
        fi
        autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
        return 1
    fi
    if ! mv "$undos_tmp" "$ACFS_UNDOS_FILE"; then
        log_error "[ROLLBACK] Failed to replace undo journal with pruned state"
        if ! autofix_existing_restore_journal_file_from_backup "$ACFS_CHANGES_FILE" "$changes_backup" "$changes_existed"; then
            log_error "[ROLLBACK] Failed to restore change journal after undo journal replacement failure"
        fi
        autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
        return 1
    fi
    if ! fsync_directory "$undos_dir"; then
        log_warn "[ROLLBACK] Failed to sync undo journal directory after pruning"
    fi

    for change_id in "${dropped_ids[@]}"; do
        unset "ACFS_CHANGE_RECORDS[$change_id]"
    done
    ACFS_CHANGE_ORDER=("${ACFS_CHANGE_ORDER[@]:0:start_index}")

    autofix_existing_cleanup_temp_paths "$changes_tmp" "$undos_tmp" "$changes_backup" "$undos_backup"
    return 0
}

autofix_existing_rollback_and_drop_changes_since() {
    local start_index="${1:-0}"

    if ! autofix_existing_rollback_changes_since "$start_index"; then
        return 1
    fi
    if ! autofix_existing_drop_changes_since "$start_index"; then
        return 1
    fi

    return 0
}

# =============================================================================
# Detection Functions
# =============================================================================

# Detect existing ACFS installation
# Returns: space-separated list of found markers (empty if none)
detect_existing_acfs() {
    local -a found_markers=()
    local marker=""

    while IFS= read -r marker; do
        [[ -n "$marker" ]] || continue
        if autofix_path_exists "$marker"; then
            found_markers+=("$marker")
        fi
    done < <(autofix_existing_installation_markers 2>/dev/null || true)

    if [[ ${#found_markers[@]} -gt 0 ]]; then
        echo "${found_markers[*]}"
        return 0
    fi

    return 1
}

# Get installed ACFS version
get_installed_version() {
    local version_output=""
    local version=""
    local acfs_home=""
    local runtime_home=""

    # Method 1: Try acfs --version command
    if command -v acfs &>/dev/null; then
        version_output=$(acfs --version 2>/dev/null | head -1)
        if [[ -n "$version_output" ]]; then
            # Extract version number (e.g., "ACFS v0.4.0" -> "0.4.0")
            version="$(printf '%s\n' "$version_output" | { grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true; } | head -1)"
            if [[ -n "$version" ]]; then
                printf '%s\n' "$version"
                return 0
            fi
        fi
    fi

    # Method 2: Check version file
    acfs_home="$(autofix_existing_acfs_home 2>/dev/null || true)"
    if [[ -n "$acfs_home" ]] && [[ -f "$acfs_home/version" ]]; then
        cat "$acfs_home/version"
        return 0
    fi

    # Method 3: Check installed marker file for version info
    runtime_home="$(autofix_existing_runtime_home 2>/dev/null || true)"
    if [[ -n "$runtime_home" ]] && [[ -f "$runtime_home/.acfs_installed" ]]; then
        version="$({ grep -oE 'version=[0-9]+\.[0-9]+\.[0-9]+' "$runtime_home/.acfs_installed" 2>/dev/null || true; } | cut -d= -f2)"
        if [[ -n "$version" ]]; then
            printf '%s\n' "$version"
            return 0
        fi
    fi

    printf 'unknown\n'
}

# Check if installation appears corrupted/partial
detect_installation_state() {
    local markers
    markers=$(detect_existing_acfs 2>/dev/null) || true

    if [[ -z "$markers" ]]; then
        echo "none"
        return
    fi

    local has_config=false
    local has_binary=false
    local has_marker=false

    for marker in $markers; do
        case "$marker" in
            */.acfs|*/.config/acfs) has_config=true ;;
            */bin/acfs) has_binary=true ;;
            */.acfs_installed) has_marker=true ;;
        esac
    done

    # Determine state
    if $has_config && $has_binary && $has_marker; then
        echo "complete"
    elif $has_marker && ! $has_config && ! $has_binary; then
        echo "marker_only"
    elif ! $has_marker && ($has_config || $has_binary); then
        echo "partial"
    else
        echo "partial"
    fi
}

# Returns JSON with installation details
autofix_existing_acfs_check() {
    local markers
    markers=$(detect_existing_acfs 2>/dev/null) || markers=""

    local version
    version=$(get_installed_version)

    local state
    state=$(detect_installation_state)

    local markers_json
    if [[ -n "$markers" ]]; then
        # shellcheck disable=SC2086
        markers_json=$(printf '%s\n' $markers | jq -R . | jq -s .)
    else
        markers_json="[]"
    fi

    jq -n \
        --arg state "$state" \
        --arg version "$version" \
        --argjson markers "$markers_json" \
        '{state: $state, version: $version, markers: $markers}'
}

# Quick check - returns 0 if existing installation found, 1 if clean
autofix_existing_acfs_needs_handling() {
    local markers
    markers=$(detect_existing_acfs 2>/dev/null) || true

    [[ -n "$markers" ]]
}

# Fix function for handle_autofix dispatch pattern
# In fix/--yes mode, defaults to upgrade; in dry-run, shows what would happen
autofix_existing_fix() {
    local mode="${1:-fix}"

    if [[ "$mode" == "dry-run" ]]; then
        log_info "[DRY-RUN] Would handle existing ACFS installation"
        log_info "  - Check installed version"
        log_info "  - Offer upgrade or clean reinstall option"
        return 0
    fi

    # In fix mode: use upgrade strategy
    if handle_existing_installation "${ACFS_VERSION:-unknown}" "upgrade"; then
        return 0
    else
        log_error "Failed to handle existing installation"
        return 1
    fi
}

# =============================================================================
# Version Comparison Utilities
# =============================================================================

# Compare two semantic versions
# Returns: -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
version_compare() {
    local v1="$1"
    local v2="$2"

    # Handle unknown versions
    if [[ "$v1" == "unknown" || "$v2" == "unknown" ]]; then
        echo "0"
        return
    fi

    # Split into arrays
    IFS='.' read -ra V1_PARTS <<< "$v1"
    IFS='.' read -ra V2_PARTS <<< "$v2"

    # Compare each part
    for i in 0 1 2; do
        local p1="${V1_PARTS[$i]:-0}"
        local p2="${V2_PARTS[$i]:-0}"

        if ((p1 < p2)); then
            echo "-1"
            return
        elif ((p1 > p2)); then
            echo "1"
            return
        fi
    done

    echo "0"
}

# Check if migration is required between versions
version_requires_migration() {
    local from="$1"
    local to="$2"

    if [[ "$from" == "unknown" ]]; then
        return 0  # Unknown version always needs migration check
    fi

    # Compare major versions
    local from_major="${from%%.*}"
    local to_major="${to%%.*}"

    if [[ "$from_major" != "$to_major" ]]; then
        return 0  # Major version change requires migration
    fi

    return 1
}

# =============================================================================
# Migration Functions
# =============================================================================

# Run migrations from one version to another
run_migrations() {
    local from="$1"
    local to="$2"
    local runtime_home=""
    local acfs_home=""
    local legacy_config=""
    local settings_path=""
    local legacy_json_config=""
    local migrated_json_config=""
    local files_json=""
    local acfs_home_existed=false
    local config_dir_existed=false
    local local_dir=""
    local local_bin_dir=""
    local local_dir_existed=false
    local local_bin_dir_existed=false
    local rollback_start_index=0

    log_info "[MIGRATE] Running migrations from $from to $to"

    runtime_home="$(autofix_existing_runtime_home 2>/dev/null || true)"
    acfs_home="$(autofix_existing_acfs_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1
    [[ -n "$acfs_home" ]] || return 1
    [[ -d "$acfs_home" ]] && acfs_home_existed=true
    [[ -d "$acfs_home/config" ]] && config_dir_existed=true
    rollback_start_index=${#ACFS_CHANGE_ORDER[@]}

    # Migration: v0.x -> v1.x: Move config from ~/.acfs_config to ~/.acfs/config
    legacy_config="$runtime_home/.acfs_config"
    settings_path="$acfs_home/config/settings.toml"
    if [[ -f "$legacy_config" ]] && [[ ! -f "$settings_path" ]]; then
        local legacy_move_undo=""
        log_info "[MIGRATE] Moving legacy config to new location"
        if ! mkdir -p "$acfs_home/config"; then
            log_error "[MIGRATE] Failed to create config directory: $acfs_home/config"
            return 1
        fi
        if ! mv "$legacy_config" "$settings_path"; then
            log_error "[MIGRATE] Failed to move legacy config to $settings_path"
            autofix_existing_cleanup_created_config_dirs "$acfs_home" "$acfs_home_existed" "$config_dir_existed"
            return 1
        fi
        files_json="$(jq -cn --arg old "$legacy_config" --arg new "$settings_path" '[$old, $new]')"
        legacy_move_undo="$(
            autofix_existing_mv_undo_with_optional_dir_cleanup_command \
                "$settings_path" \
                "$legacy_config" \
                "$acfs_home" \
                "$acfs_home_existed" \
                "$config_dir_existed" 2>/dev/null || true
        )"
        if [[ -z "$legacy_move_undo" ]]; then
            log_error "[MIGRATE] Failed to build undo command for legacy config migration"
            if ! mv "$settings_path" "$legacy_config"; then
                log_error "[MIGRATE] Failed to revert legacy config move after undo-command build failure"
            fi
            autofix_existing_cleanup_created_config_dirs "$acfs_home" "$acfs_home_existed" "$config_dir_existed"
            return 1
        fi

        if ! record_change \
            "acfs" \
            "Migrated legacy config file to new location" \
            "$legacy_move_undo" \
            false \
            "info" \
            "$files_json" \
            '[]' \
            '[]' >/dev/null; then
            log_error "[MIGRATE] Failed to record legacy config migration; reverting"
            if ! mv "$settings_path" "$legacy_config"; then
                log_error "[MIGRATE] Failed to revert legacy config move after journaling failure"
            fi
            autofix_existing_cleanup_created_config_dirs "$acfs_home" "$acfs_home_existed" "$config_dir_existed"
            return 1
        fi
    fi

    # Migration: Convert JSON config to TOML (if present)
    legacy_json_config="$acfs_home/config.json"
    migrated_json_config="$acfs_home/config.json.migrated"
    if [[ -f "$legacy_json_config" ]] && [[ ! -f "$migrated_json_config" ]]; then
        local json_backup_undo=""
        log_info "[MIGRATE] Backing up legacy JSON config"
        if ! mv "$legacy_json_config" "$migrated_json_config"; then
            log_error "[MIGRATE] Failed to preserve legacy JSON config"
            if ! autofix_existing_rollback_and_drop_changes_since "$rollback_start_index"; then
                log_error "[MIGRATE] Failed to roll back earlier migration changes after JSON backup failure"
            fi
            return 1
        fi
        files_json="$(jq -cn --arg old "$legacy_json_config" --arg new "$migrated_json_config" '[$old, $new]')"
        json_backup_undo="$(autofix_existing_mv_undo_command "$migrated_json_config" "$legacy_json_config" 2>/dev/null || true)"
        if [[ -z "$json_backup_undo" ]]; then
            log_error "[MIGRATE] Failed to build undo command for legacy JSON config backup"
            if ! mv "$migrated_json_config" "$legacy_json_config"; then
                log_error "[MIGRATE] Failed to restore legacy JSON config after undo-command build failure"
            fi
            if ! autofix_existing_rollback_and_drop_changes_since "$rollback_start_index"; then
                log_error "[MIGRATE] Failed to roll back earlier migration changes after JSON backup undo-command failure"
            fi
            return 1
        fi

        if ! record_change \
            "acfs" \
            "Backed up legacy JSON config" \
            "$json_backup_undo" \
            false \
            "info" \
            "$files_json" \
            '[]' \
            '[]' >/dev/null; then
            log_error "[MIGRATE] Failed to record JSON config backup; reverting"
            if ! mv "$migrated_json_config" "$legacy_json_config"; then
                log_error "[MIGRATE] Failed to restore legacy JSON config after journaling failure"
            fi
            if ! autofix_existing_rollback_and_drop_changes_since "$rollback_start_index"; then
                log_error "[MIGRATE] Failed to roll back earlier migration changes after JSON backup journaling failure"
            fi
            return 1
        fi
    fi

    # Migration: Ensure .local/bin exists and is in PATH
    local_dir="$runtime_home/.local"
    local_bin_dir="$runtime_home/.local/bin"
    [[ -d "$local_dir" ]] && local_dir_existed=true
    [[ -d "$local_bin_dir" ]] && local_bin_dir_existed=true
    if [[ "$local_bin_dir_existed" != "true" ]]; then
        local local_bin_undo=""
        log_info "[MIGRATE] Creating ~/.local/bin directory"
        if ! mkdir -p "$local_bin_dir"; then
            log_error "[MIGRATE] Failed to create $local_bin_dir"
            autofix_existing_cleanup_created_local_bin_dirs "$local_bin_dir" "$local_bin_dir_existed" "$local_dir" "$local_dir_existed"
            if ! autofix_existing_rollback_and_drop_changes_since "$rollback_start_index"; then
                log_error "[MIGRATE] Failed to roll back earlier migration changes after ~/.local/bin creation failure"
            fi
            return 1
        fi
        files_json="$(jq -cn --arg local_dir "$local_dir" --arg local_bin "$local_bin_dir" '[$local_dir, $local_bin] | unique')"
        local_bin_undo="$(
            autofix_existing_rmdir_undo_with_optional_parent_cleanup_command \
                "$local_bin_dir" \
                "$local_dir" \
                "$local_dir_existed" 2>/dev/null || true
        )"
        if [[ -z "$local_bin_undo" ]]; then
            log_error "[MIGRATE] Failed to build undo command for ~/.local/bin creation"
            autofix_existing_cleanup_created_local_bin_dirs "$local_bin_dir" "$local_bin_dir_existed" "$local_dir" "$local_dir_existed"
            if ! autofix_existing_rollback_and_drop_changes_since "$rollback_start_index"; then
                log_error "[MIGRATE] Failed to roll back earlier migration changes after ~/.local/bin undo-command failure"
            fi
            return 1
        fi
        if ! record_change \
            "acfs" \
            "Created ~/.local/bin directory for ACFS PATH support" \
            "$local_bin_undo" \
            false \
            "info" \
            "$files_json" \
            '[]' \
            '[]' >/dev/null; then
            log_error "[MIGRATE] Failed to record ~/.local/bin creation; reverting"
            autofix_existing_cleanup_created_local_bin_dirs "$local_bin_dir" "$local_bin_dir_existed" "$local_dir" "$local_dir_existed"
            if ! autofix_existing_rollback_and_drop_changes_since "$rollback_start_index"; then
                log_error "[MIGRATE] Failed to roll back earlier migration changes after ~/.local/bin journaling failure"
            fi
            return 1
        fi
    fi

    log_info "[MIGRATE] Migrations complete"
    return 0
}

# Update PATH entries in shell configs
update_path_entries() {
    local config=""
    local edit_config=""
    local backup=""
    local restore_command=""
    local files_json=""
    local recovery_incomplete=false
    local legacy_acfs_path_line='export PATH="$HOME/.local/bin:$PATH" # ACFS'
    local legacy_profile_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"'
    local current_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH" # ACFS'

    while IFS= read -r config; do
        [[ -n "$config" ]] || continue
        edit_config="$(autofix_existing_shell_config_edit_path "$config" 2>/dev/null || true)"
        if [[ -n "$edit_config" ]]; then
            if autofix_existing_shell_config_needs_path_update "$edit_config"; then
                log_info "[UPGRADE] Adding PATH entry to $config"

                # Create backup
                if ! backup=$(create_backup "$edit_config" "upgrade-path-entry") || [[ -z "$backup" ]]; then
                    log_error "[UPGRADE] Failed to back up $config before PATH update"
                    return 1
                fi
                files_json="$(autofix_existing_shell_config_files_json "$config" "$edit_config" 2>/dev/null || printf '[]\n')"
                restore_command="$(autofix_backup_restore_command "$backup" 2>/dev/null || true)"
                if [[ -z "$restore_command" ]]; then
                    log_error "[UPGRADE] Failed to build a restore command for $config"
                    return 1
                fi

                # Repair exact legacy ACFS lines in place; otherwise append a fresh block.
                if grep -Fxq "$legacy_acfs_path_line" "$edit_config" 2>/dev/null; then
                    if ! sed -i "s|^$(autofix_existing_sed_literal "$legacy_acfs_path_line")$|$current_path_line|" "$edit_config"; then
                        log_error "[UPGRADE] Failed to update legacy PATH entry in $config"
                        if ! autofix_existing_restore_from_backup "$backup" "$edit_config"; then
                            log_error "[UPGRADE] Failed to restore $config after PATH update failure"
                            recovery_incomplete=true
                        fi
                        if [[ "$recovery_incomplete" == "true" ]]; then
                            return 2
                        fi
                        return 1
                    fi
                elif grep -Fxq "$legacy_profile_path_line" "$edit_config" 2>/dev/null; then
                    if ! sed -i "s|^$(autofix_existing_sed_literal "$legacy_profile_path_line")$|$current_path_line|" "$edit_config"; then
                        log_error "[UPGRADE] Failed to update legacy login PATH entry in $config"
                        if ! autofix_existing_restore_from_backup "$backup" "$edit_config"; then
                            log_error "[UPGRADE] Failed to restore $config after PATH update failure"
                            recovery_incomplete=true
                        fi
                        if [[ "$recovery_incomplete" == "true" ]]; then
                            return 2
                        fi
                        return 1
                    fi
                elif ! {
                    echo ''
                    echo '# ACFS PATH'
                    echo "$current_path_line"
                } >> "$edit_config"; then
                    log_error "[UPGRADE] Failed to append PATH entry to $config"
                    if ! autofix_existing_restore_from_backup "$backup" "$edit_config"; then
                        log_error "[UPGRADE] Failed to restore $config after PATH update failure"
                        recovery_incomplete=true
                    fi
                    if [[ "$recovery_incomplete" == "true" ]]; then
                        return 2
                    fi
                    return 1
                fi

                if ! record_change \
                    "acfs" \
                    "Added PATH entry to $config" \
                    "$restore_command" \
                    false \
                    "info" \
                    "$files_json" \
                    "$(echo "$backup" | jq -c '[.]' 2>/dev/null || echo '[]')" \
                    '[]' >/dev/null; then
                    log_error "[UPGRADE] Failed to record PATH update for $config"
                    if ! autofix_existing_restore_from_backup "$backup" "$edit_config"; then
                        log_error "[UPGRADE] Failed to restore $config after journaling failure"
                        recovery_incomplete=true
                    fi
                    if [[ "$recovery_incomplete" == "true" ]]; then
                        return 2
                    fi
                    return 1
                fi
            fi
        fi
    done < <(autofix_existing_shell_configs 2>/dev/null || true)
}

autofix_existing_restore_upgrade_version_file() {
    local version_file="$1"
    local version_backup="${2:-}"
    local version_file_existed="${3:-false}"
    local acfs_home_existed="${4:-true}"

    if [[ "$version_file_existed" == "true" ]]; then
        if [[ -z "$version_backup" ]]; then
            log_error "[UPGRADE] Missing version-file backup for restore: $version_file"
            return 1
        fi
        if ! autofix_existing_restore_from_backup "$version_backup" "$version_file"; then
            log_error "[UPGRADE] Failed to restore previous version file: $version_file"
            return 1
        fi
        return 0
    fi

    if autofix_path_exists "$version_file"; then
        if ! rm -f "$version_file"; then
            log_error "[UPGRADE] Failed to remove newly created version file: $version_file"
            return 1
        fi
    fi
    if [[ "$acfs_home_existed" != "true" ]]; then
        autofix_existing_remove_dir_if_empty "$(dirname "$version_file")"
    fi

    return 0
}

# =============================================================================
# Upgrade Implementation
# =============================================================================

# Upgrade existing installation (preserve config)
upgrade_existing_installation() {
    local current_version="$1"
    local new_version="$2"
    local acfs_home=""
    local runtime_home=""
    local acfs_home_existed=false
    local config_backup=""
    local version_file=""
    local version_backup=""
    local version_file_existed=false
    local upgrade_files_json='[]'
    local rollback_start_index=0

    log_info "[UPGRADE] Starting upgrade from $current_version to $new_version"

    runtime_home="$(autofix_existing_runtime_home 2>/dev/null || true)"
    acfs_home="$(autofix_existing_acfs_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1
    [[ -n "$acfs_home" ]] || return 1
    [[ -d "$acfs_home" ]] && acfs_home_existed=true
    rollback_start_index=${#ACFS_CHANGE_ORDER[@]}

    # Step 1: Backup current config (for safety)
    if autofix_path_exists "$acfs_home/config"; then
        if ! config_backup=$(create_backup "$acfs_home/config" "upgrade-config-backup") || [[ -z "$config_backup" ]]; then
            log_error "[UPGRADE] Failed to create the pre-upgrade ACFS config backup"
            return 1
        fi
        log_info "[UPGRADE] Config backed up: $(echo "$config_backup" | jq -r '.backup' 2>/dev/null || echo "$config_backup")"
    fi

    # Step 2: Check for migration requirements
    if version_requires_migration "$current_version" "$new_version"; then
        log_info "[UPGRADE] Migration required from $current_version to $new_version"
        if ! run_migrations "$current_version" "$new_version"; then
            log_error "[UPGRADE] Migration failed"
            if ! autofix_existing_rollback_changes_since "$rollback_start_index"; then
                log_error "[UPGRADE] Failed to roll back migration changes after migration failure"
            fi
            return 1
        fi
    fi

    version_file="$acfs_home/version"
    upgrade_files_json="$(jq -cn --arg path "$version_file" '[$path]')"
    if autofix_path_exists "$version_file"; then
        version_file_existed=true
        if ! version_backup="$(create_backup "$version_file" "upgrade-version-file")" || [[ -z "$version_backup" ]]; then
            log_error "[UPGRADE] Failed to back up version file before upgrade: $version_file"
            if ! autofix_existing_rollback_and_drop_changes_since "$rollback_start_index"; then
                log_error "[UPGRADE] Failed to roll back upgrade changes after version backup failure"
            fi
            return 1
        fi
    fi

    # Step 3: Update version file
    if ! mkdir -p "$acfs_home"; then
        log_error "[UPGRADE] Failed to create ACFS home: $acfs_home"
        if ! autofix_existing_rollback_and_drop_changes_since "$rollback_start_index"; then
            log_error "[UPGRADE] Failed to roll back upgrade changes after ACFS home creation failure"
        fi
        return 1
    fi
    if ! printf '%s\n' "$new_version" > "$version_file"; then
        local rollback_ok=false
        local restore_ok=false
        log_error "[UPGRADE] Failed to update version file: $version_file"
        if ! autofix_existing_rollback_changes_since "$rollback_start_index"; then
            log_error "[UPGRADE] Failed to roll back upgrade changes after write failure"
        else
            rollback_ok=true
        fi
        if ! autofix_existing_restore_upgrade_version_file "$version_file" "$version_backup" "$version_file_existed" "$acfs_home_existed"; then
            log_error "[UPGRADE] Failed to restore version file after write failure"
        else
            restore_ok=true
        fi
        if [[ "$rollback_ok" == "true" && "$restore_ok" == "true" ]]; then
            if ! autofix_existing_drop_changes_since "$rollback_start_index"; then
                log_error "[UPGRADE] Failed to prune rolled-back upgrade journal entries after write failure"
            fi
        fi
        return 1
    fi

    # Step 4: Update PATH entries if needed
    local path_update_status=0
    update_path_entries || path_update_status=$?
    if (( path_update_status != 0 )); then
        local rollback_ok=false
        local restore_ok=false
        log_error "[UPGRADE] Failed to repair shell PATH entries"
        if ! autofix_existing_rollback_changes_since "$rollback_start_index"; then
            log_error "[UPGRADE] Failed to roll back upgrade changes after PATH repair failure"
        else
            rollback_ok=true
        fi
        if ! autofix_existing_restore_upgrade_version_file "$version_file" "$version_backup" "$version_file_existed" "$acfs_home_existed"; then
            log_error "[UPGRADE] Failed to restore version file after PATH repair failure"
        else
            restore_ok=true
        fi
        if [[ "$rollback_ok" == "true" && "$restore_ok" == "true" && $path_update_status -ne 2 ]]; then
            if ! autofix_existing_drop_changes_since "$rollback_start_index"; then
                log_error "[UPGRADE] Failed to prune rolled-back upgrade journal entries after PATH repair failure"
            fi
        else
            log_warn "[UPGRADE] Preserving upgrade journal because rollback after PATH repair failure was incomplete"
        fi
        return 1
    fi

    # Step 5: Record upgrade change after mutations succeed
    if ! record_change \
        "acfs" \
        "Upgraded ACFS from $current_version to $new_version" \
        "# Downgrade not supported - restore from backup if needed" \
        false \
        "info" \
        "$upgrade_files_json" \
        '[]' \
        '[]' \
        false >/dev/null; then
        local rollback_ok=false
        local restore_ok=false
        log_error "[UPGRADE] Failed to record upgrade operation"
        if ! autofix_existing_rollback_changes_since "$rollback_start_index"; then
            log_error "[UPGRADE] Failed to roll back upgrade changes after upgrade journaling failure"
        else
            rollback_ok=true
        fi
        if ! autofix_existing_restore_upgrade_version_file "$version_file" "$version_backup" "$version_file_existed" "$acfs_home_existed"; then
            log_error "[UPGRADE] Failed to restore version file after upgrade journaling failure"
        else
            restore_ok=true
        fi
        if [[ "$rollback_ok" == "true" && "$restore_ok" == "true" ]]; then
            if ! autofix_existing_drop_changes_since "$rollback_start_index"; then
                log_error "[UPGRADE] Failed to prune rolled-back upgrade journal entries after upgrade journaling failure"
            fi
        fi
        return 1
    fi

    log_info "[UPGRADE] Upgrade preparation complete"
    log_info "[UPGRADE] Installation will continue with updated binaries"

    return 0
}

# =============================================================================
# Clean Reinstall Implementation
# =============================================================================

# Create comprehensive backup of existing installation
create_installation_backup() {
    local backup_dir
    local backup_dir_base=""
    local backup_index=0
    local runtime_home=""
    local artifact=""
    local artifact_type=""
    local dest=""
    local dest_rel=""
    local checksum=""
    local backup_checksum=""
    local items_json=""
    local backup_item=""
    local cleanup_backup_dir_on_failure=false
    local -a backed_up_items=()

    runtime_home="$(autofix_existing_runtime_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1
    backup_dir_base="$runtime_home/.acfs-backup-$(date +%Y%m%d_%H%M%S)"
    backup_dir="$backup_dir_base"
    while autofix_path_exists "$backup_dir"; do
        backup_index=$((backup_index + 1))
        backup_dir="${backup_dir_base}.${backup_index}"
    done

    log_info "[CLEAN] Creating backup at $backup_dir"
    if ! mkdir -p "$backup_dir"; then
        log_error "[CLEAN] Failed to create backup directory: $backup_dir"
        return 1
    fi
    cleanup_backup_dir_on_failure=true
    if ! fsync_directory "$(dirname "$backup_dir")"; then
        log_error "[CLEAN] Failed to fsync backup directory parent: $(dirname "$backup_dir")"
        autofix_existing_cleanup_failed_installation_backup_if_needed "$cleanup_backup_dir_on_failure" "$backup_dir"
        return 1
    fi

    local backup_manifest="$backup_dir/manifest.json"

    while IFS= read -r artifact; do
        [[ -n "$artifact" ]] || continue
        if autofix_path_exists "$artifact"; then
            log_info "[CLEAN] Backing up: $artifact"
            artifact_type="$(autofix_detect_path_type "$artifact" 2>/dev/null || true)"
            case "$artifact" in
                "$runtime_home")
                    dest_rel=".acfs-home"
                    ;;
                "$runtime_home"/*)
                    dest_rel="${artifact#$runtime_home/}"
                    ;;
                /*)
                    dest_rel="${artifact#/}"
                    ;;
                *)
                    dest_rel="$artifact"
                    ;;
            esac
            dest="$backup_dir/$dest_rel"
            if ! mkdir -p "$(dirname "$dest")"; then
                log_error "[CLEAN] Failed to create backup parent directory for: $dest"
                autofix_existing_cleanup_failed_installation_backup_if_needed "$cleanup_backup_dir_on_failure" "$backup_dir"
                return 1
            fi

            if [[ "$artifact_type" == "directory" || "$artifact_type" == "symlink" ]]; then
                if ! cp -rp "$artifact" "$dest" 2>/dev/null; then
                    log_error "[CLEAN] Failed to back up $artifact_type: $artifact"
                    autofix_existing_cleanup_failed_installation_backup_if_needed "$cleanup_backup_dir_on_failure" "$backup_dir"
                    return 1
                fi
            else
                if ! cp -p "$artifact" "$dest" 2>/dev/null; then
                    log_error "[CLEAN] Failed to back up file: $artifact"
                    autofix_existing_cleanup_failed_installation_backup_if_needed "$cleanup_backup_dir_on_failure" "$backup_dir"
                    return 1
                fi
            fi
            if ! autofix_sync_backup_path "$dest"; then
                log_error "[CLEAN] Failed to fsync backup artifact: $dest"
                autofix_existing_cleanup_failed_installation_backup_if_needed "$cleanup_backup_dir_on_failure" "$backup_dir"
                return 1
            fi

            checksum="$(calculate_backup_checksum "$artifact" 2>/dev/null || true)"
            if [[ -z "$checksum" ]]; then
                log_error "[CLEAN] Failed to checksum original artifact: $artifact"
                autofix_existing_cleanup_failed_installation_backup_if_needed "$cleanup_backup_dir_on_failure" "$backup_dir"
                return 1
            fi

            backup_checksum="$(calculate_backup_checksum "$dest" 2>/dev/null || true)"
            if [[ -z "$backup_checksum" ]]; then
                log_error "[CLEAN] Failed to checksum backup artifact: $dest"
                autofix_existing_cleanup_failed_installation_backup_if_needed "$cleanup_backup_dir_on_failure" "$backup_dir"
                return 1
            fi
            if [[ "$backup_checksum" != "$checksum" ]]; then
                log_error "[CLEAN] Backup verification failed for: $artifact"
                log_error "[CLEAN]   Original checksum: $checksum"
                log_error "[CLEAN]   Backup checksum:   $backup_checksum"
                autofix_existing_cleanup_failed_installation_backup_if_needed "$cleanup_backup_dir_on_failure" "$backup_dir"
                return 1
            fi

            backup_item="$(jq -cn \
                --arg original "$artifact" \
                --arg backup "$dest" \
                --arg path_type "$artifact_type" \
                --arg checksum "$checksum" \
                '{original: $original, backup: $backup, path_type: $path_type, checksum: $checksum}')"
            backed_up_items+=("$backup_item")
        fi
    done < <(autofix_existing_artifacts 2>/dev/null || true)

    # Write manifest
    if ! items_json=$(printf '%s\n' "${backed_up_items[@]}" | jq -s '.'); then
        log_error "[CLEAN] Failed to serialize backup manifest entries"
        autofix_existing_cleanup_failed_installation_backup_if_needed "$cleanup_backup_dir_on_failure" "$backup_dir"
        return 1
    fi

    if ! jq -n \
        --arg created "$(date -Iseconds)" \
        --argjson items "$items_json" \
        '{created: $created, backed_up_items: $items}' > "$backup_manifest"; then
        log_error "[CLEAN] Failed to write backup manifest: $backup_manifest"
        autofix_existing_cleanup_failed_installation_backup_if_needed "$cleanup_backup_dir_on_failure" "$backup_dir"
        return 1
    fi
    if ! fsync_file "$backup_manifest"; then
        log_error "[CLEAN] Failed to fsync backup manifest: $backup_manifest"
        autofix_existing_cleanup_failed_installation_backup_if_needed "$cleanup_backup_dir_on_failure" "$backup_dir"
        return 1
    fi

    cleanup_backup_dir_on_failure=false
    echo "$backup_dir"
}

# Remove all ACFS artifacts
remove_acfs_artifacts() {
    local artifact=""
    local failed=0

    while IFS= read -r artifact; do
        [[ -n "$artifact" ]] || continue
        if autofix_path_exists "$artifact"; then
            log_info "[CLEAN] Removing: $artifact"
            if ! rm -rf "$artifact"; then
                if [[ "$artifact" == "/usr/local/bin/acfs" ]] && [[ $EUID -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
                    if ! sudo -n rm -rf "$artifact"; then
                        log_error "[CLEAN] Failed to remove artifact with sudo: $artifact"
                        failed=1
                    fi
                else
                    log_error "[CLEAN] Failed to remove artifact: $artifact"
                    failed=1
                fi
            fi
        fi
    done < <(autofix_existing_artifacts 2>/dev/null || true)

    [[ $failed -eq 0 ]]
}

# Clean ACFS entries from shell configs
clean_shell_configs() {
    local config=""
    local edit_config=""
    local config_backup=""
    local restore_command=""
    local files_json=""
    local temp_file=""
    local orig_mode=""
    local orig_owner=""
    local temp_owner=""
    local grep_exit=0
    local failed=0
    local recovery_incomplete=0

    while IFS= read -r config; do
        [[ -n "$config" ]] || continue
        edit_config="$(autofix_existing_shell_config_edit_path "$config" 2>/dev/null || true)"
        if [[ -n "$edit_config" ]]; then
            # Check if config has ACFS-related content
            if grep -qE '# ACFS|\.acfs|acfs_' "$edit_config" 2>/dev/null; then
                # Backup config first
                if ! config_backup=$(create_backup "$edit_config" "clean-shell-config") || [[ -z "$config_backup" ]]; then
                    log_error "[CLEAN] Failed to back up shell config before cleanup: $config"
                    failed=1
                    continue
                fi

                restore_command="$(autofix_backup_restore_command "$config_backup" 2>/dev/null || true)"
                if [[ -z "$restore_command" ]]; then
                    log_error "[CLEAN] Failed to build a restore command for $config"
                    failed=1
                    continue
                fi
                files_json="$(autofix_existing_shell_config_files_json "$config" "$edit_config" 2>/dev/null || printf '[]\n')"
                log_info "[CLEAN] Cleaning ACFS entries from $config"

                # Create temp file in same directory to preserve permissions on mv
                temp_file=$(mktemp -p "$(dirname "$edit_config")" ".acfs-clean.XXXXXX") || {
                    log_error "[CLEAN] Failed to create temp file for $config"
                    failed=1
                    continue
                }

                # Preserve original permissions by copying mode
                orig_mode=$(stat -c '%a' "$edit_config" 2>/dev/null || stat -f '%Lp' "$edit_config" 2>/dev/null)
                orig_owner=$(stat -c '%u:%g' "$edit_config" 2>/dev/null || stat -f '%u:%g' "$edit_config" 2>/dev/null)

                grep_exit=0
                grep -vE '# ACFS|\.acfs|acfs_' "$edit_config" > "$temp_file" || grep_exit=$?
                if [[ $grep_exit -ne 0 && $grep_exit -ne 1 ]]; then
                    log_error "[CLEAN] Failed to filter ACFS entries from $config"
                    rm -f "$temp_file" 2>/dev/null || true
                    failed=1
                    continue
                fi

                # Restore original permissions before move
                if [[ -n "$orig_mode" ]] && ! chmod "$orig_mode" "$temp_file"; then
                    log_error "[CLEAN] Failed to preserve permissions for $config"
                    rm -f "$temp_file" 2>/dev/null || true
                    failed=1
                    continue
                fi

                temp_owner=$(stat -c '%u:%g' "$temp_file" 2>/dev/null || stat -f '%u:%g' "$temp_file" 2>/dev/null)
                if [[ -n "$orig_owner" && -n "$temp_owner" && "$orig_owner" != "$temp_owner" ]]; then
                    if ! chown "$orig_owner" "$temp_file" 2>/dev/null; then
                        log_error "[CLEAN] Failed to preserve ownership for $config"
                        rm -f "$temp_file" 2>/dev/null || true
                        failed=1
                        continue
                    fi
                fi

                if ! mv "$temp_file" "$edit_config"; then
                    log_error "[CLEAN] Failed to write cleaned shell config: $config"
                    rm -f "$temp_file" 2>/dev/null || true
                    failed=1
                    continue
                fi

                if ! record_change \
                    "acfs" \
                    "Cleaned ACFS entries from $config" \
                    "$restore_command" \
                    false \
                    "info" \
                    "$files_json" \
                    "$(printf '%s' "$config_backup" | jq -c '[.]' 2>/dev/null || echo '[]')" \
                    '[]' >/dev/null; then
                    log_error "[CLEAN] Failed to record shell config cleanup for $config"
                    if ! autofix_existing_restore_from_backup "$config_backup" "$edit_config"; then
                        log_error "[CLEAN] Failed to restore $config after journaling failure"
                        recovery_incomplete=1
                    fi
                    failed=1
                fi
            fi
        fi
    done < <(autofix_existing_shell_configs 2>/dev/null || true)

    if (( recovery_incomplete != 0 )); then
        return 2
    fi
    [[ $failed -eq 0 ]]
}

autofix_existing_relocate_state_for_clean_reinstall() {
    local runtime_home=""
    local state_dir=""
    local relocated_state_dir=""

    runtime_home="$(autofix_existing_runtime_home 2>/dev/null || true)"
    state_dir="$(autofix_sanitize_abs_nonroot_path "${ACFS_STATE_DIR:-}" 2>/dev/null || true)"
    [[ -n "$runtime_home" && -n "$state_dir" ]] || return 0

    case "$state_dir" in
        "$runtime_home/.acfs"/*)
            relocated_state_dir="$(mktemp -d "$runtime_home/.acfs-autofix-clean.XXXXXX" 2>/dev/null || true)"
            if [[ -z "$relocated_state_dir" ]]; then
                relocated_state_dir="$runtime_home/.acfs-autofix-clean.$(date +%s)"
                mkdir -p "$relocated_state_dir" || return 1
            fi
            rmdir "$relocated_state_dir" 2>/dev/null || true

            mv "$state_dir" "$relocated_state_dir" || {
                log_error "[CLEAN] Failed to relocate autofix state: $state_dir"
                return 1
            }

            ACFS_STATE_DIR="$relocated_state_dir"
            ACFS_CHANGES_FILE="$ACFS_STATE_DIR/changes.jsonl"
            ACFS_UNDOS_FILE="$ACFS_STATE_DIR/undos.jsonl"
            ACFS_BACKUPS_DIR="$ACFS_STATE_DIR/backups"
            ACFS_LOCK_FILE="$ACFS_STATE_DIR/.lock"
            ACFS_INTEGRITY_FILE="$ACFS_STATE_DIR/.integrity"
            ACFS_CLEAN_RELOCATED_STATE_ORIG="$state_dir"
            ACFS_CLEAN_RELOCATED_STATE_NEW="$relocated_state_dir"

            log_info "[CLEAN] Relocated autofix state to $ACFS_STATE_DIR"
            ;;
    esac
}

autofix_existing_restore_relocated_state_after_clean_abort() {
    local original_state_dir="${ACFS_CLEAN_RELOCATED_STATE_ORIG:-}"
    local relocated_state_dir="${ACFS_CLEAN_RELOCATED_STATE_NEW:-}"
    local original_parent=""
    local relocated_parent=""
    local replace_existing="${1:-false}"

    [[ -n "$original_state_dir" && -n "$relocated_state_dir" ]] || return 0
    [[ -d "$relocated_state_dir" ]] || return 0

    original_parent="$(dirname "$original_state_dir")"
    relocated_parent="$(dirname "$relocated_state_dir")"

    if ! mkdir -p "$original_parent"; then
        log_error "[CLEAN] Failed to recreate autofix state parent directory: $original_parent"
        return 1
    fi
    if autofix_path_exists "$original_state_dir"; then
        if [[ "$replace_existing" == "true" ]]; then
            if ! rm -rf "$original_state_dir"; then
                log_error "[CLEAN] Failed to replace existing autofix state path: $original_state_dir"
                return 1
            fi
        else
            log_error "[CLEAN] Refusing to restore relocated autofix state over existing path: $original_state_dir"
            return 1
        fi
    fi
    if ! mv "$relocated_state_dir" "$original_state_dir"; then
        log_error "[CLEAN] Failed to restore relocated autofix state to $original_state_dir"
        return 1
    fi

    fsync_directory "$original_parent" >/dev/null 2>&1 || true
    fsync_directory "$relocated_parent" >/dev/null 2>&1 || true

    ACFS_STATE_DIR="$original_state_dir"
    ACFS_CHANGES_FILE="$ACFS_STATE_DIR/changes.jsonl"
    ACFS_UNDOS_FILE="$ACFS_STATE_DIR/undos.jsonl"
    ACFS_BACKUPS_DIR="$ACFS_STATE_DIR/backups"
    ACFS_LOCK_FILE="$ACFS_STATE_DIR/.lock"
    ACFS_INTEGRITY_FILE="$ACFS_STATE_DIR/.integrity"
    ACFS_CLEAN_RELOCATED_STATE_ORIG=""
    ACFS_CLEAN_RELOCATED_STATE_NEW=""
    return 0
}

autofix_existing_restore_installation_backup() {
    local backup_dir="$1"
    local backup_manifest=""
    local backup_item=""
    local restore_failed=0

    [[ -n "$backup_dir" ]] || return 1
    backup_manifest="$backup_dir/manifest.json"
    [[ -f "$backup_manifest" ]] || return 1

    while IFS= read -r backup_item; do
        [[ -n "$backup_item" ]] || continue
        if ! autofix_existing_restore_from_backup "$backup_item"; then
            log_error "[CLEAN] Failed to restore backed-up artifact during clean reinstall recovery"
            restore_failed=1
        fi
    done < <(jq -c '.backed_up_items // [] | .[]' "$backup_manifest" 2>/dev/null)

    [[ $restore_failed -eq 0 ]]
}

# Perform clean reinstall
clean_reinstall() {
    log_warn "[CLEAN] Starting clean reinstall - this will remove existing installation"

    # Step 1: Create comprehensive backup
    local backup_dir
    local artifacts_json=""
    local backups_json="[]"
    local clean_record_index=-1
    if ! backup_dir=$(create_installation_backup); then
        log_error "[CLEAN] Backup creation failed; aborting clean reinstall"
        return 1
    fi
    if [[ -f "$backup_dir/manifest.json" ]]; then
        backups_json="$(jq -c '.backed_up_items // []' "$backup_dir/manifest.json" 2>/dev/null || printf '[]\n')"
    fi

    if ! autofix_existing_relocate_state_for_clean_reinstall; then
        log_error "[CLEAN] Failed to preserve autofix state before removing ACFS artifacts"
        return 1
    fi

    # Step 2: Record the clean reinstall change before destructive removal begins
    artifacts_json=$(autofix_existing_artifacts 2>/dev/null | jq -R . | jq -s '.')

    if ! record_change \
        "acfs" \
        "Clean reinstall - removed existing ACFS installation" \
        "# Restore from backup: $backup_dir" \
        false \
        "warning" \
        "$artifacts_json" \
        "$backups_json" \
        '[]' \
        false >/dev/null; then
        log_error "[CLEAN] Failed to record clean reinstall operation"
        if ! autofix_existing_restore_relocated_state_after_clean_abort; then
            log_error "[CLEAN] Failed to restore relocated autofix state after journaling failure"
        fi
        return 1
    fi
    clean_record_index=$((${#ACFS_CHANGE_ORDER[@]} - 1))

    # Step 3: Remove existing installation
    if ! remove_acfs_artifacts; then
        local restore_ok=false
        local state_restore_ok=false
        log_error "[CLEAN] Failed to remove one or more ACFS artifacts"
        if ! autofix_existing_restore_installation_backup "$backup_dir"; then
            log_error "[CLEAN] Failed to restore installation backup after artifact removal failure"
        else
            restore_ok=true
        fi
        if ! autofix_existing_restore_relocated_state_after_clean_abort true; then
            log_error "[CLEAN] Failed to restore relocated autofix state after artifact removal failure"
        else
            state_restore_ok=true
        fi
        if [[ "$restore_ok" == "true" && "$state_restore_ok" == "true" ]]; then
            if ! autofix_existing_drop_changes_since "$clean_record_index"; then
                log_error "[CLEAN] Failed to prune aborted clean reinstall journal entries after artifact removal failure"
            fi
        else
            log_warn "[CLEAN] Preserving aborted clean reinstall journal because recovery after artifact removal failure was incomplete"
        fi
        return 1
    fi

    # Step 4: Clean shell configs
    local clean_shell_status=0
    clean_shell_configs || clean_shell_status=$?
    if (( clean_shell_status != 0 )); then
        local cleanup_rollback_ok=false
        local restore_ok=false
        local state_restore_ok=false
        log_error "[CLEAN] Failed to clean one or more shell configs"
        if (( clean_record_index >= 0 )); then
            if ! autofix_existing_rollback_changes_since "$((clean_record_index + 1))"; then
                log_error "[CLEAN] Failed to roll back shell config cleanups after clean reinstall failure"
            else
                cleanup_rollback_ok=true
            fi
        else
            cleanup_rollback_ok=true
        fi
        if ! autofix_existing_restore_installation_backup "$backup_dir"; then
            log_error "[CLEAN] Failed to restore installation backup after shell config cleanup failure"
        else
            restore_ok=true
        fi
        if ! autofix_existing_restore_relocated_state_after_clean_abort true; then
            log_error "[CLEAN] Failed to restore relocated autofix state after shell config cleanup failure"
        else
            state_restore_ok=true
        fi
        if [[ "$cleanup_rollback_ok" == "true" && "$restore_ok" == "true" && "$state_restore_ok" == "true" && $clean_shell_status -ne 2 ]]; then
            if ! autofix_existing_drop_changes_since "$clean_record_index"; then
                log_error "[CLEAN] Failed to prune aborted clean reinstall journal entries after shell config cleanup failure"
            fi
        else
            log_warn "[CLEAN] Preserving aborted clean reinstall journal because shell config cleanup recovery was incomplete"
        fi
        return 1
    fi

    log_info "[CLEAN] Clean removal complete"
    log_info "[CLEAN] Backup saved to: $backup_dir"
    log_info "[CLEAN] Proceeding with fresh installation..."

    return 0
}

# =============================================================================
# Main Handler
# =============================================================================

# Handle existing installation (interactive mode)
# Arguments:
#   $1 - new version being installed
#   $2 - mode: "interactive" (default), "upgrade", "clean", "abort"
# Returns:
#   0 - continue with installation
#   1 - abort installation
handle_existing_installation() {
    local new_version="${1:-${ACFS_VERSION:-unknown}}"
    local mode="${2:-interactive}"

    # Check for existing installation
    local markers
    if ! markers=$(detect_existing_acfs); then
        log_debug "[EXISTING] No existing installation detected"
        return 0  # No existing installation, continue
    fi

    local current_version
    current_version=$(get_installed_version)

    local state
    state=$(detect_installation_state)

    # `abort` short-circuits before any backups, so it does not need a session.
    if [[ "$mode" == "abort" ]]; then
        log_info "Aborting installation per request."
        return 1
    fi

    # Both upgrade and clean paths call create_backup/record_change, which
    # require an active autofix session. When this function is invoked from
    # handle_autofix dispatch or the CLI entry points, no session has been
    # started yet — acquire one here and release it on exit.
    local session_owned=false
    if ! autofix_ensure_session session_owned; then
        log_error "[EXISTING] Failed to start autofix session for existing-installation handling"
        return 1
    fi

    local result=1
    case "$mode" in
        upgrade)
            if upgrade_existing_installation "$current_version" "$new_version"; then
                result=0
            fi
            ;;
        clean)
            if clean_reinstall; then
                result=0
            fi
            ;;
        *)
            # Interactive mode - show info and prompt
            log_warn "════════════════════════════════════════════════════════════"
            log_warn "  Existing ACFS installation detected!"
            log_warn "════════════════════════════════════════════════════════════"
            log_warn ""
            log_warn "  Current version: $current_version"
            log_warn "  New version:     $new_version"
            log_warn "  State:           $state"
            log_warn ""
            log_warn "  Found markers:"
            # shellcheck disable=SC2086
            for marker in $markers; do
                log_warn "    - $marker"
            done
            log_warn ""

            echo ""
            echo "How would you like to proceed?"
            echo ""
            echo "  1) Upgrade (Recommended) - Keep config, update binaries"
            echo "  2) Clean reinstall - Backup and start fresh"
            echo "  3) Abort - Exit without changes"
            echo ""

            local choice
            read -rp "Enter choice [1-3]: " choice < /dev/tty

            case "$choice" in
                1)
                    if upgrade_existing_installation "$current_version" "$new_version"; then
                        result=0
                    fi
                    ;;
                2)
                    if clean_reinstall; then
                        result=0
                    fi
                    ;;
                3|*)
                    log_info "Aborting installation."
                    result=1
                    ;;
            esac
            ;;
    esac

    if ! autofix_finalize_managed_session "$session_owned"; then
        log_error "[EXISTING] Failed to finalize autofix session"
        return 1
    fi

    return "$result"
}

# Non-interactive upgrade check (for CI/automated runs)
# Returns 0 if should proceed with install, 1 if should abort
autofix_existing_should_proceed() {
    local new_version="${1:-${ACFS_VERSION:-unknown}}"
    local force="${2:-false}"

    if ! autofix_existing_acfs_needs_handling; then
        return 0  # No existing installation, proceed
    fi

    local current_version
    current_version=$(get_installed_version)

    # If force mode, always proceed with upgrade
    if [[ "$force" == "true" ]]; then
        log_info "[AUTO] Force mode - proceeding with upgrade"
        local session_owned=false
        if ! autofix_ensure_session session_owned; then
            log_error "[AUTO] Failed to start autofix session for force-mode upgrade"
            return 1
        fi
        local upgrade_result=1
        if upgrade_existing_installation "$current_version" "$new_version"; then
            upgrade_result=0
        fi
        if ! autofix_finalize_managed_session "$session_owned"; then
            log_error "[AUTO] Failed to finalize autofix session after force-mode upgrade"
            return 1
        fi
        return "$upgrade_result"
    fi

    # Compare versions
    local cmp
    cmp=$(version_compare "$current_version" "$new_version")

    case "$cmp" in
        -1)
            # Current < New: upgrade available
            log_info "[AUTO] Newer version available ($current_version -> $new_version)"
            return 0  # Proceed with upgrade
            ;;
        0)
            # Same version
            log_info "[AUTO] Same version already installed ($current_version)"
            return 1  # Skip installation
            ;;
        1)
            # Current > New: downgrade not supported
            log_warn "[AUTO] Installed version ($current_version) is newer than target ($new_version)"
            return 1  # Abort
            ;;
    esac
}

# =============================================================================
# Verification
# =============================================================================

# Verify installation is complete and functional
verify_installation() {
    log_info "[VERIFY] Checking installation..."

    local errors=0
    local runtime_home=""
    local acfs_home=""

    runtime_home="$(autofix_existing_runtime_home 2>/dev/null || true)"
    acfs_home="$(autofix_existing_acfs_home 2>/dev/null || true)"

    # Check config directory
    if [[ -z "$acfs_home" ]] || [[ ! -d "$acfs_home" ]]; then
        log_warn "[VERIFY] Config directory missing"
        ((errors++)) || true
    fi

    # Check version file
    if [[ -z "$acfs_home" ]] || [[ ! -f "$acfs_home/version" ]]; then
        log_warn "[VERIFY] Version file missing"
        ((errors++)) || true
    fi

    # Check .local/bin exists
    if [[ -z "$runtime_home" ]] || [[ ! -d "$runtime_home/.local/bin" ]]; then
        log_warn "[VERIFY] ~/.local/bin directory missing"
        ((errors++)) || true
    fi

    if [[ $errors -gt 0 ]]; then
        log_warn "[VERIFY] Found $errors issues"
        return 1
    fi

    log_info "[VERIFY] Installation verified successfully"
    return 0
}

# =============================================================================
# CLI Interface
# =============================================================================

# Run when script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-check}" in
        check)
            autofix_existing_acfs_check
            ;;
        needs-handling)
            if autofix_existing_acfs_needs_handling; then
                echo "true"
                exit 0
            else
                echo "false"
                exit 1
            fi
            ;;
        handle)
            handle_existing_installation "${2:-}" "${3:-interactive}"
            ;;
        upgrade)
            handle_existing_installation "${2:-}" "upgrade"
            ;;
        clean)
            handle_existing_installation "${2:-}" "clean"
            ;;
        verify)
            verify_installation
            ;;
        version)
            get_installed_version
            ;;
        *)
            echo "Usage: $0 {check|needs-handling|handle|upgrade|clean|verify|version}"
            echo ""
            echo "Commands:"
            echo "  check          Output JSON status of existing installation"
            echo "  needs-handling Exit 0 if existing installation found, 1 if clean"
            echo "  handle [ver]   Interactive handling of existing installation"
            echo "  upgrade [ver]  Non-interactive upgrade"
            echo "  clean [ver]    Non-interactive clean reinstall"
            echo "  verify         Verify installation is complete"
            echo "  version        Show installed version"
            exit 1
            ;;
    esac
fi
