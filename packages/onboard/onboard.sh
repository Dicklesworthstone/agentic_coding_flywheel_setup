#!/usr/bin/env bash
#
# onboard - ACFS Interactive Onboarding TUI
#
# Teaches users the ACFS workflow through 9 interactive lessons.
# Uses gum for TUI elements with fallback to basic bash menus.
#
# Usage:
#   onboard           # Launch interactive menu
#   onboard N         # Jump to lesson N (1-9)
#   onboard reset     # Reset progress
#   onboard status    # Show completion status
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

LESSONS_DIR="${ACFS_LESSONS_DIR:-$HOME/.acfs/onboard/lessons}"
PROGRESS_FILE="${ACFS_PROGRESS_FILE:-$HOME/.acfs/onboard_progress.json}"
VERSION="0.1.0"

# Source gum_ui library if available for consistent theming
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for candidate in \
    "$SCRIPT_DIR/../scripts/lib/gum_ui.sh" \
    "$SCRIPT_DIR/../../scripts/lib/gum_ui.sh" \
    "$HOME/.acfs/scripts/lib/gum_ui.sh"; do
    if [[ -f "$candidate" ]]; then
        # shellcheck disable=SC1090,SC1091
        source "$candidate"
        break
    fi
done

# Lesson titles (indexed 0-8)
declare -a LESSON_TITLES=(
    "Welcome & Overview"
    "Linux Navigation"
    "SSH & Persistence"
    "tmux Basics"
    "Agent Commands (cc, cod, gmi)"
    "NTM Command Center"
    "NTM Prompt Palette"
    "The Flywheel Loop"
    "Keeping Updated"
)

# Lesson files (indexed 0-8)
declare -a LESSON_FILES=(
    "00_welcome.md"
    "01_linux_basics.md"
    "02_ssh_basics.md"
    "03_tmux_basics.md"
    "04_agents_login.md"
    "05_ntm_core.md"
    "06_ntm_command_palette.md"
    "07_flywheel_loop.md"
    "08_keeping_updated.md"
)

# Service definitions for authentication flow
declare -a AUTH_SERVICES=(
    "tailscale"
    "claude"
    "codex"
    "gemini"
    "github"
    "vercel"
    "supabase"
    "cloudflare"
)

declare -A AUTH_SERVICE_NAMES=(
    ["tailscale"]="Tailscale"
    ["claude"]="Claude Code"
    ["codex"]="Codex CLI"
    ["gemini"]="Gemini CLI"
    ["github"]="GitHub"
    ["vercel"]="Vercel"
    ["supabase"]="Supabase"
    ["cloudflare"]="Cloudflare"
)

declare -A AUTH_SERVICE_DESCRIPTIONS=(
    ["tailscale"]="Secure VPS access via private network"
    ["claude"]="Anthropic's AI coding agent"
    ["codex"]="OpenAI's AI coding agent"
    ["gemini"]="Google's AI coding agent"
    ["github"]="Code hosting and version control"
    ["vercel"]="Frontend deployment platform"
    ["supabase"]="Database and auth backend"
    ["cloudflare"]="CDN and edge computing"
)

declare -A AUTH_SERVICE_COMMANDS=(
    ["tailscale"]="sudo tailscale up"
    ["claude"]="claude"
    ["codex"]="codex login"
    ["gemini"]="gemini"
    ["github"]="gh auth login"
    ["vercel"]="vercel login"
    ["supabase"]="supabase login"
    ["cloudflare"]="wrangler login"
)

# Colors (works in most terminals) - fallback if gum_ui not loaded
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Catppuccin Mocha color scheme (if not already set by gum_ui)
ACFS_PRIMARY="${ACFS_PRIMARY:-#89b4fa}"
ACFS_SECONDARY="${ACFS_SECONDARY:-#74c7ec}"
ACFS_SUCCESS="${ACFS_SUCCESS:-#a6e3a1}"
ACFS_WARNING="${ACFS_WARNING:-#f9e2af}"
ACFS_ERROR="${ACFS_ERROR:-#f38ba8}"
ACFS_MUTED="${ACFS_MUTED:-#6c7086}"
ACFS_ACCENT="${ACFS_ACCENT:-#cba6f7}"
ACFS_PINK="${ACFS_PINK:-#f5c2e7}"
ACFS_TEAL="${ACFS_TEAL:-#94e2d5}"

# ─────────────────────────────────────────────────────────────────────────────
# Utility Functions
# ─────────────────────────────────────────────────────────────────────────────

# Check if gum is available
has_gum() {
    command -v gum &>/dev/null
}

# Check if glow is available (for markdown rendering)
has_glow() {
    command -v glow &>/dev/null
}

# Initialize progress file if it doesn't exist
init_progress() {
    local dir
    dir=$(dirname "$PROGRESS_FILE")
    mkdir -p "$dir"

    if [[ ! -f "$PROGRESS_FILE" ]]; then
        cat > "$PROGRESS_FILE" <<EOF
{
  "completed": [],
  "current": 0,
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "last_accessed": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    fi
}

# Get list of completed lessons
get_completed() {
    if [[ -f "$PROGRESS_FILE" ]]; then
        # Parse JSON with jq if available, otherwise use sed (POSIX-compatible)
        if command -v jq &>/dev/null; then
            jq -r '.completed | @csv' "$PROGRESS_FILE" 2>/dev/null | tr -d '"' || echo ""
        else
            # POSIX-compatible: extract array contents with sed
            sed -n 's/.*"completed":[[:space:]]*\[\([^]]*\)\].*/\1/p' "$PROGRESS_FILE" 2>/dev/null || echo ""
        fi
    else
        echo ""
    fi
}

# Check if a lesson is completed
is_completed() {
    local lesson=$1
    local completed
    completed=$(get_completed | tr -d ' ')
    [[ "$completed" =~ (^|,)$lesson(,|$) ]]
}

# Get current lesson
get_current() {
    if [[ -f "$PROGRESS_FILE" ]] && command -v jq &>/dev/null; then
        jq -r '.current // 0' "$PROGRESS_FILE" 2>/dev/null || echo "0"
    else
        # POSIX-compatible: extract current value with sed
        sed -n 's/.*"current":[[:space:]]*\([0-9]*\).*/\1/p' "$PROGRESS_FILE" 2>/dev/null | head -1 || echo "0"
    fi
}

# Mark a lesson as completed
mark_completed() {
    local lesson=$1

    if command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp "${TMPDIR:-/tmp}/acfs_onboard.XXXXXX" 2>/dev/null) || tmp="/tmp/acfs_onboard_temp.$$"
        jq --argjson lesson "$lesson" '
            .completed = (.completed + [$lesson] | unique | sort) |
            .current = (if $lesson < 9 then $lesson + 1 else $lesson end) |
            .last_accessed = now | todate
        ' "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"
    else
        # Fallback: warn user that progress is not saved
        echo -e "${YELLOW}Warning: 'jq' not found. Progress will NOT be saved.${NC}"
        echo "Please install jq to enable progress tracking."
    fi
}

# Update current lesson without marking complete
set_current() {
    local lesson=$1

    if command -v jq &>/dev/null; then
        local tmp
        tmp=$(mktemp "${TMPDIR:-/tmp}/acfs_onboard.XXXXXX" 2>/dev/null) || tmp="/tmp/acfs_onboard_temp.$$"
        jq --argjson lesson "$lesson" '
            .current = $lesson |
            .last_accessed = now | todate
        ' "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"
    fi
}

# Reset progress
reset_progress() {
    rm -f "$PROGRESS_FILE"
    init_progress
    echo -e "${GREEN}Progress reset!${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Authentication Check Functions
# ─────────────────────────────────────────────────────────────────────────────

# Check if a service is authenticated
# Returns: 0 = authenticated, 1 = not authenticated, 2 = not installed
check_auth_status() {
    local service=$1

    case "$service" in
        tailscale)
            if ! command -v tailscale &>/dev/null; then
                return 2
            fi
            local status="unknown"
            if command -v jq &>/dev/null; then
                status=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "unknown"' 2>/dev/null || echo "unknown")
            else
                if tailscale status --json 2>/dev/null | grep -q '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
                    status="Running"
                fi
            fi
            [[ "$status" == "Running" ]] && return 0 || return 1
            ;;
        claude)
            if ! command -v claude &>/dev/null; then
                return 2
            fi
            # Check for claude config
            if [[ -s "$HOME/.claude/config.json" || -s "$HOME/.config/claude/config.json" ]]; then
                return 0
            fi
            [[ -d "$HOME/.claude" ]] && return 0 || return 1
            ;;
        codex)
            if ! command -v codex &>/dev/null; then
                return 2
            fi
            # Codex stores auth in ~/.codex
            local codex_home="${CODEX_HOME:-$HOME/.codex}"
            [[ -s "$codex_home/auth.json" ]] && return 0 || return 1
            ;;
        gemini)
            if ! command -v gemini &>/dev/null; then
                return 2
            fi
            # Gemini CLI uses OAuth web login (like Claude Code and Codex CLI)
            # Users authenticate via `gemini` command which opens browser login
            if [[ -s "$HOME/.config/gemini/credentials.json" || -d "$HOME/.config/gemini" ]]; then
                return 0
            fi
            if [[ -f "$HOME/.gemini/config" ]]; then
                return 0
            fi
            return 1
            ;;
        github)
            if ! command -v gh &>/dev/null; then
                return 2
            fi
            gh auth status &>/dev/null && return 0 || return 1
            ;;
        vercel)
            if ! command -v vercel &>/dev/null; then
                return 2
            fi
            if [[ -s "$HOME/.config/vercel/auth.json" || -s "$HOME/.vercel/auth.json" ]]; then
                return 0
            fi
            return 1
            ;;
        supabase)
            if ! command -v supabase &>/dev/null; then
                return 2
            fi
            if [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
                return 0
            fi
            if [[ -s "$HOME/.supabase/access-token" || -s "$HOME/.config/supabase/access-token" ]]; then
                return 0
            fi
            return 1
            ;;
        cloudflare)
            if ! command -v wrangler &>/dev/null; then
                return 2
            fi
            if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
                return 0
            fi
            if [[ -s "$HOME/.config/wrangler/config/default.toml" || -s "$HOME/.wrangler/config/default.toml" ]]; then
                return 0
            fi
            return 1
            ;;
        *)
            return 2
            ;;
    esac
}

# Fetch auth status without tripping `set -e`
# Echoes: 0 (authed), 1 (needs auth), 2 (not installed)
get_auth_status_code() {
    local service=$1
    check_auth_status "$service"
    echo "$?"
}

# Get auth status display for a service
get_auth_status_display() {
    local service=$1
    local status
    status=$(get_auth_status_code "$service")

    case $status in
        0) echo -e "${GREEN}✓${NC}" ;;
        1) echo -e "${YELLOW}○${NC}" ;;
        2) echo -e "${DIM}—${NC}" ;;
    esac
}

# Show authentication flow
show_auth_flow() {
    while true; do
        clear 2>/dev/null || true

        if has_gum; then
            gum style \
                --border rounded \
                --border-foreground "$ACFS_ACCENT" \
                --padding "1 4" \
                --margin "1" \
                "$(gum style --foreground "$ACFS_PINK" --bold '🔐 Service Authentication')" \
                "$(gum style --foreground "$ACFS_MUTED" --italic "Connect your services for the full experience")"
        else
            echo ""
            echo -e "${BOLD}${MAGENTA}╭─────────────────────────────────────────╮${NC}"
            echo -e "${BOLD}${MAGENTA}│     🔐 Service Authentication          │${NC}"
            echo -e "${BOLD}${MAGENTA}│  Connect your services                  │${NC}"
            echo -e "${BOLD}${MAGENTA}╰─────────────────────────────────────────╯${NC}"
            echo ""
        fi

        echo ""
        echo -e "${BOLD}Service Status:${NC}"
        echo ""

        local authed=0
        local total=0

        for service in "${AUTH_SERVICES[@]}"; do
            local name="${AUTH_SERVICE_NAMES[$service]}"
            local desc="${AUTH_SERVICE_DESCRIPTIONS[$service]}"
            local status_icon
            status_icon=$(get_auth_status_display "$service")

            local status
            status=$(get_auth_status_code "$service")

            if [[ $status -ne 2 ]]; then
                ((total++))
                [[ $status -eq 0 ]] && ((authed++))
            fi

            printf "  %s  %-15s %s\n" "$status_icon" "$name" "${DIM}$desc${NC}"
        done

        echo ""
        echo -e "${DIM}Legend: ${GREEN}✓${NC} authenticated  ${YELLOW}○${NC} needs auth  ${DIM}—${NC} not installed${NC}"
        echo ""

        if [[ $total -gt 0 ]]; then
            echo -e "${CYAN}Progress: $authed/$total services authenticated${NC}"
        fi

        echo ""
        echo -e "${DIM}─────────────────────────────────────────${NC}"

        # Show menu options
        if has_gum; then
            local -a items=()
            for service in "${AUTH_SERVICES[@]}"; do
                local status
                status=$(get_auth_status_code "$service")
                if [[ $status -eq 1 ]]; then
                    items+=("🔑 Authenticate ${AUTH_SERVICE_NAMES[$service]}")
                fi
            done
            items+=("─────────────────────────────────")
            items+=("📋 [m] Back to menu")
            items+=("🔄 [r] Refresh status")

            local choice
            choice=$(printf '%s\n' "${items[@]}" | gum choose \
                --cursor.foreground "$ACFS_ACCENT" \
                --selected.foreground "$ACFS_SUCCESS")

            case "$choice" in
                *"[m]"*) return 0 ;;
                *"[r]"*) continue ;;
                *"Authenticate"*)
                    # Extract service name from choice
                    for service in "${AUTH_SERVICES[@]}"; do
                        if [[ "$choice" == *"${AUTH_SERVICE_NAMES[$service]}"* ]]; then
                            show_auth_service "$service"
                            # Loop continues to refresh
                            break
                        fi
                    done
                    ;;
            esac
        else
            echo "Options:"
            echo "  [1-8] Authenticate a service"
            echo "  [m]   Back to menu"
            echo "  [r]   Refresh status"
            echo ""

            local idx=1
            for service in "${AUTH_SERVICES[@]}"; do
                local status
                status=$(get_auth_status_code "$service")
                if [[ $status -eq 1 ]]; then
                    echo "  [$idx] ${AUTH_SERVICE_NAMES[$service]}"
                fi
                ((idx++))
            done

            read -rp "$(echo -e "${CYAN}Choose:${NC} ")" choice

            case "$choice" in
                m|M) return 0 ;;
                r|R) continue ;;
                [1-8])
                    local idx=$((choice - 1))
                    if [[ $idx -lt ${#AUTH_SERVICES[@]} ]]; then
                        show_auth_service "${AUTH_SERVICES[$idx]}"
                        # Loop continues to refresh
                    fi
                    ;;
            esac
        fi
    done
}

# Show auth instructions for a specific service
show_auth_service() {
    local service=$1
    local name="${AUTH_SERVICE_NAMES[$service]}"
    local cmd="${AUTH_SERVICE_COMMANDS[$service]}"

    clear 2>/dev/null || true

    if has_gum; then
        gum style \
            --border rounded \
            --border-foreground "$ACFS_PRIMARY" \
            --padding "1 2" \
            "$(gum style --foreground "$ACFS_ACCENT" "🔑 Authenticate $name")"

        echo ""
        echo "To authenticate $name, run this command:"
        echo ""
        gum style --foreground "$ACFS_TEAL" --bold "  $cmd"
        echo ""
        echo "This will open a browser or show an auth URL."
        echo "Follow the prompts to complete authentication."
        echo ""

        gum confirm --affirmative "I've authenticated" --negative "Skip for now" || true
    else
        echo ""
        echo -e "${BOLD}${CYAN}Authenticate $name${NC}"
        echo ""
        echo "Run this command:"
        echo ""
        echo -e "  ${GREEN}$cmd${NC}"
        echo ""
        echo "Follow the prompts to complete authentication."
        echo ""
        read -rp "Press Enter when done (or 's' to skip)... " _
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Display Functions
# ─────────────────────────────────────────────────────────────────────────────

# Print header
print_header() {
    clear 2>/dev/null || true
    if has_gum; then
        gum style \
            --border rounded \
            --border-foreground "$ACFS_ACCENT" \
            --padding "1 4" \
            --margin "1" \
            "$(gum style --foreground "$ACFS_PINK" --bold '📚 ACFS Onboarding')" \
            "$(gum style --foreground "$ACFS_MUTED" --italic "Learn the agentic coding workflow")"
    else
        echo ""
        echo -e "${BOLD}${MAGENTA}╭─────────────────────────────────────────╮${NC}"
        echo -e "${BOLD}${MAGENTA}│       📚 ACFS Onboarding Tutorial       │${NC}"
        echo -e "${BOLD}${MAGENTA}│  Learn the agentic coding workflow      │${NC}"
        echo -e "${BOLD}${MAGENTA}╰─────────────────────────────────────────╯${NC}"
        echo ""
    fi
}

# Format lesson title with status
format_lesson() {
    local idx=$1
    local title="${LESSON_TITLES[$idx]}"
    local status=""
    local current
    current=$(get_current)

    if is_completed "$idx"; then
        status="${GREEN}✓${NC}"
    elif [[ "$idx" == "$current" ]]; then
        status="${YELLOW}●${NC}"
    else
        status="${DIM}○${NC}"
    fi

    printf "%s [%d] %s" "$status" "$((idx + 1))" "$title"
}

# Show lesson menu with gum
show_menu_gum() {
    local current
    current=$(get_current)

    # Build menu items with styled status indicators
    local -a items=()
    for i in {0..8}; do
        local status=""
        if is_completed "$i"; then
            status="✓"
        elif [[ "$i" == "$current" ]]; then
            status="●"
        else
            status="○"
        fi
        items+=("${status} [$((i + 1))] ${LESSON_TITLES[$i]}")
    done
    items+=("─────────────────────────────────")
    items+=("🔐 [a] Authenticate Services")
    items+=("↺ [r] Restart from beginning")
    items+=("📊 [s] Show status")
    items+=("👋 [q] Quit")

    # Show menu with gum using Catppuccin colors
    local choice
    choice=$(printf '%s\n' "${items[@]}" | gum choose \
        --cursor.foreground "$ACFS_ACCENT" \
        --selected.foreground "$ACFS_SUCCESS" \
        --header.foreground "$ACFS_PRIMARY" \
        --header "Select a lesson:")

    # Parse choice
    if [[ "$choice" =~ \[([0-9])\] ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$choice" =~ \[a\] ]]; then
        echo "a"
    elif [[ "$choice" =~ \[r\] ]]; then
        echo "r"
    elif [[ "$choice" =~ \[s\] ]]; then
        echo "s"
    else
        echo "q"
    fi
}

# Show lesson menu with basic bash
show_menu_basic() {
    echo -e "${BOLD}Choose a lesson:${NC}"
    echo ""

    for i in {0..8}; do
        echo -e "  $(format_lesson "$i")"
    done

    echo ""
    echo -e "  ${DIM}[a] Authenticate Services${NC}"
    echo -e "  ${DIM}[r] Restart from beginning${NC}"
    echo -e "  ${DIM}[s] Show status${NC}"
    echo -e "  ${DIM}[q] Quit${NC}"
    echo ""

    read -rp "$(echo -e "${CYAN}Choose [1-9, a, r, s, q]:${NC} ")" choice

    case "$choice" in
        [1-9]) echo "$choice" ;;
        a|A) echo "a" ;;
        r|R) echo "r" ;;
        s|S) echo "s" ;;
        q|Q|"") echo "q" ;;
        *) echo "invalid" ;;
    esac
}

# Render markdown content
render_markdown() {
    local file=$1

    if has_glow; then
        glow -s dark "$file"
    elif has_gum; then
        # Use gum format for markdown rendering
        gum format -t markdown < "$file"
    elif command -v bat &>/dev/null; then
        bat --style=plain --language=markdown "$file"
    else
        # Basic markdown rendering with sed
        sed \
            -e "s/^# \(.*\)$/$(printf '\033[1;35m')\\1$(printf '\033[0m')/" \
            -e "s/^## \(.*\)$/$(printf '\033[1;36m')\\1$(printf '\033[0m')/" \
            -e "s/^### \(.*\)$/$(printf '\033[1;33m')\\1$(printf '\033[0m')/" \
            -e "s/\*\*\([^*]*\)\*\*/$(printf '\033[1m')\\1$(printf '\033[0m')/g" \
            -e "s/\`\([^\`]*\)\`/$(printf '\033[36m')\\1$(printf '\033[0m')/g" \
            -e "s/^---$/$(printf '\033[90m')────────────────────────────────────────$(printf '\033[0m')/" \
            -e "s/^- /  • /" \
            "$file"
    fi
}

# Show a lesson
show_lesson() {
    local idx=$1
    local file="${LESSONS_DIR}/${LESSON_FILES[$idx]}"

    if [[ ! -f "$file" ]]; then
        if has_gum; then
            gum style --foreground "$ACFS_ERROR" "Error: Lesson file not found: $file"
        else
            echo -e "${RED}Error: Lesson file not found: $file${NC}"
        fi
        echo "Please ensure ACFS is properly installed."
        return 1
    fi

    clear 2>/dev/null || true

    # Header with step indicator
    if has_gum; then
        # Build progress dots
        local dots=""
        for ((i = 0; i < 9; i++)); do
            if is_completed "$i"; then
                dots+="$(gum style --foreground "$ACFS_SUCCESS" "●") "
            elif [[ $i -eq $idx ]]; then
                dots+="$(gum style --foreground "$ACFS_PRIMARY" --bold "●") "
            else
                dots+="$(gum style --foreground "$ACFS_MUTED" "○") "
            fi
        done

        gum style \
            --border rounded \
            --border-foreground "$ACFS_PRIMARY" \
            --padding "1 2" \
            --margin "0 0 1 0" \
            "$(gum style --foreground "$ACFS_ACCENT" "Lesson $((idx + 1)) of 9")
$dots
$(gum style --foreground "$ACFS_PINK" --bold "${LESSON_TITLES[$idx]}")"
    else
        echo -e "${BOLD}${MAGENTA}Lesson $((idx + 1)): ${LESSON_TITLES[$idx]}${NC}"
        echo -e "${DIM}─────────────────────────────────────────${NC}"
        echo ""
    fi

    # Content
    render_markdown "$file"

    echo ""

    # Navigation with gum
    if has_gum; then
        gum style --foreground "$ACFS_MUTED" "─────────────────────────────────────────"

        # Build navigation options
        local -a nav_items=()
        nav_items+=("📋 [m] Menu")
        [[ $idx -gt 0 ]] && nav_items+=("⬅️  [p] Previous")
        [[ $idx -lt 8 ]] && nav_items+=("➡️  [n] Next")
        nav_items+=("✅ [c] Mark complete")
        nav_items+=("👋 [q] Quit")

        local action
        action=$(printf '%s\n' "${nav_items[@]}" | gum choose \
            --cursor.foreground "$ACFS_ACCENT" \
            --selected.foreground "$ACFS_SUCCESS")

        case "$action" in
            *"[m]"*) return 0 ;;
            *"[p]"*)
                if [[ $idx -gt 0 ]]; then
                    set_current $((idx - 1))
                    show_lesson $((idx - 1))
                    return $?
                fi
                ;;
            *"[n]"*)
                if [[ $idx -lt 8 ]]; then
                    set_current $((idx + 1))
                    show_lesson $((idx + 1))
                    return $?
                fi
                ;;
            *"[c]"*)
                mark_completed "$idx"
                gum style --foreground "$ACFS_SUCCESS" --bold "✓ Lesson $((idx + 1)) marked complete!"
                sleep 1
                if [[ $idx -lt 8 ]]; then
                    show_lesson $((idx + 1))
                    return $?
                else
                    gum style \
                        --border double \
                        --border-foreground "$ACFS_SUCCESS" \
                        --padding "1 3" \
                        --align center \
                        "$(gum style --foreground "$ACFS_SUCCESS" --bold '🎉 Congratulations!')
$(gum style --foreground "$ACFS_TEAL" "You've completed all lessons!")
$(gum style --foreground "$ACFS_MUTED" "You're ready to fly!")"
                    sleep 2
                    return 0
                fi
                ;;
            *"[q]"*) exit 0 ;;
        esac
    else
        echo -e "${DIM}─────────────────────────────────────────${NC}"

        # Navigation
        local nav_options="[m] Menu"
        if [[ $idx -gt 0 ]]; then
            nav_options+="  [p] Previous"
        fi
        if [[ $idx -lt 8 ]]; then
            nav_options+="  [n] Next"
        fi
        nav_options+="  [c] Mark complete  [q] Quit"

        echo -e "${DIM}$nav_options${NC}"
        echo ""

        while true; do
            read -rp "$(echo -e "${CYAN}Action:${NC} ")" action
            case "$action" in
                m|M) return 0 ;;
                p|P)
                    if [[ $idx -gt 0 ]]; then
                        set_current $((idx - 1))
                        show_lesson $((idx - 1))
                        return $?
                    fi
                    ;;
                n|N)
                    if [[ $idx -lt 8 ]]; then
                        set_current $((idx + 1))
                        show_lesson $((idx + 1))
                        return $?
                    fi
                    ;;
                c|C)
                    mark_completed "$idx"
                    echo -e "${GREEN}Lesson $((idx + 1)) marked complete!${NC}"
                    sleep 1
                    if [[ $idx -lt 8 ]]; then
                        show_lesson $((idx + 1))
                        return $?
                    else
                        echo -e "${GREEN}${BOLD}Congratulations! You've completed all lessons!${NC}"
                        sleep 2
                        return 0
                    fi
                    ;;
                q|Q) exit 0 ;;
                "") ;;
                *) echo -e "${YELLOW}Invalid option. Use m/p/n/c/q${NC}" ;;
            esac
        done
    fi
}

# Show completion status
show_status() {
    print_header

    local completed_count=0
    for i in {0..8}; do
        if is_completed "$i"; then
            ((completed_count += 1))
        fi
    done

    if has_gum; then
        # Styled progress display with gum
        local percent=$((completed_count * 100 / 9))
        local filled=$((percent / 2))
        local empty=$((50 - filled))

        local bar=""
        for ((i = 0; i < filled; i++)); do bar+="█"; done
        for ((i = 0; i < empty; i++)); do bar+="░"; done

        gum style \
            --border rounded \
            --border-foreground "$ACFS_ACCENT" \
            --padding "1 2" \
            --margin "0 0 1 0" \
            "$(gum style --foreground "$ACFS_PINK" --bold "📊 Progress: $completed_count/9 lessons")

$(gum style --foreground "$ACFS_PRIMARY" "$bar") $(gum style --foreground "$ACFS_SUCCESS" --bold "$percent%")"

        # Lesson list with styled status
        echo ""
        for i in {0..8}; do
            local status_icon status_color
            if is_completed "$i"; then
                status_icon="✓"
                status_color="$ACFS_SUCCESS"
            elif [[ "$i" == "$(get_current)" ]]; then
                status_icon="●"
                status_color="$ACFS_PRIMARY"
            else
                status_icon="○"
                status_color="$ACFS_MUTED"
            fi
            echo "  $(gum style --foreground "$status_color" "$status_icon") $(gum style --foreground "$ACFS_TEAL" "[$((i + 1))]") ${LESSON_TITLES[$i]}"
        done

        echo ""

        if [[ $completed_count -eq 9 ]]; then
            gum style \
                --foreground "$ACFS_SUCCESS" \
                --bold \
                "🎉 All lessons complete! You're ready to fly!"
        else
            local current
            current=$(get_current)
            echo "$(gum style --foreground "$ACFS_MUTED" "Next up:") $(gum style --foreground "$ACFS_PRIMARY" "Lesson $((current + 1)) - ${LESSON_TITLES[$current]}")"
        fi

        echo ""
        gum confirm --affirmative "Continue" --negative "" "Ready to continue?" || true
    else
        echo -e "${BOLD}Progress: $completed_count/9 lessons completed${NC}"
        echo ""

        # Progress bar
        local filled=$((completed_count * 5))
        local empty=$((45 - filled))
        local i
        printf '%s' "${GREEN}"
        for ((i = 0; i < filled; i++)); do printf '█'; done
        printf '%s' "${DIM}"
        for ((i = 0; i < empty; i++)); do printf '░'; done
        printf '%s' "${NC}"
        echo " $((completed_count * 100 / 9))%"
        echo ""

        for i in {0..8}; do
            echo -e "  $(format_lesson "$i")"
        done

        echo ""

        if [[ $completed_count -eq 9 ]]; then
            echo -e "${GREEN}${BOLD}All lessons complete! You're ready to fly!${NC}"
        else
            local current
            current=$(get_current)
            echo -e "${CYAN}Next up: Lesson $((current + 1)) - ${LESSON_TITLES[$current]}${NC}"
        fi

        echo ""
        read -rp "Press Enter to continue..."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main_menu() {
    while true; do
        print_header

        local choice
        if has_gum; then
            choice=$(show_menu_gum)
        else
            choice=$(show_menu_basic)
        fi

        case "$choice" in
            [1-9])
                local idx=$((choice - 1))
                set_current "$idx"
                show_lesson "$idx"
                ;;
            a)
                show_auth_flow
                ;;
            r)
                if has_gum; then
                    if gum confirm "Reset all progress?"; then
                        reset_progress
                    fi
                else
                    read -rp "Reset all progress? [y/N] " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        reset_progress
                    fi
                fi
                ;;
            s)
                show_status
                ;;
            q)
                echo -e "${GREEN}Happy coding!${NC}"
                exit 0
                ;;
            invalid)
                echo -e "${YELLOW}Invalid choice. Please try again.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Handle command line arguments
case "${1:-}" in
    reset)
        init_progress
        reset_progress
        ;;
    status)
        init_progress
        show_status
        ;;
    --version|-v)
        echo "onboard v$VERSION"
        ;;
    --help|-h)
        cat <<EOF
ACFS Onboarding Tutorial

Usage:
  onboard           Launch interactive menu
  onboard N         Jump to lesson N (1-9)
  onboard reset     Reset all progress
  onboard status    Show completion status
  onboard --help    Show this help

Lessons:
  1 - Welcome & Overview
  2 - Linux Navigation
  3 - SSH & Persistence
  4 - tmux Basics
  5 - Agent Commands (cc, cod, gmi)
  6 - NTM Command Center
  7 - NTM Prompt Palette
  8 - The Flywheel Loop
  9 - Keeping Updated

Environment:
  ACFS_LESSONS_DIR   Path to lesson files (default: ~/.acfs/onboard/lessons)
  ACFS_PROGRESS_FILE Path to progress file (default: ~/.acfs/onboard_progress.json)
EOF
        ;;
    "")
        init_progress
        main_menu
        ;;
    [1-9])
        init_progress
        idx=$(( $1 - 1 ))
        show_lesson "$idx"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'onboard --help' for usage."
        exit 1
        ;;
esac
