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

_acfs_security_source="${BASH_SOURCE[0]}"
_acfs_security_source_dir="."
case "$_acfs_security_source" in
    */*) _acfs_security_source_dir="${_acfs_security_source%/*}" ;;
esac
SECURITY_SCRIPT_DIR="$(cd "$_acfs_security_source_dir" && pwd -P)"
unset _acfs_security_source _acfs_security_source_dir

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$SECURITY_SCRIPT_DIR/logging.sh" 2>/dev/null || true
fi

# Fallback logging if logging.sh was not sourced or failed to load
if ! declare -f log_success &>/dev/null; then
    log_success() { printf "OK: %s\n" "$1" >&2; }
    log_error()   { printf "ERROR: %s\n" "$1" >&2; }
    log_info()    { printf "INFO: %s\n" "$1" >&2; }
    log_warn()    { printf "WARN: %s\n" "$1" >&2; }
    log_step()    { printf "[%s] %s\n" "$1" "$2" >&2; }
    log_detail()  { printf "  %s\n" "$1" >&2; }
    log_fatal()   { printf "FATAL: %s\n" "$1" >&2; exit 1; }
fi

# Color aliases for backward compatibility (used by display functions below)
# Respects NO_COLOR standard via logging.sh's ACFS_* variables.
# Use ${var-default} (not ${var:-default}) to preserve empty strings.
# Related: bd-39ye
CYAN="${ACFS_BLUE-\033[0;36m}"
DIM="${ACFS_GRAY-\033[0;90m}"
NC="${ACFS_NC-\033[0m}"
RED="${ACFS_RED-\033[0;31m}"
GREEN="${ACFS_GREEN-\033[0;32m}"
YELLOW="${ACFS_YELLOW-\033[0;33m}"

# ============================================================
# Configuration
# ============================================================

ACFS_REPO_OWNER="${ACFS_REPO_OWNER:-Dicklesworthstone}"
ACFS_REPO_NAME="${ACFS_REPO_NAME:-agentic_coding_flywheel_setup}"
ACFS_CHECKSUMS_REF="${ACFS_CHECKSUMS_REF:-main}"

acfs_security_system_binary_path() {
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
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

acfs_security_curl_binary_path() {
    acfs_security_system_binary_path curl
}

acfs_security_required_binary_path() {
    local name="${1:-}"
    local path=""

    path="$(acfs_security_system_binary_path "$name" 2>/dev/null || true)"
    if [[ -z "$path" ]]; then
        log_error "No trusted $name binary available"
        return 127
    fi

    printf '%s\n' "$path"
}

acfs_security_hash_tool() {
    local sha256sum_bin=""
    local shasum_bin=""

    sha256sum_bin="$(acfs_security_system_binary_path sha256sum 2>/dev/null || true)"
    if [[ -n "$sha256sum_bin" ]]; then
        printf 'sha256sum:%s\n' "$sha256sum_bin"
        return 0
    fi

    shasum_bin="$(acfs_security_system_binary_path shasum 2>/dev/null || true)"
    if [[ -n "$shasum_bin" ]]; then
        printf 'shasum:%s\n' "$shasum_bin"
        return 0
    fi

    return 1
}

acfs_security_mktemp() {
    local mktemp_bin=""

    mktemp_bin="$(acfs_security_required_binary_path mktemp)" || return $?
    if [[ "$#" -gt 0 ]]; then
        "$mktemp_bin" "$@"
    else
        "$mktemp_bin"
    fi
}

acfs_security_cat_file() {
    local cat_bin=""
    local file="${1:-}"

    [[ -r "$file" ]] || {
        log_error "Cannot read file: $file"
        return 1
    }

    cat_bin="$(acfs_security_required_binary_path cat)" || return $?
    "$cat_bin" "$file"
}

acfs_security_mkdir_p() {
    local mkdir_bin=""
    local dir="${1:-}"

    [[ -n "$dir" ]] || return 1
    mkdir_bin="$(acfs_security_required_binary_path mkdir)" || return $?
    "$mkdir_bin" -p "$dir"
}

acfs_security_sort_lines() {
    local sort_bin=""

    sort_bin="$(acfs_security_required_binary_path sort)" || return $?
    "$sort_bin"
}

acfs_security_date() {
    local date_bin=""

    date_bin="$(acfs_security_required_binary_path date)" || return $?
    "$date_bin" "$@"
}

# Check if running in interactive mode
# Returns 0 if interactive, 1 if non-interactive
_acfs_is_interactive() {
    [[ "${ACFS_INTERACTIVE:-true}" == "true" ]] || return 1

    # Prefer /dev/tty so curl|bash (stdin is a pipe) can still prompt safely.
    if [[ -e /dev/tty ]] && (exec 3<>/dev/tty) 2>/dev/null; then
        return 0
    fi

    [[ -t 0 ]]
}

# curl defaults: enforce HTTPS (including redirects) when supported
ACFS_CURL_BIN=""
ACFS_CURL_BASE_ARGS=()

acfs_security_configure_curl() {
    local curl_help=""

    ACFS_CURL_BIN="$(acfs_security_curl_binary_path 2>/dev/null || true)"
    ACFS_CURL_BASE_ARGS=(--connect-timeout 30 --max-time 300 -fsSL)

    if [[ -n "$ACFS_CURL_BIN" ]] && curl_help="$("$ACFS_CURL_BIN" --help all 2>/dev/null)" && [[ "$curl_help" == *"--proto"* ]]; then
        ACFS_CURL_BASE_ARGS=(--proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 300 -fsSL)
    fi
}

acfs_security_configure_curl

acfs_curl() {
    if [[ -z "$ACFS_CURL_BIN" || ! -x "$ACFS_CURL_BIN" ]]; then
        acfs_security_configure_curl
        if [[ -z "$ACFS_CURL_BIN" || ! -x "$ACFS_CURL_BIN" ]]; then
            log_error "No trusted curl binary available"
            return 127
        fi
    fi

    "$ACFS_CURL_BIN" "${ACFS_CURL_BASE_ARGS[@]}" "$@"
}

# Automatic retries for transient network errors (fast total budget).
ACFS_CURL_RETRY_DELAYS=(0 5 15)

acfs_is_retryable_curl_exit_code() {
    local exit_code="${1:-0}"
    case "$exit_code" in
        6|7|28|35|52|56) return 0 ;; # DNS/connect/timeout/SSL/empty reply/recv error
        *) return 1 ;;
    esac
}

# Download URL to a file with retries.
# Arguments:
#   $1 - URL
#   $2 - Output path
#   $3 - Name (for logging)
# Returns: 0 on success, curl exit code on failure
#
# For GitHub URLs, uses github_fetch_with_backoff for rate limit handling.
# Related: bd-1lug
acfs_download_to_file() {
    local url="$1"
    local output_path="$2"
    local name="${3:-$url}"
    local output_dir="${output_path%/*}"

    if [[ "$output_dir" == "$output_path" ]]; then
        output_dir="."
    elif [[ -z "$output_dir" ]]; then
        output_dir="/"
    fi

    # Ensure parent dir exists
    acfs_security_mkdir_p "$output_dir" || return $?

    # Use GitHub-specific backoff for GitHub URLs (rate limit handling)
    if [[ "$url" == *"github.com"* || "$url" == *"githubusercontent.com"* ]]; then
        # Load github_api.sh if not already loaded
        if ! declare -f github_fetch_with_backoff &>/dev/null; then
            local github_lib="$SECURITY_SCRIPT_DIR/github_api.sh"
            if [[ -r "$github_lib" ]]; then
                # shellcheck source=github_api.sh
                source "$github_lib"
            fi
        fi

        # Use backoff if available, fallback to standard fetch
        if declare -f github_fetch_with_backoff &>/dev/null; then
            github_fetch_with_backoff "$url" "$output_path" "$name"
            return $?
        fi
    fi

    # Standard retry logic for non-GitHub URLs
    local max_attempts="${#ACFS_CURL_RETRY_DELAYS[@]}"
    if (( max_attempts == 0 )); then
        ACFS_CURL_RETRY_DELAYS=(0 5 15)
        max_attempts="${#ACFS_CURL_RETRY_DELAYS[@]}"
    fi

    local retries=$((max_attempts - 1))
    local attempt delay status=0

    for ((attempt=0; attempt<max_attempts; attempt++)); do
        delay="${ACFS_CURL_RETRY_DELAYS[$attempt]}"

        if (( attempt > 0 )); then
            log_info "Retry ${attempt}/${retries} for fetching ${name} (waiting ${delay}s)..."
            sleep "$delay"
        fi

        # Use -o to save to file directly
        if acfs_curl "$url" -o "$output_path"; then
            (( attempt > 0 )) && log_info "Succeeded on retry ${attempt} for fetching ${name}"
            return 0
        else
            status=$?
        fi

        if ! acfs_is_retryable_curl_exit_code "$status"; then
            return "$status"
        fi
    done

    log_error "Failed to download $name after $max_attempts attempts (exit code $status)"
    return 1
}

# Checksums file location.
# Prefer the repo-root checksums.yaml based on this script's location.
# Security: Always use absolute paths to prevent path traversal attacks.
DEFAULT_CHECKSUMS_FILE="$SECURITY_SCRIPT_DIR/../../checksums.yaml"

# Resolve to absolute path to prevent working directory manipulation
if [[ -r "$DEFAULT_CHECKSUMS_FILE" ]]; then
    # Use trusted realpath if available, otherwise use cd/pwd to get absolute path.
    _acfs_security_realpath_bin="$(acfs_security_system_binary_path realpath 2>/dev/null || true)"
    if [[ -n "$_acfs_security_realpath_bin" ]]; then
        DEFAULT_CHECKSUMS_FILE="$("$_acfs_security_realpath_bin" "$DEFAULT_CHECKSUMS_FILE")"
    else
        _acfs_security_checksums_dir="${DEFAULT_CHECKSUMS_FILE%/*}"
        _acfs_security_checksums_base="${DEFAULT_CHECKSUMS_FILE##*/}"
        DEFAULT_CHECKSUMS_FILE="$(cd "$_acfs_security_checksums_dir" && pwd -P)/$_acfs_security_checksums_base"
    fi
    unset _acfs_security_realpath_bin _acfs_security_checksums_dir _acfs_security_checksums_base
    CHECKSUMS_FILE="${CHECKSUMS_FILE:-$DEFAULT_CHECKSUMS_FILE}"
else
    # If default not found and CHECKSUMS_FILE not set, use absolute path to repo root
    # Never fall back to relative path as it could be manipulated
    if [[ -z "${CHECKSUMS_FILE:-}" ]]; then
        # Try to find checksums.yaml relative to ACFS_REPO_ROOT if available
        if [[ -n "${ACFS_REPO_ROOT:-}" && -r "${ACFS_REPO_ROOT}/checksums.yaml" ]]; then
            CHECKSUMS_FILE="${ACFS_REPO_ROOT}/checksums.yaml"
        else
            # No checksums file found - will be handled at verification time
            CHECKSUMS_FILE=""
        fi
    fi
fi

# Known installer URLs and their expected checksums
# Format: URL|SHA256 (computed from the install script content)
# These are reference checksums - actual scripts may change
declare -gA KNOWN_INSTALLERS=(
    [antigravity]="https://antigravity.google/cli/install.sh"
    [bun]="https://bun.sh/install"
    [claude]="https://claude.ai/install.sh"
    [uv]="https://astral.sh/uv/install.sh"
    [rust]="https://sh.rustup.rs"
    [nvm]="https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh"
    [ohmyzsh]="https://install.ohmyz.sh/"
    [opencode]="https://opencode.ai/install"
    [zoxide]="https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh"
    [atuin]="https://github.com/atuinsh/atuin/releases/latest/download/atuin-installer.sh"
    [ntm]="https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh"
    [mcp_agent_mail]="https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail_rust/refs/heads/main/install.sh"
    [ubs]="https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/main/install.sh"
    [bv]="https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh"
    [cass]="https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh"
    [cm]="https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh"
    [caam]="https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_account_manager/main/install.sh"
    [slb]="https://raw.githubusercontent.com/Dicklesworthstone/simultaneous_launch_button/main/scripts/install.sh"
    [dcg]="https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/main/install.sh"
    [ru]="https://raw.githubusercontent.com/Dicklesworthstone/repo_updater/main/install.sh"
    [apr]="https://raw.githubusercontent.com/Dicklesworthstone/automated_plan_reviser_pro/main/install.sh"
    [ms]="https://raw.githubusercontent.com/Dicklesworthstone/meta_skill/main/scripts/install.sh"
    [pt]="https://raw.githubusercontent.com/Dicklesworthstone/process_triage/main/install.sh"
    [srps]="https://raw.githubusercontent.com/Dicklesworthstone/system_resource_protection_script/main/install.sh"
    [xf]="https://raw.githubusercontent.com/Dicklesworthstone/xf/main/install.sh"
    [giil]="https://raw.githubusercontent.com/Dicklesworthstone/giil/main/install.sh"
    [csctf]="https://raw.githubusercontent.com/Dicklesworthstone/chat_shared_conversation_to_file/main/install.sh"
    [jfp]="https://jeffreysprompts.com/install-cli.sh"
    [br]="https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh"
    [brenner_bot]="https://raw.githubusercontent.com/Dicklesworthstone/brenner_bot/main/install.sh"
    [rch]="https://raw.githubusercontent.com/Dicklesworthstone/remote_compilation_helper/main/install.sh"
    [tru]="https://raw.githubusercontent.com/Dicklesworthstone/toon_rust/main/install.sh"
    [rano]="https://raw.githubusercontent.com/Dicklesworthstone/rano/main/install.sh"
    [mdwb]="https://raw.githubusercontent.com/Dicklesworthstone/markdown_web_browser/main/install.sh"
    [s2p]="https://raw.githubusercontent.com/Dicklesworthstone/source_to_prompt_tui/main/install.sh"
    [gemini_patch]="https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/fix-gemini-cli-ebadf-crash.sh"
    [fsfs]="https://raw.githubusercontent.com/Dicklesworthstone/frankensearch/refs/heads/main/install.sh"
    [sbh]="https://raw.githubusercontent.com/Dicklesworthstone/storage_ballast_helper/main/scripts/install.sh"
    [casr]="https://raw.githubusercontent.com/Dicklesworthstone/cross_agent_session_resumer/main/install.sh"
    [dsr]="https://raw.githubusercontent.com/Dicklesworthstone/doodlestein_self_releaser/main/install.sh"
    [asb]="https://raw.githubusercontent.com/Dicklesworthstone/agent_settings_backup_script/main/install.sh"
    [pcr]="https://raw.githubusercontent.com/Dicklesworthstone/post_compact_reminder/main/install-post-compact-reminder.sh"
)
declare -ga ACFS_SECURITY_REQUIRED_INSTALLERS=("${!KNOWN_INSTALLERS[@]}")

# ============================================================
# Checksum Verification Policy
# ============================================================
#
# ACFS fails closed on checksum mismatch: scripts are NOT executed unless the
# downloaded bytes match checksums.yaml exactly.

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
        log_error "Security Error: URL for '$name' is not HTTPS"
        printf "  URL: %s\n" "$url" >&2
        printf "  All installer URLs must use HTTPS.\n" >&2
        return 1
    fi
    return 0
}

# ============================================================
# Checksum Verification
# ============================================================

# Calculate SHA256 of a file
# Arguments:
#   $1 - File path
calculate_file_sha256() {
    local filepath="$1"
    local hash_tool=""
    local tool_name=""
    local tool_path=""
    local output=""
    local hash=""

    if [[ ! -r "$filepath" ]]; then
        log_error "Cannot read file for checksum: $filepath"
        return 1
    fi

    if ! hash_tool="$(acfs_security_hash_tool)"; then
        log_error "No SHA256 tool available"
        return 1
    fi

    tool_name="${hash_tool%%:*}"
    tool_path="${hash_tool#*:}"

    case "$tool_name" in
        sha256sum)
            output="$("$tool_path" "$filepath")" || return 1
            ;;
        shasum)
            output="$("$tool_path" -a 256 "$filepath")" || return 1
            ;;
        *)
            log_error "Unsupported SHA256 tool: $tool_name"
            return 1
            ;;
    esac

    read -r hash _ <<< "$output"
    [[ -n "$hash" ]] || return 1
    printf '%s\n' "$hash"
}

# Calculate SHA256 from stdin
# Usage: printf 'content' | calculate_sha256
calculate_sha256() {
    local hash_tool=""
    local tool_name=""
    local tool_path=""
    local output=""
    local hash=""

    if ! hash_tool="$(acfs_security_hash_tool)"; then
        log_error "No SHA256 tool available"
        return 1
    fi

    tool_name="${hash_tool%%:*}"
    tool_path="${hash_tool#*:}"

    case "$tool_name" in
        sha256sum)
            output="$("$tool_path")" || return 1
            ;;
        shasum)
            output="$("$tool_path" -a 256)" || return 1
            ;;
        *)
            log_error "Unsupported SHA256 tool: $tool_name"
            return 1
            ;;
    esac

    read -r hash _ <<< "$output"
    [[ -n "$hash" ]] || return 1
    printf '%s\n' "$hash"
}

_acfs_remove_temp_files() {
    local path
    local rm_bin=""

    rm_bin="$(acfs_security_system_binary_path rm 2>/dev/null || true)"
    [[ -n "$rm_bin" ]] || return 0

    for path in "$@"; do
        [[ -n "$path" ]] && "$rm_bin" -f -- "$path" 2>/dev/null || true
    done
}

acfs_security_file_size() {
    local file="${1:-}"
    local output=""
    local wc_bin=""

    [[ -r "$file" ]] || return 1
    wc_bin="$(acfs_security_required_binary_path wc)" || return $?
    output="$("$wc_bin" -c < "$file")" || return 1
    output="${output//[[:space:]]/}"
    [[ -n "$output" ]] || return 1
    printf '%s\n' "$output"
}

acfs_offline_pack_requested() {
    [[ -n "${ACFS_OFFLINE_PACK:-${ACFS_OFFLINE_ARTIFACT_PACK:-}}" ]]
}

acfs_offline_pack_fail_closed() {
    local mode="${ACFS_OFFLINE_NETWORK_MODE:-offline}"
    local required="${ACFS_OFFLINE_PACK_REQUIRED:-}"

    [[ "$mode" == "offline" || "$mode" == "disabled" || "$required" == "true" || "$required" == "1" ]]
}

acfs_offline_pack_error() {
    local code="$1"
    local name="$2"
    local detail="$3"

    log_error "offline_pack_refused code=$code tool=$name"
    printf "  Detail: %s\n" "$detail" >&2
}

acfs_offline_pack_jq_bin() {
    acfs_security_required_binary_path jq
}

acfs_offline_pack_current_arch() {
    local raw_arch=""
    local uname_bin=""

    uname_bin="$(acfs_security_required_binary_path uname)" || return $?
    raw_arch="$("$uname_bin" -m)" || return 1

    case "$raw_arch" in
        amd64|x64) printf 'x86_64\n' ;;
        arm64) printf 'aarch64\n' ;;
        *) printf '%s\n' "$raw_arch" ;;
    esac
}

acfs_offline_pack_current_manifest_file() {
    local manifest_file="${ACFS_MANIFEST_YAML:-}"
    local default_manifest="$SECURITY_SCRIPT_DIR/../../acfs.manifest.yaml"

    if [[ -n "$manifest_file" && -r "$manifest_file" ]]; then
        printf '%s\n' "$manifest_file"
        return 0
    fi
    if [[ -r "$default_manifest" ]]; then
        printf '%s\n' "$default_manifest"
        return 0
    fi

    return 1
}

acfs_offline_pack_locate() {
    local configured="${ACFS_OFFLINE_PACK:-${ACFS_OFFLINE_ARTIFACT_PACK:-}}"
    local name="$1"
    local pack_root=""

    if [[ -z "$configured" ]]; then
        acfs_offline_pack_error "pack_missing_manifest" "$name" "ACFS_OFFLINE_PACK is empty"
        return 1
    fi

    case "$configured" in
        /*) ;;
        *) configured="$PWD/$configured" ;;
    esac
    configured="${configured%/}"

    if [[ -d "$configured/acfs-offline-pack" ]]; then
        pack_root="$configured/acfs-offline-pack"
    else
        pack_root="$configured"
    fi

    if [[ ! -r "$pack_root/manifest.json" ]]; then
        acfs_offline_pack_error "pack_missing_manifest" "$name" "manifest.json is absent under $pack_root"
        return 1
    fi

    printf '%s\t%s\n' "$pack_root" "$pack_root/manifest.json"
}

acfs_offline_pack_path_is_safe() {
    local rel_path="${1:-}"

    case "$rel_path" in
        ""|.|..|/*|./*|../*|*/..|*"/../"*|*"/./"*|*"/")
            return 1
            ;;
    esac

    return 0
}

acfs_offline_pack_resolve_existing_path() {
    local path="${1:-}"
    local realpath_bin=""
    local dir=""
    local base=""

    [[ -n "$path" && -e "$path" ]] || return 1

    realpath_bin="$(acfs_security_system_binary_path realpath 2>/dev/null || true)"
    if [[ -n "$realpath_bin" ]]; then
        "$realpath_bin" -e -- "$path"
        return $?
    fi

    if [[ -d "$path" ]]; then
        (cd "$path" 2>/dev/null && pwd -P)
        return $?
    fi

    case "$path" in
        */*)
            dir="${path%/*}"
            base="${path##*/}"
            ;;
        *)
            dir="."
            base="$path"
            ;;
    esac

    (cd "$dir" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$base")
}

acfs_offline_pack_artifact_is_contained() {
    local pack_root="${1:-}"
    local artifact_file="${2:-}"
    local pack_root_real=""
    local artifact_real=""

    pack_root_real="$(acfs_offline_pack_resolve_existing_path "$pack_root" 2>/dev/null || true)"
    artifact_real="$(acfs_offline_pack_resolve_existing_path "$artifact_file" 2>/dev/null || true)"

    [[ -n "$pack_root_real" && "$pack_root_real" != "/" ]] || return 1
    [[ -n "$artifact_real" ]] || return 1
    [[ "$artifact_real" == "$pack_root_real/"* ]]
}

acfs_offline_pack_validate_manifest() {
    local pack_root="$1"
    local manifest_file="$2"
    local name="$3"
    local jq_bin=""
    local schema=""
    local schema_version=""
    local pack_mode=""
    local network_mode=""
    local policy=""
    local expires_at=""
    local expires_epoch=""
    local now_epoch=""
    local arch=""
    local checksums_declared=""
    local checksums_actual=""
    local pack_checksums_actual=""
    local manifest_declared=""
    local manifest_actual=""
    local current_manifest=""

    jq_bin="$(acfs_offline_pack_jq_bin)" || {
        acfs_offline_pack_error "pack_malformed_manifest" "$name" "jq is required to read manifest.json"
        return 1
    }

    if ! "$jq_bin" -e . "$manifest_file" >/dev/null 2>&1; then
        acfs_offline_pack_error "pack_malformed_manifest" "$name" "manifest.json is not valid JSON"
        return 1
    fi

    schema="$("$jq_bin" -r '.schema // empty' "$manifest_file")"
    schema_version="$("$jq_bin" -r '.schemaVersion // empty' "$manifest_file")"
    if [[ "$schema" != "acfs.offline-artifact-pack.v1" || "$schema_version" != "1" ]]; then
        acfs_offline_pack_error "pack_schema_unsupported" "$name" "unsupported schema=${schema:-missing} schemaVersion=${schema_version:-missing}"
        return 1
    fi

    pack_mode="$("$jq_bin" -r '.packMode // "complete"' "$manifest_file")"
    if [[ "$pack_mode" != "complete" ]]; then
        acfs_offline_pack_error "pack_unbundled_required_module" "$name" "packMode=$pack_mode cannot satisfy a verified offline install"
        return 1
    fi

    policy="$("$jq_bin" -r '.policy.verifiedInstallerPolicy // empty' "$manifest_file")"
    if [[ "$policy" != "must_match_checksums_yaml" ]]; then
        acfs_offline_pack_error "pack_checksums_mismatch" "$name" "verifiedInstallerPolicy must be must_match_checksums_yaml"
        return 1
    fi

    network_mode="$("$jq_bin" -r '.policy.networkMode // "offline"' "$manifest_file")"
    if [[ "$network_mode" != "offline" ]]; then
        acfs_offline_pack_error "pack_unbundled_required_module" "$name" "policy.networkMode=$network_mode does not provide offline guarantees"
        return 1
    fi

    expires_at="$("$jq_bin" -r '.expiresAt // empty' "$manifest_file")"
    expires_epoch="$(acfs_security_date -u -d "$expires_at" +%s 2>/dev/null || true)"
    now_epoch="$(acfs_security_date -u +%s 2>/dev/null || true)"
    if [[ -z "$expires_at" || -z "$expires_epoch" || -z "$now_epoch" || "$now_epoch" -gt "$expires_epoch" ]]; then
        acfs_offline_pack_error "pack_expired" "$name" "expiresAt=${expires_at:-missing}"
        return 1
    fi

    arch="$(acfs_offline_pack_current_arch)" || {
        acfs_offline_pack_error "pack_arch_unsupported" "$name" "unable to determine current architecture"
        return 1
    }
    if ! "$jq_bin" -e --arg arch "$arch" '
        any(.targets[]?; ((.os // "ubuntu") == "ubuntu") and (((.architecture // .arch // "") == $arch) or ((.architectures // []) | index($arch))))
    ' "$manifest_file" >/dev/null; then
        acfs_offline_pack_error "pack_arch_unsupported" "$name" "current architecture $arch is not listed in targets[]"
        return 1
    fi

    checksums_declared="$("$jq_bin" -r '.acfs.checksumsYamlSha256 // .acfs.checksumsSha256 // empty' "$manifest_file")"
    if [[ -z "$checksums_declared" || -z "${CHECKSUMS_FILE:-}" || ! -r "${CHECKSUMS_FILE:-}" ]]; then
        acfs_offline_pack_error "pack_checksums_mismatch" "$name" "current checksums.yaml is unavailable for pack comparison"
        return 1
    fi
    checksums_actual="$(calculate_file_sha256 "$CHECKSUMS_FILE")" || {
        acfs_offline_pack_error "pack_checksums_mismatch" "$name" "failed to checksum current checksums.yaml"
        return 1
    }
    if [[ "$checksums_actual" != "$checksums_declared" ]]; then
        acfs_offline_pack_error "pack_checksums_mismatch" "$name" "pack was built with a different checksums.yaml"
        return 1
    fi
    if [[ ! -r "$pack_root/checksums.yaml" ]]; then
        acfs_offline_pack_error "pack_checksums_mismatch" "$name" "pack copy of checksums.yaml is missing"
        return 1
    fi
    pack_checksums_actual="$(calculate_file_sha256 "$pack_root/checksums.yaml")" || return 1
    if [[ "$pack_checksums_actual" != "$checksums_declared" ]]; then
        acfs_offline_pack_error "pack_checksums_mismatch" "$name" "pack copy of checksums.yaml does not match manifest"
        return 1
    fi

    manifest_declared="$("$jq_bin" -r '.acfs.manifestSha256 // empty' "$manifest_file")"
    if [[ -n "$manifest_declared" ]]; then
        current_manifest="$(acfs_offline_pack_current_manifest_file 2>/dev/null || true)"
        if [[ -z "$current_manifest" ]]; then
            acfs_offline_pack_error "pack_malformed_manifest" "$name" "current acfs.manifest.yaml is unavailable for pack comparison"
            return 1
        fi
        manifest_actual="$(calculate_file_sha256 "$current_manifest")" || {
            acfs_offline_pack_error "pack_malformed_manifest" "$name" "failed to checksum current acfs.manifest.yaml"
            return 1
        }
        if [[ "$manifest_actual" != "$manifest_declared" ]]; then
            acfs_offline_pack_error "pack_malformed_manifest" "$name" "pack was built with a different acfs.manifest.yaml"
            return 1
        fi
    fi

    return 0
}

acfs_offline_pack_verify_artifact() {
    local url="$1"
    local expected_sha256="$2"
    local name="$3"
    local pack_info=""
    local pack_root=""
    local manifest_file=""
    local jq_bin=""
    local arch=""
    local artifact_tsv=""
    local key_count=""
    local module_id=""
    local rel_path=""
    local artifact_sha=""
    local size_bytes=""
    local artifact_file=""
    local actual_sha=""
    local actual_size=""

    pack_info="$(acfs_offline_pack_locate "$name")" || return 1
    pack_root="${pack_info%%$'\t'*}"
    manifest_file="${pack_info#*$'\t'}"

    acfs_offline_pack_validate_manifest "$pack_root" "$manifest_file" "$name" || return 1

    jq_bin="$(acfs_offline_pack_jq_bin)" || return 1
    arch="$(acfs_offline_pack_current_arch)" || return 1
    artifact_tsv="$("$jq_bin" -r --arg key "$name" --arg url "$url" --arg sha "$expected_sha256" --arg arch "$arch" '
        def artifact_arch: (.architecture // .platform.arch // "");
        [
            .artifacts[]?
            | select((.kind == "verified_installer" or .kind == "verified_installer_script") and .verifiedInstallerKey == $key)
            | select((.sourceUrl // "") == $url)
            | select(((.sha256 // "") == $sha) or ((.checksumsYamlSha256 // "") == $sha))
            | select((artifact_arch == "") or (artifact_arch == $arch))
        ]
        | first // empty
        | if type == "object" then [.moduleId, .path, (.sha256 // ""), ((.sizeBytes // "") | tostring)] | @tsv else empty end
    ' "$manifest_file")"

    if [[ -z "$artifact_tsv" ]]; then
        key_count="$("$jq_bin" -r --arg key "$name" '[.artifacts[]? | select(.verifiedInstallerKey == $key)] | length' "$manifest_file")"
        if [[ "$key_count" == "0" ]]; then
            acfs_offline_pack_error "pack_unbundled_required_module" "$name" "no bundled artifact has verifiedInstallerKey=$name"
        else
            acfs_offline_pack_error "pack_checksums_mismatch" "$name" "no artifact matches the requested URL, sha256, and architecture"
        fi
        return 1
    fi

    IFS=$'\t' read -r module_id rel_path artifact_sha size_bytes <<< "$artifact_tsv"
    if ! "$jq_bin" -e --arg moduleId "$module_id" --arg key "$name" '
        any(.modules[]?; .id == $moduleId and (.bundlingPolicy // "") == "bundled" and (.verifiedInstallerKey // "") == $key)
    ' "$manifest_file" >/dev/null; then
        acfs_offline_pack_error "pack_unbundled_required_module" "$name" "module $module_id is not marked bundled for verifiedInstallerKey=$name"
        return 1
    fi

    if ! acfs_offline_pack_path_is_safe "$rel_path"; then
        acfs_offline_pack_error "pack_path_escape" "$name" "artifact path is unsafe: $rel_path"
        return 1
    fi

    artifact_file="$pack_root/$rel_path"
    if [[ ! -f "$artifact_file" ]]; then
        acfs_offline_pack_error "pack_unbundled_required_module" "$name" "artifact file is missing or unsafe: $rel_path"
        return 1
    fi
    if ! acfs_offline_pack_artifact_is_contained "$pack_root" "$artifact_file"; then
        acfs_offline_pack_error "pack_path_escape" "$name" "artifact path resolves outside the pack: $rel_path"
        return 1
    fi
    if [[ -L "$artifact_file" ]]; then
        acfs_offline_pack_error "pack_unbundled_required_module" "$name" "artifact file is missing or unsafe: $rel_path"
        return 1
    fi

    actual_sha="$(calculate_file_sha256 "$artifact_file")" || {
        acfs_offline_pack_error "pack_hash_mismatch" "$name" "failed to checksum artifact $rel_path"
        return 1
    }
    if [[ "$artifact_sha" != "$expected_sha256" ]]; then
        acfs_offline_pack_error "pack_checksums_mismatch" "$name" "manifest sha256 for $rel_path does not match checksums.yaml"
        return 1
    fi
    if [[ "$actual_sha" != "$expected_sha256" ]]; then
        acfs_offline_pack_error "pack_hash_mismatch" "$name" "artifact $rel_path does not match expected sha256"
        return 1
    fi

    if [[ -n "$size_bytes" && "$size_bytes" != "null" ]]; then
        actual_size="$(acfs_security_file_size "$artifact_file")" || {
            acfs_offline_pack_error "pack_hash_mismatch" "$name" "failed to measure artifact $rel_path"
            return 1
        }
        if [[ "$actual_size" != "$size_bytes" ]]; then
            acfs_offline_pack_error "pack_hash_mismatch" "$name" "artifact $rel_path does not match declared size"
            return 1
        fi
    fi

    log_detail "offline_pack_hit tool=$name module=$module_id artifact=$rel_path"
    log_success "Verified offline artifact: $name"
    acfs_security_cat_file "$artifact_file"
}

# Fetch content and calculate checksum (using temp file)
fetch_checksum() {
    local url="$1"

    if ! enforce_https "$url"; then
        return 1
    fi

    # Create safe temp file
    local tmp_file
    tmp_file="$(acfs_security_mktemp "${TMPDIR:-/tmp}/acfs-fetch.XXXXXX")" || {
        log_error "Failed to create temp file"
        return 1
    }

    local status=0
    local file_sha256=""

    if ! acfs_download_to_file "$url" "$tmp_file" "$url"; then
        log_error "Failed to fetch $url"
        status=1
    elif ! file_sha256=$(calculate_file_sha256 "$tmp_file"); then
        log_error "Failed to checksum $url"
        status=1
    else
        printf '%s\n' "$file_sha256"
    fi

    _acfs_remove_temp_files "$tmp_file"
    return "$status"
}

# Verify URL content against expected checksum
#
# Downloads to a temporary file, verifies the checksum, and if valid,
# prints the content to stdout. This ensures binary safety (no null byte stripping)
# and verification before execution.
#
# Arguments:
#   $1 - URL
#   $2 - Expected SHA256
#   $3 - Name (for logging)
verify_checksum() {
    local url="$1"
    local expected_sha256="$2"
    local name="${3:-installer}"
    local fresh_tmp_file=""

    if ! enforce_https "$url"; then
        return 1
    fi

    if acfs_offline_pack_requested; then
        local offline_status=0
        acfs_offline_pack_verify_artifact "$url" "$expected_sha256" "$name" || offline_status=$?
        if [[ "$offline_status" -eq 0 ]]; then
            return 0
        fi
        if acfs_offline_pack_fail_closed; then
            return "$offline_status"
        fi
        log_warn "offline_pack_live_fallback tool=$name url=$url"
    fi

    # Create safe temp file
    local tmp_file
    tmp_file="$(acfs_security_mktemp "${TMPDIR:-/tmp}/acfs-verify.XXXXXX")" || {
        log_error "Failed to create temp file for $name"
        return 1
    }

    local status=0
    local verified_file=""

    if ! acfs_download_to_file "$url" "$tmp_file" "$name"; then
        log_error "Security Error: Failed to fetch $name"
        status=1
    fi

    local actual_sha256=""
    if [[ "$status" -eq 0 ]] && ! actual_sha256=$(calculate_file_sha256 "$tmp_file"); then
        log_error "Security Error: Failed to checksum $name"
        status=1
    fi

    if [[ "$status" -eq 0 && "$actual_sha256" != "$expected_sha256" ]]; then
        local refreshed_expected_sha256=""
        local refreshed_url="$url"
        local refreshed_actual_sha256=""

        if acfs_refresh_loaded_checksums_from_remote; then
            refreshed_expected_sha256="$(get_checksum "$name")"
            refreshed_url="${KNOWN_INSTALLERS[$name]:-$url}"

            if [[ -n "$refreshed_expected_sha256" ]]; then
                if [[ "$refreshed_url" == "$url" && "$actual_sha256" == "$refreshed_expected_sha256" ]]; then
                    log_success "Verified with refreshed checksums: $name"
                    verified_file="$tmp_file"
                fi

                if [[ -z "$verified_file" ]]; then
                    fresh_tmp_file="$(acfs_security_mktemp "${TMPDIR:-/tmp}/acfs-verify.XXXXXX" 2>/dev/null)" || fresh_tmp_file=""
                    if [[ -n "$fresh_tmp_file" ]] && acfs_download_to_file "$refreshed_url" "$fresh_tmp_file" "$name"; then
                        refreshed_actual_sha256="$(calculate_file_sha256 "$fresh_tmp_file")" || refreshed_actual_sha256=""
                        if [[ -n "$refreshed_actual_sha256" && "$refreshed_actual_sha256" == "$refreshed_expected_sha256" ]]; then
                            log_success "Verified with refreshed checksums: $name"
                            verified_file="$fresh_tmp_file"
                        fi
                    fi
                fi

                expected_sha256="$refreshed_expected_sha256"
                url="$refreshed_url"
                [[ -n "$refreshed_actual_sha256" ]] && actual_sha256="$refreshed_actual_sha256"
            fi
        fi

        # A trusted GitHub owner is not a substitute for checksum metadata.
        # Consistent bytes across downloads may only prove CDN consistency; the
        # installer still needs a matching checked-in or freshly loaded checksum.

        if [[ -z "$verified_file" ]]; then
            log_error "Security Error: Checksum mismatch for $name"
            printf "  Expected: %s\n" "$expected_sha256" >&2
            printf "  Actual:   %s\n" "$actual_sha256" >&2
            printf "  URL: %s\n" "$url" >&2
            printf "  Refusing to execute unverified installer script.\n" >&2
            printf "  Fix:\n" >&2
            printf "    - End users: update ACFS to refresh checksums.yaml (re-run install.sh / update scripts)\n" >&2
            printf "    - Maintainers: regenerate checksums.yaml with:\n" >&2
            printf "        ./scripts/lib/security.sh --update-checksums > checksums.yaml\n" >&2
            status=1
        fi
    elif [[ "$status" -eq 0 ]]; then
        log_success "Verified: $name"
        verified_file="$tmp_file"
    fi

    if [[ "$status" -eq 0 ]]; then
        # Return the verified content (verbatim bytes) on stdout.
        acfs_security_cat_file "$verified_file"
        status=$?
    fi

    _acfs_remove_temp_files "$tmp_file" "$fresh_tmp_file"
    return "$status"
}

# Fetch and run with optional verification
fetch_and_run() {
    local url="$1"
    local expected_sha256="${2:-}"
    local name="${3:-installer}"
    local bash_bin=""
    shift 3 || true
    local args=("$@")

    if ! enforce_https "$url"; then
        return 1
    fi

    if [[ -z "$expected_sha256" ]]; then
        log_error "Security Error: Missing checksum for $name"
        printf "  URL: %s\n" "$url" >&2
        printf "  Refusing to execute unverified installer script.\n" >&2
        printf "  Fix:\n" >&2
        printf "    - End users: update ACFS to refresh checksums.yaml (re-run install.sh / update scripts)\n" >&2
        printf "    - Maintainers: regenerate checksums.yaml with:\n" >&2
        printf "        ./scripts/lib/security.sh --update-checksums > checksums.yaml\n" >&2
        return 1
    fi

    bash_bin="$(acfs_security_required_binary_path bash)" || return $?

    (
        set -o pipefail
        verify_checksum "$url" "$expected_sha256" "$name" | "$bash_bin" -s -- "${args[@]}"
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
#
# NOTE: Mismatched scripts are not executed. To install updated scripts, regenerate checksums.yaml.
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
    local bash_bin=""
    shift 3 || true
    local args=("$@")

    if ! enforce_https "$url"; then
        return 1
    fi

    if [[ -z "$expected_sha256" ]]; then
        log_error "Security Error: Missing checksum for $name"
        printf "  URL: %s\n" "$url" >&2
        printf "  Refusing to execute unverified installer script.\n" >&2
        printf "  Fix:\n" >&2
        printf "    - End users: update ACFS to refresh checksums.yaml (re-run install.sh / update scripts)\n" >&2
        printf "    - Maintainers: regenerate checksums.yaml with:\n" >&2
        printf "        ./scripts/lib/security.sh --update-checksums > checksums.yaml\n" >&2
        return 1
    fi

    bash_bin="$(acfs_security_required_binary_path bash)" || return $?

    # Create safe temp file
    local tmp_file
    tmp_file="$(acfs_security_mktemp "${TMPDIR:-/tmp}/acfs-recovery.XXXXXX")" || {
        log_error "Failed to create temp file for $name"
        return 1
    }

    local status=0

    # Fetch content to file with retries
    if ! acfs_download_to_file "$url" "$tmp_file" "$name"; then
        log_error "Error: Failed to fetch $name"
        status=1
    fi

    # Calculate actual checksum
    local actual_sha256=""
    if [[ "$status" -eq 0 ]] && ! actual_sha256=$(calculate_file_sha256 "$tmp_file"); then
        log_error "Error: Failed to calculate checksum for $name"
        status=1
    fi

    # Check for mismatch
    if [[ "$status" -eq 0 && "$actual_sha256" != "$expected_sha256" ]]; then
        # Call mismatch handler
        handle_checksum_mismatch "$name" "$expected_sha256" "$actual_sha256" "$url"
        local mismatch_result=$?

        case $mismatch_result in
            0)
                # Skip - tool was skipped, continue installation
                log_info "Skipped: $name (checksum mismatch)"
                status=0
                ;;
            1)
                # Abort - user or policy chose to abort
                status=1
                ;;
            *)
                log_error "Error: Unexpected checksum mismatch handler result for $name: $mismatch_result"
                status=1
                ;;
        esac
    elif [[ "$status" -eq 0 ]]; then
        log_success "Verified: $name"
        # Run the installer
        "$bash_bin" "$tmp_file" "${args[@]}"
        status=$?
    fi

    _acfs_remove_temp_files "$tmp_file"
    return "$status"
}

# ============================================================
# Print Mode Support
# ============================================================

# Print all upstream URLs that will be fetched
print_upstream_urls() {
    echo ""
    printf "${CYAN}Upstream Installers${NC}\n"
    echo "============================================================"
    echo ""
    echo "The following scripts will be downloaded and executed:"
    echo ""

    for name in "${!KNOWN_INSTALLERS[@]}"; do
        local url="${KNOWN_INSTALLERS[$name]}"
        printf "  %-20s %s\n" "$name:" "$url"
    done | acfs_security_sort_lines

    echo ""
    printf "${DIM}All URLs use HTTPS for secure transport.${NC}\n"
    echo ""
}

# Print URLs with current checksums (for updating checksums.yaml)
print_current_checksums() {
    local had_failure=false
    local tmp_output=""

    tmp_output="$(acfs_security_mktemp "${TMPDIR:-/tmp}/acfs-checksums-out.XXXXXX" 2>/dev/null)" || tmp_output=""

    if [[ -z "$tmp_output" ]]; then
        echo "ERROR: unable to create temp file for checksums output" >&2
        return 1
    fi

    # Progress info to stderr (not part of YAML output)
    echo "" >&2
    printf "${CYAN}Generating checksums.yaml...${NC}\n" >&2
    echo "" >&2

    {
        # YAML output to stdout
        echo "# checksums.yaml - Auto-generated $(acfs_security_date -Iseconds)"
        echo "# Run: ./scripts/lib/security.sh --update-checksums"
        echo ""
        echo "installers:"
    } >"$tmp_output"

    local -a installer_names=()
    local name=""
    for name in "${!KNOWN_INSTALLERS[@]}"; do
        installer_names+=("$name")
    done
    if [[ ${#installer_names[@]} -gt 0 ]]; then
        mapfile -t installer_names < <(printf '%s\n' "${installer_names[@]}" | acfs_security_sort_lines)
    fi

    local wrote_entry=false
    for name in "${installer_names[@]}"; do
        local url="${KNOWN_INSTALLERS[$name]}"
        local sha256

        printf "  Fetching %s... " "$name" >&2
        sha256=$(fetch_checksum "$url" 2>/dev/null) || {
            echo "FAILED" >&2
            had_failure=true
            continue
        }

        if [[ ! "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
            echo "FAILED (invalid hash format)" >&2
            had_failure=true
            continue
        fi
        echo "done" >&2

        {
            if [[ "$wrote_entry" == "true" ]]; then
                echo ""
            fi
            echo "  $name:"
            echo "    url: \"$url\""
            echo "    sha256: \"$sha256\""
        } >>"$tmp_output"
        wrote_entry=true
    done

    if [[ "$had_failure" == "true" ]]; then
        _acfs_remove_temp_files "$tmp_output"
        echo "ERROR: one or more installer checksums failed to fetch; refusing to emit incomplete checksums.yaml" >&2
        return 1
    fi

    acfs_security_cat_file "$tmp_output"
    _acfs_remove_temp_files "$tmp_output"
}

# ============================================================
# Checksums File Management
# ============================================================

# Load checksums from YAML file (simple parser)
# shellcheck disable=SC2120  # $1 is optional with default
load_checksums() {
    local file="${1:-$CHECKSUMS_FILE}"
    local current_tool=""
    local in_installers=false
    local installers_indent=0
    local tool_indent=""
    local tool=""
    local -A parsed_checksums=()
    local -A parsed_installers=()
    # Use ACFS colors if available, preserving empty-string NO_COLOR behavior.
    local warn_color="${ACFS_YELLOW-\033[0;33m}"
    local nc_color="${ACFS_NC-\033[0m}"

    if [[ ! -r "$file" ]]; then
        printf "${warn_color}Warning:${nc_color} Checksums file not found: %s\n" "$file" >&2
        return 1
    fi

    # Lightweight YAML parsing for our specific format:
    #
    # installers:
    #   tool_name:
    #     url: "https://..."
    #     sha256: "0123...abcd"
    #
    # Rules:
    # - Only read entries under the top-level "installers:" mapping.
    # - Tool keys are detected as a mapping key with an empty value (e.g. "  bun:").
    # - Accept SHA256 values with or without quotes, and allow uppercase hex.
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line//[[:space:]]/}" ]] && continue

        local indent="${line%%[^ ]*}"
        local indent_len="${#indent}"

        if [[ "$in_installers" == "false" ]]; then
            if [[ "$line" =~ ^[[:space:]]*installers:[[:space:]]*$ ]]; then
                in_installers=true
                installers_indent="$indent_len"
                tool_indent=""
                current_tool=""
            fi
            continue
        fi

        # Stop parsing when leaving the installers section.
        if (( indent_len <= installers_indent )); then
            in_installers=false
            tool_indent=""
            current_tool=""
            continue
        fi

        # Match tool name (a mapping key line like "  bun:")
        if [[ "$line" =~ ^[[:space:]]*([[:alnum:]_-]+):[[:space:]]*$ ]]; then
            if [[ -z "$tool_indent" ]]; then
                tool_indent="$indent_len"
            fi

            if (( indent_len == tool_indent )); then
                current_tool="${BASH_REMATCH[1]}"
                continue
            fi
        fi

        # Match url value for the current tool — override KNOWN_INSTALLERS so
        # stale URLs baked into an older security.sh are corrected when
        # checksums.yaml is refreshed from GitHub. Accept quoted or unquoted
        # YAML scalars, matching install.sh's bootstrap parser.
        if [[ -n "$current_tool" ]] && [[ "$line" =~ ^[[:space:]]*url:[[:space:]]*(.*)$ ]]; then
            local url_value="${BASH_REMATCH[1]}"
            url_value="${url_value%%#*}"
            url_value="${url_value%"${url_value##*[![:space:]]}"}"
            url_value="${url_value#"${url_value%%[![:space:]]*}"}"
            url_value="${url_value%\"}"
            url_value="${url_value#\"}"
            url_value="${url_value%\'}"
            url_value="${url_value#\'}"

            if [[ "$url_value" =~ ^https://[^[:space:]]+$ ]]; then
                parsed_installers["$current_tool"]="$url_value"
            fi
        fi

        # Match sha256 value for the current tool.
        if [[ -n "$current_tool" ]] && [[ "$line" =~ ^[[:space:]]*sha256:[[:space:]]*(.*)$ ]]; then
            local checksum_value="${BASH_REMATCH[1]}"
            checksum_value="${checksum_value%%#*}"
            checksum_value="${checksum_value%"${checksum_value##*[![:space:]]}"}"
            checksum_value="${checksum_value#"${checksum_value%%[![:space:]]*}"}"
            checksum_value="${checksum_value%\"}"
            checksum_value="${checksum_value#\"}"
            checksum_value="${checksum_value%\'}"
            checksum_value="${checksum_value#\'}"

            if [[ "$checksum_value" =~ ^[0-9A-Fa-f]{64}$ ]]; then
                parsed_checksums["$current_tool"]="${checksum_value,,}"
            fi
        fi
    done < "$file"

    if [[ ${#parsed_checksums[@]} -eq 0 ]]; then
        printf "${warn_color}Warning:${nc_color} No valid installer checksums found in: %s\n" "$file" >&2
        return 1
    fi

    # Commit parsed data only after validating that the new file has usable
    # checksum entries, so a malformed refresh cannot erase previous state.
    LOADED_CHECKSUMS=()
    for tool in "${!parsed_checksums[@]}"; do
        LOADED_CHECKSUMS["$tool"]="${parsed_checksums[$tool]}"
        if [[ -n "${parsed_installers[$tool]:-}" ]]; then
            KNOWN_INSTALLERS["$tool"]="${parsed_installers[$tool]}"
        fi
    done

    return 0
}

# Get checksum for a tool
get_checksum() {
    local tool="$1"
    echo "${LOADED_CHECKSUMS[$tool]:-}"
}

# Associative array to store loaded checksums
declare -gA LOADED_CHECKSUMS=()
declare -g ACFS_CHECKSUMS_REMOTE_REFRESHED=false

acfs_checksums_file_looks_valid() {
    local file="$1"
    local line=""
    local current_tool=""
    local in_installers=false
    local installers_indent=0
    local tool_indent=""
    local tool=""
    local -A parsed_checksums=()
    local -A parsed_installers=()

    [[ -r "$file" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"

        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line//[[:space:]]/}" ]] && continue

        local indent="${line%%[^ ]*}"
        local indent_len="${#indent}"

        if [[ "$in_installers" == "false" ]]; then
            if [[ "$line" =~ ^[[:space:]]*installers:[[:space:]]*$ ]]; then
                in_installers=true
                installers_indent="$indent_len"
                tool_indent=""
                current_tool=""
            fi
            continue
        fi

        if (( indent_len <= installers_indent )); then
            in_installers=false
            tool_indent=""
            current_tool=""
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]*([[:alnum:]_-]+):[[:space:]]*$ ]]; then
            if [[ -z "$tool_indent" ]]; then
                tool_indent="$indent_len"
            fi

            if (( indent_len == tool_indent )); then
                current_tool="${BASH_REMATCH[1]}"
                continue
            fi
        fi

        [[ -n "$current_tool" ]] || continue

        if [[ "$line" =~ ^[[:space:]]*url:[[:space:]]*(.*)$ ]]; then
            local url_value="${BASH_REMATCH[1]}"
            url_value="${url_value%%#*}"
            url_value="${url_value%"${url_value##*[![:space:]]}"}"
            url_value="${url_value#"${url_value%%[![:space:]]*}"}"
            url_value="${url_value%\"}"
            url_value="${url_value#\"}"
            url_value="${url_value%\'}"
            url_value="${url_value#\'}"

            if [[ "$url_value" =~ ^https://[^[:space:]]+$ ]]; then
                parsed_installers["$current_tool"]="$url_value"
            fi
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]*sha256:[[:space:]]*(.*)$ ]]; then
            local checksum_value="${BASH_REMATCH[1]}"
            checksum_value="${checksum_value%%#*}"
            checksum_value="${checksum_value%"${checksum_value##*[![:space:]]}"}"
            checksum_value="${checksum_value#"${checksum_value%%[![:space:]]*}"}"
            checksum_value="${checksum_value%\"}"
            checksum_value="${checksum_value#\"}"
            checksum_value="${checksum_value%\'}"
            checksum_value="${checksum_value#\'}"

            if [[ "$checksum_value" =~ ^[0-9A-Fa-f]{64}$ ]]; then
                parsed_checksums["$current_tool"]="${checksum_value,,}"
            fi
        fi
    done < "$file"

    for tool in "${ACFS_SECURITY_REQUIRED_INSTALLERS[@]}"; do
        if [[ -z "${parsed_installers[$tool]:-}" ]] || [[ -z "${parsed_checksums[$tool]:-}" ]]; then
            return 1
        fi
    done

    return 0
}

acfs_fetch_fresh_checksums_to_file() {
    local dest="$1"
    local cache_buster=""
    local api_url="https://api.github.com/repos/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/contents/checksums.yaml?ref=${ACFS_CHECKSUMS_REF}"
    cache_buster="$(acfs_security_date +%s 2>/dev/null || printf '0')"
    local raw_url="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_CHECKSUMS_REF}/checksums.yaml?cb=${cache_buster}"

    : > "$dest" 2>/dev/null || {
        log_detail "Unable to initialize temporary checksums file: $dest"
        return 1
    }

    if acfs_curl \
        -H "Accept: application/vnd.github.raw" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$api_url" \
        -o "$dest" 2>/dev/null; then
        if acfs_checksums_file_looks_valid "$dest"; then
            return 0
        fi
        log_detail "GitHub API returned unexpected checksums.yaml content"
    else
        log_detail "GitHub API fetch for checksums.yaml failed"
    fi

    if acfs_download_to_file "$raw_url" "$dest" "checksums.yaml"; then
        if acfs_checksums_file_looks_valid "$dest"; then
            return 0
        fi
        log_detail "Raw checksums.yaml fetch returned unexpected content"
    else
        log_detail "Raw checksums.yaml fetch failed"
    fi

    return 1
}

acfs_refresh_loaded_checksums_from_remote() {
    if [[ "$ACFS_CHECKSUMS_REMOTE_REFRESHED" == "true" ]]; then
        return 0
    fi

    local refreshed_file=""
    refreshed_file="$(acfs_security_mktemp "${TMPDIR:-/tmp}/acfs-checksums-refresh.XXXXXX" 2>/dev/null)" || refreshed_file=""
    if [[ -z "$refreshed_file" ]]; then
        log_detail "Unable to create temp file for refreshed checksums"
        return 1
    fi

    if ! acfs_fetch_fresh_checksums_to_file "$refreshed_file"; then
        _acfs_remove_temp_files "$refreshed_file"
        return 1
    fi

    if ! load_checksums "$refreshed_file"; then
        _acfs_remove_temp_files "$refreshed_file"
        return 1
    fi

    ACFS_CHECKSUMS_REMOTE_REFRESHED=true
    _acfs_remove_temp_files "$refreshed_file"
    return 0
}

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
#   2. Presents ONE decision prompt with S/A options (fail closed)
#   3. Handles non-interactive mode based on tool classification
#
# Environment:
#   ACFS_INTERACTIVE - "true" for interactive, "false" for non-interactive
#   ACFS_STRICT_MODE - "true" treats all mismatches as critical
#
# Returns:
#   0 - User chose to skip mismatched tools (or no mismatches)
#   1 - User chose to abort (or critical tool mismatch in non-interactive)
#
handle_all_checksum_mismatches() {
    if ! has_checksum_mismatches; then
        return 0  # No mismatches, all good
    fi

    local mismatch_count
    mismatch_count="$(count_checksum_mismatches)"

    if [[ "${ACFS_STRICT_MODE:-false}" == "true" ]]; then
        echo "" >&2
        printf "${RED}Security Error:${NC} Checksum mismatches detected (strict mode). Aborting.\n" >&2
        echo "" >&2
        for entry in "${CHECKSUM_MISMATCHES[@]}"; do
            IFS="|" read -r tool url expected actual <<< "$entry"
            printf "  ${RED}[mismatch]${NC} %s\n" "$tool" >&2
            printf "      Expected: %.16s...\n" "$expected" >&2
            printf "      Actual:   %.16s...\n" "$actual" >&2
            printf "      URL: %s\n" "$url" >&2
            echo "" >&2
        done
        return 1
    fi

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
    printf "${YELLOW}============================================================${NC}\n" >&2
    printf "${YELLOW}  Checksum Mismatches Detected: %s installer(s)${NC}\n" "$mismatch_count" >&2
    printf "${YELLOW}============================================================${NC}\n" >&2
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
        printf "      Expected: %.16s...\n" "$expected" >&2
        printf "      Actual:   %.16s...\n" "$actual" >&2
        printf "      URL: %s\n" "$url" >&2
        echo "" >&2
    done

    echo "This usually means upstream scripts were updated (normal)." >&2
    echo "In rare cases, it could indicate a security issue." >&2
    echo "" >&2

    if [[ "$has_critical" == "true" ]]; then
        printf "${RED}ABORTING: %s CRITICAL tool(s) have checksum mismatches.${NC}\n" "${#critical_tools[@]}" >&2
        printf "ACFS will not run unverified CRITICAL installers.\n" >&2
        printf "Fix: update ACFS/checksums.yaml (or pin ACFS_REF to a known-good version) and re-run.\n" >&2
        return 1
    fi

    echo "Options:" >&2
    echo "  [S] Skip mismatched tools, install everything else" >&2
    echo "  [A] Abort installation" >&2
    echo "" >&2

    local choice
    if [[ -t 0 ]]; then
        read -r -p "Choice [s/A]: " choice < /dev/tty
    elif [[ -r /dev/tty ]]; then
        read -r -p "Choice [s/A]: " choice < /dev/tty
    else
        choice=""
    fi

    case "${choice,,}" in
        s|skip)
            # Add all mismatched tools to SKIPPED_TOOLS
            for entry in "${CHECKSUM_MISMATCHES[@]}"; do
                IFS="|" read -r tool url _ _ <<< "$entry"
                if declare -f record_skipped_tool &>/dev/null; then
                    record_skipped_tool "$tool" "Checksum mismatch (user chose to skip)" "$url"
                else
                    SKIPPED_TOOLS+=("$tool")
                fi
            done
            clear_checksum_mismatches
            return 0
            ;;
        a|abort|"")
            printf "${RED}Installation aborted by user.${NC}\n" >&2
            return 1
            ;;
        *)
            printf "Invalid choice. Aborting for safety.\n" >&2
            return 1
            ;;
    esac
}

# Internal: Handle mismatches in non-interactive mode
#
# Rules:
#   - CRITICAL tool mismatch → abort
#   - RECOMMENDED tool mismatch → auto-skip with warning
#
_handle_mismatches_noninteractive() {
    local has_critical=false
    local critical_names=()

    echo "" >&2
    printf "${YELLOW}Checksum mismatches detected (non-interactive mode):${NC}\n" >&2
    echo "" >&2

    for entry in "${CHECKSUM_MISMATCHES[@]}"; do
        IFS="|" read -r tool url expected actual <<< "$entry"

        local is_crit=false
        if [[ "${ACFS_STRICT_MODE:-false}" == "true" ]]; then
            is_crit=true
        elif declare -f is_critical_tool &>/dev/null && is_critical_tool "$tool"; then
            is_crit=true
        fi

        if [[ "$is_crit" == "true" ]]; then
            printf "  ${RED}[CRITICAL]${NC} %s - checksum mismatch\n" "$tool" >&2
            has_critical=true
            critical_names+=("$tool")
        else
            printf "  ${YELLOW}[skipping]${NC} %s - checksum mismatch\n" "$tool" >&2
            if declare -f record_skipped_tool &>/dev/null; then
                record_skipped_tool "$tool" "Checksum mismatch (auto-skipped in non-interactive mode)" "$url"
            else
                SKIPPED_TOOLS+=("$tool")
            fi
        fi
    done

    echo "" >&2

    if [[ "$has_critical" == "true" ]]; then
        printf "${RED}ABORTING: Critical tools have checksum mismatches: %s${NC}\n" "${critical_names[*]}" >&2
        printf "Cannot proceed safely without verified critical installers.\n" >&2
        return 1
    fi

    printf "${GREEN}Proceeding with installation (non-critical mismatches skipped).${NC}\n" >&2
    clear_checksum_mismatches
    return 0
}

# ============================================================
# Per-Tool Checksum Mismatch Handler
# Related: agentic_coding_flywheel_setup-anq
# ============================================================

# Handle a single checksum mismatch with skip/abort options
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
#
handle_checksum_mismatch() {
    local tool="$1"
    local expected="$2"
    local actual="$3"
    local url="$4"

    if [[ "${ACFS_STRICT_MODE:-false}" == "true" ]]; then
        printf "${RED}Security Error:${NC} Checksum mismatch for %s (strict mode)\n" "$tool" >&2
        printf "  Expected: %s\n" "$expected" >&2
        printf "  Actual:   %s\n" "$actual" >&2
        printf "  URL: %s\n" "$url" >&2
        return 1
    fi

    # If batch mode is enabled, record and skip (fail closed)
    if [[ "${ACFS_BATCH_CHECKSUMS:-false}" == "true" ]]; then
        record_checksum_mismatch "$tool" "$url" "$expected" "$actual"
        return 0
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
        if [[ "$is_critical" == "true" ]]; then
            echo -e "${RED}CRITICAL tool $tool has checksum mismatch - aborting${NC}" >&2
            return 1  # Abort
        else
            echo -e "${YELLOW}Skipping $tool (checksum mismatch, non-interactive)${NC}" >&2
            if declare -f record_skipped_tool &>/dev/null; then
                record_skipped_tool "$tool" "Checksum mismatch (auto-skipped)" "$url"
            else
                SKIPPED_TOOLS+=("$tool")
            fi
            return 0  # Skip
        fi
    fi

    # Interactive mode: show details and prompt
    echo "" >&2
    printf "${YELLOW}━━━ Checksum Mismatch: %s ━━━${NC}\n" "$tool" >&2
    echo "" >&2

    local classification_label
    if [[ "$is_critical" == "true" ]]; then
        classification_label="${RED}[CRITICAL]${NC}"
    else
        classification_label="${YELLOW}[optional]${NC}"
    fi

    printf "  Tool: %b %s\n" "$classification_label" "$tool" >&2
    printf "  Expected: %.16s...\n" "$expected" >&2
    printf "  Actual:   %.16s...\n" "$actual" >&2
    printf "  URL: %s\n" "$url" >&2
    echo "" >&2
    echo "This usually means the upstream script was updated." >&2
    echo "" >&2

    if [[ "$is_critical" == "true" ]]; then
        printf "${RED}ABORTING:${NC} %s is CRITICAL and its installer checksum changed.\n" "$tool" >&2
        printf "Update ACFS/checksums.yaml and re-run to proceed safely.\n" >&2
        return 1
    fi

    echo "Options:" >&2
    echo "  [S] Skip this tool" >&2
    echo "  [A] Abort installation" >&2
    echo "" >&2

    local choice
    if [[ -t 0 ]]; then
        read -r -p "Choice [s/A]: " choice < /dev/tty
    elif [[ -r /dev/tty ]]; then
        read -r -p "Choice [s/A]: " choice < /dev/tty
    else
        choice=""
    fi

    case "${choice,,}" in
        s|skip)
            if declare -f record_skipped_tool &>/dev/null; then
                record_skipped_tool "$tool" "Checksum mismatch (user chose to skip)" "$url"
            else
                SKIPPED_TOOLS+=("$tool")
            fi
            return 0  # Skip
            ;;
        a|abort|"")
            echo -e "${RED}Installation aborted by user.${NC}" >&2
            return 1  # Abort
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
    printf "${CYAN}Verifying Installer Integrity${NC}\n"
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
    timestamp="$(acfs_security_date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Arrays to collect results
    local matches=()
    local mismatches=()
    local errors=()
    local skipped=()
    local total=0

    # Helper function to escape strings for JSON
    _json_escape() {
        local s="$1"
        s="${s//\\/\\\\}" # escape backslashes
        s="${s//\"/\\\"}" # escape quotes
        s="${s//$'\n'/\\n}" # escape newlines
        s="${s//$'\r'/\\r}" # escape CR
        s="${s//$'\t'/\\t}" # escape tabs
        # Also escape control characters (0x00-0x1F)
        # shellcheck disable=SC1003
        s=$(printf '%s' "$s" | tr '\000-\037' ' ')
        printf '%s' "$s"
    }

    for name in "${!KNOWN_INSTALLERS[@]}"; do
        local url="${KNOWN_INSTALLERS[$name]}"
        local expected="${LOADED_CHECKSUMS[$name]:-}"
        total=$((total + 1))

        if [[ -z "$expected" ]]; then
            skipped+=("{\"name\":\"$(_json_escape "$name")\",\"reason\":\"no checksum recorded\"}")
            continue
        fi

        local actual=""
        local fetch_error=""
        local tmp_err=""

        # Create temp file for stderr capture. If this fails, do not use a
        # predictable fallback path; lose stderr detail instead.
        tmp_err="$(acfs_security_mktemp 2>/dev/null)" || tmp_err=""

        # Capture stdout to variable, stderr to file (if tmp_err exists)
        if [[ -n "$tmp_err" ]]; then
            if actual=$(fetch_checksum "$url" 2>"$tmp_err"); then
                # Success
                :
            else
                # Failure
                fetch_error="$(acfs_security_cat_file "$tmp_err")"
                [[ -z "$fetch_error" ]] && fetch_error="Unknown error fetching checksum"
            fi
            _acfs_remove_temp_files "$tmp_err"
        else
            # Fallback: capture combined output or lose stderr if we can't separate them safely
            # without a temp file. Here we prioritize safety over error details.
            if actual=$(fetch_checksum "$url" 2>/dev/null); then
                :
            else
                fetch_error="Unknown error (mktemp failed, stderr unavailable)"
            fi
        fi

        if [[ -n "$fetch_error" ]]; then
            local escaped_error
            escaped_error=$(_json_escape "$fetch_error")
            errors+=("{\"name\":\"$(_json_escape "$name")\",\"url\":\"$(_json_escape "$url")\",\"error\":\"$escaped_error\"}")
        elif [[ "$actual" == "$expected" ]]; then
            matches+=("{\"name\":\"$(_json_escape "$name")\",\"checksum\":\"$expected\"}")
        else
            mismatches+=("{\"name\":\"$(_json_escape "$name")\",\"url\":\"$(_json_escape "$url")\",\"expected\":\"$expected\",\"actual\":\"$actual\"}")
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
