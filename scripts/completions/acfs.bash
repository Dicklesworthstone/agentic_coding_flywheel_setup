#!/bin/bash
# Bash completion for ACFS (Agentic Coding Flywheel Setup)
# Install: source this file in ~/.bashrc or copy to /etc/bash_completion.d/
#
# Related: bead bd-zhdi

_acfs_completions() {
    local cur prev words cword
    _init_completion || return

    local commands="newproj new services-setup services setup doctor check session sessions update status continue progress info i cheatsheet cs dashboard dash support-bundle bundle version help"

    # Subcommand-specific flags
    local newproj_flags="-i --interactive --no-bd --no-claude --no-agents -h --help"
    local doctor_flags="--json --deep --no-cache --fix --dry-run -h --help"
    local info_flags="--json --html --minimal"
    local cheatsheet_flags="--json"
    local session_subcommands="list export recent import show"
    local session_list_flags="--json --days --agent --limit"
    local session_export_flags="--format --no-sanitize --output"
    local session_recent_flags="--workspace --format"
    local session_import_flags="--dry-run"
    local session_show_flags="--format"
    local dashboard_subcommands="generate serve"
    local common_flags="-h --help"

    # Determine the subcommand
    local cmd=""
    for ((i=1; i < cword; i++)); do
        case "${words[i]}" in
            newproj|new|services-setup|services|setup|doctor|check|session|sessions|update|status|continue|progress|info|i|cheatsheet|cs|dashboard|dash|support-bundle|bundle|version|help)
                cmd="${words[i]}"
                break
                ;;
        esac
    done

    case "$cmd" in
        newproj|new)
            COMPREPLY=($(compgen -W "$newproj_flags" -- "$cur"))
            return
            ;;
        doctor|check)
            COMPREPLY=($(compgen -W "$doctor_flags" -- "$cur"))
            return
            ;;
        info|i)
            COMPREPLY=($(compgen -W "$info_flags" -- "$cur"))
            return
            ;;
        cheatsheet|cs)
            COMPREPLY=($(compgen -W "$cheatsheet_flags" -- "$cur"))
            return
            ;;
        session|sessions)
            # Check if we have a session subcommand
            local session_cmd=""
            for ((j=i+1; j < cword; j++)); do
                case "${words[j]}" in
                    list|export|recent|import|show)
                        session_cmd="${words[j]}"
                        break
                        ;;
                esac
            done

            case "$session_cmd" in
                list)
                    COMPREPLY=($(compgen -W "$session_list_flags" -- "$cur"))
                    ;;
                export)
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "$session_export_flags" -- "$cur"))
                    else
                        _filedir
                    fi
                    ;;
                recent)
                    COMPREPLY=($(compgen -W "$session_recent_flags" -- "$cur"))
                    ;;
                import)
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "$session_import_flags" -- "$cur"))
                    else
                        _filedir '@(json)'
                    fi
                    ;;
                show)
                    COMPREPLY=($(compgen -W "$session_show_flags" -- "$cur"))
                    ;;
                *)
                    COMPREPLY=($(compgen -W "$session_subcommands" -- "$cur"))
                    ;;
            esac
            return
            ;;
        dashboard|dash)
            # Check if we have a dashboard subcommand
            local dash_cmd=""
            for ((j=i+1; j < cword; j++)); do
                case "${words[j]}" in
                    generate|serve)
                        dash_cmd="${words[j]}"
                        break
                        ;;
                esac
            done

            if [[ -z "$dash_cmd" ]]; then
                COMPREPLY=($(compgen -W "$dashboard_subcommands" -- "$cur"))
            fi
            return
            ;;
        update|status|continue|progress|services-setup|services|setup|support-bundle|bundle|version|help)
            COMPREPLY=($(compgen -W "$common_flags" -- "$cur"))
            return
            ;;
    esac

    # No subcommand yet, complete commands
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
}

complete -F _acfs_completions acfs
