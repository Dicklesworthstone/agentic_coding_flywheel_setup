#!/usr/bin/env bash
# ============================================================
# ACFS Nightly Update - Pre-flight wrapper
#
# Called by systemd timer at 4am. Checks system health before
# running acfs-update to avoid updating under adverse conditions.
#
# Pre-flight checks:
#   1. Load average - defer if system is overloaded
#   2. Disk space   - defer if critically low (<2GB)
#   3. Low-risk cleanup if disk is tight (<5GB)
#   4. Run acfs-update --yes --quiet --no-self-update by default
#
# Logs to: ~/.acfs/logs/updates/nightly-YYYY-MM-DD-HHMMSS.log
# State:   ~/.acfs/nightly-update.state (atomic, not an executable shell file)
# Retries: two more pre-flight checks at 30-minute intervals, then stop.
# ============================================================

# Shared, side-effect-free reader for `acfs status`. Keep this before the
# execution guard: both the repository path and deployed nightly-update.sh
# can be sourced without starting an update or changing shell options/HOME.
acfs_nightly_state_read() {
    local file="$1" record="" number=""
    local version outcome reason attempt_ts success_ts first_skip skip_date skips attempt retry extra

    [[ -f "$file" && -r "$file" && ! -L "$file" ]] || return 1
    # Bound the read and require one complete record. Never source/eval state.
    IFS= read -r -d '' -n 1024 record < "$file" || true
    [[ ${#record} -lt 1024 && "$record" == *$'\n' ]] || return 1
    record="${record%$'\n'}"
    [[ "$record" != *$'\n'* && "$record" != *$'\r'* ]] || return 1
    IFS=$'\t' read -r version outcome reason attempt_ts success_ts first_skip skip_date skips attempt retry extra <<< "$record"
    [[ "$version" == 1 && -z "$extra" ]] || return 1
    case "$outcome" in retrying|skipped|running|success|failed|interrupted) ;; *) return 1 ;; esac
    case "$reason" in none|load|disk|metrics|update|interrupted) ;; *) return 1 ;; esac
    for number in "$attempt_ts" "$success_ts" "$first_skip" "$retry"; do
        [[ "$number" =~ ^(0|[1-9][0-9]{0,9})$ ]] || return 1
    done
    [[ "$skips" =~ ^(0|[1-9][0-9]{0,5})$ && "$attempt" =~ ^[1-3]$ ]] || return 1
    [[ "$skip_date" == - || "$skip_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    # Reject missing/extra/empty columns (IFS normally collapses adjacent tabs).
    [[ "$record" == "$(printf '1\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
        "$outcome" "$reason" "$attempt_ts" "$success_ts" "$first_skip" "$skip_date" "$skips" "$attempt" "$retry")" ]] || return 1
    if [[ "$outcome" == success ]]; then
        [[ "$success_ts" != 0 && "$skips" == 0 && "$first_skip" == 0 && "$skip_date" == - && "$reason" == none ]] || return 1
    fi
    if [[ "$outcome" == retrying ]]; then
        (( retry > attempt_ts && retry - attempt_ts <= 1800 && skips > 0 )) || return 1
    else
        [[ "$retry" == 0 ]] || return 1
    fi
    if [[ "$skips" == 0 ]]; then
        [[ "$first_skip" == 0 && "$skip_date" == - ]] || return 1
    else
        [[ "$first_skip" != 0 && "$skip_date" != - ]] || return 1
    fi
    ACFS_NIGHTLY_OUTCOME="$outcome"
    ACFS_NIGHTLY_REASON="$reason"
    ACFS_NIGHTLY_LAST_ATTEMPT="$attempt_ts"
    ACFS_NIGHTLY_LAST_SUCCESS="$success_ts"
    ACFS_NIGHTLY_FIRST_SKIP="$first_skip"
    ACFS_NIGHTLY_SKIP_DATE="$skip_date"
    ACFS_NIGHTLY_SKIPPED_NIGHTS="$skips"
    ACFS_NIGHTLY_ATTEMPT="$attempt"
    ACFS_NIGHTLY_NEXT_RETRY="$retry"
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi

set -euo pipefail

sanitize_abs_nonroot_path() {
    local path_value="${1:-}"

    [[ -n "$path_value" ]] || return 1
    path_value="${path_value%/}"
    [[ -n "$path_value" ]] || return 1
    [[ "$path_value" == /* ]] || return 1
    [[ "$path_value" != "/" ]] || return 1
    printf '%s\n' "$path_value"
}

system_binary_path() {
    local name="${1:-}"
    local candidate=""

    [[ -n "$name" ]] || return 1
    case "$name" in
        .|..)
            return 1
            ;;
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac

    for candidate in \
        "/usr/bin/$name" \
        "/bin/$name" \
        "/usr/local/bin/$name" \
        "/usr/local/sbin/$name" \
        "/usr/sbin/$name" \
        "/sbin/$name"
    do
        [[ -x "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done

    return 1
}

resolve_current_user() {
    local current_user=""
    local id_bin=""
    local whoami_bin=""

    id_bin="$(system_binary_path id 2>/dev/null || true)"
    if [[ -n "$id_bin" ]]; then
        current_user="$("$id_bin" -un 2>/dev/null || true)"
    fi

    if [[ -z "$current_user" ]]; then
        whoami_bin="$(system_binary_path whoami 2>/dev/null || true)"
        if [[ -n "$whoami_bin" ]]; then
            current_user="$("$whoami_bin" 2>/dev/null || true)"
        fi
    fi

    [[ -n "$current_user" ]] || return 1
    printf '%s\n' "$current_user"
}

getent_passwd_entry() {
  local user="${1-}"
  local getent_bin=""
  local passwd_entry=""
  local passwd_line=""
  local printed_any=false

  getent_bin="$(system_binary_path getent 2>/dev/null || true)"
  if [[ -z "$user" ]]; then
    if [[ -n "$getent_bin" ]]; then
      while IFS= read -r passwd_line; do
        printf '%s\n' "$passwd_line"
        printed_any=true
      done < <("$getent_bin" passwd 2>/dev/null || true)
      if [[ "$printed_any" == true ]]; then
        return 0
      fi
    fi

    [[ -r /etc/passwd ]] || return 1
    while IFS= read -r passwd_line; do
      printf '%s\n' "$passwd_line"
    done < /etc/passwd
    return 0
  fi

  if [[ -n "$getent_bin" ]]; then
    passwd_entry="$("$getent_bin" passwd "$user" 2>/dev/null || true)"
  fi

  if [[ -z "$passwd_entry" ]] && [[ -r /etc/passwd ]]; then
    while IFS= read -r passwd_line; do
      [[ "${passwd_line%%:*}" == "$user" ]] || continue
      passwd_entry="$passwd_line"
      break
    done < /etc/passwd
  fi

  [[ -n "$passwd_entry" ]] || return 1
  printf '%s\n' "$passwd_entry"
}

passwd_home_from_entry() {
  local passwd_entry="${1:-}"
  local passwd_home=""

  [[ -n "$passwd_entry" ]] || return 1
  IFS=: read -r _ _ _ _ _ passwd_home _ <<< "$passwd_entry"
  passwd_home="$(sanitize_abs_nonroot_path "$passwd_home" 2>/dev/null || true)"
  [[ -n "$passwd_home" ]] || return 1
  printf '%s\n' "$passwd_home"
}

read_state_string_from_file() {
    local state_file="${1:-}"
    local key="${2:-}"
    local jq_expr="${3:-}"
    local value=""
    local jq_bin=""
    local sed_bin=""
    local head_bin=""

    [[ -f "$state_file" ]] || return 1
    [[ "$key" =~ ^[A-Za-z0-9_-]+$ ]] || return 1

    jq_bin="$(system_binary_path jq 2>/dev/null || true)"
    if [[ -n "$jq_bin" && -n "$jq_expr" ]]; then
        value="$("$jq_bin" -r "$jq_expr" "$state_file" 2>/dev/null || true)"
        value="${value%%$'\n'*}"
    fi

    if [[ -z "$value" ]]; then
        sed_bin="$(system_binary_path sed 2>/dev/null || true)"
        head_bin="$(system_binary_path head 2>/dev/null || true)"
        if [[ -n "$sed_bin" && -n "$head_bin" ]]; then
            value="$("$sed_bin" -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$state_file" 2>/dev/null | "$head_bin" -n 1 || true)"
        elif [[ -n "$sed_bin" ]]; then
            value="$("$sed_bin" -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$state_file" 2>/dev/null || true)"
            value="${value%%$'\n'*}"
        fi
    fi

    [[ -n "$value" ]] || return 1
    printf '%s\n' "$value"
}

resolve_current_home() {
    local current_user=""
    local home_candidate=""
    local passwd_entry=""
    local passwd_home=""

    home_candidate="$(sanitize_abs_nonroot_path "${HOME:-}" 2>/dev/null || true)"
    if declare -F nightly_home_has_update_entrypoint >/dev/null 2>&1 && nightly_home_has_update_entrypoint "$home_candidate"; then
        printf '%s\n' "$home_candidate"
        return 0
    fi

    current_user="$(resolve_current_user 2>/dev/null || true)"
    if [[ "$current_user" == "root" ]]; then
        printf '/root\n'
        return 0
    fi

    if [[ -n "$current_user" ]]; then
        passwd_entry="$(getent_passwd_entry "$current_user" 2>/dev/null || true)"
        if [[ -n "$passwd_entry" ]]; then
            passwd_home="$(passwd_home_from_entry "$passwd_entry" 2>/dev/null || true)"
            if [[ -n "$passwd_home" ]]; then
                printf '%s\n' "$passwd_home"
                return 0
            fi
        fi
    fi

    [[ -n "$home_candidate" ]] || return 1
    printf '%s\n' "$home_candidate"
}

nightly_home_has_update_entrypoint() {
    local candidate_home="${1:-}"

    candidate_home="$(sanitize_abs_nonroot_path "$candidate_home" 2>/dev/null || true)"
    [[ -n "$candidate_home" ]] || return 1

    [[ -x "$candidate_home/.acfs/bin/acfs-update" || -x "$candidate_home/.local/bin/acfs-update" || -f "$candidate_home/.acfs/scripts/lib/update.sh" ]]
}

# Resolve home directory (systemd %h may not set HOME reliably)
explicit_system_state_file="${ACFS_SYSTEM_STATE_FILE:-}"
HOME="$(resolve_current_home)" || {
    echo "ERROR: Unable to resolve a valid HOME for nightly update" >&2
    exit 1
}
export HOME
TARGET_HOME="$(sanitize_abs_nonroot_path "${TARGET_HOME:-}" 2>/dev/null || true)"
ACFS_HOME="$(sanitize_abs_nonroot_path "${ACFS_HOME:-}" 2>/dev/null || true)"
ACFS_STATE_FILE="$(sanitize_abs_nonroot_path "${ACFS_STATE_FILE:-}" 2>/dev/null || true)"
ACFS_SYSTEM_STATE_FILE="$(sanitize_abs_nonroot_path "${ACFS_SYSTEM_STATE_FILE:-/var/lib/acfs/state.json}" 2>/dev/null || true)"
explicit_system_state_file="$(sanitize_abs_nonroot_path "$explicit_system_state_file" 2>/dev/null || true)"
ACFS_BIN_DIR="$(sanitize_abs_nonroot_path "${ACFS_BIN_DIR:-}" 2>/dev/null || true)"
explicit_target_home="${TARGET_HOME:-}"
if [[ -n "$explicit_target_home" ]]; then
    if nightly_home_has_update_entrypoint "$explicit_target_home" || ! nightly_home_has_update_entrypoint "$HOME"; then
        HOME="$explicit_target_home"
        ACFS_HOME="$explicit_target_home/.acfs"
        export HOME ACFS_HOME
    fi
fi
export TARGET_HOME ACFS_HOME ACFS_STATE_FILE ACFS_SYSTEM_STATE_FILE ACFS_BIN_DIR

read_bin_dir_from_state_file() {
    local state_file="$1"
    local bin_dir=""

    bin_dir="$(read_state_string_from_file "$state_file" bin_dir '.bin_dir // empty' 2>/dev/null || true)"

    if [[ -n "$bin_dir" ]] && [[ "$bin_dir" == /* ]] && [[ "$bin_dir" != "/" ]]; then
        printf '%s\n' "${bin_dir%/}"
        return 0
    fi

    return 1
}

read_target_home_from_state_file() {
    local state_file="$1"
    local target_home=""

    target_home="$(read_state_string_from_file "$state_file" target_home '.target_home // empty' 2>/dev/null || true)"

    target_home="$(sanitize_abs_nonroot_path "$target_home" 2>/dev/null || true)"
    [[ -n "$target_home" ]] || return 1
    [[ -d "$target_home" ]] || return 1
    printf '%s\n' "$target_home"
}

state_file_path_target_home() {
    local state_file="$1"
    local candidate_home=""

    [[ "$state_file" == */.acfs/state.json ]] || return 1
    candidate_home="${state_file%/.acfs/state.json}"
    candidate_home="$(sanitize_abs_nonroot_path "$candidate_home" 2>/dev/null || true)"
    [[ -n "$candidate_home" ]] || return 1
    [[ -d "$candidate_home" ]] || return 1
    printf '%s\n' "$candidate_home"
}

state_file_matches_target_home() {
    local state_file="$1"
    local expected_home="$2"
    local state_home=""

    [[ -f "$state_file" ]] || return 1
    expected_home="$(sanitize_abs_nonroot_path "$expected_home" 2>/dev/null || true)"
    [[ -n "$expected_home" ]] || return 1

    state_home="$(state_file_path_target_home "$state_file" 2>/dev/null || true)"
    if [[ -z "$state_home" ]]; then
        state_home="$(read_target_home_from_state_file "$state_file" 2>/dev/null || true)"
    fi

    [[ -n "$state_home" ]] || return 1
    [[ "$state_home" == "$expected_home" ]]
}

validate_bin_dir_for_home() {
    local bin_dir="${1:-}"
    local base_home="${2:-}"
    local passwd_line=""
    local passwd_home=""
    local hinted_home=""

    bin_dir="$(sanitize_abs_nonroot_path "$bin_dir" 2>/dev/null || true)"
    [[ -n "$bin_dir" ]] || return 1
    base_home="$(sanitize_abs_nonroot_path "$base_home" 2>/dev/null || true)"

    if [[ -n "$base_home" ]] && [[ "$bin_dir" == "$base_home" || "$bin_dir" == "$base_home/"* ]]; then
        printf '%s\n' "$bin_dir"
        return 0
    fi

    case "$bin_dir" in
        */.local/bin) hinted_home="${bin_dir%/.local/bin}" ;;
        */.acfs/bin) hinted_home="${bin_dir%/.acfs/bin}" ;;
        */.bun/bin) hinted_home="${bin_dir%/.bun/bin}" ;;
        */.cargo/bin) hinted_home="${bin_dir%/.cargo/bin}" ;;
        */.atuin/bin) hinted_home="${bin_dir%/.atuin/bin}" ;;
        */go/bin) hinted_home="${bin_dir%/go/bin}" ;;
        */google-cloud-sdk/bin) hinted_home="${bin_dir%/google-cloud-sdk/bin}" ;;
    esac
    hinted_home="$(sanitize_abs_nonroot_path "$hinted_home" 2>/dev/null || true)"
    if [[ -n "$hinted_home" ]] && [[ -n "$base_home" ]] && [[ "$hinted_home" != "$base_home" ]]; then
        return 1
    fi

    while IFS= read -r passwd_line; do
        passwd_home="$(passwd_home_from_entry "$passwd_line" 2>/dev/null || true)"
        [[ -n "$passwd_home" ]] || continue
        [[ -n "$base_home" && "$passwd_home" == "$base_home" ]] && continue
        if [[ "$bin_dir" == "$passwd_home" || "$bin_dir" == "$passwd_home/"* ]]; then
            return 1
        fi
    done < <(getent_passwd_entry 2>/dev/null || true)

    printf '%s\n' "$bin_dir"
}

state_candidates=()
state_target_home=""
if [[ -n "${ACFS_STATE_FILE:-}" ]]; then
    state_candidates+=("$ACFS_STATE_FILE")
fi
if [[ -n "$explicit_system_state_file" ]]; then
    state_candidates+=("$ACFS_SYSTEM_STATE_FILE")
fi
if [[ "$HOME" == "/root" ]]; then
    [[ -z "$explicit_system_state_file" && -n "${ACFS_SYSTEM_STATE_FILE:-}" ]] && state_candidates+=("$ACFS_SYSTEM_STATE_FILE")
    state_candidates+=("$HOME/.acfs/state.json")
else
    state_candidates+=("$HOME/.acfs/state.json")
    [[ -z "$explicit_system_state_file" && -n "${ACFS_SYSTEM_STATE_FILE:-}" ]] && state_candidates+=("$ACFS_SYSTEM_STATE_FILE")
fi

for state_candidate in "${state_candidates[@]}"; do
    [[ -n "$state_candidate" && -f "$state_candidate" ]] || continue
    if [[ -n "$explicit_target_home" ]] && ! state_file_matches_target_home "$state_candidate" "$explicit_target_home"; then
        continue
    fi
    ACFS_STATE_FILE="$state_candidate"
    state_target_home="$(read_target_home_from_state_file "$state_candidate" 2>/dev/null || true)"
    if [[ -z "${state_target_home:-}" ]]; then
        state_target_home="$(state_file_path_target_home "$state_candidate" 2>/dev/null || true)"
    fi
    if [[ -n "${state_target_home:-}" ]]; then
        if ! nightly_home_has_update_entrypoint "$state_target_home"; then
            continue
        fi
        TARGET_HOME="$state_target_home"
        HOME="$TARGET_HOME"
        ACFS_HOME="$TARGET_HOME/.acfs"
        export HOME TARGET_HOME ACFS_HOME
    fi
    ACFS_BIN_DIR="$(read_bin_dir_from_state_file "$state_candidate" 2>/dev/null || true)"
    export ACFS_STATE_FILE ACFS_BIN_DIR
    break
done

if [[ -z "${ACFS_HOME:-}" ]] && nightly_home_has_update_entrypoint "$HOME"; then
    ACFS_HOME="$HOME/.acfs"
    export ACFS_HOME
fi

ACFS_BIN_DIR="$(sanitize_abs_nonroot_path "${ACFS_BIN_DIR:-}" 2>/dev/null || true)"
# Validate persisted or ambient bin_dir against the resolved runtime home.
# HOME is updated from state when a live target install is discovered, so an
# unrelated exported TARGET_HOME must not poison the preflight PATH.
ACFS_BIN_DIR="$(validate_bin_dir_for_home "${ACFS_BIN_DIR:-}" "$HOME" 2>/dev/null || true)"
export ACFS_BIN_DIR

PATH_PREFIX=""
if [[ -n "${ACFS_BIN_DIR:-}" ]]; then
    PATH_PREFIX="${ACFS_BIN_DIR}:"
fi
export PATH="${PATH_PREFIX}${HOME}/.acfs/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${HOME}/.bun/bin:${HOME}/.atuin/bin:${HOME}/go/bin:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

TIMESTAMP="$(date '+%Y-%m-%d-%H%M%S')"
LOG_DIR="$HOME/.acfs/logs/updates"
LOG_FILE="$LOG_DIR/nightly-${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"

# Redirect all output to log file AND journal (stdout/stderr already go to journal via systemd)
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== ACFS Nightly Update starting ==="
log "Date: $(date)"
log "Host: $(hostname)"

# ── Source notification library (best-effort, non-fatal) ─────
_ACFS_NOTIFY_LIB=""
for _candidate in \
    "$HOME/.acfs/scripts/lib/notify.sh" \
    "/data/projects/agentic_coding_flywheel_setup/scripts/lib/notify.sh"; do
    if [[ -f "$_candidate" ]]; then
        _ACFS_NOTIFY_LIB="$_candidate"
        break
    fi
done
if [[ -n "$_ACFS_NOTIFY_LIB" ]]; then
    # shellcheck source=scripts/lib/notify.sh
    source "$_ACFS_NOTIFY_LIB" 2>/dev/null || true
fi

# ── Bounded retries and persistent health state ──────────
# A single service invocation owns the retry window. No detached jobs, no
# forced updates, and no overlapping manual/timer runs. The lock survives
# sleeps but is closed in the updater so its background children cannot own it.
NIGHTLY_MAX_RETRIES="${ACFS_NIGHTLY_MAX_RETRIES:-2}"
NIGHTLY_RETRY_DELAY="${ACFS_NIGHTLY_RETRY_DELAY_SECONDS:-1800}"
if [[ ! "$NIGHTLY_MAX_RETRIES" =~ ^[0-2]$ ]] ||
    [[ ! "$NIGHTLY_RETRY_DELAY" =~ ^[1-9][0-9]{0,3}$ ]] ||
    (( NIGHTLY_RETRY_DELAY > 1800 )); then
    log "ERROR: retries must be 0..2 and retry delay must be 1..1800 seconds"
    exit 1
fi
NIGHTLY_STATE_FILE="$HOME/.acfs/nightly-update.state"
exec 9>"$HOME/.acfs/nightly-update.lock"
if ! command -v flock >/dev/null 2>&1; then
    log "ERROR: flock unavailable; refusing an unlocked nightly update"
    exit 1
fi
if ! flock -n 9; then
    log "SKIP: another nightly update/retry window is already running"
    exit 0
fi

ACFS_NIGHTLY_OUTCOME=running
ACFS_NIGHTLY_REASON=none
ACFS_NIGHTLY_LAST_ATTEMPT=0
ACFS_NIGHTLY_LAST_SUCCESS=0
ACFS_NIGHTLY_FIRST_SKIP=0
ACFS_NIGHTLY_SKIP_DATE=-
ACFS_NIGHTLY_SKIPPED_NIGHTS=0
ACFS_NIGHTLY_ATTEMPT=1
ACFS_NIGHTLY_NEXT_RETRY=0
if [[ -e "$NIGHTLY_STATE_FILE" || -L "$NIGHTLY_STATE_FILE" ]]; then
    if ! acfs_nightly_state_read "$NIGHTLY_STATE_FILE"; then
        log "ERROR: invalid nightly state: $NIGHTLY_STATE_FILE (preserved for inspection)"
        exit 1
    fi
fi
# Freeze the date for this retry window, including one spanning midnight.
NIGHTLY_DATE="$(date +%F)"
NIGHTLY_FINALIZED=false

nightly_write_state() {
    local tmp=""
    tmp="$(mktemp "${NIGHTLY_STATE_FILE}.XXXXXX")" || return 1
    if ! printf '1\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$ACFS_NIGHTLY_OUTCOME" "$ACFS_NIGHTLY_REASON" \
        "$ACFS_NIGHTLY_LAST_ATTEMPT" "$ACFS_NIGHTLY_LAST_SUCCESS" \
        "$ACFS_NIGHTLY_FIRST_SKIP" "$ACFS_NIGHTLY_SKIP_DATE" \
        "$ACFS_NIGHTLY_SKIPPED_NIGHTS" "$ACFS_NIGHTLY_ATTEMPT" \
        "$ACFS_NIGHTLY_NEXT_RETRY" > "$tmp" ||
        ! mv -fT -- "$tmp" "$NIGHTLY_STATE_FILE"; then
        log "ERROR: cannot persist nightly health state; refusing to continue"
        return 1
    fi
}

nightly_on_exit() {
    if [[ "$NIGHTLY_FINALIZED" != true ]]; then
        ACFS_NIGHTLY_OUTCOME=interrupted
        ACFS_NIGHTLY_REASON=interrupted
        ACFS_NIGHTLY_NEXT_RETRY=0
        nightly_write_state || log "ERROR: could not record interrupted nightly update"
    fi
}
trap nightly_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

nightly_resources_ready() {
    # Collect BOTH metrics on every attempt. Failed probes and malformed values
    # are not zero load / unlimited disk. Validate before any Bash arithmetic.
    NPROC="$(nproc 2>/dev/null)" || NPROC=""
    LOAD_5MIN="$(awk '{print $2}' /proc/loadavg 2>/dev/null)" || LOAD_5MIN=""
    ROOT_AVAIL_KB="$(LC_ALL=C df --output=avail / 2>/dev/null | tail -1 | tr -d '[:space:]')" || ROOT_AVAIL_KB=""
    if [[ ! "$NPROC" =~ ^[1-9][0-9]{0,5}$ ||
          ! "$LOAD_5MIN" =~ ^[0-9]{1,6}(\.[0-9]{1,6})?$ ||
          ! "$ROOT_AVAIL_KB" =~ ^[0-9]{1,15}$ ]]; then
        ACFS_NIGHTLY_REASON=metrics
        log "DEFER: load/CPU/disk metrics unavailable or invalid; cannot establish safe update conditions"
        return 1
    fi
    LOAD_INT=$((10#${LOAD_5MIN%%.*}))
    ROOT_AVAIL_GB=$((10#$ROOT_AVAIL_KB / 1048576))
    if (( LOAD_INT >= NPROC )); then
        ACFS_NIGHTLY_REASON=load
        log "DEFER: 5-min load average ($LOAD_5MIN) >= nproc ($NPROC). System overloaded."
        return 1
    fi
    if (( ROOT_AVAIL_GB < 2 )); then
        ACFS_NIGHTLY_REASON=disk
        log "DEFER: Root filesystem has only ${ROOT_AVAIL_GB}GB free (need >= 2GB). Critically low."
        return 1
    fi
    ACFS_NIGHTLY_REASON=none
    log "OK: Load average $LOAD_5MIN < $NPROC cores; root has ${ROOT_AVAIL_GB}GB free"
}

for (( ACFS_NIGHTLY_ATTEMPT=1; ACFS_NIGHTLY_ATTEMPT<=NIGHTLY_MAX_RETRIES+1; ACFS_NIGHTLY_ATTEMPT++ )); do
    ACFS_NIGHTLY_LAST_ATTEMPT="$(date +%s)"
    ACFS_NIGHTLY_NEXT_RETRY=0
    if nightly_resources_ready; then
        ACFS_NIGHTLY_OUTCOME=running
        nightly_write_state
        break
    fi
    if [[ "$ACFS_NIGHTLY_SKIP_DATE" != "$NIGHTLY_DATE" ]]; then
        # Count distinct nights with a blocked pre-flight since the last fully
        # successful run, not retries or manual invocations on the same date.
        if (( ACFS_NIGHTLY_SKIPPED_NIGHTS < 999999 )); then
            ACFS_NIGHTLY_SKIPPED_NIGHTS=$((ACFS_NIGHTLY_SKIPPED_NIGHTS + 1))
        fi
        ACFS_NIGHTLY_SKIP_DATE="$NIGHTLY_DATE"
    fi
    if (( ACFS_NIGHTLY_FIRST_SKIP == 0 )); then
        ACFS_NIGHTLY_FIRST_SKIP="$ACFS_NIGHTLY_LAST_ATTEMPT"
    fi
    if (( ACFS_NIGHTLY_ATTEMPT > NIGHTLY_MAX_RETRIES )); then
        ACFS_NIGHTLY_OUTCOME=skipped
        nightly_write_state
        NIGHTLY_FINALIZED=true
        log "SKIP: retry budget exhausted; ${ACFS_NIGHTLY_SKIPPED_NIGHTS} skipped night(s) since last success. See acfs status."
        exit 0
    fi
    ACFS_NIGHTLY_OUTCOME=retrying
    ACFS_NIGHTLY_NEXT_RETRY=$((ACFS_NIGHTLY_LAST_ATTEMPT + NIGHTLY_RETRY_DELAY))
    nightly_write_state
    log "RETRY: checking load and disk again in ${NIGHTLY_RETRY_DELAY}s (attempt $((ACFS_NIGHTLY_ATTEMPT + 1))/$((NIGHTLY_MAX_RETRIES + 1)))"
    sleep "$NIGHTLY_RETRY_DELAY" 9>&-
done

# ── Pre-flight 3: Low-risk cleanup if tight on space ──────
if [[ "$ROOT_AVAIL_GB" -lt 5 ]]; then
    log "WARN: Disk below 5GB free (${ROOT_AVAIL_GB}GB). Running safe cleanup..."
    FREED=0

    # Clean old /tmp build artifacts (>7 days)
    # Note: || true after du pipeline guards against set -eo pipefail
    # killing the script if a file disappears between find and du (race).
    for pattern in "cargo-install*" "rustc*" "npm-*" "bun-*"; do
        while IFS= read -r -d '' dir; do
            sz="$(du -sk "$dir" 2>/dev/null | cut -f1 || true)"
            sz="${sz:-0}"
            rm -rf "$dir" 2>/dev/null && FREED=$((FREED + sz)) && log "  Cleaned: $dir (${sz}KB)"
        done < <(find /tmp -maxdepth 1 -name "$pattern" -mtime +7 -print0 2>/dev/null || true)
    done

    # Cargo registry cache if > 500MB
    CARGO_REGISTRY="$HOME/.cargo/registry/cache"
    if [[ -d "$CARGO_REGISTRY" ]]; then
        REG_SIZE_KB="$(du -sk "$CARGO_REGISTRY" 2>/dev/null | cut -f1 || true)"
        REG_SIZE_KB="${REG_SIZE_KB:-0}"
        if [[ "$REG_SIZE_KB" -gt 512000 ]]; then
            rm -rf "$CARGO_REGISTRY" 2>/dev/null || true
            FREED=$((FREED + REG_SIZE_KB))
            log "  Cleaned: cargo registry cache (${REG_SIZE_KB}KB)"
        fi
    fi

    # Bun install cache if > 500MB
    BUN_CACHE="$HOME/.bun/install/cache"
    if [[ -d "$BUN_CACHE" ]]; then
        BUN_SIZE_KB="$(du -sk "$BUN_CACHE" 2>/dev/null | cut -f1 || true)"
        BUN_SIZE_KB="${BUN_SIZE_KB:-0}"
        if [[ "$BUN_SIZE_KB" -gt 512000 ]]; then
            rm -rf "$BUN_CACHE" 2>/dev/null || true
            FREED=$((FREED + BUN_SIZE_KB))
            log "  Cleaned: bun install cache (${BUN_SIZE_KB}KB)"
        fi
    fi

    log "Cleanup freed ~$((FREED / 1024))MB"
fi

# ── Housekeeping: rotate this service's own logs (>30 days) ──
# Unconditional: one log accumulates per night, and until now it was only
# ever cleaned once the disk had already dropped below 5GB free.
while IFS= read -r -d '' f; do
    rm -f "$f" 2>/dev/null && log "  Rotated old nightly log: $f"
done < <(find "$LOG_DIR" -name "nightly-*.log" -mtime +30 -print0 2>/dev/null || true)

# ── Run acfs-update ───────────────────────────────────────
ACFS_UPDATE=""
update_candidates=(
    "$HOME/.acfs/bin/acfs-update"
    "$HOME/.local/bin/acfs-update"
)
if [[ -n "${ACFS_BIN_DIR:-}" ]]     && [[ "$ACFS_BIN_DIR" != "$HOME/.acfs/bin" ]]     && [[ "$ACFS_BIN_DIR" != "$HOME/.local/bin" ]]; then
    # Prefer the live target-home install over a persisted bin_dir because the
    # state can lag behind home repairs or copied installs.
    update_candidates+=("${ACFS_BIN_DIR}/acfs-update")
fi
update_candidates+=(
    "$HOME/.acfs/scripts/lib/update.sh"
    "/data/projects/agentic_coding_flywheel_setup/scripts/acfs-update"
)

for candidate in "${update_candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
        ACFS_UPDATE="$candidate"
        break
    fi
done

if [[ -z "$ACFS_UPDATE" ]]; then
    log "ERROR: acfs-update not found in any expected location"
    exit 1
fi

# By default, nightly updates skip ACFS self-update because many machines run
# from a deployed ~/.acfs tree instead of a git checkout. Opt in by setting
# ACFS_NIGHTLY_SELF_UPDATE=true in a systemd override or the unit environment.
NIGHTLY_UPDATE_ARGS=(--yes --quiet)
if [[ "${ACFS_NIGHTLY_SELF_UPDATE:-false}" != "true" ]]; then
    # Only pass --no-self-update if this acfs-update supports it; older
    # acfs-update versions lack the flag and would error out on an unknown arg
    # (e.g. ACFS 0.1.0/0.5.0), which fails the whole nightly update.
    # Capture the help text first: under `set -o pipefail`, piping straight
    # into `grep -q` can fail spuriously (grep exits at the first match and
    # the help writer dies on SIGPIPE), which would silently re-enable
    # self-update on machines that must not self-update.
    update_help="$("$ACFS_UPDATE" --help 2>&1 || true)"
    if grep -q -- '--no-self-update' <<<"$update_help"; then
        NIGHTLY_UPDATE_ARGS+=(--no-self-update)
    fi
fi

log "Running: $ACFS_UPDATE ${NIGHTLY_UPDATE_ARGS[*]}"
log "---"

# Run update; capture exit code but don't fail the whole script
set +e
"$ACFS_UPDATE" "${NIGHTLY_UPDATE_ARGS[@]}" 9>&-
UPDATE_RC=$?
set -e

ACFS_NIGHTLY_NEXT_RETRY=0
if [[ "$UPDATE_RC" -eq 0 ]]; then
    ACFS_NIGHTLY_OUTCOME=success
    ACFS_NIGHTLY_REASON=none
    ACFS_NIGHTLY_LAST_SUCCESS="$(date +%s)"
    ACFS_NIGHTLY_FIRST_SKIP=0
    ACFS_NIGHTLY_SKIP_DATE=-
    ACFS_NIGHTLY_SKIPPED_NIGHTS=0
else
    # Partial failure (2) is not full recovery; do not refresh success time.
    ACFS_NIGHTLY_OUTCOME=failed
    ACFS_NIGHTLY_REASON=update
fi
nightly_write_state
NIGHTLY_FINALIZED=true

log "---"
if [[ "$UPDATE_RC" -eq 0 ]]; then
    log "=== Nightly update completed successfully ==="
    if type -t acfs_notify_update_success &>/dev/null; then
        acfs_notify_update_success 2>/dev/null || true
    fi
elif [[ "$UPDATE_RC" -eq 2 ]]; then
    # acfs-update exit 2 = partial failure: most tools updated, a few failed
    # (issue #357). Distinct wording so "60 succeeded, 2 failed" is never read
    # as "the update failed".
    log "=== Nightly update PARTIALLY failed (exit 2): most tools updated, some failed -- see the acfs-update log ==="
    if type -t acfs_notify_update_failure &>/dev/null; then
        acfs_notify_update_failure "partial failure (exit code 2): some tools failed while others updated" 2>/dev/null || true
    fi
else
    log "=== Nightly update FAILED (exit code $UPDATE_RC) ==="
    if type -t acfs_notify_update_failure &>/dev/null; then
        acfs_notify_update_failure "exit code $UPDATE_RC" 2>/dev/null || true
    fi
fi

exit "$UPDATE_RC"
