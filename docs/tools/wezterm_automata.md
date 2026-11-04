# wezterm_automata (wa)

Terminal automation and orchestration for AI agents using WezTerm.

> **Status:** ACFS no longer installs `wa`. The repository is now
> [FrankenTerm](https://github.com/Dicklesworthstone/frankenterm), and its
> workspace has no `wa` package. Selecting `stack.wezterm_automata` reports this
> and builds nothing. An existing `wa` binary is still detected by `acfs doctor`.
> Install FrankenTerm with its own release installer, described in its
> [installation guide](https://github.com/Dicklesworthstone/frankenterm#installation).

## What It Does

`wa` (WezTerm Automata) provides programmatic control over WezTerm terminal sessions:
- Create, manage, and destroy terminal panes/tabs
- Send commands to terminal sessions
- Capture terminal output
- Orchestrate multi-terminal workflows

## Installation Verification

```bash
# Check wa is installed
wa --version

# Or check help
wa --help
```

## Basic Usage

### List Sessions

```bash
# List all WezTerm panes
wa list

# List with details
wa list --verbose
```

### Send Commands

```bash
# Send command to a specific pane
wa send --pane 0 "echo hello"

# Send to named session
wa send --name my-session "ls -la"
```

### Create Panes

```bash
# Create new pane
wa new

# Create with specific directory
wa new --cwd /data/projects/myproject

# Create named pane
wa new --name build-pane
```

### Capture Output

```bash
# Get current pane content
wa capture --pane 0

# Capture last N lines
wa capture --pane 0 --lines 50
```

## Common Workflows

### Multi-Agent Terminal Setup

Set up terminals for parallel agent work:

```bash
# Create development layout
wa new --name agent-1 --cwd /data/projects/backend
wa new --name agent-2 --cwd /data/projects/frontend
wa new --name logs --cwd /var/log
```

### Automated Build Monitoring

```bash
# Start build in one pane
wa send --name build "rch exec -- cargo build --release"

# Monitor in another
wa send --name logs "tail -f build.log"
```

### Session Persistence

```bash
# Save current layout
wa save my-layout

# Restore later
wa restore my-layout
```

## Configuration

Configuration is typically in `~/.config/wezterm/wa.toml`:

```toml
[defaults]
shell = "/usr/bin/zsh"
cwd = "/data/projects"

[layouts.dev]
panes = [
  { name = "editor", cwd = "." },
  { name = "shell", cwd = "." },
  { name = "logs", cmd = "tail -f logs/dev.log" }
]
```

## Troubleshooting

### "WezTerm not running"

Ensure WezTerm is started:

```bash
# Check if WezTerm is running
pgrep -f wezterm

# Start WezTerm
wezterm start &
```

### "Cannot connect to WezTerm"

Check the WezTerm socket:

```bash
# List WezTerm sockets
ls -la /tmp/wezterm-*

# Verify WEZTERM_UNIX_SOCKET
echo $WEZTERM_UNIX_SOCKET
```

### "wa: command not found"

Verify installation:

```bash
# Check installation
which wa
ls -la ~/.cargo/bin/wa
```

If it is missing, `wa` cannot be installed any more; see the status note at the
top of this page.

### Pane IDs Change

Pane IDs are dynamic. Use named panes for stability:

```bash
# Create with name (more stable)
wa new --name my-pane

# Reference by name
wa send --name my-pane "command"
```

## Integration with AI Agents

Agents can use wa for:
1. Setting up multi-pane development environments
2. Running parallel builds/tests
3. Monitoring logs while developing
4. Orchestrating complex workflows across terminals

Best practices:
- Use named panes for reliability
- Save layouts for reproducibility
- Capture output when debugging

## Integration with ntm

`wa` complements `ntm` (Named Tmux Manager):
- Use `ntm` for tmux-based session management
- Use `wa` for WezTerm-specific automation
- Both support AI agent orchestration workflows

## Related Tools

- `ntm` - Named tmux manager for session orchestration
- WezTerm - The terminal emulator being automated
- `pt` - Process triage for managing terminal processes
