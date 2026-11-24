#!/usr/bin/env python3
"""Bind NTM's managed provider commands to the selected ACFS installation.

The original TOML is retained before an atomic update. Only recognized native
defaults or exact commands generated here are managed; arbitrary shell commands
are never rewritten. Provider execution uses Python's standard library and the
installed ACFS state reader.
"""
import argparse
import base64
import datetime
import fcntl
import json
import math
import os
from pathlib import Path
import pwd
import re
import signal
import stat
import subprocess
import sys
import tempfile
import time

LIMIT = 1024 * 1024
MARKER = "{{/* ACFS agent policy v1 "
MODULES = {
    "claude": "agents.claude", "codex": "agents.codex",
    "agy": "agents.antigravity", "gemini": "agents.gemini",
    "grok": "agents.grok", "omp": "agents.omp",
    "opencode": "agents.opencode", "pi": "stack.pi_agent_rust",
}
KEYS = {"claude": "claude", "codex": "codex", "agy": "antigravity",
        "gemini": "gemini", "grok": "grok", "omp": "omp", "opencode": "oc"}
PERMISSIONS = {
    "claude": "--dangerously-skip-permissions",
    "codex": "--dangerously-bypass-approvals-and-sandbox",
    "gemini": "--yolo", "grok": "--always-approve", "omp": "--auto-approve",
}
# Model, effort and persona references must remain actual Go-template actions,
# so NTM's own unsupported-override guards and Claude hook injection still work.
MODEL = "{{if .Model}} --model {{shellQuote .Model}}{{end}}"
PERSONA = "{{if .SystemPromptFile}} --system-prompt-file {{shellQuote .SystemPromptFile}}{{end}}"
CLAUDE_HOOKS = "{{if .ClaudeSettings}} --settings {{shellQuote .ClaudeSettings}}{{end}}"
CODEX_ARGS = ' -m {{shellQuote (.Model | default "gpt-6.2-sol")}} -c model_reasoning_effort={{shellQuote (.ReasoningEffort | default "xhigh")}} -c model_reasoning_summary_format=experimental'
PI_COMMAND = "pi" + MODEL + "{{if .ReasoningEffort}} --thinking {{shellQuote .ReasoningEffort}}{{end}}{{if .SystemPromptFile}} --append-system-prompt {{shellQuote .SystemPromptFile}}{{end}}"

# style -> (provider, prefix, executable, arguments, permission flag placement)
STYLES = {
    "claude": ("claude", "{{memLimitPrefix}} ", "claude",
               MODEL + ' --effort {{shellQuote (.ReasoningEffort | default "xhigh")}}' + PERSONA, "before"),
    "codex": ("codex", '{{if .SystemPromptFile}}CODEX_SYSTEM_PROMPT="$(/bin/cat {{shellQuote .SystemPromptFile}})" {{end}}',
              "codex", CODEX_ARGS + " --search", "before"),
    "codex-acfs": ("codex", '{{if .SystemPromptFile}}CODEX_SYSTEM_PROMPT="$(cat {{shellQuote .SystemPromptFile}})" {{end}}',
                   "codex", " --search" + CODEX_ARGS, "before"),
    "gemini": ("gemini", "{{if .SystemPromptFile}}GEMINI_SYSTEM_MD={{shellQuote .SystemPromptFile}} {{end}}",
               "gemini", MODEL, "after"),
    "gemini-acfs": ("agy", "", "agy-locked", MODEL, ""),
    "agy": ("agy", "", "{{agyBinary}}",
            ' --model {{shellQuote .Model}}{{if .SystemPromptFile}} --prompt-interactive "$(/bin/cat {{shellQuote .SystemPromptFile}})"{{end}}', "before"),
    "grok": ("grok", "", "grok", MODEL + "{{if .ReasoningEffort}} --effort {{shellQuote .ReasoningEffort}}{{end}}", "before"),
    "omp": ("omp", "", "omp", MODEL + "{{if .ReasoningEffort}} --thinking {{shellQuote .ReasoningEffort}}{{end}}{{if .SystemPromptFile}} --append-system-prompt {{shellQuote .SystemPromptFile}}{{end}}", "before"),
    "opencode": ("opencode", "", "opencode", MODEL, ""),
}
for _provider, _command in (("claude", "claude"), ("codex", "codex"),
                           ("gemini", "gemini"), ("agy", "agy-locked"),
                           ("grok", "grok"), ("omp", "omp"), ("opencode", "opencode")):
    STYLES[_provider + "-simple"] = (_provider, "", _command, "", "before")

PROJECT_ENV = {
    "GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE",
    "GIT_IMPLICIT_WORK_TREE", "GIT_GRAFT_FILE", "GIT_REPLACE_REF_BASE", "GIT_PREFIX",
    "GIT_SHALLOW_FILE", "GIT_SUPER_PREFIX", "GIT_INTERNAL_SUPER_PREFIX",
    "GIT_CEILING_DIRECTORIES", "GIT_DISCOVERY_ACROSS_FILESYSTEM",
    "GIT_CONFIG", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",
    "BEADS_DB", "BD_DB", "BD_DATABASE", "BEADS_JSONL", "BEADS_CACHE_DIR",
}

class PolicyError(Exception):
    pass

def absolute(value, label):
    if not isinstance(value, str) or not value.startswith("/") or value == "/" or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise PolicyError(label + " must be an absolute, non-root path without control characters")
    value.encode("utf-8")
    return value

def read_regular(path, missing=False):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    except FileNotFoundError:
        if missing:
            return None
        raise
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode):
            raise PolicyError("not a regular file: " + str(path))
        data = stream.read(LIMIT + 1)
    if len(data) > LIMIT:
        raise PolicyError("configuration exceeds the one-MiB limit: " + str(path))
    return data, info

def unchanged_file(previous, current):
    if previous is None or current is None:
        return previous is current
    attributes = ("st_dev", "st_ino", "st_mode", "st_uid", "st_gid", "st_mtime_ns")
    return previous[0] == current[0] and all(
        getattr(previous[1], attribute) == getattr(current[1], attribute) for attribute in attributes)

def validate_catalog(modules):
    # Use the same data-only catalogue reader as the installer and guided
    # launch. The already parsed checkpoint supplies the list, so a second
    # file read cannot mix a new permission mode with an old module selection.
    library = str(Path(__file__).resolve().parent)
    script = '''
source "$1/state.sh" || exit 1
catalog="$1/../generated/manifest_index.sh"
shift
ACFS_STATE_SELECTION_MODE=scoped
ACFS_STATE_SELECTED_MODULES=("$@")
state_validate_module_selection_catalog_file "$catalog"
'''
    environment = os.environ.copy()
    environment["PATH"] = "/usr/sbin:/usr/bin:/sbin:/bin"
    try:
        result = subprocess.run(["/bin/bash", "--noprofile", "--norc", "-p", "-c", script,
                                 "acfs-ntm-policy", library, *modules],
                                env=environment, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    except subprocess.TimeoutExpired as error:
        raise PolicyError("ACFS module catalogue validation timed out") from error
    if result.returncode:
        raise PolicyError("saved module selection cannot be validated against the installed ACFS catalogue; run acfs doctor")

def installation(binding, provider=None):
    home = absolute(binding["home"], "target home")
    state_file = absolute(binding["state"], "checkpoint")
    user = binding["user"]
    if pwd.getpwuid(os.geteuid()).pw_name != user:
        raise PolicyError("the selected installation belongs to a different account")
    canonical = state_file == str(Path(home) / ".acfs/state.json")
    loaded = read_regular(state_file, missing=canonical and binding["legacy"])
    if loaded is None:
        return "vibe", True
    state = json.loads(loaded[0])
    if not isinstance(state, dict):
        raise PolicyError("checkpoint must contain one object")
    for key, expected in (("target_home", home), ("target_user", user)):
        if (not canonical or key in state) and state.get(key) != expected:
            raise PolicyError("checkpoint does not belong to the selected account")
    mode = state.get("mode", "safe")
    if mode not in ("safe", "vibe"):
        raise PolicyError("invalid saved installation mode")
    if "module_selection" in state:
        scope = state["module_selection"]
        if not isinstance(scope, dict) or type(scope.get("schema_version")) not in (int, float) or scope["schema_version"] != 1:
            raise PolicyError("unsupported module selection")
        modules = scope.get("selected_modules")
        if not isinstance(modules, list) or not modules or any(
                not isinstance(m, str) or not re.fullmatch(r"[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+", m) for m in modules):
            raise PolicyError("invalid selected_modules")
        if len(set(modules)) != len(modules):
            raise PolicyError("duplicate selected_modules")
        requested = scope.get("requested_modules", [])
        if not isinstance(requested, list) or any(not isinstance(m, str) or m not in modules for m in requested):
            raise PolicyError("invalid requested_modules")
        if len(set(requested)) != len(requested):
            raise PolicyError("duplicate requested_modules")
        validate_catalog(modules)
        if "stack.ntm" not in modules:
            raise PolicyError("NTM is no longer selected for this installation")
        if provider and MODULES[provider] not in modules:
            raise PolicyError(provider + " is no longer selected for this installation")
    return mode, False

def toml_parser():
    try:
        import tomllib
        return tomllib
    except ImportError:
        try:
            import tomli
            return tomli
        except ImportError:
            try:
                from pip._vendor import tomli
                return tomli
            except ImportError as error:
                raise PolicyError("NTM policy setup requires Python 3.11+ or an already installed tomli parser; open an agent directly until it is available") from error

def quoted(value):
    return json.dumps(value, ensure_ascii=False).replace("\x7f", "\\u007f")

def toml_value(value):
    if isinstance(value, str):
        return quoted(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, (datetime.datetime, datetime.date, datetime.time)):
        return value.isoformat()
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(v) for v in value) + "]"
    if isinstance(value, dict):
        return "{ " + ", ".join(quoted(k) + " = " + toml_value(v) for k, v in value.items()) + " }"
    raise PolicyError("unsupported TOML value: " + type(value).__name__)

def equivalent(left, right):
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(equivalent(left[k], right[k]) for k in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(equivalent(a, b) for a, b in zip(left, right))
    if isinstance(left, float) and math.isnan(left):
        return math.isnan(right)
    return left == right

def encode_toml(data, parser):
    text = "# NTM provider defaults managed by ACFS; original retained beside this file.\n"
    text += "".join(quoted(k) + " = " + toml_value(v) + "\n" for k, v in data.items())
    if not equivalent(data, parser.loads(text)):
        raise PolicyError("cannot preserve NTM configuration values")
    return text.encode("utf-8")

def native_command(style, permissions):
    provider, prefix, executable, suffix, placement = STYLES[style]
    flag = PERMISSIONS.get(provider, "--dangerously-skip-permissions" if provider == "agy" else "") if permissions else ""
    permission = " " + flag if flag and placement else ""
    if style == "agy" and permissions:
        return executable + ' --model {{shellQuote .Model}} --dangerously-skip-permissions{{if .SystemPromptFile}} --prompt-interactive "$(/bin/cat {{shellQuote .SystemPromptFile}})"{{end}}'
    return prefix + executable + (permission if placement == "before" else "") + suffix + (permission if placement == "after" else "")

def shell_literal(value):
    return "{{shellQuote " + quoted(value) + "}}"

def validate_binding(binding):
    expected = {"schema", "home", "user", "state", "runtime", "bin_dir", "legacy", "provider", "binary", "python", "helper", "style", "vibe"}
    if not isinstance(binding, dict) or set(binding) != expected or type(binding["schema"]) is not int or binding["schema"] != 1:
        raise PolicyError("invalid managed command binding")
    if type(binding["legacy"]) is not bool or type(binding["vibe"]) is not bool:
        raise PolicyError("invalid managed command policy")
    if binding["style"] not in STYLES or binding["provider"] != STYLES[binding["style"]][0]:
        raise PolicyError("invalid managed provider")
    if not isinstance(binding["user"], str) or not re.fullmatch(r"[a-z_][a-z0-9_-]*[$]?", binding["user"]):
        raise PolicyError("invalid target user")
    for key in ("home", "state", "runtime", "bin_dir", "python", "helper"):
        absolute(binding[key], key)
    if binding["binary"]:
        absolute(binding["binary"], "provider executable")
    elif not isinstance(binding["binary"], str):
        raise PolicyError("invalid provider executable")

def managed_command(binding):
    validate_binding(binding)
    encoded = json.dumps(binding, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    marker = base64.urlsafe_b64encode(encoded.encode()).decode()
    provider, prefix, _, suffix, _ = STYLES[binding["style"]]
    command = (MARKER + marker + " */}}" + prefix + shell_literal(binding["python"]) +
               " -I " + shell_literal(binding["helper"]) + " launch --binding " +
               shell_literal(encoded) + " --" + suffix)
    if provider == "claude":
        command += CLAUDE_HOOKS
    return command

def existing_managed(command):
    if not command.startswith(MARKER):
        return None
    close = command.find(" */}}", len(MARKER))
    if close < 0:
        return None
    encoded = command[len(MARKER):close]
    if not re.fullmatch(r"[A-Za-z0-9_=-]+", encoded):
        return None
    try:
        binding = json.loads(base64.urlsafe_b64decode(encoded))
        if managed_command(binding) != command:
            return None
        return binding
    except (ValueError, TypeError, KeyError, UnicodeError, PolicyError):
        return None

def recognized(command, key):
    managed = existing_managed(command)
    if managed:
        actual = STYLES[managed["style"]][0]
        if actual == key or key == "gemini" and managed["style"] == "gemini-acfs":
            return managed["style"], managed["vibe"]
        return None
    for style, (provider, _, _, _, _) in STYLES.items():
        if provider != key and not (key == "gemini" and style == "gemini-acfs"):
            continue
        for permissions in (False, True):
            # agy-locked follows the checkpoint itself. Converting a native
            # command with approval bypass deliberately removed would restore
            # bypass in Vibe, so keep that explicit override as custom.
            if style == "agy" and not permissions:
                continue
            if command == native_command(style, permissions):
                return style, permissions
    return None

def config_path(args):
    explicit = os.environ.get("NTM_CONFIG")
    if explicit:
        path = explicit
        if path == "~" or path.startswith("~/"):
            path = args.target_home + path[1:]
    else:
        base = os.environ.get("XDG_CONFIG_HOME") or str(Path(args.target_home) / ".config")
        path = str(Path(base) / "ntm/config.toml")
    path = os.path.abspath(os.path.join(args.project, path))
    return Path(absolute(path, "NTM config")), bool(explicit)

def selected_pi_is_safe(path, parser, mode):
    found = []
    plugin_dir = path.parent / "agents"
    if not plugin_dir.exists():
        return
    for candidate in sorted(plugin_dir.glob("*.toml")):
        # NTM loads plugins in filename order; don't infer a safe command from
        # only pi.toml when another plugin file declares the same native name.
        target = candidate.resolve(strict=True)
        parsed = parser.loads(read_regular(target)[0].decode("utf-8"))
        agent = parsed.get("agent", {})
        if not isinstance(agent, dict):
            raise PolicyError("invalid NTM plugin: " + str(candidate))
        name = agent.get("name", candidate.stem)
        alias = agent.get("alias", "")
        if not isinstance(name, str) or not isinstance(alias, str):
            raise PolicyError("invalid NTM plugin identity: " + str(candidate))
        if name.strip().lower() == "pi" or alias.strip().lower() == "pi":
            if name != "pi":
                raise PolicyError("a custom plugin shadows Pi; restore its native name before using the guided Pi workspace")
            if mode == "safe" and agent.get("env"):
                raise PolicyError("custom Pi plugin environment is unchanged and cannot be verified for Safe mode; open Pi directly")
            found.append(agent.get("command"))
    if len(found) > 1 or mode == "safe" and found and found[0] not in ("pi", PI_COMMAND):
        raise PolicyError("custom Pi plugin is unchanged; use the shipped Pi command or open Pi directly for Safe mode")

def bounded_validate(ntm, path, project, home):
    environment = os.environ.copy()
    environment["HOME"] = home
    environment["NTM_CONFIG"] = str(path)
    process = subprocess.Popen([ntm, "--config", str(path), "--json", "config", "validate"],
                               cwd=project, env=environment, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            process.communicate(timeout=1)
        except subprocess.TimeoutExpired:
            process.stdout.close()
            process.stderr.close()
        raise PolicyError("NTM config validation timed out; no provider was started")
    try:
        report = json.loads(stdout)
    except (ValueError, UnicodeError) as error:
        raise PolicyError("NTM did not return a valid config-validation result; update NTM or run ntm config validate") from error
    if process.returncode or not isinstance(report, dict) or report.get("success", True) is not True or report.get("valid") is not True:
        # Config diagnostics can contain credentials or command text. Let the
        # native interactive command display them; do not echo them here.
        raise PolicyError("NTM rejected its configuration; run ntm config validate before starting agents")

def build_configuration(args, parser, source, binding):
    data = parser.loads(source.decode("utf-8")) if source is not None else {}
    if not isinstance(data.get("agents", {}), dict):
        raise PolicyError("NTM agents configuration must be a table")
    agents = data.setdefault("agents", {})
    binaries = {}
    for entry in args.binary:
        provider, separator, binary = entry.partition("=")
        if not separator or provider not in MODULES or provider in binaries:
            raise PolicyError("invalid provider executable mapping")
        if binary:
            absolute(binary, "provider executable")
        binaries[provider] = binary
    mode, legacy = installation(binding)
    binding["legacy"] = legacy
    for provider, key in KEYS.items():
        configured = agents.get(key)
        if configured is None or configured == "":
            style, vibe = provider, provider in PERMISSIONS
        elif isinstance(configured, str):
            previous = existing_managed(configured)
            if previous and not previous["legacy"] and legacy and all(
                    previous[field] == binding[field] for field in ("state", "home", "user")):
                raise PolicyError("the previously configured installation checkpoint is missing; restore it before starting NTM")
            match = recognized(configured, provider)
            if match is None:
                if mode == "safe" and (provider in args.agent or binaries.get(provider)):
                    raise PolicyError("custom agents." + key + " is unchanged and cannot be verified for Safe mode; remove that override to use ACFS defaults, or open the agent directly")
                continue
            style, vibe = match
        else:
            raise PolicyError("agents." + key + " must be a command string")
        actual_provider = STYLES[style][0]
        if provider in args.agent:
            installation(binding, actual_provider)
        current = dict(binding, provider=actual_provider, binary=binaries.get(actual_provider, ""),
                       style=style, vibe=vibe)
        agents[key] = managed_command(current)
    if "pi" in args.agent or mode == "safe" and binaries.get("pi"):
        selected_pi_is_safe(args.config_path, parser, mode)
    return data

def configure(args):
    parser = toml_parser()
    original, explicit = config_path(args)
    args.config_path = original
    # Preserve dotfile-manager symlinks: update the verified regular target,
    # while NTM continues to use the original directory for state and plugins.
    target = Path(os.path.realpath(original))
    current = read_regular(target, missing=not explicit)
    source = current[0] if current else None
    if current and current[1].st_uid != os.geteuid():
        raise PolicyError("NTM config belongs to another account")
    binding = {
        "schema": 1, "home": args.target_home, "user": args.target_user,
        "state": args.state_file, "legacy": True, "provider": "claude",
        "runtime": str(Path(__file__).resolve().parents[2]),
        "bin_dir": str(Path(args.target_home) / ".local/bin"),
        "binary": "", "python": str(Path(sys.executable).absolute()),
        "helper": str(Path(__file__).resolve()), "style": "claude", "vibe": True,
    }
    validate_binding(binding)
    saved = read_regular(args.state_file, missing=args.state_file == str(Path(args.target_home) / ".acfs/state.json"))
    if saved:
        state = json.loads(saved[0])
        if isinstance(state, dict) and state.get("bin_dir"):
            binding["bin_dir"] = absolute(state["bin_dir"], "saved executable directory")
    planned = build_configuration(args, parser, source, binding)
    ntm = absolute(args.ntm_binary, "NTM executable")
    bounded_validate(ntm, original, args.project, args.target_home)
    if args.operation == "check":
        return
    if source is not None and equivalent(parser.loads(source.decode("utf-8")), planned):
        print(original)
        return
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock_fd = os.open(str(target) + ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    with os.fdopen(lock_fd, "a+b") as lock:
        info = os.fstat(lock.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
            raise PolicyError("unsafe NTM configuration lock")
        deadline = time.monotonic() + 5
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise PolicyError("NTM configuration is busy; retry after its writer finishes")
                time.sleep(0.01)
        latest = read_regular(target, missing=source is None)
        if Path(os.path.realpath(original)) != target or not unchanged_file(current, latest):
            raise PolicyError("NTM config changed during setup; retry without overwriting the other edit")
        rendered = encode_toml(planned, parser)
        fd, stage = tempfile.mkstemp(prefix=original.name + ".acfs-policy-", suffix=".toml", dir=original.parent)
        with os.fdopen(fd, "wb") as output:
            output.write(rendered)
            output.flush()
            os.fsync(output.fileno())
        # Validate with NTM's own strict reader in the same state/plugin
        # directory before either replacing its config or creating a task.
        bounded_validate(ntm, Path(stage), args.project, args.target_home)
        if original.parent.resolve() != target.parent.resolve():
            # Keep the native validation beside the selected path so plugin
            # and state lookup stay authoritative, then stage the identical
            # bytes beside a symlink target for an atomic same-filesystem move.
            fd, stage = tempfile.mkstemp(prefix=target.name + ".acfs-policy-", suffix=".toml", dir=target.parent)
            with os.fdopen(fd, "wb") as output:
                output.write(rendered)
                output.flush()
                os.fsync(output.fileno())
        if source is not None:
            backup_fd, backup = tempfile.mkstemp(prefix=target.name + ".acfs-before-policy-", dir=target.parent)
            with os.fdopen(backup_fd, "wb") as output:
                output.write(source)
                output.flush()
                os.fsync(output.fileno())
            os.chown(stage, -1, current[1].st_gid)
            os.chmod(stage, stat.S_IMODE(current[1].st_mode))
            print("NTM original configuration retained at " + backup, file=sys.stderr)
        # Native NTM writers use this same resolved-path flock. Recheck other
        # editors as well; files written for diagnosis are deliberately retained.
        latest = read_regular(target, missing=source is None)
        if Path(os.path.realpath(original)) != target or not unchanged_file(current, latest):
            raise PolicyError("NTM config changed before replacement; original edit preserved")
        os.replace(stage, target)
    print(original)

def launch(args):
    binding = json.loads(args.binding)
    validate_binding(binding)
    provider = binding["provider"]
    mode, _ = installation(binding, provider)
    binary = binding["binary"]
    if not binary or not Path(binary).is_file() or not os.access(binary, os.X_OK):
        raise PolicyError(provider + " has no configured executable; run acfs newproj again after installing it")
    argv = args.arguments
    if argv[:1] == ["--"]:
        argv = argv[1:]
    permissions = []
    if binding["vibe"] and mode == "vibe" and provider in PERMISSIONS:
        permissions = [PERMISSIONS[provider]]
    environment = {key: value for key, value in os.environ.items()
                   if key not in PROJECT_ENV and not re.fullmatch(r"GIT_CONFIG_(?:KEY|VALUE)_[0-9]+", key)}
    environment.update(HOME=binding["home"], TARGET_HOME=binding["home"],
                       TARGET_USER=binding["user"], ACFS_STATE_FILE=binding["state"],
                       USER=binding["user"], LOGNAME=binding["user"],
                       ACFS_HOME=binding["runtime"], ACFS_BIN_DIR=binding["bin_dir"],
                       BEADS_DIR=str(Path.cwd() / ".beads"))
    if provider == "agy":
        environment["ACFS_BIN_DIR"] = str(Path(binary).parent)
    os.execve(binary, [binary, *permissions, *argv], environment)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="operation", required=True)
    commands.add_parser("parser")
    for operation in ("check", "configure"):
        command = commands.add_parser(operation)
        command.add_argument("--project", required=True)
        command.add_argument("--state-file", required=True)
        command.add_argument("--target-home", required=True)
        command.add_argument("--target-user", required=True)
        command.add_argument("--ntm-binary", required=True)
        command.add_argument("--binary", action="append", default=[])
        command.add_argument("--agent", choices=tuple(MODULES), action="append", default=[])
    command = commands.add_parser("launch")
    command.add_argument("--binding", required=True)
    command.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        if args.operation == "parser":
            toml_parser()
        elif args.operation == "launch":
            launch(args)
        else:
            configure(args)
    except (PolicyError, OSError, ValueError, UnicodeError, KeyError) as error:
        print("ACFS NTM policy: " + str(error), file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

