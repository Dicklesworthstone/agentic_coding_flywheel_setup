#!/usr/bin/env bash
# ============================================================
# ACFS Installer - User Normalization Library
# Ensures consistent user setup across VPS providers
#
# Requires:
#   - logging.sh to be sourced first for log_* functions
#   - $SUDO to be set (empty string for root, "sudo" otherwise)
# ============================================================

# Fallback logging if logging.sh not sourced
if ! declare -f log_fatal &>/dev/null; then
    log_fatal() { echo "FATAL: $1" >&2; exit 1; }
    log_detail() { echo "  $1" >&2; }
    log_warn() { echo "WARN: $1" >&2; }
    log_success() { echo "OK: $1" >&2; }
    log_error() { echo "ERROR: $1" >&2; }
    log_step() { echo "[$1] $2" >&2; }
fi

# Ensure SUDO is set
: "${SUDO:=sudo}"

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
        log_warn "No SSH keys found to migrate"
        return 0
    fi

    log_detail "Migrating SSH keys from $source_keys"

    # Create .ssh directory for target user
    $SUDO mkdir -p "$ACFS_TARGET_HOME/.ssh"

    # Copy authorized_keys
    $SUDO cp "$source_keys" "$ACFS_TARGET_HOME/.ssh/authorized_keys"

    # Fix permissions
    $SUDO chown -R "$target:$target" "$ACFS_TARGET_HOME/.ssh"
    $SUDO chmod 700 "$ACFS_TARGET_HOME/.ssh"
    $SUDO chmod 600 "$ACFS_TARGET_HOME/.ssh/authorized_keys"

    log_success "SSH keys migrated to $target"
}

# Set default shell for target user
set_default_shell() {
    local shell="$1"
    local target="$ACFS_TARGET_USER"

    if [[ -z "$shell" ]]; then
        shell=$(which zsh)
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
    local authorized_keys="/root/.ssh/authorized_keys"

    # 1. Check if we already have a valid key
    if [[ -f "$authorized_keys" ]]; then
        if grep -q "^ssh-" "$authorized_keys" 2>/dev/null; then
            log_detail "SSH key already present, skipping prompt"
            return 0
        fi
    fi

    # 2. Check if stdin is a terminal (interactive mode)
    if [[ ! -t 0 ]]; then
        log_warn "Non-interactive mode detected, skipping SSH key prompt"
        log_detail "You can add your key later with: ssh-copy-id root@<ip>"
        return 0
    fi

    # 3. Display prompt UI
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  SSH Key Setup                                               ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  Let's set up SSH key authentication so you won't need      ║"
    echo "║  to enter a password every time you connect.                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Your public key should start with:"
    echo "  ssh-ed25519 AAAAC3NzaC1...  OR  ssh-rsa AAAAB3NzaC1..."
    echo ""
    echo "You saved this earlier when you ran ssh-keygen on your computer."
    echo "(Press Enter to skip - you'll need password for future logins)"
    echo ""

    # 4. Read the key
    local pubkey
    read -r -p "Paste your public key: " pubkey

    # 5. Handle skip (empty input)
    if [[ -z "$pubkey" ]]; then
        log_warn "SSH key setup skipped"
        log_detail "You can add your key later by running:"
        log_detail "  echo 'your-key-here' >> ~/.ssh/authorized_keys"
        return 0
    fi

    # 6. Validate key format
    if [[ ! "$pubkey" =~ ^ssh-(ed25519|rsa|ecdsa|dss)[[:space:]] ]]; then
        log_error "Invalid SSH key format"
        log_detail "Expected format: ssh-ed25519 AAAA... or ssh-rsa AAAA..."
        log_detail "Make sure you copied the PUBLIC key (the .pub file)"
        return 1
    fi

    # 7. Install the key
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo "$pubkey" >> "$authorized_keys"
    chmod 600 "$authorized_keys"

    log_success "SSH key installed successfully"
    log_detail "You can now connect with: ssh -i ~/.ssh/your_key root@<this_ip>"

    return 0
}

# Full user normalization sequence
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
