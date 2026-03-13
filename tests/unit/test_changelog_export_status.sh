#!/usr/bin/env bash
# shellcheck disable=SC1091
# ============================================================
# Targeted regression tests for changelog, export-config, and
# status output handling.
# Usage: bash tests/unit/test_changelog_export_status.sh
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHANGELOG_SH="$REPO_ROOT/scripts/lib/changelog.sh"
EXPORT_CONFIG_SH="$REPO_ROOT/scripts/lib/export-config.sh"
STATUS_SH="$REPO_ROOT/scripts/lib/status.sh"
DASHBOARD_SH="$REPO_ROOT/scripts/lib/dashboard.sh"
DOCTOR_SH="$REPO_ROOT/scripts/lib/doctor.sh"
CONTINUE_SH="$REPO_ROOT/scripts/lib/continue.sh"
ONBOARD_SH="$REPO_ROOT/packages/onboard/onboard.sh"

source "$REPO_ROOT/tests/vm/lib/test_harness.sh"

TEST_HOME=""
TEST_ACFS=""
TEST_REPO=""
TEST_INSTALL_HELPERS=""
TEST_MANIFEST_INDEX=""
TEST_ROOT_HOME=""
TEST_INSTALLED_ACFS=""
TEST_TARGET_HOME=""
TEST_FAKE_BIN=""
TEST_INSTALLED_HELPERS=""
TEST_INSTALLED_MANIFEST_INDEX=""
TEST_SYSTEM_STATE_FILE=""
TEST_DEV_REPO=""

setup_mock_env() {
    TEST_HOME="$(mktemp -d)"
    TEST_ACFS="$TEST_HOME/.acfs"
    TEST_REPO="$TEST_HOME/mock-repo"
    mkdir -p "$TEST_ACFS" "$TEST_REPO"

    cat > "$TEST_ACFS/state.json" <<'JSON'
{
  "mode": "vibe \"quoted\"",
  "target_user": "tester",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
JSON

    printf '1.2.3 "beta"\n' > "$TEST_ACFS/VERSION"

    cat > "$TEST_REPO/CHANGELOG.md" <<'EOF'
# Changelog

## [1.2.3] - 2026-03-10

### Fixed
- Fixed "quoted" Windows path C:\temp
  Continued detail with	tab data

## [1.2.2] - 2026-03-01

### Added
- Legacy entry that should be filtered by the current state timestamp
EOF

    TEST_INSTALL_HELPERS="$TEST_HOME/mock_install_helpers.sh"
    TEST_MANIFEST_INDEX="$TEST_HOME/mock_manifest_index.sh"

    cat > "$TEST_INSTALL_HELPERS" <<'EOF'
#!/usr/bin/env bash
acfs_module_is_installed() {
    [[ "${TARGET_USER:-}" == "tester" ]] || return 1
    [[ "${TARGET_HOME:-}" == "/home/tester" ]] || return 1

    case "$1" in
        alpha|'module "beta" \\ path') return 0 ;;
        *) return 1 ;;
    esac
}
EOF
    chmod +x "$TEST_INSTALL_HELPERS"

    cat > "$TEST_MANIFEST_INDEX" <<'EOF'
#!/usr/bin/env bash
ACFS_MODULES_IN_ORDER=(
  "alpha"
  "module \"beta\" \\\\ path"
  "gamma"
)
ACFS_MANIFEST_INDEX_LOADED=true
EOF
    chmod +x "$TEST_MANIFEST_INDEX"
}

write_fake_command() {
    local path="$1"
    local output="$2"
    cat > "$path" <<EOF
#!/usr/bin/env bash
echo '$output'
EOF
    chmod +x "$path"
}

setup_installed_layout_env() {
    setup_mock_env

    TEST_ROOT_HOME="$TEST_HOME/root-home"
    TEST_INSTALLED_ACFS="$TEST_HOME/installed/.acfs"
    TEST_TARGET_HOME="$TEST_HOME/users/tester"
    TEST_FAKE_BIN="$TEST_HOME/fake-bin"
    TEST_INSTALLED_HELPERS="$TEST_HOME/installed_helpers.sh"
    TEST_INSTALLED_MANIFEST_INDEX="$TEST_HOME/installed_manifest_index.sh"

    mkdir -p \
        "$TEST_ROOT_HOME" \
        "$TEST_INSTALLED_ACFS/bin" \
        "$TEST_INSTALLED_ACFS/scripts/lib" \
        "$TEST_INSTALLED_ACFS/scripts/generated" \
        "$TEST_TARGET_HOME/.local/bin" \
        "$TEST_TARGET_HOME/.bun/bin" \
        "$TEST_TARGET_HOME/.cargo/bin" \
        "$TEST_TARGET_HOME/go/bin" \
        "$TEST_TARGET_HOME/.atuin/bin" \
        "$TEST_FAKE_BIN"

    cp "$DOCTOR_SH" "$TEST_INSTALLED_ACFS/bin/acfs"
    cp "$STATUS_SH" "$TEST_INSTALLED_ACFS/scripts/lib/status.sh"
    cp "$CHANGELOG_SH" "$TEST_INSTALLED_ACFS/scripts/lib/changelog.sh"
    cp "$EXPORT_CONFIG_SH" "$TEST_INSTALLED_ACFS/scripts/lib/export-config.sh"
    cp "$CONTINUE_SH" "$TEST_INSTALLED_ACFS/scripts/lib/continue.sh"

    cat > "$TEST_INSTALLED_ACFS/state.json" <<'JSON'
{
  "mode": "safe",
  "target_user": "tester",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools"
}
JSON
    printf '2.0.0\n' > "$TEST_INSTALLED_ACFS/VERSION"

    cat > "$TEST_INSTALLED_ACFS/CHANGELOG.md" <<'EOF'
# Changelog

## [2.0.0] - 2026-03-10

### Fixed
- Installed-layout root discovery now works correctly

## [1.9.0] - 2026-02-01

### Added
- Older entry that should be filtered out by last_updated
EOF

    cat > "$TEST_INSTALLED_HELPERS" <<EOF
#!/usr/bin/env bash
acfs_module_is_installed() {
    [[ "\${TARGET_USER:-}" == "tester" ]] || return 1
    [[ "\${TARGET_HOME:-}" == "$TEST_TARGET_HOME" ]] || return 1

    case "\$1" in
        alpha|'module "beta" \\\\ path') return 0 ;;
        *) return 1 ;;
    esac
}
EOF
    chmod +x "$TEST_INSTALLED_HELPERS"

    cat > "$TEST_INSTALLED_MANIFEST_INDEX" <<'EOF'
#!/usr/bin/env bash
ACFS_MODULES_IN_ORDER=(
  "alpha"
  "module \"beta\" \\\\ path"
  "gamma"
)
ACFS_MANIFEST_INDEX_LOADED=true
EOF
    chmod +x "$TEST_INSTALLED_MANIFEST_INDEX"

    cat > "$TEST_FAKE_BIN/getent" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "passwd" ]] && [[ "\$2" == "tester" ]]; then
    echo "tester:x:1000:1000::${TEST_TARGET_HOME}:/bin/bash"
    exit 0
fi
exit 2
EOF
    chmod +x "$TEST_FAKE_BIN/getent"

    cat > "$TEST_FAKE_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/pgrep"

    cat > "$TEST_FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/systemctl"

    write_fake_command "$TEST_TARGET_HOME/.local/bin/zsh" "zsh 5.9"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/git" "git version 2.43.0"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/tmux" "tmux 3.4"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/rg" "ripgrep 14.1.0"
    write_fake_command "$TEST_TARGET_HOME/.local/bin/claude" "claude 1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.bun/bin/bun" "1.2.3"
    write_fake_command "$TEST_TARGET_HOME/.cargo/bin/cargo" "cargo 1.85.0"
    write_fake_command "$TEST_TARGET_HOME/go/bin/go" "go version go1.24.0 linux/amd64"
}

setup_system_state_only_env() {
    setup_installed_layout_env

    TEST_SYSTEM_STATE_FILE="$TEST_HOME/system-state/state.json"
    mkdir -p "$(dirname "$TEST_SYSTEM_STATE_FILE")"
    mv "$TEST_INSTALLED_ACFS/state.json" "$TEST_INSTALLED_ACFS/state.user.bak"

    cat > "$TEST_SYSTEM_STATE_FILE" <<'JSON'
{
  "mode": "safe",
  "target_user": "tester",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "current_phase": { "id": "bootstrap" },
  "current_step": "Installing tools",
  "skipped_tools": ["ntm", "bv"]
}
JSON
}

cleanup_mock_env() {
    if [[ -n "$TEST_HOME" ]] && [[ -d "$TEST_HOME" ]]; then
        rm -rf "$TEST_HOME"
    fi
}

test_changelog_json_is_valid() {
    setup_mock_env

    local output
    output=$(ACFS_HOME="$TEST_ACFS" ACFS_REPO="$TEST_REPO" bash "$CHANGELOG_SH" --all --json)

    if printf '%s\n' "$output" | jq -e '.changes | length == 2' >/dev/null 2>&1; then
        harness_pass "changelog JSON stays valid with quotes, backslashes, and tabs"
    else
        harness_fail "changelog JSON stays valid with quotes, backslashes, and tabs"
    fi

    cleanup_mock_env
}

test_changelog_rejects_invalid_duration() {
    setup_mock_env

    local output=""
    local exit_code=0
    output=$(ACFS_HOME="$TEST_ACFS" ACFS_REPO="$TEST_REPO" bash "$CHANGELOG_SH" --since nonsense 2>&1) || exit_code=$?

    if [[ "$exit_code" -ne 0 ]] && [[ "$output" == *"invalid duration"* ]]; then
        harness_pass "changelog rejects malformed --since values"
    else
        harness_fail "changelog rejects malformed --since values" "exit=$exit_code output=$output"
    fi

    cleanup_mock_env
}

test_changelog_defaults_to_last_updated() {
    setup_mock_env

    local output
    output=$(ACFS_HOME="$TEST_ACFS" ACFS_REPO="$TEST_REPO" bash "$CHANGELOG_SH" --json)

    if printf '%s\n' "$output" | jq -e '.changes | (length == 1 and .[0].version == "1.2.3")' >/dev/null 2>&1; then
        harness_pass "changelog defaults to the current state last_updated timestamp"
    else
        harness_fail "changelog defaults to the current state last_updated timestamp"
    fi

    cleanup_mock_env
}

test_export_config_json_is_valid() {
    setup_mock_env

    local output
    output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" \
        ACFS_INSTALL_HELPERS_SH="$TEST_INSTALL_HELPERS" \
        ACFS_MANIFEST_INDEX_SH="$TEST_MANIFEST_INDEX" \
        bash "$EXPORT_CONFIG_SH" --json)

    if printf '%s\n' "$output" | jq -e '.settings.mode == "vibe \"quoted\"" and .modules[0] == "alpha" and .modules[1] == "module \"beta\" \\\\ path" and .metadata.acfs_version == "1.2.3 \"beta\""' >/dev/null 2>&1; then
        harness_pass "export-config JSON escapes state, version, and detected module strings correctly"
    else
        harness_fail "export-config JSON escapes state, version, and detected module strings correctly"
    fi

    cleanup_mock_env
}

test_status_rejects_unknown_flags() {
    setup_mock_env

    local output=""
    local exit_code=0
    output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" bash "$STATUS_SH" --bogus 2>&1) || exit_code=$?

    if [[ "$exit_code" -ne 0 ]] && [[ "$output" == *"Unknown option"* ]]; then
        harness_pass "status rejects unknown flags"
    else
        harness_fail "status rejects unknown flags" "exit=$exit_code output=$output"
    fi

    cleanup_mock_env
}

test_status_plain_output_avoids_ansi_when_not_tty() {
    setup_mock_env

    local output
    output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" bash "$STATUS_SH")

    if [[ "$output" == *$'\033['* ]]; then
        harness_fail "status suppresses ANSI codes when stdout is not a TTY" "$output"
    else
        harness_pass "status suppresses ANSI codes when stdout is not a TTY"
    fi

    cleanup_mock_env
}

test_status_reports_last_updated_timestamp() {
    setup_mock_env

    local output
    output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" bash "$STATUS_SH" --json)

    if printf '%s\n' "$output" | jq -e '.last_update == "2026-03-10T12:34:56Z"' >/dev/null 2>&1; then
        harness_pass "status reports last_updated from the current state schema"
    else
        harness_fail "status reports last_updated from the current state schema"
    fi

    cleanup_mock_env
}

test_status_errors_on_malformed_state_json() {
    setup_mock_env
    printf '{ invalid json\n' > "$TEST_ACFS/state.json"

    local output=""
    local exit_code=0
    output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" bash "$STATUS_SH" --json 2>&1) || exit_code=$?

    if [[ "$exit_code" -eq 2 ]] && printf '%s\n' "$output" | jq -e '.errors | index("state file invalid JSON")' >/dev/null 2>&1; then
        harness_pass "status marks malformed state.json as an error"
    else
        harness_fail "status marks malformed state.json as an error" "exit=$exit_code output=$output"
    fi

    cleanup_mock_env
}

test_dashboard_generation_is_atomic_on_failure() {
    setup_mock_env
    TEST_DEV_REPO="$TEST_HOME/dev-repo-failing-dashboard"
    mkdir -p "$TEST_ACFS/dashboard" "$TEST_DEV_REPO/scripts/lib"
    printf 'existing dashboard\n' > "$TEST_ACFS/dashboard/index.html"
    cp "$DASHBOARD_SH" "$TEST_DEV_REPO/scripts/lib/dashboard.sh"
    cat > "$TEST_DEV_REPO/scripts/lib/info.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TEST_DEV_REPO/scripts/lib/info.sh"

    local output=""
    local exit_code=0
    output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" bash "$TEST_DEV_REPO/scripts/lib/dashboard.sh" generate --force 2>&1) || exit_code=$?
    local current_contents
    current_contents=$(cat "$TEST_ACFS/dashboard/index.html")
    local leftover_tmp
    leftover_tmp=$(find "$TEST_ACFS/dashboard" -maxdepth 1 -name 'index.html.tmp.*' -print -quit 2>/dev/null || true)

    if [[ "$exit_code" -ne 0 ]] && [[ "$current_contents" == "existing dashboard" ]] && [[ -z "$leftover_tmp" ]]; then
        harness_pass "dashboard generation preserves the previous file on failure"
    else
        harness_fail "dashboard generation preserves the previous file on failure" "exit=$exit_code output=$output contents=$current_contents leftover_tmp=$leftover_tmp"
    fi

    cleanup_mock_env
}

test_dashboard_rejects_invalid_ports_before_serving() {
    setup_mock_env
    mkdir -p "$TEST_ACFS/dashboard"
    printf 'existing dashboard\n' > "$TEST_ACFS/dashboard/index.html"

    local output=""
    local exit_code=0
    output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" bash "$DASHBOARD_SH" serve --port not-a-number 2>&1) || exit_code=$?

    if [[ "$exit_code" -ne 0 ]] \
        && [[ "$output" == *"port must be an integer between 1 and 65535"* ]] \
        && [[ "$output" != *"http://localhost:not-a-number"* ]]; then
        harness_pass "dashboard serve rejects invalid ports before printing URLs"
    else
        harness_fail "dashboard serve rejects invalid ports before printing URLs" "exit=$exit_code output=$output"
    fi

    cleanup_mock_env
}

test_dashboard_prefers_repo_local_info_script() {
    setup_installed_layout_env

    TEST_DEV_REPO="$TEST_HOME/dev-repo"
    mkdir -p "$TEST_DEV_REPO/scripts/lib" "$TEST_INSTALLED_ACFS/scripts/lib"
    cp "$DASHBOARD_SH" "$TEST_DEV_REPO/scripts/lib/dashboard.sh"

    cat > "$TEST_DEV_REPO/scripts/lib/info.sh" <<'EOF'
#!/usr/bin/env bash
printf '<html>repo-local-info</html>\n'
EOF
    chmod +x "$TEST_DEV_REPO/scripts/lib/info.sh"

    cat > "$TEST_INSTALLED_ACFS/scripts/lib/info.sh" <<'EOF'
#!/usr/bin/env bash
printf '<html>installed-info</html>\n'
EOF
    chmod +x "$TEST_INSTALLED_ACFS/scripts/lib/info.sh"

    local output
    output=$(HOME="$TEST_ROOT_HOME" ACFS_HOME="$TEST_INSTALLED_ACFS" \
        bash "$TEST_DEV_REPO/scripts/lib/dashboard.sh" generate --force)

    if [[ "$output" == *"Dashboard generated:"* ]] \
        && grep -q 'repo-local-info' "$TEST_INSTALLED_ACFS/dashboard/index.html" \
        && ! grep -q 'installed-info' "$TEST_INSTALLED_ACFS/dashboard/index.html"; then
        harness_pass "dashboard prefers repo-local info.sh over installed copy"
    else
        harness_fail "dashboard prefers repo-local info.sh over installed copy" "$output"
    fi

    cleanup_mock_env
}

test_doctor_entrypoint_dispatches_helper_commands() {
    setup_mock_env

    local status_output
    status_output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" bash "$DOCTOR_SH" status --short)

    local changelog_output
    changelog_output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" ACFS_REPO="$TEST_REPO" bash "$DOCTOR_SH" changelog --all --json)

    local export_output
    export_output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" \
        ACFS_INSTALL_HELPERS_SH="$TEST_INSTALL_HELPERS" \
        ACFS_MANIFEST_INDEX_SH="$TEST_MANIFEST_INDEX" \
        bash "$DOCTOR_SH" export-config --json)

    if [[ -n "$status_output" ]] \
        && printf '%s\n' "$changelog_output" | jq -e '.changes | length == 2' >/dev/null 2>&1 \
        && printf '%s\n' "$export_output" | jq -e '.modules | length == 2' >/dev/null 2>&1; then
        harness_pass "doctor entrypoint dispatches status, changelog, and export-config"
    else
        harness_fail "doctor entrypoint dispatches status, changelog, and export-config"
    fi

    cleanup_mock_env
}

test_status_uses_installed_layout_under_root_home() {
    setup_installed_layout_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_ACFS/scripts/lib/status.sh" --json)

    if printf '%s\n' "$output" | jq -e '.status == "ok" and .last_update == "2026-03-10T12:34:56Z" and (.errors | length == 0)' >/dev/null 2>&1; then
        harness_pass "status resolves installed layout and target-user PATH under root home"
    else
        harness_fail "status resolves installed layout and target-user PATH under root home" "$output"
    fi

    cleanup_mock_env
}

test_status_uses_system_state_when_user_state_missing() {
    setup_system_state_only_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        ACFS_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_INSTALLED_ACFS/scripts/lib/status.sh" --json)

    if printf '%s\n' "$output" | jq -e '.status == "ok" and .last_update == "2026-03-10T12:34:56Z" and (.errors | length == 0)' >/dev/null 2>&1; then
        harness_pass "status falls back to system state when user state is missing"
    else
        harness_fail "status falls back to system state when user state is missing" "$output"
    fi

    cleanup_mock_env
}

test_changelog_uses_installed_layout_under_root_home() {
    setup_installed_layout_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_ACFS/scripts/lib/changelog.sh" --json)

    if printf '%s\n' "$output" | jq -e '.changes | (length == 1 and .[0].version == "2.0.0")' >/dev/null 2>&1; then
        harness_pass "changelog uses installed-layout state under root home"
    else
        harness_fail "changelog uses installed-layout state under root home" "$output"
    fi

    cleanup_mock_env
}

test_changelog_uses_system_state_when_user_state_missing() {
    setup_system_state_only_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        ACFS_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        bash "$TEST_INSTALLED_ACFS/scripts/lib/changelog.sh" --json)

    if printf '%s\n' "$output" | jq -e '.changes | (length == 1 and .[0].version == "2.0.0")' >/dev/null 2>&1; then
        harness_pass "changelog falls back to system state when user state is missing"
    else
        harness_fail "changelog falls back to system state when user state is missing" "$output"
    fi

    cleanup_mock_env
}

test_export_config_uses_installed_layout_under_root_home() {
    setup_installed_layout_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        ACFS_INSTALL_HELPERS_SH="$TEST_INSTALLED_HELPERS" \
        ACFS_MANIFEST_INDEX_SH="$TEST_INSTALLED_MANIFEST_INDEX" \
        bash "$TEST_INSTALLED_ACFS/scripts/lib/export-config.sh" --json)

    if printf '%s\n' "$output" | jq -e '.metadata.acfs_version == "2.0.0" and .settings.mode == "safe" and .tools.bun.version == "1.2.3" and .agents.claude.version == "1.2.3" and (.modules | length == 2)' >/dev/null 2>&1; then
        harness_pass "export-config uses installed-layout state and target-user PATH under root home"
    else
        harness_fail "export-config uses installed-layout state and target-user PATH under root home" "$output"
    fi

    cleanup_mock_env
}

test_export_config_uses_system_state_when_user_state_missing() {
    setup_system_state_only_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        ACFS_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        ACFS_INSTALL_HELPERS_SH="$TEST_INSTALLED_HELPERS" \
        ACFS_MANIFEST_INDEX_SH="$TEST_INSTALLED_MANIFEST_INDEX" \
        bash "$TEST_INSTALLED_ACFS/scripts/lib/export-config.sh" --json)

    if printf '%s\n' "$output" | jq -e '.metadata.acfs_version == "2.0.0" and .settings.mode == "safe" and .tools.bun.version == "1.2.3" and .agents.claude.version == "1.2.3" and (.modules | length == 2)' >/dev/null 2>&1; then
        harness_pass "export-config falls back to system state when user state is missing"
    else
        harness_fail "export-config falls back to system state when user state is missing" "$output"
    fi

    cleanup_mock_env
}

test_continue_uses_installed_layout_under_root_home() {
    setup_installed_layout_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_ACFS/scripts/lib/continue.sh" --status)

    if [[ "$output" == *"Installation in progress"* ]] && [[ "$output" == *"Phase:"*bootstrap* ]]; then
        harness_pass "continue discovers installed-layout state under root home"
    else
        harness_fail "continue discovers installed-layout state under root home" "$output"
    fi

    cleanup_mock_env
}

test_continue_ignores_generic_install_process_matches() {
    setup_installed_layout_env

    cat > "$TEST_INSTALLED_ACFS/state.json" <<'JSON'
{
  "mode": "safe",
  "target_user": "tester",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z"
}
JSON

    cat > "$TEST_FAKE_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *"bash.*install.sh.*--mode"*|*"bash.*install.sh.*--yes"*|*"bash.*install.sh.*--resume"*|*"bash -s -- .*--resume"*)
    exit 0
    ;;
esac
exit 1
EOF
    chmod +x "$TEST_FAKE_BIN/pgrep"

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_ACFS/scripts/lib/continue.sh" --status)

    if [[ "$output" == *"No active installation"* ]] && [[ "$output" != *"Installation in progress"* ]]; then
        harness_pass "continue ignores generic install.sh process matches"
    else
        harness_fail "continue ignores generic install.sh process matches" "$output"
    fi

    cleanup_mock_env
}

test_continue_failed_state_beats_runtime_probe() {
    setup_installed_layout_env

    cat > "$TEST_INSTALLED_ACFS/state.json" <<'JSON'
{
  "mode": "safe",
  "target_user": "tester",
  "started_at": "2026-03-09T08:00:00Z",
  "last_updated": "2026-03-10T12:34:56Z",
  "failed_phase": "agents",
  "failed_step": "install codex"
}
JSON

    cat > "$TEST_FAKE_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TEST_FAKE_BIN/pgrep"

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_ACFS/scripts/lib/continue.sh" --status)

    if [[ "$output" == *"Installation failed"* ]] && \
       [[ "$output" == *"install codex"* ]] && \
       [[ "$output" != *"Installation in progress"* ]]; then
        harness_pass "continue failure status beats loose runtime probes"
    else
        harness_fail "continue failure status beats loose runtime probes" "$output"
    fi

    cleanup_mock_env
}

test_continue_reports_installed_layout_log_locations() {
    setup_installed_layout_env
    mkdir -p "$TEST_INSTALLED_ACFS/logs"
    printf 'install log\n' > "$TEST_INSTALLED_ACFS/logs/install-20260310.log"

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_ACFS/scripts/lib/continue.sh" --status)

    if [[ "$output" == *"$TEST_INSTALLED_ACFS/logs/install-20260310.log"* ]]; then
        harness_pass "continue reports installed-layout log paths"
    else
        harness_fail "continue reports installed-layout log paths" "$output"
    fi

    cleanup_mock_env
}

test_continue_live_log_hint_uses_installed_layout_log_dir() {
    setup_installed_layout_env

    local output=""
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash -c '
            source "'"$TEST_INSTALLED_ACFS"'/scripts/lib/continue.sh"
            get_log_root_hint
        ' 2>&1)

    if [[ "$output" == "$TEST_INSTALLED_ACFS/logs" ]]; then
        harness_pass "continue live-log hint uses installed-layout log dir"
    else
        harness_fail "continue live-log hint uses installed-layout log dir" "$output"
    fi

    cleanup_mock_env
}

test_doctor_dispatches_installed_layout_under_root_home() {
    setup_installed_layout_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" PATH="$TEST_FAKE_BIN:/usr/bin:/bin" \
        bash "$TEST_INSTALLED_ACFS/bin/acfs" version)

    if [[ "$output" == "2.0.0" ]]; then
        harness_pass "installed acfs dispatcher finds VERSION and helper tree under root home"
    else
        harness_fail "installed acfs dispatcher finds VERSION and helper tree under root home" "$output"
    fi

    cleanup_mock_env
}

test_info_zero_lessons_hides_onboard_prompt_and_explains_state() {
    setup_mock_env

    local empty_lessons_dir
    empty_lessons_dir="$(mktemp -d)"
    local progress_file="$empty_lessons_dir/progress.json"

    local terminal_output
    terminal_output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" ACFS_LESSONS_DIR="$empty_lessons_dir" ACFS_PROGRESS_FILE="$progress_file" \
        bash "$REPO_ROOT/scripts/lib/info.sh")

    local html_output
    html_output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" ACFS_LESSONS_DIR="$empty_lessons_dir" ACFS_PROGRESS_FILE="$progress_file" \
        bash "$REPO_ROOT/scripts/lib/info.sh" --html)

    if [[ "$terminal_output" == *"No lessons available"* ]] \
        && [[ "$terminal_output" != *"Run 'onboard' to continue learning"* ]] \
        && [[ "$html_output" == *"No lessons available."* ]] \
        && [[ "$html_output" != *'<div class="progress-fill">0/0</div>'* ]]; then
        harness_pass "info handles zero lessons without misleading onboarding prompts"
    else
        harness_fail "info handles zero lessons without misleading onboarding prompts" "terminal=$terminal_output html=$html_output"
    fi

    cleanup_mock_env
}

test_info_reads_skipped_tools_without_jq() {
    setup_system_state_only_env

    local output
    output=$(HOME="$TEST_ROOT_HOME" ACFS_HOME="$TEST_INSTALLED_ACFS" ACFS_SYSTEM_STATE_FILE="$TEST_SYSTEM_STATE_FILE" \
        TEST_INFO_SCRIPT="$REPO_ROOT/scripts/lib/info.sh" \
        bash -lc '
            command() {
                if [[ "$1" == "-v" && "$2" == "jq" ]]; then
                    return 1
                fi
                builtin command "$@"
            }
            source "$TEST_INFO_SCRIPT"
            info_get_skipped_tools
        ')

    if [[ "$output" == "ntm, bv" ]]; then
        harness_pass "info reads skipped tools without jq from system state"
    else
        harness_fail "info reads skipped tools without jq from system state" "$output"
    fi

    cleanup_mock_env
}

test_onboard_cli_aliases_work_in_zero_lessons_mode() {
    setup_mock_env

    local empty_lessons_dir
    empty_lessons_dir="$(mktemp -d)"
    local progress_file="$empty_lessons_dir/progress.json"

    local help_output=""
    local help_exit=0
    help_output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" ACFS_LESSONS_DIR="$empty_lessons_dir" ACFS_PROGRESS_FILE="$progress_file" \
        bash "$ONBOARD_SH" help 2>&1) || help_exit=$?

    local list_output=""
    local list_exit=0
    list_output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" ACFS_LESSONS_DIR="$empty_lessons_dir" ACFS_PROGRESS_FILE="$progress_file" \
        bash "$ONBOARD_SH" list 2>&1) || list_exit=$?

    local version_output=""
    local version_exit=0
    version_output=$(HOME="$TEST_HOME" ACFS_HOME="$TEST_ACFS" ACFS_LESSONS_DIR="$empty_lessons_dir" ACFS_PROGRESS_FILE="$progress_file" \
        bash "$ONBOARD_SH" version 2>&1) || version_exit=$?

    if [[ "$help_exit" -eq 0 ]] \
        && [[ "$help_output" == *"ACFS Onboarding Tutorial"* ]] \
        && [[ "$list_exit" -eq 0 ]] \
        && [[ "$list_output" == *"No lessons available"* ]] \
        && [[ "$version_exit" -eq 0 ]] \
        && [[ "$version_output" == onboard\ v* ]]; then
        harness_pass "onboard noun-style aliases work in zero-lessons mode"
    else
        harness_fail "onboard noun-style aliases work in zero-lessons mode" "help_exit=$help_exit list_exit=$list_exit version_exit=$version_exit"
    fi

    cleanup_mock_env
}

main() {
    harness_init "ACFS Changelog/Export/Status Tests"

    if ! command -v jq >/dev/null 2>&1; then
        harness_warn "jq not available — skipping JSON validation tests"
    fi

    harness_section "Changelog"
    test_changelog_json_is_valid || true
    test_changelog_defaults_to_last_updated || true
    test_changelog_rejects_invalid_duration || true

    harness_section "Export Config"
    test_export_config_json_is_valid || true
    test_export_config_uses_installed_layout_under_root_home || true
    test_export_config_uses_system_state_when_user_state_missing || true

    harness_section "Status"
    test_status_rejects_unknown_flags || true
    test_status_plain_output_avoids_ansi_when_not_tty || true
    test_status_reports_last_updated_timestamp || true
    test_status_errors_on_malformed_state_json || true
    test_status_uses_installed_layout_under_root_home || true
    test_status_uses_system_state_when_user_state_missing || true

    harness_section "Changelog Root Context"
    test_changelog_uses_installed_layout_under_root_home || true
    test_changelog_uses_system_state_when_user_state_missing || true

    harness_section "Continue"
    test_continue_uses_installed_layout_under_root_home || true
    test_continue_ignores_generic_install_process_matches || true
    test_continue_failed_state_beats_runtime_probe || true
    test_continue_reports_installed_layout_log_locations || true
    test_continue_live_log_hint_uses_installed_layout_log_dir || true

    harness_section "Dashboard"
    test_dashboard_generation_is_atomic_on_failure || true
    test_dashboard_rejects_invalid_ports_before_serving || true
    test_dashboard_prefers_repo_local_info_script || true

    harness_section "Info / Onboard"
    test_info_zero_lessons_hides_onboard_prompt_and_explains_state || true
    test_info_reads_skipped_tools_without_jq || true
    test_onboard_cli_aliases_work_in_zero_lessons_mode || true

    harness_section "Entrypoint Dispatch"
    test_doctor_entrypoint_dispatches_helper_commands || true
    test_doctor_dispatches_installed_layout_under_root_home || true

    harness_summary
}

main "$@"
