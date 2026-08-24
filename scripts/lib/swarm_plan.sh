#!/usr/bin/env bash
# ============================================================
# ACFS Swarm Plan - queue-aware launch advisor
#
# Reads current swarm status and capacity JSON, then emits a read-only
# launch recommendation. This script never starts agents, mutates Beads,
# sends Agent Mail, force-releases reservations, or runs build commands.
# ============================================================

set -euo pipefail

SWARM_PLAN_JSON=false
SWARM_PLAN_AGENTS=""
SWARM_PLAN_PROFILE="balanced"
SWARM_PLAN_WORKLOAD="standard"
SWARM_PLAN_STATUS_FILE=""
SWARM_PLAN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM_STATUS_SCRIPT="${ACFS_SWARM_STATUS_SCRIPT:-$SWARM_PLAN_SCRIPT_DIR/swarm_status.sh}"
SWARM_CAPACITY_SCRIPT="${ACFS_SWARM_CAPACITY_SCRIPT:-$SWARM_PLAN_SCRIPT_DIR/capacity.sh}"

swarm_plan_usage() {
    cat <<'EOF'
Usage: acfs swarm plan --agents N [OPTIONS]

Options:
  --json              Emit machine-readable JSON
  --agents N          Requested agent count
  --profile NAME      balanced, codex-heavy, review-heavy, or docs-heavy
                      (default: balanced)
  --workload NAME     light, standard, or heavy (default: standard)
  --status-file FILE  Read an existing swarm_status.json snapshot
  --help, -h          Show this help

Exit codes:
  0  Launch is reasonable
  1  Launch may proceed only after reviewing warnings
  2  Hard blockers must be fixed before launching
EOF
}

swarm_plan_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                SWARM_PLAN_JSON=true
                shift
                ;;
            --agents)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --agents requires a positive integer" >&2
                    return 2
                fi
                SWARM_PLAN_AGENTS="$2"
                shift 2
                ;;
            --profile)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --profile requires a value" >&2
                    return 2
                fi
                SWARM_PLAN_PROFILE="$2"
                shift 2
                ;;
            --workload)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --workload requires a value" >&2
                    return 2
                fi
                SWARM_PLAN_WORKLOAD="$2"
                shift 2
                ;;
            --status-file)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    echo "Error: --status-file requires a path" >&2
                    return 2
                fi
                SWARM_PLAN_STATUS_FILE="$2"
                shift 2
                ;;
            --help|-h)
                swarm_plan_usage
                return 100
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'acfs swarm plan --help' for usage." >&2
                return 2
                ;;
        esac
    done

    if [[ ! "$SWARM_PLAN_AGENTS" =~ ^[0-9]+$ ]] || (( SWARM_PLAN_AGENTS < 1 )); then
        echo "Error: --agents requires a positive integer" >&2
        return 2
    fi

    case "$SWARM_PLAN_PROFILE" in
        balanced|codex-heavy|review-heavy|docs-heavy) ;;
        *)
            echo "Error: unsupported profile: $SWARM_PLAN_PROFILE" >&2
            return 2
            ;;
    esac

    case "$SWARM_PLAN_WORKLOAD" in
        light|standard|heavy) ;;
        *)
            echo "Error: unsupported workload: $SWARM_PLAN_WORKLOAD" >&2
            return 2
            ;;
    esac
}

swarm_plan_binary_path() {
    local name="${1:-}"
    local path_value=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..|*/*) return 1 ;;
    esac

    path_value="$(command -v "$name" 2>/dev/null || true)"
    [[ -n "$path_value" && -x "$path_value" ]] || return 1
    printf '%s\n' "$path_value"
}

swarm_plan_collect_status_json() {
    if [[ -n "$SWARM_PLAN_STATUS_FILE" ]]; then
        if [[ ! -f "$SWARM_PLAN_STATUS_FILE" ]]; then
            echo "Error: status file not found: $SWARM_PLAN_STATUS_FILE" >&2
            return 2
        fi
        cat "$SWARM_PLAN_STATUS_FILE"
        return 0
    fi

    if [[ ! -f "$SWARM_STATUS_SCRIPT" ]]; then
        echo "Error: swarm_status.sh not found" >&2
        return 2
    fi

    bash "$SWARM_STATUS_SCRIPT" --json
}

swarm_plan_collect_capacity_json() {
    if [[ ! -f "$SWARM_CAPACITY_SCRIPT" ]]; then
        echo "Error: capacity.sh not found" >&2
        return 2
    fi

    bash "$SWARM_CAPACITY_SCRIPT" \
        --json \
        --workload "$SWARM_PLAN_WORKLOAD" \
        --profile "${SWARM_PLAN_AGENTS}-agents" \
        --recommend-ntm
}

swarm_plan_jq_filter() {
    cat <<'JQ'
def n($v):
  if $v == null then 0
  elif ($v | type) == "number" then $v
  elif (($v | type) == "string") and ($v | test("^[0-9]+([.][0-9]+)?$")) then ($v | tonumber)
  else 0 end;

def b($v): $v == true;
def min2($a; $b): if $a < $b then $a else $b end;

def check($id; $status; $summary; $details; $commands):
  {
    id: $id,
    status: $status,
    summary: $summary,
    details: $details,
    commands: $commands
  };

def agent_mix($count; $profile):
  if $profile == "codex-heavy" then
    (($count / 4) | floor) as $cc
    | (($count / 5) | floor) as $agy
    | {cc: $cc, cod: ($count - $cc - $agy), agy: $agy}
  elif $profile == "docs-heavy" then
    (($count / 4) | floor) as $cc
    | (($count / 4) | floor) as $cod
    | {cc: $cc, cod: $cod, agy: ($count - $cc - $cod)}
  elif $profile == "review-heavy" then
    (($count / 3) | floor) as $cc
    | (($count / 3) | floor) as $cod
    | {cc: $cc, cod: $cod, agy: ($count - $cc - $cod)}
  else
    (($count * 2 / 5) | floor) as $cc
    | (($count * 2 / 5) | floor) as $cod
    | {cc: $cc, cod: $cod, agy: ($count - $cc - $cod)}
  end;

def example_plan($count; $safe; $recommended; $has_warnings; $has_failures):
  if $has_failures then
    {requested_agents: $count, status: "fail", recommendation: "block"}
  elif $safe < 1 or $count > $safe then
    {requested_agents: $count, status: "fail", recommendation: "block"}
  elif $recommended > 0 and $count > $recommended then
    {requested_agents: $count, status: "warn", recommendation: "defer_or_reduce"}
  elif $has_warnings then
    {requested_agents: $count, status: "warn", recommendation: "launch_with_review"}
  else
    {requested_agents: $count, status: "pass", recommendation: "launch"}
  end;

$status as $s
| $capacity as $c
| ($s.probes.agent_mail // {}) as $am
| ($s.probes.beads // {}) as $beads
| ($s.probes.bv // {}) as $bv
| ($s.probes.rch // {}) as $rch
| ($s.probes.ntm // {}) as $ntm
| ($s.host // {}) as $host
| (n($host.cpu_count)) as $host_cpu_count
| (n($host.load_1m)) as $host_load_1m
| (n($host.mem_available_kb)) as $host_mem_available_kb
| (if n($host.cpu_count) > 0 then (n($host.load_1m) / n($host.cpu_count)) else 0 end) as $host_load_ratio
| (($host_cpu_count > 0 and $host_load_ratio >= 1.25) or ($host_mem_available_kb > 0 and $host_mem_available_kb < 4194304)) as $host_pressure_high
| (n($c.capacity.recommended_agent_count)) as $capacity_recommended
| (n($c.capacity.safe_agent_count)) as $capacity_safe
| (if $capacity_safe > 0 then $capacity_safe else n($c.capacity.max_agent_count) end) as $safe_from_capacity
| (n($rch.queue_depth)) as $rch_queue_depth
| (n($rch.active_build_count)) as $rch_active_builds
| (n($rch.slots_available)) as $rch_slots_available
| (n($rch.workers_total)) as $rch_workers_total
| (n($rch.workers_healthy)) as $rch_workers_healthy
| (n($rch.workers_busy)) as $rch_workers_busy
| (n($rch.workers_offline)) as $rch_workers_offline
| (n($rch.pressure_warning_count)) as $rch_pressure_warning_count
| (n($rch.stale_worker_count)) as $rch_stale_worker_count
| (n($beads.stale_in_progress_count) + n($beads.stale_work_count) + n($beads.stale_count) + n($s.stale_work.total_stale_count) + n($s.stale_work.stale_count)) as $stale_work_count
| (
    if (b($rch.available) | not) then "fail"
    elif (b($rch.status_json_ok) | not) then "fail"
    elif ($rch_workers_total < 1) then "fail"
    elif ($rch_workers_total > 0 and $rch_workers_healthy < 1) then "fail"
    elif ($rch_queue_depth > 0 or $rch_active_builds > 0 or $rch_workers_busy > 0 or $rch_pressure_warning_count > 0 or $rch_stale_worker_count > 0) then "warn"
    else "pass" end
  ) as $rch_check_status
| (
    if $rch_check_status == "fail" then 0
    elif $rch_check_status == "warn" and $rch_slots_available > 0 then min2($requested_agents; $rch_slots_available)
    elif $capacity_recommended > 0 then min2($requested_agents; $capacity_recommended)
    else $requested_agents end
  ) as $pressure_adjusted_recommended
| (
    if $safe_from_capacity > 0 then $safe_from_capacity else 0 end
  ) as $safe_agents
| (
    if $pressure_adjusted_recommended > 0 then $pressure_adjusted_recommended
    elif $capacity_recommended > 0 then min2($requested_agents; $capacity_recommended)
    else $requested_agents end
  ) as $recommended_agents
| [
    check(
      "host_capacity";
      (if ($safe_agents < 1 or $requested_agents > $safe_agents or ($c.profile_check.status // $c.status // "warn") == "fail") then "fail"
       elif (($c.profile_check.status // "pass") == "warn" or ($capacity_recommended > 0 and $requested_agents > $capacity_recommended)) then "warn"
       else "pass" end);
      (if ($safe_agents < 1) then "Capacity model reports no safe launch size"
       elif $requested_agents > $safe_agents then "Requested agent count exceeds the safe capacity limit"
       elif (($c.profile_check.status // "pass") == "warn" or ($capacity_recommended > 0 and $requested_agents > $capacity_recommended)) then "Requested count exceeds the conservative recommendation"
       else "Requested count is within the capacity recommendation" end);
      ($c.recommendations // []);
      ["acfs capacity --json --profile " + ($requested_agents | tostring) + "-agents --recommend-ntm"]
    ),
    check(
      "host_pressure";
      (if $host_pressure_high then "warn" else "pass" end);
      (if ($host_cpu_count > 0 and $host_load_ratio >= 1.25 and $host_mem_available_kb > 0 and $host_mem_available_kb < 4194304) then "Host load and available memory are already under pressure"
       elif ($host_cpu_count > 0 and $host_load_ratio >= 1.25) then "Host load is already high; pause new launches until pressure clears"
       elif ($host_mem_available_kb > 0 and $host_mem_available_kb < 4194304) then "Available memory is below the conservative launch threshold"
       else "Host pressure is acceptable" end);
      ([
        if ($host_cpu_count > 0 and $host_load_ratio >= 1.25) then "load_1m=" + ($host_load_1m | tostring) + " cpu_count=" + ($host_cpu_count | tostring) else empty end,
        if ($host_mem_available_kb > 0 and $host_mem_available_kb < 4194304) then "mem_available_kb=" + ($host_mem_available_kb | tostring) else empty end
      ]);
      ["acfs swarm status --json", "acfs capacity --json --recommend-ntm"]
    ),
    check(
      "rch_pressure";
      $rch_check_status;
      (if (b($rch.available) | not) then "RCH is unavailable for CPU-heavy build/test offload"
       elif (b($rch.status_json_ok) | not) then "RCH status JSON failed or timed out"
       elif ($rch_workers_total < 1) then "RCH reports no workers"
       elif ($rch_workers_total > 0 and $rch_workers_healthy < 1) then "RCH reports no healthy workers"
       elif $rch_queue_depth > 0 then "RCH queue already has pending work"
       elif $rch_active_builds > 0 then "RCH has active builds"
       elif $rch_pressure_warning_count > 0 then "RCH workers report elevated pressure"
       elif $rch_stale_worker_count > 0 then "RCH pressure telemetry has stale workers"
       else "RCH pressure is acceptable" end);
      ($rch.warnings // []);
      ["rch status", "rch queue --json", "rch workers probe --all"]
    ),
    check(
      "coordination_health";
      (if ((b($am.available) | not) or (b($beads.available) | not) or (b($bv.available) | not) or ($beads.status // "warn") != "pass" or (b($bv.robot_ok) | not)) then "fail"
       elif (($am.status // "warn") != "pass" or ($am.healthy == false)) then "warn"
       else "pass" end);
      (if (b($beads.available) | not) then "br is unavailable"
       elif (b($bv.available) | not) then "bv is unavailable"
       elif (b($am.available) | not) then "Agent Mail CLI is unavailable"
       elif ($beads.status // "warn") != "pass" then "Beads JSON commands failed or timed out"
       elif (b($bv.robot_ok) | not) then "bv robot mode failed or timed out"
       elif (($am.status // "warn") != "pass" or ($am.healthy == false)) then "Agent Mail health is uncertain"
       else "Coordination probes are usable" end);
      (($am.warnings // []) + ($beads.warnings // []) + ($bv.warnings // []));
      ["br ready --json", "bv --robot-next", "mcp-agent-mail doctor check --json"]
    ),
    check(
      "ntm_tmux";
      (if (b($ntm.available) | not) then "fail"
       elif (b($ntm.robot_status_ok)) then "pass"
       elif (b($ntm.tmux_available)) then "warn"
       else "fail" end);
      (if (b($ntm.available) | not) then "NTM is unavailable for launch command generation"
       elif (b($ntm.robot_status_ok)) then "NTM robot status is usable"
       elif (b($ntm.tmux_available)) then "NTM robot status is uncertain, but tmux is usable"
       else "NTM and tmux are unavailable" end);
      ($ntm.warnings // []);
      ["ntm --robot-status", "tmux list-sessions -F '#S #{session_windows}'"]
    ),
    check(
      "active_work";
      (if $stale_work_count > 0 or n($beads.in_progress_count) > 0 then "warn" else "pass" end);
      (if $stale_work_count > 0 then "Stale in-progress work requires verification before adding agents"
       elif n($beads.in_progress_count) > 0 then "There is active in-progress Beads work; inspect before adding agents"
       else "No in-progress Beads work reported" end);
      (if $stale_work_count > 0 then ["stale_work_count=" + ($stale_work_count | tostring)] else [] end);
      ["br list --status in_progress --json", "acfs swarm status --json", "acfs swarm doctor --stale-hours 12"]
    ),
    check(
      "active_sessions";
      (if n($ntm.tmux_session_count) >= $requested_agents and $requested_agents > 1 then "warn" else "pass" end);
      (if n($ntm.tmux_session_count) >= $requested_agents and $requested_agents > 1 then "Existing tmux session count is already at or above the requested agent count" else "Existing tmux activity does not block planning" end);
      [];
      ["ntm --robot-status", "acfs swarm status --json"]
    )
  ] as $checks
| (if any($checks[]; .status == "fail") then "fail" elif any($checks[]; .status == "warn") then "warn" else "pass" end) as $plan_status
| (if $plan_status == "fail" then 2 elif $plan_status == "warn" then 1 else 0 end) as $exit_code
| (if $plan_status == "fail" then "block"
   elif $requested_agents > $recommended_agents then "defer_or_reduce"
   elif $plan_status == "warn" then "launch_with_review"
   else "launch" end) as $recommendation
| (if $plan_status == "fail" then null
   elif $requested_agents > $recommended_agents then $recommended_agents
   else $requested_agents end) as $launch_agents
| (if ($launch_agents // 0) > 0 then agent_mix($launch_agents; $profile) else null end) as $mix
| ([$checks[] | select(.status != "pass") | .summary] | unique) as $warnings
| (if ($plan_status == "fail" or $host_pressure_high or $stale_work_count > 0) then "wait"
   elif ($requested_agents > $recommended_agents or $plan_status == "warn") then "scale_down"
   else "proceed" end) as $quiesce_recommendation
| (if $quiesce_recommendation == "wait" then
     ([$checks[] | select(.status == "fail" or .id == "host_pressure" or (.id == "active_work" and $stale_work_count > 0)) | select(.status != "pass") | .summary] | unique)
   elif $quiesce_recommendation == "scale_down" then
     ([$checks[] | select(.status == "warn") | .summary] | unique)
   else
     ["No load-shedding pressure detected"]
   end) as $quiesce_reasons
| {
    schema_version: 1,
    generated_at: (now | todateiso8601),
    status: $plan_status,
    exit_code: $exit_code,
    requested_agents: $requested_agents,
    recommended_agents: (if $recommended_agents > 0 then $recommended_agents else null end),
    safe_agents: (if $safe_agents > 0 then $safe_agents else null end),
    workload: $workload,
    profile: $profile,
    recommendation: $recommendation,
    recommended_action:
      (if $plan_status == "fail" then "Do not launch; resolve hard blockers first."
       elif $requested_agents > $recommended_agents then "Reduce to " + ($recommended_agents | tostring) + " agents or wait for pressure to clear."
       elif $plan_status == "warn" then "Launch only after reviewing warnings."
       else "Launch is reasonable." end),
    quiesce_advisory: {
      recommendation: $quiesce_recommendation,
      action:
        (if $quiesce_recommendation == "wait" then "Wait before launching new agents; inspect the listed pressure or stale-work reasons."
         elif $quiesce_recommendation == "scale_down" then "Scale down to " + ($recommended_agents | tostring) + " agents or wait for pressure to clear."
         else "Proceed with the requested launch size." end),
      recommended_agents:
        (if $quiesce_recommendation == "proceed" then $requested_agents
         elif $quiesce_recommendation == "scale_down" and $recommended_agents > 0 then $recommended_agents
         else null end),
      reasons: $quiesce_reasons,
      does_not: ["kill sessions", "delete files", "release reservations", "mutate Beads"]
    },
    inputs: {
      swarm_status_file: (if $status_file == "" then null else $status_file end),
      capacity_profile: (($requested_agents | tostring) + "-agents"),
      capacity_workload: $workload
    },
    summary: {
      failed: ([$checks[] | select(.status == "fail")] | length),
      warnings: ([$checks[] | select(.status == "warn")] | length),
      passed: ([$checks[] | select(.status == "pass")] | length),
      beads_ready: ($beads.ready_count // null),
      beads_in_progress: ($beads.in_progress_count // null),
      tmux_sessions: ($ntm.tmux_session_count // null),
      rch_queue_depth: ($rch.queue_depth // null),
      rch_slots_available: ($rch.slots_available // null)
    },
    checks: $checks,
    launch_profile: {
      recommended: ($plan_status != "fail" and ($launch_agents // 0) > 0),
      not_executed: true,
      agent_count: $launch_agents,
      label: (if ($launch_agents // 0) > 0 then "swarm-" + ($launch_agents | tostring) else null end),
      mix: $mix,
      command:
        (if ($launch_agents // 0) > 0 then
          "ntm spawn myproject --label swarm-" + ($launch_agents | tostring)
          + " --cc=" + ($mix.cc | tostring)
          + " --cod=" + ($mix.cod | tostring)
          + " --agy=" + ($mix.agy | tostring)
          + " --assign --stagger-mode=smart"
        else null end)
    },
    rch_policy: {
      cpu_heavy_commands_require_rch: true,
      required_prefix: "rch exec --",
      examples: ["rch exec -- cargo test", "rch exec -- cargo clippy"],
      forbidden_local_examples: ["cargo test", "cargo build --release"]
    },
    safety: {
      read_only: true,
      launches_agents: false,
      mutates_beads: false,
      sends_agent_mail: false,
      force_releases_reservations: false,
      runs_builds: false
    },
    warnings: $warnings,
    next_commands: ([$checks[] | select(.status != "pass") | .commands[]] | unique),
    examples: [10, 25, 50] | map(example_plan(.; $safe_agents; $recommended_agents; ($plan_status == "warn"); ($plan_status == "fail")))
  }
JQ
}

swarm_plan_jq_error_report() {
    local message="$1"
    local jq_bin="$2"

    "$jq_bin" -n \
        --arg generated_at "$(date -Iseconds)" \
        --arg message "$message" \
        '{
            schema_version: 1,
            generated_at: $generated_at,
            status: "fail",
            exit_code: 2,
            requested_agents: null,
            recommended_agents: null,
            safe_agents: null,
            workload: null,
            profile: null,
            recommendation: "block",
            recommended_action: $message,
            checks: [
                {
                    id: "planner_input",
                    status: "fail",
                    summary: $message,
                    details: [],
                    commands: ["acfs swarm status --json", "acfs capacity --json --recommend-ntm"]
                }
            ],
            launch_profile: {recommended: false, not_executed: true, agent_count: null, label: null, mix: null, command: null},
            quiesce_advisory: {
                recommendation: "wait",
                action: $message,
                recommended_agents: null,
                reasons: [$message],
                does_not: ["kill sessions", "delete files", "release reservations", "mutate Beads"]
            },
            warnings: [$message],
            next_commands: ["acfs swarm status --json", "acfs capacity --json --recommend-ntm"],
            examples: []
        }'
}

swarm_plan_build_report() {
    local jq_bin=""
    local status_json=""
    local capacity_json=""

    jq_bin="$(swarm_plan_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        printf '{"schema_version":1,"status":"fail","exit_code":2,"recommendation":"block","recommended_action":"jq is required for swarm plan JSON evaluation","checks":[{"id":"jq","status":"fail","summary":"jq is required for swarm plan JSON evaluation","details":[],"commands":["sudo apt-get -o DPkg::Lock::Timeout=120 install -y jq"]}],"launch_profile":{"recommended":false,"not_executed":true,"agent_count":null,"label":null,"mix":null,"command":null},"warnings":["jq is required for swarm plan JSON evaluation"],"next_commands":["sudo apt-get -o DPkg::Lock::Timeout=120 install -y jq"],"examples":[]}\n'
        return 0
    fi

    status_json="$(swarm_plan_collect_status_json)" || {
        swarm_plan_jq_error_report "swarm status JSON is unavailable" "$jq_bin"
        return 0
    }

    capacity_json="$(swarm_plan_collect_capacity_json)" || {
        swarm_plan_jq_error_report "capacity JSON is unavailable" "$jq_bin"
        return 0
    }

    if ! printf '%s' "$status_json" | "$jq_bin" . >/dev/null 2>&1; then
        swarm_plan_jq_error_report "swarm status JSON is malformed" "$jq_bin"
        return 0
    fi

    if ! printf '%s' "$capacity_json" | "$jq_bin" . >/dev/null 2>&1; then
        swarm_plan_jq_error_report "capacity JSON is malformed" "$jq_bin"
        return 0
    fi

    "$jq_bin" -n \
        --argjson status "$status_json" \
        --argjson capacity "$capacity_json" \
        --argjson requested_agents "$SWARM_PLAN_AGENTS" \
        --arg profile "$SWARM_PLAN_PROFILE" \
        --arg workload "$SWARM_PLAN_WORKLOAD" \
        --arg status_file "$SWARM_PLAN_STATUS_FILE" \
        "$(swarm_plan_jq_filter)"
}

swarm_plan_emit_human() {
    local report="$1"
    local jq_bin="$2"
    local launch_command=""

    echo "ACFS Swarm Plan"
    echo "Status: $("${jq_bin}" -r '.status' <<<"$report")"
    echo "Requested: $("${jq_bin}" -r '.requested_agents // "unknown"' <<<"$report") agents"
    echo "Recommended: $("${jq_bin}" -r '.recommended_agents // "none"' <<<"$report") agents"
    echo "Safe max: $("${jq_bin}" -r '.safe_agents // "none"' <<<"$report") agents"
    echo "Workload: $("${jq_bin}" -r '.workload // "unknown"' <<<"$report")"
    echo "Profile: $("${jq_bin}" -r '.profile // "unknown"' <<<"$report")"
    echo "Recommendation: $("${jq_bin}" -r '.recommendation' <<<"$report")"
    echo "Action: $("${jq_bin}" -r '.recommended_action' <<<"$report")"
    echo "Quiesce: $("${jq_bin}" -r '.quiesce_advisory.recommendation // "wait"' <<<"$report") - $("${jq_bin}" -r '.quiesce_advisory.action // "Inspect status before launching."' <<<"$report")"

    launch_command="$("${jq_bin}" -r '.launch_profile.command // ""' <<<"$report")"
    if [[ -n "$launch_command" ]]; then
        echo ""
        echo "Launch command (not executed):"
        echo "  $launch_command"
    fi

    if [[ "$("${jq_bin}" -r '.warnings | length' <<<"$report")" != "0" ]]; then
        echo ""
        echo "Warnings:"
        "${jq_bin}" -r '.warnings[] | "  - " + .' <<<"$report"
    fi

    if [[ "$("${jq_bin}" -r '.next_commands | length' <<<"$report")" != "0" ]]; then
        echo ""
        echo "Next commands:"
        "${jq_bin}" -r '.next_commands[] | "  " + .' <<<"$report"
    fi
}

swarm_plan_main() {
    local parse_status=0
    local report=""
    local jq_bin=""
    local exit_code=2

    set +e
    swarm_plan_parse_args "$@"
    parse_status=$?
    set -e

    if [[ $parse_status -eq 100 ]]; then
        return 0
    elif [[ $parse_status -ne 0 ]]; then
        return "$parse_status"
    fi

    report="$(swarm_plan_build_report)"
    jq_bin="$(swarm_plan_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        printf '%s\n' "$report"
        return 2
    fi

    exit_code="$("$jq_bin" -r '.exit_code // 2' <<<"$report" 2>/dev/null || echo 2)"

    if [[ "$SWARM_PLAN_JSON" == true ]]; then
        printf '%s\n' "$report"
    else
        swarm_plan_emit_human "$report" "$jq_bin"
    fi

    return "$exit_code"
}

swarm_plan_main "$@"
