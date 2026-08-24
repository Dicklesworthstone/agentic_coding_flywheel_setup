#!/usr/bin/env bash
# ============================================================
# ACFS Fresh-Root Bootstrap Regression Test
#
# This is a focused production-regression test for the real beginner path:
#   root@fresh-ubuntu:~# curl .../install.sh | bash -s -- --yes --mode vibe
#
# It proves that a container with no ubuntu user can run the installer from
# stdin, that ACFS creates a missing target user automatically, that --yes mode
# cannot stop to ask for an SSH public key, and that pre-existing
# authorized_keys files with no trailing newline are merged safely.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

UBUNTU_VERSION="24.04"
INSIDE_CONTAINER=false

usage() {
    cat <<'EOF'
tests/vm/test_fresh_root_bootstrap_regression.sh

Usage:
  tests/vm/test_fresh_root_bootstrap_regression.sh [options]

Options:
  --ubuntu <version>     Ubuntu image tag for the self-wrapping Docker run.
  --inside-container     Run checks directly in the current container.
  --help                 Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ubuntu)
            UBUNTU_VERSION="${2:-}"
            shift 2
            ;;
        --inside-container)
            INSIDE_CONTAINER=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "$INSIDE_CONTAINER" != "true" ]]; then
    if [[ -z "$UBUNTU_VERSION" ]]; then
        echo "ERROR: --ubuntu requires a version (e.g. 24.04)" >&2
        exit 1
    fi
    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: docker not found. Install Docker or run with --inside-container inside Ubuntu." >&2
        exit 1
    fi

    docker pull "ubuntu:${UBUNTU_VERSION}" >/dev/null
    docker run --rm -t \
        -e DEBIAN_FRONTEND=noninteractive \
        -v "${REPO_ROOT}:/repo:rw" \
        "ubuntu:${UBUNTU_VERSION}" \
        bash /repo/tests/vm/test_fresh_root_bootstrap_regression.sh --inside-container
    exit $?
fi

PASS=0
FAIL=0
LOG_DIR="/tmp/acfs-fresh-root-bootstrap-regression.$$"
LOCAL_BOOTSTRAP_ARCHIVE=""
mkdir -p "$LOG_DIR"

log() {
    echo "[fresh-root-e2e] $*" >&2
}

pass() {
    echo "  PASS: $*"
    PASS=$((PASS + 1))
}

fail() {
    echo "  FAIL: $*" >&2
    FAIL=$((FAIL + 1))
}

require_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    fi
    echo "ERROR: required command not found: $1" >&2
    exit 1
}

create_bootstrap_archive() {
    local archive_path="$1"
    local stage_dir=""

    stage_dir="$(mktemp -d "$LOG_DIR/archive-stage.XXXXXX")"
    mkdir -p "$stage_dir/acfs-local/scripts" "$stage_dir/acfs-local/packages"

    cp -R /repo/scripts/lib "$stage_dir/acfs-local/scripts/"
    cp -R /repo/scripts/generated "$stage_dir/acfs-local/scripts/"
    cp /repo/scripts/preflight.sh "$stage_dir/acfs-local/scripts/preflight.sh"
    cp /repo/scripts/acfs-global "$stage_dir/acfs-local/scripts/acfs-global"
    cp /repo/scripts/acfs-update "$stage_dir/acfs-local/scripts/acfs-update"
    cp -R /repo/packages/onboard "$stage_dir/acfs-local/packages/onboard"
    cp -R /repo/acfs "$stage_dir/acfs-local/acfs"
    cp /repo/checksums.yaml "$stage_dir/acfs-local/checksums.yaml"
    cp /repo/acfs.manifest.yaml "$stage_dir/acfs-local/acfs.manifest.yaml"
    cp /repo/VERSION "$stage_dir/acfs-local/VERSION"

    tar -czf "$archive_path" -C "$stage_dir" acfs-local
}

assert_user_home() {
    local user="$1"
    local expected_home="$2"
    local actual_home=""

    actual_home="$(getent passwd "$user" | cut -d: -f6 || true)"
    if [[ "$actual_home" == "$expected_home" ]]; then
        pass "$user passwd home is $expected_home"
    else
        fail "$user passwd home expected $expected_home, got ${actual_home:-<empty>}"
    fi
}

assert_file_contains() {
    local path="$1"
    local needle="$2"
    local desc="$3"

    if grep -Fq "$needle" "$path" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

assert_file_not_contains() {
    local path="$1"
    local needle="$2"
    local desc="$3"

    if grep -Fq "$needle" "$path" 2>/dev/null; then
        fail "$desc"
    else
        pass "$desc"
    fi
}

assert_key_count() {
    local path="$1"
    local key_line="$2"
    local expected="$3"
    local desc="$4"
    local actual="0"

    actual="$(grep -Fxc "$key_line" "$path" 2>/dev/null || true)"
    if [[ "$actual" == "$expected" ]]; then
        pass "$desc"
    else
        fail "$desc (expected $expected, got $actual)"
    fi
}

run_stdin_install() {
    local target_user="$1"
    local log_file="$2"
    local status=0

    set +e
    # shellcheck disable=SC2016  # $1 expands inside the child bash -c.
    timeout 240s bash -c '
        set -euo pipefail
        cat /repo/install.sh | env \
            ACFS_TEST_MODE=1 \
            ACFS_TEST_ARCHIVE=/should-be-ignored \
            ACFS_GENERATED_MIGRATED_CATEGORIES=filesystem,cli,network,tools,lang,agents,db,cloud,stack,acfs \
            TARGET_USER="$1" \
            bash -s -- --bootstrap-archive "$2" --yes --skip-preflight --skip-ubuntu-upgrade --mode vibe --only users.ubuntu --no-deps
    ' _ "$target_user" "$LOCAL_BOOTSTRAP_ARCHIVE" > "$log_file" 2>&1
    status=$?
    set -e

    return "$status"
}

log "Installing bootstrap prerequisites"
apt-get update -qq
apt-get install -y -qq sudo curl git ca-certificates jq unzip tar xz-utils gnupg >/dev/null

require_cmd bash
require_cmd cat
require_cmd cut
require_cmd getent
require_cmd grep
require_cmd id
require_cmd mktemp
require_cmd runuser
require_cmd sudo
require_cmd tar
require_cmd timeout

cd /repo

LOCAL_BOOTSTRAP_ARCHIVE="$LOG_DIR/acfs-local-bootstrap.tar.gz"
log "Creating local bootstrap archive from current checkout"
create_bootstrap_archive "$LOCAL_BOOTSTRAP_ARCHIVE"
if [[ -f "$LOCAL_BOOTSTRAP_ARCHIVE" ]]; then
    pass "local bootstrap archive created"
else
    fail "local bootstrap archive was not created"
fi

FRESH_TARGET_USER="acfsfresh"
FRESH_TARGET_HOME="/home/$FRESH_TARGET_USER"

log "Verifying missing target-user starting point"
if id ubuntu >/dev/null 2>&1; then
    pass "base image may pre-create ubuntu; missing-user regression uses $FRESH_TARGET_USER"
else
    pass "base image starts without ubuntu user"
fi
if id "$FRESH_TARGET_USER" >/dev/null 2>&1; then
    fail "$FRESH_TARGET_USER should not pre-exist in the fresh container"
else
    pass "fresh container starts without $FRESH_TARGET_USER user"
fi

FIRST_LOG="$LOG_DIR/fresh-root-$FRESH_TARGET_USER.log"
log "Running stdin installer for missing $FRESH_TARGET_USER user"
if run_stdin_install "$FRESH_TARGET_USER" "$FIRST_LOG"; then
    pass "stdin installer exits successfully for missing target user"
else
    fail "stdin installer failed for missing target user; see $FIRST_LOG"
fi

if id "$FRESH_TARGET_USER" >/dev/null 2>&1; then
    pass "installer created $FRESH_TARGET_USER user"
else
    fail "installer did not create $FRESH_TARGET_USER user"
fi
assert_user_home "$FRESH_TARGET_USER" "$FRESH_TARGET_HOME"

if [[ -d "$FRESH_TARGET_HOME/.acfs" ]]; then
    pass "installer created $FRESH_TARGET_HOME/.acfs"
else
    fail "installer did not create $FRESH_TARGET_HOME/.acfs"
fi

if runuser -u "$FRESH_TARGET_USER" -- sudo -n true >/dev/null 2>&1; then
    pass "vibe mode grants passwordless sudo to $FRESH_TARGET_USER"
else
    fail "$FRESH_TARGET_USER cannot use passwordless sudo after vibe install"
fi

assert_file_not_contains "$FIRST_LOG" "Unable to resolve TARGET_HOME" "fresh-root log has no TARGET_HOME resolution failure"
assert_file_not_contains "$FIRST_LOG" "SSH Key Setup" "--yes mode did not render SSH key setup UI"
assert_file_not_contains "$FIRST_LOG" "Paste your public key" "--yes mode did not prompt for a public key"
assert_file_contains "$FIRST_LOG" "Using explicitly selected local archive" "fresh-root run used the local checkout archive"
assert_file_contains "$FIRST_LOG" "Target user: $FRESH_TARGET_USER" "fresh-root log records target user"
assert_file_contains "$FIRST_LOG" "Target home: $FRESH_TARGET_HOME" "fresh-root log records target home"

SECOND_LOG="$LOG_DIR/fresh-root-$FRESH_TARGET_USER-rerun.log"
log "Re-running stdin installer to prove idempotency"
if run_stdin_install "$FRESH_TARGET_USER" "$SECOND_LOG"; then
    pass "stdin installer rerun exits successfully"
else
    fail "stdin installer rerun failed; see $SECOND_LOG"
fi
assert_file_not_contains "$SECOND_LOG" "Unable to resolve TARGET_HOME" "rerun log has no TARGET_HOME resolution failure"
assert_file_not_contains "$SECOND_LOG" "Paste your public key" "rerun did not prompt for a public key"
assert_file_contains "$SECOND_LOG" "Using explicitly selected local archive" "rerun used the local checkout archive"

KEY_TARGET_USER="acfskeytest"
KEY_TARGET_HOME="/home/$KEY_TARGET_USER"
EXISTING_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExistingTargetKey acfs-existing"
NEW_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMigrationRegressionKey acfs-e2e"

log "Preparing pre-existing target authorized_keys without a trailing newline"
if ! id "$KEY_TARGET_USER" >/dev/null 2>&1; then
    useradd -m -d "$KEY_TARGET_HOME" -s /bin/bash "$KEY_TARGET_USER"
fi
mkdir -p "$KEY_TARGET_HOME/.ssh"
printf '%s' "$EXISTING_KEY" > "$KEY_TARGET_HOME/.ssh/authorized_keys"
chown -R "$KEY_TARGET_USER:$KEY_TARGET_USER" "$KEY_TARGET_HOME/.ssh"
chmod 700 "$KEY_TARGET_HOME/.ssh"
chmod 600 "$KEY_TARGET_HOME/.ssh/authorized_keys"

log "Adding root authorized_keys entries for merge and de-dupe coverage"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
printf '%s\n%s\n' "$EXISTING_KEY" "$NEW_KEY" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

KEY_LOG="$LOG_DIR/fresh-root-key-migration.log"
log "Running stdin installer for pre-existing key-migration user"
if run_stdin_install "$KEY_TARGET_USER" "$KEY_LOG"; then
    pass "stdin installer exits successfully for key-migration user"
else
    fail "stdin installer failed for key-migration user; see $KEY_LOG"
fi

if id "$KEY_TARGET_USER" >/dev/null 2>&1; then
    pass "$KEY_TARGET_USER user exists after key-migration run"
else
    fail "$KEY_TARGET_USER user is missing after key-migration run"
fi
assert_user_home "$KEY_TARGET_USER" "$KEY_TARGET_HOME"

assert_key_count "$KEY_TARGET_HOME/.ssh/authorized_keys" "$EXISTING_KEY" "1" "existing target key was not duplicated"
assert_key_count "$KEY_TARGET_HOME/.ssh/authorized_keys" "$NEW_KEY" "1" "new root key was appended exactly once"
assert_file_not_contains "$KEY_LOG" "SSH Key Setup" "key-migration run did not render SSH key setup UI"
assert_file_not_contains "$KEY_LOG" "Paste your public key" "key-migration run did not prompt for a public key"
assert_file_not_contains "$KEY_LOG" "local: can only be used in a function" "key-migration run avoided top-level local regression"
assert_file_contains "$KEY_LOG" "Using explicitly selected local archive" "key-migration run used the local checkout archive"

echo ""
echo "---"
echo "Results: $PASS passed, $FAIL failed"
echo "Logs: $LOG_DIR"

if [[ "$FAIL" -gt 0 ]]; then
    echo ""
    echo "FAIL: fresh-root bootstrap regression test failed."
    for log_file in "$LOG_DIR"/*.log; do
        [[ -f "$log_file" ]] || continue
        echo ""
        echo "==> $log_file"
        tail -n 60 "$log_file" || true
    done
    exit 1
fi

echo "PASS: fresh-root bootstrap regression test passed."
