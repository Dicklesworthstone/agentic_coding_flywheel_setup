# ACFS Utility Tools

This document covers the utility tools included in ACFS. These are optional but useful tools from the Dicklesworthstone ecosystem.

## Tool Overview

| Tool | Command | Purpose |
|------|---------|---------|
| toon_rust | `toon` | Token-optimized notation for LLM context |
| rust_proxy | `rust_proxy` | Route selected domains through an upstream proxy (Linux iptables + ipset) |
| rano | `rano` | Observe which hosts AI CLI processes connect to |
| xf | `xf` | Ultra-fast X/Twitter archive search |
| mdwb | `mdwb` | Convert websites to Markdown for LLMs |
| pt | `pt` | Process triage for stuck processes |
| aadc | `aadc` | ASCII diagram corrector |
| s2p | `s2p` | Source code to LLM prompt generator |
| caut | `caut` | Coding agent usage tracker |

---

## toon_rust (toon)

Token-optimized notation format for efficient LLM context usage. The Cargo package
(and ACFS checksum key) is `tru`; the binary it installs is `toon`.

### Installation Verification

```bash
toon --version
toon --help
```

### Basic Usage

```bash
# Convert JSON to TOON (direction is auto-detected from the extension)
toon input.json -o output.toon

# Convert TOON back to JSON
toon input.toon -o output.json

# Encode stdin and print token estimates to stderr
cat input.json | toon --encode --stats
```

### Use Cases

- Compress large JSON payloads for LLM context
- Reduce token usage in agent communications
- Optimize data serialization for AI workflows

---

## rust_proxy

Targeted transparent routing (Linux only): iptables + ipset send traffic for selected
domains through an upstream HTTP proxy via CONNECT tunnels, with health checks and
failover. It does not decrypt or inspect payloads.

### Installation Verification

```bash
rust_proxy --version
rust_proxy --help
```

### Basic Usage

```bash
# Write a starter config (already targets the main AI provider domains)
rust_proxy init

# Add an upstream proxy and an extra target domain
rust_proxy proxy add mesh-us us-wa.proxymesh.com:31280 \
  --username-env PROXY_USER --password-env PROXY_PASS
rust_proxy targets add api.x.ai

# Pick the active proxy, then run the daemon (needs root for iptables)
rust_proxy activate --select
sudo rust_proxy daemon

# Check routing and health
rust_proxy status
rust_proxy test api.openai.com --verbose
```

### Use Cases

- Route AI API traffic through a specific egress region or proxy provider
- Keep agent traffic on a known proxy with automatic failover
- Diagnose proxy reachability (`test`, `trace`, `ping`, `doctor`)

---

## rano

Network observer for AI CLIs: polls the sockets held by Claude Code, Codex CLI, Gemini CLI
and their descendants and attributes each connection to a process and provider. No proxy,
no payload capture.

### Installation Verification

```bash
rano --version
rano --help
```

### Basic Usage

```bash
# Watch all detected AI CLI processes live
rano

# Watch only Codex and log events to SQLite
rano --pattern codex --sqlite /tmp/rano.sqlite

# Summarize the latest run, or export history
rano report --latest
rano export --format csv --since 24h > daily.csv
```

### Use Cases

- See which provider endpoints an agent actually connects to
- Spot retry storms and long-lived connections during a stuck session
- Keep an auditable connection history per run

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
# Index your downloaded archive once
xf index /path/to/your-archive

# Search everything (tweets, likes, DMs, Grok chats, bookmarks)
xf search "machine learning"

# Search only tweets in a date range
xf search "rust" --types tweet --since 2024-01-01 --until 2024-06-01

# Search DMs
xf search "project update" --types dm
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
# Capture a page (screenshot tiles -> OCR -> stitched Markdown) and watch progress
mdwb fetch https://example.com --watch

# Check a job's status, print its Markdown, and list extracted links
mdwb show <job-id>
mdwb jobs result <job-id>
mdwb links <job-id> --json

# Crawl a docs site (seed plus discovered pages, capped)
mdwb crawl https://docs.example.com --max-depth 1 --max-pages 10
```

The CLI talks to the mdwb server and needs an olmOCR endpoint (hosted API key or a local
olmOCR server); see the project README for setup.

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
# Interactive golden path: scan, review candidates, confirm actions
pt run

# Quick scan only (no inference or action)
pt scan

# Full deep scan with all available probes
pt deep-scan

# Agent-friendly ranked plan with evidence (no execution)
pt agent plan --format json
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
# Print the corrected diagram to stdout
aadc diagram.txt

# Fix the file in place
aadc -i diagram.txt

# Show a diff of the proposed changes without writing
aadc --diff diagram.txt

# Fix every Markdown file under docs/ in place
aadc -ri --glob "*.md" docs/
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

Check remaining quota, rate-limit windows, credits, and local cost across coding-agent providers (Codex, Claude, Gemini, Cursor, Copilot, and more).

### Installation Verification

```bash
caut --version
caut --help
```

### Basic Usage

```bash
# Quota, rate-limit windows and credits per provider
caut usage --provider all

# Local cost from agent JSONL logs
caut cost

# Usage trend for the past week
caut history show --days 7

# Export usage history
caut history export --format csv
```

### Use Cases

- Check remaining quota before launching a swarm
- Track local cost per provider and per session (`caut session --today`)
- Review usage history and trends

---

## Installation

All utilities are optional ACFS modules. toon_rust, pt, mdwb and s2p are on by default;
xf, rano, rust_proxy, aadc and caut are opt-in. ACFS installs toon_rust, rano, xf, pt, mdwb
and s2p with each project's checksum-verified `install.sh` (see `checksums.yaml`), and builds
rust_proxy, aadc and caut from a source checkout as Cargo release builds.

Do not guess crate names for `cargo install`: only toon_rust is on crates.io (as `tru`), and
the crates named `rano`, `xf` and `rust-proxy` there are unrelated projects by other authors.
To install one by hand, use the install one-liner in that project's README.

`mdwb` (markdown_web_browser) is a Python project (FastAPI + Playwright + OCR), not a Rust crate; follow its README.

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

Tools from verified installers land in `~/.local/bin/`; the source-built ones (rust_proxy,
aadc, caut) land in `~/.cargo/bin/`. The ACFS zshrc puts both on PATH; in another shell:

```bash
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
```

### Version Mismatch

Update the Flywheel stack tools (this re-runs each selected tool's verified installer or
source build):

```bash
acfs update --stack-only
```

### Missing Dependencies

The released binaries need no extra libraries. Building from source needs a C toolchain:

```bash
sudo apt install -y build-essential pkg-config libssl-dev
```

rano's optional pcap mode (DNS answers and TLS SNI) needs a build with `--features pcap`,
`libpcap-dev`, and root or CAP_NET_RAW. rust_proxy needs `iptables` and `ipset` at runtime.
