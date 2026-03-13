#!/usr/bin/env bash
# ============================================================
# ACFS Doctor --fix Implementation
# Safe, deterministic fixers with logging and undo capability
#
# Implements bd-31ps.6.2 based on spec in doctor_fix_spec.md
# ============================================================

# Prevent multiple sourcing
[[ -n "${_ACFS_DOCTOR_FIX_LOADED:-}" ]] && return 0
_ACFS_DOCTOR_FIX_LOADED=1

# Source autofix library for change tracking
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -f "$SCRIPT_DIR/autofix.sh" ]]; then
    # shellcheck source=autofix.sh
    source "$SCRIPT_DIR/autofix.sh"
elif [[ -f "$HOME/.acfs/scripts/lib/autofix.sh" ]]; then
    # shellcheck source=autofix.sh
    source "$HOME/.acfs/scripts/lib/autofix.sh"
fi

# ============================================================
# Configuration
# ============================================================

DOCTOR_FIX_LOG="${HOME}/.local/share/acfs/doctor.log"
DOCTOR_FIX_DRY_RUN=false
DOCTOR_FIX_YES=false
DOCTOR_FIX_PROMPT=false

# Counters for fix summary
declare -g FIX_APPLIED=0
declare -g FIX_SKIPPED=0
declare -g FIX_FAILED=0
declare -g FIX_MANUAL=0

# Arrays to track fixes for summary
declare -ga FIXES_APPLIED=()
declare -ga FIXES_DRY_RUN=()
declare -ga FIXES_MANUAL=()
declare -ga FIXES_PROMPTED=()

# ============================================================
# Logging Helpers
# ============================================================

doctor_fix_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Ensure log directory exists
    mkdir -p "$(dirname "$DOCTOR_FIX_LOG")"

    # Log to file
    echo "[$timestamp] [$level] $message" >> "$DOCTOR_FIX_LOG"

    # Output to user
    case "$level" in
        INFO)  echo "  [fix] $message" ;;
        WARN)  echo "  [fix] WARNING: $message" >&2 ;;
        ERROR) echo "  [fix] ERROR: $message" >&2 ;;
        DRY)   echo "  [dry-run] Would: $message" ;;
    esac
}

# ============================================================
# Guard Helpers
# ============================================================

# Check if a file contains a specific line
file_contains_line() {
    local file="$1"
    local pattern="$2"

    [[ -f "$file" ]] && grep -qF "$pattern" "$file" 2>/dev/null
}

# Check if directory is in PATH
dir_in_path() {
    local dir="$1"
    case ":$PATH:" in
        *":$dir:"*) return 0 ;;
        *) return 1 ;;
    esac
}

doctor_fix_require_security() {
    if [[ "${DOCTOR_FIX_SECURITY_READY:-false}" == "true" ]]; then
        return 0
    fi

    local security_script="$SCRIPT_DIR/security.sh"
    if [[ ! -r "$security_script" ]]; then
        security_script="$HOME/.acfs/scripts/lib/security.sh"
    fi

    if [[ ! -r "$security_script" ]]; then
        doctor_fix_log WARN "security.sh not available; cannot verify upstream installer scripts"
        return 1
    fi

    # shellcheck source=security.sh
    source "$security_script" || return 1
    if ! load_checksums >/dev/null 2>&1; then
        doctor_fix_log WARN "checksums.yaml not available; refusing to run unverified installer scripts"
        return 1
    fi

    DOCTOR_FIX_SECURITY_READY=true
    return 0
}

doctor_fix_run_verified_installer() {
    local tool="$1"
    shift
    local ms_arch=""
    ms_arch="$(uname -m 2>/dev/null || true)"

    if [[ "$tool" == "ms" ]] && [[ "$(uname -s 2>/dev/null)" == "Linux" ]] && [[ "$ms_arch" == "aarch64" || "$ms_arch" == "arm64" ]]; then
        if ! command -v cargo >/dev/null 2>&1; then
            doctor_fix_log WARN "meta_skill ARM64 Linux fallback requires cargo in PATH"
            return 1
        fi

        doctor_fix_log INFO "meta_skill: Linux ARM64 detected, rebuilding from source via cargo"
        cargo install --git https://github.com/Dicklesworthstone/meta_skill --force
        return $?
    fi

    if ! doctor_fix_require_security; then
        return 1
    fi

    local url="${KNOWN_INSTALLERS[$tool]:-}"
    local expected_sha256=""
    expected_sha256="$(get_checksum "$tool")"

    if [[ -z "$url" || -z "$expected_sha256" ]]; then
        doctor_fix_log WARN "Missing verified installer metadata for $tool"
        return 1
    fi

    fetch_and_run "$url" "$expected_sha256" "$tool" "$@"
}

# ============================================================
# Fixer: PATH Ordering (fix.path.ordering)
# ============================================================

# Fix PATH ordering in shell config
# Ensures ~/.local/bin and other ACFS dirs are at front of PATH
fix_path_ordering() {
    local check_id="$1"
    local target_file="${HOME}/.zshrc"

    # Required directories in order
    local -a path_dirs=(
        '$HOME/.local/bin'
        '$HOME/.bun/bin'
        '$HOME/.cargo/bin'
        '$HOME/go/bin'
        '$HOME/.atuin/bin'
    )

    # Build the export line
    local path_string
    path_string=$(IFS=:; echo "${path_dirs[*]}")
    local export_line="export PATH=\"${path_string}:\$PATH\""
    local marker="# ACFS PATH ordering (added by doctor --fix)"

    # Guard: Check if already present
    if file_contains_line "$target_file" "$marker"; then
        doctor_fix_log INFO "PATH ordering already configured in $target_file"
        return 0
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.path.ordering|Prepend PATH directories to $target_file|$target_file|$export_line")
        doctor_fix_log DRY "Prepend PATH directories to $target_file"
        return 0
    fi

    # Create backup
    local backup_json=""
    if [[ -f "$target_file" ]]; then
        backup_json=$(create_backup "$target_file" "path-ordering")
    fi

    # Apply fix
    {
        echo ""
        echo "$marker"
        echo "$export_line"
    } >> "$target_file"

    # Record change
    record_change "path" "Added PATH ordering to $target_file" \
        "sed -i '/$marker/,+1d' '$target_file'" \
        false "info" "[\"$target_file\"]" "${backup_json:-[]}" "[]" >/dev/null

    doctor_fix_log INFO "Added PATH ordering to $target_file"
    FIXES_APPLIED+=("fix.path.ordering|Added PATH ordering to $target_file")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}

# ============================================================
# Fixer: Config Copy (fix.config.copy)
# ============================================================

# Copy missing ACFS config files
fix_config_copy() {
    local check_id="$1"
    local src="$2"
    local dest="$3"

    # Guard: Source must exist
    if [[ ! -f "$src" ]]; then
        doctor_fix_log WARN "Source config not found: $src"
        return 1
    fi

    # Guard: Dest must not exist
    if [[ -f "$dest" ]]; then
        doctor_fix_log INFO "Config already exists: $dest"
        return 0
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.config.copy|Copy $(basename "$src") to $dest|$dest|cp -p $src $dest")
        doctor_fix_log DRY "Copy $(basename "$src") to $dest"
        return 0
    fi

    # Ensure parent directory exists
    mkdir -p "$(dirname "$dest")"

    # Copy file
    cp -p "$src" "$dest"

    # Record change
    record_change "config" "Copied config: $(basename "$src")" \
        "rm -f '$dest'" \
        false "info" "[\"$dest\"]" "[]" "[]" >/dev/null

    doctor_fix_log INFO "Copied $(basename "$src") to $dest"
    FIXES_APPLIED+=("fix.config.copy|Copied $(basename "$src") to $dest")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}

# ============================================================
# Fixer: DCG Hook (fix.dcg.hook)
# ============================================================

dcg_hook_already_installed() {
    local doctor_json=""

    doctor_json="$(dcg doctor --format json 2>/dev/null)" || return 1
    [[ -n "$doctor_json" ]] || return 1

    if command -v jq &>/dev/null; then
        printf '%s' "$doctor_json" | jq -e '
            (.hook_installed == true) or
            any(.checks[]?; .id == "hook_wiring" and .status == "ok")
        ' >/dev/null 2>&1
        return $?
    fi

    printf '%s' "$doctor_json" | grep -q '"hook_installed"[[:space:]]*:[[:space:]]*true' && return 0
    printf '%s' "$doctor_json" | grep -Eq '"id"[[:space:]]*:[[:space:]]*"hook_wiring".*"status"[[:space:]]*:[[:space:]]*"ok"' && return 0
    return 1
}

# Install DCG pre-tool-use hook
fix_dcg_hook() {
    local check_id="$1"

    # Guard: dcg command must exist
    if ! command -v dcg &>/dev/null; then
        doctor_fix_log WARN "DCG not installed, cannot fix hook"
        return 1
    fi

    # Guard: Check if already installed
    if dcg_hook_already_installed; then
        doctor_fix_log INFO "DCG hook already installed"
        return 0
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.dcg.hook|Install DCG pre-tool-use hook|~/.config/claude-code|dcg install")
        doctor_fix_log DRY "Install DCG pre-tool-use hook"
        return 0
    fi

    # Install hook
    if dcg install 2>/dev/null; then
        record_change "hook" "Installed DCG pre-tool-use hook" \
            "dcg uninstall" \
            false "info" "[]" "[]" "[]" >/dev/null

        doctor_fix_log INFO "Installed DCG pre-tool-use hook"
        FIXES_APPLIED+=("fix.dcg.hook|Installed DCG pre-tool-use hook")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        return 0
    else
        doctor_fix_log ERROR "Failed to install DCG hook"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
}

# ============================================================
# Fixer: Symlink Create (fix.symlink.create)
# ============================================================

# Create missing tool symlinks
fix_symlink_create() {
    local check_id="$1"
    local binary="$2"
    local symlink="$3"

    # Guard: Binary must exist and be executable
    if [[ ! -x "$binary" ]]; then
        doctor_fix_log WARN "Binary not found or not executable: $binary"
        return 1
    fi

    # Guard: Symlink must not exist
    if [[ -e "$symlink" ]]; then
        doctor_fix_log INFO "Symlink already exists: $symlink"
        return 0
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.symlink.create|Create symlink $(basename "$symlink")|$symlink|ln -s $binary $symlink")
        doctor_fix_log DRY "Create symlink: $(basename "$symlink") -> $binary"
        return 0
    fi

    # Ensure symlink directory exists
    mkdir -p "$(dirname "$symlink")"

    # Create symlink
    ln -s "$binary" "$symlink"

    # Record change
    record_change "symlink" "Created symlink: $(basename "$symlink")" \
        "rm -f '$symlink'" \
        false "info" "[\"$symlink\"]" "[]" "[]" >/dev/null

    doctor_fix_log INFO "Created symlink: $(basename "$symlink") -> $binary"
    FIXES_APPLIED+=("fix.symlink.create|Created symlink $(basename "$symlink")")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}

# ============================================================
# Fixer: Plugin Clone (fix.plugin.clone)
# ============================================================

# Clone missing zsh plugins
fix_plugin_clone() {
    local check_id="$1"
    local plugin_name="$2"
    local repo_url="$3"

    local plugins_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
    local target_dir="$plugins_dir/$plugin_name"

    # Guard: Must not already exist
    if [[ -d "$target_dir" ]]; then
        doctor_fix_log INFO "Plugin already installed: $plugin_name"
        return 0
    fi

    # Guard: Oh-my-zsh must be installed
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        doctor_fix_log WARN "Oh-my-zsh not installed, cannot install plugins"
        FIXES_MANUAL+=("fix.plugin.clone|Install Oh-my-zsh first|curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | bash")
        FIX_MANUAL=$((FIX_MANUAL + 1))
        return 1
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.plugin.clone|Clone zsh plugin: $plugin_name|$target_dir|git clone --depth 1 $repo_url $target_dir")
        doctor_fix_log DRY "Clone zsh plugin: $plugin_name"
        return 0
    fi

    # Ensure plugins directory exists
    mkdir -p "$plugins_dir"

    # Clone plugin
    if git clone --depth 1 "$repo_url" "$target_dir" 2>/dev/null; then
        record_change "plugin" "Cloned zsh plugin: $plugin_name" \
            "rm -rf '$target_dir'" \
            false "info" "[\"$target_dir\"]" "[]" "[]" >/dev/null

        doctor_fix_log INFO "Cloned zsh plugin: $plugin_name"
        FIXES_APPLIED+=("fix.plugin.clone|Cloned zsh plugin: $plugin_name")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        return 0
    else
        doctor_fix_log ERROR "Failed to clone plugin: $plugin_name"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
}

# ============================================================
# Fixer: ACFS Sourcing (fix.acfs.sourcing)
# ============================================================

# Add ACFS config sourcing to .zshrc
fix_acfs_sourcing() {
    local check_id="$1"
    local zshrc="$HOME/.zshrc"
    local source_line='[[ -f ~/.acfs/zsh/acfs.zshrc ]] && source ~/.acfs/zsh/acfs.zshrc'
    local marker="# ACFS configuration (added by doctor --fix)"

    # Guard: Check if already sourced
    if file_contains_line "$zshrc" "acfs.zshrc"; then
        doctor_fix_log INFO "ACFS already sourced in .zshrc"
        return 0
    fi

    # Guard: Check if acfs.zshrc exists
    if [[ ! -f "$HOME/.acfs/zsh/acfs.zshrc" ]]; then
        doctor_fix_log WARN "ACFS config not found at ~/.acfs/zsh/acfs.zshrc"
        return 1
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.acfs.sourcing|Add ACFS sourcing to .zshrc|$zshrc|$source_line")
        doctor_fix_log DRY "Add ACFS sourcing to .zshrc"
        return 0
    fi

    # Create backup
    local backup_json=""
    if [[ -f "$zshrc" ]]; then
        backup_json=$(create_backup "$zshrc" "acfs-sourcing")
    fi

    # Append sourcing line
    {
        echo ""
        echo "$marker"
        echo "$source_line"
    } >> "$zshrc"

    # Record change
    record_change "config" "Added ACFS sourcing to .zshrc" \
        "sed -i '/$marker/,+1d' '$zshrc'" \
        false "info" "[\"$zshrc\"]" "${backup_json:-[]}" "[]" >/dev/null

    doctor_fix_log INFO "Added ACFS sourcing to .zshrc"
    FIXES_APPLIED+=("fix.acfs.sourcing|Added ACFS sourcing to .zshrc")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}

# ============================================================
# Fix Dispatcher
# ============================================================

# Dispatch a fix based on check ID
# Returns 0 if fix was applied or not needed, 1 if fix failed
dispatch_fix() {
    local check_id="$1"
    local check_status="$2"
    local fix_hint="${3:-}"  # Optional hint from check (e.g., file path)

    # Only fix failed or warned checks
    case "$check_status" in
        pass) return 0 ;;
        skip) return 0 ;;
    esac

    case "$check_id" in
        # PATH fixes
        path.*)
            fix_path_ordering "$check_id"
            ;;

        # Config file copies
        config.acfs_zshrc)
            fix_config_copy "$check_id" \
                "$SCRIPT_DIR/../../acfs/zsh/acfs.zshrc" \
                "$HOME/.acfs/zsh/acfs.zshrc"
            ;;
        config.tmux)
            fix_config_copy "$check_id" \
                "$SCRIPT_DIR/../../acfs/tmux/tmux.conf" \
                "$HOME/.acfs/tmux/tmux.conf"
            ;;

        # DCG hook
        hook.dcg.*)
            fix_dcg_hook "$check_id"
            ;;

        # Stack tools (fixes #160 - meta_skill and other stack tools)
        stack.meta_skill*)
            fix_verified_install "$check_id" "ms" "ms" --easy-mode
            ;;
        stack.mcp_agent_mail*)
            fix_mcp_agent_mail "$check_id"
            ;;

        # Symlinks
        symlink.br)
            fix_symlink_create "$check_id" "$HOME/.cargo/bin/br" "$HOME/.local/bin/br"
            ;;
        symlink.bv)
            fix_symlink_create "$check_id" "$HOME/.cargo/bin/bv" "$HOME/.local/bin/bv"
            ;;

        # Zsh plugins
        shell.plugins.zsh_autosuggestions)
            fix_plugin_clone "$check_id" "zsh-autosuggestions" \
                "https://github.com/zsh-users/zsh-autosuggestions"
            ;;
        shell.plugins.zsh_syntax_highlighting)
            fix_plugin_clone "$check_id" "zsh-syntax-highlighting" \
                "https://github.com/zsh-users/zsh-syntax-highlighting"
            ;;

        # ACFS sourcing
        shell.acfs_sourced)
            fix_acfs_sourcing "$check_id"
            ;;

        # SSH server (fixes #161/#162)
        network.ssh_server)
            fix_ssh_server "$check_id"
            ;;

        # SSH keepalive
        network.ssh_keepalive|network.ssh_keepalive.*)
            fix_ssh_keepalive "$check_id"
            ;;

        # Agent CLI tools (fixes #213)
        agent.claude)
            fix_verified_install "$check_id" "claude" "claude"
            ;;
        agent.codex)
            fix_stack_install "$check_id" "codex" \
                "bun install -g --trust @openai/codex@latest"
            ;;
        agent.gemini)
            fix_stack_install "$check_id" "gemini" \
                "bun install -g --trust @google/gemini-cli@latest"
            ;;

        # Agent aliases/functions (fixes #163)
        agent.alias.*)
            fix_acfs_sourcing "$check_id"
            ;;

        # Manual fixes (log suggestion only)
        shell.ohmyzsh|shell.p10k|*.apt_install|*.sudo_required)
            if [[ -n "$fix_hint" ]]; then
                FIXES_MANUAL+=("$check_id|Requires manual action|$fix_hint")
            fi
            FIX_MANUAL=$((FIX_MANUAL + 1))
            return 0
            ;;

        *)
            # Unknown check - skip silently
            FIX_SKIPPED=$((FIX_SKIPPED + 1))
            return 0
            ;;
    esac
}

# ============================================================
# Fixer: Stack Install (fix.stack.install)
# ============================================================

# Install missing stack tools via their upstream installer
fix_stack_install() {
    local check_id="$1"
    local binary_name="$2"
    local install_cmd="$3"

    # Guard: Check if already installed
    if command -v "$binary_name" &>/dev/null; then
        doctor_fix_log INFO "$binary_name already installed"
        return 0
    fi

    # Dry-run mode
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.stack.$binary_name|Install $binary_name|~/.local/bin/$binary_name|$install_cmd")
        doctor_fix_log DRY "Install $binary_name"
        return 0
    fi

    # Run installer
    if eval "$install_cmd" 2>/dev/null; then
        doctor_fix_log INFO "Installed $binary_name"
        FIXES_APPLIED+=("fix.stack.$binary_name|Installed $binary_name")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        return 0
    else
        doctor_fix_log ERROR "Failed to install $binary_name"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
}

fix_verified_install() {
    local check_id="$1"
    local binary_name="$2"
    local tool="$3"
    shift 3
    local args=("$@")
    local args_display="${args[*]:-}"

    if command -v "$binary_name" &>/dev/null; then
        doctor_fix_log INFO "$binary_name already installed"
        return 0
    fi

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.stack.$binary_name|Install $binary_name via verified installer|~/.local/bin/$binary_name|verified:$tool ${args_display}")
        doctor_fix_log DRY "Install $binary_name via verified installer"
        return 0
    fi

    if doctor_fix_run_verified_installer "$tool" "${args[@]}" >/dev/null 2>&1; then
        hash -r
        if command -v "$binary_name" &>/dev/null; then
            doctor_fix_log INFO "Installed $binary_name via verified installer"
            FIXES_APPLIED+=("fix.stack.$binary_name|Installed $binary_name via verified installer")
            FIX_APPLIED=$((FIX_APPLIED + 1))
            return 0
        fi
    fi

    doctor_fix_log ERROR "Failed to install $binary_name via verified installer"
    FIX_FAILED=$((FIX_FAILED + 1))
    return 1
}

# ============================================================
# Fixer: SSH Server (fix.ssh.server)
# ============================================================

# Install and enable SSH server
fix_ssh_server() {
    local check_id="$1"

    # Guard: Check if already installed
    if command -v sshd &>/dev/null || [[ -f /etc/ssh/sshd_config ]]; then
        # Check if running
        if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
            if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
                doctor_fix_log INFO "SSH server already installed and running"
                return 0
            fi

            # Installed but not running - enable and start
            if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
                FIXES_DRY_RUN+=("fix.ssh.server|Enable and start SSH server|/etc/ssh/sshd_config|sudo systemctl enable --now ssh")
                doctor_fix_log DRY "Enable and start SSH server"
                return 0
            fi

            if sudo systemctl enable --now ssh 2>/dev/null || sudo systemctl enable --now sshd 2>/dev/null; then
                doctor_fix_log INFO "Enabled and started SSH server"
                FIXES_APPLIED+=("fix.ssh.server|Enabled and started SSH server")
                FIX_APPLIED=$((FIX_APPLIED + 1))
                return 0
            else
                doctor_fix_log ERROR "Failed to start SSH server"
                FIX_FAILED=$((FIX_FAILED + 1))
                return 1
            fi
        fi
        return 0
    fi

    # Not installed - install it
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.ssh.server|Install openssh-server|/etc/ssh/sshd_config|sudo apt-get install -y openssh-server")
        doctor_fix_log DRY "Install openssh-server"
        return 0
    fi

    if sudo apt-get install -y openssh-server 2>/dev/null; then
        sudo systemctl enable --now ssh 2>/dev/null || sudo systemctl enable --now sshd 2>/dev/null || true
        doctor_fix_log INFO "Installed and enabled openssh-server"
        FIXES_APPLIED+=("fix.ssh.server|Installed and enabled openssh-server")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        return 0
    else
        doctor_fix_log ERROR "Failed to install openssh-server"
        FIX_FAILED=$((FIX_FAILED + 1))
        return 1
    fi
}

# ============================================================
# Fixer: SSH Keepalive (fix.ssh.keepalive)
# ============================================================

# Configure SSH keepalive settings
fix_ssh_keepalive() {
    local check_id="$1"
    local sshd_config="/etc/ssh/sshd_config"

    # Guard: sshd_config must exist
    if [[ ! -f "$sshd_config" ]]; then
        doctor_fix_log WARN "sshd_config not found, install openssh-server first"
        FIXES_MANUAL+=("$check_id|Install openssh-server first|sudo apt-get install -y openssh-server")
        FIX_MANUAL=$((FIX_MANUAL + 1))
        return 1
    fi

    # Guard: Check if already configured
    if grep -qE '^[[:space:]]*ClientAliveInterval[[:space:]]+[0-9]+' "$sshd_config" 2>/dev/null; then
        doctor_fix_log INFO "SSH keepalive already configured"
        return 0
    fi

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.ssh.keepalive|Configure SSH keepalive|$sshd_config|echo 'ClientAliveInterval 60' >> $sshd_config")
        doctor_fix_log DRY "Configure SSH keepalive in $sshd_config"
        return 0
    fi

    # Create backup
    local backup_json=""
    if [[ -f "$sshd_config" ]]; then
        backup_json=$(create_backup "$sshd_config" "ssh-keepalive")
    fi

    # Apply settings
    {
        echo ""
        echo "# ACFS: SSH keepalive settings (added by doctor --fix)"
        echo "ClientAliveInterval 60"
        echo "ClientAliveCountMax 3"
    } | sudo tee -a "$sshd_config" > /dev/null

    # Restart sshd to apply
    sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd 2>/dev/null || true

    doctor_fix_log INFO "Configured SSH keepalive (ClientAliveInterval 60, ClientAliveCountMax 3)"
    FIXES_APPLIED+=("fix.ssh.keepalive|Configured SSH keepalive settings")
    FIX_APPLIED=$((FIX_APPLIED + 1))

    return 0
}

# ============================================================
# Fixer: MCP Agent Mail (fix.stack.mcp_agent_mail)
# ============================================================

agent_mail_fix_doctor_healthy() {
    local doctor_json=""
    local -a cmd=(am doctor check --json)

    if [[ $# -gt 0 ]]; then
        cmd+=("$1")
    fi

    if command -v timeout &>/dev/null; then
        doctor_json="$(timeout 15s "${cmd[@]}" 2>/dev/null)" || return 1
    else
        doctor_json="$("${cmd[@]}" 2>/dev/null)" || return 1
    fi

    [[ -n "$doctor_json" ]] || return 1

    if command -v jq &>/dev/null; then
        [[ "$(printf '%s' "$doctor_json" | jq -r '.healthy // false' 2>/dev/null)" == "true" ]]
        return $?
    fi

    printf '%s' "$doctor_json" | grep -q '"healthy"[[:space:]]*:[[:space:]]*true'
}

agent_mail_fix_wait_for_health() {
    local attempt
    for attempt in {1..15}; do
        if curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

agent_mail_fix_write_unit() {
    local storage_root="$HOME/.mcp_agent_mail_git_mailbox_repo"
    local unit_dir="$HOME/.config/systemd/user"
    local unit_file="$unit_dir/agent-mail.service"
    local am_bin=""
    local db_url=""

    if ! am_bin="$(command -v am 2>/dev/null)"; then
        return 1
    fi

    db_url="sqlite+aiosqlite:///${storage_root}/storage.sqlite3"

    mkdir -p "$storage_root" "$unit_dir" || return 1
    cat > "$unit_file" <<UNIT_EOF
[Unit]
Description=MCP Agent Mail Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$storage_root
Environment=RUST_LOG=info
Environment=STORAGE_ROOT=$storage_root
Environment=DATABASE_URL=$db_url
Environment=HTTP_PATH=/mcp/
ExecStart=$am_bin serve-http --host 127.0.0.1 --port 8765 --path /mcp --no-auth --no-tui
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT_EOF
}

agent_mail_fix_launch_fallback() {
    local storage_root="$HOME/.mcp_agent_mail_git_mailbox_repo"
    local fallback_pid_file="$storage_root/agent-mail.pid"
    local fallback_log_file="$storage_root/agent-mail.log"
    local am_bin=""
    local db_url=""
    local existing_pid=""

    if ! am_bin="$(command -v am 2>/dev/null)"; then
        return 1
    fi

    db_url="sqlite+aiosqlite:///${storage_root}/storage.sqlite3"

    if curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; then
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
        HTTP_PATH=/mcp/ \
        "$am_bin" serve-http --host 127.0.0.1 --port 8765 --path /mcp --no-auth --no-tui \
        >>"$fallback_log_file" 2>&1 < /dev/null &
    echo $! > "$fallback_pid_file"
}

agent_mail_fix_stop_fallback() {
    local storage_root="$HOME/.mcp_agent_mail_git_mailbox_repo"
    local fallback_pid_file="$storage_root/agent-mail.pid"
    local am_bin=""
    local existing_pid=""

    if ! am_bin="$(command -v am 2>/dev/null)"; then
        return 1
    fi

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

fix_mcp_agent_mail() {
    local check_id="$1"
    local fixed_any=false
    local service_healthy=false
    local doctor_healthy=false
    local project_path=""

    if ! command -v am &>/dev/null; then
        if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
            FIXES_DRY_RUN+=("fix.stack.mcp_agent_mail|Install MCP Agent Mail via verified installer, then repair service state|$HOME/.mcp_agent_mail_git_mailbox_repo|verified:mcp_agent_mail --dir $HOME/mcp_agent_mail --yes --no-start")
            doctor_fix_log DRY "Install MCP Agent Mail via verified installer, then repair service state"
            return 0
        fi

        if doctor_fix_run_verified_installer "mcp_agent_mail" --dir "$HOME/mcp_agent_mail" --yes --no-start >/dev/null 2>&1; then
            hash -r
            if command -v am &>/dev/null; then
                doctor_fix_log INFO "Installed MCP Agent Mail CLI via verified installer"
                FIXES_APPLIED+=("fix.stack.mcp_agent_mail.install|Installed MCP Agent Mail CLI via verified installer")
                FIX_APPLIED=$((FIX_APPLIED + 1))
                fixed_any=true
            else
                doctor_fix_log ERROR "Verified MCP Agent Mail install completed without providing 'am'"
                FIX_FAILED=$((FIX_FAILED + 1))
                return 1
            fi
        else
            doctor_fix_log ERROR "Failed to install MCP Agent Mail via verified installer"
            FIX_FAILED=$((FIX_FAILED + 1))
            return 1
        fi
    elif [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        FIXES_DRY_RUN+=("fix.stack.mcp_agent_mail|Repair MCP Agent Mail and apply upstream doctor fixes|$HOME/.mcp_agent_mail_git_mailbox_repo|am doctor repair --yes && am doctor fix --yes")
        doctor_fix_log DRY "Repair MCP Agent Mail database, apply upstream doctor fixes, and restart the service"
        return 0
    fi

    if am doctor repair --yes >/dev/null 2>&1; then
        doctor_fix_log INFO "Ran MCP Agent Mail database repair"
        FIXES_APPLIED+=("fix.stack.mcp_agent_mail.repair|Ran MCP Agent Mail database repair")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        fixed_any=true
    else
        doctor_fix_log WARN "MCP Agent Mail database repair did not complete cleanly"
    fi

    if am doctor fix --yes >/dev/null 2>&1; then
        doctor_fix_log INFO "Applied MCP Agent Mail doctor fixes"
        FIXES_APPLIED+=("fix.stack.mcp_agent_mail.fix|Applied MCP Agent Mail doctor fixes")
        FIX_APPLIED=$((FIX_APPLIED + 1))
        fixed_any=true
    else
        doctor_fix_log WARN "MCP Agent Mail doctor fix did not complete cleanly"
    fi

    if curl -fsS --max-time 5 http://127.0.0.1:8765/health/liveness >/dev/null 2>&1; then
        service_healthy=true
    fi

    if command -v systemctl &>/dev/null; then
        local uid runtime_dir user_bus
        local -a service_env=("HOME=$HOME")

        uid="$(id -u)"
        runtime_dir="/run/user/$uid"
        user_bus="$runtime_dir/bus"
        if [[ -d "$runtime_dir" ]]; then
            service_env+=("XDG_RUNTIME_DIR=$runtime_dir")
            if [[ -S "$user_bus" ]]; then
                service_env+=("DBUS_SESSION_BUS_ADDRESS=unix:path=$user_bus")
            fi
        fi

        if agent_mail_fix_write_unit; then
            doctor_fix_log INFO "Rewrote MCP Agent Mail user service unit"
            FIXES_APPLIED+=("fix.stack.mcp_agent_mail.service|Rewrote MCP Agent Mail user service unit")
            FIX_APPLIED=$((FIX_APPLIED + 1))
            fixed_any=true

            if env "${service_env[@]}" systemctl --user show-environment >/dev/null 2>&1; then
                service_healthy=false
                agent_mail_fix_stop_fallback
                env "${service_env[@]}" systemctl --user daemon-reload >/dev/null 2>&1 || true
                if env "${service_env[@]}" systemctl --user enable --now agent-mail.service >/dev/null 2>&1 || \
                   env "${service_env[@]}" systemctl --user restart agent-mail.service >/dev/null 2>&1; then
                    if env "${service_env[@]}" systemctl --user is-active --quiet agent-mail.service >/dev/null 2>&1 && \
                       agent_mail_fix_wait_for_health; then
                        doctor_fix_log INFO "Agent Mail service is healthy after restart"
                        service_healthy=true
                    else
                        doctor_fix_log WARN "Agent Mail user service is still inactive after restart"
                    fi
                fi
            elif [[ "$service_healthy" != "true" ]]; then
                if agent_mail_fix_launch_fallback && agent_mail_fix_wait_for_health; then
                    doctor_fix_log INFO "Agent Mail service is healthy after fallback launch"
                    service_healthy=true
                fi
            fi
        else
            doctor_fix_log WARN "Failed to rewrite MCP Agent Mail user service unit"
        fi
    elif [[ "$service_healthy" != "true" ]]; then
        if agent_mail_fix_launch_fallback && agent_mail_fix_wait_for_health; then
            doctor_fix_log INFO "Agent Mail service is healthy after fallback launch"
            service_healthy=true
        fi
    fi

    if [[ "$service_healthy" == "true" ]] && agent_mail_fix_doctor_healthy; then
        project_path="$(git rev-parse --show-toplevel 2>/dev/null || true)"
        if [[ -n "$project_path" ]]; then
            if agent_mail_fix_doctor_healthy "$project_path"; then
                doctor_healthy=true
            fi
        else
            doctor_healthy=true
        fi
    fi

    if [[ "$doctor_healthy" == "true" ]]; then
        if [[ "$fixed_any" == "true" ]]; then
            doctor_fix_log INFO "MCP Agent Mail is healthy after repair"
        else
            doctor_fix_log INFO "MCP Agent Mail is already healthy"
        fi
        return 0
    fi

    doctor_fix_log ERROR "Failed to repair MCP Agent Mail to a healthy state"
    FIX_FAILED=$((FIX_FAILED + 1))
    return 1
}

# ============================================================
# Summary Output
# ============================================================

# Print fix summary
print_fix_summary() {
    echo ""
    echo "========================================================================"
    echo "  Doctor --fix Summary"
    echo "========================================================================"

    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        echo "  Mode: DRY-RUN (no changes made)"
        echo ""

        if [[ ${#FIXES_DRY_RUN[@]} -gt 0 ]]; then
            echo "  Would apply the following fixes:"
            for fix in "${FIXES_DRY_RUN[@]}"; do
                IFS='|' read -r id desc file cmd <<< "$fix"
                echo ""
                echo "    [$id]"
                echo "      Action: $desc"
                echo "      File: $file"
                echo "      Command: $cmd"
            done
        else
            echo "  No fixes needed."
        fi
    else
        echo "  Applied: $FIX_APPLIED"
        echo "  Skipped: $FIX_SKIPPED"
        echo "  Failed:  $FIX_FAILED"
        echo "  Manual:  $FIX_MANUAL"

        if [[ ${#FIXES_APPLIED[@]} -gt 0 ]]; then
            echo ""
            echo "  Applied fixes:"
            for fix in "${FIXES_APPLIED[@]}"; do
                IFS='|' read -r id desc <<< "$fix"
                echo "    [$id] $desc"
            done
        fi
    fi

    if [[ ${#FIXES_MANUAL[@]} -gt 0 ]]; then
        echo ""
        echo "  Manual fixes needed:"
        for fix in "${FIXES_MANUAL[@]}"; do
            IFS='|' read -r id desc cmd <<< "$fix"
            echo "    [$id] $desc"
            echo "      Run: $cmd"
        done
    fi

    echo ""
    echo "========================================================================"

    # Show undo hint if changes were made
    if [[ "$DOCTOR_FIX_DRY_RUN" != "true" ]] && [[ $FIX_APPLIED -gt 0 ]]; then
        echo ""
        echo "  To undo changes: acfs undo --list"
        echo ""
    fi
}

# ============================================================
# Main Entry Point
# ============================================================

# Run doctor --fix
# Usage: run_doctor_fix [--dry-run] [--yes] [--only <categories>]
run_doctor_fix() {
    local only_categories=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DOCTOR_FIX_DRY_RUN=true; shift ;;
            --yes) DOCTOR_FIX_YES=true; shift ;;
            --prompt) DOCTOR_FIX_PROMPT=true; shift ;;
            --only)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --only requires a category value" >&2
                    return 1
                fi
                only_categories="$2"
                shift 2
                ;;
            *) shift ;;
        esac
    done

    # Initialize autofix session (unless dry-run)
    if [[ "$DOCTOR_FIX_DRY_RUN" != "true" ]]; then
        start_autofix_session || {
            echo "ERROR: Failed to start autofix session" >&2
            return 1
        }
    fi

    # Reset counters
    FIX_APPLIED=0
    FIX_SKIPPED=0
    FIX_FAILED=0
    FIX_MANUAL=0
    FIXES_APPLIED=()
    FIXES_DRY_RUN=()
    FIXES_MANUAL=()
    FIXES_PROMPTED=()

    echo ""
    if [[ "$DOCTOR_FIX_DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: acfs doctor --fix"
        echo "Scanning for fixable issues..."
    else
        echo "Running: acfs doctor --fix"
        echo "Applying safe fixes..."
    fi
    echo ""

    # The actual fixes are dispatched by the caller (doctor.sh)
    # based on check results. This function sets up the environment.

    return 0
}

# Finalize doctor --fix
finalize_doctor_fix() {
    # Print summary
    print_fix_summary

    # End autofix session (unless dry-run)
    if [[ "$DOCTOR_FIX_DRY_RUN" != "true" ]]; then
        end_autofix_session

        # Print undo summary if changes were made
        if [[ $FIX_APPLIED -gt 0 ]]; then
            print_undo_summary
        fi
    fi

    # Return failure if any fixes failed
    if [[ $FIX_FAILED -gt 0 ]]; then
        return 1
    fi

    return 0
}
