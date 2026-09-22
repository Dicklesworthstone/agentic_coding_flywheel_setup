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

# ============================================================
# Screen: Success
# ============================================================

# Screen metadata
SCREEN_SUCCESS_ID="success"
SCREEN_SUCCESS_TITLE="Success"
SCREEN_SUCCESS_STEP=9

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

    echo "  2. Start coding with Claude Code:"
    printf "%b\n" "     ${TUI_CYAN}claude${TUI_NC}"
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
    echo "  [c]         Open in Claude Code"
    echo "  [n]         Start a multi-agent NTM workspace"
    echo "  [w]         Start agents and hand off ready Beads tasks"
    echo "  [q]         Exit wizard"
}

# Open project in new shell
open_in_shell() {
    local project_dir
    project_dir=$(state_get "project_dir")

    if [[ ! -d "$project_dir" ]]; then
        echo ""
        printf "%b\n" "${TUI_WARNING}Project directory no longer exists: $project_dir${TUI_NC}"
        return 1
    fi

    local shell_bin="${SHELL:-}"
    if [[ -z "$shell_bin" ]] || ! command -v "$shell_bin" &>/dev/null; then
        shell_bin="$(command -v zsh 2>/dev/null || command -v bash 2>/dev/null || true)"
    fi
    if [[ -z "$shell_bin" ]]; then
        echo ""
        printf "%b\n" "${TUI_WARNING}No interactive shell found in PATH${TUI_NC}"
        return 1
    fi

    echo ""
    printf "%b\n" "${TUI_PRIMARY}Opening project shell...${TUI_NC}"
    echo ""
    prepare_success_exec
    cd "$project_dir" || return 1
    exec "$shell_bin" -i
}

# Open project in Claude Code
open_in_claude() {
    local project_dir
    project_dir=$(state_get "project_dir")

    if [[ ! -d "$project_dir" ]]; then
        echo ""
        printf "%b\n" "${TUI_WARNING}Project directory no longer exists: $project_dir${TUI_NC}"
        return 1
    fi

    if ! command -v claude &>/dev/null; then
        echo ""
        printf "%b\n" "${TUI_WARNING}Claude Code not found in PATH${TUI_NC}"
        echo "Run manually:"
        printf "%b\n" "  ${TUI_CYAN}cd $project_dir && claude${TUI_NC}"
        return 1
    fi

    echo ""
    printf "%b\n" "${TUI_PRIMARY}Opening in Claude Code...${TUI_NC}"
    prepare_success_exec
    cd "$project_dir" || return 1
    exec claude
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

# Validate before either task creation or agent launch can mutate the project.
newproj_validate_ntm_request() {
    local project_dir="$1" session="$2" cc="$3" cod="$4" agy="$5"
    local count total=0 tool
    if [[ ! "$session" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$ ]]; then
        echo "Use a session name of 1-64 letters, numbers, underscores, or hyphens." >&2
        return 1
    fi
    for count in "$cc" "$cod" "$agy"; do
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
    for tool in ntm tmux jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'Missing %s. Run acfs doctor before starting a workspace.\n' "$tool" >&2
            return 1
        fi
    done
    if { ((cc > 0)) && ! command -v claude >/dev/null 2>&1; } ||
       { ((cod > 0)) && ! command -v codex >/dev/null 2>&1; } ||
       { ((agy > 0)) && ! command -v agy >/dev/null 2>&1; }; then
        echo "A selected agent CLI is missing; adjust the mix or run acfs doctor." >&2
        return 1
    fi
}

# Scope both Beads and NTM's child processes to this project. A terminal can
# inherit another repository's database overrides; changing cwd alone is not
# sufficient. The subshell preserves the caller's environment and directory.
newproj_ntm_project_command() (
    local project_dir="$1"
    shift
    unset BEADS_DB BD_DB BD_DATABASE BEADS_JSONL
    export BEADS_DIR="$project_dir/.beads"
    cd -- "$project_dir" || return 1
    "$@"
)

# Read the local ready queue before asking for permission to assign work. NTM
# remains responsible for fresh triage, claims, reservations and safe dispatch.
newproj_ntm_ready_work() {
    local project_dir="$1" ready
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
    local project_dir="$1" session="$2" cc="$3" cod="$4" agy="$5" work="${6:-false}"
    local response status=0 total delivered assignments
    newproj_validate_ntm_request "$project_dir" "$session" "$cc" "$cod" "$agy" || return 1
    total=$((cc + cod + agy))
    local -a work_args=()
    case "$work" in
        true)
            newproj_ntm_ready_work "$project_dir" >/dev/null || return 1
            work_args=(--spawn-assign-work)
            ;;
        false) ;;
        *) echo "Work assignment requires an explicit true/false choice." >&2; return 1 ;;
    esac
    # --spawn-safety delegates the create-only check to NTM. Never retry without
    # it: an existing session may belong to another project or contain live work.
    response=$(newproj_ntm_project_command "$project_dir" ntm "--robot-spawn=$session" \
        "--spawn-dir=$project_dir" --spawn-safety --robot-format=json \
        "--spawn-cc=$cc" "--spawn-cod=$cod" "--spawn-agy=$agy" "${work_args[@]}") || status=$?
    if ((status != 0)) || ! jq -e -s --arg session "$session" --arg dir "$project_dir" \
        --argjson count "$total" '
        length == 1 and (.[0] |
        type == "object" and .success == true and .session == $session and
        .working_dir == $dir and (.dry_run != true) and
        (.agents | type == "array" and length == $count and
            all(.[]; type == "object" and ((.error // "") == ""))) and
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
    local project_dir project_name session answer cc=0 cod=0 agy=0 available=0
    local work="${1:-false}" ready task_title="" created_task=""
    [[ "$work" == true || "$work" == false ]] || return 1
    project_dir=$(newproj_ntm_project) || return 1
    project_name=$(state_get "project_name") || return 1
    for answer in ntm tmux jq; do
        if ! command -v "$answer" >/dev/null 2>&1; then
            printf 'Missing %s. Run acfs doctor before starting a workspace.\n' "$answer" >&2
            return 1
        fi
    done
    command -v claude >/dev/null 2>&1 && { cc=1; available=$((available + 1)); }
    command -v codex >/dev/null 2>&1 && { cod=1; available=$((available + 1)); }
    command -v agy >/dev/null 2>&1 && { agy=1; available=$((available + 1)); }
    if ((available == 0)); then
        echo "Install Claude Code, Codex, or Antigravity before starting a workspace." >&2
        return 1
    fi
    # Even a single-provider installation can start a useful two-agent workspace.
    if ((available == 1)); then
        ((cc > 0)) && cc=2
        ((cod > 0)) && cod=2
        ((agy > 0)) && agy=2
    fi
    session="acfs-${project_name:0:48}"
    printf '\nProject: %s\n' "$project_dir"
    echo "Start separate agent panes plus your own shell in a persistent tmux session."
    echo "Installed does not mean authenticated. Sign in inside each agent as needed."
    echo "Agents use your existing NTM configuration and may incur provider charges."
    if [[ "$work" == true ]]; then
        echo "Work mode lets NTM claim ready Beads tasks and send prompts to agents."
    else
        echo "ACFS will not send a task or enable automatic work assignment."
    fi
    read -r -p "Session name [$session]: " answer || return 1
    session="${answer:-$session}"
    if ((cc > 0)); then
        read -r -p "Claude agents, 0-4 [$cc]: " answer || return 1
        cc="${answer:-$cc}"
    fi
    if ((cod > 0)); then
        read -r -p "Codex agents, 0-4 [$cod]: " answer || return 1
        cod="${answer:-$cod}"
    fi
    if ((agy > 0)); then
        read -r -p "Antigravity agents, 0-4 [$agy]: " answer || return 1
        agy="${answer:-$agy}"
    fi
    printf '\nSession: %s\nClaude: %s  Codex: %s  Antigravity: %s\n' "$session" "$cc" "$cod" "$agy"
    newproj_validate_ntm_request "$project_dir" "$session" "$cc" "$cod" "$agy" || return 1
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
    if [[ -n "$task_title" ]]; then
        # --silent is br's single-ID output contract. A title stays one argument,
        # including quotes or shell syntax. Never recreate automatically on error.
        if ! created_task=$(newproj_ntm_project_command "$project_dir" br create "--title=$task_title" --type=task --priority=2 --silent) ||
           [[ ! "$created_task" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$ ]]; then
            echo "Task creation was not confirmed. Inspect br list before retrying; existing work was preserved." >&2
            return 1
        fi
        printf 'Created task %s. It remains in Beads even if workspace launch fails.\n' "$created_task"
    fi
    if ! session=$(newproj_start_ntm "$project_dir" "$session" "$cc" "$cod" "$agy" "$work"); then
        return 1
    fi
    printf '\nWorkspace started. Reconnect later with: ntm attach %q\n' "$session"
    echo "Detach with Ctrl-b then d. Agents keep running after you disconnect."
    prepare_success_exec
    cd -- "$project_dir" || return 1
    exec ntm attach "$session"
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
                if open_in_claude; then
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
