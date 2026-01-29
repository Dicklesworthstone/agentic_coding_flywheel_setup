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
_AUTOFIX_VERSION_MANAGERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$_AUTOFIX_VERSION_MANAGERS_DIR/autofix.sh"

# ============================================================
# NVM Detection and Fix
# ============================================================

# Check for existing nvm installation
# Returns JSON with status, nvm_dir, version, shell_configs
autofix_nvm_check() {
    local status="none"
    local nvm_dir=""
    local nvm_version=""
    local shell_configs=()

    # Check for NVM_DIR environment variable
    if [[ -n "${NVM_DIR:-}" ]]; then
        nvm_dir="$NVM_DIR"
        status="env_set"
    fi

    # Check common locations
    local nvm_locations=(
        "$HOME/.nvm"
        "${XDG_CONFIG_HOME:-$HOME/.config}/nvm"
    )

    for loc in "${nvm_locations[@]}"; do
        if [[ -d "$loc" ]]; then
            nvm_dir="$loc"
            status="installed"

            # Get installed version
            if [[ -f "$loc/nvm.sh" ]]; then
                nvm_version=$(grep "NVM_VERSION=" "$loc/nvm.sh" 2>/dev/null | head -1 | cut -d'"' -f2 || echo "unknown")
            fi
            break
        fi
    done

    # Check shell configs for nvm references
    local configs=(
        "$HOME/.bashrc"
        "$HOME/.zshrc"
        "$HOME/.profile"
        "$HOME/.bash_profile"
        "$HOME/.zprofile"
    )

    for config in "${configs[@]}"; do
        if [[ -f "$config" ]] && grep -q "NVM_DIR\|nvm.sh\|nvm use\|nvm alias" "$config" 2>/dev/null; then
            shell_configs+=("$config")
        fi
    done

    # Build JSON output
    local shell_configs_json="[]"
    if [[ ${#shell_configs[@]} -gt 0 ]]; then
        shell_configs_json=$(printf '%s\n' "${shell_configs[@]}" | jq -R . | jq -s .)
    fi

    jq -n \
        --arg status "$status" \
        --arg nvm_dir "$nvm_dir" \
        --arg nvm_version "$nvm_version" \
        --argjson shell_configs "$shell_configs_json" \
        '{
            status: $status,
            nvm_dir: $nvm_dir,
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

    log_info "[AUTO-FIX:nvm] Starting nvm fix (mode=$mode)"

    local check_result
    check_result=$(autofix_nvm_check)
    local status
    status=$(echo "$check_result" | jq -r '.status')

    if [[ "$status" == "none" ]]; then
        log_info "[AUTO-FIX:nvm] No nvm installation detected"
        return 0
    fi

    local nvm_dir nvm_version
    nvm_dir=$(echo "$check_result" | jq -r '.nvm_dir')
    nvm_version=$(echo "$check_result" | jq -r '.version')
    local config_count
    config_count=$(echo "$check_result" | jq -r '.shell_configs | length')

    log_info "[AUTO-FIX:nvm] Found nvm $nvm_version at $nvm_dir"
    log_info "[AUTO-FIX:nvm] Shell configs affected: $config_count files"

    if [[ "$mode" == "dry-run" ]]; then
        log_info "[DRY-RUN] Would backup $nvm_dir"
        echo "$check_result" | jq -r '.shell_configs[]' | while read -r config; do
            log_info "[DRY-RUN] Would backup and clean nvm references from $config"
        done
        return 0
    fi

    local partial_failure=0

    # STEP 1: Create verified backup of nvm directory
    if [[ -d "$nvm_dir" ]]; then
        local backup_info
        backup_info=$(create_backup "$nvm_dir" "nvm-directory")

        if [[ -z "$backup_info" ]]; then
            log_error "[AUTO-FIX:nvm] Failed to create backup of $nvm_dir"
            return 2
        fi

        local backup_path backup_checksum
        backup_path=$(echo "$backup_info" | jq -r '.backup')
        backup_checksum=$(echo "$backup_info" | jq -r '.checksum')

        log_info "[AUTO-FIX:nvm] Created backup: $backup_path (checksum: ${backup_checksum:0:16}...)"

        record_change \
            "nvm" \
            "Backed up and moved nvm directory: $nvm_dir" \
            "mv \"$backup_path\" \"$nvm_dir\"" \
            false \
            "warning" \
            "[\"$nvm_dir\"]" \
            "[$backup_info]" \
            '[]'

        # Move the directory to backup location (create_backup already copied it)
        if ! rm -rf "$nvm_dir"; then
            log_error "[AUTO-FIX:nvm] Failed to remove original nvm directory"
            partial_failure=1
        else
            log_info "[AUTO-FIX:nvm] Removed original nvm directory"
        fi
    fi

    # STEP 2: Clean shell configuration files
    while IFS= read -r config; do
        [[ -z "$config" ]] && continue
        log_info "[AUTO-FIX:nvm] Cleaning nvm references from $config"

        # Create backup of config file
        local config_backup
        config_backup=$(create_backup "$config" "shell-config")
        if [[ -n "$config_backup" ]]; then
            local config_backup_path
            config_backup_path=$(echo "$config_backup" | jq -r '.backup')
            log_info "[AUTO-FIX:nvm] Backed up config: $config_backup_path"

            record_change \
                "nvm" \
                "Cleaned nvm references from $config" \
                "cp \"$config_backup_path\" \"$config\"" \
                false \
                "info" \
                "[\"$config\"]" \
                "[$config_backup]" \
                '[]'

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
            sed -i \
                -e '/export NVM_DIR/d' \
                -e '/\[ -s.*nvm\.sh \]/d' \
                -e '/\. "$NVM_DIR\/nvm\.sh"/d' \
                -e '/source.*nvm\.sh/d' \
                -e '/nvm use/d' \
                -e '/nvm alias/d' \
                -e '/# NVM/d' \
                -e '/# Node Version Manager/d' \
                -e '/# nvm/d' \
                "$config" || {
                    log_warn "[AUTO-FIX:nvm] Failed to clean $config"
                    partial_failure=1
                }
        else
            log_warn "[AUTO-FIX:nvm] Failed to backup $config, skipping"
            partial_failure=1
        fi
    done < <(echo "$check_result" | jq -r '.shell_configs[]')

    # STEP 3: Unset NVM_DIR in current shell (for this session)
    unset NVM_DIR 2>/dev/null || true

    if [[ $partial_failure -eq 1 ]]; then
        log_warn "[AUTO-FIX:nvm] Fix completed with some failures"
        return 1
    fi

    log_info "[AUTO-FIX:nvm] Fix completed successfully"
    return 0
}

# ============================================================
# Pyenv Detection and Fix
# ============================================================

# Check for existing pyenv installation
# Returns JSON with status, pyenv_root, version, shell_configs
autofix_pyenv_check() {
    local status="none"
    local pyenv_root=""
    local pyenv_version=""
    local shell_configs=()

    # Check for PYENV_ROOT environment variable
    if [[ -n "${PYENV_ROOT:-}" ]]; then
        pyenv_root="$PYENV_ROOT"
        status="env_set"
    fi

    # Check common locations
    local pyenv_locations=(
        "$HOME/.pyenv"
        "${XDG_DATA_HOME:-$HOME/.local/share}/pyenv"
    )

    for loc in "${pyenv_locations[@]}"; do
        if [[ -d "$loc" ]]; then
            pyenv_root="$loc"
            status="installed"

            # Get installed version
            if [[ -x "$loc/bin/pyenv" ]]; then
                pyenv_version=$("$loc/bin/pyenv" --version 2>/dev/null | head -1 || echo "unknown")
            fi
            break
        fi
    done

    # Check shell configs for pyenv references
    local configs=(
        "$HOME/.bashrc"
        "$HOME/.zshrc"
        "$HOME/.profile"
        "$HOME/.bash_profile"
        "$HOME/.zprofile"
    )

    for config in "${configs[@]}"; do
        if [[ -f "$config" ]] && grep -q "PYENV\|pyenv init\|pyenv virtualenv" "$config" 2>/dev/null; then
            shell_configs+=("$config")
        fi
    done

    # Build JSON output
    local shell_configs_json="[]"
    if [[ ${#shell_configs[@]} -gt 0 ]]; then
        shell_configs_json=$(printf '%s\n' "${shell_configs[@]}" | jq -R . | jq -s .)
    fi

    jq -n \
        --arg status "$status" \
        --arg pyenv_root "$pyenv_root" \
        --arg pyenv_version "$pyenv_version" \
        --argjson shell_configs "$shell_configs_json" \
        '{
            status: $status,
            pyenv_root: $pyenv_root,
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

    log_info "[AUTO-FIX:pyenv] Starting pyenv fix (mode=$mode)"

    local check_result
    check_result=$(autofix_pyenv_check)
    local status
    status=$(echo "$check_result" | jq -r '.status')

    if [[ "$status" == "none" ]]; then
        log_info "[AUTO-FIX:pyenv] No pyenv installation detected"
        return 0
    fi

    local pyenv_root pyenv_version
    pyenv_root=$(echo "$check_result" | jq -r '.pyenv_root')
    pyenv_version=$(echo "$check_result" | jq -r '.version')
    local config_count
    config_count=$(echo "$check_result" | jq -r '.shell_configs | length')

    log_info "[AUTO-FIX:pyenv] Found pyenv $pyenv_version at $pyenv_root"
    log_info "[AUTO-FIX:pyenv] Shell configs affected: $config_count files"

    if [[ "$mode" == "dry-run" ]]; then
        log_info "[DRY-RUN] Would backup $pyenv_root"
        echo "$check_result" | jq -r '.shell_configs[]' | while read -r config; do
            log_info "[DRY-RUN] Would backup and clean pyenv references from $config"
        done
        return 0
    fi

    local partial_failure=0

    # STEP 1: Create verified backup of pyenv directory
    if [[ -d "$pyenv_root" ]]; then
        local backup_info
        backup_info=$(create_backup "$pyenv_root" "pyenv-directory")

        if [[ -z "$backup_info" ]]; then
            log_error "[AUTO-FIX:pyenv] Failed to create backup of $pyenv_root"
            return 2
        fi

        local backup_path backup_checksum
        backup_path=$(echo "$backup_info" | jq -r '.backup')
        backup_checksum=$(echo "$backup_info" | jq -r '.checksum')

        log_info "[AUTO-FIX:pyenv] Created backup: $backup_path (checksum: ${backup_checksum:0:16}...)"

        record_change \
            "pyenv" \
            "Backed up and moved pyenv directory: $pyenv_root" \
            "mv \"$backup_path\" \"$pyenv_root\"" \
            false \
            "warning" \
            "[\"$pyenv_root\"]" \
            "[$backup_info]" \
            '[]'

        if ! rm -rf "$pyenv_root"; then
            log_error "[AUTO-FIX:pyenv] Failed to remove original pyenv directory"
            partial_failure=1
        else
            log_info "[AUTO-FIX:pyenv] Removed original pyenv directory"
        fi
    fi

    # STEP 2: Clean shell configuration files
    while IFS= read -r config; do
        [[ -z "$config" ]] && continue
        log_info "[AUTO-FIX:pyenv] Cleaning pyenv references from $config"

        local config_backup
        config_backup=$(create_backup "$config" "shell-config")
        if [[ -n "$config_backup" ]]; then
            local config_backup_path
            config_backup_path=$(echo "$config_backup" | jq -r '.backup')
            log_info "[AUTO-FIX:pyenv] Backed up config: $config_backup_path"

            record_change \
                "pyenv" \
                "Cleaned pyenv references from $config" \
                "cp \"$config_backup_path\" \"$config\"" \
                false \
                "info" \
                "[\"$config\"]" \
                "[$config_backup]" \
                '[]'

            # Remove pyenv-related lines
            local removed_lines
            removed_lines=$(grep -E "PYENV|pyenv init|pyenv virtualenv" "$config" 2>/dev/null || true)
            if [[ -n "$removed_lines" ]]; then
                log_debug "[AUTO-FIX:pyenv] Removing lines from $config:"
                echo "$removed_lines" | while IFS= read -r line; do
                    log_debug "  - $line"
                done
            fi

            sed -i \
                -e '/export PYENV_ROOT/d' \
                -e '/pyenv init/d' \
                -e '/pyenv virtualenv-init/d' \
                -e '/# pyenv/d' \
                -e '/# Pyenv/d' \
                -e '/eval "$(pyenv/d' \
                -e '/PATH.*pyenv/d' \
                "$config" || {
                    log_warn "[AUTO-FIX:pyenv] Failed to clean $config"
                    partial_failure=1
                }
        else
            log_warn "[AUTO-FIX:pyenv] Failed to backup $config, skipping"
            partial_failure=1
        fi
    done < <(echo "$check_result" | jq -r '.shell_configs[]')

    # STEP 3: Unset PYENV_ROOT in current shell
    unset PYENV_ROOT 2>/dev/null || true

    if [[ $partial_failure -eq 1 ]]; then
        log_warn "[AUTO-FIX:pyenv] Fix completed with some failures"
        return 1
    fi

    log_info "[AUTO-FIX:pyenv] Fix completed successfully"
    return 0
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

    log_info "[AUTO-FIX] Starting version managers fix (mode=$mode)"

    # Fix nvm
    if ! autofix_nvm_fix "$mode"; then
        local nvm_result=$?
        if [[ $nvm_result -eq 2 ]]; then
            log_error "[AUTO-FIX] nvm fix failed critically"
            overall_result=2
        elif [[ $nvm_result -eq 1 ]]; then
            log_warn "[AUTO-FIX] nvm fix had partial failures"
            [[ $overall_result -lt 2 ]] && overall_result=1
        fi
    fi

    # Fix pyenv
    if ! autofix_pyenv_fix "$mode"; then
        local pyenv_result=$?
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

    return $overall_result
}
