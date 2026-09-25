#!/usr/bin/env python3
"""Restore an ACFS module selection from a configuration export.

Run from a trusted ACFS checkout, including its normal install.sh. The export is
inert data, not an installer or a source of download URLs. Dependency resolution,
verification, checkpoints and installation remain owned by install.sh.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import signal
import stat
import subprocess
import sys
import tempfile
import time

LIMIT = 1024 * 1024
MAX_MODULES = 1024
MODULE_ID = re.compile(r"[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*")
SCHEMA = "acfs.config-import.v1"


class ImportConfigError(Exception):
    """An invalid export or a refused installer plan."""


def read_export(filename):
    if filename == "-":
        raw = sys.stdin.buffer.read(LIMIT + 1)
    else:
        # Do not block on a FIFO or read a device masquerading as a backup.
        fd = os.open(filename, os.O_RDONLY | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                raise ImportConfigError("The export must be a regular file or stdin (-).")
            raw = stream.read(LIMIT + 1)
    if len(raw) > LIMIT:
        raise ImportConfigError("The export exceeds the 1 MiB limit.")
    try:
        return raw.decode("utf-8-sig")
    except UnicodeError:
        raise ImportConfigError("The export must be UTF-8 text.") from None


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ImportConfigError("Duplicate JSON fields are not supported.")
        result[key] = value
    return result


def invalid_number(_value):
    raise ImportConfigError("Non-finite JSON numbers are not supported.")


def parse_export(text):
    """Return a canonical selection, never shell syntax from the export."""
    source_mode = None
    stripped = text.lstrip()
    if stripped.startswith(("{", "[")):
        try:
            data = json.loads(text, object_pairs_hook=unique_object,
                              parse_constant=invalid_number)
        except (ValueError, RecursionError):
            raise ImportConfigError("Invalid JSON configuration export.") from None
        if not isinstance(data, dict):
            raise ImportConfigError("A JSON export must be an object with a modules array.")
        modules = data.get("modules")
        settings = data.get("settings")
        if isinstance(settings, dict) and isinstance(settings.get("mode"), str):
            source_mode = settings["mode"]
        source_format = "json"
    else:
        modules = [line.strip() for line in text.splitlines()
                   if line.strip() and not line.lstrip().startswith("#")]
        source_format = "minimal"
    if not isinstance(modules, list) or not modules:
        raise ImportConfigError("The export contains no modules; refusing a full default install.")
    if len(modules) > MAX_MODULES:
        raise ImportConfigError("The export contains too many modules.")
    for module in modules:
        if not isinstance(module, str) or len(module) > 128 or not MODULE_ID.fullmatch(module):
            raise ImportConfigError("Invalid module ID. Use an export from acfs export-config --json or --minimal.")
    return {"modules": list(dict.fromkeys(modules)), "source_format": source_format,
            "source_mode": source_mode}


def installer_environment():
    # The normal installer also sanitizes these. Drop startup hooks before Bash
    # itself starts, not only after its first script line has already executed.
    return {key: value for key, value in os.environ.items()
            if key not in {"BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS"}
            and not key.startswith("BASH_FUNC_")}


def installer_command(selection, args):
    installer = Path(args.installer).expanduser().absolute()
    if installer.is_symlink() or not installer.is_file():
        raise ImportConfigError("Select a regular install.sh from a trusted ACFS checkout with --installer.")
    bash = next((path for path in ("/bin/bash", "/usr/bin/bash")
                 if os.access(path, os.X_OK)), None)
    if bash is None:
        raise ImportConfigError("A system Bash installation is required.")
    command = [bash, "--noprofile", "--norc", "-p", str(installer), "--mode", args.mode,
               "--skip-ubuntu-upgrade"]
    if args.yes:
        command.append("--yes")
    if args.resume:
        command.append("--resume")
    for module in selection["modules"]:
        command.extend(("--only", module))
    return command


def installer_plan(command, timeout):
    """Use the existing resolver; never duplicate its dependency graph here."""
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        process = subprocess.Popen(command + ["--print-plan"], stdin=subprocess.DEVNULL,
                                   stdout=out, stderr=err, env=installer_environment(),
                                   start_new_session=True)
        try:
            deadline = time.monotonic() + timeout
            while process.poll() is None:
                if time.monotonic() >= deadline:
                    raise ImportConfigError("Installer plan timed out; no installation was started.")
                if os.fstat(out.fileno()).st_size + os.fstat(err.fileno()).st_size > LIMIT:
                    raise ImportConfigError("Installer plan output exceeds 1 MiB.")
                time.sleep(0.02)
            out.seek(0)
            err.seek(0)
            stdout, stderr = out.read(LIMIT + 1), err.read(LIMIT + 1)
            if len(stdout) + len(stderr) > LIMIT:
                raise ImportConfigError("Installer plan output exceeds 1 MiB.")
            if process.returncode:
                raise ImportConfigError("Installer refused the module selection (exit %s).\n%s" %
                                        (process.returncode, (stderr or stdout).decode("utf-8", "replace")))
            return stdout.decode("utf-8", "replace"), stderr.decode("utf-8", "replace")
        finally:
            # Planning must not leave a timed-out downloader or helper running.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()


def main(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("export", help="JSON or minimal acfs export-config output; - reads stdin")
    parser.add_argument("--installer", default=str(Path(__file__).resolve().parent.parent / "install.sh"),
                        help="Trusted local installer (default: this checkout's install.sh)")
    parser.add_argument("--mode", choices=("safe", "vibe"), default="safe",
                        help="Destination mode, never inherited from the export (default: safe)")
    parser.add_argument("--apply", action="store_true", help="Run the installer after validating its plan")
    parser.add_argument("--yes", action="store_true", help="Explicitly allow the installer's non-interactive mode")
    parser.add_argument("--resume", action="store_true", help="Pass --resume to the existing checkpointed installer")
    parser.add_argument("--json", action="store_true", help="Emit the preview as JSON (not compatible with --apply)")
    parser.add_argument("--plan-timeout", type=int, choices=range(1, 301), default=60, metavar="1..300")
    args = parser.parse_args(arguments)
    if args.apply and args.json:
        parser.error("--json is preview-only; installer output is not an import JSON report")
    if args.apply and args.export == "-" and not args.yes:
        parser.error("--apply with stdin requires --yes, or save the export to a file for an interactive install")
    selection = parse_export(read_export(args.export))
    command = installer_command(selection, args)
    plan, diagnostics = installer_plan(command, args.plan_timeout)
    report = {"schema": SCHEMA, "status": "preview", **selection,
              "mode": args.mode, "upgrades_ubuntu": False, "restores_credentials": False,
              "pins_tool_versions": False, "uninstalls_extra_modules": False,
              "installer_argv": command, "installer_command": shlex.join(command),
              "installer_plan": plan, "installer_diagnostics": diagnostics}
    if args.json:
        print(json.dumps(report, ensure_ascii=True, indent=2))
        return 0
    print("ACFS module restore: %d selected module(s); destination mode: %s" %
          (len(selection["modules"]), args.mode))
    print("Credentials, source-host paths and recorded tool versions are not restored.")
    print("Ubuntu upgrades are disabled. Dependencies are resolved by the existing installer.")
    if diagnostics:
        print(diagnostics, file=sys.stderr, end="" if diagnostics.endswith("\n") else "\n")
    if plan:
        print(plan, end="" if plan.endswith("\n") else "\n")
    print("Installer command: " + shlex.join(command))
    if not args.apply:
        print("Preview only. Re-run this helper with --apply to install the selected modules.")
        return 0
    # Hand over rather than inventing a second supervisor or checkpoint format.
    # The installer's exit status, terminal and signal handling remain intact.
    sys.stdout.flush()
    sys.stderr.flush()
    os.execve(command[0], command, installer_environment())


def cli(arguments=None):
    try:
        return main(arguments)
    except (ImportConfigError, OSError) as exc:
        print("Error: " + str(exc), file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("Import interrupted before installation.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(cli())
