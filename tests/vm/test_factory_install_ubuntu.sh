#!/usr/bin/env bash
# ============================================================
# ACFS Factory Ubuntu Installer E2E
#
# Authoritative system-level check for the beginner path on a real
# systemd-capable Ubuntu host:
#
#   root@fresh-ubuntu:~# curl .../install.sh | bash -s -- --yes --mode vibe
#
# This is intentionally not a Docker test. It expects SSH access to a freshly
# provisioned host and verifies user creation, SSH key merge, systemd user
# services, tool availability, warning-free doctor health, and idempotency.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SSH_TARGET="${ACFS_FACTORY_SSH_TARGET:-}"
SSH_KEY="${ACFS_FACTORY_SSH_KEY:-}"
SSH_PORT="${ACFS_FACTORY_SSH_PORT:-}"
REF="${ACFS_REF:-main}"
MODE="${ACFS_FACTORY_MODE:-vibe}"
EXPECT_UBUNTU_VERSION="${ACFS_FACTORY_EXPECT_UBUNTU_VERSION:-25.10}"
EXPECT_FINAL_UBUNTU_VERSION="${ACFS_FACTORY_EXPECT_FINAL_UBUNTU_VERSION:-25.10}"
EXPECT_NO_UBUNTU="${ACFS_FACTORY_EXPECT_NO_UBUNTU:-true}"
INSTALL_TIMEOUT_SECONDS="${ACFS_FACTORY_INSTALL_TIMEOUT_SECONDS:-14400}"
POST_REBOOT_TIMEOUT_SECONDS="${ACFS_FACTORY_POST_REBOOT_TIMEOUT_SECONDS:-14400}"
ALLOW_INSTALL_REBOOT="${ACFS_FACTORY_ALLOW_INSTALL_REBOOT:-false}"
PUBLIC_KEY_FILE="${ACFS_FACTORY_PUBLIC_KEY_FILE:-}"
INSTALL_URL="${ACFS_FACTORY_INSTALL_URL:-}"
ARTIFACTS_DIR="${ACFS_FACTORY_ARTIFACTS_DIR:-}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

usage() {
    cat <<'EOF'
tests/vm/test_factory_install_ubuntu.sh - authoritative ACFS factory-host E2E

Usage:
  tests/vm/test_factory_install_ubuntu.sh --ssh-target root@HOST [options]

Required:
  --ssh-target <target>       Fresh Ubuntu host reachable by SSH, usually root@IP.

Options:
  --ssh-key <path>            Private key for SSH/scp.
  --ssh-port <port>           SSH port.
  --ref <ref>                 ACFS ref to install (default: ACFS_REF or main).
  --mode <mode>               Install mode: vibe or safe (default: vibe).
  --expect-ubuntu <version>   Required initial VERSION_ID from /etc/os-release (default: 25.10).
  --expect-final-ubuntu <ver> Required final VERSION_ID after install/resume (default: 25.10).
  --allow-existing-ubuntu     Do not fail if the ubuntu user exists before install.
  --allow-install-reboot      Treat SSH disconnects during install as expected and reconnect.
  --public-key-file <path>    Public key to seed into root authorized_keys before install.
  --install-timeout <seconds> Timeout per installer run (default: 14400).
  --post-reboot-timeout <sec> Timeout for reboot/resume follow-up (default: 14400).
  --install-url <url>         Override install.sh URL. Defaults to GitHub raw URL for --ref.
  --artifacts-dir <path>      Local artifact directory.
  --help                      Show this help.

Environment equivalents:
  ACFS_FACTORY_SSH_TARGET
  ACFS_FACTORY_SSH_KEY
  ACFS_FACTORY_SSH_PORT
  ACFS_FACTORY_MODE
  ACFS_FACTORY_EXPECT_UBUNTU_VERSION
  ACFS_FACTORY_EXPECT_FINAL_UBUNTU_VERSION
  ACFS_FACTORY_EXPECT_NO_UBUNTU
  ACFS_FACTORY_ALLOW_INSTALL_REBOOT
  ACFS_FACTORY_PUBLIC_KEY_FILE
  ACFS_FACTORY_INSTALL_TIMEOUT_SECONDS
  ACFS_FACTORY_POST_REBOOT_TIMEOUT_SECONDS
  ACFS_FACTORY_INSTALL_URL
  ACFS_FACTORY_ARTIFACTS_DIR

Notes:
  - This test is meant for a disposable, freshly provisioned VM/VPS.
  - By default it fails if the ubuntu user already exists before install.
  - It does not clean up the remote host; preserve it for failure forensics or
    destroy it using your provider tooling after reviewing artifacts.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-target)
            SSH_TARGET="${2:-}"
            shift 2
            ;;
        --ssh-key)
            SSH_KEY="${2:-}"
            shift 2
            ;;
        --ssh-port)
            SSH_PORT="${2:-}"
            shift 2
            ;;
        --ref)
            REF="${2:-}"
            shift 2
            ;;
        --mode)
            MODE="${2:-}"
            shift 2
            ;;
        --expect-ubuntu)
            EXPECT_UBUNTU_VERSION="${2:-}"
            shift 2
            ;;
        --expect-final-ubuntu)
            EXPECT_FINAL_UBUNTU_VERSION="${2:-}"
            shift 2
            ;;
        --allow-existing-ubuntu)
            EXPECT_NO_UBUNTU=false
            shift
            ;;
        --allow-install-reboot)
            ALLOW_INSTALL_REBOOT=true
            shift
            ;;
        --public-key-file)
            PUBLIC_KEY_FILE="${2:-}"
            shift 2
            ;;
        --install-timeout)
            INSTALL_TIMEOUT_SECONDS="${2:-}"
            shift 2
            ;;
        --post-reboot-timeout)
            POST_REBOOT_TIMEOUT_SECONDS="${2:-}"
            shift 2
            ;;
        --install-url)
            INSTALL_URL="${2:-}"
            shift 2
            ;;
        --artifacts-dir)
            ARTIFACTS_DIR="${2:-}"
            shift 2
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

if [[ -z "$SSH_TARGET" ]]; then
    echo "ERROR: --ssh-target is required (for example: root@203.0.113.10)" >&2
    exit 1
fi

case "$MODE" in
    vibe|safe) ;;
    *)
        echo "ERROR: --mode must be vibe or safe (got: $MODE)" >&2
        exit 1
        ;;
esac

if [[ -z "$REF" ]]; then
    echo "ERROR: --ref cannot be empty" >&2
    exit 1
fi

if [[ ! "$INSTALL_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || [[ "$INSTALL_TIMEOUT_SECONDS" -lt 60 ]]; then
    echo "ERROR: --install-timeout must be an integer >= 60" >&2
    exit 1
fi

if [[ ! "$POST_REBOOT_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || [[ "$POST_REBOOT_TIMEOUT_SECONDS" -lt 60 ]]; then
    echo "ERROR: --post-reboot-timeout must be an integer >= 60" >&2
    exit 1
fi

if [[ -n "$PUBLIC_KEY_FILE" && ! -r "$PUBLIC_KEY_FILE" ]]; then
    echo "ERROR: --public-key-file is not readable: $PUBLIC_KEY_FILE" >&2
    exit 1
fi

if [[ -z "$INSTALL_URL" ]]; then
    INSTALL_URL="https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/${REF}/install.sh?acfs_factory_e2e=${TIMESTAMP}"
fi

if [[ -z "$ARTIFACTS_DIR" ]]; then
    ARTIFACTS_DIR="$REPO_ROOT/tests/artifacts/factory-install-${TIMESTAMP}"
fi
mkdir -p "$ARTIFACTS_DIR"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $1" >&2
        exit 1
    fi
}

require_cmd ssh
require_cmd scp
require_cmd date
require_cmd mkdir
require_cmd base64

ssh_args=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20)
scp_args=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20)
known_hosts_file="$ARTIFACTS_DIR/known_hosts"
touch "$known_hosts_file"
ssh_args+=(-o "UserKnownHostsFile=$known_hosts_file")
scp_args+=(-o "UserKnownHostsFile=$known_hosts_file")
if [[ -n "$SSH_KEY" ]]; then
    ssh_args+=(-i "$SSH_KEY")
    scp_args+=(-i "$SSH_KEY")
fi
if [[ -n "$SSH_PORT" ]]; then
    ssh_args+=(-p "$SSH_PORT")
    scp_args+=(-P "$SSH_PORT")
fi

public_key_b64=""
if [[ -n "$PUBLIC_KEY_FILE" ]]; then
    if base64 --help 2>&1 | grep -q -- '-w'; then
        public_key_b64="$(base64 -w0 "$PUBLIC_KEY_FILE")"
    else
        public_key_b64="$(base64 "$PUBLIC_KEY_FILE" | tr -d '\n')"
    fi
fi

remote_dir="/var/log/acfs/factory-e2e-${TIMESTAMP}"
remote_runner="${remote_dir}/remote-runner.sh"
local_runner="${ARTIFACTS_DIR}/remote-runner.sh"

echo "[factory-e2e] Target: $SSH_TARGET" >&2
echo "[factory-e2e] Ref: $REF" >&2
echo "[factory-e2e] Mode: $MODE" >&2
echo "[factory-e2e] Expected initial Ubuntu: $EXPECT_UBUNTU_VERSION" >&2
echo "[factory-e2e] Expected final Ubuntu: $EXPECT_FINAL_UBUNTU_VERSION" >&2
echo "[factory-e2e] Allow install reboot: $ALLOW_INSTALL_REBOOT" >&2
echo "[factory-e2e] Artifacts: $ARTIFACTS_DIR" >&2

# shellcheck disable=SC2029  # remote_dir is intentionally generated locally.
ssh "${ssh_args[@]}" "$SSH_TARGET" "mkdir -p '$remote_dir' && chmod 700 '$remote_dir'"

cat > "$local_runner" <<'REMOTE_RUNNER'
#!/usr/bin/env bash
set -euo pipefail

: "${ACFS_FACTORY_REMOTE_DIR:?}"
: "${ACFS_FACTORY_INSTALL_URL:?}"
: "${ACFS_FACTORY_REF:?}"
: "${ACFS_FACTORY_MODE:?}"
: "${ACFS_FACTORY_EXPECT_UBUNTU_VERSION:?}"
: "${ACFS_FACTORY_EXPECT_FINAL_UBUNTU_VERSION:?}"
: "${ACFS_FACTORY_EXPECT_NO_UBUNTU:?}"
: "${ACFS_FACTORY_INSTALL_TIMEOUT_SECONDS:?}"
: "${ACFS_FACTORY_POST_REBOOT_TIMEOUT_SECONDS:?}"
: "${ACFS_FACTORY_RUN_MODE:?}"

REMOTE_LOG="${ACFS_FACTORY_REMOTE_DIR}/factory-e2e.log"
REMOTE_JSONL="${ACFS_FACTORY_REMOTE_DIR}/factory-e2e.jsonl"
INSTALL_LOG="${ACFS_FACTORY_REMOTE_DIR}/install.log"
IDEMPOTENCY_LOG="${ACFS_FACTORY_REMOTE_DIR}/idempotency.log"

mkdir -p "$ACFS_FACTORY_REMOTE_DIR"
exec > >(tee -a "$REMOTE_LOG") 2>&1

json_escape() {
    local value="${1-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    printf '%s' "$value"
}

log_event() {
    local phase="$1"
    local status="$2"
    local message="${3-}"
    printf '{"ts":"%s","phase":"%s","status":"%s","message":"%s"}\n' \
        "$(date -Iseconds)" \
        "$(json_escape "$phase")" \
        "$(json_escape "$status")" \
        "$(json_escape "$message")" >> "$REMOTE_JSONL"
    printf '[%s] %s: %s\n' "$status" "$phase" "$message"
}

fail() {
    log_event "$1" "fail" "${2-}"
    exit 1
}

pass() {
    log_event "$1" "ok" "${2-}"
}

FACTORY_REDACTED_ARTIFACT_DIR=""

run_step() {
    local phase="$1"
    shift
    log_event "$phase" "start" "$*"
    if "$@"; then
        pass "$phase" "$*"
    else
        local rc=$?
        fail "$phase" "exit $rc: $*"
    fi
}

run_target_step() {
    local phase="$1"
    local script="$2"
    local target_home=""
    local target_path=""

    target_home="$(getent passwd ubuntu | cut -d: -f6)"
    [[ -n "$target_home" ]] || fail "$phase" "unable to resolve ubuntu home"
    target_path="$target_home/.local/bin:$target_home/.acfs/bin:$target_home/.cargo/bin:$target_home/.bun/bin:$target_home/.atuin/bin:$target_home/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

    log_event "$phase" "start" "$script"
    if sudo -n -u ubuntu env ACFS_DOCTOR_CI=true HOME="$target_home" PATH="$target_path" bash -lc "$script"; then
        pass "$phase" "$script"
    else
        local rc=$?
        fail "$phase" "exit $rc: $script"
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "preflight.command.$1" "missing command"
    pass "preflight.command.$1" "found"
}

append_public_key_to_root() {
    local key_b64="${ACFS_FACTORY_PUBLIC_KEY_B64:-}"
    local public_key=""
    local last_char=""

    [[ -n "$key_b64" ]] || return 0
    require_command base64
    public_key="$(printf '%s' "$key_b64" | base64 -d)"
    [[ -n "$public_key" ]] || fail "preflight.public_key" "decoded public key is empty"

    mkdir -p /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/authorized_keys

    if grep -Fxq "$public_key" /root/.ssh/authorized_keys 2>/dev/null; then
        pass "preflight.public_key" "root authorized_keys already contains seeded key"
        return 0
    fi

    if [[ -s /root/.ssh/authorized_keys ]]; then
        last_char="$(tail -c 1 /root/.ssh/authorized_keys | od -An -t u1 | tr -d ' ' 2>/dev/null || true)"
        if [[ "$last_char" != "10" ]]; then
            printf '\n' >> /root/.ssh/authorized_keys
        fi
    fi
    printf '%s\n' "$public_key" >> /root/.ssh/authorized_keys
    pass "preflight.public_key" "seeded root authorized_keys"
}

run_install_once() {
    local phase="$1"
    local log_file="$2"
    local rc=0

    log_event "$phase" "start" "curl public installer"
    set +e
    timeout "$ACFS_FACTORY_INSTALL_TIMEOUT_SECONDS" bash -s -- \
        "$ACFS_FACTORY_INSTALL_URL" \
        "$ACFS_FACTORY_MODE" \
        "$ACFS_FACTORY_REF" > "$log_file" 2>&1 <<'INSTALL_SCRIPT'
set -euo pipefail
install_url="$1"
mode="$2"
ref="$3"
curl -fsSL "$install_url" | bash -s -- --yes --mode "$mode" --ref "$ref"
INSTALL_SCRIPT
    rc=$?
    set -e

    if [[ "$rc" -ne 0 ]]; then
        tail -n 80 "$log_file" || true
        fail "$phase" "installer exited $rc; see $log_file"
    fi

    pass "$phase" "installer completed"
}

assert_ubuntu_version() {
    local phase="$1"
    local expected="$2"

    if [[ ! -r /etc/os-release ]]; then
        fail "${phase}.os_release" "/etc/os-release is missing"
    fi

    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || fail "${phase}.os" "expected ubuntu, got ${ID:-unknown}"
    if [[ "$expected" != "any" ]]; then
        [[ "${VERSION_ID:-}" == "$expected" ]] || \
            fail "${phase}.os_version" "expected ${expected}, got ${VERSION_ID:-unknown}"
    fi
    pass "${phase}.os" "Ubuntu ${VERSION_ID:-unknown}"
}

assert_systemd_host() {
    local init_name=""
    require_command systemctl
    init_name="$(ps -p 1 -o comm= 2>/dev/null | awk '{print $1}')"
    [[ "$init_name" == "systemd" ]] || fail "preflight.systemd" "PID 1 is ${init_name:-unknown}, not systemd"
    systemctl --version >/dev/null
    pass "preflight.systemd" "systemd is PID 1"
}

assert_fresh_user_state() {
    if id ubuntu >/dev/null 2>&1; then
        if [[ "$ACFS_FACTORY_EXPECT_NO_UBUNTU" == "true" ]]; then
            fail "preflight.fresh_user" "ubuntu user already exists before install"
        fi
        pass "preflight.fresh_user" "ubuntu user pre-exists and was allowed"
    else
        pass "preflight.fresh_user" "ubuntu user does not exist before install"
    fi
}

assert_target_user() {
    local home=""
    local uid=""
    id ubuntu >/dev/null 2>&1 || fail "post.user" "ubuntu user was not created"
    home="$(getent passwd ubuntu | cut -d: -f6)"
    [[ "$home" == "/home/ubuntu" ]] || fail "post.user_home" "expected /home/ubuntu, got ${home:-empty}"
    [[ -d /home/ubuntu ]] || fail "post.home_dir" "/home/ubuntu missing"
    uid="$(id -u ubuntu)"
    [[ -d "/run/user/$uid" ]] || fail "post.runtime_dir" "/run/user/$uid missing"
    pass "post.user" "ubuntu user, home, and runtime dir exist"
}

assert_ssh_key_merge() {
    local key_b64="${ACFS_FACTORY_PUBLIC_KEY_B64:-}"
    local public_key=""
    local count=""
    local last_char=""

    [[ -n "$key_b64" ]] || {
        pass "post.ssh_keys" "no seeded public key requested"
        return 0
    }

    public_key="$(printf '%s' "$key_b64" | base64 -d)"
    [[ -f /home/ubuntu/.ssh/authorized_keys ]] || fail "post.ssh_keys" "authorized_keys missing"
    grep -Fxq "$public_key" /home/ubuntu/.ssh/authorized_keys || fail "post.ssh_keys" "seeded key missing from ubuntu authorized_keys"
    count="$(grep -Fxc "$public_key" /home/ubuntu/.ssh/authorized_keys || true)"
    [[ "$count" == "1" ]] || fail "post.ssh_keys" "seeded key count expected 1, got $count"
    last_char="$(tail -c 1 /home/ubuntu/.ssh/authorized_keys | od -An -t u1 | tr -d ' ' 2>/dev/null || true)"
    [[ "$last_char" == "10" ]] || fail "post.ssh_keys" "authorized_keys does not end with newline"
    pass "post.ssh_keys" "seeded key merged exactly once with trailing newline"
}

assert_agent_mail_systemd() {
    run_target_step "post.agent_mail_health" 'curl -fsS --max-time 10 http://127.0.0.1:8765/health/liveness >/dev/null'
    run_target_step "post.agent_mail_systemd" '
uid="$(id -u)"
runtime_dir="/run/user/$uid"
export XDG_RUNTIME_DIR="$runtime_dir"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
systemctl --user show-environment >/dev/null
systemctl --user is-active --quiet agent-mail.service
'
}

assert_acfs_surface() {
    require_command sudo
    if [[ "$ACFS_FACTORY_MODE" == "vibe" ]]; then
        run_target_step "post.sudo_nopasswd" 'sudo -n true'
    else
        pass "post.sudo_nopasswd" "safe mode does not require passwordless sudo"
    fi
    run_target_step "post.path_core" 'for cmd in acfs acfs-update onboard; do command -v "$cmd" >/dev/null; done'
    run_target_step "post.shell_startup" 'zsh -ic "command -v acfs >/dev/null && command -v onboard >/dev/null"'
    run_target_step "post.doctor" '
doctor_json="$(acfs doctor --json)"
printf "%s\n" "$doctor_json" | jq -e ".summary.fail == 0 and .summary.warn == 0" >/dev/null || {
    printf "%s\n" "$doctor_json"
    exit 1
}
'
    run_target_step "post.stack_bins" 'for cmd in am ntm dcg ru cass cm caam slb ubs bv br; do command -v "$cmd" >/dev/null; done'
    run_target_step "post.dcg_guard" 'dcg test "git reset --hard" 2>&1 | grep -Eqi "deny|block"'
    assert_agent_mail_systemd
    run_target_step "post.nightly_timer" '
uid="$(id -u)"
runtime_dir="/run/user/$uid"
export XDG_RUNTIME_DIR="$runtime_dir"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
systemctl --user is-enabled acfs-nightly-update.timer >/dev/null
'
}

redact_factory_artifacts() {
    local support_lib="/home/ubuntu/.acfs/scripts/lib/support.sh"
    local stage="${ACFS_FACTORY_REMOTE_DIR}/redacted-artifacts-$(date +%s)"
    local file=""

    [[ -r "$support_lib" ]] || fail "artifacts.redaction" "support redaction library missing: $support_lib"

    mkdir -p \
        "$stage/factory" \
        "$stage/var-log-acfs" \
        "$stage/home-ubuntu-acfs-logs"

    for file in "$REMOTE_LOG" "$REMOTE_JSONL" "$INSTALL_LOG" "$IDEMPOTENCY_LOG"; do
        [[ -f "$file" ]] || continue
        cp -f "$file" "$stage/factory/"
    done
    if [[ -d /var/log/acfs ]]; then
        cp -a /var/log/acfs/. "$stage/var-log-acfs/" 2>/dev/null || true
    fi
    if [[ -d /home/ubuntu/.acfs/logs ]]; then
        cp -a /home/ubuntu/.acfs/logs/. "$stage/home-ubuntu-acfs-logs/" 2>/dev/null || true
    fi

    # shellcheck source=/dev/null
    source "$support_lib"
    REDACT=true
    REDACTION_COUNT=0
    VERBOSE=false
    redact_bundle "$stage"

    FACTORY_REDACTED_ARTIFACT_DIR="$stage"
    pass "artifacts.redaction" "redacted diagnostic artifact copy"
}

collect_artifacts() {
    local archive="${ACFS_FACTORY_REMOTE_DIR}/factory-e2e-artifacts.tar.gz"

    redact_factory_artifacts
    [[ -n "$FACTORY_REDACTED_ARTIFACT_DIR" ]] || fail "artifacts.archive" "redacted artifact directory was not created"
    tar -czf "$archive" -C "$FACTORY_REDACTED_ARTIFACT_DIR" . 2>/dev/null || \
        fail "artifacts.archive" "failed to archive redacted diagnostics"
    pass "artifacts.remote_archive" "$archive"
}

wait_for_post_install_ready() {
    local deadline=$((SECONDS + ACFS_FACTORY_POST_REBOOT_TIMEOUT_SECONDS))
    local target_path="/home/ubuntu/.local/bin:/home/ubuntu/.acfs/bin:/home/ubuntu/.cargo/bin:/home/ubuntu/.bun/bin:/home/ubuntu/.atuin/bin:/home/ubuntu/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

    while [[ "$SECONDS" -lt "$deadline" ]]; do
        if id ubuntu >/dev/null 2>&1 \
            && [[ -f /home/ubuntu/.acfs/VERSION ]] \
            && sudo -n -u ubuntu env ACFS_DOCTOR_CI=true HOME=/home/ubuntu PATH="$target_path" bash -lc 'command -v acfs >/dev/null' >/dev/null 2>&1; then
            pass "post.wait_ready" "ACFS files and ubuntu user are present"
            return 0
        fi
        log_event "post.wait_ready" "wait" "installation/resume still in progress"
        sleep 30
    done

    fail "post.wait_ready" "timed out waiting for ACFS install/resume to finish"
}

post_install_assertions() {
    wait_for_post_install_ready
    assert_ubuntu_version "post.final" "$ACFS_FACTORY_EXPECT_FINAL_UBUNTU_VERSION"
    assert_target_user
    assert_ssh_key_merge
    assert_acfs_surface

    run_install_once "install.idempotency_run" "$IDEMPOTENCY_LOG"
    assert_ubuntu_version "post.idempotency_final" "$ACFS_FACTORY_EXPECT_FINAL_UBUNTU_VERSION"
    assert_target_user
    assert_ssh_key_merge
    assert_acfs_surface
}

main() {
    log_event "start" "ok" "factory E2E starting"
    require_command awk
    require_command cp
    require_command curl
    require_command cut
    require_command find
    require_command getent
    require_command grep
    require_command id
    require_command md5sum
    require_command od
    require_command ps
    require_command sed
    require_command tail
    require_command tar
    require_command timeout
    require_command tr

    if [[ "$ACFS_FACTORY_RUN_MODE" == "post-only" ]]; then
        post_install_assertions
        collect_artifacts
        pass "complete" "factory E2E post-install assertions passed"
        return 0
    fi

    assert_ubuntu_version "preflight.initial" "$ACFS_FACTORY_EXPECT_UBUNTU_VERSION"
    assert_systemd_host
    assert_fresh_user_state
    append_public_key_to_root

    run_install_once "install.first_run" "$INSTALL_LOG"
    post_install_assertions

    collect_artifacts
    pass "complete" "factory E2E passed"
}

main "$@"
REMOTE_RUNNER

chmod 700 "$local_runner"
scp "${scp_args[@]}" "$local_runner" "$SSH_TARGET:$remote_runner"

run_remote_runner() {
    local run_mode="$1"
    local remote_command_string=""
    local -a remote_command=(
        env
        "ACFS_FACTORY_REMOTE_DIR=$remote_dir"
        "ACFS_FACTORY_INSTALL_URL=$INSTALL_URL"
        "ACFS_FACTORY_REF=$REF"
        "ACFS_FACTORY_MODE=$MODE"
        "ACFS_FACTORY_EXPECT_UBUNTU_VERSION=$EXPECT_UBUNTU_VERSION"
        "ACFS_FACTORY_EXPECT_FINAL_UBUNTU_VERSION=$EXPECT_FINAL_UBUNTU_VERSION"
        "ACFS_FACTORY_EXPECT_NO_UBUNTU=$EXPECT_NO_UBUNTU"
        "ACFS_FACTORY_INSTALL_TIMEOUT_SECONDS=$INSTALL_TIMEOUT_SECONDS"
        "ACFS_FACTORY_POST_REBOOT_TIMEOUT_SECONDS=$POST_REBOOT_TIMEOUT_SECONDS"
        "ACFS_FACTORY_PUBLIC_KEY_B64=$public_key_b64"
        "ACFS_FACTORY_RUN_MODE=$run_mode"
        bash
        "$remote_runner"
    )

    printf -v remote_command_string '%q ' "${remote_command[@]}"
    # shellcheck disable=SC2029  # remote_command_string is a locally assembled argv.
    ssh "${ssh_args[@]}" "$SSH_TARGET" "$remote_command_string"
}

wait_for_ssh_ready() {
    local deadline=$((SECONDS + POST_REBOOT_TIMEOUT_SECONDS))

    while [[ "$SECONDS" -lt "$deadline" ]]; do
        if ssh "${ssh_args[@]}" "$SSH_TARGET" true >/dev/null 2>&1; then
            echo "[factory-e2e] SSH is reachable again" >&2
            return 0
        fi
        echo "[factory-e2e] Waiting for SSH after install/reboot..." >&2
        sleep 20
    done

    return 1
}

redact_local_factory_artifacts() {
    local support_lib="$REPO_ROOT/scripts/lib/support.sh"

    if [[ ! -r "$support_lib" ]]; then
        echo "ERROR: support redaction library missing: $support_lib" >&2
        return 1
    fi

    (
        # shellcheck source=../../scripts/lib/support.sh
        source "$support_lib"
        REDACT=true
        REDACTION_COUNT=0
        VERBOSE=false
        redact_bundle "$ARTIFACTS_DIR"
    )
}

collect_remote_artifacts() {
    echo "[factory-e2e] Collecting remote artifacts from $remote_dir" >&2
    scp "${scp_args[@]}" "$SSH_TARGET:$remote_dir/factory-e2e.log" "$ARTIFACTS_DIR/" 2>/dev/null || true
    scp "${scp_args[@]}" "$SSH_TARGET:$remote_dir/factory-e2e.jsonl" "$ARTIFACTS_DIR/" 2>/dev/null || true
    scp "${scp_args[@]}" "$SSH_TARGET:$remote_dir/install.log" "$ARTIFACTS_DIR/" 2>/dev/null || true
    scp "${scp_args[@]}" "$SSH_TARGET:$remote_dir/idempotency.log" "$ARTIFACTS_DIR/" 2>/dev/null || true
    scp "${scp_args[@]}" "$SSH_TARGET:$remote_dir/factory-e2e-artifacts.tar.gz" "$ARTIFACTS_DIR/" 2>/dev/null || true
    redact_local_factory_artifacts
}

remote_status=0
set +e
run_remote_runner "full"
remote_status=$?
set -e

if [[ "$remote_status" -ne 0 && "$ALLOW_INSTALL_REBOOT" == "true" ]]; then
    echo "[factory-e2e] Initial SSH run exited $remote_status; treating as possible installer reboot." >&2
    if wait_for_ssh_ready; then
        post_deadline=$((SECONDS + POST_REBOOT_TIMEOUT_SECONDS))
        while [[ "$SECONDS" -lt "$post_deadline" ]]; do
            set +e
            run_remote_runner "post-only"
            remote_status=$?
            set -e
            [[ "$remote_status" -eq 0 ]] && break
            echo "[factory-e2e] Post-reboot assertions exited $remote_status; waiting before retry..." >&2
            sleep 30
            wait_for_ssh_ready || break
        done
    fi
fi

collect_remote_artifacts

if [[ "$remote_status" -ne 0 ]]; then
    echo "ERROR: factory E2E failed with exit code $remote_status. Artifacts: $ARTIFACTS_DIR" >&2
    exit "$remote_status"
fi

echo "[factory-e2e] PASS: factory Ubuntu installer E2E passed. Artifacts: $ARTIFACTS_DIR" >&2
