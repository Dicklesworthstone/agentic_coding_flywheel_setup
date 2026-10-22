# ACFS Flywheel Tools Documentation

This directory contains documentation for the tools installed by ACFS (Agentic Coding Flywheel Setup).

## Core Tools

| Document | Tool(s) | Description |
|----------|---------|-------------|
| [beads_rust.md](beads_rust.md) | `br`, `bv` | Local-first issue tracker with graph-aware dependencies |
| [meta_skill.md](meta_skill.md) | `ms` | Knowledge management with hybrid semantic search |

## Build & Automation

| Document | Tool(s) | Description |
|----------|---------|-------------|
| [rch.md](rch.md) | `rch` | Remote compilation helper for build offloading |
| [wezterm_automata.md](wezterm_automata.md) | `wa` | Terminal automation and orchestration |

## Agent Memory

| Document | Tool(s) | Description |
|----------|---------|-------------|
| [ee.md](ee.md) | `ee` | Per-project durable memory you record explicitly; how it fits next to `cm` |

## Research & Knowledge

| Document | Tool(s) | Description |
|----------|---------|-------------|
| [brenner_bot.md](brenner_bot.md) | `brenner` | Research session manager with hypothesis tracking |

## Utility Tools

| Document | Tool(s) | Description |
|----------|---------|-------------|
| [utilities.md](utilities.md) | `tru`, `rust_proxy`, `rano`, `xf`, `mdwb`, `pt`, `aadc`, `s2p`, `caut` | Optional utility tools |

## Quick Reference

### Installation Verification

All tools can be verified with `acfs doctor`:

```bash
acfs doctor --json
```

### Tool Categories

- **Required**: br, ms, bv - Core workflow tools
- **Optional**: rch, wa, brenner, ee - Enhanced development tools
- **Utilities**: 9 optional utilities for specialized workflows

## Related Documentation

- [AGENTS.md](../../AGENTS.md) - Agent coordination guidelines
- [README.md](../../README.md) - Project overview
- [manifest-gap-analysis.md](../audits/manifest-gap-analysis.md) - Installer/manifest mapping
