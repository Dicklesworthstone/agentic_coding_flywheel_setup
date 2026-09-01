#!/usr/bin/env bash
# ============================================================
# ACFS Per-Tool Version Holds (issue #357)
#
# A hold pins one tool out of the nightly/interactive updater
# without pausing updates for everything else. Every hold
# records an owner, a reason, and an optional expiry so a hold
# is a visible decision with a name and an end date, never a
# silent permanent pin. Expired holds warn and are ignored.
#
# Storage: ~/.acfs/holds.yaml (next to state.json, the update
# system's per-install state convention). The file is a small
# YAML subset written and read only by this library:
#
#   holds:
#     br:
#       held_version: "current"
#       owner: "jemanuel"
#       reason: "0.5.2 cannot read existing beads DBs"
#       expiry: "2026-09-15"
#
# Consumers:
#   - scripts/lib/update.sh skips held tools in every verified
#     installer path and reports them in the summary.
#   - scripts/lib/doctor.sh surfaces holds every run and
#     dispatches `acfs hold|unhold|holds` to this file.
# ============================================================

# Prevent multiple sourcing
if [[ -n "${_ACFS_HOLDS_SH_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
_ACFS_HOLDS_SH_LOADED=1

# Resolve the holds file. Honors ACFS_HOLDS_FILE, then the
# ACFS_HOME convention used by state.json.
acfs_holds_file() {
    if [[ -n "${ACFS_HOLDS_FILE:-}" ]]; then
        printf '%s\n' "$ACFS_HOLDS_FILE"
        return 0
    fi
    local acfs_home="${ACFS_HOME:-}"
    if [[ -z "$acfs_home" || "$acfs_home" != /* ]]; then
        [[ -n "${HOME:-}" && "$HOME" == /* && "$HOME" != "/" ]] || return 1
        acfs_home="$HOME/.acfs"
    fi
    printf '%s\n' "${acfs_home%/}/holds.yaml"
}

# Valid tool name: same charset the update system accepts for
# installer keys.
acfs_holds_valid_tool() {
    local tool="${1:-}"
    [[ -n "$tool" ]] || return 1
    case "$tool" in
        .|..|*[!A-Za-z0-9._+-]*) return 1 ;;
    esac
    return 0
}

acfs_holds_valid_expiry() {
    local expiry="${1:-}"
    [[ "$expiry" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

acfs_holds_today() {
    date +%F 2>/dev/null || printf '%s\n' "1970-01-01"
}

# rc 0 when the expiry date is set and strictly in the past.
# ISO dates compare correctly as strings.
acfs_hold_is_expired() {
    local expiry="${1:-}"
    [[ -n "$expiry" ]] || return 1
    acfs_holds_valid_expiry "$expiry" || return 1
    [[ "$expiry" < "$(acfs_holds_today)" ]]
}

# List held tool names, one per line.
acfs_holds_tools() {
    local holds_file=""
    holds_file="$(acfs_holds_file 2>/dev/null || true)"
    [[ -n "$holds_file" && -f "$holds_file" ]] || return 0
    awk '
        /^holds:[[:space:]]*$/ { in_holds = 1; next }
        /^[^[:space:]#]/ { in_holds = 0 }
        in_holds && /^  [A-Za-z0-9._+-]+:[[:space:]]*$/ {
            line = $0
            sub(/^  /, "", line)
            sub(/:[[:space:]]*$/, "", line)
            print line
        }
    ' "$holds_file"
}

# Print `held_version<TAB>owner<TAB>reason<TAB>expiry` for a tool.
# rc 0 when an entry exists (expired or not), rc 1 otherwise.
acfs_holds_lookup() {
    local tool="${1:-}"
    acfs_holds_valid_tool "$tool" || return 1

    local holds_file=""
    holds_file="$(acfs_holds_file 2>/dev/null || true)"
    [[ -n "$holds_file" && -f "$holds_file" ]] || return 1

    local entry=""
    entry="$(awk -v tool="$tool" '
        function unquote(v) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            if (v ~ /^".*"$/) {
                v = substr(v, 2, length(v) - 2)
                # Reverse the writer escaping: \" -> " and \\ -> \
                gsub(/\\"/, "\"", v)
                gsub(/\\\\/, "\\", v)
            }
            else if (v ~ /^\x27.*\x27$/) { v = substr(v, 2, length(v) - 2) }
            return v
        }
        /^holds:[[:space:]]*$/ { in_holds = 1; next }
        /^[^[:space:]#]/ { in_holds = 0 }
        in_holds && /^  [A-Za-z0-9._+-]+:[[:space:]]*$/ {
            line = $0
            sub(/^  /, "", line)
            sub(/:[[:space:]]*$/, "", line)
            in_tool = (line == tool)
            if (in_tool) { found = 1 }
            next
        }
        in_tool && /^    [A-Za-z_]+:/ {
            key = $0
            sub(/^    /, "", key)
            value = key
            sub(/:.*$/, "", key)
            sub(/^[A-Za-z_]+:[[:space:]]*/, "", value)
            value = unquote(value)
            if (key == "held_version") { held = value }
            else if (key == "owner") { owner = value }
            else if (key == "reason") { reason = value }
            else if (key == "expiry") { expiry = value }
        }
        END {
            if (found) { printf "%s\t%s\t%s\t%s\n", held, owner, reason, expiry }
        }
    ' "$holds_file")"

    [[ -n "$entry" ]] || return 1
    printf '%s\n' "$entry"
}

# Print a one-line human description of an ACTIVE hold on stdout.
# rc 0: active hold (description printed)
# rc 1: no hold entry
# rc 2: hold entry exists but is expired (description printed on stderr-free
#       stdout as well so callers can warn with it)
acfs_holds_active_details() {
    local tool="${1:-}"
    local entry=""
    entry="$(acfs_holds_lookup "$tool" 2>/dev/null)" || return 1

    local held_version="" owner="" reason="" expiry=""
    IFS=$'\t' read -r held_version owner reason expiry <<< "$entry"

    local expiry_display="${expiry:-never}"
    local details="held at ${held_version:-current} by ${owner:-unknown}: ${reason:-no reason recorded} (expires ${expiry_display})"

    if acfs_hold_is_expired "$expiry"; then
        printf '%s\n' "$details"
        return 2
    fi
    printf '%s\n' "$details"
    return 0
}

# Write the holds file atomically from stdin content.
_acfs_holds_write_file() {
    local holds_file="${1:-}"
    [[ -n "$holds_file" ]] || return 1
    local holds_dir="${holds_file%/*}"
    mkdir -p "$holds_dir" 2>/dev/null || return 1
    local tmp_file=""
    tmp_file="$(mktemp "${holds_file}.XXXXXX" 2>/dev/null)" || return 1
    if ! cat - >| "$tmp_file"; then
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    fi
    if ! mv -f "$tmp_file" "$holds_file"; then
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    fi
    return 0
}

# Emit the current file minus one tool's entry (plus header if absent).
_acfs_holds_file_without_tool() {
    local holds_file="${1:-}"
    local tool="${2:-}"
    if [[ ! -f "$holds_file" ]]; then
        printf '# ACFS per-tool version holds (issue #357). Managed by `acfs hold`.\n'
        printf 'holds:\n'
        return 0
    fi
    awk -v tool="$tool" '
        /^holds:[[:space:]]*$/ { in_holds = 1; print; next }
        /^[^[:space:]#]/ { in_holds = 0 }
        in_holds && /^  [A-Za-z0-9._+-]+:[[:space:]]*$/ {
            line = $0
            sub(/^  /, "", line)
            sub(/:[[:space:]]*$/, "", line)
            skipping = (line == tool)
            if (skipping) { next }
        }
        in_holds && skipping && /^    / { next }
        { print }
    ' "$holds_file"
    # Ensure the top-level key exists even in a hand-emptied file.
    if ! grep -Eq '^holds:[[:space:]]*$' "$holds_file"; then
        printf 'holds:\n'
    fi
}

# YAML-quote a scalar: double quotes with " and \ escaped.
_acfs_holds_quote() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

# acfs_holds_add tool held_version owner reason expiry
acfs_holds_add() {
    local tool="${1:-}"
    local held_version="${2:-current}"
    local owner="${3:-}"
    local reason="${4:-}"
    local expiry="${5:-}"

    if ! acfs_holds_valid_tool "$tool"; then
        echo "Invalid tool name: '${tool}'" >&2
        return 1
    fi
    if [[ -z "$reason" ]]; then
        echo "A hold needs a reason (--reason \"...\")" >&2
        return 1
    fi
    if [[ -n "$expiry" ]] && ! acfs_holds_valid_expiry "$expiry"; then
        echo "Invalid expiry '${expiry}' (expected ISO date, e.g. 2026-09-15)" >&2
        return 1
    fi
    if [[ -n "$expiry" ]] && acfs_hold_is_expired "$expiry"; then
        echo "Refusing to create an already-expired hold (expiry ${expiry} is in the past)" >&2
        return 1
    fi
    if [[ -z "$owner" ]]; then
        owner="$(id -un 2>/dev/null || true)"
        [[ -n "$owner" ]] || owner="unknown"
    fi
    # Reason/owner live on single YAML lines; newlines would corrupt the file.
    reason="${reason//$'\n'/ }"
    owner="${owner//$'\n'/ }"
    held_version="${held_version//$'\n'/ }"

    local holds_file=""
    holds_file="$(acfs_holds_file)" || {
        echo "Unable to resolve the holds file path" >&2
        return 1
    }

    {
        _acfs_holds_file_without_tool "$holds_file" "$tool"
        printf '  %s:\n' "$tool"
        printf '    held_version: %s\n' "$(_acfs_holds_quote "$held_version")"
        printf '    owner: %s\n' "$(_acfs_holds_quote "$owner")"
        printf '    reason: %s\n' "$(_acfs_holds_quote "$reason")"
        if [[ -n "$expiry" ]]; then
            printf '    expiry: %s\n' "$(_acfs_holds_quote "$expiry")"
        fi
    } | _acfs_holds_write_file "$holds_file" || {
        echo "Failed to write $holds_file" >&2
        return 1
    }
    return 0
}

acfs_holds_remove() {
    local tool="${1:-}"
    if ! acfs_holds_valid_tool "$tool"; then
        echo "Invalid tool name: '${tool}'" >&2
        return 1
    fi

    local holds_file=""
    holds_file="$(acfs_holds_file)" || {
        echo "Unable to resolve the holds file path" >&2
        return 1
    }
    if ! acfs_holds_lookup "$tool" >/dev/null 2>&1; then
        echo "No hold recorded for '${tool}'" >&2
        return 1
    fi
    _acfs_holds_file_without_tool "$holds_file" "$tool" \
        | _acfs_holds_write_file "$holds_file" || {
        echo "Failed to write $holds_file" >&2
        return 1
    }
    return 0
}

acfs_holds_list() {
    local holds_file=""
    holds_file="$(acfs_holds_file 2>/dev/null || true)"

    local -a tools=()
    local tool=""
    while IFS= read -r tool; do
        [[ -n "$tool" ]] && tools+=("$tool")
    done < <(acfs_holds_tools)

    if [[ ${#tools[@]} -eq 0 ]]; then
        echo "No version holds recorded${holds_file:+ ($holds_file)}"
        return 0
    fi

    printf '%-18s %-12s %-12s %-12s %s\n' "TOOL" "VERSION" "OWNER" "EXPIRY" "REASON"
    local entry="" held_version="" owner="" reason="" expiry="" state=""
    for tool in "${tools[@]}"; do
        entry="$(acfs_holds_lookup "$tool" 2>/dev/null || true)"
        [[ -n "$entry" ]] || continue
        IFS=$'\t' read -r held_version owner reason expiry <<< "$entry"
        state=""
        if acfs_hold_is_expired "$expiry"; then
            state=" [EXPIRED - ignored by updates]"
        fi
        printf '%-18s %-12s %-12s %-12s %s%s\n' \
            "$tool" "${held_version:-current}" "${owner:-unknown}" \
            "${expiry:-never}" "${reason:-}" "$state"
    done
    return 0
}

_acfs_holds_cli_usage() {
    cat << 'EOF'
Manage per-tool version holds for the ACFS updater (issue #357).

USAGE:
  acfs hold <tool> --reason "why" [--version X|current] [--expiry YYYY-MM-DD] [--owner who]
  acfs unhold <tool>
  acfs holds

A held tool is skipped by every acfs-update / nightly run and reported in the
update summary and `acfs doctor` until the hold is removed or expires.
Expired holds warn and are ignored (the tool updates normally).

EXAMPLES:
  acfs hold br --version 0.4.1 --reason "0.5.2 cannot read existing beads DBs" --expiry 2026-09-15
  acfs holds
  acfs unhold br
EOF
}

_acfs_holds_cli() {
    local action="${1:-list}"
    shift || true

    case "$action" in
        add|hold)
            local tool="" held_version="current" owner="" reason="" expiry=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --version) shift; held_version="${1:-}" ;;
                    --version=*) held_version="${1#*=}" ;;
                    --owner) shift; owner="${1:-}" ;;
                    --owner=*) owner="${1#*=}" ;;
                    --reason) shift; reason="${1:-}" ;;
                    --reason=*) reason="${1#*=}" ;;
                    --expiry) shift; expiry="${1:-}" ;;
                    --expiry=*) expiry="${1#*=}" ;;
                    --help|-h) _acfs_holds_cli_usage; return 0 ;;
                    -*)
                        echo "Unknown option: $1" >&2
                        _acfs_holds_cli_usage >&2
                        return 1
                        ;;
                    *)
                        if [[ -n "$tool" ]]; then
                            echo "Only one tool per hold (got '$tool' and '$1')" >&2
                            return 1
                        fi
                        tool="$1"
                        ;;
                esac
                shift || true
            done
            if [[ -z "$tool" ]]; then
                echo "Usage: acfs hold <tool> --reason \"why\" [--version X] [--expiry YYYY-MM-DD] [--owner who]" >&2
                return 1
            fi
            acfs_holds_add "$tool" "$held_version" "$owner" "$reason" "$expiry" || return 1
            echo "Hold recorded: $(acfs_holds_active_details "$tool" 2>/dev/null || echo "$tool")"
            echo "Updates will skip '${tool}' until 'acfs unhold ${tool}'${expiry:+ or ${expiry}}."
            return 0
            ;;
        remove|unhold|rm|delete)
            local tool="${1:-}"
            if [[ "$tool" == "--help" || "$tool" == "-h" || -z "$tool" ]]; then
                echo "Usage: acfs unhold <tool>" >&2
                [[ -n "$tool" ]] && return 0
                return 1
            fi
            acfs_holds_remove "$tool" || return 1
            echo "Hold removed: '${tool}' will update normally again."
            return 0
            ;;
        list|ls|holds)
            acfs_holds_list
            return $?
            ;;
        help|--help|-h)
            _acfs_holds_cli_usage
            return 0
            ;;
        *)
            echo "Unknown holds action: ${action}" >&2
            _acfs_holds_cli_usage >&2
            return 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    set -euo pipefail
    _acfs_holds_cli "$@"
fi
