#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Installer - CLI Tools Library
# Installs modern CLI replacements that acfs.zshrc depends on
# ============================================================

CLI_TOOLS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure we have logging functions available
if [[ -z "${ACFS_BLUE:-}" ]]; then
    # shellcheck source=logging.sh
    source "$CLI_TOOLS_SCRIPT_DIR/logging.sh"
fi

# ============================================================
# Configuration
# ============================================================

# APT packages (available in Ubuntu 24.04+)
APT_CLI_TOOLS=(
    ripgrep         # rg - fast grep
    fd-find         # fd - fast find
    fzf             # fuzzy finder
    tmux            # terminal multiplexer
    neovim          # better vim
    direnv          # directory-specific env vars
    jq              # JSON processor
    gh              # GitHub CLI (auth, issues, PRs)
    git-lfs         # Git LFS (large files)
    rsync           # fast file sync/copy
    lsof            # open files / ports debugging
    dnsutils        # dig/nslookup for DNS debugging
    netcat-openbsd  # nc for network debugging
    strace          # syscall tracing
    htop            # process viewer (fallback for btop)
    tree            # directory tree viewer
    ncdu            # interactive disk usage
    httpie          # better curl for APIs
    entr            # run commands when files change
    mtr             # better traceroute
    pv              # pipe viewer (progress bars)
)

# APT packages that may not be available on all Ubuntu versions
APT_CLI_TOOLS_OPTIONAL=(
    bat             # better cat (may be 'batcat' on older Ubuntu)
    lsd             # modern ls with icons
    eza             # modern ls alternative
    btop            # better top
    dust            # better du
    git-delta       # beautiful git diffs (provides 'delta' command)
)

# Cargo packages (for latest versions or missing apt packages)
# shellcheck disable=SC2034  # Used for documentation/reference
CARGO_CLI_TOOLS=(
    zoxide          # better cd (z command)
    ast-grep        # structural grep (sg command)
    tealdeer        # tldr - simplified man pages
)

# ============================================================
# Helper Functions
# ============================================================

# Check if a command exists
_cli_command_exists() {
    command -v "$1" &>/dev/null
}

_cli_remove_temp_dir() {
    local tmpdir="${1:-}"
    if [[ -n "$tmpdir" && -d "$tmpdir" ]]; then
        rm -rf -- "$tmpdir" 2>/dev/null || true
    fi
}

_cli_target_has_command() {
    local cmd="${1:-}"
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    local primary_bin=""
    local candidate=""

    [[ -n "$cmd" ]] || return 1
    case "$cmd" in
        .|..) return 1 ;;
        *[!A-Za-z0-9._+-]*) return 1 ;;
    esac

    target_home="$(_cli_target_home "$target_user" 2>/dev/null || true)"
    [[ -n "$target_home" ]] || return 1

    primary_bin="$(_cli_preferred_bin_dir "$target_home" 2>/dev/null || true)"
    [[ -n "$primary_bin" ]] || primary_bin="$target_home/.local/bin"
    for candidate in \
        "$primary_bin/$cmd" \
        "$target_home/.local/bin/$cmd" \
        "$target_home/.acfs/bin/$cmd" \
        "$target_home/.cargo/bin/$cmd" \
        "$target_home/.bun/bin/$cmd" \
        "$target_home/.atuin/bin/$cmd" \
        "$target_home/go/bin/$cmd" \
        "/usr/local/bin/$cmd" \
        "/usr/local/sbin/$cmd" \
        "/usr/bin/$cmd" \
        "/bin/$cmd" \
        "/snap/bin/$cmd"; do
        [[ -x "$candidate" ]] && return 0
    done
    return 1
}

# Get the sudo command if needed
_cli_get_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo ""
    else
        echo "sudo"
    fi
}

_cli_existing_abs_home() {
    local home_candidate="${1:-}"

    [[ -n "$home_candidate" ]] || return 1
    home_candidate="${home_candidate%/}"
    [[ -n "$home_candidate" ]] || return 1
    [[ "$home_candidate" == /* ]] || return 1
    [[ "$home_candidate" != "/" ]] || return 1
    [[ -d "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

_cli_system_binary_path() {
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

_cli_resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(_cli_system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(_cli_system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

_cli_getent_passwd_entry() {
    local user="${1-}"
    local getent_bin=""
    local passwd_entry=""
    local passwd_line=""
    local printed_any=false

    getent_bin="$(_cli_system_binary_path getent 2>/dev/null || true)"
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

_cli_passwd_home_from_entry() {
    local passwd_entry="${1:-}"
    local passwd_home=""

    [[ -n "$passwd_entry" ]] || return 1
    IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
    passwd_home="$(_cli_existing_abs_home "$passwd_home" 2>/dev/null || true)"
    [[ -n "$passwd_home" ]] || return 1
    printf '%s\n' "$passwd_home"
}

_cli_target_home() {
    local target_user="${1:-${TARGET_USER:-ubuntu}}"
    local explicit_home=""
    local explicit_bin_dir=""
    local passwd_entry=""
    local current_user=""
    local current_home=""

    explicit_home="$(_cli_existing_abs_home "${TARGET_HOME:-}" 2>/dev/null || true)"
    explicit_bin_dir="$(_cli_existing_abs_home "${ACFS_BIN_DIR:-}" 2>/dev/null || true)"
    current_user="$(_cli_resolve_current_user 2>/dev/null || true)"
    if [[ "$target_user" == "root" ]]; then
        printf '/root\n'
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
    if [[ -n "$explicit_home" ]] \
        && [[ -n "${ACFS_BIN_DIR:-}" ]] \
        && [[ -z "$(_cli_validate_bin_dir_for_home "$explicit_bin_dir" "$explicit_home" 2>/dev/null || true)" ]] \
        && [[ "$target_user" == "$current_user" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    passwd_entry="$(_cli_getent_passwd_entry "$target_user" 2>/dev/null || true)"
    if [[ -n "$passwd_entry" ]]; then
        passwd_entry="$(_cli_passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            printf '%s\n' "${passwd_entry%/}"
            return 0
        fi
    fi

    if [[ "$current_user" == "$target_user" ]]; then
        current_home="$(_cli_existing_abs_home "${HOME:-}" 2>/dev/null || true)"
        if [[ -n "$current_home" ]] && { [[ -z "$explicit_home" ]] || [[ "$current_home" == "$explicit_home" ]]; }; then
            printf '%s\n' "$current_home"
            return 0
        fi
    fi

    if [[ -n "$explicit_home" ]]; then
        printf '%s\n' "$explicit_home"
        return 0
    fi

    return 1
}

_cli_validate_target_user() {
    local username="${1:-${TARGET_USER:-}}"
    local display="${username:-<empty>}"

    if [[ "$username" =~ ^[a-z_][a-z0-9._-]*$ ]]; then
        return 0
    fi

    log_error "Invalid TARGET_USER '$display' (expected: lowercase user name like 'ubuntu')"
    return 1
}

_cli_validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="${bin_dir%/}"
    [[ -n "$bin_dir" ]] || return 1
    [[ "$bin_dir" == /* ]] || return 1
    [[ "$bin_dir" != "/" ]] || return 1
    base_home="$(_cli_existing_abs_home "$base_home" 2>/dev/null || true)"

    if [[ -n "$base_home" ]] && [[ "$bin_dir" == "$base_home" || "$bin_dir" == "$base_home/"* ]]; then
        printf '%s\n' "$bin_dir"
        return 0
    fi

    case "$bin_dir" in
        */.local/bin) hinted_home="${bin_dir%/.local/bin}" ;;
        */.acfs/bin) hinted_home="${bin_dir%/.acfs/bin}" ;;
        */.bun/bin) hinted_home="${bin_dir%/.bun/bin}" ;;
        */.cargo/bin) hinted_home="${bin_dir%/.cargo/bin}" ;;
        */.atuin/bin) hinted_home="${bin_dir%/.atuin/bin}" ;;
        */go/bin) hinted_home="${bin_dir%/go/bin}" ;;
        */google-cloud-sdk/bin) hinted_home="${bin_dir%/google-cloud-sdk/bin}" ;;
    esac
    hinted_home="${hinted_home%/}"
    if [[ "$hinted_home" != /* ]] || [[ "$hinted_home" == "/" ]]; then
        hinted_home=""
    fi
    if [[ -n "$hinted_home" ]] && [[ -n "$base_home" ]] && [[ "$hinted_home" != "$base_home" ]]; then
        return 1
    fi

    while IFS= read -r passwd_line; do
        passwd_home="$(_cli_passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(_cli_getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

_cli_preferred_bin_dir() {
    local target_home="${1:-}"
    local candidate=""

    [[ -n "$target_home" ]] || return 1

    candidate="$(_cli_validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$target_home" 2>/dev/null || true)"
    if [[ -n "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    printf '%s\n' "$target_home/.local/bin"
}

_cli_normalize_atuin_shims() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_cli_target_home "$target_user")"
    local preferred_src="$target_home/.atuin/bin/atuin"
    local primary_dir="${ACFS_BIN_DIR:-$target_home/.local/bin}"
    local fallback_dir="$target_home/.local/bin"

    primary_dir="$(_cli_validate_bin_dir_for_home "$primary_dir" "$target_home" 2>/dev/null || true)"
    [[ -n "$primary_dir" ]] || primary_dir="$fallback_dir"

    [[ -x "$preferred_src" ]] || return 0

    _cli_run_as_user "
        set -e
        preferred_src='$preferred_src'
        primary_dir='$primary_dir'
        fallback_dir='$fallback_dir'
        mkdir -p \"\$primary_dir\"
        ln -sf \"\$preferred_src\" \"\$primary_dir/atuin\"
        if [[ \"\$fallback_dir\" != \"\$primary_dir\" ]]; then
            mkdir -p \"\$fallback_dir\"
            ln -sf \"\$preferred_src\" \"\$fallback_dir/atuin\"
        fi
    " >/dev/null 2>&1 || true
}

# Fetch latest version tag from GitHub
# Usage: _fetch_github_version "owner/repo" [strip_v]
_fetch_github_version() {
    local repo="$1"
    local strip_v="${2:-false}"
    local tag=""

    # Attempt to use robust github_get_latest_release if available
    if declare -f github_get_latest_release &>/dev/null; then
        tag=$(github_get_latest_release "$repo")
    fi

    if [[ -z "$tag" ]]; then
        # Strategy 1: Try HTTP HEAD request to /releases/latest (redirects to /releases/tag/vX.Y.Z)
        # This avoids GitHub API rate limits (60 requests/hr for unauthenticated IP)
        local location_header
        if location_header=$(curl -sI --max-time 10 "https://github.com/$repo/releases/latest" | grep -i "^location:"); then
            # Extract tag from URL: https://github.com/owner/repo/releases/tag/v1.2.3
            # Remove trailing CR if present
            location_header="${location_header%$'\r'}"
            tag="${location_header##*/}"
        fi

        # Strategy 2: Fallback to GitHub API if HEAD failed or returned no tag
        if [[ -z "$tag" ]]; then
            local json
            if json=$(curl -s --max-time 10 "https://api.github.com/repos/$repo/releases/latest"); then
                if command -v jq &>/dev/null; then
                    tag=$(echo "$json" | jq -r '.tag_name // empty')
                elif command -v python3 &>/dev/null; then
                    tag=$(echo "$json" | python3 -c "import sys, json; print(json.load(sys.stdin).get('tag_name', ''))" 2>/dev/null)
                else
                    tag=$(echo "$json" | { grep -o '"tag_name": *"[^"]*"' || true; } | head -n1 | cut -d'"' -f4)
                fi
            fi
        fi
    fi

    [[ -z "$tag" || "$tag" == "null" ]] && return 1

    if [[ "$strip_v" == "true" ]]; then
        echo "${tag#v}"
    else
        echo "$tag"
    fi
}

# Run a command as target user
_cli_run_as_user() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    local target_path_prefix=""
    local preferred_bin_dir=""
    local cmd="$1"
    local target_user_q=""
    local target_home_q=""
    local target_path_prefix_q=""
    local acfs_home_q=""
    local acfs_bin_dir_q=""
    local wrapped_cmd=""
    local bash_bin=""
    local sudo_bin=""
    local runuser_bin=""
    local su_bin=""

    _cli_validate_target_user "$target_user" || return 1
    bash_bin="$(_cli_system_binary_path bash 2>/dev/null || true)"
    [[ -n "$bash_bin" ]] || {
        log_error "Unable to locate bash for target-user CLI command"
        return 1
    }

    target_home="$(_cli_target_home "$target_user" 2>/dev/null || true)"
    if [[ -z "$target_home" ]] || [[ "$target_home" == "/" ]] || [[ "$target_home" != /* ]]; then
        log_error "Invalid TARGET_HOME for '$target_user': ${target_home:-<empty>} (must be an absolute path and cannot be '/')"
        return 1
    fi

    if [[ -n "${ACFS_BIN_DIR:-}" ]] && { [[ "${ACFS_BIN_DIR}" == "/" ]] || [[ "${ACFS_BIN_DIR}" != /* ]]; }; then
        log_error "ACFS_BIN_DIR must be an absolute path and cannot be '/' (got: ${ACFS_BIN_DIR:-<empty>})"
        return 1
    fi

    preferred_bin_dir="$(_cli_preferred_bin_dir "$target_home" 2>/dev/null || true)"
    [[ -n "$preferred_bin_dir" ]] || preferred_bin_dir="$target_home/.local/bin"
    target_path_prefix="$preferred_bin_dir:$target_home/.local/bin:$target_home/.acfs/bin:$target_home/.cargo/bin:$target_home/.bun/bin:$target_home/.atuin/bin:$target_home/go/bin"

    printf -v target_user_q '%q' "$target_user"
    printf -v target_home_q '%q' "$target_home"
    printf -v target_path_prefix_q '%q' "$target_path_prefix"
    if [[ -n "${ACFS_HOME:-}" ]]; then
        printf -v acfs_home_q '%q' "$ACFS_HOME"
    fi
    if [[ -n "$preferred_bin_dir" ]]; then
        printf -v acfs_bin_dir_q '%q' "$preferred_bin_dir"
    fi

    wrapped_cmd="export TARGET_USER=$target_user_q TARGET_HOME=$target_home_q HOME=$target_home_q;"
    if [[ -n "$acfs_home_q" ]]; then
        wrapped_cmd+=" export ACFS_HOME=$acfs_home_q;"
    fi
    if [[ -n "$acfs_bin_dir_q" ]]; then
        wrapped_cmd+=" export ACFS_BIN_DIR=$acfs_bin_dir_q;"
    fi
    wrapped_cmd+=" export PATH=$target_path_prefix_q:\$PATH; set -o pipefail; cd \"\$HOME\" || exit 1; $cmd"

    if [[ "$(_cli_resolve_current_user 2>/dev/null || true)" == "$target_user" ]]; then
        "$bash_bin" -c "$wrapped_cmd"
        return $?
    fi

    sudo_bin="$(_cli_system_binary_path sudo 2>/dev/null || true)"
    if [[ -n "$sudo_bin" ]]; then
        "$sudo_bin" -u "$target_user" -H "$bash_bin" -c "$wrapped_cmd"
        return $?
    fi

    runuser_bin="$(_cli_system_binary_path runuser 2>/dev/null || true)"
    if [[ -n "$runuser_bin" ]]; then
        "$runuser_bin" -u "$target_user" -- "$bash_bin" -c "$wrapped_cmd"
        return $?
    fi

    su_bin="$(_cli_system_binary_path su 2>/dev/null || true)"
    [[ -n "$su_bin" ]] || {
        log_error "Unable to locate sudo, runuser, or su for target-user CLI command"
        return 1
    }

    # Avoid login shells: profile files are not a stable API and can break non-interactive runs.
    "$su_bin" "$target_user" -c "$(printf '%q' "$bash_bin") -c $(printf %q "$wrapped_cmd")"
}

# Load security helpers + checksums.yaml (fail closed if unavailable).
CLI_SECURITY_READY=false
_cli_require_security() {
    if [[ "${CLI_SECURITY_READY}" == "true" ]]; then
        return 0
    fi

    if [[ ! -f "$CLI_TOOLS_SCRIPT_DIR/security.sh" ]]; then
        log_warn "Security library not found ($CLI_TOOLS_SCRIPT_DIR/security.sh); refusing to run upstream installer scripts"
        return 1
    fi

    # shellcheck source=security.sh
    source "$CLI_TOOLS_SCRIPT_DIR/security.sh"
    if ! load_checksums; then
        log_warn "checksums.yaml not available; refusing to run upstream installer scripts"
        return 1
    fi

    CLI_SECURITY_READY=true
    return 0
}

# ============================================================
# APT-based CLI Tools
# ============================================================

# Install CLI tools available via apt
install_apt_cli_tools() {
    local sudo_cmd
    sudo_cmd=$(_cli_get_sudo)

    log_detail "Installing apt-based CLI tools..."

    # Update package list
    $sudo_cmd apt-get update -y >/dev/null 2>&1 || true

    # Install core packages (these should always be available)
    for pkg in "${APT_CLI_TOOLS[@]}"; do
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            log_detail "Installing $pkg..."
            $sudo_cmd apt-get install -y "$pkg" >/dev/null 2>&1 || log_warn "Could not install $pkg via apt"
        fi
    done

    # Install optional packages (may not be available on all versions)
    for pkg in "${APT_CLI_TOOLS_OPTIONAL[@]}"; do
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            log_detail "Installing $pkg (optional)..."
            $sudo_cmd apt-get install -y "$pkg" >/dev/null 2>&1 || true
        fi
    done

    # Handle bat/batcat naming issue (Ubuntu calls it batcat)
    if ! _cli_command_exists bat && _cli_command_exists batcat; then
        log_detail "Creating bat symlink for batcat..."
        $sudo_cmd ln -sf "$(command -v batcat)" /usr/local/bin/bat 2>/dev/null || true
    fi

    # Handle fd-find naming issue (Ubuntu calls it fdfind)
    if ! _cli_command_exists fd && _cli_command_exists fdfind; then
        log_detail "Creating fd symlink for fdfind..."
        $sudo_cmd ln -sf "$(command -v fdfind)" /usr/local/bin/fd 2>/dev/null || true
    fi

    log_success "APT CLI tools installed"
}

# ============================================================
# Cargo-based CLI Tools
# ============================================================

# Install CLI tools via cargo (for latest versions)
install_cargo_cli_tools() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_cli_target_home "$target_user")"
    local cargo_bin="$target_home/.cargo/bin/cargo"

    log_detail "Installing cargo-based CLI tools..."

    # Check if cargo is available
    if [[ ! -x "$cargo_bin" ]]; then
        log_warn "Cargo not found at $cargo_bin, skipping cargo CLI tools"
        return 0
    fi
    local cargo_bin_q=""
    printf -v cargo_bin_q '%q' "$cargo_bin"

    # Install zoxide if not already installed
    if ! _cli_target_has_command zoxide; then
        log_detail "Installing zoxide via cargo..."
        _cli_run_as_user "$cargo_bin_q install zoxide --locked 2>/dev/null" || {
            # Fallback: try the official installer
            log_detail "Trying zoxide official installer..."
            if _cli_require_security; then
                local url="${KNOWN_INSTALLERS[zoxide]}"
                local expected_sha256
                expected_sha256="$(get_checksum zoxide)"
                if [[ -n "$expected_sha256" ]]; then
                    local security_lib_q=""
                    local url_q=""
                    local expected_sha256_q=""
                    printf -v security_lib_q '%q' "$CLI_TOOLS_SCRIPT_DIR/security.sh"
                    printf -v url_q '%q' "$url"
                    printf -v expected_sha256_q '%q' "$expected_sha256"
                    _cli_run_as_user "source $security_lib_q; verify_checksum $url_q $expected_sha256_q zoxide | sh" || true
                else
                    log_warn "No checksum recorded for zoxide; skipping unverified installer fallback"
                fi
            fi
        }
    fi

    # Install ast-grep (sg command)
    if ! _cli_target_has_command sg; then
        log_detail "Installing ast-grep via cargo..."
        _cli_run_as_user "$cargo_bin_q install ast-grep --locked 2>/dev/null" || log_warn "Could not install ast-grep"
    fi

    # Install lsd via cargo if apt version not available
    if ! _cli_target_has_command lsd && ! _cli_target_has_command eza; then
        log_detail "Installing lsd via cargo..."
        _cli_run_as_user "$cargo_bin_q install lsd --locked 2>/dev/null" || log_warn "Could not install lsd"
    fi

    # Install dust via cargo if apt version not available
    if ! _cli_target_has_command dust; then
        log_detail "Installing dust via cargo..."
        _cli_run_as_user "$cargo_bin_q install du-dust --locked 2>/dev/null" || log_warn "Could not install dust"
    fi

    # Install tealdeer (tldr - simplified man pages)
    if ! _cli_target_has_command tldr; then
        log_detail "Installing tealdeer (tldr) via cargo..."
        _cli_run_as_user "$cargo_bin_q install tealdeer --locked 2>/dev/null" || log_warn "Could not install tealdeer"
        # Fetch tldr pages cache (use full path since ~/.cargo/bin may not be in PATH yet)
        local tldr_bin="$target_home/.cargo/bin/tldr"
        if [[ -x "$tldr_bin" ]]; then
            local tldr_bin_q=""
            printf -v tldr_bin_q '%q' "$tldr_bin"
            _cli_run_as_user "$tldr_bin_q --update 2>/dev/null" || true
        fi
    fi

    log_success "Cargo CLI tools installed"
}

# ============================================================
# Other CLI Tools (via curl/installer scripts)
# ============================================================

# Install gum (Charmbracelet's glamorous shell tool)
install_gum_cli_tool() {
    local sudo_cmd
    sudo_cmd=$(_cli_get_sudo)

    if _cli_command_exists gum; then
        log_detail "gum already installed"
        return 0
    fi

    log_detail "Installing gum..."

    # Add Charm repository (DEB822 format for Ubuntu 24.04+)
    $sudo_cmd mkdir -p /etc/apt/keyrings
    curl --proto '=https' --proto-redir '=https' -fsSL https://repo.charm.sh/apt/gpg.key | $sudo_cmd gpg --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null || true
    printf 'Types: deb\nURIs: https://repo.charm.sh/apt/\nSuites: *\nComponents: *\nSigned-By: /etc/apt/keyrings/charm.gpg\n' | $sudo_cmd tee /etc/apt/sources.list.d/charm.sources > /dev/null
    $sudo_cmd apt-get update -y >/dev/null 2>&1 || true
    $sudo_cmd apt-get install -y gum >/dev/null 2>&1 || log_warn "Could not install gum"

    if _cli_command_exists gum; then
        log_success "gum installed"
    fi
}

# Install lazygit (Git TUI)
install_lazygit() {
    local sudo_cmd
    sudo_cmd=$(_cli_get_sudo)

    if _cli_command_exists lazygit; then
        log_detail "lazygit already installed"
        return 0
    fi

    log_detail "Installing lazygit..."

    # Try apt first (available in newer Ubuntu)
    if $sudo_cmd apt-get install -y lazygit >/dev/null 2>&1; then
        log_success "lazygit installed via apt"
        return 0
    fi

    # Fallback: install from GitHub releases
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_warn "Unsupported architecture for lazygit: $arch"; return 1 ;;
    esac

    local version
    # Use helper for robust version fetching (strips 'v' prefix)
    version=$(_fetch_github_version "jesseduffield/lazygit" true) || version="0.44.1"

    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/acfs_lazygit.XXXXXX" 2>/dev/null)" || tmpdir=""
    if [[ -z "$tmpdir" ]] || [[ ! -d "$tmpdir" ]]; then
        log_warn "mktemp failed; cannot install lazygit"
        return 1
    fi
    curl --proto '=https' --proto-redir '=https' -fsSL -o "$tmpdir/lazygit.tar.gz" \
        "https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_${arch}.tar.gz" || {
        log_warn "Could not download lazygit"
        _cli_remove_temp_dir "$tmpdir"
        return 1
    }

    tar -xzf "$tmpdir/lazygit.tar.gz" -C "$tmpdir" || {
        log_warn "Failed to extract lazygit tarball"
        _cli_remove_temp_dir "$tmpdir"
        return 1
    }
    $sudo_cmd install "$tmpdir/lazygit" /usr/local/bin/lazygit || {
        log_warn "Failed to install lazygit"
        _cli_remove_temp_dir "$tmpdir"
        return 1
    }
    _cli_remove_temp_dir "$tmpdir"

    log_success "lazygit installed from GitHub"
}

# Install lazydocker (Docker TUI)
install_lazydocker() {
    local sudo_cmd
    sudo_cmd=$(_cli_get_sudo)

    if _cli_command_exists lazydocker; then
        log_detail "lazydocker already installed"
        return 0
    fi

    log_detail "Installing lazydocker..."

    # Install from GitHub releases
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="x86_64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_warn "Unsupported architecture for lazydocker: $arch"; return 1 ;;
    esac

    local version
    # Use helper for robust version fetching (strips 'v' prefix)
    version=$(_fetch_github_version "jesseduffield/lazydocker" true) || version="0.23.3"

    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/acfs_lazydocker.XXXXXX" 2>/dev/null)" || tmpdir=""
    if [[ -z "$tmpdir" ]] || [[ ! -d "$tmpdir" ]]; then
        log_warn "mktemp failed; cannot install lazydocker"
        return 1
    fi
    curl --proto '=https' --proto-redir '=https' -fsSL -o "$tmpdir/lazydocker.tar.gz" \
        "https://github.com/jesseduffield/lazydocker/releases/download/v${version}/lazydocker_${version}_Linux_${arch}.tar.gz" || {
        log_warn "Could not download lazydocker"
        _cli_remove_temp_dir "$tmpdir"
        return 1
    }

    tar -xzf "$tmpdir/lazydocker.tar.gz" -C "$tmpdir" || {
        log_warn "Failed to extract lazydocker tarball"
        _cli_remove_temp_dir "$tmpdir"
        return 1
    }
    $sudo_cmd install "$tmpdir/lazydocker" /usr/local/bin/lazydocker || {
        log_warn "Failed to install lazydocker"
        _cli_remove_temp_dir "$tmpdir"
        return 1
    }
    _cli_remove_temp_dir "$tmpdir"

    log_success "lazydocker installed from GitHub"
}

# Install yq (YAML processor, like jq for YAML)
install_yq() {
    local sudo_cmd
    sudo_cmd=$(_cli_get_sudo)

    if _cli_command_exists yq; then
        log_detail "yq already installed"
        return 0
    fi

    log_detail "Installing yq..."

    # Install from GitHub releases (Mike Farah's yq)
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_warn "Unsupported architecture for yq: $arch"; return 1 ;;
    esac

    local version
    # Use helper for robust version fetching (keeps 'v' prefix)
    version=$(_fetch_github_version "mikefarah/yq" false) || version="v4.44.1"

    local tmpdir
    tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/acfs_yq.XXXXXX" 2>/dev/null)" || tmpdir=""
    if [[ -z "$tmpdir" ]] || [[ ! -d "$tmpdir" ]]; then
        log_warn "mktemp failed; cannot install yq"
        return 1
    fi
    curl --proto '=https' --proto-redir '=https' -fsSL -o "$tmpdir/yq" \
        "https://github.com/mikefarah/yq/releases/download/${version}/yq_linux_${arch}" || {
        log_warn "Could not download yq"
        _cli_remove_temp_dir "$tmpdir"
        return 1
    }

    chmod +x "$tmpdir/yq" || {
        log_warn "Failed to make yq executable"
        _cli_remove_temp_dir "$tmpdir"
        return 1
    }
    $sudo_cmd install "$tmpdir/yq" /usr/local/bin/yq || {
        log_warn "Failed to install yq"
        _cli_remove_temp_dir "$tmpdir"
        return 1
    }
    _cli_remove_temp_dir "$tmpdir"

    log_success "yq installed from GitHub"
}

# Install atuin (shell history)
install_atuin() {
    local target_user="${TARGET_USER:-ubuntu}"
    local target_home=""
    target_home="$(_cli_target_home "$target_user")"
    local target_atuin_bin="$target_home/.atuin/bin/atuin"

    if [[ -x "$target_atuin_bin" ]]; then
        log_detail "atuin already installed"
        _cli_normalize_atuin_shims
        return 0
    fi

    log_detail "Installing atuin..."
    if ! _cli_require_security; then
        return 1
    fi

    local url="${KNOWN_INSTALLERS[atuin]}"
    local expected_sha256
    expected_sha256="$(get_checksum atuin)"
    if [[ -z "$expected_sha256" ]]; then
        log_warn "No checksum recorded for atuin; refusing to run unverified installer"
        return 1
    fi

    local security_lib_q=""
    local url_q=""
    local expected_sha256_q=""
    printf -v security_lib_q '%q' "$CLI_TOOLS_SCRIPT_DIR/security.sh"
    printf -v url_q '%q' "$url"
    printf -v expected_sha256_q '%q' "$expected_sha256"
    if ! _cli_run_as_user "source $security_lib_q; verify_checksum $url_q $expected_sha256_q atuin | sh -s -- --non-interactive"; then
        log_warn "Could not install atuin"
    fi

    if [[ -x "$target_atuin_bin" ]]; then
        _cli_normalize_atuin_shims
        log_success "atuin installed"
        return 0
    fi

    log_warn "atuin not installed"
    return 1
}

# ============================================================
# Docker Setup
# ============================================================

# Install and configure Docker
install_docker() {
    local sudo_cmd
    sudo_cmd=$(_cli_get_sudo)
    local target_user="${TARGET_USER:-ubuntu}"

    if _cli_command_exists docker; then
        log_detail "Docker already installed"
    else
        log_detail "Installing Docker..."
        $sudo_cmd apt-get install -y docker.io docker-compose-plugin >/dev/null 2>&1 || log_warn "Could not install Docker"
    fi

    # Add target user to docker group
    if getent group docker &>/dev/null; then
        log_detail "Adding $target_user to docker group..."
        $sudo_cmd usermod -aG docker "$target_user" 2>/dev/null || true
    fi

    log_success "Docker configured"
}

# ============================================================
# Verification Functions
# ============================================================

# Verify all CLI tools are installed
verify_cli_tools() {
    local all_pass=true

    log_detail "Verifying CLI tools..."

    # Core tools (must have)
    local core_tools=("rg" "fzf" "tmux" "jq")
    for tool in "${core_tools[@]}"; do
        if _cli_command_exists "$tool"; then
            log_detail "  $tool"
        else
            log_warn "  Missing: $tool"
            all_pass=false
        fi
    done

    # Preferred tools (one of alternatives)
    if _cli_command_exists lsd || _cli_command_exists eza; then
        log_detail "  ls replacement: $(command -v lsd || command -v eza)"
    else
        log_warn "  Missing: lsd or eza"
    fi

    if _cli_command_exists bat || _cli_command_exists batcat; then
        log_detail "  cat replacement: $(command -v bat || command -v batcat)"
    else
        log_warn "  Missing: bat"
    fi

    if _cli_command_exists fd || _cli_command_exists fdfind; then
        log_detail "  find replacement: $(command -v fd || command -v fdfind)"
    else
        log_warn "  Missing: fd"
    fi

    # Optional tools (nice to have)
    local optional_tools=("zoxide" "direnv" "nvim" "lazygit" "gum" "atuin" "yq" "tldr" "delta" "tree" "ncdu" "http")
    for tool in "${optional_tools[@]}"; do
        if _cli_command_exists "$tool"; then
            log_detail "  $tool"
        fi
    done

    if [[ "$all_pass" == "true" ]]; then
        log_success "All core CLI tools verified"
        return 0
    else
        log_warn "Some CLI tools are missing"
        return 1
    fi
}

# Get versions of installed tools (for doctor output)
get_cli_tool_versions() {
    echo "CLI Tool Versions:"

    _cli_command_exists rg && echo "  ripgrep: $(rg --version | head -1)"
    _cli_command_exists fzf && echo "  fzf: $(fzf --version)"
    _cli_command_exists tmux && echo "  tmux: $(tmux -V)"
    _cli_command_exists nvim && echo "  neovim: $(nvim --version | head -1)"
    _cli_command_exists lsd && echo "  lsd: $(lsd --version)"
    _cli_command_exists eza && echo "  eza: $(eza --version | head -1)"
    _cli_command_exists bat && echo "  bat: $(bat --version)"
    _cli_command_exists fd && echo "  fd: $(fd --version)"
    _cli_command_exists zoxide && echo "  zoxide: $(zoxide --version)"
    _cli_command_exists lazygit && echo "  lazygit: $(lazygit --version | head -1)"
    _cli_command_exists gum && echo "  gum: $(gum --version)"
    _cli_command_exists atuin && echo "  atuin: $(atuin --version)"
    _cli_command_exists docker && echo "  docker: $(docker --version)"
    _cli_command_exists yq && echo "  yq: $(yq --version)"
    _cli_command_exists tldr && echo "  tldr: $(tldr --version 2>/dev/null || echo 'installed')"
    _cli_command_exists delta && echo "  delta: $(delta --version)"
    _cli_command_exists tree && echo "  tree: $(tree --version | head -1)"
    _cli_command_exists ncdu && echo "  ncdu: $(ncdu --version 2>/dev/null | head -1 || echo 'installed')"
    _cli_command_exists http && echo "  httpie: $(http --version)"
}

# ============================================================
# Main Installation Function
# ============================================================

# Install all CLI tools (called by install.sh)
install_all_cli_tools() {
    log_step "4/8" "Installing CLI tools..."

    # Install gum first for enhanced UI
    install_gum_cli_tool

    # APT-based tools
    install_apt_cli_tools

    # Cargo-based tools (requires rust to be installed first)
    install_cargo_cli_tools

    # Other installers
    install_lazygit
    install_lazydocker
    install_yq
    install_atuin

    # Docker
    install_docker

    # Verify installation
    verify_cli_tools

    log_success "CLI tools installation complete"
}

# ============================================================
# Module can be sourced or run directly
# ============================================================

# If run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_all_cli_tools "$@"
fi
