# Capacity within the current process's resource limits

`acfs capacity --json` now bounds its existing workload model by the CPU and
memory actually visible to its **current execution context**. A container or
systemd service is not allowed to borrow the whole machine's advertised RAM
or round a fractional CPU quota up to a full core.

The calculation takes the smaller of the existing host observations, scheduler
CPU affinity (including cpusets), and applicable cgroup ceilings. CPU budgets
stay in integer millicores until division by the per-agent workload. For
example, a 1.5-core quota permits at most three light, one standard, or zero
heavy agents under the existing CPU assumptions. A 256-GiB host restricted to
8 GiB uses 8 GiB before the existing memory reserve and per-agent calculations.
Nothing writes cgroup settings, installs a package, changes a service, or
launches an agent.

## Observed controls

The collector resolves this process's memberships through `/proc/self/cgroup`
and `/proc/self/mountinfo`; it does not assume a fixed `/sys/fs/cgroup` layout.
It handles unified v2, separate v1 controllers, hybrid layouts, namespaced
roots, and subtree mounts. Every visible ancestor up to the selected mount
root is inspected so an unlimited leaf cannot hide a tighter parent.

For v2 it reads `cpu.max` and `memory.max`. For v1 it reads
`cpu.cfs_quota_us`, `cpu.cfs_period_us`, `memory.limit_in_bytes`, and the
optional kernel-computed `hierarchical_memory_limit` in `memory.stat`.
Unlimited values never raise host bounds. Scheduler affinity supplies the
cpuset restriction; CPU weights and memory.high are not misrepresented as
hard quotas. V1 ancestor limits are conservatively included even on obsolete
kernels configured without hierarchical accounting.

These interfaces are documented by the Linux kernel:
- https://docs.kernel.org/admin-guide/cgroup-v2.html
- https://docs.kernel.org/admin-guide/cgroup-v1/memory.html
- https://docs.kernel.org/scheduler/sched-bwc.html

## Read the report

The v1 capacity JSON retains its existing count fields and adds
`resource_limits` with observation status, controller version, affinity count,
CPU/memory ceilings, effective budgets, and redacted diagnostic codes. No
cgroup pathname, process ID, hostname, or raw kernel exception is included.
`host.mem_total_mib` is the effective model memory; `host.physical_mem_total_mib`
retains the original host observation. `host.cpu_count` remains the existing
processor count, while `host.effective_cpu_millicores` is the budget used by
the model. Human output labels both budgets.

Missing Python, unresolved membership, unreadable or malformed controller data,
and a membership/mount change during inspection suppress positive capacity.
The JSON has `status: fail`, zero recommended/safe counts, and a remediation
message rather than silently falling back to unrestricted host resources.
A successful JSON command exit still means the report was produced, not that
its `status` is pass. Inspect the report's status and counts before use.

The existing explicitly supplied CPU/memory test overrides remain supported
and are marked `test_override`/`fixture`, not measured kernel evidence. They are
not inherited by the inventory's `probe-local` calculator child. No new
production filesystem override or bypass flag is introduced.

## Scope and downstream use

The existing planner and local inventory probe consume the corrected capacity
counts without a separate resource model. Measure in the same container,
service, and account context where the agents will execute. Running a probe in
a restricted transient service does not describe agents later launched outside
that service, and the inverse is equally unsafe. Re-probe existing inventories;
saved snapshots do not change retroactively.

Only **visible** ancestors can be inspected. Namespaces can hide additional
limits, and resource settings can change after the observation. These are
upper bounds for the existing sizing model, not a reservation or a guarantee
of available CPU/RAM. Other processes may consume a shared ancestor's budget.
Continue using live queue/pressure admission before an actual swarm launch.

## Validation

`python3 -B tests/unit/test_capacity_limits.py` exercises controller fixtures
and the production capacity model/JSON projection. `--live` separately runs
the unmodified entrypoint against its current Linux process. CI additionally
runs it in a real transient systemd service with a 512-MiB memory ceiling and
a half-core quota, verifies zero safe capacity there, and compares the original
and modified report under the same restrictions. No memory stress workload or
paid provider session is started.
