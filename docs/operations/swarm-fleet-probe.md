# Refresh an explicit fleet before placement

Fleet placement needs fresh capacity observations, not yesterday's positive
counts. The fleet collector refreshes an operator-selected set of existing
inventory IDs over strictly host-key-verified SSH. It produces a NEW redacted
inventory snapshot for `acfs swarm inventory report` and `plan`. It does not
start agents, change remote configuration, install tools, mutate Beads, send
Agent Mail, run RU, or modify RCH configuration.

## Keep connection information separate

Create a private JSON file outside the inventory and support bundles:

```json
{
  "schema": "acfs.swarm-probe-targets.v1",
  "targets": [
    {"id": "controller-a", "host": "controller-a.example.com", "user": "ubuntu", "port": 22},
    {"id": "worker-b", "host": "worker-b.example.com", "user": "ubuntu", "port": 22}
  ]
}
```

`chmod 600 targets.json`. Each ID must already exist in the selected inventory.
The file contains endpoint mappings, never passwords or private-key material.
Hostnames must be lowercase DNS names or canonical IP addresses. Duplicate IDs
and identical endpoints are rejected, including the same host on different
ports/users. Different DNS aliases may still identify one machine: operators
must not enter aliases as additional capacity. There is no network discovery.

Each remote account needs an installed ACFS with `probe-local` available at
`$HOME/.acfs/scripts/lib/swarm_inventory.sh`. The collector runs precisely that
read-only measurement with the selected ID and its inventory workload. It does
not upload scripts, bootstrap a machine, change remote inventory, or pass
`--allow-launch`. Measurements occur in the remote SSH process's resource
context; separately configured agent services may have different resource limits.

## Preview, review, collect

On a fresh or updated installation:

```bash
acfs swarm inventory probe-fleet \
  --inventory hosts.inventory.json \
  --targets targets.json \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --parallel 4 --timeout 45 --json
```

The checkout entrypoint `bash scripts/lib/swarm_fleet_probe.sh` accepts the same
arguments. Fresh installs and runtime updates distribute the collector alongside
the inventory command under the canonical internal-checksum contract. An older
partial installation without that sibling fails closed; it never searches PATH
for a replacement collector. Local `report`, `plan`, `probe-local`, `import`,
`export` and `validate` commands never turn into remote probes.

The optional identity must be an existing private, single-link, user-owned file.
Without it, normal default SSH identities or an existing local authentication
agent may be used. Authentication remains noninteractive; encrypted identities
must already be usable without prompting. Agent forwarding is always disabled.
The known-hosts file must already contain independently verified host keys.
Unknown or changed host keys are refused; this command never learns new keys.

Preview validates local inputs and prints a `plan_sha256`, but opens no SSH
connection and creates no output. Read the inventory and private target file,
then repeat the same arguments with:

```bash
  --probe --accept-plan THE_PREVIEW_DIGEST --output ./snapshots/fresh-inventory.json
```

The output parent must already exist, be owned by the caller and not be writable
by others. The destination must not exist. Input inventory, mapping, host-key
bytes, explicit identity bytes, workloads, limits and local runtime policy are
bound into approval. Changing those inputs requires another preview. File paths
may change without changing approval when all bound bytes/semantics are unchanged.
The identity is not persisted in the plan; only its digest is included.

OpenSSH receives fixed arguments with user/system SSH configuration disabled,
strict host keys, no proxy command/jump, local command, multiplexing, TTY,
forwarding, or environment transmission. Existing SSH config aliases and bastion
setups are therefore not supported. Use directly reachable authorized endpoints.
Connection data and remote stdout/stderr are not included in the published
inventory or result report. Reviewed trust and explicit identity bytes are held
in private anonymous files during SSH execution rather than reopened by pathname.

## Use the result conservatively

Successful measurements update only capacity/resource fields and observation
metadata. Existing roles, disabled states, launch vetoes, notes and unrelated
hosts are preserved. A measurement may withdraw `ntm.can_launch`, never grant it
against local policy. Restoring a withdrawn permission is a separate operator
review, not an automatic response to the next probe.

A failed selected host gets zero recommended/safe counts and a null probe time.
It cannot retain a stale positive recommendation. Successful peers still appear
in a partial snapshot, which can be reviewed and planned immediately:

```bash
acfs swarm inventory report --inventory ./snapshots/fresh-inventory.json --json
acfs swarm inventory plan --inventory ./snapshots/fresh-inventory.json --agents 12 --json
```

Collection is advisory, not a resource reservation or launch admission. Run fresh
local swarm admission on each host immediately before launching work. The fixed
remote command trusts the installed collector and remote account; SSH authenticates
the endpoint, not the truth of its capacity claims. Timestamp checks reject stale
observations and remote clocks more than 60 seconds behind the request, or ahead
of completion. They do not cryptographically attest measurements or eliminate
same-window replay from a compromised remote host.

Exit 0 means every selected host returned valid measurement evidence (including
valid zero-capacity measurements). Exit 1 means partial/all probe failure; a
conservative snapshot is still created and `snapshot_created` is true. Exit 2
means invalid inputs, stale approval or publication failure. Signals return 130
or 143 and cannot report successful collection. A publication interrupted by
I/O failure may leave a partial output file as evidence; inspect it and choose a
new output name. No output is silently replaced or deleted on retry.

Limits: 32 targets, 1–8 concurrent connections, 1–120 seconds per target,
1 MiB per input/response, bounded JSON nesting and nodes. Deadlines and
cancellation terminate the local SSH process group. They cannot guarantee that
a remote process immediately exits after network loss; the installed local
probe has its own bounded measurement and performs no installation or launch.

## Verification

```bash
python3 -B tests/unit/test_swarm_fleet_probe.py
python3 -B tests/unit/test_swarm_fleet_probe.py --live-ssh
```

The second command is for a disposable Linux test runner with OpenSSH client,
server, key generator and passwordless sudo. It uses synthetic throwaway keys,
a loopback-only server and a forced-command capacity fixture. It exercises real
SSH authentication and host-key verification, not real VPS capacity or provider
credentials. Normal unit tests use real bounded subprocesses and the canonical
inventory validator without SSH/network access.
