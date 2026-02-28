#!/usr/bin/env bash
# ============================================================
# ACFS Update - Update All Components
# Updates system packages, agents, cloud CLIs, and stack tools
# ============================================================

set -euo pipefail

# Prevent interactive prompts during apt operations
export DEBIAN_FRONTEND=noninteractive

ACFS_VERSION="${ACFS_VERSION:-0.1.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACFS_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Track if self-update already ran (prevents re-exec loops)
ACFS_SELF_UPDATE_DONE="${ACFS_SELF_UPDATE_DONE:-false}"

if [[ -f "$SCRIPT_DIR/../../VERSION" ]]; then
    ACFS_VERSION="$(cat "$SCRIPT_DIR/../../VERSION" 2>/dev/null || echo "$ACFS_VERSION")"
fi

# Colors - respect NO_COLOR standard (https://no-color.org/)
# Related: bd-39ye
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 2 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    BOLD=''
    DIM=''
    NC=''
fi

# Counters
SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

# Flags
UPDATE_APT=true
UPDATE_AGENTS=true
UPDATE_CLOUD=true
UPDATE_RUNTIME=true
UPDATE_STACK=true
UPDATE_SHELL=true
UPDATE_SELF=true
FORCE_MODE=false
DRY_RUN=false
VERBOSE=false
QUIET=false
YES_MODE=false
ABORT_ON_FAILURE=false
REBOOT_REQUIRED=false

# Logging
UPDATE_LOG_DIR="${HOME}/.acfs/logs/updates"
UPDATE_LOG_FILE=""

# Version tracking
declare -gA VERSION_BEFORE=()
declare -gA VERSION_AFTER=()

# ============================================================
# Path Setup
# ============================================================

ensure_path() {
    local dir
    local to_add=()

    for dir in \
        "$HOME/.local/bin" \
        "$HOME/.bun/bin" \
        "$HOME/.cargo/bin" \
        "$HOME/go/bin" \
        "$HOME/.atuin/bin"; do
        [[ -d "$dir" ]] || continue
        case ":$PATH:" in
            *":$dir:"*) ;;
            *) to_add+=("$dir") ;;
        esac
    done

    if [[ ${#to_add[@]} -gt 0 ]]; then
        local prefix
        prefix=$(IFS=:; echo "${to_add[*]}")
        export PATH="${prefix}:$PATH"
    fi
}

# ============================================================
# Logging Infrastructure
# ============================================================

init_logging() {
    mkdir -p "$UPDATE_LOG_DIR"
    UPDATE_LOG_FILE="$UPDATE_LOG_DIR/$(date '+%Y-%m-%d-%H%M%S').log"

    # Write log header
    {
        echo "==============================================="
        echo "ACFS Update Log"
        echo "Started: $(date -Iseconds)"
        echo "User: $(whoami)"
        echo "Version: $ACFS_VERSION"
        echo "==============================================="
        echo ""
    } >> "$UPDATE_LOG_FILE"
}

log_to_file() {
    local msg="$1"
    if [[ -n "$UPDATE_LOG_FILE" ]]; then
        echo "[$(date '+%H:%M:%S')] $msg" >> "$UPDATE_LOG_FILE"
    fi
}

# ============================================================
# Version Detection
# ============================================================

get_version() {
    local tool="$1"
    local version=""

    case "$tool" in
        bun)
            version=$("$HOME/.bun/bin/bun" --version 2>/dev/null || echo "unknown")
            ;;
        rust)
            version=$("$HOME/.cargo/bin/rustc" --version 2>/dev/null | awk '{print $2}' || echo "unknown")
            ;;
        uv)
            version=$("$HOME/.local/bin/uv" --version 2>/dev/null | awk '{print $2}' || echo "unknown")
            ;;
        claude)
            version=$(claude --version 2>/dev/null | head -1 || echo "unknown")
            ;;
        codex)
            version=$(codex --version 2>/dev/null || echo "unknown")
            ;;
        gemini)
            version=$(gemini --version 2>/dev/null || echo "unknown")
            ;;
        wrangler)
            version=$(wrangler --version 2>/dev/null || echo "unknown")
            ;;
        supabase)
            version=$(supabase --version 2>/dev/null || echo "unknown")
            ;;
        vercel)
            version=$(vercel --version 2>/dev/null || echo "unknown")
            ;;
        ntm|ubs|bv|cass|cm|caam|slb|ru|dcg|apr|pt|xf|jfp|ms|br|rch|giil|csctf|srps|tru|rano|mdwb|s2p|brenner)
            version=$("$tool" --version 2>/dev/null | head -1 || echo "unknown")
            ;;
        sg|lsd|dust|tldr)
            version=$("$tool" --version 2>/dev/null | head -1 || echo "unknown")
            ;;
        atuin)
            version=$(atuin --version 2>/dev/null | awk '{print $2}' || echo "unknown")
            ;;
        zoxide)
            version=$(zoxide --version 2>/dev/null | awk '{print $2}' || echo "unknown")
            ;;
        omz)
            # OMZ version from .oh-my-zsh git tag or commit
            local omz_dir="${ZSH:-$HOME/.oh-my-zsh}"
            if [[ -d "$omz_dir/.git" ]]; then
                version=$(git -C "$omz_dir" describe --tags --abbrev=0 2>/dev/null || \
                          git -C "$omz_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
            else
                version="unknown"
            fi
            ;;
        p10k)
            # P10K version from git tag or commit
            local p10k_dir="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/themes/powerlevel10k"
            if [[ -d "$p10k_dir/.git" ]]; then
                version=$(git -C "$p10k_dir" describe --tags --abbrev=0 2>/dev/null || \
                          git -C "$p10k_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
            else
                version="unknown"
            fi
            ;;
        *)
            version="unknown"
            ;;
    esac

    echo "$version"
}

capture_version_before() {
    local tool="$1"
    VERSION_BEFORE["$tool"]=$(get_version "$tool")
    log_to_file "Version before [$tool]: ${VERSION_BEFORE[$tool]}"
}

capture_version_after() {
    local tool="$1"
    VERSION_AFTER["$tool"]=$(get_version "$tool")
    log_to_file "Version after [$tool]: ${VERSION_AFTER[$tool]}"

    local before="${VERSION_BEFORE[$tool]:-unknown}"
    local after="${VERSION_AFTER[$tool]}"

    if [[ "$before" != "$after" ]]; then
        log_to_file "Updated [$tool]: $before -> $after"
        return 0
    fi
    return 1
}

# ============================================================
# Helper Functions
# ============================================================

log_section() {
    log_to_file "=== $1 ==="
    if [[ "$QUIET" != "true" ]]; then
        echo ""
        echo -e "${BOLD}${CYAN}$1${NC}"
        echo "------------------------------------------------------------"
    fi
}

log_item() {
    local status="$1"
    local msg="$2"
    local details="${3:-}"

    log_to_file "[$status] $msg${details:+ - $details}"

    case "$status" in
        ok)
            [[ "$QUIET" != "true" ]] && printf "  ${GREEN}[ok]${NC} %s\n" "$msg"
            [[ -n "$details" && "$VERBOSE" == "true" && "$QUIET" != "true" ]] && printf "       ${DIM}%s${NC}\n" "$details"
            ((SUCCESS_COUNT += 1))
            ;;
        skip)
            [[ "$QUIET" != "true" ]] && printf "  ${DIM}[skip]${NC} %s\n" "$msg"
            [[ -n "$details" && "$QUIET" != "true" ]] && printf "       ${DIM}%s${NC}\n" "$details"
            ((SKIP_COUNT += 1))
            ;;
        fail)
            # Always show failures even in quiet mode
            printf "  ${RED}[fail]${NC} %s\n" "$msg"
            [[ -n "$details" ]] && printf "       ${DIM}%s${NC}\n" "$details"
            ((FAIL_COUNT += 1))
            ;;
        run)
            [[ "$QUIET" != "true" ]] && printf "  ${YELLOW}[...]${NC} %s\n" "$msg"
            ;;
        warn)
            [[ "$QUIET" != "true" ]] && printf "  ${YELLOW}[warn]${NC} %s\n" "$msg"
            [[ -n "$details" && "$QUIET" != "true" ]] && printf "       ${DIM}%s${NC}\n" "$details"
            ;;
        wait)
            [[ "$QUIET" != "true" ]] && printf "  ${YELLOW}[wait]${NC} %s\n" "$msg"
            [[ -n "$details" && "$QUIET" != "true" ]] && printf "       ${DIM}%s${NC}\n" "$details"
            ;;
        fix)
            [[ "$QUIET" != "true" ]] && printf "  ${YELLOW}[fix]${NC} %s\n" "$msg"
            [[ -n "$details" && "$QUIET" != "true" ]] && printf "       ${DIM}%s${NC}\n" "$details"
            ((SUCCESS_COUNT += 1))
            ;;
        info)
            [[ "$QUIET" != "true" ]] && printf "  ${CYAN}[info]${NC} %s\n" "$msg"
            [[ -n "$details" && "$QUIET" != "true" ]] && printf "       ${DIM}%s${NC}\n" "$details"
            ;;
    esac
}

run_cmd() {
    local desc="$1"
    shift
    local cmd_display=""
    cmd_display=$(printf '%q ' "$@")

    log_to_file "Running: $cmd_display"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "skip" "$desc" "dry-run: $cmd_display"
        return 0
    fi

    log_item "run" "$desc"

    local exit_code=0

    # In verbose mode, stream command output to the console AND log file.
    # In non-verbose mode, capture output for logging without flooding the terminal.
    if [[ "$VERBOSE" == "true" ]]; then
        if [[ -n "${UPDATE_LOG_FILE:-}" ]]; then
            # Separate commands in the log for readability.
            {
                echo ""
                echo "----- COMMAND: $cmd_display"
            } >> "$UPDATE_LOG_FILE"
        fi

        if [[ "$QUIET" != "true" ]] && [[ -n "${UPDATE_LOG_FILE:-}" ]]; then
            if "$@" 2>&1 | tee -a "$UPDATE_LOG_FILE"; then
                exit_code=0
            else
                exit_code=${PIPESTATUS[0]}
            fi
        elif [[ -n "${UPDATE_LOG_FILE:-}" ]]; then
            if "$@" >> "$UPDATE_LOG_FILE" 2>&1; then
                exit_code=0
            else
                exit_code=$?
            fi
        else
            # Should not happen (init_logging sets UPDATE_LOG_FILE), but keep a safe fallback.
            if [[ "$QUIET" != "true" ]]; then
                "$@" || exit_code=$?
            else
                "$@" >/dev/null 2>&1 || exit_code=$?
            fi
        fi
    else
        local output=""
        output=$("$@" 2>&1) || exit_code=$?
        [[ -n "$output" ]] && log_to_file "Output: $output"
    fi

    if [[ $exit_code -eq 0 ]]; then
        # Move cursor up and overwrite (only in non-verbose, non-quiet mode)
        if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
            printf "\033[1A\033[2K  ${GREEN}[ok]${NC} %s\n" "$desc"
        elif [[ "$QUIET" != "true" ]]; then
            printf "  ${GREEN}[ok]${NC} %s\n" "$desc"
        fi
        log_to_file "Success: $desc"
        ((SUCCESS_COUNT += 1))
        return 0
    else
        if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
            printf "\033[1A\033[2K  ${RED}[fail]${NC} %s\n" "$desc"
        else
            printf "  ${RED}[fail]${NC} %s\n" "$desc"
        fi
        log_to_file "Failed: $desc (exit code: $exit_code)"
        ((FAIL_COUNT += 1))

        # Handle abort-on-failure
        if [[ "$ABORT_ON_FAILURE" == "true" ]]; then
            echo -e "${RED}Aborting due to failure (--abort-on-failure)${NC}"
            log_to_file "ABORT: Stopping due to --abort-on-failure"
            exit 1
        fi
        return 0
    fi
}

# Run bun command with retry logic for transient failures
# Usage: run_cmd_bun_with_retry "description" bun_bin install -g --trust pkg@latest
run_cmd_bun_with_retry() {
    local desc="$1"
    shift
    local max_attempts=3
    local attempt=1
    local exit_code=0
    local output=""
    local cmd_display=""
    cmd_display=$(printf '%q ' "$@")

    log_to_file "Running (with retry): $cmd_display"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "skip" "$desc" "dry-run: $cmd_display"
        return 0
    fi

    log_item "run" "$desc"

    while [[ $attempt -le $max_attempts ]]; do
        exit_code=0
        output=""

        if [[ "$VERBOSE" == "true" ]]; then
            if [[ -n "${UPDATE_LOG_FILE:-}" ]]; then
                {
                    echo ""
                    echo "----- COMMAND (attempt $attempt/$max_attempts): $cmd_display"
                } >> "$UPDATE_LOG_FILE"
            fi

            if [[ "$QUIET" != "true" ]] && [[ -n "${UPDATE_LOG_FILE:-}" ]]; then
                output=$("$@" 2>&1 | tee -a "$UPDATE_LOG_FILE") || exit_code=${PIPESTATUS[0]}
            elif [[ -n "${UPDATE_LOG_FILE:-}" ]]; then
                output=$("$@" 2>&1) || exit_code=$?
                [[ -n "$output" ]] && echo "$output" >> "$UPDATE_LOG_FILE"
            else
                output=$("$@" 2>&1) || exit_code=$?
            fi
        else
            output=$("$@" 2>&1) || exit_code=$?
            [[ -n "$output" ]] && log_to_file "Output: $output"
        fi

        if [[ $exit_code -eq 0 ]]; then
            if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
                printf "\033[1A\033[2K  ${GREEN}[ok]${NC} %s\n" "$desc"
            elif [[ "$QUIET" != "true" ]]; then
                printf "  ${GREEN}[ok]${NC} %s\n" "$desc"
            fi
            log_to_file "Success: $desc"
            ((SUCCESS_COUNT += 1))
            return 0
        fi

        # Check for transient errors that warrant a retry
        local is_transient=false
        if echo "$output" | grep -qiE "failed to map segment|ENOENT|EACCES|EAGAIN|Connection reset|timed out|rate limit|503|502|500"; then
            is_transient=true
        fi

        if [[ "$is_transient" == "true" ]] && [[ $attempt -lt $max_attempts ]]; then
            local sleep_secs=$((attempt * 2))
            log_to_file "Transient error detected, retrying in ${sleep_secs}s (attempt $attempt/$max_attempts)"

            if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
                printf "\033[1A\033[2K  ${YELLOW}[retry]${NC} %s (attempt %d/%d)\n" "$desc" "$attempt" "$max_attempts"
            elif [[ "$QUIET" != "true" ]]; then
                printf "  ${YELLOW}[retry]${NC} %s (attempt %d/%d)\n" "$desc" "$attempt" "$max_attempts"
            fi

            # Clear bun's tmp cache to avoid stale locks
            local bun_cache_tmp="${HOME}/.bun/install/cache/.tmp"
            if [[ -d "$bun_cache_tmp" ]]; then
                rm -rf "$bun_cache_tmp" 2>/dev/null || true
                log_to_file "Cleared bun cache .tmp directory"
            fi

            sleep "$sleep_secs"
            ((attempt += 1))

            # Re-display "running" status for the retry
            if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
                log_item "run" "$desc"
            fi
        else
            break
        fi
    done

    # Final failure
    if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
        printf "\033[1A\033[2K  ${RED}[fail]${NC} %s\n" "$desc"
    else
        printf "  ${RED}[fail]${NC} %s\n" "$desc"
    fi
    log_to_file "Failed: $desc (exit code: $exit_code after $attempt attempts)"
    ((FAIL_COUNT += 1))

    if [[ "$ABORT_ON_FAILURE" == "true" ]]; then
        echo -e "${RED}Aborting due to failure (--abort-on-failure)${NC}"
        log_to_file "ABORT: Stopping due to --abort-on-failure"
        exit 1
    fi
    return 0
}

# Check if command exists
cmd_exists() {
    command -v "$1" &>/dev/null
}

# Get sudo (empty if already root)
get_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo ""
    else
        echo "sudo"
    fi
}

run_cmd_sudo() {
    local desc="$1"
    shift

    local sudo_cmd
    sudo_cmd=$(get_sudo)
    if [[ -n "$sudo_cmd" ]]; then
        run_cmd "$desc" "$sudo_cmd" "$@"
        return 0
    fi
    run_cmd "$desc" "$@"
}

# ============================================================
# Migration Cleanup
# ============================================================

# Clean up legacy git_safety_guard artifacts from pre-DCG installations
# This runs on every update to ensure stale files are removed
cleanup_legacy_git_safety_guard() {
    local cleaned=false
    local hooks_dirs=(
        "$HOME/.acfs/claude/hooks"
        "$HOME/.claude/hooks"
    )
    local legacy_files=(
        "git_safety_guard.py"
        "git_safety_guard.sh"
    )

    # Remove legacy hook files
    for dir in "${hooks_dirs[@]}"; do
        for file in "${legacy_files[@]}"; do
            if [[ -f "$dir/$file" ]]; then
                rm -f "$dir/$file" 2>/dev/null && cleaned=true
                log_to_file "Removed legacy file: $dir/$file"
            fi
        done
        # Remove empty hooks directory
        if [[ -d "$dir" ]] && [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
            rmdir "$dir" 2>/dev/null && cleaned=true
            log_to_file "Removed empty directory: $dir"
        fi
    done

    # Clean parent directories if empty
    for parent in "$HOME/.acfs/claude" "$HOME/.claude"; do
        if [[ -d "$parent" ]] && [[ -z "$(ls -A "$parent" 2>/dev/null)" ]]; then
            rmdir "$parent" 2>/dev/null || true
            log_to_file "Removed empty directory: $parent"
        fi
    done

    # Clean git_safety_guard from Claude settings.json if present
    local settings_file="$HOME/.claude/settings.json"
    if [[ -f "$settings_file" ]] && command -v jq &>/dev/null; then
        if jq -e '.hooks // empty' "$settings_file" &>/dev/null; then
            # Check if git_safety_guard is referenced in hooks
            if grep -q "git_safety_guard" "$settings_file" 2>/dev/null; then
                local tmp_settings
                tmp_settings=$(mktemp)
                # Remove any hook entries containing git_safety_guard
                if jq 'walk(if type == "object" and .hooks then .hooks |= map(select(. | tostring | contains("git_safety_guard") | not)) else . end)' "$settings_file" > "$tmp_settings" 2>/dev/null; then
                    mv "$tmp_settings" "$settings_file" && cleaned=true
                    log_to_file "Cleaned git_safety_guard references from $settings_file"
                else
                    rm -f "$tmp_settings"
                fi
            fi
        fi
    fi

    if [[ "$cleaned" == "true" ]]; then
        log_item "ok" "legacy cleanup" "removed git_safety_guard artifacts"
    fi
}

# Fix stale aliases in deployed acfs.zshrc
# Older versions aliased br='bun run dev', which shadows beads_rust (br).
cleanup_legacy_br_alias() {
    local deployed="$HOME/.acfs/zsh/acfs.zshrc"
    [[ -f "$deployed" ]] || return 0

    # Check for the exact problematic alias (uncommented)
    if grep -q "^alias br='bun run dev'" "$deployed" 2>/dev/null; then
        # Comment out the old alias (sync_acfs_zshrc will deploy the correct version later;
        # this sed is a safety net for when the repo isn't available)
        sed -i "s|^alias br='bun run dev'|# alias br='bun run dev'  # disabled - conflicts with beads_rust (br)|" "$deployed"
        log_item "ok" "legacy cleanup" "fixed br alias conflict in deployed acfs.zshrc"
        log_to_file "Commented out alias br='bun run dev' in $deployed"
    fi
}

# Re-deploy acfs.zshrc from repo to ~/.acfs/ if repo copy is newer
sync_acfs_zshrc() {
    local repo_zshrc="$ACFS_REPO_ROOT/acfs/zsh/acfs.zshrc"
    local deployed_zshrc="$HOME/.acfs/zsh/acfs.zshrc"

    [[ -f "$repo_zshrc" ]] || return 0

    # Skip if deployed copy is identical
    if [[ -f "$deployed_zshrc" ]] && cmp -s "$repo_zshrc" "$deployed_zshrc"; then
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "ok" "acfs.zshrc" "would sync from repo (changed)"
        return 0
    fi

    mkdir -p "$(dirname "$deployed_zshrc")"
    cp "$repo_zshrc" "$deployed_zshrc"
    log_item "ok" "acfs.zshrc" "synced from repo"
    log_to_file "Deployed $repo_zshrc -> $deployed_zshrc"
}

# ============================================================
# Checksums Refresh (Auto-update from GitHub)
# ============================================================

CHECKSUMS_URL="https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/checksums.yaml"
CHECKSUMS_LOCAL="${HOME}/.acfs/checksums.yaml"

# Refresh checksums.yaml from GitHub before verifying installers
# This ensures we always have the latest checksums without requiring
# a full ACFS re-install.
refresh_checksums() {
    local quiet="${1:-false}"

    # Create directory if needed
    mkdir -p "$(dirname "$CHECKSUMS_LOCAL")"

    # Download with timeout and retry
    local tmp_checksums
    tmp_checksums=$(mktemp "${TMPDIR:-/tmp}/acfs-checksums.XXXXXX")

    if curl -fsSL --connect-timeout 5 --max-time 30 -o "$tmp_checksums" "$CHECKSUMS_URL" 2>/dev/null; then
        # Validate it looks like a checksums file
        if grep -q "^installers:" "$tmp_checksums" 2>/dev/null; then
            if mv "$tmp_checksums" "$CHECKSUMS_LOCAL" 2>/dev/null; then
                chmod 644 "$CHECKSUMS_LOCAL" 2>/dev/null || true  # Ensure readable permissions
                if [[ "$quiet" != "true" ]]; then
                    log_item "ok" "checksums refresh" "synced from GitHub"
                fi
                log_to_file "Refreshed checksums.yaml from $CHECKSUMS_URL"
                return 0
            else
                rm -f "$tmp_checksums"
                [[ "$quiet" != "true" ]] && log_item "warn" "checksums refresh" "failed to install, using cached"
                log_to_file "Checksums refresh failed: mv failed"
                return 1
            fi
        else
            rm -f "$tmp_checksums"
            [[ "$quiet" != "true" ]] && log_item "warn" "checksums refresh" "invalid format, using cached"
            log_to_file "Checksums refresh failed: invalid format"
            return 1
        fi
    else
        rm -f "$tmp_checksums"
        [[ "$quiet" != "true" ]] && log_item "warn" "checksums refresh" "network error, using cached"
        log_to_file "Checksums refresh failed: network error"
        return 1
    fi
}

# ============================================================
# Upstream installer verification (checksums.yaml)
# ============================================================

UPDATE_SECURITY_READY=false
update_require_security() {
    if [[ "${UPDATE_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    # Refresh checksums from GitHub before loading
    # This ensures we have the latest checksums when security verification is needed
    refresh_checksums "${QUIET:-false}" || true

    # Check for security.sh in expected locations
    local security_script=""
    if [[ -f "$SCRIPT_DIR/security.sh" ]]; then
        security_script="$SCRIPT_DIR/security.sh"
    elif [[ -f "$HOME/.acfs/scripts/lib/security.sh" ]]; then
        security_script="$HOME/.acfs/scripts/lib/security.sh"
    fi

    if [[ -z "$security_script" ]]; then
        echo "" >&2
        echo "═══════════════════════════════════════════════════════════════" >&2
        echo "  ERROR: security.sh not found" >&2
        echo "═══════════════════════════════════════════════════════════════" >&2
        echo "" >&2
        echo "  The security verification script is missing." >&2
        echo "  This is required for --stack updates." >&2
        echo "" >&2
        echo "  Checked locations:" >&2
        echo "    - $SCRIPT_DIR/security.sh" >&2
        echo "    - $HOME/.acfs/scripts/lib/security.sh" >&2
        echo "" >&2
        echo "  This usually means:" >&2
        echo "    1. You have an older ACFS installation, OR" >&2
        echo "    2. The installation didn't complete fully" >&2
        echo "" >&2
        echo "  TO FIX: Re-run the ACFS installer:" >&2
        echo "" >&2
        echo "    curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes" >&2
        echo "" >&2
        echo "═══════════════════════════════════════════════════════════════" >&2
        echo "" >&2
        return 1
    fi

    # shellcheck source=security.sh
    # shellcheck disable=SC1091  # runtime relative source
    source "$security_script"
    load_checksums || return 1

    UPDATE_SECURITY_READY=true
    return 0
}

# shellcheck disable=SC2317,SC2329  # invoked indirectly via run_cmd()
update_run_verified_installer() {
    local tool="$1"
    shift || true

    if ! update_require_security; then
        echo "Security verification unavailable (missing $SCRIPT_DIR/security.sh or checksums.yaml)" >&2
        return 1
    fi

    local url="${KNOWN_INSTALLERS[$tool]:-}"
    local expected_sha256
    expected_sha256="$(get_checksum "$tool")"

    if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
        echo "Missing checksum entry for $tool" >&2
        return 1
    fi

    (
        set -o pipefail
        verify_checksum "$url" "$expected_sha256" "$tool" | bash -s -- "$@"
    )
}

# ============================================================
# Update Functions
# ============================================================

# ------------------------------------------------------------
# Self-Update: Update ACFS itself before anything else
# ------------------------------------------------------------
# This ensures users always have the latest update logic,
# security fixes, and new tool definitions.
# ------------------------------------------------------------
update_acfs_self() {
    log_section "ACFS Self-Update"

    # Skip if disabled
    if [[ "$UPDATE_SELF" != "true" ]]; then
        log_item "skip" "ACFS self-update" "disabled via --no-self-update"
        return 0
    fi

    # Skip if already done (prevents infinite re-exec loops)
    if [[ "$ACFS_SELF_UPDATE_DONE" == "true" ]]; then
        log_item "skip" "ACFS self-update" "already completed"
        return 0
    fi

    # Check if ACFS repo exists and is a git repo.
    # If installed via tarball (no .git dir), bootstrap a git repo so
    # the existing pull-based self-update logic works on subsequent runs.
    if [[ ! -d "$ACFS_REPO_ROOT/.git" ]]; then
        log_to_file "No .git directory found at $ACFS_REPO_ROOT — bootstrapping git repo for self-update..."

        # Check if git is available before attempting bootstrap
        if ! command -v git &>/dev/null; then
            log_item "skip" "ACFS self-update" "git not found, cannot bootstrap"
            return 0
        fi

        if ! git -C "$ACFS_REPO_ROOT" init 2>/dev/null; then
            log_item "warn" "ACFS self-update" "git init failed at $ACFS_REPO_ROOT"
            return 0
        fi

        if ! git -C "$ACFS_REPO_ROOT" remote add origin \
                https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup.git 2>/dev/null; then
            # Remote may already exist from a partial prior run; verify it points to the right URL
            local existing_url
            existing_url=$(git -C "$ACFS_REPO_ROOT" remote get-url origin 2>/dev/null) || true
            if [[ "$existing_url" != *"agentic_coding_flywheel_setup"* ]]; then
                log_item "warn" "ACFS self-update" "unexpected origin remote: $existing_url"
                return 0
            fi
        fi

        if ! git -C "$ACFS_REPO_ROOT" fetch origin main --quiet 2>/dev/null; then
            log_item "warn" "ACFS self-update" "git fetch failed during bootstrap (network issue?)"
            return 0
        fi

        # Use --mixed reset so local modifications (custom configs, etc.) are
        # preserved as unstaged changes rather than being destroyed.
        if ! git -C "$ACFS_REPO_ROOT" reset --mixed origin/main 2>/dev/null; then
            log_item "warn" "ACFS self-update" "git reset failed during bootstrap"
            return 0
        fi

        log_item "ok" "ACFS" "git repo bootstrapped from tarball install"
        log_to_file "ACFS git repo initialized at $ACFS_REPO_ROOT — run 'acfs update' again for full self-update"
        return 0
    fi

    # Check if git is available
    if ! command -v git &>/dev/null; then
        log_item "skip" "ACFS self-update" "git not found"
        return 0
    fi

    # Get current branch
    local current_branch
    current_branch=$(git -C "$ACFS_REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) || {
        log_item "warn" "ACFS self-update" "failed to get current branch"
        return 0
    }

    # Only auto-update on main branch
    if [[ "$current_branch" != "main" ]]; then
        log_item "skip" "ACFS self-update" "not on main branch (on: $current_branch)"
        return 0
    fi

    # Save current update.sh hash for re-exec detection
    local update_script="$SCRIPT_DIR/update.sh"
    local old_hash=""
    if [[ -f "$update_script" ]]; then
        old_hash=$(sha256sum "$update_script" 2>/dev/null | cut -d' ' -f1) || true
    fi

    # Fetch latest from origin
    log_to_file "Fetching from origin..."
    if ! git -C "$ACFS_REPO_ROOT" fetch origin main --quiet 2>/dev/null; then
        log_item "warn" "ACFS self-update" "git fetch failed (network issue?)"
        return 0
    fi

    # Compare local HEAD with remote
    local local_head remote_head
    local_head=$(git -C "$ACFS_REPO_ROOT" rev-parse HEAD 2>/dev/null) || true
    remote_head=$(git -C "$ACFS_REPO_ROOT" rev-parse origin/main 2>/dev/null) || true

    if [[ -z "$local_head" ]] || [[ -z "$remote_head" ]]; then
        log_item "warn" "ACFS self-update" "failed to compare versions"
        return 0
    fi

    if [[ "$local_head" == "$remote_head" ]]; then
        log_item "ok" "ACFS" "already up to date"
        return 0
    fi

    # Show what's coming
    local commit_count
    commit_count=$(git -C "$ACFS_REPO_ROOT" rev-list --count HEAD..origin/main 2>/dev/null) || commit_count="?"
    log_to_file "Found $commit_count new commit(s)"

    # Dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "ok" "ACFS" "would update ($commit_count new commits)"
        return 0
    fi

    # Stash local modifications so they don't block the pull
    local stashed=false
    if ! git -C "$ACFS_REPO_ROOT" diff --quiet 2>/dev/null || ! git -C "$ACFS_REPO_ROOT" diff --cached --quiet 2>/dev/null; then
        log_to_file "Local modifications detected, stashing before update..."
        if git -C "$ACFS_REPO_ROOT" stash --quiet 2>/dev/null; then
            stashed=true
        fi
    fi

    # Pull updates
    log_to_file "Pulling updates..."
    if ! git -C "$ACFS_REPO_ROOT" pull --ff-only origin main 2>/dev/null; then
        # ff-only failed (diverged history?), try reset --mixed
        log_to_file "ff-only pull failed, using reset --mixed"
        git -C "$ACFS_REPO_ROOT" reset --mixed origin/main 2>/dev/null || {
            log_item "warn" "ACFS self-update" "git update failed"
            [[ "$stashed" == "true" ]] && git -C "$ACFS_REPO_ROOT" stash pop --quiet 2>/dev/null || true
            return 0
        }
    fi

    # Restore local modifications
    if [[ "$stashed" == "true" ]]; then
        git -C "$ACFS_REPO_ROOT" stash pop --quiet 2>/dev/null || true
    fi

    log_item "ok" "ACFS" "updated ($commit_count commits)"
    log_to_file "ACFS updated from $local_head to $remote_head"

    # Check if update.sh itself changed - if so, re-exec
    local new_hash=""
    if [[ -f "$update_script" ]]; then
        new_hash=$(sha256sum "$update_script" 2>/dev/null | cut -d' ' -f1) || true
    fi

    if [[ -n "$old_hash" ]] && [[ -n "$new_hash" ]] && [[ "$old_hash" != "$new_hash" ]]; then
        log_to_file "update.sh changed, re-executing with new version..."
        echo ""
        echo -e "${CYAN}update.sh was updated, restarting with new version...${NC}"
        echo ""

        # Re-exec with same args, but mark self-update as done
        export ACFS_SELF_UPDATE_DONE=true
        exec "$update_script" "$@"
        # exec replaces this process, so we never reach here
    fi

    return 0
}

update_apt() {
    log_section "System Packages (apt)"

    if [[ "$UPDATE_APT" != "true" ]]; then
        log_item "skip" "apt update" "disabled via --no-apt"
        return 0
    fi

    # Check if apt/dpkg is available (Linux only)
    if ! command -v apt-get &>/dev/null; then
        log_item "skip" "apt" "not available (non-Debian system)"
        return 0
    fi

    # Check for apt lock (with automatic waiting)
    if ! check_apt_lock; then
        return 0
    fi

    # Fix any broken packages first
    fix_apt_issues

    # Run apt update
    run_cmd_sudo "apt update" apt-get update -y

    # Get list of upgradable packages before upgrade
    local upgradable_list=""
    local upgrade_count=0
    if upgradable_list=$(apt list --upgradable 2>/dev/null | grep -v "^Listing"); then
        upgrade_count=$(echo "$upgradable_list" | grep -c . || echo 0)
        if [[ $upgrade_count -gt 0 ]]; then
            log_to_file "Upgradable packages ($upgrade_count):"
            log_to_file "$upgradable_list"
        fi
    fi

    if [[ $upgrade_count -eq 0 ]]; then
        log_item "ok" "apt upgrade" "all packages up to date"
    else
        log_to_file "Upgrading $upgrade_count packages..."
        run_cmd_sudo "apt upgrade ($upgrade_count packages)" apt-get upgrade -y
    fi

    run_cmd_sudo "apt autoremove" apt-get autoremove -y

    # Check if reboot is required (kernel updates, etc.)
    check_reboot_required
}

# Wait for apt lock to be released, with automatic retry
# Returns 0 if lock is free, 1 if still locked after max attempts
wait_for_apt_lock() {
    local max_wait=${1:-120}  # Default 120 seconds (2 minutes)
    local interval=5
    local waited=0

    if ! command -v fuser &>/dev/null; then
        log_to_file "fuser not available (psmisc not installed), skipping apt lock detection"
        return 0
    fi

    while [[ $waited -lt $max_wait ]]; do
        # Only check actual lock files — background processes (e.g. unattended-upgrades
        # daemon) don't hold locks unless actively installing
        local lock_held=false
        for lockfile in /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock; do
            if [[ -f "$lockfile" ]] && fuser "$lockfile" &>/dev/null; then
                lock_held=true
                break
            fi
        done

        if [[ "$lock_held" == "false" ]]; then
            return 0
        fi

        if [[ $waited -eq 0 ]]; then
            log_item "wait" "apt lock" "waiting for other package operations to complete..."
            log_to_file "APT lock detected, waiting up to ${max_wait}s for release"
            local lock_info=""
            lock_info=$(fuser -v /var/lib/dpkg/lock-frontend 2>&1 || true)
            [[ -n "$lock_info" ]] && log_to_file "Lock holder: $lock_info"
        fi

        sleep "$interval"
        waited=$((waited + interval))

        # Progress indicator every 30 seconds
        if [[ $((waited % 30)) -eq 0 ]] && [[ "$QUIET" != "true" ]]; then
            echo -e "       ${DIM}Still waiting... (${waited}s/${max_wait}s)${NC}"
        fi
    done

    return 1
}

# Fix common dpkg/apt issues automatically
fix_apt_issues() {
    log_to_file "Checking for apt issues to fix..."

    # Fix interrupted dpkg (check if there are pending updates)
    if ls /var/lib/dpkg/updates/* &>/dev/null; then
        log_item "fix" "dpkg" "configuring interrupted packages"
        log_to_file "Running: sudo dpkg --configure -a"
        local dpkg_output
        dpkg_output=$(sudo dpkg --configure -a 2>&1) || true
        [[ -n "$dpkg_output" ]] && log_to_file "dpkg output: $dpkg_output"
    fi

    # Check for broken dependencies or packages needing reinstall
    local needs_fix=false
    local broken_count=0
    broken_count=$(dpkg -l 2>/dev/null | grep -c "^..R" || true)
    broken_count=$((broken_count + 0))  # Ensure integer
    if [[ $broken_count -gt 0 ]]; then
        needs_fix=true
        log_to_file "Found $broken_count package(s) in reinstall-required state"
    fi

    # Also check if apt reports broken dependencies
    if ! apt-get check &>/dev/null; then
        needs_fix=true
        log_to_file "apt-get check reported issues"
    fi

    if [[ "$needs_fix" == "true" ]]; then
        log_item "fix" "apt" "fixing broken dependencies"
        log_to_file "Running: sudo apt-get -f install -y"
        local apt_output
        apt_output=$(sudo apt-get -f install -y 2>&1) || true
        [[ -n "$apt_output" ]] && log_to_file "apt-get -f output: $apt_output"
    fi
}

# Check if apt is locked by another process, with automatic waiting and fixing
check_apt_lock() {
    # Only check if actual dpkg/apt lock files are held by a process.
    # Background daemons (e.g. unattended-upgrades) don't hold locks unless
    # actively installing, so pgrep-based checks cause false positives.
    local locks_held=false
    for lockfile in /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock; do
        if [[ -f "$lockfile" ]] && fuser "$lockfile" &>/dev/null; then
            locks_held=true
            break
        fi
    done

    if [[ "$locks_held" == "false" ]]; then
        return 0  # No locks held, safe to proceed
    fi

    # Lock IS held — wait for release
    if wait_for_apt_lock 120; then
        log_item "ok" "apt lock" "lock released, proceeding"
        return 0
    fi

    # Still locked after waiting — show diagnostic
    log_item "skip" "apt" "dpkg lock held after 2m wait"
    log_to_file "APT lock still held after waiting"

    local lock_holder=""
    lock_holder=$(sudo fuser -v /var/lib/dpkg/lock-frontend 2>&1 || true)
    if [[ -n "$lock_holder" ]]; then
        log_to_file "Lock holder: $lock_holder"
        if [[ "$QUIET" != "true" ]]; then
            echo -e "       ${DIM}Lock held by: $lock_holder${NC}"
        fi
    fi

    if [[ "$ABORT_ON_FAILURE" == "true" ]]; then
        echo -e "${RED}Aborting: apt is locked and could not be released${NC}"
        exit 1
    fi

    return 1
}

# Check if system reboot is required after updates
check_reboot_required() {
    if [[ -f /var/run/reboot-required ]]; then
        log_item "warn" "Reboot required" "kernel or critical package updated"
        log_to_file "REBOOT REQUIRED: /var/run/reboot-required exists"

        if [[ -f /var/run/reboot-required.pkgs ]]; then
            local pkgs
            pkgs=$(cat /var/run/reboot-required.pkgs 2>/dev/null || echo "unknown")
            log_to_file "Packages requiring reboot: $pkgs"
            if [[ "$QUIET" != "true" ]]; then
                echo -e "       ${DIM}Packages: $pkgs${NC}"
            fi
        fi

        # Set a global flag for summary
        REBOOT_REQUIRED=true
    fi
}

update_bun() {
    log_section "Bun Runtime"

    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        log_item "skip" "Bun" "disabled via --no-runtime / category selection"
        return 0
    fi

    local bun_bin="$HOME/.bun/bin/bun"

    if [[ ! -x "$bun_bin" ]]; then
        log_item "skip" "Bun" "not installed"
        return 0
    fi

    # Capture version before update
    capture_version_before "bun"

    run_cmd "Bun self-upgrade" "$bun_bin" upgrade

    # Capture version after and log if changed (don't use log_item "ok" to avoid double-counting)
    if capture_version_after "bun"; then
        [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[bun]}" "${VERSION_AFTER[bun]}"
    fi
}

update_agents() {
    log_section "Coding Agents"

    if [[ "$UPDATE_AGENTS" != "true" ]]; then
        log_item "skip" "agents update" "disabled via --no-agents"
        return 0
    fi

    # Claude Code - can update without bun; supports install/reinstall with --force.
    #
    # Check for bun-installed Claude and remove it if native install is requested.
    # The native install goes to ~/.local/bin/claude which should take precedence,
    # but having both can cause PATH confusion and doctor warnings.
    local claude_path=""
    claude_path=$(command -v claude 2>/dev/null) || true
    local bun_claude_detected=false

    # Check if claude is bun-installed. This can happen in two ways:
    # 1. Direct path: ~/.bun/bin/claude
    # 2. Symlink: ~/.local/bin/claude -> ~/.bun/bin/claude (created by installer)
    # We need to resolve symlinks to detect case 2.
    if [[ -n "$claude_path" ]]; then
        local resolved_path="$claude_path"
        if [[ -L "$claude_path" ]]; then
            resolved_path=$(readlink -f "$claude_path" 2>/dev/null) || resolved_path="$claude_path"
        fi
        if [[ "$claude_path" == *".bun"* || "$claude_path" == *"node_modules"* || \
              "$resolved_path" == *".bun"* || "$resolved_path" == *"node_modules"* ]]; then
            bun_claude_detected=true
        fi
    fi

    if [[ "$bun_claude_detected" == "true" ]] && [[ "$FORCE_MODE" == "true" ]]; then
        log_to_file "Removing bun-installed Claude to switch to native version: $claude_path"
        local bun_bin="$HOME/.bun/bin/bun"
        if [[ -x "$bun_bin" ]]; then
            # Try to uninstall via bun
            "$bun_bin" remove -g @anthropic-ai/claude-code 2>/dev/null || true
        fi
        # Also remove the symlink/binary directly if it still exists
        if [[ -f "$claude_path" || -L "$claude_path" ]]; then
            rm -f "$claude_path" 2>/dev/null || true
        fi
        # Remove the actual bun binary too if it's separate from the symlink
        local bun_claude_bin="$HOME/.bun/bin/claude"
        if [[ -f "$bun_claude_bin" || -L "$bun_claude_bin" ]] && [[ "$bun_claude_bin" != "$claude_path" ]]; then
            rm -f "$bun_claude_bin" 2>/dev/null || true
        fi
        # Clear the cached path so we detect as "not installed" for fresh install
        claude_path=""
    fi

    if cmd_exists claude && [[ "$bun_claude_detected" != "true" || "$FORCE_MODE" != "true" ]]; then
        capture_version_before "claude"

        # Try native update first
        if ! run_cmd_claude_update; then
            log_to_file "Claude update failed, attempting reinstall via official installer"
            if update_require_security; then
                # INTENTIONAL: verified installer is the correct fallback for failed updates
                run_cmd "Claude Code (reinstall)" update_run_verified_installer claude latest
            else
                log_item "fail" "Claude Code" "update failed and reinstall unavailable (missing security.sh)"
            fi
        fi

        # Show version change without double-counting (run_cmd already incremented SUCCESS_COUNT)
        if capture_version_after "claude"; then
            [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[claude]}" "${VERSION_AFTER[claude]}"
        fi
    elif [[ "$FORCE_MODE" == "true" ]]; then
        capture_version_before "claude"
        if update_require_security; then
            # INTENTIONAL: verified installer is the correct path for fresh installs
            run_cmd "Claude Code (install)" update_run_verified_installer claude latest
            if capture_version_after "claude"; then
                [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[claude]}" "${VERSION_AFTER[claude]}"
            fi
        else
            log_item "fail" "Claude Code" "not installed and install unavailable (missing security.sh/checksums.yaml)"
        fi
    else
        log_item "skip" "Claude Code" "not installed (use --force to install)"
    fi

    local bun_bin="$HOME/.bun/bin/bun"
    if [[ ! -x "$bun_bin" ]]; then
        log_item "fail" "Bun not installed" "required for Codex/Gemini updates"
        return 0
    fi

    # Codex CLI via bun (--trust allows postinstall scripts)
    # Uses fallback chain: @latest -> unversioned -> pinned 0.87.0
    # npm can 404 briefly after publishing; pinned version is reliable fallback
    if cmd_exists codex || [[ "$FORCE_MODE" == "true" ]]; then
        local codex_bin_local="$HOME/.local/bin/codex"
        local codex_bin_bun="$HOME/.bun/bin/codex"
        local codex_fallback_version="0.87.0"

        capture_version_before "codex"
        run_cmd_bun_with_retry "Codex CLI" "$bun_bin" install -g --trust @openai/codex@latest

        if [[ ! -x "$codex_bin_local" && ! -x "$codex_bin_bun" ]]; then
            log_item "warn" "Codex CLI" "latest tag failed; retrying @openai/codex"
            run_cmd_bun_with_retry "Codex CLI (fallback)" "$bun_bin" install -g --trust @openai/codex
        fi

        if [[ ! -x "$codex_bin_local" && ! -x "$codex_bin_bun" ]]; then
            log_item "warn" "Codex CLI" "unversioned failed; retrying pinned $codex_fallback_version"
            run_cmd_bun_with_retry "Codex CLI (pinned)" "$bun_bin" install -g --trust "@openai/codex@$codex_fallback_version"
        fi

        # Show version change without double-counting
        if capture_version_after "codex"; then
            [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[codex]}" "${VERSION_AFTER[codex]}"
        fi
    else
        log_item "skip" "Codex CLI" "not installed (use --force to install)"
    fi

    # Gemini CLI via bun (--trust allows postinstall scripts)
    if cmd_exists gemini || [[ "$FORCE_MODE" == "true" ]]; then
        capture_version_before "gemini"
        run_cmd_bun_with_retry "Gemini CLI" "$bun_bin" install -g --trust @google/gemini-cli@latest
        # Show version change without double-counting
        if capture_version_after "gemini"; then
            [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[gemini]}" "${VERSION_AFTER[gemini]}"
        fi
        # Apply Gemini CLI patches (EBADF crash fix, rate-limit retry, quota retry)
        log_item "run" "Gemini CLI patches" "EBADF, retry, quota"
        curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/fix-gemini-cli-ebadf-crash.sh | bash 2>&1 | tail -5 || true
    else
        log_item "skip" "Gemini CLI" "not installed (use --force to install)"
    fi
}

# Helper for Claude update with proper error handling
# FIX(bd-gsjqf.2): Replaced bare "claude update --channel latest" (flag does not exist)
# with update_run_verified_installer which uses the official install.sh script.
# See: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues/125
run_cmd_claude_update() {
    local desc="Claude Code (verified installer)"
    local cmd_display="update_run_verified_installer claude latest"

    log_to_file "Running: $cmd_display"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "skip" "$desc" "dry-run: $cmd_display"
        return 0
    fi

    log_item "run" "$desc"

    local exit_code=0

    if [[ "$VERBOSE" == "true" ]]; then
        if [[ -n "${UPDATE_LOG_FILE:-}" ]]; then
            {
                echo ""
                echo "----- COMMAND: $cmd_display"
            } >> "$UPDATE_LOG_FILE"
        fi

        if [[ "$QUIET" != "true" ]] && [[ -n "${UPDATE_LOG_FILE:-}" ]]; then
            if update_run_verified_installer claude latest 2>&1 | tee -a "$UPDATE_LOG_FILE"; then
                exit_code=0
            else
                exit_code=${PIPESTATUS[0]}
            fi
        elif [[ -n "${UPDATE_LOG_FILE:-}" ]]; then
            if update_run_verified_installer claude latest >> "$UPDATE_LOG_FILE" 2>&1; then
                exit_code=0
            else
                exit_code=$?
            fi
        else
            if [[ "$QUIET" != "true" ]]; then
                update_run_verified_installer claude latest || exit_code=$?
            else
                update_run_verified_installer claude latest >/dev/null 2>&1 || exit_code=$?
            fi
        fi
    else
        local output=""
        output=$(update_run_verified_installer claude latest 2>&1) || exit_code=$?
        [[ -n "$output" ]] && log_to_file "Output: $output"
    fi

    if [[ $exit_code -eq 0 ]]; then
        if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
            echo -e "\033[1A\033[2K  ${GREEN}[ok]${NC} $desc"
        elif [[ "$QUIET" != "true" ]]; then
            echo -e "  ${GREEN}[ok]${NC} $desc"
        fi
        log_to_file "Success: $desc"
        ((SUCCESS_COUNT += 1))
        return 0
    else
        if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
            echo -e "\033[1A\033[2K  ${YELLOW}[retry]${NC} $desc"
        elif [[ "$QUIET" != "true" ]]; then
            echo -e "  ${YELLOW}[retry]${NC} $desc"
        fi
        log_to_file "Failed: $desc (exit code: $exit_code), will try reinstall"
        return 1
    fi
}

supabase_release_update_script() {
    cat <<'EOF'
set -euo pipefail

CURL_ARGS=(-fsSL)
if command -v curl &>/dev/null && curl --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi

arch=""
case "$(uname -m)" in
  x86_64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *)
    echo "Supabase CLI: unsupported architecture ($(uname -m))" >&2
    exit 1
    ;;
esac

release_url="$(curl "${CURL_ARGS[@]}" -o /dev/null -w '%{url_effective}\n' "https://github.com/supabase/cli/releases/latest" 2>/dev/null | tail -n1)" || true
tag="${release_url##*/}"
if [[ -z "$tag" ]] || [[ "$tag" != v* ]]; then
  echo "Supabase CLI: failed to resolve latest release tag" >&2
  exit 1
fi

version="${tag#v}"
base_url="https://github.com/supabase/cli/releases/download/${tag}"
tarball="supabase_linux_${arch}.tar.gz"
checksums="supabase_${version}_checksums.txt"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/acfs-supabase.XXXXXX" 2>/dev/null)" || tmp_dir=""
tmp_tgz="$(mktemp "${TMPDIR:-/tmp}/acfs-supabase.tgz.XXXXXX" 2>/dev/null)" || tmp_tgz=""
tmp_checksums="$(mktemp "${TMPDIR:-/tmp}/acfs-supabase.sha.XXXXXX" 2>/dev/null)" || tmp_checksums=""

if [[ -z "$tmp_dir" ]] || [[ -z "$tmp_tgz" ]] || [[ -z "$tmp_checksums" ]]; then
  echo "Supabase CLI: failed to create temp files" >&2
  exit 1
fi

if ! curl "${CURL_ARGS[@]}" -o "$tmp_tgz" "${base_url}/${tarball}" 2>/dev/null; then
  echo "Supabase CLI: failed to download ${tarball}" >&2
  exit 1
fi
if ! curl "${CURL_ARGS[@]}" -o "$tmp_checksums" "${base_url}/${checksums}" 2>/dev/null; then
  echo "Supabase CLI: failed to download checksums" >&2
  exit 1
fi

expected_sha="$(awk -v tb="$tarball" '$2 == tb {print $1; exit}' "$tmp_checksums" 2>/dev/null)"
if [[ -z "$expected_sha" ]]; then
  echo "Supabase CLI: checksum entry not found for ${tarball}" >&2
  exit 1
fi

actual_sha=""
if command -v sha256sum &>/dev/null; then
  actual_sha="$(sha256sum "$tmp_tgz" | awk '{print $1}')"
elif command -v shasum &>/dev/null; then
  actual_sha="$(shasum -a 256 "$tmp_tgz" | awk '{print $1}')"
else
  echo "Supabase CLI: no SHA256 tool available (need sha256sum or shasum)" >&2
  exit 1
fi

if [[ -z "$actual_sha" ]] || [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "Supabase CLI: checksum mismatch" >&2
  echo "  Expected: $expected_sha" >&2
  echo "  Actual:   ${actual_sha:-<missing>}" >&2
  exit 1
fi

if ! tar -xzf "$tmp_tgz" -C "$tmp_dir" --no-same-owner --no-same-permissions supabase 2>/dev/null; then
  tar -xzf "$tmp_tgz" -C "$tmp_dir" --no-same-owner --no-same-permissions 2>/dev/null || {
    echo "Supabase CLI: failed to extract tarball" >&2
    exit 1
  }
fi

extracted_bin="$tmp_dir/supabase"
if [[ ! -f "$extracted_bin" ]]; then
  extracted_bin="$(find "$tmp_dir" -maxdepth 2 -type f -name supabase -print -quit 2>/dev/null || true)"
fi
if [[ -z "$extracted_bin" ]] || [[ ! -f "$extracted_bin" ]]; then
  echo "Supabase CLI: binary not found after extract" >&2
  exit 1
fi

mkdir -p "$HOME/.local/bin"
install -m 0755 "$extracted_bin" "$HOME/.local/bin/supabase"

if command -v timeout &>/dev/null; then
  timeout 5 "$HOME/.local/bin/supabase" --version >/dev/null 2>&1 || {
    echo "Supabase CLI: installed but failed to run" >&2
    exit 1
  }
else
  "$HOME/.local/bin/supabase" --version >/dev/null 2>&1 || {
    echo "Supabase CLI: installed but failed to run" >&2
    exit 1
  }
fi

# Best-effort cleanup
rm -f "$tmp_tgz" "$tmp_checksums" "$extracted_bin" 2>/dev/null || true
rmdir "$tmp_dir" 2>/dev/null || true
EOF
}

update_cloud() {
    log_section "Cloud CLIs"

    if [[ "$UPDATE_CLOUD" != "true" ]]; then
        log_item "skip" "cloud CLIs update" "disabled via --no-cloud"
        return 0
    fi

    local bun_bin="$HOME/.bun/bin/bun"
    local has_bun=false
    [[ -x "$bun_bin" ]] && has_bun=true

    # Wrangler (--trust allows postinstall scripts for native binaries)
    if cmd_exists wrangler || [[ "$FORCE_MODE" == "true" ]]; then
        if [[ "$has_bun" == "true" ]]; then
            run_cmd_bun_with_retry "Wrangler (Cloudflare)" "$bun_bin" install -g --trust wrangler@latest
        else
            log_item "fail" "Wrangler (Cloudflare)" "bun not installed (required)"
        fi
    else
        log_item "skip" "Wrangler" "not installed"
    fi

    # Supabase (verified GitHub release binary; installed to ~/.local/bin)
    if cmd_exists supabase || [[ "$FORCE_MODE" == "true" ]]; then
        capture_version_before "supabase"
        run_cmd "Supabase CLI" bash -c "$(supabase_release_update_script)"
        # Refresh PATH in case ~/.local/bin was created during install.
        ensure_path
        if capture_version_after "supabase"; then
            [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[supabase]}" "${VERSION_AFTER[supabase]}"
        fi
    else
        log_item "skip" "Supabase CLI" "not installed"
    fi

    # Vercel (--trust allows postinstall scripts for native binaries)
    if cmd_exists vercel || [[ "$FORCE_MODE" == "true" ]]; then
        if [[ "$has_bun" == "true" ]]; then
            run_cmd_bun_with_retry "Vercel CLI" "$bun_bin" install -g --trust vercel@latest
        else
            log_item "fail" "Vercel CLI" "bun not installed (required)"
        fi
    else
        log_item "skip" "Vercel CLI" "not installed"
    fi

    # GitHub CLI (gh) - update extensions
    if cmd_exists gh; then
        capture_version_before "gh"
        # Update gh extensions if any are installed
        local gh_extensions=0
        gh_extensions=$(gh extension list 2>/dev/null | wc -l || true)
        gh_extensions=$((gh_extensions + 0))  # Strip whitespace, ensure integer
        if [[ $gh_extensions -gt 0 ]]; then
            run_cmd "GitHub CLI extensions" gh extension upgrade --all
        else
            log_item "ok" "GitHub CLI" "no extensions to update"
        fi
        # gh itself is updated via apt, log current version
        if capture_version_after "gh"; then
            [[ "$QUIET" != "true" ]] && printf "       ${DIM}version: %s${NC}\n" "${VERSION_AFTER[gh]}"
        fi
    else
        log_item "skip" "GitHub CLI" "not installed"
    fi

    # Google Cloud SDK (gcloud)
    if cmd_exists gcloud; then
        capture_version_before "gcloud"
        # gcloud components update requires --quiet for non-interactive
        run_cmd "Google Cloud SDK" gcloud components update --quiet
        if capture_version_after "gcloud"; then
            [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[gcloud]}" "${VERSION_AFTER[gcloud]}"
        fi
    else
        log_item "skip" "Google Cloud SDK" "not installed"
    fi
}

update_rust() {
    log_section "Rust Toolchain"

    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        log_item "skip" "Rust" "disabled via --no-runtime / category selection"
        return 0
    fi

    local rustup_bin="$HOME/.cargo/bin/rustup"

    if [[ ! -x "$rustup_bin" ]]; then
        log_item "skip" "Rust" "not installed"
        return 0
    fi

    # Capture version before update
    capture_version_before "rust"

    # Update stable toolchain
    run_cmd "Rust stable" "$rustup_bin" update stable

    # Check if nightly is installed and update it too
    if "$rustup_bin" toolchain list 2>/dev/null | grep -q "^nightly"; then
        run_cmd "Rust nightly" "$rustup_bin" update nightly
    fi

    # Update rustup itself
    run_cmd "rustup self-update" "$rustup_bin" self update

    # Show version change without double-counting
    if capture_version_after "rust"; then
        [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[rust]}" "${VERSION_AFTER[rust]}"
    fi

    # Log installed toolchains
    local toolchains
    toolchains=$("$rustup_bin" toolchain list 2>/dev/null | tr '\n' ', ' | sed 's/, $//')
    log_to_file "Installed toolchains: $toolchains"
}

update_cargo_tools() {
    log_section "Cargo Tools"

    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        log_item "skip" "Cargo tools" "disabled via --no-runtime / category selection"
        return 0
    fi

    local cargo_bin="$HOME/.cargo/bin/cargo"
    if [[ ! -x "$cargo_bin" ]]; then
        log_item "skip" "Cargo tools" "cargo not found"
        return 0
    fi

    # Tools to update via cargo install
    # Format: package_name|binary_name
    local tools=("ast-grep|sg" "lsd|lsd" "du-dust|dust" "tealdeer|tldr")

    for entry in "${tools[@]}"; do
        local tool="${entry%|*}"
        local binary_name="${entry#*|}"

        if ! command -v "$binary_name" &>/dev/null && [[ ! -x "$HOME/.cargo/bin/$binary_name" ]]; then
            continue
        fi

        capture_version_before "$binary_name"
        
        # force is required to update existing install with cargo
        # Use run_cmd to log and handle errors
        run_cmd "Update $tool" "$cargo_bin" install "$tool" --locked --force

        if capture_version_after "$binary_name"; then
             [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[$binary_name]}" "${VERSION_AFTER[$binary_name]}"
        fi
    done
}

update_uv() {
    log_section "Python Tools (uv)"

    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        log_item "skip" "uv" "disabled via --no-runtime / category selection"
        return 0
    fi

    local uv_bin="$HOME/.local/bin/uv"

    if [[ ! -x "$uv_bin" ]]; then
        log_item "skip" "uv" "not installed"
        return 0
    fi

    # Capture version before update
    capture_version_before "uv"

    run_cmd "uv self-update" "$uv_bin" self update

    # Show version change without double-counting
    if capture_version_after "uv"; then
        [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[uv]}" "${VERSION_AFTER[uv]}"
    fi
}

update_go() {
    log_section "Go Runtime"

    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        log_item "skip" "Go" "disabled via --no-runtime / category selection"
        return 0
    fi

    # Check if go is installed
    if ! command -v go &>/dev/null; then
        log_item "skip" "Go" "not installed"
        return 0
    fi

    # Determine how Go was installed
    local go_path
    go_path=$(command -v go 2>/dev/null || true)

    # Check if it's apt-managed (system install)
    if [[ "$go_path" == "/usr/bin/go" ]] || [[ "$go_path" == "/usr/local/go/bin/go" ]]; then
        # System install - apt handles it, or manual install
        if dpkg -l golang-go &>/dev/null 2>&1; then
            log_item "ok" "Go" "apt-managed (updated via apt upgrade)"
            log_to_file "Go is managed by apt, skipping dedicated update"
        else
            log_item "skip" "Go" "manual install, update manually from golang.org"
            log_to_file "Go appears to be manually installed at $go_path"
        fi
        return 0
    fi

    # Check for goenv or similar version managers
    if [[ -d "$HOME/.goenv" ]]; then
        log_item "skip" "Go" "managed by goenv, use goenv to update"
        return 0
    fi

    # For other installations, just log the version
    local go_version
    go_version=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')
    log_item "ok" "Go $go_version" "no auto-update available"
    log_to_file "Go version: $go_version (path: $go_path)"
}

update_stack() {
    log_section "Dicklesworthstone Stack"

    if [[ "$UPDATE_STACK" != "true" ]]; then
        log_item "skip" "stack update" "disabled via --no-stack"
        return 0
    fi

    if ! update_require_security; then
        log_item "fail" "stack updates" "security verification unavailable (missing security.sh/checksums.yaml)"
        return 0
    fi

    # Brenner Bot - MUST run BEFORE individual tool installs (NTM, CASS, CM, etc.)
    # because Brenner Bot's installer bundles and pins its own copies of these tools
    # at older versions. By running it first, its pinned deps get laid down, then the
    # individual tool updates below bring them to the latest versions.
    run_cmd "Brenner Bot" update_run_verified_installer brenner_bot

    # NTM - always install/update (installer is idempotent)
    run_cmd "NTM" update_run_verified_installer ntm

    # MCP Agent Mail - always install/update (requires tmux for server process)
    # Fix: Track installer exit code via status file instead of trusting
    # tmux new-session -d exit code (which only reflects session creation).
    if cmd_exists tmux; then
        local tool="mcp_agent_mail"
        local url="${KNOWN_INSTALLERS[$tool]:-}"
        local expected_sha256
        expected_sha256="$(get_checksum "$tool")"

        if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
            # Fetch and verify content first
            local tmp_install
            tmp_install=$(mktemp "${TMPDIR:-/tmp}/acfs-install-am.XXXXXX" 2>/dev/null) || tmp_install=""
            if [[ -z "$tmp_install" ]]; then
                log_item "fail" "MCP Agent Mail" "failed to create temp file for verified installer"
            else
                if verify_checksum "$url" "$expected_sha256" "$tool" > "$tmp_install"; then
                    chmod +x "$tmp_install"

                    local tmux_session="acfs-services"
                    # Kill old session if exists
                    tmux kill-session -t "$tmux_session" 2>/dev/null || true

                    # Use a status file to track the installer's actual exit code.
                    # tmux new-session -d returns 0 for session creation regardless
                    # of whether the payload succeeds (issue #148).
                    local status_file
                    status_file=$(mktemp "${TMPDIR:-/tmp}/acfs-am-status.XXXXXX" 2>/dev/null) || status_file=""

                    if [[ -n "$status_file" ]]; then
                        log_item "run" "MCP Agent Mail (tmux)"

                        # Wrap the installer: run it, write exit code to status file
                        tmux new-session -d -s "$tmux_session" \
                            "bash -c '\"$tmp_install\" --dir \"$HOME/mcp_agent_mail\" --yes; echo \$? > \"$status_file\"'"

                        # Wait for the tmux session to finish (up to 300s / 5 min)
                        local waited=0
                        local max_wait=300
                        while tmux has-session -t "$tmux_session" 2>/dev/null && [[ $waited -lt $max_wait ]]; do
                            sleep 2
                            waited=$((waited + 2))
                        done

                        # Check installer exit code from status file
                        if [[ -f "$status_file" ]] && [[ -s "$status_file" ]]; then
                            local installer_rc
                            installer_rc=$(cat "$status_file")
                            if [[ "$installer_rc" == "0" ]]; then
                                if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
                                    printf "\033[1A\033[2K  ${GREEN}[ok]${NC} %s\n" "MCP Agent Mail (tmux)"
                                elif [[ "$QUIET" != "true" ]]; then
                                    printf "  ${GREEN}[ok]${NC} %s\n" "MCP Agent Mail (tmux)"
                                fi
                                log_to_file "Success: MCP Agent Mail (tmux)"
                                ((SUCCESS_COUNT += 1))
                            else
                                if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
                                    printf "\033[1A\033[2K  ${RED}[fail]${NC} %s\n" "MCP Agent Mail (tmux)"
                                else
                                    printf "  ${RED}[fail]${NC} %s\n" "MCP Agent Mail (tmux)"
                                fi
                                log_to_file "Failed: MCP Agent Mail installer exited with code $installer_rc"
                                ((FAIL_COUNT += 1))
                            fi
                        elif [[ $waited -ge $max_wait ]]; then
                            # Timed out waiting
                            if [[ "$QUIET" != "true" ]]; then
                                printf "  ${YELLOW}[warn]${NC} %s\n" "MCP Agent Mail (tmux) - timed out after ${max_wait}s"
                            fi
                            log_to_file "Warning: MCP Agent Mail tmux session timed out after ${max_wait}s"
                            ((FAIL_COUNT += 1))
                            tmux kill-session -t "$tmux_session" 2>/dev/null || true
                        else
                            # Session ended but no status file - treat as failure
                            if [[ "$QUIET" != "true" ]]; then
                                printf "  ${RED}[fail]${NC} %s\n" "MCP Agent Mail (tmux) - no exit status"
                            fi
                            log_to_file "Failed: MCP Agent Mail - tmux session ended without writing status"
                            ((FAIL_COUNT += 1))
                        fi
                        rm -f "$status_file"
                    else
                        # Fallback: can't create status file, use old fire-and-forget
                        run_cmd "MCP Agent Mail (tmux)" tmux new-session -d -s "$tmux_session" "$tmp_install" --dir "$HOME/mcp_agent_mail" --yes
                        if tmux has-session -t "$tmux_session" 2>/dev/null; then
                            log_to_file "Started MCP Agent Mail update in tmux session: $tmux_session (no exit tracking)"
                            [[ "$QUIET" != "true" ]] && printf "       ${DIM}Update running in tmux session '%s' (exit tracking unavailable)${NC}\n" "$tmux_session"
                        fi
                    fi

                    # Cleanup happens when system tmp is cleaned
                else
                    rm -f "$tmp_install"
                    log_item "fail" "MCP Agent Mail" "verification failed"
                fi
            fi
        else
            log_item "fail" "MCP Agent Mail" "unknown installer URL/checksum"
        fi
    else
        log_item "skip" "MCP Agent Mail" "tmux not found (required for install)"
    fi

    # Meta Skill (ms) - always install/update (installer is idempotent)
    run_cmd "Meta Skill" update_run_verified_installer ms --easy-mode

    # APR (Automated Plan Reviser Pro) - always install/update
    run_cmd "APR" update_run_verified_installer apr --easy-mode

    # Process Triage (pt) - always install/update
    run_cmd "Process Triage" update_run_verified_installer pt

    # xf (X Archive Search) - always install/update
    run_cmd "xf" update_run_verified_installer xf --easy-mode

    # JeffreysPrompts (jfp) - only update if already installed
    # Note: JFP requires a paid subscription to jeffreysprompts.com
    if cmd_exists jfp; then
        run_cmd "JeffreysPrompts" update_run_verified_installer jfp
    fi

    # UBS - always install/update (installer is idempotent)
    run_cmd "Ultimate Bug Scanner" update_run_verified_installer ubs --easy-mode

    # Beads Viewer - always install/update
    run_cmd "Beads Viewer" update_run_verified_installer bv

    # Beads Rust (br) - local issue tracker CLI - always install/update
    run_cmd "Beads Rust" update_run_verified_installer br

    # CASS - always install/update
    run_cmd "CASS" update_run_verified_installer cass --easy-mode --verify

    # CASS Memory - always install/update
    run_cmd "CASS Memory" update_run_verified_installer cm --easy-mode --verify

    # CAAM - always install/update
    run_cmd "CAAM" update_run_verified_installer caam

    # SLB - always install/update
    run_cmd "SLB" update_run_verified_installer slb

    # RU (Repo Updater) - always install/update
    run_cmd "RU" update_run_verified_installer ru --easy-mode

    # DCG (Destructive Command Guard) - always install/update
    run_cmd "DCG" update_run_verified_installer dcg --easy-mode
    # Re-register hook after install/update to ensure latest version is active
    if cmd_exists dcg && cmd_exists claude; then
        run_cmd "DCG Hook" dcg install --force 2>/dev/null || true
    fi

    # RCH (Remote Compilation Helper) - always install/update
    run_cmd "RCH" update_run_verified_installer rch

    # GIIL (Google Image Inline Linker) - always install/update
    run_cmd "GIIL" update_run_verified_installer giil

    # CSCTF (Chat Shared Conversation To File) - always install/update
    run_cmd "CSCTF" update_run_verified_installer csctf

    # SRPS (System Resource Protection Script) - always install/update
    run_cmd "SRPS" update_run_verified_installer srps

    # TRU (Toon Rust) - always install/update
    run_cmd "TRU" update_run_verified_installer tru

    # RANO - always install/update
    run_cmd "RANO" update_run_verified_installer rano

    # MDWB (Markdown Web Browser) - always install/update
    run_cmd "MDWB" update_run_verified_installer mdwb

    # S2P (Source to Prompt TUI) - always install/update
    run_cmd "S2P" update_run_verified_installer s2p
}

# ============================================================
# Root AGENTS.md Generation
# ============================================================
update_root_agents_md() {
    log_section "Root AGENTS.md"

    if ! cmd_exists flywheel-update-agents-md; then
        log_item "skip" "Root AGENTS.md" "flywheel-update-agents-md not installed"
        return 0
    fi

    run_cmd_sudo "Root AGENTS.md" flywheel-update-agents-md
}

# ============================================================
# Shell Tool Updates
# Related: bead db0
# ============================================================

# Update Oh-My-Zsh via its built-in upgrade script
update_omz() {
    local omz_dir="${ZSH:-$HOME/.oh-my-zsh}"

    if [[ ! -d "$omz_dir" ]]; then
        log_item "skip" "Oh-My-Zsh" "not installed"
        return 0
    fi

    capture_version_before "omz"

    # OMZ has its own upgrade script that handles everything
    # Set DISABLE_UPDATE_PROMPT to avoid interactive prompts
    local upgrade_script="$omz_dir/tools/upgrade.sh"
    if [[ -x "$upgrade_script" ]]; then
        run_cmd "Oh-My-Zsh upgrade" timeout 120 env DISABLE_UPDATE_PROMPT=true ZSH="$omz_dir" "$upgrade_script"
    elif [[ -f "$upgrade_script" ]]; then
        run_cmd "Oh-My-Zsh upgrade" timeout 120 env DISABLE_UPDATE_PROMPT=true ZSH="$omz_dir" bash "$upgrade_script"
    else
        # Fallback to git pull
        if [[ -d "$omz_dir/.git" ]]; then
            run_cmd "Oh-My-Zsh (git pull)" timeout 60 git -C "$omz_dir" pull --ff-only
        else
            log_item "skip" "Oh-My-Zsh" "no upgrade mechanism found"
            return 0
        fi
    fi

    # Show version change without double-counting
    if capture_version_after "omz"; then
        [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[omz]}" "${VERSION_AFTER[omz]}"
    fi
}

# Update Powerlevel10k theme via git
update_p10k() {
    local p10k_dir="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/themes/powerlevel10k"

    if [[ ! -d "$p10k_dir" ]]; then
        log_item "skip" "Powerlevel10k" "not installed"
        return 0
    fi

    if [[ ! -d "$p10k_dir/.git" ]]; then
        log_item "skip" "Powerlevel10k" "not a git repo"
        return 0
    fi

    capture_version_before "p10k"

    # Use --ff-only to avoid merge conflicts
    local output=""
    local exit_code=0
    output=$(timeout 60 git -C "$p10k_dir" pull --ff-only 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        if capture_version_after "p10k"; then
            log_item "ok" "Powerlevel10k updated" "${VERSION_BEFORE[p10k]} → ${VERSION_AFTER[p10k]}"
        else
            log_item "ok" "Powerlevel10k" "already up to date"
        fi
    else
        # Check if it's a ff-only failure (local changes)
        if echo "$output" | grep -q "fatal.*not possible to fast-forward"; then
            log_item "skip" "Powerlevel10k" "local changes detected, manual merge required"
            log_to_file "P10K update failed: $output"
        else
            log_item "fail" "Powerlevel10k" "git pull failed"
            log_to_file "P10K update failed: $output"
            # Note: log_item "fail" already increments FAIL_COUNT
        fi
    fi
}

# Update zsh plugins via git
update_zsh_plugins() {
    local zsh_custom="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}"
    local plugins_dir="$zsh_custom/plugins"

    # Known plugins to update
    local -a plugins=(
        "zsh-autosuggestions"
        "zsh-syntax-highlighting"
        "zsh-completions"
        "zsh-history-substring-search"
    )

    local updated=0
    local skipped=0

    for plugin in "${plugins[@]}"; do
        local plugin_dir="$plugins_dir/$plugin"

        if [[ ! -d "$plugin_dir" ]]; then
            continue
        fi

        if [[ ! -d "$plugin_dir/.git" ]]; then
            log_item "warn" "$plugin" "not a git repo (skipped)"
            log_to_file "Plugin $plugin exists but is not a git repo"
            continue
        fi

        local output=""
        local exit_code=0
        output=$(timeout 60 git -C "$plugin_dir" pull --ff-only 2>&1) || exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            if ! echo "$output" | grep -q "Already up to date"; then
                log_item "ok" "$plugin" "updated"
                ((updated += 1))
            else
                ((skipped += 1))
            fi
        else
            if echo "$output" | grep -q "fatal.*not possible to fast-forward"; then
                log_item "skip" "$plugin" "local changes"
            else
                log_item "fail" "$plugin" "git pull failed"
                log_to_file "$plugin update failed: $output"
            fi
        fi
    done

    if [[ $updated -eq 0 && $skipped -gt 0 ]]; then
        log_item "ok" "zsh plugins" "$skipped plugins already up to date"
    elif [[ $updated -eq 0 && $skipped -eq 0 ]]; then
        log_item "skip" "zsh plugins" "no plugins installed"
    fi
}

# Update Atuin - try self-update first, fallback to installer
update_atuin() {
    if ! cmd_exists atuin; then
        log_item "skip" "Atuin" "not installed"
        return 0
    fi

    capture_version_before "atuin"

    # Try atuin self-update first (available in newer versions)
    if atuin --help 2>&1 | grep -q "self-update"; then
        run_cmd "Atuin self-update" atuin self-update
    else
        # Fallback to reinstall via official installer with checksum verification
        if update_require_security; then
            run_cmd "Atuin (reinstall)" update_run_verified_installer atuin
        else
            # Last resort: no checksum verification available
            if [[ "$YES_MODE" == "true" ]]; then
                log_item "skip" "Atuin" "checksum verification unavailable (missing security.sh/checksums.yaml)"
            else
                log_item "skip" "Atuin" "no self-update command, manual update recommended"
                local curl_cmd="curl -fsSL"
                if command -v curl &>/dev/null && curl --help all 2>/dev/null | grep -q -- '--proto'; then
                    curl_cmd="curl --proto '=https' --proto-redir '=https' -fsSL"
                fi
                log_to_file "Atuin update (manual; review first):"
                log_to_file "  ${curl_cmd} https://setup.atuin.sh -o /tmp/atuin.install.sh"
                log_to_file "  sed -n '1,120p' /tmp/atuin.install.sh"
                log_to_file "  bash /tmp/atuin.install.sh"
            fi
            return 0
        fi
    fi

    # Show version change without double-counting
    if capture_version_after "atuin"; then
        [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[atuin]}" "${VERSION_AFTER[atuin]}"
    fi
}

# Update Zoxide via reinstall (checksum verified)
update_zoxide() {
    if ! cmd_exists zoxide; then
        log_item "skip" "Zoxide" "not installed"
        return 0
    fi

    capture_version_before "zoxide"

    # Zoxide doesn't have self-update, reinstall via official installer
    if update_require_security; then
        run_cmd "Zoxide (reinstall)" update_run_verified_installer zoxide
    else
        log_item "skip" "Zoxide" "checksum verification unavailable (missing security.sh/checksums.yaml)"
        local curl_cmd="curl -fsSL"
        if command -v curl &>/dev/null && curl --help all 2>/dev/null | grep -q -- '--proto'; then
            curl_cmd="curl --proto '=https' --proto-redir '=https' -fsSL"
        fi
        log_to_file "Zoxide update (manual; review first):"
        log_to_file "  ${curl_cmd} https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh -o /tmp/zoxide.install.sh"
        log_to_file "  sed -n '1,120p' /tmp/zoxide.install.sh"
        log_to_file "  bash /tmp/zoxide.install.sh"
        return 0
    fi

    # Show version change without double-counting
    if capture_version_after "zoxide"; then
        [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[zoxide]}" "${VERSION_AFTER[zoxide]}"
    fi
}

# Main shell update dispatcher
update_shell() {
    log_section "Shell Tools"

    if [[ "$UPDATE_SHELL" != "true" ]]; then
        log_item "skip" "shell tools update" "disabled via --no-shell"
        return 0
    fi

    # Git-based updates (OMZ, P10K, plugins)
    update_omz
    update_p10k
    update_zsh_plugins

    # Installer-based updates (Atuin, Zoxide)
    update_atuin
    update_zoxide

    # Keep deployed acfs.zshrc in sync with repo
    sync_acfs_zshrc
}

# ============================================================
# Summary
# ============================================================

print_summary() {
    # Log footer to file
    if [[ -n "$UPDATE_LOG_FILE" ]]; then
        {
            echo ""
            echo "==============================================="
            echo "Summary"
            echo "==============================================="
            echo "Updated: $SUCCESS_COUNT"
            echo "Skipped: $SKIP_COUNT"
            echo "Failed:  $FAIL_COUNT"
            if [[ "$REBOOT_REQUIRED" == "true" ]]; then
                echo "Reboot:  REQUIRED"
            fi
            echo ""
            echo "Completed: $(date -Iseconds)"
            echo "==============================================="
        } >> "$UPDATE_LOG_FILE"
    fi

    # Console output (respects quiet mode for success, always shows failures)
    if [[ "$QUIET" != "true" ]]; then
        echo ""
        echo "============================================================"
        printf "Summary: ${GREEN}%d updated${NC}, ${DIM}%d skipped${NC}, ${RED}%d failed${NC}\n" "$SUCCESS_COUNT" "$SKIP_COUNT" "$FAIL_COUNT"
        echo ""

        if [[ $FAIL_COUNT -eq 0 ]]; then
            printf "${GREEN}All updates completed successfully!${NC}\n"
        else
            printf "${YELLOW}Some updates failed. Check output above.${NC}\n"
        fi

        # Reboot warning
        if [[ "$REBOOT_REQUIRED" == "true" ]]; then
            echo ""
            printf "${YELLOW}${BOLD}⚠ System reboot required${NC}\n"
            printf "${DIM}Run: sudo reboot${NC}\n"
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            echo ""
            printf "${DIM}(dry-run mode - no changes were made)${NC}\n"
        fi

        # Show log location
        if [[ -n "$UPDATE_LOG_FILE" ]]; then
            echo ""
            printf "${DIM}Log: %s${NC}\n" "$UPDATE_LOG_FILE"
        fi
    elif [[ $FAIL_COUNT -gt 0 ]]; then
        # In quiet mode, still report failures
        echo ""
        printf "${RED}Update failed: %d error(s)${NC}\n" "$FAIL_COUNT"
        if [[ -n "$UPDATE_LOG_FILE" ]]; then
            printf "${DIM}See: %s${NC}\n" "$UPDATE_LOG_FILE"
        fi
    fi
}

# ============================================================
# CLI
# ============================================================

usage() {
    cat << 'EOF'
acfs update - Update all ACFS components

USAGE:
  acfs-update [options]
  acfs update [options]    (if acfs wrapper is installed)

CATEGORY OPTIONS (select what to update):
  --apt-only         Only update system packages (apt)
  --agents-only      Only update coding agents (Claude, Codex, Gemini)
  --cloud-only       Only update cloud CLIs (Wrangler, Supabase, Vercel, gh, gcloud)
  --shell-only       Only update shell tools (OMZ, P10K, plugins, Atuin, Zoxide)
  --runtime-only     Only update runtimes (Bun, Rust, uv, Go)
  --stack            Include Dicklesworthstone stack tools (enabled by default)

SKIP OPTIONS (exclude categories from update):
  --no-self-update   Skip ACFS self-update (not recommended)
  --no-apt           Skip apt update/upgrade
  --no-agents        Skip coding agent updates
  --no-cloud         Skip cloud CLI updates
  --no-shell         Skip shell tool updates
  --no-runtime       Skip runtime updates (Bun, Rust, uv, Go)
  --no-stack         Skip Dicklesworthstone stack tool updates

BEHAVIOR OPTIONS:
  --force            Force reinstallation even if already up to date
  --dry-run          Preview changes without making them
  --yes, -y          Non-interactive mode, skip all prompts
  --quiet, -q        Minimal output, only show errors and summary
  --verbose, -v      Show detailed output including command details
  --abort-on-failure Stop immediately on first failure
  --continue         Continue after failures (default)
  --help, -h         Show this help message

EXAMPLES:
  # Standard update (EVERYTHING: apt, runtimes, shell, agents, cloud, stack)
  acfs-update

  # Skip Dicklesworthstone stack updates (faster)
  acfs-update --no-stack

  # Only update agents
  acfs-update --agents-only

  # Only update runtimes
  acfs-update --runtime-only

  # Update everything except apt (faster)
  acfs-update --no-apt

  # Preview what would be updated
  acfs-update --dry-run

  # Automated CI/cron mode
  acfs-update --yes --quiet

  # Strict mode: stop on first error
  acfs-update --abort-on-failure

WHAT EACH CATEGORY UPDATES:
  self:     ACFS itself (git pull) - runs FIRST to ensure latest update logic
            If update.sh changes, automatically re-executes with new version
  apt:      System packages via apt update && apt upgrade && apt autoremove
  shell:    Oh-My-Zsh, Powerlevel10k, zsh plugins (git pull)
            Atuin, Zoxide (reinstall from upstream)
  agents:   Claude Code (verified installer: curl claude.ai/install.sh | bash -- latest)
            Codex CLI (bun install -g --trust @openai/codex@latest)
            Gemini CLI (bun install -g --trust @google/gemini-cli@latest)
  cloud:    Wrangler, Vercel (bun install -g --trust <pkg>@latest)
            Supabase CLI (verified GitHub release tarball + sha256 checksums)
            GitHub CLI (gh extension upgrade --all)
            Google Cloud SDK (gcloud components update)
  runtime:  Bun (bun upgrade), Rust (rustup update), uv (uv self update), Go (apt-managed)
  stack:    Dicklesworthstone stack tools (verified upstream installers)
            Installs missing tools and updates existing ones automatically:
            NTM, Agent Mail, Meta Skill, APR, pt, xf, UBS, BV, BR, CASS, CM,
            CAAM, SLB, RU, DCG, RCH, GIIL, CSCTF, SRPS, TRU, RANO, MDWB, S2P, Brenner Bot
            Exception: JFP requires subscription, only updated if already installed

LOGS:
  Update logs are saved to: ~/.acfs/logs/updates/
  Log files are timestamped: YYYY-MM-DD-HHMMSS.log

  Example: tail -f ~/.acfs/logs/updates/$(ls -1t ~/.acfs/logs/updates | head -1)

ENVIRONMENT VARIABLES:
  ACFS_HOME          Base directory for ACFS (default: ~/.acfs)
  ACFS_VERSION       Override version string in logs

TROUBLESHOOTING:
  - If apt is locked: wait for other package operations to finish.
    To see who holds the lock:
      sudo fuser -v /var/lib/dpkg/lock-frontend || true
      sudo systemctl status unattended-upgrades --no-pager || true
    If unattended-upgrades is running, wait for it to complete (recommended),
    or temporarily stop it:
      sudo systemctl stop unattended-upgrades
    (After the update finishes, re-enable it:)
      sudo systemctl start unattended-upgrades

  - If an agent update fails: try running the update command directly:
    curl -fsSL https://claude.ai/install.sh | bash -s -- latest
    bun install -g --trust @openai/codex@latest
    bun install -g --trust @google/gemini-cli@latest

  - If shell tools fail to update: check git remote access:
    git -C ~/.oh-my-zsh remote -v

  - View recent logs:
    ls -lt ~/.acfs/logs/updates/ | head -5
    cat ~/.acfs/logs/updates/LATEST_LOG_FILE

  - Force reinstall a specific tool:
    acfs-update --force --agents-only
EOF
}

main() {
    # Ensure PATH includes user tool directories
    ensure_path

    # Save original arguments before parsing (for re-exec after self-update)
    local -a ACFS_UPDATE_ARGS=("$@")

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --apt-only)
                UPDATE_APT=true
                UPDATE_AGENTS=false
                UPDATE_CLOUD=false
                UPDATE_RUNTIME=false
                UPDATE_STACK=false
                UPDATE_SHELL=false
                shift
                ;;
            --agents-only)
                UPDATE_APT=false
                UPDATE_AGENTS=true
                UPDATE_CLOUD=false
                UPDATE_RUNTIME=false
                UPDATE_STACK=false
                UPDATE_SHELL=false
                shift
                ;;
            --cloud-only)
                UPDATE_APT=false
                UPDATE_AGENTS=false
                UPDATE_CLOUD=true
                UPDATE_RUNTIME=false
                UPDATE_STACK=false
                UPDATE_SHELL=false
                shift
                ;;
            --shell-only)
                UPDATE_APT=false
                UPDATE_AGENTS=false
                UPDATE_CLOUD=false
                UPDATE_RUNTIME=false
                UPDATE_STACK=false
                UPDATE_SHELL=true
                shift
                ;;
            --runtime-only)
                UPDATE_APT=false
                UPDATE_AGENTS=false
                UPDATE_CLOUD=false
                UPDATE_RUNTIME=true
                UPDATE_STACK=false
                UPDATE_SHELL=false
                shift
                ;;
            --stack)
                UPDATE_STACK=true
                shift
                ;;
            --no-apt)
                UPDATE_APT=false
                shift
                ;;
            --no-agents)
                UPDATE_AGENTS=false
                shift
                ;;
            --no-cloud)
                UPDATE_CLOUD=false
                shift
                ;;
            --no-shell)
                UPDATE_SHELL=false
                shift
                ;;
            --no-runtime)
                UPDATE_RUNTIME=false
                shift
                ;;
            --no-stack)
                UPDATE_STACK=false
                shift
                ;;
            --no-self-update)
                UPDATE_SELF=false
                shift
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --quiet|-q)
                QUIET=true
                shift
                ;;
            --yes|-y)
                YES_MODE=true
                shift
                ;;
            --abort-on-failure)
                ABORT_ON_FAILURE=true
                shift
                ;;
            --continue)
                ABORT_ON_FAILURE=false
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Try: acfs update --help" >&2
                exit 1
                ;;
        esac
    done

    # Guard against running as root (unless ACFS is actually installed in /root)
    # This check is placed after argument parsing so --yes works correctly
    if [[ $EUID -eq 0 ]] && [[ "${HOME}" != "/root" ]]; then
        echo -e "${YELLOW}Warning: Running as root but HOME is $HOME.${NC}"
        echo "ACFS update should typically be run as the target user (e.g. ubuntu)."
        if [[ "$YES_MODE" != "true" ]]; then
            read -r -p "Continue anyway? [y/N] " response
            if [[ ! "$response" =~ ^[Yy] ]]; then
                exit 1
            fi
        fi
    fi

    # Self-update ACFS before touching any other components.
    # This runs BEFORE init_logging so we get the latest update logic ASAP.
    # Pass original args so re-exec (if update.sh changed) uses the same arguments.
    update_acfs_self "${ACFS_UPDATE_ARGS[@]}"

    # Initialize logging
    init_logging

    # Header
    if [[ "$QUIET" != "true" ]]; then
        echo ""
        echo -e "${BOLD}ACFS Update v$ACFS_VERSION${NC}"
        echo -e "User: $(whoami)"
        echo -e "Date: $(date '+%Y-%m-%d %H:%M')"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${YELLOW}Mode: dry-run${NC}"
        fi
    fi

    # Set non-interactive mode if --yes was passed
    if [[ "$YES_MODE" == "true" ]]; then
        export ACFS_INTERACTIVE=false
    fi

    # Clean up legacy artifacts from previous versions
    cleanup_legacy_git_safety_guard
    cleanup_legacy_br_alias

    # Run updates
    update_apt
    update_bun
    update_agents
    update_cloud
    update_rust
    update_cargo_tools
    update_uv
    update_go
    update_shell
    update_stack
    update_root_agents_md

    # Summary
    print_summary

    # Exit code
    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
