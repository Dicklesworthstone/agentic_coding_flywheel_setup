# Publish the exact tested candidate to an explicit Git destination

`scripts/swarm-fleet-publish.py` connects verified candidate-test evidence and an
already-promoted local branch to one explicitly selected destination branch.
It sends the tested commit ID, never a moving HEAD, inferred upstream, matching
branch set or repository mirror. A publication preview does not upload objects
or update refs. Publication has its own approval, separate from test, integration
and local-promotion approvals.

**A push may start the receiver's hooks, CI, deployments or other automation.**
Review that destination and its policies before applying. Committed history is
not redacted: secrets deleted by later commits can still be sent. Test logs and
uncommitted files are not uploaded. No provider/model calls or dependency installs
are performed by this controller; remote automation is outside its control.

## Preview and publish

After an explicit [fleet runtime installation or upgrade](fleet-runtime.md),
run on Linux as the repository owner:

```bash
acfs-fleet publish \
  --test-run "$HOME/fleet-tests-wave1" \
  --repository /path/to/project \
  --expect-test-plan ORIGINAL_TEST_PLAN_DIGEST \
  --branch release --remote-branch main \
  --expect-old FULL_CURRENT_REMOTE_COMMIT \
  --remote-url ssh://git@github.com/OWNER/REPOSITORY.git \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --state-dir "$HOME/fleet-publication-wave1"
```

From a complete trusted checkout, `python3 -I scripts/swarm-fleet-publish.py`
accepts the same arguments. Installed publication requires a v5 runtime. Older
v1/v2/v3/v4 versions retain their original capabilities and cannot fall back to
the new publisher. Keep the original runtime ID with publication records;
`acfs-fleet --runtime ORIGINAL_RUNTIME_ID publish ...` selects that complete
retained implementation without changing the active launcher.

Replace the placeholders and select the actual branch, destination and identity.
The local `release` branch must already point directly to the exact tested commit;
use the [local promotion workflow](swarm-fleet-promotion.md) separately. A
checked-out local branch is allowed here because publication does not modify it.

The destination branch must already exist at the explicit full `--expect-old`
commit, which must be present locally and an ancestor of the tested candidate.
New branches, abbreviated hashes, non-fast-forwards, untested local changes and
mismatched test evidence are refused. The verifier checks the original complete
test records, log fingerprints and retained tracked workspace without rerunning
any test. Same-user evidence is not signed execution attestation.

Preview authenticates to the selected Git server to read the branch. It creates
no journal or staging repository. Review the resulting JSON plan, then append:

```text
--push --accept-plan THE_PUBLICATION_PLAN_DIGEST
```

The publication digest binds the evidence bytes, tested commit/tree, source
repository identity, local and remote branch names, full old/new commits, endpoint,
SSH trust fingerprints, Git version, controller code and journal destination.
Changed inputs require another preview. Neither an earlier test approval nor a
saved passing summary supplies push permission.

Apply rechecks evidence and the source branch, then writes a private intent and
uses a fresh bare transport repository with no source-repository configuration.
It borrows source objects; no source refs, objects, index, working files,
FETCH_HEAD or remote-tracking refs are changed. URL rewrites, push defaults,
extra refspecs, client hooks, automatic tags, submodule pushes and inherited Git
configuration cannot redirect or broaden the operation.

The push uses Git's explicit `--force-with-lease=REF:EXPECTED_OLD` form solely as
a compare-and-swap guard **after requiring the old commit to be an ancestor of
the candidate**. There is no unrestricted force option or history-discarding
path. Even a racing intermediate commit already included in the candidate
invalidates the reviewed old value. A normal fast-forward receipt and a subsequent
remote ref query are required before reporting `published`. Server policy and
receive hooks remain in force.

If old and candidate are identical and the remote still matches, apply returns
`noop` without creating state or starting a push.

## Explicit transports and trust

Network publication supports only canonical `ssh://USER@HOST[:PORT]/REPOSITORY`
URLs. There is no `origin` inference, scp shorthand, HTTP credential handling,
arbitrary helper protocol, jump host or fallback transport. Default port is 22.
URL paths have a restricted ASCII component grammar; credential URLs, queries,
fragments and percent escapes are refused. Select independently verified host
keys and an explicit private identity. The existing local SSH agent may unlock
that identity; it is never forwarded.

The transport reuses the fleet's strict SSH policy: batch mode, pinned known
hosts, no host-key updates, no ambient SSH config, no proxy/jump/local commands,
no forwarding and no multiplexed existing connection. Git's protocol needs
stdin, so the command-only fleet transport's `-n` option is intentionally omitted.
The controller requires system Git and OpenSSH; it does not install them.

For offline operation against an explicitly trusted **local bare** repository,
replace all three SSH arguments with:

```text
--local-remote /path/to/receiver.git
```

Its path, owner, directory identity and object format are checked. Source,
receiver, test directory and journal must not overlap. Receiver-owned hooks and
receive policies still run on a push. This is the same Git send/receive-pack
workflow, not a copy of object files or a test-only fake publication mode.

**The selected Git service and its branch policy are trusted.** Git's usual ref
advertisement does not expose the type of every non-HEAD symbolic ref. Locally
visible symbolic destination branches are refused, but neither transport can
certify branch type atomically against a receiver owner changing it. Accordingly
`remote_reference_kind_verified` is false. A server may also run hooks or mutate
other refs; the client does not claim to constrain those server-owned actions.
Use ordinary direct destination branches and do not concurrently replace them
with symbolic aliases. See the official [ls-remote](https://git-scm.com/docs/git-ls-remote)
and [push](https://git-scm.com/docs/git-push) contracts.

## Lost responses and interruptions

Before invoking the push, apply durably writes `attempt.json`. It writes
`result.json` only after validating Git's receipt and the remote commit. A
nonzero exit, timeout or lost response can occur after the server accepted the
push or ran automation. `push_started` means transmission may have begun, not
that it completed. Never automatically retry.

Inspect using the exact original arguments, journal and publication digest:

```text
--check --accept-plan ORIGINAL_PUBLICATION_PLAN_DIGEST
```

Use these options **instead of** `--push`. Check rereads the intact test evidence
and intent, queries the remote twice, and reports `matched`, `not_published`,
`missing`, `different` or `unconfirmed`. It never pushes, restores a result file,
runs local tests or changes the journal. The old local branch need not still
point to the candidate for historical checking. Remote-query errors are errors,
not fabricated `missing` results.

A matching remote ref proves only the observed value, not which process wrote
it or whether a deployment succeeded. `publication_provenance_verified`,
`test_provenance_verified` and `task_completion_verified` are false. A recorded
successful result is not a substitute for querying the destination.

Existing journals are never replayed or overwritten. Retain partial directories
and inspect the destination before choosing another separately reviewed operation.
The private `transport.git` uses source object alternates and is not a backup;
it contains no credentials. It and all intent/result records are retained.
Cooperating controllers use kernel directory locks, but observations are not a
globally atomic snapshot against unrelated Git writers.

Exit 0 means preview, publication, no-op or a matched check succeeded. Exit 1 is a
completed check requiring attention. Exit 2 is refused input, evidence, approval,
remote operation or local execution. Handled signals return 128 plus the signal
number. `--timeout` (default 90, 1..600 seconds) bounds local Git inspection and,
separately, the combined remote subprocess phase. Local hashing, journal writes
and bounded child cleanup are not strict wall-clock bounds. Upload size is not
capped independently; the existing test snapshot bounds do not cap full history.

## Validation

```bash
python3 -B tests/unit/test_swarm_fleet_publish.py -v
```

Tests use the production integration, test-evidence and promotion implementations,
real Git objects, local bare receivers, actual receive hooks and unprivileged
processes. They exercise stale leases, dirty source preservation, SHA-256,
tampered evidence, exact refspecs, explicit SSH argument/environment construction
and SIGKILL before/after a real push. The SSH policy construction test is not a
live OpenSSH/GitHub acceptance test. No paid provider call or production remote
update is performed by these tests.
