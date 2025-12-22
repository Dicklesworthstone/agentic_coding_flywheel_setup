#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - Cloud & Database Tools Library
# Installs PostgreSQL, HashiCorp Vault, and Cloud CLIs
# ============================================================

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=logging.sh
    source "$SCRIPT_DIR/logging.sh"
fi

# ============================================================
# Configuration
# ============================================================

# PostgreSQL version to install
POSTGRESQL_VERSION="${POSTGRESQL_VERSION:-18}"

# Cloud CLI npm packages (installed via bun)
CLOUD_CLIS=(
    "wrangler"       # Cloudflare Workers CLI
    "supabase"       # Supabase CLI
    "vercel"         # Vercel CLI
)

# ============================================================
# Helper Functions
# ============================================================

# Security: Validate username contains only safe characters (alphanumeric + underscore + hyphen)
# Prevents SQL injection and command injection via username
_cloud_validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
        log_error "Invalid username format: $username (must be alphanumeric + underscore/hyphen)"
        return 1
    fi
    # Also check reasonable length
    if [[ ${#username} -gt 63 ]]; then
        log_error "Username too long: $username (max 63 characters)"
        return 1
    fi
    return 0
}

# Check if a command exists
_cloud_command_exists() {
    command -v "$1" &>/dev/null
}

# Get the sudo command if needed
_cloud_get_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo ""
    else
        echo "sudo"
    fi
}

# Run a command as target user
_cloud_run_as_user() {
    local target_user="${TARGET_USER:-ubuntu}"
    local cmd="$1"
    local wrapped_cmd="set -o pipefail; $cmd"

    if [[ "$(whoami)" == "$target_user" ]]; then
        bash -c "$wrapped_cmd"
        return $?
    fi

    if command -v sudo &>/dev/null; then
        sudo -u "$target_user" -H bash -c "$wrapped_cmd"
        return $?
    fi

    if command -v runuser &>/dev/null; then
        runuser -u "$target_user" -- bash -c "$wrapped_cmd"
        return $?
    fi

    su - "$target_user" -c "bash -c $(printf %q "$wrapped_cmd")"
}

_cloud_run_as_postgres() {
    local cmd="$1"
    local wrapped_cmd="set -o pipefail; $cmd"

    if [[ $EUID -eq 0 ]]; then
        if command -v runuser &>/dev/null; then
            runuser -u postgres -- bash -c "$wrapped_cmd"
            return $?
        fi

        su - postgres -c "bash -c $(printf %q "$wrapped_cmd")"
        return $?
    fi

    sudo -u postgres -H bash -c "$wrapped_cmd"
}

# Get bun binary path for target user
_cloud_get_bun_bin() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    echo "$target_home/.bun/bin/bun"
}

# Get Ubuntu codename
_cloud_get_codename() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        local codename="${VERSION_CODENAME:-noble}"
        case "$codename" in
            oracular|plucky|questing) codename="noble" ;;
        esac
        echo "$codename"
    else
        echo "noble"  # Default to Ubuntu 24.04
    fi
}

# ============================================================
# PostgreSQL Installation
# ============================================================

# Install PostgreSQL from official PGDG repository
install_postgresql() {
    local sudo_cmd
    sudo_cmd=$(_cloud_get_sudo)
    local pg_version="${POSTGRESQL_VERSION:-18}"

    # Check if already installed
    if _cloud_command_exists psql; then
        local installed_version
        installed_version=$(psql --version 2>/dev/null | grep -oP '\d+' | head -1 || echo "unknown")
        log_detail "PostgreSQL already installed (version $installed_version)"
        return 0
    fi

    log_detail "Installing PostgreSQL $pg_version..."

    # Get Ubuntu codename
    local codename
    codename=$(_cloud_get_codename)

    # Add PostgreSQL APT repository
    log_detail "Adding PostgreSQL APT repository..."
    $sudo_cmd mkdir -p /etc/apt/keyrings

    # Download and install the repository signing key
    # Use --yes to overwrite existing keyring file without prompting
    if ! curl --proto '=https' --proto-redir '=https' -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
        $sudo_cmd gpg --batch --yes --dearmor -o /etc/apt/keyrings/postgresql.gpg 2>/dev/null; then
        log_warn "Failed to download/install PostgreSQL signing key"
        return 1
    fi

    # Add repository
    echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main" | \
        $sudo_cmd tee /etc/apt/sources.list.d/pgdg.list > /dev/null

    # Update and install
    log_detail "Installing PostgreSQL $pg_version packages..."
    $sudo_cmd apt-get update -y >/dev/null 2>&1 || true

    if $sudo_cmd apt-get install -y "postgresql-${pg_version}" "postgresql-client-${pg_version}" >/dev/null 2>&1; then
        log_success "PostgreSQL $pg_version installed"

        # Start and enable service
        if _cloud_command_exists systemctl; then
            $sudo_cmd systemctl enable postgresql >/dev/null 2>&1 || true
            $sudo_cmd systemctl start postgresql >/dev/null 2>&1 || true
            log_detail "PostgreSQL service enabled and started"
        fi

        return 0
    else
        log_warn "PostgreSQL installation failed"
        return 1
    fi
}

# Configure PostgreSQL for development use
configure_postgresql() {
    local target_user="${TARGET_USER:-ubuntu}"

    # Security: Validate username before using in SQL/commands
    if ! _cloud_validate_username "$target_user"; then
        log_error "Cannot configure PostgreSQL: invalid target user"
        return 1
    fi

    log_detail "Configuring PostgreSQL for development..."

    # Create role for target user if it doesn't exist
    if _cloud_run_as_postgres "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='$target_user'\" | grep -q 1"; then
        log_detail "PostgreSQL role '$target_user' already exists"
    else
        log_detail "Creating PostgreSQL role '$target_user'..."
        _cloud_run_as_postgres "createuser -s '$target_user'" 2>/dev/null || true
    fi

    # Create database for target user if it doesn't exist
    if _cloud_run_as_postgres "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='$target_user'\" | grep -q 1"; then
        log_detail "PostgreSQL database '$target_user' already exists"
    else
        log_detail "Creating PostgreSQL database '$target_user'..."
        _cloud_run_as_postgres "createdb '$target_user'" 2>/dev/null || true
    fi

    log_success "PostgreSQL configured for $target_user"
}

# ============================================================
# HashiCorp Vault Installation
# ============================================================

# Install HashiCorp Vault
install_vault() {
    local sudo_cmd
    sudo_cmd=$(_cloud_get_sudo)

    # Check if already installed
    if _cloud_command_exists vault; then
        log_detail "Vault already installed"
        return 0
    fi

    log_detail "Installing HashiCorp Vault..."

    # Add HashiCorp GPG key and repository
    $sudo_cmd mkdir -p /etc/apt/keyrings

    # Use --yes to overwrite existing keyring file without prompting
    if ! curl --proto '=https' --proto-redir '=https' -fsSL https://apt.releases.hashicorp.com/gpg | \
        $sudo_cmd gpg --batch --yes --dearmor -o /etc/apt/keyrings/hashicorp.gpg 2>/dev/null; then
        log_warn "Failed to download/install HashiCorp signing key"
        return 1
    fi

    # Get Ubuntu codename
    local codename
    codename=$(_cloud_get_codename)

    echo "deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${codename} main" | \
        $sudo_cmd tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

    # Update and install
    $sudo_cmd apt-get update -y >/dev/null 2>&1 || true

    if $sudo_cmd apt-get install -y vault >/dev/null 2>&1; then
        log_success "Vault installed"
        return 0
    else
        log_warn "Vault installation failed"
        return 1
    fi
}

# ============================================================
# Cloud CLI Installation
# ============================================================

# Install a single cloud CLI via bun
_install_cloud_cli() {
    local cli="$1"
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local bun_bin
    bun_bin=$(_cloud_get_bun_bin)
    local cli_bin="$target_home/.bun/bin/$cli"

    # Check if already installed
    if [[ -x "$cli_bin" ]]; then
        log_detail "$cli already installed"
        return 0
    fi

    log_detail "Installing $cli..."

    if _cloud_run_as_user "\"$bun_bin\" install -g $cli@latest"; then
        if [[ -x "$cli_bin" ]]; then
            log_success "$cli installed"
            return 0
        fi
    fi

    log_warn "$cli installation may have failed"
    return 1
}

# Install Cloudflare Wrangler CLI
install_wrangler() {
    local bun_bin
    bun_bin=$(_cloud_get_bun_bin)

    if [[ ! -x "$bun_bin" ]]; then
        log_warn "Bun not found, skipping Wrangler installation"
        return 1
    fi

    _install_cloud_cli "wrangler"
}

# Install Supabase CLI
install_supabase() {
    local bun_bin
    bun_bin=$(_cloud_get_bun_bin)

    if [[ ! -x "$bun_bin" ]]; then
        log_warn "Bun not found, skipping Supabase CLI installation"
        return 1
    fi

    _install_cloud_cli "supabase"
}

# Install Vercel CLI
install_vercel() {
    local bun_bin
    bun_bin=$(_cloud_get_bun_bin)

    if [[ ! -x "$bun_bin" ]]; then
        log_warn "Bun not found, skipping Vercel CLI installation"
        return 1
    fi

    _install_cloud_cli "vercel"
}

# Install all cloud CLIs
install_cloud_clis() {
    local bun_bin
    bun_bin=$(_cloud_get_bun_bin)

    if [[ ! -x "$bun_bin" ]]; then
        log_warn "Bun not found at $bun_bin, skipping cloud CLI installation"
        return 1
    fi

    log_detail "Installing cloud CLIs..."

    for cli in "${CLOUD_CLIS[@]}"; do
        _install_cloud_cli "$cli"
    done

    log_success "Cloud CLIs installed"
}

# ============================================================
# Verification Functions
# ============================================================

# Verify all cloud and database tools
verify_cloud_db() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local all_pass=true

    log_detail "Verifying cloud & database tools..."

    # Check PostgreSQL
    if [[ "${SKIP_POSTGRES:-false}" == "true" ]]; then
        log_detail "  psql: skipped (SKIP_POSTGRES=true)"
    elif _cloud_command_exists psql; then
        local pg_version
        pg_version=$(psql --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1 || echo "installed")
        log_detail "  psql: $pg_version"

        # Check if service is running
        if _cloud_command_exists systemctl; then
            if systemctl is-active --quiet postgresql 2>/dev/null; then
                log_detail "  postgresql service: running"
            else
                log_warn "  postgresql service: not running"
            fi
        fi
    else
        log_warn "  Missing: psql (PostgreSQL)"
        all_pass=false
    fi

    # Check Vault
    if [[ "${SKIP_VAULT:-false}" == "true" ]]; then
        log_detail "  vault: skipped (SKIP_VAULT=true)"
    elif _cloud_command_exists vault; then
        local vault_version
        vault_version=$(vault --version 2>/dev/null | head -1 || echo "installed")
        log_detail "  vault: $vault_version"
    else
        log_warn "  Missing: vault"
        all_pass=false
    fi

    # Check cloud CLIs
    local bun_bin_dir="$target_home/.bun/bin"
    if [[ "${SKIP_CLOUD:-false}" == "true" ]]; then
        log_detail "  cloud CLIs: skipped (SKIP_CLOUD=true)"
    else
        for cli in "${CLOUD_CLIS[@]}"; do
            if [[ -x "$bun_bin_dir/$cli" ]]; then
                log_detail "  $cli: installed"
            else
                log_warn "  Missing: $cli"
                all_pass=false
            fi
        done
    fi

    if [[ "$all_pass" == "true" ]]; then
        log_success "All cloud & database tools verified"
        return 0
    else
        log_warn "Some cloud & database tools are missing"
        return 1
    fi
}

# Get versions of installed tools (for doctor output)
get_cloud_db_versions() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home="${TARGET_HOME:-/home/$target_user}"
    local bun_bin_dir="$target_home/.bun/bin"

    echo "Cloud & Database Tool Versions:"

    _cloud_command_exists psql && echo "  psql: $(psql --version 2>/dev/null | head -1)"
    _cloud_command_exists vault && echo "  vault: $(vault --version 2>/dev/null | head -1)"

    for cli in "${CLOUD_CLIS[@]}"; do
        if [[ -x "$bun_bin_dir/$cli" ]]; then
            echo "  $cli: $("$bun_bin_dir/$cli" --version 2>/dev/null | head -1 || echo 'installed')"
        fi
    done
}

# ============================================================
# Main Installation Function
# ============================================================

# Install all cloud and database tools (called by install.sh)
# Respects SKIP_POSTGRES, SKIP_VAULT, SKIP_CLOUD flags
install_all_cloud_db() {
    log_step "4b/8" "Installing cloud & database tools..."

    # PostgreSQL (unless skipped)
    if [[ "${SKIP_POSTGRES:-false}" != "true" ]]; then
        if ! install_postgresql; then
            log_warn "PostgreSQL install failed"
            return 1
        fi
        if ! configure_postgresql; then
            log_warn "PostgreSQL configuration failed"
            return 1
        fi
    else
        log_detail "Skipping PostgreSQL (SKIP_POSTGRES=true)"
    fi

    # Vault (unless skipped)
    if [[ "${SKIP_VAULT:-false}" != "true" ]]; then
        if ! install_vault; then
            log_warn "Vault install failed"
            return 1
        fi
    else
        log_detail "Skipping Vault (SKIP_VAULT=true)"
    fi

    # Cloud CLIs (unless skipped)
    if [[ "${SKIP_CLOUD:-false}" != "true" ]]; then
        if ! install_cloud_clis; then
            log_warn "Cloud CLI install failed"
            return 1
        fi
    else
        log_detail "Skipping cloud CLIs (SKIP_CLOUD=true)"
    fi

    # Verify installation
    verify_cloud_db

    log_success "Cloud & database tools installation complete"
}

# ============================================================
# Module can be sourced or run directly
# ============================================================

# If run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_all_cloud_db "$@"
fi
