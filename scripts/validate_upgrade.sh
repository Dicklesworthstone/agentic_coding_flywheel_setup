#!/usr/bin/env bash
# ============================================================
# ACFS Ubuntu Upgrade Validation Script
# Manual QA helper for verifying upgrade functionality
#
# Usage: ./scripts/validate_upgrade.sh
# Related beads: agentic_coding_flywheel_setup-dwh (ubu.7)
# ============================================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m'

# ============================================================
# Helpers
# ============================================================

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  ACFS Ubuntu Upgrade Validation${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${YELLOW}▸ $1${NC}"
    echo -e "${GRAY}───────────────────────────────────────────────────────────────${NC}"
}

print_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_fail() {
    echo -e "  ${RED}✗${NC} $1"
}

print_info() {
    echo -e "  ${GRAY}→${NC} $1"
}

# ============================================================
# Source libraries
# ============================================================

source_libs() {
    local libs_loaded=true

    if [[ -f "$PROJECT_ROOT/scripts/lib/ubuntu_upgrade.sh" ]]; then
        # shellcheck source=scripts/lib/ubuntu_upgrade.sh
        source "$PROJECT_ROOT/scripts/lib/ubuntu_upgrade.sh"
    else
        print_fail "ubuntu_upgrade.sh not found"
        libs_loaded=false
    fi

    if [[ -f "$PROJECT_ROOT/scripts/lib/state.sh" ]]; then
        # shellcheck source=scripts/lib/state.sh
        source "$PROJECT_ROOT/scripts/lib/state.sh"
    else
        print_fail "state.sh not found"
        libs_loaded=false
    fi

    if [[ "$libs_loaded" != "true" ]]; then
        echo ""
        print_fail "Required libraries not found. Run from repository root."
        exit 1
    fi
}

# ============================================================
# Validation Checks
# ============================================================

check_ubuntu_version() {
    print_section "1. Ubuntu Version Detection"

    if [[ ! -f /etc/os-release ]]; then
        print_warn "Not running on Linux - version detection will fail"
        print_info "This is expected on macOS/Windows development machines"
        return 0
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    if [[ "$ID" != "ubuntu" ]]; then
        print_warn "Not running on Ubuntu (detected: $ID)"
        return 0
    fi

    local version
    version=$(ubuntu_get_version_string)
    print_ok "Current version: Ubuntu $version"

    local version_num
    version_num=$(ubuntu_get_version_number)
    print_info "Numeric version code: $version_num"

    # Check if LTS
    if ubuntu_is_lts "$version"; then
        print_info "This is an LTS release"
    else
        print_info "This is a non-LTS release"
    fi
}

check_upgrade_path() {
    print_section "2. Upgrade Path Calculation"

    local target="${TARGET_UBUNTU_VERSION:-26.04}"
    print_info "Target version: $target"

    # Test path from 24.04
    echo ""
    echo -e "  ${GRAY}From 24.04 to $target:${NC}"
    local path_2404=""
    local current=2404
    local target_num="${target/./}"
    while [[ $current -lt $target_num ]]; do
        local next
        next=$(ubuntu_get_next_version_hardcoded "$current" "$target_num" || true)
        if [[ -z "$next" ]]; then
            break
        fi
        path_2404+="$next "
        local major="${next%%.*}"
        local minor="${next#*.}"
        current=$((major * 100 + minor))
    done
    print_ok "Path: 24.04 → ${path_2404:-[already at target]}"

    # Test path from 22.04 (LTS hop)
    echo ""
    echo -e "  ${GRAY}From 22.04 to $target (LTS hop):${NC}"
    local next_from_2204
    next_from_2204=$(ubuntu_get_next_version_hardcoded 2204 "$target_num" || true)
    if [[ -n "$next_from_2204" ]]; then
        print_ok "22.04 → $next_from_2204 (LTS hop)"
    else
        print_fail "No reviewed hop from 22.04 toward $target"
    fi

    # 25.10 is end-of-life: it is only a recovery source on the way to 26.04
    echo ""
    echo -e "  ${GRAY}From 25.10 (EOL recovery source) to $target:${NC}"
    local next_from_2510
    next_from_2510=$(ubuntu_get_next_version_hardcoded 2510 "$target_num" || true)
    if [[ -n "$next_from_2510" ]]; then
        print_ok "25.10 → $next_from_2510 (EOL recovery hop)"
    else
        print_info "No recovery hop from 25.10 toward $target (only 26.04 is a recovery destination)"
    fi
}

check_preflight_functions() {
    print_section "3. Preflight Check Functions"

    local checks=(
        "ubuntu_check_disk_space:Disk space check"
        "ubuntu_check_network:Network connectivity check"
        "ubuntu_check_apt_state:APT state check"
        "ubuntu_check_not_docker:Docker environment check"
        "ubuntu_check_not_wsl:WSL environment check"
        "ubuntu_check_root:Root user check"
    )

    for check in "${checks[@]}"; do
        local func="${check%%:*}"
        local desc="${check#*:}"

        if type -t "$func" &>/dev/null; then
            print_ok "$desc ($func)"
        else
            print_fail "$desc ($func) - function not found"
        fi
    done
}

check_state_functions() {
    print_section "4. State Management Functions"

    local functions=(
        "state_upgrade_init"
        "state_upgrade_start"
        "state_upgrade_complete"
        "state_upgrade_needs_reboot"
        "state_upgrade_resumed"
        "state_upgrade_is_complete"
        "state_upgrade_get_stage"
        "state_upgrade_set_error"
        "state_upgrade_mark_complete"
        "state_upgrade_get_next_version"
        "state_upgrade_get_progress"
        "state_upgrade_print_status"
    )

    local missing=0
    for func in "${functions[@]}"; do
        if type -t "$func" &>/dev/null; then
            print_ok "$func"
        else
            print_fail "$func - not found"
            ((missing += 1))
        fi
    done

    if [[ $missing -eq 0 ]]; then
        echo ""
        print_ok "All state functions available"
    fi
}

check_upgrade_state() {
    print_section "5. Current Upgrade State"

    local stage
    stage=$(state_upgrade_get_stage 2>/dev/null || echo "not_started")
    print_info "Current stage: $stage"

    if [[ "$stage" == "not_started" ]]; then
        print_ok "No upgrade in progress"
    else
        # Show more details
        if type -t state_upgrade_print_status &>/dev/null; then
            echo ""
            state_upgrade_print_status 2>/dev/null || true
        fi
    fi
}

check_systemd_service() {
    print_section "6. Systemd Resume Service"

    local service_template="$PROJECT_ROOT/scripts/templates/acfs-upgrade-resume.service"
    if [[ -f "$service_template" ]]; then
        print_ok "Service template exists: $service_template"
    else
        print_fail "Service template not found"
    fi

    local resume_script="$PROJECT_ROOT/scripts/lib/upgrade_resume.sh"
    if [[ -f "$resume_script" ]]; then
        print_ok "Resume script exists: $resume_script"
        local complete_block=""
        complete_block="$(sed -n '/^mark_state_complete()/,/^}/p' "$resume_script")"
        if [[ "$complete_block" == *'.ubuntu_upgrade.current_stage = "completed"'* ]] \
            && [[ "$complete_block" == *'.ubuntu_upgrade.completed_at = $now'* ]] \
            && [[ "$complete_block" == *'.ubuntu_upgrade.needs_reboot = false'* ]] \
            && [[ "$complete_block" == *'.ubuntu_upgrade.resume_after_reboot = false'* ]] \
            && [[ "$complete_block" == *'.ubuntu_upgrade.current_upgrade = null'* ]]; then
            print_ok "Resume script writes a complete terminal upgrade state"
        else
            print_fail "Resume script completion state is incomplete"
        fi
    else
        print_fail "Resume script not found"
    fi

    # Check if service is installed (only on Ubuntu)
    if command -v systemctl &>/dev/null; then
        if systemctl is-enabled acfs-upgrade-resume &>/dev/null; then
            print_warn "Resume service is enabled (upgrade may be in progress)"
        else
            print_info "Resume service is not enabled (normal state)"
        fi
    else
        print_info "systemctl not available (not running on systemd system)"
    fi
}

check_install_integration() {
    print_section "7. Install.sh Integration"

    local install_sh="$PROJECT_ROOT/install.sh"
    if [[ ! -f "$install_sh" ]]; then
        print_fail "install.sh not found"
        return
    fi

    # Check for upgrade-related CLI flags
    if grep -q "SKIP_UBUNTU_UPGRADE" "$install_sh"; then
        print_ok "SKIP_UBUNTU_UPGRADE variable present"
    else
        print_fail "SKIP_UBUNTU_UPGRADE variable not found"
    fi

    if grep -q "TARGET_UBUNTU_VERSION" "$install_sh"; then
        print_ok "TARGET_UBUNTU_VERSION variable present"
    else
        print_fail "TARGET_UBUNTU_VERSION variable not found"
    fi

    if grep -q "run_ubuntu_upgrade_phase" "$install_sh"; then
        print_ok "run_ubuntu_upgrade_phase function present"
    else
        print_fail "run_ubuntu_upgrade_phase function not found"
    fi

    if grep -q "_source_ubuntu_upgrade_lib" "$install_sh"; then
        print_ok "_source_ubuntu_upgrade_lib function present"
    else
        print_fail "_source_ubuntu_upgrade_lib function not found"
    fi
}

print_summary() {
    print_section "Summary"

    echo ""
    echo -e "  ${GREEN}Validation complete.${NC}"
    echo ""
    echo -e "  ${GRAY}For authoritative real-host testing:${NC}"
    echo -e "  ${GRAY}1. Fresh Ubuntu 24.04 LTS factory install gate (release is preserved):${NC}"
    echo -e "  ${GRAY}   tests/vm/test_factory_install_ubuntu.sh --ssh-target root@HOST --expect-ubuntu 24.04 --expect-final-ubuntu 24.04${NC}"
    echo -e "  ${GRAY}2. Separate slow opt-in upgrade gate (the factory harness does not forward --target-ubuntu):${NC}"
    echo -e "  ${GRAY}   On a disposable, reboot-capable Ubuntu 24.04 host, run as root:${NC}"
    echo -e "  ${GRAY}   curl -fsSL <install.sh URL> | bash -s -- --yes --mode vibe --target-ubuntu=26.04${NC}"
    echo -e "  ${GRAY}3. Observe upgrade from 24.04 → 26.04 and post-reboot resume${NC}"
    echo -e "  ${GRAY}4. Verify ACFS installation continues after upgrade and acfs doctor passes${NC}"
    echo ""
}

# ============================================================
# Main
# ============================================================

main() {
    print_header
    source_libs

    check_ubuntu_version
    check_upgrade_path
    check_preflight_functions
    check_state_functions
    check_upgrade_state
    check_systemd_service
    check_install_integration
    print_summary
}

main "$@"
