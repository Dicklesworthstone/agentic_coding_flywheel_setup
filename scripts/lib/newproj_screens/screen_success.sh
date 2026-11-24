#!/usr/bin/env bash
# ============================================================
# ACFS newproj TUI Wizard - Success Screen
# Shows success message and next steps
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_SCREEN_SUCCESS_LOADED:-}" ]]; then
    return 0
fi
_ACFS_SCREEN_SUCCESS_LOADED=1

# Both the TUI and CLI source this screen. Keep project handoffs on the same
# repository-isolation contract as project creation, including standalone use.
# shellcheck source=../newproj_errors.sh
source "${BASH_SOURCE[0]%/*}/../newproj_errors.sh" || return 1

# ============================================================
# Screen: Success
# ============================================================

# Screen metadata
SCREEN_SUCCESS_ID="success"
SCREEN_SUCCESS_TITLE="Success"
SCREEN_SUCCESS_STEP=9

# Keep launch choices tied to cumulative installation intent. State parsing runs
# in a separate shell because the installer and wizard both define state_get.
# Never execute the generated catalogue; state.sh validates it as data.
_NEWPROJ_LAUNCH_SELECTION_MODE=invalid
_NEWPROJ_LAUNCH_INSTALL_MODE=invalid
_NEWPROJ_LAUNCH_HOME=""
_NEWPROJ_LAUNCH_USER=""
_NEWPROJ_LAUNCH_STATE=""
declare -ga _NEWPROJ_LAUNCH_MODULES=()
declare -ga _NEWPROJ_AGENT_COMMANDS=(claude codex agy opencode omp grok gemini pi)
declare -gA _NEWPROJ_AGENT_MODULES=(
    [claude]=agents.claude [codex]=agents.codex [agy]=agents.antigravity
    [opencode]=agents.opencode [omp]=agents.omp [grok]=agents.grok
    [gemini]=agents.gemini [pi]=stack.pi_agent_rust
)
declare -gA _NEWPROJ_AGENT_NAMES=(
    [claude]="Claude Code" [codex]="Codex" [agy]="Antigravity"
    [opencode]="OpenCode" [omp]="oh-my-pi" [grok]="Grok"
    [gemini]="Gemini CLI (legacy)" [pi]="Pi"
)
# Native robot-spawn flag suffix and response type. Pi is NTM's shipped agent
# plugin; older NTM builds must advertise its flag before it can be offered.
declare -gA _NEWPROJ_NTM_PROVIDERS=(
    [claude]=cc:claude [codex]=cod:codex [agy]=agy:antigravity
    [opencode]=oc:oc [omp]=omp:omp [grok]=grok:grok
    [gemini]=gmi:gemini [pi]=pi:pi
)

newproj_load_launch_selection() {
    _NEWPROJ_LAUNCH_SELECTION_MODE=invalid
    _NEWPROJ_LAUNCH_INSTALL_MODE=invalid
    _NEWPROJ_LAUNCH_HOME=""
    _NEWPROJ_LAUNCH_USER=""
    _NEWPROJ_LAUNCH_STATE=""
    _NEWPROJ_LAUNCH_MODULES=()
    local lib_dir parsed
    lib_dir=$(CDPATH='' cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P) || return 1
    if ! parsed=$(PATH=/usr/sbin:/usr/bin:/sbin:/bin "$BASH" --noprofile --norc -p -c '
        source "$1/state.sh" || exit 1
        selection_home=$(state_resolve_target_home) || exit 1
        selection_user="${TARGET_USER:-$(state_resolve_current_user)}"
        state_is_valid_username "$selection_user" || exit 1
        selection_file=$(state_get_file) || exit 1
        [[ "$selection_file" == /* && "$selection_file" != / && "$selection_file" != *[[:cntrl:]]* ]] || exit 1
        if [[ "$selection_file" == "$selection_home/.acfs/state.json" ]]; then
            state_load_module_selection "$selection_file" "$selection_home" "$selection_user" allow-legacy-identity || exit 1
        else
            state_load_module_selection "$selection_file" "$selection_home" "$selection_user" || exit 1
        fi
        state_validate_module_selection_catalog_file "$1/../generated/manifest_index.sh" || exit 1
        install_mode=${ACFS_STATE_INSTALL_MODE:-safe}
        if [[ ! -e "$selection_file" && ! -L "$selection_file" ]]; then
            install_mode=vibe
        fi
        printf "%s\n" "$ACFS_STATE_SELECTION_MODE" "$install_mode" "$selection_home" "$selection_user" "$selection_file"
        if [[ "$ACFS_STATE_SELECTION_MODE" == scoped ]]; then
            printf "%s\n" "${ACFS_STATE_SELECTED_MODULES[@]}"
        fi
    ' _ "$lib_dir"); then
        printf '%s\n' 'Cannot validate the installation selection. Run acfs doctor before launching agents.' >&2
        return 1
    fi
    local -a records=()
    mapfile -t records <<< "$parsed"
    case "${records[0]:-}" in
        legacy|scoped) _NEWPROJ_LAUNCH_SELECTION_MODE="${records[0]}" ;;
        *) return 1 ;;
    esac
    case "${records[1]:-}" in
        safe|vibe) _NEWPROJ_LAUNCH_INSTALL_MODE="${records[1]}" ;;
        *) return 1 ;;
    esac
    _NEWPROJ_LAUNCH_HOME="${records[2]:-}"
    _NEWPROJ_LAUNCH_USER="${records[3]:-}"
    _NEWPROJ_LAUNCH_STATE="${records[4]:-}"
    _NEWPROJ_LAUNCH_MODULES=("${records[@]:5}")
}

newproj_launch_module_selected() {
    local wanted="$1" module
    case "$_NEWPROJ_LAUNCH_SELECTION_MODE" in
        legacy) return 0 ;;
        scoped)
            for module in "${_NEWPROJ_LAUNCH_MODULES[@]}"; do
                [[ "$module" != "$wanted" ]] || return 0
            done
            return 1
            ;;
        *) return 2 ;;
    esac
}

newproj_agent_selected() {
    case "${1:-}" in
        claude|codex|agy|opencode|omp|grok|gemini|pi) ;;
        *) return 1 ;;
    esac
    local module="${_NEWPROJ_AGENT_MODULES[${1:-}]:-}"
    [[ -n "$module" ]] && newproj_launch_module_selected "$module"
}

newproj_agent_binary() {
    local command_name="$1" binary
    # Non-interactive Bash does not expand the login shell's agy alias. Use
    # the installed policy wrapper, and never fall back to the raw provider.
    [[ "$command_name" != agy ]] || command_name="agy-locked"
    binary=$(type -P -- "$command_name") || return 1
    # A relative PATH entry must keep referring to the same executable after
    # the launcher changes into the new project.
    [[ "$binary" == /* ]] || binary="$PWD/$binary"
    printf '%s\n' "$binary"
}

newproj_print_agent_next_steps() {
    newproj_load_launch_selection || return 1
    local agent command_name found=false
    for agent in "${_NEWPROJ_AGENT_COMMANDS[@]}"; do
        newproj_agent_selected "$agent" || continue
        if newproj_agent_binary "$agent" >/dev/null; then
            command_name="$agent"
            [[ "$agent" != agy ]] || command_name="agy-locked"
            printf '  %s  # Start %s\n' "$command_name" "${_NEWPROJ_AGENT_NAMES[$agent]}"
            found=true
        elif [[ "$_NEWPROJ_LAUNCH_SELECTION_MODE" == scoped ]]; then
            printf '  # %s is selected but unavailable; run acfs doctor.\n' "${_NEWPROJ_AGENT_NAMES[$agent]}"
        fi
    done
    if [[ "$found" != true ]]; then
        printf '%s\n' '  # No selected agent CLI is available. Run acfs doctor or install an agent you want to use.'
    fi
}

prepare_success_exec() {
    tui_cleanup
    finalize_logging 2>/dev/null || true
}

# Render the success screen
render_success_screen() {
    render_screen_header "Project Created!" "$SCREEN_SUCCESS_STEP" 9

    local project_name
    project_name=$(state_get "project_name")
    local project_dir
    project_dir=$(state_get "project_dir")
    local beads_initialized=false
    if [[ -d "$project_dir/.beads" ]]; then
        beads_initialized=true
    fi

    # Success banner
    if [[ "$TERM_HAS_UNICODE" == "true" ]]; then
        printf "%b\n" "${TUI_SUCCESS}"
        cat << 'BANNER'
    ╔══════════════════════════════════════════════════════╗
    ║                                                      ║
    ║       ✓ ✓ ✓   PROJECT CREATED SUCCESSFULLY   ✓ ✓ ✓  ║
    ║                                                      ║
    ╚══════════════════════════════════════════════════════╝
BANNER
        printf "%b\n" "${TUI_NC}"
    else
        echo ""
        printf "%b\n" "${TUI_SUCCESS}=== PROJECT CREATED SUCCESSFULLY ===${TUI_NC}"
        echo ""
    fi

    echo ""
    printf "%b\n" "Your new project ${TUI_PRIMARY}$project_name${TUI_NC} is ready!"
    echo ""

    # What was created
    printf "%b\n" "${TUI_BOLD}What was created:${TUI_NC}"
    draw_line 50

    printf "%b\n" "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} Project directory: $project_dir"
    printf "%b\n" "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} Git repository initialized"
    printf "%b\n" "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} README.md"
    printf "%b\n" "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} .gitignore"

    if [[ "$(state_get "enable_agents")" == "true" ]]; then
        printf "%b\n" "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} AGENTS.md for AI assistants"
    fi

    if [[ "$(state_get "enable_br")" == "true" && "$beads_initialized" == "true" ]]; then
        printf "%b\n" "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} Beads issue tracking (.beads/)"
    elif [[ "$(state_get "enable_br")" == "true" ]]; then
        printf "%b\n" "  ${TUI_WARNING}!${TUI_NC} Beads issue tracking requested but not initialized"
    fi

    if [[ "$(state_get "enable_claude")" == "true" ]]; then
        printf "%b\n" "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} Claude Code settings (.claude/)"
    fi

    if [[ "$(state_get "enable_ubsignore")" == "true" ]]; then
        printf "%b\n" "  ${TUI_SUCCESS}${BOX_CHECK}${TUI_NC} UBS ignore patterns (.ubsignore)"
    fi

    echo ""

    # Next steps
    printf "%b\n" "${TUI_BOLD}Next steps:${TUI_NC}"
    draw_line 50
    echo ""

    echo "  1. Navigate to your project:"
    printf "%b\n" "     ${TUI_CYAN}cd $project_dir${TUI_NC}"
    echo ""

    echo "  2. Start coding with an installed agent:"
    if ! newproj_print_agent_next_steps; then
        echo "     Repair the saved installation selection with acfs doctor."
    fi
    echo ""

    if [[ "$(state_get "enable_br")" == "true" && "$beads_initialized" == "true" ]]; then
        echo "  3. Create your first task:"
        printf "%b\n" "     ${TUI_CYAN}br create --title=\"First feature\" --type=feature${TUI_NC}"
        echo ""
    elif [[ "$(state_get "enable_br")" == "true" ]]; then
        echo "  3. Finish enabling Beads (optional):"
        printf "%b\n" "     ${TUI_CYAN}br init${TUI_NC}"
        echo ""
    fi

    echo "  For help, run:"
    printf "%b\n" "     ${TUI_CYAN}acfs help${TUI_NC}"
    echo ""

    draw_line 50
    echo ""
    echo "Options:"
    echo "  [Enter/o]   Open project in shell"
    if [[ "$_NEWPROJ_LAUNCH_SELECTION_MODE" != invalid ]]; then
        echo "  [a]         Open in a coding agent"
        if newproj_agent_selected claude && newproj_agent_binary claude >/dev/null; then
            echo "  [c]         Open in Claude Code"
        fi
        if newproj_launch_module_selected stack.ntm; then
            echo "  [n]         Start a multi-agent NTM workspace"
            if newproj_launch_module_selected stack.beads_rust && newproj_launch_module_selected stack.beads_viewer; then
                echo "  [w]         Start agents and hand off ready Beads tasks"
            fi
        fi
    fi
    echo "  [q]         Exit wizard"
}

# Open project in new shell
open_in_shell() {
    local project_dir
    project_dir=$(newproj_ntm_project) || return 1

    local shell_bin="${SHELL:-}"
    if [[ -n "$shell_bin" ]]; then
        shell_bin=$(type -P -- "$shell_bin" 2>/dev/null || true)
    fi
    if [[ -z "$shell_bin" ]]; then
        shell_bin="$(type -P zsh 2>/dev/null || type -P bash 2>/dev/null || true)"
    fi
    if [[ -z "$shell_bin" ]]; then
        echo ""
        printf "%b\n" "${TUI_WARNING}No interactive shell found in PATH${TUI_NC}"
        return 1
    fi
    [[ "$shell_bin" == /* ]] || shell_bin="$PWD/$shell_bin"

    echo ""
    printf "%b\n" "${TUI_PRIMARY}Opening project shell...${TUI_NC}"
    echo ""
    prepare_success_exec
    newproj_enter_launch_project "$project_dir" || return 1
    exec "$shell_bin" -i
}

# Direct launch works without NTM/tmux. A provider choice never adds permission
# bypass flags, starts login, sends a task, or changes global agent settings.
open_in_agent() {
    local agent="${1:-}" project_dir binary answer index=0
    local -a available=()
    [[ $# -le 1 ]] || return 1
    project_dir=$(newproj_ntm_project) || return 1
    newproj_load_launch_selection || return 1
    if [[ -z "$agent" ]]; then
        for agent in "${_NEWPROJ_AGENT_COMMANDS[@]}"; do
            if newproj_agent_selected "$agent" && newproj_agent_binary "$agent" >/dev/null; then
                available+=("$agent")
            fi
        done
        if [[ ${#available[@]} -eq 0 ]]; then
            echo "No selected agent CLI is available. Run acfs doctor before launching an agent." >&2
            return 1
        fi
        agent="${available[0]}"
        if [[ ${#available[@]} -gt 1 ]]; then
            echo "Choose the agent to open in this project:"
            for agent in "${available[@]}"; do
                index=$((index + 1))
                printf '  [%s] %s (%s)\n' "$index" "${_NEWPROJ_AGENT_NAMES[$agent]}" "$agent"
            done
            read -r -p "Agent [1]: " answer || return 1
            answer="${answer:-1}"
            if [[ ! "$answer" =~ ^[1-9][0-9]?$ ]] || ((answer > ${#available[@]})); then
                echo "Choose one of the listed agent numbers." >&2
                return 1
            fi
            agent="${available[$((answer - 1))]}"
        fi
    fi
    # Re-read after an interactive choice: a changed or damaged checkpoint is
    # not permission to launch using stale defaults.
    newproj_load_launch_selection || return 1
    if ! newproj_agent_selected "$agent"; then
        echo "This agent is not selected for this installation." >&2
        return 1
    fi
    binary=$(newproj_agent_binary "$agent") || {
        echo "The selected agent CLI is unavailable. Run acfs doctor before launching it." >&2
        return 1
    }
    printf '\nOpening %s in %s...\n' "${_NEWPROJ_AGENT_NAMES[$agent]}" "$project_dir"
    prepare_success_exec
    newproj_enter_launch_project "$project_dir" || return 1
    exec "$binary"
}

# Enter the chosen project with no inherited Git repository/index/config or
# Beads database/cache selectors. Account configuration and authentication stay
# intact. Exec handoffs call this in the replacing shell; tool probes use the
# subshell below so the wizard's own environment remains unchanged.
newproj_enter_launch_project() {
    local project_dir="$1"
    newproj_clear_project_environment || return 1
    cd -- "$project_dir" || return 1
    export BEADS_DIR="$project_dir/.beads"
}

# Canonicalize the exact project selected by the wizard, not NTM's default
# projects directory. Never use project names or paths as shell source.
newproj_ntm_project() {
    local project_dir
    project_dir=$(state_get "project_dir") || return 1
    if [[ -z "$project_dir" || "$project_dir" == *[[:cntrl:]]* || ! -d "$project_dir" ]]; then
        echo "The project directory is missing or invalid; no agents were started." >&2
        return 1
    fi
    (CDPATH='' cd -P -- "$project_dir" && pwd -P)
}

# Inspect the installed version, including its registered plugin flags. Match
# flag declarations rather than examples or similarly named options in help.
newproj_ntm_has_flag() {
    local help="$1" flag="$2"
    local pattern="(^|"$'\n'")[[:space:]]*--${flag}([=[:space:]]|$)"
    [[ "$help" =~ $pattern ]]
}

newproj_ntm_help() {
    local help tool binary
    local -a binaries=()
    for tool in timeout sleep cat ntm; do
        binary=$(type -P -- "$tool" 2>/dev/null || true)
        if [[ -z "$binary" && "$tool" == timeout ]]; then
            binary=$(type -P gtimeout 2>/dev/null || true)
        fi
        if [[ -z "$binary" ]]; then
            printf 'Missing %s for bounded NTM capability checks. Run acfs doctor or open an agent directly.\n' "$tool" >&2
            return 1
        fi
        [[ "$binary" == /* ]] || binary="$PWD/$binary"
        binaries+=("$binary")
    done
    # Keep a guardian alive through TERM so a wrapper cannot exit early and
    # leave a descendant holding the captured output pipe past the deadline.
    if ! help=$(newproj_ntm_project_command "$1" "${binaries[0]}" --kill-after=1 -- 5 \
        "$BASH" --noprofile --norc -p -c '
            set +e
            set +m
            set -o pipefail
            guardian_sleep=$1
            guardian_cat=$2
            shift 2
            trap '\''trap "" HUP INT QUIT TERM; while :; do "$guardian_sleep" 1; done'\'' HUP INT QUIT TERM
            "$@" 2>&1 | "$guardian_cat" &
            probe_pid=$!
            probe_status=0
            wait "$probe_pid" || probe_status=$?
            exit "$probe_status"
        ' _ "${binaries[1]}" "${binaries[2]}" "${binaries[3]}" --help </dev/null); then
        [[ -z "$help" ]] || printf '%s\n' "$help" >&2
        echo "Cannot inspect NTM launch support. Run acfs doctor or open an agent directly." >&2
        return 1
    fi
    printf '%s\n' "$help"
}

# Prepare only recognized NTM defaults. The helper retains the original TOML
# and binds every managed built-in provider launch to the accepted account/checkpoint,
# including later ntm add/restart commands from an existing tmux server.
# Pi retains its plugin and is checked for this guided launch only.
# "check" is read-only; "configure" is called only after launch consent.
newproj_ntm_policy() {
    local operation="$1" project_dir="$2"
    shift 2
    local -a counts=("$@") arguments=()
    local helper python_bin="" candidate agent binary index ntm_binary
    helper=$(CDPATH='' cd -- "${BASH_SOURCE[0]%/*}/.." && pwd -P) || return 1
    helper="$helper/ntm_policy.py"
    if [[ ! -f "$helper" || ${#counts[@]} -ne ${#_NEWPROJ_AGENT_COMMANDS[@]} ]]; then
        echo "NTM policy support is unavailable. Run acfs update or open an agent directly." >&2
        return 1
    fi
    for candidate in /usr/bin/python3 /usr/local/bin/python3 /opt/homebrew/bin/python3; do
        if [[ -f "$candidate" && -x "$candidate" ]] && "$candidate" -I "$helper" parser >/dev/null 2>&1; then
            python_bin="$candidate"
            break
        fi
    done
    if [[ -z "$python_bin" ]]; then
        echo "NTM policy setup needs Python 3.11+ or an installed tomli parser. Open an agent directly until it is available." >&2
        return 1
    fi
    ntm_binary=$(newproj_agent_binary ntm) || return 1
    arguments=("$operation" --project "$project_dir" --state-file "$_NEWPROJ_LAUNCH_STATE"
        --target-home "$_NEWPROJ_LAUNCH_HOME" --target-user "$_NEWPROJ_LAUNCH_USER" --ntm-binary "$ntm_binary")
    for index in "${!_NEWPROJ_AGENT_COMMANDS[@]}"; do
        agent="${_NEWPROJ_AGENT_COMMANDS[$index]}"
        binary=$(newproj_agent_binary "$agent" 2>/dev/null || true)
        arguments+=(--binary "$agent=$binary")
        if ((counts[index] > 0)); then
            arguments+=(--agent "$agent")
        fi
    done
    newproj_ntm_project_command "$project_dir" "$python_bin" -I "$helper" "${arguments[@]}"
}

# Counts follow _NEWPROJ_AGENT_COMMANDS. Validate before either task creation or
# agent launch can mutate the project; no count is evaluated as shell arithmetic
# until it has matched the single-digit range.
newproj_validate_ntm_request() {
    if [[ $# -ne $((${#_NEWPROJ_AGENT_COMMANDS[@]} + 3)) ]]; then
        echo "A count for each workspace provider is required." >&2
        return 1
    fi
    local project_dir="$1" session="$2" work="$3"
    shift 3
    local -a counts=("$@") flags=(robot-spawn spawn-dir spawn-safety robot-format)
    local count total=0 tool index agent flag help
    case "$work" in
        true) flags+=(spawn-assign-work) ;;
        false) ;;
        *) echo "Work assignment requires an explicit true/false choice." >&2; return 1 ;;
    esac
    if [[ ! "$session" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$ ]]; then
        echo "Use a session name of 1-64 letters, numbers, underscores, or hyphens." >&2
        return 1
    fi
    for count in "${counts[@]}"; do
        if [[ ! "$count" =~ ^[0-4]$ ]]; then
            echo "Choose 0-4 agents per provider, with 1-8 agents in total." >&2
            return 1
        fi
        total=$((total + count))
    done
    if ((total < 1 || total > 8)); then
        echo "Choose 1-8 agents in total." >&2
        return 1
    fi
    if [[ "$project_dir" != /* || "$project_dir" == / || "$project_dir" == *[[:cntrl:]]* || ! -d "$project_dir" ]]; then
        echo "An existing absolute project directory is required." >&2
        return 1
    fi
    newproj_load_launch_selection || return 1
    if ! newproj_launch_module_selected stack.ntm; then
        echo "NTM is not selected for this installation. Open an agent directly instead." >&2
        return 1
    fi
    for index in "${!counts[@]}"; do
        ((counts[index] > 0)) || continue
        agent="${_NEWPROJ_AGENT_COMMANDS[$index]}"
        if ! newproj_agent_selected "$agent"; then
            echo "An agent in this mix is not selected for this installation." >&2
            return 1
        fi
    done
    for tool in ntm tmux jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'Missing %s. Run acfs doctor before starting a workspace.\n' "$tool" >&2
            return 1
        fi
    done
    for index in "${!counts[@]}"; do
        ((counts[index] > 0)) || continue
        agent="${_NEWPROJ_AGENT_COMMANDS[$index]}"
        if ! newproj_agent_binary "$agent" >/dev/null; then
            echo "A selected agent CLI is missing; adjust the mix or run acfs doctor." >&2
            return 1
        fi
        flags+=("spawn-${_NEWPROJ_NTM_PROVIDERS[$agent]%%:*}")
    done
    help=$(newproj_ntm_help "$project_dir") || return 1
    for flag in "${flags[@]}"; do
        if ! newproj_ntm_has_flag "$help" "$flag"; then
            printf 'Installed NTM does not support --%s. Update NTM or open an agent directly.\n' "$flag" >&2
            return 1
        fi
    done
    newproj_ntm_policy check "$project_dir" "${counts[@]}" || return 1
}

# Scope both Beads and NTM's child processes to this project. A terminal can
# inherit another repository's database overrides; changing cwd alone is not
# sufficient. The subshell preserves the caller's environment and directory.
newproj_ntm_project_command() (
    local project_dir="$1"
    shift
    newproj_enter_launch_project "$project_dir" || return 1
    "$@"
)

# Read the local ready queue before asking for permission to assign work. NTM
# remains responsible for fresh triage, claims, reservations and safe dispatch.
newproj_ntm_ready_work() {
    local project_dir="$1" ready
    newproj_load_launch_selection || return 1
    if ! newproj_launch_module_selected stack.beads_rust || ! newproj_launch_module_selected stack.beads_viewer; then
        echo "Beads Rust and Beads Viewer are not selected for this installation. Start a workspace without task handoff." >&2
        return 1
    fi
    if [[ ! -d "$project_dir/.beads" || -L "$project_dir/.beads" ]]; then
        echo "This project needs its own initialized .beads directory. Run br init first." >&2
        return 1
    fi
    if ! command -v br >/dev/null 2>&1 || ! command -v bv >/dev/null 2>&1; then
        echo "Beads Rust (br) and Beads Viewer (bv) are required for task handoff." >&2
        return 1
    fi
    ready=$(newproj_ntm_project_command "$project_dir" br ready --json) || {
        echo "Could not read ready tasks; no work was assigned." >&2
        return 1
    }
    if ! jq -e -s '
        length == 1 and (.[0] | type == "array" and all(.[];
            type == "object" and
            (.id | type == "string" and test("^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$")) and
            (.title | type == "string")))
    ' >/dev/null 2>&1 <<< "$ready"; then
        echo "Beads returned an invalid ready queue; no work was assigned." >&2
        return 1
    fi
    printf '%s\n' "$ready"
}

# Returns a validated session name. Ordinary launch never sends a task. Work
# mode delegates dispatch to NTM, never raw tmux send-keys or a shell broadcast.
newproj_start_ntm() {
    newproj_validate_ntm_request "$@" || return 1
    local project_dir="$1" session="$2" work="$3"
    shift 3
    local -a counts=("$@") spawn_args=()
    local response status=0 total=0 delivered assignments index agent count number ntm_binary ntm_config
    ntm_config=$(newproj_ntm_policy configure "$project_dir" "${counts[@]}") || return 1
    local expected_types='["user"'
    for index in "${!counts[@]}"; do
        count="${counts[$index]}"
        ((count > 0)) || continue
        agent="${_NEWPROJ_AGENT_COMMANDS[$index]}"
        # Omitted robot-spawn providers default to zero. Do not pass a new
        # provider's flag with =0 to an older NTM that does not understand it.
        spawn_args+=("--spawn-${_NEWPROJ_NTM_PROVIDERS[$agent]%%:*}=$count")
        total=$((total + count))
        for ((number = 0; number < count; number++)); do
            expected_types+=",\"${_NEWPROJ_NTM_PROVIDERS[$agent]#*:}\""
        done
    done
    expected_types+=']'
    if [[ "$work" == true ]]; then
        newproj_ntm_ready_work "$project_dir" >/dev/null || return 1
        spawn_args+=(--spawn-assign-work)
    fi
    ntm_binary=$(newproj_agent_binary ntm) || return 1
    # --spawn-safety delegates the create-only check to NTM. Never retry without
    # it: an existing session may belong to another project or contain live work.
    response=$(NTM_CONFIG="$ntm_config" HOME="$_NEWPROJ_LAUNCH_HOME" \
        newproj_ntm_project_command "$project_dir" "$ntm_binary" "--robot-spawn=$session" \
        "--spawn-dir=$project_dir" --spawn-safety --robot-format=json \
        "${spawn_args[@]}") || status=$?
    # NTM includes the operator's shell as one type=user entry in agents.
    # Confirm that shell plus the exact provider mix, not only the total panes.
    if ((status != 0)) || ! jq -e -s --arg session "$session" --arg dir "$project_dir" \
        --argjson count "$total" --argjson types "$expected_types" '
        length == 1 and (.[0] |
        type == "object" and .success == true and .session == $session and
        .working_dir == $dir and (.dry_run != true) and
        (.agents | type == "array" and length == ($count + 1) and
            all(.[]; type == "object" and ((.error // "") == "")) and
            ((map(.type) | sort) == ($types | sort))) and
        ((.error // "") == ""))
    ' >/dev/null 2>&1 <<< "$response"; then
        echo "NTM did not confirm the requested workspace. No automatic retry or cleanup was attempted." >&2
        echo "Inspect ntm list and acfs doctor; a partial or existing session may need attention." >&2
        return 1
    fi
    if [[ "$work" == true ]]; then
        # NTM omits its empty assignment list (omitempty). That is zero
        # confirmed deliveries, not malformed output or proof of started work.
        if ! jq -e '(if has("assignments") then .assignments else [] end) |
            type == "array" and all(.[];
            type == "object" and (.claimed | type == "boolean") and
            (.prompt_sent | type == "boolean"))' >/dev/null 2>&1 <<< "$response"; then
            echo "Workspace started, but task handoff was not confirmed. Inspect NTM before retrying." >&2
            return 1
        fi
        delivered=$(jq '[(.assignments // [])[] | select(.claimed == true and .prompt_sent == true)] | length' <<< "$response")
        assignments=$(jq '(.assignments // []) | length' <<< "$response")
        printf 'NTM confirmed %s delivered task(s) from %s assignment(s).\n' "$delivered" "$assignments" >&2
        if ((delivered == 0 || delivered < assignments)); then
            echo "Some or all work was not delivered. Check agent sign-in and NTM assignments before retrying." >&2
        fi
    fi
    printf '%s\n' "$session"
}

open_in_ntm() {
    local project_dir project_name session answer agent index help ntm_binary ntm_config
    local -a counts=() available_indices=()
    local work="${1:-false}" ready task_title="" created_task=""
    [[ "$work" == true || "$work" == false ]] || return 1
    project_dir=$(newproj_ntm_project) || return 1
    project_name=$(state_get "project_name") || return 1
    newproj_load_launch_selection || return 1
    if ! newproj_launch_module_selected stack.ntm; then
        echo "NTM is not selected for this installation. Open an agent directly instead." >&2
        return 1
    fi
    for answer in ntm tmux jq; do
        if ! command -v "$answer" >/dev/null 2>&1; then
            printf 'Missing %s. Run acfs doctor before starting a workspace.\n' "$answer" >&2
            return 1
        fi
    done
    help=$(newproj_ntm_help "$project_dir") || return 1
    for index in "${!_NEWPROJ_AGENT_COMMANDS[@]}"; do
        counts+=(0)
        agent="${_NEWPROJ_AGENT_COMMANDS[$index]}"
        newproj_agent_selected "$agent" && newproj_agent_binary "$agent" >/dev/null || continue
        if ! newproj_ntm_has_flag "$help" "spawn-${_NEWPROJ_NTM_PROVIDERS[$agent]%%:*}"; then
            printf '%s is selected, but this NTM cannot launch it. Update NTM or open it directly.\n' "${_NEWPROJ_AGENT_NAMES[$agent]}" >&2
            continue
        fi
        counts[index]=1
        available_indices+=("$index")
    done
    if [[ ${#available_indices[@]} -eq 0 ]]; then
        echo "No selected agent is available for this NTM. Run acfs doctor, update NTM, or open an agent directly." >&2
        return 1
    fi
    # Even a single-provider installation can start a useful two-agent workspace.
    if [[ ${#available_indices[@]} -eq 1 ]]; then
        counts[available_indices[0]]=2
    fi
    session="acfs-${project_name:0:48}"
    printf '\nProject: %s\n' "$project_dir"
    echo "Start separate agent panes plus your own shell in a persistent tmux session."
    echo "Installed does not mean authenticated. Sign in inside each agent as needed."
    echo "Built-in NTM provider defaults will follow your saved Safe/Vibe mode on future launches."
    echo "Your other NTM settings are preserved; custom agent commands are checked before launch."
    for index in "${available_indices[@]}"; do
        if [[ "${_NEWPROJ_AGENT_COMMANDS[$index]}" == pi ]]; then
            echo "Pi keeps its own plugin settings; ACFS checks its selection for this guided launch."
        fi
    done
    echo "Agents may incur provider charges."
    if [[ "$work" == true ]]; then
        echo "Work mode lets NTM claim ready Beads tasks and send prompts to agents."
    else
        echo "ACFS will not send a task or enable automatic work assignment."
    fi
    read -r -p "Session name [$session]: " answer || return 1
    session="${answer:-$session}"
    for index in "${available_indices[@]}"; do
        agent="${_NEWPROJ_AGENT_COMMANDS[$index]}"
        read -r -p "${_NEWPROJ_AGENT_NAMES[$agent]} agents, 0-4 [${counts[$index]}]: " answer || return 1
        counts[index]="${answer:-${counts[$index]}}"
    done
    printf '\nSession: %s\n' "$session"
    for index in "${available_indices[@]}"; do
        agent="${_NEWPROJ_AGENT_COMMANDS[$index]}"
        printf '%s: %s\n' "${_NEWPROJ_AGENT_NAMES[$agent]}" "${counts[$index]}"
    done
    newproj_validate_ntm_request "$project_dir" "$session" "$work" "${counts[@]}" || return 1
    if [[ "$work" == true ]]; then
        ready=$(newproj_ntm_ready_work "$project_dir") || return 1
        if [[ "$(jq 'length' <<< "$ready")" == 0 ]]; then
            echo "No tasks are ready. Enter a concrete first task, or leave blank to cancel."
            read -r -p "First task: " task_title || return 1
            if [[ -z "${task_title//[[:space:]]/}" || ${#task_title} -gt 512 || "$task_title" == *[[:cntrl:]]* ]]; then
                echo "A nonblank task title of at most 512 characters is required." >&2
                return 1
            fi
            printf 'Will create a priority-2 task: %s\n' "$task_title"
        else
            echo "Ready task preview (up to eight; NTM will recheck the queue before claiming):"
            jq -r '.[:8][] | "  \(.id | @json): \(.title | @json)"' <<< "$ready"
        fi
        echo "Consent covers NTM assigning currently ready tasks, not only this preview."
        echo "Tasks, claims and sessions are preserved if launch or prompt delivery fails."
    fi
    read -r -p "Start these agents? Type yes to continue: " answer || return 1
    if [[ "$answer" != yes ]]; then
        echo "Workspace launch cancelled; your project is unchanged."
        return 1
    fi
    # Selection and the installed NTM may change during the prompts. Recheck
    # before creating a first task, then the spawn path checks again itself.
    newproj_validate_ntm_request "$project_dir" "$session" "$work" "${counts[@]}" || return 1
    ntm_config=$(newproj_ntm_policy configure "$project_dir" "${counts[@]}") || return 1
    if [[ -n "$task_title" ]]; then
        newproj_ntm_ready_work "$project_dir" >/dev/null || return 1
        # --silent is br's single-ID output contract. A title stays one argument,
        # including quotes or shell syntax. Never recreate automatically on error.
        if ! created_task=$(newproj_ntm_project_command "$project_dir" br create "--title=$task_title" --type=task --priority=2 --silent) ||
           [[ ! "$created_task" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$ ]]; then
            echo "Task creation was not confirmed. Inspect br list before retrying; existing work was preserved." >&2
            return 1
        fi
        printf 'Created task %s. It remains in Beads even if workspace launch fails.\n' "$created_task"
    fi
    if ! session=$(NTM_CONFIG="$ntm_config" newproj_start_ntm "$project_dir" "$session" "$work" "${counts[@]}"); then
        return 1
    fi
    ntm_binary=$(newproj_agent_binary ntm) || return 1
    printf '\nWorkspace started. Reconnect later with: NTM_CONFIG=%q ntm attach %q\n' "$ntm_config" "$session"
    echo "Use this same NTM_CONFIG when adding or restarting agents for this workspace."
    echo "Detach with Ctrl-b then d. Agents keep running after you disconnect."
    prepare_success_exec
    newproj_enter_launch_project "$project_dir" || return 1
    export NTM_CONFIG="$ntm_config" HOME="$_NEWPROJ_LAUNCH_HOME"
    exec "$ntm_binary" attach "$session"
}

# Handle input for success screen
handle_success_input() {
    while true; do
        render_success_screen

        local key
        # EOF is not consent to open a shell or launch agents.
        read -rsn1 key || return 0

        case "$key" in
            ''|'o'|'O')
                # Open in shell
                log_input "success" "open_shell"
                if open_in_shell; then
                    return 0
                fi
                ;;
            'c'|'C')
                # Open in Claude Code
                log_input "success" "open_claude"
                if open_in_agent claude; then
                    return 0
                fi
                ;;
            'a'|'A')
                log_input "success" "open_agent"
                if open_in_agent; then
                    return 0
                fi
                ;;
            'n'|'N')
                log_input "success" "open_ntm"
                if open_in_ntm; then
                    return 0
                fi
                echo "Press any key to return to the project menu."
                read -rsn1 key || return 0
                ;;
            'w'|'W')
                log_input "success" "open_ntm_work"
                if open_in_ntm true; then
                    return 0
                fi
                echo "Press any key to return to the project menu."
                read -rsn1 key || return 0
                ;;
            'q'|'Q'|$'\e')
                # Quit
                log_input "success" "quit"
                return 0
                ;;
        esac
    done
}

# Run the success screen
run_success_screen() {
    log_screen "ENTER" "success"

    handle_success_input

    # Clean up
    tui_cleanup
    finalize_logging 2>/dev/null || true

    return 0
}
