#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Post-Install Services Setup
# Interactive wizard to configure AI agents and cloud services
# Run after main installer completes: acfs services-setup
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries - try installed location first, then development location
if [[ -f "$HOME/.acfs/scripts/lib/logging.sh" ]]; then
    source "$HOME/.acfs/scripts/lib/logging.sh"
    source "$HOME/.acfs/scripts/lib/gum_ui.sh"
elif [[ -f "$SCRIPT_DIR/lib/logging.sh" ]]; then
    source "$SCRIPT_DIR/lib/logging.sh"
    source "$SCRIPT_DIR/lib/gum_ui.sh"
else
    echo "Error: Cannot find ACFS script libraries"
    echo "Expected at: $HOME/.acfs/scripts/lib/ or $SCRIPT_DIR/lib/"
    exit 1
fi

# ============================================================
# Configuration
# ============================================================

TARGET_USER="${TARGET_USER:-${SUDO_USER:-$(whoami)}}"
SERVICES_SETUP_ACTION="${SERVICES_SETUP_ACTION:-}"
SERVICES_SETUP_NONINTERACTIVE="${SERVICES_SETUP_NONINTERACTIVE:-false}"

resolve_home_dir() {
    local user="$1"
    local home=""

    if command -v getent &>/dev/null; then
        home="$(getent passwd "$user" 2>/dev/null | cut -d: -f6)"
    elif [[ -r /etc/passwd ]]; then
        home="$(awk -F: -v u="$user" '$1==u{print $6}' /etc/passwd)"
    fi

    printf '%s' "$home"
}

TARGET_HOME="${TARGET_HOME:-}"
BUN_BIN="${BUN_BIN:-}"

init_target_context() {
    if [[ -z "${TARGET_HOME:-}" ]]; then
        TARGET_HOME="$(resolve_home_dir "$TARGET_USER")"
    fi
    if [[ -z "${TARGET_HOME:-}" ]]; then
        log_error "Unable to determine home directory for user: $TARGET_USER"
        return 1
    fi

    if [[ -z "${BUN_BIN:-}" ]]; then
        BUN_BIN="$TARGET_HOME/.bun/bin/bun"
    fi
}

# Service status tracking
declare -A SERVICE_STATUS

# ============================================================
# Helper Functions
# ============================================================

# Run a command (argv) as target user.
#
# Prefer argv mode to avoid quoting pitfalls (paths with spaces, etc.).
run_as_user() {
    if [[ $# -lt 1 ]]; then
        return 0
    fi

    if [[ "$(whoami)" == "$TARGET_USER" ]]; then
        "$@"
        return $?
    fi

    sudo -u "$TARGET_USER" -H "$@"
}

# Run a shell string as target user (use for pipelines/redirections).
run_as_user_shell() {
    local cmd="$1"
    if [[ "$(whoami)" == "$TARGET_USER" ]]; then
        bash -c "$cmd"
    else
        sudo -u "$TARGET_USER" -H bash -c "$cmd"
    fi
}

# Check if a command exists in target user's PATH
# More robust than checking binary paths directly - respects user's PATH
user_command_exists() {
    local cmd="$1"
    # Include common user install locations (bun/cargo/etc) even when running
    # via sudo, which may otherwise provide a restricted PATH.
    # shellcheck disable=SC2016  # $HOME/$PATH expand inside the target user's bash -c
    run_as_user bash -c \
        'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.bun/bin:$HOME/.atuin/bin:$HOME/go/bin:$PATH"; command -v -- "$1" >/dev/null 2>&1' \
        _ "$cmd"
}

# Check if a file exists (from current user perspective)
# Used for checking config files in target user's home
user_file_exists() {
    local path="$1"
    [[ -f "$path" ]]
}

# Check if a directory exists and is non-empty
user_dir_has_content() {
    local path="$1"
    [[ -d "$path" && -n "$(ls -A "$path" 2>/dev/null)" ]]
}

find_user_bin() {
    local name="$1"

    local candidates=(
        "$TARGET_HOME/.local/bin/$name"
        "$TARGET_HOME/.cargo/bin/$name"
        "$TARGET_HOME/.bun/bin/$name"
        "$TARGET_HOME/.atuin/bin/$name"
        "/usr/local/bin/$name"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -x "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    return 1
}

dcg_hook_registered() {
    local settings_file="$TARGET_HOME/.claude/settings.json"
    local alt_settings_file="$TARGET_HOME/.config/claude/settings.json"

    if [[ -f "$settings_file" ]] && grep -q "dcg" "$settings_file" 2>/dev/null; then
        return 0
    fi

    if [[ -f "$alt_settings_file" ]] && grep -q "dcg" "$alt_settings_file" 2>/dev/null; then
        return 0
    fi

    return 1
}

select_dcg_packs() {
    local -a options=(
        "database.postgresql (PostgreSQL guard pack)"
        "kubernetes (kubectl + cluster safety)"
        "cloud.aws (AWS CLI guard pack)"
    )

    local selected_lines=""

    if [[ "$HAS_GUM" == "true" ]]; then
        if [[ -r /dev/tty ]]; then
            selected_lines=$(gum choose --no-limit \
                --header "Select additional DCG packs (space to toggle, enter to confirm)" \
                --cursor.foreground "$ACFS_ACCENT" \
                --selected.foreground "$ACFS_SUCCESS" \
                "${options[@]}" < /dev/tty) || true
        elif [[ -t 0 ]]; then
            selected_lines=$(gum choose --no-limit \
                --header "Select additional DCG packs (space to toggle, enter to confirm)" \
                --cursor.foreground "$ACFS_ACCENT" \
                --selected.foreground "$ACFS_SUCCESS" \
                "${options[@]}") || true
        else
            echo "ERROR: --yes is required when no TTY is available" >&2
            return 1
        fi
    else
        echo "Select additional DCG packs (enter numbers separated by spaces, or 'all')"
        local i=1
        for opt in "${options[@]}"; do
            echo "  $i) $opt"
            ((i++))
        done

        local input=""
        if [[ -t 0 ]]; then
            read -r -p "Select: " input
        elif [[ -r /dev/tty ]]; then
            read -r -p "Select: " input < /dev/tty
        else
            echo "ERROR: --yes is required when no TTY is available" >&2
            return 1
        fi

        if [[ "$input" == "all" ]]; then
            for opt in "${options[@]}"; do
                selected_lines+="${opt}"$'\n'
            done
        else
            for num in $input; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le ${#options[@]} ]]; then
                    selected_lines+="${options[$((num - 1))]}"$'\n'
                fi
            done
        fi
    fi

    local -a packs=()
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        packs+=("${line%% *}")
    done <<< "$selected_lines"

    printf '%s' "${packs[*]}"
}

remove_dcg_hook_from_settings() {
    local settings_file="$1"

    if [[ -L "$settings_file" ]]; then
        gum_warn "Skipping DCG hook cleanup (symlink): $settings_file"
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        gum_warn "jq not available; cannot remove DCG hook automatically"
        gum_detail "Remove the dcg hook entry from: $settings_file"
        return 1
    fi

    local settings_dir
    settings_dir="$(dirname "$settings_file")"

    local tmp
    tmp="$(run_as_user mktemp "${settings_dir}/.acfs_dcg_cleanup.XXXXXX" 2>/dev/null || true)"
    if [[ -z "$tmp" ]]; then
        gum_warn "Could not update $settings_file (mktemp failed)"
        return 1
    fi

    local jq_program
    jq_program="$(cat <<'JQ'
def strip_dcg:
  if (type == "object" and has("hooks") and (.hooks | type) == "array") then
    .hooks |= [ .[]? | select(.type != "command" or ((.command // "") | test("dcg") | not)) ] |
    select((.hooks | length) > 0)
  else
    select(.type != "command" or ((.command // "") | test("dcg") | not))
  end;

.hooks = (.hooks // {}) |
if (.hooks.PreToolUse | type) != "array" then
  .hooks.PreToolUse = []
else
  .hooks.PreToolUse = [
    .hooks.PreToolUse[]?
    | strip_dcg
  ]
end
JQ
)"

    if run_as_user jq "$jq_program" "$settings_file" 2>/dev/null | run_as_user tee "$tmp" >/dev/null; then
        run_as_user mv -- "$tmp" "$settings_file" 2>/dev/null || {
            run_as_user rm -f -- "$tmp" 2>/dev/null || true
            gum_warn "Could not update $settings_file (mv failed)"
            return 1
        }
    else
        run_as_user rm -f -- "$tmp" 2>/dev/null || true
        gum_warn "Could not update $settings_file (invalid JSON?)"
        return 1
    fi

    return 0
}

cleanup_stale_dcg_hook() {
    if user_command_exists dcg; then
        return 0
    fi

    if ! dcg_hook_registered; then
        return 0
    fi

    gum_warn "DCG hook registered but dcg binary is missing"
    gum_detail "You can reinstall DCG or remove the hook registration."

    if [[ "$SERVICES_SETUP_NONINTERACTIVE" == "true" ]]; then
        gum_detail "Skipping cleanup (noninteractive)"
        return 0
    fi

    if ! gum_confirm "Remove stale DCG hook from Claude settings?"; then
        gum_warn "Skipped removing DCG hook"
        return 0
    fi

    local cleaned_any="false"
    local settings_file=""
    local settings_files=(
        "$TARGET_HOME/.claude/settings.json"
        "$TARGET_HOME/.config/claude/settings.json"
    )

    for settings_file in "${settings_files[@]}"; do
        if [[ -f "$settings_file" ]]; then
            if remove_dcg_hook_from_settings "$settings_file"; then
                cleaned_any="true"
                gum_success "Removed DCG hook from $settings_file"
            fi
        fi
    done

    if [[ "$cleaned_any" != "true" ]]; then
        gum_warn "No DCG hook entries removed"
    fi
}

# ============================================================
# Status Check Functions
# ============================================================

check_claude_status() {
    local claude_bin
    claude_bin="$(find_user_bin "claude" 2>/dev/null || true)"

    if [[ -z "$claude_bin" || ! -x "$claude_bin" ]]; then
        SERVICE_STATUS[claude]="not_installed"
        return
    fi

    # Directory existence/content alone is not enough to indicate authentication.
    # Require an actual config file.
    if user_file_exists "$TARGET_HOME/.claude/config.json" || \
       user_file_exists "$TARGET_HOME/.config/claude/config.json"; then
        SERVICE_STATUS[claude]="configured"
    else
        SERVICE_STATUS[claude]="installed"
    fi
}

check_codex_status() {
    local codex_bin
    codex_bin="$(find_user_bin "codex" 2>/dev/null || true)"

    if [[ -z "$codex_bin" || ! -x "$codex_bin" ]]; then
        SERVICE_STATUS[codex]="not_installed"
        return
    fi

    # Check for OAuth auth.json or config files
    if user_file_exists "$TARGET_HOME/.codex/auth.json" || \
       user_file_exists "$TARGET_HOME/.codex/config.json" || \
       user_file_exists "$TARGET_HOME/.config/codex/config.json"; then
        SERVICE_STATUS[codex]="configured"
    else
        SERVICE_STATUS[codex]="installed"
    fi
}

check_gemini_status() {
    local gemini_bin
    gemini_bin="$(find_user_bin "gemini" 2>/dev/null || true)"

    if [[ -z "$gemini_bin" || ! -x "$gemini_bin" ]]; then
        SERVICE_STATUS[gemini]="not_installed"
        return
    fi

    # Check for credentials (OAuth web login, like Claude Code and Codex CLI)
    # Directory existence/content alone is not enough - require actual credential files.
    if user_file_exists "$TARGET_HOME/.config/gemini/credentials.json" || \
       user_file_exists "$TARGET_HOME/.gemini/config"; then
        SERVICE_STATUS[gemini]="configured"
    else
        SERVICE_STATUS[gemini]="installed"
    fi
}

check_vercel_status() {
    local vercel_bin="$TARGET_HOME/.bun/bin/vercel"

    if [[ ! -x "$vercel_bin" ]]; then
        SERVICE_STATUS[vercel]="not_installed"
        return
    fi

    # Check if logged in by looking for auth token
    if user_file_exists "$TARGET_HOME/.config/vercel/auth.json" || \
       user_file_exists "$TARGET_HOME/.vercel/auth.json" || \
       [[ -n "${VERCEL_TOKEN:-}" ]]; then
        SERVICE_STATUS[vercel]="configured"
    else
        SERVICE_STATUS[vercel]="installed"
    fi
}

check_supabase_status() {
    local supabase_bin
    supabase_bin="$(find_user_bin "supabase" 2>/dev/null || true)"

    if [[ -z "$supabase_bin" || ! -x "$supabase_bin" ]]; then
        SERVICE_STATUS[supabase]="not_installed"
        return
    fi

    # Check for access token
    if user_file_exists "$TARGET_HOME/.supabase/access-token" || \
       user_file_exists "$TARGET_HOME/.config/supabase/access-token" || \
       [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
        SERVICE_STATUS[supabase]="configured"
    else
        SERVICE_STATUS[supabase]="installed"
    fi
}

check_wrangler_status() {
    local wrangler_bin="$TARGET_HOME/.bun/bin/wrangler"

    if [[ ! -x "$wrangler_bin" ]]; then
        SERVICE_STATUS[wrangler]="not_installed"
        return
    fi

    # Check for Cloudflare credentials
    if user_file_exists "$TARGET_HOME/.config/wrangler/config/default.toml" || \
        user_file_exists "$TARGET_HOME/.wrangler/config/default.toml" || \
        [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        SERVICE_STATUS[wrangler]="configured"
    else
        SERVICE_STATUS[wrangler]="installed"
    fi
}

check_postgres_status() {
    # Check if psql is available to the target user
    if ! user_command_exists psql; then
        SERVICE_STATUS[postgres]="not_installed"
        return
    fi

    # Check if service is running and user can connect
    if run_as_user psql -c 'SELECT 1' &>/dev/null; then
        SERVICE_STATUS[postgres]="configured"
    elif systemctl is-active --quiet postgresql 2>/dev/null; then
        SERVICE_STATUS[postgres]="running"
    else
        SERVICE_STATUS[postgres]="installed"
    fi
}

check_dcg_status() {
    if ! user_command_exists dcg; then
        SERVICE_STATUS[dcg]="not_installed"
        return
    fi

    if ! user_command_exists claude; then
        SERVICE_STATUS[dcg]="installed"
        return
    fi

    if dcg_hook_registered; then
        SERVICE_STATUS[dcg]="configured"
    else
        SERVICE_STATUS[dcg]="installed"
    fi
}

check_all_status() {
    check_claude_status
    check_codex_status
    check_gemini_status
    check_vercel_status
    check_supabase_status
    check_wrangler_status
    check_postgres_status
    check_dcg_status
}

# ============================================================
# Status Display
# ============================================================

get_status_icon() {
    local status="$1"
    case "$status" in
        configured) echo "✓" ;;
        running)    echo "●" ;;
        installed)  echo "○" ;;
        *)          echo "✗" ;;
    esac
}

get_status_color() {
    local status="$1"
    case "$status" in
        configured) echo "$ACFS_SUCCESS" ;;
        running)    echo "$ACFS_WARNING" ;;
        installed)  echo "$ACFS_WARNING" ;;
        *)          echo "$ACFS_ERROR" ;;
    esac
}

print_status_table() {
    echo ""
    gum_section "Service Status"
    echo ""

    local services=("claude" "codex" "gemini" "vercel" "supabase" "wrangler" "postgres")
    local labels=("Claude Code" "Codex CLI" "Gemini CLI" "Vercel" "Supabase" "Cloudflare" "PostgreSQL")
    local categories=("AI Agent" "AI Agent" "AI Agent" "Cloud" "Cloud" "Cloud" "Database")

    if [[ "$HAS_GUM" == "true" ]]; then
        # Use gum table for beautiful display
        local table_data="Service,Category,Status,Action\n"
        for i in "${!services[@]}"; do
            local svc="${services[$i]}"
            local label="${labels[$i]}"
            local category="${categories[$i]}"
            local status="${SERVICE_STATUS[$svc]:-unknown}"
            local icon
            icon=$(get_status_icon "$status")
            local action=""
            case "$status" in
                configured) action="Ready" ;;
                running|installed) action="Needs setup" ;;
                not_installed) action="Install first" ;;
                *) action="Check" ;;
            esac
            table_data+="$icon $label,$category,$status,$action\n"
        done

        local dcg_status="${SERVICE_STATUS[dcg]:-unknown}"
        local dcg_icon
        dcg_icon=$(get_status_icon "$dcg_status")
        local dcg_action=""
        case "$dcg_status" in
            configured) dcg_action="Ready" ;;
            installed) dcg_action="Needs setup" ;;
            not_installed) dcg_action="Install first" ;;
            *) dcg_action="Check" ;;
        esac
        table_data+="$dcg_icon DCG (Destructive Command Guard),Safety,$dcg_status,$dcg_action\n"

        echo -e "$table_data" | gum table \
            --border.foreground "$ACFS_MUTED" \
            --header.foreground "$ACFS_PRIMARY"
    else
        # Fallback to simple display
        for i in "${!services[@]}"; do
            local svc="${services[$i]}"
            local label="${labels[$i]}"
            local status="${SERVICE_STATUS[$svc]:-unknown}"
            local icon
            icon=$(get_status_icon "$status")

            case "$status" in
                configured) echo -e "\033[32m  $icon $label: $status\033[0m" ;;
                running|installed) echo -e "\033[33m  $icon $label: $status\033[0m" ;;
                *) echo -e "\033[31m  $icon $label: $status\033[0m" ;;
            esac
        done

        local dcg_status="${SERVICE_STATUS[dcg]:-unknown}"
        local dcg_icon
        dcg_icon=$(get_status_icon "$dcg_status")
        case "$dcg_status" in
            configured) echo -e "\033[32m  $dcg_icon DCG (Destructive Command Guard): $dcg_status\033[0m" ;;
            running|installed) echo -e "\033[33m  $dcg_icon DCG (Destructive Command Guard): $dcg_status\033[0m" ;;
            *) echo -e "\033[31m  $dcg_icon DCG (Destructive Command Guard): $dcg_status\033[0m" ;;
        esac
    fi
    echo ""
}

# ============================================================
# Setup Functions
# ============================================================

setup_claude() {
    local claude_bin
    claude_bin="$(find_user_bin "claude" 2>/dev/null || true)"

    if [[ -z "$claude_bin" || ! -x "$claude_bin" ]]; then
        gum_error "Claude Code not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[claude]}" == "configured" ]]; then
        if ! gum_confirm "Claude Code appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    gum_box "Claude Code Setup" "Claude Code uses OAuth to authenticate.
When you run 'claude', it will:
1. Open a browser window (or show a URL)
2. Ask you to log in with your Anthropic account
3. Authorize the CLI

Press Enter to launch Claude Code login..."

    read -r

    # Run claude interactively
    run_as_user "$claude_bin" || true

    # Re-check status
    check_claude_status
    if [[ "${SERVICE_STATUS[claude]}" == "configured" ]]; then
        gum_success "Claude Code configured successfully!"
    else
        gum_warn "Claude Code may not be fully configured. Try running 'claude' again."
    fi
}

setup_codex() {
    local codex_bin
    codex_bin="$(find_user_bin "codex" 2>/dev/null || true)"

    if [[ -z "$codex_bin" || ! -x "$codex_bin" ]]; then
        gum_error "Codex CLI not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[codex]}" == "configured" ]]; then
        if ! gum_confirm "Codex CLI appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    gum_box "Codex CLI Setup" "Codex CLI uses OAuth login with your ChatGPT account.
We'll launch the login flow in your terminal/browser."

    gum_detail "Launching Codex OAuth login..."
    run_as_user "$codex_bin" login || true

    check_codex_status
    if [[ "${SERVICE_STATUS[codex]}" == "configured" ]]; then
        gum_success "Codex CLI configured successfully!"
    fi
}

configure_dcg() {
    cleanup_stale_dcg_hook

    local dcg_bin
    dcg_bin="$(find_user_bin "dcg" 2>/dev/null || true)"

    if [[ -z "$dcg_bin" || ! -x "$dcg_bin" ]]; then
        gum_error "DCG not installed. Run the main installer first."
        gum_detail "Then run: dcg install (or re-run acfs services-setup)"
        return 1
    fi

    if [[ "$SERVICES_SETUP_NONINTERACTIVE" != "true" ]]; then
        gum_box "DCG Safety Primer" "DCG (Destructive Command Guard) blocks dangerous commands before they run.

Examples it will block:
  • git reset --hard
  • rm -rf ./src
  • DROP TABLE users

When blocked, you'll see:
  • Why it matched
  • A safer alternative
  • An allow-once code for legit bypasses

Try it:
  dcg test 'git status'
  dcg test 'git reset --hard' --explain"
    fi

    gum_box "DCG Setup" "DCG blocks destructive git/filesystem commands before they execute.
It also supports optional protection packs (database, Kubernetes, cloud)."

    if user_command_exists claude; then
        if dcg_hook_registered; then
            gum_success "DCG hook already registered with Claude Code"
        else
            if [[ "$SERVICES_SETUP_NONINTERACTIVE" == "true" ]]; then
                gum_detail "Registering DCG hook (noninteractive)"
                run_as_user "$dcg_bin" install --yes || gum_warn "DCG hook registration failed"
            else
                if gum_confirm "Register DCG hook for Claude Code?"; then
                    run_as_user "$dcg_bin" install || gum_warn "DCG hook registration failed"
                else
                    gum_warn "Skipped DCG hook registration"
                    gum_detail "You can enable later with: dcg install"
                fi
            fi
        fi
    else
        gum_warn "Claude Code not detected; skipping hook registration"
        gum_detail "Install Claude Code, then run: dcg install"
    fi

    if user_command_exists claude && ! run_as_user "$dcg_bin" doctor &>/dev/null; then
        gum_warn "DCG doctor reported issues"
        if [[ "$SERVICES_SETUP_NONINTERACTIVE" == "true" ]]; then
            gum_detail "Attempting DCG repair (noninteractive)"
            run_as_user "$dcg_bin" install --force --yes || gum_warn "DCG repair failed"
        else
            if gum_confirm "Attempt DCG repair by re-registering the hook?"; then
                run_as_user "$dcg_bin" install --force || gum_warn "DCG repair failed"
            else
                gum_warn "Skipped DCG repair"
            fi
        fi
    fi

    if [[ "$SERVICES_SETUP_NONINTERACTIVE" == "true" ]]; then
        gum_detail "Skipping pack selection (noninteractive)"
        return 0
    fi

    if ! gum_confirm "Enable additional DCG protection packs?"; then
        return 0
    fi

    local selected
    selected="$(select_dcg_packs)"
    if [[ -z "$selected" ]]; then
        gum_warn "No packs selected"
        return 0
    fi

    local config_dir="$TARGET_HOME/.config/dcg"
    local config_file="$config_dir/config.toml"

    if [[ -L "$config_dir" || -L "$config_file" ]]; then
        gum_error "Refusing to operate: $config_dir or $config_file is a symlink"
        return 1
    fi

    if [[ -f "$config_file" ]]; then
        if ! gum_confirm "Update existing DCG config at $config_file?"; then
            gum_warn "Skipped DCG config update"
            return 0
        fi
    fi

    run_as_user mkdir -p "$config_dir"

    {
        echo "[packs]"
        echo "enabled = ["
        for pack in $selected; do
            echo "    \"${pack}\","
        done
        echo "]"
    } | run_as_user tee "$config_file" >/dev/null

    gum_success "DCG config written to $config_file"
}


print_cli_help() {
    cat << 'EOF'
ACFS services-setup

Interactive:
  acfs services-setup

Options:
  --yes, -y    Non-interactive mode
  --install-claude-guard  Install DCG hook for Claude Code (non-interactive)
  --help, -h   Show this help
EOF
}

maybe_run_cli_action() {
    local arg

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --yes|-y)
                SERVICES_SETUP_NONINTERACTIVE="true"
                ;;
            --install-claude-guard)
                SERVICES_SETUP_ACTION="install-claude-guard"
                SERVICES_SETUP_NONINTERACTIVE="true"
                ;;
            --help|-h)
                SERVICES_SETUP_ACTION="help"
                ;;
            *)
                ;;
        esac
        shift || true
    done

    return 0
}

run_cli_action() {
    case "${SERVICES_SETUP_ACTION:-}" in
        help)
            print_cli_help
            return 0
            ;;
        install-claude-guard)
            if ! init_target_context; then
                return 1
            fi
            configure_dcg
            return $?
            ;;
        *)
            return 1
            ;;
    esac
}

setup_gemini() {
    local gemini_bin
    gemini_bin="$(find_user_bin "gemini" 2>/dev/null || true)"

    if [[ -z "$gemini_bin" || ! -x "$gemini_bin" ]]; then
        gum_error "Gemini CLI not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[gemini]}" == "configured" ]]; then
        if ! gum_confirm "Gemini CLI appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    gum_box "Gemini CLI Setup" "Gemini CLI uses Google OAuth to authenticate.
When you run 'gemini', it will:
1. Open a browser window (or show a URL)
2. Ask you to log in with your Google account
3. Authorize the CLI

Press Enter to launch Gemini login..."

    read -r

    run_as_user "$gemini_bin" || true

    check_gemini_status
    if [[ "${SERVICE_STATUS[gemini]}" == "configured" ]]; then
        gum_success "Gemini CLI configured successfully!"
    fi
}

setup_vercel() {
    local vercel_bin="$TARGET_HOME/.bun/bin/vercel"

    if [[ ! -x "$vercel_bin" ]]; then
        gum_error "Vercel CLI not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[vercel]}" == "configured" ]]; then
        if ! gum_confirm "Vercel appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    gum_box "Vercel Setup" "Vercel CLI uses OAuth to authenticate.

Press Enter to launch 'vercel login'..."

    read -r

    run_as_user "$vercel_bin" login || true

    check_vercel_status
    if [[ "${SERVICE_STATUS[vercel]}" == "configured" ]]; then
        gum_success "Vercel configured successfully!"
    fi
}

setup_supabase() {
    local supabase_bin
    supabase_bin="$(find_user_bin "supabase" 2>/dev/null || true)"

    if [[ -z "$supabase_bin" || ! -x "$supabase_bin" ]]; then
        gum_error "Supabase CLI not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[supabase]}" == "configured" ]]; then
        if ! gum_confirm "Supabase appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    gum_box "Supabase Setup" "Supabase CLI uses OAuth to authenticate.

Note: some Supabase projects expose the direct Postgres host over IPv6-only.
If your VPS/network is IPv4-only, use the Supabase pooler connection string instead.

Press Enter to launch 'supabase login'..."

    read -r

    run_as_user "$supabase_bin" login || true

    check_supabase_status
    if [[ "${SERVICE_STATUS[supabase]}" == "configured" ]]; then
        gum_success "Supabase configured successfully!"
    fi
}

setup_wrangler() {
    local wrangler_bin="$TARGET_HOME/.bun/bin/wrangler"

    if [[ ! -x "$wrangler_bin" ]]; then
        gum_error "Wrangler (Cloudflare) CLI not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[wrangler]}" == "configured" ]]; then
        if ! gum_confirm "Cloudflare/Wrangler appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    gum_box "Cloudflare Wrangler Setup" "Wrangler uses OAuth to authenticate with Cloudflare.

Press Enter to launch 'wrangler login'..."

    read -r

    run_as_user "$wrangler_bin" login || true

    check_wrangler_status
    if [[ "${SERVICE_STATUS[wrangler]}" == "configured" ]]; then
        gum_success "Cloudflare/Wrangler configured successfully!"
    fi
}

setup_postgres() {
    if ! user_command_exists psql; then
        gum_error "PostgreSQL not installed. Run the main installer first."
        return 1
    fi

    gum_box "PostgreSQL Status" "Checking PostgreSQL configuration..."

    # Check service status
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        gum_success "PostgreSQL service is running"
    else
        gum_warn "PostgreSQL service is not running"
        if gum_confirm "Start PostgreSQL service?"; then
            sudo systemctl start postgresql
            sudo systemctl enable postgresql
            gum_success "PostgreSQL service started and enabled"
        fi
    fi

    # Test connection
    if run_as_user psql -c 'SELECT version()' &>/dev/null; then
        gum_success "Database connection working"
        echo ""
        gum_detail "PostgreSQL version:"
        run_as_user psql -c 'SELECT version()' 2>/dev/null | head -3
    else
        gum_warn "Cannot connect to database as $TARGET_USER"
        gum_detail "This is normal if you haven't created a role yet"
        gum_detail "The installer should have created a role for you"
    fi

    check_postgres_status
}

# ============================================================
# Interactive Menu
# ============================================================

show_menu() {
    check_all_status
    print_status_table

    echo ""

    if [[ "$HAS_GUM" == "true" ]]; then
        # Build menu items with status indicators
        local -a items=()
        local services=("claude" "codex" "gemini" "dcg" "vercel" "supabase" "wrangler" "postgres")
        local labels=("Claude Code" "Codex CLI" "Gemini CLI" "DCG" "Vercel" "Supabase" "Cloudflare Wrangler" "PostgreSQL")
        local descs=("AI coding assistant" "OpenAI assistant" "Google AI assistant" "Destructive command guard" "Deployment platform" "Database platform" "Edge platform" "Local database")

        for i in "${!services[@]}"; do
            local svc="${services[$i]}"
            local label="${labels[$i]}"
            local desc="${descs[$i]}"
            local status="${SERVICE_STATUS[$svc]:-unknown}"
            local icon
            icon=$(get_status_icon "$status")
            items+=("$icon $label - $desc [$status]")
        done

        items+=("─────────────────────────────────────────")
        items+=("⚡ Configure ALL unconfigured services")
        items+=("🔄 Refresh status")
        items+=("👋 Exit")

        # Use gum filter for fuzzy search
        gum style --foreground "$ACFS_PRIMARY" --bold "What would you like to configure?"
        echo ""
        local choice
        choice=$(printf '%s\n' "${items[@]}" | gum filter \
            --indicator.foreground "$ACFS_ACCENT" \
            --match.foreground "$ACFS_SUCCESS" \
            --placeholder "Type to filter services..." \
            --height 12)

        case "$choice" in
            *"Claude"*)    setup_claude ;;
            *"Codex"*)     setup_codex ;;
            *"Gemini"*)    setup_gemini ;;
            *"DCG"*)       configure_dcg ;;
            *"Vercel"*)    setup_vercel ;;
            *"Supabase"*)  setup_supabase ;;
            *"Wrangler"*)  setup_wrangler ;;
            *"PostgreSQL"*) setup_postgres ;;
            *"ALL"*)       setup_all_unconfigured ;;
            *"Refresh"*)   return 0 ;;
            *"Exit"*)      exit 0 ;;
            *)             return 0 ;;
        esac
    else
        local choice
        choice=$(gum_choose "What would you like to configure?" \
            "1. Claude Code (AI coding assistant)" \
            "2. Codex CLI (OpenAI coding assistant)" \
            "3. Gemini CLI (Google AI assistant)" \
            "4. DCG (destructive command guard)" \
            "5. Vercel (deployment platform)" \
            "6. Supabase (database platform)" \
            "7. Cloudflare Wrangler (edge platform)" \
            "8. PostgreSQL (check database)" \
            "9. Configure ALL unconfigured services" \
            "10. Refresh status" \
            "0. Exit")

        case "$choice" in
            *"Claude"*)    setup_claude ;;
            *"Codex"*)     setup_codex ;;
            *"Gemini"*)    setup_gemini ;;
            *"DCG"*)       configure_dcg ;;
            *"Vercel"*)    setup_vercel ;;
            *"Supabase"*)  setup_supabase ;;
            *"Cloudflare"*) setup_wrangler ;;
            *"PostgreSQL"*) setup_postgres ;;
            *"ALL"*)       setup_all_unconfigured ;;
            *"Refresh"*)   return 0 ;;
            *"Exit"*)      exit 0 ;;
            *)             return 0 ;;
        esac
    fi
}

setup_all_unconfigured() {
    gum_section "Configuring All Unconfigured Services"

    local services=("claude" "codex" "gemini" "dcg" "vercel" "supabase" "wrangler")
    local labels=("Claude Code" "Codex CLI" "Gemini CLI" "DCG (Destructive Command Guard)" "Vercel" "Supabase" "Cloudflare Wrangler")
    local setup_funcs=("setup_claude" "setup_codex" "setup_gemini" "configure_dcg" "setup_vercel" "setup_supabase" "setup_wrangler")

    # Count services needing setup
    local needs_setup=0
    for i in "${!services[@]}"; do
        local status="${SERVICE_STATUS[${services[$i]}]:-unknown}"
        if [[ "$status" != "configured" && "$status" != "not_installed" ]]; then
            ((needs_setup += 1))
        fi
    done

    if [[ $needs_setup -eq 0 ]]; then
        if [[ "$HAS_GUM" == "true" ]]; then
            gum style \
                --foreground "$ACFS_SUCCESS" \
                --bold \
                "✓ All services are already configured!"
        else
            gum_success "All services are already configured!"
        fi
        return 0
    fi

    local current=0
    for i in "${!services[@]}"; do
        local svc="${services[$i]}"
        local label="${labels[$i]}"
        local func="${setup_funcs[$i]}"
        local status="${SERVICE_STATUS[$svc]:-unknown}"

        if [[ "$status" != "configured" && "$status" != "not_installed" ]]; then
            ((current += 1))
            echo ""

            if [[ "$HAS_GUM" == "true" ]]; then
                # Show wizard-style progress
                local dots=""
                for ((j = 1; j <= needs_setup; j++)); do
                    if [[ $j -lt $current ]]; then
                        dots+="$(gum style --foreground "$ACFS_SUCCESS" "●") "
                    elif [[ $j -eq $current ]]; then
                        dots+="$(gum style --foreground "$ACFS_PRIMARY" --bold "●") "
                    else
                        dots+="$(gum style --foreground "$ACFS_MUTED" "○") "
                    fi
                done

                gum style \
                    --border rounded \
                    --border-foreground "$ACFS_PRIMARY" \
                    --padding "0 2" \
                    "$(gum style --foreground "$ACFS_ACCENT" "Service $current of $needs_setup") $dots
$(gum style --foreground "$ACFS_PINK" --bold "Setting up $label...")"
            else
                gum_step "$current" "$needs_setup" "Setting up $label..."
            fi

            $func || true
        fi
    done

    # Always check postgres
    echo ""
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style --foreground "$ACFS_MUTED" "Checking PostgreSQL status..."
    fi
    setup_postgres

    echo ""
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style \
            --border double \
            --border-foreground "$ACFS_SUCCESS" \
            --padding "1 2" \
            --align center \
            "$(gum style --foreground "$ACFS_SUCCESS" --bold '✓ Setup Complete!')
$(gum style --foreground "$ACFS_TEAL" "All available services have been configured")"
    else
        gum_success "Setup complete!"
    fi
}

# ============================================================
# Main
# ============================================================

main() {
    if [[ "$HAS_GUM" == "true" ]]; then
        # Styled header
        echo ""
        gum style \
            --border double \
            --border-foreground "$ACFS_ACCENT" \
            --padding "1 3" \
            --margin "0 0 1 0" \
            "$(gum style --foreground "$ACFS_PINK" --bold '⚙️  ACFS Services Setup')
$(gum style --foreground "$ACFS_MUTED" "Configure AI agents and cloud services")"

        gum style --foreground "$ACFS_TEAL" "  User: $TARGET_USER"
    else
        print_compact_banner
        echo ""
        gum_detail "Post-install services configuration for user: $TARGET_USER"
    fi
    echo ""

    if ! init_target_context; then
        exit 1
    fi

    # Check if bun is available
    if [[ ! -x "$BUN_BIN" ]]; then
        if [[ "$HAS_GUM" == "true" ]]; then
            gum style \
                --foreground "$ACFS_ERROR" \
                --bold \
                "✖ Bun not found at $BUN_BIN"
            gum style --foreground "$ACFS_ERROR" "  Run the main ACFS installer first!"
        else
            gum_error "Bun not found at $BUN_BIN"
            gum_error "Run the main ACFS installer first!"
        fi
        exit 1
    fi

    # Main loop
    while true; do
        show_menu
        echo ""
        if [[ "$HAS_GUM" == "true" ]]; then
            if ! gum confirm \
                --prompt.foreground "$ACFS_PRIMARY" \
                --selected.foreground "$ACFS_SUCCESS" \
                "Configure more services?"; then
                break
            fi
        else
            if ! gum_confirm "Configure more services?"; then
                break
            fi
        fi
    done

    # Final status
    check_all_status
    print_status_table

    if [[ "$HAS_GUM" == "true" ]]; then
        gum style \
            --border double \
            --border-foreground "$ACFS_SUCCESS" \
            --padding "1 3" \
            --margin "1 0" \
            --align center \
            "$(gum style --foreground "$ACFS_SUCCESS" --bold '🎉 Services Setup Complete!')

$(gum style --foreground "$ACFS_TEAL" 'Your ACFS environment is configured!')

$(gum style --foreground "$ACFS_MUTED" 'Next steps:')
$(gum style --foreground "$ACFS_PRIMARY" '  • Start coding with:') $(gum style --foreground "$ACFS_ACCENT" 'cc') $(gum style --foreground "$ACFS_MUTED" '(Claude Code)')
$(gum style --foreground "$ACFS_PRIMARY" '  • Create a project:') $(gum style --foreground "$ACFS_ACCENT" 'ntm new myproject')
$(gum style --foreground "$ACFS_PRIMARY" '  • Run the onboarding:') $(gum style --foreground "$ACFS_ACCENT" 'onboard')

$(gum style --foreground "$ACFS_PINK" --bold '  Happy coding! 🚀')"
    else
        gum_completion "Services Setup Complete" "Your ACFS environment is configured!

Next steps:
  • Start coding with: cc (Claude Code)
  • Create a project session: ntm new myproject
  • Run the onboarding: onboard

Happy coding!"
    fi
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    maybe_run_cli_action "$@"
    if [[ -n "${SERVICES_SETUP_ACTION:-}" ]]; then
        run_cli_action
        exit $?
    fi
    main "$@"
fi
