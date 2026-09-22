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
`starter`, `ci`, `prompt`, and `agent-mail`. The last requires `--agent-mail URL`.
Selecting `ci` also requires explicitly selecting
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
Agent launch remains manual. Agent Mail project registration is a separate,
explicit option described below; enabling Beads alone never enables it.

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

No model requests, package installation, Git staging, commits,
pushes, global agent configuration changes, or permission bypasses are initiated.
Remote project registration occurs only when Agent Mail is explicitly selected.
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

## Connect the first project to Agent Mail

`--agent-mail URL` is an explicit opt-in to network access. It adds the exact
`ensure_project(human_key=<canonical project path>)` request to the reviewed
plan, a project-local Claude Code `.mcp.json`, and `AGENT_MAIL.md` with the
per-session registration, inbox, Beads-thread and file-reservation workflow.
The configuration is ignored by Git and contains no credential values.
Without this option the bootstrap remains offline.

```sh
acfs newproj --plan myapp /data/projects/myapp --preset first-project --beads \
  --agent-mail http://127.0.0.1:8765/api/ \
  --agent-mail-token-env AGENT_MAIL_TOKEN > /tmp/myapp-plan.json
# Review the plan. Supply AGENT_MAIL_TOKEN through your secret manager or an
# existing private shell environment, not a literal command in shell history.
acfs newproj --apply /tmp/myapp-plan.json --yes
```

Use the service's actual endpoint, including the trailing slash. Plain HTTP is
accepted only for literal loopback IPs; other destinations require HTTPS and
an explicitly named authentication environment variable. For a deliberately
unauthenticated loopback service, omit `--agent-mail-token-env`. Ambient bearer
tokens, `.env` files, and HTTP proxy variables are not imported automatically.

A missing credential fails before creating the project. An unavailable server,
HTTP error, malformed result, or response naming a different project fails
without claiming registration succeeded. Files and local Git/Beads setup remain
available; fix the service/credential and resume the **same** plan:

```sh
acfs newproj --apply /tmp/myapp-plan.json --yes --resume
```

Completed registration is checkpointed and is not repeated on resume. A lost
response can safely repeat `ensure_project`: that operation is idempotent for
the same canonical project key. Remote writes are not rolled back. The client
uses Agent Mail's stateless JSON HTTP API, with no redirects, bounded response
size, connection timeout and total deadline. It does not support an arbitrary
SSE-only MCP service. Error responses and credential values are never printed.

After apply, start Claude Code from the project, approve its project-local MCP
server, and use `FIRST_AGENT_PROMPT.md`. Export the same credential environment
variable for the client. For Codex or Gemini, select their project-local
configuration explicitly as described below. Global settings are never changed.

Bootstrap registers a **project**, not an agent impersonating your session.
Each real agent calls `register_agent` with its actual program and model, keeps
its own returned registration token private, and checks its inbox. It must wait
for approved work before sending messages or reserving files. No model, agent,
server installer, message send, file lease, commit or push is started by apply.

The HTTP integration tests use a real loopback HTTP server with contract
fixtures, not a running Agent Mail deployment or a live Claude session:

```sh
python3 -B tests/unit/test_project_bootstrap_mail.py
```

## Configure multiple agent clients for the same project

Select the clients explicitly when creating the plan:

```sh
acfs newproj --plan myapp /data/projects/myapp --preset first-project --beads \
  --agent-mail http://127.0.0.1:8765/api/ \
  --agent-mail-token-env AGENT_MAIL_TOKEN \
  --agent-mail-clients claude,codex > /tmp/myapp-plan.json
cat /tmp/myapp-plan.json
acfs newproj --apply /tmp/myapp-plan.json --yes
```

Any non-empty subset of `claude,codex,gemini` is supported. Gemini remains an
optional client: selecting it here does not install or promote it to a default
ACFS agent. Unknown, duplicate, or empty selections fail before mutation. The
selection requires `--agent-mail URL`, belongs to the reviewed plan, and cannot
be overridden at apply time. Configuration is created only for selected clients:

| Client | Project-local configuration | Authentication reference | Shared policy |
| --- | --- | --- | --- |
| Claude Code | `.mcp.json` | `Authorization: Bearer ${NAME}` | `CLAUDE.md` imports `AGENTS.md` |
| Codex | `.codex/config.toml` | `bearer_token_env_var = "NAME"` | Native `AGENTS.md` discovery |
| Gemini CLI | `.gemini/settings.json` | HTTP `headers.Authorization` environment reference | `context.fileName` includes `AGENTS.md` and `GEMINI.md` |

Policy integration is emitted only when the `agents` feature is selected; a
minimal file-only selection never imports a nonexistent AGENTS file. The Claude
import supports sessions without native AGENTS discovery and does not copy the
policy. Gemini retains its native GEMINI.md discovery alongside the shared policy.
All connection files are ignored by Git. No credential values are stored, and
unauthenticated loopback configurations do not import ambient token variables.

The project is registered **once**, not once per client. An interrupted apply
can resume the same plan without rewriting matching client files or repeating
completed registration. Edited or redirected client configuration stops resume
before another network request or creation of missing planned files.

After apply, launch the chosen client from the project root and follow the
client-specific steps in `AGENT_MAIL.md`. Codex must trust the project before it
loads `.codex/config.toml`; bootstrap does not grant that trust. Use `/mcp` in
the client to check connectivity. Configuration presence alone is not proof of
a live connection. Each session still registers its own Agent Mail identity.
There are no model calls, automatic logins, tool-approval bypasses, global MCP
writes, agent launches, message sends, or file reservations during bootstrap.

Omitting `--agent-mail-clients` preserves the earlier Claude-only template and
plan shape, so previously reviewed plans remain usable with this extension.
Choosing `--agent-mail-clients claude` explicitly adds the new policy handoff;
it is a new plan, not an override for an old interrupted apply.

Native formats were checked against the official [Codex MCP documentation](https://developers.openai.com/codex/mcp),
[Claude instruction-file documentation](https://code.claude.com/docs/en/memory),
[Gemini MCP documentation](https://geminicli.com/docs/tools/mcp-server/), and
[Gemini configuration reference](https://geminicli.com/docs/reference/configuration/).

The client suite uses Python 3.11+ for standard-library TOML parsing, the real
shell entrypoint, Git, and a real loopback HTTP contract fixture. It does not
launch installed provider clients or replace live client/service acceptance:

```sh
python3 -B tests/unit/test_project_bootstrap_clients.py
```
