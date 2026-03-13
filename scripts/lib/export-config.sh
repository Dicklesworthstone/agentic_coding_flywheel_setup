#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# ACFS Export Config - Export current configuration
# Exports tool versions, settings, and module list for backup/migration
# ============================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_EXPORT_EXPLICIT_ACFS_HOME="${ACFS_HOME:-}"
_EXPORT_DEFAULT_ACFS_HOME="$HOME/.acfs"
ACFS_HOME="${_EXPORT_EXPLICIT_ACFS_HOME:-$_EXPORT_DEFAULT_ACFS_HOME}"
_EXPORT_SYSTEM_STATE_FILE="${ACFS_SYSTEM_STATE_FILE:-/var/lib/acfs/state.json}"
_EXPORT_RESOLVED_ACFS_HOME=""

# Source logging if available
if [[ -f "$SCRIPT_DIR/logging.sh" ]]; then
    source "$SCRIPT_DIR/logging.sh"
else
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
fi

# ============================================================
# Configuration
# ============================================================
OUTPUT_FORMAT="yaml"  # yaml, json, or minimal
STATE_FILE=""
VERSION_FILE=""
INSTALL_HELPERS_FILE="${ACFS_INSTALL_HELPERS_SH:-$SCRIPT_DIR/install_helpers.sh}"
MANIFEST_INDEX_FILE="${ACFS_MANIFEST_INDEX_SH:-$SCRIPT_DIR/../generated/manifest_index.sh}"

# ============================================================
# Parse Arguments
# ============================================================
show_help() {
    cat << 'EOF'
ACFS Export Config - Export current configuration

USAGE:
  acfs export-config [OPTIONS]

OPTIONS:
  --json          Output in JSON format (default: YAML)
  --minimal       Output only module list (one per line)
  --output FILE   Write to file instead of stdout
  -h, --help      Show this help message

EXAMPLES:
  acfs export-config                    # Print YAML to stdout
  acfs export-config > backup.yaml      # Save to file
  acfs export-config --json             # JSON output
  acfs export-config --minimal          # Just module list

SENSITIVE DATA:
  This command NEVER exports:
  - SSH keys, API tokens, passwords
  - Full paths containing usernames (sanitized to ~/)
  - Environment-specific secrets

EOF
}

OUTPUT_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            OUTPUT_FORMAT="json"
            shift
            ;;
        --minimal)
            OUTPUT_FORMAT="minimal"
            shift
            ;;
        --output)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                log_error "--output requires a file path"
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# ============================================================
# Utility Functions
# ============================================================

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

yaml_escape() {
    local value="$1"
    value=${value//\'/\'\'}
    printf '%s' "$value"
}

read_state_string_from_file() {
    local state_file="$1"
    local key="$2"
    local value=""

    [[ -f "$state_file" ]] || return 1

    if command -v jq &>/dev/null; then
        value=$(jq -r --arg key "$key" '.[$key] // empty' "$state_file" 2>/dev/null || true)
    elif command -v python3 &>/dev/null; then
        value=$(python3 - "$state_file" "$key" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
    value = data.get(sys.argv[2], "")
    if isinstance(value, str):
        print(value)
except Exception:
    pass
PY
        )
    else
        value=$(sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$state_file" 2>/dev/null | head -1 || true)
    fi

    [[ -n "$value" ]] || return 1
    printf '%s\n' "$value"
}

get_state_string() {
    local key="$1"
    read_state_string_from_file "$STATE_FILE" "$key"
}

read_target_user_from_state() {
    local state_file="$1"
    read_state_string_from_file "$state_file" "target_user"
}

script_acfs_home() {
    local candidate=""
    candidate=$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd) || return 1
    [[ "$(basename "$candidate")" == ".acfs" ]] || return 1
    printf '%s\n' "$candidate"
}

resolve_acfs_home() {
    if [[ -n "$_EXPORT_RESOLVED_ACFS_HOME" ]]; then
        printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
        return 0
    fi

    local candidate=""
    local detected_home=""
    local detected_user=""

    if [[ -n "$_EXPORT_EXPLICIT_ACFS_HOME" ]]; then
        _EXPORT_RESOLVED_ACFS_HOME="$_EXPORT_EXPLICIT_ACFS_HOME"
        printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
        return 0
    fi

    candidate=$(script_acfs_home 2>/dev/null || true)
    if [[ -n "$candidate" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
        _EXPORT_RESOLVED_ACFS_HOME="$candidate"
        printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -f "$ACFS_HOME/state.json" || -f "$ACFS_HOME/VERSION" || -d "$ACFS_HOME/onboard" ]]; then
        _EXPORT_RESOLVED_ACFS_HOME="$ACFS_HOME"
        printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
        return 0
    fi

    if [[ -n "${SUDO_USER:-}" ]]; then
        detected_home=$(home_for_user "$SUDO_USER" 2>/dev/null || true)
        candidate="${detected_home}/.acfs"
        if [[ -n "$detected_home" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
            _EXPORT_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    detected_user=$(read_target_user_from_state "$_EXPORT_SYSTEM_STATE_FILE" 2>/dev/null || true)
    if [[ -n "$detected_user" ]]; then
        detected_home=$(home_for_user "$detected_user" 2>/dev/null || true)
        candidate="${detected_home}/.acfs"
        if [[ -n "$detected_home" ]] && [[ -f "$candidate/state.json" || -f "$candidate/VERSION" || -d "$candidate/onboard" ]]; then
            _EXPORT_RESOLVED_ACFS_HOME="$candidate"
            printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
            return 0
        fi
    fi

    _EXPORT_RESOLVED_ACFS_HOME="$ACFS_HOME"
    printf '%s\n' "$_EXPORT_RESOLVED_ACFS_HOME"
}

resolve_state_file() {
    local candidate="${ACFS_HOME}/state.json"

    if [[ -f "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    if [[ -f "$_EXPORT_SYSTEM_STATE_FILE" ]]; then
        printf '%s\n' "$_EXPORT_SYSTEM_STATE_FILE"
        return 0
    fi

    printf '%s\n' "$candidate"
}

refresh_acfs_paths() {
    ACFS_HOME="$(resolve_acfs_home)"
    export ACFS_HOME
    STATE_FILE="$(resolve_state_file)"
    VERSION_FILE="$ACFS_HOME/VERSION"
}

get_target_user() {
    if [[ -n "${TARGET_USER:-}" ]]; then
        printf '%s\n' "$TARGET_USER"
        return 0
    fi

    read_target_user_from_state "$STATE_FILE" 2>/dev/null || \
        read_target_user_from_state "$_EXPORT_SYSTEM_STATE_FILE" 2>/dev/null
}

home_for_user() {
    local user="$1"
    local passwd_entry=""

    [[ -n "$user" ]] || return 1

    if command -v getent &>/dev/null; then
        passwd_entry=$(getent passwd "$user" 2>/dev/null || true)
        if [[ -n "$passwd_entry" ]]; then
            printf '%s\n' "$(printf '%s\n' "$passwd_entry" | cut -d: -f6)"
            return 0
        fi
    fi

    if [[ "$user" == "root" ]]; then
        echo "/root"
        return 0
    fi

    if [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "/home/$user"
        return 0
    fi

    return 1
}

prepare_target_context() {
    local detected_user=""
    local detected_home=""

    refresh_acfs_paths

    if detected_user=$(get_target_user 2>/dev/null || true); then
        if [[ -n "$detected_user" ]] && [[ -z "${TARGET_USER:-}" ]]; then
            export TARGET_USER="$detected_user"
        fi
    fi

    if [[ -z "${TARGET_HOME:-}" ]] && [[ -n "${TARGET_USER:-}" ]]; then
        detected_home=$(home_for_user "$TARGET_USER" 2>/dev/null || true)
        if [[ -n "$detected_home" ]]; then
            export TARGET_HOME="$detected_home"
        fi
    fi
}

augment_path_for_target_user() {
    local dir=""
    local target_home="${TARGET_HOME:-}"

    [[ -n "$target_home" ]] || return 0

    for dir in \
        "$target_home/.local/bin" \
        "$target_home/.bun/bin" \
        "$target_home/.cargo/bin" \
        "$target_home/go/bin" \
        "$target_home/.atuin/bin"; do
        case ":$PATH:" in
            *":$dir:"*) ;;
            *) export PATH="$dir:$PATH" ;;
        esac
    done
}

load_module_detection_support() {
    if [[ "${_ACFS_EXPORT_MODULE_SUPPORT_LOADED:-false}" == "true" ]]; then
        return 0
    fi

    if [[ ! -f "$INSTALL_HELPERS_FILE" ]] || [[ ! -f "$MANIFEST_INDEX_FILE" ]]; then
        return 1
    fi

    prepare_target_context
    augment_path_for_target_user

    # shellcheck source=/dev/null
    source "$INSTALL_HELPERS_FILE"
    # shellcheck source=/dev/null
    source "$MANIFEST_INDEX_FILE"
    _ACFS_EXPORT_MODULE_SUPPORT_LOADED=true
}

prepare_target_context
augment_path_for_target_user

# Get ACFS version
get_acfs_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE"
    else
        echo "unknown"
    fi
}

# Get tool version (returns empty string if not found)
get_tool_version() {
    local tool="$1"
    local version=""

    case "$tool" in
        rust|cargo)
            version=$(cargo --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        bun)
            version=$(bun --version 2>/dev/null || true)
            ;;
        uv)
            version=$(uv --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        go)
            version=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//' || true)
            ;;
        zsh)
            version=$(zsh --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        tmux)
            version=$(tmux -V 2>/dev/null | awk '{print $2}' || true)
            ;;
        nvim|neovim)
            version=$(nvim --version 2>/dev/null | head -1 | awk '{print $2}' | sed 's/v//' || true)
            ;;
        claude|claude-code)
            version=$(claude --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
            ;;
        codex)
            version=$(codex --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
            ;;
        gemini)
            version=$(gemini --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
            ;;
        zoxide)
            version=$(zoxide --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        atuin)
            version=$(atuin --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        fzf)
            version=$(fzf --version 2>/dev/null | awk '{print $1}' || true)
            ;;
        ripgrep|rg)
            version=$(rg --version 2>/dev/null | head -1 | awk '{print $2}' || true)
            ;;
        gh)
            version=$(gh --version 2>/dev/null | head -1 | awk '{print $3}' || true)
            ;;
        docker)
            version=$(docker --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
            ;;
        postgresql|psql)
            version=$(psql --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+' | head -1 || true)
            ;;
        ntm)
            # ntm uses "ntm version" not --version
            version=$(ntm version 2>/dev/null | awk '{print $3}' || true)
            ;;
        cass)
            version=$(cass --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        cm)
            version=$(cm --version 2>/dev/null | head -1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
            ;;
        bv)
            version=$(bv --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        br)
            version=$(br --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        dcg)
            # dcg doesn't have --version, check if binary exists
            if command -v dcg &>/dev/null; then
                version="installed"
            fi
            ;;
        slb)
            # slb uses "slb version" not --version, first line only
            version=$(slb version 2>/dev/null | head -1 | awk '{print $2}' || true)
            ;;
        caam)
            # caam uses "caam version" not --version
            version=$(caam version 2>/dev/null | awk '{print $2}' || true)
            ;;
        ubs)
            # ubs doesn't have typical version output, check if binary exists
            if command -v ubs &>/dev/null; then
                version="installed"
            fi
            ;;
        rch)
            version=$(rch --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        ms)
            version=$(ms --version 2>/dev/null | awk '{print $2}' || true)
            ;;
        ru)
            version=$(ru --version 2>/dev/null | awk '{print $3}' || true)
            ;;
        *)
            # Generic version check
            version=$($tool --version 2>/dev/null | head -1 | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
            ;;
    esac

    echo "${version:-}"
}

# Get mode from state.json
get_mode() {
    if [[ -f "$STATE_FILE" ]]; then
        if command -v jq &>/dev/null; then
            jq -r '.mode // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown"
        elif command -v python3 &>/dev/null; then
            python3 - "$STATE_FILE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
    value = data.get("mode", "unknown")
    print(value if value else "unknown")
except Exception:
    print("unknown")
PY
        else
            # Use sed instead of grep -oP for portability (works on macOS/BSD)
            sed -n 's/.*"mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" 2>/dev/null | head -1 || echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# Get installed modules from state.json
get_modules_from_state_file() {
    if [[ -f "$STATE_FILE" ]]; then
        if command -v jq &>/dev/null; then
            jq -r '.installed_modules // [] | .[]' "$STATE_FILE" 2>/dev/null || true
        elif command -v python3 &>/dev/null; then
            python3 - "$STATE_FILE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
    modules = data.get("installed_modules", [])
    if isinstance(modules, list):
        for module in modules:
            if module is not None:
                print(module)
except Exception:
    pass
PY
        fi
    fi
}

get_modules() {
    local module=""

    if load_module_detection_support; then
        for module in "${ACFS_MODULES_IN_ORDER[@]}"; do
            if acfs_module_is_installed "$module"; then
                printf '%s\n' "$module"
            fi
        done
        return 0
    fi

    get_modules_from_state_file
}

# ============================================================
# Output Generation
# ============================================================

generate_minimal() {
    # Just output module list, one per line
    get_modules
}

generate_yaml() {
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date)
    local acfs_version
    acfs_version=$(get_acfs_version)
    local mode
    mode=$(get_mode)

    cat << EOF
# ACFS Configuration Export
# Generated: $timestamp
# Hostname: $hostname
# ACFS Version: $acfs_version

settings:
  mode: '$(yaml_escape "$mode")'
  shell: '$(yaml_escape "${SHELL##*/}")'

modules:
EOF

    # List modules
    while IFS= read -r module; do
        [[ -n "$module" ]] && printf "  - '%s'\n" "$(yaml_escape "$module")"
    done < <(get_modules)

    echo ""
    echo "tools:"

    # Core tools
    local tools=(
        "rust" "bun" "uv" "go" "zsh" "tmux" "nvim"
        "zoxide" "atuin" "fzf" "ripgrep" "gh" "docker" "postgresql"
    )

    for tool in "${tools[@]}"; do
        local version
        version=$(get_tool_version "$tool")
        if [[ -n "$version" ]]; then
            printf "  %s:\n" "$tool"
            printf "    version: '%s'\n" "$(yaml_escape "$version")"
            echo "    installed: true"
        fi
    done

    echo ""
    echo "agents:"

    # AI agents
    local agents=("claude" "codex" "gemini")
    for agent in "${agents[@]}"; do
        local version
        version=$(get_tool_version "$agent")
        if [[ -n "$version" ]]; then
            printf "  %s:\n" "$agent"
            printf "    version: '%s'\n" "$(yaml_escape "$version")"
            echo "    installed: true"
        fi
    done

    echo ""
    echo "flywheel_stack:"

    # Flywheel tools
    local stack_tools=("ntm" "cass" "cm" "bv" "br" "dcg" "slb" "caam" "ubs" "rch" "ms" "ru")
    for tool in "${stack_tools[@]}"; do
        local version
        version=$(get_tool_version "$tool")
        if [[ -n "$version" ]]; then
            printf "  %s:\n" "$tool"
            printf "    version: '%s'\n" "$(yaml_escape "$version")"
            echo "    installed: true"
        fi
    done
}

generate_json() {
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date)
    local acfs_version
    acfs_version=$(get_acfs_version)
    local mode
    mode=$(get_mode)

    # Build JSON manually to avoid jq dependency for output
    cat << EOF
{
  "metadata": {
    "generated_at": "$(json_escape "$timestamp")",
    "hostname": "$(json_escape "$hostname")",
    "acfs_version": "$(json_escape "$acfs_version")"
  },
  "settings": {
    "mode": "$(json_escape "$mode")",
    "shell": "$(json_escape "${SHELL##*/}")"
  },
  "modules": [
EOF

    # Collect modules into array
    local modules=()
    while IFS= read -r module; do
        [[ -n "$module" ]] && modules+=("$module")
    done < <(get_modules)

    # Output modules as JSON array
    local first=true
    for module in "${modules[@]}"; do
        if [[ "$first" == "true" ]]; then
            printf '    "%s"\n' "$(json_escape "$module")"
            first=false
        else
            printf '    ,"%s"\n' "$(json_escape "$module")"
        fi
    done

    cat << 'EOF'
  ],
  "tools": {
EOF

    # Core tools
    local tools=("rust" "bun" "uv" "go" "zsh" "tmux" "nvim" "zoxide" "atuin" "fzf" "ripgrep" "gh" "docker" "postgresql")
    first=true
    for tool in "${tools[@]}"; do
        local version
        version=$(get_tool_version "$tool")
        if [[ -n "$version" ]]; then
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            printf '    "%s": { "version": "%s", "installed": true }' \
                "$(json_escape "$tool")" \
                "$(json_escape "$version")"
        fi
    done

    cat << 'EOF'

  },
  "agents": {
EOF

    # AI agents
    local agents=("claude" "codex" "gemini")
    first=true
    for agent in "${agents[@]}"; do
        local version
        version=$(get_tool_version "$agent")
        if [[ -n "$version" ]]; then
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            printf '    "%s": { "version": "%s", "installed": true }' \
                "$(json_escape "$agent")" \
                "$(json_escape "$version")"
        fi
    done

    cat << 'EOF'

  },
  "flywheel_stack": {
EOF

    # Flywheel tools
    local stack_tools=("ntm" "cass" "cm" "bv" "br" "dcg" "slb" "caam" "ubs" "rch" "ms" "ru")
    first=true
    for tool in "${stack_tools[@]}"; do
        local version
        version=$(get_tool_version "$tool")
        if [[ -n "$version" ]]; then
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            printf '    "%s": { "version": "%s", "installed": true }' \
                "$(json_escape "$tool")" \
                "$(json_escape "$version")"
        fi
    done

    cat << 'EOF'

  }
}
EOF
}

# ============================================================
# Main
# ============================================================

main() {
    local output

    case "$OUTPUT_FORMAT" in
        minimal)
            output=$(generate_minimal)
            ;;
        json)
            output=$(generate_json)
            ;;
        yaml|*)
            output=$(generate_yaml)
            ;;
    esac

    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$output" > "$OUTPUT_FILE"
        echo "Configuration exported to: $OUTPUT_FILE" >&2
    else
        echo "$output"
    fi
}

main "$@"
