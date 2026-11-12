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
expected_post_command="$(cat <<'COMMAND'
/usr/bin/env -i HOME=%h PATH=/usr/bin:/bin /usr/bin/bash --noprofile --norc -c 'set -eu; bootstrap_head=$$(/usr/bin/git -C "$$1" rev-parse --verify HEAD^{commit}); bootstrap_expected=$$(/usr/bin/git -C "$$1" rev-parse --verify refs/remotes/acfs-bootstrap/main^{commit}); test "$$bootstrap_head" = "$$bootstrap_expected"' acfs-bootstrap %h/acfs-monitor
COMMAND
)"
expected_pre_commands=(
    '/usr/bin/git -C %h/acfs-monitor diff --quiet --exit-code --'
    '/usr/bin/git -C %h/acfs-monitor diff --cached --quiet --exit-code --'
    '/usr/bin/git -C %h/acfs-monitor fetch --quiet --no-tags --recurse-submodules=no https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup.git +refs/heads/main:refs/remotes/acfs-bootstrap/main'
    '/usr/bin/git -C %h/acfs-monitor merge-base --is-ancestor HEAD refs/remotes/acfs-bootstrap/main'
    '/usr/bin/git -C %h/acfs-monitor -c core.hooksPath=/dev/null merge --ff-only --quiet refs/remotes/acfs-bootstrap/main'
    "$expected_post_command"
)

[[ ${#pre_commands[@]} -eq ${#expected_pre_commands[@]} ]] \
    || fail "expected ${#expected_pre_commands[@]} bootstrap commands, found ${#pre_commands[@]}"

for index in "${!expected_pre_commands[@]}"; do
    [[ "${pre_commands[$index]}" == "${expected_pre_commands[$index]}" ]] \
        || fail "bootstrap command $((index + 1)) changed or moved"
done

[[ "$(sed -n 's/^UMask=//p' "$UNIT")" == "0077" ]] \
    || fail "monitor must create its state private (UMask=0077); a 002 umask makes it fail closed"

exec_start="$(sed -n 's/^ExecStart=//p' "$UNIT")"
[[ "$exec_start" == '%h/acfs-monitor/scripts/checksum-monitor-local.sh' ]] \
    || fail "monitor ExecStart no longer names the dedicated-clone script"

fetch_line="$(grep -n '^ExecStartPre=.* fetch ' "$UNIT" | cut -d: -f1)"
ancestry_line="$(grep -n '^ExecStartPre=.* merge-base ' "$UNIT" | cut -d: -f1)"
merge_line="$(grep -n '^ExecStartPre=.* merge ' "$UNIT" | cut -d: -f1)"
post_line="$(grep -n '^ExecStartPre=/usr/bin/env .*rev-parse' "$UNIT" | cut -d: -f1)"
exec_line="$(grep -n '^ExecStart=' "$UNIT" | cut -d: -f1)"
[[ "$fetch_line" =~ ^[0-9]+$ && "$ancestry_line" =~ ^[0-9]+$ && "$merge_line" =~ ^[0-9]+$ \
    && "$post_line" =~ ^[0-9]+$ && "$exec_line" =~ ^[0-9]+$ ]] \
    || fail "could not locate bootstrap ordering"
(( fetch_line < ancestry_line && ancestry_line < merge_line && merge_line < post_line && post_line < exec_line )) \
    || fail "fetch, ancestry, fast-forward and exact-commit checks must precede monitor execution"

[[ "${pre_commands[2]}" != *' origin '* ]] \
    || fail "bootstrap fetch must not trust the clone's configurable origin"
[[ "${pre_commands[2]}" == *'--recurse-submodules=no'* ]] \
    || fail "bootstrap fetch must not recurse into repository-configured submodules"
[[ "${pre_commands[4]}" == *'-c core.hooksPath=/dev/null'* ]] \
    || fail "bootstrap merge must disable repository hooks"
[[ "${pre_commands[4]}" == *'--ff-only'* ]] \
    || fail "bootstrap merge must remain fast-forward-only"

command -v python3 >/dev/null || fail "service integration tests require python3"
[[ -x /usr/bin/git && -x /usr/bin/env && -x /usr/bin/bash ]] \
    || fail "service integration tests require the production system executables"

# Execute the unit's parsed commands, substituting only the canonical network
# URL and %h for retained local fixtures. No monitor, installer or network runs.
# All Git histories, dirty files, execution markers and receipts are retained.
python3 - "$UNIT" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile

unit = Path(sys.argv[1])
unit_text = unit.read_text()
pre_lines = [line.partition("=")[2] for line in unit_text.splitlines() if line.startswith("ExecStartPre=")]
start_line = next(line.partition("=")[2] for line in unit_text.splitlines() if line.startswith("ExecStart="))
service_umask = int(next(line.partition("=")[2] for line in unit_text.splitlines()
                         if line.startswith("UMask=")), 8)
canonical_url = "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup.git"
root = Path(tempfile.mkdtemp(prefix="acfs-service-bootstrap-tests-"))
root.chmod(0o700)
# A permissive fixture parent makes ignoring the service's mask observable,
# independent of the developer shell or CI runner's own umask. All fixtures
# remain underneath the private retained root.
os.umask(0o002)
print(f"Retaining checksum monitor service fixtures: {root}", flush=True)
base_env = {"PATH": "/usr/bin:/bin", "HOME": str(root), "LANG": "C", "LC_ALL": "C",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_NAME": "ACFS service fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "ACFS service fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid"}


def run(arguments, *, cwd=None, environment=None, check=True, umask=-1):
    result = subprocess.run(arguments, cwd=cwd, env=base_env if environment is None else environment,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20, umask=umask)
    if check and result.returncode:
        raise AssertionError((arguments, result.returncode, result.stderr.decode(errors="replace")))
    return result


def git(repo, *arguments, check=True):
    return run(["/usr/bin/git", "-C", str(repo), *arguments], check=check)


def commit(repo, label):
    script = repo / "scripts/checksum-monitor-local.sh"
    script.parent.mkdir(exist_ok=True)
    # This inert monitor records the actual ExecStart creation policy. It
    # neither loads production helpers nor contacts a network or publisher.
    script.write_text("#!/usr/bin/env bash\nset -eu\n"
                      'mkdir -p -- "$EXECUTION_STATE/logs"\n'
                      'printf "private fixture lock\\n" > "$EXECUTION_STATE/monitor.lock"\n'
                      'printf "private fixture log\\n" > "$EXECUTION_STATE/logs/run.log"\n'
                      "printf '%s\\n' '" + label + "' > \"$EXECUTION_MARKER\"\n")
    script.chmod(0o755)
    policy = repo / "checksums.yaml"
    policy.write_text("fixture: " + label + "\n")
    policy.chmod(0o644)
    git(repo, "add", "--", "scripts/checksum-monitor-local.sh", "checksums.yaml")
    git(repo, "commit", "-qm", label)


def command(line, home, canonical):
    # These templates use systemd's quoted words, %h, and literal-dollar $$.
    # Expand specifiers after tokenization so a home containing spaces remains
    # one argument. The independent systemd parser check below covers syntax.
    return [str(canonical) if word == canonical_url else
            word.replace("%h", str(home)).replace("$$", "$") for word in shlex.split(line)]


def fingerprint(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


receipts = []
scenarios = ("exact", "behind", "ahead", "diverged", "tracked_dirty", "staged_dirty",
             "head_moves_before_merge", "head_moves_after_merge", "ref_moves_after_merge",
             "head_lookup_fails", "ref_lookup_fails", "post_guard_ambient_hook")
for scenario in scenarios:
    case = root / scenario
    case.mkdir()
    canonical = case / "canonical"
    canonical.mkdir()
    git(canonical, "init", "-q", "--initial-branch=main")
    commit(canonical, "canonical-base")
    # Exercise quoting in both systemd specifier expansion and the exact-head
    # shell. The fixture's direct ExecStart still receives one complete path.
    home = case / "monitor home"
    home.mkdir()
    checkout = home / "acfs-monitor"
    run(["/usr/bin/git", "clone", "--quiet", "--no-hardlinks", str(canonical), str(checkout)])
    if scenario in ("behind", "diverged"):
        commit(canonical, "canonical-new")
    if scenario in ("ahead", "diverged"):
        commit(checkout, "unreviewed-local")
    if scenario in ("tracked_dirty", "staged_dirty"):
        script = checkout / "scripts/checksum-monitor-local.sh"
        script.write_text(script.read_text() + "# uncommitted evidence must remain\n")
        if scenario == "staged_dirty":
            git(checkout, "add", "--", "scripts/checksum-monitor-local.sh")
    marker = case / "executed"
    state = home / ".local/state/acfs-monitor"
    hook_marker = case / "unexpected-hook"
    hooks = case / "hooks"
    hooks.mkdir()
    hook = hooks / "post-merge"
    hook.write_text("#!/usr/bin/env bash\nprintf 'unexpected hook' > '" + str(hook_marker) + "'\n")
    hook.chmod(0o755)
    git(checkout, "config", "core.hooksPath", str(hooks))
    environment = {**base_env, "HOME": str(home), "EXECUTION_MARKER": str(marker),
                   "EXECUTION_STATE": str(state)}
    before_head = git(checkout, "rev-parse", "HEAD").stdout.decode().strip()
    before_index = git(checkout, "write-tree").stdout.decode().strip()
    before_script = fingerprint(checkout / "scripts/checksum-monitor-local.sh")
    row = {"scenario": scenario, "commands": [], "executed": False,
           "service_umask": format(service_umask, "04o")}
    successful = True
    for line in pre_lines:
        arguments = command(line, home, canonical)
        if "merge" in arguments and scenario == "head_moves_before_merge":
            commit(checkout, "unreviewed-between-steps")
        command_env = environment
        if arguments[0] == "/usr/bin/env" and scenario == "post_guard_ambient_hook":
            poison = case / "bash-environment"
            poison.write_text("printf 'unexpected BASH_ENV' > '" + str(hook_marker) + "'\n")
            command_env = {**environment, "BASH_ENV": str(poison), "ENV": str(poison)}
        result = run(arguments, environment=command_env, check=False, umask=service_umask)
        row["commands"].append({"arguments": arguments, "exit": result.returncode,
                                "stdout": result.stdout.decode(errors="replace"),
                                "stderr": result.stderr.decode(errors="replace")})
        if result.returncode:
            successful = False
            break
        if "fetch" in arguments:
            # The unit mask applies to ExecStartPre as well as ExecStart.
            # Neither path may silently inherit the fixture's 0002 policy.
            fetch_head = checkout / ".git/FETCH_HEAD"
            assert stat.S_IMODE(fetch_head.stat().st_mode) == 0o600, row
            row["fetch_head_mode"] = "0600"
        if "merge" in arguments:
            if scenario == "head_moves_after_merge":
                commit(checkout, "unreviewed-after-merge")
            elif scenario == "ref_moves_after_merge":
                commit(canonical, "canonical-after-merge")
                git(checkout, "fetch", "--quiet", "--no-tags", "--recurse-submodules=no", str(canonical),
                    "+refs/heads/main:refs/remotes/acfs-bootstrap/main")
            elif scenario == "head_lookup_fails":
                original = checkout / ".git/HEAD"
                original.rename(case / "retained-HEAD")
                original.write_text("ref: refs/heads/absent-fixture\n")
            elif scenario == "ref_lookup_fails":
                original = checkout / ".git/refs/remotes/acfs-bootstrap/main"
                original.rename(case / "retained-bootstrap-ref")
                original.write_text("ref: refs/heads/absent-fixture\n")
    if successful:
        result = run(command(start_line, home, canonical), environment=environment,
                     check=False, umask=service_umask)
        row.update(executed=True, execution_exit=result.returncode,
                   execution_marker=marker.read_text() if marker.exists() else None)
    expected_execution = scenario in ("exact", "behind", "post_guard_ambient_hook")
    assert row["executed"] == expected_execution, row
    assert not hook_marker.exists(), "bootstrap executed a configured or ambient hook"
    if expected_execution:
        expected_label = "canonical-new\n" if scenario == "behind" else "canonical-base\n"
        assert row["execution_exit"] == 0 and row["execution_marker"] == expected_label, row
        assert git(checkout, "rev-parse", "HEAD").stdout == git(checkout, "rev-parse", "refs/remotes/acfs-bootstrap/main").stdout
        for directory in (home / ".local", home / ".local/state", state, state / "logs"):
            assert stat.S_IMODE(directory.stat().st_mode) == 0o700, directory
        for record in (marker, state / "monitor.lock", state / "logs/run.log"):
            assert stat.S_IMODE(record.stat().st_mode) == 0o600, record
        row["private_state_created"] = True
        # Private checkout modes retain Git's executable distinction. A
        # canonical fast-forward must still execute the new monitor itself.
        script_mode = stat.S_IMODE((checkout / "scripts/checksum-monitor-local.sh").stat().st_mode)
        policy_mode = stat.S_IMODE((checkout / "checksums.yaml").stat().st_mode)
        assert script_mode & stat.S_IXUSR and not policy_mode & stat.S_IXUSR, row
        if scenario == "behind":
            assert (script_mode, policy_mode) == (0o700, 0o600), (script_mode, policy_mode)
            row["fast_forward_modes"] = {"monitor": "0700", "policy": "0600"}
    else:
        assert not marker.exists(), "refused checkout reached its monitor script"
        assert not state.exists(), "refused checkout created monitor state"
    if scenario in ("ahead", "diverged", "tracked_dirty", "staged_dirty"):
        assert git(checkout, "rev-parse", "HEAD").stdout.decode().strip() == before_head
        assert git(checkout, "write-tree").stdout.decode().strip() == before_index
        assert fingerprint(checkout / "scripts/checksum-monitor-local.sh") == before_script
        row["refused_checkout_preserved"] = True
    row["passed"] = True
    receipts.append(row)
    print(f"PASS: service bootstrap {scenario}", flush=True)

# systemd-analyze does not execute unit commands. Substitute only ExecStart's
# unavailable deployment path with /usr/bin/true; all pre-command syntax,
# including specifiers, quoting and literal dollar signs, remains untouched.
analyzer = shutil.which("systemd-analyze")
parser_result = {"status": "unavailable"}
if analyzer:
    parser_unit = root / "acfs-bootstrap-parser.service"
    parser_unit.write_text("\n".join("ExecStart=/usr/bin/true" if line.startswith("ExecStart=") else line
                                      for line in unit_text.splitlines()) + "\n")
    result = run([analyzer, "--man=no", "verify", str(parser_unit)], check=False)
    parser_result = {"exit": result.returncode, "stdout": result.stdout.decode(errors="replace"),
                     "stderr": result.stderr.decode(errors="replace")}
    (root / "parser-result.json").write_text(json.dumps(parser_result, indent=2) + "\n")
    assert result.returncode == 0, parser_result
    print("PASS: systemd parser accepts service pre-commands", flush=True)
else:
    print("SKIP: systemd-analyze is unavailable; no native unit-parser qualification", flush=True)

summary = {"unit_sha256": hashlib.sha256(unit.read_bytes()).hexdigest(),
           "passed": len(receipts), "scenarios": receipts, "systemd_parser": parser_result,
           "proof_class": "actual parsed unit commands with a local canonical Git fixture"}
(root / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
print(f"Service bootstrap results: {root / 'results.json'}", flush=True)
PY

printf 'PASS: checksum monitor service requires canonical main before ExecStart\n'
