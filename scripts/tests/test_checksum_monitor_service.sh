#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UNIT="$REPO_ROOT/scripts/templates/acfs-checksum-monitor.service"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$UNIT" ]] || fail "missing checksum monitor service template"

mapfile -t pre_commands < <(sed -n 's/^ExecStartPre=//p' "$UNIT")
expected_pre_commands=(
    '/usr/bin/git -C %h/acfs-monitor diff --quiet --exit-code --'
    '/usr/bin/git -C %h/acfs-monitor diff --cached --quiet --exit-code --'
    '/usr/bin/git -C %h/acfs-monitor fetch --quiet --no-tags --recurse-submodules=no https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup.git +refs/heads/main:refs/remotes/acfs-bootstrap/main'
    '/usr/bin/git -C %h/acfs-monitor -c core.hooksPath=/dev/null merge --ff-only --quiet refs/remotes/acfs-bootstrap/main'
)

[[ ${#pre_commands[@]} -eq ${#expected_pre_commands[@]} ]] \
    || fail "expected ${#expected_pre_commands[@]} bootstrap commands, found ${#pre_commands[@]}"

for index in "${!expected_pre_commands[@]}"; do
    [[ "${pre_commands[$index]}" == "${expected_pre_commands[$index]}" ]] \
        || fail "bootstrap command $((index + 1)) changed or moved"
done

exec_start="$(sed -n 's/^ExecStart=//p' "$UNIT")"
[[ "$exec_start" == '%h/acfs-monitor/scripts/checksum-monitor-local.sh' ]] \
    || fail "monitor ExecStart no longer names the dedicated-clone script"

fetch_line="$(grep -n '^ExecStartPre=.* fetch ' "$UNIT" | cut -d: -f1)"
merge_line="$(grep -n '^ExecStartPre=.* merge ' "$UNIT" | cut -d: -f1)"
exec_line="$(grep -n '^ExecStart=' "$UNIT" | cut -d: -f1)"
[[ "$fetch_line" =~ ^[0-9]+$ && "$merge_line" =~ ^[0-9]+$ && "$exec_line" =~ ^[0-9]+$ ]] \
    || fail "could not locate bootstrap ordering"
(( fetch_line < merge_line && merge_line < exec_line )) \
    || fail "canonical fetch and fast-forward must precede monitor execution"

[[ "${pre_commands[2]}" != *' origin '* ]] \
    || fail "bootstrap fetch must not trust the clone's configurable origin"
[[ "${pre_commands[2]}" == *'--recurse-submodules=no'* ]] \
    || fail "bootstrap fetch must not recurse into repository-configured submodules"
[[ "${pre_commands[3]}" == *'-c core.hooksPath=/dev/null'* ]] \
    || fail "bootstrap merge must disable repository hooks"
[[ "${pre_commands[3]}" == *'--ff-only'* ]] \
    || fail "bootstrap merge must remain fast-forward-only"

printf 'PASS: checksum monitor service bootstraps canonical main before ExecStart\n'
