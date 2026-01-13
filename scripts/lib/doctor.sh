#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Doctor - System Health Check
# Validates that ACFS installation is complete and working
#
# Uses gum for enhanced terminal UI when available
# ============================================================

ACFS_VERSION="${ACFS_VERSION:-0.1.0}"

# Ensure the doctor is self-contained and doesn't depend on shell rc files
# for PATH setup (e.g., when run from a fresh SSH session or non-zsh shell).
ensure_path() {
    local dir
    local to_add=()

    for dir in \
        "$HOME/.local/bin" \
        "$HOME/.bun/bin" \
        "$HOME/.cargo/bin" \
        "$HOME/go/bin" \
        "$HOME/.atuin/bin"; do
        [[ -d "$dir" ]] || continue
        case ":$PATH:" in
            *":$dir:"*) ;;
            *) to_add+=("$dir") ;;
        esac
    done

    if [[ ${#to_add[@]} -gt 0 ]]; then
        local prefix
        prefix=$(IFS=:; echo "${to_add[*]}")
        export PATH="${prefix}:$PATH"
    fi
}
ensure_path

# Check for gum and source gum_ui if available
HAS_GUM=false
if command -v gum &>/dev/null; then
    HAS_GUM=true
fi

# Source gum_ui library if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer the installed VERSION file when available.
if [[ -f "$HOME/.acfs/VERSION" ]]; then
    ACFS_VERSION="$(cat "$HOME/.acfs/VERSION" 2>/dev/null || echo "$ACFS_VERSION")"
elif [[ -f "$SCRIPT_DIR/../VERSION" ]]; then
    ACFS_VERSION="$(cat "$SCRIPT_DIR/../VERSION" 2>/dev/null || echo "$ACFS_VERSION")"
elif [[ -f "$SCRIPT_DIR/../../VERSION" ]]; then
    ACFS_VERSION="$(cat "$SCRIPT_DIR/../../VERSION" 2>/dev/null || echo "$ACFS_VERSION")"
fi

# Prefer the installed state file for mode (vibe/safe) when available.
if [[ -z "${ACFS_MODE:-}" ]] && [[ -f "$HOME/.acfs/state.json" ]]; then
    if command -v jq &>/dev/null; then
        ACFS_MODE="$(jq -r '.mode // empty' "$HOME/.acfs/state.json" 2>/dev/null || true)"
    fi
    if [[ -z "${ACFS_MODE:-}" ]]; then
        ACFS_MODE="$(sed -n 's/.*"mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$HOME/.acfs/state.json" | head -n 1)"
    fi
    [[ -n "${ACFS_MODE:-}" ]] && export ACFS_MODE
fi

# Prefer the installed state file for target user (for installs where the target user is not ubuntu).
ACFS_TARGET_USER="${ACFS_TARGET_USER:-}"
if [[ -z "${ACFS_TARGET_USER:-}" ]] && [[ -f "$HOME/.acfs/state.json" ]]; then
    if command -v jq &>/dev/null; then
        ACFS_TARGET_USER="$(jq -r '.target_user // empty' "$HOME/.acfs/state.json" 2>/dev/null || true)"
    fi
    if [[ -z "${ACFS_TARGET_USER:-}" ]]; then
        ACFS_TARGET_USER="$(sed -n 's/.*"target_user"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$HOME/.acfs/state.json" | head -n 1)"
    fi
fi
ACFS_TARGET_USER="${ACFS_TARGET_USER:-ubuntu}"
if [[ ! "$ACFS_TARGET_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    ACFS_TARGET_USER="ubuntu"
fi
export ACFS_TARGET_USER

if [[ -f "$SCRIPT_DIR/gum_ui.sh" ]]; then
    source "$SCRIPT_DIR/gum_ui.sh"
elif [[ -f "$HOME/.acfs/scripts/lib/gum_ui.sh" ]]; then
    source "$HOME/.acfs/scripts/lib/gum_ui.sh"
fi

# Colors (fallback if gum_ui not loaded)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Color scheme (Catppuccin Mocha)
ACFS_PRIMARY="${ACFS_PRIMARY:-#89b4fa}"
ACFS_SUCCESS="${ACFS_SUCCESS:-#a6e3a1}"
ACFS_WARNING="${ACFS_WARNING:-#f9e2af}"
ACFS_ERROR="${ACFS_ERROR:-#f38ba8}"
ACFS_MUTED="${ACFS_MUTED:-#6c7086}"
ACFS_ACCENT="${ACFS_ACCENT:-#cba6f7}"
ACFS_TEAL="${ACFS_TEAL:-#94e2d5}"

# Counters
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Skipped tools data (bead qup)
declare -a SKIPPED_TOOLS_DATA=()

# Output modes
JSON_MODE=false
JSON_CHECKS=()

# Deep mode - run functional tests beyond binary existence
# Related: agentic_coding_flywheel_setup-01s
DEEP_MODE=false

# Caching for deep checks - skip slow operations that recently passed
# Related: agentic_coding_flywheel_setup-lz1
NO_CACHE=false
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/acfs/doctor"
CACHE_TTL=300  # 5 minutes

# Per-check timeout (prevents indefinite hangs)
# Related: agentic_coding_flywheel_setup-lz1
DEEP_CHECK_TIMEOUT=15  # seconds

# Print `acfs` CLI help (only used when this script is installed as the `acfs` entrypoint).
print_acfs_help() {
    echo "ACFS - Agentic Coding Flywheel Setup"
    echo ""
    echo "Usage: acfs <command> [options]"
    echo ""
    echo "Commands:"
    echo "  doctor [options]    Check system health and tool status"
    echo "    --json            Output results as JSON"
    echo "    --deep            Run functional tests (auth, connections)"
    echo "  info [options]      Quick system overview (terminal/json/html)"
    echo "  cheatsheet          Command reference (aliases, shortcuts)"
    echo "  continue [options]  View installation/upgrade progress"
    echo "  dashboard <command> Generate/view a static HTML dashboard"
    echo "  newproj <name>      Create new project with git, bd, claude settings"
    echo "  update [options]    Update ACFS tools to latest versions"
    echo "  services-setup      Configure AI agents and cloud services"
    echo "  session <command>   Export/import/share agent sessions"
    echo "  version             Show ACFS version"
    echo "  help                Show this help message"
}

resolve_session_lib() {
    if [[ -f "$HOME/.acfs/scripts/lib/session.sh" ]]; then
        echo "$HOME/.acfs/scripts/lib/session.sh"
        return 0
    fi
    if [[ -f "$SCRIPT_DIR/session.sh" ]]; then
        echo "$SCRIPT_DIR/session.sh"
        return 0
    fi
    return 1
}

print_session_help() {
    echo "Usage: acfs session <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list [--json] [--days N] [--agent NAME] [--limit N]"
    echo "  export <session_path> [--format json|markdown] [--no-sanitize] [--output FILE]"
    echo "  recent [--workspace PATH] [--format json|markdown]"
    echo "  import <file.json> [--dry-run]"
    echo "  show <id> [--format json|markdown|summary]"
    echo "  list-imported"
    echo ""
    echo "Examples:"
    echo "  acfs session list --days 7"
    echo "  acfs session export ~/.codex/sessions/.../abc.jsonl --output session.json"
    echo "  acfs session recent --workspace /data/projects/foo"
    echo "  acfs session import session.json --dry-run"
}

acfs_session_recent() {
    local workspace
    workspace="$(pwd)"
    local format="json"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace)
                workspace="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    export_recent_session "$workspace" "$format"
}

acfs_session_main() {
    local session_lib
    session_lib="$(resolve_session_lib)" || {
        echo "Error: session.sh not found. Re-run the ACFS installer." >&2
        return 1
    }

    # shellcheck source=/dev/null
    source "$session_lib"

    if ! check_session_deps; then
        return 1
    fi

    local subcmd="${1:-}"
    case "$subcmd" in
        list)
            shift
            list_sessions "$@"
            ;;
        export)
            shift
            export_session "$@"
            ;;
        recent)
            shift
            acfs_session_recent "$@"
            ;;
        import)
            shift
            import_session "$@"
            ;;
        show)
            shift
            show_session "$@"
            ;;
        list-imported)
            shift
            list_imported_sessions "$@"
            ;;
        help|-h|"")
            print_session_help
            ;;
        *)
            echo "Unknown session command: $subcmd" >&2
            print_session_help
            return 1
            ;;
    esac
}

# Print a section header only in human output mode.
section() {
    if [[ "$JSON_MODE" != "true" ]]; then
        if [[ "$HAS_GUM" == "true" ]]; then
            echo ""
            gum style \
                --foreground "$ACFS_PRIMARY" \
                --bold \
                --border-foreground "$ACFS_MUTED" \
                --border normal \
                --padding "0 2" \
                "󰋊 $1"
        else
            echo ""
            echo -e "${CYAN}━━━ $1 ━━━${NC}"
        fi
    fi
}

# Print a blank line only in human output mode.
blank_line() {
    if [[ "$JSON_MODE" != "true" ]]; then
        echo ""
    fi
}

# Escape a string for safe inclusion in JSON (without surrounding quotes).
json_escape() {
    local s="${1:-}"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

# ============================================================
# Timeout and Caching Helpers (bead lz1)
# ============================================================

# Run a command with timeout, returning special status for timeout
# Usage: run_with_timeout <timeout_seconds> <description> <command> [args...]
# Returns: 0=success, 124=timeout, other=command exit code
# Output: Command stdout (or "TIMEOUT" on timeout)
run_with_timeout() {
    local timeout_secs="$1"
    local description="$2"
    shift 2

    local result
    local status
    result=$(timeout "$timeout_secs" "$@" 2>&1)
    status=$?

    if ((status == 124)); then
        echo "TIMEOUT"
        if [[ "$JSON_MODE" != "true" ]]; then
            # Log timeout warning (non-fatal)
            if [[ "$HAS_GUM" == "true" ]]; then
                gum style --foreground "$ACFS_MUTED" "    ⏱ $description timed out after ${timeout_secs}s" >&2
            else
                echo -e "    ${YELLOW}⏱ $description timed out after ${timeout_secs}s${NC}" >&2
            fi
        fi
        return 124
    fi

    echo "$result"
    return $status
}

# Store a successful check result in cache
# Usage: cache_result <key> <value>
cache_result() {
    local key="$1"
    local value="$2"

    # Skip if caching disabled
    [[ "$NO_CACHE" == "true" ]] && return 0

    mkdir -p "$CACHE_DIR"
    echo "$value" > "$CACHE_DIR/$key"
}

# Get a cached result if it exists and is fresh
# Usage: get_cached_result <key>
# Returns: 0 if cache hit, 1 if miss/expired
# Output: Cached value on hit
get_cached_result() {
    local key="$1"
    local cache_file="$CACHE_DIR/$key"

    # Skip if caching disabled
    [[ "$NO_CACHE" == "true" ]] && return 1

    # Check if cache file exists
    [[ -f "$cache_file" ]] || return 1

    # Check cache age (compatible with both Linux and macOS)
    local file_mtime
    local current_time
    current_time=$(date +%s)

    # Try GNU stat first, fall back to BSD stat
    if file_mtime=$(stat -c %Y "$cache_file" 2>/dev/null); then
        : # GNU stat worked
    elif file_mtime=$(stat -f %m "$cache_file" 2>/dev/null); then
        : # BSD stat worked
    else
        return 1  # Can't determine age, cache miss
    fi

    local age=$((current_time - file_mtime))
    if ((age >= CACHE_TTL)); then
        return 1  # Cache expired
    fi

    cat "$cache_file"
    return 0
}

# Run a check with cache support
# Usage: check_with_cache <cache_key> <description> <command> [args...]
# Returns: Command exit status (0 = cache hit counts as success)
check_with_cache() {
    local cache_key="$1"
    local description="$2"
    shift 2

    # Try cache first
    local cached
    if cached=$(get_cached_result "$cache_key"); then
        echo "$cached (cached)"
        return 0
    fi

    # Run actual check with timeout
    local result
    local status
    result=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "$description" "$@")
    status=$?

    # Cache successful results
    if ((status == 0)); then
        cache_result "$cache_key" "$result"
    fi

    echo "$result"
    return $status
}

# Check with [?] (unknown) indicator for timeouts
# This variant of check() handles timeout status specially
# Usage: check_with_timeout_status <id> <label> <status> [details] [fix]
# status can be: pass, warn, fail, timeout
check_with_timeout_status() {
    local id="$1"
    local label="$2"
    local status="$3"
    local details="${4:-}"
    local fix="${5:-}"

    # Convert timeout to special handling
    if [[ "$status" == "timeout" ]]; then
        # Timeouts count as warnings for stats (unknown state, not failed)
        ((WARN_COUNT += 1))

        if [[ "$JSON_MODE" == "true" ]]; then
            local fix_json="null"
            if [[ -n "$fix" ]]; then
                fix_json="\"$(json_escape "$fix")\""
            fi
            JSON_CHECKS+=("{\"id\":\"$(json_escape "$id")\",\"label\":\"$(json_escape "$label")\",\"status\":\"timeout\",\"details\":\"$(json_escape "$details")\",\"fix\":$fix_json}")
            return 0
        fi

        # Display with [?] indicator
        if [[ "$HAS_GUM" == "true" ]]; then
            echo "  $(gum style --foreground "$ACFS_WARNING" --bold "? WAIT") $(gum style "$label")"
            if [[ -n "$fix" ]]; then
                echo "        $(gum style --foreground "$ACFS_MUTED" "Fix:") $(gum style --foreground "$ACFS_ACCENT" --italic "$fix")"
            fi
        else
            echo -e "  ${YELLOW}? WAIT${NC} $label"
            if [[ -n "$fix" ]]; then
                echo -e "        Fix: $fix"
            fi
        fi
        return 0
    fi

    # Delegate to standard check for other statuses
    check "$id" "$label" "$status" "$details" "$fix"
}

# Check result helper
check() {
    local id="$1"
    local label="$2"
    local status="$3"
    local details="${4:-}"
    local fix="${5:-}"

    case "$status" in
        pass) ((PASS_COUNT += 1)) ;;
        warn) ((WARN_COUNT += 1)) ;;
        fail) ((FAIL_COUNT += 1)) ;;
    esac

    if [[ "$JSON_MODE" == "true" ]]; then
        local fix_json="null"
        if [[ -n "$fix" ]]; then
            fix_json="\"$(json_escape "$fix")\""
        fi

        JSON_CHECKS+=("{\"id\":\"$(json_escape "$id")\",\"label\":\"$(json_escape "$label")\",\"status\":\"$(json_escape "$status")\",\"details\":\"$(json_escape "$details")\",\"fix\":$fix_json}")
        return 0
    fi

    if [[ "$HAS_GUM" == "true" ]]; then
        case "$status" in
            pass)
                echo "  $(gum style --foreground "$ACFS_SUCCESS" --bold "✓ PASS") $(gum style --foreground "$ACFS_TEAL" "$label")"
                ;;
            warn)
                echo "  $(gum style --foreground "$ACFS_WARNING" --bold "⚠ WARN") $(gum style "$label")"
                if [[ -n "$fix" ]]; then
                    echo "        $(gum style --foreground "$ACFS_MUTED" "Fix:") $(gum style --foreground "$ACFS_ACCENT" --italic "$fix")"
                fi
                ;;
            fail)
                echo "  $(gum style --foreground "$ACFS_ERROR" --bold "✖ FAIL") $(gum style "$label")"
                if [[ -n "$fix" ]]; then
                    echo "        $(gum style --foreground "$ACFS_MUTED" "Fix:") $(gum style --foreground "$ACFS_ACCENT" --italic "$fix")"
                fi
                ;;
        esac
    else
        case "$status" in
            pass)
                echo -e "  ${GREEN}✓ PASS${NC} $label"
                ;;
            warn)
                echo -e "  ${YELLOW}⚠ WARN${NC} $label"
                if [[ -n "$fix" ]]; then
                    echo -e "        Fix: $fix"
                fi
                ;;
            fail)
                echo -e "  ${RED}✖ FAIL${NC} $label"
                if [[ -n "$fix" ]]; then
                    echo -e "        Fix: $fix"
                fi
                ;;
        esac
    fi
}

# Try to retrieve a reasonably informative version line for a command without
# assuming it supports `--version`.
get_version_line() {
    local cmd="$1"

    local version=""
    version=$("$cmd" --version 2>/dev/null | head -n1) || true
    if [[ -z "$version" ]]; then
        version=$("$cmd" -V 2>/dev/null | head -n1) || true
    fi
    if [[ -z "$version" ]]; then
        version=$("$cmd" version 2>/dev/null | head -n1) || true
    fi

    if [[ -z "$version" ]]; then
        version="available"
    fi

    printf '%s' "$version"
}

# Check if command exists
check_command() {
    local id="$1"
    local label="$2"
    local cmd="$3"
    local fix="${4:-}"

    if command -v "$cmd" &>/dev/null; then
        local version
        version=$(get_version_line "$cmd")
        check "$id" "$label ($version)" "pass" "installed"
    else
        check "$id" "$label" "fail" "not found" "$fix"
    fi
}

# Check a command, but treat missing as WARN (optional dependency).
check_optional_command() {
    local id="$1"
    local label="$2"
    local cmd="$3"
    local fix="${4:-}"

    if command -v "$cmd" &>/dev/null; then
        local version
        version=$(get_version_line "$cmd")
        check "$id" "$label ($version)" "pass" "installed"
    else
        check "$id" "$label" "warn" "not found" "$fix"
    fi
}

# Check identity
check_identity() {
    section "Identity"

    # Check user
    local user
    user=$(whoami)
    if [[ "$user" == "$ACFS_TARGET_USER" ]]; then
        check "identity.user_is_ubuntu" "Logged in as $ACFS_TARGET_USER" "pass" "whoami=$user"
    else
        check "identity.user_is_ubuntu" "Logged in as $ACFS_TARGET_USER (currently: $user)" "warn" "whoami=$user" "ssh ${ACFS_TARGET_USER}@YOUR_SERVER"
    fi

    # Check sudo configuration (passwordless only required in vibe mode)
    if [[ "${ACFS_MODE:-vibe}" == "vibe" ]]; then
        if sudo -n true 2>/dev/null; then
            check "identity.passwordless_sudo" "Passwordless sudo (vibe mode)" "pass"
        else
            check "identity.passwordless_sudo" "Passwordless sudo (vibe mode)" "fail" "requires password" "Re-run ACFS installer with --mode vibe"
        fi
    else
        if command -v sudo &>/dev/null && id -nG 2>/dev/null | grep -qw sudo; then
            check "identity.sudo" "Sudo available (safe mode)" "pass"
        else
            check "identity.sudo" "Sudo available (safe mode)" "fail" "sudo unavailable" "Ensure ${ACFS_TARGET_USER} is in the sudo group and sudo is installed"
        fi
    fi

    blank_line
}

# Check workspace
check_workspace() {
    section "Workspace"

    if [[ -d "/data/projects" ]] && [[ -w "/data/projects" ]]; then
        check "workspace.data_projects" "/data/projects exists and writable" "pass"
    else
        check "workspace.data_projects" "/data/projects" "fail" "missing or not writable" "sudo mkdir -p /data/projects && sudo chown ${ACFS_TARGET_USER}:${ACFS_TARGET_USER} /data/projects"
    fi

    blank_line
}

# Check shell
check_shell() {
    section "Shell"

    check_command "shell.zsh" "zsh" "zsh" "sudo apt install zsh"

    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        check "shell.ohmyzsh" "Oh My Zsh" "pass"
    else
        check "shell.ohmyzsh" "Oh My Zsh" "fail" "not installed" "Re-run: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only-phase 3"
    fi

    local p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ -d "$p10k_dir" ]]; then
        check "shell.p10k" "Powerlevel10k" "pass"
    else
        check "shell.p10k" "Powerlevel10k" "warn" "not installed"
    fi

    # Check plugins
    local plugins_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
    if [[ -d "$plugins_dir/zsh-autosuggestions" ]]; then
        check "shell.plugins.zsh_autosuggestions" "zsh-autosuggestions" "pass"
    else
        check "shell.plugins.zsh_autosuggestions" "zsh-autosuggestions" "warn" "not installed" \
            "git clone https://github.com/zsh-users/zsh-autosuggestions \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    fi

    if [[ -d "$plugins_dir/zsh-syntax-highlighting" ]]; then
        check "shell.plugins.zsh_syntax_highlighting" "zsh-syntax-highlighting" "pass"
    else
        check "shell.plugins.zsh_syntax_highlighting" "zsh-syntax-highlighting" "warn" "not installed" \
            "git clone https://github.com/zsh-users/zsh-syntax-highlighting \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
    fi

    # Check modern CLI tools
    if command -v lsd &>/dev/null; then
        check "shell.lsd_or_eza" "lsd" "pass"
    elif command -v eza &>/dev/null; then
        check "shell.lsd_or_eza" "eza (fallback)" "pass"
    else
        check "shell.lsd_or_eza" "lsd/eza" "warn" "neither installed" "sudo apt install lsd"
    fi

    check_command "shell.atuin" "Atuin" "atuin" "Re-run: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only-phase 5"
    check_command "shell.fzf" "fzf" "fzf" "sudo apt install fzf"
    check_command "shell.zoxide" "zoxide" "zoxide" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash"
    check_command "shell.direnv" "direnv" "direnv" "sudo apt install direnv"

    blank_line
}

# Check core tools
check_core_tools() {
    section "Core tools"

    check_command "tool.bun" "Bun" "bun" "Re-run: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only-phase 5"
    check_command "tool.uv" "uv" "uv" "Re-run: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only-phase 5"
    check_command "tool.cargo" "Cargo (Rust)" "cargo" "Re-run: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only-phase 5"
    check_command "tool.go" "Go" "go" "sudo apt install golang-go"
    check_command "tool.tmux" "tmux" "tmux" "sudo apt install tmux"
    check_command "tool.rg" "ripgrep" "rg" "sudo apt install ripgrep"
    check_command "tool.gh" "GitHub CLI (gh)" "gh" "sudo apt-get install -y gh"
    check_command "tool.git_lfs" "Git LFS" "git-lfs" "sudo apt-get install -y git-lfs"
    check_command "tool.rsync" "rsync" "rsync" "sudo apt-get install -y rsync"
    check_command "tool.strace" "strace" "strace" "sudo apt-get install -y strace"
    check_command "tool.lsof" "lsof" "lsof" "sudo apt-get install -y lsof"
    check_command "tool.dig" "dig (dnsutils)" "dig" "sudo apt-get install -y dnsutils"
    check_command "tool.nc" "nc (netcat-openbsd)" "nc" "sudo apt-get install -y netcat-openbsd"
    check_command "tool.sg" "ast-grep" "sg" "cargo install ast-grep --locked"

    blank_line
}

# Check coding agents
check_agents() {
    section "Agents"

    check_command "agent.claude" "Claude Code" "claude" \
        "Re-run: curl -fsSL https://claude.ai/install.sh | bash"
    check_command "agent.codex" "Codex CLI" "codex" "bun install -g --trust @openai/codex@latest"
    check_command "agent.gemini" "Gemini CLI" "gemini" "bun install -g --trust @google/gemini-cli@latest"

    # Check aliases are defined in the zshrc
    if grep -q "^alias cc=" ~/.acfs/zsh/acfs.zshrc 2>/dev/null; then
        check "agent.alias.cc" "cc alias" "pass"
    else
        check "agent.alias.cc" "cc alias" "warn" "not in zshrc"
    fi

    if grep -q "^alias cod=" ~/.acfs/zsh/acfs.zshrc 2>/dev/null; then
        check "agent.alias.cod" "cod alias" "pass"
    else
        check "agent.alias.cod" "cod alias" "warn" "not in zshrc"
    fi

    if grep -q "^alias gmi=" ~/.acfs/zsh/acfs.zshrc 2>/dev/null; then
        check "agent.alias.gmi" "gmi alias" "pass"
    else
        check "agent.alias.gmi" "gmi alias" "warn" "not in zshrc"
    fi

    # Check for PATH conflicts (bead hi7)
    # Claude Code native install should be in ~/.local/bin, not bun/npm
    check_agent_path_conflicts

    blank_line
}

# Check for agent PATH conflicts (bead hi7)
# Native installations should take precedence over package manager versions
check_agent_path_conflicts() {
    local doctor_ci="${ACFS_DOCTOR_CI:-false}"

    local claude_path
    claude_path=$(command -v claude 2>/dev/null) || true

    if [[ -z "$claude_path" ]]; then
        return 0  # Not installed, skip
    fi

    # Native install should be in ~/.local/bin
    if [[ "$claude_path" == "$HOME/.local/bin/claude" ]]; then
        check "agent.path.claude" "Claude Code path" "pass" "native ($claude_path)"
    elif [[ "$claude_path" == *".bun"* ]] || [[ "$claude_path" == *"node_modules"* ]]; then
        if [[ "$doctor_ci" == "true" ]]; then
            check "agent.path.claude" "Claude Code path" "pass" "using bun/npm version (expected in CI): $claude_path"
        else
            # Package manager version - warn about potential conflicts
            check "agent.path.claude" "Claude Code path" "warn" \
                "using bun/npm version ($claude_path)" \
                "Switch to native: acfs update --force --agents-only (removes bun version, installs native)"
        fi
    else
        # Some other path - just note it
        check "agent.path.claude" "Claude Code path" "pass" "$claude_path"
    fi
}

# Check DCG hook registration status
check_dcg_hook_status() {
    if ! command -v dcg &>/dev/null; then
        check "stack.dcg" "DCG" "warn" "not installed" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/main/install.sh | bash && dcg install"
        return
    fi

    local version
    version=$(get_version_line "dcg")

    if ! command -v claude &>/dev/null; then
        check "stack.dcg" "DCG ($version)" "warn" "Claude Code not found for hook registration" \
            "Install Claude Code, then run: dcg install"
        return
    fi

    local settings_file=""
    if [[ -f "$HOME/.claude/settings.json" ]]; then
        settings_file="$HOME/.claude/settings.json"
    elif [[ -f "$HOME/.config/claude/settings.json" ]]; then
        settings_file="$HOME/.config/claude/settings.json"
    fi

    if [[ -z "$settings_file" ]]; then
        check "stack.dcg" "DCG ($version)" "warn" "hook not registered (settings.json missing)" \
            "Run: dcg install"
        return
    fi

    if grep -q "dcg" "$settings_file" 2>/dev/null; then
        check "stack.dcg" "DCG ($version)" "pass" "installed + hook registered"
    else
        check "stack.dcg" "DCG ($version)" "warn" "binary installed but hook not registered" \
            "Run: dcg install"
    fi
}

# Check cloud tools
check_cloud() {
    section "Cloud/DB"

    local doctor_ci="${ACFS_DOCTOR_CI:-false}"

    check_optional_command "cloud.vault" "Vault" "vault"
    check_optional_command "cloud.postgres" "PostgreSQL" "psql"
    check_optional_command "cloud.wrangler" "Wrangler" "wrangler" "bun install -g --trust wrangler@latest"
    check_optional_command "cloud.supabase" "Supabase CLI" "supabase" "acfs update --cloud-only --force"
    check_optional_command "cloud.vercel" "Vercel CLI" "vercel" "bun install -g --trust vercel@latest"

    # Tailscale VPN (bt5)
    if command -v tailscale &>/dev/null; then
        local ts_status
        if command -v jq &>/dev/null; then
            ts_status=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // "unknown"' 2>/dev/null || echo "unknown")
        else
            ts_status=$(tailscale status --json 2>/dev/null | sed -n 's/.*"BackendState"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
            ts_status="${ts_status:-unknown}"
        fi
        case "$ts_status" in
            "Running")
                check "network.tailscale" "Tailscale" "pass" "connected"
                ;;
            "NeedsLogin")
                if [[ "$doctor_ci" == "true" ]]; then
                    check "network.tailscale" "Tailscale (needs login)" "pass" "expected in CI"
                else
                    check "network.tailscale" "Tailscale" "warn" "needs login" "Run: sudo tailscale up"
                fi
                ;;
            *)
                if [[ "$doctor_ci" == "true" ]]; then
                    check "network.tailscale" "Tailscale ($ts_status)" "pass" "expected in CI"
                else
                    check "network.tailscale" "Tailscale" "warn" "$ts_status" "Run: sudo tailscale up"
                fi
                ;;
        esac
    else
        if [[ "$doctor_ci" == "true" ]]; then
            check "network.tailscale" "Tailscale (not installed)" "pass" "ok in CI"
        else
            check "network.tailscale" "Tailscale" "warn" "not installed (optional)" "Install: curl --proto '=https' --proto-redir '=https' -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only network.tailscale"
        fi
    fi

    # SSH keepalive configuration (prevents VPN/NAT disconnects)
    if [[ -f /etc/ssh/sshd_config ]]; then
        local keepalive_interval
        keepalive_interval=$(grep -E '^ClientAliveInterval[[:space:]]+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
        keepalive_interval="${keepalive_interval:-0}"
        if [[ "$keepalive_interval" -gt 0 ]] 2>/dev/null; then
            check "network.ssh_keepalive" "SSH keepalive" "pass" "ClientAliveInterval ${keepalive_interval}s"
        else
            if [[ "$doctor_ci" == "true" ]]; then
                check "network.ssh_keepalive" "SSH keepalive (not configured)" "pass" "ok in CI"
            else
                check "network.ssh_keepalive" "SSH keepalive" "warn" "not configured (optional)" "Install: curl --proto '=https' --proto-redir '=https' -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only network.ssh_keepalive"
            fi
        fi
    fi

    blank_line
}

# Check Dicklesworthstone stack
check_stack() {
    section "Dicklesworthstone stack"

    check_command "stack.ntm" "NTM" "ntm" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh | bash"
    check_command "stack.slb" "SLB" "slb" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/simultaneous_launch_button/main/scripts/install.sh | bash"

    # UBS - custom check
    if command -v ubs &>/dev/null; then
        local version
        version=$(get_version_line "ubs")
        check "stack.ubs" "UBS ($version)" "pass" "installed"
    else
        check "stack.ubs" "UBS" "fail" "not found" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/master/install.sh | bash"
    fi

    check_command "stack.bv" "Beads Viewer" "bv" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh | bash"

    # CASS - custom check
    if command -v cass &>/dev/null; then
        local version
        version=$(get_version_line "cass")
        check "stack.cass" "CASS ($version)" "pass" "installed"
    else
        check "stack.cass" "CASS" "fail" "not found" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_session_search/main/install.sh | bash -s -- --easy-mode"
    fi

    check_command "stack.cm" "CASS Memory" "cm" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh | bash -s -- --easy-mode"
    check_command "stack.caam" "CAAM" "caam" \
        "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/coding_agent_account_manager/main/install.sh | bash"

    # Check MCP Agent Mail
    if command -v am &>/dev/null || [[ -d "$HOME/mcp_agent_mail" ]]; then
        check "stack.mcp_agent_mail" "MCP Agent Mail" "pass"
    else
        check "stack.mcp_agent_mail" "MCP Agent Mail" "warn" "not installed" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh | bash"
    fi

    # Check RU (Repo Updater)
    if command -v ru &>/dev/null; then
        local version
        version=$(get_version_line "ru")
        check "stack.ru" "RU ($version)" "pass" "installed"
    else
        check "stack.ru" "RU (Repo Updater)" "warn" "not installed" \
            "Re-run: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/repo_updater/main/install.sh | bash"
    fi

    # Check DCG (Destructive Command Guard)
    check_dcg_hook_status

    blank_line
}

# ============================================================
# Skipped Tools Display (bead qup)
# ============================================================
# Shows tools the user intentionally skipped during installation.
# These are not failures - they are deliberate choices.

# Load skipped tools from state.json
# Populates SKIPPED_TOOLS_DATA array with "tool:reason" entries
load_skipped_tools() {
    SKIPPED_TOOLS_DATA=()
    local state_file="$HOME/.acfs/state.json"

    [[ -f "$state_file" ]] || return 0

    # Use jq if available for reliable parsing
    if command -v jq &>/dev/null; then
        local skipped_json
        skipped_json=$(jq -r '.skipped_tools // empty' "$state_file" 2>/dev/null) || return 0

        # Handle both array format ["tool1","tool2"] and object format {"tool1":"reason"}
        if [[ "$skipped_json" == "["* ]]; then
            # Array format - no reasons stored
            while IFS= read -r tool; do
                [[ -n "$tool" && "$tool" != "null" ]] && SKIPPED_TOOLS_DATA+=("$tool:user choice")
            done < <(jq -r '.skipped_tools[]? // empty' "$state_file" 2>/dev/null)
        elif [[ "$skipped_json" == "{"* ]]; then
            # Object format with reasons
            while IFS= read -r line; do
                [[ -n "$line" ]] && SKIPPED_TOOLS_DATA+=("$line")
            done < <(jq -r '.skipped_tools | to_entries[]? | "\(.key):\(.value)"' "$state_file" 2>/dev/null)
        fi
    else
        # Fallback: basic sed for array format (POSIX-compatible, works on macOS/BSD)
        local skipped
        skipped=$(sed -n 's/.*"skipped_tools"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' "$state_file" 2>/dev/null | tr -d '", ')
        for tool in $skipped; do
            [[ -n "$tool" ]] && SKIPPED_TOOLS_DATA+=("$tool:user choice")
        done
    fi
}

# Display a skipped tool with [○] indicator
# Usage: check_skipped <id> <label> [reason]
check_skipped() {
    local id="$1"
    local label="$2"
    local reason="${3:-user choice}"

    ((SKIP_COUNT += 1))

    if [[ "$JSON_MODE" == "true" ]]; then
        JSON_CHECKS+=("{\"id\":\"$(json_escape "$id")\",\"label\":\"$(json_escape "$label")\",\"status\":\"skipped\",\"details\":\"$(json_escape "$reason")\",\"fix\":null}")
        return 0
    fi

    if [[ "$HAS_GUM" == "true" ]]; then
        echo "  $(gum style --foreground "$ACFS_MUTED" --bold "○ SKIP") $(gum style --foreground "$ACFS_MUTED" "$label")"
        echo "        $(gum style --foreground "$ACFS_MUTED" --italic "Reason: $reason")"
    else
        echo -e "  ${CYAN}○ SKIP${NC} $label"
        echo -e "        Reason: $reason"
    fi
}

# Show intentionally skipped tools section
show_skipped_tools() {
    load_skipped_tools

    # Skip section if nothing was skipped
    [[ ${#SKIPPED_TOOLS_DATA[@]} -eq 0 ]] && return 0

    section "Intentionally Skipped"

    if [[ "$JSON_MODE" != "true" ]]; then
        if [[ "$HAS_GUM" == "true" ]]; then
            gum style --foreground "$ACFS_MUTED" "  These tools were skipped during installation (not errors)"
        else
            echo -e "  ${CYAN}These tools were skipped during installation (not errors)${NC}"
        fi
        echo ""
    fi

    for entry in "${SKIPPED_TOOLS_DATA[@]}"; do
        local tool="${entry%%:*}"
        local reason="${entry#*:}"
        check_skipped "skipped.$tool" "$tool" "$reason"
    done

    blank_line
}

# ============================================================
# Deep Checks - Functional Tests (bead 01s)
# ============================================================
# These tests go beyond "is the binary installed" to verify
# actual functionality: authentication, connectivity, etc.
#
# Only runs when --deep flag is provided.
# ============================================================

# Deep check counters (separate from main counters for summary)
DEEP_PASS_COUNT=0
DEEP_WARN_COUNT=0
DEEP_FAIL_COUNT=0

# Run all deep/functional checks with formatted output
# Enhanced per bead aqs: Adds counters and summary
# Enhanced per bead lz1: Adds timing
# Usage: run_deep_checks
run_deep_checks() {
    section "Deep Checks (Functional Tests)"

    # Track total deep check time (bead lz1)
    local start_time
    start_time=$(date +%s)

    if [[ "$JSON_MODE" != "true" ]]; then
        local cache_status=""
        if [[ "$NO_CACHE" == "true" ]]; then
            cache_status=" (cache disabled)"
        fi
        if [[ "$HAS_GUM" == "true" ]]; then
            gum style --foreground "$ACFS_MUTED" "  Running functional tests...$cache_status"
        else
            echo -e "  ${CYAN}Running functional tests...$cache_status${NC}"
        fi
        echo ""
    fi

    # Capture counts before deep checks to calculate deep-only stats
    local pre_pass=$PASS_COUNT
    local pre_warn=$WARN_COUNT
    local pre_fail=$FAIL_COUNT

    # Agent authentication checks
    deep_check_agent_auth

    # Database connectivity checks
    deep_check_database

    # Cloud CLI checks
    deep_check_cloud

    # tmux responsiveness checks (GitHub issue #20: NTM timeouts / slow tmux)
    deep_check_tmux_performance

    # Calculate deep check specific counts
    DEEP_PASS_COUNT=$((PASS_COUNT - pre_pass))
    DEEP_WARN_COUNT=$((WARN_COUNT - pre_warn))
    DEEP_FAIL_COUNT=$((FAIL_COUNT - pre_fail))
    local deep_total=$((DEEP_PASS_COUNT + DEEP_WARN_COUNT + DEEP_FAIL_COUNT))

    # Calculate elapsed time (bead lz1)
    local end_time elapsed_time
    end_time=$(date +%s)
    elapsed_time=$((end_time - start_time))
    DEEP_CHECK_ELAPSED=$elapsed_time  # Export for JSON output

    # Print deep checks summary
    if [[ "$JSON_MODE" != "true" ]]; then
        echo ""
        if [[ "$HAS_GUM" == "true" ]]; then
            local summary_text=""
            if [[ $DEEP_FAIL_COUNT -eq 0 ]]; then
                summary_text="$(gum style --foreground "$ACFS_SUCCESS" --bold "$DEEP_PASS_COUNT/$deep_total") functional tests passed"
                [[ $DEEP_WARN_COUNT -gt 0 ]] && summary_text="$summary_text $(gum style --foreground "$ACFS_WARNING" "($DEEP_WARN_COUNT warnings)")"
            else
                summary_text="$(gum style --foreground "$ACFS_ERROR" --bold "$DEEP_PASS_COUNT/$deep_total") functional tests passed"
                summary_text="$summary_text $(gum style --foreground "$ACFS_ERROR" "($DEEP_FAIL_COUNT failed)")"
            fi
            echo "  $summary_text $(gum style --foreground "$ACFS_MUTED" "in ${elapsed_time}s")"
        else
            if [[ $DEEP_FAIL_COUNT -eq 0 ]]; then
                echo -e "  ${GREEN}$DEEP_PASS_COUNT/$deep_total${NC} functional tests passed in ${elapsed_time}s"
            else
                echo -e "  ${RED}$DEEP_PASS_COUNT/$deep_total${NC} functional tests passed (${RED}$DEEP_FAIL_COUNT failed${NC}) in ${elapsed_time}s"
            fi
        fi
    fi

    blank_line
}

# Deep check: Agent authentication
# Enhanced per bead 325: Check config files, API keys, and low-cost API checks
deep_check_agent_auth() {
    check_claude_auth
    check_codex_auth
    check_gemini_auth
}

# check_claude_auth - Thorough Claude Code authentication check
# Returns via check(): pass (auth OK), warn (partial/skipped), fail (auth broken)
# Related: bead 325
# Fixed: Check correct credentials file (.credentials.json, not config.json)
# Fixed: Removed non-existent --print-system-info flag
check_claude_auth() {
    # Skip if not installed
    if ! command -v claude &>/dev/null; then
        check "deep.agent.claude_auth" "Claude Code" "warn" "not installed" "acfs update --force --agents-only"
        return
    fi

    # Check if binary works
    if ! claude --version &>/dev/null; then
        check "deep.agent.claude_auth" "Claude Code auth" "fail" "binary error" "Reinstall: acfs update --force --agents-only"
        return
    fi

    # Check for credentials file (indicates previous auth)
    # Claude Code stores OAuth credentials in ~/.claude/.credentials.json (note leading dot)
    local creds_file="$HOME/.claude/.credentials.json"
    if [[ ! -f "$creds_file" ]]; then
        check "deep.agent.claude_auth" "Claude Code auth" "warn" "not authenticated" "Run: claude to authenticate"
        return
    fi

    # Verify OAuth token exists in credentials file
    local has_token=false
    if command -v jq &>/dev/null; then
        # Use jq for reliable JSON parsing
        if jq -e '.claudeAiOauth.accessToken // empty' "$creds_file" >/dev/null 2>&1; then
            has_token=true
        fi
    else
        # Fallback: basic grep check (less reliable but works without jq)
        if grep -q '"accessToken"' "$creds_file" 2>/dev/null; then
            has_token=true
        fi
    fi

    if [[ "$has_token" == "true" ]]; then
        check "deep.agent.claude_auth" "Claude Code auth" "pass" "OAuth authenticated"
    else
        check "deep.agent.claude_auth" "Claude Code auth" "warn" "credentials file exists but no valid token" "Run: claude to re-authenticate"
    fi
}

# check_codex_auth - Thorough Codex CLI authentication check
# Codex CLI uses OAuth (ChatGPT accounts), NOT OPENAI_API_KEY environment variable.
# Token location: ~/.codex/auth.json (or $CODEX_HOME/auth.json)
# Returns via check(): pass (auth OK), warn (partial/skipped), fail (auth broken)
# Related: bead 325, ua5 (Codex auth documentation fix)
check_codex_auth() {
    # Skip if not installed
    if ! command -v codex &>/dev/null; then
        check "deep.agent.codex_auth" "Codex CLI" "warn" "not installed" "bun install -g --trust @openai/codex@latest"
        return
    fi

    # Check if binary works
    if ! codex --version &>/dev/null; then
        check "deep.agent.codex_auth" "Codex CLI auth" "fail" "binary error" "Reinstall: bun install -g --trust @openai/codex@latest"
        return
    fi

    # Determine auth.json location (respects CODEX_HOME if set)
    local auth_file="${CODEX_HOME:-$HOME/.codex}/auth.json"

    # Check if auth.json exists
    if [[ ! -f "$auth_file" ]]; then
        check "deep.agent.codex_auth" "Codex CLI auth" "warn" "not authenticated" "Run: codex login"
        return
    fi

    # Check for OAuth tokens (primary auth method)
    # auth.json structure: { "tokens": { "access_token": "..." }, "OPENAI_API_KEY": null|"..." }
    local has_oauth=false
    local has_api_key=false

    # Check for OAuth tokens.access_token (preferred)
    if command -v jq &>/dev/null; then
        # Use jq if available for reliable JSON parsing
        if jq -e '.tokens.access_token // empty' "$auth_file" >/dev/null 2>&1; then
            has_oauth=true
        fi
        # Check for legacy API key in auth.json
        if jq -e '.OPENAI_API_KEY // empty' "$auth_file" 2>/dev/null | grep -q .; then
            has_api_key=true
        fi
    else
        # Fallback: basic grep checks (less reliable but works without jq)
        if grep -q '"access_token"' "$auth_file" 2>/dev/null; then
            has_oauth=true
        fi
        if grep -q '"OPENAI_API_KEY".*:.*"[^"]\+"' "$auth_file" 2>/dev/null; then
            has_api_key=true
        fi
    fi

    if [[ "$has_oauth" == "true" ]]; then
        check "deep.agent.codex_auth" "Codex CLI auth" "pass" "OAuth authenticated (ChatGPT account)"
    elif [[ "$has_api_key" == "true" ]]; then
        check "deep.agent.codex_auth" "Codex CLI auth" "pass" "API key authenticated (pay-as-you-go)"
    else
        check "deep.agent.codex_auth" "Codex CLI auth" "warn" "auth.json exists but no valid tokens" "Run: codex login"
    fi
}

# check_gemini_auth - Thorough Gemini CLI authentication check
# Returns via check(): pass (auth OK), warn (partial/skipped), fail (auth broken)
# Related: bead 325
check_gemini_auth() {
    # Skip if not installed
    if ! command -v gemini &>/dev/null; then
        check "deep.agent.gemini_auth" "Gemini CLI" "warn" "not installed" "bun install -g --trust @google/gemini-cli@latest"
        return
    fi

    # Check if binary works
    if ! gemini --version &>/dev/null; then
        check "deep.agent.gemini_auth" "Gemini CLI auth" "fail" "binary error" "Reinstall: bun install -g --trust @google/gemini-cli@latest"
        return
    fi

    # Gemini CLI uses OAuth web login (like Claude Code and Codex CLI)
    # Users authenticate via `gemini` command which opens browser login
    # Credentials are stored in config files, NOT via API keys
    local found_auth=false

    # Check for actual Gemini CLI OAuth tokens (primary auth method)
    if [[ -f "$HOME/.gemini/mcp-oauth-tokens-v2.json" ]]; then
        found_auth=true
    fi

    # Check for Google accounts file (secondary auth evidence)
    if [[ -f "$HOME/.gemini/google_accounts.json" ]]; then
        found_auth=true
    fi

    # Check for alternative credential locations (fallback)
    if [[ -f "$HOME/.config/gemini/credentials.json" ]]; then
        found_auth=true
    fi

    # Some versions may store auth tokens in other files; only treat the config
    # directory as evidence of auth if it exists and is non-empty.
    if [[ -d "$HOME/.config/gemini" ]] && [[ -n "$(ls -A "$HOME/.config/gemini" 2>/dev/null)" ]]; then
        found_auth=true
    fi

    # Check for legacy config
    if [[ -f "$HOME/.gemini/config" ]]; then
        found_auth=true
    fi

    if [[ "$found_auth" == "true" ]]; then
        check "deep.agent.gemini_auth" "Gemini CLI auth" "pass" "authenticated"
    else
        check "deep.agent.gemini_auth" "Gemini CLI auth" "warn" "not logged in" "Run 'gemini' to authenticate via browser"
    fi
}

# Deep check: Database connectivity
# Enhanced per bead azw: PostgreSQL connection and role checks
deep_check_database() {
    check_postgres_connection
    check_postgres_role
}

# check_postgres_connection - Test PostgreSQL connectivity
# Related: bead azw
check_postgres_connection() {
    # Skip if not installed
    if ! command -v psql &>/dev/null; then
        check "deep.db.postgres_connect" "PostgreSQL connection" "warn" "psql not installed" "sudo apt install postgresql-client"
        return
    fi

    # Try to connect to local postgres (5 second timeout, no password prompt)
    # Use -w to avoid password prompts (would hang)
    if timeout 5 psql -w -h localhost -U postgres -c 'SELECT 1' &>/dev/null; then
        check "deep.db.postgres_connect" "PostgreSQL connection" "pass" "localhost:5432"
    elif timeout 5 psql -w -h /var/run/postgresql -U postgres -c 'SELECT 1' &>/dev/null; then
        check "deep.db.postgres_connect" "PostgreSQL connection" "pass" "unix socket"
    else
        # Try connecting as current user
        if timeout 5 psql -w -c 'SELECT 1' &>/dev/null; then
            check "deep.db.postgres_connect" "PostgreSQL connection" "pass" "current user"
        else
            check "deep.db.postgres_connect" "PostgreSQL connection" "warn" "connection failed" "sudo systemctl status postgresql"
        fi
    fi
}

# check_postgres_role - Verify target user role exists in PostgreSQL
# Related: bead azw
# Fixed: Try current user first before postgres user (pg_roles is readable by any authenticated user)
# Fixed: Provide actionable fix message (createuser, not systemctl status)
# Fixed: Use parameterized queries to prevent SQL injection (ACFS_TARGET_USER is passed via -v)
check_postgres_role() {
    # Skip if not installed
    if ! command -v psql &>/dev/null; then
        return  # Already reported in connection check
    fi

    # Validate target user - PostgreSQL identifiers must match this pattern
    # SECURITY: Prevents SQL injection by validating input before use
    local target_user="${ACFS_TARGET_USER:-}"
    if [[ -z "$target_user" ]]; then
        check "deep.db.postgres_role" "PostgreSQL role check" "warn" "ACFS_TARGET_USER not set"
        return
    fi
    if [[ ! "$target_user" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        check "deep.db.postgres_role" "PostgreSQL role check" "fail" "invalid username format"
        return
    fi

    # Try to check if target user role exists
    # pg_roles view is readable by any authenticated user - no superuser required
    # SECURITY: Use psql -v to pass variable and :'var' syntax for safe interpolation
    local role_check
    local connect_success=false
    local sql_query="SELECT 1 FROM pg_roles WHERE rolname=:'target_user'"

    # Try connecting as current user first (mirrors check_postgres_connection behavior)
    # This works when pg_hba.conf allows peer auth for local users
    if role_check=$(timeout 5 psql -w -tAc "$sql_query" -v target_user="$target_user" 2>/dev/null); then
        connect_success=true
    # Try localhost with postgres user as fallback
    elif role_check=$(timeout 5 psql -w -h localhost -U postgres -tAc "$sql_query" -v target_user="$target_user" 2>/dev/null); then
        connect_success=true
    # Try unix socket with postgres user as last resort
    elif role_check=$(timeout 5 psql -w -h /var/run/postgresql -U postgres -tAc "$sql_query" -v target_user="$target_user" 2>/dev/null); then
        connect_success=true
    fi

    if [[ "$connect_success" == "true" ]]; then
        if [[ "$role_check" == "1" ]]; then
            check "deep.db.postgres_role" "PostgreSQL $target_user role" "pass" "role exists"
        else
            check "deep.db.postgres_role" "PostgreSQL $target_user role" "warn" "role missing" "sudo -u postgres createuser -s $target_user"
        fi
    else
        # Connection failed - provide actionable fix
        check "deep.db.postgres_role" "PostgreSQL $target_user role" "warn" "could not verify (connection failed)" "sudo -u postgres createuser -s $target_user"
    fi
}

# Deep check: Cloud CLI authentication
# Enhanced per bead azw: Thorough cloud CLI auth checks with proper status handling
# All checks use 10 second timeout to prevent hanging on network issues
deep_check_cloud() {
    check_vault_configured
    check_gh_auth
    check_wrangler_auth
    check_supabase_auth
    check_vercel_auth
}

# Deep check: tmux responsiveness
# Related: GitHub issue #20 (NTM: "context deadline exceeded")
deep_check_tmux_performance() {
    if ! command -v tmux &>/dev/null; then
        check "deep.tmux.present" "tmux responsiveness" "warn" "tmux not installed" "sudo apt install tmux"
        return
    fi

    local timeout_secs=5
    local warn_threshold_ms=1000
    local hint="If NTM shows 'context deadline exceeded', tmux may be slow. Try running NTM outside of tmux (fresh SSH session). Diagnose with: time tmux list-sessions; time tmux list-panes -a; ls -la /tmp/tmux-*."
    if [[ -n "${TMUX:-}" ]]; then
        hint="You are currently inside tmux. If NTM is timing out, try running it outside tmux (new SSH session). Diagnose with: time tmux list-sessions; time tmux list-panes -a; ls -la /tmp/tmux-*."
    fi

    _deep_check_tmux_cmd() {
        local id="$1"
        local label="$2"
        shift 2

        local start_ns end_ns elapsed_ms
        start_ns=$(date +%s%N 2>/dev/null || echo "")

        local output status
        output=$(run_with_timeout "$timeout_secs" "$label" "$@")
        status=$?

        end_ns=$(date +%s%N 2>/dev/null || echo "")
        if [[ "$start_ns" =~ ^[0-9]+$ ]] && [[ "$end_ns" =~ ^[0-9]+$ ]]; then
            elapsed_ms=$(((end_ns - start_ns) / 1000000))
        else
            elapsed_ms=-1
        fi

        if ((status == 124)); then
            check_with_timeout_status "$id" "$label" "timeout" "timed out after ${timeout_secs}s" "$hint"
            return 0
        fi

        if ((status != 0)); then
            if echo "$output" | grep -qiE "no server running|failed to connect to server"; then
                check "$id" "$label (no server)" "pass" "no tmux server running"
                return 0
            fi

            local first_line=""
            first_line="$(printf '%s\n' "$output" | head -n 1)"
            [[ -z "$first_line" ]] && first_line="tmux command failed"
            check "$id" "$label" "warn" "$first_line" "$hint"
            return 0
        fi

        local label_with_timing="$label"
        if ((elapsed_ms >= 0)); then
            label_with_timing="$label (${elapsed_ms}ms)"
        fi

        if ((elapsed_ms >= 0)) && ((elapsed_ms >= warn_threshold_ms)); then
            check "$id" "$label_with_timing" "warn" "slow tmux" "$hint"
        else
            check "$id" "$label_with_timing" "pass" "ok"
        fi
        return 0
    }

    _deep_check_tmux_cmd "deep.tmux.list_sessions" "tmux list-sessions responsiveness" bash -lc "tmux list-sessions >/dev/null"
    _deep_check_tmux_cmd "deep.tmux.list_panes" "tmux list-panes -a responsiveness" bash -lc "tmux list-panes -a -F '#{pane_id}' >/dev/null"
}

# check_vault_configured - Check if Vault is configured and reachable
# Related: bead azw
check_vault_configured() {
    # Skip if not installed
    if ! command -v vault &>/dev/null; then
        check "deep.cloud.vault_status" "Vault" "warn" "not installed" "Install from https://www.vaultproject.io/"
        return
    fi

    # Check if VAULT_ADDR is set (required for vault to work)
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        # Check common config locations
        if [[ -f "$HOME/.zshrc.local" ]] && grep -q "VAULT_ADDR" "$HOME/.zshrc.local" 2>/dev/null; then
            check "deep.cloud.vault_config" "Vault config" "pass" "VAULT_ADDR in ~/.zshrc.local"
        else
            check "deep.cloud.vault_config" "Vault config" "warn" "VAULT_ADDR not set" "export VAULT_ADDR=https://your-vault-server:8200"
        fi
        return
    fi

    # VAULT_ADDR is set, try to connect
    if timeout 10 vault status &>/dev/null; then
        check "deep.cloud.vault_status" "Vault status" "pass" "connected to $VAULT_ADDR"
    else
        check "deep.cloud.vault_status" "Vault status" "warn" "not reachable" "Check VAULT_ADDR and network"
    fi
}

# check_gh_auth - GitHub CLI authentication check
# Related: bead azw
# Enhanced: Caching support (bead lz1)
check_gh_auth() {
    if ! command -v gh &>/dev/null; then
        check "deep.cloud.gh_auth" "GitHub CLI" "warn" "not installed" "sudo apt install gh"
        return
    fi

    # Try cache first for auth status (bead lz1)
    local cached_result
    if cached_result=$(get_cached_result "gh_auth"); then
        check "deep.cloud.gh_auth" "GitHub CLI auth" "pass" "$cached_result (cached)"
        return
    fi

    # Run with timeout
    local result
    result=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "GitHub CLI auth" gh auth status 2>&1)
    local status=$?

    if ((status == 124)); then
        check_with_timeout_status "deep.cloud.gh_auth" "GitHub CLI auth" "timeout" "check timed out" "Check network, then: gh auth login"
    elif ((status == 0)); then
        # Get the authenticated user for more detail
        local gh_user
        gh_user=$(timeout 5 gh api user --jq '.login' 2>/dev/null) || gh_user="authenticated"
        cache_result "gh_auth" "$gh_user"
        check "deep.cloud.gh_auth" "GitHub CLI auth" "pass" "$gh_user"
    else
        check "deep.cloud.gh_auth" "GitHub CLI auth" "warn" "not authenticated" "gh auth login"
    fi
}

# check_wrangler_auth - Cloudflare Wrangler authentication check
# Related: bead azw
# Enhanced: Caching and timeout support (bead lz1)
check_wrangler_auth() {
    if ! command -v wrangler &>/dev/null; then
        check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare)" "warn" "not installed" "bun install -g --trust wrangler@latest"
        return
    fi

    # Try cache first (bead lz1)
    local cached_result
    if cached_result=$(get_cached_result "wrangler_auth"); then
        check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "pass" "$cached_result (cached)"
        return
    fi

    # Run with timeout
    local result
    result=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "Wrangler auth" wrangler whoami 2>&1)
    local status=$?

    if ((status == 124)); then
        check_with_timeout_status "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "timeout" "check timed out" "Check network, then: wrangler login"
    elif ((status == 0)); then
        cache_result "wrangler_auth" "authenticated"
        check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "pass" "authenticated"
    else
        # Check for CLOUDFLARE_API_TOKEN as alternative
        if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
            cache_result "wrangler_auth" "CLOUDFLARE_API_TOKEN"
            check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "pass" "CLOUDFLARE_API_TOKEN set"
        else
            check "deep.cloud.wrangler_auth" "Wrangler (Cloudflare) auth" "warn" "not authenticated" "wrangler login (or set CLOUDFLARE_API_TOKEN for headless)"
        fi
    fi
}

# check_supabase_auth - Supabase CLI authentication check
# Related: bead azw
check_supabase_auth() {
    if ! command -v supabase &>/dev/null; then
        check "deep.cloud.supabase" "Supabase CLI" "warn" "not installed" "acfs update --cloud-only --force"
        return
    fi

    # Check if binary works
    if ! timeout 5 supabase --version &>/dev/null; then
        check "deep.cloud.supabase" "Supabase CLI" "fail" "binary error" "Reinstall: acfs update --cloud-only --force"
        return
    fi

    # Check for access token in config directory
    local access_token_file="$HOME/.supabase/access-token"
    local alt_access_token_file="$HOME/.config/supabase/access-token"

    if [[ -f "$access_token_file" || -f "$alt_access_token_file" ]]; then
        # Check if token is not empty
        if [[ -s "$access_token_file" || -s "$alt_access_token_file" ]]; then
            check "deep.cloud.supabase" "Supabase CLI auth" "pass" "access token exists"
        else
            check "deep.cloud.supabase" "Supabase CLI auth" "warn" "empty access token" "supabase login (or set SUPABASE_ACCESS_TOKEN for headless)"
        fi
    elif [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
        check "deep.cloud.supabase" "Supabase CLI auth" "pass" "SUPABASE_ACCESS_TOKEN set"
    else
        check "deep.cloud.supabase" "Supabase CLI auth" "warn" "not authenticated" "supabase login (or set SUPABASE_ACCESS_TOKEN for headless)"
    fi
}

# check_vercel_auth - Vercel CLI authentication check
# Related: bead azw
# Enhanced: Caching and timeout support (bead lz1)
check_vercel_auth() {
    if ! command -v vercel &>/dev/null; then
        check "deep.cloud.vercel_auth" "Vercel CLI" "warn" "not installed" "bun install -g --trust vercel@latest"
        return
    fi

    # Try cache first (bead lz1)
    local cached_result
    if cached_result=$(get_cached_result "vercel_auth"); then
        check "deep.cloud.vercel_auth" "Vercel auth" "pass" "$cached_result (cached)"
        return
    fi

    # Run with timeout
    local result
    result=$(run_with_timeout "$DEEP_CHECK_TIMEOUT" "Vercel auth" vercel whoami 2>&1)
    local status=$?

    if ((status == 124)); then
        check_with_timeout_status "deep.cloud.vercel_auth" "Vercel auth" "timeout" "check timed out" "Check network, then: vercel login"
    elif ((status == 0)); then
        # Get the authenticated user/team for more detail
        local vercel_user
        vercel_user=$(timeout 5 vercel whoami 2>/dev/null) || vercel_user="authenticated"
        cache_result "vercel_auth" "$vercel_user"
        check "deep.cloud.vercel_auth" "Vercel auth" "pass" "$vercel_user"
    else
        # Check for VERCEL_TOKEN as alternative
        if [[ -n "${VERCEL_TOKEN:-}" ]]; then
            cache_result "vercel_auth" "VERCEL_TOKEN"
            check "deep.cloud.vercel_auth" "Vercel auth" "pass" "VERCEL_TOKEN set"
            return
        fi

        # Fallback: detect auth file if offline
        if [[ -f "$HOME/.config/vercel/auth.json" || -f "$HOME/.vercel/auth.json" ]]; then
            cache_result "vercel_auth" "auth file present"
            check "deep.cloud.vercel_auth" "Vercel auth" "pass" "auth file present"
        else
            check "deep.cloud.vercel_auth" "Vercel auth" "warn" "not authenticated" "vercel login (or use --token for headless)"
        fi
    fi
}

# Print summary
print_summary() {
    echo ""

    # Print legend (bead qup)
    local doctor_ci="${ACFS_DOCTOR_CI:-false}"
    if [[ "$doctor_ci" != "true" ]]; then
        if [[ "$HAS_GUM" == "true" ]]; then
            gum style --foreground "$ACFS_MUTED" "  Legend: $(gum style --foreground "$ACFS_SUCCESS" "✓") installed  $(gum style --foreground "$ACFS_MUTED" "○") skipped  $(gum style --foreground "$ACFS_ERROR" "✖") missing  $(gum style --foreground "$ACFS_WARNING" "⚠") warning  $(gum style --foreground "$ACFS_WARNING" "?") timeout"
        else
            echo -e "  Legend: ${GREEN}✓${NC} installed  ${CYAN}○${NC} skipped  ${RED}✖${NC} missing  ${YELLOW}⚠${NC} warning  ${YELLOW}?${NC} timeout"
        fi
    fi

    if [[ "$HAS_GUM" == "true" ]]; then
        # Beautiful gum-styled summary
        local status_line=""
        status_line="$(gum style --foreground "$ACFS_SUCCESS" --bold "$PASS_COUNT passed") "
        [[ $SKIP_COUNT -gt 0 ]] && status_line+="$(gum style --foreground "$ACFS_MUTED" "$SKIP_COUNT skipped") "
        status_line+="$(gum style --foreground "$ACFS_WARNING" "$WARN_COUNT warnings") "
        status_line+="$(gum style --foreground "$ACFS_ERROR" "$FAIL_COUNT failed")"

        if [[ $FAIL_COUNT -eq 0 ]]; then
            gum style \
                --border double \
                --border-foreground "$ACFS_SUCCESS" \
                --padding "1 3" \
                --margin "1 0" \
                --align center \
                "$(gum style --foreground "$ACFS_SUCCESS" --bold '✓ ACFS Health Check Passed')

$status_line

$(gum style --foreground "$ACFS_MUTED" "Next: run 'onboard' to learn how to use your new setup")"
        else
            gum style \
                --border double \
                --border-foreground "$ACFS_ERROR" \
                --padding "1 3" \
                --margin "1 0" \
                --align center \
                "$(gum style --foreground "$ACFS_ERROR" --bold '✖ Some Checks Failed')

$status_line

$(gum style --foreground "$ACFS_MUTED" "Run the suggested fix commands, then 'acfs doctor' again")"
        fi
    else
        echo "============================================================"
        local summary_line="Checks: ${GREEN}$PASS_COUNT passed${NC}"
        [[ $SKIP_COUNT -gt 0 ]] && summary_line+=", ${CYAN}$SKIP_COUNT skipped${NC}"
        summary_line+=", ${YELLOW}$WARN_COUNT warnings${NC}, ${RED}$FAIL_COUNT failed${NC}"
        echo -e "$summary_line"
        echo ""

        if [[ $FAIL_COUNT -eq 0 ]]; then
            echo -e "${GREEN}All critical checks passed!${NC}"
            echo ""
            echo "Next: run 'onboard' to learn how to use your new setup"
        else
            echo -e "${RED}Some checks failed. Run the suggested fix commands.${NC}"
            echo ""
            echo "After fixing, run 'acfs doctor' again to verify."
        fi
    fi
}

# Print JSON output
# Enhanced per bead aqs: Includes deep check summary when --deep is used
print_json() {
    local checks_json
    checks_json=$(printf '%s,' "${JSON_CHECKS[@]}" | sed 's/,$//')

    local os_id="unknown"
    local os_version="unknown"
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_id="${ID:-unknown}"
        os_version="${VERSION_ID:-unknown}"
    fi

    # Build deep summary JSON if deep mode was used
    local deep_summary_json=""
    if [[ "$DEEP_MODE" == "true" ]]; then
        local deep_total=$((DEEP_PASS_COUNT + DEEP_WARN_COUNT + DEEP_FAIL_COUNT))
        deep_summary_json=",
  \"deep_summary\": {\"pass\": $DEEP_PASS_COUNT, \"warn\": $DEEP_WARN_COUNT, \"fail\": $DEEP_FAIL_COUNT, \"total\": $deep_total, \"elapsed_seconds\": ${DEEP_CHECK_ELAPSED:-0}}"
    fi

    cat << EOF
{
  "acfs_version": "$(json_escape "$ACFS_VERSION")",
  "timestamp": "$(json_escape "$(date -Iseconds)")",
  "mode": "$(json_escape "${ACFS_MODE:-vibe}")",
  "deep_mode": $DEEP_MODE,
  "user": "$(json_escape "$(whoami)")",
  "os": {"id": "$(json_escape "$os_id")", "version": "$(json_escape "$os_version")"},
  "checks": [$checks_json],
  "summary": {"pass": $PASS_COUNT, "skip": $SKIP_COUNT, "warn": $WARN_COUNT, "fail": $FAIL_COUNT}$deep_summary_json
}
EOF
}

# Main
main() {
    local invoked_as
    invoked_as="$(basename "${0:-acfs}")"

    # If installed as `acfs`, support subcommands (doctor/update/services-setup/version).
    local subcmd="${1:-}"
    case "$subcmd" in
        doctor|check)
            shift
            ;;
        info|i)
            shift
            local info_script=""
            if [[ -f "$HOME/.acfs/scripts/lib/info.sh" ]]; then
                info_script="$HOME/.acfs/scripts/lib/info.sh"
            elif [[ -f "$SCRIPT_DIR/info.sh" ]]; then
                info_script="$SCRIPT_DIR/info.sh"
            fi

            if [[ -n "$info_script" ]]; then
                exec bash "$info_script" "$@"
            fi

            echo "Error: info.sh not found" >&2
            return 1
            ;;
        dashboard)
            shift
            local dashboard_script=""
            if [[ -f "$HOME/.acfs/scripts/lib/dashboard.sh" ]]; then
                dashboard_script="$HOME/.acfs/scripts/lib/dashboard.sh"
            elif [[ -f "$SCRIPT_DIR/dashboard.sh" ]]; then
                dashboard_script="$SCRIPT_DIR/dashboard.sh"
            fi

            if [[ -n "$dashboard_script" ]]; then
                exec bash "$dashboard_script" "$@"
            fi

            echo "Error: dashboard.sh not found" >&2
            return 1
            ;;
        continue|progress)
            shift
            local continue_script=""
            if [[ -f "$HOME/.acfs/scripts/lib/continue.sh" ]]; then
                continue_script="$HOME/.acfs/scripts/lib/continue.sh"
            elif [[ -f "$SCRIPT_DIR/continue.sh" ]]; then
                continue_script="$SCRIPT_DIR/continue.sh"
            fi

            if [[ -n "$continue_script" ]]; then
                exec bash "$continue_script" "$@"
            fi

            echo "Error: continue.sh not found" >&2
            return 1
            ;;
        cheatsheet|cs)
            shift
            local cheatsheet_script=""
            if [[ -f "$HOME/.acfs/scripts/lib/cheatsheet.sh" ]]; then
                cheatsheet_script="$HOME/.acfs/scripts/lib/cheatsheet.sh"
            elif [[ -f "$SCRIPT_DIR/cheatsheet.sh" ]]; then
                cheatsheet_script="$SCRIPT_DIR/cheatsheet.sh"
            fi

            if [[ -n "$cheatsheet_script" ]]; then
                exec bash "$cheatsheet_script" "$@"
            fi

            echo "Error: cheatsheet.sh not found" >&2
            return 1
            ;;
        session)
            shift
            acfs_session_main "$@"
            return $?
            ;;
        update)
            shift
            local update_script=""
            if [[ -f "$HOME/.acfs/scripts/lib/update.sh" ]]; then
                update_script="$HOME/.acfs/scripts/lib/update.sh"
            elif [[ -f "$SCRIPT_DIR/update.sh" ]]; then
                update_script="$SCRIPT_DIR/update.sh"
            fi

            if [[ -n "$update_script" ]]; then
                exec bash "$update_script" "$@"
            fi

            echo "Error: update.sh not found" >&2
            return 1
            ;;
        newproj|new-project|new)
            shift
            local newproj_script=""
            if [[ -f "$HOME/.acfs/scripts/lib/newproj.sh" ]]; then
                newproj_script="$HOME/.acfs/scripts/lib/newproj.sh"
            elif [[ -f "$SCRIPT_DIR/newproj.sh" ]]; then
                newproj_script="$SCRIPT_DIR/newproj.sh"
            fi

            if [[ -n "$newproj_script" ]]; then
                exec bash "$newproj_script" "$@"
            fi

            echo "Error: newproj.sh not found" >&2
            return 1
            ;;
        services-setup|services|setup)
            shift
            local services_script=""
            if [[ -f "$HOME/.acfs/scripts/services-setup.sh" ]]; then
                services_script="$HOME/.acfs/scripts/services-setup.sh"
            elif [[ -f "$SCRIPT_DIR/../services-setup.sh" ]]; then
                services_script="$SCRIPT_DIR/../services-setup.sh"
            fi

            if [[ -n "$services_script" ]]; then
                exec bash "$services_script" "$@"
            fi

            echo "Error: services-setup.sh not found" >&2
            return 1
            ;;
        version|-v|--version)
            local version_file=""
            if [[ -f "$HOME/.acfs/VERSION" ]]; then
                version_file="$HOME/.acfs/VERSION"
            elif [[ -f "$SCRIPT_DIR/../VERSION" ]]; then
                version_file="$SCRIPT_DIR/../VERSION"
            elif [[ -f "$SCRIPT_DIR/../../VERSION" ]]; then
                version_file="$SCRIPT_DIR/../../VERSION"
            fi

            if [[ -n "$version_file" ]]; then
                cat "$version_file"
            else
                echo "${ACFS_VERSION:-unknown}"
            fi
            return 0
            ;;
        help|-h)
            print_acfs_help
            return 0
            ;;
        "")
            if [[ "$invoked_as" == "acfs" ]]; then
                print_acfs_help
                return 0
            fi
            ;;
    esac

    # Parse args
    while [[ $# -gt 0 ]]; do
        case $1 in
            --json)
                JSON_MODE=true
                shift
                ;;
            --deep)
                DEEP_MODE=true
                shift
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            --help|-h)
                echo "Usage: acfs doctor [--json] [--deep] [--no-cache]"
                echo ""
                echo "Options:"
                echo "  --json      Output results as JSON"
                echo "  --deep      Run functional tests (auth, connections)"
                echo "  --no-cache  Skip cache, run all checks fresh"
                echo ""
                echo "By default, doctor runs quick existence checks only."
                echo "Use --deep for thorough validation including:"
                echo "  - Agent authentication (claude, codex, gemini)"
                echo "  - Database connectivity (PostgreSQL)"
                echo "  - Cloud CLI authentication (vault, wrangler, etc.)"
                echo ""
                echo "Deep checks are cached for 5 minutes by default."
                echo "Use --no-cache to force fresh checks."
                echo ""
                echo "Examples:"
                echo "  acfs doctor                   # Quick health check"
                echo "  acfs doctor --deep            # Full functional tests"
                echo "  acfs doctor --deep --no-cache # Force fresh deep checks"
                echo "  acfs doctor --json            # JSON output for tooling"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ "$JSON_MODE" != "true" ]]; then
        local os_pretty="unknown"
        if [[ -f /etc/os-release ]]; then
            # shellcheck disable=SC1091
            . /etc/os-release
            os_pretty="${PRETTY_NAME:-${ID:-unknown} ${VERSION_ID:-unknown}}"
        fi

        if [[ "$HAS_GUM" == "true" ]]; then
            echo ""
            gum style \
                --border rounded \
                --border-foreground "$ACFS_PRIMARY" \
                --padding "1 2" \
                --margin "0 0 1 0" \
                "$(gum style --foreground "$ACFS_ACCENT" --bold '🩺 ACFS Doctor') $(gum style --foreground "$ACFS_MUTED" "v$ACFS_VERSION")

$(gum style --foreground "$ACFS_MUTED" "User:") $(gum style --foreground "$ACFS_TEAL" "$(whoami)")  $(gum style --foreground "$ACFS_MUTED" "Mode:") $(gum style --foreground "$ACFS_TEAL" "${ACFS_MODE:-vibe}")
$(gum style --foreground "$ACFS_MUTED" "OS:") $(gum style --foreground "$ACFS_TEAL" "$os_pretty")"
        else
            echo ""
            echo "ACFS Doctor v$ACFS_VERSION"
            echo "User: $(whoami)"
            echo "Mode: ${ACFS_MODE:-vibe}"
            echo "OS: $os_pretty"
            echo ""
        fi
    fi

    check_identity
    check_workspace
    check_shell
    check_core_tools
    check_agents
    check_cloud
    check_stack
    show_skipped_tools

    # Run deep checks if --deep flag was provided
    if [[ "$DEEP_MODE" == "true" ]]; then
        run_deep_checks
    fi

    if [[ "$JSON_MODE" == "true" ]]; then
        print_json
    else
        print_summary
    fi

    # Exit with appropriate code
    if [[ $FAIL_COUNT -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
