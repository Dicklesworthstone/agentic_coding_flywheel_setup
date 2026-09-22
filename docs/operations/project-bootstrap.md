# Reviewed first-project bootstrap

`acfs newproj` now has an explicit plan/apply path for the first working project
after installation. The existing positional CLI and interactive wizard are
unchanged. Put `--plan` or `--apply` first to enter the reviewed workflow.

## Create a project

Choose an existing parent directory. Keep the plan outside the destination.

```sh
acfs newproj --plan myapp /data/projects/myapp \
  --preset first-project --stack python > /tmp/myapp-plan.json

# Read the entire plan before authorizing it.
cat /tmp/myapp-plan.json
acfs newproj --apply /tmp/myapp-plan.json --yes
cd /data/projects/myapp
sh scripts/check.sh
```

The preset explicitly selects a local Git repository on `main`, README,
`.gitignore`, project-specific AGENTS policy, starter source and three tests,
a portable verification script, and a first-agent prompt. The Python starter
uses only the standard library. Select `--stack typescript` for a Bun project
with `bun:test` checks and no external dependencies. Bootstrap does not install
a missing runtime. `ci` means the portable `scripts/check.sh` entrypoint; it
does not create a hosted CI workflow.

For a narrower operation, select individual features rather than the preset:

```sh
acfs newproj --plan notes /data/projects/notes --with readme,agents \
  > /tmp/notes-plan.json
acfs newproj --apply /tmp/notes-plan.json --yes
```

Available features are `git`, `beads`, `readme`, `gitignore`, `agents`,
`starter`, `ci`, and `prompt`. Selecting `ci` also requires explicitly selecting
`starter`; selecting `beads` requires explicitly selecting `git`.

## Optional Beads initialization

```sh
acfs newproj --plan myapp /data/projects/myapp \
  --preset first-project --stack python --beads > /tmp/myapp-plan.json
acfs newproj --apply /tmp/myapp-plan.json --yes
```

Beads is off unless requested. With it selected, the plan lists `br init`, its
`.beads/` write scope, and the `br ready --json` verification probe. The local
`br` executable must already be installed. No issues are invented or claimed;
the generated policy and prompt explain how to agree on the first task.
Agent Mail registration and agent launch are not performed automatically.

## Review and execution boundaries

The plan contains exact file bytes, modes, SHA-256 hashes, allowed command argv,
target directory identities, and the `.acfs/bootstrap-state.json` checkpoint
path. Its deterministic digest detects changes; it is not a signature or a
substitute for reviewing the plan. Apply reconstructs the expected plan from
the installed templates, so editing and rehashing a command or file does not
make arbitrary content executable. After an ACFS template update, regenerate
and review the plan instead of editing its digest.

A destination must be absent or an existing empty directory. Files are created
exclusively rather than overwritten, and path traversal does not follow
symlinks. An advisory directory lock prevents concurrent cooperative applies.
Inherited Git and Beads override variables are removed from child processes;
Git templates and global/system Git configuration are disabled for init.
Tools use fixed argument arrays with bounded execution, not shell evaluation.
Installed `git` and `br` remain trusted executables: this is not a sandbox for
malicious tools or an untrusted user concurrently modifying the project.

No model requests, package installation, remote setup, Git staging, commits,
pushes, global agent configuration changes, or permission bypasses are initiated.
Generated checks and `FIRST_AGENT_PROMPT.md` are offered for separate review and
execution. Plans contain local absolute paths and filesystem identities; treat
them as local artifacts, not redacted support bundles.

## Resume an interrupted apply

```sh
acfs newproj --apply /tmp/myapp-plan.json --yes --resume
```

Use the same reviewed plan and installed ACFS version. The checkpoint is
private to the project, written with mode 0600, and updated atomically after
each file and command. Resume validates the plan and directory identity, checks
all existing planned file contents before writing missing files, and does not
rewrite matching files or repeat completed tool commands. A Beads init that
completed just before its checkpoint is verified rather than repeated.

Edited planned files, mismatched checkpoints, and unsafe tool metadata stop
resume. Nothing is automatically deleted or rolled back. Preserve user changes
and inspect the reported partial project before deciding how to recover. An
interruption before the first checkpoint requires manual review; `--resume`
does not adopt arbitrary existing projects. Temporary checkpoint files from an
interrupted write are retained and ignored by the generated `.gitignore`.

## Tests

```sh
python3 -B tests/unit/test_project_bootstrap.py
bash -n scripts/lib/newproj.sh
```

The suite invokes the real shell entrypoint and uses real filesystem operations,
Git initialization, and generated Python checks. Beads failure/recovery uses an
explicit executable contract fixture, not a real Beads database. The TypeScript
source is also executed through Node's type stripper where available; that is
not a substitute for running the generated suite with Bun. Live `br` and Bun
validation remain required before claiming those integrations are fully tested.
