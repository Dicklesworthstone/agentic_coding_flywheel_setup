#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Dicklesworthstone Stack Library
# Installs all 19 Dicklesworthstone tools + utilities
# ============================================================

STACK_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$STACK_SCRIPT_DIR/logging.sh"
fi

# ============================================================
# Configuration
# ============================================================

# Tool commands for verification
declare -gA STACK_COMMANDS=(
    [ntm]="ntm"
    [mcp_agent_mail]="am"
    [ubs]="ubs"
    [bv]="bv"
    [br]="br"
    [cass]="cass"
    [cm]="cm"
    [caam]="caam"
    [slb]="slb"
    [ru]="ru"
    [dcg]="dcg"
    [rch]="rch"
    [pt]="pt"
    [fsfs]="fsfs"
    [sbh]="sbh"
    [casr]="casr"
    [dsr]="dsr"
    [asb]="asb"
    [pcr]="claude-post-compact-reminder"
)

# Tool display names
declare -gA STACK_NAMES=(
    [ntm]="NTM (Named Tmux Manager)"
    [mcp_agent_mail]="MCP Agent Mail"
    [ubs]="Ultimate Bug Scanner"
    [bv]="Beads Viewer"
    [br]="BR (Beads Rust)"
    [cass]="CASS (Coding Agent Session Search)"
    [cm]="CM (CASS Memory System)"
    [caam]="CAAM (Coding Agent Account Manager)"
    [slb]="SLB (Simultaneous Launch Button)"
    [ru]="RU (Repo Updater)"
    [dcg]="DCG (Destructive Command Guard)"
    [rch]="RCH (Remote Compilation Helper)"
    [pt]="PT (Process Triage)"
    [fsfs]="Frankensearch"
    [sbh]="SBH (Storage Ballast Helper)"
    [casr]="CASR (Cross-Agent Session Resumer)"
    [dsr]="DSR (Doodlestein Self-Releaser)"
    [asb]="ASB (Agent Settings Backup)"
    [pcr]="PCR (Post-Compact Reminder)"
)

# ============================================================
# Helper Functions
# ============================================================

# Check if a command exists
_stack_command_exists() {
    command -v "$1" &>/dev/null
}

_stack_sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

_stack_home_from_user_bin_dir() {
    local bin_dir="${1:-}"
    local hinted_home=""

    case "$bin_dir" in
        */.local/bin) hinted_home="${bin_dir%/.local/bin}" ;;
        */.acfs/bin) hinted_home="${bin_dir%/.acfs/bin}" ;;
        */.cargo/bin) hinted_home="${bin_dir%/.cargo/bin}" ;;
        */.bun/bin) hinted_home="${bin_dir%/.bun/bin}" ;;
        */.atuin/bin) hinted_home="${bin_dir%/.atuin/bin}" ;;
        */go/bin) hinted_home="${bin_dir%/go/bin}" ;;
        */google-cloud-sdk/bin) hinted_home="${bin_dir%/google-cloud-sdk/bin}" ;;
        *) return 1 ;;
    esac

    hinted_home="$(_stack_existing_abs_home "$hinted_home" 2>/dev/null || true)"
    [[ -n "$hinted_home" ]] || return 1
    printf '%s\n' "$hinted_home"
}

_stack_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local target_home="${2:-}"

    bin_dir="$(_stack_sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    target_home="$(_stack_existing_abs_home "$target_home" 2>/dev/null || true)"
    [[ -n "$bin_dir" && -n "$target_home" ]] || return 1
    [[ "$bin_dir" == "$target_home" || "$bin_dir" == "$target_home/"* ]] || return 1

    printf '%s\n' "$bin_dir"
}

_stack_target_bin_dir() {
    local target_user="${1:-${TARGET_USER:-ubuntu}}"
    local target_home=""
    local configured_bin=""
    local candidate_home=""
    local hinted_home=""
    local getent_bin=""

    target_home="$(_stack_target_home "$target_user" 2>/dev/null || true)"
    [[ -n "$target_home" ]] || return 1

    configured_bin="$(_stack_sanitize_abs_nonroot_path "${ACFS_BIN_DIR:-}" 2>/dev/null || true)"
    if [[ -n "$configured_bin" ]]; then
        if [[ "$configured_bin" == "$target_home" || "$configured_bin" == "$target_home/"* ]]; then
            printf '%s\n' "$configured_bin"
            return 0
        fi

        hinted_home="$(_stack_home_from_user_bin_dir "$configured_bin" 2>/dev/null || true)"
        if [[ -n "$hinted_home" ]] && [[ "$hinted_home" != "$target_home" ]]; then
            configured_bin=""
        fi

        getent_bin="$(_stack_system_binary_path getent 2>/dev/null || true)"
        if [[ -n "$configured_bin" ]] && [[ -n "$getent_bin" ]]; then
            while IFS=: read -r _ _ _ _ _ candidate_home _; do
                candidate_home="$(_stack_existing_abs_home "$candidate_home" 2>/dev/null || true)"
                [[ -n "$candidate_home" ]] || continue
                [[ "$candidate_home" == "$target_home" ]] && continue
                if [[ "$configured_bin" == "$candidate_home" || "$configured_bin" == "$candidate_home/"* ]]; then
                    configured_bin=""
                    break
                fi
            done < <("$getent_bin" passwd 2>/dev/null || true)
        fi

        if [[ -n "$configured_bin" ]]; then
            printf '%s\n' "$configured_bin"
            return 0
        fi
    fi

    printf '%s/.local/bin\n' "$target_home"
}

_stack_target_command_path() {
    local cmd="${1:-}"
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    local primary_bin=""
    local candidate=""

    [[ -n "$cmd" ]] || return 1

    target_home="$(_stack_target_home "$target_user" 2>/dev/null || true)"
    [[ -n "$target_home" ]] || return 1
    primary_bin="$(_stack_target_bin_dir "$target_user" 2>/dev/null || true)"
    [[ -n "$primary_bin" ]] || return 1

    for candidate in \
        "$primary_bin/$cmd" \
        "$target_home/.local/bin/$cmd" \
        "$target_home/.acfs/bin/$cmd" \
        "$target_home/.cargo/bin/$cmd" \
        "$target_home/.bun/bin/$cmd" \
        "$target_home/.atuin/bin/$cmd" \
        "$target_home/go/bin/$cmd" \
        "$target_home/bin/$cmd" \
        "/usr/local/bin/$cmd" \
        "/usr/local/sbin/$cmd" \
        "/usr/bin/$cmd" \
        "/bin/$cmd" \
        "/snap/bin/$cmd"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

_stack_target_has_command() {
    [[ -n "$(_stack_target_command_path "${1:-}" 2>/dev/null || true)" ]]
}

_stack_claude_settings_has_command_hook() {
    local settings_file="${1:-}"
    local command_pattern="${2:-}"

    [[ -n "$settings_file" && -n "$command_pattern" ]] || return 1
    [[ -f "$settings_file" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1

    jq -e --arg pattern "$command_pattern" '
      def command_hook_matches:
        type == "object"
        and ((.type? // "command") == "command")
        and ((.command? // "") | strings | test($pattern));
      def event_entry_matches:
        if type == "object" and (.hooks? | type) == "array" then
          any(.hooks[]?; command_hook_matches)
        else
          command_hook_matches
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

_stack_curl() {
    local curl_bin=""

    curl_bin="$(_stack_target_command_path curl 2>/dev/null || true)"
    [[ -n "$curl_bin" ]] || return 127

    "$curl_bin" "$@"
}

_stack_system_curl() {
    local curl_bin=""

    curl_bin="$(_stack_system_binary_path curl 2>/dev/null || true)"
    [[ -n "$curl_bin" ]] || return 127

    "$curl_bin" "$@"
}
# Check if we're in interactive mode (fallback if security.sh isn't loaded yet).
_stack_is_interactive() {
    if declare -f _acfs_is_interactive >/dev/null 2>&1; then
        _acfs_is_interactive
        return $?
    fi

    [[ "${ACFS_INTERACTIVE:-true}" == "true" ]] || return 1

    if [[ -e /dev/tty ]] && (exec 3<>/dev/tty) 2>/dev/null; then
        return 0
    fi

    [[ -t 0 ]]
}

# Get the sudo command if needed
_stack_get_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo ""
    else
        echo "sudo"
    fi
}

_stack_existing_abs_home() {
    local home_candidate="${1:-}"

    [[ -n "$home_candidate" ]] || return 1
    home_candidate="${home_candidate%/}"
    [[ -n "$home_candidate" ]] || return 1
    [[ "$home_candidate" == /* ]] || return 1
    [[ "$home_candidate" != "/" ]] || return 1
    [[ -d "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

_stack_system_binary_path() {
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

_stack_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(_stack_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(_stack_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

_stack_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(_stack_system_binary_path getent 2>/dev/null || true)"
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

_stack_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(_stack_existing_abs_home "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}

_stack_target_home() {
    local target_user="${1:-${TARGET_USER:-ubuntu}}"
    local explicit_bin_dir=""
    local explicit_home=""
    local initial_env_home=""
    local passwd_entry=""
    local current_user=""
    local current_home=""

    explicit_home="$(_stack_existing_abs_home "${TARGET_HOME:-}" 2>/dev/null || true)"
    initial_env_home="$(_stack_existing_abs_home "${ACFS_INITIAL_ENV_HOME:-${_UPDATE_INITIAL_ENV_HOME:-}}" 2>/dev/null || true)"
    current_user="$(_stack_resolve_current_user 2>/dev/null || true)"
    explicit_bin_dir="$(_stack_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$explicit_home" 2>/dev/null || true)"
    if [[ "$target_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi
    # Doctor/update call this only after they have already resolved TARGET_HOME.
    # Normal installer paths still prefer passwd/NSS data over inherited env.
    if [[ "${ACFS_STACK_TRUST_TARGET_HOME:-false}" == "true" && -n "$explicit_home" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi
    if [[ -n "$explicit_home" ]] && [[ "$target_user" == "$current_user" ]] && {
        [[ -f "$explicit_home/.acfs/state.json" ]] \
            || [[ -f "$explicit_home/.acfs/VERSION" ]] \
            || [[ -d "$explicit_home/.acfs/scripts/lib" ]]
    }; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    if [[ -n "$explicit_home" && -n "$explicit_bin_dir" && -z "${TARGET_USER:-}" && "$explicit_home" != "$initial_env_home" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    if [[ -n "$explicit_home" ]]; then
        passwd_entry="$(_stack_getent_passwd_entry "$target_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_entry="$(_stack_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_entry" ]]; then
                current_home="$(_stack_existing_abs_home "${HOME:-}" 2>/dev/null || true)"
                if [[ -n "$explicit_home" ]] \
                    && [[ -n "$explicit_bin_dir" ]] \
                    && [[ "$target_user" == "$current_user" ]] \
                    && [[ "$current_home" == "$passwd_entry" ]] \
                    && [[ "$explicit_home" != "$initial_env_home" ]]; then
                    printf '%s\n' "$explicit_home"
                    return 0
                fi
                printf '%s\n' "${passwd_entry%/}"
                return 0
            fi
        fi
    fi

    if [[ "$current_user" == "$target_user" ]]; then
        current_home="$(_stack_existing_abs_home "${HOME:-}" 2>/dev/null || true)"
        if [[ -n "$current_home" ]] && { [[ -z "$explicit_home" ]] || [[ "$current_home" == "$explicit_home" ]]; }; then
            printf '%s\n' "$current_home"
            return 0
        fi
    fi

    passwd_entry="$(_stack_getent_passwd_entry "$target_user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        passwd_entry="$(_stack_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            printf '%s\n' "${passwd_entry%/}"
            return 0
        fi
    fi

    if [[ -n "$explicit_home" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    return 1
}
_stack_validate_target_user() {
    local username="${1:-${TARGET_USER:-}}"
    local display="${username:-<empty>}"

    if [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        return 0
    fi

    log_error "Invalid TARGET_USER '$display' (expected: lowercase user name like 'ubuntu')"
    return 1
}

_stack_trim_ascii_whitespace() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

_stack_strip_wrapping_quotes() {
    local value
    value="$(_stack_trim_ascii_whitespace "${1:-}")"
    if [[ "${#value}" -ge 2 ]]; then
        case "$value" in
            \"*\"|\'*\')
                if [[ "${value:0:1}" == "${value: -1}" ]]; then
                    value="${value:1:${#value}-2}"
                fi
                ;;
        esac
    fi
    printf '%s\n' "$value"
}

_stack_parse_env_assignment_rhs() {
    local raw="$1"
    local out=""
    local quote=""
    local prev=""
    local char=""
    local raw_len="${#raw}"
    local i=0

    while [[ "$i" -lt "$raw_len" ]]; do
        char="${raw:i:1}"
        if [[ -n "$quote" ]]; then
            out="${out}${char}"
            if [[ "$char" == "$quote" ]]; then
                quote=""
            fi
        else
            if [[ "$char" == '"' || "$char" == "'" ]]; then
                quote="$char"
                out="${out}${char}"
            elif [[ "$char" == "#" ]]; then
                if [[ -z "$prev" || "$prev" =~ [[:space:]] ]]; then
                    break
                fi
                out="${out}${char}"
            else
                out="${out}${char}"
            fi
        fi
        prev="$char"
        i=$((i + 1))
    done

    out="$(_stack_trim_ascii_whitespace "$out")"
    _stack_strip_wrapping_quotes "$out"
}

_stack_read_env_assignment_value() {
    local file="$1"
    local key="$2"
    local value=""

    [[ -f "$file" ]] || return 0
    value="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" "$file" 2>/dev/null | tail -1 | sed -E "s/^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=[[:space:]]*//" || true)"
    [[ -n "$value" ]] || return 0
    _stack_parse_env_assignment_rhs "$value"
}

_stack_normalize_http_path() {
    local value="${1:-/mcp/}"
    case "$value" in
        mcp|/mcp|/mcp/) printf '/mcp/\n' ;;
        api|/api|/api/) printf '/api/\n' ;;
        *)
            [[ -n "$value" ]] || value="/mcp/"
            [[ "$value" == /* ]] || value="/${value}"
            [[ "$value" == */ ]] || value="${value}/"
            printf '%s\n' "$value"
            ;;
    esac
}

_stack_agent_mail_cli_path() {
    local target_home=""
    target_home="$(_stack_target_home "${TARGET_USER:-ubuntu}")"

    local preferred="$target_home/mcp_agent_mail/am"
    local primary_bin=""
    local fallback_bin="$target_home/.local/bin/am"
    primary_bin="$(_stack_target_bin_dir "${TARGET_USER:-ubuntu}" 2>/dev/null || true)"
    primary_bin="${primary_bin}/am"
    local candidate=""

    for candidate in \
        "$preferred" \
        "$primary_bin" \
        "$fallback_bin" \
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

_stack_repair_agent_mail_cli_symlink() {
    local target_home=""
    target_home="$(_stack_target_home "${TARGET_USER:-ubuntu}")"

    local am_src="$target_home/mcp_agent_mail/am"
    [[ -x "$am_src" ]] || return 1

    local primary_dir=""
    primary_dir="$(_stack_target_bin_dir "${TARGET_USER:-ubuntu}" 2>/dev/null || true)"
    local fallback_dir="$target_home/.local/bin"
    local -a bin_dirs=("$primary_dir")

    if [[ "$fallback_dir" != "$primary_dir" ]]; then
        bin_dirs+=("$fallback_dir")
    fi

    local dir=""
    local repaired=0
    for dir in "${bin_dirs[@]}"; do
        [[ -n "$dir" ]] || continue
        [[ "$dir/am" == "$am_src" ]] && continue
        local dir_q=""
        local am_src_q=""
        local am_dest_q=""
        printf -v dir_q '%q' "$dir"
        printf -v am_src_q '%q' "$am_src"
        printf -v am_dest_q '%q' "$dir/am"
        _stack_run_as_user "mkdir -p $dir_q && ln -sfn $am_src_q $am_dest_q && [[ -x $am_dest_q ]]" || repaired=1
    done

    return "$repaired"
}

_stack_agent_mail_liveness() {
    _stack_curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 || \
        _stack_curl -fsS --max-time 10 http://127.0.0.1:8765/healthz >/dev/null 2>&1
}

_stack_agent_mail_readiness() {
    local readiness_body=""
    readiness_body="$(_stack_curl -fsS --max-time 10 http://127.0.0.1:8765/health 2>/dev/null)" || return 1
    printf '%s\n' "$readiness_body" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"([[:space:]]*[,}])'
}

# Run a command as target user
_stack_run_as_user() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    local resolved_bin_dir=""
    local system_path_prefix="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
    _stack_validate_target_user "$target_user" || return 1
    target_home="$(_stack_target_home "$target_user" 2>/dev/null || true)"
    if [[ -z "$target_home" ]] || [[ "$target_home" == "/" ]] || [[ "$target_home" != /* ]]; then
        log_error "Invalid TARGET_HOME for '$target_user': ${target_home:-<empty>} (must be an absolute path and cannot be '/')"
        return 1
    fi
    resolved_bin_dir="$(_stack_target_bin_dir "$target_user" 2>/dev/null || true)"
    [[ -n "$resolved_bin_dir" ]] || resolved_bin_dir="$target_home/.local/bin"
    local target_path_prefix="$resolved_bin_dir:$target_home/.local/bin:$target_home/.acfs/bin:$target_home/.cargo/bin:$target_home/.bun/bin:$target_home/.atuin/bin:$target_home/go/bin"
    local cmd="$1"
    local target_user_q=""
    local target_home_q=""
    local acfs_bin_dir_q=""
    local target_path_prefix_q=""
    local wrapped_cmd=""
    local bash_bin=""
    local sudo_bin=""
    local runuser_bin=""
    local su_bin=""

    bash_bin="$(_stack_system_binary_path bash 2>/dev/null || true)"
    [[ -n "$bash_bin" ]] || {
        log_error "Unable to locate bash for target-user stack command"
        return 1
    }

    printf -v target_user_q '%q' "$target_user"
    printf -v target_home_q '%q' "$target_home"
    printf -v acfs_bin_dir_q '%q' "$resolved_bin_dir"
    printf -v target_path_prefix_q '%q' "$target_path_prefix"

    wrapped_cmd="export TARGET_USER=$target_user_q TARGET_HOME=$target_home_q HOME=$target_home_q ACFS_BIN_DIR=$acfs_bin_dir_q;"
    wrapped_cmd+=" export PATH=$target_path_prefix_q:$system_path_prefix:\$PATH; set -o pipefail; cd \"\$HOME\" || exit 1; $cmd"

    if [[ "$(_stack_resolve_current_user 2>/dev/null || true)" == "$target_user" ]]; then
        "$bash_bin" -c "$wrapped_cmd"
        return $?
    fi

    sudo_bin="$(_stack_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -u "$target_user" -H "$bash_bin" -c "$wrapped_cmd"
        return $?
    fi

    runuser_bin="$(_stack_system_binary_path runuser 2>/dev/null || true)"
    if [[ -n "$runuser_bin" ]]; then
        "$runuser_bin" -u "$target_user" -- "$bash_bin" -c "$wrapped_cmd"
        return $?
    fi

    su_bin="$(_stack_system_binary_path su 2>/dev/null || true)"
    [[ -n "$su_bin" ]] || {
        log_error "Unable to locate sudo, runuser, or su for target-user stack command"
        return 1
    }

    # Avoid login shells: profile files are not a stable API and can break non-interactive runs.
    "$su_bin" "$target_user" -c "$(printf '%q' "$bash_bin") -c $(printf %q "$wrapped_cmd")"
}

# Load security helpers + checksums.yaml (fail closed if unavailable).
STACK_SECURITY_READY=false
_stack_require_security() {
    if [[ "${STACK_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    if [[ ! -f "$STACK_SCRIPT_DIR/security.sh" ]]; then
        log_warn "Security library not found ($STACK_SCRIPT_DIR/security.sh); refusing to run upstream installer scripts"
        return 1
    fi

    # shellcheck source=security.sh
    source "$STACK_SCRIPT_DIR/security.sh"
    if ! load_checksums; then
        log_warn "checksums.yaml not available; refusing to run upstream installer scripts"
        return 1
    fi

    STACK_SECURITY_READY=true
    return 0
}

# Run an installer script as target user with checksum verification.
# Some upstream installers use environment variables instead of CLI flags for
# non-interactive mode, so allow one optional inline env assignment like VAR=value.
_stack_run_verified_installer_with_env() {
    if [[ $# -lt 1 ]]; then
        log_warn "_stack_run_verified_installer_with_env requires at least a tool name"
        return 1
    fi

    local tool="$1"
    local bash_env_assignment="${2:-}"
    if [[ $# -ge 2 ]]; then
        shift 2
    else
        set --
    fi

    if ! _stack_require_security; then
        return 1
    fi

    local url="${KNOWN_INSTALLERS[$tool]:-}"
    local expected_sha256
    expected_sha256="$(get_checksum "$tool")"

    if [[ -z "$url" ]]; then
        log_warn "No installer URL configured for $tool (KNOWN_INSTALLERS)"
        return 1
    fi
    if [[ -z "$expected_sha256" ]]; then
        log_warn "No checksum recorded for $tool; refusing to run unverified installer"
        return 1
    fi
    local env_assignment_rendered=""
    if [[ -n "$bash_env_assignment" ]]; then
        if [[ "$bash_env_assignment" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local env_name="${BASH_REMATCH[1]}"
            local env_value="${BASH_REMATCH[2]}"
            local env_value_q=""
            printf -v env_value_q '%q' "$env_value"
            env_assignment_rendered="${env_name}=${env_value_q}"
        else
            log_warn "Invalid inline env assignment for $tool installer: $bash_env_assignment"
            return 1
        fi
    fi

    local -a quoted_args=()
    local arg
    for arg in "$@"; do
        quoted_args+=("$(printf '%q' "$arg")")
    done

    local security_lib_q=""
    local url_q=""
    local expected_sha256_q=""
    local tool_q=""
    printf -v security_lib_q '%q' "$STACK_SCRIPT_DIR/security.sh"
    printf -v url_q '%q' "$url"
    printf -v expected_sha256_q '%q' "$expected_sha256"
    printf -v tool_q '%q' "$tool"

    local cmd="set -o pipefail; source $security_lib_q; verify_checksum $url_q $expected_sha256_q $tool_q | "
    if [[ -n "$env_assignment_rendered" ]]; then
        cmd+="$env_assignment_rendered "
    fi
    cmd+="bash -s --"
    if [[ ${#quoted_args[@]} -gt 0 ]]; then
        cmd+=" ${quoted_args[*]}"
    fi

    _stack_run_as_user "$cmd"
}

_stack_run_verified_installer() {
    if [[ $# -lt 1 ]]; then
        log_warn "_stack_run_verified_installer requires a tool name"
        return 1
    fi

    local tool="$1"
    if [[ $# -ge 1 ]]; then
        shift
    else
        set --
    fi
    _stack_run_verified_installer_with_env "$tool" "" "$@"
}

_stack_fsfs_linux_target_triple() {
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

_stack_is_valid_fsfs_version() {
    local version="${1:-}"
    [[ "$version" =~ ^v[0-9][A-Za-z0-9._-]*$ ]]
}

_stack_resolve_fsfs_latest_version() {
    if [[ -n "${ACFS_FSFS_VERSION:-}" ]]; then
        _stack_is_valid_fsfs_version "$ACFS_FSFS_VERSION" || return 1
        printf '%s\n' "$ACFS_FSFS_VERSION"
        return 0
    fi

    local latest_url="https://api.github.com/repos/Dicklesworthstone/frankensearch/releases/latest"
    local redirect_url="https://github.com/Dicklesworthstone/frankensearch/releases/latest"
    local tag=""
    tag="$(_stack_system_curl -fsSL --connect-timeout 30 --max-time 60 -H "Accept: application/vnd.github.v3+json" "$latest_url" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1 || true)"

    if _stack_is_valid_fsfs_version "$tag"; then
        printf '%s\n' "$tag"
        return 0
    fi

    tag="$(_stack_system_curl -fsSL --connect-timeout 30 --max-time 60 -o /dev/null -w '%{url_effective}' "$redirect_url" 2>/dev/null \
        | sed -E 's|.*/tag/||' || true)"

    _stack_is_valid_fsfs_version "$tag" || return 1
    printf '%s\n' "$tag"
}

_stack_fetch_fsfs_artifact_checksum() {
    local checksum_url="$1"
    local checksum=""

    checksum="$(_stack_system_curl -fsSL --connect-timeout 30 --max-time 60 "$checksum_url" 2>/dev/null \
        | awk 'NR == 1 { print $1 }' || true)"
    [[ "$checksum" =~ ^[0-9A-Fa-f]{64}$ ]] || return 1
    printf '%s\n' "${checksum,,}"
}

_stack_resolve_fsfs_artifact_contract() {
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
        _stack_is_valid_fsfs_version "$ACFS_FSFS_VERSION" || return 1
        candidates+=("$ACFS_FSFS_VERSION")
    else
        while IFS= read -r candidate; do
            [[ -n "$candidate" ]] || continue
            case " ${candidates[*]} " in
                *" $candidate "*) ;;
                *) candidates+=("$candidate") ;;
            esac
        done < <(
            _stack_system_curl -fsSL --connect-timeout 30 --max-time 60 \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/Dicklesworthstone/frankensearch/releases?per_page=10" 2>/dev/null \
                | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true
        )

        candidate="$(_stack_system_curl -fsSL --connect-timeout 30 --max-time 60 -o /dev/null -w '%{url_effective}' \
            "https://github.com/Dicklesworthstone/frankensearch/releases/latest" 2>/dev/null \
            | sed -E 's|.*/tag/||' || true)"
        if _stack_is_valid_fsfs_version "$candidate"; then
            case " ${candidates[*]} " in
                *" $candidate "*) ;;
                *) candidates+=("$candidate") ;;
            esac
        fi
    fi

    for fsfs_version in "${candidates[@]}"; do
        _stack_is_valid_fsfs_version "$fsfs_version" || continue
        fsfs_version_bare="${fsfs_version#v}"
        fsfs_artifact_url="https://github.com/Dicklesworthstone/frankensearch/releases/download/${fsfs_version}/fsfs-lite-${fsfs_version_bare}-${fsfs_target}.tar.xz"
        if fsfs_checksum="$(_stack_fetch_fsfs_artifact_checksum "${fsfs_artifact_url}.sha256" 2>/dev/null)"; then
            printf '%s\n%s\n%s\n' "$fsfs_version" "$fsfs_artifact_url" "$fsfs_checksum"
            return 0
        fi
        log_detail "FrankenSearch lite artifact checksum unavailable for ${fsfs_version}"
    done

    return 1
}

_stack_run_fsfs_installer() {
    local -a fsfs_args=("$@")
    local -a fsfs_contract=()
    local fsfs_target=""
    local fsfs_version=""
    local fsfs_artifact_url=""
    local fsfs_checksum=""

    if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
        if ! fsfs_target="$(_stack_fsfs_linux_target_triple 2>/dev/null)"; then
            log_warn "FrankenSearch Linux binary artifact unavailable for this architecture; skipping source-build fallback"
            return 1
        fi

        mapfile -t fsfs_contract < <(_stack_resolve_fsfs_artifact_contract "$fsfs_target")
        fsfs_version="${fsfs_contract[0]:-}"
        fsfs_artifact_url="${fsfs_contract[1]:-}"
        fsfs_checksum="${fsfs_contract[2]:-}"
        if [[ -z "$fsfs_version" || -z "$fsfs_artifact_url" || -z "$fsfs_checksum" ]]; then
            log_warn "Unable to resolve a FrankenSearch lite artifact with a checksum; skipping source-build fallback"
            return 1
        fi

        fsfs_args+=(
            --version "$fsfs_version"
            --artifact-url "$fsfs_artifact_url"
            --checksum "$fsfs_checksum"
        )
        log_detail "Using FrankenSearch Linux lite artifact: $fsfs_artifact_url"
    fi

    _stack_run_verified_installer fsfs "${fsfs_args[@]}"
}

_stack_run_installer() {
    if [[ $# -lt 1 ]]; then
        log_warn "_stack_run_installer requires a tool name"
        return 1
    fi

    local tool="$1"
    if [[ $# -ge 1 ]]; then
        shift
    else
        set --
    fi
    _stack_run_verified_installer "$tool" "$@"
}

# Check whether the local Agent Mail HTTP service is healthy.
_stack_agent_mail_healthy() {
    _stack_agent_mail_liveness
}

_stack_agent_mail_ready() {
    local am_cli_path=""
    local am_cli_path_q=""
    local check_cmd

    am_cli_path="$(_stack_agent_mail_cli_path 2>/dev/null || true)"
    [[ -n "$am_cli_path" ]] || return 1
    printf -v am_cli_path_q '%q' "$am_cli_path"

    check_cmd="$(cat <<EOF
set -euo pipefail
export PATH="\${ACFS_BIN_DIR:-\$HOME/.local/bin}:\$HOME/.local/bin:\$HOME/.acfs/bin:\$HOME/.cargo/bin:\$HOME/.bun/bin:\$HOME/.atuin/bin:\$HOME/go/bin:/usr/local/bin:/usr/bin:/bin:/snap/bin"

stack_service_curl() {
    local curl_bin=""
    local candidate=""

    for candidate in /usr/bin/curl /bin/curl /usr/local/bin/curl /usr/local/sbin/curl /usr/sbin/curl /sbin/curl; do
        [[ -x "\$candidate" ]] || continue
        curl_bin="\$candidate"
        break
    done

    [[ -n "\$curl_bin" ]] || return 127
    "\$curl_bin" "\$@"
}

am_bin=$am_cli_path_q
[[ -x "\$am_bin" ]] || exit 1

if ! stack_service_curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 && \
   ! stack_service_curl -fsS --max-time 10 http://127.0.0.1:8765/healthz >/dev/null 2>&1; then
    exit 1
fi

readiness_body="\$(stack_service_curl -fsS --max-time 10 http://127.0.0.1:8765/health 2>/dev/null)" || exit 1
printf '%s\n' "\$readiness_body" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"([[:space:]]*[,}])' || exit 1

runtime_dir="/run/user/\$(id -u)"
if [[ -d "\$runtime_dir" ]]; then
    export XDG_RUNTIME_DIR="\$runtime_dir"
    if [[ -S "\$runtime_dir/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=\$runtime_dir/bus"
    fi
fi

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1
fi
EOF
)"

    _stack_run_as_user "$check_cmd"
}

# Write and enable the managed Agent Mail user service for the target user.
_stack_configure_agent_mail_service() {
    local service_cmd
    service_cmd="$(cat <<'EOF'
set -euo pipefail
export PATH="${ACFS_BIN_DIR:-$HOME/.local/bin}:$HOME/.local/bin:$HOME/.acfs/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$HOME/go/bin:/usr/local/bin:/usr/bin:/bin:/snap/bin"

stack_service_curl() {
    local curl_bin=""
    local candidate=""

    for candidate in /usr/bin/curl /bin/curl /usr/local/bin/curl /usr/local/sbin/curl /usr/sbin/curl /sbin/curl; do
        [[ -x "$candidate" ]] || continue
        curl_bin="$candidate"
        break
    done

    [[ -n "$curl_bin" ]] || return 127
    "$curl_bin" "$@"
}

trim_ascii_whitespace() {
    local value="${1:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

strip_wrapping_quotes() {
    local value
    value="$(trim_ascii_whitespace "${1:-}")"
    if [[ "${#value}" -ge 2 ]]; then
        case "$value" in
            \"*\"|\'*\')
                if [[ "${value:0:1}" == "${value: -1}" ]]; then
                    value="${value:1:${#value}-2}"
                fi
                ;;
        esac
    fi
    printf '%s\n' "$value"
}

parse_env_assignment_rhs() {
    local raw="$1"
    local out=""
    local quote=""
    local prev=""
    local char=""
    local raw_len="${#raw}"
    local i=0

    while [[ "$i" -lt "$raw_len" ]]; do
        char="${raw:i:1}"
        if [[ -n "$quote" ]]; then
            out="${out}${char}"
            if [[ "$char" == "$quote" ]]; then
                quote=""
            fi
        else
            if [[ "$char" == '"' || "$char" == "'" ]]; then
                quote="$char"
                out="${out}${char}"
            elif [[ "$char" == "#" ]]; then
                if [[ -z "$prev" || "$prev" =~ [[:space:]] ]]; then
                    break
                fi
                out="${out}${char}"
            else
                out="${out}${char}"
            fi
        fi
        prev="$char"
        i=$((i + 1))
    done

    out="$(trim_ascii_whitespace "$out")"
    strip_wrapping_quotes "$out"
}

read_env_assignment_value() {
    local file="$1"
    local key="$2"
    local value=""

    [[ -f "$file" ]] || return 0
    value="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=" "$file" 2>/dev/null | tail -1 | sed -E "s/^[[:space:]]*(export[[:space:]]+)?${key}[[:space:]]*=[[:space:]]*//" || true)"
    [[ -n "$value" ]] || return 0
    parse_env_assignment_rhs "$value"
}

normalize_http_path() {
    local value="${1:-/mcp/}"
    case "$value" in
        mcp|/mcp|/mcp/) printf '/mcp/\n' ;;
        api|/api|/api/) printf '/api/\n' ;;
        *)
            [[ -n "$value" ]] || value="/mcp/"
            [[ "$value" == /* ]] || value="/${value}"
            [[ "$value" == */ ]] || value="${value}/"
            printf '%s\n' "$value"
            ;;
    esac
}

systemd_unit_reject_line_breaks() {
    local value="${1:-}"
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]]
}

systemd_unit_path_escape() {
    local value="${1:-}"
    local tab=$'\t'

    systemd_unit_reject_line_breaks "$value" || return 1
    value="${value//\\/\\\\}"
    value="${value//%/%%}"
    value="${value// /\\s}"
    value="${value//$tab/\\t}"
    printf '%s\n' "$value"
}

systemd_unit_quote() {
    local value="${1:-}"
    local escape_dollar="${2:-false}"

    systemd_unit_reject_line_breaks "$value" || return 1
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//%/%%}"
    if [[ "$escape_dollar" == "true" ]]; then
        value="${value//\$/\$\$}"
    fi
    printf '"%s"\n' "$value"
}

systemd_unit_exec_arg() {
    systemd_unit_quote "${1:-}" true
}

systemd_unit_exec_command() {
    systemd_unit_quote "${1:-}" false
}

systemd_unit_env_assignment() {
    local name="${1:-}"
    local value="${2:-}"

    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
    systemd_unit_quote "${name}=${value}" false
}

sqlite_user_table_count() {
    local db_path="$1"
    [[ -f "$db_path" ]] || {
        printf '0\n'
        return 0
    }
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$db_path" <<'PY'
import sqlite3
import sys

db_path = sys.argv[1]
try:
    conn = sqlite3.connect(db_path)
    cur = conn.execute("SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
    row = cur.fetchone()
    print(int(row[0]) if row and row[0] is not None else 0)
except Exception:
    print(0)
PY
        return 0
    fi
    if command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "$db_path" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';" 2>/dev/null || printf '0\n'
        return 0
    fi
    printf '0\n'
}

preferred_am="$HOME/mcp_agent_mail/am"
resolve_target_am() {
    local primary_am="${ACFS_BIN_DIR:-$HOME/.local/bin}/am"
    local candidate=""

    for candidate in \
        "$preferred_am" \
        "$primary_am" \
        "$HOME/.local/bin/am" \
        "$HOME/.acfs/bin/am" \
        "$HOME/.cargo/bin/am" \
        "$HOME/.bun/bin/am" \
        "$HOME/.atuin/bin/am" \
        "$HOME/go/bin/am"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

am_bin="$(resolve_target_am 2>/dev/null || true)"
[[ -n "$am_bin" ]] || {
    echo "am CLI missing after install" >&2
    exit 1
}

primary_bin_dir="${ACFS_BIN_DIR:-$HOME/.local/bin}"
fallback_bin_dir="$HOME/.local/bin"
mkdir -p "$primary_bin_dir" 2>/dev/null || true
if [[ -x "$preferred_am" ]]; then
    ln -sf "$preferred_am" "$primary_bin_dir/am" 2>/dev/null || true
    if [[ "$fallback_bin_dir" != "$primary_bin_dir" ]]; then
        mkdir -p "$fallback_bin_dir" 2>/dev/null || true
        ln -sf "$preferred_am" "$fallback_bin_dir/am" 2>/dev/null || true
    fi
    am_bin="$preferred_am"
fi

storage_root="$HOME/.mcp_agent_mail_git_mailbox_repo"
unit_dir="$HOME/.config/systemd/user"
unit_file="$unit_dir/agent-mail.service"
db_path="$storage_root/storage.sqlite3"
db_url="sqlite:///${db_path}"
env_file=""
for candidate in "$HOME/.config/mcp-agent-mail/config.env" "$HOME/.config/mcp-agent-mail/.env"; do
    if [[ -f "$candidate" ]]; then
        env_file="$candidate"
        break
    fi
done

cfg_db_url=""
cfg_storage_root=""
cfg_http_path=""
if [[ -n "$env_file" ]]; then
    cfg_db_url="$(read_env_assignment_value "$env_file" "DATABASE_URL")"
    cfg_storage_root="$(read_env_assignment_value "$env_file" "STORAGE_ROOT")"
    cfg_http_path="$(read_env_assignment_value "$env_file" "HTTP_PATH")"
fi

if [[ -n "$cfg_storage_root" ]]; then
    cfg_storage_root="${cfg_storage_root/#\~/$HOME}"
    case "$cfg_storage_root" in
        /*) storage_root="$cfg_storage_root" ;;
    esac
fi

db_path="$storage_root/storage.sqlite3"
db_url="sqlite:///${db_path}"

if [[ -n "$cfg_db_url" ]]; then
    cfg_db_path="$(printf '%s\n' "$cfg_db_url" | sed -n 's|^sqlite[^:]*:///||p')"
    cfg_db_path="${cfg_db_path/#\~/$HOME}"
    if [[ -n "$cfg_db_path" && "$cfg_db_path" != ":memory:" && "$cfg_db_path" != "/:memory:" ]]; then
        db_path="$cfg_db_path"
        db_url="$cfg_db_url"
        storage_root="$(dirname "$cfg_db_path")"
    fi
fi

install_storage_root="$HOME/mcp_agent_mail"
install_db="$install_storage_root/storage.sqlite3"
default_legacy_db="$HOME/.mcp_agent_mail_git_mailbox_repo/storage.sqlite3"
selected_tables="$(sqlite_user_table_count "$db_path")"
if [[ -f "$install_db" ]]; then
    install_tables="$(sqlite_user_table_count "$install_db")"
    if [[ "$install_tables" -gt 0 ]] && [[ "$selected_tables" -eq 0 ]] && {
        [[ -z "$cfg_storage_root" && -z "$cfg_db_url" ]] || [[ "$db_path" == "$default_legacy_db" ]];
    }; then
        storage_root="$install_storage_root"
        db_path="$install_db"
        db_url="sqlite:///${install_db}"
    fi
fi

# Detect MCP base path: Rust am uses /mcp/, Python mcp_agent_mail uses /api/
if "$am_bin" --version 2>/dev/null | grep -q '^am '; then
    am_mcp_path="/mcp/"
else
    am_mcp_path="/api/"
fi
if [[ -n "$cfg_http_path" ]]; then
    am_mcp_path="$(normalize_http_path "$cfg_http_path")"
fi

mkdir -p "$storage_root" "$unit_dir"
env_file_line=""
if [[ -n "$env_file" ]]; then
    env_file_unit="$(systemd_unit_path_escape "$env_file")" || exit 1
    env_file_line="EnvironmentFile=-$env_file_unit"
fi
storage_root_unit="$(systemd_unit_path_escape "$storage_root")" || exit 1
rust_log_env="$(systemd_unit_env_assignment RUST_LOG info)" || exit 1
storage_root_env="$(systemd_unit_env_assignment STORAGE_ROOT "$storage_root")" || exit 1
database_url_env="$(systemd_unit_env_assignment DATABASE_URL "$db_url")" || exit 1
http_allow_env="$(systemd_unit_env_assignment HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED true)" || exit 1
am_bin_exec="$(systemd_unit_exec_command "$am_bin")" || exit 1
am_mcp_path_exec="$(systemd_unit_exec_arg "$am_mcp_path")" || exit 1
cat > "$unit_file" <<UNIT_EOF
[Unit]
Description=MCP Agent Mail Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$storage_root_unit
${env_file_line}
Environment=$rust_log_env
Environment=$storage_root_env
Environment=$database_url_env
Environment=$http_allow_env
ExecStartPre=${am_bin_exec} migrate
ExecStart=${am_bin_exec} serve-http --no-tui --host 127.0.0.1 --port 8765 --path ${am_mcp_path_exec}
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=default.target
UNIT_EOF

runtime_dir="/run/user/$(id -u)"
if [[ -d "$runtime_dir" ]]; then
    export XDG_RUNTIME_DIR="$runtime_dir"
    if [[ -S "$runtime_dir/bus" ]]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
    fi
fi

fallback_pid_file="$storage_root/agent-mail.pid"
fallback_log_file="$storage_root/agent-mail.log"

stop_agent_mail_fallback() {
    if [[ -f "$fallback_pid_file" ]]; then
        existing_pid="$(cat "$fallback_pid_file" 2>/dev/null || true)"
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null && \
           ps -p "$existing_pid" -o args= 2>/dev/null | grep -Fq "$am_bin serve-http"; then
            kill "$existing_pid" >/dev/null 2>&1 || true
            for _ in {1..10}; do
                if ! kill -0 "$existing_pid" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            if kill -0 "$existing_pid" 2>/dev/null; then
                kill -9 "$existing_pid" >/dev/null 2>&1 || true
            fi
        fi
        rm -f "$fallback_pid_file"
    fi
}

launch_agent_mail_fallback() {
    if {
        stack_service_curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 || \
        stack_service_curl -fsS --max-time 5 http://127.0.0.1:8765/healthz >/dev/null 2>&1;
    } && stack_service_curl -fsS --max-time 5 http://127.0.0.1:8765/health 2>/dev/null | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"([[:space:]]*[,}])'; then
        return 0
    fi

    if [[ -f "$fallback_pid_file" ]]; then
        existing_pid="$(cat "$fallback_pid_file" 2>/dev/null || true)"
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null && \
           ps -p "$existing_pid" -o args= 2>/dev/null | grep -Fq "$am_bin serve-http"; then
            stop_agent_mail_fallback
        else
            rm -f "$fallback_pid_file"
        fi
    fi

    nohup env \
        RUST_LOG=info \
        STORAGE_ROOT="$storage_root" \
        DATABASE_URL="$db_url" \
        HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED=true \
        "$am_bin" migrate \
        >>"$fallback_log_file" 2>&1 < /dev/null || true

    nohup env \
        RUST_LOG=info \
        STORAGE_ROOT="$storage_root" \
        DATABASE_URL="$db_url" \
        HTTP_ALLOW_LOCALHOST_UNAUTHENTICATED=true \
        "$am_bin" serve-http --no-tui --host 127.0.0.1 --port 8765 --path "$am_mcp_path" \
        >>"$fallback_log_file" 2>&1 < /dev/null &
    echo $! > "$fallback_pid_file"
}

agent_mail_endpoint_ready() {
    local readiness_body=""

    if ! {
        stack_service_curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1 || \
        stack_service_curl -fsS --max-time 5 http://127.0.0.1:8765/healthz >/dev/null 2>&1;
    }; then
        return 1
    fi

    readiness_body="$(stack_service_curl -fsS --max-time 5 http://127.0.0.1:8765/health 2>/dev/null)" || return 1
    printf '%s\n' "$readiness_body" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"([[:space:]]*[,}])'
}

if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
    if agent_mail_endpoint_ready && ! systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1; then
        systemctl --user stop agent-mail.service >/dev/null 2>&1 || true
        systemctl --user reset-failed agent-mail.service >/dev/null 2>&1 || true
        echo "Agent Mail: healthy existing runtime detected; skipping managed service restart" >&2
        exit 0
    fi

    stop_agent_mail_fallback
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    if ! systemctl --user enable --now agent-mail.service >/dev/null 2>&1; then
        systemctl --user restart agent-mail.service >/dev/null 2>&1
    fi
    active_waited=0
    active_max_wait=10
    until systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1; do
        if [[ "$active_waited" -ge "$active_max_wait" ]]; then
            break
        fi
        sleep 1
        active_waited=$((active_waited + 1))
    done
    systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1
else
    echo "Agent Mail: systemctl --user unavailable, using background fallback" >&2
    launch_agent_mail_fallback
fi
EOF
)"

    _stack_run_as_user "$service_cmd"
}

# Wait for the managed Agent Mail service to become healthy.
_stack_wait_for_agent_mail_health() {
    local waited=0
    local max_wait=30

    until _stack_agent_mail_healthy && _stack_agent_mail_readiness; do
        if [[ "$waited" -ge "$max_wait" ]]; then
            return 1
        fi
        sleep 2
        waited=$((waited + 2))
    done

    return 0
}

# Check if a stack tool is installed
_stack_is_installed() {
    local tool="$1"
    local cmd="${STACK_COMMANDS[$tool]:-}"

    if [[ -z "$cmd" ]]; then
        return 1
    fi

    _stack_target_has_command "$cmd"
}

# PCR is only fully installed once both the hook binary and Claude settings entry exist.
_stack_pcr_installed() {
    local target_home=""
    target_home="$(_stack_target_home "${TARGET_USER:-ubuntu}")"
    local hook_script="$target_home/.local/bin/claude-post-compact-reminder"
    local settings_file="$target_home/.claude/settings.json"
    local alt_settings_file="$target_home/.config/claude/settings.json"
    local pcr_command_pattern='(^|[[:space:]/])claude-post-compact-reminder([[:space:]]|$)'

    [[ -x "$hook_script" ]] || return 1

    if _stack_claude_settings_has_command_hook "$settings_file" "$pcr_command_pattern"; then
        return 0
    fi

    if _stack_claude_settings_has_command_hook "$alt_settings_file" "$pcr_command_pattern"; then
        return 0
    fi

    return 1
}

# Some stack tools are only "ready" when their managed service or config is in place.
_stack_tool_ready() {
    local tool="$1"

    case "$tool" in
        mcp_agent_mail)
            _stack_is_installed "$tool" && _stack_agent_mail_ready
            ;;
        pcr)
            _stack_pcr_installed
            ;;
        *)
            _stack_is_installed "$tool"
            ;;
    esac
}

# ============================================================
# Individual Tool Installers
# ============================================================

# Install NTM (Named Tmux Manager)
# Agent orchestration cockpit
install_ntm() {
    local tool="ntm"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install MCP Agent Mail
# Agent coordination server
install_mcp_agent_mail() {
    local tool="mcp_agent_mail"
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_stack_target_home "$target_user")"
    local target_dir="$target_home/mcp_agent_mail"

    if _stack_tool_ready "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed and healthy"
        return 0
    fi

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed; ensuring managed service"
    else
        log_detail "Installing ${STACK_NAMES[$tool]}..."
        if ! _stack_run_installer "$tool" --dest "$target_dir" --yes; then
            log_warn "${STACK_NAMES[$tool]} installation may have failed"
            return 1
        fi
    fi

    if _stack_repair_agent_mail_cli_symlink; then
        log_detail "${STACK_NAMES[$tool]}: ensured am resolves to $target_dir/am"
    fi

    if ! _stack_is_installed "$tool"; then
        log_warn "${STACK_NAMES[$tool]} CLI missing after install"
        return 1
    fi

    if ! _stack_configure_agent_mail_service; then
        log_warn "${STACK_NAMES[$tool]} installed but managed service setup failed"
        return 1
    fi

    if ! _stack_wait_for_agent_mail_health; then
        log_warn "${STACK_NAMES[$tool]} installed but service did not become healthy on http://127.0.0.1:8765"
        return 1
    fi

    log_success "${STACK_NAMES[$tool]} installed and running on http://127.0.0.1:8765"
    return 0
}

# Install Ultimate Bug Scanner (UBS)
# Bug scanning with guardrails
install_ubs() {
    local tool="ubs"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    # UBS uses --easy-mode for simplified setup
    # Also add --yes for non-interactive installs if needed by UBS installer
    local -a args=(--easy-mode)
    if ! _stack_is_interactive; then
        args+=(--yes)
    fi

    if _stack_run_installer "$tool" "${args[@]}"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install Beads Viewer (BV)
# Task management TUI
install_bv() {
    local tool="bv"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install Beads Rust (BR)
# Local-first issue tracker CLI
install_beads_rust() {
    local tool="br"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install CASS (Coding Agent Session Search)
# Unified session search
install_cass() {
    local tool="cass"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    # CASS uses --easy-mode --verify for simplified setup with verification
    if _stack_run_installer "$tool" --easy-mode --verify; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install CM (CASS Memory System)
# Procedural memory for agents
install_cm() {
    local tool="cm"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    # CM uses --easy-mode --verify for simplified setup with verification
    if _stack_run_installer "$tool" --easy-mode --verify; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install CAAM (Coding Agent Account Manager)
# Auth switching
install_caam() {
    local tool="caam"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install SLB (Simultaneous Launch Button)
# Two-person rule for dangerous commands
install_slb() {
    local tool="slb"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    # SLB upstream installer is broken due to module path mismatch
    # Build from source instead
    local slb_build_cmd
    slb_build_cmd="$(cat <<'EOF'
set -euo pipefail
mkdir -p "$HOME/go/bin"
SLB_TMP="$(mktemp -d "${TMPDIR:-/tmp}/slb_build.XXXXXX")"
trap 'rm -rf "$SLB_TMP"' EXIT
cd "$SLB_TMP"
git clone --depth 1 https://github.com/Dicklesworthstone/simultaneous_launch_button.git .
go build -o "$HOME/go/bin/slb" ./cmd/slb

# Add ~/go/bin to PATH if not already present
acfs_has_active_go_bin_path() {
  local file="${1:-}"
  [[ -f "$file" ]] || return 1

  awk '
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*(export[[:space:]]+)?PATH[[:space:]]*=/ && index($0, "$HOME/go/bin") { found=1; exit }
      END { exit(found ? 0 : 1) }
  ' "$file" 2>/dev/null
}

if ! acfs_has_active_go_bin_path ~/.zshrc; then
  echo '' >> ~/.zshrc
  echo '# Go binaries' >> ~/.zshrc
  echo 'export PATH="$HOME/go/bin:$PATH"' >> ~/.zshrc
fi
EOF
)"

    if _stack_run_as_user "$slb_build_cmd"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install RU (Repo Updater)
# Multi-repo sync + AI automation
install_ru() {
    local tool="ru"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    # RU uses an environment variable, not CLI flags, for unattended install.
    if _stack_run_verified_installer_with_env "$tool" "RU_NON_INTERACTIVE=1"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install DCG (Destructive Command Guard)
# Blocks dangerous commands
install_dcg() {
    local tool="dcg"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    # DCG uses --easy-mode
    local -a args=(--easy-mode)
    if ! _stack_is_interactive; then
        args+=(--yes)
    fi

    if _stack_run_installer "$tool" "${args[@]}"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            
            # Register hook if Claude Code is present
            if _stack_target_has_command claude; then
                log_detail "Registering DCG hook..."
                _stack_run_as_user "dcg install --force" || log_warn "Failed to register DCG hook"
            fi
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install RCH (Remote Compilation Helper)
# Build offloading daemon
install_rch() {
    local tool="rch"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool" --easy-mode; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install PT (Process Triage)
# Bayesian process cleanup
install_pt() {
    local tool="pt"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install Frankensearch (fsfs)
# Hybrid search engine
install_fsfs() {
    local tool="fsfs"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_fsfs_installer --easy-mode; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install SBH (Storage Ballast Helper)
# Disk pressure defense daemon
install_sbh() {
    local tool="sbh"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install CASR (Cross-Agent Session Resumer)
# Cross-provider session handoff
install_casr() {
    local tool="casr"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install DSR (Doodlestein Self-Releaser)
# Fallback release infrastructure
install_dsr() {
    local tool="dsr"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_verified_installer "$tool" --easy-mode; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install ASB (Agent Settings Backup)
# Agent config backup tool
install_asb() {
    local tool="asb"

    if _stack_is_installed "$tool"; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool"; then
        if _stack_is_installed "$tool"; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# Install PCR (Post-Compact Reminder)
# Claude Code hook for AGENTS.md re-read after compaction
install_pcr() {
    local tool="pcr"
    if _stack_pcr_installed; then
        log_detail "${STACK_NAMES[$tool]} already installed"
        return 0
    fi

    if ! _stack_target_has_command claude; then
        log_detail "Skipping ${STACK_NAMES[$tool]} because Claude Code is not installed"
        return 0
    fi

    log_detail "Installing ${STACK_NAMES[$tool]}..."

    if _stack_run_installer "$tool" --yes; then
        if _stack_pcr_installed; then
            log_success "${STACK_NAMES[$tool]} installed"
            return 0
        fi
    fi

    log_warn "${STACK_NAMES[$tool]} installation may have failed"
    return 1
}

# ============================================================
# Verification Functions
# ============================================================

# Verify all stack tools are installed
verify_stack() {
    local all_pass=true
    local installed_count=0
    local total_count=${#STACK_COMMANDS[@]}

    log_detail "Verifying Dicklesworthstone stack..."

    for tool in ntm mcp_agent_mail ubs bv br cass cm caam slb ru dcg rch pt fsfs sbh casr dsr asb pcr; do
        local cmd="${STACK_COMMANDS[$tool]}"
        local name="${STACK_NAMES[$tool]}"

        if _stack_tool_ready "$tool"; then
            log_detail "  $cmd: installed"
            ((installed_count += 1))
        else
            log_warn "  Not ready: $cmd ($name)"
            all_pass=false
        fi
    done

    if [[ "$all_pass" == "true" ]]; then
        log_success "All $total_count stack tools verified"
        return 0
    else
        log_warn "Stack: $installed_count/$total_count tools installed"
        return 1
    fi
}

# Check if stack tools respond to --help
verify_stack_help() {
    local failures=()

    log_detail "Testing stack tools --help..."

    for tool in ntm mcp_agent_mail ubs bv br cass cm caam slb ru dcg rch pt fsfs sbh casr dsr asb pcr; do
        local cmd="${STACK_COMMANDS[$tool]}"

        if _stack_is_installed "$tool"; then
            if ! _stack_run_as_user "$cmd --help >/dev/null 2>&1"; then
                failures+=("$cmd")
            fi
        fi
    done

    if [[ ${#failures[@]} -gt 0 ]]; then
        log_warn "Stack tools --help failed: ${failures[*]}"
        return 1
    fi

    log_success "All stack tools respond to --help"
    return 0
}

# Get versions of installed stack tools (for doctor output)
get_stack_versions() {
    echo "Dicklesworthstone Stack Versions:"

    for tool in ntm mcp_agent_mail ubs bv br cass cm caam slb ru dcg rch pt fsfs sbh casr dsr asb pcr; do
        local cmd="${STACK_COMMANDS[$tool]}"
        local name="${STACK_NAMES[$tool]}"

        if _stack_is_installed "$tool"; then
            local version
            version=$(_stack_run_as_user "$cmd --version 2>/dev/null" || echo "installed")
            echo "  $cmd: $version"
        fi
    done
}

# ============================================================
# Main Installation Function
# ============================================================

# Install all stack tools (called by install.sh)
install_all_stack() {
    log_step "7/8" "Installing Dicklesworthstone stack..."

    # Install in recommended order (original 10 tools)
    install_ntm
    install_mcp_agent_mail
    install_ubs
    install_bv
    install_beads_rust
    install_cass
    install_cm
    install_caam
    install_slb
    install_ru
    install_dcg

    # Additional tools (8 new integrations)
    install_rch
    install_pt
    install_fsfs
    install_sbh
    install_casr
    install_dsr
    install_asb
    install_pcr

    # Verify installation
    verify_stack

    log_success "Dicklesworthstone stack installation complete"
}

# ============================================================
# Module can be sourced or run directly
# ============================================================

# If run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_all_stack "$@"
fi
