#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Security Verification Library
# Provides checksum verification and HTTPS enforcement
#
# NOTE: This file is intended to be *sourced* by other scripts. Do not enable
# global strict mode here, since it would leak `set -euo pipefail` into callers.
# When executed directly, strict mode is enabled in the entrypoint below.
# ============================================================

SECURITY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$SECURITY_SCRIPT_DIR/logging.sh" 2>/dev/null || true
fi

# ============================================================
# Configuration
# ============================================================

# Check if running in interactive mode
# Returns 0 if interactive, 1 if non-interactive
_acfs_is_interactive() {
    [[ "${ACFS_INTERACTIVE:-true}" == "true" ]] && [[ -t 0 ]]
}

# curl defaults: enforce HTTPS (including redirects) when supported
ACFS_CURL_BASE_ARGS=(-fsSL)
if curl --help all 2>/dev/null | grep -q -- '--proto'; then
    ACFS_CURL_BASE_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi

acfs_curl() {
    curl "${ACFS_CURL_BASE_ARGS[@]}" "$@"
}

# Preserve trailing newlines when capturing remote script content.
ACFS_EOF_SENTINEL="__ACFS_EOF_SENTINEL__"

# Automatic retries for transient network errors (fast total budget).
ACFS_CURL_RETRY_DELAYS=(0 5 15)

acfs_is_retryable_curl_exit_code() {
    local exit_code="${1:-0}"
    case "$exit_code" in
        6|7|28|35|52|56) return 0 ;; # DNS/connect/timeout/SSL/empty reply/recv error
        *) return 1 ;;
    esac
}

# Fetch URL content with retries and an EOF sentinel appended.
# - Prints: <content><sentinel> on stdout (no trailing newline)
# - Returns: 0 on success; curl exit code on non-retryable failures; 1 on exhausted retries
acfs_curl_with_retry_and_sentinel() {
    local url="$1"
    local name="${2:-$url}"
    local sentinel="${ACFS_EOF_SENTINEL}"

    local max_attempts="${#ACFS_CURL_RETRY_DELAYS[@]}"
    if (( max_attempts == 0 )); then
        ACFS_CURL_RETRY_DELAYS=(0 5 15)
        max_attempts="${#ACFS_CURL_RETRY_DELAYS[@]}"
    fi

    local retries=$((max_attempts - 1))
    local attempt delay
    for ((attempt=0; attempt<max_attempts; attempt++)); do
        delay="${ACFS_CURL_RETRY_DELAYS[$attempt]}"

        if (( attempt > 0 )); then
            log_info "Retry ${attempt}/${retries} for fetching ${name} (waiting ${delay}s)..."
            sleep "$delay"
        fi

        local content status
        content="$(
            acfs_curl "$url" 2>/dev/null
            status=$?
            if (( status != 0 )); then
                exit "$status"
            fi
            printf '%s' "$sentinel"
        )"
        status=$?

        if (( status == 0 )) && [[ "$content" == *"$sentinel" ]]; then
            (( attempt > 0 )) && log_info "Succeeded on retry ${attempt} for fetching ${name}"
            printf '%s' "$content"
            return 0
        fi

        if ! acfs_is_retryable_curl_exit_code "$status"; then
            return "$status"
        fi
    done

    return 1
}

# Checksums file location.
# Prefer the repo-root checksums.yaml based on this script's location.
DEFAULT_CHECKSUMS_FILE="$SECURITY_SCRIPT_DIR/../../checksums.yaml"
if [[ -r "$DEFAULT_CHECKSUMS_FILE" ]]; then
    CHECKSUMS_FILE="${CHECKSUMS_FILE:-$DEFAULT_CHECKSUMS_FILE}"
else
    CHECKSUMS_FILE="${CHECKSUMS_FILE:-checksums.yaml}"
fi

# Known installer URLs and their expected checksums
# Format: URL|SHA256 (computed from the install script content)
# These are reference checksums - actual scripts may change
declare -gA KNOWN_INSTALLERS=(
    [bun]="https://bun.sh/install"
    [claude]="https://claude.ai/install.sh"
    [uv]="https://astral.sh/uv/install.sh"
    [rust]="https://sh.rustup.rs"
    [ohmyzsh]="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    [zoxide]="https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh"
    [atuin]="https://setup.atuin.sh"
    [ntm]="https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh"
    [mcp_agent_mail]="https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh"
    [ubs]="https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/master/install.sh"
    [bv]="https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh"
    [cass]="https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh"
    [cm]="https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh"
    [caam]="https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_account_manager/main/install.sh"
    [slb]="https://raw.githubusercontent.com/Dicklesworthstone/simultaneous_launch_button/main/scripts/install.sh"
)

# ============================================================
# Trusted Sources - Auto-Accept Checksum Changes
# ============================================================
#
# URLs from these domains are considered trusted. When checksums
# mismatch for trusted sources, we log a warning but PROCEED anyway.
# This prevents stale checksums from blocking legitimate installations.
#
# Rationale: A checksum mismatch from bun.sh is 99.99% likely to be
# a legitimate upstream update, not a supply chain attack.
#
TRUSTED_DOMAINS=(
    "bun.sh"
    "astral.sh"
    "rustup.rs"
    "sh.rustup.rs"
    "claude.ai"
    "setup.atuin.sh"
    "raw.githubusercontent.com"
)

# Check if a URL is from a trusted domain
is_trusted_source() {
    local url="$1"
    local domain

    # Extract domain from URL (handles https://domain.com/path)
    domain="${url#https://}"
    domain="${domain#http://}"
    domain="${domain%%/*}"

    for trusted in "${TRUSTED_DOMAINS[@]}"; do
        # Match exact domain or subdomain
        if [[ "$domain" == "$trusted" ]] || [[ "$domain" == *".$trusted" ]]; then
            return 0
        fi
    done
    return 1
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# ============================================================
# HTTPS Enforcement
# ============================================================

# Check if a URL is HTTPS
is_https() {
    local url="$1"
    [[ "$url" =~ ^https:// ]]
}

# Enforce HTTPS - fail if URL is not HTTPS
enforce_https() {
    local url="$1"
    local name="${2:-unknown}"

    if ! is_https "$url"; then
        echo -e "${RED}Security Error:${NC} URL for '$name' is not HTTPS" >&2
        echo -e "  URL: $url" >&2
        echo -e "  All installer URLs must use HTTPS." >&2
        return 1
    fi
    return 0
}

# ============================================================
# Checksum Verification
# ============================================================

# Calculate SHA256 of content
calculate_sha256() {
    if command -v sha256sum &>/dev/null; then
        sha256sum | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 | cut -d' ' -f1
    else
        echo "ERROR: No SHA256 tool available" >&2
        return 1
    fi
}

# Fetch content and calculate checksum
fetch_checksum() {
    local url="$1"

    if ! enforce_https "$url"; then
        return 1
    fi

    local sentinel="${ACFS_EOF_SENTINEL}"
    local content
    content="$(
        acfs_curl_with_retry_and_sentinel "$url" "$url"
    )" || {
        echo "ERROR: Failed to fetch $url" >&2
        return 1
    }

    if [[ "$content" != *"$sentinel" ]]; then
        echo "ERROR: Failed to fetch $url" >&2
        return 1
    fi
    content="${content%"$sentinel"}"

    if ! printf '%s' "$content" | calculate_sha256; then
        echo "ERROR: Failed to checksum $url" >&2
        return 1
    fi
}

# Verify URL content against expected checksum
verify_checksum() {
    local url="$1"
    local expected_sha256="$2"
    local name="${3:-installer}"

    if ! enforce_https "$url"; then
        return 1
    fi

    # Fetch once and verify the exact bytes we will output/run.
    #
    # NOTE: Bash command substitution trims trailing newlines, so we append a
    # sentinel token to preserve the original content verbatim (including
    # trailing newlines) without writing temp files.
    local sentinel="${ACFS_EOF_SENTINEL}"
    local content
    content="$(
        acfs_curl_with_retry_and_sentinel "$url" "$name"
    )" || {
        echo -e "${RED}Security Error:${NC} Failed to fetch $name" >&2
        return 1
    }

    if [[ "$content" != *"$sentinel" ]]; then
        echo -e "${RED}Security Error:${NC} Failed to fetch $name" >&2
        return 1
    fi
    content="${content%"$sentinel"}"

    local actual_sha256
    actual_sha256=$(printf '%s' "$content" | calculate_sha256) || {
        echo -e "${RED}Security Error:${NC} Failed to checksum $name" >&2
        return 1
    }

    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        echo -e "${RED}Security Error:${NC} Checksum mismatch for $name" >&2
        echo -e "  Expected: $expected_sha256" >&2
        echo -e "  Actual:   $actual_sha256" >&2
        echo -e "  URL: $url" >&2
        return 1
    fi

    echo -e "${GREEN}Verified:${NC} $name" >&2
    # Return the verified content (verbatim bytes) on stdout.
    printf '%s' "$content"
}

# Fetch and run with optional verification
fetch_and_run() {
    local url="$1"
    local expected_sha256="${2:-}"
    local name="${3:-installer}"
    shift 3 || true
    local args=("$@")

    if ! enforce_https "$url"; then
        return 1
    fi

    if [[ -z "$expected_sha256" ]]; then
        echo -e "${RED}Security Error:${NC} Missing checksum for $name" >&2
        echo -e "  URL: $url" >&2
        echo -e "  Refusing to execute unverified installer script." >&2
        echo -e "  Fix: update checksums.yaml (./scripts/lib/security.sh --update-checksums > checksums.yaml)" >&2
        return 1
    fi

    (
        set -o pipefail
        verify_checksum "$url" "$expected_sha256" "$name" | bash -s -- "${args[@]}"
    )
}

# ============================================================
# Fetch and Run with Recovery (bead anq)
# ============================================================

# Fetch and run installer with checksum mismatch recovery
#
# Unlike fetch_and_run(), this function handles checksum mismatches
# gracefully by calling handle_checksum_mismatch() which can:
#   - Skip the tool (return 0)
#   - Abort installation (return 1)
#   - Proceed with the new version (return 2)
#
# Arguments:
#   $1 - URL to fetch
#   $2 - Expected SHA256 checksum
#   $3 - Tool name (for display and classification)
#   $@ - Additional args to pass to the installer
#
# Environment:
#   ACFS_INTERACTIVE - "true" for prompts, "false" for auto-handling
#   ACFS_BATCH_CHECKSUMS - "true" to defer to batch handler
#
# Returns:
#   0 - Success (installed or skipped)
#   1 - Failure (abort or error)
#
fetch_and_run_with_recovery() {
    local url="$1"
    local expected_sha256="${2:-}"
    local name="${3:-installer}"
    shift 3 || true
    local args=("$@")

    if ! enforce_https "$url"; then
        return 1
    fi

    if [[ -z "$expected_sha256" ]]; then
        echo -e "${RED}Security Error:${NC} Missing checksum for $name" >&2
        echo -e "  URL: $url" >&2
        echo -e "  Refusing to execute unverified installer script." >&2
        return 1
    fi

    # Fetch content with retries
    local sentinel="${ACFS_EOF_SENTINEL}"
    local content
    content="$(acfs_curl_with_retry_and_sentinel "$url" "$name")" || {
        echo -e "${RED}Error:${NC} Failed to fetch $name" >&2
        return 1
    }

    if [[ "$content" != *"$sentinel" ]]; then
        echo -e "${RED}Error:${NC} Failed to fetch $name" >&2
        return 1
    fi
    content="${content%"$sentinel"}"

    # Calculate actual checksum
    local actual_sha256
    actual_sha256=$(printf '%s' "$content" | calculate_sha256) || {
        echo -e "${RED}Error:${NC} Failed to calculate checksum for $name" >&2
        return 1
    }

    # Check for mismatch
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        # Call mismatch handler
        handle_checksum_mismatch "$name" "$expected_sha256" "$actual_sha256" "$url"
        local mismatch_result=$?

        case $mismatch_result in
            0)
                # Skip - tool was skipped, continue installation
                echo -e "${YELLOW}Skipped:${NC} $name (checksum mismatch)" >&2
                return 0
                ;;
            1)
                # Abort - user or policy chose to abort
                return 1
                ;;
            2)
                # Proceed - run with new version
                echo -e "${GREEN}Proceeding:${NC} $name (new version accepted)" >&2
                ;;
            *)
                # Unknown result, abort for safety
                echo -e "${RED}Error:${NC} Unexpected handler result" >&2
                return 1
                ;;
        esac
    else
        echo -e "${GREEN}Verified:${NC} $name" >&2
    fi

    # Run the installer
    printf '%s' "$content" | bash -s -- "${args[@]}"
}

# ============================================================
# Print Mode Support
# ============================================================

# Print all upstream URLs that will be fetched
print_upstream_urls() {
    echo ""
    echo -e "${CYAN}Upstream Installers${NC}"
    echo "============================================================"
    echo ""
    echo "The following scripts will be downloaded and executed:"
    echo ""

    for name in "${!KNOWN_INSTALLERS[@]}"; do
        local url="${KNOWN_INSTALLERS[$name]}"
        printf "  %-20s %s\n" "$name:" "$url"
    done | sort

    echo ""
    echo -e "${DIM}All URLs use HTTPS for secure transport.${NC}"
    echo ""
}

# Print URLs with current checksums (for updating checksums.yaml)
print_current_checksums() {
    # Progress info to stderr (not part of YAML output)
    echo "" >&2
    echo -e "${CYAN}Generating checksums.yaml...${NC}" >&2
    echo "" >&2

    # YAML output to stdout
    echo "# checksums.yaml - Auto-generated $(date -Iseconds)"
    echo "# Run: ./scripts/lib/security.sh --update-checksums"
    echo ""
    echo "installers:"

    for name in "${!KNOWN_INSTALLERS[@]}"; do
        local url="${KNOWN_INSTALLERS[$name]}"
        local sha256

        printf "  Fetching %s... " "$name" >&2
        sha256=$(fetch_checksum "$url" 2>/dev/null) || {
            echo "FAILED" >&2
            sha256="FETCH_FAILED"
        }
        echo "done" >&2

        echo "  $name:"
        echo "    url: \"$url\""
        echo "    sha256: \"$sha256\""
        echo ""
    done
}

# ============================================================
# Checksums File Management
# ============================================================

# Load checksums from YAML file (simple parser)
# shellcheck disable=SC2120  # $1 is optional with default
load_checksums() {
    local file="${1:-$CHECKSUMS_FILE}"
    local current_tool=""

    if [[ ! -r "$file" ]]; then
        echo -e "${YELLOW}Warning:${NC} Checksums file not found: $file" >&2
        return 1
    fi

    # Simple YAML parsing for our specific format
    # Extracts name and sha256 pairs
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Match tool name (2-space indent, ends with :)
        if [[ "$line" =~ ^[[:space:]]{2}([a-z_]+): ]]; then
            current_tool="${BASH_REMATCH[1]}"
        fi

        # Match sha256 value
        if [[ "$line" =~ sha256:[[:space:]]*\"?([a-f0-9]{64})\"? ]]; then
            if [[ -n "$current_tool" ]]; then
                LOADED_CHECKSUMS["$current_tool"]="${BASH_REMATCH[1]}"
            fi
        fi
    done < "$file"
}

# Get checksum for a tool
get_checksum() {
    local tool="$1"
    echo "${LOADED_CHECKSUMS[$tool]:-}"
}

# Associative array to store loaded checksums
declare -gA LOADED_CHECKSUMS

# ============================================================
# Checksum Mismatch Batching
# Related: agentic_coding_flywheel_setup-4jr
# ============================================================

# Array to collect checksum mismatches during verification phase
# Format: "tool|url|expected|actual"
declare -g -a CHECKSUM_MISMATCHES=()

# Record a checksum mismatch for later batched handling
#
# Arguments:
#   $1 - Tool name
#   $2 - URL
#   $3 - Expected checksum
#   $4 - Actual checksum
#
record_checksum_mismatch() {
    local tool="$1"
    local url="$2"
    local expected="$3"
    local actual="$4"

    CHECKSUM_MISMATCHES+=("$tool|$url|$expected|$actual")
}

# Clear all recorded mismatches
clear_checksum_mismatches() {
    CHECKSUM_MISMATCHES=()
}

# Get count of recorded mismatches
count_checksum_mismatches() {
    echo "${#CHECKSUM_MISMATCHES[@]}"
}

# Check if any mismatches were recorded
has_checksum_mismatches() {
    [[ ${#CHECKSUM_MISMATCHES[@]} -gt 0 ]]
}

# Handle all checksum mismatches with batched prompts
#
# Instead of prompting for each mismatch, this function:
#   1. Collects all mismatches first (via record_checksum_mismatch)
#   2. Presents ONE decision prompt with P/S/A options
#   3. Handles non-interactive mode based on tool classification
#
# Environment:
#   ACFS_INTERACTIVE - "true" for interactive, "false" for non-interactive
#   ACFS_STRICT_MODE - "true" treats all mismatches as critical
#
# Returns:
#   0 - User chose to proceed or skip
#   1 - User chose to abort (or critical tool mismatch in non-interactive)
#
handle_all_checksum_mismatches() {
    if ! has_checksum_mismatches; then
        return 0  # No mismatches, all good
    fi

    local mismatch_count
    mismatch_count="$(count_checksum_mismatches)"

    # Source tools.sh for CRITICAL vs RECOMMENDED classification
    local tools_lib="${SECURITY_SCRIPT_DIR}/tools.sh"
    if [[ -r "$tools_lib" ]]; then
        # shellcheck source=tools.sh
        source "$tools_lib"
    fi

    # Non-interactive mode handling
    if ! _acfs_is_interactive; then
        _handle_mismatches_noninteractive
        return $?
    fi

    # Interactive mode: display mismatches and prompt
    echo "" >&2
    echo -e "${YELLOW}============================================================${NC}" >&2
    echo -e "${YELLOW}  Checksum Mismatches Detected: $mismatch_count installer(s)${NC}" >&2
    echo -e "${YELLOW}============================================================${NC}" >&2
    echo "" >&2
    echo "The following installers have changed since checksums.yaml was generated:" >&2
    echo "" >&2

    local has_critical=false
    local critical_tools=()
    local recommended_tools=()

    for entry in "${CHECKSUM_MISMATCHES[@]}"; do
        IFS="|" read -r tool url expected actual <<< "$entry"

        local classification="recommended"
        if declare -f is_critical_tool &>/dev/null && is_critical_tool "$tool"; then
            classification="critical"
            has_critical=true
            critical_tools+=("$tool")
        else
            recommended_tools+=("$tool")
        fi

        local classification_label
        if [[ "$classification" == "critical" ]]; then
            classification_label="${RED}[CRITICAL]${NC}"
        else
            classification_label="${YELLOW}[optional]${NC}"
        fi

        echo -e "  $classification_label $tool:" >&2
        echo "      Expected: ${expected:0:16}..." >&2
        echo "      Actual:   ${actual:0:16}..." >&2
        echo "      URL: $url" >&2
        echo "" >&2
    done

    echo "This usually means upstream scripts were updated (normal)." >&2
    echo "In rare cases, it could indicate a security issue." >&2
    echo "" >&2

    if [[ "$has_critical" == "true" ]]; then
        echo -e "${RED}WARNING: ${#critical_tools[@]} CRITICAL tool(s) affected.${NC}" >&2
        echo "Skipping critical tools may break the installation." >&2
        echo "" >&2
    fi

    echo "Options:" >&2
    echo "  [P] Proceed with new versions (update checksums.yaml later)" >&2
    echo "  [S] Skip mismatched tools, install everything else" >&2
    echo "  [A] Abort installation" >&2
    echo "" >&2

    local choice
    read -r -p "Choice [P/s/a]: " choice < /dev/tty

    case "${choice,,}" in
        s|skip)
            # Add all mismatched tools to SKIPPED_TOOLS
            for entry in "${CHECKSUM_MISMATCHES[@]}"; do
                IFS="|" read -r tool _ _ _ <<< "$entry"
                if declare -f handle_tool_failure &>/dev/null; then
                    # Use tool classification logic
                    handle_tool_failure "$tool" "Checksum mismatch (user chose to skip)" || return 1
                else
                    # Fallback: just track skipped
                    SKIPPED_TOOLS+=("$tool")
                fi
            done
            clear_checksum_mismatches
            return 0
            ;;
        a|abort)
            echo -e "${RED}Installation aborted by user.${NC}" >&2
            return 1
            ;;
        p|proceed|"")
            # Proceed with new versions (default)
            echo -e "${GREEN}Proceeding with updated installers...${NC}" >&2
            clear_checksum_mismatches
            return 0
            ;;
        *)
            echo "Invalid choice. Aborting for safety." >&2
            return 1
            ;;
    esac
}

# Internal: Handle mismatches in non-interactive mode
#
# Rules (updated for bulletproof automation):
#   - TRUSTED source mismatch → auto-accept with warning (never blocks)
#   - CRITICAL tool from UNTRUSTED source → abort (security risk)
#   - RECOMMENDED tool mismatch → auto-skip with warning
#
_handle_mismatches_noninteractive() {
    local has_critical_untrusted=false
    local critical_untrusted_names=()
    local trusted_accepted=()

    echo "" >&2
    echo -e "${YELLOW}Checksum mismatches detected (non-interactive mode):${NC}" >&2
    echo "" >&2

    for entry in "${CHECKSUM_MISMATCHES[@]}"; do
        IFS="|" read -r tool url expected actual <<< "$entry"

        # TRUSTED SOURCES: Always auto-accept (bulletproof automation)
        if is_trusted_source "$url"; then
            echo -e "  ${GREEN}[trusted]${NC} $tool - auto-accepting updated checksum" >&2
            trusted_accepted+=("$tool")
            continue
        fi

        # Non-trusted sources: use old critical/recommended logic
        local is_crit=false
        if declare -f is_critical_tool &>/dev/null && is_critical_tool "$tool"; then
            is_crit=true
            has_critical_untrusted=true
            critical_untrusted_names+=("$tool")
        fi

        if [[ "$is_crit" == "true" ]]; then
            echo -e "  ${RED}[CRITICAL-UNTRUSTED]${NC} $tool - checksum mismatch" >&2
        else
            echo -e "  ${YELLOW}[skipping]${NC} $tool - checksum mismatch" >&2
            # Auto-skip recommended tools from untrusted sources
            if declare -f handle_tool_failure &>/dev/null; then
                handle_tool_failure "$tool" "Checksum mismatch (auto-skipped in non-interactive mode)"
            else
                SKIPPED_TOOLS+=("$tool")
            fi
        fi
    done

    echo "" >&2

    # Report trusted sources that were auto-accepted
    if [[ ${#trusted_accepted[@]} -gt 0 ]]; then
        echo -e "${GREEN}Auto-accepted ${#trusted_accepted[@]} tool(s) from trusted sources: ${trusted_accepted[*]}${NC}" >&2
    fi

    # Only abort if there are critical tools from UNTRUSTED sources
    if [[ "$has_critical_untrusted" == "true" ]]; then
        echo -e "${RED}ABORTING: Critical tools from UNTRUSTED sources have checksum mismatches: ${critical_untrusted_names[*]}${NC}" >&2
        echo "Cannot proceed safely without verified critical installers from untrusted sources." >&2
        return 1
    fi

    # All trusted sources accepted, non-critical untrusted skipped - continue
    echo -e "${GREEN}Proceeding with installation (trusted sources accepted, non-critical skipped).${NC}" >&2
    clear_checksum_mismatches
    return 0
}

# ============================================================
# Per-Tool Checksum Mismatch Handler
# Related: agentic_coding_flywheel_setup-anq
# ============================================================

# Handle a single checksum mismatch with skip/abort/proceed options
#
# This function provides immediate per-tool handling when not using
# batch mode (handle_all_checksum_mismatches).
#
# Arguments:
#   $1 - Tool name
#   $2 - Expected checksum
#   $3 - Actual checksum
#   $4 - URL
#
# Environment:
#   ACFS_INTERACTIVE - "true" for interactive, "false" for non-interactive
#   ACFS_BATCH_CHECKSUMS - "true" to record for batch handling instead
#
# Returns:
#   0 - Skip this tool, continue installation
#   1 - Abort installation
#   2 - Proceed anyway (use the new version)
#
handle_checksum_mismatch() {
    local tool="$1"
    local expected="$2"
    local actual="$3"
    local url="$4"

    # If batch mode is enabled, just record and return proceed
    if [[ "${ACFS_BATCH_CHECKSUMS:-false}" == "true" ]]; then
        record_checksum_mismatch "$tool" "$url" "$expected" "$actual"
        return 2  # Caller should proceed (batch handler decides later)
    fi

    # Source tools.sh for classification if not already loaded
    local tools_lib="${SECURITY_SCRIPT_DIR}/tools.sh"
    if ! declare -f is_critical_tool &>/dev/null && [[ -r "$tools_lib" ]]; then
        # shellcheck source=tools.sh
        source "$tools_lib"
    fi

    local is_critical=false
    if declare -f is_critical_tool &>/dev/null && is_critical_tool "$tool"; then
        is_critical=true
    fi

    # Non-interactive mode
    if ! _acfs_is_interactive; then
        # TRUSTED SOURCES: Auto-accept checksum changes with warning
        # This is the key to bulletproof automation - trusted sources are almost
        # never compromised, and stale checksums are the #1 cause of install failures
        if is_trusted_source "$url"; then
            echo -e "${YELLOW}NOTICE: Checksum changed for $tool (trusted source: auto-accepting)${NC}" >&2
            echo -e "  Expected: ${expected:0:16}..." >&2
            echo -e "  Actual:   ${actual:0:16}..." >&2
            echo -e "  ${GREEN}Proceeding with updated version from trusted source${NC}" >&2
            return 2  # Proceed
        fi

        # Non-trusted sources: fall back to old behavior
        if [[ "$is_critical" == "true" ]]; then
            echo -e "${RED}CRITICAL tool $tool has checksum mismatch (untrusted source) - aborting${NC}" >&2
            return 1  # Abort
        else
            echo -e "${YELLOW}Skipping $tool (checksum mismatch, non-interactive)${NC}" >&2
            if declare -f handle_tool_failure &>/dev/null; then
                handle_tool_failure "$tool" "Checksum mismatch (auto-skipped)"
            fi
            return 0  # Skip
        fi
    fi

    # Interactive mode: show details and prompt
    echo "" >&2
    echo -e "${YELLOW}━━━ Checksum Mismatch: $tool ━━━${NC}" >&2
    echo "" >&2

    local classification_label
    if [[ "$is_critical" == "true" ]]; then
        classification_label="${RED}[CRITICAL]${NC}"
    else
        classification_label="${YELLOW}[optional]${NC}"
    fi

    echo -e "  Tool: $classification_label $tool" >&2
    echo "  Expected: ${expected:0:16}..." >&2
    echo "  Actual:   ${actual:0:16}..." >&2
    echo "  URL: $url" >&2
    echo "" >&2
    echo "This usually means the upstream script was updated." >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  [P] Proceed with new version" >&2
    echo "  [S] Skip this tool" >&2
    echo "  [A] Abort installation" >&2
    echo "" >&2

    if [[ "$is_critical" == "true" ]]; then
        echo -e "${RED}WARNING: Skipping a CRITICAL tool may break installation.${NC}" >&2
    fi

    local choice
    read -r -p "Choice [P/s/a]: " choice < /dev/tty

    case "${choice,,}" in
        s|skip)
            if declare -f handle_tool_failure &>/dev/null; then
                handle_tool_failure "$tool" "Checksum mismatch (user chose to skip)"
            fi
            return 0  # Skip
            ;;
        a|abort)
            echo -e "${RED}Installation aborted by user.${NC}" >&2
            return 1  # Abort
            ;;
        p|proceed|"")
            echo -e "${GREEN}Proceeding with new version of $tool...${NC}" >&2
            return 2  # Proceed
            ;;
        *)
            echo "Invalid choice. Aborting for safety." >&2
            return 1  # Abort
            ;;
    esac
}

# Check installer and record mismatch if found
#
# Arguments:
#   $1 - Tool name
#   $2 - URL (optional, uses KNOWN_INSTALLERS if not provided)
#   $3 - Expected checksum (optional, uses LOADED_CHECKSUMS if not provided)
#
# Returns:
#   0 - Checksum matches
#   1 - Checksum mismatch (recorded for later batched handling)
#   2 - Fetch error
#
check_installer_checksum() {
    local tool="$1"
    local url="${2:-${KNOWN_INSTALLERS[$tool]:-}}"
    local expected="${3:-${LOADED_CHECKSUMS[$tool]:-}}"

    if [[ -z "$url" ]]; then
        echo "Warning: No URL for tool $tool" >&2
        return 2
    fi

    if [[ -z "$expected" ]]; then
        echo "Warning: No expected checksum for $tool" >&2
        return 2
    fi

    local actual
    actual=$(fetch_checksum "$url" 2>/dev/null) || {
        echo "Warning: Failed to fetch $tool from $url" >&2
        return 2
    }

    if [[ "$actual" != "$expected" ]]; then
        record_checksum_mismatch "$tool" "$url" "$expected" "$actual"
        return 1
    fi

    return 0
}

# ============================================================
# Verification Report
# ============================================================

# Verify all known installers and report
verify_all_installers() {
    local all_pass=true
    local verified=0
    local failed=0

    echo ""
    echo -e "${CYAN}Verifying Installer Integrity${NC}"
    echo "============================================================"
    echo ""

    for name in "${!KNOWN_INSTALLERS[@]}"; do
        local url="${KNOWN_INSTALLERS[$name]}"
        local expected="${LOADED_CHECKSUMS[$name]:-}"

        printf "  %-20s " "$name"

        if [[ -z "$expected" ]]; then
            echo -e "${YELLOW}[skip]${NC} no checksum recorded"
            continue
        fi

        local actual
        actual=$(fetch_checksum "$url" 2>/dev/null) || {
            echo -e "${RED}[fail]${NC} fetch error"
            ((failed += 1))
            all_pass=false
            continue
        }

        if [[ "$actual" == "$expected" ]]; then
            echo -e "${GREEN}[ok]${NC}"
            ((verified += 1))
        else
            echo -e "${RED}[fail]${NC} checksum changed"
            ((failed += 1))
            all_pass=false
        fi
    done

    echo ""
    echo "------------------------------------------------------------"
    echo -e "Verified: $verified, Failed: $failed"

    if [[ "$all_pass" == "true" ]]; then
        echo -e "${GREEN}All installer checksums verified.${NC}"
        return 0
    else
        echo -e "${YELLOW}Some checksums failed or changed.${NC}"
        echo "This may indicate:"
        echo "  - Upstream scripts were updated (normal)"
        echo "  - Potential security issue (rare)"
        echo ""
        echo "To update checksums after review:"
        echo "  ./scripts/lib/security.sh --update-checksums > checksums.yaml"
        return 1
    fi
}

# Verify all known installers and output as JSON
# Usage: verify_all_installers_json
# Output: JSON object with matches, mismatches, and errors arrays
verify_all_installers_json() {
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Arrays to collect results
    local matches=()
    local mismatches=()
    local errors=()
    local skipped=()
    local total=0

    # Helper function to escape strings for JSON
    _json_escape() {
        local str="$1"
        # Escape backslashes first, then other special characters
        str="${str//\\/\\\\}"
        str="${str//\"/\\\"}"
        str="${str//$'\t'/\\t}"
        str="${str//$'\r'/\\r}"
        str="${str//$'\n'/\\n}"
        echo -n "$str"
    }

    for name in "${!KNOWN_INSTALLERS[@]}"; do
        local url="${KNOWN_INSTALLERS[$name]}"
        local expected="${LOADED_CHECKSUMS[$name]:-}"
        total=$((total + 1))

        if [[ -z "$expected" ]]; then
            skipped+=("{\"name\":\"$name\",\"reason\":\"no checksum recorded\"}")
            continue
        fi

        local actual
        local fetch_error=""
        actual=$(fetch_checksum "$url" 2>&1) || fetch_error="$actual"

        if [[ -n "$fetch_error" ]]; then
            local escaped_error
            escaped_error=$(_json_escape "$fetch_error")
            errors+=("{\"name\":\"$name\",\"url\":\"$url\",\"error\":\"$escaped_error\"}")
        elif [[ "$actual" == "$expected" ]]; then
            matches+=("{\"name\":\"$name\",\"checksum\":\"$expected\"}")
        else
            mismatches+=("{\"name\":\"$name\",\"url\":\"$url\",\"expected\":\"$expected\",\"actual\":\"$actual\"}")
        fi
    done

    # Build JSON output
    echo "{"
    echo "  \"timestamp\": \"$timestamp\","
    echo "  \"total\": $total,"

    # Matches array
    echo "  \"matches\": ["
    local first=true
    for item in "${matches[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    $item"
    done
    if [[ ${#matches[@]} -gt 0 ]]; then echo; fi
    echo "  ],"

    # Mismatches array
    echo "  \"mismatches\": ["
    first=true
    for item in "${mismatches[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    $item"
    done
    if [[ ${#mismatches[@]} -gt 0 ]]; then echo; fi
    echo "  ],"

    # Errors array
    echo "  \"errors\": ["
    first=true
    for item in "${errors[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    $item"
    done
    if [[ ${#errors[@]} -gt 0 ]]; then echo; fi
    echo "  ],"

    # Skipped array
    echo "  \"skipped\": ["
    first=true
    for item in "${skipped[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    $item"
    done
    if [[ ${#skipped[@]} -gt 0 ]]; then echo; fi
    echo "  ]"

    echo "}"

    # Return non-zero if there are mismatches or errors
    if [[ ${#mismatches[@]} -gt 0 || ${#errors[@]} -gt 0 ]]; then
        return 1
    fi
    return 0
}

# ============================================================
# CLI Interface
# ============================================================

usage() {
    cat << 'EOF'
security.sh - ACFS Installer Security Verification

Usage:
  security.sh [command] [options]

Commands:
  --print              Print all upstream URLs
  --update-checksums   Generate checksums.yaml content
  --verify             Verify all installers against saved checksums
  --checksum URL       Calculate SHA256 of a URL
  --help               Show this help

Options:
  --json               Output in JSON format (use with --verify)

Examples:
  ./security.sh --print
  ./security.sh --update-checksums > checksums.yaml
  ./security.sh --verify
  ./security.sh --verify --json
  ./security.sh --checksum https://bun.sh/install
EOF
}

main() {
    local json_output=false

    # Parse --json flag if present
    for arg in "$@"; do
        if [[ "$arg" == "--json" ]]; then
            json_output=true
        fi
    done

    case "${1:-}" in
        --print)
            print_upstream_urls
            ;;
        --update-checksums)
            print_current_checksums
            ;;
        --verify)
            load_checksums
            if [[ "$json_output" == "true" ]]; then
                verify_all_installers_json
            else
                verify_all_installers
            fi
            ;;
        --checksum)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: security.sh --checksum URL" >&2
                exit 1
            fi
            fetch_checksum "$2"
            ;;
        --help|-h)
            usage
            ;;
        "")
            usage
            ;;
        *)
            echo "Unknown command: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    main "$@"
fi
