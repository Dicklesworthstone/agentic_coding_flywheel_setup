#!/usr/bin/env bash
# ============================================================
# Test: Update Channel Fix (bd-gsjqf)
# Validates that all update paths use update_run_verified_installer
# instead of bare "claude update" (which has no --channel flag and
# silently downgrades from latest to stable channel).
# ============================================================
# Bead: bd-gsjqf.4
# 10 tests per specification:
#   1. Static Analysis — No bare "claude update" in function body
#   2. Static Analysis — update_run_verified_installer is called
#   3. Dry-run behavior
#   4. Function instrumentation (mock)
#   5. Security fallback
#   6. Repo checkout prefers repo checksums over installed cache
#   7. Checksum recovery succeeds after refreshed remote metadata
#   8. uca alias definition
#   9. Completeness sweep
#   10. Channel version (live, optional)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
SKIP=0
LOG_FILE="/tmp/test_update_channel_$(date +%Y%m%d_%H%M%S).log"

# --- Helpers ---
log()     { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*" | tee -a "$LOG_FILE"; }
pass()    { PASS=$((PASS + 1)); log "  PASS: $1"; }
fail()    { FAIL=$((FAIL + 1)); log "  FAIL: $1"; }
skip()    { SKIP=$((SKIP + 1)); log "  SKIP: $1"; }
section() { log ""; log "=== $1 ==="; }

UPDATE_SH="$REPO_ROOT/scripts/lib/update.sh"
ZSHRC="$REPO_ROOT/acfs/zsh/acfs.zshrc"

log "Test: Update Channel Fix (bd-gsjqf)"
log "Log file: $LOG_FILE"
log "Repo root: $REPO_ROOT"

# Ensure required files exist
if [[ ! -f "$UPDATE_SH" ]]; then
    log "FATAL: $UPDATE_SH not found"
    exit 2
fi

# Extract function body once for Tests 1-2
func_body=$(sed -n '/^run_cmd_claude_update()/,/^}/p' "$UPDATE_SH")
if [[ -z "$func_body" ]]; then
    log "FATAL: Could not extract run_cmd_claude_update() from $UPDATE_SH"
    exit 2
fi

# ============================================================
section "Test 1: Static Analysis — No bare 'claude update' in function body"
# ============================================================
# Extract lines that are NOT comments, NOT variable assignments (cmd_display=),
# and NOT log strings, then check for bare "claude update" invocations.
bare_claude_update=$(
    echo "$func_body" \
    | grep -v '^\s*#' \
    | grep -v 'cmd_display=' \
    | grep -v 'log_to_file' \
    | grep -v 'log_item' \
    | grep -v 'echo.*claude update' \
    | grep 'claude update' \
    || true
)
if [[ -z "$bare_claude_update" ]]; then
    pass "No bare 'claude update' invocation in run_cmd_claude_update() body"
else
    fail "Found bare 'claude update' invocation in run_cmd_claude_update(): $bare_claude_update"
fi

# ============================================================
section "Test 2: Static Analysis — update_run_verified_installer is called"
# ============================================================
installer_calls=$(echo "$func_body" | grep -c 'update_run_verified_installer' || true)
if [[ "$installer_calls" -gt 0 ]]; then
    pass "run_cmd_claude_update() calls update_run_verified_installer ($installer_calls occurrences)"
else
    fail "run_cmd_claude_update() does NOT call update_run_verified_installer"
fi

# ============================================================
section "Test 2b: update_target_home resolves passwd homes"
# ============================================================
home_resolution_dir="${TMPDIR:-/tmp}/acfs-home-resolution.$$"
mkdir -p "$home_resolution_dir"
home_resolution_output=$(
    HOME_RESOLUTION_DIR="$home_resolution_dir" \
    bash -c '
        source "'"$UPDATE_SH"'"
        TARGET_HOME=""
        HOME="/tmp/not-the-target-home"

        update_getent_passwd_entry() {
            if [[ "$1" == "dummy" ]]; then
                printf "dummy:x:1000:1000::%s:/bin/bash\n" "$HOME_RESOLUTION_DIR"
                return 0
            fi
            return 1
        }

        update_target_home dummy
    ' 2>&1
) || true

if [[ "$home_resolution_output" == "$home_resolution_dir" ]]; then
    pass "update_target_home prefers passwd-resolved homes over /home fallback"
else
    fail "update_target_home did not use passwd-resolved home: $home_resolution_output"
fi

# ============================================================
section "Test 3: Dry-run behavior"
# ============================================================
# Source update.sh in a subshell. The BASH_SOURCE guard at line ~2444 prevents
# main() from running when sourced. Then call run_cmd_claude_update with
# DRY_RUN=true and verify it returns 0 without executing anything.
dry_run_output=$(
    bash -c '
        source "'"$UPDATE_SH"'"

        # Provide required globals after sourcing update.sh so test settings
        # override the script defaults instead of getting reset by them.
        DRY_RUN=true
        VERBOSE=false
        QUIET=true
        FORCE_MODE=false
        YES_MODE=false
        ABORT_ON_FAILURE=false
        UPDATE_LOG_FILE="/dev/null"
        SUCCESS_COUNT=0
        SKIP_COUNT=0
        FAIL_COUNT=0
        NO_COLOR=1
        RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""
        declare -gA VERSION_BEFORE=()
        declare -gA VERSION_AFTER=()

        run_cmd_claude_update
        echo "DRY_RUN_EXIT=$?"
    ' 2>&1
) || true

if echo "$dry_run_output" | grep -q 'DRY_RUN_EXIT=0'; then
    pass "Dry-run mode returns 0 without executing installer"
else
    fail "Dry-run mode did not return 0. Output: $dry_run_output"
fi

# ============================================================
section "Test 3b: Antigravity dry-run previews locked launchers without mutation"
# ============================================================
agy_dry_run_output=$(
    bash -c '
        temp_home="${TMPDIR:-/tmp}/acfs-agy-dry-run.$$"
        mkdir -p "$temp_home/.bun/bin"
        printf "#!/usr/bin/env bash\nexit 0\n" > "$temp_home/.bun/bin/bun"
        chmod +x "$temp_home/.bun/bin/bun"

        HOME="$temp_home"
        TARGET_HOME="$temp_home"
        source "'"$UPDATE_SH"'"

        DRY_RUN=true
        VERBOSE=false
        QUIET=true
        FORCE_MODE=false
        YES_MODE=false
        ABORT_ON_FAILURE=false
        UPDATE_LOG_FILE="/dev/null"
        UPDATE_AGENTS=true
        UPDATE_RUNTIME=true
        SUCCESS_COUNT=0
        SKIP_COUNT=0
        FAIL_COUNT=0
        NO_COLOR=1
        RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""
        declare -gA VERSION_BEFORE=()
        declare -gA VERSION_AFTER=()

        log_item() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}"; }
        update_binary_exists() { [[ "$1" == "agy" ]]; }
        update_binary_path() {
            case "$1" in
                agy) printf "%s\n" "/usr/bin/agy" ;;
                bun) printf "%s\n" "$HOME/.bun/bin/bun" ;;
                *) return 1 ;;
            esac
        }
        capture_version_before() { return 0; }
        capture_version_after() { return 1; }
        update_run_in_target_context() {
            echo "update_run_in_target_context should not run during dry-run" >&2
            return 99
        }

        update_agents
    ' 2>&1
) || true

if echo "$agy_dry_run_output" | grep -q 'should not run during dry-run'; then
    fail "Antigravity dry-run executed a mutating target command: $agy_dry_run_output"
elif echo "$agy_dry_run_output" | grep -q '^skip|Antigravity CLI|dry-run:' \
    && echo "$agy_dry_run_output" | grep -q '^skip|agy locked launchers|dry-run$'; then
    pass "Antigravity dry-run previews the CLI and locked launchers without mutation"
else
    fail "Antigravity dry-run preview output missing or changed unexpectedly: $agy_dry_run_output"
fi

# ============================================================
section "Test 3c: update dry-run does not create on-disk logs"
# ============================================================
dry_run_logging_output=$(
    bash -c '
        source "'"$UPDATE_SH"'"

        temp_home="${TMPDIR:-/tmp}/acfs-update-dry-run-logging.$$"
        HOME="$temp_home"
        UPDATE_LOG_DIR="$temp_home/.acfs/logs/updates"
        DRY_RUN=true
        UPDATE_LOG_FILE="sentinel"

        init_logging

        printf "LOG_FILE=%s\n" "${UPDATE_LOG_FILE:-}"
        if [[ -d "$UPDATE_LOG_DIR" ]]; then
            echo "DIR_CREATED=yes"
        else
            echo "DIR_CREATED=no"
        fi
    ' 2>&1
) || true

if echo "$dry_run_logging_output" | grep -q '^LOG_FILE=$' && echo "$dry_run_logging_output" | grep -q '^DIR_CREATED=no$'; then
    pass "Dry-run skips creating update log files and directories"
else
    fail "Dry-run logging still created filesystem state: $dry_run_logging_output"
fi

# ============================================================
section "Test 3d: jq bootstrap is skipped in dry-run"
# ============================================================
dry_run_jq_output=$(
    bash -c '
        source "'"$UPDATE_SH"'"

        DRY_RUN=true
        QUIET=true
        YES_MODE=false
        UPDATE_LOG_FILE="/dev/null"
        NO_COLOR=1
        YELLOW="" NC=""

        cmd_exists() {
            return 1
        }

        apt-get() {
            echo "apt-get should not run in dry-run" >&2
            return 99
        }

        sudo() {
            echo "sudo should not run in dry-run" >&2
            return 99
        }

        update_ensure_jq_available
        echo "JQ_EXIT=$?"
    ' 2>&1
) || true

if echo "$dry_run_jq_output" | grep -q '^JQ_EXIT=0$' && ! echo "$dry_run_jq_output" | grep -q 'should not run'; then
    pass "Dry-run skips jq installation attempts entirely"
else
    fail "Dry-run still attempted jq installation: $dry_run_jq_output"
fi

# ============================================================
section "Test 3e: legacy cleanup stays non-destructive in dry-run"
# ============================================================
dry_run_cleanup_output=$(
    bash -c '
        temp_home="${TMPDIR:-/tmp}/acfs-update-dry-run-cleanup.$$"
        mkdir -p "$temp_home/.claude/hooks"
        printf "legacy\n" > "$temp_home/.claude/hooks/git_safety_guard.sh"

        HOME="$temp_home"
        TARGET_HOME="$temp_home"
        source "'"$UPDATE_SH"'"

        DRY_RUN=true
        QUIET=true
        UPDATE_LOG_FILE="/dev/null"
        NO_COLOR=1
        RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""

        log_item() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}"; }

        cleanup_legacy_git_safety_guard

        if [[ -f "$HOME/.claude/hooks/git_safety_guard.sh" ]]; then
            echo "FILE_STILL_EXISTS=yes"
        else
            echo "FILE_STILL_EXISTS=no"
        fi
    ' 2>&1
) || true

if echo "$dry_run_cleanup_output" | grep -q '^skip|legacy cleanup|dry-run: would remove git_safety_guard artifacts$' \
    && echo "$dry_run_cleanup_output" | grep -q '^FILE_STILL_EXISTS=yes$'; then
    pass "Dry-run legacy cleanup reports intent without deleting files"
else
    fail "Dry-run legacy cleanup still mutated files or lost its preview message: $dry_run_cleanup_output"
fi

# ============================================================
section "Test 3f: ACFS self-update dry-run avoids git fetch mutations"
# ============================================================
dry_run_self_update_output=$(
    bash -c '
        source "'"$UPDATE_SH"'"

        temp_root="${TMPDIR:-/tmp}/acfs-update-dry-run-self.$$"
        mkdir -p "$temp_root/.git"

        ACFS_REPO_ROOT="$temp_root"
        DRY_RUN=true
        QUIET=true
        UPDATE_SELF=true
        ACFS_SELF_UPDATE_DONE=false
        UPDATE_LOG_FILE="/dev/null"
        ACFS_VERSION_DISPLAY="vtest"
        NO_COLOR=1
        RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""

        log_item() { printf "%s|%s|%s\n" "$1" "$2" "$3"; }

        git() {
            if [[ "$*" == *"fetch origin main"* ]]; then
                echo "FETCH_CALLED=yes"
                return 99
            fi

            case "$*" in
                *"remote get-url origin"*)
                    printf "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup.git\n"
                    return 0
                    ;;
                *"branch --show-current"*)
                    printf "main\n"
                    return 0
                    ;;
                *"rev-parse HEAD"*)
                    printf "1111111111111111111111111111111111111111\n"
                    return 0
                    ;;
                *"ls-remote --heads origin main"*)
                    printf "2222222222222222222222222222222222222222\trefs/heads/main\n"
                    return 0
                    ;;
                *)
                    printf "unexpected git call: %s\n" "$*" >&2
                    return 98
                    ;;
            esac
        }

        update_acfs_self
    ' 2>&1
) || true

if ! echo "$dry_run_self_update_output" | grep -q '^FETCH_CALLED=yes$' \
    && echo "$dry_run_self_update_output" | grep -q '^ok|ACFS|would update (remote main differs)$'; then
    pass "ACFS self-update dry-run uses a non-mutating remote probe instead of git fetch"
else
    fail "ACFS self-update dry-run still triggered git fetch or lost its preview output: $dry_run_self_update_output"
fi

# ============================================================
section "Test 3f2: ACFS self-update re-exec marker does not count as skipped work"
# ============================================================
self_update_done_output=$(
    bash -c '
        source "'"$UPDATE_SH"'"

        QUIET=true
        UPDATE_SELF=true
        ACFS_SELF_UPDATE_DONE=true
        UPDATE_LOG_FILE="/dev/null"
        SUCCESS_COUNT=0
        SKIP_COUNT=0
        FAIL_COUNT=0
        NO_COLOR=1
        RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""

        update_acfs_self
        printf "SUCCESS_COUNT=%s\n" "$SUCCESS_COUNT"
        printf "SKIP_COUNT=%s\n" "$SKIP_COUNT"
        printf "FAIL_COUNT=%s\n" "$FAIL_COUNT"
    ' 2>&1
) || true

if echo "$self_update_done_output" | grep -q '^SUCCESS_COUNT=0$' \
    && echo "$self_update_done_output" | grep -q '^SKIP_COUNT=0$' \
    && echo "$self_update_done_output" | grep -q '^FAIL_COUNT=0$'; then
    pass "ACFS self-update re-exec marker stays out of summary counters"
else
    fail "ACFS self-update re-exec marker polluted summary counters: $self_update_done_output"
fi

# ============================================================
section "Test 3g: ACFS self-update preserves upstream-looking dirty checkout"
# ============================================================
self_update_repair_output=$(
    bash -c '
        set -euo pipefail
        source "'"$UPDATE_SH"'"

        temp_root="${TMPDIR:-/tmp}/acfs-update-dirty-repair.$$"
        seed_repo="$temp_root/seed"
        origin_repo="$temp_root/origin.git"
        work_repo="$temp_root/work"

        mkdir -p "$seed_repo/scripts/lib" "$seed_repo/scripts/generated"
        git -C "$seed_repo" init -b main >/dev/null
        git -C "$seed_repo" config user.email test@example.invalid
        git -C "$seed_repo" config user.name "ACFS Test"
        printf "base-update\n" > "$seed_repo/scripts/lib/update.sh"
        printf "base-generated\n" > "$seed_repo/scripts/generated/install_all.sh"
        git -C "$seed_repo" add .
        git -C "$seed_repo" commit -m base >/dev/null
        git clone --bare "$seed_repo" "$origin_repo" >/dev/null 2>&1
        git clone "$origin_repo" "$work_repo" >/dev/null 2>&1

        git -C "$seed_repo" remote add origin "$origin_repo"
        printf "intermediate-update\n" > "$seed_repo/scripts/lib/update.sh"
        printf "intermediate-generated\n" > "$seed_repo/scripts/generated/install_all.sh"
        git -C "$seed_repo" add .
        git -C "$seed_repo" commit -m intermediate >/dev/null
        intermediate_commit="$(git -C "$seed_repo" rev-parse HEAD)"
        git -C "$seed_repo" push origin main >/dev/null 2>&1

        printf "final-update\n" > "$seed_repo/scripts/lib/update.sh"
        printf "final-generated\n" > "$seed_repo/scripts/generated/install_all.sh"
        git -C "$seed_repo" add .
        git -C "$seed_repo" commit -m final >/dev/null
        git -C "$seed_repo" push origin main >/dev/null 2>&1

        git -C "$work_repo" fetch origin main >/dev/null 2>&1
        git -C "$work_repo" show "$intermediate_commit:scripts/lib/update.sh" > "$work_repo/scripts/lib/update.sh"
        git -C "$work_repo" show "$intermediate_commit:scripts/generated/install_all.sh" > "$work_repo/scripts/generated/install_all.sh"

        ACFS_REPO_ROOT="$work_repo"
        ACFS_HOME="$work_repo"
        DRY_RUN=false
        QUIET=true
        UPDATE_SELF=true
        ACFS_SELF_UPDATE_DONE=false
        UPDATE_LOG_FILE="/dev/null"
        ACFS_VERSION_DISPLAY="vtest"
        NO_COLOR=1
        RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""

        log_item() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}"; }
        is_expected_acfs_origin_url() { return 0; }
        sync_acfs_global_wrapper() { return 0; }
        update_runtime_acfs_home() { printf "%s\n" "$work_repo"; }

        update_acfs_self
        printf "HEAD=%s\n" "$(git -C "$work_repo" rev-parse HEAD)"
        printf "REMOTE=%s\n" "$(git -C "$work_repo" rev-parse origin/main)"
        if [[ -z "$(git -C "$work_repo" status --porcelain --untracked-files=no)" ]]; then
            printf "STATUS_CLEAN=yes\n"
        else
            printf "STATUS_CLEAN=no\n"
            git -C "$work_repo" status --porcelain --untracked-files=no
        fi
    ' 2>&1
) || true

if echo "$self_update_repair_output" | grep -q '^warn|ACFS self-update|BLOCKED:' \
    && echo "$self_update_repair_output" | grep -q '^STATUS_CLEAN=no$' \
    && [[ "$(echo "$self_update_repair_output" | sed -n 's/^HEAD=//p' | tail -1)" != "$(echo "$self_update_repair_output" | sed -n 's/^REMOTE=//p' | tail -1)" ]] \
    && echo "$self_update_repair_output" | grep -q '^ M scripts/generated/install_all.sh$' \
    && echo "$self_update_repair_output" | grep -q '^ M scripts/lib/update.sh$'; then
    pass "ACFS self-update preserves dirty tracked files even when their bytes match upstream history"
else
    fail "ACFS self-update modified or misreported an upstream-looking dirty checkout: $self_update_repair_output"
fi

# ============================================================
section "Test 3h: deployed sync skips git-tracked files in ACFS home"
# ============================================================
sync_git_tracked_output=$(
    bash -c '
        set -euo pipefail
        source "'"$UPDATE_SH"'"

        temp_root="${TMPDIR:-/tmp}/acfs-sync-git-managed.$$"
        source_repo="$temp_root/source"
        deployed_repo="$temp_root/deployed"

        mkdir -p "$source_repo/scripts/lib" "$deployed_repo/scripts/lib"
        printf "source-update\n" > "$source_repo/scripts/lib/update.sh"
        printf "deployed-update\n" > "$deployed_repo/scripts/lib/update.sh"
        git -C "$deployed_repo" init -b main >/dev/null
        git -C "$deployed_repo" config user.email test@example.invalid
        git -C "$deployed_repo" config user.name "ACFS Test"
        git -C "$deployed_repo" add scripts/lib/update.sh
        git -C "$deployed_repo" commit -m deployed >/dev/null

        ACFS_REPO_ROOT="$source_repo"
        ACFS_HOME="$deployed_repo"
        DRY_RUN=false
        UPDATE_LOG_FILE="/dev/null"
        update_runtime_acfs_home() { printf "%s\n" "$ACFS_HOME"; }
        log_to_file() { :; }

        sync_acfs_deployed
        printf "DEPLOYED_CONTENT=%s\n" "$(cat "$deployed_repo/scripts/lib/update.sh")"
        if [[ -z "$(git -C "$deployed_repo" status --porcelain --untracked-files=no)" ]]; then
            printf "STATUS_CLEAN=yes\n"
        else
            printf "STATUS_CLEAN=no\n"
            git -C "$deployed_repo" status --porcelain --untracked-files=no
        fi
    ' 2>&1
) || true

if echo "$sync_git_tracked_output" | grep -q '^DEPLOYED_CONTENT=deployed-update$' \
    && echo "$sync_git_tracked_output" | grep -q '^STATUS_CLEAN=yes$'; then
    pass "sync_acfs_deployed leaves git-tracked ACFS home files untouched"
else
    fail "sync_acfs_deployed still dirtied a git-managed ACFS home: $sync_git_tracked_output"
fi

# ============================================================
section "Test 3i: cargo git source installs ignore inherited CARGO_TARGET_DIR"
# ============================================================
cargo_target_dir_output=$(
    bash -c '
        set -euo pipefail
        source "'"$UPDATE_SH"'"

        temp_root="${TMPDIR:-/tmp}/acfs-cargo-target-dir.$$"
        source_repo="$temp_root/source"
        fake_bin="$temp_root/bin"
        temp_home="$temp_root/home"
        inherited_target="$temp_root/inherited-target"

        mkdir -p "$source_repo" "$fake_bin" "$temp_home" "$inherited_target"
        git -C "$source_repo" init -b main >/dev/null
        git -C "$source_repo" config user.email test@example.invalid
        git -C "$source_repo" config user.name "ACFS Test"
        printf "[package]\nname = \"demo_tool\"\nversion = \"0.1.0\"\nedition = \"2021\"\n" > "$source_repo/Cargo.toml"
        git -C "$source_repo" add Cargo.toml
        git -C "$source_repo" commit -m base >/dev/null

        cat > "$fake_bin/cargo" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
set -euo pipefail
target_dir=""
prev=""
for arg in "$@"; do
    if [[ "$prev" == "--target-dir" ]]; then
        target_dir="$arg"
        break
    fi
    prev="$arg"
done
if [[ -z "$target_dir" ]]; then
    echo "MISSING_TARGET_DIR=yes"
    exit 42
fi
mkdir -p "$target_dir/release"
printf "%s\n" "#!/usr/bin/env bash" "printf \"%s\\n\" demo-tool" > "$target_dir/release/demo_tool"
chmod +x "$target_dir/release/demo_tool"
printf "CARGO_TARGET_DIR_ENV=%s\n" "${CARGO_TARGET_DIR:-}"
printf "CARGO_ARGS=%s\n" "$*"
printf "BUILD_OUTPUT=%s\n" "$target_dir"
EOF
        chmod +x "$fake_bin/cargo"

        HOME="$temp_home"
        TARGET_HOME="$temp_home"
        CARGO_TARGET_DIR="$inherited_target"
        PATH="$fake_bin:$PATH"
        UPDATE_LOG_FILE="/dev/null"

        update_run_cargo_git_source_install "$source_repo" demo_tool
        "$temp_home/.cargo/bin/demo_tool"
    ' 2>&1
) || true

if echo "$cargo_target_dir_output" | grep -q '^CARGO_TARGET_DIR_ENV=.*/inherited-target$' \
    && echo "$cargo_target_dir_output" | grep -q '^CARGO_ARGS=build --release --target-dir .*/target$' \
    && echo "$cargo_target_dir_output" | grep -q '^demo-tool$' \
    && ! echo "$cargo_target_dir_output" | grep -q '^BUILD_OUTPUT=.*/inherited-target'; then
    pass "cargo git source helper installs from its own target dir despite inherited CARGO_TARGET_DIR"
else
    fail "cargo git source helper still depends on inherited or default target dir: $cargo_target_dir_output"
fi

# ============================================================
section "Test 3j: source-build version capture is set -e safe"
# ============================================================
source_build_capture_hits=$(
    sed -n '/# ASCII Art Diagram Corrector/,/# Agent Settings Backup/p' "$UPDATE_SH" \
        | grep -E '^[[:space:]]*capture_version_after "(aadc|rust_proxy)"' \
        || true
)
if [[ -z "$source_build_capture_hits" ]]; then
    pass "source-build update branches guard capture_version_after non-change returns"
else
    fail "source-build update branches still call capture_version_after bare: $source_build_capture_hits"
fi

# ============================================================
section "Test 4: Function instrumentation (mock)"
# ============================================================
# Source update.sh, override update_run_verified_installer with a mock,
# call run_cmd_claude_update, verify the mock was called with "claude latest".
# NOTE: The non-verbose code path runs update_run_verified_installer inside
# a $() subshell, so shell variable changes are lost. We use a temp file
# as a signal instead, and run in VERBOSE mode so the mock runs in-process.
MOCK_SIGNAL="/tmp/test_update_channel_mock_$$"
rm -f "$MOCK_SIGNAL"
mock_output=$(
    bash -c '
        source "'"$UPDATE_SH"'"

        DRY_RUN=false
        VERBOSE=true
        QUIET=false
        FORCE_MODE=false
        YES_MODE=false
        ABORT_ON_FAILURE=false
        UPDATE_LOG_FILE=""
        SUCCESS_COUNT=0
        SKIP_COUNT=0
        FAIL_COUNT=0
        NO_COLOR=1
        RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""
        declare -gA VERSION_BEFORE=()
        declare -gA VERSION_AFTER=()

        # Override with mock — write args to a temp file signal
        update_run_verified_installer() {
            echo "$*" > "'"$MOCK_SIGNAL"'"
            return 0
        }

        run_cmd_claude_update 2>&1
    ' 2>&1
) || true

if [[ -f "$MOCK_SIGNAL" ]]; then
    mock_args=$(cat "$MOCK_SIGNAL")
    rm -f "$MOCK_SIGNAL"
    if [[ "$mock_args" == "claude latest" ]]; then
        pass "Mock update_run_verified_installer called with 'claude latest'"
    else
        fail "Mock called but with wrong args: '$mock_args'"
    fi
else
    fail "Mock update_run_verified_installer was NOT called. Output: $mock_output"
fi

# ============================================================
section "Test 5: Security fallback"
# ============================================================
# Source update.sh, mock update_require_security to fail,
# verify update_run_verified_installer returns non-zero with a warning.
security_output=$(
    bash -c '
        source "'"$UPDATE_SH"'"

        DRY_RUN=false
        VERBOSE=false
        QUIET=true
        FORCE_MODE=false
        YES_MODE=false
        ABORT_ON_FAILURE=false
        UPDATE_LOG_FILE="/dev/null"
        SUCCESS_COUNT=0
        SKIP_COUNT=0
        FAIL_COUNT=0
        NO_COLOR=1
        RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""
        declare -gA VERSION_BEFORE=()
        declare -gA VERSION_AFTER=()

        # Override security check to always fail
        update_require_security() { return 1; }

        # Call the verified installer directly — it should fail gracefully
        update_run_verified_installer claude latest 2>&1 || echo "SECURITY_EXIT=$?"
    ' 2>&1
) || true

if echo "$security_output" | grep -q 'SECURITY_EXIT='; then
    if echo "$security_output" | grep -qiE 'security|unavailable|missing'; then
        pass "Security fallback produces warning and non-zero exit when security unavailable"
    else
        pass "Security fallback returns non-zero when update_require_security fails"
    fi
else
    fail "update_run_verified_installer did not fail when security was unavailable. Output: $security_output"
fi

# ============================================================
section "Test 5b: meta_skill ARM64 Linux source fallback"
# ============================================================
for ms_arm64_arch in aarch64 arm64; do
    MS_ARM64_SIGNAL="/tmp/test_update_channel_ms_arm64_${ms_arm64_arch}_$$"
    rm -f "$MS_ARM64_SIGNAL"
    ms_arm64_output=$(
        bash -c '
            source "'"$UPDATE_SH"'"

            DRY_RUN=false
            VERBOSE=false
            QUIET=true
            FORCE_MODE=false
            YES_MODE=false
            ABORT_ON_FAILURE=false
            UPDATE_LOG_FILE="/dev/null"
            SUCCESS_COUNT=0
            SKIP_COUNT=0
            FAIL_COUNT=0
            NO_COLOR=1
            RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""
            declare -gA VERSION_BEFORE=()
            declare -gA VERSION_AFTER=()

            uname() {
                case "${1:-}" in
                    -s) printf "Linux\n" ;;
                    -m) printf "'"$ms_arm64_arch"'\n" ;;
                    *) command uname "$@" ;;
                esac
            }

            cargo() {
                echo "$*" > "'"$MS_ARM64_SIGNAL"'"
                return 0
            }

            update_binary_path() {
                if [[ "$1" == "cargo" ]]; then
                    printf "cargo\n"
                    return 0
                fi
                return 1
            }

            update_run_in_target_context() {
                shift
                "$@"
            }

            update_run_verified_installer ms --easy-mode
        ' 2>&1
    ) || true

    if [[ -f "$MS_ARM64_SIGNAL" ]]; then
        ms_arm64_args=$(cat "$MS_ARM64_SIGNAL")
        rm -f "$MS_ARM64_SIGNAL"
        if [[ "$ms_arm64_args" == *"--git https://github.com/Dicklesworthstone/meta_skill --force"* ]]; then
            pass "meta_skill ARM64 Linux update path falls back to cargo source install ($ms_arm64_arch)"
        else
            fail "meta_skill ARM64 Linux fallback used wrong cargo args for $ms_arm64_arch: $ms_arm64_args"
        fi
    else
        fail "meta_skill ARM64 Linux fallback did not invoke cargo for $ms_arm64_arch. Output: $ms_arm64_output"
    fi
done

# ============================================================
section "Test 6: Repo checkout prefers repo checksums over installed cache"
# ============================================================
current_mcp_agent_mail_sha=$(awk '
    $1 == "mcp_agent_mail:" { in_block=1; next }
    in_block && $1 == "sha256:" { gsub(/"/, "", $2); print $2; exit }
' "$REPO_ROOT/checksums.yaml")

repo_checksum_preference_output=$(
    bash -c '
        set -euo pipefail
        export HOME
        HOME="$(mktemp -d)"
        mkdir -p "$HOME/.acfs"
        cp "'"$REPO_ROOT"'/checksums.yaml" "$HOME/.acfs/checksums.yaml"
        python3 - <<'"'"'PY'"'"' "$HOME/.acfs/checksums.yaml"
import sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    content = fh.read()
content = content.replace(
    "'"$current_mcp_agent_mail_sha"'",
    "1111111111111111111111111111111111111111111111111111111111111111",
    1,
)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(content)
PY

        source "'"$UPDATE_SH"'"
        QUIET=true
        CHECKSUMS_URL="https://127.0.0.1:9/nowhere"
        update_require_security >/dev/null
        printf "CHECKSUM=%s\n" "$(get_checksum mcp_agent_mail)"
    ' 2>&1
) || true

if echo "$repo_checksum_preference_output" | grep -q "CHECKSUM=$current_mcp_agent_mail_sha"; then
    pass "Repo-local update.sh ignores stale ~/.acfs/checksums.yaml and loads repo checksums"
else
    fail "Repo-local update.sh still preferred stale installed checksums. Output: $repo_checksum_preference_output"
fi

# ============================================================
section "Test 6b: RCH update keeps daemon and fleet setup active"
# ============================================================
if grep -Eq 'run_cmd "RCH" update_run_verified_installer rch --easy-mode([[:space:]]|$)' "$UPDATE_SH"; then
    pass "RCH stack update invokes installer with --easy-mode"
else
    fail "RCH stack update still invokes bare installer without --easy-mode"
fi

rch_manifest_block=$(awk '
    /^[[:space:]]*- id: stack\.rch$/ { in_block=1 }
    in_block { print }
    in_block && /^[[:space:]]*verify:/ { exit }
' "$REPO_ROOT/acfs.manifest.yaml")

if echo "$rch_manifest_block" | grep -Fq 'args: ["--easy-mode"]'; then
    pass "RCH manifest verified installer records --easy-mode"
else
    fail "RCH manifest verified installer is missing --easy-mode"
fi

# ============================================================
section "Test 7: Verified installer recovers from stale checksum metadata"
# ============================================================
checksum_recovery_output=$(
    bash -c '
        set -euo pipefail

        tmpdir="$(mktemp -d)"
        fake_installer_payload=$'"'"'#!/usr/bin/env bash\necho RECOVERED_INSTALLER\n'"'"'
        fake_installer_sha="$(printf "%s" "$fake_installer_payload" | sha256sum | awk "{print \$1}")"

        cat > "$tmpdir/checksums.yaml" <<EOF
installers:
  mcp_agent_mail:
    url: "https://example.invalid/stale-install.sh"
    sha256: "1111111111111111111111111111111111111111111111111111111111111111"
EOF

        source "'"$UPDATE_SH"'"

        DRY_RUN=false
        VERBOSE=false
        QUIET=true
        FORCE_MODE=false
        YES_MODE=false
        ABORT_ON_FAILURE=false
        UPDATE_LOG_FILE="/dev/null"
        SUCCESS_COUNT=0
        SKIP_COUNT=0
        FAIL_COUNT=0
        NO_COLOR=1
        RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" NC=""
        declare -gA VERSION_BEFORE=()
        declare -gA VERSION_AFTER=()

        export CHECKSUMS_FILE="$tmpdir/checksums.yaml"
        source "'"$REPO_ROOT"'/scripts/lib/security.sh"
        load_checksums "$tmpdir/checksums.yaml"

        update_require_security() { return 0; }
        update_run_in_target_context() {
            local _env_assignment="$1"
            shift
            "$@"
        }

        acfs_download_to_file() {
            local url="$1"
            local output_path="$2"
            case "$url" in
                https://example.invalid/stale-install.sh|https://example.invalid/fresh-install.sh)
                    printf "%s" "$fake_installer_payload" > "$output_path"
                    ;;
                *)
                    return 1
                    ;;
            esac
        }

        acfs_fetch_fresh_checksums_to_file() {
            cat > "$1" <<EOF
installers:
  mcp_agent_mail:
    url: "https://example.invalid/fresh-install.sh"
    sha256: "$fake_installer_sha"
EOF
        }

        update_run_verified_installer mcp_agent_mail
    ' 2>&1
) || true

if echo "$checksum_recovery_output" | grep -q 'RECOVERED_INSTALLER'; then
    pass "update_run_verified_installer recovers after refreshed checksum metadata"
else
    fail "Verified installer did not recover from stale checksum metadata. Output: $checksum_recovery_output"
fi

# ============================================================
section "Test 8: security globals initialize under set -u"
# ============================================================
security_globals_output=$(
    bash -c '
        set -u
        source "'"$REPO_ROOT"'/scripts/lib/security.sh"
        printf "checksums=%s\n" "${#LOADED_CHECKSUMS[@]}"
    ' 2>&1
) || true

if echo "$security_globals_output" | grep -q '^checksums=0$'; then
    pass "security.sh initializes LOADED_CHECKSUMS safely under set -u"
else
    fail "security.sh still leaves LOADED_CHECKSUMS uninitialized under set -u. Output: $security_globals_output"
fi

# ============================================================
section "Test 9: uca alias definition"
# ============================================================
if [[ -f "$ZSHRC" ]]; then
    uca_line=$(grep "alias uca=" "$ZSHRC" || true)
    if [[ -z "$uca_line" ]]; then
        fail "uca alias not found in acfs.zshrc"
    else
        # Check 1: no bare "claude update" in the alias
        if echo "$uca_line" | grep -q 'claude update'; then
            fail "uca alias contains bare 'claude update': $uca_line"
        else
            # Check 2: uses install.sh with latest (the verified approach)
            if echo "$uca_line" | grep -q 'install.sh.*latest'; then
                pass "uca alias uses install.sh with latest channel (no bare 'claude update')"
            else
                pass "uca alias does not contain bare 'claude update'"
            fi
        fi

        # Check 3: codex and agy are preserved in the alias chain
        has_codex=false
        has_agy=false
        echo "$uca_line" | grep -q 'codex' && has_codex=true
        echo "$uca_line" | grep -q 'agy' && has_agy=true
        if $has_codex && $has_agy; then
            pass "uca alias preserves codex and agy components"
        else
            fail "uca alias missing components: codex=$has_codex agy=$has_agy"
        fi
    fi
else
    skip "acfs.zshrc not found at $ZSHRC"
fi

# ============================================================
section "Test 10: Completeness sweep — no bare 'claude update' in repo"
# ============================================================
# Grep across the whole repo for "claude update", excluding:
# - comments (lines starting with #)
# - this test file itself
# - .beads/ directories
# - node_modules/target/.git
# - known-safe patterns (update_run_verified_installer, install.sh, cmd_display=, FIX(bd-gsjqf)
# - lines with INTENTIONAL marker
sweep_hits=$(
    grep -rn "claude update" "$REPO_ROOT" \
        --include='*.sh' --include='*.zsh' --include='*.zshrc' --include='*.bashrc' \
        --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='.beads' \
        --exclude-dir='target' \
        2>/dev/null \
    | grep -v 'update_run_verified_installer' \
    | grep -v 'install\.sh.*latest' \
    | grep -v '^\s*#' \
    | grep -v 'test_update_channel' \
    | grep -v 'cmd_display=' \
    | grep -v 'FIX(bd-gsjqf' \
    | grep -v 'INTENTIONAL' \
    | grep -v 'PLAN_TO_CREATE' \
    || true
)
if [[ -z "$sweep_hits" ]]; then
    pass "No unprotected bare 'claude update' found in shell files"
else
    log "  Bare hits found:"
    echo "$sweep_hits" | while IFS= read -r line; do log "    $line"; done
    fail "Found bare 'claude update' in shell files (see above)"
fi

# ============================================================
section "Test 11: Channel version alignment (live, optional)"
# ============================================================
if command -v npm &>/dev/null && command -v claude &>/dev/null; then
    dist_tags=$(npm view @anthropic-ai/claude-code dist-tags 2>/dev/null || true)
    installed=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
    latest=$(echo "$dist_tags" | sed -n "s/.*latest: '\([^']*\)'.*/\1/p" || true)
    stable=$(echo "$dist_tags" | sed -n "s/.*stable: '\([^']*\)'.*/\1/p" || true)
    log "  Installed: ${installed:-unknown}"
    log "  Latest:    ${latest:-unknown}"
    log "  Stable:    ${stable:-unknown}"
    if [[ -z "$installed" ]] || [[ -z "$latest" ]]; then
        skip "Could not determine version info for live channel check"
    elif [[ "$installed" == "$latest" ]]; then
        pass "Installed claude version matches latest channel ($installed)"
    elif [[ "$installed" == "$stable" ]]; then
        fail "Installed claude version matches STABLE channel ($installed) — possible downgrade!"
    else
        skip "Version $installed matches neither latest ($latest) nor stable ($stable)"
    fi
else
    skip "npm or claude not available — skipping live channel check"
fi

# ============================================================
section "Summary"
# ============================================================
log ""
log "Results: $PASS passed, $FAIL failed, $SKIP skipped"
log "Log: $LOG_FILE"

if [[ "$FAIL" -gt 0 ]]; then
    log "RESULT: FAIL"
    exit 1
else
    log "RESULT: PASS"
    exit 0
fi
