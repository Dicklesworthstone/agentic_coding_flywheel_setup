#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Ensure logging functions available
ACFS_GENERATED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# When running a generated installer directly (not sourced by install.sh),
# set sane defaults and derive ACFS paths from the script location so
# contract validation passes and local assets are discoverable.
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    # Match install.sh defaults
    if [[ -z "${TARGET_USER:-}" ]]; then
        if [[ $EUID -eq 0 ]] && [[ -z "${SUDO_USER:-}" ]]; then
            _ACFS_DETECTED_USER="ubuntu"
        else
            _ACFS_DETECTED_USER="${SUDO_USER:-$(whoami)}"
        fi
        TARGET_USER="$_ACFS_DETECTED_USER"
    fi
    unset _ACFS_DETECTED_USER
    MODE="${MODE:-vibe}"

    if [[ -z "${TARGET_HOME:-}" ]]; then
        if [[ "${TARGET_USER}" == "root" ]]; then
            TARGET_HOME="/root"
        elif [[ "$(whoami 2>/dev/null || true)" == "${TARGET_USER}" ]]; then
            TARGET_HOME="${HOME}"
        else
            TARGET_HOME="/home/${TARGET_USER}"
        fi
    fi

    # Derive "bootstrap" paths from the repo layout (scripts/generated/.. -> repo root).
    if [[ -z "${ACFS_BOOTSTRAP_DIR:-}" ]]; then
        ACFS_BOOTSTRAP_DIR="$(cd "$ACFS_GENERATED_SCRIPT_DIR/../.." && pwd)"
    fi

    ACFS_LIB_DIR="${ACFS_LIB_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/lib}"
    ACFS_GENERATED_DIR="${ACFS_GENERATED_DIR:-$ACFS_BOOTSTRAP_DIR/scripts/generated}"
    ACFS_ASSETS_DIR="${ACFS_ASSETS_DIR:-$ACFS_BOOTSTRAP_DIR/acfs}"
    ACFS_CHECKSUMS_YAML="${ACFS_CHECKSUMS_YAML:-$ACFS_BOOTSTRAP_DIR/checksums.yaml}"
    ACFS_MANIFEST_YAML="${ACFS_MANIFEST_YAML:-$ACFS_BOOTSTRAP_DIR/acfs.manifest.yaml}"

    export TARGET_USER TARGET_HOME MODE
    export ACFS_BOOTSTRAP_DIR ACFS_LIB_DIR ACFS_GENERATED_DIR ACFS_ASSETS_DIR ACFS_CHECKSUMS_YAML ACFS_MANIFEST_YAML
fi
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

# Category: tools
# Modules: 16

# Lazygit (apt or binary fallback)
install_tools_lazygit() {
    local module_id="tools.lazygit"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing tools.lazygit"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if apt-get install -y lazygit; then (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_LAZYGIT'
if apt-get install -y lazygit; then
  exit 0
fi
# Fallback to binary install
LG_VER="0.44.1"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) LG_SHA="84682f4ad5a449d0a3ffbc8332200fe8651aee9dd91dcd8d87197ba6c2450dbc" ;;
  aarch64) LG_SHA="26a435f47b691325c086dad2f84daa6556df5af8efc52b6ed624fa657605c976" ;;
  *) echo "Unsupported arch for lazygit binary: $ARCH"; exit 0 ;;
esac

LG_URL="https://github.com/jesseduffield/lazygit/releases/download/v${LG_VER}/lazygit_${LG_VER}_Linux_${ARCH}.tar.gz"
TMP_FILE="$(mktemp)"

curl -fsSL "$LG_URL" -o "$TMP_FILE"
echo "$LG_SHA $TMP_FILE" | sha256sum -c - || { echo "Checksum failed"; rm "$TMP_FILE"; exit 1; }

tar -xzf "$TMP_FILE" -C /usr/local/bin lazygit
chmod +x /usr/local/bin/lazygit
rm "$TMP_FILE"
INSTALL_TOOLS_LAZYGIT
        then
            log_error "tools.lazygit: install command failed: if apt-get install -y lazygit; then"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: lazygit --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_LAZYGIT'
lazygit --version
INSTALL_TOOLS_LAZYGIT
        then
            log_error "tools.lazygit: verify failed: lazygit --version"
            return 1
        fi
    fi

    log_success "tools.lazygit installed"
}

# Lazydocker (binary install)
install_tools_lazydocker() {
    local module_id="tools.lazydocker"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing tools.lazydocker"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: case \"\$ARCH\" in (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_LAZYDOCKER'
LD_VER="0.23.3"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) LD_SHA="1f3c7037326973b85cb85447b2574595103185f8ed067b605dd43cc201bc8786" ;;
  aarch64) LD_SHA="ae7bed0309289396d396b8502b2d78d153a4f8ce8add042f655332241e7eac31" ;;
  *) echo "Unsupported arch for lazydocker binary: $ARCH"; exit 0 ;;
esac

LD_URL="https://github.com/jesseduffield/lazydocker/releases/download/v${LD_VER}/lazydocker_${LD_VER}_Linux_${ARCH}.tar.gz"
TMP_FILE="$(mktemp)"

curl -fsSL "$LD_URL" -o "$TMP_FILE"
echo "$LD_SHA $TMP_FILE" | sha256sum -c - || { echo "Checksum failed"; rm "$TMP_FILE"; exit 1; }

tar -xzf "$TMP_FILE" -C /usr/local/bin lazydocker
chmod +x /usr/local/bin/lazydocker
rm "$TMP_FILE"
INSTALL_TOOLS_LAZYDOCKER
        then
            log_error "tools.lazydocker: install command failed: case \"\$ARCH\" in"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: lazydocker --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_LAZYDOCKER'
lazydocker --version
INSTALL_TOOLS_LAZYDOCKER
        then
            log_error "tools.lazydocker: verify failed: lazydocker --version"
            return 1
        fi
    fi

    log_success "tools.lazydocker installed"
}

# Atuin shell history (Ctrl-R superpowers)
install_tools_atuin() {
    local module_id="tools.atuin"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing tools.atuin"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: tools.atuin"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="atuin"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "tools.atuin: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'sh' '-s' '--' '--non-interactive'; then
                            install_success=true
                        else
                            log_error "tools.atuin: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "tools.atuin: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "tools.atuin: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "tools.atuin: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "tools.atuin: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for tools.atuin"
                false
            fi
        }; then
            log_error "tools.atuin: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: ~/.atuin/bin/atuin --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_TOOLS_ATUIN'
~/.atuin/bin/atuin --version
INSTALL_TOOLS_ATUIN
        then
            log_error "tools.atuin: verify failed: ~/.atuin/bin/atuin --version"
            return 1
        fi
    fi

    log_success "tools.atuin installed"
}

# Zoxide (better cd)
install_tools_zoxide() {
    local module_id="tools.zoxide"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing tools.zoxide"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: tools.zoxide"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="zoxide"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "tools.zoxide: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'sh' '-s'; then
                            install_success=true
                        else
                            log_error "tools.zoxide: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "tools.zoxide: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "tools.zoxide: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "tools.zoxide: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "tools.zoxide: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for tools.zoxide"
                false
            fi
        }; then
            log_error "tools.zoxide: verified installer failed"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: command -v zoxide (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_TOOLS_ZOXIDE'
command -v zoxide
INSTALL_TOOLS_ZOXIDE
        then
            log_error "tools.zoxide: verify failed: command -v zoxide"
            return 1
        fi
    fi

    log_success "tools.zoxide installed"
}

# ast-grep (used by UBS for syntax-aware scanning)
install_tools_ast_grep() {
    local module_id="tools.ast_grep"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing tools.ast_grep"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: ~/.cargo/bin/cargo install ast-grep --locked (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_TOOLS_AST_GREP'
~/.cargo/bin/cargo install ast-grep --locked
INSTALL_TOOLS_AST_GREP
        then
            log_error "tools.ast_grep: install command failed: ~/.cargo/bin/cargo install ast-grep --locked"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: sg --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_TOOLS_AST_GREP'
sg --version
INSTALL_TOOLS_AST_GREP
        then
            log_error "tools.ast_grep: verify failed: sg --version"
            return 1
        fi
    fi

    log_success "tools.ast_grep installed"
}

# HashiCorp Vault CLI
install_tools_vault() {
    local module_id="tools.vault"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing tools.vault"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: if curl --help all 2>/dev/null | grep -q -- '--proto'; then (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_VAULT'
# HashiCorp doesn't always publish packages for newest Ubuntu versions.
# Fall back to noble (24.04 LTS) if the current codename isn't supported.
CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble")

CURL_ARGS=(-fsSL)
CURL_CHECK_ARGS=(-fsSI)
if curl --help all 2>/dev/null | grep -q -- '--proto'; then
  CURL_ARGS=(--proto '=https' --proto-redir '=https' -fsSL)
  CURL_CHECK_ARGS=(--proto '=https' --proto-redir '=https' -fsSI)
fi

if ! curl "${CURL_CHECK_ARGS[@]}" "https://apt.releases.hashicorp.com/dists/${CODENAME}/main/binary-amd64/Packages" >/dev/null 2>&1; then
  CODENAME="noble"
fi

curl "${CURL_ARGS[@]}" https://apt.releases.hashicorp.com/gpg \
  | gpg --batch --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
  > /etc/apt/sources.list.d/hashicorp.list
apt-get update && apt-get install -y vault
INSTALL_TOOLS_VAULT
        then
            log_warn "tools.vault: install command failed: if curl --help all 2>/dev/null | grep -q -- '--proto'; then"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "tools.vault" "install command failed: if curl --help all 2>/dev/null | grep -q -- '--proto'; then"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "tools.vault"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: vault --version (root)"
    else
        if ! run_as_root_shell <<'INSTALL_TOOLS_VAULT'
vault --version
INSTALL_TOOLS_VAULT
        then
            log_warn "tools.vault: verify failed: vault --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "tools.vault" "verify failed: vault --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "tools.vault"
            fi
            return 0
        fi
    fi

    log_success "tools.vault installed"
}

# Get Image from Internet Link - download cloud images for visual debugging
install_utils_giil() {
    local module_id="utils.giil"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing utils.giil"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: utils.giil"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="giil"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "utils.giil: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "utils.giil: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "utils.giil: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "utils.giil: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "utils.giil: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "utils.giil: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for utils.giil"
                false
            fi
        }; then
            log_warn "utils.giil: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.giil" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.giil"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: giil --help || giil --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_UTILS_GIIL'
giil --help || giil --version
INSTALL_UTILS_GIIL
        then
            log_warn "utils.giil: verify failed: giil --help || giil --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.giil" "verify failed: giil --help || giil --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.giil"
            fi
            return 0
        fi
    fi

    log_success "utils.giil installed"
}

# Chat Shared Conversation to File - convert AI share links to Markdown/HTML
install_utils_csctf() {
    local module_id="utils.csctf"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing utils.csctf"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: utils.csctf"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="csctf"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "utils.csctf: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "utils.csctf: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "utils.csctf: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "utils.csctf: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "utils.csctf: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "utils.csctf: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for utils.csctf"
                false
            fi
        }; then
            log_warn "utils.csctf: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.csctf" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.csctf"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: csctf --help || csctf --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_UTILS_CSCTF'
csctf --help || csctf --version
INSTALL_UTILS_CSCTF
        then
            log_warn "utils.csctf: verify failed: csctf --help || csctf --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.csctf" "verify failed: csctf --help || csctf --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.csctf"
            fi
            return 0
        fi
    fi

    log_success "utils.csctf installed"
}

# xf - Ultra-fast X/Twitter archive search with Tantivy
install_utils_xf() {
    local module_id="utils.xf"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing utils.xf"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: utils.xf"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="xf"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "utils.xf: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s' '--' '--easy-mode'; then
                            install_success=true
                        else
                            log_error "utils.xf: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "utils.xf: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "utils.xf: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "utils.xf: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "utils.xf: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for utils.xf"
                false
            fi
        }; then
            log_warn "utils.xf: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.xf" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.xf"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: xf --help || xf --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_UTILS_XF'
xf --help || xf --version
INSTALL_UTILS_XF
        then
            log_warn "utils.xf: verify failed: xf --help || xf --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.xf" "verify failed: xf --help || xf --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.xf"
            fi
            return 0
        fi
    fi

    log_success "utils.xf installed"
}

# toon_rust (tru) - Token-optimized notation format for LLM context efficiency
install_utils_toon_rust() {
    local module_id="utils.toon_rust"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing utils.toon_rust"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: utils.toon_rust"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="tru"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "utils.toon_rust: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "utils.toon_rust: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "utils.toon_rust: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "utils.toon_rust: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "utils.toon_rust: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "utils.toon_rust: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for utils.toon_rust"
                false
            fi
        }; then
            log_warn "utils.toon_rust: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.toon_rust" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.toon_rust"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: tru --help || tru --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_UTILS_TOON_RUST'
tru --help || tru --version
INSTALL_UTILS_TOON_RUST
        then
            log_warn "utils.toon_rust: verify failed: tru --help || tru --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.toon_rust" "verify failed: tru --help || tru --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.toon_rust"
            fi
            return 0
        fi
    fi

    log_success "utils.toon_rust installed"
}

# rano - Network observer for AI CLIs with request/response logging
install_utils_rano() {
    local module_id="utils.rano"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing utils.rano"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: utils.rano"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="rano"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "utils.rano: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "utils.rano: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "utils.rano: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "utils.rano: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "utils.rano: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "utils.rano: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for utils.rano"
                false
            fi
        }; then
            log_warn "utils.rano: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.rano" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.rano"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: rano --help || rano --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_UTILS_RANO'
rano --help || rano --version
INSTALL_UTILS_RANO
        then
            log_warn "utils.rano: verify failed: rano --help || rano --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.rano" "verify failed: rano --help || rano --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.rano"
            fi
            return 0
        fi
    fi

    log_success "utils.rano installed"
}

# markdown_web_browser (mdwb) - Convert websites to Markdown for LLM consumption
install_utils_mdwb() {
    local module_id="utils.mdwb"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing utils.mdwb"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: utils.mdwb"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="mdwb"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "utils.mdwb: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "utils.mdwb: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "utils.mdwb: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "utils.mdwb: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "utils.mdwb: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "utils.mdwb: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for utils.mdwb"
                false
            fi
        }; then
            log_warn "utils.mdwb: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.mdwb" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.mdwb"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: mdwb --help || mdwb --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_UTILS_MDWB'
mdwb --help || mdwb --version
INSTALL_UTILS_MDWB
        then
            log_warn "utils.mdwb: verify failed: mdwb --help || mdwb --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.mdwb" "verify failed: mdwb --help || mdwb --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.mdwb"
            fi
            return 0
        fi
    fi

    log_success "utils.mdwb installed"
}

# source_to_prompt_tui (s2p) - Code to LLM prompt generator with TUI
install_utils_s2p() {
    local module_id="utils.s2p"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing utils.s2p"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verified installer: utils.s2p"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="s2p"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    if ! expected_sha256="$(get_checksum "$tool")"; then
                        log_error "utils.s2p: get_checksum failed for tool '$tool'"
                        expected_sha256=""
                    fi

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" | run_as_target_runner 'bash' '-s'; then
                            install_success=true
                        else
                            log_error "utils.s2p: verify_checksum or installer execution failed"
                        fi
                    else
                        if [[ -z "$url" ]]; then
                            log_error "utils.s2p: KNOWN_INSTALLERS[$tool] not found"
                        fi
                        if [[ -z "$expected_sha256" ]]; then
                            log_error "utils.s2p: checksum for '$tool' not found"
                        fi
                    fi
                else
                    log_error "utils.s2p: KNOWN_INSTALLERS array not available"
                fi
            else
                log_error "utils.s2p: acfs_security_init failed - check security.sh and checksums.yaml"
            fi

            # Verified install is required - no fallback
            if [[ "$install_success" = "true" ]]; then
                true
            else
                log_error "Verified install failed for utils.s2p"
                false
            fi
        }; then
            log_warn "utils.s2p: verified installer failed"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.s2p" "verified installer failed"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.s2p"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: s2p --help || s2p --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_UTILS_S2P'
s2p --help || s2p --version
INSTALL_UTILS_S2P
        then
            log_warn "utils.s2p: verify failed: s2p --help || s2p --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.s2p" "verify failed: s2p --help || s2p --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.s2p"
            fi
            return 0
        fi
    fi

    log_success "utils.s2p installed"
}

# rust_proxy - Transparent proxy routing for debugging network traffic
install_utils_rust_proxy() {
    local module_id="utils.rust_proxy"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing utils.rust_proxy"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -rf \"\$TMPDIR\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_UTILS_RUST_PROXY'
# Build rust_proxy from source (no install.sh available)
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
git clone --depth 1 https://github.com/Dicklesworthstone/rust_proxy.git "$TMPDIR/rust_proxy"
cd "$TMPDIR/rust_proxy"
cargo build --release
cp target/release/rust_proxy ~/.cargo/bin/
INSTALL_UTILS_RUST_PROXY
        then
            log_warn "utils.rust_proxy: install command failed: trap 'rm -rf \"\$TMPDIR\"' EXIT"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.rust_proxy" "install command failed: trap 'rm -rf \"\$TMPDIR\"' EXIT"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.rust_proxy"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: rust_proxy --help || rust_proxy --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_UTILS_RUST_PROXY'
rust_proxy --help || rust_proxy --version
INSTALL_UTILS_RUST_PROXY
        then
            log_warn "utils.rust_proxy: verify failed: rust_proxy --help || rust_proxy --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.rust_proxy" "verify failed: rust_proxy --help || rust_proxy --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.rust_proxy"
            fi
            return 0
        fi
    fi

    log_success "utils.rust_proxy installed"
}

# aadc - ASCII diagram corrector for fixing malformed ASCII art
install_utils_aadc() {
    local module_id="utils.aadc"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing utils.aadc"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -rf \"\$TMPDIR\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_UTILS_AADC'
# Build aadc from source (no install.sh available)
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
git clone --depth 1 https://github.com/Dicklesworthstone/aadc.git "$TMPDIR/aadc"
cd "$TMPDIR/aadc"
cargo build --release
cp target/release/aadc ~/.cargo/bin/
INSTALL_UTILS_AADC
        then
            log_warn "utils.aadc: install command failed: trap 'rm -rf \"\$TMPDIR\"' EXIT"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.aadc" "install command failed: trap 'rm -rf \"\$TMPDIR\"' EXIT"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.aadc"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: aadc --help || aadc --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_UTILS_AADC'
aadc --help || aadc --version
INSTALL_UTILS_AADC
        then
            log_warn "utils.aadc: verify failed: aadc --help || aadc --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.aadc" "verify failed: aadc --help || aadc --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.aadc"
            fi
            return 0
        fi
    fi

    log_success "utils.aadc installed"
}

# coding_agent_usage_tracker (caut) - LLM provider usage tracker
install_utils_caut() {
    local module_id="utils.caut"
    acfs_require_contract "module:${module_id}" || return 1
    log_step "Installing utils.caut"

    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: install: trap 'rm -rf \"\$TMPDIR\"' EXIT (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_UTILS_CAUT'
# Build caut from source (no install.sh available)
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
git clone --depth 1 https://github.com/Dicklesworthstone/coding_agent_usage_tracker.git "$TMPDIR/caut"
cd "$TMPDIR/caut"
cargo build --release
cp target/release/caut ~/.cargo/bin/
INSTALL_UTILS_CAUT
        then
            log_warn "utils.caut: install command failed: trap 'rm -rf \"\$TMPDIR\"' EXIT"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.caut" "install command failed: trap 'rm -rf \"\$TMPDIR\"' EXIT"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.caut"
            fi
            return 0
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" = "true" ]]; then
        log_info "dry-run: verify: caut --help || caut --version (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_UTILS_CAUT'
caut --help || caut --version
INSTALL_UTILS_CAUT
        then
            log_warn "utils.caut: verify failed: caut --help || caut --version"
            if type -t record_skipped_tool >/dev/null 2>&1; then
              record_skipped_tool "utils.caut" "verify failed: caut --help || caut --version"
            elif type -t state_tool_skip >/dev/null 2>&1; then
              state_tool_skip "utils.caut"
            fi
            return 0
        fi
    fi

    log_success "utils.caut installed"
}

# Install all tools modules
install_tools() {
    log_section "Installing tools modules"
    install_tools_lazygit
    install_tools_lazydocker
    install_tools_atuin
    install_tools_zoxide
    install_tools_ast_grep
    install_tools_vault
    install_utils_giil
    install_utils_csctf
    install_utils_xf
    install_utils_toon_rust
    install_utils_rano
    install_utils_mdwb
    install_utils_s2p
    install_utils_rust_proxy
    install_utils_aadc
    install_utils_caut
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    install_tools
fi
