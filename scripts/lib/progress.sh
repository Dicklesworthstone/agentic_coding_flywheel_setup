#!/usr/bin/env bash
# ============================================================
# ACFS Progress Bar Library
# Provides visual progress tracking during tool installation.
#
# Related: bead bd-21kh
# ============================================================

# NOTE: Do not enable strict mode here. This file is sourced by
# installers and must not leak set -euo pipefail.

# Global progress state
ACFS_PROGRESS_TOTAL=0
ACFS_PROGRESS_CURRENT=0
ACFS_PROGRESS_START_TIME=0
ACFS_PROGRESS_ENABLED=true
ACFS_PROGRESS_IS_TTY=false
ACFS_PROGRESS_LAST_LINE_LEN=0

_progress_is_nonnegative_integer() {
    local value="${1:-}"
    [[ "$value" =~ ^[0-9]+$ ]]
}

_progress_is_positive_integer() {
    local value="${1:-}"
    _progress_is_nonnegative_integer "$value" || return 1
    (( 10#$value > 0 ))
}

# Check if we should use color/formatting
_progress_check_tty() {
    # Disable progress bar if NO_COLOR is set or output is not a TTY
    if [[ -n "${NO_COLOR:-}" ]]; then
        ACFS_PROGRESS_ENABLED=true  # Still show text, just no colors
        ACFS_PROGRESS_IS_TTY=false
    elif [[ -t 2 ]]; then
        ACFS_PROGRESS_ENABLED=true
        ACFS_PROGRESS_IS_TTY=true
    else
        # Non-TTY (piped output) - use simple line-by-line
        ACFS_PROGRESS_ENABLED=true
        ACFS_PROGRESS_IS_TTY=false
    fi
}

# Initialize progress tracking
# Usage: progress_init <total_items>
progress_init() {
    local total="${1:-0}"

    _progress_check_tty

    if ! _progress_is_positive_integer "$total"; then
        ACFS_PROGRESS_TOTAL=0
        ACFS_PROGRESS_CURRENT=0
        ACFS_PROGRESS_START_TIME=0
        ACFS_PROGRESS_LAST_LINE_LEN=0
        ACFS_PROGRESS_ENABLED=false
        return
    fi

    ACFS_PROGRESS_TOTAL="$total"
    ACFS_PROGRESS_CURRENT=0
    ACFS_PROGRESS_START_TIME=$(date +%s)
    ACFS_PROGRESS_LAST_LINE_LEN=0
}

# Build ASCII progress bar
# Usage: _progress_bar <current> <total> <width>
_progress_bar() {
    local current="${1:-0}"
    local total="${2:-0}"
    local width="${3:-20}"

    if ! _progress_is_positive_integer "$width"; then
        width=20
    fi

    if ! _progress_is_positive_integer "$total" || ! _progress_is_nonnegative_integer "$current"; then
        printf '%*s' "$width" ""
        return
    fi

    local percent=$((10#$current * 100 / 10#$total))
    if [[ "$percent" -gt 100 ]]; then
        percent=100
    fi
    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    local bar=""
    local i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    printf '%s' "$bar"
}

# Update progress display
# Usage: progress_update <item_name> [<item_description>]
progress_update() {
    local item_name="${1:-}"
    local item_desc="${2:-}"

    if [[ "$ACFS_PROGRESS_ENABLED" != "true" ]]; then
        return
    fi
    if ! _progress_is_positive_integer "${ACFS_PROGRESS_TOTAL:-0}"; then
        ACFS_PROGRESS_ENABLED=false
        return
    fi
    if ! _progress_is_nonnegative_integer "${ACFS_PROGRESS_CURRENT:-0}"; then
        ACFS_PROGRESS_CURRENT=0
    fi

    ((ACFS_PROGRESS_CURRENT++)) || true

    local current="$ACFS_PROGRESS_CURRENT"
    local total="$ACFS_PROGRESS_TOTAL"
    local percent=$((10#$current * 100 / 10#$total))
    if [[ "$percent" -gt 100 ]]; then
        percent=100
    fi

    # Truncate item name if too long
    local display_name="$item_name"
    if [[ ${#display_name} -gt 35 ]]; then
        display_name="${display_name:0:32}..."
    fi

    if [[ "$ACFS_PROGRESS_IS_TTY" == "true" ]]; then
        # Interactive TTY: in-place update
        local bar
        bar="$(_progress_bar "$current" "$total" 20)"

        # Build the progress line
        local line
        printf -v line "[%s] %d/%d (%d%%) %s" "$bar" "$current" "$total" "$percent" "$display_name"

        # Clear previous line and print new one
        # Use carriage return to overwrite, then clear to end of line
        printf '\r\033[K%s' "$line" >&2

        ACFS_PROGRESS_LAST_LINE_LEN=${#line}
    else
        # Non-TTY or NO_COLOR: simple line-by-line output
        printf '[%d/%d] Installing %s...\n' "$current" "$total" "$display_name" >&2
    fi
}

# Mark progress as complete (add newline for TTY mode)
progress_finish() {
    local total="${ACFS_PROGRESS_TOTAL:-0}"

    if [[ "$ACFS_PROGRESS_ENABLED" != "true" ]]; then
        return
    fi
    if ! _progress_is_nonnegative_integer "$total"; then
        total=0
    fi

    if [[ "$ACFS_PROGRESS_IS_TTY" == "true" ]] && [[ "$ACFS_PROGRESS_LAST_LINE_LEN" -gt 0 ]]; then
        # Print completion message and newline
        local bar
        bar="$(_progress_bar "$total" "$total" 20)"
        printf '\r\033[K[%s] %d/%d (100%%) Complete\n' "$bar" "$total" "$total" >&2
    fi

    # Reset state
    ACFS_PROGRESS_TOTAL=0
    ACFS_PROGRESS_CURRENT=0
    ACFS_PROGRESS_LAST_LINE_LEN=0
}

# Helper to count modules for a category/phase
# Usage: progress_count_modules <category> <phase>
# Returns count via stdout
progress_count_modules() {
    local category="$1"
    local phase="$2"
    local count=0
    local module key

    if [[ "${ACFS_MANIFEST_INDEX_LOADED:-false}" != "true" ]]; then
        echo "0"
        return
    fi

    for module in "${ACFS_EFFECTIVE_PLAN[@]:-}"; do
        key="$module"
        if [[ "${ACFS_MODULE_CATEGORY[$key]:-}" == "$category" ]] && \
           [[ "${ACFS_MODULE_PHASE[$key]:-}" == "$phase" ]] && \
           [[ "${ACFS_MODULE_GENERATED[$key]:-}" == "1" ]]; then
            ((count++)) || true
        fi
    done

    echo "$count"
}

# ============================================================
# Local milestone progress
# ============================================================

local_progress_file_path() {
    if [[ -n "${ACFS_LOCAL_PROGRESS_FILE:-}" ]]; then
        printf '%s\n' "$ACFS_LOCAL_PROGRESS_FILE"
        return 0
    fi

    if [[ -n "${ACFS_HOME:-}" ]]; then
        printf '%s/local_progress.json\n' "${ACFS_HOME%/}"
        return 0
    fi

    if [[ -n "${HOME:-}" ]]; then
        printf '%s/.acfs/local_progress.json\n' "${HOME%/}"
        return 0
    fi

    return 1
}

local_progress_is_disabled() {
    local value=""

    value="${ACFS_LOCAL_PROGRESS:-}"
    case "${value,,}" in
        0|false|no|off|disabled|disable|opt-out|opt_out)
            return 0
            ;;
    esac

    for value in "${ACFS_LOCAL_PROGRESS_OPT_OUT:-}" "${ACFS_DISABLE_LOCAL_PROGRESS:-}" "${DO_NOT_TRACK:-}"; do
        case "${value,,}" in
            1|true|yes|on|enabled|enable)
                return 0
                ;;
        esac
    done

    return 1
}

local_progress_safe_token() {
    local value="${1:-unknown}"

    if [[ "$value" =~ ^[A-Za-z0-9_.:-]{1,80}$ ]]; then
        printf '%s\n' "$value"
        return 0
    fi

    printf 'unknown\n'
}

local_progress_json_number_or_null() {
    local value="${1:-}"

    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%d\n' "$((10#$value))"
        return 0
    fi

    printf 'null\n'
}

local_progress_json_bool() {
    local value="${1:-false}"

    case "${value,,}" in
        1|true|yes|on)
            printf 'true\n'
            ;;
        *)
            printf 'false\n'
            ;;
    esac
}

local_progress_now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -Iseconds
}

local_progress_python_binary() {
    local candidate
    for candidate in /usr/bin/python3 /bin/python3 /usr/local/bin/python3; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

local_progress_record_event() {
    local source="$1"
    local kind="$2"
    local status="$3"
    local details_json="${4:-}"
    local python_bin=""
    local progress_file=""
    local max_events="${ACFS_LOCAL_PROGRESS_MAX_EVENTS:-100}"

    [[ -n "$details_json" ]] || details_json="{}"
    local_progress_is_disabled && return 0
    python_bin="$(local_progress_python_binary)" || return 0
    source="$(local_progress_safe_token "$source")"
    kind="$(local_progress_safe_token "$kind")"
    status="$(local_progress_safe_token "$status")"
    progress_file="$(local_progress_file_path 2>/dev/null || true)"
    [[ -n "$progress_file" ]] || return 0

    # Milestones are advisory, including when called by an elevated installer.
    # Shell redirects follow links and can block on a FIFO before flock gets a
    # chance to enforce its timeout. Keep path traversal, locking, the bounded
    # read and atomic replacement in one no-follow descriptor transaction.
    # Missing Python or unsafe/unavailable storage must not break the caller.
    "$python_bin" -I - "$progress_file" "$source" "$kind" "$status" "$details_json" "$max_events" <<'ACFS_LOCAL_PROGRESS_PY' 2>/dev/null || true
import datetime
import fcntl
import json
import os
import re
import secrets
import stat
import sys
import time

LIMIT = 8 * 1024 * 1024
DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC


def identity(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns,
            info.st_ctime_ns, info.st_uid, info.st_gid, info.st_mode, info.st_nlink)


def same_inode(first, second):
    return first is not None and second is not None and (first.st_dev, first.st_ino) == (second.st_dev, second.st_ino)


def regular(info, owners):
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid not in owners:
        raise ValueError("unsafe milestone file")
    return info


def inspect(directory, name, owners):
    try:
        return regular(os.stat(name, dir_fd=directory, follow_symlinks=False), owners)
    except FileNotFoundError:
        return None


def open_directory(path):
    directory = os.open("/", DIRECTORY_FLAGS)
    try:
        for part in path.split("/")[1:]:
            if not part:
                continue
            try:
                next_directory = os.open(part, DIRECTORY_FLAGS, dir_fd=directory)
            except FileNotFoundError:
                try:
                    os.mkdir(part, 0o700, dir_fd=directory)
                except FileExistsError:
                    pass
                next_directory = os.open(part, DIRECTORY_FLAGS, dir_fd=directory)
            os.close(directory)
            directory = next_directory
        return directory
    except BaseException:
        os.close(directory)
        raise


def record():
    path, source, kind, status, raw_details, raw_max_events = sys.argv[1:]
    path = os.path.abspath(path)
    parent, name = os.path.split(path)
    if not name:
        return
    directory = open_directory(parent)
    lock = None
    try:
        directory_info = os.fstat(directory)
        owners = {os.geteuid()}
        if os.geteuid() == 0:
            owners.add(directory_info.st_uid)
        # Reject links and special files before opening either existing name.
        inspect(directory, name, owners)
        lock_name = name + ".lock"
        lock_info = inspect(directory, lock_name, owners)
        if lock_info is None:
            try:
                lock = os.open(lock_name, FILE_FLAGS | os.O_CREAT | os.O_EXCL, 0o600, dir_fd=directory)
                if os.geteuid() == 0:
                    os.fchown(lock, directory_info.st_uid, directory_info.st_gid)
            except FileExistsError:
                lock_info = inspect(directory, lock_name, owners)
        if lock is None:
            lock = os.open(lock_name, FILE_FLAGS, dir_fd=directory)
        bound_lock = regular(os.fstat(lock), owners)
        if lock_info is not None and not same_inode(lock_info, bound_lock):
            return
        deadline = time.monotonic() + 2
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    return
                time.sleep(0.05)
        visible_lock = inspect(directory, lock_name, owners)
        if not same_inode(visible_lock, bound_lock):
            return

        previous = inspect(directory, name, owners)
        state = {}
        if previous is not None:
            if previous.st_size > LIMIT:
                return
            with os.fdopen(os.open(name, FILE_FLAGS, dir_fd=directory), "rb") as stream:
                if identity(regular(os.fstat(stream.fileno()), owners)) != identity(previous):
                    return
                raw = stream.read(LIMIT + 1)
                if len(raw) > LIMIT or identity(os.fstat(stream.fileno())) != identity(previous):
                    return
            state = json.loads(raw)
        if not isinstance(state, dict):
            state = {}
        try:
            details = json.loads(raw_details)
        except ValueError:
            details = {}
        max_events = int(raw_max_events) if re.fullmatch(r"[0-9]{1,18}", raw_max_events) else 100
        if max_events <= 0:
            max_events = 100
        now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        events = state.get("events", [])
        if not isinstance(events, list):
            events = []
        events.append({"timestamp": now, "source": source, "kind": kind, "status": status, "details": details})
        state.update(schema_version=1, updated_at=now, events=events[-max_events:])
        if state.get("created_at") is None or state.get("created_at") is False:
            state["created_at"] = now
        output = (json.dumps(state, indent=2, ensure_ascii=True, allow_nan=False) + "\n").encode()
        if len(output) > LIMIT:
            return

        temporary = ".local_progress." + secrets.token_hex(16)
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                     0o600, dir_fd=directory)
        with os.fdopen(fd, "wb") as stream:
            if os.geteuid() == 0:
                owner = previous if previous is not None else directory_info
                os.fchown(stream.fileno(), owner.st_uid, owner.st_gid)
            stream.write(output)
            stream.flush()
            temporary_info = os.fstat(stream.fileno())
        current = inspect(directory, name, owners)
        current_lock = inspect(directory, lock_name, owners)
        current_temporary = inspect(directory, temporary, owners)
        if ((identity(current) if current is not None else None)
                != (identity(previous) if previous is not None else None)
                or not same_inode(current_lock, bound_lock)
                or current_temporary is None or identity(current_temporary) != identity(temporary_info)):
            return
        os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
    finally:
        if lock is not None:
            os.close(lock)
        os.close(directory)


try:
    record()
except (OSError, ValueError, TypeError, OverflowError, RecursionError):
    pass
ACFS_LOCAL_PROGRESS_PY
    return 0
}

local_progress_record_installer_phase() {
    local phase_id
    local status
    local kind
    local details_json

    phase_id="$(local_progress_safe_token "${1:-unknown}")"
    status="$(local_progress_safe_token "${2:-unknown}")"

    case "$status" in
        started) kind="phase_started" ;;
        completed) kind="phase_completed" ;;
        failed) kind="phase_failed" ;;
        *) kind="phase_event" ;;
    esac

    printf -v details_json '{"phase_id":"%s"}' "$phase_id"
    local_progress_record_event "installer" "$kind" "$status" "$details_json"
}

local_progress_record_doctor_invoked() {
    local deep_mode
    local fix_mode
    local dry_run_mode
    local json_mode
    local details_json

    deep_mode="$(local_progress_json_bool "${1:-false}")"
    fix_mode="$(local_progress_json_bool "${2:-false}")"
    dry_run_mode="$(local_progress_json_bool "${3:-false}")"
    json_mode="$(local_progress_json_bool "${4:-false}")"
    printf -v details_json '{"deep_mode":%s,"fix_mode":%s,"dry_run_mode":%s,"json_mode":%s}' \
        "$deep_mode" "$fix_mode" "$dry_run_mode" "$json_mode"

    local_progress_record_event "doctor" "doctor_invoked" "invoked" "$details_json"
}

local_progress_record_onboard_lesson() {
    local status
    local kind
    local lesson_index
    local lesson_number
    local details_json

    status="$(local_progress_safe_token "${1:-unknown}")"
    lesson_index="$(local_progress_json_number_or_null "${2:-}")"
    lesson_number="$(local_progress_json_number_or_null "${3:-}")"

    case "$status" in
        started) kind="lesson_started" ;;
        completed) kind="lesson_completed" ;;
        *) kind="lesson_event" ;;
    esac

    printf -v details_json '{"lesson_index":%s,"lesson_number":%s}' "$lesson_index" "$lesson_number"
    local_progress_record_event "onboard" "$kind" "$status" "$details_json"
}

local_progress_record_onboard_event() {
    local kind
    local status
    local completed_count
    local total_lessons
    local details_json

    kind="$(local_progress_safe_token "${1:-event}")"
    status="$(local_progress_safe_token "${2:-observed}")"
    completed_count="$(local_progress_json_number_or_null "${3:-}")"
    total_lessons="$(local_progress_json_number_or_null "${4:-}")"

    printf -v details_json '{"completed_count":%s,"total_lessons":%s}' "$completed_count" "$total_lessons"
    local_progress_record_event "onboard" "$kind" "$status" "$details_json"
}
