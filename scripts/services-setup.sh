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
TARGET_HOME="${TARGET_HOME:-$(eval echo ~"$TARGET_USER")}"
BUN_BIN="$TARGET_HOME/.bun/bin/bun"

# Service status tracking
declare -A SERVICE_STATUS

# ============================================================
# Helper Functions
# ============================================================

# Run command as target user
run_as_user() {
    local cmd="$1"
    if [[ "$(whoami)" == "$TARGET_USER" ]]; then
        bash -c "$cmd"
    else
        sudo -u "$TARGET_USER" -H bash -c "$cmd"
    fi
}

# ============================================================
# Status Check Functions
# ============================================================

check_claude_status() {
    local claude_bin="$TARGET_HOME/.bun/bin/claude"

    if [[ ! -x "$claude_bin" ]]; then
        SERVICE_STATUS[claude]="not_installed"
        return
    fi

    # Check for config indicating login
    if [[ -f "$TARGET_HOME/.claude/config.json" ]] || \
       [[ -f "$TARGET_HOME/.config/claude/config.json" ]] || \
       [[ -d "$TARGET_HOME/.claude" && -n "$(ls -A "$TARGET_HOME/.claude" 2>/dev/null)" ]]; then
        SERVICE_STATUS[claude]="configured"
    else
        SERVICE_STATUS[claude]="installed"
    fi
}

check_codex_status() {
    local codex_bin="$TARGET_HOME/.bun/bin/codex"

    if [[ ! -x "$codex_bin" ]]; then
        SERVICE_STATUS[codex]="not_installed"
        return
    fi

    # Check for API key or config
    if [[ -n "${OPENAI_API_KEY:-}" ]] || \
       [[ -f "$TARGET_HOME/.codex/config.json" ]] || \
       [[ -f "$TARGET_HOME/.config/codex/config.json" ]]; then
        SERVICE_STATUS[codex]="configured"
    else
        SERVICE_STATUS[codex]="installed"
    fi
}

check_gemini_status() {
    local gemini_bin="$TARGET_HOME/.bun/bin/gemini"

    if [[ ! -x "$gemini_bin" ]]; then
        SERVICE_STATUS[gemini]="not_installed"
        return
    fi

    # Check for credentials
    if [[ -f "$TARGET_HOME/.config/gemini/credentials.json" ]] || \
       [[ -n "${GOOGLE_API_KEY:-}" ]] || \
       [[ -n "${GEMINI_API_KEY:-}" ]]; then
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
    if [[ -f "$TARGET_HOME/.config/vercel/auth.json" ]] || \
       [[ -n "${VERCEL_TOKEN:-}" ]]; then
        SERVICE_STATUS[vercel]="configured"
    else
        SERVICE_STATUS[vercel]="installed"
    fi
}

check_supabase_status() {
    local supabase_bin="$TARGET_HOME/.bun/bin/supabase"

    if [[ ! -x "$supabase_bin" ]]; then
        SERVICE_STATUS[supabase]="not_installed"
        return
    fi

    # Check for access token
    if [[ -f "$TARGET_HOME/.config/supabase/access-token" ]] || \
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
    if [[ -f "$TARGET_HOME/.config/wrangler/config/default.toml" ]] || \
       [[ -f "$TARGET_HOME/.wrangler/config/default.toml" ]] || \
       [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
        SERVICE_STATUS[wrangler]="configured"
    else
        SERVICE_STATUS[wrangler]="installed"
    fi
}

check_postgres_status() {
    if ! command -v psql &>/dev/null; then
        SERVICE_STATUS[postgres]="not_installed"
        return
    fi

    # Check if service is running and user can connect
    if run_as_user "psql -c 'SELECT 1' &>/dev/null"; then
        SERVICE_STATUS[postgres]="configured"
    elif systemctl is-active --quiet postgresql 2>/dev/null; then
        SERVICE_STATUS[postgres]="running"
    else
        SERVICE_STATUS[postgres]="installed"
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

    for i in "${!services[@]}"; do
        local svc="${services[$i]}"
        local label="${labels[$i]}"
        local status="${SERVICE_STATUS[$svc]:-unknown}"
        local icon
        icon=$(get_status_icon "$status")

        if [[ "$HAS_GUM" == "true" ]]; then
            local color
            color=$(get_status_color "$status")
            gum style --foreground "$color" "  $icon $label: $status"
        else
            case "$status" in
                configured) echo -e "\033[32m  $icon $label: $status\033[0m" ;;
                running|installed) echo -e "\033[33m  $icon $label: $status\033[0m" ;;
                *) echo -e "\033[31m  $icon $label: $status\033[0m" ;;
            esac
        fi
    done
    echo ""
}

# ============================================================
# Setup Functions
# ============================================================

setup_claude() {
    local claude_bin="$TARGET_HOME/.bun/bin/claude"

    if [[ ! -x "$claude_bin" ]]; then
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
    run_as_user "'$claude_bin'" || true

    # Re-check status
    check_claude_status
    if [[ "${SERVICE_STATUS[claude]}" == "configured" ]]; then
        gum_success "Claude Code configured successfully!"
    else
        gum_warn "Claude Code may not be fully configured. Try running 'claude' again."
    fi
}

setup_codex() {
    local codex_bin="$TARGET_HOME/.bun/bin/codex"

    if [[ ! -x "$codex_bin" ]]; then
        gum_error "Codex CLI not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[codex]}" == "configured" ]]; then
        if ! gum_confirm "Codex CLI appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    gum_box "Codex CLI Setup" "Codex CLI can be configured two ways:

1. OPENAI_API_KEY environment variable (for API access)
2. OAuth login (for ChatGPT Plus/Pro subscribers)

Which method would you like to use?"

    local method
    method=$(gum_choose "Select authentication method:" "OAuth Login (recommended)" "API Key")

    if [[ "$method" == *"API Key"* ]]; then
        echo ""
        echo "Enter your OpenAI API key (starts with sk-):"
        local api_key
        if [[ "$HAS_GUM" == "true" ]]; then
            api_key=$(gum input --password --placeholder "sk-...")
        else
            read -r -s api_key
            echo ""  # Newline after hidden input
        fi

        if [[ -n "$api_key" ]]; then
            # Add to shell config
            local zshrc="$TARGET_HOME/.zshrc"
            if ! grep -q "OPENAI_API_KEY" "$zshrc" 2>/dev/null; then
                {
                    echo ""
                    echo "# OpenAI API Key (added by ACFS services-setup)"
                    echo "export OPENAI_API_KEY='$api_key'"
                } >> "$zshrc"
                gum_success "API key added to ~/.zshrc"
                gum_detail "Run 'source ~/.zshrc' or start a new shell to use it"
            else
                gum_warn "OPENAI_API_KEY already exists in ~/.zshrc"
                gum_detail "Edit ~/.zshrc manually to update it"
            fi
        fi
    else
        gum_detail "Launching Codex OAuth login..."
        run_as_user "'$codex_bin'" || true
    fi

    check_codex_status
    if [[ "${SERVICE_STATUS[codex]}" == "configured" ]]; then
        gum_success "Codex CLI configured successfully!"
    fi
}

setup_gemini() {
    local gemini_bin="$TARGET_HOME/.bun/bin/gemini"

    if [[ ! -x "$gemini_bin" ]]; then
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

    run_as_user "'$gemini_bin'" || true

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

    run_as_user "'$vercel_bin' login" || true

    check_vercel_status
    if [[ "${SERVICE_STATUS[vercel]}" == "configured" ]]; then
        gum_success "Vercel configured successfully!"
    fi
}

setup_supabase() {
    local supabase_bin="$TARGET_HOME/.bun/bin/supabase"

    if [[ ! -x "$supabase_bin" ]]; then
        gum_error "Supabase CLI not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[supabase]}" == "configured" ]]; then
        if ! gum_confirm "Supabase appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    gum_box "Supabase Setup" "Supabase CLI uses OAuth to authenticate.

Press Enter to launch 'supabase login'..."

    read -r

    run_as_user "'$supabase_bin' login" || true

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

    run_as_user "'$wrangler_bin' login" || true

    check_wrangler_status
    if [[ "${SERVICE_STATUS[wrangler]}" == "configured" ]]; then
        gum_success "Cloudflare/Wrangler configured successfully!"
    fi
}

setup_postgres() {
    if ! command -v psql &>/dev/null; then
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
    if run_as_user "psql -c 'SELECT version()'" &>/dev/null; then
        gum_success "Database connection working"
        echo ""
        gum_detail "PostgreSQL version:"
        run_as_user "psql -c 'SELECT version()'" 2>/dev/null | head -3
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
    local choice
    choice=$(gum_choose "What would you like to configure?" \
        "1. Claude Code (AI coding assistant)" \
        "2. Codex CLI (OpenAI coding assistant)" \
        "3. Gemini CLI (Google AI assistant)" \
        "4. Vercel (deployment platform)" \
        "5. Supabase (database platform)" \
        "6. Cloudflare Wrangler (edge platform)" \
        "7. PostgreSQL (check database)" \
        "8. Configure ALL unconfigured services" \
        "9. Refresh status" \
        "0. Exit")

    case "$choice" in
        *"Claude"*)    setup_claude ;;
        *"Codex"*)     setup_codex ;;
        *"Gemini"*)    setup_gemini ;;
        *"Vercel"*)    setup_vercel ;;
        *"Supabase"*)  setup_supabase ;;
        *"Cloudflare"*) setup_wrangler ;;
        *"PostgreSQL"*) setup_postgres ;;
        *"ALL"*)       setup_all_unconfigured ;;
        *"Refresh"*)   return 0 ;;  # Will loop back and refresh
        *"Exit"*)      exit 0 ;;
        *)             return 0 ;;
    esac
}

setup_all_unconfigured() {
    gum_section "Configuring All Unconfigured Services"

    local services=("claude" "codex" "gemini" "vercel" "supabase" "wrangler")
    local setup_funcs=("setup_claude" "setup_codex" "setup_gemini" "setup_vercel" "setup_supabase" "setup_wrangler")

    for i in "${!services[@]}"; do
        local svc="${services[$i]}"
        local func="${setup_funcs[$i]}"
        local status="${SERVICE_STATUS[$svc]:-unknown}"

        if [[ "$status" != "configured" && "$status" != "not_installed" ]]; then
            echo ""
            gum_step "$((i+1))" "${#services[@]}" "Setting up $svc..."
            $func || true
        fi
    done

    # Always check postgres
    setup_postgres

    echo ""
    gum_success "Setup complete!"
}

# ============================================================
# Main
# ============================================================

main() {
    print_compact_banner

    echo ""
    gum_detail "Post-install services configuration for user: $TARGET_USER"
    echo ""

    # Check if bun is available
    if [[ ! -x "$BUN_BIN" ]]; then
        gum_error "Bun not found at $BUN_BIN"
        gum_error "Run the main ACFS installer first!"
        exit 1
    fi

    # Main loop
    while true; do
        show_menu
        echo ""
        if ! gum_confirm "Configure more services?"; then
            break
        fi
    done

    # Final status
    check_all_status
    print_status_table

    gum_completion "Services Setup Complete" "Your ACFS environment is configured!

Next steps:
  • Start coding with: cc (Claude Code)
  • Create a project session: ntm new myproject
  • Run the onboarding: onboard

Happy coding!"
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
