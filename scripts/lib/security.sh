#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Security Verification Library
# Provides checksum verification and HTTPS enforcement
# ============================================================

set -euo pipefail

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=logging.sh
    source "$SCRIPT_DIR/logging.sh" 2>/dev/null || true
fi

# ============================================================
# Configuration
# ============================================================

# Checksums file location (relative to project root)
CHECKSUMS_FILE="${CHECKSUMS_FILE:-checksums.yaml}"

# Known installer URLs and their expected checksums
# Format: URL|SHA256 (computed from the install script content)
# These are reference checksums - actual scripts may change
declare -A KNOWN_INSTALLERS=(
    ["bun"]="https://bun.sh/install"
    ["uv"]="https://astral.sh/uv/install.sh"
    ["rust"]="https://sh.rustup.rs"
    ["ohmyzsh"]="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    ["zoxide"]="https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh"
    ["atuin"]="https://setup.atuin.sh"
    ["ntm"]="https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh"
    ["mcp_agent_mail"]="https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh"
    ["ubs"]="https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/master/install.sh"
    ["bv"]="https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh"
    ["cass"]="https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh"
    ["cm"]="https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh"
    ["caam"]="https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_account_manager/main/install.sh"
    ["slb"]="https://raw.githubusercontent.com/Dicklesworthstone/simultaneous_launch_button/main/scripts/install.sh"
)

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

    if ! curl -fsSL "$url" 2>/dev/null | calculate_sha256; then
        echo "ERROR: Failed to fetch $url" >&2
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

    local actual_sha256
    actual_sha256=$(curl -fsSL "$url" 2>/dev/null | calculate_sha256) || {
        echo -e "${RED}Security Error:${NC} Failed to fetch $name" >&2
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
    curl -fsSL "$url" 2>/dev/null || {
        echo -e "${RED}Security Error:${NC} Failed to fetch $name (post-verify)" >&2
        return 1
    }
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

    if [[ -n "$expected_sha256" ]]; then
        verify_checksum "$url" "$expected_sha256" "$name" | bash -s -- "${args[@]}"
    else
        curl -fsSL "$url" 2>/dev/null | bash -s -- "${args[@]}"
    fi
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
    echo ""
    echo -e "${CYAN}Current Installer Checksums${NC}"
    echo "============================================================"
    echo ""
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
load_checksums() {
    local file="${1:-$CHECKSUMS_FILE}"

    if [[ ! -f "$file" ]]; then
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
            if [[ -n "${current_tool:-}" ]]; then
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
declare -A LOADED_CHECKSUMS

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
            ((failed++))
            all_pass=false
            continue
        }

        if [[ "$actual" == "$expected" ]]; then
            echo -e "${GREEN}[ok]${NC}"
            ((verified++))
        else
            echo -e "${RED}[fail]${NC} checksum changed"
            ((failed++))
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

# ============================================================
# CLI Interface
# ============================================================

usage() {
    cat << 'EOF'
security.sh - ACFS Installer Security Verification

Usage:
  security.sh [command]

Commands:
  --print              Print all upstream URLs
  --update-checksums   Generate checksums.yaml content
  --verify             Verify all installers against saved checksums
  --checksum URL       Calculate SHA256 of a URL
  --help               Show this help

Examples:
  ./security.sh --print
  ./security.sh --update-checksums > checksums.yaml
  ./security.sh --verify
  ./security.sh --checksum https://bun.sh/install
EOF
}

main() {
    case "${1:-}" in
        --print)
            print_upstream_urls
            ;;
        --update-checksums)
            print_current_checksums
            ;;
        --verify)
            load_checksums
            verify_all_installers
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
    main "$@"
fi
