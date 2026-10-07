# Install the fleet controllers without retaining a checkout

`acfs-fleet` provides one installed entrypoint for the existing fleet `launch`,
`prepare`, `dispatch`, `status`, `collect`, `test`, and `publish` controllers. Install it explicitly from a trusted,
complete ACFS checkout on a Linux controller with Python 3.9 or newer. It does
not replace `acfs`, change the one-line installer, or install anything remotely.

## Preview and install

Choose existing user-owned directories that are not group/world-writable. For
example, after creating `$HOME/.acfs/fleet` and `$HOME/.local/bin` yourself:

```bash
python3 -I scripts/acfs-fleet.py install \
  --prefix "$HOME/.acfs/fleet" --bin-dir "$HOME/.local/bin"
```

This reads and syntax-checks the frontend and seven controller files, reports a content-derived
runtime ID and an installation plan digest, and creates nothing. Review the
paths, files and previous launcher. Repeat the command with
`--apply --accept-plan THE_RETURNED_DIGEST` to install, as the target user without
sudo. Installation performs no network access and launches no agents or prompts.
The source checkout is a code trust decision; hashes are not publisher signatures.

The prefix contains `releases/RUNTIME_ID/`, holding the frontend, seven complete
controllers and a hash/size manifest. The release directory and entrypoint are
mode 0500; remaining files are mode 0400. A symlink named `acfs-fleet` in the
selected bin directory points to the completed release. Ensure that directory
is on PATH; the installer does not edit shell startup files.

## Use the existing workflows

```bash
acfs-fleet version
acfs-fleet launch --help
acfs-fleet prepare --help
acfs-fleet dispatch --help
acfs-fleet status --help
acfs-fleet collect --help
acfs-fleet test --help
acfs-fleet publish --help
```

All options after the command are forwarded literally to the corresponding
controller. Standard input, current directory, terminal and exit/signal status
are preserved. There is no new approval parser or implicit `--launch`,
`--prepare`, `--send`, `--collect`, `--run`, `--push`, or `--resume`. The launch/dispatch controllers' previews
can open SSH connections; preparation's preview stays local. Their normal
explicit approvals, trust files, receipt rules and recovery limitations remain.
The status observer opens read-only SSH queries against the original fleet; it
cannot launch agents or send work. It keeps agent liveness, historical submission
receipts, and exported Bead state separate. See [fleet status](swarm-fleet-status.md)
and the existing fleet launch, preparation and dispatch operating guides.

The [collector](swarm-fleet-collection.md) reads explicitly selected committed
ranges from the original fleet repositories. Its preview opens SSH connections
but creates nothing; `--collect --accept-plan SHA256` saves private incremental
Git bundles. `acfs-fleet collect --verify DIRECTORY` checks a saved collection
offline. Its separate offline import and [integration](swarm-fleet-integration.md)
modes need their own explicit approvals before publishing new review/candidate
refs; they do not change the working checkout or execute project code.
Committed history is not redacted; review it before sharing any bundle.

The [test runner](swarm-fleet-testing.md) closes the handoff from a published
candidate to explicitly selected project checks. `test` previews the exact
commit/tree, commands, executable hashes and environment. `--run --accept-plan
SHA256` executes those commands in a private tree snapshot with bounded logs,
not in your dirty source checkout. **This is not a sandbox:** tests run as you
and can access network and user files. No commands or dependencies are discovered
or installed automatically, and no inherited credential environment is copied.
Use only reviewed, trusted tests or your own disposable containment environment.

The [publisher](swarm-fleet-publication.md) connects complete passing test
evidence and an already-promoted local branch to an explicit remote Git branch.
It previews the expected old/new commits and destination, then requires separate
`--push --accept-plan SHA256` approval. It uses an exact expected-old lease only
after proving fast-forward ancestry, and never relies on a moving HEAD or ambient
remote configuration. A push may activate receiver hooks, CI or deployment;
neither test nor local-promotion approval grants that authority. Its read-only
`--check` observes a lost response without repeating a push.

The frontend replaces itself with the selected Python controller in isolated
mode. It verifies the complete cohort before doing so, including siblings that
a different command imports. Missing manifests, changed files, symlinked
controllers or partial releases cannot silently fall back to PATH or a checkout.
This checks local integrity, not provider readiness, remote software, filesystem
sandboxing or resistance to a malicious same-user process replacing the verifier.

## Updates and interrupted installs

Run the same explicit installation flow from a newer trusted checkout. Approval
binds its file hashes, destination directory identities and previous launcher.
A changed source, replaced destination or changed launcher requires a new review.
An unrelated existing `acfs-fleet` file or symlink is never overwritten.

Each distinct cohort gets its own immutable-by-convention release directory.
The active symlink changes only after all files and the final manifest are
written, synced and verified. The update retains every previous release.
Interrupted writes retain their partial evidence and leave the old launcher
usable. An incomplete release is refused, not overwritten or deleted on retry.
There is no garbage collection, forced repair or destructive rollback command.
Concurrent cooperating installations use an exclusive kernel directory lock.

**Keep the runtime ID with the operation's private records, outside its strict
journal directory.** Fleet preparation approval includes controller-derived
policy bytes; recovering an old operation with different code may be refused.
The install result includes `pinned_launcher`, an absolute entrypoint for that
exact retained cohort. Invoke it directly to use the original code after an
update. Do not edit or rehash an old journal to bypass a changed-policy refusal.

### Select the original runtime without changing the active version

```bash
acfs-fleet runtimes
acfs-fleet --runtime ORIGINAL_RUNTIME_ID version
acfs-fleet --runtime ORIGINAL_RUNTIME_ID prepare --help
```

`runtimes` is a read-only integrity inventory of this installation. Exit 0 means
all listed releases verified; exit 1 means at least one retained release is
unavailable. Partial or modified versions are not advertised as usable. The
`current` field names the runtime executing the inventory, which may itself be
a directly invoked pinned entrypoint rather than the PATH launcher.

Put `--runtime ID` **before** `launch`, `prepare`, `dispatch`, `status`, `collect`, `test`, or `publish`, then supply the
original controller arguments, journal paths and approvals. The selector verifies
that exact retained cohort and executes its original frontend as well as its
controllers. It does not rewrite the active launcher or operation journals,
install a version, choose a substitute, or grant permission to retry work. An
unknown, incomplete or damaged runtime fails before controller execution.

Selection requires an installed runtime; it does not search arbitrary checkouts
or download historical code. The runtime ID is not an operation approval digest.
ACFS does not infer which version authored an old journal: preserve the original
runtime ID or pinned entrypoint with your external operation records.

### Upgrade from a retained runtime

Publication-enabled releases use manifest schema `acfs.fleet-runtime.v5`: the frontend
plus all seven fixed controller roles are required. The installer, inventory and
selector also verify retained `acfs.fleet-runtime.v1` releases (frontend plus
launch/prepare/dispatch), `acfs.fleet-runtime.v2` releases (those files plus
status), `acfs.fleet-runtime.v3` releases (v2 plus collect), and
`acfs.fleet-runtime.v4` releases (v3 plus test). It never adds a
command to an old release, changes its runtime ID, or rewrites its manifest.
Unknown layouts, missing roles, extra paths and malformed metadata are refused.

Upgrade using the explicit preview/apply flow above. The new `version` and
`runtimes` reports include a `commands` list for each verified runtime. Legacy
v1 releases do not advertise `status`; neither v1 nor v2 advertises `collect`;
none of v1/v2/v3 advertises `test`; none of v1/v2/v3/v4 advertises `publish`.
Selecting an unsupported command on a retained release returns
`runtime_command_unavailable` before executing that frontend. There is no fallback
to the current controller. Unavailable releases advertise no commands. Use the new
frontend to inventory all five generations; an old frontend cannot verify the new
layout, but its pinned original operations remain unchanged.

Selecting a legacy runtime still executes that release's original frontend and
controllers. Observation of old compatible journals using a newer observer does
not migrate them or establish that newer execution code may resume their work.
Collection approval also binds the fixed remote collector policy. Keep the
collector runtime ID with the artifact directory so local verification remains
available if that policy changes in a later release.

## Validation

```bash
python3 -B tests/unit/test_fleet_runtime.py -v
python3 -B tests/unit/test_fleet_runtime_status.py -v
python3 -B tests/unit/test_swarm_fleet_collect.py -v
python3 -B tests/unit/test_swarm_fleet_test.py -v
python3 -B tests/unit/test_swarm_fleet_publish.py -v
```

These tests run the actual frontend and installer with real private files and
unprivileged child processes. Controller peers record arguments and perform no
SSH, provider request, agent launch, or work dispatch. Tests cover installation
without the checkout, upgrades, retained releases, literal arguments, stdin,
exit/signals, explicit old-runtime selection, directory locking, damaged/partial
releases and refusal boundaries. An actual SIGKILL during release publication
checks that the old active command remains usable and the partial new release is
retained rather than activated or silently repaired. They do not replace
full acceptance against installed ACFS hosts and authenticated providers.

The observer integration suite also exercises legacy-to-current upgrades,
capability-aware selection, and the actual installed status controller with its
production launch/dispatch imports after the source checkout becomes unavailable.
Its journal contains no attempted launch, so that integration test opens no SSH
connections, starts no agents, and sends no work.
Collection integration covers exact retained layouts, unavailable-command
refusal and the actual installed collector verifying real Git bundle artifacts
without its checkout. Other controller roles are inert peers in that case.
Test integration executes the actual installed runner and production Git helpers
against a real commit after its source checkout becomes unavailable. It verifies
explicit and pinned-runtime execution, original source preservation, old-runtime
refusal and whole-cohort integrity after adding the test role.
Publication integration executes the installed publisher and all its real Git/test
helpers after its checkout becomes unavailable, publishing a tested two-parent
candidate to a local bare receiver and checking it without replay. That is real
Git send/receive-pack coverage, not hosted SSH/provider acceptance. Legacy v4
test/recovery arguments and its retained files remain unchanged.
