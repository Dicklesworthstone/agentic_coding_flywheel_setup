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
    log_fatal() { echo "FATAL: $1" >&2; exit 1; }
    log_detail() { echo "  $1" >&2; }
    log_warn() { echo "WARN: $1" >&2; }
    log_success() { echo "OK: $1" >&2; }
    log_error() { echo "ERROR: $1" >&2; }
    log_step() { echo "[$1] $2" >&2; }
fi

# Ensure SUDO is set (empty string for root, "sudo" otherwise)
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    : "${SUDO:=sudo}"
fi

# Target user for ACFS installations
ACFS_TARGET_USER="${ACFS_TARGET_USER:-ubuntu}"
ACFS_TARGET_HOME="/home/$ACFS_TARGET_USER"

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
    local target="$ACFS_TARGET_USER"

    if ! id "$target" &>/dev/null; then
        log_detail "Creating user: $target"
        $SUDO useradd -m -s /bin/bash -G sudo "$target"

        # Generate random password (user will use SSH key)
        local passwd
        passwd=$(_generate_random_password)
        
        if [[ -n "$passwd" ]]; then
            echo "$target:$passwd" | $SUDO chpasswd
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
    local target="$ACFS_TARGET_USER"
    local sudoers_file="/etc/sudoers.d/90-ubuntu-acfs"

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
    current_user=$(whoami)
    local target="$ACFS_TARGET_USER"

    # Nothing to do if we're already the target user
    if [[ "$current_user" == "$target" ]]; then
        log_detail "Already running as $target, no key migration needed"
        return 0
    fi

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
            echo ""
            echo "════════════════════════════════════════════════════════════"
            echo "  ⚠  SSH KEY SETUP REQUIRED FOR USER: $target"
            echo "════════════════════════════════════════════════════════════"
            echo ""
            echo "  You connected with a password, so no SSH key was migrated."
            echo "  After installation, you'll need to set up SSH access."
            echo ""
            echo "  EASIEST FIX - from your LOCAL machine, run:"
            echo ""
            echo "    ssh-copy-id ${target}@YOUR_SERVER_IP"
            echo ""
            echo "  Or manually: SSH in as root and run these commands:"
            echo ""
            echo "    mkdir -p ${ACFS_TARGET_HOME}/.ssh"
            echo "    cat >> ${ACFS_TARGET_HOME}/.ssh/authorized_keys << 'EOF'"
            echo "    YOUR_PUBLIC_KEY_HERE"
            echo "    EOF"
            echo "    chown -R ${target}:${target} ${ACFS_TARGET_HOME}/.ssh"
            echo "    chmod 700 ${ACFS_TARGET_HOME}/.ssh"
            echo "    chmod 600 ${ACFS_TARGET_HOME}/.ssh/authorized_keys"
            echo ""
            echo "════════════════════════════════════════════════════════════"
            echo ""
            # Set a flag for the final summary
            export ACFS_SSH_KEY_WARNING="true"
        fi
        return 0
    fi

    log_detail "Migrating SSH keys from $source_keys"

    local ssh_dir="$ACFS_TARGET_HOME/.ssh"

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
        if $SUDO bash -c "[[ -s \"$target_keys\" ]] && [[ -n \"\$(tail -c 1 \"$target_keys\")\" ]]"; then
            # File has content and last char is not newline
            printf '\n' | $SUDO tee -a "$target_keys" >/dev/null
        fi

        if ! printf '%s\n' "$line" | $SUDO tee -a "$target_keys" >/dev/null; then
            log_error "Failed to append SSH key to: $target_keys"
            return 1
        fi
    done < "$source_keys"

    # Fix permissions
    $SUDO chown -hR "$target:$target" "$ACFS_TARGET_HOME/.ssh"
    $SUDO chmod 700 "$ACFS_TARGET_HOME/.ssh"
    $SUDO chmod 600 "$target_keys"

    log_success "SSH keys migrated to $target"
}

# Set default shell for target user
set_default_shell() {
    local shell="$1"
    local target="$ACFS_TARGET_USER"

    if [[ -z "$shell" ]]; then
        shell=$(command -v zsh)
    fi

    if [[ ! -x "$shell" ]]; then
        log_warn "Shell $shell not found or not executable"
        return 1
    fi

    log_detail "Setting default shell to $shell for $target"
    $SUDO chsh -s "$shell" "$target"
}

# Get current user info
get_current_user_info() {
    echo "Current user: $(whoami)"
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

# Prompt user for SSH public key and install it
# Called when running as root with no existing key
# Returns 0 on success or skip, 1 on invalid key
prompt_ssh_key() {
    # Skip entirely in CI mode - no TTY available and no need for SSH keys
    if [[ "${ACFS_CI:-false}" == "true" ]]; then
        log_detail "Skipping SSH key prompt (CI mode)"
        return 0
    fi

    local authorized_keys="/root/.ssh/authorized_keys"
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

    # 2. Check if we can prompt the user (handle curl | bash pipe)
    if [[ ! -t 0 ]] && [[ ! -r /dev/tty ]]; then
        if [[ "$has_existing_key" == "true" ]]; then
            log_detail "SSH key already present (non-interactive mode)"
            return 0
        fi
        log_warn "Non-interactive mode detected (no TTY), skipping SSH key prompt"
        log_detail "You can add your key later with: ssh-copy-id root@<ip>"
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
    local pubkey
    if [[ -t 0 ]]; then
        read -r -p "Paste your public key: " pubkey
    else
        # When running via curl | bash, stdin is the script content.
        # We must read from /dev/tty to get user input.
        # Note: read -p writes prompt to stderr, which is visible.
        # We manually print prompt to stderr to be explicit/consistent.
        echo -n "Paste your public key: " >&2
        read -r pubkey < /dev/tty
    fi

    # 5. Handle skip (empty input)
    if [[ -z "$pubkey" ]]; then
        if [[ "$has_existing_key" == "true" ]]; then
            log_detail "Keeping existing SSH keys"
        else
            log_warn "SSH key setup skipped"
            log_detail "You can add your key later by running:"
            log_detail "  echo 'your-key-here' >> ~/.ssh/authorized_keys"
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
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh

    # Ensure authorized_keys ends with a newline before appending.
    if [[ -s "$authorized_keys" ]] && [[ -n "$(tail -c 1 "$authorized_keys")" ]]; then
        printf '\n' >> "$authorized_keys"
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
