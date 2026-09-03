#!/usr/bin/env python3
"""Launch Antigravity CLI with ACFS pinned defaults and dcg guard wiring."""

import json
import os
import pathlib
import signal
import shlex
import subprocess
import sys
import tempfile


MODEL = "Gemini 3.8 Flash (High)"
HOME = pathlib.Path.home()
REAL_AGY = HOME / ".local" / "bin" / "agy-real"
SETTINGS_PATH = HOME / ".gemini" / "antigravity-cli" / "settings.json"
HOOKS_PATH = HOME / ".gemini" / "config" / "hooks.json"
DCG_HOOK = HOME / ".gemini" / "config" / "hooks" / "dcg-antigravity-hook.py"
HOOK_TIMEOUT_SECONDS = 6
DCG_TIMEOUT_SECONDS = 4
PRIME_SETTINGS_FLAG = "--acfs-prime-settings"
LAUNCHER_MARKER = "acfs-agy-locked-launcher-v1"


def is_real_agy_candidate(candidate):
    if candidate.is_symlink() or not candidate.is_file() or not os.access(candidate, os.X_OK):
        return False
    try:
        with candidate.open("rb") as candidate_file:
            prefix = candidate_file.read(4096)
    except OSError:
        return False
    return (
        LAUNCHER_MARKER.encode() not in prefix
        and b"Launch Antigravity CLI with ACFS pinned defaults" not in prefix
    )


def resolve_real_agy():
    bin_dir = os.environ.get("ACFS_BIN_DIR")
    if bin_dir:
        candidate = pathlib.Path(bin_dir) / "agy-real"
        if is_real_agy_candidate(candidate):
            return candidate
    try:
        candidate = pathlib.Path(__file__).resolve().parent / "agy-real"
        if is_real_agy_candidate(candidate):
            return candidate
    except (OSError, RuntimeError):
        pass
    candidate = HOME / ".local" / "bin" / "agy-real"
    if is_real_agy_candidate(candidate):
        return candidate
    return REAL_AGY


PINNED_SETTINGS = {
    "allowNonWorkspaceAccess": True,
    "altScreenMode": "never",
    "artifactReviewPolicy": "always-proceed",
    "colorScheme": "terminal",
    "editor": "auto",
    "effort": "high",
    "enableTelemetry": False,
    "enableTerminalSandbox": False,
    "model": MODEL,
    "notifications": False,
    "runningLightSpeed": "medium",
    "showFeedbackSurvey": False,
    "showTips": False,
    "toolPermission": "always-proceed",
    "useG1Credits": False,
    "verbosity": "high",
}

DCG_HOOK_SOURCE = r'''#!/usr/bin/env python3
"""Antigravity PreToolUse adapter for dcg."""

import json
import os
import subprocess
import sys


DCG_TIMEOUT_SECONDS = 4
DCG_DENY_DECISIONS = frozenset({"deny", "block"})
DCG_REVIEW_DECISIONS = frozenset({"ask", "indeterminate"})


def emit(decision, reason=None):
    payload = {"decision": decision}
    if reason:
        payload["reason"] = reason
    print(json.dumps(payload), flush=True)


def extract_command(payload):
    if not isinstance(payload, dict):
        return ""
    tool_call = payload.get("toolCall") or payload.get("tool_call")
    if not isinstance(tool_call, dict):
        return ""
    args = tool_call.get("args") or tool_call.get("arguments") or tool_call.get("input")
    if not isinstance(args, dict):
        return ""
    command = (
        args.get("CommandLine")
        or args.get("commandLine")
        or args.get("command_line")
        or args.get("command")
        or args.get("cmd")
    )
    return command if isinstance(command, str) else ""


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        emit("force_ask", "DCG could not inspect malformed Antigravity hook input")
        return 0

    command = extract_command(payload)
    if not command:
        emit("force_ask", "DCG could not inspect the proposed command")
        return 0

    dcg_bin = os.environ.get("DCG_BIN", os.path.expanduser("~/.local/bin/dcg"))
    dcg_env = os.environ.copy()
    # DCG v0.9.2 understands stdin robot mode but predates the --dialect CLI
    # flag. Newer releases accept the equivalent environment setting, while
    # older releases safely ignore it and evaluate all supported dialects.
    dcg_env["DCG_DIALECT"] = "posix"
    try:
        proc = subprocess.run(
            [
                dcg_bin,
                "--robot",
                "--agent",
                "antigravity",
                "test",
                "--stdin",
            ],
            input=command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=DCG_TIMEOUT_SECONDS,
            check=False,
            env=dcg_env,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        emit("allow", f"dcg unavailable; fail-open: {exc}")
        return 0

    try:
        result = json.loads(proc.stdout) if proc.stdout.strip() else {}
    except json.JSONDecodeError:
        result = {}
    if not isinstance(result, dict):
        result = {}

    decision = result.get("decision")
    reason = (
        result.get("reason")
        or result.get("explanation")
        or proc.stderr.strip()
        or "dcg returned no explanation"
    )
    rule_id = result.get("rule_id")
    if rule_id:
        reason = f"{reason} ({rule_id})"

    if decision in DCG_DENY_DECISIONS:
        emit("deny", f"Blocked by dcg: {reason}")
        return 0

    if decision in DCG_REVIEW_DECISIONS:
        emit("force_ask", f"Review required by dcg: {reason}")
        return 0

    if proc.returncode == 1:
        emit("force_ask", "dcg withheld execution but returned no usable verdict")
        return 0

    if decision in {"allow", "warn", "log"}:
        emit("allow")
        return 0

    # DCG deliberately fails open on infrastructure and output failures. Keep
    # that availability policy here; exit 1 above remains fail-safe because it
    # is DCG's explicit withheld-execution signal.
    if proc.returncode != 0:
        reason = (
            proc.stderr.strip()
            or f"evaluator exited with status {proc.returncode}"
        )
        emit("allow", f"dcg unavailable; fail-open: {reason}")
    else:
        emit("allow", "dcg unavailable; fail-open: invalid evaluator output")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
'''


def fail_config(message):
    print(f"agy-locked: {message}", file=sys.stderr)
    raise SystemExit(2)


def read_json(path, description):
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return {}
    except UnicodeDecodeError as exc:
        fail_config(f"{description} is not valid UTF-8: {path}: {exc}")
    except OSError as exc:
        fail_config(f"cannot read {description}: {path}: {exc}")
    if not text.strip():
        return {}
    try:
        value = json.loads(text)
    except json.JSONDecodeError as exc:
        fail_config(f"invalid {description}: {path}: {exc}")
    if not isinstance(value, dict):
        fail_config(f"{description} must contain a JSON object: {path}")
    return value


def write_text_if_changed(path, value, mode=None):
    # Atomic replacement must target the file behind a dotfiles-managed
    # symlink. Replacing the link itself would detach the live config from its
    # source of truth; a broken/looping link is ambiguous and must fail closed.
    try:
        if path.is_symlink():
            path = path.resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        fail_config(f"cannot resolve config symlink {path}: {exc}")

    try:
        path.parent.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        fail_config(f"cannot create config directory {path.parent}: {exc}")
    try:
        current = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        current = None
    except UnicodeDecodeError:
        current = None
    except OSError as exc:
        fail_config(f"cannot read existing config file {path}: {exc}")
    if current != value:
        # Write-then-rename so a launcher killed mid-write (tmux pane closed
        # while the finally-block re-pins the model) can never leave a
        # truncated settings.json that fails every later agy/gmi start.
        tmp_path = None
        try:
            # NamedTemporaryFile uses exclusive creation, so a stale or
            # attacker-planted path cannot redirect this write through a
            # symlink. Keep it beside the destination for an atomic replace.
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=path.parent,
                prefix=f".{path.name}.tmp-",
                delete=False,
            ) as tmp_file:
                tmp_path = pathlib.Path(tmp_file.name)
                tmp_file.write(value)
                tmp_file.flush()
                os.fsync(tmp_file.fileno())
                if mode is not None:
                    os.fchmod(tmp_file.fileno(), mode)
            os.replace(tmp_path, path)
        except OSError as exc:
            if tmp_path is not None:
                try:
                    tmp_path.unlink()
                except OSError:
                    pass
            fail_config(f"cannot write config file {path}: {exc}")
    if mode is not None:
        try:
            path.chmod(mode)
        except OSError as exc:
            fail_config(f"cannot set permissions on {path}: {exc}")


def write_json_if_changed(path, value):
    rendered = json.dumps(value, indent=2, sort_keys=False) + "\n"
    write_text_if_changed(path, rendered)


def ensure_settings():
    settings = read_json(SETTINGS_PATH, "Antigravity settings")
    settings.update(PINNED_SETTINGS)
    write_json_if_changed(SETTINGS_PATH, settings)


def ensure_hook_script():
    write_text_if_changed(DCG_HOOK, DCG_HOOK_SOURCE, 0o755)


def is_assignment(token):
    name, sep, _value = token.partition("=")
    return bool(sep and name and name.replace("_", "A").isalnum() and not name[0].isdigit())


def command_parts(tokens):
    index = 0
    while index < len(tokens) and is_assignment(tokens[index]):
        index += 1
    if index >= len(tokens):
        return "", []
    return tokens[index], tokens[index + 1 :]


def env_invokes_dcg(tokens, depth):
    index = 0
    while index < len(tokens):
        arg = tokens[index]
        if arg in {"--"}:
            index += 1
            break
        if is_assignment(arg):
            index += 1
            continue
        if arg in {"-i", "-0", "--ignore-environment", "--null"}:
            index += 1
            continue
        if arg in {"-u", "--unset", "-C", "--chdir"}:
            index += 2
            continue
        if arg in {"-S", "--split-string"}:
            if index + 1 >= len(tokens):
                return False
            try:
                split_tokens = shlex.split(tokens[index + 1])
            except ValueError:
                return False
            return tokens_invoke_dcg(split_tokens, depth)
        if arg.startswith("-u") and len(arg) > 2:
            index += 1
            continue
        if arg.startswith("--split-string="):
            try:
                split_tokens = shlex.split(arg.partition("=")[2])
            except ValueError:
                return False
            return tokens_invoke_dcg(split_tokens, depth)
        if arg.startswith("--unset=") or arg.startswith("--chdir="):
            index += 1
            continue
        if arg.startswith("-"):
            return False
        break
    return tokens_invoke_dcg(tokens[index:], depth) if index < len(tokens) else False


def shell_invokes_dcg(tokens, depth):
    index = 0
    while index < len(tokens):
        arg = tokens[index]
        if arg.startswith("-") and "c" in arg[1:]:
            if index + 1 >= len(tokens):
                return False
            try:
                script_args = shlex.split(tokens[index + 1])
            except ValueError:
                return False
            if script_args and script_args[0] == "exec":
                script_args = script_args[1:]
            return tokens_invoke_dcg(script_args, depth)
        index += 1
    return False


def tokens_invoke_dcg(tokens, depth=0):
    if depth > 4:
        return False

    executable_token, remaining = command_parts(tokens)
    if not executable_token:
        return False

    executable = pathlib.Path(os.path.expanduser(executable_token)).name
    if executable in {"dcg", "dcg-antigravity-hook.py"}:
        return True
    if executable == "env":
        return env_invokes_dcg(remaining, depth + 1)
    if executable in {"bash", "dash", "sh", "zsh"}:
        return shell_invokes_dcg(remaining, depth + 1)
    if executable.startswith("python"):
        return any(
            pathlib.Path(os.path.expanduser(arg)).name == "dcg-antigravity-hook.py"
            for arg in remaining
        )
    return False


def is_dcg_hook(hook):
    if not isinstance(hook, dict):
        return False
    command = hook.get("command")
    if not isinstance(command, str):
        return False
    try:
        tokens = shlex.split(command)
    except ValueError:
        return False
    return bool(tokens and tokens_invoke_dcg(tokens))


def without_dcg_pre_tool_hooks(group):
    if not isinstance(group, dict):
        return group

    pre_tool = group.get("PreToolUse")
    if not isinstance(pre_tool, list):
        return group

    kept_entries = []
    changed = False
    for entry in pre_tool:
        if not isinstance(entry, dict):
            kept_entries.append(entry)
            continue
        hooks_value = entry.get("hooks")
        if not isinstance(hooks_value, list):
            kept_entries.append(entry)
            continue

        non_dcg_hooks = [hook for hook in hooks_value if not is_dcg_hook(hook)]
        if len(non_dcg_hooks) == len(hooks_value):
            kept_entries.append(entry)
            continue

        changed = True
        if non_dcg_hooks:
            kept_entries.append({**entry, "hooks": non_dcg_hooks})

    if not changed:
        return group
    return {**group, "PreToolUse": kept_entries}


def ensure_dcg_hook():
    ensure_hook_script()
    hooks = read_json(HOOKS_PATH, "Antigravity hooks")

    # Native DCG releases and older ACFS versions used different group names
    # and matcher expressions. Remove only recognized DCG handlers from every
    # group, without interpreting peer regexes or collapsing their entries.
    for group_name, existing_group in list(hooks.items()):
        hooks[group_name] = without_dcg_pre_tool_hooks(existing_group)

    group = hooks.get("dcg")
    if not isinstance(group, dict):
        group = {}

    pre_tool = group.get("PreToolUse")
    if not isinstance(pre_tool, list):
        pre_tool = []

    acfs_dcg_entry = {
        "matcher": "run_command",
        "hooks": [
            {
                "type": "command",
                "command": str(DCG_HOOK),
                "timeout": HOOK_TIMEOUT_SECONDS,
            }
        ],
    }
    group["enabled"] = True
    group["PreToolUse"] = [
        acfs_dcg_entry,
        *pre_tool,
    ]
    hooks["dcg"] = group
    write_json_if_changed(HOOKS_PATH, hooks)


def filtered_args(argv):
    value_flags = {"--model", "-model", "-m"}
    pinned_bool_flags = {
        "--dangerously-skip-permissions",
        "-dangerously-skip-permissions",
        "--sandbox",
        "-sandbox",
    }
    result = []
    skip_next = False
    passthrough = False
    for arg in argv:
        if passthrough:
            result.append(arg)
            continue
        if skip_next:
            skip_next = False
            continue
        if arg == "--":
            passthrough = True
            result.append(arg)
            continue
        if arg in value_flags:
            skip_next = True
            continue
        if any(arg.startswith(f"{flag}=") for flag in value_flags):
            continue
        if arg in pinned_bool_flags:
            continue
        if any(arg.startswith(f"{flag}=") for flag in pinned_bool_flags):
            continue
        result.append(arg)
    return result


def run_real_agy(args):
    with subprocess.Popen(args) as proc:
        previous_handlers = {}
        for sig in (signal.SIGINT, signal.SIGQUIT):
            previous_handlers[sig] = signal.getsignal(sig)
            signal.signal(sig, signal.SIG_IGN)
        try:
            status = proc.wait()
        finally:
            for sig, handler in previous_handlers.items():
                signal.signal(sig, handler)
    return 128 - status if status < 0 else status


def main():
    if sys.argv[1:] == [PRIME_SETTINGS_FLAG]:
        ensure_settings()
        ensure_dcg_hook()
        return 0

    real_agy = resolve_real_agy()
    if not is_real_agy_candidate(real_agy):
        print(f"agy-locked: real agy binary is missing or unsafe: {real_agy}", file=sys.stderr)
        return 127

    ensure_settings()
    ensure_dcg_hook()

    args = [
        str(real_agy),
        "--model",
        MODEL,
        "--dangerously-skip-permissions",
        *filtered_args(sys.argv[1:]),
    ]
    try:
        return run_real_agy(args)
    finally:
        ensure_settings()
        ensure_dcg_hook()


if __name__ == "__main__":
    raise SystemExit(main())
