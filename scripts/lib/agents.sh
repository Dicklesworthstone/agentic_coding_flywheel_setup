#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Coding Agents Library
# Installs Claude Code, Codex CLI, and Gemini CLI
# ============================================================

AGENTS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$AGENTS_SCRIPT_DIR/logging.sh"
fi

# ============================================================
# Configuration
# ============================================================

# NPM package names for each agent
CLAUDE_PACKAGE="@anthropic-ai/claude-code@latest"
CODEX_PACKAGE="${CODEX_PACKAGE:-@openai/codex@latest}"
CODEX_FALLBACK_VERSION="${CODEX_FALLBACK_VERSION:-0.87.0}"
CODEX_FALLBACK_PACKAGE=""
if [[ -n "$CODEX_FALLBACK_VERSION" ]]; then
    CODEX_FALLBACK_PACKAGE="@openai/codex@${CODEX_FALLBACK_VERSION}"
fi
GEMINI_PACKAGE="@google/gemini-cli@latest"

# Binary names after installation
CLAUDE_BIN="claude"
CODEX_BIN="codex"
GEMINI_BIN="gemini"

# ============================================================
# Helper Functions
# ============================================================

# Check if a command exists
_agent_command_exists() {
    command -v "$1" &>/dev/null
}

_agent_normalize_config_value() {
    local value="${1-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ ${#value} -ge 2 ]]; then
        local first_char="${value:0:1}"
        local last_char="${value: -1}"
        if [[ ( "$first_char" == '"' && "$last_char" == '"' ) || ( "$first_char" == "'" && "$last_char" == "'" ) ]]; then
            value="${value:1:${#value}-2}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
        fi
    fi

    printf '%s\n' "$value"
}

_agent_is_placeholder_secret() {
    local normalized=""
    normalized="$(_agent_normalize_config_value "${1-}")"
    normalized="${normalized,,}"

    case "$normalized" in
        your-token-here|your_token_here|your-token|your_token|your_api_key|your-api-key|your_github_token|your_openai_api_key|your_claude_token|your_vercel_token|your_supabase_access_token|your_cloudflare_api_token|your_gemini_api_key|your_google_api_key|your_project_id|your_project_location|replace-me|change-me|changeme|"<token>"|"<api-key>"|"<secret>")
            return 0
            ;;
    esac

    return 1
}

_agent_has_usable_secret() {
    local normalized=""
    normalized="$(_agent_normalize_config_value "${1-}")"
    [[ -n "${normalized//[[:space:]]/}" ]] && ! _agent_is_placeholder_secret "$normalized"
}

_agent_json_file_has_usable_jq_value() {
    local file_path="${1:-}"
    local jq_expr="${2:-}"
    local candidate=""

    [[ -s "$file_path" ]] || return 1
    [[ -n "$jq_expr" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    while IFS= read -r candidate; do
        if _agent_has_usable_secret "$candidate"; then
            return 0
        fi
    done < <(jq -r "$jq_expr" "$file_path" 2>/dev/null || true)

    return 1
}

_agent_json_file_has_usable_string_key() {
    local file_path="${1:-}"
    shift || true

    [[ -s "$file_path" ]] || return 1

    local key=""
    local regex=""
    local line=""
    for key in "$@"; do
        [[ -n "$key" ]] || continue
        regex="\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\""
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ $regex ]] && _agent_has_usable_secret "${BASH_REMATCH[1]}"; then
                return 0
            fi
        done < "$file_path"
    done

    return 1
}

# Get the sudo command if needed
_agent_get_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo ""
    else
        echo "sudo"
    fi
}

_agent_existing_abs_home() {
    local home_candidate="${1:-}"

    [[ -n "$home_candidate" ]] || return 1
    home_candidate="${home_candidate%/}"
    [[ -n "$home_candidate" ]] || return 1
    [[ "$home_candidate" == /* ]] || return 1
    [[ "$home_candidate" != "/" ]] || return 1
    [[ -d "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

_agent_system_binary_path() {
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

_agent_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(_agent_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(_agent_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

_agent_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(_agent_system_binary_path getent 2>/dev/null || true)"
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

_agent_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(_agent_existing_abs_home "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}

_agent_target_home() {
    local target_user="${1:-${TARGET_USER:-ubuntu}}"
    local explicit_home=""
    local passwd_entry=""
    local current_user=""
    local current_home=""

    explicit_home="$(_agent_existing_abs_home "${TARGET_HOME:-}" 2>/dev/null || true)"
    current_user="$(_agent_resolve_current_user 2>/dev/null || true)"
    if [[ "$target_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi
    if [[ -n "$explicit_home" && -z "${TARGET_USER:-}" && "$target_user" == "$current_user" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    passwd_entry="$(_agent_getent_passwd_entry "$target_user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        passwd_entry="$(_agent_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            printf '%s\n' "${passwd_entry%/}"
            return 0
        fi
    fi

    if [[ "$current_user" == "$target_user" ]]; then
        current_home="$(_agent_existing_abs_home "${HOME:-}" 2>/dev/null || true)"
        if [[ -n "$current_home" ]] && { [[ -z "$explicit_home" ]] || [[ "$current_home" == "$explicit_home" ]]; }; then
            printf '%s\n' "$current_home"
            return 0
        fi
    fi

    if [[ -n "$explicit_home" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    return 1
}

_agent_validate_target_user() {
    local username="${1:-${TARGET_USER:-}}"
    local display="${username:-<empty>}"

    if [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        return 0
    fi

    log_error "Invalid TARGET_USER '$display' (expected: lowercase user name like 'ubuntu')"
    return 1
}

_agent_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="${bin_dir%/}"
    [[ -n "$bin_dir" ]] || return 1
    [[ "$bin_dir" == /* ]] || return 1
    [[ "$bin_dir" != "/" ]] || return 1
    base_home="$(_agent_existing_abs_home "$base_home" 2>/dev/null || true)"

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
        passwd_home="$(_agent_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(_agent_getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

_agent_preferred_bin_dir() {
    local target_home="${1:-}"
    local candidate=""

    [[ -n "$target_home" ]] || return 1

    candidate="$(_agent_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$target_home" 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    printf '%s\n' "$target_home/.local/bin"
}

# Run a command as target user
_agent_run_as_user() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    local target_path_prefix=""
    local preferred_bin_dir=""
    local cmd="$1"
    local target_user_q=""
    local target_home_q=""
    local target_path_prefix_q=""
    local acfs_home_q=""
    local acfs_bin_dir_q=""
    local wrapped_cmd=""
    local bash_bin=""
    local sudo_bin=""
    local runuser_bin=""
    local su_bin=""

    _agent_validate_target_user "$target_user" || return 1
    bash_bin="$(_agent_system_binary_path bash 2>/dev/null || true)"
    [[ -n "$bash_bin" ]] || {
        log_error "Unable to locate bash for target-user agent command"
        return 1
    }

    target_home="$(_agent_target_home "$target_user" 2>/dev/null || true)"
    if [[ -z "$target_home" ]] || [[ "$target_home" == "/" ]] || [[ "$target_home" != /* ]]; then
        log_error "Invalid TARGET_HOME for '$target_user': ${target_home:-<empty>} (must be an absolute path and cannot be '/')"
        return 1
    fi

    if [[ -n "${ACFS_BIN_DIR:-}" ]] && { [[ "${ACFS_BIN_DIR}" == "/" ]] || [[ "${ACFS_BIN_DIR}" != /* ]]; }; then
        log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${ACFS_BIN_DIR:-<empty>})"
        return 1
    fi

    preferred_bin_dir="$(_agent_preferred_bin_dir "$target_home" 2>/dev/null || true)"
    [[ -n "$preferred_bin_dir" ]] || preferred_bin_dir="$target_home/.local/bin"
    target_path_prefix="$preferred_bin_dir:$target_home/.local/bin:$target_home/.acfs/bin:$target_home/.cargo/bin:$target_home/.bun/bin:$target_home/.atuin/bin:$target_home/go/bin"

    printf -v target_user_q '%q' "$target_user"
    printf -v target_home_q '%q' "$target_home"
    printf -v target_path_prefix_q '%q' "$target_path_prefix"
    if [[ -n "${ACFS_HOME:-}" ]]; then
        printf -v acfs_home_q '%q' "$ACFS_HOME"
    fi
    if [[ -n "$preferred_bin_dir" ]]; then
        printf -v acfs_bin_dir_q '%q' "$preferred_bin_dir"
    fi

    wrapped_cmd="export TARGET_USER=$target_user_q TARGET_HOME=$target_home_q HOME=$target_home_q;"
    if [[ -n "$acfs_home_q" ]]; then
        wrapped_cmd+=" export ACFS_HOME=$acfs_home_q;"
    fi
    if [[ -n "$acfs_bin_dir_q" ]]; then
        wrapped_cmd+=" export ACFS_BIN_DIR=$acfs_bin_dir_q;"
    fi
    wrapped_cmd+=" export PATH=$target_path_prefix_q:\$PATH; set -o pipefail; $cmd"

    if [[ "$(_agent_resolve_current_user 2>/dev/null || true)" == "$target_user" ]]; then
        "$bash_bin" -c "$wrapped_cmd"
        return $?
    fi

    sudo_bin="$(_agent_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -u "$target_user" -H "$bash_bin" -c "$wrapped_cmd"
        return $?
    fi

    runuser_bin="$(_agent_system_binary_path runuser 2>/dev/null || true)"
    if [[ -n "$runuser_bin" ]]; then
        "$runuser_bin" -u "$target_user" -- "$bash_bin" -c "$wrapped_cmd"
        return $?
    fi

    su_bin="$(_agent_system_binary_path su 2>/dev/null || true)"
    [[ -n "$su_bin" ]] || {
        log_error "Unable to locate sudo, runuser, or su for target-user agent command"
        return 1
    }

    # Avoid login shells: profile files are not a stable API and can break non-interactive runs.
    "$su_bin" "$target_user" -c "$(printf '%q' "$bash_bin") -c $(printf %q "$wrapped_cmd")"
}

# Get bun binary path for target user
_agent_get_bun_bin() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_agent_target_home "$target_user")"
    echo "$target_home/.bun/bin/bun"
}

# Check if bun is available
_agent_check_bun() {
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)

    if [[ ! -x "$bun_bin" ]]; then
        log_warn "Bun not found at $bun_bin"
        log_warn "Install bun first: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only-phase 5"
        return 1
    fi
    return 0
}

_agent_find_am_bin() {
    local target_home="${1:-}"
    local primary_bin=""
    local candidate=""

    if [[ -z "$target_home" ]]; then
        target_home="$(_agent_target_home "${TARGET_USER:-ubuntu}" 2>/dev/null || true)"
    fi
    [[ -n "$target_home" ]] || return 1

    primary_bin="$(_agent_preferred_bin_dir "$target_home" 2>/dev/null || true)"
    [[ -n "$primary_bin" ]] || primary_bin="$target_home/.local/bin"
    for candidate in \
        "$target_home/mcp_agent_mail/am" \
        "$primary_bin/am" \
        "$target_home/.local/bin/am" \
        "$target_home/.acfs/bin/am" \
        "$target_home/.cargo/bin/am" \
        "$target_home/.bun/bin/am" \
        "$target_home/.atuin/bin/am" \
        "$target_home/go/bin/am"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done


    return 1
}

_agent_detect_am_mcp_path() {
    local target_home="${1:-}"
    local am_bin=""

    am_bin="$(_agent_find_am_bin "$target_home" 2>/dev/null || true)"
    if [[ -n "$am_bin" ]] && "$am_bin" --version 2>/dev/null | grep -q '^am '; then
        printf '/mcp/\n'
        return 0
    fi

    if [[ -n "$am_bin" ]]; then
        printf '/api/\n'
        return 0
    fi

    printf '/mcp/\n'
}

# Create a wrapper script that uses bun as the runtime instead of node.
# This avoids the "node not found" error when nvm hasn't added node to PATH yet.
# The wrapper is placed in ~/.local/bin which is early in PATH.
_agent_create_bun_wrapper() {
    local target_home="$1"
    local tool_name="$2"
    local wrapper_path="$target_home/.local/bin/$tool_name"
    local bun_tool_path="$target_home/.bun/bin/$tool_name"

    # Skip if wrapper already exists
    [[ -x "$wrapper_path" ]] && return 0

    # Skip if bun tool doesn't exist
    [[ -x "$bun_tool_path" ]] || return 0

    log_detail "Creating $tool_name bun wrapper at $wrapper_path"
    local local_bin_q=""
    local wrapper_path_q=""
    local wrapper_exec_line=""
    local wrapper_exec_line_q=""
    printf -v local_bin_q '%q' "$target_home/.local/bin"
    printf -v wrapper_path_q '%q' "$wrapper_path"
    wrapper_exec_line="exec ~/.bun/bin/bun ~/.bun/bin/$tool_name \"\$@\""
    printf -v wrapper_exec_line_q '%q' "$wrapper_exec_line"

    _agent_run_as_user "mkdir -p $local_bin_q" || return 1
    # Use printf to avoid heredoc quoting issues with variable expansion
    _agent_run_as_user "printf '%s\\n' '#!/bin/bash' $wrapper_exec_line_q > $wrapper_path_q" || return 1
    _agent_run_as_user "chmod +x $wrapper_path_q" || return 1
    return 0
}

_agent_has_nvm_node() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_agent_target_home "$target_user")"
    compgen -G "$target_home/.nvm/versions/node/*/bin/node" >/dev/null 2>&1
}

_agent_latest_nvm_node_bin() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_agent_target_home "$target_user")"
    local node_path=""

    while IFS= read -r node_path; do
        if [[ -x "$node_path" ]]; then
            printf '%s\n' "${node_path%/node}"
            return 0
        fi
    done < <(compgen -G "$target_home/.nvm/versions/node/*/bin/node" | sort -Vr)

    return 1
}

_agent_ensure_nvm_node() {
    local patch_tool="nvm"
    local installer_url=""
    local installer_sha=""

    if _agent_has_nvm_node; then
        return 0
    fi

    if [[ ! -f "$AGENTS_SCRIPT_DIR/security.sh" ]]; then
        log_warn "security.sh unavailable; cannot prepare Node.js for Gemini patch"
        return 1
    fi

    # shellcheck source=security.sh
    source "$AGENTS_SCRIPT_DIR/security.sh"
    if ! load_checksums; then
        log_warn "Checksum metadata unavailable; cannot prepare Node.js for Gemini patch"
        return 1
    fi

    installer_url="${KNOWN_INSTALLERS[$patch_tool]:-}"
    installer_sha="$(get_checksum "$patch_tool")"
    if [[ -z "$installer_url" || -z "$installer_sha" ]]; then
        log_warn "nvm installer metadata unavailable; cannot prepare Node.js for Gemini patch"
        return 1
    fi

    log_detail "Installing nvm + latest Node.js for Gemini patch compatibility..."
    local security_lib_q=""
    local installer_url_q=""
    local installer_sha_q=""
    local patch_tool_q=""
    printf -v security_lib_q '%q' "$AGENTS_SCRIPT_DIR/security.sh"
    printf -v installer_url_q '%q' "$installer_url"
    printf -v installer_sha_q '%q' "$installer_sha"
    printf -v patch_tool_q '%q' "$patch_tool"
    if ! _agent_run_as_user "source $security_lib_q; verify_checksum $installer_url_q $installer_sha_q $patch_tool_q | bash -s --"; then
        log_warn "nvm installer verification failed; cannot prepare Node.js for Gemini patch"
        return 1
    fi

    if ! _agent_run_as_user 'set -euo pipefail
        export NVM_DIR="$HOME/.nvm"
        if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
            echo "nvm.sh not found at $NVM_DIR/nvm.sh" >&2
            exit 1
        fi
        . "$NVM_DIR/nvm.sh"
        nvm install node
        nvm alias default node'; then
        log_warn "Failed to install latest Node.js via nvm for Gemini patch"
        return 1
    fi

    _agent_has_nvm_node
}

_agent_apply_verified_gemini_patch() {
    local patch_tool="gemini_patch"
    local patch_url="https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/fix-gemini-cli-ebadf-crash.sh"
    local patch_sha=""
    local node_bin_dir=""

    if [[ -f "$AGENTS_SCRIPT_DIR/security.sh" ]]; then
        # shellcheck source=security.sh
        source "$AGENTS_SCRIPT_DIR/security.sh"
        if load_checksums; then
            patch_url="${KNOWN_INSTALLERS[$patch_tool]:-$patch_url}"
            patch_sha="$(get_checksum "$patch_tool")"
        fi
    fi

    if [[ -z "$patch_sha" ]]; then
        log_warn "Gemini patch checksum unavailable; skipping patch for safety"
        return 1
    fi

    if ! _agent_ensure_nvm_node; then
        log_warn "Node.js via nvm unavailable; skipping Gemini patch"
        return 1
    fi

    if ! node_bin_dir="$(_agent_latest_nvm_node_bin)"; then
        log_warn "nvm Node.js bin not found; skipping Gemini patch"
        return 1
    fi

    local node_bin_dir_q=""
    local security_lib_q=""
    local patch_url_q=""
    local patch_sha_q=""
    local patch_tool_q=""
    printf -v node_bin_dir_q '%q' "$node_bin_dir"
    printf -v security_lib_q '%q' "$AGENTS_SCRIPT_DIR/security.sh"
    printf -v patch_url_q '%q' "$patch_url"
    printf -v patch_sha_q '%q' "$patch_sha"
    printf -v patch_tool_q '%q' "$patch_tool"
    if _agent_run_as_user "export PATH=$node_bin_dir_q:\"\$PATH\"; source $security_lib_q; verify_checksum $patch_url_q $patch_sha_q $patch_tool_q | bash -s --"; then
        return 0
    fi

    log_warn "Gemini patch verification failed; skipping patch"
    return 1
}

# ============================================================
# Claude Code Installation
# ============================================================

# Install Claude Code CLI (Native)
# Official installer from https://claude.ai/install.sh
install_claude_code() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_agent_target_home "$target_user")"
    local claude_bin="$target_home/.local/bin/claude"

    # Check if already installed
    if [[ -x "$claude_bin" ]]; then
        log_detail "Claude Code already installed at $claude_bin"
        return 0
    fi

    log_detail "Installing Claude Code (native) for $target_user..."

    # Try to use security.sh for verification
    if [[ -f "$AGENTS_SCRIPT_DIR/security.sh" ]]; then
        # shellcheck source=security.sh
        source "$AGENTS_SCRIPT_DIR/security.sh"
        if load_checksums; then
            local url="${KNOWN_INSTALLERS[claude]}"
            local sha="${LOADED_CHECKSUMS[claude]}"
            if [[ -n "$url" && -n "$sha" ]]; then
                local security_lib_q=""
                local url_q=""
                local sha_q=""
                printf -v security_lib_q '%q' "$AGENTS_SCRIPT_DIR/security.sh"
                printf -v url_q '%q' "$url"
                printf -v sha_q '%q' "$sha"
                if _agent_run_as_user "source $security_lib_q; verify_checksum $url_q $sha_q claude | bash -s -- latest"; then
                    log_success "Claude Code installed (verified)"
                    return 0
                fi
            fi
        fi
    fi

    # Fail closed: never execute unverified remote installer scripts.
    log_error "Security verification unavailable or failed for Claude Code"
    log_error "Refusing to execute unverified installer script"
    return 1
}

# Upgrade Claude Code to latest version
upgrade_claude_code() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_agent_target_home "$target_user")"
    local claude_bin="$target_home/.local/bin/claude"

    if [[ -x "$claude_bin" ]]; then
        log_detail "Upgrading Claude Code (native)..."
        if _agent_run_as_user "\"$claude_bin\" update --channel latest"; then
            log_success "Claude Code upgraded"
            return 0
        fi

        log_warn "Claude Code native update failed, attempting reinstall..."
        install_claude_code
        return $?
    fi

    # Legacy fallback: bun-installed Claude Code
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)
    if _agent_check_bun; then
        log_detail "Upgrading Claude Code (bun)..."
        _agent_run_as_user "\"$bun_bin\" install -g --trust $CLAUDE_PACKAGE" && log_success "Claude Code upgraded"
        return 0
    fi

    log_warn "Claude Code not installed"
    return 1
}

# ============================================================
# Codex CLI Installation (OpenAI)
# ============================================================

# Install Codex CLI via bun
# The official package is @openai/codex
install_codex_cli() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_agent_target_home "$target_user")"
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)
    local codex_bin="$target_home/.bun/bin/$CODEX_BIN"
    local codex_wrapper="$target_home/.local/bin/codex"

    # Check if already installed (wrapper takes precedence)
    if [[ -x "$codex_wrapper" ]]; then
        log_detail "Codex CLI already installed at $codex_wrapper"
        return 0
    fi
    if [[ -x "$codex_bin" ]]; then
        log_detail "Codex CLI already installed at $codex_bin"
        # Create wrapper if missing (fixes node PATH issues)
        _agent_create_bun_wrapper "$target_home" "codex"
        return 0
    fi

    # Verify bun is available
    if ! _agent_check_bun; then
        return 1
    fi

    log_detail "Installing Codex CLI for $target_user..."

    # Install via bun global (fallback to a pinned version if latest is broken)
    _agent_run_as_user "\"$bun_bin\" install -g --trust $CODEX_PACKAGE" || true
    if [[ ! -x "$codex_bin" ]] && [[ -n "$CODEX_FALLBACK_PACKAGE" ]]; then
        log_warn "Codex CLI latest install failed; retrying pinned fallback $CODEX_FALLBACK_VERSION"
        _agent_run_as_user "\"$bun_bin\" install -g --trust $CODEX_FALLBACK_PACKAGE" || true
    fi

    if [[ -x "$codex_bin" ]]; then
        # Create wrapper script that uses bun as runtime (avoids node PATH issues)
        _agent_create_bun_wrapper "$target_home" "codex"
        log_success "Codex CLI installed"
        log_detail "Note: Run 'codex login --device-auth' to authenticate with your ChatGPT Pro account"
        return 0
    fi

    log_warn "Codex CLI installation may have failed"
    return 1
}

# Upgrade Codex CLI to latest version
upgrade_codex_cli() {
    local target_user="${TARGET_USER:-ubuntu}"
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)

    if ! _agent_check_bun; then
        return 1
    fi

    log_detail "Upgrading Codex CLI..."
    if _agent_run_as_user "\"$bun_bin\" install -g --trust $CODEX_PACKAGE"; then
        log_success "Codex CLI upgraded"
        return 0
    fi

    if [[ -n "$CODEX_FALLBACK_PACKAGE" ]]; then
        log_warn "Codex CLI latest upgrade failed; retrying pinned fallback $CODEX_FALLBACK_VERSION"
        if _agent_run_as_user "\"$bun_bin\" install -g --trust $CODEX_FALLBACK_PACKAGE"; then
            log_success "Codex CLI upgraded (fallback)"
            return 0
        fi
    fi

    log_warn "Codex CLI upgrade failed"
    return 1
}

# ============================================================
# Gemini CLI Installation (Google)
# ============================================================

# Configure Gemini CLI settings for tmux/agent compatibility and OAuth authentication
# Sets enableInteractiveShell: false to avoid node-pty issues in tmux panes
# Sets selectedType: "oauth-personal" for browser-based OAuth (not API key)
_configure_gemini_settings() {
    local target_home="$1"
    local settings_dir="$target_home/.gemini"
    local settings_file="$settings_dir/settings.json"

    # Detect MCP base path: Rust am uses /mcp/, Python mcp_agent_mail uses /api/
    local am_mcp_path="/mcp/"
    am_mcp_path="$(_agent_detect_am_mcp_path "$target_home")"
    local am_mcp_url="http://127.0.0.1:8765${am_mcp_path}"
    local settings_dir_q=""
    local settings_file_q=""
    local am_mcp_url_q=""
    printf -v settings_dir_q '%q' "$settings_dir"
    printf -v settings_file_q '%q' "$settings_file"
    printf -v am_mcp_url_q '%q' "$am_mcp_url"

    # Create settings directory if needed
    _agent_run_as_user "mkdir -p $settings_dir_q" || return 1

    # If settings file doesn't exist, create it with tmux-compatible defaults, OAuth auth,
    # and MCP Agent Mail server configuration (fixes #158)
    if [[ ! -f "$settings_file" ]]; then
        log_detail "Creating Gemini settings for tmux compatibility, OAuth auth, and MCP Agent Mail..."
        # Write default settings - the JSON is simple enough to inline
        # Note: Using double quotes for variable expansion, escaping inner quotes
        _agent_run_as_user "cat > $settings_file_q << 'GEMINI_EOF'
{
  \"selectedType\": \"oauth-personal\",
  \"tools\": {
    \"shell\": {
      \"enableInteractiveShell\": false
    }
  },
  \"mcpServers\": {
    \"mcp-agent-mail\": {
      \"httpUrl\": \"$am_mcp_url\"
    }
  }
}
GEMINI_EOF"
        return $?
    fi

    # Settings file exists - merge our settings if jq is available
    if command -v jq &>/dev/null; then
        local tmp_file="$settings_dir/.settings.tmp.$$"
        local tmp_file_q=""
        local needs_update=false
        printf -v tmp_file_q '%q' "$tmp_file"

        # Check if enableInteractiveShell is already set correctly
        local shell_value
        shell_value=$(_agent_run_as_user "jq -r 'if .tools.shell | has(\"enableInteractiveShell\") then .tools.shell.enableInteractiveShell | tostring else \"unset\" end' $settings_file_q" 2>/dev/null || echo "error")

        if [[ "$shell_value" != "false" ]]; then
            needs_update=true
        fi

        # Check if selectedType is set to oauth-personal (fix gemini-api-key if found)
        local auth_value
        auth_value=$(_agent_run_as_user "jq -r '.selectedType // \"unset\"' $settings_file_q" 2>/dev/null || echo "error")

        if [[ "$auth_value" == "gemini-api-key" ]]; then
            log_detail "Fixing Gemini auth from API key to OAuth..."
            needs_update=true
        elif [[ "$auth_value" != "oauth-personal" ]]; then
            needs_update=true
        fi

        # Check if MCP Agent Mail server is configured (fixes #158)
        local mcp_value
        mcp_value=$(_agent_run_as_user "jq -r '.mcpServers.\"mcp-agent-mail\".httpUrl // \"unset\"' $settings_file_q" 2>/dev/null || echo "error")
        if [[ "$mcp_value" != "$am_mcp_url" ]]; then
            needs_update=true
        fi

        if [[ "$needs_update" == "true" ]]; then
            log_detail "Configuring Gemini settings for tmux compatibility, OAuth, and MCP Agent Mail..."
            # Update shell settings, auth type, and MCP server config
            if _agent_run_as_user "jq --arg http_url $am_mcp_url_q '.selectedType = \"oauth-personal\" | .tools = (.tools // {}) | .tools.shell = (.tools.shell // {}) | .tools.shell.enableInteractiveShell = false | .mcpServers = (.mcpServers // {}) | .mcpServers.\"mcp-agent-mail\" = {\"httpUrl\": \$http_url}' $settings_file_q > $tmp_file_q && mv $tmp_file_q $settings_file_q" 2>/dev/null; then
                log_detail "Gemini settings configured (OAuth + tmux + MCP Agent Mail)"
            else
                _agent_run_as_user "rm -f $tmp_file_q" 2>/dev/null
                log_warn "Could not update Gemini settings automatically"
            fi
        else
            log_detail "Gemini settings already configured correctly"
        fi
    else
        log_detail "jq not available; skipping Gemini settings merge"
    fi

    return 0
}

# Install Gemini CLI via bun
# The official package is @google/gemini-cli
install_gemini_cli() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_agent_target_home "$target_user")"
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)
    local gemini_bin="$target_home/.bun/bin/$GEMINI_BIN"
    local gemini_wrapper="$target_home/.local/bin/gemini"

    # Check if already installed (wrapper takes precedence)
    if [[ -x "$gemini_wrapper" ]]; then
        log_detail "Gemini CLI already installed at $gemini_wrapper"
        # Ensure tmux-compatible settings are configured
        _configure_gemini_settings "$target_home"
        return 0
    fi
    if [[ -x "$gemini_bin" ]]; then
        log_detail "Gemini CLI already installed at $gemini_bin"
        # Create wrapper if missing (fixes node PATH issues)
        _agent_create_bun_wrapper "$target_home" "gemini"
        # Ensure tmux-compatible settings are configured
        _configure_gemini_settings "$target_home"
        return 0
    fi

    # Verify bun is available
    if ! _agent_check_bun; then
        return 1
    fi

    log_detail "Installing Gemini CLI for $target_user..."

    # Install via bun global
    if _agent_run_as_user "\"$bun_bin\" install -g --trust $GEMINI_PACKAGE"; then
        if [[ -x "$gemini_bin" ]]; then
            # Create wrapper script that uses bun as runtime (avoids node PATH issues)
            _agent_create_bun_wrapper "$target_home" "gemini"
            # Apply patches (EBADF crash fix, rate-limit retry 3→1000, quota retry)
            log_detail "Applying Gemini CLI patches..."
            _agent_apply_verified_gemini_patch || true
            # Configure settings for tmux/agent compatibility
            _configure_gemini_settings "$target_home"
            log_success "Gemini CLI installed"
            log_detail "Note: Run 'gemini' to complete Google login"
            return 0
        fi
    fi

    log_warn "Gemini CLI installation may have failed"
    return 1
}

# Upgrade Gemini CLI to latest version
upgrade_gemini_cli() {
    local target_user="${TARGET_USER:-ubuntu}"
    local bun_bin
    bun_bin=$(_agent_get_bun_bin)

    if ! _agent_check_bun; then
        return 1
    fi

    log_detail "Upgrading Gemini CLI..."
    if _agent_run_as_user "\"$bun_bin\" install -g --trust $GEMINI_PACKAGE"; then
        # Apply patches (EBADF crash fix, rate-limit retry 3→1000, quota retry)
        log_detail "Applying Gemini CLI patches..."
        _agent_apply_verified_gemini_patch || true
        log_success "Gemini CLI upgraded"
        return 0
    else
        log_warn "Gemini CLI upgrade failed"
        return 1
    fi
}

# ============================================================
# Verification Functions
# ============================================================

# Verify all coding agents are installed
verify_agents() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_agent_target_home "$target_user")"
    local bun_bin_dir="$target_home/.bun/bin"
    local all_pass=true

    log_detail "Verifying coding agents..."

    # Check Claude Code
    local claude_native_bin="$target_home/.local/bin/claude"
    if [[ -x "$claude_native_bin" ]]; then
        local version
        version=$(_agent_run_as_user "\"$claude_native_bin\" --version" 2>/dev/null || echo "installed")
        log_detail "  claude: $version"
    elif [[ -x "$bun_bin_dir/$CLAUDE_BIN" ]]; then
        local version
        version=$(_agent_run_as_user "\"$bun_bin_dir/$CLAUDE_BIN\" --version" 2>/dev/null || echo "installed")
        log_detail "  claude: $version"
    else
        log_warn "  Missing: claude (Claude Code)"
        all_pass=false
    fi

    # Check Codex CLI
    if [[ -x "$bun_bin_dir/$CODEX_BIN" ]]; then
        local version
        version=$(_agent_run_as_user "\"$bun_bin_dir/$CODEX_BIN\" --version" 2>/dev/null || echo "installed")
        log_detail "  codex: $version"
    else
        log_warn "  Missing: codex (Codex CLI)"
        all_pass=false
    fi

    # Check Gemini CLI
    if [[ -x "$bun_bin_dir/$GEMINI_BIN" ]]; then
        local version
        version=$(_agent_run_as_user "\"$bun_bin_dir/$GEMINI_BIN\" --version" 2>/dev/null || echo "installed")
        log_detail "  gemini: $version"
    else
        log_warn "  Missing: gemini (Gemini CLI)"
        all_pass=false
    fi

    if [[ "$all_pass" == "true" ]]; then
        log_success "All coding agents verified"
        log_detail "Note: Each agent requires login before use"
        return 0
    else
        log_warn "Some coding agents are missing"
        return 1
    fi
}

# Check if agents are authenticated/logged in
check_agent_auth() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_agent_target_home "$target_user")"

    log_detail "Checking agent authentication status..."

    # Claude: require a non-empty OAuth token, not just a config file.
    local claude_creds_file="$target_home/.claude/.credentials.json"
    local claude_configured=false
    if command -v jq &>/dev/null; then
        if _agent_json_file_has_usable_jq_value "$claude_creds_file" '.claudeAiOauth.accessToken // empty | strings'; then
            claude_configured=true
        fi
    elif _agent_json_file_has_usable_string_key "$claude_creds_file" "accessToken"; then
        claude_configured=true
    fi

    if [[ "$claude_configured" == "true" ]]; then
        log_detail "  Claude: configured"
    else
        log_warn "  Claude: not configured (run 'claude' to login)"
    fi

    # Codex: require a non-empty OAuth/API token, not just auth.json presence.
    local codex_home="${CODEX_HOME:-$target_home/.codex}"
    local codex_auth_file="$codex_home/auth.json"
    local codex_configured=false
    if command -v jq &>/dev/null; then
        if _agent_json_file_has_usable_jq_value "$codex_auth_file" '[.tokens.access_token, .access_token, .accessToken, .OPENAI_API_KEY] | .[]? | strings'; then
            codex_configured=true
        fi
    elif _agent_json_file_has_usable_string_key "$codex_auth_file" "access_token" "accessToken" "OPENAI_API_KEY"; then
        codex_configured=true
    fi

    if [[ "$codex_configured" == "true" ]]; then
        log_detail "  Codex: configured"
    else
        log_warn "  Codex: not configured (run 'codex login --device-auth' to authenticate)"
    fi

    # Gemini: require a non-empty active account or token, not just file presence.
    local gemini_accounts_file="$target_home/.gemini/google_accounts.json"
    local gemini_oauth_file="$target_home/.gemini/oauth_creds.json"
    local gemini_configured=false

    if command -v jq &>/dev/null; then
        if _agent_json_file_has_usable_jq_value "$gemini_accounts_file" '.active // empty | strings'; then
            gemini_configured=true
        elif _agent_json_file_has_usable_jq_value "$gemini_oauth_file" '[.access_token, .refresh_token] | .[]? | strings'; then
            gemini_configured=true
        fi
    else
        if _agent_json_file_has_usable_string_key "$gemini_accounts_file" "active"; then
            gemini_configured=true
        elif _agent_json_file_has_usable_string_key "$gemini_oauth_file" "access_token" "refresh_token"; then
            gemini_configured=true
        fi
    fi

    if [[ "$gemini_configured" == "true" ]]; then
        log_detail "  Gemini: configured"
    else
        log_warn "  Gemini: not configured (run 'gemini' to login via browser)"
    fi
}

# Get versions of installed agents (for doctor output)
get_agent_versions() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_agent_target_home "$target_user")"
    local bun_bin_dir="$target_home/.bun/bin"
    local claude_native_bin="$target_home/.local/bin/claude"

    echo "Coding Agent Versions:"

    # Check Claude Code (native install takes priority, then bun)
    if [[ -x "$claude_native_bin" ]]; then
        echo "  claude: $(_agent_run_as_user "\"$claude_native_bin\" --version" 2>/dev/null || echo 'installed')"
    elif [[ -x "$bun_bin_dir/$CLAUDE_BIN" ]]; then
        echo "  claude: $(_agent_run_as_user "\"$bun_bin_dir/$CLAUDE_BIN\" --version" 2>/dev/null || echo 'installed')"
    fi
    if [[ -x "$bun_bin_dir/$CODEX_BIN" ]]; then
        echo "  codex: $(_agent_run_as_user "\"$bun_bin_dir/$CODEX_BIN\" --version" 2>/dev/null || echo 'installed')"
    fi
    if [[ -x "$bun_bin_dir/$GEMINI_BIN" ]]; then
        echo "  gemini: $(_agent_run_as_user "\"$bun_bin_dir/$GEMINI_BIN\" --version" 2>/dev/null || echo 'installed')"
    fi
}

# ============================================================
# Upgrade All Agents
# ============================================================

# Upgrade all agents to latest versions
# Returns: 0 if all succeeded, 1 if any failed
upgrade_all_agents() {
    log_detail "Upgrading all coding agents..."

    local failed=0

    if ! upgrade_claude_code; then
        failed=$((failed + 1))
    fi
    if ! upgrade_codex_cli; then
        failed=$((failed + 1))
    fi
    if ! upgrade_gemini_cli; then
        failed=$((failed + 1))
    fi

    if ((failed == 0)); then
        log_success "All coding agents upgraded"
        return 0
    elif ((failed == 3)); then
        log_error "All agent upgrades failed"
        return 1
    else
        log_warn "Some agent upgrades failed ($failed of 3)"
        return 1
    fi
}

# ============================================================
# Main Installation Function
# ============================================================

# Install all coding agents (called by install.sh)
install_all_agents() {
    log_step "6/8" "Installing coding agents..."

    # Verify bun is available first
    if ! _agent_check_bun; then
        log_warn "Skipping agent installation - bun not available"
        log_warn "Install bun first, then re-run this script"
        return 1
    fi

    # Install each agent
    install_claude_code
    install_codex_cli
    install_gemini_cli

    # Verify installation
    verify_agents

    # Note about authentication
    echo ""
    log_detail "Next steps: Login to each agent"
    log_detail "  • Claude: Run 'claude' and follow prompts"
    log_detail "  • Codex:  Run 'codex login --device-auth' (uses ChatGPT Pro account, not API key)"
    log_detail "  • Gemini: Run 'gemini' and complete Google login"
    echo ""

    log_success "Coding agents installation complete"
}

# ============================================================
# Module can be sourced or run directly
# ============================================================

# If run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_all_agents "$@"
fi
