#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================

set -euo pipefail

# Ensure logging functions available
ACFS_GENERATED_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh" ]]; then
    source "$ACFS_GENERATED_SCRIPT_DIR/../lib/logging.sh"
else
    # Fallback logging functions if logging.sh not found
    log_step() { echo "[*] $*"; }
    log_section() { echo ""; echo "=== $* ==="; }
    log_success() { echo "[OK] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "    $*"; }
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
    if [[ "${ACFS_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    local security_lib="$ACFS_GENERATED_SCRIPT_DIR/../lib/security.sh"
    if [[ ! -f "$security_lib" ]]; then
        log_error "Security library not found: $security_lib"
        return 1
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
    log_step "Installing shell.zsh"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
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
    log_step "Installing shell.omz"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: verified installer: shell.omz"
    else
        if ! {
            # Try security-verified install (no unverified fallback; fail closed)
            local install_success=false

            if acfs_security_init 2>/dev/null; then
                # Check if KNOWN_INSTALLERS is available as an associative array (declare -A)
                # The grep ensures we specifically have an associative array, not just any variable
                if declare -p KNOWN_INSTALLERS 2>/dev/null | grep -q 'declare -A'; then
                    local tool="ohmyzsh"
                    local url=""
                    local expected_sha256=""

                    # Safe access with explicit empty default
                    url="${KNOWN_INSTALLERS[$tool]:-}"
                    expected_sha256="$(get_checksum "$tool" 2>/dev/null)" || expected_sha256=""

                    if [[ -n "$url" ]] && [[ -n "$expected_sha256" ]]; then
                        if verify_checksum "$url" "$expected_sha256" "$tool" 2>/dev/null | run_as_target_runner 'sh' '-s' '--' '--unattended' '--keep-zshrc'; then
                            install_success=true
                        fi
                    fi
                fi
            fi

            # No unverified fallback: verified install is required
            if [[ "$install_success" != "true" ]]; then
                log_error "Verified install failed for shell.omz"
                false
            fi
        }; then
            log_error "shell.omz: verified installer failed"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: # Install Powerlevel10k (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install Powerlevel10k
if [[ ! -d ~/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: # Install Powerlevel10k"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: # Install zsh-autosuggestions (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install zsh-autosuggestions
if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: # Install zsh-autosuggestions"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: # Install zsh-syntax-highlighting (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install zsh-syntax-highlighting
if [[ ! -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: # Install zsh-syntax-highlighting"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: # Install ACFS zshrc (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Install ACFS zshrc
ACFS_RAW="${ACFS_RAW:-https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main}"
mkdir -p ~/.acfs/zsh
curl --proto '=https' --proto-redir '=https' -fsSL -o ~/.acfs/zsh/acfs.zshrc "${ACFS_RAW}/acfs/zsh/acfs.zshrc"
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: # Install ACFS zshrc"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: # Setup loader .zshrc (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Setup loader .zshrc
if [[ -f ~/.zshrc ]] && ! grep -q "ACFS loader" ~/.zshrc; then
  mv ~/.zshrc ~/.zshrc.bak.$(date +%s)
fi
echo '# ACFS loader' > ~/.zshrc
echo 'source "$HOME/.acfs/zsh/acfs.zshrc"' >> ~/.zshrc
echo '' >> ~/.zshrc
echo '# User overrides live here forever' >> ~/.zshrc
echo '[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"' >> ~/.zshrc
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: # Setup loader .zshrc"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: # Setup ~/.profile for bash login shells (prevents PATH warnings from installers) (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Setup ~/.profile for bash login shells (prevents PATH warnings from installers)
if [[ ! -f ~/.profile ]]; then
  echo '# ~/.profile: executed by bash for login shells' > ~/.profile
  echo '' >> ~/.profile
  echo '# User binary paths' >> ~/.profile
  echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"' >> ~/.profile
elif ! grep -q '\.local/bin' ~/.profile; then
  echo '' >> ~/.profile
  echo '# Added by ACFS - user binary paths' >> ~/.profile
  echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$PATH"' >> ~/.profile
fi
INSTALL_SHELL_OMZ
        then
            log_error "shell.omz: install command failed: # Setup ~/.profile for bash login shells (prevents PATH warnings from installers)"
            return 1
        fi
    fi
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "dry-run: install: # Set default shell (target_user)"
    else
        if ! run_as_target_shell <<'INSTALL_SHELL_OMZ'
# Set default shell
if [[ "$SHELL" != */zsh ]]; then
  zsh_path="$(command -v zsh || true)"
  if [[ -z "$zsh_path" ]]; then
    echo "WARN: zsh not found; cannot set default shell automatically." >&2
    exit 0
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo chsh -s "$zsh_path" "$(whoami)"
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
            log_error "shell.omz: install command failed: # Set default shell"
            return 1
        fi
    fi

    # Verify
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
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

    log_success "shell.omz installed"
}

# Install all shell modules
install_shell() {
    log_section "Installing shell modules"
    install_shell_zsh
    install_shell_omz
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_shell
fi
