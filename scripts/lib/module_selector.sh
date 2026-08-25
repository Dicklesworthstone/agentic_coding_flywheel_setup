#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
# ============================================================
# ACFS - Interactive Module Selector TUI Library (bd-l56ty)
# ============================================================
# Provides an interactive terminal selector for ACFS install profiles
# and optional module groups with safe non-interactive fallbacks.

# Prevent multiple sourcing
if [[ -n "${_ACFS_MODULE_SELECTOR_SH_LOADED:-}" ]]; then
    return 0
fi
_ACFS_MODULE_SELECTOR_SH_LOADED=1

ACFS_MODULE_SELECTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure dependencies are available
if ! declare -F log_info &>/dev/null; then
    if [[ -f "$ACFS_MODULE_SELECTOR_DIR/logging.sh" ]]; then
        # shellcheck source=logging.sh
        source "$ACFS_MODULE_SELECTOR_DIR/logging.sh"
    fi
fi

if ! declare -F acfs_resolve_selection &>/dev/null; then
    if [[ -f "$ACFS_MODULE_SELECTOR_DIR/install_helpers.sh" ]]; then
        # shellcheck source=install_helpers.sh
        source "$ACFS_MODULE_SELECTOR_DIR/install_helpers.sh"
    fi
fi

acfs_is_interactive_terminal() {
    # Non-interactive if explicitly requested or running in automated test/CI
    if [[ "${YES_MODE:-false}" == "true" ]] || [[ "${CI:-}" == "true" ]]; then
        return 1
    fi

    # Interactive if stdin/stdout are attached to a terminal or one bidirectional
    # /dev/tty descriptor can actually be opened by the caller.
    if [[ -t 0 && -t 1 ]]; then
        return 0
    fi
    local tty_fd=""
    if exec {tty_fd}<>/dev/tty 2>/dev/null; then
        exec {tty_fd}>&-
        return 0
    fi
    return 1
}

acfs_format_reproducible_cli_command() {
    local cmd="bash install.sh"
    if [[ -n "${MODE:-}" && "$MODE" != "vibe" ]]; then
        cmd+=" --mode $MODE"
    fi
    local profile_has_selectors=false
    if [[ -n "${ACFS_SELECTED_PROFILE:-}" ]] \
        && { [[ -n "${ACFS_PROFILE_ONLY_MODULES["$ACFS_SELECTED_PROFILE"]:-}" ]] \
            || [[ -n "${ACFS_PROFILE_ONLY_PHASES["$ACFS_SELECTED_PROFILE"]:-}" ]]; }; then
        profile_has_selectors=true
    fi
    if [[ "$profile_has_selectors" == "true" ]]; then
        cmd+=" --profile $ACFS_SELECTED_PROFILE"
    fi
    if [[ "${#ONLY_MODULES[@]}" -gt 0 && "$profile_has_selectors" != "true" ]]; then
        local m=""
        for m in "${ONLY_MODULES[@]}"; do
            [[ -n "$m" ]] && cmd+=" --only $m"
        done
    fi
    if [[ "${#ONLY_PHASES[@]}" -gt 0 && "$profile_has_selectors" != "true" ]]; then
        local ph=""
        for ph in "${ONLY_PHASES[@]}"; do
            [[ -n "$ph" ]] && cmd+=" --only-phase $ph"
        done
    fi
    if [[ "${#SKIP_MODULES[@]}" -gt 0 ]]; then
        local sm=""
        for sm in "${SKIP_MODULES[@]}"; do
            [[ -n "$sm" ]] && cmd+=" --skip $sm"
        done
    fi
    if [[ "${NO_DEPS:-false}" == "true" ]]; then
        cmd+=" --no-deps"
    fi
    echo "$cmd"
}

acfs_render_selection_review() {
    local title="ACFS Installation Plan Review"
    local total_count="${#ACFS_MODULES_IN_ORDER[@]}"
    local selected_count="${#ACFS_EFFECTIVE_PLAN[@]}"
    local skipped_count=$((total_count - selected_count))

    echo ""
    echo "================================================================="
    echo " $title"
    echo "================================================================="
    echo " Selected Profile: ${ACFS_SELECTED_PROFILE:-default (vibe)}"
    echo " Mode:             ${MODE:-vibe}"
    echo " Plan Summary:     ${selected_count}/${total_count} modules selected (${skipped_count} skipped)"
    echo "-----------------------------------------------------------------"
    echo " Included Modules by Phase:"
    local current_phase=""
    local mod=""
    for mod in "${ACFS_EFFECTIVE_PLAN[@]}"; do
        local ph="${ACFS_MODULE_PHASE["$mod"]:-?}"
        local desc="${ACFS_MODULE_DESC["$mod"]:-$mod}"
        local reason="${ACFS_PLAN_REASON["$mod"]:-included}"
        local opt="${ACFS_MODULE_OPTIONAL["$mod"]:-1}"
        local lock_marker=""
        if [[ "$opt" == "0" ]]; then
            lock_marker=" [Locked Core]"
        fi

        if [[ "$ph" != "$current_phase" ]]; then
            current_phase="$ph"
            echo "   [Phase $ph]"
        fi
        echo "     • $mod - $desc$lock_marker"
        if [[ "$reason" != "default" && "$reason" != "included" && "$reason" != "explicitly requested" ]]; then
            echo "       └─ reason: $reason"
        fi
    done

    if [[ "$skipped_count" -gt 0 ]]; then
        echo "-----------------------------------------------------------------"
        echo " Skipped / Excluded Modules:"
        for mod in "${ACFS_MODULES_IN_ORDER[@]}"; do
            if [[ -z "${ACFS_EFFECTIVE_RUN["$mod"]:-}" ]]; then
                local exc_reason="${ACFS_PLAN_EXCLUDE_REASON["$mod"]:-not selected}"
                echo "     ✕ $mod ($exc_reason)"
            fi
        done
    fi

    echo "-----------------------------------------------------------------"
    echo " Reproducible CLI Command:"
    echo "   $(acfs_format_reproducible_cli_command)"
    echo "================================================================="
    echo ""
}

acfs_interactive_custom_module_toggles() {
    echo ""
    echo "--- Custom Module Selection ---"
    echo "Core required modules are locked and cannot be disabled."
    echo "Enter module IDs to toggle (or press Enter when finished):"
    echo ""

    local optional_modules=()
    local mod=""
    for mod in "${ACFS_MODULES_IN_ORDER[@]}"; do
        local opt="${ACFS_MODULE_OPTIONAL["$mod"]:-1}"
        if [[ "$opt" == "1" ]]; then
            optional_modules+=("$mod")
        fi
    done

    local i=1
    for mod in "${optional_modules[@]}"; do
        local state="[ ]"
        local selected=""
        for selected in "${ONLY_MODULES[@]}"; do
            if [[ "$selected" == "$mod" ]]; then
                state="[x]"
                break
            fi
        done
        local desc="${ACFS_MODULE_DESC["$mod"]:-$mod}"
        printf "  %2d) %s %-25s - %s\n" "$i" "$state" "$mod" "$desc"
        i=$((i + 1))
    done
    echo ""
    echo "Type the number or ID to toggle skip status, or 'done' to finish:"

    local input=""
    while true; do
        if ! read -r -p "Toggle [number/ID/done]: " input; then
            echo "Input closed; cancelling module customization." >&2
            return 1
        fi

        [[ -z "$input" || "$input" == "done" || "$input" == "d" ]] && break

        local target=""
        if [[ "$input" =~ ^[0-9]+$ ]] && [[ "$input" -ge 1 && "$input" -le "${#optional_modules[@]}" ]]; then
            target="${optional_modules[$((input - 1))]}"
        else
            for mod in "${optional_modules[@]}"; do
                if [[ "$mod" == "$input" ]]; then
                    target="$mod"
                    break
                fi
            done
        fi

        if [[ -z "$target" ]]; then
            echo "Unknown optional module: $input" >&2
            continue
        fi

        local is_selected=false
        local new_selection=()
        for selected in "${ONLY_MODULES[@]}"; do
            if [[ "$selected" == "$target" ]]; then
                is_selected=true
            else
                new_selection+=("$selected")
            fi
        done

        if [[ "$is_selected" == "true" ]]; then
            ONLY_MODULES=("${new_selection[@]}")
            echo "Disabled: $target"
        else
            ONLY_MODULES+=("$target")
            echo "Enabled: $target"
        fi
    done
}

acfs_prepare_custom_selection() {
    ONLY_MODULES=("${ACFS_EFFECTIVE_PLAN[@]}")
    ONLY_PHASES=()
    SKIP_MODULES=()
    ACFS_SELECTED_PROFILE=""
    ACFS_EXPLICIT_TARGETED_SELECTION=true
    export ACFS_SELECTED_PROFILE
}

acfs_interactive_module_selector() {
    if ! acfs_is_interactive_terminal; then
        if [[ "${ACFS_INTERACTIVE:-false}" == "true" ]]; then
            log_error "Interactive module selection requested (--interactive), but no interactive TTY is attached."
            log_error "Run with --yes to accept defaults or provide explicit flags (--profile, --only, --skip)."
            return 1
        fi
        # Default non-interactive path: resolve selection with current settings and return
        acfs_resolve_selection
        return $?
    fi

    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        if ! source_manifest_index 2>/dev/null; then
            log_error "Manifest index not loaded. Cannot open module selector."
            return 1
        fi
    fi

    local tty_fd=""
    if ! exec {tty_fd}<>/dev/tty 2>/dev/null; then
        log_error "Interactive module selection requested, but /dev/tty could not be opened."
        return 1
    fi
    local selector_status=0
    _acfs_interactive_module_selector_on_tty <&"$tty_fd" >&"$tty_fd" || selector_status=$?
    exec {tty_fd}>&-
    return "$selector_status"
}

_acfs_interactive_module_selector_on_tty() {
    while true; do
        echo ""
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║            ACFS - Interactive Module Selector                 ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo ""
        echo " Select an installation profile:"
        echo "   1) vibe         - Full Agentic Flywheel stack (Recommended)"
        echo "   2) safe         - Strict security verification mode"
        echo "   3) minimal      - Lightweight core agentic essentials"
        echo "   4) agents-only  - Only coding agents (Claude Code, Codex, AGY, OpenCode)"
        echo "   5) cloud-only   - Only cloud & deployment CLIs (Wrangler, Supabase, Vercel)"
        echo "   6) stack-only   - Agent Flywheel coordination tools only (NTM, Mail, UBS, Beads, CASS)"
        echo "   7) custom       - Custom per-module selection / advanced toggles"
        echo "   q) Quit / Abort installation"
        echo ""

        local profile_choice=""
        if ! read -r -p " Choose profile [1-7, q]: " profile_choice; then
            echo "Input closed; cancelling installation." >&2
            return 1
        fi

        case "$profile_choice" in
            1|vibe|"")
                ACFS_EXPLICIT_TARGETED_SELECTION=false
                acfs_apply_profile "vibe"
                ;;
            2|safe)
                ACFS_EXPLICIT_TARGETED_SELECTION=false
                acfs_apply_profile "safe"
                ;;
            3|minimal)
                ACFS_EXPLICIT_TARGETED_SELECTION=false
                acfs_apply_profile "minimal"
                ;;
            4|agents-only|agents)
                ACFS_EXPLICIT_TARGETED_SELECTION=false
                acfs_apply_profile "agents-only"
                ;;
            5|cloud-only|cloud)
                ACFS_EXPLICIT_TARGETED_SELECTION=false
                acfs_apply_profile "cloud-only"
                ;;
            6|stack-only|stack)
                ACFS_EXPLICIT_TARGETED_SELECTION=false
                acfs_apply_profile "stack-only"
                ;;
            7|custom)
                if ! acfs_resolve_selection; then
                    continue
                fi
                acfs_prepare_custom_selection
                if ! acfs_interactive_custom_module_toggles; then
                    return 1
                fi
                ;;
            q|Q|quit|exit)
                echo "Installation cancelled by user." >&2
                return 1
                ;;
            *)
                echo "Invalid selection: $profile_choice" >&2
                continue
                ;;
        esac

        if ! acfs_resolve_selection; then
            echo "Failed to resolve selection. Please adjust your choices." >&2
            continue
        fi

        acfs_render_selection_review

        local confirm_choice=""
        while true; do
            echo " What would you like to do?"
            echo "   1) Proceed with installation"
            echo "   2) Choose a different profile"
            echo "   3) Customize individual modules"
            echo "   q) Abort"
            echo ""
            if ! read -r -p " Selection [1-3, q]: " confirm_choice; then
                echo "Input closed; cancelling installation." >&2
                return 1
            fi

            case "$confirm_choice" in
                1|""|y|Y|yes)
                    echo "Proceeding with installation..."
                    return 0
                    ;;
                2)
                    ONLY_MODULES=()
                    ONLY_PHASES=()
                    SKIP_MODULES=()
                    ACFS_SELECTED_PROFILE=""
                    ACFS_EXPLICIT_TARGETED_SELECTION=false
                    break
                    ;;
                3)
                    acfs_prepare_custom_selection
                    if ! acfs_interactive_custom_module_toggles; then
                        return 1
                    fi
                    if ! acfs_resolve_selection; then
                        continue
                    fi
                    acfs_render_selection_review
                    continue
                    ;;
                q|Q|quit|abort)
                    echo "Installation cancelled by user." >&2
                    return 1
                    ;;
                *)
                    echo "Invalid selection: $confirm_choice" >&2
                    ;;
            esac
        done
    done
}
