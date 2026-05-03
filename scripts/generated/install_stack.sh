#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Resolve relative helper paths first.
ACFS_GENERATED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure logging functions available
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"
else
    # Fallback logging functions if logging.sh not found
    # Progress/status output should go to stderr so stdout stays clean for piping.
    log_step() { echo "[*] $*" >&2; }
    log_section() { echo "" >&2; echo "=== $* ===" >&2; }
    log_success() { echo "[OK] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "    $*" >&2; }
fi

# Source install helpers (run_as_*_shell, selection helpers)
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/install_helpers.sh"
fi

acfs_generated_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1

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

acfs_generated_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(acfs_generated_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(acfs_generated_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

acfs_generated_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(acfs_generated_system_binary_path getent 2>/dev/null || true)"
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

acfs_generated_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    if [[ -n "$passwd_home" ]] && [[ "$passwd_home" == /* ]] && [[ "$passwd_home" != "/" ]]; then
        printf '%s\n' "${passwd_home%/}"
        return 0
    fi

    return 1
}

# When running a generated installer directly (not sourced by install.sh),
# set sane defaults and derive ACFS paths from the script location so
# contract validation passes and local assets are discoverable.
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    # Match install.sh defaults
    if [[ -z "${TARGET_USER:-}" ]]; then
        if [[ $EUID -eq 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
            _ACFS_DETECTED_USER="ubuntu"
        else
            _ACFS_DETECTED_USER="${SUDO_USER:-}"
            if [[ -z "$_ACFS_DETECTED_USER" ]]; then
                _ACFS_DETECTED_USER="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
            fi
            if [[ -z "$_ACFS_DETECTED_USER" ]]; then
                log_error "Unable to resolve the current user for TARGET_USER"
                exit 1
            fi
        fi
        TARGET_USER="$_ACFS_DETECTED_USER"
    fi
    unset _ACFS_DETECTED_USER

    if declare -f _acfs_validate_target_user >/dev/null 2>&1; then
        _acfs_validate_target_user "${TARGET_USER}" "TARGET_USER" || exit 1
    elif [[ -z "${TARGET_USER:-}" ]] || [[ ! "${TARGET_USER}" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        log_error "Invalid TARGET_USER '${TARGET_USER:-<empty>}' (expected: lowercase user name like 'ubuntu')"
        exit 1
    fi

    MODE="${MODE:-vibe}"

    _ACFS_EXPLICIT_TARGET_HOME="${TARGET_HOME:-}"
    if [[ -n "$_ACFS_EXPLICIT_TARGET_HOME" ]]; then
        _ACFS_EXPLICIT_TARGET_HOME="${_ACFS_EXPLICIT_TARGET_HOME%/}"
    fi
    _ACFS_RESOLVED_TARGET_HOME=""
    if declare -f _acfs_resolve_target_home >/dev/null 2>&1; then
        _ACFS_RESOLVED_TARGET_HOME="$(_acfs_resolve_target_home "${TARGET_USER}" "$_ACFS_EXPLICIT_TARGET_HOME" || true)"
    else
        if [[ "${TARGET_USER}" == "root" ]]; then
            _ACFS_RESOLVED_TARGET_HOME="/root"
        else
            _acfs_passwd_entry="$(acfs_generated_getent_passwd_entry "${TARGET_USER}" 2>/dev/null || true)"
            if [[ -n "$_acfs_passwd_entry" ]]; then
                _ACFS_RESOLVED_TARGET_HOME="$(acfs_generated_passwd_home_from_entry "$_acfs_passwd_entry" 2>/dev/null || true)"
            else
                _acfs_current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
                _acfs_current_home="${HOME:-}"
                if [[ -n "$_acfs_current_home" ]]; then
                    _acfs_current_home="${_acfs_current_home%/}"
                fi
                if [[ "${_acfs_current_user:-}" == "${TARGET_USER}" ]] && [[ -n "$_acfs_current_home" ]] && [[ "$_acfs_current_home" == /* ]] && [[ "$_acfs_current_home" != "/" ]] && { [[ -z "$_ACFS_EXPLICIT_TARGET_HOME" ]] || [[ "$_acfs_current_home" == "$_ACFS_EXPLICIT_TARGET_HOME" ]]; }; then
                    _ACFS_RESOLVED_TARGET_HOME="$_acfs_current_home"
                fi
                unset _acfs_current_user _acfs_current_home
            fi
            unset _acfs_passwd_entry
        fi
    fi
    if [[ -n "$_ACFS_RESOLVED_TARGET_HOME" ]]; then
        TARGET_HOME="${_ACFS_RESOLVED_TARGET_HOME%/}"
    fi
    unset _ACFS_EXPLICIT_TARGET_HOME _ACFS_RESOLVED_TARGET_HOME

    if [[ -z "${TARGET_HOME:-}" ]] || [[ "${TARGET_HOME}" == "/" ]] || [[ "${TARGET_HOME}" != /* ]]; then
        log_error "Invalid TARGET_HOME for '${TARGET_USER}': ${TARGET_HOME:-<empty>} (must be an absolute path and cannot be '/')"
        exit 1
    fi

    # Derive "bootstrap" paths from the repo layout (scripts/generated/.. -> repo root).
    if [[ -z "${ACFS_BOOTSTRAP_DIR:-}" ]]; then
        ACFS_BOOTSTRAP_DIR="$(cd "$ACFS_GENERATED_SCRIPT_DIR/../.." && pwd)"
    fi

    ACFS_BIN_DIR="${ACFS_BIN_DIR:-$TARGET_HOME/.local/bin}"
    if [[ -z "${ACFS_BIN_DIR:-}" ]] || [[ "${ACFS_BIN_DIR}" == "/" ]] || [[ "${ACFS_BIN_DIR}" != /* ]]; then
        log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${ACFS_BIN_DIR:-<empty>})"
        exit 1
    fi
    ACFS_LIB_DIR="${ACFS_LIB_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/lib}"
    ACFS_GENERATED_DIR="${ACFS_GENERATED_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/generated}"
    ACFS_ASSETS_DIR="${ACFS_ASSETS_DIR:-$ACFS_BOOTSTRAP_DIR/acfs}"
    ACFS_CHECKSUMS_YAML="${ACFS_CHECKSUMS_YAML:-$ACFS_BOOTSTRAP_DIR/checksums.yaml}"
    ACFS_MANIFEST_YAML="${ACFS_MANIFEST_YAML:-$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml}"

    export TARGET_USER TARGET_HOME MODE ACFS_BIN_DIR
    export ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML
fi

# Source contract validation
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/contract.sh"
fi

# Optional security verification for upstream installer scripts.
# Scripts that need it should call: acfs_security_init
ACFS_SECURITY_READY=false
acfs_security_init() {
    if [[ "${ACFS_SECURITY_READY}" = "true" ]]; then
        return 0
    fi

    local security_lib="$ACFS_GENERATED_SCRIPT_DIR/../lib/security.sh"
    if [[ ! -f "$security_lib" ]]; then
        log_error "Security library not found: $security_lib"
        return 1
    fi

    # Use ACFS_CHECKSUMS_YAML if set by install.sh bootstrap (overrides security.sh default)
    if [[ -n "${ACFS_CHECKSUMS_YAML:-}" ]]; then
        export CHECKSUMS_FILE="${ACFS_CHECKSUMS_YAML}"
    fi

    # shellcheck source=../lib/security.sh
    # shellcheck disable=SC1091  # runtime relative source
    source "$security_lib"
    load_checksums || { log_error "Failed to load checksums.yaml"; return 1; }
    ACFS_SECURITY_READY=true
    return 0
}

# Category: stack
# Modules: 25

# Named tmux manager (agent cockpit)
install_stack_ntm() {
    local module_id="stack.ntm"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.ntm"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.ntm"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="ntm"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.ntm: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--no-shell'; then
                            install_success=true
                        else
                            log_error "stack.ntm: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.ntm: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.ntm: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.ntm: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.ntm: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.ntm"
                false
            fi
        }; then
            log_error "stack.ntm: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ntm --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_NTM'
ntm --help
INSTALL_STACK_NTM
        then
            log_error "stack.ntm: verify failed: ntm --help"
            return 1
        fi
    fi

    log_success "stack.ntm installed"
}

# Like gmail for coding agents; MCP HTTP server + token; installs beads tools
install_stack_mcp_agent_mail() {
    local module_id="stack.mcp_agent_mail"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.mcp_agent_mail"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.mcp_agent_mail"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="mcp_agent_mail"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.mcp_agent_mail: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--dest' "$TARGET_HOME"'/mcp_agent_mail' '--yes'; then
                            install_success=true
                        else
                            log_error "stack.mcp_agent_mail: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.mcp_agent_mail: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.mcp_agent_mail: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.mcp_agent_mail: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.mcp_agent_mail: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.mcp_agent_mail"
                false
            fi
        }; then
            log_error "stack.mcp_agent_mail: verified installer failed"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if ! command -v am >/dev/null 2>&1; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_MCP_AGENT_MAIL'
if ! command -v am >/dev/null 2>&1; then
  echo "Agent Mail CLI missing after install" >&2
  exit 1
fi
storage_root="$HOME/.mcp_agent_mail_git_mailbox_repo"
unit_dir="$HOME/.config/systemd/user"
unit_file="$unit_dir/agent-mail.service"
am_bin="$(command -v am)"
db_url="sqlite:///${storage_root}/storage.sqlite3"

# Detect MCP base path: Rust am uses /mcp/, Python mcp_agent_mail uses /api/
if "$am_bin" --version 2>/dev/null | grep -q '^am '; then
    am_mcp_path="/mcp/"
else
    am_mcp_path="/api/"
fi

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

mkdir -p "$storage_root" "$unit_dir"
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

# Pre-check: determine if systemctl --user is usable.  On fresh VPS
# installs run from root, /run/user/<uid> may exist (created by
# install.sh Phase 1) but the D-Bus session bus may not be up yet.
_systemctl_user_ok=false
if command -v systemctl >/dev/null 2>&1; then
  if ! systemctl --user show-environment >/dev/null 2>&1; then
    # Try setting DBUS_SESSION_BUS_ADDRESS to trigger socket activation
    if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
      export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
    fi
    systemctl --user show-environment >/dev/null 2>&1 && _systemctl_user_ok=true
  else
    _systemctl_user_ok=true
  fi
fi

fallback_pid_file="$storage_root/agent-mail.pid"
fallback_log_file="$storage_root/agent-mail.log"

agent_mail_service_curl() {
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
  if agent_mail_service_curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; then
    return 0
  fi

  if [[ -f "$fallback_pid_file" ]]; then
    existing_pid="$(cat "$fallback_pid_file" 2>/dev/null || true)"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null && \
       ps -p "$existing_pid" -o args= 2>/dev/null | grep -Fq "$am_bin serve-http"; then
      return 0
    fi
    rm -f "$fallback_pid_file"
  fi

  nohup env \
    RUST_LOG=info \
    STORAGE_ROOT="$storage_root" \
    DATABASE_URL="$db_url" \
    HTTP_PATH="$am_mcp_path" \
    "$am_bin" serve-http --host 127.0.0.1 --port 8765 --path "$am_mcp_path" --no-auth --no-tui \
    >>"$fallback_log_file" 2>&1 < /dev/null &
  echo $! > "$fallback_pid_file"
}

if [[ "$_systemctl_user_ok" = "true" ]]; then
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
INSTALL_STACK_MCP_AGENT_MAIL
        then
            log_error "stack.mcp_agent_mail: install command failed: if ! command -v am >/dev/null 2>&1; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: until agent_mail_service_curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; do (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_MCP_AGENT_MAIL'
# Wait for the managed Agent Mail service to become healthy.
agent_mail_service_curl() {
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

waited=0
max_wait=30
until agent_mail_service_curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; do
  if [[ "$waited" -ge "$max_wait" ]]; then
    echo "Agent Mail service did not become healthy on 127.0.0.1:8765 after ${max_wait}s" >&2
    exit 1
  fi
  sleep 2
  waited=$((waited + 2))
done
INSTALL_STACK_MCP_AGENT_MAIL
        then
            log_error "stack.mcp_agent_mail: install command failed: until agent_mail_service_curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; do"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v am (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_MCP_AGENT_MAIL'
command -v am
INSTALL_STACK_MCP_AGENT_MAIL
        then
            log_error "stack.mcp_agent_mail: verify failed: command -v am"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: if [[ -d \"\$runtime_dir\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_MCP_AGENT_MAIL'
agent_mail_service_curl() {
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

runtime_dir="/run/user/$(id -u)"
if [[ -d "$runtime_dir" ]]; then
  export XDG_RUNTIME_DIR="$runtime_dir"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
fi
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1 || exit 1
fi
agent_mail_service_curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null
INSTALL_STACK_MCP_AGENT_MAIL
        then
            log_error "stack.mcp_agent_mail: verify failed: if [[ -d \"\$runtime_dir\" ]]; then"
            return 1
        fi
    fi

    log_success "stack.mcp_agent_mail installed"
}

# Local-first knowledge management with hybrid semantic search (ms)
install_stack_meta_skill() {
    local module_id="stack.meta_skill"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.meta_skill"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.meta_skill"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            # meta_skill has no prebuilt Linux ARM64 release asset yet; build from source there.
            if [[ "$(uname -s 2>/dev/null)" == "Linux" ]] && { [[ "$(uname -m 2>/dev/null)" == "aarch64" ]] || [[ "$(uname -m 2>/dev/null)" == "arm64" ]]; }; then
                log_info "stack.meta_skill: Linux ARM64 detected; building meta_skill from source"
                if run_as_target_shell "command -v cargo >/dev/null 2>&1 && cargo install --git https://github.com/Dicklesworthstone/meta_skill --force"; then
                    install_success=true
                else
                    log_error "stack.meta_skill: cargo source install failed for Linux ARM64"
                fi
            else
                if acfs_security_init; then
                    # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                    # The grep ensures we specifically have an associative array, not just any variable
                    if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                        local tool="ms"
                        local url=""
                        local expected_sha256=""

                        # Safe access with explicit empty default
                        url="${KNOWN_INSTALLERS[$tool]:-}"
                        if ! expected_sha256="$(get_checksum "$tool")"; then
                            log_error "stack.meta_skill: get_checksum failed for tool '$tool'"
                            expected_sha256=""
                        fi

                        if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                            if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                                install_success=true
                            else
                                log_error "stack.meta_skill: verify_checksum or installer execution failed"
                            fi
                        else
                            if [[ -z "$url" ]]; then
                                log_error "stack.meta_skill: KNOWN_INSTALLERS[$tool] not found"
                            fi
                            if [[ -z "$expected_sha256" ]]; then
                                log_error "stack.meta_skill: checksum for '$tool' not found"
                            fi
                        fi
                    else
                        log_error "stack.meta_skill: KNOWN_INSTALLERS array not available"
                    fi
                else
                    log_error "stack.meta_skill: acfs_security_init failed - check security.sh and checksums.yaml"
                fi
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.meta_skill"
                false
            fi
        }; then
            log_error "stack.meta_skill: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ms --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_META_SKILL'
ms --version
INSTALL_STACK_META_SKILL
        then
            log_error "stack.meta_skill: verify failed: ms --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): ms doctor (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_META_SKILL'
ms doctor
INSTALL_STACK_META_SKILL
        then
            log_warn "Optional verify failed: stack.meta_skill"
        fi
    fi

    log_success "stack.meta_skill installed"
}

# Automated iterative spec refinement with extended AI reasoning (apr)
install_stack_automated_plan_reviser() {
    local module_id="stack.automated_plan_reviser"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.automated_plan_reviser"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.automated_plan_reviser"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="apr"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.automated_plan_reviser: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.automated_plan_reviser: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.automated_plan_reviser: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.automated_plan_reviser: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.automated_plan_reviser: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.automated_plan_reviser: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.automated_plan_reviser"
                false
            fi
        }; then
            log_warn "stack.automated_plan_reviser: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.automated_plan_reviser" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.automated_plan_reviser"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: apr --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_AUTOMATED_PLAN_REVISER'
apr --help
INSTALL_STACK_AUTOMATED_PLAN_REVISER
        then
            log_warn "stack.automated_plan_reviser: verify failed: apr --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.automated_plan_reviser" "verify failed: apr --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.automated_plan_reviser"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): apr --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_AUTOMATED_PLAN_REVISER'
apr --version
INSTALL_STACK_AUTOMATED_PLAN_REVISER
        then
            log_warn "Optional verify failed: stack.automated_plan_reviser"
        fi
    fi

    log_success "stack.automated_plan_reviser installed"
}

# Curated battle-tested prompts for AI agents - browse and install as skills (jfp)
install_stack_jeffreysprompts() {
    local module_id="stack.jeffreysprompts"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.jeffreysprompts"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.jeffreysprompts"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="jfp"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.jeffreysprompts: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.jeffreysprompts: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.jeffreysprompts: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.jeffreysprompts: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.jeffreysprompts: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.jeffreysprompts: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.jeffreysprompts"
                false
            fi
        }; then
            log_warn "stack.jeffreysprompts: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.jeffreysprompts" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.jeffreysprompts"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: jfp --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_JEFFREYSPROMPTS'
jfp --version
INSTALL_STACK_JEFFREYSPROMPTS
        then
            log_warn "stack.jeffreysprompts: verify failed: jfp --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.jeffreysprompts" "verify failed: jfp --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.jeffreysprompts"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): jfp doctor (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_JEFFREYSPROMPTS'
jfp doctor
INSTALL_STACK_JEFFREYSPROMPTS
        then
            log_warn "Optional verify failed: stack.jeffreysprompts"
        fi
    fi

    log_success "stack.jeffreysprompts installed"
}

# Find and terminate stuck/zombie processes with intelligent scoring (pt)
install_stack_process_triage() {
    local module_id="stack.process_triage"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.process_triage"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.process_triage"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="pt"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.process_triage: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.process_triage: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.process_triage: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.process_triage: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.process_triage: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.process_triage: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.process_triage"
                false
            fi
        }; then
            log_warn "stack.process_triage: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.process_triage" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.process_triage"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: pt --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_PROCESS_TRIAGE'
pt --help
INSTALL_STACK_PROCESS_TRIAGE
        then
            log_warn "stack.process_triage: verify failed: pt --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.process_triage" "verify failed: pt --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.process_triage"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): pt --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_PROCESS_TRIAGE'
pt --version
INSTALL_STACK_PROCESS_TRIAGE
        then
            log_warn "Optional verify failed: stack.process_triage"
        fi
    fi

    log_success "stack.process_triage installed"
}

# UBS bug scanning (easy-mode)
install_stack_ultimate_bug_scanner() {
    local module_id="stack.ultimate_bug_scanner"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.ultimate_bug_scanner"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.ultimate_bug_scanner"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="ubs"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.ultimate_bug_scanner: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.ultimate_bug_scanner: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.ultimate_bug_scanner: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.ultimate_bug_scanner: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.ultimate_bug_scanner: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.ultimate_bug_scanner: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.ultimate_bug_scanner"
                false
            fi
        }; then
            log_error "stack.ultimate_bug_scanner: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ubs --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_ULTIMATE_BUG_SCANNER'
ubs --help
INSTALL_STACK_ULTIMATE_BUG_SCANNER
        then
            log_error "stack.ultimate_bug_scanner: verify failed: ubs --help"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): cd /tmp && ubs doctor (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_ULTIMATE_BUG_SCANNER'
cd /tmp && ubs doctor
INSTALL_STACK_ULTIMATE_BUG_SCANNER
        then
            log_warn "Optional verify failed: stack.ultimate_bug_scanner"
        fi
    fi

    log_success "stack.ultimate_bug_scanner installed"
}

# beads_rust (br) - Rust issue tracker with graph-aware dependencies
install_stack_beads_rust() {
    local module_id="stack.beads_rust"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.beads_rust"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.beads_rust"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="br"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.beads_rust: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.beads_rust: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.beads_rust: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.beads_rust: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.beads_rust: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.beads_rust: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.beads_rust"
                false
            fi
        }; then
            log_error "stack.beads_rust: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: br --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BEADS_RUST'
br --version
INSTALL_STACK_BEADS_RUST
        then
            log_error "stack.beads_rust: verify failed: br --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): br list --json 2>/dev/null (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BEADS_RUST'
br list --json 2>/dev/null
INSTALL_STACK_BEADS_RUST
        then
            log_warn "Optional verify failed: stack.beads_rust"
        fi
    fi

    log_success "stack.beads_rust installed"
}

# bv TUI for Beads tasks
install_stack_beads_viewer() {
    local module_id="stack.beads_viewer"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.beads_viewer"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.beads_viewer"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="bv"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.beads_viewer: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.beads_viewer: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.beads_viewer: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.beads_viewer: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.beads_viewer: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.beads_viewer: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.beads_viewer"
                false
            fi
        }; then
            log_error "stack.beads_viewer: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: bv --help || bv --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BEADS_VIEWER'
bv --help || bv --version
INSTALL_STACK_BEADS_VIEWER
        then
            log_error "stack.beads_viewer: verify failed: bv --help || bv --version"
            return 1
        fi
    fi

    log_success "stack.beads_viewer installed"
}

# Unified search across agent session history
install_stack_cass() {
    local module_id="stack.cass"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.cass"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.cass"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="cass"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.cass: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode' '--verify'; then
                            install_success=true
                        else
                            log_error "stack.cass: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.cass: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.cass: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.cass: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.cass: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.cass"
                false
            fi
        }; then
            log_error "stack.cass: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: cass --help || cass --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CASS'
cass --help || cass --version
INSTALL_STACK_CASS
        then
            log_error "stack.cass: verify failed: cass --help || cass --version"
            return 1
        fi
    fi

    log_success "stack.cass installed"
}

# Procedural memory for agents (cass-memory)
install_stack_cm() {
    local module_id="stack.cm"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.cm"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.cm"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="cm"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.cm: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode' '--verify'; then
                            install_success=true
                        else
                            log_error "stack.cm: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.cm: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.cm: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.cm: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.cm: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.cm"
                false
            fi
        }; then
            log_error "stack.cm: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: cm --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CM'
cm --version
INSTALL_STACK_CM
        then
            log_error "stack.cm: verify failed: cm --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify (optional): cm doctor --json (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CM'
cm doctor --json
INSTALL_STACK_CM
        then
            log_warn "Optional verify failed: stack.cm"
        fi
    fi

    log_success "stack.cm installed"
}

# Instant auth switching for agent CLIs
install_stack_caam() {
    local module_id="stack.caam"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.caam"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.caam"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="caam"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.caam: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.caam: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.caam: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.caam: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.caam: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.caam: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.caam"
                false
            fi
        }; then
            log_error "stack.caam: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: caam status || caam --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CAAM'
caam status || caam --help
INSTALL_STACK_CAAM
        then
            log_error "stack.caam: verify failed: caam status || caam --help"
            return 1
        fi
    fi

    log_success "stack.caam installed"
}

# Two-person rule for dangerous commands (optional guardrails)
install_stack_slb() {
    local module_id="stack.slb"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.slb"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/go/bin (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_SLB'
mkdir -p ~/go/bin
SLB_TMP="$(mktemp -d "${TMPDIR:-/tmp}/slb_build.XXXXXX")"
trap 'rm -rf "$SLB_TMP"' EXIT
cd "$SLB_TMP"
git clone --depth 1 https://github.com/Dicklesworthstone/simultaneous_launch_button.git .
go build -o ~/go/bin/slb ./cmd/slb
cd ..
rm -rf "$SLB_TMP"
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
INSTALL_STACK_SLB
        then
            log_warn "stack.slb: install command failed: mkdir -p ~/go/bin"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.slb" "install command failed: mkdir -p ~/go/bin"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.slb"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: export PATH=\"\$HOME/go/bin:\$PATH\" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1 (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_SLB'
export PATH="$HOME/go/bin:$PATH" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1
INSTALL_STACK_SLB
        then
            log_warn "stack.slb: verify failed: export PATH=\"\$HOME/go/bin:\$PATH\" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.slb" "verify failed: export PATH=\"\$HOME/go/bin:\$PATH\" && slb >/dev/null 2>&1 || slb --help >/dev/null 2>&1"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.slb"
            fi
            return 0
        fi
    fi

    log_success "stack.slb installed"
}

# Destructive Command Guard - Claude Code hook blocking dangerous git/fs commands
install_stack_dcg() {
    local module_id="stack.dcg"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.dcg"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.dcg"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="dcg"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.dcg: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.dcg: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.dcg: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.dcg: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.dcg: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.dcg: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.dcg"
                false
            fi
        }; then
            log_error "stack.dcg: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: dcg --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_DCG'
dcg --version
INSTALL_STACK_DCG
        then
            log_error "stack.dcg: verify failed: dcg --version"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: claude_settings_has_command_hook \"\$settings\" \"\$dcg_command_pattern\" || (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_DCG'
claude_settings_has_command_hook() {
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

settings="$HOME/.claude/settings.json"
alt_settings="$HOME/.config/claude/settings.json"
dcg_command_pattern='(^|[[:space:]/])dcg([[:space:]]|$)'

claude_settings_has_command_hook "$settings" "$dcg_command_pattern" ||
  claude_settings_has_command_hook "$alt_settings" "$dcg_command_pattern"
INSTALL_STACK_DCG
        then
            log_error "stack.dcg: verify failed: claude_settings_has_command_hook \"\$settings\" \"\$dcg_command_pattern\" ||"
            return 1
        fi
    fi

    log_success "stack.dcg installed"
}

# Repo Updater - multi-repo sync + AI-driven commit automation
install_stack_ru() {
    local module_id="stack.ru"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.ru"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.ru"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="ru"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.ru: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'env' 'RU_NON_INTERACTIVE=1' 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.ru: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.ru: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.ru: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.ru: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.ru: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.ru"
                false
            fi
        }; then
            log_error "stack.ru: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ru --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_RU'
ru --version
INSTALL_STACK_RU
        then
            log_error "stack.ru: verify failed: ru --version"
            return 1
        fi
    fi

    log_success "stack.ru installed"
}

# Brenner Bot - research session manager with hypothesis tracking
install_stack_brenner_bot() {
    local module_id="stack.brenner_bot"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.brenner_bot"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.brenner_bot"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="brenner_bot"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.brenner_bot: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--skip-cass'; then
                            install_success=true
                        else
                            log_error "stack.brenner_bot: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.brenner_bot: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.brenner_bot: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.brenner_bot: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.brenner_bot: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.brenner_bot"
                false
            fi
        }; then
            log_warn "stack.brenner_bot: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.brenner_bot" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.brenner_bot"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: brenner --version || brenner --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_BRENNER_BOT'
brenner --version || brenner --help
INSTALL_STACK_BRENNER_BOT
        then
            log_warn "stack.brenner_bot: verify failed: brenner --version || brenner --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.brenner_bot" "verify failed: brenner --version || brenner --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.brenner_bot"
            fi
            return 0
        fi
    fi

    log_success "stack.brenner_bot installed"
}

# Remote Compilation Helper - transparent build offloading for AI coding agents
install_stack_rch() {
    local module_id="stack.rch"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.rch"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.rch"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="rch"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.rch: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.rch: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.rch: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.rch: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.rch: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.rch: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.rch"
                false
            fi
        }; then
            log_warn "stack.rch: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.rch" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.rch"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: rch --version || rch --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_RCH'
rch --version || rch --help
INSTALL_STACK_RCH
        then
            log_warn "stack.rch: verify failed: rch --version || rch --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.rch" "verify failed: rch --version || rch --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.rch"
            fi
            return 0
        fi
    fi

    log_success "stack.rch installed"
}

# WezTerm Automata (wa) - terminal automation and orchestration for AI agents
install_stack_wezterm_automata() {
    local module_id="stack.wezterm_automata"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.wezterm_automata"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -rf \"\$WA_TMP\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_WEZTERM_AUTOMATA'
WA_TMP="$(mktemp -d "${TMPDIR:-/tmp}/wa_build.XXXXXX")"
trap 'rm -rf "$WA_TMP"' EXIT
cd "$WA_TMP"
git clone --depth 1 https://github.com/Dicklesworthstone/wezterm_automata.git .
cargo build --release -p wa
cp target/release/wa ~/.cargo/bin/
rm -rf "$WA_TMP"
INSTALL_STACK_WEZTERM_AUTOMATA
        then
            log_warn "stack.wezterm_automata: install command failed: trap 'rm -rf \"\$WA_TMP\"' EXIT"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.wezterm_automata" "install command failed: trap 'rm -rf \"\$WA_TMP\"' EXIT"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.wezterm_automata"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: wa --version || wa --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_WEZTERM_AUTOMATA'
wa --version || wa --help
INSTALL_STACK_WEZTERM_AUTOMATA
        then
            log_warn "stack.wezterm_automata: verify failed: wa --version || wa --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.wezterm_automata" "verify failed: wa --version || wa --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.wezterm_automata"
            fi
            return 0
        fi
    fi

    log_success "stack.wezterm_automata installed"
}

# System Resource Protection Script - ananicy-cpp rules + TUI monitor for responsive dev workstations
install_stack_srps() {
    local module_id="stack.srps"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.srps"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.srps"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="srps"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.srps: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--install'; then
                            install_success=true
                        else
                            log_error "stack.srps: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.srps: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.srps: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.srps: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.srps: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.srps"
                false
            fi
        }; then
            log_warn "stack.srps: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.srps" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.srps"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v sysmoni (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_SRPS'
command -v sysmoni
INSTALL_STACK_SRPS
        then
            log_warn "stack.srps: verify failed: command -v sysmoni"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.srps" "verify failed: command -v sysmoni"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.srps"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: systemctl is-active ananicy-cpp (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_SRPS'
systemctl is-active ananicy-cpp
INSTALL_STACK_SRPS
        then
            log_warn "stack.srps: verify failed: systemctl is-active ananicy-cpp"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.srps" "verify failed: systemctl is-active ananicy-cpp"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.srps"
            fi
            return 0
        fi
    fi

    log_success "stack.srps installed"
}

# Two-tier hybrid local search — lexical (BM25) + semantic retrieval with progressive delivery (fsfs)
install_stack_frankensearch() {
    local module_id="stack.frankensearch"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.frankensearch"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.frankensearch"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="fsfs"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.frankensearch: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        local -a fsfs_installer_args=('--easy-mode')
                        local fsfs_arch=""
                        local fsfs_target=""
                        local fsfs_version=""
                        local fsfs_version_bare=""
                        local fsfs_artifact_url=""
                        local fsfs_checksum=""
                        local fsfs_candidate=""
                        local -a fsfs_candidates=()
                        local fsfs_can_run=true

                        if [[ "$(uname -s 2>/dev/null)" == "Linux" ]]; then
                            fsfs_arch="$(uname -m 2>/dev/null || true)"
                            case "$fsfs_arch" in
                                x86_64|amd64) fsfs_target="x86_64-unknown-linux-musl" ;;
                                aarch64|arm64) fsfs_target="aarch64-unknown-linux-musl" ;;
                                *) fsfs_target="" ;;
                            esac

                            if [[ -z "$fsfs_target" ]]; then
                                fsfs_can_run=false
                                log_warn "stack.frankensearch: FrankenSearch Linux binary artifact unavailable for this architecture; skipping source-build fallback"
                            else
                                if [[ -n "${ACFS_FSFS_VERSION:-}" ]]; then
                                    fsfs_candidates+=("$ACFS_FSFS_VERSION")
                                else
                                    while IFS= read -r fsfs_candidate; do
                                        [[ -n "$fsfs_candidate" ]] || continue
                                        case " ${fsfs_candidates[*]} " in
                                            *" $fsfs_candidate "*) ;;
                                            *) fsfs_candidates+=("$fsfs_candidate") ;;
                                        esac
                                    done < <(curl -fsSL --connect-timeout 30 --max-time 60 -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/Dicklesworthstone/frankensearch/releases?per_page=10" 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true)

                                    fsfs_candidate="$(curl -fsSL --connect-timeout 30 --max-time 60 -o /dev/null -w '%{url_effective}' "https://github.com/Dicklesworthstone/frankensearch/releases/latest" 2>/dev/null | sed -E 's|.*/tag/||' || true)"
                                    if [[ "$fsfs_candidate" =~ ^v[0-9][A-Za-z0-9._-]*$ ]]; then
                                        case " ${fsfs_candidates[*]} " in
                                            *" $fsfs_candidate "*) ;;
                                            *) fsfs_candidates+=("$fsfs_candidate") ;;
                                        esac
                                    fi
                                fi

                                if [[ ${#fsfs_candidates[@]} -eq 0 ]]; then
                                    fsfs_can_run=false
                                    log_warn "stack.frankensearch: unable to resolve FrankenSearch release; skipping source-build fallback"
                                else
                                    for fsfs_version in "${fsfs_candidates[@]}"; do
                                        [[ "$fsfs_version" =~ ^v[0-9][A-Za-z0-9._-]*$ ]] || continue
                                        fsfs_version_bare="${fsfs_version#v}"
                                        fsfs_artifact_url="https://github.com/Dicklesworthstone/frankensearch/releases/download/${fsfs_version}/fsfs-lite-${fsfs_version_bare}-${fsfs_target}.tar.xz"
                                        fsfs_checksum="$(curl -fsSL --connect-timeout 30 --max-time 60 "${fsfs_artifact_url}.sha256" 2>/dev/null | awk 'NR == 1 { print $1 }' || true)"
                                        if [[ "$fsfs_checksum" =~ ^[0-9A-Fa-f]{64}$ ]]; then
                                            fsfs_installer_args+=(
                                                --version "$fsfs_version"
                                                --artifact-url "$fsfs_artifact_url"
                                                --checksum "${fsfs_checksum,,}"
                                            )
                                            log_info "stack.frankensearch: using FrankenSearch Linux lite artifact $fsfs_artifact_url"
                                            break
                                        fi
                                        log_warn "stack.frankensearch: FrankenSearch lite artifact checksum unavailable for $fsfs_version"
                                    done
                                    if [[ ! "$fsfs_checksum" =~ ^[0-9A-Fa-f]{64}$ ]]; then
                                        fsfs_can_run=false
                                        log_warn "stack.frankensearch: unable to resolve a FrankenSearch lite artifact with a checksum; skipping source-build fallback"
                                    fi
                                fi
                            fi
                        fi

                        if [[ "$fsfs_can_run" == "true" ]]; then
                            if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' "${fsfs_installer_args[@]}"; then
                                install_success=true
                            else
                                log_error "stack.frankensearch: verify_checksum or installer execution failed"
                            fi
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.frankensearch: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.frankensearch: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.frankensearch: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.frankensearch: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.frankensearch"
                false
            fi
        }; then
            log_warn "stack.frankensearch: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.frankensearch" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.frankensearch"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: fsfs version || fsfs --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_FRANKENSEARCH'
fsfs version || fsfs --help
INSTALL_STACK_FRANKENSEARCH
        then
            log_warn "stack.frankensearch: verify failed: fsfs version || fsfs --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.frankensearch" "verify failed: fsfs version || fsfs --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.frankensearch"
            fi
            return 0
        fi
    fi

    log_success "stack.frankensearch installed"
}

# Cross-platform disk-pressure defense for AI coding workloads (sbh)
install_stack_storage_ballast_helper() {
    local module_id="stack.storage_ballast_helper"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.storage_ballast_helper"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.storage_ballast_helper"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="sbh"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.storage_ballast_helper: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.storage_ballast_helper: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.storage_ballast_helper: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.storage_ballast_helper: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.storage_ballast_helper: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.storage_ballast_helper: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.storage_ballast_helper"
                false
            fi
        }; then
            log_warn "stack.storage_ballast_helper: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.storage_ballast_helper" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.storage_ballast_helper"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v sbh (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_STORAGE_BALLAST_HELPER'
command -v sbh
INSTALL_STACK_STORAGE_BALLAST_HELPER
        then
            log_warn "stack.storage_ballast_helper: verify failed: command -v sbh"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.storage_ballast_helper" "verify failed: command -v sbh"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.storage_ballast_helper"
            fi
            return 0
        fi
    fi

    log_success "stack.storage_ballast_helper installed"
}

# Cross-provider AI coding session resumption — convert and resume sessions across providers (casr)
install_stack_cross_agent_session_resumer() {
    local module_id="stack.cross_agent_session_resumer"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.cross_agent_session_resumer"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.cross_agent_session_resumer"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="casr"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.cross_agent_session_resumer: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.cross_agent_session_resumer: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.cross_agent_session_resumer: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.cross_agent_session_resumer: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.cross_agent_session_resumer: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.cross_agent_session_resumer: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.cross_agent_session_resumer"
                false
            fi
        }; then
            log_warn "stack.cross_agent_session_resumer: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.cross_agent_session_resumer" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.cross_agent_session_resumer"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: casr providers || casr --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_CROSS_AGENT_SESSION_RESUMER'
casr providers || casr --help
INSTALL_STACK_CROSS_AGENT_SESSION_RESUMER
        then
            log_warn "stack.cross_agent_session_resumer: verify failed: casr providers || casr --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.cross_agent_session_resumer" "verify failed: casr providers || casr --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.cross_agent_session_resumer"
            fi
            return 0
        fi
    fi

    log_success "stack.cross_agent_session_resumer installed"
}

# Fallback release infrastructure — local builds via act when GitHub Actions is throttled (dsr)
install_stack_doodlestein_self_releaser() {
    local module_id="stack.doodlestein_self_releaser"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.doodlestein_self_releaser"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.doodlestein_self_releaser"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="dsr"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.doodlestein_self_releaser: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                            install_success=true
                        else
                            log_error "stack.doodlestein_self_releaser: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.doodlestein_self_releaser: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.doodlestein_self_releaser: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.doodlestein_self_releaser: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.doodlestein_self_releaser: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.doodlestein_self_releaser"
                false
            fi
        }; then
            log_warn "stack.doodlestein_self_releaser: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.doodlestein_self_releaser" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.doodlestein_self_releaser"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: dsr --version || dsr --help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_DOODLESTEIN_SELF_RELEASER'
dsr --version || dsr --help
INSTALL_STACK_DOODLESTEIN_SELF_RELEASER
        then
            log_warn "stack.doodlestein_self_releaser: verify failed: dsr --version || dsr --help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.doodlestein_self_releaser" "verify failed: dsr --version || dsr --help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.doodlestein_self_releaser"
            fi
            return 0
        fi
    fi

    log_success "stack.doodlestein_self_releaser installed"
}

# Smart backup tool for AI coding agent configuration folders (asb)
install_stack_agent_settings_backup() {
    local module_id="stack.agent_settings_backup"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.agent_settings_backup"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.agent_settings_backup"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="asb"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.agent_settings_backup: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "stack.agent_settings_backup: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.agent_settings_backup: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.agent_settings_backup: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.agent_settings_backup: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.agent_settings_backup: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.agent_settings_backup"
                false
            fi
        }; then
            log_warn "stack.agent_settings_backup: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.agent_settings_backup" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.agent_settings_backup"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ -d \"\$backup_root\" ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_AGENT_SETTINGS_BACKUP'
backup_root="${ASB_BACKUP_ROOT:-$HOME/.agent_settings_backups}"
existing_backup_repo=""

if [[ -d "$backup_root" ]]; then
  existing_backup_repo="$(find "$backup_root" -mindepth 2 -maxdepth 2 -name .git -print -quit 2>/dev/null || true)"
fi

if [[ -n "$existing_backup_repo" ]]; then
  echo "ASB backup history already exists at $backup_root" >&2
else
  if asb backup; then
    echo "ASB initial backup created at $backup_root" >&2
  else
    echo "WARN: ASB initial backup failed; continuing without a seeded backup repo" >&2
  fi
fi

cron_status="$(asb schedule --status --cron 2>&1 || true)"
systemd_status="$(asb schedule --status --systemd 2>&1 || true)"
cron_missing=false
systemd_missing=false

if printf '%s' "$cron_status" | grep -q "No cron schedule found"; then
  cron_missing=true
fi
if printf '%s' "$systemd_status" | grep -q "Systemd timer is not enabled"; then
  systemd_missing=true
fi

if [[ "$cron_missing" == "true" && "$systemd_missing" == "true" ]]; then
  if asb schedule --cron --interval daily >/dev/null 2>&1; then
    echo "ASB scheduled backups enabled via cron (daily)." >&2
  else
    echo "WARN: ASB scheduled backup setup failed; continuing without automation" >&2
  fi
fi

echo "ASB backup root: $backup_root" >&2
INSTALL_STACK_AGENT_SETTINGS_BACKUP
        then
            log_warn "stack.agent_settings_backup: install command failed: if [[ -d \"\$backup_root\" ]]; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.agent_settings_backup" "install command failed: if [[ -d \"\$backup_root\" ]]; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.agent_settings_backup"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: asb version || asb help (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_AGENT_SETTINGS_BACKUP'
asb version || asb help
INSTALL_STACK_AGENT_SETTINGS_BACKUP
        then
            log_warn "stack.agent_settings_backup: verify failed: asb version || asb help"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.agent_settings_backup" "verify failed: asb version || asb help"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.agent_settings_backup"
            fi
            return 0
        fi
    fi

    log_success "stack.agent_settings_backup installed"
}

# Post-compaction reminder hook for Claude Code that forces an AGENTS.md re-read
install_stack_pcr() {
    local module_id="stack.pcr"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing stack.pcr"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: pre-install check: command -v claude >/dev/null 2>&1 (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_PCR_PRE_INSTALL_CHECK'
command -v claude >/dev/null 2>&1
INSTALL_STACK_PCR_PRE_INSTALL_CHECK
        then
            log_warn "stack.pcr: Skipping PCR - Claude Code not found"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.pcr" "Skipping PCR - Claude Code not found"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.pcr"
            fi
            return 0
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: stack.pcr"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="pcr"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "stack.pcr: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--yes'; then
                            install_success=true
                        else
                            log_error "stack.pcr: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "stack.pcr: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "stack.pcr: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "stack.pcr: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "stack.pcr: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for stack.pcr"
                false
            fi
        }; then
            log_warn "stack.pcr: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.pcr" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.pcr"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -x \"\$hook_script\" || exit 1 (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_STACK_PCR'
claude_settings_has_command_hook() {
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

target_home="${TARGET_HOME:-$HOME}"
hook_script="$target_home/.local/bin/claude-post-compact-reminder"
settings="$target_home/.claude/settings.json"
alt_settings="$target_home/.config/claude/settings.json"
pcr_command_pattern='(^|[[:space:]/])claude-post-compact-reminder([[:space:]]|$)'

test -x "$hook_script" || exit 1

claude_settings_has_command_hook "$settings" "$pcr_command_pattern" ||
  claude_settings_has_command_hook "$alt_settings" "$pcr_command_pattern"
INSTALL_STACK_PCR
        then
            log_warn "stack.pcr: verify failed: test -x \"\$hook_script\" || exit 1"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "stack.pcr" "verify failed: test -x \"\$hook_script\" || exit 1"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "stack.pcr"
            fi
            return 0
        fi
    fi

    log_success "stack.pcr installed"
}

# Install all stack modules
install_stack() {
    log_section "Installing stack modules"
    install_stack_ntm
    install_stack_mcp_agent_mail
    install_stack_meta_skill
    install_stack_automated_plan_reviser
    install_stack_jeffreysprompts
    install_stack_process_triage
    install_stack_ultimate_bug_scanner
    install_stack_beads_rust
    install_stack_beads_viewer
    install_stack_cass
    install_stack_cm
    install_stack_caam
    install_stack_slb
    install_stack_dcg
    install_stack_ru
    install_stack_brenner_bot
    install_stack_rch
    install_stack_wezterm_automata
    install_stack_srps
    install_stack_frankensearch
    install_stack_storage_ballast_helper
    install_stack_cross_agent_session_resumer
    install_stack_doodlestein_self_releaser
    install_stack_agent_settings_backup
    install_stack_pcr
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_stack
fi
