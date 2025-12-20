#!/usr/bin/env bash
# ============================================================
# ACFS Installer - Logging Library
# Provides consistent, colored output for the installer
# ============================================================

# Colors
export ACFS_RED='\033[0;31m'
export ACFS_GREEN='\033[0;32m'
export ACFS_YELLOW='\033[0;33m'
export ACFS_BLUE='\033[0;34m'
export ACFS_GRAY='\033[0;90m'
export ACFS_NC='\033[0m' # No Color

# Log a major step (blue)
# Usage: log_step "1/8" "Installing packages..."
log_step() {
    if [[ $# -ge 2 ]]; then
        local step="$1"
        local message="$2"
        echo -e "${ACFS_BLUE}[$step]${ACFS_NC} $message" >&2
        return 0
    fi

    local message="${1:-}"
    echo -e "${ACFS_BLUE}[•]${ACFS_NC} $message" >&2
}

# Log a section header (blue)
# Usage: log_section "Phase: Shell setup"
log_section() {
    local title="$1"
    echo "" >&2
    echo -e "${ACFS_BLUE}$title${ACFS_NC}" >&2
}

# Log detail information (gray, indented)
# Usage: log_detail "Installing zsh..."
log_detail() {
    echo -e "${ACFS_GRAY}    $1${ACFS_NC}" >&2
}

# Log informational message (alias for log_detail)
# Usage: log_info "Downloading..."
log_info() {
    log_detail "$1"
}

# Log success message (green with checkmark)
# Usage: log_success "Installation complete"
log_success() {
    echo -e "${ACFS_GREEN}$1${ACFS_NC}" >&2
}

# Log warning message (yellow with warning symbol)
# Usage: log_warn "This may take a while"
log_warn() {
    echo -e "${ACFS_YELLOW}$1${ACFS_NC}" >&2
}

# Log error message (red with X)
# Usage: log_error "Failed to install package"
log_error() {
    echo -e "${ACFS_RED}$1${ACFS_NC}" >&2
}

# Log fatal error and exit
# Usage: log_fatal "Cannot continue without root"
log_fatal() {
    log_error "$1"
    exit 1
}

# Log to file (for persistent logging)
# Usage: log_to_file "message" "/path/to/log"
log_to_file() {
    local message="$1"
    local logfile="${2:-/var/log/acfs/install.log}"

    # Ensure log directory exists
    mkdir -p "$(dirname "$logfile")" 2>/dev/null || true

    # Write timestamped message
    echo "[$(date -Iseconds)] $message" >> "$logfile" 2>/dev/null || true
}

# Start a timed operation (for performance tracking)
# Usage: timer_start "operation_name"
timer_start() {
    local name="$1"
    eval "ACFS_TIMER_${name}=$(date +%s)"
}

# End a timed operation and log duration
# Usage: timer_end "operation_name"
timer_end() {
    local name="$1"
    local start_var="ACFS_TIMER_${name}"
    local start="${!start_var:-$(date +%s)}"
    local end
    end=$(date +%s)
    local duration=$((end - start))

    log_detail "Completed in ${duration}s"
}
