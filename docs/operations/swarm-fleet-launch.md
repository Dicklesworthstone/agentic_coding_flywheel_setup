# Execute a reviewed multi-host agent launch

The fleet inventory planner is advisory and describes **target totals**, not
additional processes to start. This controller supplies the missing execution
step for an explicit roster of **new, dedicated native-agent sessions**. It
never converts inventory allocations into launch authority or adds agents to an
existing session. Every host runs its own installed ACFS and NTM admission checks.

Run `python3 -I scripts/swarm-fleet-launch.py --help` from a trusted complete
checkout on a Linux controller. This is a checkout command, not a newly installed
`acfs` subcommand. Remotes need the existing native launcher at
`$HOME/.acfs/scripts/lib/swarm_launch.sh`, NTM, tmux and the selected providers.
The project and private receipt parent must already exist on each remote host.
This command does not provision machines, install tools, copy repositories,
authenticate providers, or supply remote credentials.

## Choose exactly what may start

Keep a mode-0600 spec outside version control and support bundles. Each host is
an explicitly authorized direct SSH endpoint. The `request` is the ordinary
single-host launch request; all its fields are mandatory:

```json
{
  "schema": "acfs.swarm-fleet-launch-spec.v1",
  "hosts": [
    {
      "id": "worker-a",
      "host": "worker-a.example.com",
      "user": "ubuntu",
      "port": 22,
      "request": {
        "repo": "/data/projects/myapp",
        "session": "implementation-wave-1",
        "receipt": "/home/ubuntu/receipts/implementation-wave-1.json",
        "profile": "balanced",
        "workload": "standard",
        "accept_warnings": false,
        "agents": [
          {"agent_name": "RedFox", "agent_type": "claude"},
          {"agent_name": "BlueLake", "agent_type": "codex"}
        ]
      }
    },
    {
      "id": "worker-b",
      "host": "worker-b.example.com",
      "user": "ubuntu",
      "port": 22,
      "request": {
        "repo": "/data/projects/myapp",
        "session": "review-wave-1",
        "receipt": "/home/ubuntu/receipts/review-wave-1.json",
        "profile": "review-heavy",
        "workload": "standard",
        "accept_warnings": false,
        "agents": [{"agent_name": "GreenHill", "agent_type": "claude"}]
      }
    }
  ]
}
```

Select 1–16 hosts, 1–32 agents per host, and at most 256 agents in total. Host IDs,
endpoints, and case-insensitive agent names must be distinct. Reusing the same
host with another port/user does not create extra capacity. IPv4-mapped IPv6
aliases are also deduplicated; different DNS aliases can still resolve to the
same machine, which operators must exclude themselves. Root remote accounts,
unknown providers, malformed paths, implicit selections and extra executable
fields are refused. Native support currently covers Claude and Codex.

The workload and profile choose admission policy, **not a provider model or CAAM
account**. The remote NTM configuration still chooses its normal commands,
models, permissions and credentials. Use the profile rehearsal separately to
check authentication/model access; this controller does not wire a CAAM profile
into an NTM session or treat a previous rehearsal as authorization.

## Preview and launch

Choose an existing user-owned, non-group/world-writable parent for local state.
The state directory itself must not yet exist. With the spec saved as
`fleet-launch.json`, preview live admission on all selected hosts:

```bash
python3 -I scripts/swarm-fleet-launch.py \
  --spec fleet-launch.json \
  --known-hosts "$HOME/.ssh/known_hosts" \
  --identity-file "$HOME/.ssh/id_ed25519" \
  --state-dir "$HOME/fleet-wave-1"
```

The default operation **does open SSH connections**, but only invokes each
native launcher's preview. It creates no controller state and starts no agents;
upstream tools may write their ordinary telemetry. Read the private spec and
per-host admission results, then repeat the same command with:

```bash
  --launch --accept-plan THE_RETURNED_PLAN_SHA256
```

The approval binds the entire roster, remote paths/options, host-key bytes,
explicit SSH identity bytes, local state-directory path, transport policy and
timeout. Changing one requires a new preview. Input filenames may change when
their contents remain the same. The digest is an integrity check for an operator
review, not a signature or remote software attestation.

Launch rechecks **all** hosts before any spawn. A refused/unknown admission or
an already-used remote receipt blocks the whole new operation without creating
local state. After that barrier, hosts launch sequentially in spec order. Each
native launcher performs its own fresh admission immediately before its spawn;
`accept_warnings` cannot override `wait`, `scale_down`, hard failures, or unsafe
agent counts. Admission and spawning are not a fleet-wide atomic reservation.

The controller fsyncs its private fleet intent, then an immutable per-host attempt
record **before** invoking remote launch. The remote native launcher separately
persists its own intent before NTM. Only a matching ready response with distinct,
ordered native pane/process/session identities creates a local result record.
The controller never executes the command strings returned by remote previews.

## Partial launches are not rolled back or blindly retried

A timeout, lost SSH response, native failure, malformed result or interruption
can leave remote agents running. At the first unconfirmed host, later hosts are
left `not_attempted`. Earlier confirmed sessions and every receipt are retained.
There is no automatic session kill, rollback, replacement, account switch, or
restart. A repeated new launch against an existing controller state directory
is refused before any SSH connection; preserve the state for inspection/recovery.

State is local/private and includes endpoint mappings and repository/receipt
paths. Files are mode 0600 under a mode-0700 directory:

```text
fleet-wave-1/
  intent.json
  worker-a.attempt.json
  worker-a.result.json
  worker-b.attempt.json
  ...
```

A crash while writing can leave incomplete evidence. Malformed state must not be
edited, deleted, or rehashed to retry: inspect it and the remote sessions first.
Do not change remote receipt paths to retry uncertain work. Native receipt-only
inspection remains available on the original host:

```bash
acfs swarm launch --reconcile --receipt /home/ubuntu/receipts/implementation-wave-1.json
```

A ready fleet means native processes were verified at each host's check time,
not that they are authenticated, registered with Agent Mail, executing work, or
still alive when the last host finishes. Use the ordinary launch-aware scoped
packet preparation and reviewed dispatch on each remote; this controller sends
no work prompts, claims no Beads, and acquires no file reservations.

## SSH, reporting and verification boundary

Host keys must already be independently verified. Unknown/changed keys fail;
there is no trust-on-first-use prompt or key update. The explicitly selected
identity must be private, owned and single-link. An existing local SSH agent can
unlock its matching key; unrelated identities are excluded and the agent is not
forwarded. SSH configs, proxy/jump/local commands, multiplexing, forwarding, TTYs,
and environment transmission are disabled. Bastions and SSH-config aliases are
not supported. Only directly reachable authorized endpoints are accepted.

Reviewed key/known-host bytes are held in private anonymous snapshots while SSH
runs, not reopened from caller-controlled paths. Children do not inherit shell
or loader hooks or provider credentials. The installed remote account, launcher,
NTM and provider configuration remain trusted: neither SSH authentication nor
JSON validation attests the remote executable bytes or truth of its claims.
The controller is not an operating-system sandbox.

JSON reports contain logical host IDs, fixed error codes, admission numbers and
validated targets, not raw hostnames, usernames, local/remote paths, key material
or remote diagnostics. Keep the original spec and state private; agent names and
logical IDs in reports should not themselves contain private information.

`--timeout` bounds each SSH operation (default 360 seconds, range 1–600), including
remote admission and launch. stdout/stderr share a 1 MiB in-memory bound. Signals
and deadlines terminate the local SSH process group, not arbitrary remote agents.
A network disconnect cannot prove that remote execution stopped. Starting agents
may consume provider resources; no live launch was used to validate this feature.

Exit 0 means a fully admitted preview or all requested native sessions ready;
1 means blocked admission or unconfirmed/partial launch; 2 means input, approval,
state or local execution error. Signals return 128 plus the signal number.

```bash
python3 -B -m unittest discover -s tests/unit -p test_swarm_fleet_launch.py -v
```

Tests exercise orchestration against the existing native JSON contract, real
private-file publication, no-clobber races, SSH argument/snapshot construction,
and actual bounded child processes. They do not replace live OpenSSH/VPS/NTM or
authenticated-provider acceptance. The controller never downloads a replacement
launcher or relaxes its policies when a remote installation is missing/stale.
