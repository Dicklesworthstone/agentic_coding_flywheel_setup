# Multi-Host Swarm Capacity Inventory Design

This note records the `bd-cpgj0` design for a local-first inventory of hosts
that can run or support ACFS agent swarms. It is a design contract for later
implementation Beads; it does not describe current installer behavior.

## Purpose

ACFS can already size the local host with `acfs capacity`, inspect local swarm
pressure with `acfs swarm status`, and route CPU-heavy Rust work through RCH.
Large operators may also have several 256 GiB+ VPS hosts, dedicated RCH worker
machines, or staging boxes that should not all receive the same swarm size.

The capacity inventory answers:

> Which known hosts are available for a swarm, what role should each host play,
> and what agent count is safe to try next?

The inventory must remain advisory. It must never SSH to unknown machines,
launch agents, mutate Beads, send Agent Mail, update RU state, or change RCH
worker configuration by itself.

## Non-Goals

- It is not an RCH scheduler. RCH remains responsible for remote build/test
  offload and worker queue management.
- It is not an RU inventory. RU remains responsible for repository sync and
  sweep orchestration.
- It is not an NTM launcher. NTM remains responsible for creating tmux sessions
  and panes.
- It is not a secrets store. SSH keys, tokens, provider credentials, and private
  hostnames must not be stored in the inventory.
- It does not replace `acfs capacity`; local capacity output remains the source
  for per-host recommended counts.

## Storage Model

Use one manually editable JSON file as the canonical v1 shape:

```text
~/.acfs/swarm/hosts.inventory.json
```

The command may later support YAML import/export for operators who prefer YAML,
but the on-disk file should be JSON first because ACFS already depends on `jq`
for diagnostics and tests.

The file is local to the current operator account and is safe to edit by hand.
Unknown fields are preserved on import and ignored by reports unless they match
a known sensitive field name.

## JSON Contract

```json
{
  "schema_version": 1,
  "updated_at": "2026-05-08T00:00:00Z",
  "defaults": {
    "workload": "standard",
    "stale_after_hours": 24,
    "support_bundle_detail": "redacted"
  },
  "hosts": [
    {
      "id": "local",
      "display_name": "Local ACFS host",
      "role": "swarm-controller",
      "status": "active",
      "manual_tags": ["primary", "ntm"],
      "last_probe_at": "2026-05-08T00:00:00Z",
      "probe_source": "manual",
      "resources": {
        "cpu_count": 64,
        "mem_total_mib": 262144,
        "disk_available_mib": 524288
      },
      "capacity": {
        "workload": "standard",
        "recommended_agents": 44,
        "safe_agents": 64,
        "source": "acfs capacity --json --recommend-ntm"
      },
      "rch": {
        "worker": false,
        "controller": true,
        "workers_total": 8,
        "workers_healthy": 8
      },
      "ntm": {
        "can_launch": true,
        "preferred_labels": ["swarm-25", "review"]
      },
      "ru": {
        "can_sync_repos": true
      },
      "notes": "Operator-managed display note. Do not put secrets here."
    },
    {
      "id": "rch-worker-a",
      "display_name": "RCH worker A",
      "role": "rch-worker",
      "status": "active",
      "manual_tags": ["builds"],
      "last_probe_at": "2026-05-07T23:30:00Z",
      "probe_source": "rch status --json",
      "resources": {
        "cpu_count": 32,
        "mem_total_mib": 131072,
        "disk_available_mib": 262144
      },
      "capacity": {
        "workload": "heavy",
        "recommended_agents": 0,
        "safe_agents": 0,
        "source": "reserved for RCH"
      },
      "rch": {
        "worker": true,
        "controller": false,
        "slots_total": 12,
        "slots_available": 10
      },
      "ntm": {
        "can_launch": false,
        "preferred_labels": []
      },
      "ru": {
        "can_sync_repos": false
      }
    }
  ]
}
```

## Field Rules

Required top-level fields:

| Field | Type | Notes |
| --- | --- | --- |
| `schema_version` | number | Start at `1`; reject unsupported future major versions. |
| `updated_at` | string | ISO-8601 timestamp set by import/export/report commands. |
| `defaults` | object | Report defaults; missing values use safe built-ins. |
| `hosts` | array | Host entries; empty arrays are valid. |

Required host fields:

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | Stable local identifier, not a hostname. Match `^[a-z0-9][a-z0-9._-]{0,62}$`. |
| `role` | string | `swarm-controller`, `swarm-worker`, `rch-worker`, `support`, or `disabled`. |
| `status` | string | `active`, `stale`, `disabled`, or `unknown`. |
| `last_probe_at` | string or null | ISO-8601 timestamp. Null means manually entered and never probed. |
| `resources` | object | CPU, memory, and disk summary. |
| `capacity` | object | Recommended and safe agent counts for this host role. |
| `rch` | object | RCH relationship summary. |
| `ntm` | object | Whether NTM launches are appropriate on this host. |
| `ru` | object | Whether RU repo sync is appropriate on this host. |

Sensitive fields are forbidden at any depth:

- `hostname`
- `ip`
- `address`
- `ssh_key`
- `private_key`
- `token`
- `password`
- `credential`
- `provider_api_key`
- `provider_id`
- `provider_account_id`
- `account_id`
- `project_path`
- `home`
- `username`
- `ssh_username`

The implementation should reject these fields on import unless the operator
passes an explicit future `--allow-sensitive-local-only` flag. Even then,
support bundles must redact them.

## Relationship To Existing Tools

### RCH

RCH remains the build/test offload layer. Inventory reports may summarize RCH
worker counts, slots, and stale telemetry from `rch status --json`, but they
must not rewrite RCH config or choose remote workers for a build. Rust commands
inside agent panes still use:

```bash
rch exec -- cargo test
rch exec -- cargo clippy
```

### RU

RU remains the multi-repo sync tool. Inventory can mark whether a host is
appropriate for `ru sync` or `ru agent-sweep`, but it must not run RU commands
or infer repo paths from RU state.

### NTM

NTM remains the launcher. Inventory can suggest labels and per-host agent counts
that feed an operator command such as:

```bash
ntm spawn acfs-main --label swarm-25 --cc=10 --cod=10 --agy=5 --assign --stagger-mode=smart
```

The inventory command must not launch NTM sessions.

### Agent Mail And Beads

Inventory output can include advisory thread IDs or Beads references when the
operator supplies them, but it must not create issues, claim Beads, reserve
files, send Agent Mail, or force-release reservations.

## Proposed Commands

All commands are advisory and bounded. They must exit nonzero on malformed
inventory, but they should still write a structured failure artifact when an
output directory is supplied.

```bash
acfs swarm inventory report
acfs swarm inventory report --json
acfs swarm inventory report --inventory ~/.acfs/swarm/hosts.inventory.json
acfs swarm inventory export --format json --output inventory.redacted.json
acfs swarm inventory import --input inventory.redacted.json
acfs swarm inventory validate --json
```

Optional future probe command:

```bash
acfs swarm inventory probe-local --output ~/.acfs/swarm/hosts.inventory.json
```

`probe-local` may read only the local host via existing ACFS collectors. It must
not SSH to other hosts.

## Report Output

Human output should fit in a terminal:

```text
ACFS Swarm Host Inventory
Status: warn
Hosts: 2 active, 1 stale, 1 disabled

Recommended Launch Targets
  local: 25 agents now, safe max 44, role swarm-controller
  rch-worker-a: no agents, reserved for RCH offload

Warnings
  - host edge-1 has stale probe data older than 24h
```

JSON output:

```json
{
  "schema_version": 1,
  "generated_at": "2026-05-08T00:00:00Z",
  "status": "warn",
  "inventory_file": "~/.acfs/swarm/hosts.inventory.json",
  "summary": {
    "hosts_total": 2,
    "active": 2,
    "stale": 0,
    "disabled": 0,
    "recommended_agents_total": 44,
    "safe_agents_total": 64,
    "rch_workers": 1
  },
  "hosts": [],
  "warnings": [],
  "next_commands": [
    "acfs capacity --json --recommend-ntm",
    "rch status --json",
    "acfs swarm plan --agents 25"
  ]
}
```

## Support Bundle Expectations

Support bundles should include a redacted inventory summary only when the file
exists:

```text
resource_profile.json
swarm_inventory.json
manifest.json
```

`swarm_inventory.json` must include:

- schema version
- host count by role and status
- recommended/safe agent totals
- stale probe counts
- unknown-field counts
- redaction flags

It must not include:

- raw hostnames
- IP addresses
- SSH usernames
- SSH key paths
- provider IDs
- repo paths
- home directories
- private notes that look like tokens or credentials

Manifest diagnostics should include:

```json
{
  "diagnostics": {
    "swarm_inventory": {
      "included": true,
      "status": "warn",
      "paths_redacted": true,
      "raw_hosts_collected": false
    }
  }
}
```

## Failure Artifacts

Implementation tests should assert exact names so failures are reproducible
without live multi-host access.

| Operation | Failure Artifact | Log Artifact | Notes |
| --- | --- | --- | --- |
| `report` | `swarm_inventory.report.error.json` | `swarm_inventory.report.log` | Invalid schema, stale probes, unreadable file. |
| `import` | `swarm_inventory.import.error.json` | `swarm_inventory.import.log` | Unknown schema, forbidden sensitive fields, malformed JSON/YAML. |
| `export` | `swarm_inventory.export.error.json` | `swarm_inventory.export.log` | Output path unwritable, redaction failure, unsupported format. |
| `validate` | `swarm_inventory.validate.error.json` | `swarm_inventory.validate.log` | Invalid fields, duplicate IDs, unsupported role/status. |
| `probe-local` | `swarm_inventory.probe-local.error.json` | `swarm_inventory.probe-local.log` | Local collector timeout or malformed capacity JSON. |

Error JSON shape:

```json
{
  "schema_version": 1,
  "operation": "import",
  "status": "fail",
  "error_code": "forbidden_sensitive_field",
  "message": "Inventory contains forbidden sensitive fields",
  "redacted_field_paths": ["hosts[0].hostname"],
  "next_commands": ["acfs swarm inventory validate --json"]
}
```

## Validation Test Plan

Minimum fixture tests:

1. Empty inventory:
   - `hosts: []` is valid.
   - report returns `status: warn`, totals of zero, and a next command to add or
     import hosts.
2. Stale probes:
   - host with `last_probe_at` older than `defaults.stale_after_hours` returns
     `status: warn`.
   - stale host is not counted toward launch recommendations unless explicitly
     requested.
3. Unknown fields:
   - benign unknown fields are preserved by import/export and counted.
   - forbidden sensitive field names fail import and validate.
4. Redacted support-bundle output:
   - fixture containing token-like notes, home paths, IP-looking strings, and
     hostnames produces `swarm_inventory.json` without raw sensitive values.
5. Duplicate IDs:
   - duplicate host IDs fail validation with deterministic `duplicate_host_id`.
6. Role boundaries:
   - `rch-worker` hosts contribute RCH capacity summary but zero default agent
     launches.
   - `disabled` hosts are listed but excluded from recommendations.
7. Malformed optional files:
   - missing inventory returns structured `skipped` support-bundle diagnostics.
   - malformed JSON writes `swarm_inventory.report.error.json`.

## Suggested Follow-Up Beads

Create implementation work in separate slices:

1. `Implement swarm inventory report/import/export command`
   - Add `scripts/lib/swarm_inventory.sh`.
   - Wire `acfs swarm inventory ...` through `scripts/lib/doctor.sh`.
   - Add read-only JSON and human report output.
2. `Add swarm inventory support-bundle redaction`
   - Capture sanitized `swarm_inventory.json`.
   - Extend manifest diagnostics with redaction flags.
3. `Add swarm inventory fixture tests`
   - Cover empty inventory, stale probes, unknown fields, forbidden sensitive
     fields, duplicate IDs, role boundaries, and failure artifact names.

## Final Recommendation

Implement the inventory as an advisory local JSON contract first. The first
code slice should validate and report; import/export and support-bundle capture
can follow once the schema is pinned. ACFS should keep RCH, RU, NTM, Beads, and
Agent Mail as separate tools and use the inventory only to help an operator make
better launch decisions.
