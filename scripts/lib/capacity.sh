#!/usr/bin/env bash
# ============================================================
# ACFS Capacity Report
#
# Fast, offline host sizing for multi-agent ACFS workflows.
# ============================================================

set -uo pipefail

CAPACITY_JSON=false
CAPACITY_WORKLOAD="standard"
CAPACITY_PROFILE=""
CAPACITY_RECOMMEND_NTM=false
CAPACITY_RESOURCE_PROFILE=false
CAPACITY_RESOURCE_PROFILE_APPLY=false
CAPACITY_RESOURCE_PROFILE_DISABLE=false
CAPACITY_RESOURCE_PROFILE_ROOT=""

capacity_usage() {
    cat <<'EOF'
Usage: acfs capacity [OPTIONS]

Options:
  --json                  Emit machine-readable JSON
  --workload <name>       light, standard, or heavy (default: standard)
  --profile <agents>      Check a target agent count, e.g. 25 or 25-agents
  --recommend-ntm         Include an NTM launch recommendation
  --resource-profile      Report opt-in systemd resource profile wrappers
  --apply-resource-profile
                          Write opt-in ACFS wrapper files under ~/.acfs
  --disable-resource-profile
                          Write a disabled profile marker/snippet, no deletion
  -h, --help              Show this help

Environment overrides for tests:
  ACFS_CAPACITY_CPU_COUNT
  ACFS_CAPACITY_MEM_TOTAL_KB
  ACFS_CAPACITY_DISK_AVAILABLE_KB
  ACFS_CAPACITY_RCH_AVAILABLE=true|false
  ACFS_CAPACITY_NTM_AVAILABLE=true|false
  ACFS_CAPACITY_SYSTEMD_RUN_AVAILABLE=true|false
  ACFS_CAPACITY_SYSTEMD_USER_AVAILABLE=true|false
  ACFS_CAPACITY_BIN_DIR
  ACFS_RESOURCE_PROFILE_HOME
EOF
}

capacity_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                CAPACITY_JSON=true
                shift
                ;;
            --workload)
                [[ $# -ge 2 ]] || { echo "Error: --workload requires a value" >&2; return 2; }
                CAPACITY_WORKLOAD="$2"
                shift 2
                ;;
            --profile)
                [[ $# -ge 2 ]] || { echo "Error: --profile requires a value" >&2; return 2; }
                CAPACITY_PROFILE="$2"
                shift 2
                ;;
            --recommend-ntm)
                CAPACITY_RECOMMEND_NTM=true
                shift
                ;;
            --resource-profile)
                CAPACITY_RESOURCE_PROFILE=true
                shift
                ;;
            --apply-resource-profile)
                CAPACITY_RESOURCE_PROFILE=true
                CAPACITY_RESOURCE_PROFILE_APPLY=true
                shift
                ;;
            --disable-resource-profile)
                CAPACITY_RESOURCE_PROFILE=true
                CAPACITY_RESOURCE_PROFILE_DISABLE=true
                shift
                ;;
            -h|--help)
                capacity_usage
                return 100
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'acfs capacity --help' for usage." >&2
                return 2
                ;;
        esac
    done

    case "$CAPACITY_WORKLOAD" in
        light|standard|heavy) ;;
        *)
            echo "Error: unsupported workload: $CAPACITY_WORKLOAD" >&2
            return 2
            ;;
    esac

    if [[ "$CAPACITY_RESOURCE_PROFILE_APPLY" == true && "$CAPACITY_RESOURCE_PROFILE_DISABLE" == true ]]; then
        echo "Error: choose only one of --apply-resource-profile or --disable-resource-profile" >&2
        return 2
    fi
}

capacity_system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..|*[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    if [[ -n "${ACFS_CAPACITY_BIN_DIR:-}" ]]; then
        candidate="${ACFS_CAPACITY_BIN_DIR%/}/$name"
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi

    for candidate in \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name" \
        "${HOME:-}/.local/bin/$name" \
        "${HOME:-}/.cargo/bin/$name" \
        "${HOME:-}/.bun/bin/$name"
    do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return 0
    fi

    return 1
}

capacity_read_cpu_count() {
    if [[ "${ACFS_CAPACITY_CPU_COUNT:-}" =~ ^[0-9]+$ ]] && [[ "${ACFS_CAPACITY_CPU_COUNT}" -gt 0 ]]; then
        printf '%s\n' "$ACFS_CAPACITY_CPU_COUNT"
        return 0
    fi

    local nproc_bin=""
    nproc_bin="$(capacity_system_binary_path nproc 2>/dev/null || true)"
    if [[ -n "$nproc_bin" ]]; then
        "$nproc_bin" 2>/dev/null && return 0
    fi

    getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1\n'
}

capacity_read_mem_total_kb() {
    if [[ "${ACFS_CAPACITY_MEM_TOTAL_KB:-}" =~ ^[0-9]+$ ]] && [[ "${ACFS_CAPACITY_MEM_TOTAL_KB}" -gt 0 ]]; then
        printf '%s\n' "$ACFS_CAPACITY_MEM_TOTAL_KB"
        return 0
    fi

    awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || printf '0\n'
}

capacity_read_disk_available_kb() {
    if [[ "${ACFS_CAPACITY_DISK_AVAILABLE_KB:-}" =~ ^[0-9]+$ ]] && [[ "${ACFS_CAPACITY_DISK_AVAILABLE_KB}" -ge 0 ]]; then
        printf '%s\n' "$ACFS_CAPACITY_DISK_AVAILABLE_KB"
        return 0
    fi

    local target="${ACFS_CAPACITY_DISK_PATH:-${HOME:-/}}"
    df -Pk "$target" 2>/dev/null | awk 'NR == 2 {print $4; exit}' || printf '0\n'
}

capacity_tool_available() {
    local tool="$1"
    local override_var="$2"
    local override="${!override_var:-}"

    case "$override" in
        true|false)
            printf '%s\n' "$override"
            return 0
            ;;
    esac

    if capacity_system_binary_path "$tool" >/dev/null 2>&1; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

capacity_max() {
    local a="$1"
    local b="$2"
    if (( a > b )); then
        printf '%s\n' "$a"
    else
        printf '%s\n' "$b"
    fi
}

capacity_min3() {
    local a="$1"
    local b="$2"
    local c="$3"
    local min="$a"
    (( b < min )) && min="$b"
    (( c < min )) && min="$c"
    (( min < 0 )) && min=0
    printf '%s\n' "$min"
}

capacity_requested_agents() {
    local value="$1"
    local digits="${value//[^0-9]/}"
    [[ -n "$digits" ]] || return 1
    printf '%s\n' "$digits"
}

capacity_resource_profile_root() {
    if [[ -n "$CAPACITY_RESOURCE_PROFILE_ROOT" ]]; then
        printf '%s\n' "$CAPACITY_RESOURCE_PROFILE_ROOT"
        return 0
    fi

    CAPACITY_RESOURCE_PROFILE_ROOT="${ACFS_RESOURCE_PROFILE_HOME:-${HOME:-/tmp}/.acfs/resource-profile}"
    printf '%s\n' "$CAPACITY_RESOURCE_PROFILE_ROOT"
}

capacity_resource_systemd_run_available() {
    case "${ACFS_CAPACITY_SYSTEMD_RUN_AVAILABLE:-}" in
        true|false)
            printf '%s\n' "$ACFS_CAPACITY_SYSTEMD_RUN_AVAILABLE"
            return 0
            ;;
    esac

    if capacity_system_binary_path systemd-run >/dev/null 2>&1; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

capacity_resource_systemd_user_available() {
    local systemctl_bin=""

    case "${ACFS_CAPACITY_SYSTEMD_USER_AVAILABLE:-}" in
        true|false)
            printf '%s\n' "$ACFS_CAPACITY_SYSTEMD_USER_AVAILABLE"
            return 0
            ;;
    esac

    systemctl_bin="$(capacity_system_binary_path systemctl 2>/dev/null || true)"
    if [[ -n "$systemctl_bin" ]] && "$systemctl_bin" --user show-environment >/dev/null 2>&1; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

capacity_resource_profile_state() {
    if [[ "$CAPACITY_RESOURCE_PROFILE_DISABLE" == true ]]; then
        printf 'disabled\n'
    elif [[ "$CAPACITY_RESOURCE_PROFILE_APPLY" == true ]]; then
        printf 'applied\n'
    else
        printf 'dry-run\n'
    fi
}

capacity_resource_profile_json() {
    local root="$1"
    local state="$2"
    local systemd_run_available="$3"
    local systemd_user_available="$4"
    local status="${5:-pass}"
    local failure_reason="${6:-}"
    local bin_dir="$root/bin"
    local env_file="$root/acfs-resource-profile.sh"
    local manifest_file="$root/profile.json"

    command -v jq >/dev/null 2>&1 || {
        echo "Error: jq is required for resource profile JSON" >&2
        return 1
    }

    jq -n \
        --arg generated_at "$(date -Iseconds)" \
        --arg state "$state" \
        --arg root "$root" \
        --arg bin_dir "$bin_dir" \
        --arg env_file "$env_file" \
        --arg manifest_file "$manifest_file" \
        --arg status "$status" \
        --arg failure_reason "$failure_reason" \
        --argjson systemd_run_available "$systemd_run_available" \
        --argjson systemd_user_available "$systemd_user_available" \
        '{
            schema_version: 1,
            generated_at: $generated_at,
            status: $status,
            mode: $state,
            opt_in: true,
            root: $root,
            bin_dir: $bin_dir,
            env_file: $env_file,
            manifest_file: $manifest_file,
            systemd: {
                systemd_run_available: $systemd_run_available,
                user_manager_available: $systemd_user_available
            },
            safety: {
                no_hard_memory_limits_by_default: true,
                direct_agent_aliases_unchanged: true,
                rch_remains_preferred_build_path: true,
                limited_to_acfs_owned_files: true,
                destructive_cleanup_required: false
            },
            classes: [
                {name: "agent", slice: "acfs-agent.slice", properties: ["CPUAccounting=yes", "MemoryAccounting=yes", "IOAccounting=yes", "TasksAccounting=yes", "CPUWeight=100", "IOWeight=100", "TasksMax=512"]},
                {name: "background", slice: "acfs-background.slice", properties: ["CPUAccounting=yes", "MemoryAccounting=yes", "IOAccounting=yes", "TasksAccounting=yes", "CPUWeight=40", "IOWeight=50", "TasksMax=512"]},
                {name: "local-build", slice: "acfs-local-build.slice", properties: ["CPUAccounting=yes", "MemoryAccounting=yes", "IOAccounting=yes", "TasksAccounting=yes", "CPUWeight=60", "IOWeight=50", "TasksMax=512"]},
                {name: "support", slice: "acfs-support.slice", properties: ["CPUAccounting=yes", "MemoryAccounting=yes", "IOAccounting=yes", "TasksAccounting=yes", "CPUWeight=80", "IOWeight=100", "TasksMax=256"]},
                {name: "rch", slice: "acfs-rch.slice", properties: ["CPUAccounting=yes", "MemoryAccounting=yes", "IOAccounting=yes", "TasksAccounting=yes", "CPUWeight=100", "IOWeight=100", "TasksMax=512"]}
            ],
            wrappers: [
                {name: "acfs-scope", path: ($bin_dir + "/acfs-scope"), purpose: "Run an explicit command in an opt-in ACFS systemd user scope when available; otherwise execute directly."},
                {name: "ccs", path: ($bin_dir + "/ccs"), command: "acfs-scope agent -- claude"},
                {name: "cods", path: ($bin_dir + "/cods"), command: "acfs-scope agent -- codex"},
                {name: "gmis", path: ($bin_dir + "/gmis"), command: "acfs-scope agent -- gemini"},
                {name: "acfs-local-build", path: ($bin_dir + "/acfs-local-build"), command: "acfs-scope local-build --"}
            ],
            managed_files: [
                ($bin_dir + "/acfs-scope"),
                ($bin_dir + "/ccs"),
                ($bin_dir + "/cods"),
                ($bin_dir + "/gmis"),
                ($bin_dir + "/acfs-local-build"),
                $env_file,
                $manifest_file
            ],
            partial_apply_possible: ($state == "error"),
            remediation: (
                if $state == "error" then
                    [
                        "Resource profile application did not complete.",
                        "Inspect filesystem permissions under the ACFS resource profile root.",
                        "Fix the reported write failure, then rerun acfs capacity --resource-profile --apply-resource-profile."
                    ] + (if $failure_reason == "" then [] else [$failure_reason] end)
                else
                    []
                end
            ),
            actions: (
                if $state == "dry-run" then
                    ["would create wrapper directory", "would write opt-in wrappers", "would write shell snippet", "would write manifest"]
                elif $state == "disabled" then
                    ["wrote disabled shell snippet", "wrote disabled manifest"]
                elif $state == "applying" then
                    ["started profile write", "will write opt-in wrappers", "will write shell snippet", "will write final manifest"]
                elif $state == "error" then
                    ["failed before completing resource profile write", "left any already-written ACFS-owned files for inspection", "reported remediation guidance"]
                else
                    ["wrote wrapper directory", "wrote opt-in wrappers", "wrote shell snippet", "wrote manifest"]
                end
            )
        }'
}

capacity_write_resource_scope_wrapper() {
    local path="$1"
    cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: acfs-scope <agent|background|local-build|support|rch> -- <command> [args...]

Runs a command inside an opt-in ACFS systemd user scope when systemd user
scopes are available. Falls back to direct execution when unavailable.
USAGE
}

class="${1:-}"
if [[ -z "$class" || "$class" == "-h" || "$class" == "--help" ]]; then
    usage
    exit 0
fi
shift
if [[ "${1:-}" == "--" ]]; then
    shift
fi
if [[ $# -eq 0 ]]; then
    echo "Error: command required" >&2
    usage >&2
    exit 2
fi

slice=""
properties=()
case "$class" in
    agent)
        slice="acfs-agent.slice"
        properties=(CPUAccounting=yes MemoryAccounting=yes IOAccounting=yes TasksAccounting=yes CPUWeight=100 IOWeight=100 TasksMax=512)
        ;;
    background)
        slice="acfs-background.slice"
        properties=(CPUAccounting=yes MemoryAccounting=yes IOAccounting=yes TasksAccounting=yes CPUWeight=40 IOWeight=50 TasksMax=512)
        ;;
    local-build)
        slice="acfs-local-build.slice"
        properties=(CPUAccounting=yes MemoryAccounting=yes IOAccounting=yes TasksAccounting=yes CPUWeight=60 IOWeight=50 TasksMax=512)
        ;;
    support)
        slice="acfs-support.slice"
        properties=(CPUAccounting=yes MemoryAccounting=yes IOAccounting=yes TasksAccounting=yes CPUWeight=80 IOWeight=100 TasksMax=256)
        ;;
    rch)
        slice="acfs-rch.slice"
        properties=(CPUAccounting=yes MemoryAccounting=yes IOAccounting=yes TasksAccounting=yes CPUWeight=100 IOWeight=100 TasksMax=512)
        ;;
    *)
        echo "Error: unknown ACFS resource class: $class" >&2
        exit 2
        ;;
esac

if ! command -v systemd-run >/dev/null 2>&1 || ! command -v systemctl >/dev/null 2>&1; then
    exec "$@"
fi
if ! systemctl --user show-environment >/dev/null 2>&1; then
    exec "$@"
fi

args=(--user --scope --same-dir --collect "--slice=$slice")
for property in "${properties[@]}"; do
    args+=("--property=$property")
done

exec systemd-run "${args[@]}" "$@"
EOF
}

capacity_write_resource_command_wrapper() {
    local path="$1"
    local class="$2"
    shift 2

    {
        printf '#!/usr/bin/env bash\n'
        printf 'set -euo pipefail\n'
        printf 'exec acfs-scope %q --' "$class"
        # printf ' %q' with zero args still emits " ''", which made the
        # generated wrapper exec the empty string.
        if (($#)); then
            printf ' %q' "$@"
        fi
        printf ' "$@"\n'
    } > "$path"
}

capacity_apply_resource_profile() {
    local root="$1"
    local state="$2"
    local profile_json="$3"
    local bin_dir="$root/bin"
    local env_file="$root/acfs-resource-profile.sh"
    local manifest_file="$root/profile.json"

    mkdir -p "$bin_dir" || return 1

    if [[ "$state" == "disabled" ]]; then
        cat > "$env_file" <<'EOF' || return 1
# ACFS resource profile disabled.
# Re-enable with: acfs capacity --resource-profile --apply-resource-profile
EOF
        printf '%s\n' "$profile_json" > "$manifest_file" || return 1
        return 0
    fi

    local applying_json=""
    applying_json="$(capacity_resource_profile_json "$root" "applying" "$(capacity_resource_systemd_run_available)" "$(capacity_resource_systemd_user_available)" "pending")" || return 1
    printf '%s\n' "$applying_json" > "$manifest_file" || return 1

    capacity_write_resource_scope_wrapper "$bin_dir/acfs-scope" || return 1
    capacity_write_resource_command_wrapper "$bin_dir/ccs" agent claude || return 1
    capacity_write_resource_command_wrapper "$bin_dir/cods" agent codex || return 1
    capacity_write_resource_command_wrapper "$bin_dir/gmis" agent gemini || return 1
    capacity_write_resource_command_wrapper "$bin_dir/acfs-local-build" local-build || return 1
    chmod +x "$bin_dir/acfs-scope" "$bin_dir/ccs" "$bin_dir/cods" "$bin_dir/gmis" "$bin_dir/acfs-local-build" || return 1

    cat > "$env_file" <<EOF || return 1
# ACFS opt-in resource profile wrappers.
# Source this file to add wrapper commands without changing cc/cod/agy.
case ":\${PATH:-}:" in
  *":$bin_dir:"*) ;;
  *) export PATH="$bin_dir:\${PATH:-}" ;;
esac
EOF
    printf '%s\n' "$profile_json" > "$manifest_file" || return 1
}

capacity_emit_resource_profile_json() {
    local root state systemd_run_available systemd_user_available profile_json failure_reason
    root="$(capacity_resource_profile_root)"
    state="$(capacity_resource_profile_state)"
    systemd_run_available="$(capacity_resource_systemd_run_available)"
    systemd_user_available="$(capacity_resource_systemd_user_available)"
    profile_json="$(capacity_resource_profile_json "$root" "$state" "$systemd_run_available" "$systemd_user_available")"

    if [[ "$CAPACITY_RESOURCE_PROFILE_APPLY" == true || "$CAPACITY_RESOURCE_PROFILE_DISABLE" == true ]]; then
        if ! capacity_apply_resource_profile "$root" "$state" "$profile_json"; then
            failure_reason="Failed to write the complete ACFS resource profile."
            profile_json="$(capacity_resource_profile_json "$root" "error" "$systemd_run_available" "$systemd_user_available" "fail" "$failure_reason")"
            printf '%s\n' "$profile_json"
            return 1
        fi
        profile_json="$(capacity_resource_profile_json "$root" "$state" "$systemd_run_available" "$systemd_user_available")"
    fi

    printf '%s\n' "$profile_json"
}

capacity_emit_resource_profile_human() {
    local jq_bin root state systemd_run_available systemd_user_available profile_json apply_failed failure_reason
    jq_bin="$(capacity_system_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        echo "Error: jq is required for resource profile output" >&2
        return 1
    fi

    root="$(capacity_resource_profile_root)"
    state="$(capacity_resource_profile_state)"
    systemd_run_available="$(capacity_resource_systemd_run_available)"
    systemd_user_available="$(capacity_resource_systemd_user_available)"
    profile_json="$(capacity_resource_profile_json "$root" "$state" "$systemd_run_available" "$systemd_user_available")"
    apply_failed=false
    failure_reason=""

    if [[ "$CAPACITY_RESOURCE_PROFILE_APPLY" == true || "$CAPACITY_RESOURCE_PROFILE_DISABLE" == true ]]; then
        if ! capacity_apply_resource_profile "$root" "$state" "$profile_json"; then
            apply_failed=true
            state="error"
            failure_reason="Failed to write the complete ACFS resource profile."
            profile_json="$(capacity_resource_profile_json "$root" "$state" "$systemd_run_available" "$systemd_user_available" "fail" "$failure_reason")"
        else
            profile_json="$(capacity_resource_profile_json "$root" "$state" "$systemd_run_available" "$systemd_user_available")"
        fi
    fi

    echo "ACFS Resource Profile"
    echo "Mode: $state"
    echo "Root: $root"
    echo "Systemd user manager: $systemd_user_available"
    echo "systemd-run: $systemd_run_available"
    echo ""
    echo "Safety"
    echo "  Opt-in only:          true"
    echo "  Hard MemoryMax:       not set"
    echo "  Direct cc/cod/agy:    unchanged"
    echo "  RCH build path:       remains preferred"
    echo ""
    echo "Wrappers"
    "$jq_bin" -r '.wrappers[] | "  \(.name): \(.path)"' <<< "$profile_json"
    echo ""
    echo "Resource Classes"
    "$jq_bin" -r '.classes[] | "  \(.name): \(.slice) [" + (.properties | join(", ")) + "]"' <<< "$profile_json"
    echo ""
    echo "Actions"
    "$jq_bin" -r '.actions[] | "  - " + .' <<< "$profile_json"

    if [[ "$state" == "dry-run" ]]; then
        echo ""
        echo "Apply: acfs capacity --resource-profile --apply-resource-profile"
        echo "Disable marker/snippet: acfs capacity --resource-profile --disable-resource-profile"
    elif [[ "$state" == "applied" ]]; then
        echo ""
        echo "Enable in current shell: source $root/acfs-resource-profile.sh"
        echo "Inspect: $root/bin/acfs-scope --help"
        echo "Disable marker/snippet: acfs capacity --resource-profile --disable-resource-profile"
    else
        echo ""
        echo "Disabled. Re-enable with: acfs capacity --resource-profile --apply-resource-profile"
    fi

    if [[ "$apply_failed" == true ]]; then
        echo "" >&2
        echo "Error: $failure_reason" >&2
        return 1
    fi
}

capacity_collect_model() {
    local cpu_count mem_total_kb disk_available_kb rch_available ntm_available
    cpu_count="$(capacity_read_cpu_count)"
    mem_total_kb="$(capacity_read_mem_total_kb)"
    disk_available_kb="$(capacity_read_disk_available_kb)"
    rch_available="$(capacity_tool_available rch ACFS_CAPACITY_RCH_AVAILABLE)"
    ntm_available="$(capacity_tool_available ntm ACFS_CAPACITY_NTM_AVAILABLE)"

    local mem_total_mib disk_available_mib reserve_mib usable_mem_mib
    mem_total_mib=$((mem_total_kb / 1024))
    disk_available_mib=$((disk_available_kb / 1024))
    reserve_mib="$(capacity_max 4096 $((mem_total_mib / 10)))"
    usable_mem_mib=$((mem_total_mib - reserve_mib))
    (( usable_mem_mib < 0 )) && usable_mem_mib=0

    local per_agent_mib cpu_milli_per_agent
    case "$CAPACITY_WORKLOAD" in
        light)
            per_agent_mib=2048
            cpu_milli_per_agent=500
            ;;
        heavy)
            per_agent_mib=4096
            cpu_milli_per_agent=2000
            ;;
        *)
            per_agent_mib=3072
            cpu_milli_per_agent=1000
            ;;
    esac

    local disk_reserve_mib=10240
    local disk_per_agent_mib=2048
    local usable_disk_mib=$((disk_available_mib - disk_reserve_mib))
    (( usable_disk_mib < 0 )) && usable_disk_mib=0

    local mem_limit cpu_limit disk_limit safe_agents recommended_agents
    mem_limit=$((usable_mem_mib / per_agent_mib))
    cpu_limit=$(((cpu_count * 1000) / cpu_milli_per_agent))
    disk_limit=$((usable_disk_mib / disk_per_agent_mib))
    safe_agents="$(capacity_min3 "$mem_limit" "$cpu_limit" "$disk_limit")"
    recommended_agents=$(((safe_agents * 70) / 100))
    if (( safe_agents > 0 && recommended_agents < 1 )); then
        recommended_agents=1
    fi

    local requested_agents="" profile_status="unknown" profile_reason="No profile requested"
    if [[ -n "$CAPACITY_PROFILE" ]]; then
        requested_agents="$(capacity_requested_agents "$CAPACITY_PROFILE" 2>/dev/null || true)"
        if [[ -z "$requested_agents" ]]; then
            profile_status="unknown"
            profile_reason="Profile did not include an agent count"
        elif (( requested_agents <= recommended_agents )); then
            profile_status="pass"
            profile_reason="Requested count is within the recommended tier"
        elif (( requested_agents <= safe_agents )); then
            profile_status="warn"
            profile_reason="Requested count is above recommended but within the safe maximum"
        else
            profile_status="fail"
            profile_reason="Requested count exceeds the safe maximum"
        fi
    fi

    local capacity_status="pass"
    if (( safe_agents < 1 )); then
        capacity_status="fail"
    elif [[ "$rch_available" != "true" ]]; then
        capacity_status="warn"
    fi

    CAPACITY_CPU_COUNT="$cpu_count"
    CAPACITY_MEM_TOTAL_MIB="$mem_total_mib"
    CAPACITY_DISK_AVAILABLE_MIB="$disk_available_mib"
    CAPACITY_RESERVE_MIB="$reserve_mib"
    CAPACITY_PER_AGENT_MIB="$per_agent_mib"
    CAPACITY_CPU_MILLI_PER_AGENT="$cpu_milli_per_agent"
    CAPACITY_DISK_RESERVE_MIB="$disk_reserve_mib"
    CAPACITY_DISK_PER_AGENT_MIB="$disk_per_agent_mib"
    CAPACITY_MEM_LIMIT="$mem_limit"
    CAPACITY_CPU_LIMIT="$cpu_limit"
    CAPACITY_DISK_LIMIT="$disk_limit"
    CAPACITY_SAFE_AGENTS="$safe_agents"
    CAPACITY_RECOMMENDED_AGENTS="$recommended_agents"
    CAPACITY_RCH_AVAILABLE="$rch_available"
    CAPACITY_NTM_AVAILABLE="$ntm_available"
    CAPACITY_REQUESTED_AGENTS="$requested_agents"
    CAPACITY_PROFILE_STATUS="$profile_status"
    CAPACITY_PROFILE_REASON="$profile_reason"
    CAPACITY_STATUS="$capacity_status"
}

capacity_emit_json() {
    command -v jq >/dev/null 2>&1 || {
        echo "Error: jq is required for --json output" >&2
        return 1
    }

    jq -n \
        --arg generated_at "$(date -Iseconds)" \
        --arg workload "$CAPACITY_WORKLOAD" \
        --arg profile "$CAPACITY_PROFILE" \
        --arg profile_status "$CAPACITY_PROFILE_STATUS" \
        --arg profile_reason "$CAPACITY_PROFILE_REASON" \
        --argjson requested_agents "${CAPACITY_REQUESTED_AGENTS:-null}" \
        --argjson cpu_count "$CAPACITY_CPU_COUNT" \
        --argjson mem_total_mib "$CAPACITY_MEM_TOTAL_MIB" \
        --argjson disk_available_mib "$CAPACITY_DISK_AVAILABLE_MIB" \
        --argjson reserve_mib "$CAPACITY_RESERVE_MIB" \
        --argjson per_agent_mib "$CAPACITY_PER_AGENT_MIB" \
        --argjson cpu_milli_per_agent "$CAPACITY_CPU_MILLI_PER_AGENT" \
        --argjson disk_reserve_mib "$CAPACITY_DISK_RESERVE_MIB" \
        --argjson disk_per_agent_mib "$CAPACITY_DISK_PER_AGENT_MIB" \
        --argjson mem_limit "$CAPACITY_MEM_LIMIT" \
        --argjson cpu_limit "$CAPACITY_CPU_LIMIT" \
        --argjson disk_limit "$CAPACITY_DISK_LIMIT" \
        --argjson safe_agents "$CAPACITY_SAFE_AGENTS" \
        --argjson recommended_agents "$CAPACITY_RECOMMENDED_AGENTS" \
        --argjson rch_available "$CAPACITY_RCH_AVAILABLE" \
        --argjson ntm_available "$CAPACITY_NTM_AVAILABLE" \
        --argjson recommend_ntm "$CAPACITY_RECOMMEND_NTM" \
        --arg status "$CAPACITY_STATUS" '
        {
            schema_version: 1,
            generated_at: $generated_at,
            status: $status,
            host: {
                cpu_count: $cpu_count,
                mem_total_mib: $mem_total_mib,
                disk_available_mib: $disk_available_mib
            },
            tools: {
                rch: {available: $rch_available},
                ntm: {available: $ntm_available}
            },
            assumptions: {
                workload: $workload,
                reserve_mib: $reserve_mib,
                per_agent_mib: $per_agent_mib,
                cpu_milli_per_agent: $cpu_milli_per_agent,
                disk_reserve_mib: $disk_reserve_mib,
                disk_per_agent_mib: $disk_per_agent_mib
            },
            capacity: {
                memory_limited_agents: $mem_limit,
                cpu_limited_agents: $cpu_limit,
                disk_limited_agents: $disk_limit,
                recommended_agent_count: $recommended_agents,
                safe_agent_count: $safe_agents,
                max_agent_count: $safe_agents
            },
            profile_check: {
                requested_profile: (if $profile == "" then null else $profile end),
                requested_agents: $requested_agents,
                status: $profile_status,
                reason: $profile_reason
            },
            recommendations: (
                [
                    if $rch_available then empty else "Install or repair RCH before launching CPU-heavy Rust build/test swarms." end,
                    if $safe_agents < 1 then "Increase RAM, CPU, or disk headroom before launching agents." else empty end,
                    if $recommended_agents > 0 then "Start at the recommended tier, then increase only after status/doctor checks stay clean." else empty end
                ]
            ),
            ntm: {
                recommended: $recommend_ntm,
                agent_count: (if $recommend_ntm then $recommended_agents else null end),
                launch_plan: (if $recommend_ntm then "Create one coordinator session plus focused worker sessions sized to the recommended agent count." else null end),
                profiles: (
                    if $recommend_ntm then
                        def profile_status($count):
                            if $count <= $recommended_agents then "pass"
                            elif $count <= $safe_agents then "warn"
                            else "fail"
                            end;
                        [
                            {agents: 5, cc: 2, cod: 2, agy: 1, label: "swarm-5"},
                            {agents: 10, cc: 4, cod: 4, agy: 2, label: "swarm-10"},
                            {agents: 25, cc: 10, cod: 10, agy: 5, label: "swarm-25"},
                            {agents: 50, cc: 20, cod: 20, agy: 10, label: "swarm-50"}
                        ] | map(. + {
                            status: profile_status(.agents),
                            command: ("ntm spawn myproject --label " + .label + " --cc=" + (.cc | tostring) + " --cod=" + (.cod | tostring) + " --agy=" + (.agy | tostring) + " --assign --stagger-mode=smart"),
                            rch_policy: "Use rch exec -- for cargo build/test/check/clippy/bench/run/doc commands inside every agent pane.",
                            agent_mail: "Register agents, send a start message on the bead thread, and reserve files before edits.",
                            beads: "Use br ready --json and bv --robot-triage for assignment truth; never launch bare bv."
                        })
                    else
                        []
                    end
                )
            }
        }'
}

capacity_emit_human() {
    echo "ACFS Capacity Report"
    echo "Workload: $CAPACITY_WORKLOAD"
    echo ""
    echo "Host"
    echo "  CPU cores:           $CAPACITY_CPU_COUNT"
    echo "  Memory:              ${CAPACITY_MEM_TOTAL_MIB} MiB"
    echo "  Disk available:      ${CAPACITY_DISK_AVAILABLE_MIB} MiB"
    echo ""
    echo "Agent Capacity"
    echo "  Recommended agents:  $CAPACITY_RECOMMENDED_AGENTS"
    echo "  Safe max agents:     $CAPACITY_SAFE_AGENTS"
    echo "  Memory limit:        $CAPACITY_MEM_LIMIT"
    echo "  CPU limit:           $CAPACITY_CPU_LIMIT"
    echo "  Disk limit:          $CAPACITY_DISK_LIMIT"
    echo ""
    echo "Assumptions"
    echo "  Reserved memory:     ${CAPACITY_RESERVE_MIB} MiB"
    echo "  Per-agent memory:    ${CAPACITY_PER_AGENT_MIB} MiB"
    echo "  Per-agent CPU:       ${CAPACITY_CPU_MILLI_PER_AGENT} milli-cores"
    echo ""
    echo "Tooling"
    echo "  RCH available:       $CAPACITY_RCH_AVAILABLE"
    echo "  NTM available:       $CAPACITY_NTM_AVAILABLE"

    if [[ -n "$CAPACITY_PROFILE" ]]; then
        echo ""
        echo "Profile Check"
        echo "  Requested:           $CAPACITY_PROFILE"
        echo "  Status:              $CAPACITY_PROFILE_STATUS"
        echo "  Reason:              $CAPACITY_PROFILE_REASON"
    fi

    if [[ "$CAPACITY_RECOMMEND_NTM" == "true" ]]; then
        echo ""
        echo "NTM Recommendation"
        echo "  Agent count:         $CAPACITY_RECOMMENDED_AGENTS"
        echo "  Plan:                one coordinator session plus focused worker sessions"
        echo ""
        echo "Launch Profiles"
        echo "  5 agents:            ntm spawn myproject --label swarm-5 --cc=2 --cod=2 --agy=1 --assign --stagger-mode=smart"
        echo "  10 agents:           ntm spawn myproject --label swarm-10 --cc=4 --cod=4 --agy=2 --assign --stagger-mode=smart"
        echo "  25 agents:           ntm spawn myproject --label swarm-25 --cc=10 --cod=10 --agy=5 --assign --stagger-mode=smart"
        echo "  50 agents:           ntm spawn myproject --label swarm-50 --cc=20 --cod=20 --agy=10 --assign --stagger-mode=smart"
        echo ""
        echo "Coordination"
        echo "  RCH:                 use rch exec -- for CPU-heavy Rust build/test commands"
        echo "  Agent Mail:          register, announce start, reserve files before edits"
        echo "  Beads/BV:            use br ready --json and bv --robot-triage; never bare bv"
    fi

    if [[ "$CAPACITY_RCH_AVAILABLE" != "true" ]]; then
        echo ""
        echo "Warning: RCH is not available; offload CPU-heavy Rust builds/tests before scaling."
    fi
}

capacity_main() {
    capacity_parse_args "$@"
    local parse_status=$?
    if [[ $parse_status -eq 100 ]]; then
        return 0
    elif [[ $parse_status -ne 0 ]]; then
        return "$parse_status"
    fi

    if [[ "$CAPACITY_RESOURCE_PROFILE" == "true" ]]; then
        if [[ "$CAPACITY_JSON" == "true" ]]; then
            capacity_emit_resource_profile_json
        else
            capacity_emit_resource_profile_human
        fi
        return $?
    fi

    capacity_collect_model

    if [[ "$CAPACITY_JSON" == "true" ]]; then
        capacity_emit_json
    else
        capacity_emit_human
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    capacity_main "$@"
fi
