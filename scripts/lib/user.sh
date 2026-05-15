#!/usr/bin/env bash
# ============================================================
# ACFS Installer - User Normalization Library
# Ensures consistent user setup across VPS providers
#
# Requires:
#   - logging.sh to be sourced first for log_* functions
#   - $SUDO to be set (empty string for root, "sudo" otherwise)
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_USER_SH_LOADED:-}" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    fi
    exit 0
fi
_ACFS_USER_SH_LOADED=1

# Fallback logging if logging.sh not sourced
if ! declare -f log_fatal &>/dev/null; then
    log_fatal() { printf "FATAL: %s\n" "$1" >&2; exit 1; }
    log_detail() { printf "  %s\n" "$1" >&2; }
    log_warn() { printf "WARN: %s\n" "$1" >&2; }
    log_success() { printf "OK: %s\n" "$1" >&2; }
    log_error() { printf "ERROR: %s\n" "$1" >&2; }
    log_step() { printf "[%s] %s\n" "$1" "$2" >&2; }
fi

user_valid_target_name() {
    local user="${1:-}"
    [[ -n "$user" ]] || return 1
    [[ "$user" =~ ^[a-z_][a-z0-9._-]*$ ]]
}

user_require_valid_target_user() {
    local user="${1:-${TARGET_USER:-}}"
    local display="${user:-<empty>}"

    if user_valid_target_name "$user"; then
        return 0
    fi

    log_fatal "Invalid TARGET_USER '$display' (expected: lowercase user name like 'ubuntu')"
}

user_system_binary_path() {
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
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

user_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(user_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(user_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

user_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(user_system_binary_path getent 2>/dev/null || true)"
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

user_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    [[ -n "$passwd_home" ]] || return 1
    [[ "$passwd_home" == /* ]] || return 1
    [[ "$passwd_home" != "/" ]] || return 1
    printf '%s\n' "${passwd_home%/}"
}

user_lookup_passwd_home() {
    local user="${1:-}"
    local passwd_entry=""
    local home_candidate=""

    [[ -n "$user" ]] || return 1

    passwd_entry="$(user_getent_passwd_entry "$user" 2>/dev/null || true)"
    [[ -n "$passwd_entry" ]] || return 1

    home_candidate="$(user_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
    [[ -n "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

# Ensure SUDO is set (empty string for root, "sudo" otherwise)
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    : "${SUDO:=sudo}"
fi

user_home_for_user() {
    local user="${1:-}"
    local expected_home="${2:-}"
    local current_user=""
    local home_candidate=""

    [[ -n "$user" ]] || return 1
    if [[ -n "$expected_home" ]] && [[ "$expected_home" == /* ]] && [[ "$expected_home" != "/" ]]; then
        expected_home="${expected_home%/}"
    else
        expected_home=""
    fi

    if [[ "$user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    home_candidate="$(user_lookup_passwd_home "$user" 2>/dev/null || true)"
    if [[ -n "$home_candidate" ]]; then
        printf '%s\n' "$home_candidate"
        return 0
    fi

    current_user="$(user_resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "$user" ]] && [[ -n "${HOME:-}" ]] && [[ "${HOME}" == /* ]] && [[ "${HOME}" != "/" ]]; then
        home_candidate="${HOME%/}"
        if [[ -z "$expected_home" ]] || [[ "$home_candidate" == "$expected_home" ]]; then
            printf '%s\n' "$home_candidate"
            return 0
        fi
    fi

    return 1
}

# Target user for ACFS installations
TARGET_USER="${TARGET_USER:-ubuntu}"
user_require_valid_target_user "$TARGET_USER"
_ACFS_USER_EXPLICIT_TARGET_HOME="${TARGET_HOME:-}"
if [[ -n "$_ACFS_USER_EXPLICIT_TARGET_HOME" ]] && [[ "$_ACFS_USER_EXPLICIT_TARGET_HOME" == /* ]] && [[ "$_ACFS_USER_EXPLICIT_TARGET_HOME" != "/" ]]; then
    _ACFS_USER_EXPLICIT_TARGET_HOME="${_ACFS_USER_EXPLICIT_TARGET_HOME%/}"
else
    _ACFS_USER_EXPLICIT_TARGET_HOME=""
fi
_ACFS_USER_CURRENT_USER="$(user_resolve_current_user 2>/dev/null || true)"
_ACFS_USER_RESOLVED_TARGET_HOME="$(user_home_for_user "$TARGET_USER" "$_ACFS_USER_EXPLICIT_TARGET_HOME" 2>/dev/null || true)"
if [[ -n "$_ACFS_USER_RESOLVED_TARGET_HOME" ]]; then
    TARGET_HOME="$_ACFS_USER_RESOLVED_TARGET_HOME"
elif [[ -n "$_ACFS_USER_EXPLICIT_TARGET_HOME" ]] && [[ "$TARGET_USER" == "$_ACFS_USER_CURRENT_USER" ]]; then
    TARGET_HOME="$_ACFS_USER_EXPLICIT_TARGET_HOME"
else
    TARGET_HOME=""
fi
unset _ACFS_USER_EXPLICIT_TARGET_HOME _ACFS_USER_CURRENT_USER _ACFS_USER_RESOLVED_TARGET_HOME

# Generate a random password robustly
_generate_random_password() {
    # Try openssl first (most standard)
    if command -v openssl &>/dev/null; then
        openssl rand -base64 32
        return 0
    fi

    # Fallback to python3 (standard on Ubuntu)
    if command -v python3 &>/dev/null; then
        python3 -c "import secrets; print(secrets.token_urlsafe(32))"
        return 0
    fi

    # Fallback to /dev/urandom (standard on Linux)
    if [[ -r /dev/urandom ]]; then
        # Take first 32 alphanumeric chars
        tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
        return 0
    fi

    # Last resort: date hash (better than empty)
    date +%s%N | sha256sum | head -c 32
}

# Ensure target user exists
# Creates user if missing, adds to required groups
ensure_user() {
    local target="$TARGET_USER"

    user_require_valid_target_user "$target"

    if ! id "$target" &>/dev/null; then
        log_detail "Creating user: $target"
        $SUDO useradd -m -s /bin/bash -G sudo "$target"

        # Generate random password (user will use SSH key)
        local passwd
        passwd=$(_generate_random_password)
        
        if [[ -n "$passwd" ]]; then
            echo "$target:$passwd" | $SUDO chpasswd
            
            # Print password so user isn't locked out of sudo in safe mode
            echo "" >&2
            if declare -f log_sensitive >/dev/null; then
                log_sensitive "Generated password for '$target': $passwd"
                log_sensitive "Save this password! You may need it for sudo access."
            elif declare -f log_warn >/dev/null; then
                log_warn "Generated password for '$target': $passwd"
                log_warn "Save this password! You may need it for sudo access."
            else
                echo "WARN: Generated password for '$target': $passwd" >&2
                echo "WARN: Save this password! You may need it for sudo access." >&2
            fi
            echo "" >&2
        else
            log_warn "Could not generate password for $target (openssl/python/urandom missing)"
        fi
    else
        log_detail "User $target already exists"
    fi

    # Ensure user is in required groups
    $SUDO usermod -aG sudo "$target" 2>/dev/null || true

    # Docker group (if docker is installed)
    if getent group docker &>/dev/null; then
        $SUDO usermod -aG docker "$target" 2>/dev/null || true
    fi
}

# Enable passwordless sudo for target user
# This is the "vibe mode" default
enable_passwordless_sudo() {
    local target="$TARGET_USER"
    local sudoers_file="/etc/sudoers.d/90-ubuntu-acfs"

    user_require_valid_target_user "$target"

    log_detail "Enabling passwordless sudo for $target"

    echo "$target ALL=(ALL) NOPASSWD:ALL" | $SUDO tee "$sudoers_file" > /dev/null
    $SUDO chmod 440 "$sudoers_file"

    # Validate sudoers file
    if ! $SUDO visudo -c -f "$sudoers_file" &>/dev/null; then
        log_error "Invalid sudoers file generated, removing"
        $SUDO rm -f "$sudoers_file"
        return 1
    fi

    log_success "Passwordless sudo enabled"
}

# Copy SSH keys from current user to target user
# Handles root -> ubuntu key migration common on fresh VPS
migrate_ssh_keys() {
    local current_user
    current_user="$(user_resolve_current_user 2>/dev/null || true)"
    local target="$TARGET_USER"
    local target_home="${TARGET_HOME:-}"

    user_require_valid_target_user "$target"

    # Nothing to do if we're already the target user
    if [[ "$current_user" == "$target" ]]; then
        log_detail "Already running as $target, no key migration needed"
        return 0
    fi

    target_home="$(user_home_for_user "$target" 2>/dev/null || true)"
    if [[ -z "$target_home" ]]; then
        target_home="${TARGET_HOME:-}"
    fi
    if [[ -z "$target_home" || "$target_home" == "/" || "$target_home" != /* ]]; then
        log_error "Unable to resolve TARGET_HOME for '$target'; cannot migrate SSH keys safely"
        return 1
    fi
    TARGET_HOME="${target_home%/}"

    local source_keys=""

    # Check for keys in current user's home
    if [[ -f "$HOME/.ssh/authorized_keys" ]]; then
        source_keys="$HOME/.ssh/authorized_keys"
    fi

    # Check for root keys specifically
    if [[ $EUID -eq 0 ]] && [[ -f /root/.ssh/authorized_keys ]]; then
        source_keys="/root/.ssh/authorized_keys"
    fi

    if [[ -z "$source_keys" ]]; then
        if [[ "${ACFS_CI:-false}" == "true" ]]; then
            log_detail "No SSH keys found to migrate (CI)"
        else
            log_warn "No SSH keys found to migrate to $target user"
            log_warn "You connected with password - SSH key not configured for $target"
            local target_user_repair_command="cat ~/.ssh/acfs_ed25519.pub | ssh ${target}@YOUR_SERVER_IP \"read -r acfs_pubkey && test ! -L ~/.ssh && install -d -m 700 ~/.ssh && chmod 700 ~/.ssh && test ! -L ~/.ssh/authorized_keys && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && { [ ! -s ~/.ssh/authorized_keys ] || tail -c 1 ~/.ssh/authorized_keys | od -An -t u1 | grep -qw 10 || printf '\\n' >> ~/.ssh/authorized_keys; } && if ! grep -qxF \\\"\\\$acfs_pubkey\\\" ~/.ssh/authorized_keys; then printf '%s\\n' \\\"\\\$acfs_pubkey\\\" >> ~/.ssh/authorized_keys; fi\""
            local root_repair_command="cat ~/.ssh/acfs_ed25519.pub | ssh root@YOUR_SERVER_IP \"read -r acfs_pubkey && test ! -L ${target_home}/.ssh && install -d -m 700 -o ${target} -g ${target} ${target_home}/.ssh && test ! -L ${target_home}/.ssh/authorized_keys && touch ${target_home}/.ssh/authorized_keys && { [ ! -s ${target_home}/.ssh/authorized_keys ] || tail -c 1 ${target_home}/.ssh/authorized_keys | od -An -t u1 | grep -qw 10 || printf '\\n' >> ${target_home}/.ssh/authorized_keys; } && if ! grep -qxF \\\"\\\$acfs_pubkey\\\" ${target_home}/.ssh/authorized_keys; then printf '%s\\n' \\\"\\\$acfs_pubkey\\\" >> ${target_home}/.ssh/authorized_keys; fi && chown ${target}:${target} ${target_home}/.ssh/authorized_keys && chmod 600 ${target_home}/.ssh/authorized_keys\""
            echo ""
            echo "════════════════════════════════════════════════════════════"
            echo "  ⚠  SSH KEY SETUP REQUIRED FOR USER: $target"
            echo "════════════════════════════════════════════════════════════"
            echo ""
            echo "  You connected with a password, so no SSH key was migrated."
            echo "  After installation, you'll need to set up SSH access."
            echo ""
            echo "  EASIEST FIX - from your LOCAL machine, first try this if"
            echo "  you can still sign in as $target:"
            echo ""
            echo "    $target_user_repair_command"
            echo ""
            echo "  If that cannot connect, use the root fallback:"
            echo ""
            echo "    $root_repair_command"
            echo ""
            echo "  If you know the ${target} password and have ssh-copy-id, this can also work:"
            echo ""
            echo "    ssh-copy-id -i ~/.ssh/acfs_ed25519.pub ${target}@YOUR_SERVER_IP"
            echo ""
            echo "════════════════════════════════════════════════════════════"
            echo ""
            # Set a flag for the final summary
            export ACFS_SSH_KEY_WARNING="true"
        fi
        return 0
    fi

    log_detail "Migrating SSH keys from $source_keys"

    local ssh_dir="$target_home/.ssh"

    # Basic hardening: refuse to follow symlinks when writing keys.
    if [[ -e "$ssh_dir" ]] && [[ -L "$ssh_dir" ]]; then
        log_error "Refusing to manage SSH keys: $ssh_dir is a symlink"
        return 1
    fi

    # Create .ssh directory for target user
    $SUDO mkdir -p "$ssh_dir"

    # Merge authorized_keys (do not overwrite existing keys)
    local target_keys="$ssh_dir/authorized_keys"
    if [[ -e "$target_keys" ]] && [[ -L "$target_keys" ]]; then
        log_error "Refusing to manage SSH keys: $target_keys is a symlink"
        return 1
    fi
    if ! $SUDO touch "$target_keys" 2>/dev/null; then
        log_error "Failed to create: $target_keys"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        if $SUDO grep -Fxq "$line" "$target_keys" 2>/dev/null; then
            continue
        fi

        # Ensure target file ends with a newline before appending.
        # We use a robust check that handles files without any newlines at all.
        if [[ -s "$target_keys" ]]; then
            local last_char
            last_char=$($SUDO tail -c 1 "$target_keys" 2>/dev/null | od -An -t u1 | tr -d ' ' || true)
            if [[ "$last_char" != "10" ]]; then
                # Last char is not \n (ASCII 10)
                printf '\n' | $SUDO tee -a "$target_keys" >/dev/null
            fi
        fi

        if ! printf '%s\n' "$line" | $SUDO tee -a "$target_keys" >/dev/null; then
            log_error "Failed to append SSH key to: $target_keys"
            return 1
        fi
    done < "$source_keys"

    # Fix permissions
    $SUDO chown -hR "$target:$target" "$target_home/.ssh"
    $SUDO chmod 700 "$target_home/.ssh"
    $SUDO chmod 600 "$target_keys"

    log_success "SSH keys migrated to $target"
}

# Set default shell for target user
user_external_shell_handoff_configured() {
    local target_home="${1:-}"
    local bashrc_path=""

    [[ -n "$target_home" ]] || return 1
    bashrc_path="$target_home/.bashrc"
    [[ -f "$bashrc_path" ]] || return 1

    awk '
        $0 == "# ACFS externally-managed shell handoff" { marker=1; next }
        marker && $0 ~ /^[[:space:]]*#/ { next }
        marker && index($0, "command -v zsh") && index($0, "ACFS_ZSH_HANDOFF_ACTIVE") { found=1; exit }
        marker && $0 !~ /^[[:space:]]*$/ { marker=0 }
        END { exit(found ? 0 : 1) }
    ' "$bashrc_path" 2>/dev/null
}

user_append_external_shell_handoff() {
    local target_home="${1:-}"
    local bashrc_path=""
    bashrc_path="${target_home}/.bashrc"

    [[ -n "$target_home" ]] || return 1

    if [[ -f "$bashrc_path" ]] && [[ -s "$bashrc_path" ]]; then
        local last_char=""
        last_char=$(tail -c 1 "$bashrc_path" | od -An -t u1 | tr -d ' ' 2>/dev/null || true)
        if [[ "$last_char" != "10" ]]; then
            printf '\n' >> "$bashrc_path"
        fi
    fi

    cat >> "$bashrc_path" << 'EOF'
# ACFS externally-managed shell handoff
if [[ $- == *i* ]] && [[ -t 0 ]] && command -v zsh >/dev/null 2>&1 && [[ -z "${ACFS_ZSH_HANDOFF_ACTIVE:-}" ]]; then
    export ACFS_ZSH_HANDOFF_ACTIVE=1
    exec "$(command -v zsh)" -l
fi
EOF
}

set_default_shell() {
    local shell="$1"
    local target="$TARGET_USER"
    local target_home="${TARGET_HOME:-}"
    local passwd_entry=""
    local local_entry=""

    user_require_valid_target_user "$target"

    if [[ -z "$shell" ]]; then
        shell=$(command -v zsh)
    fi

    if [[ ! -x "$shell" ]]; then
        log_warn "Shell $shell not found or not executable"
        return 1
    fi

    passwd_entry="$(user_getent_passwd_entry "$target" 2>/dev/null || true)"
    if [[ -r /etc/passwd ]]; then
        while IFS= read -r local_entry; do
            [[ "${local_entry%%:*}" == "$target" ]] || continue
            break
        done < /etc/passwd
    fi

    if [[ -n "$passwd_entry" ]]; then
        target_home="$(user_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
    fi

    if [[ -n "$passwd_entry" ]] && [[ -z "$local_entry" ]]; then
        log_warn "Shell for $target is managed outside /etc/passwd; installing a bash-to-zsh handoff instead of using chsh"
        if [[ -n "$target_home" ]] && ! user_external_shell_handoff_configured "$target_home"; then
            user_append_external_shell_handoff "$target_home" || return 1
            $SUDO chown "$target:$target" "$target_home/.bashrc" 2>/dev/null || true
        fi
        return 0
    fi

    log_detail "Setting default shell to $shell for $target"
    $SUDO chsh -s "$shell" "$target"
}

# Get current user info
get_current_user_info() {
    echo "Current user: $(user_resolve_current_user 2>/dev/null || true)"
    echo "Home: $HOME"
    echo "Shell: $SHELL"
    echo "UID: $EUID"
    echo "Groups: $(groups)"
}

# Check if we can sudo without password
can_sudo_nopasswd() {
    if sudo -n true 2>/dev/null; then
        return 0
    fi
    return 1
}

# ============================================================
# SSH Key Prompting (Password-First Flow)
# ============================================================

# Prompt for an SSH public key when interactive, or keep existing root keys.
# Called when running as root before syncing root keys to the target user.
# Returns 0 on success or skip, 1 on invalid key
prompt_ssh_key() {
    # Skip entirely in CI mode - no TTY available and no need for SSH keys
    if [[ "${ACFS_CI:-false}" == "true" ]]; then
        log_detail "Skipping SSH key prompt (CI mode)"
        return 0
    fi

    local authorized_keys="/root/.ssh/authorized_keys"
    if [[ "${ACFS_TEST_MODE:-}" =~ ^(1|true)$ ]] && [[ -n "${ACFS_TEST_ROOT_AUTHORIZED_KEYS:-}" ]]; then
        authorized_keys="$ACFS_TEST_ROOT_AUTHORIZED_KEYS"
    fi
    local has_existing_key=false
    local existing_key_info=""

    # 1. Check if we already have a valid key - but DON'T skip, just note it
    # Match all OpenSSH key formats: ssh-*, ecdsa-sha2-*, sk-* (security keys)
    if [[ -f "$authorized_keys" ]]; then
        if grep -qE "^(ssh-|ecdsa-sha2-|sk-)" "$authorized_keys" 2>/dev/null; then
            has_existing_key=true
            # Get a brief description of existing keys for display
            existing_key_info=$(grep -E "^(ssh-|ecdsa-sha2-|sk-)" "$authorized_keys" 2>/dev/null | while read -r line; do
                # Show key type and comment (last field) only
                local key_type comment
                key_type=$(echo "$line" | awk '{print $1}')
                comment=$(echo "$line" | awk '{print $NF}')
                echo "  - $key_type ...${comment}"
            done | head -3)
        fi
    fi

    if [[ "${YES_MODE:-false}" == "true" ]]; then
        if [[ "$has_existing_key" == "true" ]]; then
            log_detail "SSH keys already present; keeping existing keys (--yes mode)"
        else
            log_warn "No SSH public key found for root; skipping SSH key prompt in --yes mode"
            log_detail "After install, add your key with: ssh-copy-id ${TARGET_USER:-ubuntu}@<ip>"
            export ACFS_SSH_KEY_WARNING="true"
        fi
        return 0
    fi

    # 2. Check if we can prompt the user (handle curl | bash pipe safely).
    # /dev/tty can exist but still be unattached in batch SSH sessions, so
    # probe it by opening a file descriptor instead of checking readability.
    local prompt_fd="stdin"
    if [[ ! -t 0 ]]; then
        if exec 3<>/dev/tty 2>/dev/null; then
            prompt_fd="tty"
        else
            prompt_fd=""
        fi
    fi

    if [[ -z "$prompt_fd" ]]; then
        if [[ "$has_existing_key" == "true" ]]; then
            log_detail "SSH key already present (non-interactive mode)"
            return 0
        fi
        log_warn "Non-interactive mode detected (no TTY), skipping SSH key prompt"
        log_detail "After install, add your key with: ssh-copy-id ${TARGET_USER:-ubuntu}@<ip>"
        export ACFS_SSH_KEY_WARNING="true"
        return 0
    fi

    # 3. Display prompt UI - different message if keys already exist
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  SSH Key Setup                                               ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    if [[ "$has_existing_key" == "true" ]]; then
        echo "║  SSH keys already exist on this server:                     ║"
        echo "╠══════════════════════════════════════════════════════════════╣"
        echo "$existing_key_info"
        echo "║                                                              ║"
        echo "║  If these are YOUR keys, press Enter to skip.               ║"
        echo "║  If you need to ADD your local key, paste it below.         ║"
    else
        echo "║  Let's set up SSH key authentication so you won't need      ║"
        echo "║  to enter a password every time you connect.                ║"
    fi
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Your public key should start with:"
    echo "  ssh-ed25519 AAAAC3NzaC1...  OR  ssh-rsa AAAAB3NzaC1..."
    echo ""
    echo "You saved this earlier when you ran ssh-keygen on your computer."
    if [[ "$has_existing_key" == "true" ]]; then
        echo "(Press Enter to keep existing keys only)"
    else
        echo "(Press Enter to skip - you'll need password for future logins)"
    fi
    echo ""

    # 4. Read the key (handle pipe vs tty)
    local pubkey=""
    if [[ "$prompt_fd" == "stdin" ]]; then
        echo -n "Paste your public key: "
        read -r pubkey < /dev/tty || true
    else
        # When running via curl | bash, stdin is the script content.
        # We opened FD 3 above so we can safely read from the controlling TTY.
        echo -n "Paste your public key: " >&2
        read -r pubkey <&3 || true
        exec 3>&- 3<&-
    fi

    # 5. Handle skip (empty input)
    if [[ -z "$pubkey" ]]; then
        if [[ "$has_existing_key" == "true" ]]; then
            log_detail "Keeping existing SSH keys"
        else
            log_warn "SSH key setup skipped"
            log_detail "From your local machine, you can add your key later by running:"
            log_detail "  ssh-copy-id -i ~/.ssh/acfs_ed25519.pub ${TARGET_USER:-ubuntu}@<ip>"
            export ACFS_SSH_KEY_WARNING="true"
        fi
        return 0
    fi

    # 6. Validate key format
    # Supported formats:
    #   ssh-ed25519, ssh-rsa, ssh-dss (legacy DSA)
    #   ecdsa-sha2-nistp256, ecdsa-sha2-nistp384, ecdsa-sha2-nistp521
    #   sk-ssh-ed25519@openssh.com, sk-ecdsa-sha2-nistp256@openssh.com (security keys)
    if [[ ! "$pubkey" =~ ^(ssh-(ed25519|rsa|dss)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com)[[:space:]] ]]; then
        log_error "Invalid SSH key format"
        log_detail "Expected format: ssh-ed25519 AAAA... or ssh-rsa AAAA..."
        log_detail "Make sure you copied the PUBLIC key (the .pub file)"
        return 1
    fi

    # 7. Install the key
    local authorized_keys_dir="${authorized_keys%/*}"
    if [[ -z "$authorized_keys_dir" || "$authorized_keys_dir" == "$authorized_keys" ]]; then
        authorized_keys_dir="/root/.ssh"
    fi
    if [[ -L "$authorized_keys_dir" ]]; then
        log_error "Refusing to manage SSH keys: $authorized_keys_dir is a symlink"
        return 1
    fi
    mkdir -p "$authorized_keys_dir"
    chmod 700 "$authorized_keys_dir"

    if [[ -L "$authorized_keys" ]]; then
        log_error "Refusing to manage SSH keys: $authorized_keys is a symlink"
        return 1
    fi
    touch "$authorized_keys"
    if grep -Fxq "$pubkey" "$authorized_keys" 2>/dev/null; then
        chmod 600 "$authorized_keys"
        log_detail "SSH key already present; not adding duplicate"
        return 0
    fi

    # Ensure authorized_keys ends with a newline before appending.
    if [[ -s "$authorized_keys" ]]; then
        local last_char
        last_char=$(tail -c 1 "$authorized_keys" | od -An -t u1 | tr -d ' ' 2>/dev/null || true)
        if [[ "$last_char" != "10" ]]; then
            printf '\n' >> "$authorized_keys"
        fi
    fi

    printf '%s\n' "$pubkey" >> "$authorized_keys"
    chmod 600 "$authorized_keys"

    log_success "SSH key installed successfully"
    log_detail "You can now connect with: ssh -i ~/.ssh/your_key root@<this_ip>"

    return 0
}

# Full user normalization sequence
# NOTE: install.sh defines its own normalize_user phase function. This library is
# sourced by install.sh at runtime, so we must avoid overriding existing
# definitions (TARGET_USER handling + newer idempotency logic live in install.sh).
if ! declare -f normalize_user >/dev/null 2>&1; then
    normalize_user() {
        log_step "1/8" "Normalizing user account..."

        ensure_user

        local mode="${MODE:-${ACFS_MODE:-vibe}}"
        if [[ "$mode" == "vibe" ]]; then
            enable_passwordless_sudo
        fi

        migrate_ssh_keys

        log_success "User normalization complete"
    }
fi
