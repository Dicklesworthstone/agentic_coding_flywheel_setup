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
LOG_DIR="$STATE_DIR/logs"
LOCK_FILE="$STATE_DIR/monitor.lock"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="$LOG_DIR/run-$RUN_TS.log"
AUTHORIZATION_FILE="$STATE_DIR/authorized-checksum-change"
EXPECTED_BUN_VERSION="1.3.8"
MONITOR_EXEC_PATH="$HOME/.bun/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
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

mkdir -p "$LOG_DIR"

log() {
    printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$LOG_FILE" >&2
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

sha256_file() {
    local file="$1" digest=""
    [[ -f "$file" && ! -L "$file" && -r "$file" ]] || return 1
    digest="$(sha256sum -- "$file" 2>/dev/null)" || return 1
    digest="${digest%% *}"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$digest"
}

REMOTE_MAIN_HEAD=""
REMOTE_MASTER_HEAD=""
read_remote_heads() {
    local refs="" main_count="" mirror_count=""
    refs="$(git ls-remote --heads origin refs/heads/main refs/heads/master 2>>"$LOG_FILE")" \
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

json_has_duplicate_paths() {
    local file="$1" duplicate=""
    duplicate="$({
        jq --stream -c 'select(length == 2) | .[0]' "$file" 2>/dev/null \
            | sort \
            | uniq -d \
            | head -n 1
    } || true)"
    [[ -n "$duplicate" ]]
}

validate_drift_report() {
    local file="$1"
    ! json_has_duplicate_paths "$file" || return 1
    jq -e '
        type == "object" and
        ((keys | sort) == ([
          "drift_detected", "generated_artifacts", "internal_scripts",
          "manifest", "manifest_contract", "reasons", "repo_mcp_configs"
        ] | sort)) and
        (.drift_detected | type == "boolean") and
        (.reasons | type == "array") and all(.reasons[]; type == "string") and
        (.generated_artifacts | type == "object") and
        (.generated_artifacts.status == "clean" or .generated_artifacts.status == "drift") and
        (.generated_artifacts.drifted | type == "number") and
        (.generated_artifacts.drift_files | type == "array") and
        (.internal_scripts.drifted | type == "number") and
        (.repo_mcp_configs.drifted | type == "number") and
        (.manifest_contract.drifted | type == "number")
    ' "$file" >/dev/null 2>&1
}

validate_verification_report() {
    local file="$1" expected_digest="$2"
    ! json_has_duplicate_paths "$file" || return 1
    jq -e --arg expected_digest "$expected_digest" '
        def hash: type == "string" and test("^[0-9a-f]{64}$");
        def https_url: type == "string" and startswith("https://");
        type == "object" and
        ((keys | sort) == ([
          "checksumsYamlSha256", "errors", "matches", "mismatches",
          "schema", "schemaVersion", "skipped", "timestamp", "total"
        ] | sort)) and
        .schema == "acfs.installer-checksum-verification.v1" and
        .schemaVersion == 1 and
        (.timestamp | type == "string" and length > 0) and
        .checksumsYamlSha256 == $expected_digest and
        (.total | type == "number" and floor == . and . > 0) and
        (.matches | type == "array") and
        (.mismatches | type == "array") and
        (.errors | type == "array") and
        (.skipped | type == "array") and
        all(.matches[];
          ((keys | sort) == (["checksum", "name", "url"] | sort)) and
          (.name | type == "string" and length > 0) and
          (.url | https_url) and (.checksum | hash)) and
        all(.mismatches[];
          ((keys | sort) == (["actual", "expected", "name", "url"] | sort)) and
          (.name | type == "string" and length > 0) and
          (.url | https_url) and (.expected | hash) and (.actual | hash)) and
        all(.errors[];
          ((keys | sort) == (["error", "name", "url"] | sort)) and
          (.name | type == "string" and length > 0) and
          (.url | https_url) and (.error | type == "string" and length > 0)) and
        all(.skipped[];
          ((keys | sort) == (["name", "reason", "url"] | sort)) and
          (.name | type == "string" and length > 0) and
          (.url | https_url) and (.reason | type == "string" and length > 0)) and
        .total == ((.matches | length) + (.mismatches | length) +
                   (.errors | length) + (.skipped | length)) and
        ([.matches[].name, .mismatches[].name, .errors[].name, .skipped[].name]
          | length) ==
        ([.matches[].name, .mismatches[].name, .errors[].name, .skipped[].name]
          | unique | length)
    ' "$file" >/dev/null 2>&1
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
    (( (mode_value & 022) == 0 )) || return 1
    mapfile -t lines < "$AUTHORIZATION_FILE" || return 1
    [[ ${#lines[@]} -eq 1 && "${lines[0]}" == "authorize:$digest" ]]
}

record_external_review() {
    local report="$1" digest="$2" authorization_status="$3"
    local body_file="" existing="" external_names_json="[]" repo_slug=""
    repo_slug="Dicklesworthstone/agentic_coding_flywheel_setup"
    body_file="$(mktemp "$STATE_DIR/external-review-$RUN_TS.XXXXXX.md")" || return 1
    external_names_json="$(printf '%s\n' "${EXTERNAL_CHANGED[@]}" | jq -R . | jq -s .)" \
        || return 1
    {
        printf '## External installer checksum authorization\n\n'
        printf 'This monitor observed installer bytes outside the exact trusted owner boundary.\n\n'
        printf -- '- Authorization digest: `%s`\n' "$digest"
        printf -- '- Authorization status: `%s`\n' "$authorization_status"
        printf -- '- Pinned base: `%s`\n\n' "$BASE_HEAD"
        printf '### First-observation evidence\n\n'
        jq -r --argjson names "$external_names_json" '
          .mismatches[] | select(.name as $name | $names | index($name)) |
          "- `\(.name)`\n  - URL: `\(.url)`\n  - expected: `\(.expected)`\n  - observed: `\(.actual)`"
        ' "$report"
        printf '\n### Human authorization\n\n'
        printf 'After reviewing the upstream bytes, place exactly this line in `%s` as an owner-only, non-symlink file:\n\n' "$AUTHORIZATION_FILE"
        printf '```text\nauthorize:%s\n```\n' "$digest"
    } > "$body_file" || return 1

    existing="$(gh issue list --repo "$repo_slug" --state open \
        --label security --label checksum-update \
        --search "$digest" --json number -q '.[0].number' \
        2>>"$LOG_FILE" || true)"
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        gh issue comment "$existing" --repo "$repo_slug" \
            --body-file "$body_file" >>"$LOG_FILE" 2>&1
        return
    fi
    if gh issue create --repo "$repo_slug" \
        --title "External installer checksum authorization ${digest:0:12}" \
        --label security --label checksum-update \
        --body-file "$body_file" >>"$LOG_FILE" 2>&1; then
        return 0
    fi
    gh issue create --repo "$repo_slug" \
        --title "External installer checksum authorization ${digest:0:12}" \
        --body-file "$body_file" >>"$LOG_FILE" 2>&1
}

assert_closed_publication_worktree() {
    local path=""
    while IFS= read -r -d '' path; do
        [[ -n "${PUBLICATION_PATH_SET[$path]+present}" ]] || {
            log "unexpected tracked mutation: $path"
            return 1
        }
    done < <(git diff --name-only -z --)
    while IFS= read -r -d '' path; do
        [[ -n "${PUBLICATION_PATH_SET[$path]+present}" ]] || {
            log "unexpected untracked path: $path"
            return 1
        }
    done < <(git ls-files --others --exclude-standard -z --)
    if [[ -n "$(git diff --name-only --diff-filter=D --)" ]]; then
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
    existing="$(gh issue list --repo "$repo_slug" --state open \
        --label monitoring \
        --search "Checksum monitor failing closed" \
        --json number -q '.[0].number' 2>>"$LOG_FILE" || true)"
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        gh issue comment "$existing" --repo "$repo_slug" \
            --body "$alert_msg" >>"$LOG_FILE" 2>&1 \
            && log "commented on existing monitoring issue #$existing" || true
    else
        if gh issue create --repo "$repo_slug" \
            --title "🚨 Checksum monitor failing closed - checksums unmonitored" \
            --label monitoring \
            --body "$alert_msg" >>"$LOG_FILE" 2>&1; then
            log "created monitoring alert issue"
        else
            # The label exists in the canonical repo; if it is ever missing,
            # an unlabeled alert (dedupe degraded) beats no alert at all.
            gh issue create --repo "$repo_slug" \
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

for dep in git gh jq curl bun flock; do
    command -v "$dep" >/dev/null 2>&1 || fail_closed "missing dependency: $dep"
done

[[ -d "$MONITOR_REPO/.git" ]] || fail_closed "monitor clone not found at $MONITOR_REPO"
cd "$MONITOR_REPO"

# ---- 1. sync clone to origin/main (never destructive) ----
git fetch origin main --quiet || fail_closed "git fetch failed"
git checkout main --quiet 2>/dev/null || fail_closed "cannot checkout main"
if ! git merge --ff-only origin/main --quiet 2>>"$LOG_FILE"; then
    fail_closed "clone has diverged from origin/main (refusing non-ff merge; inspect $MONITOR_REPO manually)"
fi
log "clone synced to $(git rev-parse --short HEAD)"

# Commit identity for any automated commits from this host.
git config user.name  "acfs-checksum-monitor ($(hostname -s))"
git config user.email "jeff141421@gmail.com"

# ---- generator dependencies (idempotent, quiet) ----
( cd packages/manifest && bun install --silent >>"$LOG_FILE" 2>&1 ) \
    || fail_closed "bun install failed in packages/manifest"

# ---- 2. generated-artifact drift check ----
drift_json="$STATE_DIR/drift-$RUN_TS.json"
set +e
bash scripts/check-manifest-drift.sh --json >"$drift_json" 2>>"$LOG_FILE"
drift_exit=$?
set -e
if [[ "$drift_exit" -gt 1 ]]; then
    fail_closed "drift checker failed (exit $drift_exit)"
fi
jq empty "$drift_json" 2>/dev/null || fail_closed "drift checker returned invalid JSON"

drift_detected="$(jq -r '.drift_detected' "$drift_json")"
drift_fixed=false
if [[ "$drift_detected" == "true" ]]; then
    log "generated artifact drift detected:"
    jq -r '.reasons[] | "  - \(.)"' "$drift_json" | tee -a "$LOG_FILE" >&2
    # --fix regenerates, commits, and pushes on its own (same as the workflow).
    bash scripts/check-manifest-drift.sh --fix >>"$LOG_FILE" 2>&1 \
        || fail_closed "drift --fix failed (see $LOG_FILE)"
    drift_fixed=true
    log "drift auto-fixed and pushed"
else
    log "no generated-artifact drift"
fi

# ---- 3. verify upstream checksums ----
verify_json="$STATE_DIR/verify-$RUN_TS.json"
set +e
bash scripts/lib/security.sh --verify --json >"$verify_json" 2>>"$LOG_FILE"
set -e
jq empty "$verify_json" 2>/dev/null || fail_closed "checksum verification returned invalid JSON"

mismatches="$(jq '.mismatches | length' "$verify_json")"
errors="$(jq '.errors | length' "$verify_json")"
skipped="$(jq '.skipped | length' "$verify_json")"

# ---- 4. fail closed on any error/skip ----
if [[ "$errors" -gt 0 || "$skipped" -gt 0 ]]; then
    jq -r '.errors[]?  | "  error: \(.name) -> \(.error)"'    "$verify_json" | tee -a "$LOG_FILE" >&2
    jq -r '.skipped[]? | "  skipped: \(.name) -> \(.reason)"' "$verify_json" | tee -a "$LOG_FILE" >&2
    fail_closed "verification returned $errors error(s) / $skipped skip(s); refusing to auto-update checksums.yaml"
fi

trusted_changed=""
external_changed=""
if [[ "$mismatches" -gt 0 ]]; then
    while IFS= read -r name; do
        url="$(jq -r --arg n "$name" '.mismatches[] | select(.name==$n) | .url // empty' "$verify_json")"
        if [[ "$url" == *"Dicklesworthstone"* ]]; then
            trusted_changed="${trusted_changed}${name},"
        else
            external_changed="${external_changed}${name},"
        fi
    done < <(jq -r '.mismatches[].name' "$verify_json")
fi
trusted_changed="${trusted_changed%,}"
external_changed="${external_changed%,}"

committed=false
if [[ "$mismatches" -gt 0 ]]; then
    changed_tools="$(jq -r '.mismatches[].name' "$verify_json" | paste -sd, -)"
    log "changed tools: $changed_tools (trusted: ${trusted_changed:-none}; external: ${external_changed:-none})"

    # ---- 5. regenerate checksums via the canonical updater ----
    candidate="$STATE_DIR/checksums-$RUN_TS.yaml"
    bash scripts/lib/security.sh --update-checksums >"$candidate" 2>>"$LOG_FILE" \
        || fail_closed "--update-checksums failed"
    # Belt-and-suspenders beyond the workflow: never accept an empty or
    # shrunken candidate (a network blip must not truncate the manifest).
    old_count="$(grep -c 'sha256:' checksums.yaml || true)"
    new_count="$(grep -c 'sha256:' "$candidate" || true)"
    if [[ ! -s "$candidate" || "$new_count" -lt "$old_count" ]]; then
        fail_closed "candidate checksums.yaml invalid (entries: $new_count vs $old_count)"
    fi
    cp "$candidate" checksums.yaml

    # Regenerate in the same run: manifest-modules.ts embeds
    # checksumsYamlSha256, so skipping this leaves a guaranteed drift for
    # the next run to clean up (the Actions workflow had that two-step lag).
    ( cd packages/manifest && bun run generate >>"$LOG_FILE" 2>&1 ) \
        || fail_closed "regeneration after checksum update failed"

    # Tracked files plus brand-new generator outputs only; other stray
    # untracked files in the generated dirs must never ride along in an
    # automated commit. Without the new-file pass, a first-time generated
    # script (new manifest category) would stay untracked and the drift
    # check would wedge the monitor on every run.
    git add checksums.yaml 2>/dev/null || true
    git add -u scripts/generated/ apps/web/lib/generated/ 2>/dev/null || true
    while IFS= read -r new_generated; do
        case "$new_generated" in
            scripts/generated/*.sh|apps/web/lib/generated/*.ts) git add -- "$new_generated" 2>/dev/null || true ;;
        esac
    done < <(git ls-files --others --exclude-standard -- scripts/generated apps/web/lib/generated 2>/dev/null)
    if git diff --cached --quiet; then
        log "no staged changes after regeneration (already current)"
    else
        subject="chore(security): auto-update checksums for ${changed_tools}"
        if [[ "$drift_fixed" == "true" ]]; then
            subject="chore(security): auto-update checksums + generated drift fixes"
        fi
        git commit --quiet \
            -m "$subject" \
            -m "Updated checksums for upstream installer scripts that have changed." \
            -m "" \
            -m "Changed tools: ${changed_tools}" \
            -m "Trusted: ${trusted_changed:-none}" \
            -m "External: ${external_changed:-none}" \
            -m "Drift fixed: ${drift_fixed}" \
            -m "" \
            -m "Generated by checksum-monitor-local on $(hostname -s)"
        if ! git pull --rebase --quiet origin main; then
            git rebase --abort 2>/dev/null || true
            # Leaving the local commit in place wedged the monitor for good:
            # the next run's `merge --ff-only origin/main` then fails forever
            # ("diverged") with only a log line. This clone is dedicated and
            # every monitor commit is regenerable, so drop the local commit
            # and let the next run redo it on top of the new origin/main.
            if git checkout --quiet --detach && git branch -f main origin/main && git checkout --quiet main; then
                log "rebase conflict; discarded the local monitor commit and re-synced to origin/main — next run will retry"
            else
                log "rebase conflict and re-sync failed; inspect $MONITOR_REPO manually"
            fi
        else
            git push --quiet origin HEAD:main \
                && git push --quiet origin main:master \
                && committed=true
            log "checksum update pushed (main + master)"
        fi
    fi
else
    log "all checksums match upstream"
fi

# ---- 6. issue for external changes (security visibility) ----
if [[ -n "$external_changed" && "$committed" == "true" ]]; then
    repo_slug="Dicklesworthstone/agentic_coding_flywheel_setup"
    body_file="$STATE_DIR/issue-body-$RUN_TS.md"
    {
        echo "## External Installer Checksums Updated"
        echo
        echo "The following **external** (non-Dicklesworthstone) installer scripts have changed:"
        echo
        tr ',' '\n' <<<"$external_changed" | sed 's/^/- `/; s/$/`/'
        echo
        echo "### Action Required"
        echo "These checksums were automatically updated. Please verify the upstream changes are legitimate:"
        echo
        tr ',' '\n' <<<"$external_changed" | sed 's/^/- [ ] Review /; s/$/ changes/'
        echo
        echo "### Why this matters"
        echo "External installers (ohmyzsh, rustup, bun, etc.) could be compromised. While auto-updating keeps users unblocked, a quick review ensures we're not distributing malicious code."
        echo
        echo "---"
        echo "Auto-generated by checksum-monitor-local on $(hostname -s)"
    } >"$body_file"

    existing="$(gh issue list --repo "$repo_slug" --state open \
        --label security --label checksum-update \
        --search "External installer checksums" \
        --json number -q '.[0].number' 2>>"$LOG_FILE" || true)"
    if [[ -n "$existing" && "$existing" != "null" ]]; then
        gh issue comment "$existing" --repo "$repo_slug" \
            --body "### Additional changes detected

$(command cat "$body_file")" >>"$LOG_FILE" 2>&1 \
            && log "commented on existing issue #$existing"
    else
        gh issue create --repo "$repo_slug" \
            --title "🔐 External installer checksums updated - review recommended" \
            --label security --label checksum-update \
            --body-file "$body_file" >>"$LOG_FILE" 2>&1 \
            && log "created external-change review issue"
    fi
fi

# Healthy run: clear the consecutive fail-closed streak
printf '0\n' > "$FAIL_STREAK_FILE" 2>/dev/null || true

log "summary: result=ok drift_detected=$drift_detected drift_fixed=$drift_fixed mismatches=$mismatches errors=$errors skipped=$skipped trusted=${trusted_changed:-none} external=${external_changed:-none} committed=$committed"
