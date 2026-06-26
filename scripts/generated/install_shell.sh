#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
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

acfs_generated_target_user_exists() {
    local user="${1:-}"
    local id_bin=""

    [[ -n "$user" ]] || return 1
    id_bin="$(acfs_generated_system_binary_path id 2>/dev/null || true)"
    [[ -n "$id_bin" ]] || return 1
    "$id_bin" "$user" >/dev/null 2>&1
}

acfs_generated_default_home_for_new_user() {
    local user="${1:-}"

    [[ -n "$user" ]] || return 1
    [[ "$user" =~ ^[a-z_][a-z0-9._-]*$ ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    printf '/home/%s\n' "$user"
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
    if [[ -z "$_ACFS_RESOLVED_TARGET_HOME" ]] && [[ $EUID -eq 0 ]] && ! acfs_generated_target_user_exists "${TARGET_USER}"; then
        if [[ -n "$_ACFS_EXPLICIT_TARGET_HOME" ]] && [[ "$_ACFS_EXPLICIT_TARGET_HOME" == /* ]] && [[ "$_ACFS_EXPLICIT_TARGET_HOME" != "/" ]]; then
            _ACFS_RESOLVED_TARGET_HOME="$_ACFS_EXPLICIT_TARGET_HOME"
        else
            _ACFS_RESOLVED_TARGET_HOME="$(acfs_generated_default_home_for_new_user "${TARGET_USER}" 2>/dev/null || true)"
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

    # Defensive ownership repair (#306): when running as root, make sure the
    # target user owns their XDG bin dir before the user-space language
    # installers (uv/rust/bun) write into it. uv installs via an atomic
    # mktemp+rename inside ~/.local/bin, so a root-owned ~/.local/bin makes its
    # mktemp fail with "Permission denied (os error 13)" once the installer is
    # re-exec'd as the (non-root) target user. The chown is NON-recursive on
    # purpose — only the two directories themselves, never their contents (never
    # chown -R ~/.local, which would clobber ownership of unrelated state).
    if [[ $EUID -eq 0 ]] && [[ -n "${TARGET_USER:-}" ]] && [[ "${TARGET_USER}" != "root" ]]; then
        _acfs_repair_mkdir="$(_acfs_system_binary_path mkdir 2>/dev/null || true)"
        _acfs_repair_chown="$(_acfs_system_binary_path chown 2>/dev/null || true)"
        if [[ -n "$_acfs_repair_mkdir" ]] && [[ -n "$_acfs_repair_chown" ]]; then
            if "$_acfs_repair_mkdir" -p "$TARGET_HOME/.local/bin" 2>/dev/null; then
                "$_acfs_repair_chown" "${TARGET_USER}" "$TARGET_HOME/.local" "$TARGET_HOME/.local/bin" 2>/dev/null || true
            fi
        fi
        unset _acfs_repair_mkdir _acfs_repair_chown
    fi
fi

acfs_generated_ensure_selection() {
    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        local manifest_index="${ACFS_GENERATED_DIR:-$ACFS_GENERATED_SCRIPT_DIR}/manifest_index.sh"
        if [[ ! -f "$manifest_index" ]]; then
            log_error "Manifest index not found: $manifest_index"
            return 1
        fi
        source "$manifest_index"
        ACFS_MANIFEST_INDEX_LOADED=true
        export ACFS_MANIFEST_INDEX_LOADED
    fi

    if [[ "${ACFS_GENERATED_SELECTION_READY:-false}" != "true" ]]; then
        if ! declare -f acfs_resolve_selection >/dev/null 2>&1; then
            log_error "Install selection helper not loaded"
            return 1
        fi
        acfs_resolve_selection || return 1
        ACFS_GENERATED_SELECTION_READY=true
        export ACFS_GENERATED_SELECTION_READY
    fi

    return 0
}

acfs_generated_should_run_module() {
    local module_id="${1:-}"
    [[ -n "$module_id" ]] || return 1
    acfs_generated_ensure_selection || return 1
    should_run_module "$module_id"
}

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

# Category: shell
# Modules: 2

# Zsh shell package
install_shell_zsh() {
    local module_id="shell.zsh"
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping shell.zsh (not selected)"
        return 0
    fi
    log_step "Installing shell.zsh"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: apt-get install -y zsh (root)"
    else
        if ! run_as_root_shell <<'INSTALL_SHELL_ZSH'
apt-get install -y zsh
INSTALL_SHELL_ZSH
        then
            log_error "shell.zsh: install command failed: apt-get install -y zsh"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: zsh --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_SHELL_ZSH'
zsh --version
INSTALL_SHELL_ZSH
        then
            log_error "shell.zsh: verify failed: zsh --version"
            return 1
        fi
    fi

    log_success "shell.zsh installed"
}

# Oh My Zsh + Powerlevel10k + plugins + ACFS config
install_shell_omz() {
    local module_id="shell.omz"
    acfs_require_contract "module:${module_id}" || return 1
    acfs_generated_ensure_selection || return 1
    if ! should_run_module "${module_id}"; then
        log_info "Skipping shell.omz (not selected)"
        return 0
    fi
    log_step "Installing shell.omz"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: shell.omz"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                local known_installers_decl=""
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                known_installers_decl="$(declare -p KNOWN_INSTALLERS 2>/dev/null || true)"
                if [[ "$known_installers_decl" == declare\ -A* ]]; then
                    local tool="ohmyzsh"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "shell.omz: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'sh' '-s' '--' '--unattended' '--keep-zshrc'; then
                            install_success=true
                        else
                            log_error "shell.omz: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "shell.omz: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "shell.omz: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "shell.omz: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "shell.omz: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for shell.omz"
                false
            fi
        }; then
            log_error "shell.omz: verified installer failed"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -d ~/.oh-my-zsh/custom/themes/powerlevel10k ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install Powerlevel10k
if [[ ! -d ~/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ ! -d ~/.oh-my-zsh/custom/themes/powerlevel10k ]]; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install zsh-autosuggestions
if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install zsh-syntax-highlighting
if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]]; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/.acfs/zsh (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install ACFS zshrc
ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF:-main}}"
mkdir -p ~/.acfs/zsh
CURL_ARGS=(-fsSL)
if curl --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi
curl "${CURL_ARGS[@]}" -o ~/.acfs/zsh/acfs.zshrc "${ACFS_RAW}/acfs/zsh/acfs.zshrc"
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: mkdir -p ~/.acfs/zsh"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: mkdir -p ~/.acfs/completions (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install ACFS shell completions (zsh)
ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF:-main}}"
mkdir -p ~/.acfs/completions
CURL_ARGS=(-fsSL)
if curl --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi
curl "${CURL_ARGS[@]}" -o ~/.acfs/completions/_acfs "${ACFS_RAW}/scripts/completions/_acfs"
# Also install bash completions for users who switch shells
curl "${CURL_ARGS[@]}" -o ~/.acfs/completions/acfs.bash "${ACFS_RAW}/scripts/completions/acfs.bash"
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: mkdir -p ~/.acfs/completions"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if curl --help all 2>/dev/null | grep -q -- '--proto'; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install pre-configured Powerlevel10k settings (prevents config wizard on first login)
ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${ACFS_REF:-main}}"
CURL_ARGS=(-fsSL)
if curl --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
fi
curl "${CURL_ARGS[@]}" -o ~/.p10k.zsh "${ACFS_RAW}/acfs/zsh/p10k.zsh"
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if curl --help all 2>/dev/null | grep -q -- '--proto'; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ -f ~/.zshrc ]] && ! acfs_zshrc_is_managed_loader ~/.zshrc; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Setup loader .zshrc
acfs_zshrc_is_managed_loader() {
  local file="${1:-}"

  [[ -f "$file" ]] || return 1
  awk '
    /^[[:space:]]*$/ { next }
    { lines[++line_count]=$0 }
    END {
      if (line_count == 2 &&
          lines[1] ~ /^# ACFS loader/ &&
          lines[2] == "source \"$HOME/.acfs/zsh/acfs.zshrc\"") {
        exit 0
      }
      exit 1
    }
  ' "$file" 2>/dev/null
}

if [[ -f ~/.zshrc ]] && ! acfs_zshrc_is_managed_loader ~/.zshrc; then
  mv ~/.zshrc ~/.zshrc.bak.$(date +%s)
fi
echo '# ACFS loader' > ~/.zshrc
echo 'source "$HOME/.acfs/zsh/acfs.zshrc"' >> ~/.zshrc
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ -f ~/.zshrc ]] && ! acfs_zshrc_is_managed_loader ~/.zshrc; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -f ~/.profile ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Setup ~/.profile for bash login shells (prevents PATH warnings from installers)
profile_path_has_fragment() {
  local file="${1:-}"
  local fragment="${2:-}"

  [[ -n "$file" && -n "$fragment" && -f "$file" ]] || return 1
  awk -v fragment="$fragment" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*(export[[:space:]]+)?PATH[[:space:]]*=/ && index($0, fragment) { found=1; exit }
    END { exit(found ? 0 : 1) }
  ' "$file" 2>/dev/null
}

legacy_profile_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"'
profile_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
if [[ ! -f ~/.profile ]]; then
  echo '# ~/.profile: executed by bash for login shells' > ~/.profile
  echo '' >> ~/.profile
  echo '# User binary paths' >> ~/.profile
  echo "$profile_path_line" >> ~/.profile
elif grep -Fxq "$legacy_profile_path_line" ~/.profile; then
  sed -i "s|^$(printf '%s' "$legacy_profile_path_line" | sed 's/[][\\.^$*|]/\\&/g')$|$profile_path_line|" ~/.profile
elif ! profile_path_has_fragment ~/.profile '.local/bin' || ! profile_path_has_fragment ~/.profile '.atuin/bin'; then
  echo '' >> ~/.profile
  echo '# Added by ACFS - user binary paths' >> ~/.profile
  echo "$profile_path_line" >> ~/.profile
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ ! -f ~/.profile ]]; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ ! -f ~/.zprofile ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Setup ~/.zprofile for zsh login shells (zsh does NOT read ~/.profile)
profile_path_has_fragment() {
  local file="${1:-}"
  local fragment="${2:-}"

  [[ -n "$file" && -n "$fragment" && -f "$file" ]] || return 1
  awk -v fragment="$fragment" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*(export[[:space:]]+)?PATH[[:space:]]*=/ && index($0, fragment) { found=1; exit }
    END { exit(found ? 0 : 1) }
  ' "$file" 2>/dev/null
}

legacy_profile_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"'
profile_path_line='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$PATH"'
if [[ ! -f ~/.zprofile ]]; then
  echo '# ~/.zprofile: executed by zsh for login shells' > ~/.zprofile
  echo '' >> ~/.zprofile
  echo '# User binary paths' >> ~/.zprofile
  echo "$profile_path_line" >> ~/.zprofile
elif grep -Fxq "$legacy_profile_path_line" ~/.zprofile; then
  sed -i "s|^$(printf '%s' "$legacy_profile_path_line" | sed 's/[][\\.^$*|]/\\&/g')$|$profile_path_line|" ~/.zprofile
elif ! profile_path_has_fragment ~/.zprofile '.local/bin' || ! profile_path_has_fragment ~/.zprofile '.atuin/bin'; then
  echo '' >> ~/.zprofile
  echo '# Added by ACFS - user binary paths' >> ~/.zprofile
  echo "$profile_path_line" >> ~/.zprofile
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ ! -f ~/.zprofile ]]; then"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if [[ \"\$SHELL\" != */zsh ]]; then (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Generated helper functions used by this child shell.
acfs_generated_system_binary_path() {
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

acfs_generated_target_user_exists() {
    local user="${1:-}"
    local id_bin=""

    [[ -n "$user" ]] || return 1
    id_bin="$(acfs_generated_system_binary_path id 2>/dev/null || true)"
    [[ -n "$id_bin" ]] || return 1
    "$id_bin" "$user" >/dev/null 2>&1
}

acfs_generated_default_home_for_new_user() {
    local user="${1:-}"

    [[ -n "$user" ]] || return 1
    [[ "$user" =~ ^[a-z_][a-z0-9._-]*$ ]] || return 1

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    printf '/home/%s\n' "$user"
}

# Set default shell
acfs_external_shell_handoff_configured() {
  local bashrc_path="${1:-}"
  [[ -n "$bashrc_path" && -f "$bashrc_path" ]] || return 1

  awk '
      $0 == "# ACFS externally-managed shell handoff" { marker=1; next }
      marker && $0 ~ /^[[:space:]]*#/ { next }
      marker && index($0, "command -v zsh") && index($0, "ACFS_ZSH_HANDOFF_ACTIVE") { found=1; exit }
      marker && $0 !~ /^[[:space:]]*$/ { marker=0 }
      END { exit(found ? 0 : 1) }
  ' "$bashrc_path" 2>/dev/null
}

if [[ "$SHELL" != */zsh ]]; then
  zsh_path="$(command -v zsh || true)"
  if [[ -z "$zsh_path" ]]; then
    echo "WARN: zsh not found; cannot set default shell automatically." >&2
    exit 0
  fi
  current_user="$(acfs_generated_resolve_current_user 2>/dev/null || true)"
  if [[ -z "$current_user" ]]; then
    echo "WARN: Unable to resolve current user; skipping default shell change." >&2
    exit 0
  fi
  passwd_entry="$(acfs_generated_getent_passwd_entry "$current_user" 2>/dev/null || true)"
  local_entry=""
  if [[ -r /etc/passwd ]]; then
    local_entry="$(awk -F: -v user="$current_user" '$1 == user { print $0; exit }' /etc/passwd 2>/dev/null || true)"
  fi
  if [[ -n "$passwd_entry" ]] && [[ -z "$local_entry" ]]; then
    if ! acfs_external_shell_handoff_configured ~/.bashrc; then
      if [[ -f ~/.bashrc ]] && [[ -s ~/.bashrc ]]; then
        last_char="$(tail -c 1 ~/.bashrc | od -An -t u1 | tr -d ' ' 2>/dev/null || true)"
        if [[ "$last_char" != "10" ]]; then
          printf '\n' >> ~/.bashrc
        fi
      fi
      {
        echo '# ACFS externally-managed shell handoff'
        echo 'if [[ $- == *i* ]] && [[ -t 0 ]] && command -v zsh >/dev/null 2>&1 && [[ -z "${ACFS_ZSH_HANDOFF_ACTIVE:-}" ]]; then'
        echo '  export ACFS_ZSH_HANDOFF_ACTIVE=1'
        echo '  exec "$(command -v zsh)" -l'
        echo 'fi'
      } >> ~/.bashrc
    fi
    echo "WARN: $current_user is managed outside /etc/passwd; installed a bash-to-zsh handoff instead of using chsh." >&2
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo chsh -s "$zsh_path" "$current_user"
  else
    if [[ -t 0 ]]; then
      if ! chsh -s "$zsh_path"; then
        echo "WARN: Could not change default shell automatically. Run: chsh -s $zsh_path" >&2
      fi
    else
      echo "WARN: Skipping shell change (no TTY). Run: chsh -s $zsh_path" >&2
    fi
  fi
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: if [[ \"\$SHELL\" != */zsh ]]; then"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -d ~/.oh-my-zsh (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
test -d ~/.oh-my-zsh
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: verify failed: test -d ~/.oh-my-zsh"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -f ~/.acfs/zsh/acfs.zshrc (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
test -f ~/.acfs/zsh/acfs.zshrc
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: verify failed: test -f ~/.acfs/zsh/acfs.zshrc"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: test -f ~/.p10k.zsh (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
test -f ~/.p10k.zsh
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: verify failed: test -f ~/.p10k.zsh"
            return 1
        fi
    fi

    log_success "shell.omz installed"
}

# Install all shell modules
install_shell() {
    log_section "Installing shell modules"
    install_shell_zsh
    install_shell_omz
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_shell
fi
