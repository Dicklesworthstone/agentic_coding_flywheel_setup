# Process-storm watchdog

`acfs update` runs a small watchdog over the process table for the duration of
the run. If a single process name — or the table as a whole — blows past a
threshold, it writes a forensic snapshot to disk and keeps going. It never
kills anything.

It exists because of a failure that could not be diagnosed: a build worker
accumulated roughly 3,600 concurrent `ast-grep` processes during overlapping
`acfs update` runs and went into fork exhaustion. The host had to be rebooted,
and the reboot destroyed the only evidence that mattered — the parent chain,
the argv, and the fork rate. See issue #348.

ACFS itself does not fan `ast-grep` out. The only two places it touches the
tool are `cargo install ast-grep` (`update_cargo_tools`, `cli_tools.sh`) and a
single `timeout`-bounded `--version` probe in `doctor`. There is no `xargs`,
no `xargs -P`, no `find -exec`, and no per-file loop anywhere in
`scripts/lib/`. Overlapping runs can no longer stack in any case: `acfs
update` has taken an exclusive per-UID `flock` since #347. So the mechanism is
still open, and the watchdog is there to make the next occurrence answerable
instead of speculative.

## What it captures

Each trip appends a snapshot to
`~/.acfs/diagnostics/procwatch/storm-<timestamp>-<pid>-<n>.txt`:

- the trip reason and the total process count;
- `loadavg`, `procs_running`, `procs_blocked`, `pid_max`, `threads-max`;
- the kernel's cumulative fork counter (`/proc/stat`'s `processes` line) — two
  snapshots of it give the spawn rate directly;
- the full process-name histogram, descending;
- up to 256 of the offending processes with their PPID and complete argv;
- a parent histogram: every distinct PPID, how many children it had, and that
  parent's own name and argv (or `<gone>` if it already exited).

The parent histogram is the point. In the original incident the shape was
"many distinct short-lived `sh -c` wrappers, one `ast-grep` each", which is a
very different mechanism from "one parent forking in a loop" — and the
snapshot distinguishes them immediately.

## Why it uses no external commands

The sampling and dumping paths are pure bash builtins: globbing `/proc`,
`read`, `mapfile`, `printf`, and a `read -t` on a FIFO in place of `sleep`.
The failure being diagnosed *is* fork exhaustion. A watchdog that has to fork
`ps`, `sort`, or `sleep` is precisely the watchdog that stops working at the
moment it becomes useful.

## Tuning

| Variable | Default | Meaning |
|---|---|---|
| `ACFS_PROCWATCH` | `1` | Set to `0` to disable entirely. |
| `ACFS_PROCWATCH_INTERVAL` | `30` | Seconds between samples. |
| `ACFS_PROCWATCH_THRESHOLD` | `max(256, cores * 32)` | Trip when one process name reaches this count. |
| `ACFS_PROCWATCH_TOTAL_THRESHOLD` | `max(2000, cores * 200)` | Trip when the whole table reaches this size. |
| `ACFS_PROCWATCH_MAX_DUMPS` | `5` | Stop after this many snapshots in one run. |
| `ACFS_PROCWATCH_DIR` | `~/.acfs/diagnostics/procwatch` | Snapshot directory. |
| `ACFS_PROCWATCH_PROC` | `/proc` | Proc root (tests only). |

The defaults scale with core count because a legitimate build peaks near one
compiler per core; 32x cores is far above anything normal while still catching
a storm long before the process table fills. A non-numeric override disables
the watchdog rather than behaving unpredictably.

The watchdog is Linux-only — it needs `/proc` — and silently does nothing
elsewhere.

## Deliberate reproduction

If the storm is ever reproduced on purpose, exec-level tracing answers the
question outright. On a scratch host, before starting anything:

```bash
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_execve /str(args->filename) =~ "ast-grep"/ {
    printf("%d <- ppid %d : %s\n", pid, curtask->real_parent->pid, str(args->filename)); }'
```

or, with auditd instead of bpftrace:

```bash
sudo auditctl -a always,exit -F arch=b64 -S execve -F path=/usr/bin/env -k astgrep
```

Then start two runs that overlap, queueing the second behind the update lock
so both actually run rather than one skipping:

```bash
acfs update &
sleep 300
ACFS_UPDATE_LOCK_WAIT=1 acfs update &
```

A run that does *not* reproduce under two concurrent updates is informative
too: it points away from the concurrency theory.
