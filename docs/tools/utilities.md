# ACFS Utility Tools

This document covers the utility tools included in ACFS. These are optional but useful tools from the Dicklesworthstone ecosystem.

## Tool Overview

| Tool | Command | Purpose |
|------|---------|---------|
| toon_rust | `tru` | Token-optimized notation for LLM context |
| rust_proxy | `rust_proxy` | Transparent proxy for network debugging |
| rano | `rano` | Network observer for AI CLI traffic |
| xf | `xf` | Ultra-fast X/Twitter archive search |
| mdwb | `mdwb` | Convert websites to Markdown for LLMs |
| pt | `pt` | Process triage for stuck processes |
| aadc | `aadc` | ASCII diagram corrector |
| s2p | `s2p` | Source code to LLM prompt generator |
| caut | `caut` | Coding agent usage tracker |

---

## toon_rust (tru)

Token-optimized notation format for efficient LLM context usage.

### Installation Verification

```bash
tru --version
tru --help
```

### Basic Usage

```bash
# Convert JSON to TOON format
tru encode input.json > output.toon

# Convert TOON back to JSON
tru decode input.toon > output.json

# Estimate token savings
tru stats input.json
```

### Use Cases

- Compress large JSON payloads for LLM context
- Reduce token usage in agent communications
- Optimize data serialization for AI workflows

---

## rust_proxy

Transparent proxy routing for debugging network traffic.

### Installation Verification

```bash
rust_proxy --version
rust_proxy --help
```

### Basic Usage

```bash
# Start proxy on default port
rust_proxy start

# Start on specific port
rust_proxy start --port 8080

# View captured traffic
rust_proxy log
```

### Use Cases

- Debug API calls from AI agents
- Inspect request/response payloads
- Monitor network traffic patterns

---

## rano

Network observer for AI CLIs with request/response logging.

### Installation Verification

```bash
rano --version
rano --help
```

### Basic Usage

```bash
# Monitor Claude CLI traffic
rano watch claude

# Monitor all AI CLI traffic
rano watch --all

# Export logs
rano export --format json > traffic.json
```

### Use Cases

- Debug AI API interactions
- Monitor token usage across providers
- Analyze request patterns

---

## xf

Ultra-fast X/Twitter archive search powered by Tantivy.

### Installation Verification

```bash
xf --version
xf --help
```

### Basic Usage

```bash
# Search tweets
xf search "machine learning"

# Search with date range
xf search "rust" --after 2024-01-01 --before 2024-06-01

# Search DMs
xf search "project update" --type dm
```

### Use Cases

- Mine Twitter archives for insights
- Find historical conversations
- Extract knowledge from social media data

---

## mdwb (markdown_web_browser)

Convert websites to Markdown for LLM consumption.

### Installation Verification

```bash
mdwb --version
mdwb --help
```

### Basic Usage

```bash
# Fetch and convert URL to Markdown
mdwb fetch https://example.com

# Save to file
mdwb fetch https://docs.example.com/api > api-docs.md

# Follow links (crawl)
mdwb crawl https://docs.example.com --depth 2
```

### Use Cases

- Convert documentation to LLM-friendly format
- Prepare web content for AI analysis
- Archive web pages as Markdown

---

## pt (process_triage)

Find and terminate stuck/zombie processes with intelligent scoring.

### Installation Verification

```bash
pt --version
pt --help
```

### Basic Usage

```bash
# Show process triage recommendations
pt

# Show with details
pt --verbose

# Kill recommended processes
pt --kill

# Target specific process type
pt --filter node
```

### Use Cases

- Clean up stuck build processes
- Manage runaway AI agent processes
- Free system resources

---

## aadc

ASCII diagram corrector for fixing malformed ASCII art.

### Installation Verification

```bash
aadc --version
aadc --help
```

### Basic Usage

```bash
# Fix ASCII diagram from file
aadc fix diagram.txt

# Fix from stdin
cat diagram.txt | aadc fix

# Preview corrections
aadc fix diagram.txt --preview
```

### Use Cases

- Clean up LLM-generated ASCII diagrams
- Fix alignment issues in text art
- Standardize diagram formatting

---

## s2p (source_to_prompt_tui)

Source code to LLM prompt generator with an interactive TUI. Built with Bun/TypeScript (Ink), distributed as a compiled `s2p` binary — not a Rust crate.

### Installation Verification

```bash
s2p --help
s2p --version
```

### Basic Usage

Launch `s2p` to select files and generate prompts in its interactive TUI. Use `-h`/`--help` for usage or `-V`/`--version` for the installed version. The first positional argument is the directory to open in (defaults to the current directory):

```bash
# Launch the TUI in the current directory
s2p

# Launch the TUI rooted at a specific directory
s2p src/
```

Inside the TUI:

- **Explorer:** `j`/`k` move, `h`/`l` collapse/expand, `Space` selects files
- **Generate combined prompt:** `Ctrl+G`
- **Help:** `?` or `F1`
- **Quit:** `Esc` (twice) or `Ctrl+C`

### Use Cases

- Prepare code for LLM analysis
- Generate structured prompts from source files
- Create code review requests

---

## caut (coding_agent_usage_tracker)

Track LLM provider usage across coding agents.

### Installation Verification

```bash
caut --version
caut --help
```

### Basic Usage

```bash
# Show usage summary
caut status

# Show detailed breakdown
caut report --detailed

# Export usage data
caut export --format json > usage.json

# Set usage alerts
caut alert set --daily-limit 100000
```

### Use Cases

- Monitor API token consumption
- Track costs across providers
- Set usage budgets and alerts

---

## Installation

All utilities are installed via ACFS as optional tools. The Rust crates can be installed individually via cargo:

```bash
cargo install toon_rust
cargo install rust_proxy
cargo install rano
cargo install xf
cargo install markdown_web_browser
cargo install process_triage
cargo install aadc
cargo install coding_agent_usage_tracker
```

Install `s2p` (source_to_prompt_tui) through its Bash installer. Published standalone binaries include the Bun runtime; building from source requires Git and Bun:

```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/source_to_prompt_tui/main/install.sh | bash
```

## Health Checks

ACFS doctor includes checks for all utilities:

```bash
# Check utility installation status
acfs doctor --json | jq '.checks | map(select(.id | startswith("util.")))'
```

## Troubleshooting

### Tool Not Found

Most utilities install to `~/.cargo/bin/`. Ensure it's in your PATH:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

### Version Mismatch

Update to latest version:

```bash
cargo install --force TOOL_NAME
```

### Missing Dependencies

Some tools require system libraries:

```bash
# For Tantivy-based tools (xf)
sudo apt install -y build-essential pkg-config libssl-dev

# For network tools (rano, rust_proxy)
sudo apt install -y libpcap-dev
```
