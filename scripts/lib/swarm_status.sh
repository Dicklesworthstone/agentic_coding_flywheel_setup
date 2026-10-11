#!/usr/bin/env bash
# ============================================================
# ACFS Swarm Status - local coordination snapshot
#
# Fast, offline collector for dashboards, support bundles, and
# pre-swarm checks. External coordination tools are optional and
# every probe must degrade to structured warnings instead of hangs.
# ============================================================

set -euo pipefail

SWARM_STATUS_JSON=false
SWARM_STATUS_NTM_ONLY=false
SWARM_STATUS_TIMEOUT="${ACFS_SWARM_STATUS_TIMEOUT:-3}"
SWARM_STATUS_GENERATED_AT="$(date -Iseconds 2>/dev/null || date)"
SWARM_STATUS_OVERALL="pass"
SWARM_STATUS_WARNINGS=()

HOST_STATUS="pass"
HOST_WARNINGS=()
HOST_DURATION_MS=0
HOST_CPU_COUNT=0
HOST_LOAD_1M="null"
HOST_MEM_TOTAL_KB=0
HOST_MEM_AVAILABLE_KB=0
HOST_DISK_AVAILABLE_KB=0

NTM_STATUS="warn"
NTM_WARNINGS=()
NTM_DURATION_MS=0
NTM_AVAILABLE=false
NTM_ROBOT_STATUS_OK=false
NTM_TMUX_AVAILABLE=false
NTM_TMUX_QUERY_OK=false
NTM_TMUX_SESSION_COUNT="null"
NTM_TMUX_WINDOW_COUNT="null"

AGENT_MAIL_STATUS="warn"
AGENT_MAIL_WARNINGS=()
AGENT_MAIL_DURATION_MS=0
AGENT_MAIL_AVAILABLE=false
AGENT_MAIL_HEALTHY="null"

BEADS_STATUS="warn"
BEADS_WARNINGS=()
BEADS_DURATION_MS=0
BEADS_AVAILABLE=false
BEADS_READY_COUNT="null"
BEADS_IN_PROGRESS_COUNT="null"
BEADS_OPEN_COUNT="null"
BEADS_IN_PROGRESS_ITEMS_JSON="[]"

BV_STATUS="warn"
BV_WARNINGS=()
BV_DURATION_MS=0
BV_AVAILABLE=false
BV_ROBOT_OK=false

RCH_STATUS="warn"
RCH_WARNINGS=()
RCH_DURATION_MS=0
RCH_AVAILABLE=false
RCH_STATUS_JSON_OK=false
RCH_QUEUE_JSON_OK=false
RCH_QUEUE_DEPTH="null"
RCH_ACTIVE_BUILD_COUNT="null"
RCH_WORKERS_TOTAL="null"
RCH_WORKERS_HEALTHY="null"
RCH_WORKERS_BUSY="null"
RCH_WORKERS_OFFLINE="null"
RCH_SLOTS_TOTAL="null"
RCH_SLOTS_AVAILABLE="null"
RCH_PRESSURE_WARNING_COUNT="null"
RCH_STALE_WORKER_COUNT="null"

swarm_status_usage() {
    cat <<'EOF'
Usage: acfs swarm status [OPTIONS]

Options:
  --json       Emit machine-readable JSON
  --ntm-only   Query only NTM/tmux; skip host, Beads, mail, BV and RCH probes
  --help, -h   Show this help

Environment:
  ACFS_SWARM_STATUS_TIMEOUT=SECONDS  Per-tool timeout (default: 3)
EOF
}

swarm_status_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                SWARM_STATUS_JSON=true
                shift
                ;;
            --ntm-only)
                SWARM_STATUS_NTM_ONLY=true
                SWARM_STATUS_JSON=true
                shift
                ;;
            --help|-h)
                swarm_status_usage
                exit 0
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'acfs swarm status --help' for usage." >&2
                exit 2
                ;;
        esac
    done
}

swarm_status_binary_path() {
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

swarm_status_now_ms() {
    local now=""
    now="$(date +%s%3N 2>/dev/null || true)"
    if [[ "$now" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$now"
        return 0
    fi
    now="$(date +%s 2>/dev/null || echo 0)"
    printf '%s000\n' "$now"
}

swarm_status_duration_ms() {
    local start_ms="$1"
    local end_ms=""
    end_ms="$(swarm_status_now_ms)"
    printf '%s\n' "$((end_ms - start_ms))"
}

swarm_status_run_with_timeout() {
    local timeout_secs="$1"
    shift

    local timeout_bin=""
    timeout_bin="$(swarm_status_binary_path timeout 2>/dev/null || true)"
    if [[ -n "$timeout_bin" ]]; then
        "$timeout_bin" "$timeout_secs" "$@" 2>&1
    else
        "$@" 2>&1
    fi
}

swarm_status_json_array() {
    local jq_bin="$1"
    shift

    if [[ $# -eq 0 ]]; then
        printf '[]\n'
        return 0
    fi

    printf '%s\n' "$@" | "$jq_bin" -R . | "$jq_bin" -s .
}

swarm_status_json_number() {
    local value="${1:-}"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$value"
    else
        printf 'null\n'
    fi
}

swarm_status_count_json_items() {
    local json="$1"
    local jq_bin="$2"
    local count=""

    count="$(printf '%s' "$json" | "$jq_bin" -r 'if type == "array" then length else (.total // (.issues | length) // 0) end' 2>/dev/null || true)"
    [[ "$count" =~ ^[0-9]+$ ]] || count="0"
    printf '%s\n' "$count"
}

swarm_status_beads_in_progress_items_json() {
    local json="$1"
    local jq_bin="$2"

    printf '%s' "$json" | "$jq_bin" -c '
        def items:
            if type == "array" then .
            elif (.issues | type) == "array" then .issues
            elif (.items | type) == "array" then .items
            else []
            end;
        [
            items[]? | {
                id: (.id // .issue_id // null),
                title: (.title // null),
                assignee: (.assignee // .owner // null),
                created_at: (.created_at // null),
                updated_at: (.updated_at // null)
            }
        ][0:20]
    ' 2>/dev/null || printf '[]\n'
}

swarm_status_parse_rch_status_metrics() {
    local json="$1"
    local jq_bin="$2"
    local metrics=""

    metrics="$(printf '%s' "$json" | "$jq_bin" -r '
        def root: if type == "object" and (.data | type) == "object" then .data else . end;
        def daemon:
            (root.daemon // {}) as $d
            | if ($d.daemon | type) == "object" then $d.daemon else $d end;
        def workers: (root.workers // root.daemon.workers // []);
        def active_builds: (root.active_builds // root.daemon.active_builds // []);
        def queued_builds: (root.queued_builds // root.daemon.queued_builds // []);
        def num($v):
            if ($v | type) == "number" then $v
            elif (($v | type) == "string" and ($v | test("^[0-9]+([.][0-9]+)?$"))) then ($v | tonumber)
            else 0 end;
        def n($v):
            if ($v | type) == "number" then ($v | floor | tostring)
            elif (($v | type) == "string" and ($v | test("^[0-9]+$"))) then $v
            else "null" end;
        root as $r
        | daemon as $d
        | [
            n($d.workers_total // $r.workers_total // (workers | length)),
            n($d.workers_healthy // $r.workers_healthy // ([workers[]? | select((.status // "") == "healthy")] | length)),
            n($r.workers_busy // ([workers[]? | select(num(.used_slots // 0) > 0)] | length)),
            n($r.workers_offline // ([workers[]? | select((.status // "") | IN("offline", "disabled", "unhealthy", "failed"))] | length)),
            n($d.slots_total // $r.slots_total),
            n($d.slots_available // $r.slots_available),
            n($r.queue_depth // $r.queue.active // (queued_builds | length)),
            n($r.active_build_count // (active_builds | length)),
            n([workers[]? | select((.pressure_state // "healthy") != "healthy")] | length),
            n([workers[]? | select((.pressure_telemetry_fresh == false) or ((.pressure_state // "") | IN("telemetry_gap", "stale")))] | length)
          ] | @tsv
    ' 2>/dev/null || true)"

    [[ -n "$metrics" ]] || return 1
    IFS=$'\t' read -r \
        RCH_WORKERS_TOTAL \
        RCH_WORKERS_HEALTHY \
        RCH_WORKERS_BUSY \
        RCH_WORKERS_OFFLINE \
        RCH_SLOTS_TOTAL \
        RCH_SLOTS_AVAILABLE \
        RCH_QUEUE_DEPTH \
        RCH_ACTIVE_BUILD_COUNT \
        RCH_PRESSURE_WARNING_COUNT \
        RCH_STALE_WORKER_COUNT <<< "$metrics"
}

swarm_status_parse_rch_queue_metrics() {
    local json="$1"
    local jq_bin="$2"
    local metrics=""
    local queue_depth active_count slots_total slots_available workers_total workers_healthy workers_busy workers_offline

    metrics="$(printf '%s' "$json" | "$jq_bin" -r '
        def root: if type == "object" and (.data | type) == "object" then .data else . end;
        def active_builds: (root.active_builds // []);
        def queued_builds: (root.queued_builds // []);
        def n($v):
            if ($v | type) == "number" then ($v | floor | tostring)
            elif (($v | type) == "string" and ($v | test("^[0-9]+$"))) then $v
            else "null" end;
        root as $r
        | [
            n($r.queue_depth // (queued_builds | length)),
            n($r.active_build_count // (active_builds | length)),
            n($r.slots_total),
            n($r.slots_available),
            n($r.workers_total),
            n($r.workers_healthy // $r.workers_available),
            n($r.workers_busy),
            n($r.workers_offline)
          ] | @tsv
    ' 2>/dev/null || true)"

    [[ -n "$metrics" ]] || return 1
    IFS=$'\t' read -r queue_depth active_count slots_total slots_available workers_total workers_healthy workers_busy workers_offline <<< "$metrics"

    [[ "$queue_depth" =~ ^[0-9]+$ ]] && RCH_QUEUE_DEPTH="$queue_depth"
    [[ "$active_count" =~ ^[0-9]+$ ]] && RCH_ACTIVE_BUILD_COUNT="$active_count"
    [[ "$slots_total" =~ ^[0-9]+$ ]] && RCH_SLOTS_TOTAL="$slots_total"
    [[ "$slots_available" =~ ^[0-9]+$ ]] && RCH_SLOTS_AVAILABLE="$slots_available"
    [[ "$workers_total" =~ ^[0-9]+$ ]] && RCH_WORKERS_TOTAL="$workers_total"
    [[ "$workers_healthy" =~ ^[0-9]+$ ]] && RCH_WORKERS_HEALTHY="$workers_healthy"
    [[ "$workers_busy" =~ ^[0-9]+$ ]] && RCH_WORKERS_BUSY="$workers_busy"
    [[ "$workers_offline" =~ ^[0-9]+$ ]] && RCH_WORKERS_OFFLINE="$workers_offline"
}

swarm_status_collect_host() {
    local start_ms=""
    start_ms="$(swarm_status_now_ms)"

    HOST_CPU_COUNT="$(nproc 2>/dev/null || echo 0)"
    [[ "$HOST_CPU_COUNT" =~ ^[0-9]+$ ]] || HOST_CPU_COUNT=0

    if [[ -r /proc/loadavg ]]; then
        HOST_LOAD_1M="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo null)"
        [[ "$HOST_LOAD_1M" =~ ^[0-9]+([.][0-9]+)?$ ]] || HOST_LOAD_1M="null"
    else
        HOST_WARNINGS+=("/proc/loadavg is not readable")
    fi

    if [[ -r /proc/meminfo ]]; then
        HOST_MEM_TOTAL_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
        HOST_MEM_AVAILABLE_KB="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    else
        HOST_WARNINGS+=("/proc/meminfo is not readable")
    fi
    [[ "$HOST_MEM_TOTAL_KB" =~ ^[0-9]+$ ]] || HOST_MEM_TOTAL_KB=0
    [[ "$HOST_MEM_AVAILABLE_KB" =~ ^[0-9]+$ ]] || HOST_MEM_AVAILABLE_KB=0

    HOST_DISK_AVAILABLE_KB="$(df -k "${HOME:-/}" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)"
    [[ "$HOST_DISK_AVAILABLE_KB" =~ ^[0-9]+$ ]] || HOST_DISK_AVAILABLE_KB=0

    if [[ ${#HOST_WARNINGS[@]} -gt 0 ]]; then
        HOST_STATUS="warn"
    fi
    HOST_DURATION_MS="$(swarm_status_duration_ms "$start_ms")"
}

swarm_status_collect_ntm() {
    local start_ms=""
    start_ms="$(swarm_status_now_ms)"

    local ntm_bin=""
    local tmux_bin=""
    local output=""
    local exit_status=0

    ntm_bin="$(swarm_status_binary_path ntm 2>/dev/null || true)"
    if [[ -n "$ntm_bin" ]]; then
        NTM_AVAILABLE=true
        output="$(swarm_status_run_with_timeout "$SWARM_STATUS_TIMEOUT" "$ntm_bin" --robot-status)" || exit_status=$?
        if [[ $exit_status -eq 0 && -n "$output" ]]; then
            NTM_ROBOT_STATUS_OK=true
        else
            NTM_WARNINGS+=("ntm --robot-status failed or timed out")
        fi
    else
        NTM_WARNINGS+=("ntm not found in PATH")
    fi

    tmux_bin="$(swarm_status_binary_path tmux 2>/dev/null || true)"
    if [[ -n "$tmux_bin" ]]; then
        NTM_TMUX_AVAILABLE=true
        exit_status=0
        output="$(swarm_status_run_with_timeout "$SWARM_STATUS_TIMEOUT" "$tmux_bin" list-sessions -F '#S	#{session_windows}')" || exit_status=$?
        if [[ $exit_status -eq 0 && -n "$output" ]]; then
            NTM_TMUX_QUERY_OK=true
            NTM_TMUX_SESSION_COUNT="$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
            NTM_TMUX_WINDOW_COUNT="$(printf '%s\n' "$output" | awk -F '\t' '{sum += $2} END {print sum + 0}')"
        else
            NTM_TMUX_SESSION_COUNT=0
            NTM_TMUX_WINDOW_COUNT=0
            NTM_WARNINGS+=("tmux has no listable sessions or timed out")
        fi
    else
        NTM_WARNINGS+=("tmux not found in PATH")
    fi

    if [[ "$NTM_AVAILABLE" == true && "$NTM_ROBOT_STATUS_OK" == true ]]; then
        NTM_STATUS="pass"
    elif [[ "$NTM_TMUX_AVAILABLE" == true ]]; then
        NTM_STATUS="warn"
    fi
    NTM_DURATION_MS="$(swarm_status_duration_ms "$start_ms")"
}

swarm_status_collect_agent_mail() {
    local start_ms=""
    start_ms="$(swarm_status_now_ms)"

    local am_bin=""
    local candidate=""
    local output=""
    local exit_status=0
    local jq_bin=""

    for candidate in am mcp-agent-mail agent-mail mcp_agent_mail; do
        am_bin="$(swarm_status_binary_path "$candidate" 2>/dev/null || true)"
        [[ -n "$am_bin" ]] && break
    done

    if [[ -z "$am_bin" ]]; then
        AGENT_MAIL_WARNINGS+=("Agent Mail CLI not found in PATH")
        AGENT_MAIL_DURATION_MS="$(swarm_status_duration_ms "$start_ms")"
        return 0
    fi

    AGENT_MAIL_AVAILABLE=true
    output="$(swarm_status_run_with_timeout "$SWARM_STATUS_TIMEOUT" "$am_bin" doctor check --json)" || exit_status=$?
    if [[ $exit_status -eq 0 && -n "$output" ]]; then
        jq_bin="$(swarm_status_binary_path jq 2>/dev/null || true)"
        if [[ -n "$jq_bin" ]]; then
            AGENT_MAIL_HEALTHY="$(printf '%s' "$output" | "$jq_bin" -r '.healthy // .ok // null' 2>/dev/null || echo null)"
        fi
        AGENT_MAIL_STATUS="pass"
    else
        AGENT_MAIL_WARNINGS+=("Agent Mail doctor check failed or timed out")
    fi

    AGENT_MAIL_DURATION_MS="$(swarm_status_duration_ms "$start_ms")"
}

swarm_status_collect_beads() {
    local start_ms=""
    start_ms="$(swarm_status_now_ms)"

    local br_bin=""
    local jq_bin=""
    local output=""
    local exit_status=0

    br_bin="$(swarm_status_binary_path br 2>/dev/null || true)"
    jq_bin="$(swarm_status_binary_path jq 2>/dev/null || true)"

    if [[ -z "$br_bin" ]]; then
        BEADS_WARNINGS+=("br not found in PATH")
        BEADS_DURATION_MS="$(swarm_status_duration_ms "$start_ms")"
        return 0
    fi
    BEADS_AVAILABLE=true

    if [[ -z "$jq_bin" ]]; then
        BEADS_WARNINGS+=("jq not found; cannot parse br JSON")
        BEADS_DURATION_MS="$(swarm_status_duration_ms "$start_ms")"
        return 0
    fi

    output="$(swarm_status_run_with_timeout "$SWARM_STATUS_TIMEOUT" "$br_bin" ready --json)" || exit_status=$?
    if [[ $exit_status -eq 0 ]]; then
        BEADS_READY_COUNT="$(swarm_status_count_json_items "$output" "$jq_bin")"
    else
        BEADS_WARNINGS+=("br ready --json failed or timed out")
    fi

    exit_status=0
    output="$(swarm_status_run_with_timeout "$SWARM_STATUS_TIMEOUT" "$br_bin" list --status in_progress --json)" || exit_status=$?
    if [[ $exit_status -eq 0 ]]; then
        BEADS_IN_PROGRESS_COUNT="$(swarm_status_count_json_items "$output" "$jq_bin")"
        BEADS_IN_PROGRESS_ITEMS_JSON="$(swarm_status_beads_in_progress_items_json "$output" "$jq_bin")"
    else
        BEADS_WARNINGS+=("br list --status in_progress --json failed or timed out")
    fi

    exit_status=0
    output="$(swarm_status_run_with_timeout "$SWARM_STATUS_TIMEOUT" "$br_bin" list --status open --json)" || exit_status=$?
    if [[ $exit_status -eq 0 ]]; then
        BEADS_OPEN_COUNT="$(swarm_status_count_json_items "$output" "$jq_bin")"
    else
        BEADS_WARNINGS+=("br list --status open --json failed or timed out")
    fi

    if [[ ${#BEADS_WARNINGS[@]} -eq 0 ]]; then
        BEADS_STATUS="pass"
    fi
    BEADS_DURATION_MS="$(swarm_status_duration_ms "$start_ms")"
}

swarm_status_collect_bv() {
    local start_ms=""
    start_ms="$(swarm_status_now_ms)"

    local bv_bin=""
    local output=""
    local exit_status=0

    bv_bin="$(swarm_status_binary_path bv 2>/dev/null || true)"
    if [[ -z "$bv_bin" ]]; then
        BV_WARNINGS+=("bv not found in PATH")
        BV_DURATION_MS="$(swarm_status_duration_ms "$start_ms")"
        return 0
    fi

    BV_AVAILABLE=true
    output="$(swarm_status_run_with_timeout "$SWARM_STATUS_TIMEOUT" "$bv_bin" --robot-next)" || exit_status=$?
    if [[ $exit_status -eq 0 && -n "$output" ]]; then
        BV_ROBOT_OK=true
        BV_STATUS="pass"
    else
        BV_WARNINGS+=("bv --robot-next failed or timed out")
    fi
    BV_DURATION_MS="$(swarm_status_duration_ms "$start_ms")"
}

swarm_status_collect_rch() {
    local start_ms=""
    start_ms="$(swarm_status_now_ms)"

    local rch_bin=""
    local output=""
    local queue_output=""
    local exit_status=0
    local queue_exit_status=0
    local jq_bin=""

    rch_bin="$(swarm_status_binary_path rch 2>/dev/null || true)"
    if [[ -z "$rch_bin" ]]; then
        RCH_WARNINGS+=("rch not found in PATH")
        RCH_DURATION_MS="$(swarm_status_duration_ms "$start_ms")"
        return 0
    fi

    RCH_AVAILABLE=true
    output="$(swarm_status_run_with_timeout "$SWARM_STATUS_TIMEOUT" "$rch_bin" status --json)" || exit_status=$?
    if [[ $exit_status -eq 0 && -n "$output" ]]; then
        jq_bin="$(swarm_status_binary_path jq 2>/dev/null || true)"
        if [[ -z "$jq_bin" ]]; then
            RCH_STATUS_JSON_OK=true
            RCH_WARNINGS+=("jq not found; cannot parse RCH pressure details")
        elif printf '%s' "$output" | "$jq_bin" . >/dev/null 2>&1; then
            RCH_STATUS_JSON_OK=true
            swarm_status_parse_rch_status_metrics "$output" "$jq_bin" || RCH_WARNINGS+=("rch status --json metrics could not be parsed")
        else
            RCH_WARNINGS+=("rch status --json returned invalid JSON")
        fi
    else
        RCH_WARNINGS+=("rch status --json failed or timed out")
    fi

    if [[ "$RCH_STATUS_JSON_OK" == true && -n "$jq_bin" ]]; then
        queue_output="$(swarm_status_run_with_timeout "$SWARM_STATUS_TIMEOUT" "$rch_bin" queue --json)" || queue_exit_status=$?
        if [[ $queue_exit_status -eq 0 && -n "$queue_output" ]]; then
            if printf '%s' "$queue_output" | "$jq_bin" . >/dev/null 2>&1; then
                RCH_QUEUE_JSON_OK=true
                swarm_status_parse_rch_queue_metrics "$queue_output" "$jq_bin" || RCH_WARNINGS+=("rch queue --json metrics could not be parsed")
            else
                RCH_WARNINGS+=("rch queue --json returned invalid JSON")
            fi
        else
            RCH_WARNINGS+=("rch queue --json failed or timed out")
        fi
    fi

    if [[ "$RCH_PRESSURE_WARNING_COUNT" =~ ^[0-9]+$ ]] && (( RCH_PRESSURE_WARNING_COUNT > 0 )); then
        RCH_WARNINGS+=("rch reports $RCH_PRESSURE_WARNING_COUNT worker(s) with elevated pressure")
    fi
    if [[ "$RCH_STALE_WORKER_COUNT" =~ ^[0-9]+$ ]] && (( RCH_STALE_WORKER_COUNT > 0 )); then
        RCH_WARNINGS+=("rch reports $RCH_STALE_WORKER_COUNT worker(s) with stale pressure telemetry")
    fi

    if [[ "$RCH_STATUS_JSON_OK" == true && ${#RCH_WARNINGS[@]} -eq 0 ]]; then
        RCH_STATUS="pass"
    fi
    RCH_DURATION_MS="$(swarm_status_duration_ms "$start_ms")"
}

swarm_status_collect_all() {
    swarm_status_collect_host
    swarm_status_collect_ntm
    swarm_status_collect_agent_mail
    swarm_status_collect_beads
    swarm_status_collect_bv
    swarm_status_collect_rch

    SWARM_STATUS_WARNINGS=("${HOST_WARNINGS[@]}" "${NTM_WARNINGS[@]}" "${AGENT_MAIL_WARNINGS[@]}" "${BEADS_WARNINGS[@]}" "${BV_WARNINGS[@]}" "${RCH_WARNINGS[@]}")

    if [[ "$HOST_STATUS" == "fail" || "$NTM_STATUS" == "fail" || "$AGENT_MAIL_STATUS" == "fail" || "$BEADS_STATUS" == "fail" || "$BV_STATUS" == "fail" || "$RCH_STATUS" == "fail" ]]; then
        SWARM_STATUS_OVERALL="fail"
    elif [[ ${#SWARM_STATUS_WARNINGS[@]} -gt 0 ]]; then
        SWARM_STATUS_OVERALL="warn"
    fi
}

swarm_status_emit_json() {
    local jq_bin=""
    jq_bin="$(swarm_status_binary_path jq 2>/dev/null || true)"

    if [[ -z "$jq_bin" ]]; then
        printf '{"schema_version":1,"generated_at":"%s","status":"warn","warnings":["jq not found; full swarm status JSON unavailable"]}\n' "$SWARM_STATUS_GENERATED_AT"
        return 0
    fi

    local warnings_json host_warnings_json ntm_warnings_json agent_mail_warnings_json beads_warnings_json bv_warnings_json rch_warnings_json
    warnings_json="$(swarm_status_json_array "$jq_bin" "${SWARM_STATUS_WARNINGS[@]}")"
    host_warnings_json="$(swarm_status_json_array "$jq_bin" "${HOST_WARNINGS[@]}")"
    ntm_warnings_json="$(swarm_status_json_array "$jq_bin" "${NTM_WARNINGS[@]}")"
    agent_mail_warnings_json="$(swarm_status_json_array "$jq_bin" "${AGENT_MAIL_WARNINGS[@]}")"
    beads_warnings_json="$(swarm_status_json_array "$jq_bin" "${BEADS_WARNINGS[@]}")"
    bv_warnings_json="$(swarm_status_json_array "$jq_bin" "${BV_WARNINGS[@]}")"
    rch_warnings_json="$(swarm_status_json_array "$jq_bin" "${RCH_WARNINGS[@]}")"

    "$jq_bin" -n \
        --arg generated_at "$SWARM_STATUS_GENERATED_AT" \
        --arg status "$SWARM_STATUS_OVERALL" \
        --argjson warnings "$warnings_json" \
        --arg host_status "$HOST_STATUS" \
        --argjson host_warnings "$host_warnings_json" \
        --argjson host_duration_ms "$(swarm_status_json_number "$HOST_DURATION_MS")" \
        --argjson host_cpu_count "$(swarm_status_json_number "$HOST_CPU_COUNT")" \
        --argjson host_load_1m "$HOST_LOAD_1M" \
        --argjson host_mem_total_kb "$(swarm_status_json_number "$HOST_MEM_TOTAL_KB")" \
        --argjson host_mem_available_kb "$(swarm_status_json_number "$HOST_MEM_AVAILABLE_KB")" \
        --argjson host_disk_available_kb "$(swarm_status_json_number "$HOST_DISK_AVAILABLE_KB")" \
        --arg ntm_status "$NTM_STATUS" \
        --argjson ntm_warnings "$ntm_warnings_json" \
        --argjson ntm_duration_ms "$(swarm_status_json_number "$NTM_DURATION_MS")" \
        --argjson ntm_available "$NTM_AVAILABLE" \
        --argjson ntm_robot_status_ok "$NTM_ROBOT_STATUS_OK" \
        --argjson ntm_tmux_available "$NTM_TMUX_AVAILABLE" \
        --argjson ntm_tmux_query_ok "$NTM_TMUX_QUERY_OK" \
        --argjson ntm_tmux_session_count "$NTM_TMUX_SESSION_COUNT" \
        --argjson ntm_tmux_window_count "$NTM_TMUX_WINDOW_COUNT" \
        --arg agent_mail_status "$AGENT_MAIL_STATUS" \
        --argjson agent_mail_warnings "$agent_mail_warnings_json" \
        --argjson agent_mail_duration_ms "$(swarm_status_json_number "$AGENT_MAIL_DURATION_MS")" \
        --argjson agent_mail_available "$AGENT_MAIL_AVAILABLE" \
        --argjson agent_mail_healthy "$AGENT_MAIL_HEALTHY" \
        --arg beads_status "$BEADS_STATUS" \
        --argjson beads_warnings "$beads_warnings_json" \
        --argjson beads_duration_ms "$(swarm_status_json_number "$BEADS_DURATION_MS")" \
        --argjson beads_available "$BEADS_AVAILABLE" \
        --argjson beads_ready_count "$BEADS_READY_COUNT" \
        --argjson beads_in_progress_count "$BEADS_IN_PROGRESS_COUNT" \
        --argjson beads_open_count "$BEADS_OPEN_COUNT" \
        --argjson beads_in_progress_items "$BEADS_IN_PROGRESS_ITEMS_JSON" \
        --arg bv_status "$BV_STATUS" \
        --argjson bv_warnings "$bv_warnings_json" \
        --argjson bv_duration_ms "$(swarm_status_json_number "$BV_DURATION_MS")" \
        --argjson bv_available "$BV_AVAILABLE" \
        --argjson bv_robot_ok "$BV_ROBOT_OK" \
        --arg rch_status "$RCH_STATUS" \
        --argjson rch_warnings "$rch_warnings_json" \
        --argjson rch_duration_ms "$(swarm_status_json_number "$RCH_DURATION_MS")" \
        --argjson rch_available "$RCH_AVAILABLE" \
        --argjson rch_status_json_ok "$RCH_STATUS_JSON_OK" \
        --argjson rch_queue_json_ok "$RCH_QUEUE_JSON_OK" \
        --argjson rch_queue_depth "$(swarm_status_json_number "$RCH_QUEUE_DEPTH")" \
        --argjson rch_active_build_count "$(swarm_status_json_number "$RCH_ACTIVE_BUILD_COUNT")" \
        --argjson rch_workers_total "$(swarm_status_json_number "$RCH_WORKERS_TOTAL")" \
        --argjson rch_workers_healthy "$(swarm_status_json_number "$RCH_WORKERS_HEALTHY")" \
        --argjson rch_workers_busy "$(swarm_status_json_number "$RCH_WORKERS_BUSY")" \
        --argjson rch_workers_offline "$(swarm_status_json_number "$RCH_WORKERS_OFFLINE")" \
        --argjson rch_slots_total "$(swarm_status_json_number "$RCH_SLOTS_TOTAL")" \
        --argjson rch_slots_available "$(swarm_status_json_number "$RCH_SLOTS_AVAILABLE")" \
        --argjson rch_pressure_warning_count "$(swarm_status_json_number "$RCH_PRESSURE_WARNING_COUNT")" \
        --argjson rch_stale_worker_count "$(swarm_status_json_number "$RCH_STALE_WORKER_COUNT")" \
        '{
            schema_version: 1,
            generated_at: $generated_at,
            status: $status,
            warnings: $warnings,
            host: {
                status: $host_status,
                duration_ms: $host_duration_ms,
                warnings: $host_warnings,
                cpu_count: $host_cpu_count,
                load_1m: $host_load_1m,
                mem_total_kb: $host_mem_total_kb,
                mem_available_kb: $host_mem_available_kb,
                disk_available_kb: $host_disk_available_kb
            },
            probes: {
                ntm: {
                    status: $ntm_status,
                    available: $ntm_available,
                    robot_status_ok: $ntm_robot_status_ok,
                    tmux_available: $ntm_tmux_available,
                    tmux_query_ok: $ntm_tmux_query_ok,
                    tmux_session_count: $ntm_tmux_session_count,
                    tmux_window_count: $ntm_tmux_window_count,
                    duration_ms: $ntm_duration_ms,
                    warnings: $ntm_warnings
                },
                agent_mail: {
                    status: $agent_mail_status,
                    available: $agent_mail_available,
                    healthy: $agent_mail_healthy,
                    duration_ms: $agent_mail_duration_ms,
                    warnings: $agent_mail_warnings
                },
                beads: {
                    status: $beads_status,
                    available: $beads_available,
                    ready_count: $beads_ready_count,
                    in_progress_count: $beads_in_progress_count,
                    open_count: $beads_open_count,
                    in_progress_items: $beads_in_progress_items,
                    duration_ms: $beads_duration_ms,
                    warnings: $beads_warnings
                },
                bv: {
                    status: $bv_status,
                    available: $bv_available,
                    robot_ok: $bv_robot_ok,
                    duration_ms: $bv_duration_ms,
                    warnings: $bv_warnings
                },
                rch: {
                    status: $rch_status,
                    available: $rch_available,
                    status_json_ok: $rch_status_json_ok,
                    queue_json_ok: $rch_queue_json_ok,
                    queue_depth: $rch_queue_depth,
                    active_build_count: $rch_active_build_count,
                    workers_total: $rch_workers_total,
                    workers_healthy: $rch_workers_healthy,
                    workers_busy: $rch_workers_busy,
                    workers_offline: $rch_workers_offline,
                    slots_total: $rch_slots_total,
                    slots_available: $rch_slots_available,
                    pressure_warning_count: $rch_pressure_warning_count,
                    stale_worker_count: $rch_stale_worker_count,
                    duration_ms: $rch_duration_ms,
                    warnings: $rch_warnings
                }
            }
        }'
}

swarm_status_emit_human() {
    echo "ACFS Swarm Status"
    echo "Status: $SWARM_STATUS_OVERALL"
    echo "Host: ${HOST_CPU_COUNT} CPU, ${HOST_MEM_AVAILABLE_KB}/${HOST_MEM_TOTAL_KB} KiB memory available"
    echo "NTM/tmux: $NTM_STATUS (${NTM_TMUX_SESSION_COUNT} sessions, ${NTM_TMUX_WINDOW_COUNT} windows)"
    echo "Agent Mail: $AGENT_MAIL_STATUS"
    echo "Beads: $BEADS_STATUS (ready=${BEADS_READY_COUNT}, in_progress=${BEADS_IN_PROGRESS_COUNT}, open=${BEADS_OPEN_COUNT})"
    echo "bv: $BV_STATUS"
    echo "RCH: $RCH_STATUS (queue=${RCH_QUEUE_DEPTH}, active=${RCH_ACTIVE_BUILD_COUNT}, workers=${RCH_WORKERS_HEALTHY}/${RCH_WORKERS_TOTAL}, busy=${RCH_WORKERS_BUSY}, slots=${RCH_SLOTS_AVAILABLE}/${RCH_SLOTS_TOTAL})"
    if [[ ${#SWARM_STATUS_WARNINGS[@]} -gt 0 ]]; then
        echo ""
        echo "Warnings:"
        printf '  - %s\n' "${SWARM_STATUS_WARNINGS[@]}"
    fi
}

swarm_status_main() {
    swarm_status_parse_args "$@"
    if [[ "$SWARM_STATUS_NTM_ONLY" == true ]]; then
        local jq_bin=""
        jq_bin="$(swarm_status_binary_path jq 2>/dev/null || true)"
        [[ -n "$jq_bin" ]] || { echo "Error: jq is required for NTM-only JSON" >&2; return 2; }
        swarm_status_collect_ntm
        swarm_status_emit_json | "$jq_bin" '{schema_version, generated_at, status: .probes.ntm.status, probes: {ntm: .probes.ntm}}'
        return
    fi
    swarm_status_collect_all
    if [[ "$SWARM_STATUS_JSON" == true ]]; then
        swarm_status_emit_json
    else
        swarm_status_emit_human
    fi
}

swarm_status_main "$@"
