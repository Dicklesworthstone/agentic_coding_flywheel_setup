#!/usr/bin/env bash
# ============================================================
# ACFS newproj - Create a new project with full ACFS tooling
# Creates a project with git, beads (br), Claude settings, and AGENTS.md
# Supports both CLI mode and interactive TUI wizard mode
# ============================================================

# Reviewed bootstrap is self-contained: no TUI initialization or configuration
# writes occur while planning. Python's standard library supplies JSON and
# no-follow, exclusive filesystem operations for the apply boundary.
newproj_reviewed_main() {
    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s\n' 'Error: reviewed project bootstrap requires python3.' >&2
        return 1
    fi
    python3 - "$@" <<'ACFS_BOOTSTRAP_PY'
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys

SCHEMA = "acfs.project-bootstrap.v1"
FEATURES = ("git", "beads", "readme", "gitignore", "agents", "starter", "ci", "prompt")
PRESET = ("git", "readme", "gitignore", "agents", "starter", "ci", "prompt")
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(",", ":"))


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def identity(info):
    return {"device": info.st_dev, "inode": info.st_ino}


def templates(name, stack, features):
    files = {}
    if stack == "python":
        command = ["python3", "-B", "-m", "unittest", "discover", "-s", "tests", "-v"]
        starter = {
            "src/__init__.py": "",
            "src/app.py": 'def greet(name: str) -> str:\n    """Return a greeting for a non-empty name."""\n    name = name.strip()\n    if not name:\n        raise ValueError("name must not be empty")\n    return f"Hello, {name}!"\n',
            "tests/test_app.py": 'import unittest\n\nfrom src.app import greet\n\n\nclass GreetingTests(unittest.TestCase):\n    def test_greeting(self):\n        self.assertEqual(greet("world"), "Hello, world!")\n\n    def test_whitespace(self):\n        self.assertEqual(greet("  Ada  "), "Hello, Ada!")\n\n    def test_empty_name(self):\n        with self.assertRaises(ValueError):\n            greet("  ")\n\n\nif __name__ == "__main__":\n    unittest.main()\n',
        }
    else:
        command = ["bun", "test"]
        starter = {
            "package.json": json.dumps({"name": name.lower(), "version": "0.1.0", "private": True, "type": "module", "scripts": {"test": "bun test"}}, indent=2) + "\n",
            "src/app.ts": 'export function greet(name: string): string {\n  const normalized = name.trim();\n  if (!normalized) throw new Error("name must not be empty");\n  return `Hello, ${normalized}!`;\n}\n',
            "tests/app.test.ts": 'import { expect, test } from "bun:test";\nimport { greet } from "../src/app";\n\ntest("greets a name", () => expect(greet("world")).toBe("Hello, world!"));\ntest("trims whitespace", () => expect(greet("  Ada  ")).toBe("Hello, Ada!"));\ntest("rejects empty names", () => expect(() => greet("  ")).toThrow());\n',
        }
    check = " ".join(command)
    if "starter" in features:
        files.update(starter)
    if "readme" in features:
        files["README.md"] = f"# {name}\n\nCreated from a reviewed ACFS bootstrap plan.\n\n" + (
            f"## Verify the starter\n\n```sh\n{check}\n```\n\nThe starter has no third-party dependencies. Install the {stack} runtime\nwith ACFS before running it; bootstrap does not install packages or call models.\n\n" if "starter" in features else ""
        ) + "## First change\n\nDescribe the first useful feature before asking an agent to implement it.\nReview the diff and run checks before committing. No remote is configured.\n"
    if "gitignore" in features:
        files[".gitignore"] = ".env\n.env.*\n!.env.example\n*.log\n__pycache__/\n*.pyc\n.venv/\nnode_modules/\ndist/\ncoverage/\n.claude/settings.local.json\n/.acfs/bootstrap-state.json\n/.acfs/bootstrap-state.tmp-*\n"
    if "agents" in features:
        files["AGENTS.md"] = f"# AGENTS.md — {name}\n\n## Working agreement\n\nRead the README and inspect existing code before editing.\nDo not delete files, overwrite user work, reset Git history, publish, or push\nwithout explicit permission. Never add credentials to code, prompts, or logs.\nDo not enable permission-bypass flags or change global agent settings.\nKeep changes small enough to review and report which checks actually ran.\n" + (
            f"\n## Verification\n\nRun `{check}` from the project root. Keep the starter checks passing.\n" if "starter" in features else ""
        ) + ("\nUse Bun for JavaScript/TypeScript; do not introduce npm/yarn/pnpm lockfiles.\n" if stack == "typescript" else "\nPrefer the Python standard library until a dependency is justified.\n")
    if "ci" in features:
        files["scripts/check.sh"] = '#!/usr/bin/env sh\nset -eu\ncd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"\nexec ' + check + '\n'
    if "prompt" in features:
        files["FIRST_AGENT_PROMPT.md"] = "# First agent task\n\n" + (
            "Read AGENTS.md and README.md, then inspect the starter code and tests.\n" if "agents" in features and "readme" in features else "Inspect the project files and any existing project policy before editing.\n"
        ) + (
            f"Run `{check}` and report the result without installing anything.\n" if "starter" in features else "Identify available checks and explain how to run them.\n"
        ) + "Ask me what useful feature to build next, propose one bounded change and\nits tests, and wait for my approval before changing code. Do not delete,\ncommit, push, invoke other agents, change authentication, or run network\ncommands. Never include credentials or machine-specific secrets in output.\n"
    if "beads" in features:
        if "AGENTS.md" in files:
            files["AGENTS.md"] += "\n## Coordination\n\nUse `br ready --json` to find work and `br update ID --status in_progress`\nto claim it. Create the first bead only after agreeing on its scope.\nUse `br close ID --reason \"Completed\"` after verification, and\n`br sync --flush-only` before reviewing and committing `.beads/` changes.\nDo not edit `.beads/*.jsonl` directly.\n"
        if "FIRST_AGENT_PROMPT.md" in files:
            files["FIRST_AGENT_PROMPT.md"] += "\nRead `br ready --json` before proposing work. Do not create or claim a bead\nuntil I approve the scope; an empty board is expected for a new project.\n"
    return files, [command] if "starter" in features else []


def make_plan(name, directory, stack, features, target):
    if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,63}", name):
        raise ValueError("project name must start with a letter and contain at most 64 letters, digits, _ or -")
    if stack not in ("python", "typescript"):
        raise ValueError("stack must be python or typescript")
    if not isinstance(features, list) or not features or any(type(f) is not str or f not in FEATURES for f in features):
        raise ValueError("select an explicit preset or a non-empty --with feature list")
    if len(set(features)) != len(features):
        raise ValueError("features must not contain duplicates")
    features = [f for f in FEATURES if f in features]
    if "beads" in features and "git" not in features:
        raise ValueError("beads requires explicitly selecting git too")
    if "ci" in features and "starter" not in features:
        raise ValueError("ci requires explicitly selecting starter too")
    if not isinstance(directory, str) or not directory.startswith("/") or any(ord(c) < 32 for c in directory):
        raise ValueError("project directory must be an absolute path without control characters")
    if str(Path(directory)) != directory or ".." in Path(directory).parts or directory == "/":
        raise ValueError("project directory must be canonical, not a filesystem root")
    if type(target) is not dict or set(target) != {"parent", "directory"}:
        raise ValueError("invalid target snapshot")
    for item in (target["parent"], target["directory"]):
        if item is not None and (type(item) is not dict or set(item) != {"device", "inode"} or any(type(v) is not int or v < 0 for v in item.values())):
            raise ValueError("invalid target identity")
    if target["parent"] is None:
        raise ValueError("missing parent identity")
    files, checks = templates(name, stack, features)
    plan = {
        "schema": SCHEMA,
        "project": {"name": name, "directory": directory, "stack": stack},
        "features": features,
        "target": target,
        "files": [{"path": path, "content": content, "sha256": digest(content), "mode": "0755" if path == "scripts/check.sh" else "0644"} for path, content in sorted(files.items())],
        "commands": ([{"id": "git-init", "argv": ["git", "init", "--template=", "--initial-branch=main", "."], "writes": [".git/"]}] if "git" in features else []) + ([{"id": "beads-init", "argv": ["br", "init"], "verify_argv": ["br", "ready", "--json"], "writes": [".beads/"]}] if "beads" in features else []),
        "state_file": ".acfs/bootstrap-state.json",
        "verification_commands": checks,
        "effects": {"network": False, "model_calls": False, "global_settings": False, "commit": False, "push": False},
    }
    plan["plan_id"] = digest(canonical(plan))
    return plan


def open_directory(path):
    # Walk without following symlinks, including ancestor components.
    fd = os.open("/", DIR_FLAGS)
    try:
        for part in Path(path).parts[1:]:
            next_fd = os.open(part, DIR_FLAGS, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        return fd
    except BaseException:
        os.close(fd)
        raise


def target_snapshot(directory):
    parent = open_directory(str(Path(directory).parent))
    try:
        try:
            target = os.open(Path(directory).name, DIR_FLAGS, dir_fd=parent)
        except FileNotFoundError:
            current = None
        else:
            try:
                if os.listdir(target):
                    raise ValueError("project directory is not empty; choose a new directory")
                current = identity(os.fstat(target))
            finally:
                os.close(target)
        return {"parent": identity(os.fstat(parent)), "directory": current}
    finally:
        os.close(parent)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON field in plan")
        result[key] = value
    return result


def read_plan(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "r", encoding="utf-8") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("plan must be a regular JSON file")
        text = stream.read(1024 * 1024 + 1)
    if len(text) > 1024 * 1024:
        raise ValueError("plan exceeds 1 MiB")
    value = json.loads(text, object_pairs_hook=unique_object)
    if type(value) is not dict or type(value.get("project")) is not dict:
        raise ValueError("invalid bootstrap plan")
    project = value["project"]
    expected = make_plan(project.get("name"), project.get("directory"), project.get("stack"), value.get("features"), value.get("target"))
    if value != expected:
        raise ValueError("plan differs from this ACFS version's templates; regenerate and review it")
    return value


def write_new(directory_fd, name, content, mode):
    fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode, dir_fd=directory_fd)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write(content)
        stream.flush()
        os.fchmod(stream.fileno(), mode)
        os.fsync(stream.fileno())


def read_regular(directory_fd, name, limit=1024 * 1024):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory_fd)
    with os.fdopen(fd, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("bootstrap input must be a regular file: " + name)
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise ValueError("bootstrap input is too large: " + name)
        return data


def file_parent(root, path, create=False):
    fd = os.dup(root)
    try:
        for part in path.split("/")[:-1]:
            if create:
                try:
                    os.mkdir(part, 0o755, dir_fd=fd)
                except FileExistsError:
                    pass
            next_fd = os.open(part, DIR_FLAGS, dir_fd=fd)
            os.close(fd)
            fd = next_fd
        return fd
    except BaseException:
        os.close(fd)
        raise


def check_existing_files(root, plan):
    # Check the complete selection before writing any missing file. A resume
    # must never overwrite edits made while the bootstrap was interrupted.
    for entry in plan["files"]:
        try:
            parent = file_parent(root, entry["path"])
        except FileNotFoundError:
            continue
        try:
            try:
                data = read_regular(parent, entry["path"].split("/")[-1])
            except FileNotFoundError:
                continue
            if data != entry["content"].encode("utf-8"):
                raise ValueError("planned file was edited; refusing to overwrite: " + entry["path"])
        finally:
            os.close(parent)


def check_tool_tree(root, name):
    # git/br may traverse their own metadata: reject pre-existing links and
    # special files there rather than letting a resume redirect their writes.
    try:
        fd = os.open(name, DIR_FLAGS, dir_fd=root)
    except FileNotFoundError:
        return False
    try:
        for child in os.listdir(fd):
            info = os.stat(child, dir_fd=fd, follow_symlinks=False)
            if stat.S_ISDIR(info.st_mode):
                check_tool_tree(fd, child)
            elif not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                raise ValueError("unsafe tool metadata; review it before resuming")
        return True
    finally:
        os.close(fd)


def save_state(state_dir, state):
    import uuid
    temporary = "bootstrap-state.tmp-" + uuid.uuid4().hex
    write_new(state_dir, temporary, canonical(state) + "\n", 0o600)
    os.replace(temporary, "bootstrap-state.json", src_dir_fd=state_dir, dst_dir_fd=state_dir)
    os.fsync(state_dir)


def run_tool(executable, arguments, env):
    import signal
    # All argv are fixed by regenerated templates, never evaluated as shell.
    process = subprocess.Popen([executable, *arguments], env=env, stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    try:
        code = process.wait(timeout=30)
    except BaseException:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        raise
    if code:
        raise ValueError(f"{Path(executable).name} failed (exit {code}); partial project retained")


def apply(plan, resume=False):
    import fcntl
    directory = plan["project"]["directory"]
    parent = open_directory(str(Path(directory).parent))
    root = state_dir = None
    state = None
    touched = False
    try:
        if identity(os.fstat(parent)) != plan["target"]["parent"]:
            raise ValueError("parent directory changed after review; regenerate the plan")
        name = Path(directory).name
        if plan["target"]["directory"] is None and not resume:
            # Preflight before any mutation, including creation of the root.
            for command in plan["commands"]:
                if not shutil.which(command["argv"][0]):
                    raise ValueError("required executable is missing: " + command["argv"][0])
            os.mkdir(name, 0o700, dir_fd=parent)
            touched = True
        root = os.open(name, DIR_FLAGS, dir_fd=parent)
        fcntl.flock(root, fcntl.LOCK_EX | fcntl.LOCK_NB)
        root_identity = identity(os.fstat(root))
        if plan["target"]["directory"] is not None and root_identity != plan["target"]["directory"]:
            raise ValueError("project directory changed after review; regenerate the plan")
        if resume:
            state_dir = os.open(".acfs", DIR_FLAGS, dir_fd=root)
            state = json.loads(read_regular(state_dir, "bootstrap-state.json"), object_pairs_hook=unique_object)
            if type(state) is not dict or set(state) != {"schema", "plan_id", "directory_identity", "status", "completed_files", "completed_commands"}:
                raise ValueError("invalid bootstrap checkpoint")
            if state["schema"] != SCHEMA or state["plan_id"] != plan["plan_id"] or state["directory_identity"] != root_identity:
                raise ValueError("checkpoint does not belong to this plan and project")
            if state["status"] not in ("applying", "failed", "complete"):
                raise ValueError("invalid checkpoint status")
            for field, expected in (("completed_files", [f["path"] for f in plan["files"]]), ("completed_commands", [c["id"] for c in plan["commands"]])):
                completed = state[field]
                if type(completed) is not list or completed != expected[:len(completed)]:
                    raise ValueError("invalid checkpoint progress")
            check_existing_files(root, plan)
            for feature, metadata in (("git", ".git"), ("beads", ".beads")):
                if feature in plan["features"]:
                    exists = check_tool_tree(root, metadata)
                    if feature + "-init" in state["completed_commands"] and not exists:
                        raise ValueError("completed tool metadata is missing: " + metadata)
        elif os.listdir(root):
            raise ValueError("project directory is no longer empty; use --resume only for a reviewed interrupted bootstrap")
        # Resolve missing work now; completed commands need not be installed
        # again just to verify or resume file-only work.
        executables = {}
        for command in plan["commands"]:
            if state is not None and command["id"] in state["completed_commands"]:
                continue
            executable = shutil.which(command["argv"][0])
            if not executable:
                raise ValueError("required executable is missing: " + command["argv"][0])
            executables[command["id"]] = os.path.abspath(executable)
        if state is None:
            os.mkdir(".acfs", 0o700, dir_fd=root)
            state_dir = os.open(".acfs", DIR_FLAGS, dir_fd=root)
            state = {"schema": SCHEMA, "plan_id": plan["plan_id"], "directory_identity": root_identity,
                     "status": "applying", "completed_files": [], "completed_commands": []}
            write_new(state_dir, "bootstrap-state.json", canonical(state) + "\n", 0o600)
            os.fsync(state_dir)
            touched = True
        for entry in plan["files"]:
            fd = file_parent(root, entry["path"], create=True)
            try:
                leaf = entry["path"].split("/")[-1]
                try:
                    write_new(fd, leaf, entry["content"], int(entry["mode"], 8))
                    os.fsync(fd)
                    touched = True
                except FileExistsError:
                    if not resume or read_regular(fd, leaf) != entry["content"].encode("utf-8"):
                        raise ValueError("planned file already exists or changed: " + entry["path"])
                if entry["path"] not in state["completed_files"]:
                    state["completed_files"].append(entry["path"])
                    save_state(state_dir, state)
            finally:
                os.close(fd)
        os.fchdir(root)
        env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "BEADS_", "BR_"))}
        env.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull, "GIT_TERMINAL_PROMPT": "0"})
        for command in plan["commands"]:
            if command["id"] in state["completed_commands"]:
                continue
            executable = executables[command["id"]]
            # br init may have succeeded just before a crash prevented the
            # checkpoint write. A successful local ready probe verifies that
            # database rather than blindly initializing it a second time.
            if command["id"] == "beads-init" and check_tool_tree(root, ".beads"):
                run_tool(executable, ["ready", "--json"], env)
            else:
                run_tool(executable, command["argv"][1:], env)
            metadata = ".beads" if command["id"] == "beads-init" else ".git"
            if not check_tool_tree(root, metadata):
                raise ValueError("tool exited successfully without creating " + metadata)
            if command["id"] == "beads-init":
                run_tool(executable, ["ready", "--json"], env)
            state["completed_commands"].append(command["id"])
            save_state(state_dir, state)
        state["status"] = "complete"
        save_state(state_dir, state)
        return {"status": "resumed" if resume else "created", "plan_id": plan["plan_id"], "directory": directory,
                "created_files": state["completed_files"], "completed_commands": state["completed_commands"],
                "verification_commands": plan["verification_commands"],
                "note": "Review the files and run the verification commands. No agent, commit, or push was started."}
    except BaseException:
        if state is not None and touched:
            state["status"] = "failed"
            try:
                save_state(state_dir, state)
            except (OSError, ValueError):
                pass  # Preserve the original error and the last durable checkpoint.
        if touched:
            print("Partial project retained at " + directory + "; nothing was removed. Review it, then retry the same plan with --apply PLAN.json --yes --resume.", file=sys.stderr)
        raise
    finally:
        if state_dir is not None:
            os.close(state_dir)
        if root is not None:
            os.close(root)
        os.close(parent)


def main():
    parser = argparse.ArgumentParser(prog="acfs newproj", description="Review a deterministic first-project plan, then explicitly apply it.")
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--plan", metavar="NAME")
    action.add_argument("--apply", metavar="PLAN_JSON")
    parser.add_argument("directory", nargs="?")
    parser.add_argument("--stack", choices=("python", "typescript"))
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--preset", choices=("first-project",))
    selection.add_argument("--with", dest="features", metavar=",".join(FEATURES))
    parser.add_argument("--yes", action="store_true", help="authorize only the reviewed apply operation")
    parser.add_argument("--resume", action="store_true", help="resume this exact reviewed plan without replacing edited files")
    parser.add_argument("--beads", action="store_true", help="also select local Beads initialization (requires git)")
    args = parser.parse_args()
    if args.apply:
        if not args.yes or any((args.directory, args.stack, args.preset, args.features, args.beads)):
            parser.error("use --apply PLAN_JSON --yes without plan overrides")
        result = apply(read_plan(args.apply), args.resume)
    else:
        if args.yes or args.resume:
            parser.error("--yes and --resume apply only to --apply")
        if not args.preset and not args.features:
            parser.error("select --preset first-project or --with FEATURES explicitly")
        # Resolve parents once for a portable reviewable absolute destination;
        # apply still walks the resulting path without following symlinks.
        raw = Path(args.directory or str(Path(os.environ.get("ACFS_PROJECTS_DIR", "/data/projects")) / args.plan)).expanduser()
        directory = str(raw.parent.resolve(strict=True) / raw.name)
        result = make_plan(args.plan, directory, args.stack or "python", (list(PRESET) if args.preset else args.features.split(",")) + (["beads"] if args.beads else []), target_snapshot(directory))
    print(json.dumps(result, indent=2, ensure_ascii=True))


try:
    main()
except (OSError, ValueError, TypeError, subprocess.SubprocessError) as error:
    print(json.dumps({"status": "failed", "error": str(error)}), file=sys.stderr)
    sys.exit(1)
ACFS_BOOTSTRAP_PY
}

if [[ "${BASH_SOURCE[0]}" == "$0" && ( "${1:-}" == "--plan" || "${1:-}" == "--apply" ) ]]; then
    newproj_reviewed_main "$@"
    exit $?
fi

set -e

# Get script directory for sourcing other modules
NEWPROJ_SCRIPT_DIR="${NEWPROJ_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=newproj_errors.sh
source "$NEWPROJ_SCRIPT_DIR/newproj_errors.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Track what was created for summary
declare -ga CREATED_ITEMS=()

# Holds the project directory from the moment it is created (or an empty
# pre-existing one starts being populated) until setup completes. Under
# `set -e` any failed step aborts the script mid-way; the EXIT trap uses
# this to tell the user a partial project was left behind instead of dying
# silently. Cleared right before the success summary.
NEWPROJ_PARTIAL_DIR=""

_newproj_report_partial_on_exit() {
    local rc=$?
    if (( rc != 0 )) && [[ -n "${NEWPROJ_PARTIAL_DIR:-}" ]]; then
        {
            echo ""
            echo -e "${RED}newproj failed (exit $rc) before project setup finished.${NC}"
            echo -e "${YELLOW}Partial project left at: ${NEWPROJ_PARTIAL_DIR}${NC}"
            if [[ ${#CREATED_ITEMS[@]} -gt 0 ]]; then
                echo -e "${YELLOW}Created before the failure:${NC}"
                local item
                for item in "${CREATED_ITEMS[@]}"; do
                    echo "  - $item"
                done
            fi
            echo -e "${YELLOW}Nothing was removed automatically. Review the directory, delete it if unwanted, then re-run newproj.${NC}"
        } >&2
    fi
}

# ============================================================
# Environment Detection
# ============================================================

# Check if running in a CI environment
is_ci_environment() {
    [[ -n "${CI:-}" ]] || \
    [[ -n "${GITHUB_ACTIONS:-}" ]] || \
    [[ -n "${GITLAB_CI:-}" ]] || \
    [[ -n "${JENKINS_URL:-}" ]] || \
    [[ -n "${TRAVIS:-}" ]] || \
    [[ -n "${CIRCLECI:-}" ]] || \
    [[ "${TERM:-}" == "dumb" ]]
}

# Check if stdin is a TTY (not piped)
is_stdin_tty() {
    [[ -t 0 ]]
}

# Check if stdout is a TTY
is_stdout_tty() {
    [[ -t 1 ]]
}

# Get terminal dimensions
get_terminal_size() {
    local cols lines
    cols=$(tput cols 2>/dev/null || echo 0)
    lines=$(tput lines 2>/dev/null || echo 0)
    echo "$cols $lines"
}

# Check if terminal meets minimum size requirements
check_terminal_size() {
    local min_cols="${1:-60}"
    local min_lines="${2:-15}"

    local size
    size=$(get_terminal_size)
    local cols="${size%% *}"
    local lines="${size##* }"

    if [[ "$cols" -lt "$min_cols" ]] || [[ "$lines" -lt "$min_lines" ]]; then
        echo "Terminal too small: ${cols}x${lines} (minimum: ${min_cols}x${min_lines})"
        return 1
    fi
    return 0
}

# Check if TUI module is available
check_tui_available() {
    local screens_module="$NEWPROJ_SCRIPT_DIR/newproj_screens.sh"
    if [[ ! -f "$screens_module" ]]; then
        echo "TUI module not found: $screens_module"
        return 1
    fi
    return 0
}

print_help() {
    echo "Usage: acfs newproj [options] <project-name> [directory]"
    echo "       acfs newproj --interactive"
    echo ""
    echo "Create a new project with ACFS tooling (git, br, claude settings, AGENTS.md)"
    echo ""
    echo "Arguments:"
    echo "  project-name    Name of the project (required in CLI mode)"
    echo "  directory       Directory path (default: /data/projects/<project-name>)"
    echo ""
    echo "Interactive mode:"
    echo "  -i, --interactive   Launch TUI wizard for guided project setup"
    echo "                      (recommended for first-time users)"
    echo ""
    echo "Reviewed bootstrap (Python 3, no automatic agent or network calls):"
    echo "  --plan NAME [DIR] --preset first-project --stack python|typescript"
    echo "                      Print a reviewable JSON plan; creates nothing"
    echo "  --plan NAME [DIR] --with git,readme,gitignore,agents,starter,ci,prompt"
    echo "                      Include only explicitly selected features"
    echo "  --apply PLAN.json --yes  Apply reviewed files without overwriting work"
    echo ""
    echo "  --beads               Include local Beads initialization in a plan"
    echo "  --apply PLAN.json --yes --resume  Continue an interrupted bootstrap"
    echo ""
    echo "CLI mode options:"
    echo "  --no-br         Skip beads (br) initialization"
    echo "  --no-claude     Skip Claude settings creation"
    echo "  --no-agents     Skip AGENTS.md template creation"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  acfs newproj myapp                       # CLI mode"
    echo "  acfs newproj myapp /home/user/projects/myapp  # CLI mode with explicit project dir"
    echo "  acfs newproj --interactive               # TUI wizard"
    echo "  acfs newproj -i                          # TUI wizard (short form)"
    echo "  acfs newproj -i myapp                    # TUI with pre-filled name"
}

# Create AGENTS.md template with ACFS tooling instructions
# Generic sections are included; project-specific sections have placeholders
create_agents_template() {
    local project_name="$1"
    local template=""

    template=$(cat << 'AGENTS_EOF'
# AGENTS.md — PROJECT_NAME_PLACEHOLDER

This file was generated by `acfs newproj` as a starting template.

If you used the interactive wizard, toolchain and Docker workflow sections
may be included based on detected tech stack. In CLI mode, this template is
generic - edit or add sections as needed.

To regenerate with different options, move this file aside and re-run:
  acfs newproj --interactive

---

## RULE 1 – ABSOLUTE (DO NOT EVER VIOLATE THIS)

You may NOT delete any file or directory unless I explicitly give the exact command **in this session**.

- This includes files you just created (tests, tmp files, scripts, etc.).
- You do not get to decide that something is "safe" to remove.
- If you think something should be removed, stop and ask. You must receive clear written approval **before** any deletion command is even proposed.

Treat "never delete files without permission" as a hard invariant.

---

## IRREVERSIBLE GIT & FILESYSTEM ACTIONS

Absolutely forbidden unless I give the **exact command and explicit approval** in the same message:

- `git reset --hard`
- `git clean -fd`
- `rm -rf`
- Any command that can delete or overwrite code/data

Rules:

1. If you are not 100% sure what a command will delete, do not propose or run it. Ask first.
2. Prefer safe tools: `git status`, `git diff`, `git stash`, copying to backups, etc.
3. After approval, restate the command verbatim, list what it will affect, and wait for confirmation.
4. When a destructive command is run, record in your response:
   - The exact user text authorizing it
   - The command run
   - When you ran it

If that audit trail is missing, then you must act as if the operation never happened.

---

## Node / JS Toolchain

- Use **bun** for everything JS/TS.
- ❌ Never use `npm`, `yarn`, or `pnpm`.
- Lockfiles: only `bun.lock`. Do not introduce any other lockfile.
- Target **latest Node.js**. No need to support old Node versions.
- **Note:** `bun install -g <pkg>` is valid syntax (alias for `bun add -g`). Do not "fix" it.

---

## Project Architecture

<!-- CUSTOMIZE: Describe your project's architecture here -->

### Components

<!-- CUSTOMIZE: List your project's main components/domains -->

Example structure:
- **A) Backend API** — Framework, database, main responsibilities
- **B) Frontend** — Framework, UI library, key patterns
- **C) Shared** — Common utilities, types, constants

---

## Repo Layout

<!-- CUSTOMIZE: Document your actual directory structure -->

```
PROJECT_NAME_PLACEHOLDER/
├── README.md
├── AGENTS.md
├── .beads/                        # Issue tracking (br)
├── .claude/                       # Claude Code settings
│
└── src/                           # Your source code
```

---

## Generated Files — NEVER Edit Manually

<!-- CUSTOMIZE: If you have generated files, document them here -->

**Current state:** There are no generated files in this repo.

If/when you add generated artifacts:
- **Rule:** Never hand-edit generated outputs.
- **Convention:** Put generated outputs in a clearly labeled directory and document the generator command.

---

## Code Editing Discipline

- Do **not** run scripts that bulk-modify code (codemods, invented one-off scripts, giant `sed`/regex refactors).
- Large mechanical changes: break into smaller, explicit edits and review diffs.
- Subtle/complex changes: edit by hand, file-by-file, with careful reasoning.

---

## Backwards Compatibility & File Sprawl

We optimize for a clean architecture now, not backwards compatibility.

- No "compat shims" or "v2" file clones.
- When changing behavior, migrate callers and remove old code.
- New files are only for genuinely new domains that don't fit existing modules.
- The bar for adding files is very high.

---

## Console Output

- Prefer **structured, minimal logs** (avoid spammy debug output).
- Treat user-facing UX as UI-first; logs are for operators/debugging.

---

## MCP Agent Mail — Multi-Agent Coordination

Agent Mail is available as an MCP server for coordinating work across agents.

What Agent Mail gives:
- Identities, inbox/outbox, searchable threads.
- Advisory file reservations (leases) to avoid agents clobbering each other.
- Persistent artifacts in git (human-auditable).

Core patterns:

1. **Same repo**
   - Register identity:
     - `ensure_project` then `register_agent` with the repo's absolute path as `project_key`.
   - Reserve files before editing:
     - `file_reservation_paths(project_key, agent_name, ["src/**"], ttl_seconds=3600, exclusive=true)`.
   - Communicate:
     - `send_message(..., thread_id="FEAT-123")`.
     - `fetch_inbox`, then `acknowledge_message`.
   - Fast reads:
     - `resource://inbox/{Agent}?project=<abs-path>&limit=20`.
     - `resource://thread/{id}?project=<abs-path>&include_bodies=true`.

2. **Macros vs granular:**
   - Prefer macros when speed is more important than fine-grained control:
     - `macro_start_session`, `macro_prepare_thread`, `macro_file_reservation_cycle`, `macro_contact_handshake`.
   - Use granular tools when you need explicit behavior.

Common pitfalls:
- "from_agent not registered" → call `register_agent` with correct `project_key`.
- `FILE_RESERVATION_CONFLICT` → adjust patterns, wait for expiry, or use non-exclusive reservation.

---

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   br sync --flush-only
   git add .beads/
   git commit -m "Update beads"
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

---

<!-- br-agent-instructions-v1 -->
## Issue Tracking with br (Beads)

All issue tracking goes through **Beads**. No other TODO systems.

Key invariants:

- `.beads/` is authoritative state and **must always be committed** with code changes.
- Do not edit `.beads/*.jsonl` directly; only via `br`.

### Basics

Check ready work:

```bash
br ready --json
```

Create issues:

```bash
br create --title="Issue title" --type=bug --priority=1 --json
br create --title="Issue title" --type=task --priority=1 --deps discovered-from:br-123 --json
```

Update:

```bash
br update br-42 --status in_progress --json
br update br-42 --priority 1 --json
```

Complete:

```bash
br close br-42 --reason "Completed" --json
```

Types: `bug`, `feature`, `task`, `epic`, `chore`

Priorities: `0` critical, `1` high, `2` medium (default), `3` low, `4` backlog

Agent workflow:

1. `br ready` to find unblocked work.
2. Claim: `br update <id> --status in_progress`.
3. Implement + test.
4. If you discover new work, create a new bead with `discovered-from:<parent-id>`.
5. Close when done.
6. Commit `.beads/` in the same commit as code changes.

Never:
- Use markdown TODO lists.
- Use other trackers.
- Duplicate tracking.
<!-- end-br-agent-instructions -->

---

## Using bv as an AI sidecar

bv is a graph-aware triage engine for Beads projects. Use robot flags for deterministic outputs.

**⚠️ CRITICAL: Use ONLY `--robot-*` flags. Bare `bv` launches an interactive TUI that blocks your session.**

```bash
bv --robot-triage        # THE MEGA-COMMAND: start here
bv --robot-next          # Just the single top pick + claim command
bv --robot-plan          # Parallel execution tracks
bv --robot-insights      # Full graph metrics
```

Use bv instead of parsing beads.jsonl—it computes PageRank, critical paths, cycles, and parallel tracks deterministically.

---

## cass — Cross-Agent Search

`cass` indexes prior agent conversations so we can reuse solved problems.

**Rules:** Never run bare `cass` (TUI). Always use `--robot` or `--json`.

```bash
cass health
cass search "authentication error" --robot --limit 5
cass view /path/to/session.jsonl -n 42 --json
```

Treat cass as a way to avoid re-solving problems other agents already handled.

---

## Memory System: cass-memory

Before starting complex tasks, retrieve relevant context:

```bash
cm context "<task description>" --json
```

This returns:
- **relevantBullets**: Rules that may help with your task
- **antiPatterns**: Pitfalls to avoid
- **historySnippets**: Past sessions that solved similar problems

Protocol:
1. **START**: Run `cm context "<task>" --json` before non-trivial work
2. **WORK**: Reference rule IDs when following them
3. **END**: Just finish your work. Learning happens automatically.

---

## UBS Quick Reference

**Golden Rule:** `ubs <changed-files>` before every commit. Exit 0 = safe. Exit >0 = fix & re-run.

```bash
ubs file.ts file2.py                    # Specific files (< 1s) — USE THIS
ubs $(git diff --name-only --cached)    # Staged files — before commit
ubs .                                   # Whole project
```

**Speed Critical:** Scope to changed files. `ubs src/file.ts` (< 1s) vs `ubs .` (30s).

**Bug Severity:**
- **Critical** (always fix): Null safety, XSS/injection, async/await, memory leaks
- **Important** (production): Type narrowing, division-by-zero, resource leaks
- **Contextual** (judgment): TODO/FIXME, console logs
AGENTS_EOF
)

    printf '%s\n' "${template//PROJECT_NAME_PLACEHOLDER/$project_name}" > AGENTS.md
}

# ============================================================
# Interactive Mode
# ============================================================

# Run the interactive TUI wizard
# Usage: run_interactive_mode [prefill_name] [prefill_dir]
run_interactive_mode() {
    local prefill_name="${1:-}"
    local prefill_dir="${2:-}"

    # Pre-flight checks for interactive mode
    echo -e "${CYAN}Checking interactive mode requirements...${NC}"

    # Check 1: CI environment
    if is_ci_environment; then
        echo -e "${RED}Error: Interactive mode cannot run in CI environment${NC}" >&2
        echo -e "${YELLOW}Detected CI environment variables or TERM=dumb${NC}" >&2
        echo -e "${YELLOW}Use CLI mode instead: acfs newproj <project-name>${NC}" >&2
        return 1
    fi

    # Check 2: TTY requirement
    if ! is_stdin_tty; then
        echo -e "${RED}Error: Interactive mode requires a terminal (stdin is not a TTY)${NC}" >&2
        echo -e "${YELLOW}Cannot run in piped input mode${NC}" >&2
        echo -e "${YELLOW}Use CLI mode instead: acfs newproj <project-name>${NC}" >&2
        return 1
    fi

    if ! is_stdout_tty; then
        echo -e "${RED}Error: Interactive mode requires a terminal (stdout is not a TTY)${NC}" >&2
        echo -e "${YELLOW}Cannot run with redirected output${NC}" >&2
        echo -e "${YELLOW}Use CLI mode instead: acfs newproj <project-name>${NC}" >&2
        return 1
    fi

    # Check 3: Terminal size
    local size_error
    size_error=$(check_terminal_size 60 15) || {
        echo -e "${RED}Error: $size_error${NC}" >&2
        echo -e "${YELLOW}Please resize your terminal and try again${NC}" >&2
        return 1
    }

    # Check 4: TUI module availability
    local tui_error
    tui_error=$(check_tui_available) || {
        echo -e "${RED}Error: $tui_error${NC}" >&2
        echo -e "${YELLOW}The TUI wizard module may not be installed correctly${NC}" >&2
        echo -e "${YELLOW}Try reinstalling ACFS or use CLI mode${NC}" >&2
        return 1
    }

    echo -e "${GREEN}All checks passed, launching wizard...${NC}"
    echo ""

    # Source the screens module
    source "$NEWPROJ_SCRIPT_DIR/newproj_screens.sh"

    if [[ -z "${ACFS_SESSION_LOG:-}" ]]; then
        init_logging
    fi

    # Pre-fill state if arguments provided
    if [[ -n "$prefill_name" ]]; then
        echo -e "${CYAN}Pre-filling project name: $prefill_name${NC}"
        state_set "project_name" "$prefill_name"
    fi

    if [[ -n "$prefill_dir" ]]; then
        echo -e "${CYAN}Pre-filling project directory: $prefill_dir${NC}"
        state_set "project_dir" "$prefill_dir"
    fi

    # Run the wizard
    if run_wizard; then
        return 0
    else
        # Wizard was cancelled or failed
        echo ""
        echo -e "${YELLOW}Wizard cancelled or failed${NC}"
        return 1
    fi
}

main() {
    local project_name=""
    local project_dir=""
    local skip_br=false
    local skip_claude=false
    local skip_agents=false
    local interactive_mode=false
    local git_initialized=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_help
                exit 0
                ;;
            -i|--interactive)
                interactive_mode=true
                shift
                ;;
            --no-br)
                skip_br=true
                shift
                ;;
            --no-claude)
                skip_claude=true
                shift
                ;;
            --no-agents)
                skip_agents=true
                shift
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                print_help
                exit 1
                ;;
            *)
                if [[ -z "$project_name" ]]; then
                    project_name="$1"
                elif [[ -z "$project_dir" ]]; then
                    project_dir="$1"
                else
                    echo -e "${RED}Too many arguments${NC}" >&2
                    print_help
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Handle interactive mode
    if [[ "$interactive_mode" == "true" ]]; then
        if [[ -n "$project_name" ]]; then
            local validation_error=""
            validation_error=$(validate_project_name "$project_name" 2>&1) || {
                echo -e "${RED}Error: $validation_error${NC}" >&2
                return 1
            }
        fi
        run_interactive_mode "$project_name" "$project_dir"
        return $?
    fi

    # Validate project name
    if [[ -z "$project_name" ]]; then
        echo -e "${RED}Error: Project name is required${NC}" >&2
        print_help
        exit 1
    fi

    local validation_error=""
    validation_error=$(validate_project_name "$project_name" 2>&1) || {
        echo -e "${RED}Error: $validation_error${NC}" >&2
        exit 1
    }

    # Set default directory
    # SAFEGUARD: When running in test environment, ALWAYS use /tmp to prevent pollution
    if [[ -n "${BATS_TEST_NAME:-}" || -n "${ACFS_TEST_MODE:-}" ]]; then
        if [[ -z "$project_dir" ]]; then
            project_dir="/tmp/acfs-test-$$/$project_name"
            echo -e "${YELLOW}Test mode detected: redirecting to $project_dir${NC}" >&2
        fi
    elif [[ -z "$project_dir" ]]; then
        # Honor ACFS_PROJECTS_DIR so the non-interactive CLI matches the
        # interactive wizard (screen_directory.sh::get_default_projects_dir),
        # defaulting to the canonical /data/projects when it is unset.
        project_dir="${ACFS_PROJECTS_DIR:-/data/projects}/$project_name"
    fi

    if declare -f normalize_path &>/dev/null; then
        local resolved_project_dir=""
        resolved_project_dir=$(normalize_path "$project_dir") || true
        if [[ -n "$resolved_project_dir" ]]; then
            project_dir="$resolved_project_dir"
        fi
    fi

    # Match the wizard flow: allow only a brand-new path or an existing empty directory.
    if [[ -e "$project_dir" ]]; then
        if [[ ! -d "$project_dir" ]]; then
            echo -e "${RED}Error: Path exists but is not a directory: $project_dir${NC}" >&2
            exit 1
        fi

        if [[ ! -r "$project_dir" || ! -x "$project_dir" ]]; then
            echo -e "${RED}Error: Cannot inspect existing directory: $project_dir${NC}" >&2
            exit 1
        fi

        if [[ ! -w "$project_dir" ]]; then
            echo -e "${RED}Error: Cannot write to existing directory: $project_dir${NC}" >&2
            exit 1
        fi

        local first_entry=""
        # "$dir/." so a symlinked target directory is inspected, not the link
        # (find -P on a bare symlink start point yields nothing => "empty").
        first_entry=$(find "$project_dir/." -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) || {
            echo -e "${RED}Error: Cannot inspect existing directory: $project_dir${NC}" >&2
            exit 1
        }

        if [[ -n "$first_entry" ]]; then
            echo -e "${RED}Error: Directory already exists and is not empty: $project_dir${NC}" >&2
            echo -e "${YELLOW}Choose a new directory or move the existing contents first${NC}" >&2
            exit 1
        fi

        echo -e "${YELLOW}Warning: Directory $project_dir already exists but is empty${NC}"
    else
        local parent_dir=""
        parent_dir=$(dirname "$project_dir")
        if [[ ! -d "$parent_dir" ]]; then
            echo -e "${RED}Error: Parent directory does not exist: $parent_dir${NC}" >&2
            exit 1
        fi

        if [[ ! -w "$parent_dir" || ! -x "$parent_dir" ]]; then
            echo -e "${RED}Error: Cannot create entries in parent directory: $parent_dir${NC}" >&2
            exit 1
        fi
    fi

    echo -e "${CYAN}Creating project: $project_name${NC}"
    echo -e "${CYAN}Directory: $project_dir${NC}"
    echo ""

    # Create directory
    mkdir -p "$project_dir"
    cd "$project_dir" || {
        echo -e "${RED}Error: Failed to enter project directory: $project_dir${NC}" >&2
        exit 1
    }
    # From here on a failure leaves a partially-populated project.
    NEWPROJ_PARTIAL_DIR="$project_dir"

    # Initialize git if not already
    if [[ ! -d .git ]]; then
        echo -e "${GREEN}Initializing git repository...${NC}"
        git init -b main
        git_initialized=true
        CREATED_ITEMS+=("Git repository")

        # Create README
        echo "# $project_name" > README.md
        CREATED_ITEMS+=("README.md")

        # Create universal .gitignore (patterns that apply to ALL project types)
        cat > .gitignore << 'EOF'
# OS/Editor artifacts
.DS_Store
Thumbs.db
*~
*.swp
*.swo
.idea/
.vscode/
*.sublime-*

# Environment/secrets (never commit these)
.env
.env.*
!.env.example

# Logs
*.log
logs/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Build artifacts (add project-specific patterns below)
dist/
build/
*.pyc
__pycache__/
node_modules/
.venv/
venv/

# Local AI agent settings
.claude/settings.local.json
EOF
        CREATED_ITEMS+=(".gitignore")

        # Create universal .ubsignore (patterns for UBS bug scanner)
        cat > .ubsignore << 'EOF'
# UBS ignore globs (keep bug scanner focused on source code)
# Patterns are evaluated relative to the project root.

# Dependencies / vendored (never scan third-party code)
node_modules/
**/node_modules/

# Python virtual environments
.venv/
venv/
.tox/

# Build outputs (scan source, not artifacts)
dist/
build/
.next/
out/
target/
*.egg-info/

# Test artifacts
coverage/
.coverage
htmlcov/
.pytest_cache/
playwright-report/
test-results/

# IDE/Editor
.idea/
.vscode/

# Package manager caches
.npm/
.pnpm-store/
.yarn/
EOF
        CREATED_ITEMS+=(".ubsignore")
    else
        echo -e "${CYAN}Git already initialized, skipping${NC}"
    fi

    # Initialize beads (br) if available and not skipped
    if [[ "$skip_br" == "false" ]]; then
        if command -v br &>/dev/null; then
            if [[ ! -d .beads ]]; then
                echo -e "${GREEN}Initializing beads (br)...${NC}"
                br init
                CREATED_ITEMS+=("Beads tracking (.beads/)")
            else
                echo -e "${CYAN}Beads already initialized, skipping${NC}"
            fi
        else
            echo -e "${YELLOW}Warning: br not found, skipping beads initialization${NC}"
            echo -e "${YELLOW}Install with: curl -fsSL https://agent-flywheel.com/install | bash -s -- --yes --only stack.beads_rust${NC}"
        fi
    fi

    # Create Claude settings if not skipped
    if [[ "$skip_claude" == "false" ]]; then
        mkdir -p .claude/commands

        if [[ ! -f .claude/settings.local.json ]] && [[ ! -f .claude/settings.toml ]]; then
            echo -e "${GREEN}Creating Claude settings...${NC}"
            cat > .claude/settings.local.json << 'EOF'
{
  "permissions": {
    "allow": ["Read", "Edit", "Write", "Bash"]
  }
}
EOF
            CREATED_ITEMS+=("Claude settings (.claude/settings.local.json)")
        else
            echo -e "${CYAN}Claude settings already exist, skipping${NC}"
        fi
    fi

    # Create AGENTS.md template if not skipped
    if [[ "$skip_agents" == "false" ]]; then
        if [[ ! -f AGENTS.md ]]; then
            echo -e "${GREEN}Creating AGENTS.md template...${NC}"
            create_agents_template "$project_name"
            CREATED_ITEMS+=("AGENTS.md (template)")
        else
            echo -e "${CYAN}AGENTS.md already exists, skipping${NC}"
        fi
    fi

    if [[ "$git_initialized" == "true" ]]; then
        git add -A

        # Check if git user is configured before committing
        if git config user.name &>/dev/null && git config user.email &>/dev/null; then
            if ! git diff --cached --quiet --ignore-submodules; then
                git commit -m "Initial commit"
            fi
        else
            echo -e "${YELLOW}Warning: Git user not configured, skipping initial commit${NC}"
            echo -e "${YELLOW}Run: git config --global user.name \"Your Name\"${NC}"
            echo -e "${YELLOW}     git config --global user.email \"you@example.com\"${NC}"
        fi
    fi

    # Print summary of what was created
    echo ""
    if [[ ${#CREATED_ITEMS[@]} -gt 0 ]]; then
        echo -e "${GREEN}Created:${NC}"
        for item in "${CREATED_ITEMS[@]}"; do
            echo -e "  ${GREEN}✓${NC} $item"
        done
    fi

    echo ""
    NEWPROJ_PARTIAL_DIR=""
    echo -e "${GREEN}Project $project_name ready at $project_dir${NC}"
    echo ""
    echo "Next steps:"
    echo "  cd $project_dir"
    if [[ "$skip_agents" == "false" ]] && [[ -f AGENTS.md ]]; then
        echo "  # Edit AGENTS.md to customize for your project"
    fi
    if [[ "$skip_br" == "false" ]] && command -v br &>/dev/null; then
        echo "  br ready                    # Check for work"
        echo "  br create --title=\"...\"    # Create tasks"
    fi
    echo "  cc                          # Start Claude Code"
}

# Only run main if script is executed directly, not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Only the executed script owns the EXIT trap; a sourcing caller (tests)
    # must not have its shell's traps replaced.
    trap _newproj_report_partial_on_exit EXIT
    main "$@"
fi
