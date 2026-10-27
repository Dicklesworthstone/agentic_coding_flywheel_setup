# Swarm Resource Isolation

ACFS provides optional `systemd-run --user --scope` wrappers for commands and
their child processes. The default resource profile applies scheduling weights
and accounting. An explicit memory limit adds containment for runaway agent
children, addressing the per-scope protection layer of [issue #467](https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues/467).

The opt-in design established in `bd-8qd3d` and `bd-ylrmm` remains in effect:
ordinary agent commands and the default resource profile receive no new hard
memory limit. Existing `cc`, `cod`, and `gmi` aliases are unchanged.

## Preview a Profile

First inspect the host's capacity and the proposed profile:

```bash
acfs capacity --profile 25-agents --recommend-ntm
acfs capacity --resource-profile
```

To preview an 8 GiB memory ceiling and a separate 2 GiB swap ceiling for each
explicitly wrapped command:

```bash
acfs capacity --resource-profile \
  --memory-max-mib 8192 --memory-swap-max-mib 2048
```

These commands are read-only. The profile report identifies the limits,
resource classes, wrapper paths, systemd availability, and files that applying
the profile would write. Add `--json` for machine-readable output.

The example limits are choices to review against your workload, not an
automatic sizing recommendation. `--memory-max-mib` accepts an integer from
1 to 1048576. `--memory-swap-max-mib` accepts an integer from 0 to 1048576 and
requires `--memory-max-mib`. A swap value of zero prevents that scope from using
swap. Omitting the swap option leaves swap subject to the host's existing
policy; it does not impose a new swap ceiling. Both options require a resource
profile (`--resource-profile` or `--apply-resource-profile`).

## Apply and Use the Wrappers

Repeat the reviewed limits when applying:

```bash
acfs capacity --resource-profile \
  --memory-max-mib 8192 --memory-swap-max-mib 2048 \
  --apply-resource-profile
source ~/.acfs/resource-profile/acfs-resource-profile.sh

ccs       # Claude in a bounded agent scope
cods      # Codex in a bounded agent scope
gmis      # Gemini in a bounded agent scope
```

For another explicit command, choose its resource class:

```bash
acfs-scope background -- python3 analysis.py
acfs-scope support -- your-support-command
```

The generated wrapper retains the selected limits. Changing the limits requires
reviewing and applying another profile; it does not alter already-running
scopes. To generate the original profile with scheduling weights and accounting
only, omit both memory options when applying.

The profile writes these files under `~/.acfs/resource-profile/`:

- `bin/acfs-scope` runs an explicit command in a named resource class.
- `bin/ccs`, `bin/cods`, and `bin/gmis` wrap Claude, Codex, and Gemini.
- `bin/acfs-local-build` wraps explicit local fallback work; RCH remains the
  preferred build/test path.
- `acfs-resource-profile.sh` adds these wrapper commands to the current shell's
  PATH when sourced.
- `profile.json` records the selected profile.

Applying the profile does not rewrite NTM templates, existing aliases, or
service units. NTM-launched agents use the limit only when their launch command
explicitly selects a generated wrapper. Running support services are not moved
into the new scopes.

## Resource Classes

Every class enables CPU, memory, I/O, and task accounting. When a memory limit
is selected, the same ceiling applies separately to each invocation in all five
classes, including the `rch` class.

| Class | Slice | CPU weight | I/O weight | Task limit | Intended explicit commands |
| --- | --- | ---: | ---: | ---: | --- |
| `agent` | `acfs-agent.slice` | 100 | 100 | 512 | Claude, Codex, Gemini |
| `background` | `acfs-background.slice` | 40 | 50 | 512 | Indexing, maintenance, analysis |
| `local-build` | `acfs-local-build.slice` | 60 | 50 | 512 | Deliberate local fallback builds/tests |
| `support` | `acfs-support.slice` | 80 | 100 | 256 | Explicitly launched support processes |
| `rch` | `acfs-rch.slice` | 100 | 100 | 512 | Local RCH command processes |

Weights determine relative scheduling under contention. Memory ceilings are
set on each transient scope, not as a shared limit on the slice. Several scopes
can collectively exhaust the host even when each stays below its own ceiling;
capacity planning and RCH offload remain necessary. Wrapping a local RCH command
does not impose this limit on a remote worker.

## Enforcement and Failure Behavior

With a selected memory ceiling, the wrapper requires `systemd-run`, a working
systemd user manager, Python 3, and cgroup v2 memory control. After entering the
new scope and before starting the requested command, it checks the actual
kernel `memory.max`. The limit must be finite and no greater than the reviewed
byte count. When a swap ceiling is selected, `memory.swap.max` must pass the
same check. Tighter limits are acceptable.

If the required tools, manager, controller, or limit evidence are unavailable,
or creating the scope fails, the bounded wrapper stops without running the
payload. It never retries that command outside containment. The default
profile without a memory ceiling retains its direct-execution fallback when
systemd user scopes are unavailable.

`MemoryMax` covers memory charged to the scope's process tree. If usage cannot
be contained, the kernel can kill a process within it. The killed process may
be the agent itself: this feature does not guarantee preservation of an agent
session. ACFS does not set `OOMPolicy`, preserving compatibility with systemd
249; administrator policy and kernel victim selection still matter. See the
[systemd 249 resource-control manual](https://www.freedesktop.org/software/systemd/man/249/systemd.resource-control.html)
and [scope manual](https://www.freedesktop.org/software/systemd/man/249/systemd.scope.html).

ACFS does not set `MemoryHigh`. That setting throttles and reclaims memory; its
breach alone does not invoke the OOM killer. Do not treat a standalone
`MemoryHigh` setting as runaway protection. If adding it independently, pair
it with a verified escape mechanism such as a hard ceiling or a configured
userspace OOM killer. See the kernel's [cgroup v2 memory interface](https://docs.kernel.org/admin-guide/cgroup-v2.html#memory-interface-files).

This profile does not install or configure `systemd-oomd` or tune limits
automatically. The report and isolated tests do not establish successful
containment on every host; inspect the actual scope on the host where commands
will run.

## Check Live Memory Pressure Before Launching

The separate live preflight uses swap occupancy and Linux memory pressure stall
information (PSI), alongside the existing RAM, load, and disk checks:

```bash
acfs swarm status --json
acfs swarm doctor --json
acfs swarm plan --agents 10 --json
```

The status collector reads `SwapTotal` and `SwapFree` from `/proc/meminfo` and
the `some` and `full` `avg60` percentages from `/proc/pressure/memory`. Its
schema-1 `host` object adds `swap_total_kb`, `swap_free_kb`,
`memory_psi_some_avg60`, and `memory_psi_full_avg60`. Unavailable or malformed
readings are `null` with a warning, never a fabricated zero. Swap readings must
be nonnegative integers with free no greater than total; PSI percentages must
be between 0 and 100 with full no greater than some.

As described in the [kernel PSI documentation](https://docs.kernel.org/accounting/psi.html),
`full` measures time when all non-idle tasks are simultaneously stalled on
memory. The 60-second trend catches sustained stalls that free RAM and CPU load
alone can miss. `some` is retained for diagnostics and consistency checking.
These are instantaneous reads of the kernel's rolling averages; the command
does not wait for a new 60-second sample.

The following conservative thresholds are ACFS admission policy, not kernel
defaults. Other existing blockers still apply.

| Memory evidence | Doctor / plan status | Plan and explicit launch behavior |
| --- | --- | --- |
| At least 90% of configured swap is occupied | `warn` | `wait`; suppress launch advice and refuse a new explicit launch |
| Memory `full avg60` is at least 1%, below 10% | `warn` | `wait`; suppress launch advice and refuse a new explicit launch |
| Memory `full avg60` is at least 10% | `fail` | `wait`; refuse a new explicit launch even when RAM and load look healthy |
| A required swap or PSI reading is missing | At least `warn` | `wait`; collect fresh, complete evidence before launching |
| A saved reading has an invalid type, range, or relationship | `fail` | Refuse planning or launch from invalid evidence |
| Swap total and free are both zero | No swap warning on its own | No swap is configured; the RAM and PSI checks still apply |

High swap occupancy can reflect cold pages rather than active thrashing, so it
produces a warning instead of asserting memory failure. ACFS still pauses new
launches conservatively. Known severe PSI remains a failure even if another
reading is unavailable. Older saved snapshots without these fields remain
readable but cannot establish current readiness.

`acfs swarm launch` already obtains a fresh live plan and requires its quiesce
decision to be `proceed`. `--accept-warnings` cannot override `wait`, a hard
failure, or an invalid report. The preflight does not change static capacity
estimates, kill running agents, activate swap, or replace per-scope containment.
It checks admission at launch time; it is not a continuous memory watchdog.

For a blocked host, inspect `free -h` and `cat /proc/pressure/memory`, reduce or
finish existing work, and rerun the live preflight when pressure has cleared.
If PSI is unavailable, inspect kernel support and enable it through the host's
normal administrative process rather than substituting zero values in a report.

## Inspect or Disable

```bash
~/.acfs/resource-profile/bin/acfs-scope --help
cat ~/.acfs/resource-profile/profile.json
systemctl --user show-environment
systemctl --user list-units --type=scope
# Substitute an actual running scope from the preceding command:
systemctl --user show run-EXAMPLE.scope -p MemoryMax -p MemorySwapMax -p ControlGroup
```

To write a disabled marker/snippet without deleting files:

```bash
acfs capacity --resource-profile --disable-resource-profile
```

Disabling prevents the snippet from adding wrappers in a new shell. It does not
remove the wrapper directory from an existing shell's PATH, remove wrapper
files, or stop scopes that are already running. Start a fresh shell without the
opt-in snippet, or use the original agent commands directly.
