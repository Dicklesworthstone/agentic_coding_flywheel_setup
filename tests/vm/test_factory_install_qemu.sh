#!/usr/bin/env bash
# ============================================================
# ACFS Factory Ubuntu Installer E2E (QEMU/KVM)
#
# Boots an official Ubuntu cloud image in QEMU/KVM, waits for root SSH, then
# delegates to test_factory_install_ubuntu.sh. This is the local VM equivalent
# of a disposable VPS release gate: real kernel, systemd PID 1, sshd, cloud-init,
# user services, and reboot-capable semantics.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

UBUNTU_VERSION="${ACFS_QEMU_UBUNTU_VERSION:-25.10}"
MODE="${ACFS_QEMU_MODE:-vibe}"
REF="${ACFS_REF:-main}"
EXPECT_FINAL_UBUNTU_VERSION="${ACFS_QEMU_EXPECT_FINAL_UBUNTU_VERSION:-$UBUNTU_VERSION}"
INSTALL_TIMEOUT_SECONDS="${ACFS_QEMU_INSTALL_TIMEOUT_SECONDS:-14400}"
POST_REBOOT_TIMEOUT_SECONDS="${ACFS_QEMU_POST_REBOOT_TIMEOUT_SECONDS:-14400}"
BOOT_TIMEOUT_SECONDS="${ACFS_QEMU_BOOT_TIMEOUT_SECONDS:-900}"
MEMORY_MB="${ACFS_QEMU_MEMORY_MB:-8192}"
CPUS="${ACFS_QEMU_CPUS:-4}"
DISK_SIZE="${ACFS_QEMU_DISK_SIZE:-80G}"
SSH_PORT="${ACFS_QEMU_SSH_PORT:-}"
IMAGE_URL="${ACFS_QEMU_IMAGE_URL:-}"
IMAGE_SHA256SUMS_URL="${ACFS_QEMU_IMAGE_SHA256SUMS_URL:-}"
CACHE_DIR="${ACFS_QEMU_CACHE_DIR:-$REPO_ROOT/tests/artifacts/qemu-cache}"
ARTIFACTS_DIR="${ACFS_QEMU_ARTIFACTS_DIR:-}"
KEY_DIR="${ACFS_QEMU_KEY_DIR:-}"
INSTALL_URL="${ACFS_FACTORY_INSTALL_URL:-}"
ALLOW_INSTALL_REBOOT="${ACFS_QEMU_ALLOW_INSTALL_REBOOT:-false}"
PROVISIONING_PACKET="${ACFS_FACTORY_PROVISIONING_PACKET:-}"
LEAVE_RUNNING=false
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

usage() {
    cat <<'EOF'
tests/vm/test_factory_install_qemu.sh - local QEMU/KVM factory installer E2E

Usage:
  tests/vm/test_factory_install_qemu.sh [options]

Options:
  --ubuntu <version>           Ubuntu release to boot (default: 25.10).
  --ref <ref>                  ACFS ref to install (default: ACFS_REF or main).
  --mode <mode>                Install mode: vibe or safe (default: vibe).
  --provisioning-packet <path> Provider provisioning packet JSON to validate and map.
  --packet <path>              Alias for --provisioning-packet.
  --expect-final-ubuntu <ver>  Required final VERSION_ID after install/resume.
  --install-url <url>          Override public install.sh URL.
  --image-url <url>            Override Ubuntu cloud image URL.
  --image-sha256sums-url <url> Override SHA256SUMS URL for the cloud image.
  --cache-dir <path>           Cloud image cache dir (default: tests/artifacts/qemu-cache).
  --artifacts-dir <path>       Artifact directory for VM disk, serial log, and factory logs.
  --key-dir <path>             Directory for generated private SSH key; must be outside this repo.
  --ssh-port <port>            Host TCP port forwarded to guest SSH (default: random free port).
  --memory <mb>                VM memory in MiB (default: 8192).
  --cpus <count>               VM vCPU count (default: 4).
  --disk-size <size>           Overlay disk virtual size (default: 80G).
  --boot-timeout <seconds>     Time to wait for SSH (default: 900).
  --install-timeout <seconds>  Timeout per installer run (default: 14400).
  --post-reboot-timeout <sec>  Timeout for post-install/reboot checks (default: 14400).
  --allow-install-reboot       Allow installer-driven SSH disconnect/reconnect.
  --leave-running              Leave QEMU running after the harness exits.
  --help                       Show this help.

Dependencies:
  qemu-system-x86_64, qemu-img, cloud-localds, ssh, ssh-keygen, curl, sha256sum.

Ubuntu example:
  sudo apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils openssh-client

Notes:
  - This preserves artifacts by default: disk overlay, seed image, serial log,
    and delegated factory harness logs remain under tests/artifacts.
  - The generated private SSH key is intentionally kept outside this repository
    so CI uploads and future commits never include guest login credentials.
  - It stops the QEMU process by default to avoid leaking local resources. Use
    --leave-running when debugging a failed VM interactively.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ubuntu)
            UBUNTU_VERSION="${2:-}"
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
        --provisioning-packet|--packet)
            PROVISIONING_PACKET="${2:-}"
            shift 2
            ;;
        --expect-final-ubuntu)
            EXPECT_FINAL_UBUNTU_VERSION="${2:-}"
            shift 2
            ;;
        --install-url)
            INSTALL_URL="${2:-}"
            shift 2
            ;;
        --image-url)
            IMAGE_URL="${2:-}"
            shift 2
            ;;
        --image-sha256sums-url)
            IMAGE_SHA256SUMS_URL="${2:-}"
            shift 2
            ;;
        --cache-dir)
            CACHE_DIR="${2:-}"
            shift 2
            ;;
        --artifacts-dir)
            ARTIFACTS_DIR="${2:-}"
            shift 2
            ;;
        --key-dir)
            KEY_DIR="${2:-}"
            shift 2
            ;;
        --ssh-port)
            SSH_PORT="${2:-}"
            shift 2
            ;;
        --memory)
            MEMORY_MB="${2:-}"
            shift 2
            ;;
        --cpus)
            CPUS="${2:-}"
            shift 2
            ;;
        --disk-size)
            DISK_SIZE="${2:-}"
            shift 2
            ;;
        --boot-timeout)
            BOOT_TIMEOUT_SECONDS="${2:-}"
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
        --allow-install-reboot)
            ALLOW_INSTALL_REBOOT=true
            shift
            ;;
        --leave-running)
            LEAVE_RUNNING=true
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

case "$MODE" in
    vibe|safe) ;;
    *)
        echo "ERROR: --mode must be vibe or safe (got: $MODE)" >&2
        exit 1
        ;;
esac

for numeric_value in \
    "memory:$MEMORY_MB" \
    "cpus:$CPUS" \
    "boot-timeout:$BOOT_TIMEOUT_SECONDS" \
    "install-timeout:$INSTALL_TIMEOUT_SECONDS" \
    "post-reboot-timeout:$POST_REBOOT_TIMEOUT_SECONDS"
do
    numeric_name="${numeric_value%%:*}"
    numeric_body="${numeric_value#*:}"
    if [[ ! "$numeric_body" =~ ^[0-9]+$ ]] || [[ "$numeric_body" -lt 1 ]]; then
        echo "ERROR: --$numeric_name must be a positive integer (got: $numeric_body)" >&2
        exit 1
    fi
done

if [[ -n "$SSH_PORT" ]] && { [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]] || [[ "$SSH_PORT" -lt 1024 ]] || [[ "$SSH_PORT" -gt 65535 ]]; }; then
    echo "ERROR: --ssh-port must be an integer from 1024 to 65535 (got: $SSH_PORT)" >&2
    exit 1
fi

if [[ -z "$IMAGE_URL" ]]; then
    case "$UBUNTU_VERSION" in
        24.04|25.04|25.10)
            IMAGE_URL="https://cloud-images.ubuntu.com/releases/server/${UBUNTU_VERSION}/release/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
            ;;
        *)
            echo "ERROR: --image-url is required for unsupported --ubuntu value: $UBUNTU_VERSION" >&2
            exit 1
            ;;
    esac
fi

if [[ -z "$IMAGE_SHA256SUMS_URL" ]]; then
    IMAGE_SHA256SUMS_URL="${IMAGE_URL%/*}/SHA256SUMS"
fi

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $1" >&2
        exit 1
    fi
}

require_cmd mktemp
require_cmd python3

if [[ -z "$ARTIFACTS_DIR" ]]; then
    ARTIFACTS_DIR="$REPO_ROOT/tests/artifacts/qemu-factory-${UBUNTU_VERSION}-${TIMESTAMP}"
fi

if [[ -z "$KEY_DIR" ]]; then
    if [[ -n "${RUNNER_TEMP:-}" ]]; then
        KEY_DIR="$RUNNER_TEMP/acfs-qemu-keys-${TIMESTAMP}"
    else
        KEY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/acfs-qemu-keys-${TIMESTAMP}.XXXXXX")"
    fi
fi

path_is_within() {
    python3 - "$1" "$2" <<'PY'
import pathlib
import sys

child = pathlib.Path(sys.argv[1]).resolve()
parent = pathlib.Path(sys.argv[2]).resolve()
try:
    child.relative_to(parent)
except ValueError:
    sys.exit(1)
PY
}

if path_is_within "$KEY_DIR" "$REPO_ROOT"; then
    echo "ERROR: --key-dir must be outside the repository so private SSH keys are not committed or uploaded as artifacts" >&2
    exit 1
fi

if path_is_within "$KEY_DIR" "$ARTIFACTS_DIR"; then
    echo "ERROR: --key-dir must be outside --artifacts-dir so private SSH keys are not uploaded as artifacts" >&2
    exit 1
fi

require_cmd basename
require_cmd cloud-localds
require_cmd curl
require_cmd date
require_cmd mkdir
require_cmd qemu-img
require_cmd qemu-system-x86_64
require_cmd sha256sum
require_cmd ssh
require_cmd ssh-keygen

if [[ ! -e /dev/kvm ]]; then
    echo "ERROR: /dev/kvm is missing; QEMU canary requires KVM for a realistic and practical run." >&2
    exit 1
fi

if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
    echo "ERROR: /dev/kvm exists but is not readable/writable by $(id -un)." >&2
    echo "       Add the user to the kvm group, re-login, or run on a KVM-enabled host." >&2
    exit 1
fi

mkdir -p "$CACHE_DIR" "$ARTIFACTS_DIR" "$KEY_DIR"
chmod 700 "$KEY_DIR"

image_name="$(basename "$IMAGE_URL")"
base_image="$CACHE_DIR/$image_name"
sha_file="$CACHE_DIR/${image_name}.SHA256SUMS"
disk_path="$ARTIFACTS_DIR/acfs-factory.qcow2"
seed_iso="$ARTIFACTS_DIR/seed.iso"
user_data="$ARTIFACTS_DIR/user-data.yml"
meta_data="$ARTIFACTS_DIR/meta-data.yml"
ssh_key="$KEY_DIR/root_ssh_key"
known_hosts="$ARTIFACTS_DIR/known_hosts"
serial_log="$ARTIFACTS_DIR/serial.log"
qemu_log="$ARTIFACTS_DIR/qemu.log"
pid_file="$ARTIFACTS_DIR/qemu.pid"

echo "[qemu-factory] Ubuntu: $UBUNTU_VERSION" >&2
echo "[qemu-factory] Image: $IMAGE_URL" >&2
echo "[qemu-factory] Ref: $REF" >&2
echo "[qemu-factory] Mode: $MODE" >&2
echo "[qemu-factory] Artifacts: $ARTIFACTS_DIR" >&2
echo "[qemu-factory] Private SSH key directory: $KEY_DIR (not uploaded)" >&2

download_cloud_image() {
    if [[ ! -f "$base_image" ]]; then
        echo "[qemu-factory] Downloading cloud image to $base_image" >&2
        curl -fL --retry 3 --connect-timeout 30 --output "$base_image.part" "$IMAGE_URL"
        mv "$base_image.part" "$base_image"
    fi

    echo "[qemu-factory] Fetching image checksums" >&2
    curl -fsSL --retry 3 --connect-timeout 30 --output "$sha_file" "$IMAGE_SHA256SUMS_URL"

    if ! grep -E "[[:space:]]\\*?${image_name}$" "$sha_file" > "$ARTIFACTS_DIR/image.sha256"; then
        echo "ERROR: checksum manifest does not contain $image_name" >&2
        exit 1
    fi

    (
        cd "$CACHE_DIR"
        sha256sum -c "$ARTIFACTS_DIR/image.sha256"
    )
}

pick_ssh_port() {
    if [[ -n "$SSH_PORT" ]]; then
        printf '%s\n' "$SSH_PORT"
        return 0
    fi

    python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

write_cloud_init_seed() {
    if [[ ! -f "$ssh_key" ]]; then
        ssh-keygen -q -t ed25519 -N "" -C "acfs-qemu-factory-${TIMESTAMP}" -f "$ssh_key"
    fi

    public_key="$(<"${ssh_key}.pub")"

    cat > "$user_data" <<EOF
#cloud-config
disable_root: false
ssh_pwauth: false
package_update: false
users:
  - name: root
    lock_passwd: true
    shell: /bin/bash
    ssh_authorized_keys:
      - ${public_key}
runcmd:
  - [ bash, -lc, "systemctl enable --now ssh || systemctl enable --now sshd || true" ]
EOF

    cat > "$meta_data" <<EOF
instance-id: acfs-qemu-factory-${TIMESTAMP}
local-hostname: acfs-qemu-factory
EOF

    cloud-localds "$seed_iso" "$user_data" "$meta_data"
}

create_overlay_disk() {
    if [[ -e "$disk_path" ]]; then
        echo "ERROR: VM disk already exists: $disk_path" >&2
        echo "       Use a fresh --artifacts-dir or move the existing disk aside." >&2
        exit 1
    fi

    base_format="$(qemu-img info --output=json "$base_image" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("format", "qcow2"))')"
    qemu-img create -f qcow2 -F "$base_format" -b "$base_image" "$disk_path" "$DISK_SIZE" >/dev/null
}

stop_vm() {
    if [[ "$LEAVE_RUNNING" == "true" ]]; then
        return 0
    fi

    if [[ -f "$pid_file" ]]; then
        qemu_pid="$(<"$pid_file")"
        if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
            echo "[qemu-factory] Stopping QEMU process $qemu_pid" >&2
            kill "$qemu_pid" 2>/dev/null || true
            for _ in {1..30}; do
                kill -0 "$qemu_pid" 2>/dev/null || return 0
                sleep 1
            done
            kill -TERM "$qemu_pid" 2>/dev/null || true
        fi
    fi
}
trap stop_vm EXIT

start_vm() {
    forwarded_port="$(pick_ssh_port)"
    printf '%s\n' "$forwarded_port" > "$ARTIFACTS_DIR/ssh-port"

    echo "[qemu-factory] Starting QEMU with SSH on 127.0.0.1:${forwarded_port}" >&2
    qemu-system-x86_64 \
        -enable-kvm \
        -cpu host \
        -m "$MEMORY_MB" \
        -smp "$CPUS" \
        -drive "file=$disk_path,if=virtio,format=qcow2,cache=writeback" \
        -drive "file=$seed_iso,if=virtio,format=raw,readonly=on" \
        -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${forwarded_port}-:22" \
        -device virtio-net-pci,netdev=net0 \
        -display none \
        -serial "file:$serial_log" \
        -pidfile "$pid_file" \
        -daemonize > "$qemu_log" 2>&1
}

wait_for_ssh() {
    local deadline=$((SECONDS + BOOT_TIMEOUT_SECONDS))
    local ssh_status=0

    touch "$known_hosts"
    while [[ "$SECONDS" -lt "$deadline" ]]; do
        set +e
        ssh -i "$ssh_key" \
            -p "$forwarded_port" \
            -o BatchMode=yes \
            -o ConnectTimeout=10 \
            -o StrictHostKeyChecking=accept-new \
            -o "UserKnownHostsFile=$known_hosts" \
            root@127.0.0.1 true >/dev/null 2>&1
        ssh_status=$?
        set -e

        if [[ "$ssh_status" -eq 0 ]]; then
            echo "[qemu-factory] SSH is ready" >&2
            return 0
        fi

        if [[ -f "$pid_file" ]]; then
            qemu_pid="$(<"$pid_file")"
            if [[ -n "$qemu_pid" ]] && ! kill -0 "$qemu_pid" 2>/dev/null; then
                echo "ERROR: QEMU exited before SSH became ready. Serial log: $serial_log" >&2
                tail -n 120 "$serial_log" 2>/dev/null || true
                exit 1
            fi
        fi

        echo "[qemu-factory] Waiting for SSH..." >&2
        sleep 10
    done

    echo "ERROR: timed out waiting for SSH. Serial log: $serial_log" >&2
    tail -n 120 "$serial_log" 2>/dev/null || true
    exit 1
}

run_factory_harness() {
    local -a factory_args=(
        --ssh-target root@127.0.0.1
        --ssh-key "$ssh_key"
        --ssh-port "$forwarded_port"
        --ref "$REF"
        --mode "$MODE"
        --expect-ubuntu "$UBUNTU_VERSION"
        --expect-final-ubuntu "$EXPECT_FINAL_UBUNTU_VERSION"
        --public-key-file "${ssh_key}.pub"
        --install-timeout "$INSTALL_TIMEOUT_SECONDS"
        --post-reboot-timeout "$POST_REBOOT_TIMEOUT_SECONDS"
        --artifacts-dir "$ARTIFACTS_DIR/factory"
    )

    if [[ "$ALLOW_INSTALL_REBOOT" == "true" ]]; then
        factory_args+=(--allow-install-reboot)
    fi

    if [[ -n "$INSTALL_URL" ]]; then
        factory_args+=(--install-url "$INSTALL_URL")
    fi

    if [[ -n "$PROVISIONING_PACKET" ]]; then
        factory_args+=(--provisioning-packet "$PROVISIONING_PACKET")
    fi

    "$SCRIPT_DIR/test_factory_install_ubuntu.sh" "${factory_args[@]}"
}

download_cloud_image
write_cloud_init_seed
create_overlay_disk
start_vm
wait_for_ssh
run_factory_harness

echo "[qemu-factory] PASS: QEMU factory installer E2E passed. Artifacts: $ARTIFACTS_DIR" >&2
