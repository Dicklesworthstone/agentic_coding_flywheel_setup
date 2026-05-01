#!/usr/bin/env bash
# ============================================================
# ACFS Update - Update All Components
# Updates system packages, agents, cloud CLIs, and stack tools
# ============================================================

set -euo pipefail

# Prevent interactive prompts during apt operations.
# NEEDRESTART_* suppress the post-upgrade "which services to restart?" TUI on
# Ubuntu 22.04+. Exporting alone is insufficient because `sudo` strips env by
# default — the apt calls below pass these vars inline via `env`, and
# update_disable_needrestart_apt_hook() also chmod-x's the apt hook itself.
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

ACFS_VERSION="${ACFS_VERSION:-0.1.0}"
ACFS_REPO_OWNER="${ACFS_REPO_OWNER:-Dicklesworthstone}"
ACFS_REPO_NAME="${ACFS_REPO_NAME:-agentic_coding_flywheel_setup}"
ACFS_CHECKSUMS_REF="${ACFS_CHECKSUMS_REF:-main}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_update_initial_existing_home() {
    local home_candidate="${1:-}"

    [[ -n "$home_candidate" ]] || return 1
    home_candidate="${home_candidate%/}"
    [[ -n "$home_candidate" ]] || return 1
    [[ "$home_candidate" == /* ]] || return 1
    [[ "$home_candidate" != "/" ]] || return 1
    [[ -d "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

_update_early_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    for candidate in \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

_update_early_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(_update_early_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi
    if [[ -z "$current_user" ]]; then
        whoami_bin="$(_update_early_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

_update_early_passwd_home_for_user() {
    local user="${1:-}"
    local passwd_entry=""
    local passwd_line=""
    local passwd_home=""
    local getent_bin=""

    [[ -n "$user" ]] || return 1
    getent_bin="$(_update_early_system_binary_path getent 2>/dev/null || true)"
    if [[ -n "$getent_bin" ]]; then
        passwd_entry="$("$getent_bin" passwd "$user" 2>/dev/null || true)"
    fi
    if [[ -z "$passwd_entry" ]] && [[ -r /etc/passwd ]]; then
        while IFS= read -r passwd_line; do
            [[ "${passwd_line%%:*}" == "$user" ]] || continue
            passwd_entry="$passwd_line"
            break
        done < /etc/passwd
    fi

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    _update_initial_existing_home "$passwd_home"
}

_update_early_runtime_home() {
    local explicit_home=""
    local env_home=""
    local runtime_home=""
    local current_user=""
    local target_user="${TARGET_USER:-}"

    explicit_home="$(_update_initial_existing_home "${TARGET_HOME:-}" 2>/dev/null || true)"
    env_home="$(_update_initial_existing_home "${HOME:-}" 2>/dev/null || true)"
    current_user="$(_update_early_current_user 2>/dev/null || true)"

    if [[ "$target_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$target_user" ]]; then
        [[ "$target_user" =~ ^[a-z_][a-z0-9._-]*$ ]] || return 1
        runtime_home="$(_update_early_passwd_home_for_user "$target_user" 2>/dev/null || true)"
        if [[ -n "$runtime_home" ]]; then
            printf '%s\n' "$runtime_home"
            return 0
        fi

        if [[ "$target_user" == "$current_user" ]]; then
            if [[ -n "$env_home" ]] && { [[ -z "$explicit_home" ]] || [[ "$env_home" == "$explicit_home" ]]; }; then
                printf '%s\n' "$env_home"
                return 0
            fi
            if [[ -n "$explicit_home" ]]; then
                printf '%s\n' "$explicit_home"
                return 0
            fi
        fi

        return 1
    fi

    if [[ -n "$explicit_home" && "$explicit_home" != "$env_home" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    if [[ -n "$env_home" ]]; then
        printf '%s\n' "$env_home"
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        _update_early_passwd_home_for_user "$current_user"
        return $?
    fi

    if [[ -n "$explicit_home" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    return 1
}

_UPDATE_INITIAL_ENV_HOME="$(_update_initial_existing_home "${HOME:-}" 2>/dev/null || true)"
ACFS_INITIAL_ENV_HOME="${ACFS_INITIAL_ENV_HOME:-$_UPDATE_INITIAL_ENV_HOME}"
export ACFS_INITIAL_ENV_HOME
_UPDATE_EARLY_HOME="$(_update_early_runtime_home 2>/dev/null || true)"
if [[ -n "$_UPDATE_EARLY_HOME" ]]; then
    HOME="$_UPDATE_EARLY_HOME"
    export HOME
fi
unset _UPDATE_EARLY_HOME

# Discover ACFS_REPO_ROOT: prefer a real git repo over the tarball install dir.
# On fleet machines, update.sh runs from ~/.acfs/scripts/lib/ (no .git) but
# the authoritative source repo lives at /data/projects/agentic_coding_flywheel_setup.
# Without this, self-update can't pull new code and deployed scripts go stale.
_acfs_discover_repo_root() {
    local script_root
    script_root="$(cd "$SCRIPT_DIR/../.." && pwd)"

    # If the script already lives inside a git repo, use it directly
    if [[ -d "$script_root/.git" ]]; then
        printf '%s\n' "$script_root"
        return 0
    fi

    # Search well-known locations for a git-based ACFS checkout
    local -a candidates=(
        "/data/projects/agentic_coding_flywheel_setup"
        "/dp/agentic_coding_flywheel_setup"
    )
    if [[ -n "${HOME:-}" ]]; then
        candidates+=("$HOME/agentic_coding_flywheel_setup")
    fi
    for candidate in "${candidates[@]}"; do
        if [[ -d "$candidate/.git" ]] && [[ -f "$candidate/scripts/lib/update.sh" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    # Fallback: use script-relative root. If this is not a git checkout,
    # self-update is skipped unless the caller explicitly opts into bootstrap.
    printf '%s\n' "$script_root"
}
ACFS_REPO_ROOT="$(_acfs_discover_repo_root)"

# Track if self-update already ran (prevents re-exec loops)
ACFS_SELF_UPDATE_DONE="${ACFS_SELF_UPDATE_DONE:-false}"

if [[ -f "$ACFS_REPO_ROOT/VERSION" ]]; then
    ACFS_VERSION="$(cat "$ACFS_REPO_ROOT/VERSION" 2>/dev/null || echo "$ACFS_VERSION")"
fi

# Build display version: v0.7.0+a7598d0 (with short commit hash when available)
_acfs_short_hash=""
if command -v git &>/dev/null && [[ -d "$ACFS_REPO_ROOT/.git" ]]; then
    _acfs_short_hash=$(git -C "$ACFS_REPO_ROOT" rev-parse --short HEAD 2>/dev/null) || true
fi
if [[ -n "$_acfs_short_hash" ]]; then
    ACFS_VERSION_DISPLAY="v${ACFS_VERSION}+${_acfs_short_hash}"
else
    ACFS_VERSION_DISPLAY="v${ACFS_VERSION}"
fi
unset _acfs_short_hash

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
UPDATE_LAST_COMMAND_OUTPUT=""

# Flags
UPDATE_APT=true
UPDATE_AGENTS=true
UPDATE_CLOUD=true
UPDATE_RUNTIME=true
UPDATE_STACK=true
UPDATE_SHELL=true
UPDATE_SELF=true
BOOTSTRAP_SELF_UPDATE=false
FORCE_MODE=false
DRY_RUN=false
VERBOSE=false
QUIET=false
YES_MODE=false
ABORT_ON_FAILURE=false
REBOOT_REQUIRED=false

# Logging
UPDATE_LOG_DIR="${UPDATE_LOG_DIR:-${HOME:-/tmp}/.acfs/logs/updates}"
UPDATE_LOG_FILE=""

# Version tracking
declare -gA VERSION_BEFORE=()
declare -gA VERSION_AFTER=()

update_is_read_only_mode() {
    [[ "${DRY_RUN:-false}" == "true" ]]
}

update_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

update_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="$(update_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    base_home="$(update_existing_home "$base_home" 2>/dev/null || true)"

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
    hinted_home="${hinted_home%/}"
    if [[ "$hinted_home" != /* ]] || [[ "$hinted_home" == "/" ]]; then
        hinted_home=""
    fi
    if [[ -n "$hinted_home" ]] && [[ -n "$base_home" ]] && [[ "$hinted_home" != "$base_home" ]]; then
        return 1
    fi

    while IFS= read -r passwd_line; do
        passwd_home="$(update_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        passwd_home="$(update_existing_home "$passwd_home" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(update_getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

# ============================================================
# Path Setup
# ============================================================

ensure_path() {
    local dir
    local to_add=()
    local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
    local current_path="${PATH:-$system_path_prefix}"
    local seen_path=":$current_path:"
    local sanitized_primary_bin=""
    local _primary_bin=""

    sanitized_primary_bin="$(update_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "${HOME:-}" 2>/dev/null || true)"
    _primary_bin="${sanitized_primary_bin:-$HOME/.local/bin}"

    for dir in \
        "$_primary_bin" \
        "$HOME/.local/bin" \
        "$HOME/.acfs/bin" \
        "$HOME/.bun/bin" \
        "$HOME/.cargo/bin" \
        "$HOME/.atuin/bin" \
        "$HOME/go/bin" \
        "$HOME/google-cloud-sdk/bin" \
        "/usr/local/sbin" \
        "/usr/local/bin" \
        "/usr/sbin" \
        "/usr/bin" \
        "/sbin" \
        "/bin" \
        "/snap/bin"; do
        [[ -d "$dir" ]] || continue
        case "$seen_path" in
            *":$dir:"*) ;;
            *)
                to_add+=("$dir")
                seen_path="${seen_path}${dir}:"
                ;;
        esac
    done

    if [[ ${#to_add[@]} -gt 0 ]]; then
        local prefix
        prefix=$(IFS=:; echo "${to_add[*]}")
        export PATH="$prefix${current_path:+:$current_path}"
    fi
}

update_source_stack_lib() {
    local runtime_acfs_home=""
    local candidate=""
    local -a candidates=()

    if declare -f _stack_configure_agent_mail_service >/dev/null 2>&1; then
        return 0
    fi

    runtime_acfs_home="$(update_runtime_acfs_home 2>/dev/null || true)"
    candidates+=("$SCRIPT_DIR/stack.sh")
    [[ -n "$runtime_acfs_home" ]] && candidates+=("$runtime_acfs_home/scripts/lib/stack.sh")
    candidates+=(
        "$ACFS_REPO_ROOT/scripts/lib/stack.sh"
        "/data/projects/agentic_coding_flywheel_setup/scripts/lib/stack.sh"
        "/dp/agentic_coding_flywheel_setup/scripts/lib/stack.sh"
    )

    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" && -r "$candidate" ]] || continue
        # shellcheck source=stack.sh
        source "$candidate"
        log_to_file "Loaded stack.sh from $candidate"
        return 0
    done

    echo "Stack library not found in deployed or repo paths" >&2
    return 1
}

update_preferred_user_bin_dir() {
    local state_file=""
    local bin_dir=""
    local target_user=""
    local target_home=""
    local current_user=""
    local current_state_file=""
    local acfs_home_state_file=""
    local target_state_file=""
    local explicit_bin_dir=""
    local explicit_state_file=""
    local sanitized_acfs_home=""

    target_user="$(update_target_user)"
    target_home="$(update_target_home "$target_user" 2>/dev/null || true)"
    explicit_bin_dir="$(update_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$target_home" 2>/dev/null || true)"
    if [[ -n "$explicit_bin_dir" ]]; then
        printf '%s\n' "$explicit_bin_dir"
        return 0
    fi

    current_user="$(update_current_user)"
    explicit_state_file="$(update_sanitize_abs_nonroot_path "${ACFS_STATE_FILE:-}" 2>/dev/null || true)"
    sanitized_acfs_home="$(update_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
    [[ -n "$sanitized_acfs_home" ]] && acfs_home_state_file="$sanitized_acfs_home/state.json"
    [[ -n "$target_home" ]] && target_state_file="$target_home/.acfs/state.json"
    if [[ "$target_user" == "$current_user" ]] && [[ -n "${HOME:-}" ]] && [[ "${HOME}" == /* ]] && [[ "${HOME}" != "/" ]]; then
        current_state_file="$HOME/.acfs/state.json"
    fi

    for state_file in \
        "$explicit_state_file" \
        "$acfs_home_state_file" \
        "$target_state_file" \
        "$current_state_file" \
        "/var/lib/acfs/state.json"; do
        [[ -n "$state_file" && -f "$state_file" ]] || continue

        if command -v jq &>/dev/null; then
            bin_dir="$(jq -r '.bin_dir // empty' "$state_file" 2>/dev/null || true)"
        else
            bin_dir="$(sed -n 's/.*"bin_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$state_file" | head -n 1)"
        fi

        bin_dir="$(update_validate_bin_dir_for_home "$bin_dir" "$target_home" 2>/dev/null || true)"
        if [[ -n "$bin_dir" ]]; then
            printf '%s\n' "$bin_dir"
            return 0
        fi
    done

    if [[ -n "$target_home" ]]; then
        printf '%s\n' "$target_home/.local/bin"
        return 0
    fi

    return 1
}

update_default_user_bin_dir() {
    local target_user=""
    local target_home=""

    target_user="$(update_target_user)"
    target_home="$(update_target_home "$target_user" 2>/dev/null || true)"
    if [[ -n "$target_home" ]]; then
        printf '%s\n' "$target_home/.local/bin"
        return 0
    fi

    return 1
}

update_runtime_primary_bin_dir() {
    local primary_bin=""
    local target_user_raw="${TARGET_USER:-}"
    local target_user=""
    local current_user=""
    local target_home=""
    local runtime_home=""

    target_user="$(update_target_user 2>/dev/null || true)"
    current_user="$(update_current_user)"
    if [[ -n "$target_user" ]]; then
        target_home="$(update_target_home "$target_user" 2>/dev/null || true)"
    fi

    if [[ -n "$target_user_raw" && -z "$target_user" ]]; then
        return 1
    fi
    if [[ -n "$target_user" ]] && [[ -n "$current_user" ]] && [[ "$target_user" != "$current_user" ]] && [[ -z "$target_home" ]]; then
        return 1
    fi

    primary_bin="$(update_preferred_user_bin_dir 2>/dev/null || true)"
    if [[ -z "$primary_bin" ]]; then
        primary_bin="$(update_default_user_bin_dir 2>/dev/null || true)"
    fi
    if [[ -z "$primary_bin" ]]; then
        runtime_home="$(update_existing_home "${HOME:-}" 2>/dev/null || true)"
        primary_bin="$(update_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$runtime_home" 2>/dev/null || true)"
    fi
    if [[ -z "$primary_bin" ]]; then
        runtime_home="$(update_existing_home "${HOME:-}" 2>/dev/null || true)"
        [[ -n "$runtime_home" ]] || return 1
        primary_bin="$runtime_home/.local/bin"
    fi

    primary_bin="$(update_sanitize_abs_nonroot_path "$primary_bin" 2>/dev/null || true)"
    [[ -n "$primary_bin" ]] || return 1
    printf '%s\n' "$primary_bin"
}


update_runtime_acfs_home() {
    local target_user_raw="${TARGET_USER:-}"
    local target_user=""
    local current_user=""
    local target_home=""
    local runtime_home=""
    local explicit_acfs_home=""

    target_user="$(update_target_user 2>/dev/null || true)"
    current_user="$(update_current_user)"
    if [[ -n "$target_user" ]]; then
        target_home="$(update_target_home "$target_user" 2>/dev/null || true)"
    fi

    if [[ -n "$target_home" ]]; then
        explicit_acfs_home="$(update_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
        if [[ "$explicit_acfs_home" == "$target_home/.acfs" ]]; then
            printf '%s\n' "$explicit_acfs_home"
            return 0
        fi
        printf '%s\n' "$target_home/.acfs"
        return 0
    fi

    if [[ -n "$target_user_raw" && -z "$target_user" ]]; then
        return 1
    fi
    if [[ -n "$target_user" ]] && [[ -n "$current_user" ]] && [[ "$target_user" != "$current_user" ]]; then
        return 1
    fi

    runtime_home="$(update_existing_home "${HOME:-}" 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1

    explicit_acfs_home="$(update_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
    if [[ "$explicit_acfs_home" == "$runtime_home/.acfs" ]]; then
        printf '%s\n' "$explicit_acfs_home"
        return 0
    fi

    printf '%s\n' "$runtime_home/.acfs"
}

update_runtime_shell_home() {
    local target_user_raw="${TARGET_USER:-}"
    local target_user=""
    local current_user=""
    local target_home=""
    local runtime_home=""

    target_user="$(update_target_user 2>/dev/null || true)"
    current_user="$(update_current_user)"
    if [[ -n "$target_user" ]]; then
        target_home="$(update_target_home "$target_user" 2>/dev/null || true)"
    fi

    if [[ -n "$target_home" ]]; then
        printf '%s\n' "$target_home"
        return 0
    fi

    if [[ -n "$target_user_raw" && -z "$target_user" ]]; then
        return 1
    fi
    if [[ -n "$target_user" ]] && [[ -n "$current_user" ]] && [[ "$target_user" != "$current_user" ]]; then
        return 1
    fi

    runtime_home="$(update_existing_home "${HOME:-}" 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 1
    printf '%s\n' "$runtime_home"
}

update_binary_exists() {
    local resolved=""
    resolved="$(update_binary_path "$1" 2>/dev/null || true)"
    [[ -n "$resolved" ]]
}

update_tool_binary_path() {
    local tool="$1"
    local primary_bin=""
    local user_bin=""
    local target_user=""
    local target_home=""
    local candidate=""
    local -a candidates=()

    target_user="$(update_target_user)"
    target_home="$(update_target_home "$target_user" 2>/dev/null || true)"
    user_bin="$(update_default_user_bin_dir 2>/dev/null || true)"
    primary_bin="$(update_preferred_user_bin_dir 2>/dev/null || true)"

    case "$tool" in
        atuin)
            [[ -n "$primary_bin" ]] && candidates+=("$primary_bin/atuin")
            [[ -n "$user_bin" ]] && candidates+=("$user_bin/atuin")
            [[ -n "$target_home" ]] && candidates+=("$target_home/.atuin/bin/atuin")
            ;;
        zoxide)
            [[ -n "$primary_bin" ]] && candidates+=("$primary_bin/zoxide")
            [[ -n "$user_bin" ]] && candidates+=("$user_bin/zoxide")
            ;;
        *)
            ;;
    esac

    for candidate in "${candidates[@]}"; do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    update_binary_path "$tool"
}

update_tool_version_from_path() {
    local tool="$1"
    local binary_path="${2:-}"

    [[ -n "$binary_path" ]] || {
        printf 'unknown\n'
        return 0
    }

    case "$tool" in
        atuin|zoxide)
            "$binary_path" --version 2>/dev/null | awk '{print $2}' || echo "unknown"
            ;;
        *)
            "$binary_path" --version 2>/dev/null | head -1 || echo "unknown"
            ;;
    esac
}

update_has_nvm_node() {
    local node_path=""

    while IFS= read -r node_path; do
        [[ -x "$node_path" ]] && return 0
    done < <(compgen -G "$HOME/.nvm/versions/node/*/bin/node")

    return 1
}

update_nvm_node_bin_dir() {
    local node_path=""

    while IFS= read -r node_path; do
        if [[ -x "$node_path" ]]; then
            printf '%s\n' "${node_path%/node}"
            return 0
        fi
    done < <(compgen -G "$HOME/.nvm/versions/node/*/bin/node" | sort -Vr)

    return 1
}

update_ensure_gemini_patch_node() {
    if update_has_nvm_node; then
        return 0
    fi

    update_run_verified_installer nvm || return 1

    export NVM_DIR="$HOME/.nvm"
    if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        echo "nvm.sh not found at $NVM_DIR/nvm.sh" >&2
        return 1
    fi

    # shellcheck disable=SC1090
    . "$NVM_DIR/nvm.sh"
    nvm install node
    nvm alias default node

    update_has_nvm_node
}

is_expected_acfs_origin_url() {
    local url="$1"
    local normalized="$url"
    normalized="${normalized%/}"

    case "$normalized" in
        https://github.com/*)
            normalized="${normalized#https://github.com/}"
            ;;
        git@github.com:*)
            normalized="${normalized#git@github.com:}"
            ;;
        ssh://git@github.com/*)
            normalized="${normalized#ssh://git@github.com/}"
            ;;
        *)
            return 1
            ;;
    esac

    normalized="${normalized%.git}"
    normalized="${normalized,,}"

    local expected="${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}"
    expected="${expected,,}"
    [[ "$normalized" == "$expected" ]]
}

# ============================================================
# Logging Infrastructure
# ============================================================

init_logging() {
    if update_is_read_only_mode; then
        UPDATE_LOG_FILE=""
        return 0
    fi

    mkdir -p "$UPDATE_LOG_DIR"
    UPDATE_LOG_FILE="$UPDATE_LOG_DIR/$(date '+%Y-%m-%d-%H%M%S').log"

    # Write log header
    {
        echo "==============================================="
        echo "ACFS Update Log"
        echo "Started: $(date -Iseconds)"
        echo "User: $(update_current_user 2>/dev/null || true)"
        echo "Version: $ACFS_VERSION_DISPLAY"
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

update_ensure_jq_available() {
    if cmd_exists jq; then
        return 0
    fi

    if update_is_read_only_mode; then
        echo -e "${YELLOW}Dry-run: jq is missing; skipping jq installation and continuing with limited preview${NC}" >&2
        return 0
    fi

    echo -e "${YELLOW}Installing jq (required for update operations)...${NC}" >&2
    # Pass noninteractive env inline: sudo strips DEBIAN_FRONTEND/NEEDRESTART_*
    # from the caller's environment by default, so exports alone won't reach apt.
    local _apt_env=(env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1)
    if [[ $EUID -eq 0 ]]; then
        "${_apt_env[@]}" apt-get update -qq 2>/dev/null \
            && "${_apt_env[@]}" apt-get install -y -qq jq 2>/dev/null || true
    elif cmd_exists sudo; then
        sudo "${_apt_env[@]}" apt-get update -qq 2>/dev/null \
            && sudo "${_apt_env[@]}" apt-get install -y -qq jq 2>/dev/null || true
    fi

    if ! cmd_exists jq; then
        echo -e "${YELLOW}Warning: jq could not be installed; some operations may be limited${NC}" >&2
    fi
}

# ============================================================
# Version Detection
# ============================================================

get_version() {
    local tool="$1"
    local version=""
    local tool_bin=""

    case "$tool" in
        bun)
            tool_bin="$(update_binary_path "bun" 2>/dev/null || true)"
            if [[ -n "$tool_bin" ]]; then
                version=$("$tool_bin" --version 2>/dev/null || echo "unknown")
            else
                version="unknown"
            fi
            ;;
        rust)
            tool_bin="$(update_binary_path "rustc" 2>/dev/null || true)"
            if [[ -n "$tool_bin" ]]; then
                version=$("$tool_bin" --version 2>/dev/null | awk '{print $2}' || echo "unknown")
            else
                version="unknown"
            fi
            ;;
        uv)
            tool_bin="$(update_binary_path "uv" 2>/dev/null || true)"
            if [[ -n "$tool_bin" ]]; then
                version=$("$tool_bin" --version 2>/dev/null | awk '{print $2}' || echo "unknown")
            else
                version="unknown"
            fi
            ;;
        claude|codex|gemini|wrangler|supabase|vercel)
            tool_bin="$(update_binary_path "$tool" 2>/dev/null || true)"
            if [[ -n "$tool_bin" ]]; then
                version=$("$tool_bin" --version 2>/dev/null | head -1 || echo "unknown")
            else
                version="unknown"
            fi
            ;;
        pcr)
            local pcr_bin=""
            pcr_bin="$(update_binary_path "claude-post-compact-reminder" 2>/dev/null || true)"
            if [[ -n "$pcr_bin" ]]; then
                version=$("$pcr_bin" --version 2>/dev/null | head -1 || echo "unknown")
            else
                version="unknown"
            fi
            ;;
        ntm)
            tool_bin="$(update_binary_path "$tool" 2>/dev/null || true)"
            if [[ -n "$tool_bin" ]]; then
                version=$("$tool_bin" version 2>/dev/null | head -1 || echo "unknown")
            else
                version="unknown"
            fi
            ;;
        ubs|bv|cass|cm|caam|slb|ru|dcg|apr|pt|xf|jfp|ms|br|rch|giil|csctf|srps|tru|rano|mdwb|s2p|brenner|fsfs|sbh|casr|dsr|asb|aadc|rust_proxy)
            tool_bin="$(update_binary_path "$tool" 2>/dev/null || true)"
            if [[ -n "$tool_bin" ]]; then
                version=$("$tool_bin" --version 2>/dev/null | head -1 || echo "unknown")
            else
                version="unknown"
            fi
            ;;
        sg|lsd|dust|tldr)
            tool_bin="$(update_binary_path "$tool" 2>/dev/null || true)"
            if [[ -n "$tool_bin" ]]; then
                version=$("$tool_bin" --version 2>/dev/null | head -1 || echo "unknown")
            else
                version="unknown"
            fi
            ;;
        atuin)
            version=$(update_tool_version_from_path "atuin" "$(update_tool_binary_path "atuin" 2>/dev/null || true)")
            ;;
        zoxide)
            version=$(update_tool_version_from_path "zoxide" "$(update_tool_binary_path "zoxide" 2>/dev/null || true)")
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

get_file_mtime() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        return 1
    fi

    if stat -c %Y "$path" >/dev/null 2>&1; then
        stat -c %Y "$path"
        return 0
    fi

    if stat -f %m "$path" >/dev/null 2>&1; then
        stat -f %m "$path"
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

    return 0
}

update_finish_cmd_ok() {
    local desc="$1"
    local details="${2:-}"

    if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
        printf "\033[1A\033[2K  ${GREEN}[ok]${NC} %s\n" "$desc"
    elif [[ "$QUIET" != "true" ]]; then
        printf "  ${GREEN}[ok]${NC} %s\n" "$desc"
    fi
    [[ -n "$details" && "$QUIET" != "true" ]] && printf "       ${DIM}%s${NC}\n" "$details"

    log_to_file "Success: $desc${details:+ - $details}"
    ((SUCCESS_COUNT += 1))
}

update_finish_cmd_skip() {
    local desc="$1"
    local details="${2:-}"

    if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
        printf "\033[1A\033[2K  ${DIM}[skip]${NC} %s\n" "$desc"
    elif [[ "$QUIET" != "true" ]]; then
        printf "  ${DIM}[skip]${NC} %s\n" "$desc"
    fi
    [[ -n "$details" && "$QUIET" != "true" ]] && printf "       ${DIM}%s${NC}\n" "$details"

    log_to_file "Skipped: $desc${details:+ - $details}"
    ((SKIP_COUNT += 1))
}

update_finish_cmd_fail() {
    local desc="$1"
    local details="${2:-}"

    if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
        printf "\033[1A\033[2K  ${RED}[fail]${NC} %s\n" "$desc"
    else
        printf "  ${RED}[fail]${NC} %s\n" "$desc"
    fi
    [[ -n "$details" ]] && printf "       ${DIM}%s${NC}\n" "$details"

    log_to_file "Failed: $desc${details:+ - $details}"
    ((FAIL_COUNT += 1))

    if [[ "$ABORT_ON_FAILURE" == "true" ]]; then
        echo -e "${RED}Aborting due to failure (--abort-on-failure)${NC}"
        log_to_file "ABORT: Stopping due to --abort-on-failure"
        exit 1
    fi
}

update_run_logged_passthrough() {
    local cmd_display=""
    cmd_display=$(printf '%q ' "$@")
    log_to_file "Running: $cmd_display"

    if [[ -n "${UPDATE_LOG_FILE:-}" ]]; then
        {
            echo ""
            echo "----- COMMAND: $cmd_display"
        } >> "$UPDATE_LOG_FILE"
    fi

    if [[ "$QUIET" != "true" && -n "${UPDATE_LOG_FILE:-}" ]]; then
        "$@" 2>&1 | tee -a "$UPDATE_LOG_FILE"
        return "${PIPESTATUS[0]}"
    fi

    if [[ -n "${UPDATE_LOG_FILE:-}" ]]; then
        "$@" >> "$UPDATE_LOG_FILE" 2>&1
        return $?
    fi

    if [[ "$QUIET" != "true" ]]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

update_run_command_capture_with_retry() {
    local desc="$1"
    shift

    local max_attempts=3
    local attempt=1
    local exit_code=0
    local output=""
    local cmd_display=""
    cmd_display=$(printf '%q ' "$@")
    UPDATE_LAST_COMMAND_OUTPUT=""

    log_to_file "Running (captured with retry): $cmd_display"

    while [[ $attempt -le $max_attempts ]]; do
        exit_code=0
        output=$("$@" 2>&1) || exit_code=$?
        UPDATE_LAST_COMMAND_OUTPUT="$output"
        [[ -n "$output" ]] && log_to_file "Output: $output"
        [[ "$VERBOSE" == "true" && "$QUIET" != "true" && -n "$output" ]] && printf "%s\n" "$output"

        if [[ $exit_code -eq 0 ]]; then
            return 0
        fi

        if update_is_transient_failure_output "$output" && [[ $attempt -lt $max_attempts ]]; then
            local sleep_secs
            sleep_secs="$(update_retry_sleep_seconds "$attempt")"
            log_to_file "Transient error detected for $desc, retrying in ${sleep_secs}s (attempt $attempt/$max_attempts)"
            sleep "$sleep_secs"
            ((attempt += 1))
            continue
        fi

        break
    done

    return "$exit_code"
}

update_shell_tool_state_improved() {
    local before_path="${1:-}"
    local before_version="${2:-unknown}"
    local after_path="${3:-}"
    local after_version="${4:-unknown}"

    [[ -n "$after_path" && -x "$after_path" ]] || return 1
    [[ -n "$after_version" && "$after_version" != "unknown" ]] || return 1

    [[ -z "$before_path" || "$after_path" != "$before_path" || "$after_version" != "$before_version" ]]
}

update_repair_atuin_install() {
    local target_user=""
    local target_home=""
    local preferred_src=""
    local primary_dir=""
    local user_bin=""

    target_user="$(update_target_user)"
    target_home="$(update_target_home "$target_user" 2>/dev/null || true)"
    [[ -n "$target_home" ]] && preferred_src="$target_home/.atuin/bin/atuin"
    primary_dir="$(update_preferred_user_bin_dir 2>/dev/null || true)"
    user_bin="$(update_default_user_bin_dir 2>/dev/null || true)"
    local -a bin_dirs=()
    local dir=""

    [[ -n "$primary_dir" ]] && bin_dirs+=("$primary_dir")
    if [[ -n "$user_bin" && "$user_bin" != "$primary_dir" ]]; then
        bin_dirs+=("$user_bin")
    fi

    if [[ -x "$preferred_src" ]]; then
        for dir in "${bin_dirs[@]}"; do
            [[ -n "$dir" ]] || continue
            mkdir -p "$dir" 2>/dev/null || true
            if ln -sf "$preferred_src" "$dir/atuin" 2>/dev/null; then
                log_to_file "Atuin symlink normalized: $dir/atuin -> $preferred_src"
            fi
        done
    fi

    hash -r 2>/dev/null || true

    local resolved_bin=""
    resolved_bin="$(update_tool_binary_path "atuin" 2>/dev/null || true)"
    [[ -n "$resolved_bin" && -x "$resolved_bin" ]] || return 1
    "$resolved_bin" --version >/dev/null 2>&1
}

update_repair_zoxide_install() {
    local primary_dir=""
    local user_bin=""

    primary_dir="$(update_preferred_user_bin_dir 2>/dev/null || true)"
    user_bin="$(update_default_user_bin_dir 2>/dev/null || true)"

    # The upstream zoxide installer writes to ~/.local/bin by default. When ACFS
    # uses a custom bin_dir that comes earlier in PATH, keep that shim pointed at
    # the freshly reinstalled binary so shells don't continue resolving a stale
    # copy from the custom directory.
    if [[ -n "$primary_dir" && -n "$user_bin" && "$primary_dir" != "$user_bin" ]]; then
        local preferred_src="$user_bin/zoxide"
        [[ -x "$preferred_src" ]] || return 1
        mkdir -p "$primary_dir" 2>/dev/null || true
        if ln -sf "$preferred_src" "$primary_dir/zoxide" 2>/dev/null; then
            log_to_file "Zoxide symlink normalized: $primary_dir/zoxide -> $preferred_src"
        fi
    fi

    hash -r 2>/dev/null || true

    local resolved_bin=""
    resolved_bin="$(update_tool_binary_path "zoxide" 2>/dev/null || true)"
    [[ -n "$resolved_bin" && -x "$resolved_bin" ]] || return 1
    "$resolved_bin" --version >/dev/null 2>&1
}

update_run_verified_installer_with_shell_repair() {
    local desc="$1"
    local tool="$2"
    local repair_fn="$3"
    shift 3

    local before_path=""
    local before_version="unknown"
    local after_path=""
    local after_version="unknown"
    local exit_code=0

    before_path="$(update_tool_binary_path "$tool" 2>/dev/null || true)"
    before_version="$(get_version "$tool")"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "skip" "$desc" "dry-run: verified installer + repair"
        return 0
    fi

    log_item "run" "$desc"
    update_run_command_capture_with_retry "$desc" update_run_verified_installer "$tool" "$@" || exit_code=$?

    "$repair_fn" >/dev/null 2>&1 || true
    after_path="$(update_tool_binary_path "$tool" 2>/dev/null || true)"
    after_version="$(get_version "$tool")"

    if [[ $exit_code -eq 0 ]]; then
        if [[ -n "$after_path" && -x "$after_path" && "$after_version" != "unknown" ]]; then
            update_finish_cmd_ok "$desc"
            return 0
        fi
        update_finish_cmd_fail "$desc" "installer completed but binary verification failed"
        return 1
    fi

    if update_shell_tool_state_improved "$before_path" "$before_version" "$after_path" "$after_version"; then
        update_finish_cmd_ok "$desc" "verified repaired binary at ${after_path} (${after_version})"
        return 0
    fi

    if update_is_transient_failure_output "$UPDATE_LAST_COMMAND_OUTPUT" && [[ -n "$after_path" && -x "$after_path" && "$after_version" != "unknown" ]]; then
        update_finish_cmd_skip "$desc" "upstream temporarily unavailable; existing ${tool} ${after_version} remains installed"
        return 0
    fi

    update_finish_cmd_fail "$desc" "installer exited ${exit_code}"
    return 1
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
                # Separate commands in the log for readability.
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
            # Move cursor up and overwrite (only in non-verbose, non-quiet mode)
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
        if update_is_transient_failure_output "$output"; then
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

            # Clear bun's tmp cache to avoid stale locks in the target runtime home.
            local bun_runtime_home=""
            local bun_cache_tmp=""
            bun_runtime_home="$(update_runtime_shell_home 2>/dev/null || true)"
            if [[ -n "$bun_runtime_home" ]]; then
                bun_cache_tmp="$bun_runtime_home/.bun/install/cache/.tmp"
            elif [[ -n "${HOME:-}" ]]; then
                bun_cache_tmp="$HOME/.bun/install/cache/.tmp"
            fi
            if [[ -n "$bun_cache_tmp" && -d "$bun_cache_tmp" ]]; then
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

update_is_transient_failure_output() {
    local output="${1:-}"

    [[ -n "$output" ]] || return 1

    printf '%s\n' "$output" | grep -qiE \
        'failed to map segment|ENOENT|EACCES|EAGAIN|Connection reset|timed out|rate limit|API rate limit exceeded|too many requests|429|503|502|500|TLS|temporary failure|connection refused|reset by peer|network is unreachable|could not resolve host|curl:|wget:|failed to download|download.*failed|unable to fetch some archives|could not fetch release info|version [^[:space:]]+ was not found'
}

update_retry_sleep_seconds() {
    local attempt="${1:-1}"

    if [[ -n "${ACFS_UPDATE_RETRY_SLEEP_SECONDS:-}" ]]; then
        printf '%s\n' "$ACFS_UPDATE_RETRY_SLEEP_SECONDS"
        return 0
    fi

    printf '%s\n' "$((attempt * 2))"
}

_run_cmd_with_retry_internal() {
    local desc="$1"
    local failure_mode="$2"
    shift 2

    local max_attempts="${ACFS_UPDATE_RETRY_MAX_ATTEMPTS:-3}"
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

        if update_is_transient_failure_output "$output" && [[ $attempt -lt $max_attempts ]]; then
            local sleep_secs
            sleep_secs="$(update_retry_sleep_seconds "$attempt")"
            log_to_file "Transient error detected, retrying in ${sleep_secs}s (attempt $attempt/$max_attempts)"

            if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
                printf "\033[1A\033[2K  ${YELLOW}[retry]${NC} %s (attempt %d/%d)\n" "$desc" "$attempt" "$max_attempts"
            elif [[ "$QUIET" != "true" ]]; then
                printf "  ${YELLOW}[retry]${NC} %s (attempt %d/%d)\n" "$desc" "$attempt" "$max_attempts"
            fi

            sleep "$sleep_secs"
            ((attempt += 1))

            if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
                log_item "run" "$desc"
            fi
            continue
        fi

        break
    done

    if [[ "$failure_mode" == "fallback" ]]; then
        if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
            printf "\033[1A\033[2K  ${YELLOW}[retry]${NC} %s\n" "$desc"
        elif [[ "$QUIET" != "true" ]]; then
            printf "  ${YELLOW}[retry]${NC} %s\n" "$desc"
        fi
        log_to_file "Failed: $desc (exit code: $exit_code after $attempt attempts), will try fallback"
        return "$exit_code"
    fi

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

    return "$exit_code"
}

run_cmd_with_retry_status() {
    local desc="$1"
    shift
    _run_cmd_with_retry_internal "$desc" "fail" "$@"
}

run_cmd_attempt_with_retry() {
    local desc="$1"
    shift
    _run_cmd_with_retry_internal "$desc" "fallback" "$@"
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

run_cmd_sudo_with_retry_status() {
    local desc="$1"
    shift

    local sudo_cmd
    sudo_cmd=$(get_sudo)
    if [[ -n "$sudo_cmd" ]]; then
        run_cmd_with_retry_status "$desc" "$sudo_cmd" "$@"
        return $?
    fi
    run_cmd_with_retry_status "$desc" "$@"
}

run_cmd_sudo_attempt_with_retry() {
    local desc="$1"
    shift

    local sudo_cmd
    sudo_cmd=$(get_sudo)
    if [[ -n "$sudo_cmd" ]]; then
        run_cmd_attempt_with_retry "$desc" "$sudo_cmd" "$@"
        return $?
    fi
    run_cmd_attempt_with_retry "$desc" "$@"
}

update_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1

    for candidate in \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

update_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(update_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(update_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

update_getent_passwd_entry() {
  local user="${1-}"
  local getent_bin=""
  local passwd_entry=""
  local passwd_line=""
  local printed_any=false

  getent_bin="$(update_system_binary_path getent 2>/dev/null || true)"
  if [[ -z "$user" ]]; then
    if [[ -n "$getent_bin" ]]; then
      while IFS= read -r passwd_line; do
        printf '%s\n' "$passwd_line"
        printed_any=true
      done < <("$getent_bin" passwd 2>/dev/null || true)
      if [[ "$printed_any" == true ]]; then
        return 0
      fi
    fi

    [[ -r /etc/passwd ]] || return 1
    while IFS= read -r passwd_line; do
      printf '%s\n' "$passwd_line"
    done < /etc/passwd
    return 0
  fi

  if [[ -n "$getent_bin" ]]; then
    passwd_entry="$("$getent_bin" passwd "$user" 2>/dev/null || true)"
  fi

  if [[ -z "$passwd_entry" ]] && [[ -r /etc/passwd ]]; then
    while IFS= read -r passwd_line; do
      [[ "${passwd_line%%:*}" == "$user" ]] || continue
      passwd_entry="$passwd_line"
      break
    done < /etc/passwd
  fi

  [[ -n "$passwd_entry" ]] || return 1
  printf '%s\n' "$passwd_entry"
}

update_passwd_home_from_entry() {
  local passwd_entry="${1:-}"
  local passwd_home=""

  [[ -n "$passwd_entry" ]] || return 1
  IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
  passwd_home="$(update_sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
  [[ -n "$passwd_home" ]] || return 1
  printf '%s\n' "$passwd_home"
}

update_validate_target_user() {
    local target_user="${1:-}"

    if [[ -z "$target_user" ]] || [[ ! "$target_user" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        echo "Invalid TARGET_USER '${target_user:-<empty>}' (expected: lowercase user name like 'ubuntu')" >&2
        return 1
    fi
}

update_target_user() {
    local target_user="${TARGET_USER:-}"
    local current_user=""

    if [[ -n "$target_user" ]]; then
        update_validate_target_user "$target_user" || return 1
        printf '%s\n' "$target_user"
        return 0
    fi

    current_user="$(update_current_user)"
    target_user="${current_user:-ubuntu}"
    update_validate_target_user "$target_user" || return 1
    printf '%s\n' "$target_user"
}

update_existing_home() {
    local home_candidate="${1:-}"

    [[ -n "$home_candidate" ]] || return 1
    home_candidate="${home_candidate%/}"
    [[ -n "$home_candidate" ]] || return 1
    [[ "$home_candidate" == /* ]] || return 1
    [[ "$home_candidate" != "/" ]] || return 1
    [[ -d "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

update_target_home() {
    local target_user="${1:-}"
    local explicit_home=""
    local passwd_entry=""
    local current_user=""
    local current_home=""

    update_validate_target_user "$target_user" || return 1

    explicit_home="$(update_existing_home "${TARGET_HOME:-}" 2>/dev/null || true)"
    current_user="$(update_current_user)"
    if [[ "$target_user" == "root" ]]; then
        printf '%s\n' "/root"
        return 0
    fi
    if [[ -n "$explicit_home" && -z "${TARGET_USER:-}" && "$target_user" == "$current_user" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    passwd_entry="$(update_getent_passwd_entry "$target_user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        passwd_entry="$(update_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        passwd_entry="$(update_existing_home "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            printf '%s\n' "${passwd_entry%/}"
            return 0
        fi
    fi

    if [[ "$target_user" == "$current_user" ]]; then
        current_home="$(update_existing_home "${HOME:-}" 2>/dev/null || true)"
        if [[ -n "$current_home" ]] && { [[ -z "$explicit_home" ]] || [[ "$current_home" == "$explicit_home" ]]; }; then
            printf '%s\n' "$current_home"
            return 0
        fi
    fi

    if [[ -n "$explicit_home" && "$target_user" == "$current_user" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    return 1
}

update_target_path() {
    local target_home="$1"
    local configured_bin=""
    local target_bin=""
    local current_path="${PATH:-}"
    local dir=""
    local seen_path=":"
    local path_prefix=""
    local -a path_entries=()

    configured_bin="$(update_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$target_home" 2>/dev/null || true)"
    target_bin="${configured_bin:-$target_home/.local/bin}"

    [[ -n "$target_home" ]] || return 1
    [[ "$target_home" == /* ]] || return 1
    [[ "$target_home" != "/" ]] || return 1
    [[ -n "$target_bin" ]] || return 1
    [[ "$target_bin" == /* ]] || return 1
    [[ "$target_bin" != "/" ]] || return 1

    for dir in \
        "$target_bin" \
        "$target_home/.local/bin" \
        "$target_home/.acfs/bin" \
        "$target_home/.bun/bin" \
        "$target_home/.cargo/bin" \
        "$target_home/.atuin/bin" \
        "$target_home/go/bin" \
        "$target_home/google-cloud-sdk/bin" \
        "/usr/local/sbin" \
        "/usr/local/bin" \
        "/usr/sbin" \
        "/usr/bin" \
        "/sbin" \
        "/bin" \
        "/snap/bin"; do
        case "$seen_path" in
            *":$dir:"*) ;;
            *)
                path_entries+=("$dir")
                seen_path="${seen_path}${dir}:"
                ;;
        esac
    done

    path_prefix=$(IFS=:; echo "${path_entries[*]}")
    printf '%s\n' "$path_prefix${current_path:+:$current_path}"
}

update_binary_path() {
    local tool="$1"
    local target_user=""
    local target_home=""
    local primary_bin=""
    local configured_bin=""
    local current_user=""
    local candidate=""

    [[ -n "$tool" ]] || return 1

    target_user="$(update_target_user 2>/dev/null || true)"
    update_validate_target_user "$target_user" >/dev/null 2>&1 || return 1

    target_home="$(update_target_home "$target_user" 2>/dev/null || true)"
    current_user="$(update_current_user)"
    if [[ -z "$target_home" ]] && [[ "$target_user" == "$current_user" ]] && [[ -n "${HOME:-}" ]] && [[ "$HOME" == /* ]] && [[ "$HOME" != "/" ]]; then
        target_home="${HOME%/}"
    fi
    [[ -n "$target_home" ]] || return 1

    primary_bin="$(update_preferred_user_bin_dir 2>/dev/null || true)"
    configured_bin="$(update_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$target_home" 2>/dev/null || true)"
    if [[ -z "$primary_bin" ]] || [[ "$primary_bin" != /* ]] || [[ "$primary_bin" == "/" ]]; then
        primary_bin="${configured_bin:-$target_home/.local/bin}"
    fi

    for candidate in \
        "$primary_bin/$tool" \
        "$target_home/.local/bin/$tool" \
        "$target_home/.acfs/bin/$tool" \
        "$target_home/.bun/bin/$tool" \
        "$target_home/.cargo/bin/$tool" \
        "$target_home/.atuin/bin/$tool" \
        "$target_home/go/bin/$tool" \
        "$target_home/google-cloud-sdk/bin/$tool" \
        "$target_home/bin/$tool" \
        "/usr/local/go/bin/$tool" \
        "/usr/local/bin/$tool" \
        "/usr/local/sbin/$tool" \
        "/usr/bin/$tool" \
        "/bin/$tool" \
        "/usr/sbin/$tool" \
        "/sbin/$tool" \
        "/snap/bin/$tool"; do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

update_run_in_target_context() {
    local bash_env_assignment="${1:-}"
    shift

    local target_user=""
    local current_user=""
    local target_home=""
    local target_path=""
    target_user="$(update_target_user 2>/dev/null || true)"
    update_validate_target_user "$target_user" || return 1
    current_user="$(update_current_user)"
    target_home="$(update_target_home "$target_user" 2>/dev/null || true)"
    if [[ -z "$target_home" ]] || [[ "$target_home" != /* ]] || [[ "$target_home" == "/" ]]; then
        echo "Unable to resolve TARGET_HOME for '$target_user'; export TARGET_HOME explicitly" >&2
        return 1
    fi
    target_path="$(update_target_path "$target_home" 2>/dev/null || true)"
    [[ -n "$target_path" ]] || {
        echo "Unable to build target PATH for '$target_user'" >&2
        return 1
    }

    local sanitized_acfs_home=""
    local -a env_args=("UV_NO_CONFIG=1" "HOME=$target_home" "PATH=$target_path")
    [[ -n "$target_user" ]] && env_args+=("TARGET_USER=$target_user")
    [[ -n "$target_home" ]] && env_args+=("TARGET_HOME=$target_home")
    sanitized_acfs_home="$(update_sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
    [[ -n "$sanitized_acfs_home" ]] && env_args+=("ACFS_HOME=$sanitized_acfs_home")
    [[ -n "$bash_env_assignment" ]] && env_args+=("$bash_env_assignment")

    local env_bin=""
    local sh_bin=""
    env_bin="$(update_system_binary_path env 2>/dev/null || true)"
    sh_bin="$(update_system_binary_path sh 2>/dev/null || true)"
    if [[ -z "$env_bin" || -z "$sh_bin" ]]; then
        echo "Cannot build target-user command environment (env/sh unavailable)" >&2
        return 1
    fi

    if [[ "$current_user" == "$target_user" ]]; then
        (
            if ! cd "$target_home"; then
                echo "Unable to enter target home for '$target_user': $target_home" >&2
                exit 1
            fi
            "$env_bin" "${env_args[@]}" "$@"
        )
        return $?
    fi

    local sudo_bin=""
    sudo_bin="$(update_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -n -u "$target_user" "$env_bin" "${env_args[@]}" "$sh_bin" -c 'cd "$HOME" || exit 1; exec "$@"' _ "$@"
        return $?
    fi

    local runuser_bin=""
    runuser_bin="$(update_system_binary_path runuser 2>/dev/null || true)"
    if [[ -n "$runuser_bin" ]]; then
        "$runuser_bin" -u "$target_user" -- "$env_bin" "${env_args[@]}" "$sh_bin" -c 'cd "$HOME" || exit 1; exec "$@"' _ "$@"
        return $?
    fi

    echo "Cannot switch to target user '$target_user' (sudo/runuser unavailable)" >&2
    return 1
}

# ============================================================
# Migration Cleanup
# ============================================================

update_claude_settings_has_legacy_git_safety_guard_hook() {
    local settings_file="${1:-}"

    [[ -f "$settings_file" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    jq -e '
      def legacy_git_safety_guard_command:
        type == "object"
        and ((.type? // "command") == "command")
        and ((.command? // "") | strings | contains("git_safety_guard"));
      def event_entry_matches:
        if type == "object" and (.hooks? | type) == "array" then
          any(.hooks[]?; legacy_git_safety_guard_command)
        else
          legacy_git_safety_guard_command
        end;
      def hook_event_entries:
        if (.hooks? | type) == "object" then
          .hooks | to_entries[]? | .value | arrays | .[]?
        elif (.hooks? | type) == "array" then
          .hooks[]?
        else
          empty
        end;
      any(hook_event_entries; event_entry_matches)
    ' "$settings_file" >/dev/null 2>&1
}

# Clean up legacy git_safety_guard artifacts from pre-DCG installations
# This runs on every update to ensure stale files are removed
cleanup_legacy_git_safety_guard() {
    local runtime_home=""
    runtime_home="$(update_runtime_shell_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 0

    if update_is_read_only_mode; then
        local would_clean=false
        local hooks_dir=""
        local legacy_file=""

        for hooks_dir in "$runtime_home/.acfs/claude/hooks" "$runtime_home/.claude/hooks"; do
            for legacy_file in git_safety_guard.py git_safety_guard.sh; do
                if [[ -f "$hooks_dir/$legacy_file" ]]; then
                    would_clean=true
                fi
            done
        done

        if update_claude_settings_has_legacy_git_safety_guard_hook "$runtime_home/.claude/settings.json"; then
            would_clean=true
        fi

        if [[ "$would_clean" == "true" ]]; then
            log_item "skip" "legacy cleanup" "dry-run: would remove git_safety_guard artifacts"
        fi
        return 0
    fi

    local cleaned=false
    local hooks_dirs=(
        "$runtime_home/.acfs/claude/hooks"
        "$runtime_home/.claude/hooks"
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
    for parent in "$runtime_home/.acfs/claude" "$runtime_home/.claude"; do
        if [[ -d "$parent" ]] && [[ -z "$(ls -A "$parent" 2>/dev/null)" ]]; then
            rmdir "$parent" 2>/dev/null || true
            log_to_file "Removed empty directory: $parent"
        fi
    done

    # Clean git_safety_guard from Claude settings.json if present
    local settings_file="$runtime_home/.claude/settings.json"
    if update_claude_settings_has_legacy_git_safety_guard_hook "$settings_file"; then
        local tmp_settings
        tmp_settings=$(mktemp "${TMPDIR:-/tmp}/acfs_settings.XXXXXX" 2>/dev/null) || tmp_settings=""
        if [[ -n "$tmp_settings" ]]; then
            if jq '
              def legacy_git_safety_guard_command:
                type == "object"
                and ((.type? // "command") == "command")
                and ((.command? // "") | strings | contains("git_safety_guard"));
              def strip_legacy_git_safety_guard:
                if type == "object" and (.hooks? | type) == "array" then
                  .hooks = [ .hooks[]? | select(legacy_git_safety_guard_command | not) ] |
                  select((.hooks | length) > 0)
                else
                  select(legacy_git_safety_guard_command | not)
                end;
              if (.hooks? | type) == "object" then
                .hooks |= with_entries(
                  if (.value | type) == "array" then
                    .value = [ .value[]? | strip_legacy_git_safety_guard ]
                  else
                    .
                  end
                )
              elif (.hooks? | type) == "array" then
                .hooks = [ .hooks[]? | strip_legacy_git_safety_guard ]
              else
                .
              end
            ' "$settings_file" > "$tmp_settings" 2>/dev/null; then
                if mv "$tmp_settings" "$settings_file"; then
                    cleaned=true
                    log_to_file "Cleaned git_safety_guard references from $settings_file"
                else
                    rm -f "$tmp_settings"
                fi
            else
                rm -f "$tmp_settings"
            fi
        fi
    fi

    if [[ "$cleaned" == "true" ]]; then
        log_item "ok" "legacy cleanup" "removed git_safety_guard artifacts"
    fi
}

cleanup_legacy_bv_alias() {
    local runtime_home=""
    runtime_home="$(update_runtime_shell_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 0
    local zshrc_local="$runtime_home/.zshrc.local"
    [[ -f "$zshrc_local" ]] || return 0

    update_zshrc_local_has_active_bv_alias() {
        local file="${1:-}"
        [[ -f "$file" ]] || return 1

        awk '
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*alias[[:space:]]+bv=/ { found=1; exit }
            END { exit(found ? 0 : 1) }
        ' "$file" 2>/dev/null
    }

    update_zshrc_local_has_active_bv_block() {
        local file="${1:-}"
        [[ -f "$file" ]] || return 1

        awk '
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*if[[:space:]]+\[[^]]*\.local\/bin\/bv[^]]*\][[:space:]]*;[[:space:]]*then[[:space:]]*$/ { found=1; exit }
            END { exit(found ? 0 : 1) }
        ' "$file" 2>/dev/null
    }

    if update_is_read_only_mode; then
        if update_zshrc_local_has_active_bv_alias "$zshrc_local" || update_zshrc_local_has_active_bv_block "$zshrc_local"; then
            log_item "skip" "legacy cleanup" "dry-run: would remove stale bv alias block from .zshrc.local"
        fi
        return 0
    fi

    # The bv() function in acfs.zshrc handles beads_viewer PATH resolution.
    # Any leftover "alias bv=" in .zshrc.local causes zsh parse errors
    # ("defining function based on alias 'bv'") when acfs.zshrc tries to
    # define the bv() function after .zshrc.local has already created an alias.
    #
    # The alias was typically inside an if/elif/fi block like:
    #   # === BV ...
    #   if [ -x "$HOME/.local/bin/bv" ]; then
    #       alias bv="..."
    #   elif ...
    #   fi
    # A naive sed '/alias bv=/d' leaves orphaned if/elif/fi with empty
    # bodies — a syntax error.  We must remove the entire block.
    # Strategy: target the specific if/elif/fi block containing bv aliases
    # or their skeletons.  Do NOT use '/^# === BV/,/^fi$/d' because the
    # BV comment may precede a for/done block (PATH setup) with no fi,
    # causing sed to delete to EOF.
    if update_zshrc_local_has_active_bv_alias "$zshrc_local"; then
        # Remove the if/elif/fi block containing bv alias checks
        sed -i '/^[[:space:]]*if[[:space:]]\+\[.*\.local\/bin\/bv.*\][[:space:]]*;[[:space:]]*then[[:space:]]*$/,/^[[:space:]]*fi[[:space:]]*$/d' "$zshrc_local"
        # Safety net: remove any standalone alias bv= lines
        sed -i '/^[[:space:]]*alias[[:space:]]\+bv=/d' "$zshrc_local"
        log_item "ok" "legacy cleanup" "removed stale bv alias block from .zshrc.local"
        log_to_file "Removed bv alias block from $zshrc_local"
    fi

    # Also clean up orphaned if/elif/fi skeletons left by earlier runs
    # that only deleted the alias lines but not the surrounding block.
    if update_zshrc_local_has_active_bv_block "$zshrc_local"; then
        sed -i '/^[[:space:]]*if[[:space:]]\+\[.*\.local\/bin\/bv.*\][[:space:]]*;[[:space:]]*then[[:space:]]*$/,/^[[:space:]]*fi[[:space:]]*$/d' "$zshrc_local"
        log_item "ok" "legacy cleanup" "removed orphaned bv if/elif/fi skeleton from .zshrc.local"
        log_to_file "Removed orphaned bv block skeleton from $zshrc_local"
    fi
}

# Fix stale aliases in deployed acfs.zshrc
# Older versions aliased br='bun run dev', which shadows beads_rust (br).
cleanup_legacy_br_alias() {
    local runtime_home=""
    runtime_home="$(update_runtime_shell_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 0
    local deployed="$runtime_home/.acfs/zsh/acfs.zshrc"
    [[ -f "$deployed" ]] || return 0

    if update_is_read_only_mode; then
        if grep -q "^alias br='bun run dev'" "$deployed" 2>/dev/null; then
            log_item "skip" "legacy cleanup" "dry-run: would fix br alias conflict in deployed acfs.zshrc"
        fi
        return 0
    fi

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
    local runtime_home=""
    runtime_home="$(update_runtime_shell_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 0
    local deployed_zshrc="$runtime_home/.acfs/zsh/acfs.zshrc"

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

sync_acfs_zsh_loader() {
    local runtime_home=""
    runtime_home="$(update_runtime_shell_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 0
    local user_zshrc="$runtime_home/.zshrc"
    local acfs_loader_source='source "$HOME/.acfs/zsh/acfs.zshrc"'
    local stale_local_source='[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"'

    [[ -f "$user_zshrc" ]] || return 0

    if ! _update_file_has_active_exact_line "$user_zshrc" "$acfs_loader_source"; then
        return 0
    fi

    if ! _update_file_has_active_exact_line "$user_zshrc" "$stale_local_source"; then
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "ok" "acfs.zsh loader" "would remove duplicate ~/.zshrc.local sourcing from ~/.zshrc"
        return 0
    fi

    sed -i '\|^[[:space:]]*\[ -f "\$HOME/\.zshrc\.local" \] && source "\$HOME/\.zshrc\.local"[[:space:]]*$|d' "$user_zshrc"
    log_item "ok" "acfs.zsh loader" "removed duplicate ~/.zshrc.local sourcing from ~/.zshrc"
    log_to_file "Removed duplicate .zshrc.local sourcing from $user_zshrc"
}

_update_file_has_active_exact_line() {
    local file="${1:-}"
    local expected_line="${2:-}"

    [[ -n "$file" && -n "$expected_line" && -f "$file" ]] || return 1

    awk -v expected="$expected_line" '
        /^[[:space:]]*#/ { next }
        {
            line=$0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (line == expected) { found=1; exit }
        }
        END { exit(found ? 0 : 1) }
    ' "$file" 2>/dev/null
}

_update_profile_path_has_fragment() {
    local file="${1:-}"
    local fragment="${2:-}"

    [[ -n "$file" && -n "$fragment" && -f "$file" ]] || return 1
    awk -v fragment="$fragment" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*(export[[:space:]]+)?PATH[[:space:]]*=/ && index($0, fragment) { found=1; exit }
        END { exit(found ? 0 : 1) }
    ' "$file" 2>/dev/null
}

_update_sed_literal() {
    # This is used in sed's default BRE mode with | as the delimiter.
    # Do not escape literal parentheses: \(...\) is a BRE capture group.
    printf '%s' "$1" | sed 's/[][\\.^$*|]/\\&/g'
}

sync_acfs_profile_paths() {
    local runtime_home=""
    runtime_home="$(update_runtime_shell_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 0
    local user_profile="$runtime_home/.profile"
    local legacy_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"'
    local current_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
    local escaped_legacy_path_line=""

    if [[ ! -f "$user_profile" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_item "ok" "acfs.profile" "would create login PATH including ~/.atuin/bin"
            return 0
        fi

        {
            printf '# ~/.profile: executed by bash for login shells\n'
            printf '\n'
            printf '# User binary paths\n'
            printf '%s\n' "$current_path_line"
        } > "$user_profile"
        log_item "ok" "acfs.profile" "created login PATH including ~/.atuin/bin"
        log_to_file "Created ACFS-managed PATH line in $user_profile"
        return 0
    fi

    if grep -Fxq "$legacy_path_line" "$user_profile" 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_item "ok" "acfs.profile" "would update login PATH to include ~/.atuin/bin"
            return 0
        fi

        escaped_legacy_path_line="$(_update_sed_literal "$legacy_path_line")"
        sed -i "s|^$escaped_legacy_path_line$|$current_path_line|" "$user_profile"
        log_item "ok" "acfs.profile" "updated login PATH to include ~/.atuin/bin"
        log_to_file "Updated ACFS-managed PATH line in $user_profile"
        return 0
    fi

    if _update_profile_path_has_fragment "$user_profile" '.local/bin' && \
       _update_profile_path_has_fragment "$user_profile" '.atuin/bin'; then
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "ok" "acfs.profile" "would add login PATH including ~/.atuin/bin"
        return 0
    fi

    {
        printf '\n'
        printf '# Added by ACFS - user binary paths\n'
        printf '%s\n' "$current_path_line"
    } >> "$user_profile"
    log_item "ok" "acfs.profile" "added login PATH including ~/.atuin/bin"
    log_to_file "Added ACFS-managed PATH line to $user_profile"
}

sync_acfs_zprofile_paths() {
    local runtime_home=""
    runtime_home="$(update_runtime_shell_home 2>/dev/null || true)"
    [[ -n "$runtime_home" ]] || return 0
    local user_zprofile="$runtime_home/.zprofile"
    local legacy_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"'
    local current_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
    local escaped_legacy_path_line=""

    if [[ ! -f "$user_zprofile" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_item "ok" "acfs.zprofile" "would create login PATH including ~/.atuin/bin"
            return 0
        fi

        {
            printf '# ~/.zprofile: executed by zsh for login shells\n'
            printf '\n'
            printf '# User binary paths\n'
            printf '%s\n' "$current_path_line"
        } > "$user_zprofile"
        log_item "ok" "acfs.zprofile" "created login PATH including ~/.atuin/bin"
        log_to_file "Created ACFS-managed PATH line in $user_zprofile"
        return 0
    fi

    if grep -Fxq "$legacy_path_line" "$user_zprofile" 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_item "ok" "acfs.zprofile" "would update login PATH to include ~/.atuin/bin"
            return 0
        fi

        escaped_legacy_path_line="$(_update_sed_literal "$legacy_path_line")"
        sed -i "s|^$escaped_legacy_path_line$|$current_path_line|" "$user_zprofile"
        log_item "ok" "acfs.zprofile" "updated login PATH to include ~/.atuin/bin"
        log_to_file "Updated ACFS-managed PATH line in $user_zprofile"
        return 0
    fi

    if _update_profile_path_has_fragment "$user_zprofile" '.local/bin' && \
       _update_profile_path_has_fragment "$user_zprofile" '.atuin/bin'; then
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "ok" "acfs.zprofile" "would add login PATH including ~/.atuin/bin"
        return 0
    fi

    {
        printf '\n'
        printf '# Added by ACFS - user binary paths\n'
        printf '%s\n' "$current_path_line"
    } >> "$user_zprofile"
    log_item "ok" "acfs.zprofile" "added login PATH including ~/.atuin/bin"
    log_to_file "Added ACFS-managed PATH line to $user_zprofile"
}

# Sync critical scripts from the git repo to ~/.acfs/ so that subsequent
# runs of 'acfs update' (invoked from ~/.acfs/scripts/lib/update.sh) use
# the latest code.  Without this, fleet machines that run from the
# tarball-installed ~/.acfs/ never pick up fixes to update.sh, security.sh,
# or checksums.yaml — the self-update pulls into the git repo but the
# deployed copies at ~/.acfs/ remain stale.
sync_acfs_deployed() {
    local acfs_home=""
    acfs_home="$(update_runtime_acfs_home 2>/dev/null || true)"
    [[ -n "$acfs_home" ]] || return 0

    # Only sync when the repo is a different directory from ~/.acfs
    local resolved_repo resolved_home
    resolved_repo="$(realpath "$ACFS_REPO_ROOT" 2>/dev/null || printf '%s\n' "$ACFS_REPO_ROOT")"
    resolved_home="$(realpath "$acfs_home" 2>/dev/null || printf '%s\n' "$acfs_home")"
    [[ "$resolved_repo" != "$resolved_home" ]] || return 0

    _acfs_deployed_path_is_git_tracked() {
        local deployed_root="$1"
        local deployed_rel="$2"

        [[ -d "$deployed_root/.git" ]] || return 1
        git -C "$deployed_root" ls-files --error-unmatch -- "$deployed_rel" >/dev/null 2>&1
    }

    local -a file_pairs=(
        # repo-relative-path : deployed-relative-path
        "scripts/lib/doctor.sh:scripts/lib/doctor.sh"
        "scripts/lib/doctor.sh:bin/acfs"
        "scripts/acfs-update:bin/acfs-update"
        "scripts/services-setup.sh:scripts/services-setup.sh"
        "scripts/lib/info.sh:scripts/lib/info.sh"
        "scripts/lib/status.sh:scripts/lib/status.sh"
        "scripts/lib/changelog.sh:scripts/lib/changelog.sh"
        "scripts/lib/export-config.sh:scripts/lib/export-config.sh"
        "scripts/lib/continue.sh:scripts/lib/continue.sh"
        "scripts/lib/session.sh:scripts/lib/session.sh"
        "scripts/lib/cheatsheet.sh:scripts/lib/cheatsheet.sh"
        "scripts/lib/dashboard.sh:scripts/lib/dashboard.sh"
        "scripts/lib/support.sh:scripts/lib/support.sh"
        "scripts/lib/update.sh:scripts/lib/update.sh"
        "scripts/lib/logging.sh:scripts/lib/logging.sh"
        "scripts/lib/stack.sh:scripts/lib/stack.sh"
        "scripts/lib/contract.sh:scripts/lib/contract.sh"
        "scripts/lib/nightly_update.sh:scripts/lib/nightly_update.sh"
        "scripts/lib/nightly_update.sh:scripts/nightly-update.sh"
        "scripts/lib/security.sh:scripts/lib/security.sh"
        "scripts/templates/acfs-nightly-update.service:scripts/templates/acfs-nightly-update.service"
        "scripts/templates/acfs-nightly-update.timer:scripts/templates/acfs-nightly-update.timer"
        "checksums.yaml:checksums.yaml"
        "acfs/zsh/acfs.zshrc:zsh/acfs.zshrc"
        "acfs/zsh/p10k.zsh:zsh/p10k.zsh"
        "VERSION:VERSION"
    )

    local synced=0
    for pair in "${file_pairs[@]}"; do
        local repo_rel="${pair%%:*}"
        local deployed_rel="${pair##*:}"
        local repo_file="$ACFS_REPO_ROOT/$repo_rel"
        local deployed_file="$acfs_home/$deployed_rel"

        [[ -f "$repo_file" ]] || continue
        if _acfs_deployed_path_is_git_tracked "$acfs_home" "$deployed_rel"; then
            log_to_file "Skipped syncing $repo_rel -> $deployed_file (target is git-managed)"
            continue
        fi

        # Skip if identical
        if [[ -f "$deployed_file" ]] && cmp -s "$repo_file" "$deployed_file"; then
            continue
        fi

        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_to_file "Would sync $repo_rel -> $deployed_file"
            synced=$((synced + 1))
            continue
        fi

        mkdir -p "$(dirname "$deployed_file")"
        cp "$repo_file" "$deployed_file"
        chmod --reference="$repo_file" "$deployed_file" 2>/dev/null || true
        log_to_file "Synced $repo_rel -> $deployed_file"
        synced=$((synced + 1))
    done

    local generated_script=""
    local generated_name=""
    for generated_script in "$ACFS_REPO_ROOT/scripts/generated/"*.sh; do
        [[ -f "$generated_script" ]] || continue
        generated_name="$(basename "$generated_script")"
        local deployed_generated="$acfs_home/scripts/generated/$generated_name"

        if _acfs_deployed_path_is_git_tracked "$acfs_home" "scripts/generated/$generated_name"; then
            log_to_file "Skipped syncing scripts/generated/$generated_name -> $deployed_generated (target is git-managed)"
            continue
        fi

        if [[ -f "$deployed_generated" ]] && cmp -s "$generated_script" "$deployed_generated"; then
            continue
        fi

        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_to_file "Would sync scripts/generated/$generated_name -> $deployed_generated"
            synced=$((synced + 1))
            continue
        fi

        mkdir -p "$(dirname "$deployed_generated")"
        cp "$generated_script" "$deployed_generated"
        chmod --reference="$generated_script" "$deployed_generated" 2>/dev/null || true
        log_to_file "Synced scripts/generated/$generated_name -> $deployed_generated"
        synced=$((synced + 1))
    done

    if [[ $synced -gt 0 ]]; then
        log_to_file "Synced $synced file(s) from repo to $acfs_home"
    fi
}

sync_acfs_global_wrapper() {
    local repo_file="$ACFS_REPO_ROOT/scripts/acfs-global"
    local deployed_file="/usr/local/bin/acfs"
    local install_cmd=(install -m 0755 "$repo_file" "$deployed_file")

    [[ -f "$repo_file" ]] || return 0
    if [[ -f "$deployed_file" ]] && cmp -s "$repo_file" "$deployed_file"; then
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_to_file "Would sync scripts/acfs-global -> $deployed_file"
        return 0
    fi

    if [[ $EUID -eq 0 ]]; then
        "${install_cmd[@]}"
        log_to_file "Synced scripts/acfs-global -> $deployed_file"
        return 0
    fi

    local sudo_bin=""
    sudo_bin="$(update_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]] && "$sudo_bin" -n true >/dev/null 2>&1; then
        "$sudo_bin" -n "${install_cmd[@]}"
        log_to_file "Synced scripts/acfs-global -> $deployed_file"
        return 0
    fi

    log_to_file "Skipped syncing scripts/acfs-global -> $deployed_file (needs root)"
    return 0
}

# ============================================================
# Checksums Refresh (Auto-update from GitHub)
# ============================================================

CHECKSUMS_URL="https://raw.githubusercontent.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}/${ACFS_CHECKSUMS_REF}/checksums.yaml"
CHECKSUMS_LOCAL="${ACFS_HOME:-$HOME/.acfs}/checksums.yaml"

update_resolve_checksums_file() {
    local installed_checksums=""
    local repo_checksums=""
    local default_acfs_home=""
    default_acfs_home="$(update_runtime_acfs_home 2>/dev/null || true)"
    [[ -n "$default_acfs_home" ]] && installed_checksums="$default_acfs_home/checksums.yaml"

    if [[ -n "${ACFS_REPO_ROOT:-}" ]] && [[ -r "${ACFS_REPO_ROOT}/checksums.yaml" ]]; then
        repo_checksums="${ACFS_REPO_ROOT}/checksums.yaml"
    fi

    # When running update.sh from a repo checkout, prefer the repo's committed
    # checksums over any installed ~/.acfs cache so local development does not
    # inherit stale metadata from an older ACFS install.
    if [[ -n "$repo_checksums" ]] && [[ "${ACFS_REPO_ROOT}" != "$default_acfs_home" ]]; then
        printf '%s\n' "$repo_checksums"
        return 0
    fi

    if [[ -r "$installed_checksums" ]]; then
        printf '%s\n' "$installed_checksums"
        return 0
    fi

    if [[ -n "$repo_checksums" ]]; then
        printf '%s\n' "$repo_checksums"
        return 0
    fi

    return 1
}

# Refresh checksums.yaml from GitHub before verifying installers
# This ensures we always have the latest checksums without requiring
# a full ACFS re-install.
refresh_checksums() {
    local quiet="${1:-false}"
    local checksums_local=""

    checksums_local="$(update_runtime_acfs_home 2>/dev/null || true)"
    if [[ -z "$checksums_local" ]]; then
        log_to_file "Checksums refresh skipped: unable to resolve runtime ACFS home"
        return 1
    fi
    checksums_local="$checksums_local/checksums.yaml"

    # Create directory if needed
    mkdir -p "$(dirname "$checksums_local")"

    # Download with timeout and retry
    local tmp_checksums
    tmp_checksums=$(mktemp "${TMPDIR:-/tmp}/acfs-checksums.XXXXXX" 2>/dev/null || true)
    if [[ -z "$tmp_checksums" ]]; then
        [[ "$quiet" != "true" ]] && log_item "warn" "checksums refresh" "failed to create temp file, using cached"
        log_to_file "Checksums refresh failed: mktemp failed"
        return 1
    fi

    # Use --proto/--proto-redir to enforce HTTPS (matches install.sh / security.sh policy)
    local -a _refresh_curl_args=(--connect-timeout 5 --max-time 30 -fsSL)
    if command -v curl &>/dev/null && curl --help all 2>/dev/null | grep -q -- '--proto'; then
        _refresh_curl_args=(--proto '=https' --proto-redir '=https' --connect-timeout 5 --max-time 30 -fsSL)
    fi
    if curl "${_refresh_curl_args[@]}" -o "$tmp_checksums" "$CHECKSUMS_URL" 2>/dev/null; then
        # Validate it looks like a checksums file
        if grep -q "^installers:" "$tmp_checksums" 2>/dev/null; then
            if mv "$tmp_checksums" "$checksums_local" 2>/dev/null; then
                chmod 644 "$checksums_local" 2>/dev/null || true  # Ensure readable permissions
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
    local candidate=""
    local primary_bin=""
    local runtime_acfs_home=""
    primary_bin="$(update_runtime_primary_bin_dir 2>/dev/null || true)"
    runtime_acfs_home="$(update_runtime_acfs_home 2>/dev/null || true)"
    local -a security_candidates=()
    [[ -n "$primary_bin" ]] && security_candidates+=("$primary_bin/security.sh")
    [[ -n "$runtime_acfs_home" ]] && security_candidates+=("$runtime_acfs_home/scripts/lib/security.sh")
    if [[ -n "${ACFS_REPO_ROOT:-}" ]]; then
        security_candidates+=("${ACFS_REPO_ROOT}/scripts/lib/security.sh")
    fi

    for candidate in "${security_candidates[@]}"; do
        if [[ -n "$candidate" ]] && [[ -f "$candidate" ]]; then
            security_script="$candidate"
            break
        fi
    done

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
        printf '    - %s\n' "${security_candidates[@]}" >&2
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

    local resolved_checksums_file=""
    resolved_checksums_file="$(update_resolve_checksums_file 2>/dev/null || true)"
    if [[ -n "$resolved_checksums_file" ]]; then
        export CHECKSUMS_FILE="$resolved_checksums_file"
    fi
    # shellcheck disable=SC1090,SC1091  # runtime-resolved absolute path source
    source "$security_script"
    load_checksums || return 1

    UPDATE_SECURITY_READY=true
    return 0
}

update_is_linux_arm64() {
    local arch=""
    arch="$(uname -m 2>/dev/null || true)"
    [[ "$(uname -s 2>/dev/null)" == "Linux" ]] && [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]
}

update_fsfs_linux_target_triple() {
    local arch=""

    [[ "$(uname -s 2>/dev/null)" == "Linux" ]] || return 1
    arch="$(uname -m 2>/dev/null || true)"

    case "$arch" in
        x86_64|amd64)
            printf '%s\n' "x86_64-unknown-linux-musl"
            ;;
        aarch64|arm64)
            printf '%s\n' "aarch64-unknown-linux-musl"
            ;;
        *)
            return 1
            ;;
    esac
}

update_is_valid_fsfs_version() {
    local version="${1:-}"
    [[ "$version" =~ ^v[0-9][A-Za-z0-9._-]*$ ]]
}

update_resolve_fsfs_latest_version() {
    if [[ -n "${ACFS_FSFS_VERSION:-}" ]]; then
        update_is_valid_fsfs_version "$ACFS_FSFS_VERSION" || return 1
        printf '%s\n' "$ACFS_FSFS_VERSION"
        return 0
    fi

    local latest_url="https://api.github.com/repos/Dicklesworthstone/frankensearch/releases/latest"
    local redirect_url="https://github.com/Dicklesworthstone/frankensearch/releases/latest"
    local tag=""
    tag="$(curl -fsSL --connect-timeout 30 --max-time 60 -H "Accept: application/vnd.github.v3+json" "$latest_url" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1 || true)"

    if update_is_valid_fsfs_version "$tag"; then
        printf '%s\n' "$tag"
        return 0
    fi

    tag="$(curl -fsSL --connect-timeout 30 --max-time 60 -o /dev/null -w '%{url_effective}' "$redirect_url" 2>/dev/null \
        | sed -E 's|.*/tag/||' || true)"

    update_is_valid_fsfs_version "$tag" || return 1
    printf '%s\n' "$tag"
}

update_fetch_fsfs_artifact_checksum() {
    local checksum_url="$1"
    local checksum=""

    checksum="$(curl -fsSL --connect-timeout 30 --max-time 60 "$checksum_url" 2>/dev/null \
        | awk 'NR == 1 { print $1 }' || true)"
    [[ "$checksum" =~ ^[0-9A-Fa-f]{64}$ ]] || return 1
    printf '%s\n' "${checksum,,}"
}

update_resolve_fsfs_artifact_contract() {
    local fsfs_target="$1"
    local -a candidates=()
    local candidate=""
    local fsfs_version=""
    local fsfs_version_bare=""
    local fsfs_artifact_url=""
    local fsfs_checksum=""

    if [[ -z "$fsfs_target" ]]; then
        return 1
    fi

    if [[ -n "${ACFS_FSFS_VERSION:-}" ]]; then
        update_is_valid_fsfs_version "$ACFS_FSFS_VERSION" || return 1
        candidates+=("$ACFS_FSFS_VERSION")
    else
        while IFS= read -r candidate; do
            [[ -n "$candidate" ]] || continue
            case " ${candidates[*]} " in
                *" $candidate "*) ;;
                *) candidates+=("$candidate") ;;
            esac
        done < <(
            curl -fsSL --connect-timeout 30 --max-time 60 \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/Dicklesworthstone/frankensearch/releases?per_page=10" 2>/dev/null \
                | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true
        )

        candidate="$(curl -fsSL --connect-timeout 30 --max-time 60 -o /dev/null -w '%{url_effective}' \
            "https://github.com/Dicklesworthstone/frankensearch/releases/latest" 2>/dev/null \
            | sed -E 's|.*/tag/||' || true)"
        if update_is_valid_fsfs_version "$candidate"; then
            case " ${candidates[*]} " in
                *" $candidate "*) ;;
                *) candidates+=("$candidate") ;;
            esac
        fi
    fi

    for fsfs_version in "${candidates[@]}"; do
        update_is_valid_fsfs_version "$fsfs_version" || continue
        fsfs_version_bare="${fsfs_version#v}"
        fsfs_artifact_url="https://github.com/Dicklesworthstone/frankensearch/releases/download/${fsfs_version}/fsfs-lite-${fsfs_version_bare}-${fsfs_target}.tar.xz"
        if fsfs_checksum="$(update_fetch_fsfs_artifact_checksum "${fsfs_artifact_url}.sha256" 2>/dev/null)"; then
            printf '%s\n%s\n%s\n' "$fsfs_version" "$fsfs_artifact_url" "$fsfs_checksum"
            return 0
        fi
        log_to_file "FrankenSearch lite artifact checksum unavailable for ${fsfs_version}"
    done

    return 1
}

update_run_fsfs_installer() {
    local -a fsfs_args=("$@")
    local -a fsfs_contract=()
    local fsfs_target=""
    local fsfs_version=""
    local fsfs_artifact_url=""
    local fsfs_checksum=""

    if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
        if ! fsfs_target="$(update_fsfs_linux_target_triple 2>/dev/null)"; then
            log_to_file "FrankenSearch Linux lite artifact unsupported for this architecture"
            echo "FrankenSearch Linux binary artifact unavailable for this architecture; skipping source-build fallback" >&2
            return 1
        fi

        mapfile -t fsfs_contract < <(update_resolve_fsfs_artifact_contract "$fsfs_target")
        fsfs_version="${fsfs_contract[0]:-}"
        fsfs_artifact_url="${fsfs_contract[1]:-}"
        fsfs_checksum="${fsfs_contract[2]:-}"
        if [[ -z "$fsfs_version" || -z "$fsfs_artifact_url" || -z "$fsfs_checksum" ]]; then
            log_to_file "FrankenSearch release artifact contract unavailable; skipping source-build fallback"
            echo "Unable to resolve a FrankenSearch lite artifact with a checksum; skipping source-build fallback" >&2
            return 1
        fi

        fsfs_args+=(
            --version "$fsfs_version"
            --artifact-url "$fsfs_artifact_url"
            --checksum "$fsfs_checksum"
        )
        log_to_file "FrankenSearch Linux lite artifact selected: $fsfs_artifact_url"
    fi

    update_run_verified_installer fsfs "${fsfs_args[@]}"
}

update_run_meta_skill_source_install() {
    local cargo_bin=""
    cargo_bin="$(update_binary_path cargo 2>/dev/null || true)"
    if [[ -z "$cargo_bin" ]]; then
        echo "meta_skill ARM64 Linux fallback requires cargo for the target user" >&2
        return 1
    fi

    echo "meta_skill: Linux ARM64 detected, building from source via cargo" >&2
    update_run_in_target_context "" "$cargo_bin" install --git https://github.com/Dicklesworthstone/meta_skill --force
}

# shellcheck disable=SC2317,SC2329  # invoked indirectly via run_cmd()
update_run_slb_source_install() {
    log_to_file "Building SLB from source (upstream installer issue workaround)"

    local build_cmd
    build_cmd="$(cat <<'EOF'
set -euo pipefail
mkdir -p "$HOME/go/bin"
SLB_TMP="$(mktemp -d "${TMPDIR:-/tmp}/slb_build.XXXXXX")"
trap '[ -n "$SLB_TMP" ] && rm -rf "$SLB_TMP"' EXIT
cd "$SLB_TMP"
git clone --depth 1 https://github.com/Dicklesworthstone/simultaneous_launch_button.git .
go build -o "$HOME/go/bin/slb" ./cmd/slb
EOF
)"
    update_run_in_target_context "" bash -c "$build_cmd"
}

# shellcheck disable=SC2317,SC2329  # invoked indirectly via run_cmd()
update_run_cargo_git_source_install() {
    local repo_url="${1:-}"
    local binary_name="${2:-}"

    if [[ -z "$repo_url" || -z "$binary_name" ]]; then
        echo "update_run_cargo_git_source_install requires repo URL and binary name" >&2
        return 1
    fi

    local build_cmd
    build_cmd="$(cat <<'EOF'
set -euo pipefail
mkdir -p "$HOME/.cargo/bin"
make_acfs_cargo_tmp_dir() {
    local candidate=""
    local tmp_dir=""
    local tmpdir_value="${TMPDIR:-}"
    local non_default_tmpdir=""
    local -a candidates=()

    if [[ -n "$tmpdir_value" && "${tmpdir_value%/}" != "/tmp" ]]; then
        non_default_tmpdir="${tmpdir_value%/}"
    fi

    [[ -n "${ACFS_UPDATE_TMPDIR:-}" ]] && candidates+=("${ACFS_UPDATE_TMPDIR%/}")
    [[ -n "$non_default_tmpdir" ]] && candidates+=("$non_default_tmpdir")
    candidates+=("/data/tmp" "$HOME/.cache/acfs/tmp")
    [[ -n "$tmpdir_value" ]] && candidates+=("${tmpdir_value%/}")
    candidates+=("/tmp")

    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" ]] || continue
        [[ "$candidate" != "/" ]] || continue
        mkdir -p "$candidate" 2>/dev/null || continue
        [[ -d "$candidate" && -w "$candidate" ]] || continue
        tmp_dir="$(mktemp -d "$candidate/acfs_cargo_build.XXXXXX" 2>/dev/null)" || continue
        printf '%s\n' "$tmp_dir"
        return 0
    done

    return 1
}
ACFS_TMP_DIR="$(make_acfs_cargo_tmp_dir)" || {
    echo "No writable temporary directory available for cargo source build" >&2
    exit 1
}
trap '[ -n "$ACFS_TMP_DIR" ] && rm -rf "$ACFS_TMP_DIR"' EXIT
git clone --depth 1 "$1" "$ACFS_TMP_DIR/src"
cd "$ACFS_TMP_DIR/src"
cargo build --release --target-dir "$ACFS_TMP_DIR/target"
install -m 0755 "$ACFS_TMP_DIR/target/release/$2" "$HOME/.cargo/bin/$2"
EOF
)"
    update_run_in_target_context "" bash -c "$build_cmd" _ "$repo_url" "$binary_name"
}

# ============================================================
# Verified Installer Wrappers
# ============================================================
# Download an upstream installer, verify its SHA-256 checksum
# against checksums.yaml, and execute it in the target context.
# ============================================================

# shellcheck disable=SC2317,SC2329  # invoked indirectly via run_cmd()
update_run_verified_installer_with_env() {
    if [[ $# -lt 1 ]]; then
        echo "update_run_verified_installer_with_env requires a tool name" >&2
        return 1
    fi

    local tool="$1"
    local bash_env_assignment="${2:-}"
    if [[ $# -ge 2 ]]; then
        shift 2
    else
        shift
    fi

    if [[ "$tool" == "ms" ]] && update_is_linux_arm64; then
        update_run_meta_skill_source_install
        return $?
    fi

    if ! update_require_security; then
        echo "Security verification unavailable (missing $SCRIPT_DIR/security.sh, repo scripts/lib/security.sh, or checksums.yaml)" >&2
        return 1
    fi

    local url="${KNOWN_INSTALLERS[$tool]:-}"
    local expected_sha256
    expected_sha256="$(get_checksum "$tool")"

    if [[ -z "$url" ]] || [[ -z "$expected_sha256" ]]; then
        echo "Missing checksum entry for $tool" >&2
        return 1
    fi

    if [[ -n "$bash_env_assignment" ]]; then
        if [[ "$bash_env_assignment" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local env_name="${BASH_REMATCH[1]}"
            local env_value="${BASH_REMATCH[2]}"
            bash_env_assignment="${env_name}=${env_value}"
        else
            echo "Invalid inline env assignment for $tool installer: $bash_env_assignment" >&2
            return 1
        fi
    fi

    local tmp_install=""
    tmp_install=$(mktemp "${TMPDIR:-/tmp}/acfs-update-${tool}.XXXXXX" 2>/dev/null) || tmp_install=""
    if [[ -z "$tmp_install" ]]; then
        echo "Failed to create temp file for verified $tool installer" >&2
        return 1
    fi

    if verify_checksum "$url" "$expected_sha256" "$tool" > "$tmp_install"; then
        :
    else
        local verify_exit_code=$?
        rm -f "$tmp_install" 2>/dev/null || true
        return "$verify_exit_code"
    fi

    if ! chmod +x "$tmp_install"; then
        rm -f "$tmp_install" 2>/dev/null || true
        return 1
    fi

    local exit_code=0
    update_run_in_target_context "$bash_env_assignment" bash "$tmp_install" "$@" </dev/null || exit_code=$?
    rm -f "$tmp_install" 2>/dev/null || true

    return "$exit_code"
}

# shellcheck disable=SC2317,SC2329  # invoked indirectly via run_cmd()
update_run_verified_installer() {
    if [[ $# -lt 1 ]]; then
        echo "update_run_verified_installer requires a tool name" >&2
        return 1
    fi

    local tool="$1"
    shift
    update_run_verified_installer_with_env "$tool" "" "$@"
}

update_run_verified_installer_or_existing_on_transient() {
    local desc="$1"
    local installer_key="$2"
    local binary_name="$3"
    local version_tool="$4"
    shift 4

    local exit_code=0
    local existing_path=""
    local existing_version="unknown"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "skip" "$desc" "dry-run: verified installer"
        return 0
    fi

    log_item "run" "$desc"
    update_run_command_capture_with_retry "$desc" update_run_verified_installer "$installer_key" "$@" || exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        update_finish_cmd_ok "$desc"
        return 0
    fi

    existing_path="$(update_binary_path "$binary_name" 2>/dev/null || true)"
    existing_version="$(get_version "$version_tool" 2>/dev/null || true)"
    if update_is_transient_failure_output "$UPDATE_LAST_COMMAND_OUTPUT" && [[ -n "$existing_path" && -x "$existing_path" && -n "$existing_version" && "$existing_version" != "unknown" ]]; then
        update_finish_cmd_skip "$desc" "upstream temporarily unavailable; existing ${binary_name} ${existing_version} remains installed"
        return 0
    fi

    update_finish_cmd_fail "$desc" "installer exited ${exit_code}"
    return 1
}

update_run_pcr_installer_and_verify() {
    local hook_script="${1:-}"

    if [[ -z "$hook_script" ]]; then
        echo "PCR hook path is required" >&2
        return 1
    fi

    update_run_verified_installer pcr --yes || return $?

    if [[ ! -x "$hook_script" ]]; then
        echo "PCR installer completed but hook is missing or not executable: $hook_script" >&2
        return 1
    fi

    update_run_verified_installer pcr --doctor --json
}

# ============================================================
# Update Functions
# ============================================================

# ------------------------------------------------------------
# Refresh installed security.sh from the repo checkout.
# Stale installed copies shadow the repo because
# update_require_security() searches installed paths first.
#
# Note: sync_acfs_deployed() also syncs security.sh, but this
# function provides a targeted safety net with hardcoded paths
# that works even before sync_acfs_deployed was introduced.
# ------------------------------------------------------------
update_refresh_installed_security() {
    local installed_security=""
    local runtime_acfs_home=""
    runtime_acfs_home="$(update_runtime_acfs_home 2>/dev/null || true)"
    [[ -n "$runtime_acfs_home" ]] || return 0
    installed_security="$runtime_acfs_home/scripts/lib/security.sh"
    [[ -f "$installed_security" ]] || return 0

    # Find the authoritative repo checkout (may differ from ACFS_REPO_ROOT
    # when running from the installed copy at ~/.acfs).
    local repo_security=""
    local -a repo_candidates=(
        "/data/projects/agentic_coding_flywheel_setup/scripts/lib/security.sh"
        "${ACFS_REPO_ROOT}/scripts/lib/security.sh"
    )
    for candidate in "${repo_candidates[@]}"; do
        # Skip if it resolves to the same file as the installed copy
        if [[ -f "$candidate" ]] && [[ "$(realpath "$candidate" 2>/dev/null)" != "$(realpath "$installed_security" 2>/dev/null)" ]]; then
            repo_security="$candidate"
            break
        fi
    done
    [[ -n "$repo_security" ]] || return 0

    local repo_sec_hash installed_sec_hash
    repo_sec_hash=$(sha256sum "$repo_security" 2>/dev/null | cut -d' ' -f1) || true
    installed_sec_hash=$(sha256sum "$installed_security" 2>/dev/null | cut -d' ' -f1) || true
    if [[ -n "$repo_sec_hash" ]] && [[ "$repo_sec_hash" != "$installed_sec_hash" ]]; then
        cp "$repo_security" "$installed_security"
        log_to_file "Refreshed installed security.sh from $repo_security (was stale)"
    fi
}

# ------------------------------------------------------------
# Extract security-critical files from an already-fetched remote.
# Called when a full git pull is not possible (dirty worktree,
# ff-only failure, wrong branch, etc.) but we still need fresh
# checksums and URLs so verified-installer checks don't break.
# Requires: git fetch origin main has already succeeded.
# ------------------------------------------------------------
_acfs_refresh_security_from_fetched_remote() {
    # First arg is the canonical primary remote branch. Defaults to `main`
    # for backward compatibility, but callers in update_acfs_self() pass the
    # branch the install is checked out on (main or master — the two are
    # maintained as parallel refs with identical SHAs).
    local _sec_remote_branch="${1:-main}"
    local _sec_files_refreshed=false
    local _sec_relpath
    for _sec_relpath in checksums.yaml scripts/lib/security.sh; do
        local _sec_target="$ACFS_REPO_ROOT/$_sec_relpath"
        local _sec_tmp=""
        _sec_tmp="$(mktemp "${TMPDIR:-/tmp}/acfs-sec-refresh.XXXXXX" 2>/dev/null)" || continue
        if git -C "$ACFS_REPO_ROOT" show "origin/${_sec_remote_branch}:$_sec_relpath" > "$_sec_tmp" 2>/dev/null; then
            if [[ -s "$_sec_tmp" ]] && ! cmp -s "$_sec_tmp" "$_sec_target" 2>/dev/null; then
                cp -f "$_sec_tmp" "$_sec_target" 2>/dev/null && _sec_files_refreshed=true
                log_to_file "Refreshed $_sec_relpath from origin/${_sec_remote_branch} (bypassing full pull)"
            fi
        fi
        rm -f "$_sec_tmp" 2>/dev/null
    done

    if [[ "$_sec_files_refreshed" == "true" ]]; then
        log_item "ok" "ACFS checksums" "refreshed from remote"
        update_refresh_installed_security
        sync_acfs_deployed
        sync_acfs_global_wrapper
    fi
}

_acfs_remote_main_head() {
    # First arg is the canonical primary remote branch. Defaults to `main`
    # for backward compatibility (e.g. for any callers that haven't been
    # updated to pass it explicitly).
    local _head_remote_branch="${1:-main}"
    git -C "$ACFS_REPO_ROOT" ls-remote --heads origin "$_head_remote_branch" 2>/dev/null | awk 'NR==1 { print $1 }'
}

_acfs_repo_root_is_runtime_acfs_home() {
    local runtime_acfs_home=""
    local resolved_repo=""
    local resolved_runtime=""

    runtime_acfs_home="$(update_runtime_acfs_home 2>/dev/null || true)"
    [[ -n "$runtime_acfs_home" ]] || return 1

    resolved_repo="$(realpath "$ACFS_REPO_ROOT" 2>/dev/null || printf '%s\n' "$ACFS_REPO_ROOT")"
    resolved_runtime="$(realpath "$runtime_acfs_home" 2>/dev/null || printf '%s\n' "$runtime_acfs_home")"
    [[ "$resolved_repo" == "$resolved_runtime" ]]
}

_acfs_append_unique_path() {
    local -n _acfs_paths_ref="$1"
    local _acfs_candidate="$2"
    local _acfs_existing=""

    for _acfs_existing in "${_acfs_paths_ref[@]}"; do
        [[ "$_acfs_existing" == "$_acfs_candidate" ]] && return 0
    done

    _acfs_paths_ref+=("$_acfs_candidate")
}

_acfs_collect_tracked_dirty_paths() {
    local -n _acfs_dirty_paths_ref="$1"
    local _acfs_dirty_path=""

    _acfs_dirty_paths_ref=()
    while IFS= read -r -d '' _acfs_dirty_path; do
        _acfs_append_unique_path _acfs_dirty_paths_ref "$_acfs_dirty_path"
    done < <(git -C "$ACFS_REPO_ROOT" diff --name-only -z -- 2>/dev/null || true)

    while IFS= read -r -d '' _acfs_dirty_path; do
        _acfs_append_unique_path _acfs_dirty_paths_ref "$_acfs_dirty_path"
    done < <(git -C "$ACFS_REPO_ROOT" diff --cached --name-only -z -- 2>/dev/null || true)
}

_acfs_worktree_path_matches_upstream_history() {
    local _acfs_path="$1"
    local _acfs_remote_branch="${2:-main}"
    local _acfs_work_hash=""
    local _acfs_ref=""
    local _acfs_blob=""
    local _acfs_commit=""

    [[ -f "$ACFS_REPO_ROOT/$_acfs_path" ]] || return 1
    _acfs_work_hash="$(git -C "$ACFS_REPO_ROOT" hash-object -- "$_acfs_path" 2>/dev/null)" || return 1
    [[ -n "$_acfs_work_hash" ]] || return 1

    for _acfs_ref in HEAD "origin/${_acfs_remote_branch}"; do
        _acfs_blob="$(git -C "$ACFS_REPO_ROOT" rev-parse "$_acfs_ref:$_acfs_path" 2>/dev/null || true)"
        [[ "$_acfs_blob" == "$_acfs_work_hash" ]] && return 0
    done

    while IFS= read -r _acfs_commit; do
        [[ -n "$_acfs_commit" ]] || continue
        _acfs_blob="$(git -C "$ACFS_REPO_ROOT" rev-parse "$_acfs_commit:$_acfs_path" 2>/dev/null || true)"
        [[ "$_acfs_blob" == "$_acfs_work_hash" ]] && return 0
    done < <(git -C "$ACFS_REPO_ROOT" rev-list --ancestry-path "HEAD..origin/${_acfs_remote_branch}" -- "$_acfs_path" 2>/dev/null || true)

    return 1
}

_acfs_dirty_paths_are_upstream_derived() {
    local _acfs_remote_branch="$1"
    local _acfs_dirty_path=""
    shift || true

    (($# > 0)) || return 1
    git -C "$ACFS_REPO_ROOT" merge-base --is-ancestor HEAD "origin/${_acfs_remote_branch}" >/dev/null 2>&1 || return 1

    for _acfs_dirty_path in "$@"; do
        _acfs_worktree_path_matches_upstream_history "$_acfs_dirty_path" "$_acfs_remote_branch" || return 1
    done
}

_acfs_try_upstream_derived_dirty_fast_forward() {
    local current_branch="$1"
    local local_head="$2"
    local remote_head="$3"
    local remote_branch="${4:-main}"
    local -a dirty_paths=()

    _acfs_repo_root_is_runtime_acfs_home || return 1

    _acfs_collect_tracked_dirty_paths dirty_paths
    ((${#dirty_paths[@]} > 0)) || return 1
    _acfs_dirty_paths_are_upstream_derived "$remote_branch" "${dirty_paths[@]}" || return 1

    log_item "fix" "ACFS self-update" "tracked changes match upstream history; completing fast-forward"
    log_to_file "Repairing upstream-derived dirty checkout with ${#dirty_paths[@]} tracked path(s)"

    if git -C "$ACFS_REPO_ROOT" checkout -f -B "$current_branch" "$remote_head" >/dev/null 2>&1; then
        git -C "$ACFS_REPO_ROOT" branch --set-upstream-to="origin/${remote_branch}" "$current_branch" >/dev/null 2>&1 || true
        log_to_file "Completed managed dirty fast-forward from $local_head to $remote_head"
        return 0
    fi

    log_to_file "Managed dirty fast-forward failed; leaving checkout untouched"
    return 1
}

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
        log_item "info" "ACFS self-update" "already completed"
        return 0
    fi

    # Recovery for orphaned git init (issue #200)
    if [[ -d "$ACFS_REPO_ROOT/.git" ]] && ! git -C "$ACFS_REPO_ROOT" rev-parse HEAD &>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_item "ok" "ACFS self-update" "would recover incomplete git bootstrap"
            return 0
        fi
        log_to_file "Detected incomplete git bootstrap — attempting recovery..."
        local actual_origin
        actual_origin=$(git -C "$ACFS_REPO_ROOT" remote get-url origin 2>/dev/null || true)
        if is_expected_acfs_origin_url "$actual_origin"; then
            if ! git -C "$ACFS_REPO_ROOT" fetch origin main --quiet 2>/dev/null; then
                log_item "warn" "ACFS self-update" "git recovery fetch failed; leaving existing .git untouched"
                return 0
            fi

            if git -C "$ACFS_REPO_ROOT" checkout -f -B main --track origin/main; then
                log_to_file "Git bootstrap recovery succeeded"
            else
                log_item "warn" "ACFS self-update" "git recovery checkout failed; leaving existing .git untouched"
                return 0
            fi
        else
            log_item "warn" "ACFS self-update" "unexpected origin during git recovery: ${actual_origin:-<unset>}"
            return 0
        fi
    fi

    # Check if ACFS repo exists and is a git repo.
    # If installed via tarball (no .git dir), require an explicit opt-in before
    # converting the install into a git checkout. Automatic bootstrap can
    # overwrite local files under ~/.acfs, which is too surprising for routine
    # update and nightly flows.
    if [[ ! -d "$ACFS_REPO_ROOT/.git" ]]; then
        if [[ "$BOOTSTRAP_SELF_UPDATE" != "true" ]]; then
            log_item "skip" "ACFS self-update" "installed tree is not a git checkout; skipping to avoid overwriting local files (use --bootstrap-self-update to opt in)"
            return 0
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            log_item "ok" "ACFS self-update" "would bootstrap git checkout from https://github.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}.git"
            return 0
        fi

        log_to_file "No .git directory found at $ACFS_REPO_ROOT — bootstrapping git repo for self-update..."

        # Check if git is available before attempting bootstrap
        if ! command -v git &>/dev/null; then
            log_item "skip" "ACFS self-update" "git not found, cannot bootstrap"
            return 0
        fi

        if ! git -C "$ACFS_REPO_ROOT" init -b main 2>/dev/null; then
            log_item "warn" "ACFS self-update" "git init failed at $ACFS_REPO_ROOT"
            return 0
        fi

        local expected_origin
        expected_origin="https://github.com/${ACFS_REPO_OWNER}/${ACFS_REPO_NAME}.git"
        if ! git -C "$ACFS_REPO_ROOT" remote add origin "$expected_origin" 2>/dev/null; then
            # Remote may already exist from a partial prior run; verify it points to the right URL
            local existing_url
            existing_url=$(git -C "$ACFS_REPO_ROOT" remote get-url origin 2>/dev/null) || true
            if ! is_expected_acfs_origin_url "$existing_url"; then
                log_item "warn" "ACFS self-update" "unexpected origin remote: $existing_url"
                return 0
            fi
        fi

        if ! git -C "$ACFS_REPO_ROOT" fetch origin main --quiet 2>/dev/null; then
            log_item "warn" "ACFS self-update" "git fetch failed during bootstrap (network issue?)"
            return 0
        fi

        # Use a forced checkout so the working tree is updated to match
        # origin/main exactly (tarball files are replaced with the real repo state).
        # -f is required because the tarball-installed files appear as untracked
        # and git refuses to overwrite them without force.
        if ! git -C "$ACFS_REPO_ROOT" checkout -f -B main --track origin/main; then
            log_item "warn" "ACFS self-update" "git checkout failed during bootstrap"
            return 0
        fi

        log_item "ok" "ACFS" "git repo bootstrapped from tarball install"
        log_to_file "ACFS git repo initialized at $ACFS_REPO_ROOT — continuing with self-update"
    fi

    # Check if git is available
    if ! command -v git &>/dev/null; then
        log_item "skip" "ACFS self-update" "git not found"
        return 0
    fi

    # Security: verify we are pulling from the expected ACFS origin.
    # Do this for normal runs too (not only bootstrap mode) to prevent
    # accidental or malicious self-update from an unexpected remote.
    local origin_url
    origin_url=$(git -C "$ACFS_REPO_ROOT" remote get-url origin 2>/dev/null || true)
    if [[ -z "$origin_url" ]]; then
        log_item "warn" "ACFS self-update" "origin remote not configured"
        return 0
    fi
    if ! is_expected_acfs_origin_url "$origin_url"; then
        log_item "warn" "ACFS self-update" "unexpected origin remote: $origin_url"
        return 0
    fi

    # Get current branch
    local current_branch=""
    current_branch=$(git -C "$ACFS_REPO_ROOT" branch --show-current 2>/dev/null) || true
    if [[ -z "$current_branch" ]] || [[ "$current_branch" == "HEAD" ]]; then
        log_item "warn" "ACFS self-update" "failed to get current branch"
        return 0
    fi

    # Determine the canonical primary remote branch. The remote maintains
    # both `main` and `master` as parallel refs with identical SHAs (legacy
    # URL compatibility), so installs may be checked out on either one.
    # Prefer origin/HEAD when resolvable as the source-of-truth ref.
    local remote_branch="main"
    local _origin_head_ref=""
    _origin_head_ref=$(git -C "$ACFS_REPO_ROOT" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || true
    if [[ -n "$_origin_head_ref" ]]; then
        # Strip the literal `refs/remotes/origin/` prefix. Use shortest-match
        # `#` rather than longest-match `##*/` so branch names containing
        # slashes (e.g. `release/v1`) survive intact.
        remote_branch="${_origin_head_ref#refs/remotes/origin/}"
    fi

    # Only auto-update when the local branch matches a primary remote branch
    # (main or master — they're parallel and share SHAs). Still refresh
    # security files in the skip path so checksums stay fresh.
    if [[ "$current_branch" != "main" && "$current_branch" != "master" ]]; then
        log_item "skip" "ACFS self-update" "not on main branch (on: $current_branch)"
        if update_is_read_only_mode; then
            return 0
        fi
        # Still fetch and refresh security files so checksums stay fresh
        if git -C "$ACFS_REPO_ROOT" fetch origin "$remote_branch" --quiet 2>/dev/null; then
            _acfs_refresh_security_from_fetched_remote "$remote_branch"
        fi
        return 0
    fi

    # Track the local branch to its matching remote branch so fetch/pull/reset
    # operate on the right ref regardless of which name (main vs master) the
    # install is checked out on.
    remote_branch="$current_branch"

    local local_head=""
    local remote_head=""
    local_head=$(git -C "$ACFS_REPO_ROOT" rev-parse HEAD 2>/dev/null) || true

    if update_is_read_only_mode; then
        remote_head="$(_acfs_remote_main_head "$remote_branch")"
        if [[ -z "$local_head" ]] || [[ -z "$remote_head" ]]; then
            log_item "warn" "ACFS self-update" "failed to compare versions in dry-run"
            return 0
        fi

        if [[ "$local_head" == "$remote_head" ]]; then
            log_item "ok" "ACFS $ACFS_VERSION_DISPLAY" "already up to date"
        else
            log_item "ok" "ACFS" "would update (remote ${remote_branch} differs)"
        fi
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
    if ! git -C "$ACFS_REPO_ROOT" fetch origin "$remote_branch" --quiet 2>/dev/null; then
        log_item "warn" "ACFS self-update" "git fetch failed (network issue?)"
        return 0
    fi

    # Compare local HEAD with remote
    local_head=$(git -C "$ACFS_REPO_ROOT" rev-parse HEAD 2>/dev/null) || true
    remote_head=$(git -C "$ACFS_REPO_ROOT" rev-parse "origin/$remote_branch" 2>/dev/null) || true

    if [[ -z "$local_head" ]] || [[ -z "$remote_head" ]]; then
        log_item "warn" "ACFS self-update" "failed to compare versions"
        return 0
    fi

    if [[ "$local_head" == "$remote_head" ]]; then
        log_item "ok" "ACFS $ACFS_VERSION_DISPLAY" "already up to date"
        update_refresh_installed_security
        return 0
    fi

    # Show what's coming
    local commit_count
    commit_count=$(git -C "$ACFS_REPO_ROOT" rev-list --count "HEAD..origin/$remote_branch" 2>/dev/null) || commit_count="?"
    log_to_file "Found $commit_count new commit(s)"

    # Dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "ok" "ACFS" "would update ($commit_count new commits)"
        return 0
    fi

    # Skip full git pull if tracked files have local modifications to avoid
    # merge conflicts. Use --untracked-files=no because ~/.acfs/ contains
    # runtime state files (state.json, logs/, cache/, autofix/) that are
    # not in the git repo — these must not block self-update since
    # git pull --ff-only never touches untracked files.
    #
    # Even when we can't pull, we STILL extract security-critical files
    # (checksums.yaml, security.sh) from the fetched remote so that
    # verified-installer checks use fresh checksums and URLs. Without this,
    # machines with local modifications run with stale checksums indefinitely,
    # causing constant checksum-mismatch failures for Dicklesworthstone tools.
    local self_update_completed=false
    if [[ -n "$(git -C "$ACFS_REPO_ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
        if _acfs_try_upstream_derived_dirty_fast_forward "$current_branch" "$local_head" "$remote_head" "$remote_branch"; then
            self_update_completed=true
        else
            log_item "warn" "ACFS self-update" "tracked files have local modifications; skipping full pull"
            log_to_file "Self-update skipped: working tree has tracked modifications — refreshing security files only"
            _acfs_refresh_security_from_fetched_remote "$remote_branch"
            return 0
        fi
    fi

    if [[ "$self_update_completed" != "true" ]]; then
        # Pull updates
        log_to_file "Pulling updates..."
        if ! git -C "$ACFS_REPO_ROOT" pull --ff-only origin "$remote_branch" 2>/dev/null; then
            log_item "warn" "ACFS self-update" "ff-only pull failed (branch divergence?); refreshing security files"
            log_to_file "Self-update skipped: git pull --ff-only failed — refreshing security files only"
            _acfs_refresh_security_from_fetched_remote "$remote_branch"
            return 0
        fi
    fi

    # Refresh version display with new commit hash after pull
    local _new_short_hash=""
    _new_short_hash=$(git -C "$ACFS_REPO_ROOT" rev-parse --short HEAD 2>/dev/null) || true
    if [[ -n "$_new_short_hash" ]]; then
        # Re-read VERSION in case it changed
        if [[ -f "$ACFS_REPO_ROOT/VERSION" ]]; then
            ACFS_VERSION="$(cat "$ACFS_REPO_ROOT/VERSION" 2>/dev/null || echo "$ACFS_VERSION")"
        fi
        ACFS_VERSION_DISPLAY="v${ACFS_VERSION}+${_new_short_hash}"
    fi

    log_item "ok" "ACFS $ACFS_VERSION_DISPLAY" "updated ($commit_count commits)"
    log_to_file "ACFS updated from $local_head to $remote_head"

    update_refresh_installed_security

    # Sync critical scripts from repo to ~/.acfs/ so the deployed copies
    # stay fresh.  This MUST happen before the re-exec check below, because
    # $update_script points to ~/.acfs/scripts/lib/update.sh — if we don't
    # copy the new version there first, the hash comparison won't trigger
    # the re-exec and future runs will use the old code.
    sync_acfs_deployed
    sync_acfs_global_wrapper

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

# Prevent needrestart from hanging apt on Ubuntu 22.04+. The apt hook
# /usr/lib/needrestart/apt-pinvoke prompts interactively even when
# NEEDRESTART_SUSPEND=1 is exported, because sudo strips the env var before
# reaching the hook. Disabling the hook executable is the bulletproof fix —
# matches the pattern already used in install.sh::disable_needrestart_apt_hook.
update_disable_needrestart_apt_hook() {
    local apt_hook="/usr/lib/needrestart/apt-pinvoke"
    local nr_conf_dir="/etc/needrestart/conf.d"
    local nr_conf_file="$nr_conf_dir/50-acfs-noninteractive.conf"

    [[ "${DRY_RUN:-false}" == "true" ]] && return 0
    command -v apt-get &>/dev/null || return 0

    local sudo_cmd
    sudo_cmd=$(get_sudo)

    # Method 1: disable the apt hook executable. Bulletproof — the hook can't
    # run at all once the exec bit is cleared.
    if [[ -f "$apt_hook" && -x "$apt_hook" ]]; then
        log_to_file "Disabling needrestart apt hook to prevent interactive hangs"
        $sudo_cmd chmod -x "$apt_hook" 2>/dev/null || true
    fi

    # Method 2: drop a conf file that forces auto-restart if needrestart runs
    # via some other path (e.g. user re-enables the hook). Idempotent — always
    # (re)write so a stale/corrupted prior conf is corrected.
    if [[ -d "$nr_conf_dir" ]] || $sudo_cmd mkdir -p "$nr_conf_dir" 2>/dev/null; then
        printf '$nrconf{restart} = %s;\n' "'a'" \
            | $sudo_cmd tee "$nr_conf_file" >/dev/null 2>&1 || true
    fi
}

update_apt() {
    if [[ "$UPDATE_APT" != "true" ]]; then
        return 0
    fi

    log_section "System Packages (apt)"

    # Neutralise needrestart before any apt-get call — must happen first so
    # even `apt update` (which can trigger the hook on some configs) is safe.
    update_disable_needrestart_apt_hook

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
    run_cmd_sudo_with_retry_status "apt update" env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 apt-get update -y || true

    # Get list of upgradable packages before upgrade
    local upgradable_list=""
    local upgrade_count=0
    if upgradable_list=$(apt list --upgradable 2>/dev/null | grep -v "^Listing"); then
        upgrade_count=$(echo "$upgradable_list" | { grep -c . || true; })
        if [[ $upgrade_count -gt 0 ]]; then
            log_to_file "Upgradable packages ($upgrade_count):"
            log_to_file "$upgradable_list"
        fi
    fi

    if [[ $upgrade_count -eq 0 ]]; then
        log_item "ok" "apt upgrade" "all packages up to date"
    else
        log_to_file "Attempting apt upgrade for $upgrade_count upgradable package candidates..."
        if ! run_cmd_sudo_attempt_with_retry "apt upgrade" env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 apt-get upgrade -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold; then
            run_cmd_sudo_with_retry_status "apt upgrade --fix-missing" env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 apt-get upgrade -y --fix-missing -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold || true
        fi
    fi

    run_cmd_sudo_with_retry_status "apt autoremove" env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 apt-get autoremove -y || true

    # Check if reboot is required (kernel updates, etc.)
    check_reboot_required
}

# Wait for apt lock to be released, with automatic retry
# Returns 0 if lock is free, 1 if still locked after max attempts
apt_lock_is_held() {
    local lockfile="$1"

    local fuser_bin=""
    fuser_bin="$(update_system_binary_path fuser 2>/dev/null || true)"
    [[ -n "$fuser_bin" ]] || return 1
    [[ -f "$lockfile" ]] || return 1

    # Try as current user first (works when lockfile is readable).
    if "$fuser_bin" "$lockfile" &>/dev/null; then
        return 0
    fi

    # Fallback to non-interactive sudo to avoid hanging in safe mode / CI.
    local sudo_bin=""
    sudo_bin="$(update_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -n "$fuser_bin" "$lockfile" &>/dev/null && return 0
    fi

    return 1
}

apt_lock_holder_details() {
    local lockfile="$1"
    local details=""

    local fuser_bin=""
    fuser_bin="$(update_system_binary_path fuser 2>/dev/null || true)"
    [[ -n "$fuser_bin" ]] || return 1
    [[ -f "$lockfile" ]] || return 1

    details=$("$fuser_bin" -v "$lockfile" 2>&1 || true)
    if [[ -n "$details" ]]; then
        printf '%s\n' "$details"
        return 0
    fi

    local sudo_bin=""
    sudo_bin="$(update_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        details=$("$sudo_bin" -n "$fuser_bin" -v "$lockfile" 2>/dev/null || true)
        if [[ -n "$details" ]]; then
            printf '%s\n' "$details"
            return 0
        fi
    fi

    return 1
}

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
            if apt_lock_is_held "$lockfile"; then
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
            lock_info=$(apt_lock_holder_details /var/lib/dpkg/lock-frontend 2>/dev/null || true)
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
        local sudo_cmd
        sudo_cmd=$(get_sudo)
        log_item "fix" "dpkg" "configuring interrupted packages"
        log_to_file "Running: $sudo_cmd dpkg --configure -a"
        local dpkg_output
        dpkg_output=$($sudo_cmd env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 dpkg --configure -a 2>&1) || true
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
        local sudo_cmd
        sudo_cmd=$(get_sudo)
        log_to_file "Running: $sudo_cmd apt-get -f install -y"
        local apt_output
        apt_output=$($sudo_cmd env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 apt-get -f install -y 2>&1) || true
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
        if apt_lock_is_held "$lockfile"; then
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
    lock_holder=$(apt_lock_holder_details /var/lib/dpkg/lock-frontend 2>/dev/null || true)
    if [[ -n "$lock_holder" ]]; then
        log_to_file "Lock holder: $lock_holder"
        if [[ "$QUIET" != "true" ]]; then
            echo -e "       ${DIM}Lock held by: $lock_holder${NC}"
        fi
    fi

    if [[ "$ABORT_ON_FAILURE" == "true" ]]; then
        echo -e "${RED}Aborting: apt is locked and could not be released${NC}"
        log_to_file "ABORT: Stopping due to --abort-on-failure"
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
    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        return 0
    fi

    log_section "Bun Runtime"

    local bun_bin=""
    bun_bin="$(update_binary_path bun 2>/dev/null || true)"

    if [[ -z "$bun_bin" ]]; then
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
    if [[ "$UPDATE_AGENTS" != "true" ]]; then
        return 0
    fi

    local target_user=""
    local target_home=""
    target_user="$(update_target_user)"
    target_home="$(update_target_home "$target_user" 2>/dev/null || true)"

    log_section "Coding Agents"

    # Claude Code - can update without bun; supports install/reinstall with --force.
    #
    # Check for bun-installed Claude and remove it if native install is requested.
    # The native install goes to ~/.local/bin/claude which should take precedence,
    # but having both can cause PATH confusion and doctor warnings.
    local claude_path=""
    claude_path="$(update_binary_path claude 2>/dev/null || true)"
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
        local bun_remove_bin=""
        bun_remove_bin="$(update_binary_path bun 2>/dev/null || true)"
        if [[ -n "$bun_remove_bin" ]]; then
            # Try to uninstall via bun
            "$bun_remove_bin" remove -g @anthropic-ai/claude-code 2>/dev/null || true
        fi
        # Also remove the symlink/binary directly if it still exists
        if [[ -f "$claude_path" || -L "$claude_path" ]]; then
            rm -f "$claude_path" 2>/dev/null || true
        fi
        # Remove the actual bun binary too if it's separate from the symlink
        local bun_claude_bin="${target_home:-$HOME}/.bun/bin/claude"
        if [[ -f "$bun_claude_bin" || -L "$bun_claude_bin" ]] && [[ "$bun_claude_bin" != "$claude_path" ]]; then
            rm -f "$bun_claude_bin" 2>/dev/null || true
        fi
        # Clear the cached path so we detect as "not installed" for fresh install
        claude_path=""
    fi

    if [[ -n "$claude_path" ]] && [[ "$bun_claude_detected" != "true" || "$FORCE_MODE" != "true" ]]; then
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

    local bun_bin=""
    bun_bin="$(update_binary_path bun 2>/dev/null || true)"
    if [[ -z "$bun_bin" ]]; then
        log_item "fail" "Bun not installed" "required for Codex/Gemini updates"
        return 0
    fi

    # Codex CLI via bun (--trust allows postinstall scripts)
    # Uses fallback chain: @latest -> unversioned -> pinned 0.87.0
    # npm can 404 briefly after publishing; pinned version is reliable fallback
    if update_binary_exists codex || [[ "$FORCE_MODE" == "true" ]]; then
        local codex_fallback_version="0.87.0"

        capture_version_before "codex"
        
        log_item "run" "Codex CLI"
        local success=false
        local output=""
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_item "skip" "Codex CLI" "dry-run"
        else
            for pkg in "@openai/codex@latest" "@openai/codex" "@openai/codex@$codex_fallback_version"; do
                log_to_file "Trying bun install $pkg"
                local attempt=1
                local pkg_success=false
                while [[ $attempt -le 3 ]]; do
                    if output=$(update_run_in_target_context "" "$bun_bin" install -g --trust "$pkg" 2>&1); then
                        pkg_success=true
                        success=true
                        break 2
                    fi
                    sleep 2
                    attempt=$((attempt + 1))
                done
                log_to_file "Failed $pkg after 3 attempts: $output"
            done
            
            if [[ "$success" == "true" ]]; then
                if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
                    printf "\033[1A\033[2K  ${GREEN}[ok]${NC} Codex CLI\n"
                elif [[ "$QUIET" != "true" ]]; then
                    printf "  ${GREEN}[ok]${NC} Codex CLI\n"
                fi
                ((SUCCESS_COUNT += 1))
            else
                if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
                    printf "\033[1A\033[2K  ${RED}[FAIL]${NC} Codex CLI\n"
                elif [[ "$QUIET" != "true" ]]; then
                    printf "  ${RED}[FAIL]${NC} Codex CLI\n"
                fi
                log_to_file "All Codex install attempts failed. Last output: $output"
                ((FAIL_COUNT += 1))
            fi
        fi

        # Show version change without double-counting
        if capture_version_after "codex"; then
            [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[codex]}" "${VERSION_AFTER[codex]}"
        fi
    else
        log_item "skip" "Codex CLI" "not installed (use --force to install)"
    fi

    # Gemini CLI via bun (--trust allows postinstall scripts)
    if update_binary_exists gemini || [[ "$FORCE_MODE" == "true" ]]; then
        local gemini_patch_ready=true
        local gemini_nvm_bin=""
        local gemini_patch_skip_reason="Node.js runtime unavailable"
        capture_version_before "gemini"
        run_cmd_bun_with_retry "Gemini CLI" update_run_in_target_context "" "$bun_bin" install -g --trust @google/gemini-cli@latest
        # Show version change without double-counting
        if capture_version_after "gemini"; then
            [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[gemini]}" "${VERSION_AFTER[gemini]}"
        fi
        # Apply Gemini CLI patches (EBADF crash fix, rate-limit retry, quota retry)
        if [[ "$DRY_RUN" == "true" ]]; then
            log_item "skip" "Node.js runtime for Gemini patch" "dry-run: ensure nvm + latest Node.js when missing"
            gemini_patch_ready=false
            gemini_patch_skip_reason="dry-run: would apply after ensuring nvm + latest Node.js when needed"
        elif update_has_nvm_node; then
            log_item "info" "Node.js runtime for Gemini patch" "nvm + latest Node.js already present"
        else
            log_item "run" "Node.js runtime for Gemini patch"
            if update_ensure_gemini_patch_node; then
                log_item "fix" "Node.js runtime for Gemini patch" "installed nvm + latest Node.js"
            else
                log_item "warn" "Node.js runtime for Gemini patch" "failed to install nvm + latest Node.js; skipping Gemini patch"
                gemini_patch_ready=false
                gemini_patch_skip_reason="Node.js runtime unavailable"
            fi
        fi
        if [[ "$gemini_patch_ready" == "true" ]] && ! gemini_nvm_bin="$(update_nvm_node_bin_dir)"; then
            log_item "warn" "Node.js runtime for Gemini patch" "nvm Node.js bin not found; skipping Gemini patch"
            gemini_patch_ready=false
            gemini_patch_skip_reason="Node.js runtime unavailable"
        fi
        if [[ "$gemini_patch_ready" == "true" ]]; then
            run_cmd "Gemini CLI patches" update_run_verified_installer_with_env gemini_patch "PATH=$gemini_nvm_bin:$PATH"
        else
            log_item "skip" "Gemini CLI patches" "$gemini_patch_skip_reason"
        fi
    else
        log_item "skip" "Gemini CLI" "not installed (use --force to install)"
    fi
}

# Run update_run_verified_installer for Claude with a bounded timeout.
# Uses a background-process approach so that shell functions remain available.
# Returns 124 on timeout (matching timeout(1) convention).
_run_claude_installer_with_timeout() {
    local seconds="${1:-300}"
    update_run_verified_installer claude latest &
    local pid=$!
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        if [[ $elapsed -ge $seconds ]]; then
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    wait "$pid"
}

# Helper for Claude update with proper error handling
# FIX(bd-gsjqf.2): Replaced bare "claude update --channel latest" (flag does not exist)
# with update_run_verified_installer which uses the official install.sh script.
# See: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues/125
run_cmd_claude_update() {
    local desc="Claude Code (verified installer)"
    local cmd_display="update_run_verified_installer claude latest"
    local claude_installer_timeout="${CLAUDE_INSTALLER_TIMEOUT:-300}"

    log_to_file "Running: $cmd_display (timeout: ${claude_installer_timeout}s)"

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
                echo "----- COMMAND: $cmd_display (timeout: ${claude_installer_timeout}s)"
            } >> "$UPDATE_LOG_FILE"
        fi

        if [[ "$QUIET" != "true" ]] && [[ -n "${UPDATE_LOG_FILE:-}" ]]; then
            if _run_claude_installer_with_timeout "$claude_installer_timeout" 2>&1 | tee -a "$UPDATE_LOG_FILE"; then
                exit_code=0
            else
                exit_code=${PIPESTATUS[0]}
            fi
        elif [[ -n "${UPDATE_LOG_FILE:-}" ]]; then
            if _run_claude_installer_with_timeout "$claude_installer_timeout" >> "$UPDATE_LOG_FILE" 2>&1; then
                exit_code=0
            else
                exit_code=$?
            fi
        else
            if [[ "$QUIET" != "true" ]]; then
                _run_claude_installer_with_timeout "$claude_installer_timeout" || exit_code=$?
            else
                _run_claude_installer_with_timeout "$claude_installer_timeout" >/dev/null 2>&1 || exit_code=$?
            fi
        fi
    else
        local output=""
        output=$(_run_claude_installer_with_timeout "$claude_installer_timeout" 2>&1) || exit_code=$?
        [[ -n "$output" ]] && log_to_file "Output: $output"
    fi

    # Detect timeout specifically (exit code 124 from timeout(1))
    if [[ $exit_code -eq 124 ]]; then
        log_to_file "TIMEOUT: Claude installer exceeded ${claude_installer_timeout}s limit"
        if [[ "$QUIET" != "true" ]]; then
            echo -e "  ${YELLOW}[timeout]${NC} $desc (exceeded ${claude_installer_timeout}s)"
        fi
        return 1
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

CURL_ARGS=(--connect-timeout 30 --max-time 300 -fsSL)
if command -v curl &>/dev/null && curl --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(--proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 300 -fsSL)
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
extracted_bin=""

if [[ -z "$tmp_dir" ]] || [[ -z "$tmp_tgz" ]] || [[ -z "$tmp_checksums" ]]; then
  echo "Supabase CLI: failed to create temp files" >&2
  exit 1
fi

cleanup() {
  [[ -n "${tmp_tgz:-}" ]] && rm -f "$tmp_tgz" 2>/dev/null || true
  [[ -n "${tmp_checksums:-}" ]] && rm -f "$tmp_checksums" 2>/dev/null || true
  [[ -n "${extracted_bin:-}" ]] && rm -f "$extracted_bin" 2>/dev/null || true
  if [[ -n "${tmp_dir:-}" ]] && [[ -d "$tmp_dir" ]]; then
    find "$tmp_dir" -type f -delete 2>/dev/null || true
    find "$tmp_dir" -depth -type d -empty -delete 2>/dev/null || true
  fi
}
trap cleanup EXIT

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

mkdir -p "${ACFS_PRIMARY_BIN_DIR:-${ACFS_BIN_DIR:-$HOME/.local/bin}}"
install -m 0755 "$extracted_bin" "${ACFS_PRIMARY_BIN_DIR:-${ACFS_BIN_DIR:-$HOME/.local/bin}}/supabase"

if command -v timeout &>/dev/null; then
  timeout 5 "${ACFS_PRIMARY_BIN_DIR:-${ACFS_BIN_DIR:-$HOME/.local/bin}}/supabase" --version >/dev/null 2>&1 || {
    echo "Supabase CLI: installed but failed to run" >&2
    exit 1
  }
else
  "${ACFS_PRIMARY_BIN_DIR:-${ACFS_BIN_DIR:-$HOME/.local/bin}}/supabase" --version >/dev/null 2>&1 || {
    echo "Supabase CLI: installed but failed to run" >&2
    exit 1
  }
fi
EOF
}

update_cloud() {
    if [[ "$UPDATE_CLOUD" != "true" ]]; then
        return 0
    fi

    log_section "Cloud CLIs"

    local bun_bin=""
    local has_bun=false
    bun_bin="$(update_binary_path bun 2>/dev/null || true)"
    [[ -n "$bun_bin" ]] && has_bun=true

    # Wrangler (--trust allows postinstall scripts for native binaries)
    if update_binary_exists wrangler || [[ "$FORCE_MODE" == "true" ]]; then
        if [[ "$has_bun" == "true" ]]; then
            run_cmd_bun_with_retry "Wrangler (Cloudflare)" update_run_in_target_context "" "$bun_bin" install -g --trust wrangler@latest
        else
            log_item "fail" "Wrangler (Cloudflare)" "bun not installed (required)"
        fi
    else
        log_item "skip" "Wrangler" "not installed"
    fi

    # Supabase (verified GitHub release binary; installed to ~/.local/bin)
    if update_binary_exists supabase || [[ "$FORCE_MODE" == "true" ]]; then
        local supabase_primary_bin=""
        capture_version_before "supabase"
        supabase_primary_bin="$(update_runtime_primary_bin_dir 2>/dev/null || true)"
        if [[ -z "$supabase_primary_bin" ]]; then
            log_item "fail" "Supabase CLI" "unable to resolve target install bin"
        else
            run_cmd "Supabase CLI" update_run_in_target_context "ACFS_PRIMARY_BIN_DIR=$supabase_primary_bin" bash -c "$(supabase_release_update_script)"
            # Refresh PATH in case the target bin was created during install.
            ensure_path
            if capture_version_after "supabase"; then
                [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[supabase]}" "${VERSION_AFTER[supabase]}"
            fi
        fi
    else
        log_item "skip" "Supabase CLI" "not installed"
    fi

    # Vercel (--trust allows postinstall scripts for native binaries)
    if update_binary_exists vercel || [[ "$FORCE_MODE" == "true" ]]; then
        if [[ "$has_bun" == "true" ]]; then
            run_cmd_bun_with_retry "Vercel CLI" update_run_in_target_context "" "$bun_bin" install -g --trust vercel@latest
        else
            log_item "fail" "Vercel CLI" "bun not installed (required)"
        fi
    else
        log_item "skip" "Vercel CLI" "not installed"
    fi

    # GitHub CLI (gh) - update extensions
    local gh_bin=""
    gh_bin="$(update_binary_path gh 2>/dev/null || true)"
    if [[ -n "$gh_bin" ]]; then
        capture_version_before "gh"
        # Update gh extensions if any are installed
        local gh_extensions=0
        gh_extensions=$("$gh_bin" extension list 2>/dev/null | grep -v "no installed extensions found" | grep -c -v "No extensions installed" || true)
        gh_extensions=$((gh_extensions + 0))  # Strip whitespace, ensure integer
        if [[ $gh_extensions -gt 0 ]]; then
            run_cmd "GitHub CLI extensions" "$gh_bin" extension upgrade --all
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
    local gcloud_bin=""
    gcloud_bin="$(update_binary_path gcloud 2>/dev/null || true)"
    if [[ -n "$gcloud_bin" ]]; then
        if dpkg -s google-cloud-cli >/dev/null 2>&1; then
            # apt-managed installs disable `gcloud components update`;
            # the package is updated via apt-get instead.
            log_item "ok" "Google Cloud SDK" "apt-managed (update via apt-get upgrade)"
            log_to_file "gcloud is apt-managed; components update disabled by Google. Update with: sudo apt-get install -y --only-upgrade google-cloud-cli"
        else
            capture_version_before "gcloud"
            # gcloud components update requires --quiet for non-interactive
            run_cmd "Google Cloud SDK" "$gcloud_bin" components update --quiet
            if capture_version_after "gcloud"; then
                [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[gcloud]}" "${VERSION_AFTER[gcloud]}"
            fi
        fi
    else
        log_item "skip" "Google Cloud SDK" "not installed"
    fi
}

update_rust() {
    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        return 0
    fi

    log_section "Rust Toolchain"

    local rustup_bin=""
    rustup_bin="$(update_binary_path rustup 2>/dev/null || true)"

    if [[ -z "$rustup_bin" ]]; then
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
    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        return 0
    fi

    log_section "Cargo Tools"

    local cargo_bin=""
    cargo_bin="$(update_binary_path cargo 2>/dev/null || true)"
    if [[ -z "$cargo_bin" ]]; then
        log_item "skip" "Cargo tools" "cargo not found"
        return 0
    fi

    # Tools to update via cargo install
    # Format: package_name|binary_name
    local tools=("ast-grep|sg" "lsd|lsd" "du-dust|dust" "tealdeer|tldr")

    for entry in "${tools[@]}"; do
        local tool="${entry%|*}"
        local binary_name="${entry#*|}"

        if ! update_binary_exists "$binary_name"; then
            continue
        fi

        capture_version_before "$binary_name"
        
        # force is required to update existing install with cargo
        # Use run_cmd to log and handle errors
        run_cmd "Update $tool" update_run_in_target_context "" "$cargo_bin" install "$tool" --locked --force

        if capture_version_after "$binary_name"; then
             [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[$binary_name]}" "${VERSION_AFTER[$binary_name]}"
        fi
    done
}

update_uv() {
    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        return 0
    fi

    log_section "Python Tools (uv)"

    local uv_bin=""
    uv_bin="$(update_binary_path uv 2>/dev/null || true)"

    if [[ -z "$uv_bin" ]]; then
        log_item "skip" "uv" "not installed"
        return 0
    fi

    # Capture version before update
    capture_version_before "uv"

    if ! run_cmd_attempt_with_retry "uv self-update" "$uv_bin" self update; then
        if update_require_security; then
            run_cmd_with_retry_status "uv verified installer fallback" update_run_verified_installer uv || true
        else
            log_item "fail" "uv self-update" "failed and checksum-verified installer fallback is unavailable"
        fi
    fi

    # Show version change without double-counting
    if capture_version_after "uv"; then
        [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[uv]}" "${VERSION_AFTER[uv]}"
    fi
}

update_go() {
    if [[ "$UPDATE_RUNTIME" != "true" ]]; then
        return 0
    fi

    log_section "Go Runtime"

    # Check if go is installed
    local go_path=""
    go_path="$(update_binary_path go 2>/dev/null || true)"
    if [[ -z "$go_path" ]]; then
        log_item "skip" "Go" "not installed"
        return 0
    fi

    # Determine how Go was installed

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
    go_version=$("$go_path" version 2>/dev/null | awk '{print $3}' | sed 's/go//')
    log_item "ok" "Go $go_version" "no auto-update available"
    log_to_file "Go version: $go_version (path: $go_path)"
}

update_stack() {
    if [[ "$UPDATE_STACK" != "true" ]]; then
        return 0
    fi

    log_section "Dicklesworthstone Stack"

    if ! update_require_security; then
        log_item "fail" "stack updates" "security verification unavailable (missing security.sh/checksums.yaml)"
        return 0
    fi

    # Brenner Bot - skip all toolchain deps (NTM, CASS, CM) because ACFS
    # installs/updates them individually below.  Previously only --skip-cass
    # was passed, causing brenner's install_toolchain() to redundantly rebuild
    # NTM and CM from source — a 5+ hour hang on slow machines (fixes #210).
    capture_version_before "brenner"
    run_cmd "Brenner Bot" update_run_verified_installer brenner_bot --skip-ntm --skip-cass --skip-cm
    if capture_version_after "brenner"; then
        [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[brenner]}" "${VERSION_AFTER[brenner]}"
    fi

    # NTM - always install/update (installer is idempotent)
    capture_version_before "ntm"
    update_run_verified_installer_or_existing_on_transient "NTM" ntm ntm ntm || true
    if capture_version_after "ntm"; then
        [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[ntm]}" "${VERSION_AFTER[ntm]}"
    fi

    # MCP Agent Mail - always install/update via non-blocking installer mode,
    # then enable the managed user service on port 8765.
    local tool="mcp_agent_mail"
    local url="${KNOWN_INSTALLERS[$tool]:-}"
    local expected_sha256
    expected_sha256="$(get_checksum "$tool")"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_item "skip" "MCP Agent Mail" "dry-run: verified install + service refresh"
    elif [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
        local tmp_install
        tmp_install=$(mktemp "${TMPDIR:-/tmp}/acfs-install-am.XXXXXX" 2>/dev/null) || tmp_install=""
        if [[ -z "$tmp_install" ]]; then
            log_item "fail" "MCP Agent Mail" "failed to create temp file for verified installer"
        else
            if verify_checksum "$url" "$expected_sha256" "$tool" > "$tmp_install"; then
                chmod +x "$tmp_install"
                log_item "run" "MCP Agent Mail"

                # Use --dest and exact target dir just like the manifest
                local target_user=""
                local target_home=""
                target_user="$(update_target_user)"
                target_home="$(update_target_home "$target_user")"

                if update_run_logged_passthrough update_run_in_target_context "" bash "$tmp_install" --dest "$target_home/mcp_agent_mail" --yes; then
                    if update_source_stack_lib; then
                        ACFS_STACK_TRUST_TARGET_HOME=true TARGET_USER="$target_user" TARGET_HOME="$target_home" _stack_repair_agent_mail_cli_symlink >/dev/null 2>&1 || true
                    fi
                    if update_source_stack_lib && \
                       ACFS_STACK_TRUST_TARGET_HOME=true TARGET_USER="$target_user" TARGET_HOME="$target_home" _stack_configure_agent_mail_service && \
                       ACFS_STACK_TRUST_TARGET_HOME=true TARGET_USER="$target_user" TARGET_HOME="$target_home" _stack_wait_for_agent_mail_health; then
                        if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
                            printf "\033[1A\033[2K  ${GREEN}[ok]${NC} %s\n" "MCP Agent Mail"
                        elif [[ "$QUIET" != "true" ]]; then
                            printf "  ${GREEN}[ok]${NC} %s\n" "MCP Agent Mail"
                        fi
                        log_to_file "Success: MCP Agent Mail"
                        ((SUCCESS_COUNT += 1))
                    else
                        if [[ "$QUIET" != "true" ]] && [[ "$VERBOSE" != "true" ]]; then
                            printf "\033[1A\033[2K  ${RED}[FAIL]${NC} %s\n" "MCP Agent Mail"
                        elif [[ "$QUIET" != "true" ]]; then
                            printf "  ${RED}[FAIL]${NC} %s\n" "MCP Agent Mail"
                        fi
                        log_to_file "Failed: MCP Agent Mail - service setup/readiness failed"
                        ((FAIL_COUNT += 1))
                    fi
                else
                    log_item "fail" "MCP Agent Mail" "installer failed"
                fi

                rm -f "$tmp_install" 2>/dev/null || true
            else
                rm -f "$tmp_install"
                log_item "fail" "MCP Agent Mail" "verification failed"
            fi
        fi
    else
        log_item "fail" "MCP Agent Mail" "unknown installer URL/checksum"
    fi

    # Meta Skill (ms) - always install/update (installer is idempotent)
    update_run_verified_installer_or_existing_on_transient "Meta Skill" ms ms ms --easy-mode || true

    # APR (Automated Plan Reviser Pro) - always install/update
    run_cmd "APR" update_run_verified_installer apr --easy-mode

    # Process Triage (pt) - always install/update
    run_cmd "Process Triage" update_run_verified_installer pt

    # xf (X Archive Search) - always install/update
    run_cmd "xf" update_run_verified_installer xf --easy-mode

    # JeffreysPrompts (jfp) - only update if already installed
    # Note: JFP requires a paid subscription to jeffreysprompts.com
    if update_binary_exists jfp; then
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

    # SLB - always install/update (must build from source due to upstream installer bug)
    run_cmd "SLB" update_run_slb_source_install

    # RU (Repo Updater) - always install/update
    run_cmd "RU" update_run_verified_installer_with_env ru "RU_NON_INTERACTIVE=1"

    # DCG (Destructive Command Guard) - always install/update
    run_cmd "DCG" update_run_verified_installer dcg --easy-mode
    # Re-register hook after install/update to ensure latest version is active
    if update_binary_exists dcg && update_binary_exists claude; then
        local dcg_bin=""
        dcg_bin="$(update_binary_path dcg 2>/dev/null || true)"
        if [[ -n "$dcg_bin" ]]; then
            run_cmd "DCG Hook" "$dcg_bin" install --force 2>/dev/null || true
        fi
    fi

    # RCH (Remote Compilation Helper) - always install/update and keep daemon/fleet setup active
    run_cmd "RCH" update_run_verified_installer rch --easy-mode

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
    run_cmd "MDWB" update_run_verified_installer mdwb --yes

    # S2P (Source to Prompt TUI) - always install/update
    run_cmd "S2P" update_run_verified_installer s2p -- --skip-cass

    # FrankenSearch (fsfs) - prefer the small Linux release asset to avoid
    # upstream's missing-full-binary source-build fallback on Ubuntu.
    run_cmd "FrankenSearch" update_run_fsfs_installer --easy-mode

    # Storage Ballast Helper (sbh) - always install/update
    run_cmd "SBH" update_run_verified_installer sbh

    # Cross-Agent Session Resumer (casr) - always install/update
    run_cmd "CASR" update_run_verified_installer casr

    # ASCII Art Diagram Corrector (aadc) - update when installed, or install with --force
    if update_binary_exists aadc || [[ "$FORCE_MODE" == "true" ]]; then
        capture_version_before "aadc"
        run_cmd "AADC" update_run_cargo_git_source_install https://github.com/Dicklesworthstone/aadc.git aadc
        if capture_version_after "aadc"; then
            [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[aadc]}" "${VERSION_AFTER[aadc]}"
        else
            log_to_file "AADC already up to date: ${VERSION_AFTER[aadc]:-${VERSION_BEFORE[aadc]:-unknown}}"
        fi
    fi

    # Rust Proxy (rust_proxy) - update when installed, or install with --force
    if update_binary_exists rust_proxy || [[ "$FORCE_MODE" == "true" ]]; then
        capture_version_before "rust_proxy"
        run_cmd "Rust Proxy" update_run_cargo_git_source_install https://github.com/Dicklesworthstone/rust_proxy.git rust_proxy
        if capture_version_after "rust_proxy"; then
            [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[rust_proxy]}" "${VERSION_AFTER[rust_proxy]}"
        else
            log_to_file "Rust Proxy already up to date: ${VERSION_AFTER[rust_proxy]:-${VERSION_BEFORE[rust_proxy]:-unknown}}"
        fi
    fi

    # Agent Settings Backup (asb) - update when installed, or install with --force
    if update_binary_exists asb || [[ "$FORCE_MODE" == "true" ]]; then
        capture_version_before "asb"
        run_cmd "ASB" update_run_verified_installer asb
        if capture_version_after "asb"; then
            [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[asb]}" "${VERSION_AFTER[asb]}"
        else
            log_to_file "ASB already up to date: ${VERSION_AFTER[asb]:-${VERSION_BEFORE[asb]:-unknown}}"
        fi
    fi

    # Post-Compact Reminder (pcr) - only update when Claude Code is installed
    local pcr_hook_script=""
    pcr_hook_script="$(update_runtime_primary_bin_dir 2>/dev/null || true)"
    [[ -n "$pcr_hook_script" ]] && pcr_hook_script="$pcr_hook_script/claude-post-compact-reminder"
    if ! update_binary_exists claude; then
        log_item "skip" "PCR" "Claude Code not installed"
    elif [[ -z "$pcr_hook_script" ]]; then
        log_item "fail" "PCR" "unable to resolve target hook path"
    elif [[ -e "$pcr_hook_script" || "$FORCE_MODE" == "true" ]]; then
        local pcr_mtime_before=""
        local pcr_mtime_after=""
        pcr_mtime_before="$(get_file_mtime "$pcr_hook_script" 2>/dev/null || true)"
        if [[ -n "$pcr_mtime_before" ]]; then
            log_to_file "PCR hook mtime before: $pcr_mtime_before ($pcr_hook_script)"
        else
            log_to_file "PCR hook mtime before: missing ($pcr_hook_script)"
        fi

        run_cmd "PCR" update_run_pcr_installer_and_verify "$pcr_hook_script"

        pcr_mtime_after="$(get_file_mtime "$pcr_hook_script" 2>/dev/null || true)"
        if [[ -n "$pcr_mtime_after" ]]; then
            log_to_file "PCR hook mtime after: $pcr_mtime_after ($pcr_hook_script)"
        else
            log_to_file "PCR hook mtime after: missing ($pcr_hook_script)"
        fi

        if [[ -n "$pcr_mtime_before" && -n "$pcr_mtime_after" && "$pcr_mtime_before" != "$pcr_mtime_after" ]]; then
            [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "$pcr_mtime_before" "$pcr_mtime_after"
        elif [[ -n "$pcr_mtime_after" ]]; then
            log_to_file "PCR hook already up to date: mtime unchanged ($pcr_mtime_after)"
        fi
    else
        log_item "skip" "PCR" "not installed (use --force to install)"
    fi

    # DSR (Doodlestein Self-Releaser) - always install/update
    run_cmd "DSR" update_run_verified_installer dsr --easy-mode
}

# ============================================================
# Root AGENTS.md Generation
# ============================================================
update_root_agents_md() {
    log_section "Root AGENTS.md"

    local root_agents_generator=""
    root_agents_generator="$(update_binary_path flywheel-update-agents-md 2>/dev/null || true)"

    if [[ -z "$root_agents_generator" ]]; then
        local generator=""
        local candidate=""
        local primary_bin=""
        local runtime_acfs_home=""
        primary_bin="$(update_runtime_primary_bin_dir 2>/dev/null || true)"
        runtime_acfs_home="$(update_runtime_acfs_home 2>/dev/null || true)"
        local -a security_candidates=()
        [[ -n "$primary_bin" ]] && security_candidates+=("$primary_bin/flywheel-update-agents-md")
        [[ -n "$runtime_acfs_home" ]] && security_candidates+=("$runtime_acfs_home/bin/flywheel-update-agents-md")
        if [[ -n "${ACFS_REPO_ROOT:-}" ]]; then
            security_candidates+=("${ACFS_REPO_ROOT}/scripts/generate-root-agents-md.sh")
        fi

        for candidate in "${security_candidates[@]}"; do
            if [[ -n "$candidate" ]] && [[ -f "$candidate" ]]; then
                generator="$candidate"
                break
            fi
        done

        if [[ -f "$generator" ]]; then
            if ! run_cmd_sudo "Install flywheel-update-agents-md" ln -sf "$generator" /usr/local/bin/flywheel-update-agents-md; then
                log_item "skip" "Root AGENTS.md" "flywheel-update-agents-md not installed"
                return 0
            fi
        else
            log_item "skip" "Root AGENTS.md" "flywheel-update-agents-md not installed"
            return 0
        fi
    fi

    root_agents_generator="$(update_binary_path flywheel-update-agents-md 2>/dev/null || true)"
    [[ -n "$root_agents_generator" ]] || root_agents_generator="flywheel-update-agents-md"
    run_cmd_sudo "Root AGENTS.md" "$root_agents_generator"
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
        if ! echo "$output" | grep -q "Already up to date"; then
            if capture_version_after "p10k"; then
                log_item "ok" "Powerlevel10k updated" "${VERSION_BEFORE[p10k]} → ${VERSION_AFTER[p10k]}"
            else
                log_item "ok" "Powerlevel10k updated" "(version unchanged)"
            fi
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
    local atuin_bin=""
    atuin_bin="$(update_tool_binary_path "atuin" 2>/dev/null || true)"
    if [[ -z "$atuin_bin" ]]; then
        log_item "skip" "Atuin" "not installed"
        return 0
    fi

    capture_version_before "atuin"
    local needs_reinstall=false

    # Try atuin self-update first (available in newer versions)
    if "$atuin_bin" --help 2>&1 | grep -q "self-update"; then
        if run_cmd_attempt_with_retry "Atuin self-update" "$atuin_bin" self-update; then
            update_repair_atuin_install >/dev/null 2>&1 || true
            # If self-update succeeded, check whether version is now current;
            # skip the heavier reinstall path to avoid a stalling curl download.
            local ver_after
            ver_after=$(get_version "atuin")
            if [[ -n "$ver_after" && "$ver_after" != "unknown" ]]; then
                log_to_file "Atuin self-update succeeded (version: $ver_after), skipping reinstall"
            else
                # self-update ran but we can't determine version — fall through
                log_to_file "Atuin self-update ran but version check inconclusive, trying reinstall"
                needs_reinstall=true
            fi
        else
            log_to_file "Atuin self-update failed, trying reinstall"
            needs_reinstall=true
        fi
    else
        needs_reinstall=true
    fi

    if [[ "$needs_reinstall" == "true" ]]; then
        if update_require_security; then
            if ! update_run_verified_installer_with_shell_repair "Atuin (reinstall)" "atuin" update_repair_atuin_install --non-interactive; then
                :
            fi
        else
            # Last resort: no checksum verification available
            if [[ "$YES_MODE" == "true" ]]; then
                log_item "skip" "Atuin" "checksum verification unavailable (missing security.sh/checksums.yaml)"
            else
                log_item "skip" "Atuin" "no self-update command, manual update recommended"
                local curl_cmd="curl --connect-timeout 30 --max-time 300 -fsSL"
                if command -v curl &>/dev/null && curl --help all 2>/dev/null | grep -q -- '--proto'; then
                    curl_cmd="curl --proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 300 -fsSL"
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
    local zoxide_bin=""
    zoxide_bin="$(update_tool_binary_path "zoxide" 2>/dev/null || true)"
    if [[ -z "$zoxide_bin" ]]; then
        log_item "skip" "Zoxide" "not installed"
        return 0
    fi

    capture_version_before "zoxide"

    # Zoxide doesn't have self-update, reinstall via official installer
    if update_require_security; then
        if ! update_run_verified_installer_with_shell_repair "Zoxide (reinstall)" "zoxide" update_repair_zoxide_install; then
            :
        fi
    else
        # Last resort: no checksum verification available
        if [[ "$YES_MODE" == "true" ]]; then
            log_item "skip" "Zoxide" "checksum verification unavailable (missing security.sh/checksums.yaml)"
        else
            log_item "skip" "Zoxide" "no self-update command, manual update recommended"
            local curl_cmd="curl --connect-timeout 30 --max-time 300 -fsSL"
            if command -v curl &>/dev/null && curl --help all 2>/dev/null | grep -q -- '--proto'; then
                curl_cmd="curl --proto '=https' --proto-redir '=https' --connect-timeout 30 --max-time 300 -fsSL"
            fi
            log_to_file "Zoxide update (manual; review first):"
            log_to_file "  ${curl_cmd} https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh -o /tmp/zoxide.install.sh"
            log_to_file "  sed -n '1,120p' /tmp/zoxide.install.sh"
            log_to_file "  bash /tmp/zoxide.install.sh"
        fi
        return 0
    fi

    # Show version change without double-counting
    if capture_version_after "zoxide"; then
        [[ "$QUIET" != "true" ]] && printf "       ${DIM}%s → %s${NC}\n" "${VERSION_BEFORE[zoxide]}" "${VERSION_AFTER[zoxide]}"
    fi
}

# Main shell update dispatcher
update_shell() {
    if [[ "$UPDATE_SHELL" != "true" ]]; then
        return 0
    fi

    log_section "Shell Tools"

    # Git-based updates (OMZ, P10K, plugins)
    update_omz
    update_p10k
    update_zsh_plugins

    # Installer-based updates (Atuin, Zoxide)
    update_atuin
    update_zoxide

    # Keep deployed files in sync with repo (acfs.zshrc, update.sh, etc.)
    sync_acfs_profile_paths
    sync_acfs_zprofile_paths
    sync_acfs_zsh_loader
    sync_acfs_zshrc
    sync_acfs_deployed
    sync_acfs_global_wrapper
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
  --stack-only       Only update Dicklesworthstone stack tools
  --stack            Include Dicklesworthstone stack tools (enabled by default)

SKIP OPTIONS (exclude categories from update):
  --no-self-update   Skip ACFS self-update
  --no-apt           Skip apt update/upgrade
  --no-agents        Skip coding agent updates
  --no-cloud         Skip cloud CLI updates
  --no-shell         Skip shell tool updates
  --no-runtime       Skip runtime updates (Bun, Rust, uv, Go)
  --no-stack         Skip Dicklesworthstone stack tool updates

BEHAVIOR OPTIONS:
  --bootstrap-self-update
                     Convert a non-git ACFS install into a git checkout before self-update
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

  # Only update Dicklesworthstone stack tools
  acfs-update --stack-only

  # Update everything except apt (faster)
  acfs-update --no-apt

  # Preview what would be updated
  acfs-update --dry-run

  # Automated CI/cron mode
  acfs-update --yes --quiet

  # Explicitly convert a tarball install into a git checkout for self-updates
  acfs-update --bootstrap-self-update

  # Strict mode: stop on first error
  acfs-update --abort-on-failure

WHAT EACH CATEGORY UPDATES:
  self:     ACFS itself (git pull) - runs FIRST to ensure latest update logic
            If update.sh changes, automatically re-executes with new version
            Tarball/non-git installs skip this unless --bootstrap-self-update is used
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
            --stack-only)
                UPDATE_APT=false
                UPDATE_AGENTS=false
                UPDATE_CLOUD=false
                UPDATE_RUNTIME=false
                UPDATE_STACK=true
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
            --bootstrap-self-update)
                BOOTSTRAP_SELF_UPDATE=true
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
            echo -n "Continue anyway? [y/N] "
            read -r response < /dev/tty || true
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
        echo -e "${BOLD}ACFS Update $ACFS_VERSION_DISPLAY${NC}"
        echo -e "User: $(update_current_user 2>/dev/null || true)"
        echo -e "Date: $(date '+%Y-%m-%d %H:%M')"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo -e "${YELLOW}Mode: dry-run${NC}"
        fi
    fi

    # Set non-interactive mode if --yes was passed
    if [[ "$YES_MODE" == "true" ]]; then
        export ACFS_INTERACTIVE=false
    fi

    # Ensure jq is available (issue #180): on minimal Ubuntu installs jq may
    # not be present, but later update steps (DCG cleanup, state management)
    # depend on it. Keep dry-run truly read-only by skipping the install there.
    update_ensure_jq_available

    # Clean up legacy artifacts from previous versions
    cleanup_legacy_git_safety_guard
    cleanup_legacy_br_alias
    cleanup_legacy_bv_alias

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
