#!/usr/bin/env bash
# ============================================================
# ACFS Pre-Flight Check
#
# Validates system prerequisites before installation to fail fast
# with clear, actionable error messages.
#
# Usage:
#   ./scripts/preflight.sh               # Full check with colored output
#   ./scripts/preflight.sh --quiet       # Exit code only
#   ./scripts/preflight.sh --json        # JSON output for automation
#   ./scripts/preflight.sh --format toon # TOON output for automation
#
# Exit Codes:
#   0: All critical checks pass (warnings are OK)
#   1: Critical check failed (installation would fail)
#
# Related beads:
#   - agentic_coding_flywheel_setup-0iq: Create scripts/preflight.sh
#   - agentic_coding_flywheel_setup-0ok: EPIC: Pre-Flight Validation
# ============================================================

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
GRAY='\033[0;90m'
NC='\033[0m'

# Symbols
CHECK="${GREEN}[✓]${NC}"
WARN="${YELLOW}[!]${NC}"
FAIL="${RED}[✗]${NC}"

# Counters
ERRORS=0
WARNINGS=0

# Output mode
QUIET=false
OUTPUT_FORMAT="text" # text|json|toon
MACHINE_OUTPUT=false
NETWORK_MODE="${ACFS_PREFLIGHT_NETWORK:-check}" # check|skip
CHECKSUM_CANDIDATE_FILE="${ACFS_PREFLIGHT_CHECKSUM_CANDIDATE:-}"

# Results for JSON output
declare -a RESULTS=()

preflight_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

preflight_is_valid_username() {
    local username="${1:-}"
    [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

preflight_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

preflight_getent_passwd_entry() {
    local user="${1:-}"
    local getent_bin=""
    local passwd_line=""
    local passwd_user=""

    getent_bin="$(preflight_system_binary_path getent 2>/dev/null || true)"
    if [[ -n "$getent_bin" ]]; then
        if [[ -n "$user" ]]; then
            "$getent_bin" passwd "$user" 2>/dev/null
        else
            "$getent_bin" passwd 2>/dev/null
        fi
        return $?
    fi

    [[ -r /etc/passwd ]] || return 1

    if [[ -n "$user" ]]; then
        while IFS= read -r passwd_line; do
            IFS=: read -r passwd_user _ <<< "$passwd_line"
            if [[ "$passwd_user" == "$user" ]]; then
                printf '%s\n' "$passwd_line"
                return 0
            fi
        done < /etc/passwd
        return 1
    fi

    while IFS= read -r passwd_line; do
        printf '%s\n' "$passwd_line"
    done < /etc/passwd
}

resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(preflight_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(preflight_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

preflight_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="$(preflight_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    base_home="$(preflight_sanitize_abs_nonroot_path "$base_home" 2>/dev/null || true)"

    if [[ -n "$base_home" ]] && [[ "$bin_dir" == "$base_home" || "$bin_dir" == "$base_home/"* ]]; then
        printf '%s\n' "$bin_dir"
        return 0
    fi

    case "$bin_dir" in
        */.local/bin) hinted_home="${bin_dir%/.local/bin}" ;;
        */.acfs/bin) hinted_home="${bin_dir%/.acfs/bin}" ;;
        */.bun/bin) hinted_home="${bin_dir%/.bun/bin}" ;;
        */.cargo/bin) hinted_home="${bin_dir%/.cargo/bin}" ;;
        */.atuin/bin) hinted_home="${bin_dir%/.atuin/bin}" ;;
        */go/bin) hinted_home="${bin_dir%/go/bin}" ;;
        */google-cloud-sdk/bin) hinted_home="${bin_dir%/google-cloud-sdk/bin}" ;;
    esac
    hinted_home="$(preflight_sanitize_abs_nonroot_path "$hinted_home" 2>/dev/null || true)"
    if [[ -n "$hinted_home" ]] && [[ -n "$base_home" ]] && [[ "$hinted_home" != "$base_home" ]]; then
        return 1
    fi

    while IFS= read -r passwd_line; do
        IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_line"
        passwd_home="$(preflight_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(preflight_getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

resolve_home_dir() {
    local user="$1"
    local expected_home="${2:-}"
    local current_user=""
    local home=""
    local passwd_entry=""

    if [[ -z "$user" ]]; then
        return 1
    fi
    expected_home="$(preflight_sanitize_abs_nonroot_path "$expected_home" 2>/dev/null || true)"

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    passwd_entry="$(preflight_getent_passwd_entry "$user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        IFS=: read -r _ _ _ _ _ home _ <<< "$passwd_entry"
    fi

    home="$(preflight_sanitize_abs_nonroot_path "$home" 2>/dev/null || true)"
    if [[ -n "$home" ]]; then
        printf '%s\n' "$home"
        return 0
    fi

    current_user="$(resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "$user" ]]; then
        home="$(preflight_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
        if [[ -n "$home" ]] && { [[ -z "$expected_home" ]] || [[ "$home" == "$expected_home" ]]; }; then
            printf '%s\n' "$home"
            return 0
        fi
    fi

    return 1
}

resolve_current_home() {
    local current_user=""
    local home_candidate=""
    local resolved_home=""

    home_candidate="$(preflight_sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"

    current_user="$(resolve_current_user 2>/dev/null || true)"
    if [[ -n "$current_user" ]]; then
        resolved_home="$(resolve_home_dir "$current_user" 2>/dev/null || true)"
        if [[ -n "$resolved_home" ]]; then
            printf '%s\n' "$resolved_home"
            return 0
        fi
    fi

    [[ -n "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

resolve_install_target_home() {
    local target_home=""
    local target_user_raw="${TARGET_USER:-}"
    local target_user="${TARGET_USER:-ubuntu}"
    local current_user=""
    local explicit_target_home=""

    explicit_target_home="$(preflight_sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"

    if [[ -n "$target_user_raw" ]] && ! preflight_is_valid_username "$target_user"; then
        return 1
    fi

    if [[ -n "$target_user_raw" ]]; then
        target_home="$(resolve_home_dir "$target_user" "$explicit_target_home" 2>/dev/null || true)"
        if [[ -n "$target_home" ]]; then
            printf '%s\n' "$target_home"
            return 0
        fi

        current_user="$(resolve_current_user 2>/dev/null || true)"
        if [[ -n "$current_user" ]] && [[ "$target_user" == "$current_user" ]] && [[ -n "$explicit_target_home" ]]; then
            printf '%s\n' "$explicit_target_home"
            return 0
        fi

        return 1
    fi

    if [[ -n "$explicit_target_home" ]]; then
        printf '%s\n' "$explicit_target_home"
        return 0
    fi

    if [[ "$EUID" -eq 0 ]]; then
        preflight_is_valid_username "$target_user" || return 1
        target_home="$(resolve_home_dir "$target_user" 2>/dev/null || true)"
        if [[ -n "$target_home" ]]; then
            printf '%s\n' "$target_home"
            return 0
        fi

        return 1
    fi

    current_user="$(resolve_current_user 2>/dev/null || true)"
    if [[ -n "$target_user_raw" ]] && [[ -n "$current_user" ]] && [[ "$target_user" != "$current_user" ]]; then
        target_home="$(resolve_home_dir "$target_user" 2>/dev/null || true)"
        if [[ -n "$target_home" ]]; then
            printf '%s\n' "$target_home"
            return 0
        fi

        return 1
    fi

    target_home="$(resolve_current_home 2>/dev/null || true)"
    if [[ -n "$target_home" ]]; then
        printf '%s\n' "$target_home"
        return 0
    fi

    return 1
}
preflight_binary_path() {
    local name="${1:-}"
    local base_home=""
    local primary_bin_dir=""
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..) return 1 ;;
        *[!A-Za-z0-9._+-]*) return 1 ;;
    esac

    base_home="$(resolve_install_target_home 2>/dev/null || true)"

    if [[ -n "$base_home" ]]; then
        primary_bin_dir="$(preflight_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$base_home" 2>/dev/null || true)"
        [[ -n "$primary_bin_dir" ]] || primary_bin_dir="$base_home/.local/bin"
        for candidate in \
            "$primary_bin_dir/$name" \
            "$base_home/.local/bin/$name" \
            "$base_home/.acfs/bin/$name" \
            "$base_home/.bun/bin/$name" \
            "$base_home/.cargo/bin/$name" \
            "$base_home/.atuin/bin/$name" \
            "$base_home/go/bin/$name" \
            "$base_home/bin/$name"; do
            [[ -x "$candidate" ]] || continue
            printf '%s\n' "$candidate"
            return 0
        done
    fi

    for candidate in \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/snap/bin/$name"; do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}
preflight_binary_exists() {
    local resolved=""
    resolved="$(preflight_binary_path "$1" 2>/dev/null || true)"
    [[ -n "$resolved" ]]
}

preflight_script_dir() {
    local source_path="${BASH_SOURCE[0]:-}"

    [[ -n "$source_path" ]] || return 1
    [[ -f "$source_path" ]] || return 1
    cd "$(dirname "$source_path")" && pwd -P
}

preflight_find_checksums_file() {
    local candidates=()
    local script_dir=""
    local candidate=""

    if [[ -n "${ACFS_PREFLIGHT_CHECKSUMS_FILE:-}" ]]; then
        candidates+=("$ACFS_PREFLIGHT_CHECKSUMS_FILE")
    fi

    if [[ -n "${ACFS_CHECKSUMS_YAML:-}" ]]; then
        candidates+=("$ACFS_CHECKSUMS_YAML")
    fi

    script_dir="$(preflight_script_dir 2>/dev/null || true)"
    if [[ -n "$script_dir" ]]; then
        candidates+=("$script_dir/../checksums.yaml")
        candidates+=("$script_dir/checksums.yaml")
    fi

    candidates+=("./checksums.yaml")

    if [[ -n "${HOME:-}" ]]; then
        candidates+=("$HOME/.acfs/checksums.yaml")
    fi

    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" ]] || continue
        [[ -f "$candidate" && -r "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

preflight_checksum_field() {
    local checksums_file="$1"
    local tool="$2"
    local field="$3"

    awk -v tool="$tool" -v field="$field" '
        $0 == "  " tool ":" {
            in_tool = 1
            next
        }
        in_tool && $0 ~ /^  [^[:space:]][^:]*:/ {
            exit
        }
        in_tool && $0 ~ "^[[:space:]]+" field ":" {
            sub("^[[:space:]]+" field ":[[:space:]]*", "", $0)
            gsub(/^"/, "", $0)
            gsub(/"$/, "", $0)
            print
            exit
        }
    ' "$checksums_file"
}

preflight_network_skip_detail() {
    printf '%s\n' "offline mode requested; live reachability was not verified. Retry with --network=check when online. If install later fails, run: acfs support-bundle"
}

preflight_describe_curl_result() {
    local curl_exit="$1"
    local http_status="$2"
    local target="$3"

    case "$curl_exit" in
        0)
            printf 'HTTP %s from %s' "$http_status" "$target"
            ;;
        6)
            printf 'DNS lookup failed for %s' "$target"
            ;;
        7)
            printf 'connection failed for %s' "$target"
            ;;
        28)
            printf 'timeout contacting %s' "$target"
            ;;
        *)
            if [[ "$http_status" != "000" ]]; then
                printf 'HTTP %s from %s' "$http_status" "$target"
            else
                printf 'curl exit %s for %s' "$curl_exit" "$target"
            fi
            ;;
    esac
}

# ============================================================
# Argument Parsing
# ============================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet|-q)
            QUIET=true
            shift
            ;;
        --json)
            OUTPUT_FORMAT="json"
            MACHINE_OUTPUT=true
            shift
            ;;
        --format)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --format requires an argument (json|toon)" >&2
                exit 1
            fi
            case "$2" in
                json|toon)
                    OUTPUT_FORMAT="$2"
                    MACHINE_OUTPUT=true
                    ;;
                *)
                    echo "Error: invalid --format '$2' (expected json|toon)" >&2
                    exit 1
                    ;;
            esac
            shift 2
            ;;
        --network=check|--network=skip)
            NETWORK_MODE="${1#--network=}"
            shift
            ;;
        --network)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --network requires an argument (check|skip)" >&2
                exit 1
            fi
            NETWORK_MODE="$2"
            shift 2
            ;;
        --offline)
            NETWORK_MODE="skip"
            shift
            ;;
        --checksum-candidate=*)
            CHECKSUM_CANDIDATE_FILE="${1#--checksum-candidate=}"
            shift
            ;;
        --checksum-candidate)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --checksum-candidate requires a file path" >&2
                exit 1
            fi
            CHECKSUM_CANDIDATE_FILE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--quiet] [--json|--format json|toon] [--network check|skip]"
            echo ""
            echo "Options:"
            echo "  --quiet, -q           Suppress output, exit code only"
            echo "  --json                Output results as JSON"
            echo "  --format              Output results as json or toon"
            echo "  --network             Network checks: check (default) or skip"
            echo "  --offline             Alias for --network skip"
            echo "  --checksum-candidate  Compare a generated checksums.yaml candidate"
            echo "  --help, -h            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

case "$NETWORK_MODE" in
    check|skip)
        ;;
    *)
        echo "Error: invalid --network '$NETWORK_MODE' (expected check|skip)" >&2
        exit 1
        ;;
esac

# ============================================================
# Output Functions
# ============================================================

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}" # escape backslashes
    s="${s//\"/\\\"}" # escape quotes
    s="${s//$'\n'/\\n}" # escape newlines
    s="${s//$'\r'/\\r}" # escape CR
    s="${s//$'\t'/\\t}" # escape tabs
    printf '%s' "$s"
}

log_check() {
    local status="$1"
    local message="$2"
    local detail="${3:-}"

    if [[ "$MACHINE_OUTPUT" == "true" ]]; then
        # Escape quotes in message and detail for JSON
        message="$(json_escape "$message")"
        detail="$(json_escape "$detail")"
        RESULTS+=("{\"status\":\"$status\",\"message\":\"$message\",\"detail\":\"$detail\"}")
    elif [[ "$QUIET" != "true" ]]; then
        case "$status" in
            pass)
                echo -e "${CHECK} ${message}"
                [[ -n "$detail" ]] && echo -e "    ${GRAY}${detail}${NC}" || true
                ;;
            warn)
                echo -e "${WARN} ${YELLOW}${message}${NC}"
                [[ -n "$detail" ]] && echo -e "    ${GRAY}${detail}${NC}" || true
                ;;
            fail)
                echo -e "${FAIL} ${RED}${message}${NC}"
                [[ -n "$detail" ]] && echo -e "    ${GRAY}${detail}${NC}" || true
                ;;
        esac
    fi
}

pass() {
    log_check "pass" "$1" "${2:-}"
}

warn() {
    ((WARNINGS++)) || true
    log_check "warn" "$1" "${2:-}"
}

fail() {
    ((ERRORS++)) || true
    log_check "fail" "$1" "${2:-}"
}

emit_json_summary() {
    echo "{"
    echo "  \"errors\": $ERRORS,"
    echo "  \"warnings\": $WARNINGS,"
    echo "  \"checks\": ["
    local first=true
    for result in "${RESULTS[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo -n "    $result"
    done
    echo ""
    echo "  ]"
    echo "}"
}

# ============================================================
# System Checks
# ============================================================

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        fail "Not a Linux system" "ACFS requires Ubuntu Linux"
        return
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    local pretty_name="${PRETTY_NAME:-${ID:-unknown}}"

    local id_like="${ID_LIKE:-}"
    if [[ "${ID:-}" == "arch" ]] || [[ "${ID:-}" == "omarchy" ]] || [[ " $id_like " == *" arch "* ]]; then
        pass "Operating System: ${pretty_name} (Arch family)"
        return
    elif [[ "${ID:-}" != "ubuntu" ]]; then
        fail "Operating System: ${pretty_name}" "ACFS supports Ubuntu 22.04+ or Arch Linux"
        return
    fi

    local version="${VERSION_ID:-0}"
    local major="${version%%.*}"
    if (( major >= 24 )); then
        pass "Operating System: Ubuntu ${VERSION_ID}"
    elif (( major >= 22 )); then
        pass "Operating System: Ubuntu ${VERSION_ID}" "22.04+ supported, 24.04+ recommended"
    else
        fail "Operating System: Ubuntu ${VERSION_ID}" "ACFS supports Ubuntu 22.04+ only. Upgrade Ubuntu or provision a newer VPS image."
    fi
}

check_architecture() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64)
            pass "Architecture: x86_64 (AMD64)"
            ;;
        aarch64|arm64)
            pass "Architecture: ARM64"
            ;;
        *)
            fail "Unsupported architecture: $arch" "ACFS requires x86_64 or ARM64"
            ;;
    esac
}

check_memory() {
    if [[ ! -f /proc/meminfo ]]; then
        warn "Cannot check memory" "/proc/meminfo not available"
        return
    fi

    local mem_kb
    mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    local mem_gb=$((mem_kb / 1024 / 1024))

    if (( mem_gb >= 8 )); then
        pass "Memory: ${mem_gb}GB"
    elif (( mem_gb >= 4 )); then
        warn "Memory: ${mem_gb}GB" "8GB+ recommended for running multiple agents"
    else
        warn "Memory: ${mem_gb}GB" "Low memory may cause issues, 4GB minimum recommended"
    fi
}

check_disk() {
    local target_dir
    target_dir="$(resolve_install_target_home 2>/dev/null || true)"
    if [[ -z "$target_dir" ]]; then
        warn "Cannot determine disk space" "Unable to resolve installation target home"
        return
    fi

    # Walk up to the nearest existing ancestor directory, since the target
    # may not have been created yet (e.g. /home/newuser on a fresh VPS).
    local check_path="$target_dir"
    while [[ ! -d "$check_path" ]] && [[ "$check_path" != "/" ]]; do
        check_path="$(dirname "$check_path")"
    done

    # Capture df output once to avoid redundant subprocess and TOCTOU inconsistency
    local df_line
    df_line=$(df -k -P "$check_path" 2>/dev/null | tail -n 1)

    local free_kb
    free_kb=$(awk '{print $4}' <<< "$df_line")

    # Handle non-numeric or empty values
    if [[ -z "$free_kb" ]] || ! [[ "$free_kb" =~ ^[0-9]+$ ]]; then
        warn "Cannot determine disk space" "df command returned unexpected output"
        return
    fi

    local free_gb=$((free_kb / 1024 / 1024))
    # Fields 1-5 are fixed (Filesystem, 1K-blocks, Used, Available, Use%);
    # field 6+ is Mounted-on which may contain spaces, so print everything from field 6 onward
    local mount_point
    mount_point=$(awk '{for(i=6;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""}' <<< "$df_line")
    local detail_suffix=""
    if [[ -n "$mount_point" ]] && [[ "$mount_point" != "/" ]]; then
        detail_suffix=" on ${mount_point}"
    fi

    if (( free_gb >= 40 )); then
        pass "Disk Space: ${free_gb}GB free${detail_suffix}"
    elif (( free_gb >= 20 )); then
        pass "Disk Space: ${free_gb}GB free${detail_suffix}" "40GB+ recommended for large projects"
    else
        fail "Disk Space: ${free_gb}GB free${detail_suffix}" "Need at least 20GB free (40GB+ recommended)"
    fi
}

# ============================================================
# CPU Check
# ============================================================

check_cpu() {
    local cpu_count
    if [[ -f /proc/cpuinfo ]]; then
        cpu_count=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null) || cpu_count=1
    elif command -v nproc &>/dev/null; then
        cpu_count=$(nproc)
    else
        warn "Cannot determine CPU count" "/proc/cpuinfo not available"
        return
    fi

    if (( cpu_count >= 4 )); then
        pass "CPU: ${cpu_count} cores"
    elif (( cpu_count >= 2 )); then
        warn "CPU: ${cpu_count} cores" "4+ cores recommended for running multiple agents"
    else
        warn "CPU: ${cpu_count} core(s)" "Low CPU count may cause issues with parallel builds"
    fi
}

# ============================================================
# Network Checks
# ============================================================

check_verified_installers_cache() {
    local checksums_file=""
    local tool=""
    local url=""
    local sha256=""
    local present=()
    local missing=()
    local critical_tools=(
        bun
        uv
        rust
        claude
        caam
        rch
    )

    checksums_file="$(preflight_find_checksums_file 2>/dev/null || true)"
    if [[ -z "$checksums_file" ]]; then
        warn "Offline/cache: checksums.yaml unavailable" "verified installers fail closed without checksums.yaml; use a complete ACFS checkout or rerun with network. If install fails, run: acfs support-bundle"
        return
    fi

    for tool in "${critical_tools[@]}"; do
        url="$(preflight_checksum_field "$checksums_file" "$tool" url 2>/dev/null || true)"
        sha256="$(preflight_checksum_field "$checksums_file" "$tool" sha256 2>/dev/null || true)"
        if [[ -n "$url" && "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
            present+=("$tool")
        else
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        pass "Offline/cache: verified installer checksums available" "cached checksums.yaml: $checksums_file; entries: ${present[*]}"
    else
        warn "Offline/cache: verified installer checksums incomplete" "missing or invalid entries: ${missing[*]}; update ACFS/checksums.yaml before relying on verified installers"
    fi
}

check_checksum_candidate_file() {
    local checksums_file=""
    local current_body=""
    local candidate_body=""

    [[ -n "$CHECKSUM_CANDIDATE_FILE" ]] || return 0

    if [[ ! -r "$CHECKSUM_CANDIDATE_FILE" ]]; then
        warn "Verified installer checksum candidate unreadable" "$CHECKSUM_CANDIDATE_FILE"
        return
    fi

    checksums_file="$(preflight_find_checksums_file 2>/dev/null || true)"
    if [[ -z "$checksums_file" ]]; then
        warn "Verified installer checksum candidate not compared" "local checksums.yaml unavailable"
        return
    fi

    if cmp -s "$checksums_file" "$CHECKSUM_CANDIDATE_FILE"; then
        pass "Verified installer checksum candidate matches" "$CHECKSUM_CANDIDATE_FILE"
        return
    fi

    current_body="$(tail -n +2 "$checksums_file" 2>/dev/null || true)"
    candidate_body="$(tail -n +2 "$CHECKSUM_CANDIDATE_FILE" 2>/dev/null || true)"
    if [[ "$current_body" == "$candidate_body" ]]; then
        pass "Verified installer checksum candidate header-only diff" "only the generated timestamp differs; leave checksums.yaml unchanged"
    else
        warn "Verified installer checksum candidate differs" "review the diff before release or install support; ACFS will not bypass stored checksums. If unsure, run: acfs support-bundle"
    fi
}

check_dns() {
    if [[ "$NETWORK_MODE" == "skip" ]]; then
        warn "DNS: resolution checks skipped" "$(preflight_network_skip_detail)"
        return
    fi

    # Test DNS resolution before HTTP checks
    local test_hosts=(
        "github.com"
        "raw.githubusercontent.com"
    )
    # Only probe the distro mirror that will actually be used.
    if command -v pacman &>/dev/null && ! command -v apt-get &>/dev/null; then
        test_hosts+=("archlinux.org")
    else
        test_hosts+=("archive.ubuntu.com")
    fi

    local dns_ok=true
    local failed_hosts=()

    for host in "${test_hosts[@]}"; do
        # Try multiple DNS resolution methods
        if command -v host &>/dev/null; then
            if ! host "$host" >/dev/null 2>&1; then
                dns_ok=false
                failed_hosts+=("$host")
            fi
        elif command -v dig &>/dev/null; then
            if ! dig +short "$host" >/dev/null 2>&1; then
                dns_ok=false
                failed_hosts+=("$host")
            fi
        elif command -v getent &>/dev/null; then
            if ! getent hosts "$host" >/dev/null 2>&1; then
                dns_ok=false
                failed_hosts+=("$host")
            fi
        else
            # Fallback to ping (unreliable but better than nothing)
            if ! ping -c 1 -W 5 "$host" >/dev/null 2>&1; then
                dns_ok=false
                failed_hosts+=("$host")
            fi
        fi
    done

    if [[ "$dns_ok" == "true" ]]; then
        pass "DNS: All hosts resolved"
    else
        for host in "${failed_hosts[@]}"; do
            fail "DNS: Cannot resolve $host" "Check /etc/resolv.conf or network configuration"
        done
    fi
}

check_network_basic() {
    if [[ "$NETWORK_MODE" == "skip" ]]; then
        warn "Network: github.com reachability skipped" "$(preflight_network_skip_detail)"
        return
    fi

    if ! command -v curl &>/dev/null; then
        warn "curl not installed" "Network checks skipped; curl will be installed"
        return
    fi

    # Test basic connectivity to GitHub (critical)
    local http_status=""
    local curl_exit=0
    http_status=$(curl -sL --max-time 10 --connect-timeout 5 -o /dev/null -w "%{http_code}" https://github.com 2>/dev/null) || curl_exit=$?
    [[ "$http_status" =~ ^[0-9]+$ ]] || http_status="000"

    if [[ "$curl_exit" -eq 0 && "$http_status" -ge 200 && "$http_status" -lt 400 ]]; then
        pass "Network: github.com reachable"
    else
        fail "Network: Cannot reach github.com" "$(preflight_describe_curl_result "$curl_exit" "$http_status" "github.com"); check network/firewall settings, then retry with --network=check. If it persists, run: acfs support-bundle"
        return
    fi
}

check_network_installers() {
    if [[ "$NETWORK_MODE" == "skip" ]]; then
        warn "Network: installer URL checks skipped" "$(preflight_network_skip_detail)"
        return
    fi

    if ! command -v curl &>/dev/null; then
        return
    fi

    local checksums_file=""
    local url=""
    local tool=""
    local name=""
    local critical_targets=(
        "bun:Bun installer"
        "uv:UV/Python installer"
        "rust:Rust installer"
        "claude:Claude Code installer"
        "caam:CAAM installer"
        "rch:RCH installer"
    )
    local urls=()

    checksums_file="$(preflight_find_checksums_file 2>/dev/null || true)"
    if [[ -n "$checksums_file" ]]; then
        for entry in "${critical_targets[@]}"; do
            tool="${entry%%:*}"
            name="${entry##*:}"
            url="$(preflight_checksum_field "$checksums_file" "$tool" url 2>/dev/null || true)"
            [[ -n "$url" ]] || continue
            urls+=("$url:$name")
        done
    fi

    if [[ ${#urls[@]} -eq 0 ]]; then
        # Fallback for curl|bash preflight where checksums.yaml is not local.
        urls=(
            "https://bun.sh/install:Bun installer"
            "https://astral.sh/uv/install.sh:UV/Python installer"
            "https://sh.rustup.rs:Rust installer"
        )
    fi

    urls+=("https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/README.md:ACFS raw content")

    local all_ok=true
    local failed_urls=()
    local failure_details=()

    for entry in "${urls[@]}"; do
        # Use single % to remove shortest match from end (preserves https://)
        url="${entry%:*}"
        name="${entry##*:}"

        # Simple check: follow redirects, get HTTP status, 15s timeout
        # We just need to verify the URL is reachable, not download the content
        local http_status
        local curl_exit=0
        http_status=$(curl -sL --max-time 15 --connect-timeout 10 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null) || curl_exit=$?

        # Ensure http_status is a valid number (default to 000 if empty or invalid)
        [[ "$http_status" =~ ^[0-9]+$ ]] || http_status="000"

        if [[ "$curl_exit" -eq 0 && "$http_status" -ge 200 && "$http_status" -lt 400 ]]; then
            : # Success
        else
            all_ok=false
            failed_urls+=("$name")
            failure_details+=("$(preflight_describe_curl_result "$curl_exit" "$http_status" "$url")")
        fi
    done

    if [[ "$all_ok" == "true" ]]; then
        pass "Network: All installer URLs reachable"
    else
        local i=0
        for name in "${failed_urls[@]}"; do
            warn "Network: Cannot reach $name" "${failure_details[$i]}; retry later. ACFS will keep checksum verification enabled and will not use unverified fallbacks."
            ((i++)) || true
        done
    fi
}

# ============================================================
# APT Checks
# ============================================================

check_apt_mirrors() {
    if [[ "$NETWORK_MODE" == "skip" ]]; then
        warn "APT mirror check skipped" "$(preflight_network_skip_detail)"
        return
    fi

    # Only relevant on Debian/Ubuntu systems
    if ! command -v apt-get &>/dev/null; then
        return
    fi

    if ! command -v curl &>/dev/null; then
        return
    fi

    # Get the primary Ubuntu mirror from sources.list or DEB822 format
    local mirror_url=""

    # Traditional sources.list format
    if [[ -f /etc/apt/sources.list ]]; then
        mirror_url=$(grep -E '^deb\s+http' /etc/apt/sources.list 2>/dev/null | head -1 | awk '{print $2}' | sed 's|/$||' || true)
    fi

    # If no mirror found, check sources.list.d for traditional format
    if [[ -z "$mirror_url" ]] && [[ -d /etc/apt/sources.list.d ]]; then
        mirror_url=$(grep -rhE '^deb\s+http' /etc/apt/sources.list.d/*.list 2>/dev/null | head -1 | awk '{print $2}' | sed 's|/$||' || true)
    fi

    # DEB822 format (Ubuntu 24.04+): check *.sources files
    if [[ -z "$mirror_url" ]] && [[ -d /etc/apt/sources.list.d ]]; then
        # DEB822 format has "URIs:" line
        mirror_url=$(grep -rhE '^URIs:\s*http' /etc/apt/sources.list.d/*.sources 2>/dev/null | head -1 | sed 's/^URIs:\s*//' | awk '{print $1}' | sed 's|/$||' || true)
    fi

    # Default to archive.ubuntu.com if nothing found
    if [[ -z "$mirror_url" ]]; then
        mirror_url="http://archive.ubuntu.com/ubuntu"
    fi

    # Test mirror reachability
    local http_status
    http_status=$(curl -sL --max-time 10 --connect-timeout 5 -o /dev/null -w "%{http_code}" "$mirror_url/dists/" 2>/dev/null) || http_status="000"

    if [[ "$http_status" -ge 200 && "$http_status" -lt 400 ]]; then
        pass "APT mirror reachable" "${mirror_url##http*://}"
    else
        warn "APT mirror slow or unreachable" "Mirror: $mirror_url; Check /etc/apt/sources.list"
    fi
}

check_apt_lock() {
    # Only relevant on Debian/Ubuntu systems with apt
    local apt_get_bin=""
    apt_get_bin="$(preflight_system_binary_path apt-get 2>/dev/null || true)"
    if [[ -z "$apt_get_bin" ]]; then
        return
    fi

    # Check for dpkg lock
    if [[ -f /var/lib/dpkg/lock-frontend ]]; then
        local lock_held=false
        local sudo_bin=""
        local fuser_bin=""
        local lsof_bin=""
        sudo_bin="$(preflight_system_binary_path sudo 2>/dev/null || true)"
        fuser_bin="$(preflight_system_binary_path fuser 2>/dev/null || true)"
        lsof_bin="$(preflight_system_binary_path lsof 2>/dev/null || true)"

        if [[ -n "$fuser_bin" ]]; then
            if "$fuser_bin" /var/lib/dpkg/lock-frontend &>/dev/null; then
                lock_held=true
            elif [[ -n "$sudo_bin" ]] && "$sudo_bin" -n "$fuser_bin" /var/lib/dpkg/lock-frontend &>/dev/null; then
                lock_held=true
            fi
        fi

        if [[ "$lock_held" != "true" && -n "$lsof_bin" ]]; then
            if "$lsof_bin" /var/lib/dpkg/lock-frontend &>/dev/null; then
                lock_held=true
            elif [[ -n "$sudo_bin" ]] && "$sudo_bin" -n "$lsof_bin" /var/lib/dpkg/lock-frontend &>/dev/null; then
                lock_held=true
            fi
        fi

        if [[ "$lock_held" == "true" ]]; then
            fail "APT is locked by another process" "Wait for other apt operations to finish, then rerun preflight. If it stays locked, reboot and retry."
            return
        fi
    fi

    # Check for active package manager processes
    # Use exact process names to avoid false positives from unrelated commands.
    local pgrep_bin=""
    pgrep_bin="$(preflight_system_binary_path pgrep 2>/dev/null || true)"
    if [[ -n "$pgrep_bin" ]]; then
        if "$pgrep_bin" -x apt >/dev/null 2>&1 || \
           "$pgrep_bin" -x apt-get >/dev/null 2>&1 || \
           "$pgrep_bin" -x dpkg >/dev/null 2>&1 || \
           "$pgrep_bin" -x apt.systemd.daily >/dev/null 2>&1; then
            warn "APT process running" "Another package operation in progress"
            return
        fi

        # Check for unattended-upgrades
        if "$pgrep_bin" -f "unattended-upgr" >/dev/null 2>&1; then
            warn "unattended-upgrades running" "May cause apt conflicts; consider: sudo systemctl stop unattended-upgrades"
            return
        fi
    fi

    pass "APT: No locks detected"
}

# ============================================================
# User Environment Checks
# ============================================================

check_user() {
    if [[ "$EUID" -eq 0 ]]; then
        local target_user="${TARGET_USER:-ubuntu}"
        warn "Running as root" "ACFS will create and install for '${target_user}' user"
    else
        local current_user="$(resolve_current_user 2>/dev/null || printf unknown)"
        pass "User: $current_user"
    fi

    if [[ -z "${HOME:-}" ]]; then
        fail "HOME not set" "HOME environment variable is required"
        return
    fi

    if [[ ! -d "$HOME" ]]; then
        fail "HOME directory does not exist" "$HOME not found"
        return
    fi

    if [[ ! -w "$HOME" ]]; then
        fail "HOME not writable" "Cannot write to $HOME"
        return
    fi
}

check_shell() {
    local shell
    shell=$(basename "${SHELL:-/bin/sh}")

    case "$shell" in
        bash|zsh)
            pass "Shell: $shell"
            ;;
        *)
            warn "Shell: $shell" "bash or zsh recommended (zsh will be installed)"
            ;;
    esac
}

check_sudo() {
    local sudo_bin=""
    sudo_bin="$(preflight_system_binary_path sudo 2>/dev/null || true)"
    if [[ -z "$sudo_bin" ]]; then
        fail "sudo not installed" "sudo is required for system package installation"
        return
    fi

    # Check if user can sudo
    if [[ "$EUID" -eq 0 ]]; then
        pass "Privileges: Running as root"
    elif "$sudo_bin" -n true 2>/dev/null; then
        pass "Privileges: Passwordless sudo available"
    else
        pass "Privileges: sudo available" "Password may be required during install"
    fi
}

# ============================================================
# Conflict Detection
# ============================================================

check_conflicts() {
    local conflicts_found=false
    local user_home=""

    user_home="$(resolve_install_target_home 2>/dev/null || true)"
    if [[ -z "$user_home" ]]; then
        warn "Conflict checks skipped" "Unable to resolve installation target home"
        return
    fi

    # Check for nvm (may conflict with bun/mise)
    if [[ -d "${NVM_DIR:-$user_home/.nvm}" ]] || [[ -f "$user_home/.nvm/nvm.sh" ]]; then
        warn "nvm detected" "May conflict with bun; consider removing or deactivating"
        conflicts_found=true
    fi

    # Check for pyenv (may conflict with uv)
    if [[ -d "$user_home/.pyenv" ]] || command -v pyenv &>/dev/null; then
        warn "pyenv detected" "May conflict with uv; consider removing or deactivating"
        conflicts_found=true
    fi

    # Check for rbenv
    if [[ -d "$user_home/.rbenv" ]] || command -v rbenv &>/dev/null; then
        # Not a conflict, just FYI
        pass "rbenv detected" "Will coexist with ACFS tools"
    fi

    # Check for existing ACFS installation
    if [[ -d "$user_home/.acfs" ]]; then
        if [[ -f "$user_home/.acfs/state.json" ]]; then
            warn "Existing ACFS installation" "Previous install found; consider --resume or fresh start"
        else
            pass "ACFS directory exists" "Partial installation detected"
        fi
        conflicts_found=true
    fi

    # Check for existing tools that ACFS will install
    local existing_tools=()
    preflight_binary_exists bun && existing_tools+=("bun")
    preflight_binary_exists uv && existing_tools+=("uv")
    preflight_binary_exists claude && existing_tools+=("claude")
    preflight_binary_exists codex && existing_tools+=("codex")

    if [[ ${#existing_tools[@]} -gt 0 ]]; then
        pass "Existing tools: ${existing_tools[*]}" "Will be updated/skipped"
    fi

    if [[ "$conflicts_found" == "false" ]]; then
        pass "No conflicts detected"
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    if [[ "$QUIET" != "true" && "$MACHINE_OUTPUT" != "true" ]]; then
        echo -e "${BOLD}ACFS Pre-Flight Check${NC}"
        echo "====================="
        echo ""
    fi

    # Run all checks
    check_os
    check_architecture
    check_cpu
    check_memory
    check_disk

    [[ "$QUIET" != "true" && "$MACHINE_OUTPUT" != "true" ]] && echo ""

    check_verified_installers_cache
    check_checksum_candidate_file
    check_dns
    check_network_basic
    check_network_installers

    [[ "$QUIET" != "true" && "$MACHINE_OUTPUT" != "true" ]] && echo ""

    check_apt_mirrors
    check_apt_lock

    [[ "$QUIET" != "true" && "$MACHINE_OUTPUT" != "true" ]] && echo ""

    check_user
    check_shell
    check_sudo

    [[ "$QUIET" != "true" && "$MACHINE_OUTPUT" != "true" ]] && echo ""

    check_conflicts

    # Summary
    if [[ "$MACHINE_OUTPUT" == "true" ]]; then
        if [[ "$OUTPUT_FORMAT" == "toon" ]]; then
            if ! command -v tru >/dev/null 2>&1; then
                echo "Warning: --format toon requested but 'tru' not found; using JSON" >&2
                emit_json_summary
            else
                # Capture both stages first: if tru emits a partial document
                # before failing, do not mix that prefix with fallback JSON.
                local toon_json=""
                toon_json="$(emit_json_summary)"
                local toon_output=""
                if toon_output="$(printf '%s\n' "$toon_json" | tru --encode)"; then
                    printf '%s\n' "$toon_output"
                else
                    printf '%s\n' "$toon_json"
                fi
            fi
        else
            emit_json_summary
        fi
    elif [[ "$QUIET" != "true" ]]; then
        echo ""
        echo "====================="
        if (( ERRORS > 0 )); then
            echo -e "${RED}${BOLD}Result: $ERRORS error(s), $WARNINGS warning(s)${NC}"
            echo ""
            echo -e "${RED}Critical issues must be resolved before installation.${NC}"
        elif (( WARNINGS > 0 )); then
            echo -e "${YELLOW}${BOLD}Result: $WARNINGS warning(s)${NC}"
            echo ""
            echo -e "${GREEN}Pre-flight checks passed. Warnings are informational.${NC}"
        else
            echo -e "${GREEN}${BOLD}Result: All checks passed!${NC}"
            echo ""
            echo -e "${GREEN}System is ready for ACFS installation.${NC}"
        fi
    fi

    # Exit with error if critical failures
    if (( ERRORS > 0 )); then
        exit 1
    fi

    exit 0
}

main "$@"
