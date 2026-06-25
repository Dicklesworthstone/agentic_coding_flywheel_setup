#!/usr/bin/env python3
"""Launch Antigravity CLI with ACFS pinned defaults and dcg guard wiring."""

import json
import os
import pathlib
import signal
import shlex
import subprocess
import sys


MODEL = "Gemini 3.1 Pro (High)"
HOME = pathlib.Path.home()
REAL_AGY = HOME / ".local" / "bin" / "agy"
SETTINGS_PATH = HOME / ".gemini" / "antigravity-cli" / "settings.json"
HOOKS_PATH = HOME / ".gemini" / "config" / "hooks.json"
DCG_HOOK = HOME / ".gemini" / "config" / "hooks" / "dcg-antigravity-hook.py"
HOOK_TIMEOUT_SECONDS = 6
DCG_TIMEOUT_SECONDS = 4
PRIME_SETTINGS_FLAG = "--acfs-prime-settings"

PINNED_SETTINGS = {
    "allowNonWorkspaceAccess": True,
    "altScreenMode": "never",
    "artifactReviewPolicy": "always-proceed",
    "colorScheme": "terminal",
    "editor": "auto",
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


def emit(decision, reason=None):
    payload = {"decision": decision}
    if reason:
        payload["reason"] = reason
    print(json.dumps(payload), flush=True)


def extract_command(payload):
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
        emit("allow")
        return 0

    command = extract_command(payload)
    if not command:
        emit("allow")
        return 0

    dcg_bin = os.environ.get("DCG_BIN", os.path.expanduser("~/.local/bin/dcg"))
    try:
        proc = subprocess.run(
            [dcg_bin, "--robot", "test", command],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=DCG_TIMEOUT_SECONDS,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        emit("allow", f"dcg unavailable; fail-open: {exc}")
        return 0

    try:
        result = json.loads(proc.stdout) if proc.stdout.strip() else {}
    except json.JSONDecodeError:
        result = {}

    decision = result.get("decision")
    if proc.returncode == 1 or decision in {"deny", "block"}:
        reason = (
            result.get("reason")
            or result.get("explanation")
            or proc.stderr.strip()
            or "dcg blocked this command"
        )
        rule_id = result.get("rule_id")
        if rule_id:
            reason = f"{reason} ({rule_id})"
        emit("deny", f"Blocked by dcg: {reason}")
        return 0

    emit("allow")
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
        try:
            path.write_text(value, encoding="utf-8")
        except OSError as exc:
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


def ensure_dcg_hook():
    ensure_hook_script()
    hooks = read_json(HOOKS_PATH, "Antigravity hooks")
    group = hooks.get("dcg")
    if not isinstance(group, dict):
        group = {}

    pre_tool = group.get("PreToolUse")
    if not isinstance(pre_tool, list):
        pre_tool = []

    kept_entries = []
    run_command_hooks = []
    run_command_extras = {}
    for entry in pre_tool:
        if not isinstance(entry, dict):
            kept_entries.append(entry)
            continue
        if entry.get("matcher") != "run_command":
            kept_entries.append(entry)
            continue
        hooks_value = entry.get("hooks", [])
        if not isinstance(hooks_value, list):
            kept_entries.append(entry)
            continue
        if not run_command_extras:
            run_command_extras = {
                key: value
                for key, value in entry.items()
                if key not in {"matcher", "hooks"}
            }
        for hook in hooks_value:
            if not is_dcg_hook(hook):
                run_command_hooks.append(hook)

    run_command_hooks.insert(
        0,
        {
            "type": "command",
            "command": str(DCG_HOOK),
            "timeout": HOOK_TIMEOUT_SECONDS,
        },
    )
    group["enabled"] = True
    group["PreToolUse"] = [
        {
            **run_command_extras,
            "matcher": "run_command",
            "hooks": run_command_hooks,
        },
        *kept_entries,
    ]
    hooks["dcg"] = group
    write_json_if_changed(HOOKS_PATH, hooks)


def filtered_args(argv):
    value_flags = {"--model", "-model"}
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

    if not REAL_AGY.exists():
        print(f"agy-locked: real agy binary not found: {REAL_AGY}", file=sys.stderr)
        return 127

    ensure_settings()
    ensure_dcg_hook()

    args = [
        str(REAL_AGY),
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
