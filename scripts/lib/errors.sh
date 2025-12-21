#!/usr/bin/env bash
# ============================================================
# ACFS Installer - Error Patterns Library
# Provides common error pattern matching and suggested fixes
# Part of EPIC: Per-Phase Error Reporting (bead vwv)
# ============================================================

# Guard against double-sourcing
if [[ -n "${ACFS_ERRORS_LOADED:-}" ]]; then
    return 0
fi
export ACFS_ERRORS_LOADED=1

# ============================================================
# Error Pattern Database
# Maps known error strings to actionable fix suggestions
# ============================================================

# Common installation errors and their fixes
# Format: ["error pattern"]="suggested fix"
# shellcheck disable=SC2034  # Used by get_suggested_fix()
declare -A ERROR_PATTERNS=(
    # Network connectivity issues
    ["curl: (7) Failed to connect"]="Network connection failed. Check internet connectivity:\n  curl -I https://google.com\nAlso verify firewall allows outbound HTTPS (port 443)."

    ["curl: (6) Could not resolve"]="DNS resolution failed. Check DNS configuration:\n  cat /etc/resolv.conf\n  ping -c1 8.8.8.8\nIf ping works but DNS doesn't, try adding 'nameserver 8.8.8.8' to /etc/resolv.conf"

    ["curl: (28) Connection timed out"]="Network timeout. This could be:\n  1. Slow/unstable internet connection\n  2. Firewall blocking outbound HTTPS\n  3. Upstream server temporarily down\nTry: curl -v https://google.com --connect-timeout 10"

    ["curl: (35) SSL connect error"]="SSL/TLS handshake failed. Possible causes:\n  1. Outdated ca-certificates: sudo apt-get update && sudo apt-get install -y ca-certificates\n  2. System clock wrong: date && sudo ntpdate -s time.nist.gov\n  3. Corporate proxy/firewall intercepting HTTPS"

    ["Connection refused"]="Connection refused by remote server. The service may be:\n  1. Temporarily down - wait and retry\n  2. Blocked by firewall - check outbound rules\n  3. Rate limited - wait 60 seconds"

    # APT/package management
    ["E: Unable to locate package"]="Package not found in APT repositories. Try:\n  sudo apt-get update\nIf still failing, the package may not exist for your Ubuntu version."

    ["E: Could not get lock"]="APT lock held by another process. Solutions:\n  1. Wait for other installs to finish\n  2. Check: ps aux | grep -E 'apt|dpkg'\n  3. If stuck: sudo rm /var/lib/apt/lists/lock (use with caution)"

    ["dpkg: error processing"]="DPKG database corrupted. Try:\n  sudo dpkg --configure -a\n  sudo apt-get install -f"

    ["Unmet dependencies"]="Package dependencies cannot be satisfied. Try:\n  sudo apt-get install -f\n  sudo apt-get update && sudo apt-get upgrade"

    ["Hash Sum mismatch"]="APT cache corrupted. Fix with:\n  sudo rm -rf /var/lib/apt/lists/*\n  sudo apt-get update"

    # Permission issues
    ["Permission denied"]="Permission issue. Ensure you're running with appropriate privileges:\n  1. Run with sudo: sudo bash install.sh\n  2. Or run as root user\n  3. Check file permissions: ls -la"

    ["Operation not permitted"]="Operation blocked. You may need:\n  1. Root/sudo access\n  2. To disable read-only filesystem protection\n  3. To check SELinux/AppArmor restrictions"

    # Disk space
    ["No space left on device"]="Disk is full. Free up space:\n  df -h  # Check disk usage\n  sudo apt-get clean  # Clear APT cache\n  sudo journalctl --vacuum-time=7d  # Clear old logs"

    ["disk quota exceeded"]="Disk quota exceeded. Contact system administrator or:\n  quota -v  # Check your quota\n  du -sh ~/* | sort -h  # Find large directories"

    # GPG/signing issues
    ["gpg: keyserver receive failed"]="GPG keyserver unreachable. Alternatives:\n  1. Retry later - keyservers are sometimes slow\n  2. Try different keyserver: --keyserver hkp://keyserver.ubuntu.com:80\n  3. Check firewall allows port 11371 or 80"

    ["NO_PUBKEY"]="Missing GPG key for repository. Try:\n  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys <KEY_ID>"

    # Verification/checksum
    ["checksum mismatch"]="Upstream installer script has changed. This could mean:\n  1. Legitimate update - check the tool's GitHub for release notes\n  2. Potential tampering - verify manually before proceeding\nSee: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues"

    ["signature verification failed"]="GPG signature verification failed. The file may be:\n  1. Corrupted during download - retry\n  2. Tampered with - do not proceed\n  3. Using outdated signing key"

    # Rate limiting
    ["rate limit"]="API rate limit exceeded. Solutions:\n  1. Wait 60 seconds and retry\n  2. If using GitHub: authenticate with 'gh auth login'\n  3. Consider using a different network/IP"

    ["Too Many Requests"]="Server rate limiting requests. Wait 1-5 minutes before retrying."

    ["API rate limit exceeded"]="GitHub API rate limit. Authenticate to increase limit:\n  gh auth login\nOr wait ~60 minutes for limit reset."

    # Memory issues
    ["Cannot allocate memory"]="System out of memory. Try:\n  1. Close other applications\n  2. Add swap: sudo fallocate -l 2G /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile\n  3. Use a VPS with more RAM (4GB+ recommended)"

    ["Killed"]="Process killed (likely OOM killer). Your VPS may need more RAM.\n  Minimum: 4GB recommended for ACFS install.\n  Check: free -h"

    # Git issues
    ["fatal: not a git repository"]="Not in a git repository. Ensure you're in the correct directory:\n  pwd\n  git status"

    ["fatal: remote origin already exists"]="Git remote already configured. This is usually fine. To reset:\n  git remote remove origin\n  git remote add origin <url>"

    # Node/Bun issues
    ["EACCES: permission denied"]="Node/Bun permission issue. Don't use sudo with npm/bun global installs.\n  Instead, fix permissions: chown -R \$USER ~/.npm ~/.bun"

    ["ENOENT: no such file or directory"]="File or directory not found. Check:\n  1. Current directory: pwd\n  2. File exists: ls -la\n  3. Path is correct"

    # Python/uv issues
    ["No module named"]="Python module not found. Install with:\n  uv pip install <module>\n  Or: pip install <module>"

    # Rust/cargo issues
    ["linker 'cc' not found"]="C compiler not installed. Install build tools:\n  sudo apt-get install -y build-essential"

    ["Could not compile"]="Rust compilation failed. Usually needs:\n  sudo apt-get install -y build-essential pkg-config libssl-dev"

    # Timeout/hanging
    ["timed out"]="Operation timed out. This could be:\n  1. Slow network - retry on stable connection\n  2. Overloaded server - wait and retry\n  3. Firewall blocking - check outbound rules"

    # SSH issues (for user guidance)
    ["Connection closed by remote host"]="SSH connection closed. Possible causes:\n  1. Server rebooted - wait 30s and reconnect\n  2. Network interruption - check your connection\n  3. Server-side issue - contact VPS provider if persists"

    ["Host key verification failed"]="SSH host key changed. If expected (new VPS), fix with:\n  ssh-keygen -R <hostname>\nIf unexpected, verify you're connecting to the right server!"
)

# ============================================================
# Error Matching Functions
# ============================================================

# Get the matching pattern for an error (prioritizing specific/longer matches)
# Usage: get_error_pattern "error message text"
# Returns: The matched pattern, or empty string
get_error_pattern() {
    local error_text="$1"
    local pattern

    # Sort patterns by length (descending) to match specific errors before generic ones
    # e.g. "curl: (28) Connection timed out" before "timed out"
    # Use array for safety with spaces
    local sorted_patterns=()
    while IFS=$'\t' read -r _ len pat; do
        sorted_patterns+=("$pat")
    done < <(for p in "${!ERROR_PATTERNS[@]}"; do echo -e "${#p}\t$p"; done | sort -rn)

    for pattern in "${sorted_patterns[@]}"; do
        if [[ "$error_text" == *"$pattern"* ]]; then
            echo "$pattern"
            return 0
        fi
    done

    return 1
}

# Get a suggested fix for an error message
# Usage: get_suggested_fix "error message text"
# Returns: Suggested fix text, or generic message if no match
get_suggested_fix() {
    local error_text="$1"
    local pattern
    local fix

    pattern=$(get_error_pattern "$error_text")

    if [[ -n "$pattern" ]]; then
        fix="${ERROR_PATTERNS[$pattern]}"
        echo -e "$fix"
        return 0
    fi

    # No pattern matched - return generic guidance
    echo -e "Unknown error. Troubleshooting steps:\n  1. Check internet connectivity: curl -I https://google.com\n  2. Verify disk space: df -h\n  3. Check system logs: journalctl -xe\n  4. Search the error message online\n  5. Report at: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues"
    return 1
}

# Check if an error matches any known pattern
# Usage: is_known_error "error message text"
# Returns: 0 if known, 1 if unknown
is_known_error() {
    local error_text="$1"
    if get_error_pattern "$error_text" >/dev/null; then
        return 0
    fi
    return 1
}

# Format error with suggested fix for display
# Usage: format_error_with_fix "error message" "phase_name"
# Returns: Formatted error block with context and fix
format_error_with_fix() {
    local error_text="$1"
    local phase="${2:-unknown}"
    local suggested_fix
    local pattern

    pattern=$(get_error_pattern "$error_text")
    suggested_fix=$(get_suggested_fix "$error_text")

    echo "=========================================="
    echo "ERROR during phase: $phase"
    echo "=========================================="
    echo ""
    echo "Error message:"
    echo "  $error_text"
    echo ""
    if [[ -n "$pattern" ]]; then
        echo "Matched pattern: $pattern"
        echo ""
    fi
    echo "Suggested fix:"
    echo -e "$suggested_fix" | sed 's/^/  /'
    echo ""
    echo "=========================================="
}

# Count total number of known error patterns
# Usage: count_error_patterns
# Returns: Number of patterns in database
count_error_patterns() {
    echo "${#ERROR_PATTERNS[@]}"
}

# List all known error patterns (for debugging/docs)
# Usage: list_error_patterns
list_error_patterns() {
    local pattern
    echo "Known error patterns ($(count_error_patterns) total):"
    echo ""
    for pattern in "${!ERROR_PATTERNS[@]}"; do
        echo "  - $pattern"
    done
}
