# Create your first project with the terminal guide

Start the reviewed beginner workflow with one command:

```sh
acfs newproj --guided
```

The guide asks for a project name, destination, and Python or TypeScript
starter. Beads task tracking and Agent Mail coordination are separate, optional
choices. The destination's parent must already exist. The project itself must
be absent or empty; this is not a migration tool for an existing repository.

Nothing is created while answering questions. The review screen lists the
selected features, every file and its hash, local commands, any Agent Mail
request, and the private recovery plan's location. It distinguishes creating
the project from running its tests. Choose one of four actions:

| Action | Result |
| --- | --- |
| `details` | Show the full JSON plan, including exact file contents, without writing anything. |
| `create` | Save the reviewed plan privately, then apply it using the existing bootstrap engine. |
| `save` | Save only the plan; do not create the project or contact Agent Mail. |
| `cancel` or Enter | Exit without writing files or running commands. |

The default action is cancellation. Ctrl-C or terminal EOF also stops the guide.
`--guided` requires terminal input and terminal stderr; piped answers are not
accepted as authorization. Prompts go to stderr and the final result is JSON on
stdout. `--guided --help` works without a terminal. Other options, including
`--yes`, cannot override the guide's choices or confirmation. For automation,
use the existing [explicit plan/apply workflow](project-bootstrap.md).

## What you get

The first-project preset creates a local Git repository on `main`, README,
`.gitignore`, AGENTS policy, starter source and three tests, `scripts/check.sh`,
and `FIRST_AGENT_PROMPT.md`. Python uses the standard library; TypeScript uses
Bun. No dependency installation, model call, agent launch, global settings
change, Git staging, commit, or push is performed.

Selecting Beads adds reviewed `br init` and its verification probe. Selecting
Agent Mail asks for the actual service URL, the **name** of a credential
environment variable, and the chosen clients. Never enter a credential value.
The existing transport and native client configuration rules apply. A saved
plan contains environment references, not tokens. Saving a plan is offline;
`create` requires the selected tools and credentials before writing the plan or
creating the project. Bootstrap does not install or start a missing service.

## Verify and start work

After successful creation, the guide prints the next commands:

```sh
cd /data/projects/myapp
sh scripts/check.sh
```

Use the actual destination you selected. Review `FIRST_AGENT_PROMPT.md` before
starting an agent. For Agent Mail, follow `AGENT_MAIL.md` to approve the client's
project trust, check connectivity, and register a separate identity for each
session. Configuration presence is not proof of a live client connection.

## Resume without losing work

The default saved plan is a sibling named `.myapp-acfs-plan.json`, not a file
inside the new repository. A different existing parent directory can be chosen.
Plans contain local paths and filesystem identities; keep them private. They
are created with mode 0600 and are never overwritten, including through a
symlink. A destination or plan-directory change during review stops creation.

The guide prints recovery commands before applying anything. A tool or service
failure retains the plan and partial project. Fix the cause, then use that same
plan and ACFS version:

```sh
acfs newproj --apply /data/projects/.myapp-acfs-plan.json --yes --resume
```

For a saved-only plan, omit `--resume` on its first apply. Existing matching
files and completed tool operations are reused. Edited planned files are not
overwritten. No automatic deletion or rollback is attempted. An interruption
before the bootstrap's first checkpoint still requires manual inspection, as
with the explicit workflow.

## Validation

```sh
python3 -B tests/unit/test_project_bootstrap_guided.py
python3 -B tests/unit/test_project_bootstrap.py
bash -n scripts/lib/newproj.sh
```

The guide tests use actual pseudo-terminals, the shell entrypoint, filesystem
operations, Git, and the generated Python tests. They cover confirmation,
cancellation, EOF, interruption, private plan publication, concurrent changes,
optional features, and failure recovery. They do not launch provider clients or
replace live Agent Mail, Bun, and Beads acceptance testing.
