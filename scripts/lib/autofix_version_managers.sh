#!/usr/bin/env bash
# ============================================================
# ACFS Auto-Fix for Version Manager Conflicts
#
# Handles nvm and pyenv installations that conflict with
# ACFS-managed versions.
#
# Related beads:
#   - bd-19y9.3.2: Implement auto-fix for nvm/pyenv conflicts
#   - bd-19y9.3.3: Change recording and undo system (dependency)
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_AUTOFIX_VERSION_MANAGERS_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_AUTOFIX_VERSION_MANAGERS_SH_LOADED=1

# Source the autofix base library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/autofix.sh"

autofix_version_managers_runtime_home() {
    local runtime_home=""

    if declare -f autofix_runtime_home >/dev/null 2>&1; then
        runtime_home="$(autofix_runtime_home 2>/dev/null || true)"
    fi
    runtime_home="$(autofix_sanitize_abs_nonroot_path "$runtime_home" 2>/dev/null || true)"
    if [[ -n "$runtime_home" ]]; then
        printf '%s\n' "$runtime_home"
        return 0
    fi

    runtime_home="$(autofix_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"
    if [[ -n "$runtime_home" ]]; then
        printf '%s\n' "$runtime_home"
        return 0
    fi

    runtime_home="$(autofix_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    if [[ -n "$runtime_home" ]]; then
        printf '%s\n' "$runtime_home"
        return 0
    fi

    return 1
}

# Only trust env-provided directories when they belong to the resolved
# runtime home, otherwise root/sudo callers can leak their own XDG/NVM/PYENV
# paths into target-user repairs.
autofix_version_managers_path_belongs_to_runtime_home() {
    local candidate_path=""
    local runtime_home=""

    candidate_path="$(autofix_sanitize_abs_nonroot_path "${1:-}" 2>/dev/null || true)"
    runtime_home="$(autofix_sanitize_abs_nonroot_path "${2:-}" 2>/dev/null || true)"

    [[ -n "$candidate_path" ]] || return 1
    [[ -n "$runtime_home" ]] || return 1
    [[ "$candidate_path" == "$runtime_home" || "$candidate_path" == "$runtime_home"/* ]]
}

autofix_version_managers_restore() {
    local restore_command="${1:-}"

    [[ -n "$restore_command" ]] || return 1
    autofix_run_restore_command "$restore_command"
}

# ============================================================
# NVM Detection and Fix
# ============================================================

# Check for existing nvm installation
# Returns JSON with status, nvm_dir, version, shell_configs
autofix_nvm_check() {
    local status="none"
    local -a found_nvm_dirs=()
    local nvm_version=""
    local shell_configs=()
    local runtime_home=""
    local config_home=""

    runtime_home="$(autofix_version_managers_runtime_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1

    # Check for NVM_DIR environment variable. Ignore caller-shell values from a
    # different home when TARGET_HOME is driving the repair.
    if [[ -n "${NVM_DIR:-}" ]] && { [[ "$runtime_home" == "${HOME%/}" ]] || autofix_version_managers_path_belongs_to_runtime_home "$NVM_DIR" "$runtime_home"; }; then
        found_nvm_dirs+=("$NVM_DIR")
        status="env_set"
    fi

    config_home="$(autofix_sanitize_abs_nonroot_path "${XDG_CONFIG_HOME:-}" 2>/dev/null || true)"
    if [[ -z "$config_home" ]] || ! { [[ "$runtime_home" == "${HOME%/}" ]] || autofix_version_managers_path_belongs_to_runtime_home "$config_home" "$runtime_home"; }; then
        config_home="$runtime_home/.config"
    fi

    # Check common locations
    local nvm_locations=(
        "$runtime_home/.nvm"
        "$config_home/nvm"
    )

    for loc in "${nvm_locations[@]}"; do
        if [[ -d "$loc" ]]; then
            status="installed"
            # Avoid duplicates if NVM_DIR was already added
            local already_found=false
            for found in "${found_nvm_dirs[@]}"; do
                [[ "$found" == "$loc" ]] && already_found=true && break
            done
            if [[ "$already_found" == "false" ]]; then
                found_nvm_dirs+=("$loc")
            fi

            # Get installed version (from the first one we find)
            if [[ -z "$nvm_version" && -f "$loc/nvm.sh" ]]; then
                nvm_version=$(grep "NVM_VERSION=" "$loc/nvm.sh" 2>/dev/null | head -1 | cut -d'"' -f2 || echo "unknown")
            fi
        fi
    done

    # Check shell configs for nvm references
    local configs=(
        "$runtime_home/.bashrc"
        "$runtime_home/.zshrc"
        "$runtime_home/.profile"
        "$runtime_home/.bash_profile"
        "$runtime_home/.zprofile"
    )

    for config in "${configs[@]}"; do
        if [[ -f "$config" ]] && grep -q "NVM_DIR\|nvm.sh\|nvm use\|nvm alias" "$config" 2>/dev/null; then
            shell_configs+=("$config")
        fi
    done

    # Build JSON output
    local found_nvm_dirs_json="[]"
    if [[ ${#found_nvm_dirs[@]} -gt 0 ]]; then
        found_nvm_dirs_json=$(printf '%s\n' "${found_nvm_dirs[@]}" | jq -R . | jq -s .)
    fi

    local shell_configs_json="[]"
    if [[ ${#shell_configs[@]} -gt 0 ]]; then
        shell_configs_json=$(printf '%s\n' "${shell_configs[@]}" | jq -R . | jq -s .)
    fi

    jq -n \
        --arg status "$status" \
        --argjson nvm_dirs "$found_nvm_dirs_json" \
        --arg nvm_version "$nvm_version" \
        --argjson shell_configs "$shell_configs_json" \
        '{
            status: $status,
            nvm_dirs: $nvm_dirs,
            version: $nvm_version,
            shell_configs: $shell_configs
        }'
}

# Fix nvm installation conflicts
# Usage: autofix_nvm_fix [mode]
# Modes: fix (default), dry-run
# Returns: 0=success, 1=partial fix, 2=failed
autofix_nvm_fix() {
    local mode="${1:-fix}"
    local session_owned=false
    local result=0

    log_info "[AUTO-FIX:nvm] Starting nvm fix (mode=$mode)"

    local check_result
    if ! check_result=$(autofix_nvm_check); then
        log_error "[AUTO-FIX:nvm] Failed to inspect the existing nvm installation"
        return 2
    fi
    local status
    if ! status=$(echo "$check_result" | jq -er '.status | strings'); then
        log_error "[AUTO-FIX:nvm] Inspection returned malformed status data"
        return 2
    fi

    if [[ "$status" == "none" ]]; then
        log_info "[AUTO-FIX:nvm] No nvm installation detected"
        return 0
    fi

    local nvm_version
    nvm_version=$(echo "$check_result" | jq -r '.version')

    local config_count
    config_count=$(echo "$check_result" | jq -r '.shell_configs | length')

    log_info "[AUTO-FIX:nvm] Found nvm $nvm_version"
    log_info "[AUTO-FIX:nvm] Shell configs affected: $config_count files"

    if [[ "$mode" == "dry-run" ]]; then
        echo "$check_result" | jq -r '.nvm_dirs[]' | while IFS= read -r dir; do
            log_info "[DRY-RUN] Would backup $dir"
        done
        echo "$check_result" | jq -r '.shell_configs[]' | while IFS= read -r config; do
            log_info "[DRY-RUN] Would backup and clean nvm references from $config"
        done
        return 0
    fi

    if ! autofix_ensure_session session_owned; then
        log_error "[AUTO-FIX:nvm] Failed to start autofix session"
        return 2
    fi

    local partial_failure=0

    # STEP 1: Create verified backup of nvm directories
    while IFS= read -r nvm_dir; do
        [[ -z "$nvm_dir" ]] && continue
        
        # SECURITY: Prevent accidental deletion of critical directories
        if [[ "$nvm_dir" == "/" || "$nvm_dir" == "$HOME" || "$nvm_dir" == "/usr" || "$nvm_dir" == "/usr/local" ]]; then
            log_error "[AUTO-FIX:nvm] Unsafe nvm_dir detected: '$nvm_dir'. Skipping this directory."
            partial_failure=1
            continue
        fi

        if [[ -d "$nvm_dir" ]]; then
            local backup_info
            if ! backup_info=$(create_backup "$nvm_dir" "nvm-directory") || [[ -z "$backup_info" ]]; then
                log_error "[AUTO-FIX:nvm] Failed to create backup of $nvm_dir"
                partial_failure=1
                continue
            fi

            local backup_path backup_checksum
            local restore_command=""
            backup_path=$(echo "$backup_info" | jq -r '.backup')
            backup_checksum=$(echo "$backup_info" | jq -r '.checksum')
            restore_command="$(autofix_backup_restore_command "$backup_info" 2>/dev/null || true)"

            log_info "[AUTO-FIX:nvm] Created backup: $backup_path (checksum: ${backup_checksum:0:16}...)"

            if [[ -z "$restore_command" ]]; then
                log_error "[AUTO-FIX:nvm] Failed to build restore command for $nvm_dir"
                partial_failure=1
                continue
            fi

            if ! rm -rf "$nvm_dir"; then
                log_error "[AUTO-FIX:nvm] Failed to remove original nvm directory: $nvm_dir"
                if ! autofix_version_managers_restore "$restore_command"; then
                    log_error "[AUTO-FIX:nvm] Failed to restore $nvm_dir after removal failure"
                fi
                partial_failure=1
                continue
            fi

            if ! record_change \
                "nvm" \
                "Backed up and moved nvm directory: $nvm_dir" \
                "$restore_command" \
                false \
                "warning" \
                "$(autofix_files_json "$nvm_dir")" \
                "[$backup_info]" \
                '[]' >/dev/null; then
                log_error "[AUTO-FIX:nvm] Failed to record nvm directory migration for $nvm_dir"
                if ! autofix_version_managers_restore "$restore_command"; then
                    log_error "[AUTO-FIX:nvm] Failed to restore $nvm_dir after journaling failure"
                fi
                partial_failure=1
                continue
            fi

            log_info "[AUTO-FIX:nvm] Removed original nvm directory: $nvm_dir"
        fi
    done < <(echo "$check_result" | jq -r '.nvm_dirs[]')

    # STEP 2: Clean shell configuration files
    while IFS= read -r config; do
        [[ -z "$config" ]] && continue
        log_info "[AUTO-FIX:nvm] Cleaning nvm references from $config"

        # Create backup of config file
        local config_backup
        if config_backup=$(create_backup "$config" "shell-config") && [[ -n "$config_backup" ]]; then
            local config_backup_path
            local restore_command=""
            config_backup_path=$(echo "$config_backup" | jq -r '.backup')
            restore_command="$(autofix_backup_restore_command "$config_backup" 2>/dev/null || true)"
            log_info "[AUTO-FIX:nvm] Backed up config: $config_backup_path"

            if [[ -z "$restore_command" ]]; then
                log_error "[AUTO-FIX:nvm] Failed to build restore command for $config"
                partial_failure=1
                continue
            fi

            # Remove nvm-related lines using sed
            # Pattern: lines containing NVM_DIR, nvm.sh, nvm use, nvm alias, or NVM comments
            local removed_lines
            removed_lines=$(grep -E "NVM_DIR|nvm\.sh|nvm use|nvm alias" "$config" 2>/dev/null || true)
            if [[ -n "$removed_lines" ]]; then
                log_debug "[AUTO-FIX:nvm] Removing lines from $config:"
                echo "$removed_lines" | while IFS= read -r line; do
                    log_debug "  - $line"
                done
            fi

            # Apply sed to remove nvm-related lines
            if ! sed -i \
                -e '/export NVM_DIR/d' \
                -e '/\[ -s.*nvm\.sh \]/d' \
                -e '/\. "$NVM_DIR\/nvm\.sh"/d' \
                -e '/source.*nvm\.sh/d' \
                -e '/nvm use/d' \
                -e '/nvm alias/d' \
                -e '/# NVM/d' \
                -e '/# Node Version Manager/d' \
                -e '/# nvm/d' \
                "$config"; then
                log_warn "[AUTO-FIX:nvm] Failed to clean $config"
                if ! autofix_version_managers_restore "$restore_command"; then
                    log_error "[AUTO-FIX:nvm] Failed to restore $config after cleanup failure"
                fi
                partial_failure=1
                continue
            fi

            if ! record_change \
                "nvm" \
                "Cleaned nvm references from $config" \
                "$restore_command" \
                false \
                "info" \
                "$(autofix_files_json "$config")" \
                "[$config_backup]" \
                '[]' >/dev/null; then
                log_error "[AUTO-FIX:nvm] Failed to record shell config cleanup for $config"
                if ! autofix_version_managers_restore "$restore_command"; then
                    log_error "[AUTO-FIX:nvm] Failed to restore $config after journaling failure"
                fi
                partial_failure=1
                continue
            fi
        else
            log_warn "[AUTO-FIX:nvm] Failed to backup $config, skipping"
            partial_failure=1
        fi
    done < <(echo "$check_result" | jq -r '.shell_configs[]')

    # STEP 3: Unset NVM_DIR in current shell (for this session)
    unset NVM_DIR 2>/dev/null || true

    if [[ $partial_failure -eq 1 ]]; then
        log_warn "[AUTO-FIX:nvm] Fix completed with some failures"
        result=1
    else
        log_info "[AUTO-FIX:nvm] Fix completed successfully"
        result=0
    fi
    if ! autofix_finalize_managed_session "$session_owned"; then
        log_error "[AUTO-FIX:nvm] Failed to finalize autofix session"
        return 2
    fi
    return "$result"
}

# ============================================================
# Pyenv Detection and Fix
# ============================================================

# Check for existing pyenv installation
# Returns JSON with status, pyenv_root, version, shell_configs
autofix_pyenv_check() {
    local status="none"
    local -a found_pyenv_roots=()
    local pyenv_version=""
    local shell_configs=()
    local runtime_home=""
    local data_home=""

    runtime_home="$(autofix_version_managers_runtime_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1

    # Check for PYENV_ROOT environment variable. Ignore caller-shell values from a
    # different home when TARGET_HOME is driving the repair.
    if [[ -n "${PYENV_ROOT:-}" ]] && { [[ "$runtime_home" == "${HOME%/}" ]] || autofix_version_managers_path_belongs_to_runtime_home "$PYENV_ROOT" "$runtime_home"; }; then
        found_pyenv_roots+=("$PYENV_ROOT")
        status="env_set"
    fi

    data_home="$(autofix_sanitize_abs_nonroot_path "${XDG_DATA_HOME:-}" 2>/dev/null || true)"
    if [[ -z "$data_home" ]] || ! { [[ "$runtime_home" == "${HOME%/}" ]] || autofix_version_managers_path_belongs_to_runtime_home "$data_home" "$runtime_home"; }; then
        data_home="$runtime_home/.local/share"
    fi

    # Check common locations
    local pyenv_locations=(
        "$runtime_home/.pyenv"
        "$data_home/pyenv"
    )

    for loc in "${pyenv_locations[@]}"; do
        if [[ -d "$loc" ]]; then
            status="installed"
            # Avoid duplicates if PYENV_ROOT was already added
            local already_found=false
            for found in "${found_pyenv_roots[@]}"; do
                [[ "$found" == "$loc" ]] && already_found=true && break
            done
            if [[ "$already_found" == "false" ]]; then
                found_pyenv_roots+=("$loc")
            fi

            # Get installed version (from the first one we find)
            if [[ -z "$pyenv_version" && -x "$loc/bin/pyenv" ]]; then
                pyenv_version=$("$loc/bin/pyenv" --version 2>/dev/null | head -1 || echo "unknown")
            fi
        fi
    done

    # Check shell configs for pyenv references
    local configs=(
        "$runtime_home/.bashrc"
        "$runtime_home/.zshrc"
        "$runtime_home/.profile"
        "$runtime_home/.bash_profile"
        "$runtime_home/.zprofile"
    )

    for config in "${configs[@]}"; do
        if [[ -f "$config" ]] && grep -q "PYENV\|pyenv init\|pyenv virtualenv" "$config" 2>/dev/null; then
            shell_configs+=("$config")
        fi
    done

    # Build JSON output
    local found_pyenv_roots_json="[]"
    if [[ ${#found_pyenv_roots[@]} -gt 0 ]]; then
        found_pyenv_roots_json=$(printf '%s\n' "${found_pyenv_roots[@]}" | jq -R . | jq -s .)
    fi

    local shell_configs_json="[]"
    if [[ ${#shell_configs[@]} -gt 0 ]]; then
        shell_configs_json=$(printf '%s\n' "${shell_configs[@]}" | jq -R . | jq -s .)
    fi

    jq -n \
        --arg status "$status" \
        --argjson pyenv_roots "$found_pyenv_roots_json" \
        --arg pyenv_version "$pyenv_version" \
        --argjson shell_configs "$shell_configs_json" \
        '{
            status: $status,
            pyenv_roots: $pyenv_roots,
            version: $pyenv_version,
            shell_configs: $shell_configs
        }'
}

# Fix pyenv installation conflicts
# Usage: autofix_pyenv_fix [mode]
# Modes: fix (default), dry-run
# Returns: 0=success, 1=partial fix, 2=failed
autofix_pyenv_fix() {
    local mode="${1:-fix}"
    local session_owned=false
    local result=0

    log_info "[AUTO-FIX:pyenv] Starting pyenv fix (mode=$mode)"

    local check_result
    if ! check_result=$(autofix_pyenv_check); then
        log_error "[AUTO-FIX:pyenv] Failed to inspect the existing pyenv installation"
        return 2
    fi
    local status
    if ! status=$(echo "$check_result" | jq -er '.status | strings'); then
        log_error "[AUTO-FIX:pyenv] Inspection returned malformed status data"
        return 2
    fi

    if [[ "$status" == "none" ]]; then
        log_info "[AUTO-FIX:pyenv] No pyenv installation detected"
        return 0
    fi

    local pyenv_version
    pyenv_version=$(echo "$check_result" | jq -r '.version')

    local config_count
    config_count=$(echo "$check_result" | jq -r '.shell_configs | length')

    log_info "[AUTO-FIX:pyenv] Found pyenv $pyenv_version"
    log_info "[AUTO-FIX:pyenv] Shell configs affected: $config_count files"

    if [[ "$mode" == "dry-run" ]]; then
        echo "$check_result" | jq -r '.pyenv_roots[]' | while IFS= read -r dir; do
            log_info "[DRY-RUN] Would backup $dir"
        done
        echo "$check_result" | jq -r '.shell_configs[]' | while IFS= read -r config; do
            log_info "[DRY-RUN] Would backup and clean pyenv references from $config"
        done
        return 0
    fi

    if ! autofix_ensure_session session_owned; then
        log_error "[AUTO-FIX:pyenv] Failed to start autofix session"
        return 2
    fi

    local partial_failure=0

    # STEP 1: Create verified backup of pyenv directories
    while IFS= read -r pyenv_root; do
        [[ -z "$pyenv_root" ]] && continue

        # SECURITY: Prevent accidental deletion of critical directories
        if [[ "$pyenv_root" == "/" || "$pyenv_root" == "$HOME" || "$pyenv_root" == "/usr" || "$pyenv_root" == "/usr/local" ]]; then
            log_error "[AUTO-FIX:pyenv] Unsafe pyenv_root detected: '$pyenv_root'. Skipping this directory."
            partial_failure=1
            continue
        fi

        if [[ -d "$pyenv_root" ]]; then
            local backup_info
            if ! backup_info=$(create_backup "$pyenv_root" "pyenv-directory") || [[ -z "$backup_info" ]]; then
                log_error "[AUTO-FIX:pyenv] Failed to create backup of $pyenv_root"
                partial_failure=1
                continue
            fi

            local backup_path backup_checksum
            local restore_command=""
            backup_path=$(echo "$backup_info" | jq -r '.backup')
            backup_checksum=$(echo "$backup_info" | jq -r '.checksum')
            restore_command="$(autofix_backup_restore_command "$backup_info" 2>/dev/null || true)"

            log_info "[AUTO-FIX:pyenv] Created backup: $backup_path (checksum: ${backup_checksum:0:16}...)"

            if [[ -z "$restore_command" ]]; then
                log_error "[AUTO-FIX:pyenv] Failed to build restore command for $pyenv_root"
                partial_failure=1
                continue
            fi

            if ! rm -rf "$pyenv_root"; then
                log_error "[AUTO-FIX:pyenv] Failed to remove original pyenv directory: $pyenv_root"
                if ! autofix_version_managers_restore "$restore_command"; then
                    log_error "[AUTO-FIX:pyenv] Failed to restore $pyenv_root after removal failure"
                fi
                partial_failure=1
                continue
            fi

            if ! record_change \
                "pyenv" \
                "Backed up and moved pyenv directory: $pyenv_root" \
                "$restore_command" \
                false \
                "warning" \
                "$(autofix_files_json "$pyenv_root")" \
                "[$backup_info]" \
                '[]' >/dev/null; then
                log_error "[AUTO-FIX:pyenv] Failed to record pyenv directory migration for $pyenv_root"
                if ! autofix_version_managers_restore "$restore_command"; then
                    log_error "[AUTO-FIX:pyenv] Failed to restore $pyenv_root after journaling failure"
                fi
                partial_failure=1
                continue
            fi

            log_info "[AUTO-FIX:pyenv] Removed original pyenv directory: $pyenv_root"
        fi
    done < <(echo "$check_result" | jq -r '.pyenv_roots[]')

    # STEP 2: Clean shell configuration files
    while IFS= read -r config; do
        [[ -z "$config" ]] && continue
        log_info "[AUTO-FIX:pyenv] Cleaning pyenv references from $config"

        local config_backup
        if config_backup=$(create_backup "$config" "shell-config") && [[ -n "$config_backup" ]]; then
            local config_backup_path
            local restore_command=""
            config_backup_path=$(echo "$config_backup" | jq -r '.backup')
            restore_command="$(autofix_backup_restore_command "$config_backup" 2>/dev/null || true)"
            log_info "[AUTO-FIX:pyenv] Backed up config: $config_backup_path"

            if [[ -z "$restore_command" ]]; then
                log_error "[AUTO-FIX:pyenv] Failed to build restore command for $config"
                partial_failure=1
                continue
            fi

            # Remove pyenv-related lines
            local removed_lines
            removed_lines=$(grep -E "PYENV|pyenv init|pyenv virtualenv" "$config" 2>/dev/null || true)
            if [[ -n "$removed_lines" ]]; then
                log_debug "[AUTO-FIX:pyenv] Removing lines from $config:"
                echo "$removed_lines" | while IFS= read -r line; do
                    log_debug "  - $line"
                done
            fi

            if ! sed -i \
                -e '/export PYENV_ROOT/d' \
                -e '/pyenv init/d' \
                -e '/pyenv virtualenv-init/d' \
                -e '/# pyenv/d' \
                -e '/# Pyenv/d' \
                -e '/eval "$(pyenv/d' \
                -e '/PATH.*pyenv/d' \
                "$config"; then
                log_warn "[AUTO-FIX:pyenv] Failed to clean $config"
                if ! autofix_version_managers_restore "$restore_command"; then
                    log_error "[AUTO-FIX:pyenv] Failed to restore $config after cleanup failure"
                fi
                partial_failure=1
                continue
            fi

            if ! record_change \
                "pyenv" \
                "Cleaned pyenv references from $config" \
                "$restore_command" \
                false \
                "info" \
                "$(autofix_files_json "$config")" \
                "[$config_backup]" \
                '[]' >/dev/null; then
                log_error "[AUTO-FIX:pyenv] Failed to record shell config cleanup for $config"
                if ! autofix_version_managers_restore "$restore_command"; then
                    log_error "[AUTO-FIX:pyenv] Failed to restore $config after journaling failure"
                fi
                partial_failure=1
                continue
            fi
        else
            log_warn "[AUTO-FIX:pyenv] Failed to backup $config, skipping"
            partial_failure=1
        fi
    done < <(echo "$check_result" | jq -r '.shell_configs[]')

    # STEP 3: Unset PYENV_ROOT in current shell
    unset PYENV_ROOT 2>/dev/null || true

    if [[ $partial_failure -eq 1 ]]; then
        log_warn "[AUTO-FIX:pyenv] Fix completed with some failures"
        result=1
    else
        log_info "[AUTO-FIX:pyenv] Fix completed successfully"
        result=0
    fi
    if ! autofix_finalize_managed_session "$session_owned"; then
        log_error "[AUTO-FIX:pyenv] Failed to finalize autofix session"
        return 2
    fi
    return "$result"
}

# ============================================================
# Combined Operations
# ============================================================

# Check all version managers
# Returns JSON with nvm and pyenv status
autofix_version_managers_check() {
    local nvm_result pyenv_result
    nvm_result=$(autofix_nvm_check)
    pyenv_result=$(autofix_pyenv_check)

    jq -n \
        --argjson nvm "$nvm_result" \
        --argjson pyenv "$pyenv_result" \
        '{
            nvm: $nvm,
            pyenv: $pyenv,
            has_conflicts: (($nvm.status != "none") or ($pyenv.status != "none"))
        }'
}

# Fix all version manager conflicts
# Usage: autofix_version_managers_fix [mode]
# Returns: 0=success, 1=partial fix, 2=failed
autofix_version_managers_fix() {
    local mode="${1:-fix}"
    local overall_result=0
    local session_owned=false

    log_info "[AUTO-FIX] Starting version managers fix (mode=$mode)"

    if [[ "$mode" != "dry-run" ]]; then
        if ! autofix_ensure_session session_owned; then
            log_error "[AUTO-FIX] Failed to start autofix session for version manager fixes"
            return 2
        fi
    fi

    # Fix nvm
    local nvm_result=0
    autofix_nvm_fix "$mode" || nvm_result=$?
    if [[ $nvm_result -ne 0 ]]; then
        if [[ $nvm_result -eq 2 ]]; then
            log_error "[AUTO-FIX] nvm fix failed critically"
            overall_result=2
        elif [[ $nvm_result -eq 1 ]]; then
            log_warn "[AUTO-FIX] nvm fix had partial failures"
            [[ $overall_result -lt 2 ]] && overall_result=1
        fi
    fi

    # Fix pyenv
    local pyenv_result=0
    autofix_pyenv_fix "$mode" || pyenv_result=$?
    if [[ $pyenv_result -ne 0 ]]; then
        if [[ $pyenv_result -eq 2 ]]; then
            log_error "[AUTO-FIX] pyenv fix failed critically"
            overall_result=2
        elif [[ $pyenv_result -eq 1 ]]; then
            log_warn "[AUTO-FIX] pyenv fix had partial failures"
            [[ $overall_result -lt 2 ]] && overall_result=1
        fi
    fi

    if [[ $overall_result -eq 0 ]]; then
        log_info "[AUTO-FIX] All version manager fixes completed successfully"
    fi
    if ! autofix_finalize_managed_session "$session_owned"; then
        log_error "[AUTO-FIX] Failed to finalize autofix session for version manager fixes"
        return 2
    fi

    return "$overall_result"
}
