# Eidetic Engine (ee)

Local-first, durable memory for coding agents: you record lessons explicitly, and
ee hands back the relevant ones for each task with a note on why each was chosen.

This page was written against ee 0.18.0 (`ee --version`). ACFS installs ee with
the `stack.eidetic_engine_cli` module, which is optional and enabled by default,
and `acfs update` reinstalls it from ee's release installer. The full command
reference is ee's [README](https://github.com/Dicklesworthstone/eidetic_engine_cli)
and `ee <command> --help`.

## What It Does

- Stores typed memories. Each has a **level** (`working`, `episodic`, `semantic`,
  `procedural`) and a **kind** (`rule`, `fact`, `decision`, `failure`, `command`,
  `convention`, `anti-pattern`, `risk`, `playbook-step`).
- Keeps one store per project (`<project>/.ee/ee.db`) plus an optional user-global
  lane shared by all of your projects.
- Retrieves with lexical plus local semantic search. Without the local embedding
  model it falls back to lexical search and says so.
- Builds token-budgeted context packs (`ee pack`) in which every item carries its
  provenance and the reason it was selected (`ee why <id>`).
- Records revisions, expirations and curation decisions in an audit trail instead
  of rewriting memories silently.
- Runs as one-shot commands: no daemon, no cloud service, no API key.

## ee and cm

ACFS installs two memory tools, and they overlap: both keep rules learned from past
work, both track whether a rule helped, and both can draw on cass session history.

| | cm (cass-memory) | ee |
|---|---|---|
| ACFS module | `stack.cm`, always installed | `stack.eidetic_engine_cli`, optional, on by default |
| How lessons get in | `cm reflect` extracts rules from recent agent sessions; `cm playbook add` adds one by hand | You or the agent record them with `ee remember`; imported cass sessions and the journal can propose more, which you review |
| Where they live | A global playbook (`~/.cass-memory/playbook.yaml`), plus a per-repo playbook in repos with a `.cass/` directory | A store per project, plus an optional user-global lane |
| Before a task | `cm context "<task>" --json` | `ee pack "<task>" --workspace . --format markdown` |
| Feedback | `cm mark <bullet-id> --helpful` or `--harmful` | `ee outcome <memory-id> --signal helpful` or `harmful` |

Recommendation:

- **Keep the core loop's cm steps.** cm is the memory layer ACFS always installs,
  and the onboarding lessons use it. `cm context` before a task and `cm reflect`
  after a session stay as they are whether or not you use ee.
- **Add ee for project knowledge you want to record on purpose and audit later:**
  decisions and why they were made, failures and their causes, commands that work,
  and project conventions. Run `ee pack` next to `cm context` before substantive
  work.
- **Write each lesson in one place.** Recording the same rule in both tools gives
  agents two copies to keep in sync. A split that works: cm's playbook holds what
  `cm reflect` extracts from sessions, and the project's ee store holds what you
  record deliberately. For a rule that applies to all of your projects, use either
  cm's global playbook or ee's global lane, not both.
- **Treat recalled memory as advisory.** The live `AGENTS.md`, README and repository
  state win over anything either tool recalls.

## Installation Verification

```bash
ee --version
ee doctor --workspace /data/projects/myproject   # once the project has a store
```

`ee doctor` prints a compact posture report; `ee doctor --full --json` has every
check.

## Setting Up a Project Store

Create the store once, at the project's permanent location:

```bash
cd /data/projects/myproject
ee init --workspace . --force --skip-boilerplate
```

- `ee init` creates `.ee/ee.db` and an empty search index in `.ee/index/`.
  Retrieval works as soon as the first memory is stored.
- In a directory without `AGENTS.md` or `CLAUDE.md`, plain `ee init --workspace .`
  writes short boilerplate versions of both. When `AGENTS.md` already exists,
  `ee init` stops and asks for `--force`; with `--force` it leaves the existing
  file unchanged. `--skip-boilerplate` keeps it from writing either file.
- Add `.ee/` to the project's `.gitignore`. It holds the database, the index and
  the store's authentication keys (`.ee/keys/`), which are local state, not source.
- The store records the absolute path it was created for. A copied or moved `.ee`
  directory refuses to open with a workspace identity mismatch; recovering it
  takes an explicit `ee workspace rebind` (see ee's README). Create stores in the
  real project directory, not in a temporary clone.
- ee works on the current directory by default; pass `--workspace <path>` when an
  agent runs from elsewhere.
- The first command that needs embeddings (usually the first `ee remember`)
  downloads ee's pinned local embedding model once, about 500 MB, into
  `~/.local/share/ee/models/`. Set `EE_EMBED_DOWNLOAD=off` to forbid that download;
  ee then keeps working with lexical search and says so. If `ee init` or
  `ee doctor` reports that semantic retrieval is off, `ee index reembed --workspace .`
  re-embeds the store with the local model.

## Basic Usage

### Record a Memory

```bash
# A durable rule
ee remember --workspace . --level procedural --kind rule --tags release,ci \
  "Run cargo test and clippy with --all-targets before tagging a release; cargo check misses test-only compile errors."

# A failure and its cause
ee remember --workspace . --kind failure \
  "The 0.4.2 release failed because the changelog step ran before the version bump."

# The same lesson seen again: strengthen the existing memory instead of adding a copy
ee remember --workspace . --reinforce "<text of the existing lesson>"
```

Without flags a memory is `episodic` and of kind `fact`. `ee remember` refuses
content that looks like a secret, such as an API key.

### Retrieve

```bash
ee pack "prepare the next release" --workspace . --max-tokens 4000 --format markdown
ee search "release tagging" --workspace . --limit 20 --explain
ee why <memory-id> --workspace .
```

`ee pack` is the call to make before a task: Markdown is its most compact output.
`ee search` is for a specific question, and `ee why` explains where a memory came
from and how it scores.

### Advisory Check Before a Risky Command

```bash
ee preflight check --cmd "git push --force origin main" --workspace .
```

It reports matching risks, failures and anti-patterns. It never blocks anything;
dcg is the tool that blocks destructive commands.

## What Is Worth Remembering

Good memories are specific, durable and checkable:

- a rule with its reason ("integration tests need the Docker socket; without it they
  hang instead of failing");
- a decision with the alternatives that were rejected;
- a failure with its cause and the fix;
- a command that works here, and when to use it;
- a project convention an agent would otherwise have to rediscover.

Leave out:

- **Session narration** ("I read the file, then I ran the tests"). For raw
  observations, use `ee journal append "<text>" --workspace .`;
  `ee journal distill --workspace . --dry-run` shows which entries carry enough
  signal to become curation candidates.
- **Anything already in `AGENTS.md`.** It is loaded every session anyway, and two
  copies drift apart. Fix `AGENTS.md` instead.
- **One-off details** that will not matter on the next task, such as a temporary
  path or a branch name.
- **Secrets.** ee refuses them; keep them out of the text in the first place.

## Where Memories Live

| Lane | Location | Put here |
|---|---|---|
| Project | `<project>/.ee/ee.db` | Anything specific to this repository: build quirks, decisions, failures, commands, conventions |
| User-global | `~/.local/share/ee/global/` (or `$XDG_DATA_HOME/ee/global/`) | Rules that hold in every project you work on |

```bash
# Record a cross-project rule directly in the global lane
ee remember --global --level procedural --kind rule \
  "Never force-push a shared branch; push a follow-up commit instead."

# Copy an existing project memory into the global lane
ee memory promote-global <memory-id> --workspace . --dry-run
```

`ee search` and `ee pack` in any project include matching global-lane memories,
labeled as global. When a project memory and a global memory say exactly the same
thing, the project one wins. To keep the global lane out of one project, set
`include_global = false` under `[memory]` in that project's `.ee/config.toml`.
Promotion copies the memory and keeps the project row. Only memories with trust
class `human_explicit` (what `ee remember` records) or `agent_validated` qualify;
`--dry-run` shows the verdict without writing.

## ee in the Bead Loop

```bash
br ready --json                                      # pick work
br update <id> --status in_progress                  # claim it
cm context "<bead title>" --json                     # cm's rules for the task
ee pack "<bead title and goal>" --workspace . --max-tokens 4000 --format markdown

# ...implement, test, scan with ubs...

ee remember --workspace . --level procedural --kind rule "<lesson worth keeping>"
ee outcome <memory-id> --workspace . --signal helpful --reason "<what it changed>"
br close <id>
```

- Run `ee pack` after claiming a bead and before writing code, using the bead's
  title and goal as the query.
- Record lessons as you learn them or at the latest before `br close`, while the
  details are fresh.
- Use `ee outcome` when a recalled memory changed what you did (`helpful`) or led
  you astray (`harmful`). Outcomes are how good memories stay ranked high.
- `ee resume --workspace .` is a read-only summary of recent memories and open
  decisions for an agent picking up after a context reset.

### Swarms

Agents working in the same checkout share that checkout's store: each runs ee
with the same `--workspace`, and several agents can record memories at once. Set
`EE_AGENT_NAME` for each agent so outcomes are attributed to it.

`ee swarm brief --workspace . --json` is a read-only snapshot of a crowded checkout
(git state, beads, rch, Agent Mail if a snapshot is available). It changes nothing;
bv and Agent Mail remain the tools for choosing and reserving work. The `ee team`
commands share memories between people's machines over ee's mesh; agents on one
host do not need them.

## Keeping Memories Correct

| Situation | Command | Effect |
|---|---|---|
| The lesson is right but the wording or a detail is wrong | `ee memory revise <id> --workspace . --content "<corrected text>" --reason correction` | Creates a new revision with a new ID; the old version stays on record (`ee memory history <new-id>` shows the revision) and drops out of search and packs |
| It was true and no longer is | `ee memory expire <id> --workspace . --reason "<why>"` | Ends the memory's validity; it stays on record but leaves search and packs |
| You learned something different, or the old memory still holds where it applies | `ee remember ...` | New memory |
| The same lesson came up again | `ee remember --reinforce "<text>"` | Strengthens the closest near-duplicate instead of adding a copy |
| A memory misled you | `ee outcome <id> --signal harmful --reason "<why>"` | Lowers its scores; harmful feedback counts for more than helpful |

Curation is review, not automation. Proposals from `ee review session` (imported
cass sessions), `ee journal distill` and other sources wait in a queue until you act:

```bash
ee curate candidates --workspace .            # what is waiting
ee curate validate <candidate-id> --workspace .
ee curate apply <candidate-id> --workspace .  # or: ee curate reject <candidate-id>
ee curate doctor --workspace .                # read-only memory-debt report
```

`ee curate doctor` ranks memories that need attention: unresolved contradictions,
stale anchors, memories that are never retrieved or have no links, low-trust
memories that rank high, and useful memories whose confidence is about to decay.

Confidence decay is applied by the `decay_sweep` maintenance job. ee runs no
background process by default, so run it now and then, for example weekly:

```bash
ee maintenance run --workspace . --dry-run   # preview
ee maintenance run --workspace .
```

## Maintenance After Upgrading ee

`acfs update` installs the new ee binary but does not migrate existing stores.
When a release changes the database schema, commands against an older store stop
and ask for a migration (`ee migrate status --workspace .` shows what is pending).
`ee init` does not add stores to `ee workspace list`, so find them on disk:

```bash
for db in /data/projects/*/.ee/ee.db; do
  [ -f "$db" ] || continue
  ws="${db%/.ee/ee.db}"
  ee migrate run --workspace "$ws" && ee doctor --workspace "$ws"
done

# The global lane, if you have used it
g="${XDG_DATA_HOME:-$HOME/.local/share}/ee/global/ee.db"
if [ -f "$g" ]; then ee migrate run --database "$g"; fi
```

`ee migrate run` applies pending migrations and rebuilds the store's index; on a
current store it changes nothing. Until the global lane is migrated, project
searches skip it and report `global_lane_migration_required`. If `ee doctor`
reports a stale index at any other time, run `ee index rebuild --workspace <path>`.

## Optional: Importing cass History

ACFS installs cass in `~/.local/bin`, and ee only runs a `cass` binary from
`/usr/local/bin`, `/usr/bin` or `/opt/homebrew/bin` unless you name it, so that a
writable home directory cannot make ee run a planted binary. Name it once in your
user config (a project's `.ee/config.toml` cannot set this). If that file already
has a `[cass]` section, add the `binary` line there instead:

```bash
mkdir -p ~/.config/ee
printf '[cass]\nbinary = "%s/.local/bin/cass"\n' "$HOME" >> ~/.config/ee/config.toml
```

Then:

```bash
ee import cass --workspace . --limit 50 --dry-run --json   # what would be imported
ee import cass --workspace . --limit 50 --json
ee index rebuild --workspace .
```

Imported excerpts become searchable evidence that `ee search` and `ee pack` can
return. They become durable memories only through review:
`ee review session <session-id> --workspace . --propose`, then the curation
commands above.

## Troubleshooting

### `ee init` fails with "Existing agent guidance requires explicit initialization intent"

The project already has an `AGENTS.md`. Re-run with `--force`; the file is left
unchanged. Add `--skip-boilerplate` to keep ee from writing a `CLAUDE.md` too.

### "migration required" after an update

Run `ee migrate run --workspace <path>` for each store, and for the global lane as
shown under [Maintenance After Upgrading ee](#maintenance-after-upgrading-ee).

### "The addressed local store contains a different workspace identity"

The `.ee` directory was copied or moved from another path. See the section on
moved stores and `ee workspace rebind` in ee's README.

### `ee import cass` says cass is outside the trusted allowlist

Set `[cass] binary` in `~/.config/ee/config.toml` as shown above, or set
`EE_CASS_BINARY` to the absolute path for a single command.

## Related Tools

- `cm` - procedural memory distilled from agent sessions; the default memory step
  in the flywheel loop
- `cass` - search across agent session history; ee can import from it
- `br` / `bv` - the task graph that ee memories are recorded against
- `dcg` - blocks destructive commands; `ee preflight` only advises
