# RCH: Remote Compilation Helper

**Goal:** Offload Rust builds to remote workers for faster compilation.

---

## Why RCH Matters

Rust compilation is CPU-intensive. When running multiple AI agents that all trigger builds, your local machine can become a bottleneck. RCH transparently routes `cargo` commands to remote workers with more CPU/RAM.

---

## How It Works

RCH intercepts Claude Code cargo commands via a hook. Codex and other agents should invoke the offload wrapper explicitly:

```
Agent: rch exec -- cargo build --release
         ↓
RCH Hook intercepts
         ↓
Syncs source to worker via rsync
         ↓
Worker: cargo build --release (on powerful server)  # rch-policy: allow worker-side command
         ↓
Artifacts synced back
```

---

## Essential Commands

### Quick Start

```bash
# Install the Claude Code hook
rch hook install

# Start the local daemon
rch daemon start
```

### Worker Management

```bash
# Add a remote worker (interactive wizard: host, SSH, cores, toolchain)
rch workers init

# Or pick hosts up from your SSH config
rch workers discover --add

# List configured workers
rch workers list

# Check worker connectivity
rch workers probe --all
```

---

## System Status

```bash
# See overall status
rch status

# Detailed diagnostics
rch doctor
```

---

## Configuration

```bash
# View current configuration
rch config show

# Set default worker
rch config set default_worker=myserver
```

---

## Quick Reference

| Command | What it does |
|---------|--------------|
| `rch hook install` | Install Claude Code hook |
| `rch daemon start` | Start local daemon |
| `rch workers init` | Add a remote worker (wizard) |
| `rch workers list` | List all workers |
| `rch workers probe --all` | Check worker connectivity |
| `rch status` | System overview |
| `rch doctor` | Run diagnostics |
| `rch update` | Update RCH binaries |

---

## Integration with Other Tools

- **NTM**: Agents spawned by NTM use RCH for builds
- **RU**: RU syncs repos that RCH then builds remotely
- **Beads**: Build tasks can be tracked via beads

---

## Best Practices

1. **Set up SSH keys** for passwordless access to workers
2. **Use fast workers** with lots of CPU cores and RAM
3. **Keep workers in sync** with `rch update --fleet`
4. **Check status regularly** with `rch status`

---

## Troubleshooting

```bash
# If builds aren't offloading
rch doctor --fix

# Check if daemon is running
rch daemon status

# Verify worker connectivity
rch workers probe --all
```

---

*Run `rch status` to see your current setup!*
