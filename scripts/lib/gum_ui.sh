#!/usr/bin/env bash
# ============================================================
# ACFS Installer - Glamorous UI Library (using Charmbracelet Gum)
# Creates beautiful, colorful terminal output
# Falls back to basic output if gum is not available
# ============================================================

# Check if gum is available
HAS_GUM=false
if command -v gum &>/dev/null; then
    HAS_GUM=true
fi

# ============================================================
# NO_COLOR Support (https://no-color.org/)
# Fallback colors respect NO_COLOR env var and TTY status.
# Related: bd-39ye
# ============================================================
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
    GUM_FB_BLUE='\033[0;34m'
    GUM_FB_GREEN='\033[0;32m'
    GUM_FB_YELLOW='\033[0;33m'
    GUM_FB_RED='\033[0;31m'
    GUM_FB_GRAY='\033[0;90m'
    GUM_FB_PURPLE='\033[0;35m'
    GUM_FB_NC='\033[0m'
else
    GUM_FB_BLUE=''
    GUM_FB_GREEN=''
    GUM_FB_YELLOW=''
    GUM_FB_RED=''
    GUM_FB_GRAY=''
    GUM_FB_PURPLE=''
    GUM_FB_NC=''
fi

# ACFS Color scheme (Catppuccin Mocha inspired)
ACFS_PRIMARY="#89b4fa"    # Blue
ACFS_SUCCESS="#a6e3a1"    # Green
ACFS_WARNING="#f9e2af"    # Yellow
ACFS_ERROR="#f38ba8"      # Red
ACFS_MUTED="#6c7086"      # Gray
ACFS_ACCENT="#cba6f7"     # Purple
ACFS_PINK="#f5c2e7"       # Pink
export ACFS_TEAL="#94e2d5"       # Teal (used by external consumers)

# ASCII Art Banner for ACFS
print_banner() {
    local banner='
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║     █████╗  ██████╗███████╗███████╗                          ║
    ║    ██╔══██╗██╔════╝██╔════╝██╔════╝                          ║
    ║    ███████║██║     █████╗  ███████╗                          ║
    ║    ██╔══██║██║     ██╔══╝  ╚════██║                          ║
    ║    ██║  ██║╚██████╗██║     ███████║                          ║
    ║    ╚═╝  ╚═╝ ╚═════╝╚═╝     ╚══════╝                          ║
    ║                                                               ║
    ║    Agentic Coding Flywheel Setup                             ║
    ║    github.com/Dicklesworthstone/agentic_coding_flywheel_setup║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
'

    if [[ "$HAS_GUM" == "true" ]]; then
        echo "$banner" | gum style \
            --foreground "$ACFS_PRIMARY" \
            --bold
    else
        echo -e "${GUM_FB_BLUE}$banner${GUM_FB_NC}"
    fi
}

# Compact banner for smaller screens
print_compact_banner() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum style \
            --border double \
            --border-foreground "$ACFS_PRIMARY" \
            --padding "1 2" \
            --align center \
            --width 50 \
            "$(gum style --foreground "$ACFS_ACCENT" --bold 'ACFS')
$(gum style --foreground "$ACFS_MUTED" 'Agentic Coding Flywheel Setup')"
    else
        echo ""
        echo "╔════════════════════════════════════════════╗"
        echo "║           ACFS v${ACFS_VERSION:-0.1.0}                       ║"
        echo "║   Agentic Coding Flywheel Setup            ║"
        echo "╚════════════════════════════════════════════╝"
        echo ""
    fi
}

# Styled step indicator
gum_step() {
    local step="$1"
    local total="$2"
    local message="$3"

    if [[ "$HAS_GUM" == "true" ]]; then
        gum style \
            --foreground "$ACFS_PRIMARY" \
            --bold \
            "[$step/$total]" | tr -d '\n'
        echo -n " "
        gum style "$message"
    else
        echo -e "${GUM_FB_BLUE}[$step/$total]${GUM_FB_NC} $message"
    fi
}

# Styled detail (indented, muted)
gum_detail() {
    local message="$1"

    if [[ "$HAS_GUM" == "true" ]]; then
        gum style \
            --foreground "$ACFS_MUTED" \
            --margin "0 0 0 4" \
            "→ $message"
    else
        echo -e "${GUM_FB_GRAY}    → $message${GUM_FB_NC}"
    fi
}

# Success message with checkmark
gum_success() {
    local message="$1"

    if [[ "$HAS_GUM" == "true" ]]; then
        gum style \
            --foreground "$ACFS_SUCCESS" \
            --bold \
            "✓ $message"
    else
        echo -e "${GUM_FB_GREEN}✓ $message${GUM_FB_NC}"
    fi
}

# Warning message
gum_warn() {
    local message="$1"

    if [[ "$HAS_GUM" == "true" ]]; then
        gum style \
            --foreground "$ACFS_WARNING" \
            "⚠ $message"
    else
        echo -e "${GUM_FB_YELLOW}⚠ $message${GUM_FB_NC}"
    fi
}

# Error message
gum_error() {
    local message="$1"

    if [[ "$HAS_GUM" == "true" ]]; then
        gum style \
            --foreground "$ACFS_ERROR" \
            --bold \
            "✖ $message"
    else
        echo -e "${GUM_FB_RED}✖ $message${GUM_FB_NC}"
    fi
}

# Fatal error (exits)
gum_fatal() {
    gum_error "$1"
    exit 1
}

# Spinner for long operations
# Usage: gum_spin "message" command arg1 arg2 ...
gum_spin() {
    local message="$1"
    shift

    if [[ "$HAS_GUM" == "true" ]]; then
        gum spin \
            --spinner.foreground "$ACFS_PRIMARY" \
            --title.foreground "$ACFS_MUTED" \
            --spinner dot \
            --title "$message" \
            -- "$@"
    else
        echo -e "${GUM_FB_GRAY}⏳ $message...${GUM_FB_NC}"
        "$@"
    fi
}

# Confirmation prompt
gum_confirm() {
    local message="$1"

    if [[ "$HAS_GUM" == "true" ]]; then
        if [[ -r /dev/tty && -w /dev/tty ]]; then
            gum confirm \
                --affirmative "Yes" \
                --negative "No" \
                --prompt.foreground "$ACFS_PRIMARY" \
                "$message" < /dev/tty > /dev/tty
        elif [[ -t 0 && -t 1 ]]; then
            gum confirm \
                --affirmative "Yes" \
                --negative "No" \
                --prompt.foreground "$ACFS_PRIMARY" \
                "$message"
        else
            echo "ERROR: --yes is required when no TTY is available" >&2
            return 1
        fi
    else
        local response=""
        if [[ -t 0 ]]; then
            read -r -p "$message [y/N] " response
        elif [[ -r /dev/tty ]]; then
            read -r -p "$message [y/N] " response < /dev/tty
        else
            echo "ERROR: --yes is required when no TTY is available" >&2
            return 1
        fi
        [[ "$response" =~ ^[Yy] ]]
    fi
}

# Choice selection
gum_choose() {
    local prompt="$1"
    shift
    local options=("$@")

    if [[ "$HAS_GUM" == "true" ]]; then
        if [[ -r /dev/tty ]]; then
            gum choose \
                --header.foreground "$ACFS_PRIMARY" \
                --cursor.foreground "$ACFS_ACCENT" \
                --selected.foreground "$ACFS_SUCCESS" \
                --header "$prompt" \
                "${options[@]}" < /dev/tty
        elif [[ -t 0 ]]; then
            gum choose \
                --header.foreground "$ACFS_PRIMARY" \
                --cursor.foreground "$ACFS_ACCENT" \
                --selected.foreground "$ACFS_SUCCESS" \
                --header "$prompt" \
                "${options[@]}"
        else
            echo "ERROR: --yes is required when no TTY is available" >&2
            return 1
        fi
    else
        if [[ -t 0 ]]; then
            echo "$prompt"
            select opt in "${options[@]}"; do
                if [[ -n "$opt" ]]; then
                    echo "$opt"
                    break
                fi
                echo "Invalid choice. Enter a number between 1 and ${#options[@]}." >&2
            done
        elif [[ -r /dev/tty ]]; then
            echo "$prompt" >&2
            (
                select opt in "${options[@]}"; do
                    if [[ -n "$opt" ]]; then
                        echo "$opt"
                        break
                    fi
                    echo "Invalid choice. Enter a number between 1 and ${#options[@]}." >&2
                done
            ) < /dev/tty
        else
            echo "ERROR: --yes is required when no TTY is available" >&2
            return 1
        fi
    fi
}

# Styled box/panel
gum_box() {
    local title="$1"
    local content="$2"

    if [[ "$HAS_GUM" == "true" ]]; then
        gum style \
            --border rounded \
            --border-foreground "$ACFS_PRIMARY" \
            --padding "1 2" \
            --margin "1 0" \
            "$(gum style --foreground "$ACFS_ACCENT" --bold "$title")

$content"
    else
        echo ""
        echo "┌─────────────────────────────────────────┐"
        echo "│ $title"
        echo "├─────────────────────────────────────────┤"
        # shellcheck disable=SC2001
        echo "$content" | sed 's/^/│ /'
        echo "└─────────────────────────────────────────┘"
        echo ""
    fi
}

# Progress section header
gum_section() {
    local title="$1"

    if [[ "$HAS_GUM" == "true" ]]; then
        echo ""
        gum style \
            --foreground "$ACFS_PINK" \
            --bold \
            --border-foreground "$ACFS_MUTED" \
            --border normal \
            --padding "0 2" \
            "$title"
    else
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${GUM_FB_PURPLE} $title${GUM_FB_NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

# Styled log levels (using gum log if available)
gum_log_info() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum log --level info "$1"
    else
        echo "[INFO] $1"
    fi
}

gum_log_warn() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum log --level warn "$1"
    else
        echo "[WARN] $1"
    fi
}

gum_log_error() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum log --level error "$1"
    else
        echo "[ERROR] $1"
    fi
}

gum_log_debug() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum log --level debug "$1"
    else
        echo "[DEBUG] $1"
    fi
}

# Print completion summary
gum_completion() {
    local title="$1"
    local content="$2"

    if [[ "$HAS_GUM" == "true" ]]; then
        gum style \
            --border double \
            --border-foreground "$ACFS_SUCCESS" \
            --padding "1 3" \
            --margin "1 0" \
            --align center \
            "$(gum style --foreground "$ACFS_SUCCESS" --bold "$title")

$content"
    else
        echo ""
        echo "╔═══════════════════════════════════════════╗"
        echo -e "║ ${GUM_FB_GREEN}$title${GUM_FB_NC}"
        echo "╠═══════════════════════════════════════════╣"
        # shellcheck disable=SC2001
        echo "$content" | sed 's/^/║ /'
        echo "╚═══════════════════════════════════════════╝"
        echo ""
    fi
}

# Install gum if not present
ensure_gum_installed() {
    if [[ "$HAS_GUM" == "true" ]]; then
        gum_detail "gum already installed"
        return 0
    fi

    gum_detail "Installing gum for enhanced UI..."

    local sudo_cmd=""
    if [[ $EUID -ne 0 ]]; then
        if command -v sudo &>/dev/null; then
            sudo_cmd="sudo"
        else
            gum_warn "sudo not found, trying installation without it..."
        fi
    fi

    # Try different installation methods
    if command -v brew &>/dev/null; then
        brew install gum
    elif command -v apt-get &>/dev/null; then
        # Add charm repository (DEB822 format for Ubuntu 24.04+)
        $sudo_cmd mkdir -p /etc/apt/keyrings
        curl --proto '=https' --proto-redir '=https' -fsSL https://repo.charm.sh/apt/gpg.key | $sudo_cmd gpg --batch --yes --dearmor -o /etc/apt/keyrings/charm.gpg
        printf 'Types: deb\nURIs: https://repo.charm.sh/apt/\nSuites: *\nComponents: *\nSigned-By: /etc/apt/keyrings/charm.gpg\n' | $sudo_cmd tee /etc/apt/sources.list.d/charm.sources > /dev/null
        $sudo_cmd apt-get -o DPkg::Lock::Timeout=120 update && \
            $sudo_cmd apt-get -o DPkg::Lock::Timeout=120 install -y gum
    elif command -v go &>/dev/null; then
        go install github.com/charmbracelet/gum@latest
    else
        gum_warn "Could not install gum automatically. Install manually: https://github.com/charmbracelet/gum"
        return 1
    fi

    if command -v gum &>/dev/null; then
        HAS_GUM=true
        gum_success "gum installed successfully"
    fi
}
