#!/bin/bash
# ============================================================
# ACFS Swarm Inventory - advisory local host inventory
#
# Implements the v1 local-first swarm capacity inventory contract.
# Commands read or explicitly write JSON files only; they never launch NTM,
# run RU, send Agent Mail, mutate Beads, or change RCH configuration.
# ============================================================

set -euo pipefail

readonly SWARM_INV_PRIVILEGED_PATH="/usr/sbin:/usr/bin:/sbin:/bin"
if [[ $EUID -eq 0 ]]; then
    export PATH="$SWARM_INV_PRIVILEGED_PATH"
fi

SWARM_INV_SUBCOMMAND="report"
SWARM_INV_SUBCOMMAND_SET=false
SWARM_INV_JSON=false
SWARM_INV_FORMAT="json"
SWARM_INV_INPUT=""
SWARM_INV_OUTPUT=""
SWARM_INV_ARTIFACT_DIR=""
SWARM_INV_AGENTS=""
SWARM_INV_WORKLOAD="standard"
SWARM_INV_WORKLOAD_SET=false
SWARM_INV_INVENTORY_FILE="${ACFS_SWARM_INVENTORY_FILE:-${HOME:-/tmp}/.acfs/swarm/hosts.inventory.json}"
SWARM_INV_GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"

swarm_inventory_usage() {
    cat <<'EOF'
Usage: acfs swarm inventory <report|plan|import|export|validate> [OPTIONS]

Options:
  --json                Emit machine-readable JSON
  --markdown            Emit human output (default)
  --inventory FILE      Inventory file (default: ~/.acfs/swarm/hosts.inventory.json)
  --input FILE          Input file for import
  --output FILE         Output file for import/export
  --format json         Export format (json only for v1)
  --agents N            Required total agent target for plan (1-1000000)
  --workload NAME       Plan workload: light, standard (default), or heavy
  --artifact-dir DIR    Write deterministic error artifacts on failure
  --help, -h            Show this help

Commands are advisory and local-first. They never SSH, launch NTM, run RU,
send Agent Mail, mutate Beads, or change RCH configuration. Import/export
write only to explicit output targets or the canonical inventory file.
Plan distributes a target total across eligible hosts, not additional agents.
It requires fresh live admission on each host before any actual launch.
EOF
}

swarm_inventory_parse_args() {
    if [[ $# -gt 0 ]]; then
        case "$1" in
            report|plan|import|export|validate)
                SWARM_INV_SUBCOMMAND="$1"
                SWARM_INV_SUBCOMMAND_SET=true
                shift
                ;;
            help|-h|--help)
                swarm_inventory_usage
                return 100
                ;;
        esac
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            report|plan|import|export|validate)
                [[ "$SWARM_INV_SUBCOMMAND_SET" == false ]] || { echo "Error: select only one inventory command" >&2; return 2; }
                SWARM_INV_SUBCOMMAND="$1"
                SWARM_INV_SUBCOMMAND_SET=true
                shift
                ;;
            --json)
                SWARM_INV_JSON=true
                shift
                ;;
            --markdown)
                SWARM_INV_JSON=false
                shift
                ;;
            --inventory)
                [[ -n "${2:-}" && "$2" != -* ]] || { echo "Error: --inventory requires a path" >&2; return 2; }
                SWARM_INV_INVENTORY_FILE="$2"
                shift 2
                ;;
            --input)
                [[ -n "${2:-}" && "$2" != -* ]] || { echo "Error: --input requires a path" >&2; return 2; }
                SWARM_INV_INPUT="$2"
                shift 2
                ;;
            --output)
                [[ -n "${2:-}" && "$2" != -* ]] || { echo "Error: --output requires a path" >&2; return 2; }
                SWARM_INV_OUTPUT="$2"
                shift 2
                ;;
            --format)
                [[ -n "${2:-}" && "$2" != -* ]] || { echo "Error: --format requires a value" >&2; return 2; }
                SWARM_INV_FORMAT="$2"
                shift 2
                ;;
            --agents)
                [[ -n "${2:-}" && -z "$SWARM_INV_AGENTS" ]] || { echo "Error: supply --agents once with a positive integer" >&2; return 2; }
                [[ "$2" =~ ^([1-9][0-9]{0,5}|1000000)$ ]] || { echo "Error: --agents must be an integer from 1 to 1000000" >&2; return 2; }
                SWARM_INV_AGENTS="$2"
                shift 2
                ;;
            --workload)
                [[ -n "${2:-}" && "$SWARM_INV_WORKLOAD_SET" == false ]] || { echo "Error: supply --workload once" >&2; return 2; }
                case "$2" in light|standard|heavy) ;; *) echo "Error: workload must be light, standard, or heavy" >&2; return 2 ;; esac
                SWARM_INV_WORKLOAD="$2"
                SWARM_INV_WORKLOAD_SET=true
                shift 2
                ;;
            --artifact-dir)
                [[ -n "${2:-}" && "$2" != -* ]] || { echo "Error: --artifact-dir requires a directory" >&2; return 2; }
                SWARM_INV_ARTIFACT_DIR="$2"
                shift 2
                ;;
            --help|-h)
                swarm_inventory_usage
                return 100
                ;;
            *)
                echo "Error: unknown option: $1" >&2
                echo "Run 'acfs swarm inventory --help' for usage." >&2
                return 2
                ;;
        esac
    done

    case "$SWARM_INV_SUBCOMMAND" in
        report|plan|import|export|validate) ;;
        *)
            echo "Error: unknown inventory subcommand: $SWARM_INV_SUBCOMMAND" >&2
            return 2
            ;;
    esac

    if [[ "$SWARM_INV_FORMAT" != "json" ]]; then
        echo "Error: unsupported inventory format: $SWARM_INV_FORMAT" >&2
        return 2
    fi

    if [[ "$SWARM_INV_SUBCOMMAND" == plan ]]; then
        [[ -n "$SWARM_INV_AGENTS" ]] || { echo "Error: plan requires --agents N" >&2; return 2; }
        [[ -z "$SWARM_INV_INPUT" && -z "$SWARM_INV_OUTPUT" && -z "$SWARM_INV_ARTIFACT_DIR" ]] || {
            echo "Error: plan is read-only; --input, --output, and --artifact-dir do not apply" >&2
            return 2
        }
    elif [[ -n "$SWARM_INV_AGENTS" || "$SWARM_INV_WORKLOAD_SET" == true ]]; then
        echo "Error: --agents and --workload require the plan command" >&2
        return 2
    fi
}

swarm_inventory_binary_path() {
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

swarm_inventory_read_single_json() {
    local path="$2"
    local python_bin=""

    # jq discards duplicate keys before validation. Read the original bytes
    # first so a second can_launch/status/capacity value cannot hide a veto.
    python_bin="$(swarm_inventory_binary_path python3)" || return 1
    "$python_bin" -I - "$path" <<'PY'
import json
import math
import os
import stat
import sys


def reject(*_):
    raise ValueError("invalid inventory")


def unique(pairs):
    value = {}
    for key, item in pairs:
        if key in value or any(0xD800 <= ord(c) <= 0xDFFF for c in key):
            reject()
        value[key] = item
    return value


try:
    fd = os.open(sys.argv[1], os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > 1048576:
            reject()
        data = stream.read(1048577)
    if len(data) > 1048576:
        reject()
    value = json.loads(data.decode("utf-8"), object_pairs_hook=unique, parse_constant=reject)
    pending = [(value, 0)]
    nodes = 0
    while pending:
        item, depth = pending.pop()
        nodes += 1
        if depth > 32 or nodes > 50000:
            reject()
        if isinstance(item, dict):
            pending.extend((child, depth + 1) for child in item.values())
        elif isinstance(item, list):
            pending.extend((child, depth + 1) for child in item)
        elif isinstance(item, float) and not math.isfinite(item):
            reject()
        elif isinstance(item, str) and any(0xD800 <= ord(c) <= 0xDFFF for c in item):
            reject()
    print(json.dumps(value, separators=(",", ":"), ensure_ascii=True, allow_nan=False))
except (OSError, ValueError, RecursionError):
    # Do not echo untrusted JSON, paths, or parser errors containing secrets.
    sys.exit(1)
PY
}

swarm_inventory_parent_dir() {
    local path="$1"
    local dir=""

    dir="$(dirname -- "$path")"
    [[ -n "$dir" && "$dir" != "." ]] || return 0
    mkdir -p -- "$dir"
}

swarm_inventory_sync_path() {
    local sync_bin="$1"
    local path="$2"

    # GNU coreutils accepts a file operand and fsyncs only that file. BSD sync
    # accepts no operands, so retain a portable (but broader) fallback there.
    if "$sync_bin" --version >/dev/null 2>&1; then
        "$sync_bin" "$path"
    else
        "$sync_bin"
    fi
}

swarm_inventory_atomic_write() {
    local output_file="$1"
    local contents="$2"
    local parent_dir=""
    local temp_file=""
    local sync_bin=""

    parent_dir="$(dirname -- "$output_file")"
    [[ -n "$parent_dir" ]] || return 1
    swarm_inventory_parent_dir "$output_file" || return 1

    # Never follow or replace a pre-existing special path. Replacing a regular
    # file by rename is atomic and avoids the truncation window of `> "$path"`.
    if [[ -e "$output_file" || -L "$output_file" ]]; then
        [[ -f "$output_file" && ! -L "$output_file" ]] || return 1
    fi

    temp_file="$(mktemp "$parent_dir/.swarm_inventory.XXXXXX")" || return 1
    if ! printf '%s\n' "$contents" > "$temp_file"; then
        rm -f -- "$temp_file" 2>/dev/null || true
        return 1
    fi

    # Flush the complete temporary file before publishing it. On the supported
    # GNU target this is a file-scoped fsync, avoiding a system-wide writeback.
    sync_bin="$(swarm_inventory_binary_path sync 2>/dev/null || true)"
    if [[ -z "$sync_bin" ]] || ! swarm_inventory_sync_path "$sync_bin" "$temp_file"; then
        rm -f -- "$temp_file" 2>/dev/null || true
        return 1
    fi

    if ! mv -- "$temp_file" "$output_file"; then
        rm -f -- "$temp_file" 2>/dev/null || true
        return 1
    fi

    # Persist the rename itself before reporting success. If this barrier fails,
    # preserve the already-published valid file and report durability uncertainty.
    swarm_inventory_sync_path "$sync_bin" "$parent_dir"
}

swarm_inventory_error_json() {
    local jq_bin="$1"
    local operation="$2"
    local error_code="$3"
    local message="$4"
    local redacted_paths_json="${5:-[]}"
    local next_commands_json="${6:-[]}"

    "$jq_bin" -n \
        --arg operation "$operation" \
        --arg error_code "$error_code" \
        --arg message "$message" \
        --argjson redacted_field_paths "$redacted_paths_json" \
        --argjson next_commands "$next_commands_json" \
        '{
            schema_version: 1,
            operation: $operation,
            status: "fail",
            error_code: $error_code,
            message: $message,
            redacted_field_paths: $redacted_field_paths,
            next_commands: $next_commands,
            advisory_only: true,
            mutations: {
              ntm: false,
              ru: false,
              agent_mail: false,
              beads: false,
              rch_config: false
            }
          }'
}

swarm_inventory_write_error_artifacts() {
    local operation="$1"
    local error_json="$2"
    local error_file=""
    local log_file=""

    [[ -n "$SWARM_INV_ARTIFACT_DIR" ]] || return 0
    mkdir -p "$SWARM_INV_ARTIFACT_DIR"
    error_file="$SWARM_INV_ARTIFACT_DIR/swarm_inventory.$operation.error.json"
    log_file="$SWARM_INV_ARTIFACT_DIR/swarm_inventory.$operation.log"
    printf '%s\n' "$error_json" > "$error_file"
    printf 'operation=%s\nstatus=fail\nerror_file=%s\n' "$operation" "$error_file" > "$log_file"
}

swarm_inventory_fail() {
    local jq_bin="$1"
    local operation="$2"
    local error_code="$3"
    local message="$4"
    local redacted_paths_json="${5:-[]}"
    local next_commands_json="${6:-[]}"
    local error_json=""

    error_json="$(swarm_inventory_error_json "$jq_bin" "$operation" "$error_code" "$message" "$redacted_paths_json" "$next_commands_json")"
    swarm_inventory_write_error_artifacts "$operation" "$error_json"
    if [[ "$SWARM_INV_JSON" == true ]]; then
        printf '%s\n' "$error_json"
    else
        echo "Error: $message" >&2
    fi
    return 2
}

swarm_inventory_validation_json() {
    local jq_bin="$1"
    local inventory_json="$2"
    local source_file="$3"

    "$jq_bin" \
        --arg source_file "$source_file" \
        '
        def pathstr($p):
          reduce $p[] as $x ("";
            . + if ($x | type) == "number" then "[" + ($x | tostring) + "]"
                elif . == "" then $x
                else "." + $x end);
        def err($code; $path; $message): {code: $code, path: $path, message: $message};
        def sensitive_names: [
          "hostname", "ip", "address", "ssh_key", "private_key", "token",
          "password", "credential", "provider_api_key", "project_path", "home",
          "username", "ssh_username", "sshusername", "provider_id", "providerid",
          "provider_account_id", "provideraccountid", "account_id", "accountid"
        ];
        def role_ok($v): ($v | IN("swarm-controller", "swarm-worker", "rch-worker", "support", "disabled"));
        def status_ok($v): ($v | IN("active", "stale", "disabled", "unknown"));
        def id_ok($v):
          if ($v | type) != "string" then false
          else ($v | test("^[a-z0-9][a-z0-9._-]{0,62}$")) end;
        def is_object($v): (($v | type) == "object");
        def stale_hours_ok($v):
          if ($v | type) != "number" then false
          else ($v >= 1 and $v <= 8760 and ($v | floor) == $v) end;
        def counter_ok($v):
          if ($v | type) != "number" then false
          else ($v >= 0 and $v <= 1000000 and ($v | floor) == $v) end;
        def workload_ok($v): ($v | IN("light", "standard", "heavy"));
        def unknown_count($obj; $allowed):
          if ($obj | type) == "object" then
            ([($obj | keys_unsorted[]) as $k | select(($allowed | index($k)) | not)] | length)
          else 0 end;
        . as $inventory
        | ($inventory | type) as $inventory_type
        | (if $inventory_type == "object" then $inventory else {} end) as $inventory_obj
        | (if $inventory_type == "object" then [] else
             [err("invalid_inventory"; ""; "inventory must be an object")]
           end) as $inventory_errors
        | (if ($inventory_obj | has("defaults")) then $inventory_obj.defaults else null end) as $defaults_raw
        | (if ($defaults_raw | type) == "object" then $defaults_raw else {} end) as $defaults
        | ($inventory_obj.hosts // null) as $hosts
        | (if ($inventory_obj.schema_version // null) == 1 then [] else [err("unsupported_schema_version"; "schema_version"; "schema_version must be 1")] end) as $schema_errors
        | (if $defaults_raw == null or ($defaults_raw | type) == "object" then [] else
             [err("invalid_defaults"; "defaults"; "defaults must be an object")]
           end) as $defaults_errors
        | (if (($defaults | has("stale_after_hours")) | not) then []
           elif stale_hours_ok($defaults.stale_after_hours) then []
           else [err("invalid_stale_after_hours"; "defaults.stale_after_hours"; "stale_after_hours must be a positive integer")]
           end) as $stale_hours_errors
        | (if (($defaults | has("workload")) | not) or workload_ok($defaults.workload) then []
           else [err("invalid_workload"; "defaults.workload"; "workload must be light, standard, or heavy when present")]
           end) as $workload_errors
        | (if ($hosts | type) == "array" then [] else [err("invalid_hosts"; "hosts"; "hosts must be an array")] end) as $host_array_errors
        | (if ($hosts | type) == "array" then $hosts else [] end) as $host_list
        | ([
            $inventory_obj
            | paths as $p
            | select(($p | length) > 0 and (($p[-1] | type) == "string"))
            | ($p[-1] | ascii_downcase) as $key
            # Exact names, plus any key that merely contains a sensitive stem
            # (ip_address, tailscale_ip, ssh_host, api_key, apiKey, home_dir,
            # notes_password ...). The exact-match list alone let all of
            # those through while the docs promised they were rejected.
            | select((sensitive_names | index($key))
                     or ($key | test("(^|[_.-])(host|hostname|ip|ipv4|ipv6|addr|address|ssh|key|token|secret|pass|passwd|password|cred|credential|home|path|user)([_.-]|$)"))
                     or ($p[-1] | test("[a-z](Host|Ip|Addr|Key|Token|Secret|Pass|Cred|Home|Path|User|Username|AccountId|ProviderId|ProviderAccountId)([A-Z]|$)")))
            | pathstr($p)
          ] + [
            # Values that look like network endpoints or credentials, whatever
            # the key is called (free-text notes are the usual leak).
            $inventory_obj
            | paths(type == "string") as $p
            | select(getpath($p) | test("(^|[^0-9.])[0-9]{1,3}(\\.[0-9]{1,3}){3}([^0-9.]|$)|[0-9a-f]{0,4}(:[0-9a-f]{0,4}){5,7}|(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|github_pat_|tskey-|sk-[A-Za-z0-9]{20,}|hvs\\.|xox[bpsar]-|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|(ssh|scp) +[A-Za-z0-9._-]+@"; "i"))
            | pathstr($p)
          ] | unique) as $sensitive_paths
        | ($host_list | map(select(type == "object") | select((.id | type) == "string") | .id) | group_by(.) | map(select(length > 1) | .[0])) as $duplicates
        | [
            $host_list | to_entries[] | . as $entry
            | ($entry.key) as $idx
            | ($entry.value) as $h
            | if ($h | type) != "object" then
                err("invalid_host"; "hosts[" + ($idx | tostring) + "]"; "host must be an object")
              else
                (if id_ok($h.id) then empty else
                   err("invalid_host_id"; "hosts[" + ($idx | tostring) + "].id"; "host id must match ^[a-z0-9][a-z0-9._-]{0,62}$")
                 end),
                (if role_ok($h.role) then empty else
                   err("invalid_role"; "hosts[" + ($idx | tostring) + "].role"; "unsupported host role")
                 end),
                (if status_ok($h.status) then empty else
                   err("invalid_status"; "hosts[" + ($idx | tostring) + "].status"; "unsupported host status")
                 end),
                (if (($h.last_probe_at == null) or (($h.last_probe_at | type) == "string")) then empty else
                   err("invalid_last_probe_at"; "hosts[" + ($idx | tostring) + "].last_probe_at"; "last_probe_at must be string or null")
                 end),
                (if is_object($h.resources) then empty else
                   err("invalid_resources"; "hosts[" + ($idx | tostring) + "].resources"; "resources must be an object")
                 end),
                (if is_object($h.capacity) then empty else
                   err("invalid_capacity"; "hosts[" + ($idx | tostring) + "].capacity"; "capacity must be an object")
                 end),
                (if is_object($h.rch) then empty else
                   err("invalid_rch"; "hosts[" + ($idx | tostring) + "].rch"; "rch must be an object")
                 end),
                (if is_object($h.ntm) then empty else
                   err("invalid_ntm"; "hosts[" + ($idx | tostring) + "].ntm"; "ntm must be an object")
                 end),
                (if is_object($h.ru) then empty else
                   err("invalid_ru"; "hosts[" + ($idx | tostring) + "].ru"; "ru must be an object")
                 end),
                (if is_object($h.capacity) then
                   if (($h.capacity | has("workload")) | not) or workload_ok($h.capacity.workload) then empty else
                     err("invalid_workload"; "hosts[" + ($idx | tostring) + "].capacity.workload"; "workload must be light, standard, or heavy when present")
                   end
                 else empty end),
                (if is_object($h.capacity) then
                   ["recommended_agents", "safe_agents"][] as $key
                   | if $h.capacity[$key] == null or counter_ok($h.capacity[$key]) then empty else
                       err("invalid_capacity_counter"; "hosts[" + ($idx | tostring) + "].capacity." + $key; "capacity counters must be integers from 0 to 1000000 or null")
                     end
                 else empty end),
                (if is_object($h.ntm) then
                   if $h.ntm.can_launch == null or ($h.ntm.can_launch | type) == "boolean" then empty else
                     err("invalid_launch_flag"; "hosts[" + ($idx | tostring) + "].ntm.can_launch"; "can_launch must be boolean or null")
                   end
                 else empty end)
              end
          ] as $field_errors
        | ($sensitive_paths | map(err("forbidden_sensitive_field"; .; "Inventory contains forbidden sensitive field name"))) as $sensitive_errors
        | ($duplicates | map(err("duplicate_host_id"; "hosts[].id"; "duplicate host id: " + .))) as $duplicate_errors
        | ($inventory_errors + $schema_errors + $defaults_errors + $stale_hours_errors + $workload_errors + $host_array_errors + $field_errors + $sensitive_errors + $duplicate_errors) as $errors
        | {
            schema_version: 1,
            source_file: $source_file,
            status: (if ($errors | length) > 0 then "fail" else "pass" end),
            errors: $errors,
            forbidden_sensitive_field_paths: $sensitive_paths,
            duplicate_ids: $duplicates,
            unknown_field_count: (
              unknown_count($inventory_obj; ["schema_version", "updated_at", "defaults", "hosts"])
              + ([ $host_list[]? | unknown_count(.; ["id", "display_name", "role", "status", "manual_tags", "last_probe_at", "probe_source", "resources", "capacity", "rch", "ntm", "ru", "notes"]) ] | add // 0)
            ),
            warnings: []
          }
        ' <<< "$inventory_json"
}

swarm_inventory_report_json() {
    local jq_bin="$1"
    local inventory_json="$2"
    local validation_json="$3"
    local inventory_file="$4"

    # Feed documents through stdin, not argv (large inventories exceed ARG_MAX).
    printf '%s\n' "$inventory_json" "$validation_json" | "$jq_bin" -s \
        --arg generated_at "$SWARM_INV_GENERATED_AT" \
        --arg inventory_file "$inventory_file" \
        '
        def n($v):
          if ($v | type) == "number" then $v
          elif ($v | type) != "string" then 0
          elif ($v | test("^[0-9]+$")) then ($v | tonumber)
          else 0 end;
        def ts($s):
          if ($s | type) != "string" then null
          elif ($s | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) | not then null
          else (try ($s | fromdateiso8601) catch null) as $t
            | if $t == null then null
              elif ($t | strftime("%Y-%m-%dT%H:%M:%SZ")) == $s then $t else null end
          end;
        def launch_role($role): ($role | IN("swarm-controller", "swarm-worker", "support"));
        .[0] as $inventory | .[1] as $validation
        | ts($generated_at) as $evaluated_at
        | ($inventory.hosts // []) as $hosts
        | (($inventory.defaults.stale_after_hours // 24) | tonumber) as $stale_hours
        | [
            $hosts[]
            | . as $h
            | ((ts($h.last_probe_at)) as $probe_ts
              | (if $probe_ts == null or $evaluated_at == null then "unknown"
                 elif $probe_ts > $evaluated_at then "future"
                 elif ($evaluated_at - $probe_ts) >= ($stale_hours * 3600) then "stale"
                 else "fresh" end) as $probe_state
              | [
                  (if $h.status != "active" then "host_not_active" else empty end),
                  (if launch_role($h.role) | not then "role_not_launchable" else empty end),
                  (if $h.ntm.can_launch != true then "launch_not_enabled" else empty end),
                  (if $probe_state != "fresh" then "probe_" + $probe_state else empty end),
                  (if $h.capacity.recommended_agents == null or $h.capacity.safe_agents == null
                   then "capacity_unknown" else empty end),
                  (if $h.capacity.recommended_agents == 0 or $h.capacity.safe_agents == 0
                   then "capacity_exhausted" else empty end)
                ] as $exclusions
              | {
                  id: $h.id,
                  display_name: ($h.display_name // $h.id),
                  role: $h.role,
                  status: $h.status,
                  stale_probe: ($probe_state == "stale"),
                  probe_state: $probe_state,
                  last_probe_at: $h.last_probe_at,
                  eligible: ($exclusions | length == 0),
                  exclusion_reasons: $exclusions,
                  recommended_agents: (
                    if ($exclusions | length) == 0
                    then ([$h.capacity.recommended_agents, $h.capacity.safe_agents] | min) else 0 end
                  ),
                  safe_agents: (
                    if ($exclusions | length) == 0 then $h.capacity.safe_agents else 0 end
                  ),
                  capacity: {
                    workload: ($h.capacity.workload // ($inventory.defaults.workload // "standard")),
                    source: ($h.capacity.source // null)
                  },
                  rch: {
                    worker: ($h.rch.worker // false),
                    controller: ($h.rch.controller // false),
                    slots_total: (n($h.rch.slots_total)),
                    slots_available: (n($h.rch.slots_available)),
                    workers_total: (n($h.rch.workers_total)),
                    workers_healthy: (n($h.rch.workers_healthy))
                  },
                  ntm: {
                    can_launch: ($h.ntm.can_launch // false),
                    preferred_labels: ($h.ntm.preferred_labels // [])
                  },
                  ru: {
                    can_sync_repos: ($h.ru.can_sync_repos // false)
                  }
                })
          ] as $report_hosts
        | [$report_hosts[] | select(.stale_probe == true)] as $stale_probe_hosts
        | [$report_hosts[] | select(.role == "rch-worker" or .rch.worker == true)] as $rch_workers
        | [$report_hosts[] | select(.recommended_agents > 0)] as $launch_targets
        | (
            (if ($hosts | length) == 0 then ["inventory has no hosts; import or add host records before planning a swarm"] else [] end)
            + ($stale_probe_hosts | map("host " + .id + " has stale probe data older than " + ($stale_hours | tostring) + "h"))
            + ([$report_hosts[] | select(.status == "active" and (.role | launch_role(.)) and .eligible == false)
                | (.exclusion_reasons - ["probe_stale"]) as $other_reasons
                | select(($other_reasons | length) > 0)
                | "host " + .id + " excluded: " + ($other_reasons | join(", "))])
          ) as $warnings
        | {
            schema_version: 1,
            generated_at: $generated_at,
            status: (if $validation.status == "fail" then "fail" elif ($warnings | length) > 0 then "warn" else "pass" end),
            inventory_file: $inventory_file,
            advisory_only: true,
            evidence: {source: "operator_inventory", live_verified: false, requires_live_admission: true},
            mutations: {
              ntm: false,
              ru: false,
              agent_mail: false,
              beads: false,
              rch_config: false
            },
            summary: {
              hosts_total: ($hosts | length),
              active: ([$hosts[] | select(.status == "active")] | length),
              stale: ([$hosts[] | select(.status == "stale")] | length),
              disabled: ([$hosts[] | select(.status == "disabled" or .role == "disabled")] | length),
              stale_probe_count: ($stale_probe_hosts | length),
              recommended_agents_total: ([$launch_targets[].recommended_agents] | add // 0),
              safe_agents_total: ([$launch_targets[].safe_agents] | add // 0),
              rch_workers: ($rch_workers | length),
              unknown_field_count: ($validation.unknown_field_count // 0)
            },
            role_counts: ($report_hosts | group_by(.role) | map({key: .[0].role, value: length}) | from_entries),
            status_counts: ($report_hosts | group_by(.status) | map({key: .[0].status, value: length}) | from_entries),
            recommended_launch_targets: $launch_targets,
            hosts: $report_hosts,
            warnings: $warnings,
            next_commands: (
              if ($hosts | length) == 0 then
                ["acfs swarm inventory import --input hosts.inventory.json", "acfs capacity --json --recommend-ntm"]
              else
                ["acfs capacity --json --recommend-ntm", "rch status --json", "acfs swarm plan --agents 25"]
              end
            )
          }
        '
}

swarm_inventory_emit_report_human() {
    local report_json="$1"
    local jq_bin="$2"

    "$jq_bin" -r '
      "ACFS Swarm Host Inventory",
      "Status: \(.status)",
      "Hosts: \(.summary.active) active, \(.summary.stale) stale, \(.summary.disabled) disabled",
      "",
      "Recommended Launch Targets",
      (if (.recommended_launch_targets | length) == 0 then
        "  None"
      else
        (.recommended_launch_targets[] | "  \(.id): \(.recommended_agents) recorded agents, safe max \(.safe_agents), role \(.role)")
      end),
      "Recorded capacity only. Recheck live admission on each target before launching.",
      "",
      "Warnings",
      (if (.warnings | length) == 0 then
        "  - None"
      else
        (.warnings[] | "  - \(.)")
      end)
    ' <<< "$report_json"
}

swarm_inventory_emit_action_human() {
    local action_json="$1"
    local jq_bin="$2"

    "$jq_bin" -r '
      "ACFS Swarm Inventory \(.operation)",
      "Status: \(.status)",
      (if .input_file then "Input: \(.input_file)" else empty end),
      (if .output_file then "Output: \(.output_file)" else empty end),
      (if .inventory_file then "Inventory: \(.inventory_file)" else empty end),
      (if .summary then "Hosts: \(.summary.hosts_total // .summary.imported_hosts // .summary.exported_hosts // 0)" else empty end),
      "Advisory only: no NTM, RU, Agent Mail, Beads, or RCH state was mutated."
    ' <<< "$action_json"
}

swarm_inventory_read_inventory_or_fail() {
    local -n result_ref="$1"
    local jq_bin="$2"
    local operation="$3"
    local path="$4"
    local loaded_json=""
    local next_commands_json='["acfs swarm inventory import --input hosts.inventory.json"]'

    if [[ ! -f "$path" ]]; then
        swarm_inventory_fail "$jq_bin" "$operation" "inventory_missing" "Inventory file not found: $path" "[]" "$next_commands_json"
        return 2
    fi

    if ! loaded_json="$(swarm_inventory_read_single_json "$jq_bin" "$path")"; then
        swarm_inventory_fail "$jq_bin" "$operation" "malformed_json" "Inventory file is malformed JSON: $path" "[]" "$next_commands_json"
        return 2
    fi

    result_ref="$loaded_json"
}

swarm_inventory_validate_or_fail() {
    local -n result_ref="$1"
    local jq_bin="$2"
    local operation="$3"
    local inventory_json="$4"
    local source_file="$5"
    local validation_result_json=""
    local forbidden_paths_json=""
    local first_message=""
    local next_commands_json='["acfs swarm inventory validate --json"]'

    validation_result_json="$(swarm_inventory_validation_json "$jq_bin" "$inventory_json" "$source_file")"
    if [[ "$("$jq_bin" -r '.status' <<< "$validation_result_json")" != "pass" ]]; then
        forbidden_paths_json="$("$jq_bin" -c '.forbidden_sensitive_field_paths // []' <<< "$validation_result_json")"
        first_message="$("$jq_bin" -r '.errors[0].message // "Inventory validation failed"' <<< "$validation_result_json")"
        swarm_inventory_fail "$jq_bin" "$operation" "$("$jq_bin" -r '.errors[0].code // "validation_failed"' <<< "$validation_result_json")" "$first_message" "$forbidden_paths_json" "$next_commands_json"
        return 2
    fi

    result_ref="$validation_result_json"
}

swarm_inventory_command_report() {
    local jq_bin="$1"
    local inventory_json=""
    local validation_json=""
    local report_json=""

    swarm_inventory_read_inventory_or_fail inventory_json "$jq_bin" "report" "$SWARM_INV_INVENTORY_FILE" || return $?
    swarm_inventory_validate_or_fail validation_json "$jq_bin" "report" "$inventory_json" "$SWARM_INV_INVENTORY_FILE" || return $?
    report_json="$(swarm_inventory_report_json "$jq_bin" "$inventory_json" "$validation_json" "$SWARM_INV_INVENTORY_FILE")"

    if [[ "$SWARM_INV_JSON" == true ]]; then
        printf '%s\n' "$report_json"
    else
        swarm_inventory_emit_report_human "$report_json" "$jq_bin"
    fi

    [[ "$("$jq_bin" -r '.status' <<< "$report_json")" == "pass" ]] || return 1
}

swarm_inventory_command_validate() {
    local jq_bin="$1"
    local inventory_json=""
    local validation_json=""

    swarm_inventory_read_inventory_or_fail inventory_json "$jq_bin" "validate" "$SWARM_INV_INVENTORY_FILE" || return $?
    validation_json="$(swarm_inventory_validation_json "$jq_bin" "$inventory_json" "$SWARM_INV_INVENTORY_FILE")"

    if [[ "$("$jq_bin" -r '.status' <<< "$validation_json")" != "pass" ]]; then
        swarm_inventory_write_error_artifacts "validate" "$(swarm_inventory_error_json "$jq_bin" "validate" "$("$jq_bin" -r '.errors[0].code // "validation_failed"' <<< "$validation_json")" "$("$jq_bin" -r '.errors[0].message // "Inventory validation failed"' <<< "$validation_json")" "$("$jq_bin" -c '.forbidden_sensitive_field_paths // []' <<< "$validation_json")" '["acfs swarm inventory validate --json"]')"
    fi

    if [[ "$SWARM_INV_JSON" == true ]]; then
        printf '%s\n' "$validation_json"
    else
        swarm_inventory_emit_action_human "$("$jq_bin" '{operation:"validate", status:.status, inventory_file:.source_file, summary:{hosts_total:0}}' <<< "$validation_json")" "$jq_bin"
    fi

    [[ "$("$jq_bin" -r '.status' <<< "$validation_json")" == "pass" ]] || return 2
}

swarm_inventory_command_plan() {
    local jq_bin="$1"
    local inventory_json="" validation_json="" report_json="" plan_json=""

    swarm_inventory_read_inventory_or_fail inventory_json "$jq_bin" "plan" "$SWARM_INV_INVENTORY_FILE" || return $?
    swarm_inventory_validate_or_fail validation_json "$jq_bin" "plan" "$inventory_json" "$SWARM_INV_INVENTORY_FILE" || return $?
    report_json="$(swarm_inventory_report_json "$jq_bin" "$inventory_json" "$validation_json" "$SWARM_INV_INVENTORY_FILE")" || return 2
    # One shared eligibility calculation drives both the report and placement.
    # Pack the largest recorded headroom first to minimize coordination hosts;
    # host IDs break ties so input order never decides an allocation.
    plan_json="$("$jq_bin" --argjson requested "$SWARM_INV_AGENTS" --arg workload "$SWARM_INV_WORKLOAD" '
      . as $report
      | [.hosts[]
          | .exclusion_reasons += (if .capacity.workload == $workload then [] else ["workload_mismatch"] end)
          | .eligible = (.exclusion_reasons | length == 0)] as $hosts
      | ([$hosts[] | select(.eligible)] | sort_by(-.recommended_agents, .id)) as $eligible
      | (reduce $eligible[] as $h ({remaining: $requested, allocations: []};
          ([.remaining, $h.recommended_agents] | min) as $count
          | if $count == 0 then . else
              .remaining -= $count
              | .allocations += [{
                  host_id: $h.id,
                  agents: $count,
                  recorded_recommendation: $h.recommended_agents,
                  safe_agents: $h.safe_agents,
                  last_probe_at: $h.last_probe_at,
                  live_admission_command: ("acfs swarm plan --agents " + ($count | tostring) + " --workload " + $workload + " --json")
                }]
            end)) as $placement
      | {
          schema_version: 1, operation: "plan",
          status: (if $placement.remaining == 0 then "pass" else "warn" end),
          generated_at: $report.generated_at,
          strategy: "largest-recorded-headroom-first",
          allocation_semantics: "target_totals_not_additional_agents",
          requested_agents: $requested, workload: $workload,
          assigned_agents: ($requested - $placement.remaining),
          unassigned_agents: $placement.remaining,
          fully_placed: ($placement.remaining == 0),
          recorded_capacity_total: ([$eligible[].recommended_agents] | add // 0),
          allocations: $placement.allocations,
          excluded_hosts: ([$hosts[] | select(.eligible | not) | {id, reasons: .exclusion_reasons}] | sort_by(.id)),
          warnings: ($report.warnings + (if $placement.remaining > 0 then ["Insufficient eligible recorded capacity; no host limit was exceeded."] else [] end)),
          evidence: $report.evidence, advisory_only: true, mutations: $report.mutations
        }
    ' <<< "$report_json")" || return 2

    if [[ "$SWARM_INV_JSON" == true ]]; then
        printf '%s\n' "$plan_json"
    else
        "$jq_bin" -r '
          "ACFS Fleet Placement (recorded capacity only)",
          "Status: \(.status); target: \(.requested_agents) \(.workload) agents",
          "Placed: \(.assigned_agents); unassigned: \(.unassigned_agents)",
          "Allocations are target totals, NOT additional agents to spawn.",
          (.allocations[] | "  \(.host_id): \(.agents) agents (recorded limit \(.recorded_recommendation))\n    Recheck ON THAT HOST: \(.live_admission_command)"),
          (.excluded_hosts[] | "  Excluded \(.id): \(.reasons | join(", "))"),
          "No agents launched. Inventory cannot authorize a live launch."
        ' <<< "$plan_json"
    fi
    [[ "$("$jq_bin" -r .fully_placed <<< "$plan_json")" == true ]] || return 1
}

swarm_inventory_command_import() {
    local jq_bin="$1"
    local input_file="$SWARM_INV_INPUT"
    local output_file="${SWARM_INV_OUTPUT:-$SWARM_INV_INVENTORY_FILE}"
    local inventory_json=""
    local validation_json=""
    local normalized_json=""
    local action_json=""

    if [[ -z "$input_file" ]]; then
        swarm_inventory_fail "$jq_bin" "import" "missing_input" "import requires --input FILE" "[]" '["acfs swarm inventory import --input hosts.inventory.json"]'
        return 2
    fi

    swarm_inventory_read_inventory_or_fail inventory_json "$jq_bin" "import" "$input_file" || return $?
    swarm_inventory_validate_or_fail validation_json "$jq_bin" "import" "$inventory_json" "$input_file" || return $?
    normalized_json="$("$jq_bin" --arg updated_at "$SWARM_INV_GENERATED_AT" '.updated_at = $updated_at' <<< "$inventory_json")"
    if ! swarm_inventory_atomic_write "$output_file" "$normalized_json"; then
        swarm_inventory_fail "$jq_bin" "import" "write_failed" "Could not atomically and durably write inventory: $output_file" "[]" '[]'
        return 2
    fi

    action_json="$(printf '%s\n' "$normalized_json" "$validation_json" | "$jq_bin" -s \
        --arg input_file "$input_file" \
        --arg output_file "$output_file" \
        '.[0] as $inventory | .[1] as $validation | {
          schema_version: 1,
          operation: "import",
          status: "pass",
          input_file: $input_file,
          output_file: $output_file,
          summary: {
            imported_hosts: (($inventory.hosts // []) | length),
            unknown_field_count: ($validation.unknown_field_count // 0)
          },
          advisory_only: true,
          mutations: {ntm:false, ru:false, agent_mail:false, beads:false, rch_config:false}
        }')"

    if [[ "$SWARM_INV_JSON" == true ]]; then
        printf '%s\n' "$action_json"
    else
        swarm_inventory_emit_action_human "$action_json" "$jq_bin"
    fi
}

swarm_inventory_command_export() {
    local jq_bin="$1"
    local output_file="$SWARM_INV_OUTPUT"
    local inventory_json=""
    local validation_json=""
    local export_json=""
    local action_json=""

    swarm_inventory_read_inventory_or_fail inventory_json "$jq_bin" "export" "$SWARM_INV_INVENTORY_FILE" || return $?
    swarm_inventory_validate_or_fail validation_json "$jq_bin" "export" "$inventory_json" "$SWARM_INV_INVENTORY_FILE" || return $?
    export_json="$("$jq_bin" --arg updated_at "$SWARM_INV_GENERATED_AT" '.updated_at = $updated_at' <<< "$inventory_json")"

    if [[ -n "$output_file" ]]; then
        if ! swarm_inventory_atomic_write "$output_file" "$export_json"; then
            swarm_inventory_fail "$jq_bin" "export" "write_failed" "Could not atomically and durably write export: $output_file" "[]" '[]'
            return 2
        fi
    else
        printf '%s\n' "$export_json"
    fi

    action_json="$(printf '%s\n' "$export_json" "$validation_json" | "$jq_bin" -s \
        --arg inventory_file "$SWARM_INV_INVENTORY_FILE" \
        --arg output_file "$output_file" \
        '.[0] as $inventory | .[1] as $validation | {
          schema_version: 1,
          operation: "export",
          status: "pass",
          inventory_file: $inventory_file,
          output_file: (if $output_file == "" then null else $output_file end),
          summary: {
            exported_hosts: (($inventory.hosts // []) | length),
            unknown_field_count: ($validation.unknown_field_count // 0)
          },
          advisory_only: true,
          mutations: {ntm:false, ru:false, agent_mail:false, beads:false, rch_config:false}
        }')"

    if [[ "$SWARM_INV_JSON" == true && -n "$output_file" ]]; then
        printf '%s\n' "$action_json"
    elif [[ "$SWARM_INV_JSON" != true ]]; then
        swarm_inventory_emit_action_human "$action_json" "$jq_bin"
    fi
}

swarm_inventory_main() {
    local parse_status=0
    local jq_bin=""

    swarm_inventory_parse_args "$@" || parse_status=$?
    case "$parse_status" in
        0) ;;
        100) return 0 ;;
        *) return "$parse_status" ;;
    esac

    jq_bin="$(swarm_inventory_binary_path jq 2>/dev/null || true)"
    if [[ -z "$jq_bin" ]]; then
        echo "Error: jq is required for swarm inventory" >&2
        return 2
    fi
    if ! swarm_inventory_binary_path python3 >/dev/null; then
        swarm_inventory_fail "$jq_bin" "$SWARM_INV_SUBCOMMAND" "python_required" "Python 3 is required for bounded inventory input validation"
        return 2
    fi

    case "$SWARM_INV_SUBCOMMAND" in
        report) swarm_inventory_command_report "$jq_bin" ;;
        plan) swarm_inventory_command_plan "$jq_bin" ;;
        import) swarm_inventory_command_import "$jq_bin" ;;
        export) swarm_inventory_command_export "$jq_bin" ;;
        validate) swarm_inventory_command_validate "$jq_bin" ;;
    esac
}

swarm_inventory_main "$@"
