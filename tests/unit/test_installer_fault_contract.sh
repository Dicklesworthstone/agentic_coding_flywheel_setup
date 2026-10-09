#!/usr/bin/env bash
# ============================================================
# Unit contract for installer fault-injection fixtures
#
# This test defines the fixture taxonomy future unit, smoke, and
# VM-style tests should use when rehearsing ugly installer failures.
# It intentionally does not run the installer, touch the network, or
# exercise distribution upgrades. The goal is a stable local contract:
#
# - upstream_installer_unavailable: verified upstream script cannot be fetched.
# - checksum_mismatch: downloaded installer content fails checksum verification.
# - network_timeout: transient network timeout after retry/backoff attempts.
# - permission_denied: state/log/support evidence cannot be written.
# - malformed_state: checkpoint file is not parseable JSON and must fail closed.
# - interrupted_resume: checkpoint is stale but not failed, so continue/status wins.
# - ubuntu_upgrade_interrupted: upgrade checkpoint is awaiting reboot/resume.
# ============================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESCUE_SH="$REPO_ROOT/scripts/lib/rescue.sh"
SUPPORT_SH="$REPO_ROOT/scripts/lib/support.sh"
TESTS_PASSED=0
TESTS_FAILED=0
ARTIFACT_DIR="${ACFS_FAULT_CONTRACT_ARTIFACTS_DIR:-${TMPDIR:-/tmp}/acfs-fault-contract-artifacts-$(date +%Y%m%d-%H%M%S)-$$}"

mkdir -p "$ARTIFACT_DIR"

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1"
    if [[ -n "${2:-}" ]]; then
        echo "  Reason: $2"
    fi
}

write_file() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path"
}

write_support_stub() {
    local fixture_dir="$1"

    write_file "$fixture_dir/support/local_progress.json" <<'JSON'
{
  "schema_version": 1,
  "status": "pass",
  "summary": {"milestone_event_count": 1},
  "redaction": {
    "raw_values_collected": false,
    "command_history_collected": false,
    "network_submission": false
  }
}
JSON
    write_file "$fixture_dir/support/manifest.json" <<'JSON'
{
  "schema_version": 1,
  "created_by": "installer fault contract test",
  "files": [
    "state.json",
    "logs/install.log",
    "rescue.json",
    "rescue.human.txt",
    "support/local_progress.json",
    "support/checkpoint_summary.json"
  ]
}
JSON
}

write_failed_state() {
    local path="$1"
    local phase_id="$2"
    local step="$3"
    local error="$4"
    local resume_hint="$5"

    write_file "$path" <<JSON
{
  "schema_version": 3,
  "version": "test",
  "mode": "vibe",
  "completed_phases": ["user_setup"],
  "current_phase": null,
  "current_step": null,
  "failed_phase": "$phase_id",
  "failed_step": "$step",
  "failed_error": "$error",
  "resume_hint": "$resume_hint"
}
JSON
}

write_interrupted_state() {
    local path="$1"

    write_file "$path" <<'JSON'
{
  "schema_version": 3,
  "version": "test",
  "mode": "vibe",
  "completed_phases": ["user_setup", "filesystem"],
  "current_phase": "languages",
  "current_step": "Installing Bun",
  "failed_phase": null,
  "failed_step": null,
  "last_updated": 1000
}
JSON
}

write_ubuntu_upgrade_state() {
    local path="$1"

    write_file "$path" <<'JSON'
{
  "schema_version": 3,
  "version": "test",
  "mode": "vibe",
  "completed_phases": ["user_setup", "filesystem"],
  "current_phase": "ubuntu_upgrade",
  "current_step": "Awaiting reboot after Ubuntu upgrade hop",
  "failed_phase": null,
  "failed_step": null,
  "last_updated": 1000,
  "ubuntu_upgrade": {
    "enabled": true,
    "started_at": "2026-05-08T00:00:00Z",
    "original_version": "22.04",
    "target_version": "25.10",
    "upgrade_path": ["24.04", "25.04", "25.10"],
    "current_stage": "awaiting_reboot",
    "completed_upgrades": [
      {"from": "22.04", "to": "24.04", "completed_at": "2026-05-08T00:30:00Z"}
    ],
    "current_upgrade": null,
    "needs_reboot": true,
    "resume_after_reboot": true,
    "last_error": null
  }
}
JSON
}

write_expected() {
    local fixture_dir="$1"
    local id="$2"
    local failure_class="$3"
    local phase_id="$4"
    local state_status="$5"
    local exit_code="$6"
    local recovery_command="$7"
    local recommendation="$8"
    local logs_json="$9"

    cat > "$fixture_dir/expected.json" <<JSON
{
  "schema_version": 1,
  "id": "$id",
  "failure_class": "$failure_class",
  "phase_id": "$phase_id",
  "state_status": "$state_status",
  "expected_exit_code": $exit_code,
  "expected_log_substrings": $logs_json,
  "support_evidence": [
    "state.json",
    "logs/install.log",
    "rescue.json",
    "rescue.human.txt",
    "support/local_progress.json",
    "support/checkpoint_summary.json",
    "support/manifest.json"
  ],
  "recovery": {
    "command": "$recovery_command",
    "recommendation": "$recommendation"
  }
}
JSON
}

new_fixture() {
    local id="$1"
    local fixture_dir="$ARTIFACT_DIR/$id"
    mkdir -p "$fixture_dir/logs"
    write_support_stub "$fixture_dir"
    printf '%s\n' "$fixture_dir"
}

fixture_upstream_installer_unavailable() {
    local dir
    dir="$(new_fixture upstream-installer-unavailable)"
    write_failed_state "$dir/state.json" "stack" "Installing RCH" "curl exit 22 while fetching verified installer" "acfs rescue --json"
    write_file "$dir/logs/install.log" <<'LOG'
[stack] Installing RCH
verified installer fetch failed
curl exit 22
support evidence: state.json logs/install.log local_progress.json
LOG
    write_expected "$dir" "upstream-installer-unavailable" "upstream_installer_unavailable" "stack" "failed" 22 \
        "acfs rescue --json" \
        "Surface the failed phase and collect a support bundle before retrying the same pinned installer." \
        '["verified installer fetch failed", "curl exit 22", "support evidence"]'
}

fixture_checksum_mismatch() {
    local dir
    dir="$(new_fixture checksum-mismatch)"
    write_failed_state "$dir/state.json" "languages" "Installing Bun" "checksum mismatch for bun installer" "acfs support-bundle"
    write_file "$dir/logs/install.log" <<'LOG'
[languages] Installing Bun
checksum mismatch for verified installer
expected sha256 did not match downloaded content
support evidence: state.json logs/install.log local_progress.json
LOG
    write_expected "$dir" "checksum-mismatch" "checksum_mismatch" "languages" "failed" 1 \
        "acfs support-bundle" \
        "Fail closed, do not bypass checksum verification, and preserve evidence for review." \
        '["checksum mismatch", "expected sha256", "support evidence"]'
}

fixture_network_timeout() {
    local dir
    dir="$(new_fixture network-timeout)"
    write_failed_state "$dir/state.json" "shell_setup" "Installing Oh My Zsh" "curl exit 28 after retry_with_backoff" "acfs rescue --json"
    write_file "$dir/logs/install.log" <<'LOG'
[shell_setup] Installing Oh My Zsh
network timeout while fetching installer
curl exit 28
retry_with_backoff attempts exhausted
support evidence: state.json logs/install.log local_progress.json
LOG
    write_expected "$dir" "network-timeout" "network_timeout" "shell_setup" "failed" 28 \
        "acfs rescue --json" \
        "Classify as transient, show retry context, and resume from the checkpoint after connectivity is back." \
        '["network timeout", "curl exit 28", "retry_with_backoff attempts exhausted"]'
}

fixture_permission_denied() {
    local dir
    dir="$(new_fixture permission-denied)"
    write_failed_state "$dir/state.json" "finalize" "Writing state file" "permission denied writing state file" "acfs support-bundle"
    write_file "$dir/logs/install.log" <<'LOG'
[finalize] Writing state file
permission denied writing state file
state_write_atomic failed
support evidence: state.json logs/install.log local_progress.json
LOG
    write_expected "$dir" "permission-denied" "permission_denied" "finalize" "failed" 13 \
        "acfs support-bundle" \
        "Preserve ownership and path evidence so support can identify the bad writable surface." \
        '["permission denied", "state_write_atomic failed", "support evidence"]'
}

fixture_malformed_state() {
    local dir
    dir="$(new_fixture malformed-state)"
    write_file "$dir/state.json" <<'JSON'
{"schema_version": 3, "completed_phases": [
JSON
    write_file "$dir/logs/install.log" <<'LOG'
[resume] Loading checkpoint
state file is not valid JSON
fail closed and ask for support bundle
support evidence: state.json logs/install.log local_progress.json
LOG
    write_expected "$dir" "malformed-state" "malformed_state" "resume" "malformed" 2 \
        "acfs support-bundle" \
        "Fail closed because resume cannot safely infer completed phases from malformed state." \
        '["state file is not valid JSON", "fail closed", "support evidence"]'
}

fixture_interrupted_resume() {
    local dir
    dir="$(new_fixture interrupted-resume)"
    write_interrupted_state "$dir/state.json"
    write_file "$dir/logs/install.log" <<'LOG'
[languages] Installing Bun
checkpoint still marks current phase
checkpoint age seconds: 4000
support evidence: state.json logs/install.log local_progress.json
LOG
    write_expected "$dir" "interrupted-resume" "interrupted_resume" "languages" "interrupted" 1 \
        "acfs continue --status" \
        "Prefer status/continue guidance before retrying because no failed phase was recorded." \
        '["checkpoint still marks current phase", "checkpoint age seconds", "support evidence"]'
}

fixture_ubuntu_upgrade_interrupted() {
    local dir
    dir="$(new_fixture ubuntu-upgrade-interrupted)"
    write_ubuntu_upgrade_state "$dir/state.json"
    write_file "$dir/logs/install.log" <<'LOG'
[ubuntu_upgrade] Awaiting reboot after Ubuntu upgrade hop
upgrade path: 22.04 -> 24.04 -> 25.04 -> 25.10
completed hop: 22.04 -> 24.04
resume service: acfs-upgrade-resume
support evidence: state.json logs/install.log local_progress.json checkpoint_summary.json
LOG
    write_expected "$dir" "ubuntu-upgrade-interrupted" "ubuntu_upgrade_interrupted" "ubuntu_upgrade" "ubuntu_upgrade" 1 \
        "acfs continue --status" \
        "Use the upgrade resume/status path and preserve upgrade logs before retrying any installer command." \
        '["upgrade path: 22.04 -> 24.04 -> 25.04 -> 25.10", "resume service: acfs-upgrade-resume", "support evidence"]'
}

assert_safe_recovery_command() {
    local command="$1"
    local package_manager_pattern='(^|[^[:alnum:]_])(npm|yarn|pnpm)([^[:alnum:]_]|$)'

    [[ "$command" != *"git reset"* ]] || return 1
    [[ "$command" != *"git clean"* ]] || return 1
    [[ ! "$command" =~ $package_manager_pattern ]] || return 1
}

state_summary() {
    local state_file="$1"

    if [[ ! -e "$state_file" ]]; then
        printf 'missing\n'
        return 0
    fi
    if ! jq -e . "$state_file" >/dev/null 2>&1; then
        printf 'malformed\n'
        return 0
    fi
    jq -r '"valid phase=" + ((.failed_phase // .current_phase // "none") | tostring) + " step=" + ((.failed_step // .current_step // "none") | tostring)' "$state_file"
}

assert_state_status() {
    local fixture_dir="$1"
    local expected_status="$2"
    local state_file="$fixture_dir/state.json"

    case "$expected_status" in
        failed)
            jq -e '.failed_phase != null and .failed_step != null and .failed_error != null and .resume_hint != null' "$state_file" >/dev/null
            ;;
        malformed)
            ! jq -e . "$state_file" >/dev/null 2>&1
            ;;
        interrupted)
            jq -e '.current_phase != null and .current_step != null and (.failed_phase == null) and (.failed_step == null)' "$state_file" >/dev/null
            ;;
        ubuntu_upgrade)
            jq -e '
              .current_phase == "ubuntu_upgrade" and
              .ubuntu_upgrade.enabled == true and
              .ubuntu_upgrade.current_stage == "awaiting_reboot" and
              .ubuntu_upgrade.needs_reboot == true and
              .ubuntu_upgrade.resume_after_reboot == true and
              (.ubuntu_upgrade.upgrade_path | join(" ") == "24.04 25.04 25.10")
            ' "$state_file" >/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

expected_rescue_status_for_state() {
    local state_status="$1"

    case "$state_status" in
        failed|malformed)
            printf 'fail|blocked|2\n'
            ;;
        interrupted|ubuntu_upgrade)
            printf 'warn|stale_checkpoint|1\n'
            ;;
        *)
            return 1
            ;;
    esac
}

expected_checkpoint_summary_for_state() {
    local state_status="$1"

    case "$state_status" in
        failed)
            printf 'fail|blocked\n'
            ;;
        malformed)
            printf 'warn|malformed_state\n'
            ;;
        interrupted|ubuntu_upgrade)
            printf 'warn|stale_checkpoint\n'
            ;;
        *)
            return 1
            ;;
    esac
}

run_rescue_lab_outputs() {
    local fixture_dir="$1"
    local state_status="$2"
    local rescue_json="$fixture_dir/rescue.json"
    local rescue_human="$fixture_dir/rescue.human.txt"
    local status=0
    local -a rescue_args=(--state-file "$fixture_dir/state.json" --support-dir "$fixture_dir/support")

    case "$state_status" in
        interrupted|ubuntu_upgrade)
            rescue_args+=(--now-epoch 5000 --stale-seconds 60)
            ;;
    esac

    set +e
    bash "$RESCUE_SH" --json "${rescue_args[@]}" > "$rescue_json" 2>&1
    status=$?
    set -e
    printf '%s\n' "$status" > "$fixture_dir/rescue.exit"

    set +e
    bash "$RESCUE_SH" "${rescue_args[@]}" > "$rescue_human" 2>&1
    status=$?
    set -e
    printf '%s\n' "$status" > "$fixture_dir/rescue.human.exit"
}

capture_checkpoint_summary_for_fixture() {
    local fixture_dir="$1"

    env SUPPORT_SH="$SUPPORT_SH" FIXTURE_DIR="$fixture_dir" bash -c '
        set -euo pipefail
        log_step() { :; }
        log_section() { :; }
        log_detail() { :; }
        log_success() { :; }
        log_warn() { :; }
        log_error() { :; }
        source "$SUPPORT_SH"
        _SUPPORT_ACFS_HOME="$FIXTURE_DIR"
        BUNDLE_FILES=()
        ACFS_SUPPORT_NOW_EPOCH=5000 ACFS_CHECKPOINT_STALE_SECONDS=60 capture_checkpoint_summary_json "$FIXTURE_DIR/support"
    '
}

assert_no_sensitive_fault_lab_output() {
    local fixture_dir="$1"
    local file=""

    for file in "$fixture_dir/rescue.json" "$fixture_dir/rescue.human.txt" "$fixture_dir/support/checkpoint_summary.json"; do
        [[ -f "$file" ]] || return 1
        ! grep -Eq 'ghp_|/home/alice|PRIVATE|password|token=' "$file" || {
            echo "Sensitive content leaked in $file"
            return 1
        }
    done
}

assert_rescue_outputs() {
    local fixture_dir="$1"
    local state_status="$2"
    local recovery_command="$3"
    local expected_status expected_severity expected_exit
    local actual_json_exit actual_human_exit

    IFS='|' read -r expected_status expected_severity expected_exit < <(expected_rescue_status_for_state "$state_status")
    actual_json_exit="$(cat "$fixture_dir/rescue.exit")"
    actual_human_exit="$(cat "$fixture_dir/rescue.human.exit")"

    [[ "$actual_json_exit" -eq "$expected_exit" ]] || {
        echo "Unexpected rescue JSON exit for $fixture_dir: $actual_json_exit"
        return 1
    }
    [[ "$actual_human_exit" -eq "$expected_exit" ]] || {
        echo "Unexpected rescue human exit for $fixture_dir: $actual_human_exit"
        return 1
    }

    jq -e \
        --arg status "$expected_status" \
        --arg severity "$expected_severity" \
        --arg command "$recovery_command" \
        '
          .status == $status and
          .severity == $severity and
          .next_command == $command and
          (.evidence | length) >= 2
        ' "$fixture_dir/rescue.json" >/dev/null || return 1

    grep -Fq "Next command: $recovery_command" "$fixture_dir/rescue.human.txt" || return 1
    grep -Fq "Evidence:" "$fixture_dir/rescue.human.txt" || return 1
    ! grep -E 'rm -rf|git reset|git clean|delete|overwrite' "$fixture_dir/rescue.human.txt" >/dev/null || return 1
}

assert_checkpoint_summary() {
    local fixture_dir="$1"
    local state_status="$2"
    local expected_status expected_severity

    IFS='|' read -r expected_status expected_severity < <(expected_checkpoint_summary_for_state "$state_status")

    jq -e \
        --arg status "$expected_status" \
        --arg severity "$expected_severity" \
        '
          .schema_version == 1 and
          .status == $status and
          .severity == $severity and
          .redaction.raw_values_collected == false and
          .redaction.raw_paths_collected == false and
          .redaction.secrets_collected == false
        ' "$fixture_dir/support/checkpoint_summary.json" >/dev/null || return 1
}

validate_fixture() {
    local fixture_dir="$1"
    local expected_json="$fixture_dir/expected.json"
    local id failure_class phase_id state_status recovery_command recommendation
    local state_text

    id="$(jq -r '.id' "$expected_json")"
    failure_class="$(jq -r '.failure_class' "$expected_json")"
    phase_id="$(jq -r '.phase_id' "$expected_json")"
    state_status="$(jq -r '.state_status' "$expected_json")"
    recovery_command="$(jq -r '.recovery.command' "$expected_json")"
    recommendation="$(jq -r '.recovery.recommendation' "$expected_json")"
    state_text="$(state_summary "$fixture_dir/state.json")"

    echo "Fixture: $id"
    echo "  artifacts: $fixture_dir"
    echo "  state: $state_text"
    echo "  recovery: $recovery_command"
    echo "  recommendation: $recommendation"

    jq -e '.schema_version == 1 and (.expected_log_substrings | length) >= 2 and (.support_evidence | length) >= 3' "$expected_json" >/dev/null || return 1

    case "$failure_class" in
        upstream_installer_unavailable|checksum_mismatch|network_timeout|permission_denied|malformed_state|interrupted_resume|ubuntu_upgrade_interrupted)
            ;;
        *)
            echo "Unknown failure class: $failure_class"
            return 1
            ;;
    esac

    [[ -n "$phase_id" && "$phase_id" != "null" ]] || return 1
    [[ -n "$recommendation" && "$recommendation" != "null" ]] || return 1
    assert_safe_recovery_command "$recovery_command" || return 1
    assert_state_status "$fixture_dir" "$state_status" || return 1
    run_rescue_lab_outputs "$fixture_dir" "$state_status"
    capture_checkpoint_summary_for_fixture "$fixture_dir"
    assert_rescue_outputs "$fixture_dir" "$state_status" "$recovery_command" || return 1
    assert_checkpoint_summary "$fixture_dir" "$state_status" || return 1
    assert_no_sensitive_fault_lab_output "$fixture_dir" || return 1

    local evidence
    mapfile -t evidence < <(jq -r '.support_evidence[]' "$expected_json")
    for evidence in "${evidence[@]}"; do
        [[ -e "$fixture_dir/$evidence" ]] || {
            echo "Missing support evidence: $evidence"
            return 1
        }
    done

    local needle
    mapfile -t needle < <(jq -r '.expected_log_substrings[]' "$expected_json")
    for needle in "${needle[@]}"; do
        grep -Fq "$needle" "$fixture_dir/logs/install.log" || {
            echo "Missing log evidence: $needle"
            return 1
        }
    done
}

run_test() {
    local name="$1"
    if "$name"; then
        pass "$name"
        return 0
    fi
    fail "$name"
    return 1
}

test_all_fault_fixtures_satisfy_contract() {
    local fixture_dir

    fixture_upstream_installer_unavailable
    fixture_checksum_mismatch
    fixture_network_timeout
    fixture_permission_denied
    fixture_malformed_state
    fixture_interrupted_resume
    fixture_ubuntu_upgrade_interrupted

    for fixture_dir in "$ARTIFACT_DIR"/*; do
        [[ -d "$fixture_dir" ]] || continue
        validate_fixture "$fixture_dir" || return 1
    done
}

main() {
    command -v jq >/dev/null 2>&1 || {
        echo "jq is required for installer fault contract tests" >&2
        exit 1
    }

    echo "Installer fault-injection contract artifacts: $ARTIFACT_DIR"
    run_test test_all_fault_fixtures_satisfy_contract || true

    echo
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo "Artifacts: $ARTIFACT_DIR"

    [[ "$TESTS_FAILED" -eq 0 ]]
}

main "$@"
