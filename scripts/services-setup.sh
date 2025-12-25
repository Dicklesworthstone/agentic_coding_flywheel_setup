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

# Run command as target user
run_as_user() {
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
    run_as_user "command -v '$cmd'" &>/dev/null
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
    if user_file_exists "$TARGET_HOME/.claude/config.json" || \
       user_file_exists "$TARGET_HOME/.config/claude/config.json" || \
       user_dir_has_content "$TARGET_HOME/.claude"; then
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
    local gemini_bin="$TARGET_HOME/.bun/bin/gemini"

    if [[ ! -x "$gemini_bin" ]]; then
        SERVICE_STATUS[gemini]="not_installed"
        return
    fi

    # Check for credentials (OAuth web login, like Claude Code and Codex CLI)
    if user_file_exists "$TARGET_HOME/.config/gemini/credentials.json" || \
       user_dir_has_content "$TARGET_HOME/.config/gemini" || \
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
    local supabase_bin="$TARGET_HOME/.bun/bin/supabase"

    if [[ ! -x "$supabase_bin" ]]; then
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

check_convex_status() {
    local convex_bin="$TARGET_HOME/.bun/bin/convex"

    if [[ ! -x "$convex_bin" ]]; then
        SERVICE_STATUS[convex]="not_installed"
        return
    fi

    # Best-effort: Convex stores auth under ~/.config/convex or ~/.convex (paths may vary).
    if user_file_exists "$TARGET_HOME/.config/convex/config.json" || \
       user_file_exists "$TARGET_HOME/.config/convex/credentials.json" || \
       user_file_exists "$TARGET_HOME/.convex/config.json" || \
       user_file_exists "$TARGET_HOME/.convex/credentials.json" || \
       [[ -n "${CONVEX_DEPLOYMENT:-}" || -n "${CONVEX_URL:-}" || -n "${CONVEX_API_KEY:-}" ]]; then
        SERVICE_STATUS[convex]="configured"
    else
        SERVICE_STATUS[convex]="installed"
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
    if run_as_user "psql -c 'SELECT 1'" &>/dev/null; then
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
    check_convex_status
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

    local services=("claude" "codex" "gemini" "vercel" "supabase" "convex" "wrangler" "postgres")
    local labels=("Claude Code" "Codex CLI" "Gemini CLI" "Vercel" "Supabase" "Convex" "Cloudflare" "PostgreSQL")
    local categories=("AI Agent" "AI Agent" "AI Agent" "Cloud" "Cloud" "Cloud" "Cloud" "Database")

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
    fi
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

    gum_box "Codex CLI Setup" "Codex CLI uses OAuth login with your ChatGPT account.
We'll launch the login flow in your terminal/browser."

    gum_detail "Launching Codex OAuth login..."
    run_as_user "'$codex_bin' login" || true

    check_codex_status
    if [[ "${SERVICE_STATUS[codex]}" == "configured" ]]; then
        gum_success "Codex CLI configured successfully!"
    fi
}

setup_claude_git_guard() {
    local settings_dir="$TARGET_HOME/.claude"
    local hooks_dir="$settings_dir/hooks"
    local guard_path_py="$hooks_dir/git_safety_guard.py"
    local guard_path_sh="$hooks_dir/git_safety_guard.sh"
    local settings_file="$settings_dir/settings.json"
    local source_py="$TARGET_HOME/.acfs/claude/hooks/git_safety_guard.py"

    if [[ "$SERVICES_SETUP_NONINTERACTIVE" != "true" ]] && { [[ -t 0 ]] || [[ -r /dev/tty ]]; }; then
        gum_box "Claude Git Safety Guard" "This installs a Claude Code PreToolUse hook that blocks destructive git/filesystem commands before they run.

It helps prevent accidental loss of uncommitted work from commands like:
  • git checkout -- <files>
  • git restore <files>
  • git reset --hard
  • git clean -f
  • git push --force / -f
  • rm -rf (except temp dirs)
  • git stash drop/clear

Recommended if you run Claude in dangerous mode (ACFS vibe aliases).

Press Enter to install the guard..."

        if [[ -r /dev/tty ]]; then
            read -r < /dev/tty || true
        else
            read -r || true
        fi
    else
        gum_detail "Installing Claude Git Safety Guard (noninteractive)"
    fi

    mkdir -p "$hooks_dir"

    # Prefer Python implementation if available
    local installed_guard="$guard_path_sh"
    
    if [[ -f "$source_py" ]] && command -v python3 &>/dev/null; then
        gum_detail "Installing Python implementation..."
        cp "$source_py" "$guard_path_py"
        chmod +x "$guard_path_py"
        installed_guard="$guard_path_py"
    else
        gum_detail "Installing Bash implementation (fallback)..."
        cat > "$guard_path_sh" << 'EOF'
#!/usr/bin/env bash
#
# git_safety_guard.sh
# Claude Code PreToolUse hook: blocks destructive git/filesystem commands.
#
# Behavior:
#   - Exit 0 with no output = allow
#   - Exit 0 with JSON permissionDecision=deny = block
#
set -euo pipefail

input="$(cat 2>/dev/null || true)"
[[ -n "$input" ]] || exit 0

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"

[[ "$tool_name" == "Bash" ]] || exit 0
[[ -n "$command" ]] || exit 0

SAFE_PATTERNS=(
  'git[[:space:]]+checkout[[:space:]]+-b[[:space:]]+'
  'git[[:space:]]+checkout[[:space:]]+--orphan[[:space:]]+'
  'git[[:space:]]+restore[[:space:]]+--staged[[:space:]]+'
  'git[[:space:]]+clean[[:space:]]+-n([[:space:]]|$)'
  'git[[:space:]]+clean[[:space:]]+--dry-run([[:space:]]|$)'
  # Allow rm -rf on temp directories (ephemeral by design)
  'rm[[:space:]]+-[a-z]*r[a-z]*f[a-z]*[[:space:]]+/tmp/'
  'rm[[:space:]]+-[a-z]*r[a-z]*f[a-z]*[[:space:]]+/var/tmp/'
  'rm[[:space:]]+-[a-z]*r[a-z]*f[a-z]*[[:space:]]+\\$TMPDIR/'
  'rm[[:space:]]+-[a-z]*r[a-z]*f[a-z]*[[:space:]]+\\$\\{TMPDIR'
  'rm[[:space:]]+-[a-z]*r[a-z]*f[a-z]*[[:space:]]+\"\\$TMPDIR/'
  'rm[[:space:]]+-[a-z]*r[a-z]*f[a-z]*[[:space:]]+\"\\$\\{TMPDIR'
)

for pat in "${SAFE_PATTERNS[@]}"; do
  if printf '%s' "$command" | grep -Eiq -- "$pat"; then
    exit 0
  fi
done

deny() {
  local reason="$1"
  jq -n --arg reason "$reason" --arg cmd "$command" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED by git_safety_guard.sh\n\nReason: " + $reason + "\n\nCommand: " + $cmd + "\n\nIf this operation is truly needed, ask the user for explicit permission and have them run the command manually.")
    }
  }'
  exit 0
}

# git checkout -- / git checkout <ref> -- <path>
if printf '%s' "$command" | grep -Eiq -- 'git[[:space:]]+checkout[[:space:]]+.*--[[:space:]]+'; then
  deny "git checkout ... -- can overwrite/discard uncommitted changes. Use 'git stash' first."
fi

# git restore (except --staged)
if printf '%s' "$command" | grep -Eiq -- 'git[[:space:]]+restore([[:space:]]|$)'; then
  deny "git restore can discard uncommitted changes. Use 'git diff' and 'git stash' first."
fi

# git reset hard/merge
if printf '%s' "$command" | grep -Eiq -- 'git[[:space:]]+reset[[:space:]]+--hard([[:space:]]|$)'; then
  deny "git reset --hard destroys uncommitted changes. Use 'git stash' first."
fi
if printf '%s' "$command" | grep -Eiq -- 'git[[:space:]]+reset[[:space:]]+--merge([[:space:]]|$)'; then
  deny "git reset --merge can lose uncommitted changes."
fi

# git clean -f / -fd / etc (except -n / --dry-run handled above)
if printf '%s' "$command" | grep -Eiq -- 'git[[:space:]]+clean[[:space:]]+-[a-z]*f'; then
  deny "git clean -f removes untracked files permanently. Review with 'git clean -n' first."
fi

# force push
if printf '%s' "$command" | grep -Eiq -- 'git[[:space:]]+push([[:space:]]|$)'; then
  if printf '%s' "$command" | grep -Eiq -- '--force-with-lease'; then
    exit 0
  fi
  if printf '%s' "$command" | grep -Eiq -- '(^|[[:space:]])(--force|-f)([[:space:]]|$)'; then
    deny "Force push can destroy remote history. Prefer --force-with-lease if absolutely necessary."
  fi
fi

# branch delete
if printf '%s' "$command" | grep -Eiq -- 'git[[:space:]]+branch[[:space:]]+-D([[:space:]]|$)'; then
  deny "git branch -D force-deletes without merge check. Use -d for safety."
fi

# git stash drop/clear
if printf '%s' "$command" | grep -Eiq -- 'git[[:space:]]+stash[[:space:]]+drop([[:space:]]|$)'; then
  deny "git stash drop permanently deletes stashed changes. List stashes first."
fi
if printf '%s' "$command" | grep -Eiq -- 'git[[:space:]]+stash[[:space:]]+clear([[:space:]]|$)'; then
  deny "git stash clear permanently deletes ALL stashed changes."
fi

# rm -rf (except temp dirs handled above)
if printf '%s' "$command" | grep -Eiq -- '(^|[[:space:]])rm[[:space:]]+-[a-z]*r[a-z]*f[a-z]*([[:space:]]|$)'; then
  if printf '%s' "$command" | grep -Eiq -- 'rm[[:space:]]+-[a-z]*r[a-z]*f[a-z]*[[:space:]]+[/~]([[:space:]]|$)'; then
    deny "rm -rf on root/home paths is extremely dangerous."
  fi
  deny "rm -rf is destructive. List files first, then delete individually with explicit permission."
fi

exit 0
EOF
        chmod +x "$guard_path_sh"
    fi

    # Create or merge settings.json
    if [[ ! -f "$settings_file" ]]; then
        cat > "$settings_file" << EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$installed_guard" }
        ]
      }
    ]
  }
}
EOF
    else
        local tmp
        if command -v jq &>/dev/null; then
            tmp="$(mktemp "${TMPDIR:-/tmp}/acfs_services.XXXXXX" 2>/dev/null)" || tmp="/tmp/acfs_services_temp.$$"
            if jq --arg cmd "$installed_guard" '
              .hooks = (.hooks // {}) |
              .hooks.PreToolUse = (.hooks.PreToolUse // []) |
              if (.hooks.PreToolUse | type) != "array" then
                .hooks.PreToolUse = []
              else .
              end |
              if ( [ .hooks.PreToolUse[]? | .hooks[]? | select(.type=="command") | .command ] | index($cmd) ) != null then
                .
              else
                ( [ .hooks.PreToolUse | to_entries[] | select(.value.matcher=="Bash") | .key ] | first ) as $bashKey |
                if $bashKey == null then
                  .hooks.PreToolUse += [{ "matcher":"Bash", "hooks":[ { "type":"command", "command":$cmd } ] }]
                else
                  .hooks.PreToolUse[$bashKey].hooks = ((.hooks.PreToolUse[$bashKey].hooks // []) | if type=="array" then . else [] end) |
                  .hooks.PreToolUse[$bashKey].hooks += [{ "type":"command", "command":$cmd }]
                end
              end
            ' "$settings_file" > "$tmp" 2>/dev/null; then
                mv "$tmp" "$settings_file"
            else
                gum_warn "Could not update $settings_file automatically (invalid JSON?)"
                gum_detail "Manually add this hook command:"
                gum_detail "  $installed_guard"
            fi
        else
            gum_warn "jq not found; cannot update $settings_file automatically"
            gum_detail "Manually add this hook command:"
            gum_detail "  $installed_guard"
        fi
    fi

    # Ensure ownership if run via sudo/root
    if [[ "$(whoami)" == "root" ]]; then
        chown -R "$TARGET_USER:$TARGET_USER" "$settings_dir" 2>/dev/null || true
    fi

    gum_success "Installed Claude Git Safety Guard"
    gum_warn "Restart Claude Code for hooks to take effect"
}

print_cli_help() {
    cat << 'EOF'
ACFS services-setup

Interactive:
  acfs services-setup

Noninteractive actions:
  services-setup.sh --install-claude-guard --yes
EOF
}

maybe_run_cli_action() {
    local arg
    local install_claude_guard="false"

    while [[ $# -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --install-claude-guard)
                install_claude_guard="true"
                ;;
            --yes|-y)
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

    if [[ "${SERVICES_SETUP_ACTION:-}" == "help" ]]; then
        print_cli_help
        return 0
    fi

    if [[ "$install_claude_guard" == "true" ]]; then
        init_target_context || return 1
        setup_claude_git_guard
        return 0
    fi

    return 1
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

Note: some Supabase projects expose the direct Postgres host over IPv6-only.
If your VPS/network is IPv4-only, use the Supabase pooler connection string instead.

Press Enter to launch 'supabase login'..."

    read -r

    run_as_user "'$supabase_bin' login" || true

    check_supabase_status
    if [[ "${SERVICE_STATUS[supabase]}" == "configured" ]]; then
        gum_success "Supabase configured successfully!"
    fi
}

setup_convex() {
    local convex_bin="$TARGET_HOME/.bun/bin/convex"

    if [[ ! -x "$convex_bin" ]]; then
        gum_error "Convex CLI not installed. Run the main installer first."
        return 1
    fi

    if [[ "${SERVICE_STATUS[convex]}" == "configured" ]]; then
        if ! gum_confirm "Convex appears to be configured. Reconfigure?"; then
            return 0
        fi
    fi

    gum_box "Convex Setup" "Convex CLI uses OAuth to authenticate.

Press Enter to launch 'convex login'..."

    read -r

    run_as_user "'$convex_bin' login" || true

    check_convex_status
    if [[ "${SERVICE_STATUS[convex]}" == "configured" ]]; then
        gum_success "Convex configured successfully!"
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

    if [[ "$HAS_GUM" == "true" ]]; then
        # Build menu items with status indicators
        local -a items=()
        local services=("claude" "codex" "gemini" "vercel" "supabase" "convex" "wrangler" "postgres")
        local labels=("Claude Code" "Codex CLI" "Gemini CLI" "Vercel" "Supabase" "Convex" "Cloudflare Wrangler" "PostgreSQL")
        local descs=("AI coding assistant" "OpenAI assistant" "Google AI assistant" "Deployment platform" "Database platform" "Realtime database" "Edge platform" "Local database")

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
        items+=("🛡 Install Claude destructive-command guard (recommended)")
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
            *"destructive-command guard"*) setup_claude_git_guard ;;
            *"Claude"*)    setup_claude ;;
            *"Codex"*)     setup_codex ;;
            *"Gemini"*)    setup_gemini ;;
            *"Vercel"*)    setup_vercel ;;
            *"Supabase"*)  setup_supabase ;;
            *"Convex"*)    setup_convex ;;
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
            "4. Vercel (deployment platform)" \
            "5. Supabase (database platform)" \
            "6. Convex (realtime database)" \
            "7. Cloudflare Wrangler (edge platform)" \
            "8. PostgreSQL (check database)" \
            "9. Install Claude destructive-command guard (recommended)" \
            "10. Configure ALL unconfigured services" \
            "11. Refresh status" \
            "0. Exit")

        case "$choice" in
            *"destructive-command guard"*) setup_claude_git_guard ;;
            *"Claude"*)    setup_claude ;;
            *"Codex"*)     setup_codex ;;
            *"Gemini"*)    setup_gemini ;;
            *"Vercel"*)    setup_vercel ;;
            *"Supabase"*)  setup_supabase ;;
            *"Convex"*)    setup_convex ;;
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

    local services=("claude" "codex" "gemini" "vercel" "supabase" "convex" "wrangler")
    local labels=("Claude Code" "Codex CLI" "Gemini CLI" "Vercel" "Supabase" "Convex" "Cloudflare Wrangler")
    local setup_funcs=("setup_claude" "setup_codex" "setup_gemini" "setup_vercel" "setup_supabase" "setup_convex" "setup_wrangler")

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
    if maybe_run_cli_action "$@"; then
        exit 0
    fi
    main "$@"
fi
