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

# =============================================================================
# Constants
# =============================================================================

# Installation markers to check
readonly -a ACFS_INSTALLATION_MARKERS=(
    "$HOME/.acfs_installed"
    "$HOME/.acfs"
    "$HOME/.config/acfs"
    "/usr/local/bin/acfs"
    "$HOME/.local/bin/acfs"
)

# Artifacts to backup during clean reinstall
readonly -a ACFS_ARTIFACTS=(
    "$HOME/.acfs"
    "$HOME/.acfs_installed"
    "$HOME/.config/acfs"
    "$HOME/.local/bin/acfs"
)

# Shell config files to clean
readonly -a SHELL_CONFIGS=(
    "$HOME/.bashrc"
    "$HOME/.zshrc"
    "$HOME/.profile"
    "$HOME/.bash_profile"
)

# =============================================================================
# Detection Functions
# =============================================================================

# Detect existing ACFS installation
# Returns: space-separated list of found markers (empty if none)
detect_existing_acfs() {
    local -a found_markers=()

    for marker in "${ACFS_INSTALLATION_MARKERS[@]}"; do
        if [[ -e "$marker" ]]; then
            found_markers+=("$marker")
        fi
    done

    if [[ ${#found_markers[@]} -gt 0 ]]; then
        echo "${found_markers[*]}"
        return 0
    fi

    return 1
}

# Get installed ACFS version
get_installed_version() {
    # Method 1: Try acfs --version command
    if command -v acfs &>/dev/null; then
        local version_output
        version_output=$(acfs --version 2>/dev/null | head -1)
        if [[ -n "$version_output" ]]; then
            # Extract version number (e.g., "ACFS v0.4.0" -> "0.4.0")
            echo "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
            return
        fi
    fi

    # Method 2: Check version file
    if [[ -f "$HOME/.acfs/version" ]]; then
        cat "$HOME/.acfs/version"
        return
    fi

    # Method 3: Check installed marker file for version info
    if [[ -f "$HOME/.acfs_installed" ]]; then
        local version
        version=$(grep -oE 'version=[0-9]+\.[0-9]+\.[0-9]+' "$HOME/.acfs_installed" 2>/dev/null | cut -d= -f2)
        if [[ -n "$version" ]]; then
            echo "$version"
            return
        fi
    fi

    echo "unknown"
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

# Fix function for handle_autofix pattern
# In --yes mode, defaults to upgrade; in interactive/dry-run, shows what would happen
autofix_existing_fix() {
    local mode="${1:-fix}"
    
    if [[ "$mode" == "dry-run" ]]; then
        log_info "[DRY-RUN] Would handle existing ACFS installation"
        log_info "  - Check installed version"
        log_info "  - Offer upgrade or clean reinstall option"
        return 0
    fi
    
    # In fix mode: use upgrade strategy for non-interactive --yes mode
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

    log_info "[MIGRATE] Running migrations from $from to $to"

    # Migration: v0.x -> v1.x: Move config from ~/.acfs_config to ~/.acfs/config
    if [[ -f "$HOME/.acfs_config" ]] && [[ ! -f "$HOME/.acfs/config/settings.toml" ]]; then
        log_info "[MIGRATE] Moving legacy config to new location"
        mkdir -p "$HOME/.acfs/config"
        mv "$HOME/.acfs_config" "$HOME/.acfs/config/settings.toml"

        record_change \
            "acfs" \
            "Migrated legacy config file to new location" \
            "mv '$HOME/.acfs/config/settings.toml' '$HOME/.acfs_config'" \
            false \
            "info" \
            '["$HOME/.acfs_config", "$HOME/.acfs/config/settings.toml"]' \
            '[]' \
            '[]'
    fi

    # Migration: Convert JSON config to TOML (if present)
    if [[ -f "$HOME/.acfs/config.json" ]] && [[ ! -f "$HOME/.acfs/config.json.migrated" ]]; then
        log_info "[MIGRATE] Backing up legacy JSON config"
        mv "$HOME/.acfs/config.json" "$HOME/.acfs/config.json.migrated"

        record_change \
            "acfs" \
            "Backed up legacy JSON config" \
            "mv '$HOME/.acfs/config.json.migrated' '$HOME/.acfs/config.json'" \
            false \
            "info" \
            '["$HOME/.acfs/config.json"]' \
            '[]' \
            '[]'
    fi

    # Migration: Ensure .local/bin exists and is in PATH
    if [[ ! -d "$HOME/.local/bin" ]]; then
        log_info "[MIGRATE] Creating ~/.local/bin directory"
        mkdir -p "$HOME/.local/bin"
    fi

    log_info "[MIGRATE] Migrations complete"
    return 0
}

# Update PATH entries in shell configs
update_path_entries() {
    for config in "${SHELL_CONFIGS[@]}"; do
        if [[ -f "$config" ]]; then
            # Check if ACFS path entry exists
            if ! grep -q "# ACFS PATH" "$config"; then
                log_info "[UPGRADE] Adding PATH entry to $config"

                # Create backup
                local backup
                backup=$(create_backup "$config" "upgrade-path-entry")

                # Append PATH entry
                {
                    echo ''
                    echo '# ACFS PATH'
                    echo 'export PATH="$HOME/.local/bin:$PATH"'
                } >> "$config"

                record_change \
                    "acfs" \
                    "Added PATH entry to $config" \
                    "# Remove PATH entry from $config manually if needed" \
                    false \
                    "info" \
                    "[\"$config\"]" \
                    "$(echo "$backup" | jq -c '[.]' 2>/dev/null || echo '[]')" \
                    '[]'
            fi
        fi
    done
}

# =============================================================================
# Upgrade Implementation
# =============================================================================

# Upgrade existing installation (preserve config)
upgrade_existing_installation() {
    local current_version="$1"
    local new_version="$2"

    log_info "[UPGRADE] Starting upgrade from $current_version to $new_version"

    # Step 1: Backup current config (for safety)
    if [[ -d "$HOME/.acfs" ]]; then
        local config_backup
        config_backup=$(create_backup "$HOME/.acfs/config" "upgrade-config-backup")
        if [[ -n "$config_backup" ]]; then
            log_info "[UPGRADE] Config backed up: $(echo "$config_backup" | jq -r '.backup' 2>/dev/null || echo "$config_backup")"
        fi
    fi

    # Step 2: Check for migration requirements
    if version_requires_migration "$current_version" "$new_version"; then
        log_info "[UPGRADE] Migration required from $current_version to $new_version"
        if ! run_migrations "$current_version" "$new_version"; then
            log_error "[UPGRADE] Migration failed"
            return 1
        fi
    fi

    # Step 3: Record upgrade change
    record_change \
        "acfs" \
        "Upgraded ACFS from $current_version to $new_version" \
        "# Downgrade not supported - restore from backup if needed" \
        false \
        "info" \
        '[]' \
        '[]' \
        '[]'

    # Step 4: Update version file
    mkdir -p "$HOME/.acfs"
    echo "$new_version" > "$HOME/.acfs/version"

    # Step 5: Update PATH entries if needed
    update_path_entries

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
    backup_dir="$HOME/.acfs-backup-$(date +%Y%m%d_%H%M%S)"

    log_info "[CLEAN] Creating backup at $backup_dir"
    mkdir -p "$backup_dir"

    local backup_manifest="$backup_dir/manifest.json"
    local backed_up_items=()

    for artifact in "${ACFS_ARTIFACTS[@]}"; do
        if [[ -e "$artifact" ]]; then
            log_info "[CLEAN] Backing up: $artifact"
            local dest
            dest="$backup_dir/$(basename "$artifact")"

            if [[ -d "$artifact" ]]; then
                cp -rp "$artifact" "$dest" 2>/dev/null || true
            else
                cp -p "$artifact" "$dest" 2>/dev/null || true
            fi

            # Calculate checksum if it's a file
            local checksum=""
            if [[ -f "$artifact" ]]; then
                checksum=$(sha256sum "$artifact" 2>/dev/null | cut -d' ' -f1)
            fi

            backed_up_items+=("{\"original\": \"$artifact\", \"backup\": \"$dest\", \"checksum\": \"$checksum\"}")
        fi
    done

    # Write manifest
    local items_json
    items_json=$(printf '%s\n' "${backed_up_items[@]}" | jq -s '.')

    jq -n \
        --arg created "$(date -Iseconds)" \
        --argjson items "$items_json" \
        '{created: $created, backed_up_items: $items}' > "$backup_manifest"

    echo "$backup_dir"
}

# Remove all ACFS artifacts
remove_acfs_artifacts() {
    for artifact in "${ACFS_ARTIFACTS[@]}"; do
        if [[ -e "$artifact" ]]; then
            log_info "[CLEAN] Removing: $artifact"
            rm -rf "$artifact"
        fi
    done
}

# Clean ACFS entries from shell configs
clean_shell_configs() {
    for config in "${SHELL_CONFIGS[@]}"; do
        if [[ -f "$config" ]]; then
            # Check if config has ACFS-related content
            if grep -qE '# ACFS|\.acfs|acfs_' "$config" 2>/dev/null; then
                # Backup config first
                local config_backup
                config_backup=$(create_backup "$config" "clean-shell-config")

                if [[ -n "$config_backup" ]]; then
                    log_info "[CLEAN] Cleaning ACFS entries from $config"

                    # Create temp file in same directory to preserve permissions on mv
                    local temp_file
                    temp_file=$(mktemp -p "$(dirname "$config")" ".acfs-clean.XXXXXX")

                    # Preserve original permissions by copying mode
                    local orig_mode
                    orig_mode=$(stat -c '%a' "$config" 2>/dev/null || stat -f '%Lp' "$config" 2>/dev/null)

                    grep -vE '# ACFS|\.acfs|acfs_' "$config" > "$temp_file" || true

                    # Restore original permissions before move
                    [[ -n "$orig_mode" ]] && chmod "$orig_mode" "$temp_file"

                    mv "$temp_file" "$config"
                fi
            fi
        fi
    done
}

# Perform clean reinstall
clean_reinstall() {
    log_warn "[CLEAN] Starting clean reinstall - this will remove existing installation"

    # Step 1: Create comprehensive backup
    local backup_dir
    backup_dir=$(create_installation_backup)

    # Step 2: Record the clean reinstall change
    local artifacts_json
    artifacts_json=$(printf '%s\n' "${ACFS_ARTIFACTS[@]}" | jq -R . | jq -s .)

    record_change \
        "acfs" \
        "Clean reinstall - removed existing ACFS installation" \
        "# Restore from backup: $backup_dir" \
        false \
        "warning" \
        "$artifacts_json" \
        "[{\"backup_dir\": \"$backup_dir\"}]" \
        '[]'

    # Step 3: Remove existing installation
    remove_acfs_artifacts

    # Step 4: Clean shell configs
    clean_shell_configs

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

    # Non-interactive modes
    case "$mode" in
        upgrade)
            upgrade_existing_installation "$current_version" "$new_version"
            return $?
            ;;
        clean)
            clean_reinstall
            return $?
            ;;
        abort)
            log_info "Aborting installation per request."
            return 1
            ;;
    esac

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
    read -rp "Enter choice [1-3]: " choice

    case "$choice" in
        1)
            upgrade_existing_installation "$current_version" "$new_version"
            return $?
            ;;
        2)
            clean_reinstall
            return $?
            ;;
        3|*)
            log_info "Aborting installation."
            return 1
            ;;
    esac
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
        upgrade_existing_installation "$current_version" "$new_version"
        return $?
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

    # Check config directory
    if [[ ! -d "$HOME/.acfs" ]]; then
        log_warn "[VERIFY] Config directory missing"
        ((errors++))
    fi

    # Check version file
    if [[ ! -f "$HOME/.acfs/version" ]]; then
        log_warn "[VERIFY] Version file missing"
        ((errors++))
    fi

    # Check .local/bin exists
    if [[ ! -d "$HOME/.local/bin" ]]; then
        log_warn "[VERIFY] ~/.local/bin directory missing"
        ((errors++))
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
