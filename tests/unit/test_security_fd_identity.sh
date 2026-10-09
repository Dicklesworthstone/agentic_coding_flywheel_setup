#!/usr/bin/env bash
# Exercise real retained descriptors on macOS fdescfs and Linux procfs.
# Preserve fixtures and snapshots; no cleanup bypass or fake identity checks.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Optional first argument lets the exact oracle exercise an incumbent library.
# shellcheck source=../../scripts/lib/security.sh
source "${1:-$REPO_ROOT/scripts/lib/security.sh}"

ACFS_SECURITY_RETAIN_TEMP_FILES=true
fixture="$(mktemp -d "${TMPDIR:-/tmp}/acfs-fd-identity.XXXXXX")"
printf 'Retaining descriptor test fixtures: %s\n' "$fixture" >&2
passed=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
accept() {
    local label="$1"
    shift
    "$@" || fail "$label"
    printf 'PASS: %s\n' "$label"
    passed=$((passed + 1))
}
reject() {
    local label="$1"
    shift
    if "$@"; then fail "$label was accepted"; fi
    printf 'PASS: %s\n' "$label"
    passed=$((passed + 1))
}

printf 'original policy\n' > "$fixture/policy"
printf 'different inode\n' > "$fixture/other"
test_snapshot="" test_identity_fd="" test_digest=""
accept 'regular policy opens a bound snapshot' acfs_security_open_bound_snapshot \
    "$fixture/policy" 1024 "$fixture/snapshot.XXXXXX" 'test policy' \
    test_snapshot test_identity_fd test_digest
accept 'snapshot bytes match the input' cmp "$fixture/policy" "$test_snapshot"
(
    exec {probe_fd}< "$fixture/policy"
    acfs_security_close_fd "$probe_fd"
    printf 'stderr remains connected\n' >&2
) 2> "$fixture/stderr-probe"
accept 'closing a descriptor preserves stderr' grep -Fx 'stderr remains connected' "$fixture/stderr-probe"
accept 'unchanged bound snapshot remains current' acfs_security_bound_snapshot_is_current \
    "$fixture/policy" "$test_identity_fd" "$test_digest" 1024 'test policy'

exec {second_fd}< "$fixture/policy"
exec {other_fd}< "$fixture/other"
exec {directory_fd}< "$fixture"
accept 'two handles for the same regular file match' acfs_security_fd_matches_path \
    "$fixture/policy" "$test_identity_fd" "$second_fd"
reject 'a different source inode cannot match' acfs_security_fd_matches_path \
    "$fixture/other" "$test_identity_fd"
reject 'a different comparison handle cannot match' acfs_security_fd_matches_path \
    "$fixture/policy" "$test_identity_fd" "$other_fd"
reject 'a directory descriptor cannot match' acfs_security_fd_matches_path \
    "$fixture/policy" "$directory_fd"
ln -s "$fixture/policy" "$fixture/symlink"
reject 'a symlink source cannot match' acfs_security_fd_matches_path \
    "$fixture/symlink" "$test_identity_fd"
reject 'a missing path cannot match' acfs_security_fd_matches_path \
    "$fixture/missing" "$test_identity_fd"
reject 'a nonnumeric descriptor cannot match' acfs_security_fd_matches_path \
    "$fixture/policy" 'invalid'

# Same inode, changed contents: identity alone must not authorize emission.
printf 'changed policy\n' >> "$fixture/policy"
reject 'changed bytes invalidate the retained snapshot' acfs_security_bound_snapshot_is_current \
    "$fixture/policy" "$test_identity_fd" "$test_digest" 1024 'test policy'
acfs_security_close_fd "$test_identity_fd"
acfs_security_close_fd "$second_fd"
acfs_security_close_fd "$other_fd"
acfs_security_close_fd "$directory_fd"
printf 'PASS: %s descriptor and byte-binding checks\n' "$passed"
