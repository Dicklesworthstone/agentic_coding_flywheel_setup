#!/bin/bash
# Bash completion for ACFS (Agentic Coding Flywheel Setup)
# Install: source this file in ~/.bashrc or copy to /etc/bash_completion.d/
#
# Related: bead bd-zhdi

_acfs_completions() {
    local cur prev words cword
    _init_completion || return

    local commands="newproj new services svc services-setup setup doctor check session sessions update status continue progress info i capacity cap policy-lint policy_lint credential-preflight credential_preflight secrets-preflight secrets_preflight swarm swarm-plan swarm_plan swarm-status swarm_status swarm-simulate swarm_simulate swarm-packet swarm_packet swarm-assign swarm_assign swarm-convergence swarm_convergence swarm-calibration swarm_calibration swarm-inventory swarm_inventory provisioning-packet provider-packet installer-cache coordinate coord cheatsheet cs changelog changes log export-config export dashboard dash support-bundle bundle version help"

    # Subcommand-specific flags
    local newproj_flags="-i --interactive --no-br --no-claude --no-agents -h --help"
    local doctor_flags="--json --deep --no-cache --fix --dry-run -h --help"
    local status_flags="--json --short --check-updates -h --help"
    local info_flags="--json --html --minimal"
    local capacity_flags="--json --workload --profile --recommend-ntm -h --help"
    local policy_lint_flags="--json --human --root --file -h --help"
    local credential_preflight_flags="--json --human --home --acfs-home --root --file --exclude --max-bytes -h --help"
    local swarm_subcommands="plan advisor status snapshot doctor preflight simulate packet assign convergence calibration inventory hosts host-inventory help"
    local swarm_plan_flags="--json --agents --profile --workload --status-file -h --help"
    local swarm_status_flags="--json -h --help"
    local swarm_doctor_flags="--json --status-file -h --help"
    local swarm_simulate_flags="--json --counts --workload --artifact-dir --status-file -h --help"
    local swarm_packet_flags="--json --markdown --bead --bead-id --bead-file --repo --agent-name --role --max-chars --agents-file --readme-file --cm-file --cass-file --no-live-context -h --help"
    local swarm_assign_flags="--json --markdown --agents --roles --profile --ready-file --triage-file -h --help"
    local swarm_convergence_flags="--json --markdown --epic --epic-file --issues-file --commits-file -h --help"
    local swarm_calibration_flags="--json --markdown --artifact-dir --rch-file -h --help"
    local swarm_inventory_flags="report import export validate --json --markdown --inventory --input --output --format --artifact-dir -h --help"
    local provisioning_packet_flags="--json --markdown --file --packet -h --help"
    local installer_cache_flags="build --json --markdown --output --module --dry-run --best-effort --source-root --manifest-file --checksums-file --arch --ubuntu-version --timeout --expires-days -h --help"
    local coordinate_subcommands="doctor preflight help"
    local cheatsheet_flags="--json"
    local changelog_flags="--all --since --json -h --help"
    local export_config_flags="--json --minimal --output -h --help"
    local session_subcommands="list export recent import convert show list-imported help"
    local session_list_flags="--json --days --agent --limit"
    local session_export_flags="--format --no-sanitize --output"
    local session_recent_flags="--workspace --format"
    local session_import_flags="--dry-run"
    local session_convert_flags="--from --to --workspace --session-id --dry-run --json --no-json"
    local session_show_flags="--format"
    local services_subcommands="start stop status restart logs help"
    local services_logs_targets="agent-mail cm cass"
    local dashboard_subcommands="generate serve"
    local common_flags="-h --help"

    # Determine the subcommand
    local cmd=""
    for ((i=1; i < cword; i++)); do
        case "${words[i]}" in
            newproj|new|services|svc|services-setup|setup|doctor|check|session|sessions|update|status|continue|progress|info|i|capacity|cap|policy-lint|policy_lint|credential-preflight|credential_preflight|secrets-preflight|secrets_preflight|swarm|swarm-plan|swarm_plan|swarm-status|swarm_status|swarm-simulate|swarm_simulate|swarm-packet|swarm_packet|swarm-assign|swarm_assign|swarm-convergence|swarm_convergence|swarm-calibration|swarm_calibration|swarm-inventory|swarm_inventory|provisioning-packet|provider-packet|installer-cache|coordinate|coord|cheatsheet|cs|changelog|changes|log|export-config|export|dashboard|dash|support-bundle|bundle|version|help)
                cmd="${words[i]}"
                break
                ;;
        esac
    done

    case "$cmd" in
        newproj|new)
            mapfile -t COMPREPLY < <(compgen -W "$newproj_flags" -- "$cur")
            return
            ;;
        doctor|check)
            mapfile -t COMPREPLY < <(compgen -W "$doctor_flags" -- "$cur")
            return
            ;;
        status)
            mapfile -t COMPREPLY < <(compgen -W "$status_flags" -- "$cur")
            return
            ;;
        info|i)
            mapfile -t COMPREPLY < <(compgen -W "$info_flags" -- "$cur")
            return
            ;;
        capacity|cap)
            mapfile -t COMPREPLY < <(compgen -W "$capacity_flags" -- "$cur")
            return
            ;;
        policy-lint|policy_lint)
            mapfile -t COMPREPLY < <(compgen -W "$policy_lint_flags" -- "$cur")
            return
            ;;
        credential-preflight|credential_preflight|secrets-preflight|secrets_preflight)
            mapfile -t COMPREPLY < <(compgen -W "$credential_preflight_flags" -- "$cur")
            return
            ;;
        provisioning-packet|provider-packet)
            mapfile -t COMPREPLY < <(compgen -W "$provisioning_packet_flags" -- "$cur")
            return
            ;;
        installer-cache)
            mapfile -t COMPREPLY < <(compgen -W "$installer_cache_flags" -- "$cur")
            return
            ;;
        swarm)
            local swarm_cmd=""
            for ((j=i+1; j < cword; j++)); do
                case "${words[j]}" in
                    plan|advisor|status|snapshot|doctor|preflight|simulate|packet|assign|convergence|calibration|inventory|hosts|host-inventory|help)
                        swarm_cmd="${words[j]}"
                        break
                        ;;
                esac
            done

            case "$swarm_cmd" in
                plan|advisor)
                    mapfile -t COMPREPLY < <(compgen -W "$swarm_plan_flags" -- "$cur")
                    ;;
                status|snapshot)
                    mapfile -t COMPREPLY < <(compgen -W "$swarm_status_flags" -- "$cur")
                    ;;
                doctor|preflight)
                    mapfile -t COMPREPLY < <(compgen -W "$swarm_doctor_flags" -- "$cur")
                    ;;
                simulate)
                    mapfile -t COMPREPLY < <(compgen -W "$swarm_simulate_flags" -- "$cur")
                    ;;
                packet)
                    mapfile -t COMPREPLY < <(compgen -W "$swarm_packet_flags" -- "$cur")
                    ;;
                assign)
                    mapfile -t COMPREPLY < <(compgen -W "$swarm_assign_flags" -- "$cur")
                    ;;
                convergence)
                    mapfile -t COMPREPLY < <(compgen -W "$swarm_convergence_flags" -- "$cur")
                    ;;
                calibration)
                    mapfile -t COMPREPLY < <(compgen -W "$swarm_calibration_flags" -- "$cur")
                    ;;
                inventory|hosts|host-inventory)
                    mapfile -t COMPREPLY < <(compgen -W "$swarm_inventory_flags" -- "$cur")
                    ;;
                help)
                    COMPREPLY=()
                    ;;
                *)
                    mapfile -t COMPREPLY < <(compgen -W "$swarm_subcommands" -- "$cur")
                    ;;
            esac
            return
            ;;
        swarm-plan|swarm_plan)
            mapfile -t COMPREPLY < <(compgen -W "$swarm_plan_flags" -- "$cur")
            return
            ;;
        swarm-status|swarm_status)
            mapfile -t COMPREPLY < <(compgen -W "$swarm_status_flags" -- "$cur")
            return
            ;;
        swarm-simulate|swarm_simulate)
            mapfile -t COMPREPLY < <(compgen -W "$swarm_simulate_flags" -- "$cur")
            return
            ;;
        swarm-packet|swarm_packet)
            mapfile -t COMPREPLY < <(compgen -W "$swarm_packet_flags" -- "$cur")
            return
            ;;
        swarm-assign|swarm_assign)
            mapfile -t COMPREPLY < <(compgen -W "$swarm_assign_flags" -- "$cur")
            return
            ;;
        swarm-convergence|swarm_convergence)
            mapfile -t COMPREPLY < <(compgen -W "$swarm_convergence_flags" -- "$cur")
            return
            ;;
        swarm-calibration|swarm_calibration)
            mapfile -t COMPREPLY < <(compgen -W "$swarm_calibration_flags" -- "$cur")
            return
            ;;
        swarm-inventory|swarm_inventory)
            mapfile -t COMPREPLY < <(compgen -W "$swarm_inventory_flags" -- "$cur")
            return
            ;;
        coordinate|coord)
            local coord_cmd=""
            for ((j=i+1; j < cword; j++)); do
                case "${words[j]}" in
                    doctor|preflight|help)
                        coord_cmd="${words[j]}"
                        break
                        ;;
                esac
            done

            case "$coord_cmd" in
                doctor|preflight)
                    mapfile -t COMPREPLY < <(compgen -W "$swarm_doctor_flags" -- "$cur")
                    ;;
                help)
                    COMPREPLY=()
                    ;;
                *)
                    mapfile -t COMPREPLY < <(compgen -W "$coordinate_subcommands" -- "$cur")
                    ;;
            esac
            return
            ;;
        cheatsheet|cs)
            mapfile -t COMPREPLY < <(compgen -W "$cheatsheet_flags" -- "$cur")
            return
            ;;
        changelog|changes|log)
            mapfile -t COMPREPLY < <(compgen -W "$changelog_flags" -- "$cur")
            return
            ;;
        export-config|export)
            if [[ "$cur" == -* ]]; then
                mapfile -t COMPREPLY < <(compgen -W "$export_config_flags" -- "$cur")
            else
                _filedir
            fi
            return
            ;;
        session|sessions)
            # Check if we have a session subcommand
            local session_cmd=""
            for ((j=i+1; j < cword; j++)); do
                case "${words[j]}" in
                    list|export|recent|import|convert|show|list-imported|help)
                        session_cmd="${words[j]}"
                        break
                        ;;
                esac
            done

            case "$session_cmd" in
                list)
                    mapfile -t COMPREPLY < <(compgen -W "$session_list_flags" -- "$cur")
                    ;;
                export)
                    if [[ "$cur" == -* ]]; then
                        mapfile -t COMPREPLY < <(compgen -W "$session_export_flags" -- "$cur")
                    else
                        _filedir
                    fi
                    ;;
                recent)
                    mapfile -t COMPREPLY < <(compgen -W "$session_recent_flags" -- "$cur")
                    ;;
                import)
                    if [[ "$cur" == -* ]]; then
                        mapfile -t COMPREPLY < <(compgen -W "$session_import_flags" -- "$cur")
                    else
                        _filedir '@(json)'
                    fi
                    ;;
                convert)
                    if [[ "$cur" == -* ]]; then
                        mapfile -t COMPREPLY < <(compgen -W "$session_convert_flags" -- "$cur")
                    else
                        _filedir
                    fi
                    ;;
                show)
                    mapfile -t COMPREPLY < <(compgen -W "$session_show_flags" -- "$cur")
                    ;;
                help)
                    COMPREPLY=()
                    ;;
                list-imported)
                    COMPREPLY=()
                    ;;
                *)
                    mapfile -t COMPREPLY < <(compgen -W "$session_subcommands" -- "$cur")
                    ;;
            esac
            return
            ;;
        services|svc)
            # Check if we have a services subcommand
            local svc_cmd=""
            for ((j=i+1; j < cword; j++)); do
                case "${words[j]}" in
                    start|stop|status|restart|logs|help)
                        svc_cmd="${words[j]}"
                        break
                        ;;
                esac
            done

            case "$svc_cmd" in
                logs)
                    mapfile -t COMPREPLY < <(compgen -W "$services_logs_targets --dry-run" -- "$cur")
                    ;;
                start|stop|restart)
                    mapfile -t COMPREPLY < <(compgen -W "--dry-run" -- "$cur")
                    ;;
                status|help)
                    COMPREPLY=()
                    ;;
                *)
                    mapfile -t COMPREPLY < <(compgen -W "$services_subcommands --dry-run" -- "$cur")
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
                mapfile -t COMPREPLY < <(compgen -W "$dashboard_subcommands" -- "$cur")
            fi
            return
            ;;
        update|continue|progress|services-setup|setup|support-bundle|bundle|version|help)
            mapfile -t COMPREPLY < <(compgen -W "$common_flags" -- "$cur")
            return
            ;;
    esac

    # No subcommand yet, complete commands
    mapfile -t COMPREPLY < <(compgen -W "$commands" -- "$cur")
}

complete -F _acfs_completions acfs
