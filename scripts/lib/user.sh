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
    local password=""
    local digest=""

    # Try openssl first (most standard)
    if command -v openssl &>/dev/null; then
        password="$(openssl rand -base64 32 2>/dev/null || true)"
        if [[ -n "$password" ]]; then
            printf '%s\n' "$password"
            return 0
        fi
    fi

    # Fallback to python3 (standard on Ubuntu)
    if command -v python3 &>/dev/null; then
        password="$(python3 -c "import secrets; print(secrets.token_urlsafe(32))" 2>/dev/null || true)"
        if [[ -n "$password" ]]; then
            printf '%s\n' "$password"
            return 0
        fi
    fi

    # Fallback to /dev/urandom (standard on Linux)
    if [[ -r /dev/urandom ]] && command -v tr &>/dev/null && command -v head &>/dev/null; then
        # Take first 32 alphanumeric chars
        password="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 || true)"
        if [[ -n "$password" ]]; then
            printf '%s\n' "$password"
            return 0
        fi
    fi

    # Last resort: date hash (better than empty)
    if command -v sha256sum &>/dev/null; then
        digest="$(date +%s%N | sha256sum 2>/dev/null || true)"
        digest="${digest%% *}"
        if [[ -n "$digest" ]]; then
            printf '%s\n' "${digest:0:32}"
            return 0
        fi
    fi

    return 1
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
        passwd="$(_generate_random_password 2>/dev/null || true)"
        
        if [[ -n "$passwd" ]]; then
            # Keep the password out of any xtrace (ACFS_DEBUG) that lands in
            # the install log and therefore in support bundles.
            {
                local chpasswd_xtrace_was_on=0
                [[ $- == *x* ]] && chpasswd_xtrace_was_on=1
                set +x
                local chpasswd_rc=0
                echo "$target:$passwd" | $SUDO chpasswd || chpasswd_rc=$?
                if [[ "$chpasswd_xtrace_was_on" -eq 1 ]]; then set -x; fi
                [[ "$chpasswd_rc" -eq 0 ]]
            }
            
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
    local mktemp_bin=""
    local chmod_bin=""
    local mv_bin=""
    local rm_bin=""
    local tee_bin=""
    local visudo_bin=""
    local staged_file=""
    local -a sudo_prefix=()

    user_require_valid_target_user "$target"

    log_detail "Enabling passwordless sudo for $target"

    mktemp_bin="$(user_system_binary_path mktemp 2>/dev/null || true)"
    chmod_bin="$(user_system_binary_path chmod 2>/dev/null || true)"
    mv_bin="$(user_system_binary_path mv 2>/dev/null || true)"
    rm_bin="$(user_system_binary_path rm 2>/dev/null || true)"
    tee_bin="$(user_system_binary_path tee 2>/dev/null || true)"
    visudo_bin="$(user_system_binary_path visudo 2>/dev/null || true)"
    if [[ -z "$mktemp_bin" || -z "$chmod_bin" || -z "$mv_bin" || -z "$rm_bin" || -z "$tee_bin" || -z "$visudo_bin" ]]; then
        log_error "Trusted mktemp, chmod, mv, rm, tee, and visudo executables are required for sudoers changes"
        return 1
    fi
    if [[ -n "${SUDO:-}" ]]; then
        sudo_prefix=("$SUDO")
    fi

    # The privileged identity creates and owns the candidate in the destination
    # directory. The invoking user therefore cannot rewrite or replace the
    # pathname after visudo validates it and before the atomic rename.
    staged_file="$("${sudo_prefix[@]}" "$mktemp_bin" /etc/sudoers.d/.90-ubuntu-acfs.XXXXXX 2>/dev/null || true)"
    if [[ -z "$staged_file" ]]; then
        log_error "Unable to create a temporary file for the sudoers drop-in"
        return 1
    fi

    if ! printf '%s\n' "$target ALL=(ALL) NOPASSWD:ALL" \
        | "${sudo_prefix[@]}" "$tee_bin" -- "$staged_file" >/dev/null \
        || ! "${sudo_prefix[@]}" "$chmod_bin" 0440 "$staged_file"; then
        "${sudo_prefix[@]}" "$rm_bin" -f -- "$staged_file" 2>/dev/null || true
        log_error "Unable to stage sudoers content for validation"
        return 1
    fi
    if ! "${sudo_prefix[@]}" "$visudo_bin" -c -f "$staged_file" >/dev/null 2>&1; then
        "${sudo_prefix[@]}" "$rm_bin" -f -- "$staged_file" 2>/dev/null || true
        log_error "Generated sudoers content failed validation; $sudoers_file was left untouched"
        return 1
    fi
    if ! "${sudo_prefix[@]}" "$mv_bin" -f -- "$staged_file" "$sudoers_file"; then
        "${sudo_prefix[@]}" "$rm_bin" -f -- "$staged_file" 2>/dev/null || true
        log_error "Unable to atomically install validated sudoers content"
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
    local current_home="${HOME:-}"

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
    if [[ -n "$current_home" && "$current_home" == /* && "$current_home" != "/" && -f "$current_home/.ssh/authorized_keys" ]]; then
        source_keys="$current_home/.ssh/authorized_keys"
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
            local target_ssh_dir="$target_home/.ssh"
            local target_authorized_keys="$target_ssh_dir/authorized_keys"
            local target_owner="$target:$target"
            local target_ssh_dir_q=""
            local target_authorized_keys_q=""
            local target_q=""
            local target_owner_q=""
            printf -v target_ssh_dir_q '%q' "$target_ssh_dir"
            printf -v target_authorized_keys_q '%q' "$target_authorized_keys"
            printf -v target_q '%q' "$target"
            printf -v target_owner_q '%q' "$target_owner"
            local root_remote_command="read -r acfs_pubkey && test ! -L $target_ssh_dir_q && install -d -m 700 -o $target_q -g $target_q $target_ssh_dir_q && test ! -L $target_authorized_keys_q && touch $target_authorized_keys_q && { [ ! -s $target_authorized_keys_q ] || tail -c 1 $target_authorized_keys_q | od -An -t u1 | grep -qw 10 || printf \"\\n\" >> $target_authorized_keys_q; } && if ! grep -qxF \"\$acfs_pubkey\" $target_authorized_keys_q; then printf \"%s\\n\" \"\$acfs_pubkey\" >> $target_authorized_keys_q; fi && chown $target_owner_q $target_authorized_keys_q && chmod 600 $target_authorized_keys_q"
            local root_remote_command_q="$root_remote_command"
            root_remote_command_q=${root_remote_command_q//\'/\'\\\'\'}
            printf -v root_remote_command_q "'%s'" "$root_remote_command_q"
            local root_repair_command="cat ~/.ssh/acfs_ed25519.pub | ssh root@YOUR_SERVER_IP $root_remote_command_q"
            echo ""
            echo "════════════════════════════════════════════════════════════"
            echo "  ⚠  SSH KEY SETUP REQUIRED FOR USER: $target"
            echo "════════════════════════════════════════════════════════════"
            echo ""
            echo "  You connected with a password, so no SSH key was migrated."
            echo "  After installation, you'll need to set up SSH access."
            echo ""
            echo "  EASIEST FIX - from your LOCAL machine, first try this only if"
            echo "  you can already sign in as $target:"
            echo ""
            echo "    $target_user_repair_command"
            echo ""
            echo "  This uses the $target account; passwordless sudo is not a login password."
            echo ""
            echo "  If you only have the VPS root password or that cannot connect,"
            echo "  use the root fallback:"
            echo ""
            echo "    $root_repair_command"
            echo ""
            echo "  The root fallback asks for the VPS root password once."
            echo ""
            echo "  ssh-copy-id is optional and only works if you know the ${target}"
            echo "  Linux account password:"
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

# Login shells are authentication policy, not just executable paths. In
# particular, pam_shells compares the passwd shell literally with /etc/shells;
# resolving a usrmerge symlink does not make an unlisted spelling acceptable.
user_local_passwd_entry() {
    local target="${1:-${TARGET_USER:-}}"
    local entry=""

    [[ -r /etc/passwd ]] || return 2
    while IFS= read -r entry || [[ -n "$entry" ]]; do
        [[ "${entry%%:*}" == "$target" ]] || continue
        printf '%s\n' "$entry"
        return 0
    done < /etc/passwd
    return 1
}

# Unlike the general bootstrap lookup, do not hide an NSS lookup failure by
# falling back to a local record: verification must observe effective state.
user_login_passwd_entry() {
    local target="${1:-${TARGET_USER:-}}"
    local getent_bin="" entry="" name="" uid="" gid="" account_home="" shell=""

    user_valid_target_name "$target" || return 1
    getent_bin="$(user_system_binary_path getent 2>/dev/null || true)"
    [[ -n "$getent_bin" ]] || return 1
    entry="$("$getent_bin" passwd "$target")" || return 1
    [[ "$entry" != *$'\n'* && "${entry//[^:]/}" == '::::::' ]] || return 1
    IFS=: read -r name _ uid gid _ account_home shell <<< "$entry"
    [[ "$name" == "$target" && "$uid" =~ ^[0-9]+$ && "$gid" =~ ^[0-9]+$ ]] || return 1
    [[ "$account_home" == /* && "$account_home" != / && "$shell" == /* ]] || return 1
    [[ "$entry" != *$'\r'* ]] || return 1
    printf '%s\n' "$entry"
}

user_login_accounts_match() {
    local effective="${1:-}" local_entry="${2:-}"
    local e_name="" e_uid="" e_gid="" e_home="" e_shell=""
    local l_name="" l_uid="" l_gid="" l_home="" l_shell=""

    [[ "${local_entry//[^:]/}" == '::::::' && "$local_entry" != *$'\n'* ]] || return 1
    IFS=: read -r e_name _ e_uid e_gid _ e_home e_shell <<< "$effective"
    IFS=: read -r l_name _ l_uid l_gid _ l_home l_shell <<< "$local_entry"
    [[ "$e_name" == "$l_name" && "$e_uid" == "$l_uid" && "$e_gid" == "$l_gid" &&
       "$e_home" == "$l_home" && "$e_shell" == "$l_shell" ]]
}

user_shells_file_is_safe() {
    local stat_bin="" mode=""

    # Match pam_shells' file checks, including its refusal of world-writable
    # policy files. stat -L follows a legitimate /etc/shells symlink as PAM does.
    [[ -f /etc/shells && -r /etc/shells ]] || return 1
    stat_bin="$(user_system_binary_path stat)" || return 1
    mode="$("$stat_bin" -Lc '%a' -- /etc/shells 2>/dev/null)" || return 1
    [[ "$mode" =~ ^[0-7]{1,4}$ ]] || return 1
    (( (8#$mode & 2) == 0 ))
}

user_shell_is_approved() {
    local shell="${1:-}" grep_bin=""

    [[ "$shell" == /* && "$shell" != *$'\n'* && "$shell" != *$'\r'* && "$shell" != *:* ]] || return 1
    [[ -f "$shell" && -x "$shell" ]] || return 1
    user_shells_file_is_safe || return 1
    grep_bin="$(user_system_binary_path grep)" || return 1
    # -a avoids grep's binary-file shortcut. Do not trim whitespace, comments,
    # CRLFs, or canonicalize aliases: only an exact policy entry is sufficient.
    "$grep_bin" -aFxq -- "$shell" /etc/shells
}

user_select_login_shell() {
    local preferred="${1:-}" target="${2:-${TARGET_USER:-}}" candidate=""

    user_shells_file_is_safe || return 1
    # Keep PATH out of login-shell selection. Prefer distro bin spellings,
    # then accept other zsh installations explicitly approved by the host.
    for candidate in "$preferred" /usr/bin/zsh /bin/zsh /usr/local/bin/zsh /usr/sbin/zsh /sbin/zsh; do
        [[ "${candidate##*/}" == zsh ]] || continue
        if user_shell_is_approved "$candidate" && user_shell_executable_by_account "$candidate" "$target"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    while IFS= read -r candidate || [[ -n "$candidate" ]]; do
        [[ "${candidate##*/}" == zsh ]] || continue
        if user_shell_is_approved "$candidate" && user_shell_executable_by_account "$candidate" "$target"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < /etc/shells
    return 1
}

# Home-directory writes must run as the account owner, even when the legacy
# installer is root. A symlink swap in that user's home must not gain privilege.
user_run_as_account() {
    local target="$1" current_user="" runner=""
    shift

    current_user="$(user_resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "$target" ]]; then
        "$@"
    elif [[ "$EUID" -eq 0 ]]; then
        runner="$(user_system_binary_path runuser)" || return 1
        "$runner" -u "$target" -- "$@"
    else
        runner="$(user_system_binary_path sudo)" || return 1
        "$runner" -n -u "$target" -- "$@"
    fi
}

user_shell_executable_by_account() {
    local shell="$1" target="$2" current_user="" bash_bin=""

    [[ -f "$shell" && -x "$shell" ]] || return 1
    current_user="$(user_resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "$target" ]]; then
        return 0
    fi
    bash_bin="$(user_system_binary_path bash)" || return 1
    user_run_as_account "$target" "$bash_bin" -c '[[ -f "$1" && -x "$1" ]]' _ "$shell"
}

user_preserve_login_shell() {
    local target="$1" target_home="$2" original="$3" bash_bin=""
    bash_bin="$(user_system_binary_path bash)" || return 1
    user_run_as_account "$target" "$bash_bin" -c '
        set -euo pipefail
        umask 077
        backup="$1/.shell.pre-acfs"
        if [[ -e "$backup" || -L "$backup" ]]; then
            [[ -f "$backup" && ! -L "$backup" && -r "$backup" && -s "$backup" ]] || exit 1
            saved="$(< "$backup")"
            [[ "$saved" == /* && "$saved" != *[[:cntrl:]:]* ]]
        else
            set -o noclobber
            printf "%s\n" "$2" > "$backup"
        fi
    ' _ "$target_home" "$original"
}

user_external_shell_handoff_configured() {
    local target_home="${1:-}"
    local bashrc_path="" bash_bin="" line="" state=0 found=false
    local guard='if [[ $- == *i* ]] && [[ -t 0 ]] && command -v zsh >/dev/null 2>&1 && [[ -z "${ACFS_ZSH_HANDOFF_ACTIVE:-}" ]]; then'

    [[ -n "$target_home" ]] || return 1
    bashrc_path="$target_home/.bashrc"
    [[ -f "$bashrc_path" && ! -L "$bashrc_path" && -r "$bashrc_path" ]] || return 1
    bash_bin="$(user_system_binary_path bash)" || return 1
    "$bash_bin" --noprofile --norc -n -- "$bashrc_path" 2>/dev/null || return 1

    # Verify the complete block, including exec and fi. A partial block that
    # only sets the recursion guard would suppress a later working handoff.
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:blank:]]*}"}"
        line="${line%"${line##*[![:blank:]]}"}"
        case "$line" in
            '# ACFS externally-managed shell handoff')
                [[ "$state" -lt 2 ]] && state=1
                continue
                ;;
            ''|\#*) continue ;;
        esac
        case "$state" in
            0|1)
                if [[ "$state" -eq 1 && "$line" == "$guard" ]]; then
                    state=2
                elif [[ "$line" == *ACFS_ZSH_HANDOFF_ACTIVE* ]]; then
                    return 1
                else
                    state=0
                fi
                ;;
            2)
                [[ "$line" == 'export ACFS_ZSH_HANDOFF_ACTIVE=1' ]] || return 1
                state=3
                ;;
            3)
                [[ "$line" == 'exec "$(command -v zsh)" -l' ]] || return 1
                state=4
                ;;
            4)
                [[ "$line" == 'fi' ]] || return 1
                state=0
                found=true
                ;;
        esac
    done < "$bashrc_path"
    [[ "$found" == true && "$state" -lt 2 ]]
}

user_append_external_shell_handoff() {
    local target_home="${1:-}"
    local bashrc_path="" bash_bin="" line=""
    bashrc_path="${target_home}/.bashrc"

    [[ "$target_home" == /* && "$target_home" != / ]] || return 1
    [[ ! -L "$bashrc_path" ]] || return 1
    [[ ! -e "$bashrc_path" || -f "$bashrc_path" ]] || return 1
    if user_external_shell_handoff_configured "$target_home"; then
        return 0
    fi

    if [[ -e "$bashrc_path" ]]; then
        [[ -r "$bashrc_path" ]] || return 1
        bash_bin="$(user_system_binary_path bash)" || return 1
        "$bash_bin" --noprofile --norc -n -- "$bashrc_path" || return 1
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line#"${line%%[![:blank:]]*}"}"
            case "$line" in
                ''|\#*) continue ;;
                *ACFS_ZSH_HANDOFF_ACTIVE*) return 1 ;;
            esac
        done < "$bashrc_path"
    fi

    # Always separate the block from an unterminated final line. Use builtins
    # so writing the handoff does not resolve utilities from the user's PATH.
    (
        umask 077
        printf '%s\n' '' \
            '# ACFS externally-managed shell handoff' \
            'if [[ $- == *i* ]] && [[ -t 0 ]] && command -v zsh >/dev/null 2>&1 && [[ -z "${ACFS_ZSH_HANDOFF_ACTIVE:-}" ]]; then' \
            '    export ACFS_ZSH_HANDOFF_ACTIVE=1' \
            '    exec "$(command -v zsh)" -l' \
            'fi' >> "$bashrc_path"
    ) || return 1
    user_external_shell_handoff_configured "$target_home"
}

user_login_shell_configured() {
    local target="${1:-${TARGET_USER:-}}" entry="" local_entry="" local_status=0
    local target_home="" shell="" bash_bin=""

    entry="$(user_login_passwd_entry "$target")" || return 1
    IFS=: read -r _ _ _ _ _ target_home shell <<< "$entry"
    user_shell_is_approved "$shell" || return 1
    user_shell_executable_by_account "$shell" "$target" || return 1
    local_entry="$(user_local_passwd_entry "$target")" || local_status=$?
    if [[ "$local_status" -eq 0 ]]; then
        user_login_accounts_match "$entry" "$local_entry" || return 1
        [[ "${shell##*/}" == zsh ]]
    elif [[ "$local_status" -eq 1 ]]; then
        [[ "${shell##*/}" == zsh ]] && return 0
        [[ "${shell##*/}" == bash ]] || return 1
        user_select_login_shell "" "$target" >/dev/null || return 1
        bash_bin="$(user_system_binary_path bash)" || return 1
        user_run_as_account "$target" "$bash_bin" -c "$(declare -f user_system_binary_path user_external_shell_handoff_configured)
            user_external_shell_handoff_configured \"\$1\"" _ "$target_home"
    else
        return 1
    fi
}

set_default_shell() {
    local preferred="${1:-}" target="${TARGET_USER:-}" target_home=""
    local before="" local_before="" local_status=0 original="" shell=""
    local chsh_bin="" sudo_bin="" bash_bin="" current_user=""
    local after="" local_after="" chsh_status=0 rollback_status=0
    local -a change_command=()

    user_require_valid_target_user "$target"
    if ! before="$(user_login_passwd_entry "$target")"; then
        log_error "Cannot read a reliable login-shell record for $target; refusing to change it"
        return 1
    fi
    IFS=: read -r _ _ _ _ _ target_home original <<< "$before"
    local_before="$(user_local_passwd_entry "$target")" || local_status=$?
    if [[ "$local_status" -gt 1 ]]; then
        log_error "Cannot read /etc/passwd; refusing to change the shell for $target"
        return 1
    fi
    if [[ "$local_status" -eq 0 ]] && ! user_login_accounts_match "$before" "$local_before"; then
        log_error "Local and NSS account records disagree for $target; refusing a local shell change"
        return 1
    fi

    # $SHELL belongs to the invoking session and can be stale. Re-check the
    # actual account even on reruns and when its current path ends in /zsh.
    if user_login_shell_configured "$target"; then
        log_detail "Login-shell configuration already verified for $target"
        return 0
    fi
    if ! shell="$(user_select_login_shell "$preferred")"; then
        log_error "No executable zsh is approved by a readable, safe /etc/shells; refusing to change $target's login shell"
        return 1
    fi
    bash_bin="$(user_system_binary_path bash)" || return 1
    if ! user_run_as_account "$target" "$bash_bin" -c '[[ -f "$1" && -x "$1" ]]' _ "$shell"; then
        log_error "Approved shell $shell is not executable by $target; refusing to change its login shell"
        return 1
    fi

    if [[ "$local_status" -eq 1 ]]; then
        # An interactive handoff does not alter the authentication shell. Only
        # Bash accounts can consume .bashrc; do not claim success for other or
        # already-rejected provider-managed login shells.
        if [[ "${original##*/}" != bash ]] || ! user_shell_is_approved "$original"; then
            log_error "Shell for $target is externally managed and cannot be safely configured locally; ask the identity provider administrator to set an approved shell"
            return 1
        fi
        if ! user_run_as_account "$target" "$bash_bin" -c "$(declare -f user_system_binary_path user_external_shell_handoff_configured user_append_external_shell_handoff)
            user_append_external_shell_handoff \"\$1\"" _ "$target_home"; then
            log_error "Could not configure the external-account shell handoff for $target"
            return 1
        fi
        after="$(user_login_passwd_entry "$target")" || return 1
        if [[ "$after" != "$before" ]] || ! user_login_shell_configured "$target"; then
            log_error "Could not verify the external-account shell handoff for $target"
            return 1
        fi
        log_warn "Shell for $target is managed outside /etc/passwd; verified a bash-to-zsh handoff without changing its login shell"
        return 0
    fi

    chsh_bin="$(user_system_binary_path chsh)" || {
        log_error "Cannot locate chsh; refusing to report a successful shell change for $target"
        return 1
    }
    if [[ "$EUID" -eq 0 ]]; then
        change_command=("$chsh_bin")
    else
        sudo_bin="$(user_system_binary_path sudo 2>/dev/null || true)"
        current_user="$(user_resolve_current_user 2>/dev/null || true)"
        if [[ -n "$sudo_bin" ]] && "$sudo_bin" -n true 2>/dev/null; then
            change_command=("$sudo_bin" -n "$chsh_bin")
        elif [[ "$current_user" == "$target" && -t 0 ]]; then
            change_command=("$chsh_bin")
        else
            log_error "Cannot change the login shell for $target without privilege or an interactive terminal. Run: chsh -s $shell"
            return 1
        fi
    fi

    if ! user_preserve_login_shell "$target" "$target_home" "$original"; then
        log_error "Cannot safely preserve the original shell in $target_home/.shell.pre-acfs; refusing the shell change"
        return 1
    fi
    # Re-read immediately before mutation so stale NSS/local state cannot
    # change the account for which the recovery record was captured.
    after="$(user_login_passwd_entry "$target")" || return 1
    local_after="$(user_local_passwd_entry "$target")" || return 1
    if [[ "$after" != "$before" || "$local_after" != "$local_before" ]] ||
       ! user_shell_is_approved "$shell" || ! user_shell_executable_by_account "$shell" "$target"; then
        log_error "Account or approved-shell policy changed during setup; refusing to change $target's shell"
        return 1
    fi
    log_detail "Setting login shell to $shell for $target (original preserved in $target_home/.shell.pre-acfs)"
    "${change_command[@]}" -s "$shell" "$target" || chsh_status=$?

    # chsh can warn and return success, fail after writing, or do nothing.
    # Verify both NSS and the local account, and re-check authentication policy.
    after="$(user_login_passwd_entry "$target" 2>/dev/null || true)"
    local_after="$(user_local_passwd_entry "$target" 2>/dev/null || true)"
    if [[ -n "$after" && "$after" == "${before%:*}:$shell" ]] &&
       [[ "$local_after" == "${local_before%:*}:$shell" ]] &&
       user_shell_is_approved "$shell" && user_shell_executable_by_account "$shell" "$target"; then
        if [[ "$chsh_status" -eq 0 ]]; then
            log_success "Verified approved login shell $shell for $target"
            return 0
        fi
        log_error "chsh exited $chsh_status despite applying the approved shell for $target; attempting to restore the original account state"
    fi

    log_error "Login-shell change for $target failed verification (chsh exit $chsh_status)"
    # Restore only an approved original, and only while the same local identity
    # remains present. Never turn a repaired usrmerge alias back into a known
    # invalid login shell or overwrite a different account's state.
    if [[ -n "$after" && "${after%:*}" == "${before%:*}" &&
          -n "$local_after" && "${local_after%:*}" == "${local_before%:*}" &&
          "${local_after##*:}" != "$original" ]] &&
       user_shell_is_approved "$original" && user_shell_executable_by_account "$original" "$target"; then
        "${change_command[@]}" -s "$original" "$target" || rollback_status=$?
        after="$(user_login_passwd_entry "$target" 2>/dev/null || true)"
        local_after="$(user_local_passwd_entry "$target" 2>/dev/null || true)"
        if [[ "$after" == "$before" && "$local_after" == "$local_before" ]] &&
           user_shell_is_approved "$original" && user_shell_executable_by_account "$original" "$target"; then
            log_warn "Restored and verified the original login shell for $target"
        else
            log_error "Could not verify restoration for $target (chsh exit $rollback_status); keep this session open and repair the account from another administrator session"
        fi
    fi
    log_error "Original shell: $original; recovery record: $target_home/.shell.pre-acfs. Keep this session open until the account's shell is repaired and verified against /etc/shells"
    return 1
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

    if [[ "${YES_MODE:-false}" == "true" && "$has_existing_key" == "true" ]]; then
        log_detail "SSH keys already present; keeping existing keys (--yes mode)"
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

    if [[ "${YES_MODE:-false}" == "true" ]]; then
        if [[ -z "$prompt_fd" ]]; then
            log_warn "No SSH public key found for root; skipping SSH key prompt in --yes mode"
            log_detail "After install, use the final summary's root fallback if you only have the VPS root password"
            export ACFS_SSH_KEY_WARNING="true"
            return 0
        fi
        log_warn "No SSH public key found for root; prompting for one even in --yes mode"
    fi

    if [[ -z "$prompt_fd" ]]; then
        if [[ "$has_existing_key" == "true" ]]; then
            log_detail "SSH key already present (non-interactive mode)"
            return 0
        fi
        log_warn "Non-interactive mode detected (no TTY), skipping SSH key prompt"
        log_detail "After install, use the final summary's root fallback if you only have the VPS root password"
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
            log_detail "  Use the final summary's root fallback if you only have the VPS root password"
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
    log_detail "ACFS will copy this key to ${TARGET_USER:-ubuntu}; after install, reconnect with the matching private key:"
    log_detail "  ssh -i ~/.ssh/your_key ${TARGET_USER:-ubuntu}@<this_ip>"

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
