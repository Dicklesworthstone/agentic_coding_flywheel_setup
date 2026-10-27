# Starting Projects with ACFS

**Goal:** Create new projects with full ACFS tooling using `acfs newproj`.

---

## Why Use `acfs newproj`?

When you create a project with `ntm spawn`, you get a tmux session with agents.
But agents work better when they have:

- **AGENTS.md** - Project-specific guidance for AI agents
- **Beads (br)** - Local issue tracking for planning and progress
- **Claude settings** - Project-specific Claude Code configuration
- **Proper .gitignore** - Ignores build artifacts, secrets, etc.

`acfs newproj` sets all of this up automatically.

---

## Quick Start

### Interactive Mode (Recommended)

```bash
acfs newproj --interactive
```

Or the short form:

```bash
acfs newproj -i
```

This launches a TUI wizard that guides you through setup.

### CLI Mode

```bash
acfs newproj myproject
```

Creates `/data/projects/myproject` with full tooling.

### Reviewed Setup and Optional GitHub Publication

Use the reviewed guide when you want to inspect the planned files and operations before creation:

```bash
acfs newproj --guided
```

The guide creates a local project by default. You can explicitly select a private or public GitHub
repository, enter its exact `OWNER/REPO` destination, and optionally register it with `ru`. Review the
summary before choosing `create`; `save` keeps only the private plan so you can apply it later.

For the same workflow from the command line, replace `OWNER` with your GitHub account or organization:

```bash
acfs newproj --plan myapp --preset first-project --stack python \
  --github=private --github-repo OWNER/myapp --ru > myapp-plan.json
cat myapp-plan.json
acfs newproj --apply myapp-plan.json --yes
```

`--plan` is offline and creates nothing. `--apply ... --yes` authorizes the specific repository creation,
initial commit/push, and registration listed in that plan. Use `--github=public` only when you intend
to publish the listed files publicly. Omit `--github`, `--github-repo`, and `--ru` for a local-only plan.
The older CLI and `--interactive` modes remain local-only.

GitHub publication requires an installed, authenticated `gh` CLI and permission to create the named
repository. If needed, run `gh auth login --hostname github.com` first. `--ru` also requires
`repo_updater`; it cannot be selected without GitHub publication. The plan must include the `git`
feature, as `--preset first-project` does. Authentication and name-conflict checks run before the local
project is created.

Only the listed generated files are committed and pushed to `main`. Private recovery state, Agent Mail
connection settings, Beads runtime metadata, and unrelated files are excluded. The generated
`AGENTS.md` still requires your permission for future pushes.

If a push or `ru` registration fails after repository creation, the error reports what succeeded.
Keep the project and its plan, resolve the reported problem, then resume:

```bash
acfs newproj --apply myapp-plan.json --yes --resume
```

Resume checks the original destination, visibility, files, and initial commit; it does not overwrite
edits or force-push. If the repository was created but its GitHub ID could not be saved, the workflow
stops for manual review rather than assuming a same-name repository is safe to use. It never deletes
the local project or remote repository as rollback.

`--ru` adds the repository to the appropriate private/public list using the configuration and state
directories recorded in the plan. It does not sync repositories or change `ru`'s clone layout. A custom
local project path does not override where a later `ru sync` will look for that repository.

---

## What Gets Created

```
myproject/
├── .git/              # Git repository initialized
├── .beads/            # Local issue tracking
├── .claude/           # Claude Code settings
├── AGENTS.md          # Instructions for AI agents
└── .gitignore         # Standard ignores
```

---

## Custom Directory

By default, projects go to `/data/projects/<name>`.

Specify a different location:

```bash
acfs newproj myproject ~/code/myproject
```

Creates `~/code/myproject`; the positional path is the exact project directory, and its parent must
already exist.

---

## Options

| Flag | Effect |
|------|--------|
| `--interactive` | TUI wizard (recommended for first use) |
| `--no-br` | Skip beads initialization |
| `--no-claude` | Skip Claude settings |
| `--no-agents` | Skip AGENTS.md creation |
| `--guided` | Review, save, and apply a project plan in the terminal |
| `--plan NAME --preset first-project` | Print an offline JSON plan with starter files and checks |
| `--github=private\|public --github-repo OWNER/REPO` | Explicitly select repository creation and initial publication in a plan |
| `--ru` | Also register the selected GitHub repository with `repo_updater` |
| `--apply PLAN.json --yes` | Authorize the reviewed plan's operations |
| `--apply PLAN.json --yes --resume` | Continue the same interrupted plan after checking existing work |

---

## The Full Workflow

1. **Create project:**
   ```bash
   acfs newproj myapp -i
   ```

2. **Spawn agents:**
   ```bash
   ntm spawn myapp --cc=2
   ```

3. **Attach and work:**
   ```bash
   ntm attach myapp
   ```

The key insight: `acfs newproj` prepares the project, `ntm spawn` starts agents.

---

## AGENTS.md

This file tells agents how to work in your project:

```markdown
# Project: myapp

## Language/Framework
- TypeScript with Bun

## Commands
- `bun dev` - Start dev server
- `bun test` - Run tests

## Conventions
- Use functional components
- Tests in __tests__ directories
```

Agents read this file and follow its instructions!

---

## Beads Integration

Projects created with `acfs newproj` include beads (br) for issue tracking:

```bash
# Create an issue
br create "Set up authentication"

# List issues
br list

# See ready work (unblocked issues)
br ready
```

This integrates with `bv` (Beads Viewer) for visualization and graph analysis.

---

## Try It Now

```bash
# Create a test project
acfs newproj test-project -i

# Explore what was created
ls -la /data/projects/test-project
cat /data/projects/test-project/AGENTS.md

# Archive it when done, instead of deleting it
mv /data/projects/test-project /data/projects/test-project.archived.$(date +%Y%m%d_%H%M%S)
```

---

## Next

Ready to spawn agents in your new project:

```bash
onboard 5
```
