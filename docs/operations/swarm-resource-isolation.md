# Swarm Resource Isolation Research

This note records the `bd-8qd3d` design decision for optional resource isolation on large ACFS hosts.

## Decision

ACFS should not enforce CPU, memory, or I/O limits for agent CLIs by default.

ACFS should expose an opt-in "balanced" resource profile later, implemented with `systemd-run --user --scope` wrappers for interactive agent commands and optional user-service drop-ins for support daemons. The first implementation should use scheduling weights and accounting before hard limits:

- Prefer `CPUWeight=` and `IOWeight=` for agent/build/background classes.
- Prefer `MemoryHigh=` only after a local capacity check can size it conservatively.
- Avoid `MemoryMax=` for Claude, Codex, Gemini, and build commands by default.
- Keep direct `cc`, `cod`, and `gmi` behavior unchanged unless the user opts in.

This matches the current ACFS posture: the capacity model recommends agent counts and RCH offload, while the shell aliases in `acfs/zsh/acfs.zshrc` launch the model CLIs directly and the Agent Mail service is the only always-on user service that ACFS currently owns.

## Why Systemd Is Appropriate

Systemd slices are designed to group services/scopes under a cgroup resource-control tree, and resource settings on a slice apply to the units inside that slice. See the upstream `systemd.slice` manual and `systemd.resource-control` manual:

- https://www.freedesktop.org/software/systemd/man/devel/systemd.slice.html
- https://www.freedesktop.org/software/systemd/man/devel/systemd.resource-control.html

For user sessions, systemd already defines user-side `app.slice`, `session.slice`, and `background.slice`. The upstream guidance describes `app.slice` for user applications, `session.slice` for latency-sensitive session services, and `background.slice` for non-interactive work:

- https://www.freedesktop.org/software/systemd/man/256/systemd.special.html

For shell-launched commands, `systemd-run --user --scope` is the least invasive shape because it creates a transient scope around a command instead of requiring a persistent service file. It also supports assigning a slice and properties such as resource controls:

- https://www.freedesktop.org/software/systemd/man/devel/systemd-run.html

## Proposed Resource Classes

These are recommendations for a future opt-in profile, not current installer behavior.

| Class | Commands | Proposed controls | Rationale |
| --- | --- | --- | --- |
| `acfs-agent.slice` | `claude`, `codex`, `gemini`, `ntm`-spawned interactive agents | `CPUWeight=100`, `IOWeight=100`, `TasksMax=512`, no default `MemoryMax` | Keep agent sessions first-class and avoid killing expensive context-heavy work. |
| `acfs-background.slice` | CASS indexing, maintenance sweeps, update jobs, local analysis that is not user-interactive | `CPUWeight=40`, `IOWeight=50`, optional `MemoryHigh=` from capacity model | Let interactive shells and support services stay responsive under load. |
| `acfs-local-build.slice` | Local fallback build/test commands when RCH is unavailable | `CPUWeight=60`, `IOWeight=50`, no default `MemoryMax` | Local builds are expensive but should not freeze the host; RCH remains the preferred path. |
| `acfs-support.slice` | Agent Mail, local dashboards, support-bundle helpers, lightweight telemetry collectors | `CPUWeight=80`, `IOWeight=100`, `TasksMax=256`, optional `MemoryHigh=1G` | Coordination daemons should remain responsive but are not expected to consume large CPU. |
| `acfs-rch.slice` | RCH CLI/daemon-side local processes | `CPUWeight=100`, `IOWeight=100` | RCH is already a pressure-relief layer; do not penalize the offload path. |

The first profile should expose these values as documented recommendations and generated examples. It should not automatically rewrite user aliases or service units.

## Example Future Wrapper

This is the shape to test before implementation:

```bash
systemd-run --user --scope --same-dir --collect \
  --slice=acfs-agent.slice \
  --property=CPUAccounting=yes \
  --property=MemoryAccounting=yes \
  --property=IOAccounting=yes \
  --property=TasksAccounting=yes \
  --property=CPUWeight=100 \
  --property=IOWeight=100 \
  --property=TasksMax=512 \
  claude --dangerously-skip-permissions
```

For Codex and Gemini, substitute the command after the properties. A wrapper must preserve the current working directory, environment variables, terminal behavior, exit status, and auth/config lookup paths.

## What To Avoid

- Do not put hard `MemoryMax=` on model CLIs until real high-context sessions are tested.
- Do not place all user processes under one capped `user-$UID.slice` profile; that risks surprising unrelated shells and editors.
- Do not make `systemd-run` mandatory. Fresh VPS and container-like environments can have a missing or degraded user manager.
- Do not wrap RCH-heavy commands in a way that hides the `rch exec --` policy or makes local fallback look like the preferred path.

## Implementation Path

1. Add an `acfs resource-profile` or `acfs capacity --resource-profile` report that prints the proposed classes for the current host.
2. Add a shell helper such as `acfs_scope <class> -- <command...>` that falls back to direct execution when `systemd-run --user` is unavailable.
3. Add opt-in aliases, for example `ccs`, `cods`, and `gmis`, instead of changing `cc`, `cod`, or `gmi`.
4. Add optional drop-ins for ACFS-owned user services only, starting with `agent-mail.service.d/resource-profile.conf`.
5. Add NTM integration only after direct shell-wrapper tests pass; NTM should receive explicit class hints rather than infer from command strings.

## Verification Required Before Implementation

Manual checks:

```bash
systemctl --user show-environment
systemd-run --user --scope --same-dir --collect --property=CPUAccounting=yes true
systemd-run --user --scope --same-dir --collect --slice=acfs-agent.slice --property=CPUWeight=100 claude --help
systemd-cgls --user
systemctl --user show acfs-agent.slice -p CPUAccounting -p CPUWeight -p TasksAccounting
```

Regression coverage:

- Wrapper preserves exit code for success and failure commands.
- Wrapper preserves `PWD` and auth/config environment for Claude, Codex, and Gemini.
- Wrapper falls back to direct execution when `systemd-run --user` or the user bus is unavailable.
- Agent Mail drop-in can be enabled, disabled, and reverted without breaking health checks.
- Capacity output explains that weights are relative and hard memory limits are opt-in.

## Final Recommendation

Systemd slices are appropriate for ACFS, but only as an opt-in profile. The safe first step is a report plus wrappers that apply CPU/I/O weights and accounting. Hard memory limits should wait for measured high-context agent sessions and explicit user consent.
