# ACFS Installer Reliability & UX Roadmap

> **Purpose**: This document provides comprehensive technical specifications for 6 approved improvements to ACFS that enhance installation reliability, error handling, and user experience without sacrificing power or simplicity.

> **Guiding Principle**: Every improvement must maintain the one-liner install experience (`curl | bash`) while making failures recoverable, errors understandable, and the system trustworthy.

---

## Table of Contents

1. [Phase-Granular Progress Persistence](#1-phase-granular-progress-persistence)
2. [Pre-Flight Validation](#2-pre-flight-validation)
3. [Per-Phase Error Reporting](#3-per-phase-error-reporting)
4. [Checkpoint-Based Checksum Recovery](#4-checkpoint-based-checksum-recovery)
5. [Enhanced Doctor with Functional Tests](#5-enhanced-doctor-with-functional-tests)
6. [Automated Upstream Checksum Monitoring](#6-automated-upstream-checksum-monitoring)
7. [Agent Session Sharing & Replay](#7-agent-session-sharing--replay)

---

## 1. Phase-Granular Progress Persistence

### Problem Statement

The current installer (`install.sh`) writes `~/.acfs/state.json` only **after successful completion** (around line 1197-1210). This creates a catastrophic UX failure: if SSH disconnects at phase 8/10, the user loses 15-20 minutes of work and must restart from scratch.

**Current behavior:**
```bash
# state.json only written here, AFTER all phases complete
install_completed() {
    cat > "$ACFS_HOME/state.json" <<EOF
{
    "installed_at": "$(date -Iseconds)",
    "version": "$ACFS_VERSION",
    "mode": "$MODE",
    "completed_phases": [1,2,3,4,5,6,7,8,9,10]
}
EOF
}
```

**Real-world impact:**
- VPS providers have occasional network hiccups
- Users close laptops, lose WiFi, or experience ISP issues
- Long-running installs (15-25 minutes) have high probability of interruption
- Each restart compounds frustration and reduces completion rate

### Technical Design

#### State File Schema (v2)

```json
{
    "schema_version": 2,
    "version": "0.1.0",
    "mode": "vibe",
    "started_at": "2025-01-15T10:30:00Z",
    "last_updated": "2025-01-15T10:42:00Z",
    "completed_phases": [1, 2, 3, 4, 5],
    "current_phase": 6,
    "current_step": "Installing Rust via rustup",
    "failed_phase": null,
    "failed_step": null,
    "failed_error": null,
    "skipped_tools": [],
    "phase_durations": {
        "1": 12,
        "2": 45,
        "3": 67,
        "4": 123,
        "5": 89
    }
}
```

#### Implementation Functions

```bash
# Initialize or load state at script start
init_state() {
    local state_file="$ACFS_HOME/state.json"

    if [[ -f "$state_file" ]]; then
        # Load existing state
        COMPLETED_PHASES=($(jq -r '.completed_phases[]' "$state_file" 2>/dev/null || echo ""))
        CURRENT_PHASE=$(jq -r '.current_phase // 0' "$state_file" 2>/dev/null || echo 0)
        log_detail "Resuming from phase $((CURRENT_PHASE))"
    else
        # Fresh install
        COMPLETED_PHASES=()
        CURRENT_PHASE=0
        mkdir -p "$ACFS_HOME"
        save_state
    fi
}

# Save state after each phase completes
save_state() {
    local state_file="$ACFS_HOME/state.json"
    local completed_json
    completed_json=$(printf '%s\n' "${COMPLETED_PHASES[@]}" | jq -R . | jq -s .)

    cat > "$state_file" <<EOF
{
    "schema_version": 2,
    "version": "$ACFS_VERSION",
    "mode": "$MODE",
    "started_at": "${STARTED_AT:-$(date -Iseconds)}",
    "last_updated": "$(date -Iseconds)",
    "completed_phases": $completed_json,
    "current_phase": $CURRENT_PHASE,
    "current_step": "${CURRENT_STEP:-}",
    "failed_phase": ${FAILED_PHASE:-null},
    "failed_step": ${FAILED_STEP:-null},
    "failed_error": ${FAILED_ERROR:-null},
    "skipped_tools": $(printf '%s\n' "${SKIPPED_TOOLS[@]:-}" | jq -R . | jq -s .)
}
EOF
}

# Check if phase is already completed (for resume)
is_phase_completed() {
    local phase=$1
    for completed in "${COMPLETED_PHASES[@]}"; do
        [[ "$completed" == "$phase" ]] && return 0
    done
    return 1
}

# Mark phase as complete and persist
complete_phase() {
    local phase=$1
    COMPLETED_PHASES+=("$phase")
    CURRENT_PHASE=$((phase + 1))
    CURRENT_STEP=""
    save_state
    log_success "Phase $phase complete"
}

# Wrapper for running a phase with state tracking
run_phase() {
    local phase_num=$1
    local phase_name=$2
    local phase_fn=$3

    if is_phase_completed "$phase_num"; then
        log_detail "Phase $phase_num already completed, skipping"
        return 0
    fi

    CURRENT_PHASE=$phase_num
    CURRENT_STEP="Starting $phase_name"
    save_state

    log_step "$phase_num/10" "$phase_name"

    if $phase_fn; then
        complete_phase "$phase_num"
    else
        FAILED_PHASE=$phase_num
        FAILED_STEP="$CURRENT_STEP"
        save_state
        return 1
    fi
}
```

#### Resume Logic

```bash
# At installer start
main() {
    init_state

    # Check for resume scenario
    if [[ ${#COMPLETED_PHASES[@]} -gt 0 ]]; then
        local last_phase="${COMPLETED_PHASES[-1]}"
        log_step "Resume" "Detected previous install (completed phases: 1-$last_phase)"

        if [[ "$YES_MODE" != "true" ]]; then
            if ! confirm_resume; then
                log_detail "Starting fresh install"
                COMPLETED_PHASES=()
                CURRENT_PHASE=0
                save_state
            fi
        fi
    fi

    # Run all phases (skipping completed ones)
    run_phase 1 "User Normalization" install_phase_1
    run_phase 2 "APT Packages" install_phase_2
    run_phase 3 "Shell Setup" install_phase_3
    # ... etc
}

confirm_resume() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum confirm "Resume from phase $((${COMPLETED_PHASES[-1]} + 1))?"
    else
        read -p "Resume from phase $((${COMPLETED_PHASES[-1]} + 1))? [Y/n] " -r
        [[ -z "$REPLY" || "$REPLY" =~ ^[Yy] ]]
    fi
}
```

#### CLI Flags

```bash
# New flags
--resume          # Explicitly resume from last checkpoint (default behavior if state exists)
--force-reinstall # Ignore state file, start fresh
--reset-state     # Delete state file and exit (for debugging)
```

### Edge Cases

1. **Corrupted state file**: Fall back to fresh install with warning
2. **Version mismatch**: Warn if state was from different ACFS version
3. **Phase ordering changes**: Track by phase name, not just number
4. **Partial phase completion**: State tracks current step within phase for better diagnostics

### Files Modified

- `install.sh`: Add state management functions, wrap phases with `run_phase`
- `scripts/lib/state.sh` (new): Extracted state management for reuse

---

## 2. Pre-Flight Validation

### Problem Statement

Users discover VPS configuration problems **15 minutes into installation**, after wasting significant time. Common issues are entirely predictable:
- Wrong Ubuntu version
- Insufficient disk space
- Low RAM
- Missing swap
- DNS resolution failures
- Firewall blocking outbound connections

### Technical Design

#### Pre-Flight Script (`scripts/preflight.sh`)

```bash
#!/usr/bin/env bash
# ACFS Pre-Flight Check
# Run this BEFORE the main installer to validate your VPS is ready.
#
# Usage:
#   curl -fsSL "https://.../preflight.sh" | bash
#   curl -fsSL "https://.../preflight.sh" | bash -s -- --json

set -euo pipefail

# Output format
JSON_MODE=false
[[ "${1:-}" == "--json" ]] && JSON_MODE=true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Results
PASS=()
WARN=()
FAIL=()

check() {
    local name="$1"
    local status="$2"  # pass, warn, fail
    local message="$3"
    local detail="${4:-}"

    case "$status" in
        pass) PASS+=("$name|$message|$detail") ;;
        warn) WARN+=("$name|$message|$detail") ;;
        fail) FAIL+=("$name|$message|$detail") ;;
    esac
}

# ============================================================
# Checks
# ============================================================

check_os() {
    local os_id os_version
    os_id=$(grep -oP '^ID=\K.*' /etc/os-release 2>/dev/null | tr -d '"')
    os_version=$(grep -oP '^VERSION_ID=\K.*' /etc/os-release 2>/dev/null | tr -d '"')

    if [[ "$os_id" != "ubuntu" ]]; then
        check "os" "fail" "Unsupported OS: $os_id" "ACFS requires Ubuntu 24.04+"
        return
    fi

    local major_version="${os_version%%.*}"
    if [[ "$major_version" -lt 24 ]]; then
        check "os" "fail" "Ubuntu $os_version too old" "ACFS requires Ubuntu 24.04+"
    else
        check "os" "pass" "Ubuntu $os_version detected"
    fi
}

check_architecture() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64)
            check "arch" "pass" "Architecture: x86_64"
            ;;
        aarch64|arm64)
            check "arch" "pass" "Architecture: arm64"
            ;;
        *)
            check "arch" "fail" "Unsupported architecture: $arch" "ACFS supports x86_64 and arm64"
            ;;
    esac
}

check_disk_space() {
    local available_kb available_gb
    available_kb=$(df -k / | tail -1 | awk '{print $4}')
    available_gb=$((available_kb / 1024 / 1024))

    if [[ $available_gb -lt 5 ]]; then
        check "disk" "fail" "Only ${available_gb}GB available" "ACFS needs at least 10GB free"
    elif [[ $available_gb -lt 10 ]]; then
        check "disk" "warn" "${available_gb}GB available" "Recommend 20GB+ for comfortable operation"
    else
        check "disk" "pass" "${available_gb}GB available"
    fi
}

check_memory() {
    local total_kb total_gb
    total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    total_gb=$((total_kb / 1024 / 1024))

    if [[ $total_gb -lt 2 ]]; then
        check "memory" "fail" "Only ${total_gb}GB RAM" "ACFS needs at least 4GB RAM"
    elif [[ $total_gb -lt 4 ]]; then
        check "memory" "warn" "${total_gb}GB RAM" "Recommend 8GB+ for agent workloads"
    else
        check "memory" "pass" "${total_gb}GB RAM"
    fi
}

check_swap() {
    local swap_kb swap_gb
    swap_kb=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
    swap_gb=$((swap_kb / 1024 / 1024))

    if [[ $swap_gb -eq 0 ]]; then
        check "swap" "warn" "No swap configured" "Recommend 2GB+ swap for agent workloads"
    else
        check "swap" "pass" "${swap_gb}GB swap configured"
    fi
}

check_internet() {
    if curl -fsSL --connect-timeout 5 https://google.com >/dev/null 2>&1; then
        check "internet" "pass" "Internet connectivity OK"
    else
        check "internet" "fail" "Cannot reach internet" "Check firewall and DNS settings"
    fi
}

check_dns() {
    if host github.com >/dev/null 2>&1; then
        check "dns" "pass" "DNS resolution OK"
    elif command -v dig &>/dev/null && dig github.com +short >/dev/null 2>&1; then
        check "dns" "pass" "DNS resolution OK"
    else
        check "dns" "fail" "DNS resolution failed" "Cannot resolve github.com"
    fi
}

check_user() {
    if [[ $EUID -eq 0 ]]; then
        check "user" "pass" "Running as root"
    elif sudo -n true 2>/dev/null; then
        check "user" "pass" "Running with passwordless sudo"
    else
        check "user" "warn" "Not root, may need sudo password" "Run as root or with passwordless sudo"
    fi
}

check_required_commands() {
    local missing=()
    for cmd in curl tar gzip; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        check "commands" "fail" "Missing: ${missing[*]}" "Install with: apt-get install ${missing[*]}"
    else
        check "commands" "pass" "Required commands present"
    fi
}

# ============================================================
# Run All Checks
# ============================================================

run_checks() {
    check_os
    check_architecture
    check_user
    check_disk_space
    check_memory
    check_swap
    check_internet
    check_dns
    check_required_commands
}

# ============================================================
# Output
# ============================================================

print_human() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              ACFS Pre-Flight Check                            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    for item in "${PASS[@]}"; do
        IFS='|' read -r name message detail <<< "$item"
        echo -e "  ${GREEN}✔${NC} $message"
    done

    for item in "${WARN[@]}"; do
        IFS='|' read -r name message detail <<< "$item"
        echo -e "  ${YELLOW}⚠${NC} $message"
        [[ -n "$detail" ]] && echo -e "    ${YELLOW}→ $detail${NC}"
    done

    for item in "${FAIL[@]}"; do
        IFS='|' read -r name message detail <<< "$item"
        echo -e "  ${RED}✖${NC} $message"
        [[ -n "$detail" ]] && echo -e "    ${RED}→ $detail${NC}"
    done

    echo ""

    if [[ ${#FAIL[@]} -gt 0 ]]; then
        echo -e "${RED}Pre-flight failed. Fix the issues above before running ACFS.${NC}"
        exit 1
    elif [[ ${#WARN[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Pre-flight passed with warnings. You may proceed, but consider addressing warnings.${NC}"
        echo ""
        echo -e "Ready to install! Run:"
        echo -e "  curl -fsSL \"https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh?\$(date +%s)\" | bash -s -- --yes --mode vibe"
    else
        echo -e "${GREEN}Pre-flight passed! Your VPS is ready for ACFS.${NC}"
        echo ""
        echo -e "Run:"
        echo -e "  curl -fsSL \"https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh?\$(date +%s)\" | bash -s -- --yes --mode vibe"
    fi
}

print_json() {
    echo "{"
    echo "  \"status\": \"$([ ${#FAIL[@]} -eq 0 ] && echo 'ready' || echo 'failed')\","
    echo "  \"pass\": ${#PASS[@]},"
    echo "  \"warn\": ${#WARN[@]},"
    echo "  \"fail\": ${#FAIL[@]},"
    echo "  \"checks\": ["

    local first=true
    for item in "${PASS[@]}"; do
        IFS='|' read -r name message detail <<< "$item"
        [[ "$first" != "true" ]] && echo ","
        first=false
        echo -n "    {\"name\": \"$name\", \"status\": \"pass\", \"message\": \"$message\"}"
    done
    for item in "${WARN[@]}"; do
        IFS='|' read -r name message detail <<< "$item"
        [[ "$first" != "true" ]] && echo ","
        first=false
        echo -n "    {\"name\": \"$name\", \"status\": \"warn\", \"message\": \"$message\", \"detail\": \"$detail\"}"
    done
    for item in "${FAIL[@]}"; do
        IFS='|' read -r name message detail <<< "$item"
        [[ "$first" != "true" ]] && echo ","
        first=false
        echo -n "    {\"name\": \"$name\", \"status\": \"fail\", \"message\": \"$message\", \"detail\": \"$detail\"}"
    done

    echo ""
    echo "  ]"
    echo "}"
}

# Main
run_checks

if [[ "$JSON_MODE" == "true" ]]; then
    print_json
else
    print_human
fi
```

### Wizard Integration

Add a new step to the wizard between "SSH Connect" (step 6) and "Run Installer" (step 7):

**Step 6.5: Pre-Flight Check**
- User runs `curl -fsSL .../preflight.sh | bash`
- Wizard shows expected output format
- Checkbox: "Pre-flight passed" (required before proceeding)
- Troubleshooting section for common failures

### Files Created/Modified

- `scripts/preflight.sh` (new): Pre-flight validation script
- `apps/web/app/wizard/preflight-check/page.tsx` (new): Wizard step
- `apps/web/lib/wizardSteps.ts`: Add pre-flight step to step list

---

## 3. Per-Phase Error Reporting

### Problem Statement

When installation fails, users see only:
```
✖ ACFS installation failed

Fix:
1. Check the log: cat /var/log/acfs/install.log
2. Run: acfs doctor
3. Re-run this installer
```

This tells them nothing about:
- **Which phase** failed (1-10)
- **What step** within the phase failed
- **What the actual error** was
- **How to fix** the specific issue

### Technical Design

#### Error Context Tracking

```bash
# Global error context
CURRENT_PHASE=""
CURRENT_PHASE_NAME=""
CURRENT_STEP=""
LAST_ERROR=""
LAST_ERROR_CODE=""

# Wrapper for individual steps within a phase
try_step() {
    local description="$1"
    shift
    local cmd="$*"

    CURRENT_STEP="$description"
    save_state  # Persist current step for resume

    log_detail "$description..."

    local output
    local exit_code

    # Capture both output and exit code
    output=$(eval "$cmd" 2>&1) && exit_code=0 || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        LAST_ERROR="$output"
        LAST_ERROR_CODE=$exit_code
        return 1
    fi

    return 0
}
```

#### Known Error Patterns and Fixes

```bash
# Error pattern matching for actionable fixes
declare -A ERROR_PATTERNS=(
    ["curl: (7) Failed to connect"]="Network connectivity issue. Check: curl -I https://google.com"
    ["curl: (6) Could not resolve"]="DNS resolution failed. Check: cat /etc/resolv.conf"
    ["E: Unable to locate package"]="Package not found. Try: sudo apt-get update"
    ["Permission denied"]="Permission issue. Ensure running as root or with sudo."
    ["No space left on device"]="Disk full. Free up space: df -h"
    ["gpg: keyserver receive failed"]="GPG keyserver unreachable. Retry or check firewall."
    ["Connection timed out"]="Network timeout. Check firewall rules for outbound HTTPS."
    ["checksum mismatch"]="Upstream script changed. See: https://github.com/.../issues"
    ["rate limit"]="API rate limited. Wait 60 seconds and retry."
)

get_suggested_fix() {
    local error="$1"

    for pattern in "${!ERROR_PATTERNS[@]}"; do
        if [[ "$error" == *"$pattern"* ]]; then
            echo "${ERROR_PATTERNS[$pattern]}"
            return 0
        fi
    done

    echo "Unknown error. Check logs: cat $ACFS_LOG_DIR/install.log"
}
```

#### Enhanced Failure Report

```bash
report_failure() {
    local phase="${CURRENT_PHASE:-unknown}"
    local phase_name="${CURRENT_PHASE_NAME:-unknown}"
    local step="${CURRENT_STEP:-unknown}"
    local error="${LAST_ERROR:-No error captured}"
    local suggested_fix
    suggested_fix=$(get_suggested_fix "$error")

    # Truncate error for display (full error in log)
    local display_error
    if [[ ${#error} -gt 200 ]]; then
        display_error="${error:0:200}..."
    else
        display_error="$error"
    fi

    if [[ "$HAS_GUM" == "true" ]]; then
        gum style \
            --border double \
            --border-foreground "$ACFS_ERROR" \
            --padding "1 2" \
            --margin "1 0" \
            "$(cat <<EOF
✖ INSTALLATION FAILED

Phase $phase/10: $phase_name
Failed at: $step

Error:
$display_error

Suggested Fix:
$suggested_fix

Full log: $ACFS_LOG_DIR/install.log
Resume: curl ... | bash -s -- --resume
EOF
)"
    else
        echo ""
        echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ✖ INSTALLATION FAILED                                        ║${NC}"
        echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}║                                                                ║${NC}"
        echo -e "${RED}║  Phase $phase/10: $phase_name${NC}"
        echo -e "${RED}║  Failed at: $step${NC}"
        echo -e "${RED}║                                                                ║${NC}"
        echo -e "${RED}║  Error: ${display_error:0:50}...${NC}"
        echo -e "${RED}║                                                                ║${NC}"
        echo -e "${YELLOW}║  Suggested Fix:${NC}"
        echo -e "${YELLOW}║    $suggested_fix${NC}"
        echo -e "${RED}║                                                                ║${NC}"
        echo -e "${RED}║  Full log: $ACFS_LOG_DIR/install.log${NC}"
        echo -e "${RED}║  Resume: curl ... | bash -s -- --resume${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    fi

    # Also log structured JSON for programmatic consumption
    cat >> "$ACFS_LOG_DIR/install.log" <<EOF

=== FAILURE REPORT ===
{
    "timestamp": "$(date -Iseconds)",
    "phase": $phase,
    "phase_name": "$phase_name",
    "step": "$step",
    "error": $(echo "$error" | jq -Rs .),
    "suggested_fix": "$suggested_fix"
}
EOF
}
```

#### Usage in Phase Functions

```bash
install_phase_languages() {
    CURRENT_PHASE_NAME="Language Runtimes"

    # Bun
    if ! command -v bun &>/dev/null; then
        try_step "Installing Bun runtime" \
            "acfs_curl https://bun.sh/install | bash" || return 1
    fi

    # Rust
    if ! command -v cargo &>/dev/null; then
        try_step "Installing Rust via rustup" \
            "acfs_curl https://sh.rustup.rs | sh -s -- -y" || return 1
    fi

    # UV
    if ! command -v uv &>/dev/null; then
        try_step "Installing uv (Python tooling)" \
            "acfs_curl https://astral.sh/uv/install.sh | sh" || return 1
    fi

    # Go
    if ! command -v go &>/dev/null; then
        try_step "Installing Go" \
            "install_go_tarball" || return 1
    fi

    return 0
}
```

### Files Modified

- `install.sh`: Add error tracking, `try_step` wrapper, `report_failure` function
- `scripts/lib/errors.sh` (new): Error pattern database and fix suggestions

---

## 4. Checkpoint-Based Checksum Recovery

### Problem Statement

If **any** of the 14 upstream tools fails checksum verification, the entire install fails. One stale checksum on tool #8 wastes all progress from tools 1-7.

**Current behavior:**
```bash
verify_and_run() {
    # ... verify checksum ...
    if [[ "$actual" != "$expected" ]]; then
        log_error "Checksum mismatch for $name"
        log_error "  Expected: $expected"
        log_error "  Got: $actual"
        return 1  # Entire install fails
    fi
}
```

### Technical Design

#### Tool Criticality Classification

```bash
# Critical tools: failure MUST abort (security/functionality critical)
CRITICAL_TOOLS=(
    "bun"       # JS runtime - everything depends on it
    "rust"      # Cargo needed for stack tools
    "uv"        # Python tooling
    "claude"    # Primary agent
)

# Recommended tools: failure should warn but allow skip
RECOMMENDED_TOOLS=(
    "ntm"              # Nice to have, not blocking
    "mcp_agent_mail"   # Coordination, not essential for solo work
    "ubs"              # Bug scanner
    "bv"               # Beads viewer
    "cass"             # Session search
    "cm"               # Memory system
    "caam"             # Account manager
    "slb"              # Safety tool
)

is_critical_tool() {
    local tool="$1"
    for critical in "${CRITICAL_TOOLS[@]}"; do
        [[ "$tool" == "$critical" ]] && return 0
    done
    return 1
}
```

#### Interactive Skip Logic

```bash
handle_checksum_mismatch() {
    local tool="$1"
    local expected="$2"
    local actual="$3"
    local url="$4"

    if is_critical_tool "$tool"; then
        log_error "Critical tool '$tool' has checksum mismatch"
        log_error "This MUST be resolved before continuing."
        log_error ""
        log_error "Options:"
        log_error "  1. File an issue: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues"
        log_error "  2. Manually verify the upstream script is safe"
        log_error "  3. Wait for maintainers to update checksums"
        return 1  # Abort for critical tools
    fi

    # Non-critical tool - offer choices
    echo ""
    log_warn "Checksum mismatch for: $tool"
    log_detail "Expected: ${expected:0:16}..."
    log_detail "Got:      ${actual:0:16}..."
    echo ""

    if [[ "$YES_MODE" == "true" ]]; then
        # In automated mode, skip non-critical tools with mismatch
        log_warn "Skipping $tool (automated mode, checksum mismatch)"
        SKIPPED_TOOLS+=("$tool")
        return 0  # Continue installation
    fi

    local choice
    if [[ "$HAS_GUM" == "true" ]]; then
        choice=$(gum choose \
            "1. Skip this tool (continue install)" \
            "2. Abort installation" \
            "3. Install anyway (SECURITY RISK)")
        choice="${choice:0:1}"
    else
        echo "Options:"
        echo "  1. Skip this tool (other tools will still install)"
        echo "  2. Abort installation"
        echo "  3. Install anyway (NOT RECOMMENDED - security risk)"
        read -p "[1/2/3]: " -r choice
    fi

    case "$choice" in
        1)
            log_warn "Skipping $tool. Install manually later:"
            log_detail "curl -fsSL $url | bash"
            SKIPPED_TOOLS+=("$tool")
            return 0  # Continue
            ;;
        2)
            log_error "Installation aborted by user"
            return 1  # Abort
            ;;
        3)
            log_warn "Installing $tool despite checksum mismatch (user accepted risk)"
            # Proceed with installation (dangerous)
            return 2  # Special code: proceed without verification
            ;;
        *)
            log_error "Invalid choice, aborting"
            return 1
            ;;
    esac
}
```

#### Modified Verification Flow

```bash
verify_and_run_with_recovery() {
    local name="$1"
    local url="$2"
    local expected_sha256="$3"

    # Fetch content
    local content
    content=$(acfs_curl "$url") || {
        log_error "Failed to fetch $url"
        return 1
    }

    # Calculate checksum
    local actual_sha256
    actual_sha256=$(echo "$content" | calculate_sha256)

    # Verify
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        handle_checksum_mismatch "$name" "$expected_sha256" "$actual_sha256" "$url"
        local result=$?

        case $result in
            0) return 0 ;;  # Skip tool, continue install
            1) return 1 ;;  # Abort
            2) ;;           # Proceed anyway (fall through to execute)
        esac
    fi

    # Execute
    echo "$content" | bash
}
```

#### Post-Install Report for Skipped Tools

```bash
report_skipped_tools() {
    if [[ ${#SKIPPED_TOOLS[@]} -eq 0 ]]; then
        return 0
    fi

    echo ""
    log_warn "The following tools were skipped due to checksum mismatches:"
    for tool in "${SKIPPED_TOOLS[@]}"; do
        local url="${KNOWN_INSTALLERS[$tool]:-unknown}"
        log_detail "$tool: $url"
    done
    echo ""
    log_detail "You can install these manually after verifying they are safe."
    log_detail "Or wait for ACFS to update checksums and run: acfs update --stack"
}
```

### Files Modified

- `scripts/lib/security.sh`: Add `handle_checksum_mismatch`, criticality classification
- `install.sh`: Use new recovery flow, track skipped tools, report at end

---

## 5. Enhanced Doctor with Functional Tests

### Problem Statement

`acfs doctor` only verifies binaries exist, not that they **work**:
- `claude --version` passes but `claude` fails with "not authenticated"
- `psql --version` passes but connection fails with "role does not exist"
- `vault --version` passes but `vault status` fails with "connection refused"

### Technical Design

#### Deep Check Flag

```bash
# New flag
acfs doctor --deep
```

#### Functional Test Functions

```bash
# Agent authentication tests
check_claude_auth() {
    if ! command -v claude &>/dev/null; then
        return 2  # Not installed, skip
    fi

    # Check if config exists
    if [[ ! -f "$HOME/.claude/config.json" ]]; then
        return 1  # Not authenticated
    fi

    # Try a minimal API call (conversation list, not a completion)
    local result
    if result=$(timeout 10 claude --print-system-info 2>&1); then
        return 0  # Auth OK
    else
        return 1  # Auth failed
    fi
}

check_codex_auth() {
    if ! command -v codex &>/dev/null; then
        return 2
    fi

    # Check for API key
    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        # Check .zshrc.local or .bashrc
        if ! grep -q "OPENAI_API_KEY" "$HOME/.zshrc.local" 2>/dev/null && \
           ! grep -q "OPENAI_API_KEY" "$HOME/.bashrc" 2>/dev/null; then
            return 1  # No API key configured
        fi
    fi

    return 0
}

check_gemini_auth() {
    if ! command -v gemini &>/dev/null; then
        return 2
    fi

    # Check for credentials (OAuth web login, like Claude Code and Codex CLI)
    if [[ ! -f "$HOME/.config/gemini/credentials.json" ]] && \
       [[ ! -d "$HOME/.config/gemini" ]]; then
        return 1
    fi

    return 0
}

# Database tests
check_postgres_connection() {
    if ! command -v psql &>/dev/null; then
        return 2
    fi

    # Try to connect as current user
    if psql -c "SELECT 1" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

check_postgres_role() {
    if ! command -v psql &>/dev/null; then
        return 2
    fi

    local user
    user=$(whoami)

    if sudo -u postgres psql -c "SELECT 1 FROM pg_roles WHERE rolname='$user'" 2>/dev/null | grep -q 1; then
        return 0
    else
        return 1
    fi
}

# Cloud CLI tests
check_vault_configured() {
    if ! command -v vault &>/dev/null; then
        return 2
    fi

    # Vault CLI is installed; server may or may not be running (that's OK)
    # Check if VAULT_ADDR is set
    if [[ -n "${VAULT_ADDR:-}" ]]; then
        return 0
    else
        # Not configured, but that might be intentional
        return 3  # "info" status - not a failure
    fi
}

check_wrangler_auth() {
    if ! command -v wrangler &>/dev/null; then
        return 2
    fi

    if wrangler whoami >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

check_supabase_auth() {
    if ! command -v supabase &>/dev/null; then
        return 2
    fi

    # Check for access token
    if [[ -f "$HOME/.config/supabase/access-token" ]]; then
        # Check if token is expired (basic check)
        return 0
    else
        return 1
    fi
}

check_convex_auth() {
    if ! command -v convex &>/dev/null; then
        return 2
    fi

    if [[ -n "${CONVEX_DEPLOYMENT:-}" || -n "${CONVEX_URL:-}" || -n "${CONVEX_API_KEY:-}" ]]; then
        return 0
    fi

    # Best-effort: Convex stores auth under ~/.config/convex or ~/.convex (paths may vary).
    if [[ -s "$HOME/.config/convex/config.json" || -s "$HOME/.config/convex/credentials.json" || -s "$HOME/.convex/config.json" || -s "$HOME/.convex/credentials.json" ]]; then
        return 0
    fi

    return 1
}

check_vercel_auth() {
    if ! command -v vercel &>/dev/null; then
        return 2
    fi

    if vercel whoami >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}
```

#### Deep Check Execution

```bash
run_deep_checks() {
    section "Functional Tests (--deep)"

    # Agent authentication
    check_with_status "Claude Code auth" check_claude_auth \
        "Run: claude auth login"

    check_with_status "Codex CLI auth" check_codex_auth \
        "Set OPENAI_API_KEY in ~/.zshrc.local"

    check_with_status "Gemini CLI auth" check_gemini_auth \
        "Run: gemini auth login"

    # Database
    check_with_status "PostgreSQL connection" check_postgres_connection \
        "Run: sudo -u postgres createuser -s $(whoami)"

    check_with_status "PostgreSQL role" check_postgres_role \
        "Run: sudo -u postgres createuser -s $(whoami)"

    # Cloud CLIs
    check_with_status "Vault configured" check_vault_configured \
        "Set VAULT_ADDR if using Vault server"

    check_with_status "Wrangler auth" check_wrangler_auth \
        "Run: wrangler login"

    check_with_status "Supabase auth" check_supabase_auth \
        "Run: supabase login"

    check_with_status "Convex auth" check_convex_auth \
        "Run: convex login"

    check_with_status "Vercel auth" check_vercel_auth \
        "Run: vercel login"
}

check_with_status() {
    local name="$1"
    local check_fn="$2"
    local fix_hint="$3"

    local result
    $check_fn
    result=$?

    case $result in
        0)
            check_result "pass" "$name" ""
            ;;
        1)
            check_result "fail" "$name" "$fix_hint"
            ;;
        2)
            check_result "skip" "$name" "Not installed"
            ;;
        3)
            check_result "info" "$name" "Not configured (optional)"
            ;;
    esac
}
```

#### Output Format

```
╔══════════════════════════════════════════════════════════════╗
║                    ACFS Deep Health Check                     ║
╠══════════════════════════════════════════════════════════════╣
║ Functional Tests (--deep)                                     ║
║   ✔ Claude Code auth: OK                                      ║
║   ✖ Codex CLI auth: OPENAI_API_KEY not set                    ║
║     → Fix: Set OPENAI_API_KEY in ~/.zshrc.local              ║
║   ✔ Gemini CLI auth: OK                                       ║
║   ✔ PostgreSQL connection: OK                                 ║
║   ✔ PostgreSQL role: ubuntu exists                            ║
║   ℹ Vault configured: Not configured (optional)               ║
║   ✖ Wrangler auth: Not logged in                              ║
║     → Fix: Run: wrangler login                               ║
║   ⚠ Supabase auth: Token expires in 3 days                    ║
║   ✔ Vercel auth: OK                                           ║
╠══════════════════════════════════════════════════════════════╣
║ Overall: 6/9 functional checks passed (1 info, 2 failed)      ║
╚══════════════════════════════════════════════════════════════╝
```

### Files Modified

- `scripts/lib/doctor.sh`: Add `--deep` flag, functional test functions

---

## 6. Automated Upstream Checksum Monitoring

### Problem Statement

Checksums in `checksums.yaml` become stale when upstream tools release updates. Users hit "checksum mismatch" errors that are actually normal releases, not security issues.

### Technical Design

#### GitHub Action

```yaml
# .github/workflows/checksum-monitor.yml
name: Monitor Upstream Checksums

on:
  schedule:
    - cron: '0 6 * * *'  # Daily at 6am UTC
  workflow_dispatch:  # Manual trigger

jobs:
  check-checksums:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y jq curl

      - name: Verify checksums
        id: verify
        run: |
          # Run verification and capture output
          ./scripts/lib/security.sh --verify --json > verification.json 2>&1 || true

          # Check for mismatches
          MISMATCHES=$(jq '.mismatches | length' verification.json)
          echo "mismatches=$MISMATCHES" >> $GITHUB_OUTPUT

          if [[ "$MISMATCHES" -gt 0 ]]; then
            echo "has_changes=true" >> $GITHUB_OUTPUT
            echo "## Checksum Mismatches Detected" >> $GITHUB_STEP_SUMMARY
            jq -r '.mismatches[] | "- **\(.name)**: \(.expected[:16])... → \(.actual[:16])..."' verification.json >> $GITHUB_STEP_SUMMARY
          else
            echo "has_changes=false" >> $GITHUB_OUTPUT
            echo "All checksums match!" >> $GITHUB_STEP_SUMMARY
          fi

      - name: Update checksums
        if: steps.verify.outputs.has_changes == 'true'
        run: |
          ./scripts/lib/security.sh --update-checksums > checksums.yaml.new
          mv checksums.yaml.new checksums.yaml

      - name: Get changelog info
        if: steps.verify.outputs.has_changes == 'true'
        id: changelog
        run: |
          # Try to fetch release notes for changed tools
          # This is a best-effort attempt
          BODY="## Upstream Checksum Updates\n\n"
          BODY+="The following upstream installer scripts have changed:\n\n"

          for tool in $(jq -r '.mismatches[].name' verification.json); do
            BODY+="### $tool\n"
            BODY+="- Old: \`$(jq -r --arg t "$tool" '.mismatches[] | select(.name==$t) | .expected[:16]' verification.json)...\`\n"
            BODY+="- New: \`$(jq -r --arg t "$tool" '.mismatches[] | select(.name==$t) | .actual[:16]' verification.json)...\`\n\n"
          done

          BODY+="\n---\n"
          BODY+="⚠️ **Review Required**: Please verify these are legitimate upstream updates before merging.\n"
          BODY+="\n### Verification Steps:\n"
          BODY+="1. Check upstream release notes\n"
          BODY+="2. Review the diff in installer scripts\n"
          BODY+="3. Ensure no malicious content\n"

          echo "body<<EOF" >> $GITHUB_OUTPUT
          echo -e "$BODY" >> $GITHUB_OUTPUT
          echo "EOF" >> $GITHUB_OUTPUT

      - name: Create Pull Request
        if: steps.verify.outputs.has_changes == 'true'
        uses: peter-evans/create-pull-request@v5
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          commit-message: "chore: update upstream checksums"
          branch: chore/update-checksums
          delete-branch: true
          title: "chore: update upstream checksums (${{ steps.verify.outputs.mismatches }} tools)"
          body: ${{ steps.changelog.outputs.body }}
          labels: |
            chore
            security
            automated
```

#### Enhanced security.sh for JSON Output

```bash
# Add to security.sh

verify_all_json() {
    local result='{"mismatches": [], "matches": [], "errors": []}'

    for name in "${!KNOWN_INSTALLERS[@]}"; do
        local url="${KNOWN_INSTALLERS[$name]}"
        local expected
        expected=$(get_expected_checksum "$name")

        if [[ -z "$expected" ]]; then
            result=$(echo "$result" | jq --arg n "$name" '.errors += [{"name": $n, "error": "No expected checksum"}]')
            continue
        fi

        local actual
        actual=$(fetch_checksum "$url" 2>/dev/null) || {
            result=$(echo "$result" | jq --arg n "$name" --arg u "$url" '.errors += [{"name": $n, "url": $u, "error": "Fetch failed"}]')
            continue
        }

        if [[ "$actual" == "$expected" ]]; then
            result=$(echo "$result" | jq --arg n "$name" --arg c "$actual" '.matches += [{"name": $n, "checksum": $c}]')
        else
            result=$(echo "$result" | jq \
                --arg n "$name" \
                --arg e "$expected" \
                --arg a "$actual" \
                --arg u "$url" \
                '.mismatches += [{"name": $n, "expected": $e, "actual": $a, "url": $u}]')
        fi
    done

    echo "$result"
}

# Update main to support --json flag
case "${1:-}" in
    --verify)
        if [[ "${2:-}" == "--json" ]]; then
            verify_all_json
        else
            verify_all_checksums
        fi
        ;;
    # ... other cases
esac
```

### Files Created/Modified

- `.github/workflows/checksum-monitor.yml` (new): Daily monitoring action
- `scripts/lib/security.sh`: Add `--json` output mode for verification

---

## 7. Agent Session Sharing & Replay

### Problem Statement

When an agent workflow works well, there's no way to:
1. Share it with teammates
2. Replay it on similar problems
3. Learn from successful patterns

### Technical Design

This is the most complex proposal, requiring integration with CASS (Coding Agent Session Search).

#### Session Export Format

```json
{
    "schema_version": 1,
    "exported_at": "2025-01-15T10:30:00Z",
    "session_id": "abc123",
    "agent": "claude-code",
    "model": "opus-4.5",
    "summary": "Implemented user authentication with Supabase",
    "duration_minutes": 45,
    "stats": {
        "turns": 23,
        "files_created": 4,
        "files_modified": 7,
        "commands_run": 12
    },
    "outcomes": [
        {
            "type": "file_created",
            "path": "src/lib/auth.ts",
            "description": "Supabase auth helper"
        },
        {
            "type": "file_modified",
            "path": "src/app/layout.tsx",
            "description": "Added auth provider wrapper"
        }
    ],
    "key_prompts": [
        "Set up Supabase authentication with email/password and OAuth",
        "Add protected routes that redirect to login"
    ],
    "sanitized_transcript": [
        {
            "role": "user",
            "content": "Set up Supabase authentication..."
        },
        {
            "role": "assistant",
            "content": "I'll help you set up Supabase auth. First, let me..."
        }
    ]
}
```

#### Sanitization Rules

```bash
# Patterns to redact from exported sessions
REDACT_PATTERNS=(
    # API keys
    'sk-[a-zA-Z0-9]{48}'           # OpenAI
    'sk-ant-[a-zA-Z0-9-]{90,}'     # Anthropic
    'AIza[a-zA-Z0-9_-]{35}'        # Google

    # Tokens
    'ghp_[a-zA-Z0-9]{36}'          # GitHub PAT
    'gho_[a-zA-Z0-9]{36}'          # GitHub OAuth
    'xoxb-[a-zA-Z0-9-]+'           # Slack

    # Passwords
    'password["\s:=]+[^\s]+'       # Password assignments
    'secret["\s:=]+[^\s]+'         # Secret assignments

    # IPs and hostnames (optional)
    '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'  # IPv4

    # Emails (optional, configurable)
    '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
)

sanitize_content() {
    local content="$1"

    for pattern in "${REDACT_PATTERNS[@]}"; do
        content=$(echo "$content" | sed -E "s/$pattern/[REDACTED]/g")
    done

    echo "$content"
}
```

#### CLI Commands

```bash
# Export last session
acfs session export --last > my-workflow.json
acfs session export --session-id abc123 > specific-session.json

# Export with options
acfs session export --last \
    --include-transcript \      # Include full transcript (sanitized)
    --include-diffs \          # Include file diffs
    --redact-emails \          # Also redact email addresses
    > detailed-export.json

# Import and preview
acfs session import my-workflow.json --dry-run
# Output:
# This session will:
#   - Create 4 files
#   - Modify 7 files
#   - Run 12 commands
#
# Files:
#   + src/lib/auth.ts (new)
#   + src/lib/supabase.ts (new)
#   ~ src/app/layout.tsx (modified)
#   ...
#
# Proceed with replay? [y/N]

# Replay (guided mode)
acfs session import my-workflow.json --guided
# Steps through each action, asking for confirmation

# Replay (automatic, dangerous)
acfs session import my-workflow.json --yes
```

#### Integration with CASS

```bash
# acfs session integrates with cass for storage
export_session() {
    local session_id="$1"
    local output_file="$2"

    # Use CASS to retrieve session
    if ! command -v cass &>/dev/null; then
        log_error "CASS not installed. Run: acfs update --stack"
        return 1
    fi

    # Get session data
    local session_data
    session_data=$(cass get "$session_id" --json) || {
        log_error "Session not found: $session_id"
        return 1
    }

    # Transform to export format
    local export_data
    export_data=$(transform_to_export_format "$session_data")

    # Sanitize
    export_data=$(sanitize_content "$export_data")

    # Write output
    echo "$export_data" > "$output_file"
    log_success "Exported session to $output_file"
}
```

### Phase 2: Community Sharing (Future)

This would require a hosted backend, which is out of scope for the initial implementation. The local export/import functionality provides immediate value without infrastructure.

### Files Created

- `scripts/lib/session.sh` (new): Session export/import logic
- `acfs/session/` (new directory): Session templates and sanitization rules

---

## Implementation Order

Based on dependencies and impact:

1. **Phase-Granular Progress Persistence** (Foundation)
   - Required by error reporting (#3)
   - Immediate user value

2. **Pre-Flight Validation** (Independent)
   - No dependencies
   - Quick win

3. **Per-Phase Error Reporting** (Depends on #1)
   - Uses state from #1
   - Major UX improvement

4. **Checkpoint-Based Checksum Recovery** (Independent)
   - No dependencies
   - Reduces friction

5. **Automated Checksum Monitoring** (Independent)
   - No code dependencies
   - Prevents future issues

6. **Enhanced Doctor** (Independent)
   - Builds on existing doctor
   - Post-install value

7. **Session Sharing** (Depends on CASS)
   - Requires stack tools
   - Longer-term value

---

## Success Metrics

| Proposal | Metric | Target |
|----------|--------|--------|
| Progress Persistence | Resume success rate | >95% |
| Pre-Flight | Issues caught before install | >80% of failures |
| Error Reporting | User self-resolution rate | >70% |
| Checksum Recovery | Install completions despite mismatch | >90% |
| Deep Doctor | Auth issues caught | 100% |
| Checksum Monitoring | Stale checksum duration | <24 hours |
| Session Sharing | Sessions exported/week | Measure baseline |

---

*Document version: 1.0*
*Last updated: 2025-01-15*
