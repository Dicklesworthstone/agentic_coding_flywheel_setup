#!/usr/bin/python3 -I
"""Install and run a versioned ACFS fleet controller cohort without a checkout.

Installation is explicit and offline. Controllers keep their existing preview,
approval, SSH and journal rules. This command never adds execution authority.
"""
import argparse
import ast
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys

SCHEMA = "acfs.fleet-runtime.v2"
LEGACY_SCHEMA = "acfs.fleet-runtime.v1"
PLAN_SCHEMA = "acfs.fleet-runtime-install.v1"
COMMANDS = {name: "swarm-fleet-" + name + ".py" for name in ("launch", "prepare", "dispatch", "status")}
FILES = tuple(sorted(("acfs-fleet.py", *COMMANDS.values())))
# Fixed role sets, not arbitrary paths or optional files from an untrusted
# manifest. Retained v1 runtimes have no observer; never rewrite their contents.
FILES_BY_SCHEMA = {
    LEGACY_SCHEMA: tuple(name for name in FILES if name != COMMANDS["status"]),
    SCHEMA: FILES,
}
LIMIT = 1024 * 1024
MANIFEST = "runtime.json"
ENTRY = Path(__file__).resolve(strict=True)


class Refused(Exception):
    """Only fixed codes cross the CLI error boundary."""


def require(value, code):
    if not value:
        raise Refused(code)


def encode(value):
    return (json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(",", ":")) + "\n").encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def decode(raw):
    require(len(raw) <= LIMIT, "manifest_too_large")
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "duplicate_manifest_key")
            result[key] = value
        return result
    try:
        return json.loads(raw.decode("utf-8"), object_pairs_hook=unique,
                          parse_constant=lambda _: require(False, "invalid_manifest_number"))
    except (ValueError, UnicodeError, RecursionError):
        raise Refused("invalid_manifest") from None


def path_arg(value):
    require(isinstance(value, str) and value and not re.search(r"[\x00-\x1f\x7f]", value), "invalid_path")
    return Path(os.path.abspath(os.path.expanduser(value)))


@contextmanager
def directory(path, owned=False, private=False):
    """Open each component without following links; retain the final descriptor."""
    path = path_arg(str(path))
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
            info = os.fstat(fd)
            sticky = info.st_uid == 0 and bool(info.st_mode & stat.S_ISVTX)
            require(info.st_uid in (0, os.geteuid()) and (not info.st_mode & 0o022 or sticky), "unsafe_directory")
        info = os.fstat(fd)
        if owned:
            require(info.st_uid == os.geteuid() and not info.st_mode & 0o022, "directory_not_owned_or_writable")
        if private:
            require(not info.st_mode & 0o077, "runtime_directory_not_private")
        yield fd
    finally:
        os.close(fd)


def read_file(fd, name, installed=False):
    handle = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    with os.fdopen(handle, "rb") as stream:
        info = os.fstat(stream.fileno())
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                and info.st_uid in (0, os.geteuid()) and not info.st_mode & 0o022, "unsafe_runtime_file")
        if installed:
            require(not info.st_mode & 0o277, "runtime_file_not_read_only_private")
        raw = stream.read(LIMIT + 1)
        require(0 < len(raw) <= LIMIT, "runtime_file_size_limit")
        return raw


def snapshot(root, installed=False, schema=SCHEMA):
    with directory(root, private=installed) as fd:
        data = {name: read_file(fd, name, installed) for name in FILES_BY_SCHEMA[schema]}
        for name, raw in data.items():
            try:
                ast.parse(raw.decode("utf-8"), filename=name)
            except (SyntaxError, UnicodeError, ValueError, RecursionError):
                raise Refused("invalid_controller_source") from None
    manifest = {"schema": schema, "files": {name: {"sha256": sha(raw), "bytes": len(raw)}
                                            for name, raw in data.items()}}
    return data, manifest, sha(encode(manifest))


def manifest_layout(manifest):
    require(type(manifest) is dict and set(manifest) == {"schema", "files"}
            and type(manifest["schema"]) is str and manifest["schema"] in FILES_BY_SCHEMA,
            "unsupported_runtime_manifest")
    files = FILES_BY_SCHEMA[manifest["schema"]]
    require(type(manifest["files"]) is dict and set(manifest["files"]) == set(files),
            "runtime_role_mismatch")
    for entry in manifest["files"].values():
        require(type(entry) is dict and set(entry) == {"sha256", "bytes"}
                and type(entry["sha256"]) is str and re.fullmatch(r"[a-f0-9]{64}", entry["sha256"])
                and type(entry["bytes"]) is int and 0 < entry["bytes"] <= LIMIT,
                "invalid_runtime_file_metadata")
    return files


def runtime_commands(manifest):
    return [command for command, name in COMMANDS.items() if name in manifest["files"]]


def verify(root):
    root = path_arg(str(root))
    with directory(root, private=True) as fd:
        raw = read_file(fd, MANIFEST, True)
        saved = decode(raw)
        files = manifest_layout(saved)
        data, manifest, release = snapshot(root, installed=True, schema=saved["schema"])
        with directory(root, private=True) as current:
            require(os.path.samestat(os.fstat(fd), os.fstat(current)), "runtime_directory_changed")
        require(set(os.listdir(fd)) == set(files) | {MANIFEST}, "unexpected_runtime_members")
        require(read_file(fd, MANIFEST, True) == raw and encode(saved) == encode(manifest),
                "runtime_integrity_mismatch")
    require(root.name == release and root.parent.name == "releases", "runtime_release_mismatch")
    return data, manifest, release


def source_snapshot():
    root = ENTRY.parent
    # A release must never turn into checkout mode because its manifest vanished.
    if root.parent.name == "releases" or os.path.lexists(root / MANIFEST):
        return verify(root)
    return snapshot(root)


def installed_releases():
    require(ENTRY.parent.parent.name == "releases", "installed_runtime_required")
    verify(ENTRY.parent)
    return ENTRY.parent.parent


def list_runtimes():
    releases = installed_releases()
    result = []
    with directory(releases, owned=True, private=True) as fd:
        names = sorted(os.listdir(fd))
        require(len(names) <= 1024, "runtime_inventory_limit")
        for name in names:
            # Do not read unrelated members or follow links into other stores.
            if re.fullmatch(r"[a-f0-9]{64}", name) is None:
                raise Refused("unexpected_release_member")
            row = {"runtime": name, "current": name == ENTRY.parent.name, "status": "verified", "commands": []}
            try:
                _, manifest, _ = verify(releases / name)
                row["commands"] = runtime_commands(manifest)
            except (Refused, OSError):
                row["status"] = "unavailable"
            result.append(row)
    return {"schema": SCHEMA, "runtimes": result}


def select_runtime(args):
    require(len(args) >= 3 and re.fullmatch(r"[a-f0-9]{64}", args[1]) is not None,
            "explicit_runtime_id_and_command_required")
    require(args[2] in COMMANDS or args[2] == "version", "runtime_selection_is_execution_only")
    releases = installed_releases()
    selected = releases / args[1]
    _, manifest, _ = verify(selected)
    require(args[2] == "version" or args[2] in runtime_commands(manifest), "runtime_command_unavailable")
    # Use the retained frontend too, not just a subset of old controller files.
    # No symlink or journal is updated and no fallback runtime is selected.
    os.execv(sys.executable, [sys.executable, "-I", str(selected / "acfs-fleet.py"), *args[2:]])


def current_link(bin_fd, prefix):
    try:
        info = os.stat("acfs-fleet", dir_fd=bin_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    require(stat.S_ISLNK(info.st_mode) and info.st_uid == os.geteuid(), "unmanaged_launcher_exists")
    target = os.readlink("acfs-fleet", dir_fd=bin_fd)
    path = Path(target)
    require(path.is_absolute() and path.name == "acfs-fleet.py"
            and path.parent.parent == prefix / "releases", "unmanaged_launcher_exists")
    verify(path.parent)
    return target


def identity(fd):
    info = os.fstat(fd)
    return [info.st_dev, info.st_ino]


def assert_path(fd, path):
    with directory(path, owned=True) as fresh:
        require(identity(fd) == identity(fresh), "installation_directory_changed")


def install_plan(prefix, bin_dir, manifest, release):
    require(prefix != bin_dir and prefix not in bin_dir.parents and bin_dir not in prefix.parents,
            "overlapping_installation_directories")
    with directory(prefix, owned=True) as store, directory(bin_dir, owned=True) as bin_fd:
        target = prefix / "releases" / release
        if os.path.lexists(prefix / "releases"):
            with directory(prefix / "releases", owned=True, private=True):
                pass
        if os.path.lexists(target):
            verify(target)
        prior = current_link(bin_fd, prefix)
        return {"schema": PLAN_SCHEMA, "prefix": str(prefix), "bin_directory": str(bin_dir),
                "prefix_identity": identity(store), "bin_identity": identity(bin_fd),
                "runtime": release, "files": manifest["files"], "previous_launcher": prior,
                "launcher": str(target / "acfs-fleet.py"),
                "network_access": False, "starts_agents": False, "sends_prompts": False}


def publish(fd, name, raw, mode):
    handle = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode, dir_fd=fd)
    with os.fdopen(handle, "wb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


def install(prefix, bin_dir, approval=None):
    require(sys.platform == "linux", "linux_runtime_required")
    require(os.getuid() == os.geteuid() and os.geteuid() != 0 and not os.environ.get("SUDO_USER"),
            "install_as_target_user_without_sudo")
    data, manifest, release = source_snapshot()
    plan = install_plan(prefix, bin_dir, manifest, release)
    plan_hash = sha(encode(plan))
    if approval is None:
        return {"status": "preview", "plan_sha256": plan_hash, "plan": plan}
    require(approval == plan_hash, "installation_approval_mismatch")
    with directory(prefix, owned=True) as store, directory(bin_dir, owned=True) as bin_fd:
        try:
            fcntl.flock(store, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Refused("runtime_installation_in_progress") from None
        require(install_plan(prefix, bin_dir, manifest, release) == plan, "installation_changed_since_review")
        try:
            os.mkdir("releases", 0o700, dir_fd=store)
            os.fsync(store)
        except FileExistsError:
            pass
        with directory(prefix / "releases", owned=True, private=True) as releases:
            if not os.path.lexists(prefix / "releases" / release):
                os.mkdir(release, 0o700, dir_fd=releases)
                os.fsync(releases)
                with directory(prefix / "releases" / release, owned=True, private=True) as dest:
                    for name, raw in data.items():
                        publish(dest, name, raw, 0o500 if name == "acfs-fleet.py" else 0o400)
                    publish(dest, MANIFEST, encode(manifest), 0o400)  # completion marker last
                    os.fsync(dest)
                    os.fchmod(dest, 0o500)
                    os.fsync(dest)
            verify(prefix / "releases" / release)
        assert_path(store, prefix)
        assert_path(bin_fd, bin_dir)
        require(current_link(bin_fd, prefix) == plan["previous_launcher"], "launcher_changed_since_review")
        if plan["previous_launcher"] != plan["launcher"]:
            temporary = ".acfs-fleet-" + secrets.token_hex(12)
            os.symlink(plan["launcher"], temporary, dir_fd=bin_fd)
            os.fsync(bin_fd)
            # Only our reviewed managed symlink is replaced; no unrelated file
            # is adopted. A concurrent same-user attacker is outside this lock.
            require(current_link(bin_fd, prefix) == plan["previous_launcher"], "launcher_changed_since_review")
            os.replace(temporary, "acfs-fleet", src_dir_fd=bin_fd, dst_dir_fd=bin_fd)
            os.fsync(bin_fd)
    return {"status": "installed", "plan_sha256": plan_hash, "runtime": release,
            "launcher": str(bin_dir / "acfs-fleet"), "pinned_launcher": plan["launcher"],
            "network_access": False, "starts_agents": False, "sends_prompts": False}


HELP = """Usage: acfs-fleet {launch|prepare|dispatch|status} [CONTROLLER OPTIONS...]
       acfs-fleet version
       acfs-fleet runtimes
       acfs-fleet --runtime SHA256 {launch|prepare|dispatch|status|version} [OPTIONS...]
       python3 -I scripts/acfs-fleet.py install --prefix DIR --bin-dir DIR
           [--apply --accept-plan SHA256]

Controller arguments pass through unchanged. Launch/dispatch previews may open
SSH connections; only each controller's explicit approval can start agents or
send work. Status only observes original agents, receipts and exported Bead states.
Use COMMAND --help for the existing operation and recovery options.
Installation is offline and preview-only by default, as the target user without
sudo. Prefix and bin directory must already exist and be user-owned, not writable
by others. Releases are retained; an update never deletes a previous runtime.
--runtime selects an exact installed cohort without changing the active symlink.
Use the original runtime for recovery; absent or damaged releases never fall back.
Legacy four-file runtimes remain usable but do not provide the status command.
"""


def main(args=None):
    args = list(sys.argv[1:] if args is None else args)
    if not args or args[0] in ("--help", "-h"):
        print(HELP)
        return 0
    if args[0] == "--runtime":
        return select_runtime(args)
    command, rest = args[0], args[1:]
    if command == "runtimes":
        require(not rest, "unexpected_runtime_inventory_arguments")
        report = list_runtimes()
        print(encode(report).decode(), end="")
        return int(any(row["status"] != "verified" for row in report["runtimes"]))
    if command == "install":
        parser = argparse.ArgumentParser(description="Install a private, complete fleet runtime", allow_abbrev=False)
        parser.add_argument("--prefix", required=True)
        parser.add_argument("--bin-dir", required=True)
        parser.add_argument("--apply", action="store_true")
        parser.add_argument("--accept-plan")
        options = parser.parse_args(rest)
        require(options.apply == (options.accept_plan is not None), "apply_requires_exact_approval")
        report = install(path_arg(options.prefix), path_arg(options.bin_dir), options.accept_plan)
        print(encode(report).decode(), end="")
        return 0
    require(command in COMMANDS or command == "version", "unknown_fleet_command")
    _, manifest, release = source_snapshot()
    if command == "version":
        require(not rest, "unexpected_version_arguments")
        print(encode({"schema": manifest["schema"], "runtime": release, "directory": str(ENTRY.parent),
                      "commands": runtime_commands(manifest)}).decode(), end="")
        return 0
    require(command in runtime_commands(manifest), "runtime_command_unavailable")
    # Process replacement preserves stdin, terminal, signals and exact status;
    # there is no second parser for approval flags and no shell/PATH fallback.
    os.execv(sys.executable, [sys.executable, "-I", str(ENTRY.parent / COMMANDS[command]), *rest])


def cli():
    try:
        return main()
    except (Refused, OSError, ValueError) as exc:
        print(encode({"schema": SCHEMA, "status": "error", "code": str(exc) if isinstance(exc, Refused)
                      else "runtime_io_failure"}).decode(), file=sys.stderr, end="")
        return 2


if __name__ == "__main__":
    sys.exit(cli())
