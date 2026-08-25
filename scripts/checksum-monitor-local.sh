#!/usr/bin/env bash
# ============================================================
# ACFS Checksum Monitor (local) — replaces the GitHub Actions
# checksum-monitor workflow with a host-local systemd timer.
#
# This monitor is an explicit fail-closed publication state machine:
#   CLEAN_BASE -> OBSERVED -> CANDIDATE_VALIDATED -> AUTHORIZED ->
#   GENERATED -> STAGED -> COMMITTED -> ATOMIC_PUBLISHED ->
#   REMOTE_VERIFIED -> HEALTHY.
#
# A run starts only from a clean main checkout whose HEAD and both remote refs
# are identical. Verification is bound to the exact checksums.yaml bytes it
# observed. A second network snapshot is data only until security.sh proves it
# is the exact candidate implied by that first report. External-owner changes
# additionally require a human authorization digest before repository bytes
# are mutated. Publication is a closed-path commit pushed to both refs in one
# atomic transaction and re-read from the remote before health is recorded.
#
# Deployment (maintainer host, e.g. ts1):
#   git clone https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup ~/acfs-monitor
#   cp ~/acfs-monitor/scripts/templates/acfs-checksum-monitor.{service,timer} \
#      ~/.config/systemd/user/
#   systemctl --user daemon-reload
#   systemctl --user enable --now acfs-checksum-monitor.timer
#   loginctl enable-linger "$USER"   # so the timer runs without a login session
#
# Requirements on the host: git (push access via gh credential helper),
# gh (authenticated), bun, jq, curl, flock.
#
# Environment overrides:
#   ACFS_MONITOR_REPO   clone to operate on   (default: ~/acfs-monitor)
#   ACFS_MONITOR_STATE  state/log directory   (default: ~/.local/state/acfs-monitor)
# ============================================================

set -euo pipefail

MONITOR_REPO="${ACFS_MONITOR_REPO:-$HOME/acfs-monitor}"
STATE_DIR="${ACFS_MONITOR_STATE:-$HOME/.local/state/acfs-monitor}"
# System utilities are resolved only from root-owned system prefixes. Bun is
# bound separately below because it intentionally lives under the monitor
# owner's home directory.
MONITOR_EXEC_PATH="/usr/local/bin:/usr/bin:/bin"
BUN_BIN="$HOME/.bun/bin/bun"
export PATH="$MONITOR_EXEC_PATH"
LOG_DIR="$STATE_DIR/logs"
LOCK_FILE="$STATE_DIR/monitor.lock"
RUN_TS="$(/usr/bin/date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="$LOG_DIR/run-$RUN_TS.log"
AUTHORIZATION_FILE="$STATE_DIR/authorized-checksum-change"
EXPECTED_BUN_VERSION="1.3.8"
MONITOR_RUN_BUDGET_SECONDS=1050
MONITOR_FAILURE_RESERVE_SECONDS=60
MONITOR_STARTED_AT_SECONDS=$SECONDS
STATE="INIT"

# Exact files the monitor may publish. Directory pathspecs and extension
# globs are intentionally absent: a newly generated filename must first be
# reviewed and added to this contract.
PUBLICATION_PATHS=(
    checksums.yaml
    scripts/generated/doctor_checks.sh
    scripts/generated/install_acfs.sh
    scripts/generated/install_agents.sh
    scripts/generated/install_all.sh
    scripts/generated/install_base.sh
    scripts/generated/install_cli.sh
    scripts/generated/install_cloud.sh
    scripts/generated/install_db.sh
    scripts/generated/install_filesystem.sh
    scripts/generated/install_lang.sh
    scripts/generated/install_network.sh
    scripts/generated/install_shell.sh
    scripts/generated/install_stack.sh
    scripts/generated/install_tools.sh
    scripts/generated/install_users.sh
    scripts/generated/internal_checksums.sh
    scripts/generated/manifest_index.sh
    apps/web/lib/generated/manifest-commands.ts
    apps/web/lib/generated/manifest-lessons-index.ts
    apps/web/lib/generated/manifest-modules.ts
    apps/web/lib/generated/manifest-tldr.ts
    apps/web/lib/generated/manifest-tools.ts
    apps/web/lib/generated/manifest-web-index.ts
)

declare -A PUBLICATION_PATH_SET=()
for publication_path in "${PUBLICATION_PATHS[@]}"; do
    PUBLICATION_PATH_SET["$publication_path"]=1
done

/usr/bin/mkdir -p "$LOG_DIR"

log() {
    printf '[%s] %s\n' "$(/usr/bin/date -u +%H:%M:%S)" "$*" \
        | /usr/bin/tee -a "$LOG_FILE" >&2
}

advance_state() {
    local expected="$1" next="$2"
    if [[ "$STATE" != "$expected" ]]; then
        fail_closed "invalid monitor transition: expected $expected, found $STATE, requested $next"
    fi
    STATE="$next"
    log "state=$STATE"
}

# Do not allow CHECKSUMS_FILE, ACFS_PLUGIN_PATHS, ACFS_PLUGINS_DIR, curl-bin
# overrides, manifest roots, or other ambient inputs to redirect verification
# or generation. Only the stable process essentials below cross this boundary.
run_clean() {
    env -i \
        HOME="$HOME" \
        USER="${USER:-}" \
        LOGNAME="${LOGNAME:-${USER:-}}" \
        PATH="$MONITOR_EXEC_PATH" \
        LANG=C \
        LC_ALL=C \
        TZ=UTC \
        CI=1 \
        NO_COLOR=1 \
        "$@"
}

run_bun_clean() {
    env -i \
        HOME="$HOME" \
        USER="${USER:-}" \
        LOGNAME="${LOGNAME:-${USER:-}}" \
        PATH="$MONITOR_EXEC_PATH" \
        LANG=C \
        LC_ALL=C \
        TZ=UTC \
        CI=1 \
        NO_COLOR=1 \
        "$BUN_BIN" "$@"
}

run_bounded() {
    local requested_seconds="$1"
    shift
    local elapsed=$((SECONDS - MONITOR_STARTED_AT_SECONDS))
    local remaining=$((MONITOR_RUN_BUDGET_SECONDS - elapsed - MONITOR_FAILURE_RESERVE_SECONDS))
    local limit="$requested_seconds"
    (( remaining > 0 )) || return 124
    if (( limit > remaining )); then
        limit="$remaining"
    fi
    timeout --signal=TERM --kill-after=10 "${limit}s" "$@"
}

run_clean_bounded() {
    local requested_seconds="$1"
    shift
    run_bounded "$requested_seconds" env -i \
        HOME="$HOME" \
        USER="${USER:-}" \
        LOGNAME="${LOGNAME:-${USER:-}}" \
        PATH="$MONITOR_EXEC_PATH" \
        LANG=C \
        LC_ALL=C \
        TZ=UTC \
        CI=1 \
        NO_COLOR=1 \
        "$@"
}

run_bun_clean_bounded() {
    local requested_seconds="$1"
    shift
    run_bounded "$requested_seconds" env -i \
        HOME="$HOME" \
        USER="${USER:-}" \
        LOGNAME="${LOGNAME:-${USER:-}}" \
        PATH="$MONITOR_EXEC_PATH" \
        LANG=C \
        LC_ALL=C \
        TZ=UTC \
        CI=1 \
        NO_COLOR=1 \
        "$BUN_BIN" "$@"
}

run_failure_bounded() {
    timeout --signal=TERM --kill-after=5 20 "$@"
}

sha256_file() {
    local file="$1" digest="" links=""
    [[ -f "$file" && ! -L "$file" && -r "$file" ]] || return 1
    links="$(stat -c '%h' -- "$file" 2>/dev/null)" || return 1
    [[ "$links" == "1" ]] || return 1
    digest="$(sha256sum -- "$file" 2>/dev/null)" || return 1
    digest="${digest%% *}"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$digest"
}

REMOTE_MAIN_HEAD=""
REMOTE_MASTER_HEAD=""
read_remote_heads() {
    local refs="" main_count="" mirror_count=""
    refs="$(run_bounded 45 git ls-remote --heads origin refs/heads/main refs/heads/master 2>>"$LOG_FILE")" \
        || return 1
    main_count="$(awk '$2 == "refs/heads/main" { count += 1 } END { print count + 0 }' <<< "$refs")"
    mirror_count="$(awk '$2 == "refs/heads/master" { count += 1 } END { print count + 0 }' <<< "$refs")"
    [[ "$main_count" -eq 1 && "$mirror_count" -eq 1 ]] || return 1
    REMOTE_MAIN_HEAD="$(awk '$2 == "refs/heads/main" { print $1 }' <<< "$refs")"
    REMOTE_MASTER_HEAD="$(awk '$2 == "refs/heads/master" { print $1 }' <<< "$refs")"
    [[ "$REMOTE_MAIN_HEAD" =~ ^[0-9a-f]{40}$ ]] \
        && [[ "$REMOTE_MASTER_HEAD" =~ ^[0-9a-f]{40}$ ]]
}

require_clean_tree() {
    local status_output=""
    status_output="$(git status --porcelain=v1 --untracked-files=all 2>>"$LOG_FILE")" \
        || return 1
    [[ -z "$status_output" ]] || return 1
    git diff --quiet --exit-code -- \
        && git diff --cached --quiet --exit-code --
}

canonical_compact_json_is_exact() {
    local file="$1" canonical="" canonical_digest="" source_digest=""
    canonical="$(jq -c . "$file" 2>/dev/null)" || return 1
    [[ "$canonical" != *$'\n'* ]] || return 1
    canonical_digest="$(printf '%s\n' "$canonical" | sha256sum | awk '{print $1}')" \
        || return 1
    source_digest="$(sha256_file "$file")" || return 1
    [[ "$canonical_digest" =~ ^[0-9a-f]{64}$ ]] \
        && [[ "$canonical_digest" == "$source_digest" ]]
}

validate_drift_report() {
    local file="$1"
    # The drift producer emits one compact jq object. Requiring byte-canonical
    # compact JSON rejects duplicate keys, alternate encodings, trailing data,
    # and empty-container duplicate-key cases before the field schema runs.
    canonical_compact_json_is_exact "$file" || return 1
    jq -e '
        def exact_keys($wanted): type == "object" and keys == ($wanted | sort);
        def count: type == "number" and floor == . and . >= 0;
        def strings: type == "array" and all(.[]; type == "string");
        type == "object" and
        exact_keys([
          "drift_detected", "generated_artifacts", "internal_scripts",
          "manifest", "manifest_contract", "reasons", "repo_mcp_configs"
        ]) and
        (.drift_detected | type == "boolean") and
        (.reasons | strings) and
        (.manifest | exact_keys(["actual_sha256", "index_modules", "manifest_modules", "recorded_sha256", "sha256_line_count"])) and
        (.manifest.actual_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
        (.manifest.recorded_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
        (.manifest.sha256_line_count | count) and
        (.manifest.manifest_modules | count) and
        (.manifest.index_modules | count) and
        (.internal_scripts | exact_keys(["checked", "drift_files", "drifted"])) and
        (.internal_scripts.checked | count) and
        (.internal_scripts.drifted | count) and
        (.internal_scripts.drift_files | strings) and
        (.repo_mcp_configs | exact_keys(["checked", "drift_files", "drifted", "expected_url"])) and
        (.repo_mcp_configs.expected_url == "http://127.0.0.1:8765/mcp/") and
        (.repo_mcp_configs.checked | count) and
        (.repo_mcp_configs.drifted | count) and
        (.repo_mcp_configs.drift_files | strings) and
        (.generated_artifacts | exact_keys(["drift_files", "drifted", "status"])) and
        (.generated_artifacts.status == "clean" or .generated_artifacts.status == "drift") and
        (.generated_artifacts.drifted | count) and
        (.generated_artifacts.drift_files | strings) and
        (.manifest_contract | exact_keys(["checked", "drift_files", "drifted", "mismatch_codes", "status"])) and
        (.manifest_contract.status == "clean" or .manifest_contract.status == "drift") and
        (.manifest_contract.checked | count) and
        (.manifest_contract.drifted | count) and
        (.manifest_contract.drift_files | strings) and
        (.manifest_contract.mismatch_codes | strings)
    ' "$file" >/dev/null 2>&1
}

validate_verification_report() {
    local file="$1" expected_digest="$2"
    canonical_compact_json_is_exact "$file" || return 1
    [[ "$(sha256_file checksums.yaml)" == "$expected_digest" ]] || return 1
    # Delegate exact schema, duplicate-key detection, installer membership,
    # URL/hash bindings, and report-to-policy digest binding to security.sh's
    # authoritative offline report validator. This accepts complete match and
    # mismatch partitions without pretending the current policy is already
    # the later candidate.
    run_clean_bounded 30 bash -c '
        set -euo pipefail
        source "$1"
        declare -A urls=() checksums=() matches=() mismatch_expected=()
        declare -A mismatch_actual=() errors=() skipped=()
        acfs_load_checksums_strict "$2" urls checksums
        digest="$(calculate_file_sha256 "$2")"
        [[ "$digest" == "$3" ]]
        acfs_validate_installer_checksum_report \
            "$4" urls checksums "$digest" \
            matches mismatch_expected mismatch_actual errors skipped
    ' bash \
        "$PWD/scripts/lib/security.sh" \
        "$PWD/checksums.yaml" \
        "$expected_digest" \
        "$file" >/dev/null 2>&1
}

is_trusted_installer_url() {
    case "$1" in
        https://raw.githubusercontent.com/Dicklesworthstone/*) return 0 ;;
        *) return 1 ;;
    esac
}

authorization_is_valid() {
    local digest="$1" owner="" links="" mode="" size="" mode_value=""
    local -a lines=()
    [[ -f "$AUTHORIZATION_FILE" && ! -L "$AUTHORIZATION_FILE" ]] || return 1
    owner="$(stat -c '%u' -- "$AUTHORIZATION_FILE" 2>/dev/null)" || return 1
    links="$(stat -c '%h' -- "$AUTHORIZATION_FILE" 2>/dev/null)" || return 1
    mode="$(stat -c '%a' -- "$AUTHORIZATION_FILE" 2>/dev/null)" || return 1
    size="$(stat -c '%s' -- "$AUTHORIZATION_FILE" 2>/dev/null)" || return 1
    [[ "$owner" == "$(id -u)" && "$links" == "1" ]] || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ && "$size" =~ ^[0-9]+$ ]] || return 1
    (( size > 0 && size <= 256 )) || return 1
    mode_value=$((8#$mode))
    (( (mode_value & 077) == 0 )) || return 1
    mapfile -t lines < "$AUTHORIZATION_FILE" || return 1
    [[ ${#lines[@]} -eq 1 && "${lines[0]}" == "authorize:$digest" ]]
}

record_external_review() {
    local report="$1" digest="$2" authorization_status="$3"
    local body_file="" existing="" external_names_json="[]" external_evidence="" repo_slug=""
    repo_slug="Dicklesworthstone/agentic_coding_flywheel_setup"
    body_file="$(mktemp "$STATE_DIR/external-review-$RUN_TS.XXXXXX.md")" || return 1
    external_names_json="$(printf '%s\n' "${EXTERNAL_CHANGED[@]}" | jq -R . | jq -s .)" \
        || return 1
    external_evidence="$(jq -r --argjson names "$external_names_json" '
      .mismatches[] | select(.name as $name | $names | index($name)) |
      "- `\(.name)`\n  - URL: `\(.url)`\n  - expected: `\(.expected)`\n  - observed: `\(.actual)`"
    ' "$report")" || return 1
    {
        printf '## External installer checksum authorization\n\n'
        printf 'This monitor observed installer bytes outside the exact trusted owner boundary.\n\n'
        printf -- '- Authorization digest: `%s`\n' "$digest"
        printf -- '- Authorization status: `%s`\n' "$authorization_status"
        printf -- '- Pinned base: `%s`\n' "$BASE_HEAD"
        printf -- '- Verification report SHA256: `%s`\n\n' "$VERIFICATION_REPORT_SHA256"
        printf '### First-observation evidence\n\n'
        printf '%s\n' "$external_evidence"
        printf '\n### Human authorization\n\n'
        printf 'After reviewing the upstream bytes, place exactly this line in `%s` as an owner-only, non-symlink file:\n\n' "$AUTHORIZATION_FILE"
        printf '```text\nauthorize:%s\n```\n' "$digest"
    } > "$body_file" || return 1

    existing="$(run_bounded 45 gh issue list --repo "$repo_slug" --state open \
        --label security --label checksum-update \
        --search "$digest" --json number -q '.[0].number' \
        2>>"$LOG_FILE" || true)"
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        run_bounded 45 gh issue comment "$existing" --repo "$repo_slug" \
            --body-file "$body_file" >>"$LOG_FILE" 2>&1
        return
    fi
    if run_bounded 45 gh issue create --repo "$repo_slug" \
        --title "External installer checksum authorization ${digest:0:12}" \
        --label security --label checksum-update \
        --body-file "$body_file" >>"$LOG_FILE" 2>&1; then
        return 0
    fi
    run_bounded 45 gh issue create --repo "$repo_slug" \
        --title "External installer checksum authorization ${digest:0:12}" \
        --body-file "$body_file" >>"$LOG_FILE" 2>&1
}

assert_closed_publication_worktree() {
    local path="" tracked_paths="" untracked_paths="" deleted_paths=""
    # Capture each producer's status before inspecting output. Git's default
    # C quoting keeps pathnames containing newlines on one line; force it so a
    # hostile filename cannot be split into an apparently allowed suffix.
    tracked_paths="$(git -c core.quotePath=true diff --name-only -- 2>>"$LOG_FILE")" \
        || return 1
    untracked_paths="$(git -c core.quotePath=true ls-files --others --exclude-standard -- 2>>"$LOG_FILE")" \
        || return 1
    deleted_paths="$(git -c core.quotePath=true diff --name-only --diff-filter=D -- 2>>"$LOG_FILE")" \
        || return 1
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [[ -n "${PUBLICATION_PATH_SET[$path]+present}" ]] || {
            log "unexpected tracked mutation: $path"
            return 1
        }
    done <<< "$tracked_paths"
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [[ -n "${PUBLICATION_PATH_SET[$path]+present}" ]] || {
            log "unexpected untracked path: $path"
            return 1
        }
    done <<< "$untracked_paths"
    if [[ -n "$deleted_paths" ]]; then
        log "publication would contain a deletion"
        return 1
    fi
}

# Consecutive fail-closed runs are tracked so a persistently broken monitor
# (expired gh auth, dead network, wedged clone) alerts a human instead of
# silently leaving checksums unmonitored. Alerting is strictly best-effort:
# it must never mask the fail-closed exit or itself abort the trap path.
FAIL_STREAK_FILE="$STATE_DIR/fail_closed_streak"

_alert_fail_closed_streak() {
    local streak="$1" reason="$2"
    # Alert when the streak first crosses 3, then re-alert every 24 runs
    # (~6h at the 15-minute timer cadence) while it persists.
    if (( streak != 3 )) && { (( streak < 3 )) || (( streak % 24 != 0 )); }; then
        return 0
    fi
    local alert_msg="ACFS checksum monitor has failed closed $streak times in a row on $(hostname 2>/dev/null || echo unknown-host). Latest reason: $reason. Checksum drift is NOT being monitored until this is fixed. See $LOG_DIR."
    # Optional push notification
    if [[ -n "${ACFS_NTFY_TOPIC:-}" ]]; then
        curl -fsS -m 10 -A "OpenAI File Downloader, XaiImageApiFetch/1.0" \
            -d "$alert_msg" "https://ntfy.sh/${ACFS_NTFY_TOPIC}" \
            >>"$LOG_FILE" 2>&1 || true
    fi
    # GitHub issue (deduped by label + search, same pattern as the
    # external-change review issue below)
    local repo_slug="Dicklesworthstone/agentic_coding_flywheel_setup"
    local existing=""
    existing="$(run_failure_bounded gh issue list --repo "$repo_slug" --state open \
        --label monitoring \
        --search "Checksum monitor failing closed" \
        --json number -q '.[0].number' 2>>"$LOG_FILE" || true)"
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        run_failure_bounded gh issue comment "$existing" --repo "$repo_slug" \
            --body "$alert_msg" >>"$LOG_FILE" 2>&1 \
            && log "commented on existing monitoring issue #$existing" || true
    else
        if run_failure_bounded gh issue create --repo "$repo_slug" \
            --title "🚨 Checksum monitor failing closed - checksums unmonitored" \
            --label monitoring \
            --body "$alert_msg" >>"$LOG_FILE" 2>&1; then
            log "created monitoring alert issue"
        else
            # The label exists in the canonical repo; if it is ever missing,
            # an unlabeled alert (dedupe degraded) beats no alert at all.
            run_failure_bounded gh issue create --repo "$repo_slug" \
                --title "🚨 Checksum monitor failing closed - checksums unmonitored" \
                --body "$alert_msg" >>"$LOG_FILE" 2>&1 \
                && log "created monitoring alert issue (unlabeled fallback)" || true
        fi
    fi
}

fail_closed() {
    log "FAIL-CLOSED: $*"
    local streak=0
    streak="$(command cat "$FAIL_STREAK_FILE" 2>/dev/null || echo 0)"
    [[ "$streak" =~ ^[0-9]+$ ]] || streak=0
    streak=$((streak + 1))
    printf '%s\n' "$streak" > "$FAIL_STREAK_FILE" 2>/dev/null || true
    _alert_fail_closed_streak "$streak" "$*" || true
    log "summary: result=fail_closed state=$STATE streak=$streak repo=$MONITOR_REPO"
    exit 1
}

# ---- single-instance lock (timer overlap is a silent no-op) ----
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    # Another run is active; skipping is the correct behavior for a
    # 15-minute timer, so exit success without noise.
    exit 0
fi

advance_state INIT LOCKED

log "ACFS checksum monitor starting (repo: $MONITOR_REPO)"

# Monitor location/notification overrides were captured above. Everything
# capable of redirecting Git, checksum, manifest, plugin, or package-manager
# behavior is removed before the first repository observation.
unset CHECKSUMS_FILE ACFS_REPO_ROOT ACFS_MANIFEST_YAML ACFS_CHECKSUMS_YAML
unset ACFS_VERIFIED_INSTALLER_CACHE ACFS_REPO_OWNER ACFS_REPO_NAME ACFS_CHECKSUMS_REF
unset ACFS_CURL_BIN ACFS_PLUGIN_PATHS ACFS_PLUGINS_DIR
unset BUN_INSTALL BUN_CONFIG_REGISTRY npm_config_registry NPM_CONFIG_REGISTRY
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_SYSTEM GIT_CONFIG_GLOBAL
unset GIT_CONFIG_NOSYSTEM GIT_CONFIG_COUNT GIT_CEILING_DIRECTORIES GIT_NAMESPACE
unset GIT_QUARANTINE_PATH GIT_REPLACE_REF_BASE GIT_SSH_COMMAND GIT_SSH_VARIANT
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_AUTHOR_DATE
unset GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_DATE
unset GIT_ASKPASS SSH_ASKPASS GH_HOST GH_REPO
for system_prefix in /usr/local/bin /usr/bin /bin; do
    [[ -d "$system_prefix" ]] || continue
    prefix_real="$(/usr/bin/readlink -f -- "$system_prefix" 2>/dev/null || true)"
    prefix_owner="$(/usr/bin/stat -c '%u' -- "$prefix_real" 2>/dev/null || true)"
    prefix_mode="$(/usr/bin/stat -c '%a' -- "$prefix_real" 2>/dev/null || true)"
    [[ "$prefix_real" == /* && "$prefix_owner" == "0" && "$prefix_mode" =~ ^[0-7]{3,4}$ ]] \
        || fail_closed "trusted system prefix metadata is unsafe: $system_prefix"
    prefix_mode_value=$((8#$prefix_mode))
    (( (prefix_mode_value & 022) == 0 )) \
        || fail_closed "trusted system prefix is group/world writable: $system_prefix -> $prefix_real"
done
for dep in bash env git gh jq curl flock sha256sum stat sort uniq awk sed tr cmp mktemp paste head id cp timeout readlink date tee mkdir hostname cat; do
    dep_path="$(command -v "$dep" 2>/dev/null || true)"
    [[ "$dep_path" == /* ]] || fail_closed "missing dependency: $dep"
    dep_real="$(/usr/bin/readlink -f -- "$dep_path" 2>/dev/null || true)"
    case "$dep_real" in
        /usr/bin/*|/usr/local/bin/*) ;;
        *) fail_closed "dependency resolves outside trusted system prefixes: $dep -> ${dep_real:-unresolved}" ;;
    esac
    [[ -f "$dep_real" && -x "$dep_real" ]] \
        || fail_closed "dependency is not a regular executable: $dep -> $dep_real"
    dep_owner="$(/usr/bin/stat -c '%u' -- "$dep_real" 2>/dev/null || true)"
    dep_mode="$(/usr/bin/stat -c '%a' -- "$dep_real" 2>/dev/null || true)"
    [[ "$dep_owner" == "0" && "$dep_mode" =~ ^[0-7]{3,4}$ ]] \
        || fail_closed "dependency metadata is unsafe: $dep -> $dep_real"
    dep_mode_value=$((8#$dep_mode))
    (( (dep_mode_value & 022) == 0 )) \
        || fail_closed "dependency is group/world writable: $dep -> $dep_real"
done

[[ -f "$BUN_BIN" && ! -L "$BUN_BIN" && -x "$BUN_BIN" ]] \
    || fail_closed "pinned Bun binary is missing or unsafe: $BUN_BIN"
bun_dir="${BUN_BIN%/*}"
bun_dir_owner="$(stat -c '%u' -- "$bun_dir" 2>/dev/null || true)"
bun_dir_mode="$(stat -c '%a' -- "$bun_dir" 2>/dev/null || true)"
[[ "$bun_dir_owner" == "$(id -u)" && "$bun_dir_mode" =~ ^[0-7]{3,4}$ ]] \
    || fail_closed "pinned Bun directory metadata is unsafe: $bun_dir"
bun_dir_mode_value=$((8#$bun_dir_mode))
(( (bun_dir_mode_value & 022) == 0 )) \
    || fail_closed "pinned Bun directory is group/world writable: $bun_dir"
bun_owner="$(stat -c '%u' -- "$BUN_BIN" 2>/dev/null || true)"
bun_links="$(stat -c '%h' -- "$BUN_BIN" 2>/dev/null || true)"
bun_mode="$(stat -c '%a' -- "$BUN_BIN" 2>/dev/null || true)"
[[ "$bun_owner" == "$(id -u)" && "$bun_links" == "1" && "$bun_mode" =~ ^[0-7]{3,4}$ ]] \
    || fail_closed "pinned Bun binary metadata is unsafe: $BUN_BIN"
bun_mode_value=$((8#$bun_mode))
(( (bun_mode_value & 022) == 0 )) \
    || fail_closed "pinned Bun binary is group/world writable: $BUN_BIN"

[[ -d "$MONITOR_REPO/.git" ]] || fail_closed "monitor clone not found at $MONITOR_REPO"
cd "$MONITOR_REPO"
origin_url="$(git remote get-url origin 2>/dev/null || true)"
case "$origin_url" in
    https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup|\
    https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup.git|\
    git@github.com:Dicklesworthstone/agentic_coding_flywheel_setup.git) ;;
    *) fail_closed "origin does not name the canonical ACFS repository: ${origin_url:-missing}" ;;
esac

# ---- CLEAN_BASE: clean main, then one ff-only synchronization ----
[[ "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)" == "main" ]] \
    || fail_closed "monitor clone must already be on main"
require_clean_tree \
    || fail_closed "monitor clone has local tracked, staged, or untracked changes"
run_bounded 60 git fetch --quiet origin main master 2>>"$LOG_FILE" \
    || fail_closed "fetch of main and legacy mirror failed"
read_remote_heads || fail_closed "could not resolve exactly one remote main and mirror ref"
[[ "$REMOTE_MAIN_HEAD" == "$REMOTE_MASTER_HEAD" ]] \
    || fail_closed "remote main and legacy mirror differ before observation"
if ! git -c core.hooksPath=/dev/null merge --ff-only --quiet \
    refs/remotes/origin/main 2>>"$LOG_FILE"; then
    fail_closed "local main is not an exact fast-forward of origin/main"
fi
BASE_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
[[ "$BASE_HEAD" =~ ^[0-9a-f]{40}$ && "$BASE_HEAD" == "$REMOTE_MAIN_HEAD" ]] \
    || fail_closed "local HEAD is not the fetched remote base"
require_clean_tree || fail_closed "clone is not clean after synchronization"

actual_bun_version="$(run_bun_clean --version 2>>"$LOG_FILE" || true)"
[[ "$actual_bun_version" == "$EXPECTED_BUN_VERSION" ]] \
    || fail_closed "Bun version mismatch: expected $EXPECTED_BUN_VERSION, found ${actual_bun_version:-unavailable}"
( cd packages/manifest \
    && run_bun_clean_bounded 90 install --frozen-lockfile --ignore-scripts --silent >>"$LOG_FILE" 2>&1 ) \
    || fail_closed "frozen, lifecycle-disabled Bun install failed in packages/manifest"
require_clean_tree || fail_closed "dependency preparation changed tracked or untracked repository state"
advance_state LOCKED CLEAN_BASE
log "clean base pinned to $BASE_HEAD"

# ---- OBSERVED: drift plus the first and only authoritative network report ----
drift_json="$(mktemp "$STATE_DIR/drift-$RUN_TS.XXXXXX.json")" \
    || fail_closed "could not allocate drift evidence file"
set +e
run_clean_bounded 120 bash scripts/check-manifest-drift.sh --json >"$drift_json" 2>>"$LOG_FILE"
drift_exit=$?
set -e
validate_drift_report "$drift_json" \
    || fail_closed "drift checker returned data outside its strict JSON contract"

drift_detected="$(jq -r '.drift_detected' "$drift_json")"
if [[ "$drift_exit" -eq 0 && "$drift_detected" == "false" ]]; then
    log "generated artifacts are clean"
elif [[ "$drift_exit" -eq 1 && "$drift_detected" == "true" ]]; then
    log "generated artifact drift detected:"
    jq -r '.reasons[] | "  - \(.)"' "$drift_json" | tee -a "$LOG_FILE" >&2
    fail_closed "pinned base already contains generated drift; repair it independently before checksum publication"
else
    fail_closed "drift checker exit/result mismatch (exit $drift_exit, drift=$drift_detected)"
fi

CURRENT_CHECKSUMS_SHA256="$(sha256_file checksums.yaml)" \
    || fail_closed "canonical checksums.yaml is missing, unsafe, or unreadable"
verify_json="$(mktemp "$STATE_DIR/verify-$RUN_TS.XXXXXX.json")" \
    || fail_closed "could not allocate verification evidence file"
set +e
run_clean_bounded 300 bash scripts/lib/security.sh --verify --json >"$verify_json" 2>>"$LOG_FILE"
verify_exit=$?
set -e
validate_verification_report "$verify_json" "$CURRENT_CHECKSUMS_SHA256" \
    || fail_closed "checksum verification returned data outside its strict bound report contract"
VERIFICATION_REPORT_SHA256="$(sha256_file "$verify_json")" \
    || fail_closed "could not bind the validated verification report bytes"

mismatches="$(jq '.mismatches | length' "$verify_json")"
errors="$(jq '.errors | length' "$verify_json")"
skipped="$(jq '.skipped | length' "$verify_json")"

if [[ "$errors" -gt 0 || "$skipped" -gt 0 ]]; then
    jq -r '.errors[]?  | "  error: \(.name) -> \(.error)"'    "$verify_json" | tee -a "$LOG_FILE" >&2
    jq -r '.skipped[]? | "  skipped: \(.name) -> \(.reason)"' "$verify_json" | tee -a "$LOG_FILE" >&2
    fail_closed "verification returned $errors error(s) / $skipped skip(s); refusing to auto-update checksums.yaml"
fi
if [[ "$mismatches" -eq 0 && "$verify_exit" -ne 0 ]]; then
    fail_closed "verification reported no mismatch but exited $verify_exit"
fi
if [[ "$mismatches" -gt 0 && "$verify_exit" -ne 1 ]]; then
    fail_closed "verification reported $mismatches mismatch(es) but exited $verify_exit"
fi
[[ "$(sha256_file checksums.yaml)" == "$CURRENT_CHECKSUMS_SHA256" ]] \
    || fail_closed "checksums.yaml changed during first observation"
[[ "$(git rev-parse HEAD 2>/dev/null || true)" == "$BASE_HEAD" ]] \
    || fail_closed "HEAD changed during observation"
require_clean_tree || fail_closed "repository changed during observation"
advance_state CLEAN_BASE OBSERVED

TRUSTED_CHANGED=()
EXTERNAL_CHANGED=()
if [[ "$mismatches" -gt 0 ]]; then
    mismatch_rows="$(jq -r '.mismatches[] | [.name, .url] | @tsv' "$verify_json")" \
        || fail_closed "could not classify validated checksum mismatches"
    while IFS=$'\t' read -r name url; do
        [[ -n "$name" ]] || continue
        if is_trusted_installer_url "$url"; then
            TRUSTED_CHANGED+=("$name")
        else
            EXTERNAL_CHANGED+=("$name")
        fi
    done <<< "$mismatch_rows"
    (( ${#TRUSTED_CHANGED[@]} + ${#EXTERNAL_CHANGED[@]} == mismatches )) \
        || fail_closed "mismatch classification did not cover the full validated report"
fi
changed_tools="$(jq -r '.mismatches[].name' "$verify_json" | paste -sd, -)" \
    || fail_closed "could not summarize validated checksum mismatches"
trusted_changed="$(printf '%s\n' "${TRUSTED_CHANGED[@]:-}" | sed '/^$/d' | paste -sd, -)"
external_changed="$(printf '%s\n' "${EXTERNAL_CHANGED[@]:-}" | sed '/^$/d' | paste -sd, -)"
log "changed tools: ${changed_tools:-none} (trusted: ${trusted_changed:-none}; external: ${external_changed:-none})"

raw_candidate=""
validated_candidate=""
CANDIDATE_SHA256="$CURRENT_CHECKSUMS_SHA256"
if [[ "$mismatches" -gt 0 ]]; then
    raw_candidate="$(mktemp "$STATE_DIR/checksums-raw-$RUN_TS.XXXXXX.yaml")" \
        || fail_closed "could not allocate raw candidate evidence file"
    validated_candidate="$(mktemp "$STATE_DIR/checksums-validated-$RUN_TS.XXXXXX.yaml")" \
        || fail_closed "could not allocate validated candidate evidence file"
    run_clean_bounded 300 bash scripts/lib/security.sh --update-checksums \
        >"$raw_candidate" 2>>"$LOG_FILE" \
        || fail_closed "canonical checksum candidate generation failed"
    run_clean_bounded 60 bash scripts/lib/security.sh \
        --validate-checksum-candidate checksums.yaml "$raw_candidate" "$verify_json" \
        >"$validated_candidate" 2>>"$LOG_FILE" \
        || fail_closed "candidate is not exactly implied by the first verification report"
    cmp -s -- "$raw_candidate" "$validated_candidate" \
        || fail_closed "candidate validator did not reproduce the exact reviewed candidate bytes"
    CANDIDATE_SHA256="$(sha256_file "$validated_candidate")" \
        || fail_closed "validated checksum candidate is empty or unsafe"
    [[ "$CANDIDATE_SHA256" != "$CURRENT_CHECKSUMS_SHA256" ]] \
        || fail_closed "verification reported mismatch but the validated candidate is byte-identical"
else
    log "all checksums match the first upstream observation"
fi
[[ "$(sha256_file checksums.yaml)" == "$CURRENT_CHECKSUMS_SHA256" ]] \
    || fail_closed "checksums.yaml changed while validating the candidate"
require_clean_tree || fail_closed "repository changed while validating the candidate"
advance_state OBSERVED CANDIDATE_VALIDATED

authorization_digest=""
authorization_consumed=false
if [[ ${#EXTERNAL_CHANGED[@]} -gt 0 ]]; then
    authorization_digest="$(
        jq -cS '[.mismatches[] | {actual, expected, name, url}] | sort_by(.name)' "$verify_json" \
            | sha256sum \
            | awk '{print $1}'
    )" || fail_closed "could not hash the external-change authorization evidence"
    [[ "$authorization_digest" =~ ^[0-9a-f]{64}$ ]] \
        || fail_closed "could not derive the external-change authorization digest"
    if authorization_is_valid "$authorization_digest"; then
        authorization_status="authorized"
    else
        authorization_status="required"
    fi
    record_external_review "$verify_json" "$authorization_digest" "$authorization_status" \
        || fail_closed "could not record external checksum evidence before mutation"
    [[ "$authorization_status" == "authorized" ]] \
        || fail_closed "external checksum changes require authorize:$authorization_digest in $AUTHORIZATION_FILE"
    authorization_consumed=true
fi
advance_state CANDIDATE_VALIDATED AUTHORIZED

publication_required=false
if [[ "$mismatches" -gt 0 ]]; then
    command cp -- "$validated_candidate" checksums.yaml \
        || fail_closed "could not place the validated checksum candidate"
    [[ "$(sha256_file checksums.yaml)" == "$CANDIDATE_SHA256" ]] \
        || fail_closed "placed checksums.yaml does not match the validated candidate"
    ( cd packages/manifest \
        && run_bun_clean_bounded 120 run generate >>"$LOG_FILE" 2>&1 ) \
        || fail_closed "generation from the validated checksum candidate failed"
    assert_closed_publication_worktree \
        || fail_closed "generation escaped the closed publication path set"

    post_drift_json="$(mktemp "$STATE_DIR/post-generate-drift-$RUN_TS.XXXXXX.json")" \
        || fail_closed "could not allocate post-generation evidence file"
    set +e
    run_clean_bounded 120 bash scripts/check-manifest-drift.sh --json \
        >"$post_drift_json" 2>>"$LOG_FILE"
    post_drift_exit=$?
    set -e
    validate_drift_report "$post_drift_json" \
        || fail_closed "post-generation drift report violated its strict JSON contract"
    [[ "$post_drift_exit" -eq 0 ]] \
        && [[ "$(jq -r '.drift_detected' "$post_drift_json")" == "false" ]] \
        || fail_closed "validated candidate did not produce a clean generated-artifact contract"
    [[ "$(sha256_file checksums.yaml)" == "$CANDIDATE_SHA256" ]] \
        || fail_closed "checksums.yaml changed during generation"
    publication_required=true
fi
advance_state AUTHORIZED GENERATED

for publication_path in "${PUBLICATION_PATHS[@]}"; do
    [[ -f "$publication_path" && ! -L "$publication_path" ]] \
        && [[ "$(stat -c '%h' -- "$publication_path" 2>/dev/null || true)" == "1" ]] \
        || fail_closed "closed publication member is missing or unsafe: $publication_path"
done

if [[ "$publication_required" == "true" ]]; then
    assert_closed_publication_worktree \
        || fail_closed "worktree contains bytes outside the closed publication set"
    git add -- "${PUBLICATION_PATHS[@]}" \
        || fail_closed "could not stage the closed publication set"
    staged_paths="$(git -c core.quotePath=true diff --cached --name-only -- 2>>"$LOG_FILE")" \
        || fail_closed "could not enumerate the staged publication"
    while IFS= read -r staged_path; do
        [[ -n "$staged_path" ]] || continue
        [[ -n "${PUBLICATION_PATH_SET[$staged_path]+present}" ]] \
            || fail_closed "unexpected staged publication path: $staged_path"
    done <<< "$staged_paths"
    staged_deletions="$(git -c core.quotePath=true diff --cached --name-only --diff-filter=D -- 2>>"$LOG_FILE")" \
        || fail_closed "could not enumerate staged deletions"
    [[ -z "$staged_deletions" ]] \
        || fail_closed "refusing to stage a file deletion"
    git diff --quiet --exit-code -- \
        || fail_closed "worktree bytes changed after staging"
    git diff --cached --check \
        || fail_closed "staged publication failed whitespace/error checks"
    git diff --cached --quiet --exit-code -- \
        && fail_closed "validated mismatch produced no staged publication"
else
    require_clean_tree || fail_closed "no-op run acquired repository mutations"
fi
advance_state GENERATED STAGED

read_remote_heads || fail_closed "could not re-read remote refs before commit"
[[ "$REMOTE_MAIN_HEAD" == "$BASE_HEAD" && "$REMOTE_MASTER_HEAD" == "$BASE_HEAD" ]] \
    || fail_closed "remote base moved after observation; refusing to commit stale evidence"

committed=false
PUBLISH_HEAD="$BASE_HEAD"
if [[ "$publication_required" == "true" ]]; then
    git -c "user.name=acfs-checksum-monitor ($(hostname -s))" \
        -c user.email=jeff141421@gmail.com \
        -c core.hooksPath=/dev/null \
        -c commit.gpgsign=false \
        commit --quiet \
        -m "chore(security): publish validated checksums for ${changed_tools}" \
        -m "Observed checksums policy: ${CURRENT_CHECKSUMS_SHA256}" \
        -m "Verification evidence: ${VERIFICATION_REPORT_SHA256}" \
        -m "Validated candidate: ${CANDIDATE_SHA256}" \
        -m "Changed tools: ${changed_tools}" \
        -m "Trusted: ${trusted_changed:-none}" \
        -m "External: ${external_changed:-none}" \
        -m "Authorization: ${authorization_digest:-not-required}" \
        || fail_closed "closed checksum publication commit failed"
    PUBLISH_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
    [[ "$PUBLISH_HEAD" =~ ^[0-9a-f]{40}$ ]] \
        && [[ "$(git rev-parse "${PUBLISH_HEAD}^" 2>/dev/null || true)" == "$BASE_HEAD" ]] \
        || fail_closed "publication commit is not the direct child of the observed base"
    committed_paths="$(git -c core.quotePath=true diff-tree --no-commit-id --name-only -r "$PUBLISH_HEAD" 2>>"$LOG_FILE")" \
        || fail_closed "could not enumerate the publication commit"
    while IFS= read -r committed_path; do
        [[ -n "$committed_path" ]] || continue
        [[ -n "${PUBLICATION_PATH_SET[$committed_path]+present}" ]] \
            || fail_closed "publication commit contains unexpected path: $committed_path"
    done <<< "$committed_paths"
    require_clean_tree || fail_closed "repository is not clean after publication commit"
    committed=true
fi
advance_state STAGED COMMITTED

read_remote_heads || fail_closed "could not read remote refs immediately before publication"
[[ "$REMOTE_MAIN_HEAD" == "$BASE_HEAD" && "$REMOTE_MASTER_HEAD" == "$BASE_HEAD" ]] \
    || fail_closed "remote refs moved before atomic publication"

push_result="not-required"
if [[ "$publication_required" == "true" ]]; then
    publication_journal="$(mktemp "$STATE_DIR/publication-$RUN_TS.XXXXXX.journal")" \
        || fail_closed "could not allocate publication journal"
    printf 'prepared\t%s\t%s\n' "$BASE_HEAD" "$PUBLISH_HEAD" >> "$publication_journal" \
        || fail_closed "could not record prepared publication"
    set +e
    run_bounded 90 git -c core.hooksPath=/dev/null push --atomic --quiet origin \
        "$PUBLISH_HEAD:refs/heads/main" \
        "$PUBLISH_HEAD:refs/heads/master" >>"$LOG_FILE" 2>&1
    push_exit=$?
    set -e
    printf 'push-exit\t%s\n' "$push_exit" >> "$publication_journal" \
        || fail_closed "could not journal the publication result"
    read_remote_heads \
        || fail_closed "atomic push result is ambiguous because remote refs cannot be read"
    if [[ "$REMOTE_MAIN_HEAD" == "$PUBLISH_HEAD" && "$REMOTE_MASTER_HEAD" == "$PUBLISH_HEAD" ]]; then
        if [[ "$push_exit" -eq 0 ]]; then
            push_result="accepted"
        else
            push_result="reconciled-after-ambiguous-exit"
        fi
    elif [[ "$REMOTE_MAIN_HEAD" == "$BASE_HEAD" && "$REMOTE_MASTER_HEAD" == "$BASE_HEAD" ]]; then
        fail_closed "atomic publication was not accepted (push exit $push_exit)"
    else
        fail_closed "remote refs are mixed or unexpected after atomic publication attempt"
    fi
    printf 'remote-observed\t%s\t%s\t%s\n' \
        "$REMOTE_MAIN_HEAD" "$REMOTE_MASTER_HEAD" "$push_result" \
        >> "$publication_journal" \
        || fail_closed "could not journal reconciled remote publication"
fi
advance_state COMMITTED ATOMIC_PUBLISHED

# A second independent remote read is the acceptance boundary. Local source,
# a successful git exit, or one remote-tracking ref is not publication proof.
read_remote_heads || fail_closed "remote verification after publication failed"
[[ "$REMOTE_MAIN_HEAD" == "$PUBLISH_HEAD" && "$REMOTE_MASTER_HEAD" == "$PUBLISH_HEAD" ]] \
    || fail_closed "remote verification does not match the intended publication commit"
[[ "$(git rev-parse HEAD 2>/dev/null || true)" == "$PUBLISH_HEAD" ]] \
    || fail_closed "local HEAD changed before remote acceptance"
require_clean_tree || fail_closed "repository is not clean at remote acceptance"
advance_state ATOMIC_PUBLISHED REMOTE_VERIFIED

if [[ "$authorization_consumed" == "true" ]]; then
    printf 'used:%s:%s\n' "$authorization_digest" "$PUBLISH_HEAD" \
        > "$AUTHORIZATION_FILE" \
        || fail_closed "remote publication succeeded but authorization consumption could not be recorded"
fi

# Only an accepted remote state can clear monitoring failure history.
printf '0\n' > "$FAIL_STREAK_FILE" \
    || fail_closed "remote publication is verified but the healthy-state marker could not be written"
advance_state REMOTE_VERIFIED HEALTHY

log "summary: result=ok state=$STATE base=$BASE_HEAD published=$PUBLISH_HEAD push=$push_result mismatches=$mismatches errors=$errors skipped=$skipped trusted=${trusted_changed:-none} external=${external_changed:-none} committed=$committed"
