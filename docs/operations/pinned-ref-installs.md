# Pinned Reference Installs

This document explains how to use pinned references for reproducible ACFS installations.

## Overview

By default, the ACFS installer fetches scripts from the `main` branch. This means you always get the latest version, but installations done at different times may produce different results.

For production environments or when you need consistent installs across multiple machines, you can "pin" to a specific version.

## How Pinning Works

Pass `--ref` to the installer and use the same ref in the raw GitHub URL:

```bash
# Pin to a tagged release (recommended for production)
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/v0.6.0/install.sh" | bash -s -- --yes --mode vibe --ref v0.6.0

# Pin to a specific commit SHA (maximum reproducibility)
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/abc1234/install.sh" | bash -s -- --yes --mode vibe --ref abc1234
```

## When to Use Pinning

### Use Pinned References When:

1. **Production Deployments** - Ensure all servers get identical installations
2. **Team Environments** - Keep everyone on the same tool versions
3. **CI/CD Pipelines** - Deterministic builds and tests
4. **Auditing/Compliance** - Document exactly what was installed

### Use Main Branch (Default) When:

1. **Development/Experimentation** - Want latest features and fixes
2. **Single Machine Setup** - One-off personal environment
3. **Following Tutorials** - Using latest documentation

## Tradeoffs

| Aspect | Pinned Ref | Main Branch |
|--------|------------|-------------|
| **Reproducibility** | Exact same install every time | May vary between installs |
| **Latest Fixes** | Only gets fixes in that version | Always gets latest fixes |
| **Security Patches** | Must manually update | Automatic on re-install |
| **Tool Versions** | Frozen at pin time | May get newer tool versions |
| **Checksums** | Stable, verified | May change with upstream |

## Using the Wizard

The [ACFS Wizard](https://agent-flywheel.com/wizard/run-installer) includes a "Pin to specific version" toggle:

1. Enable the toggle
2. Enter a tag (e.g., `v0.6.0`) or commit SHA
3. The generated command pins the installer ref automatically

## Installer Flags

When using pinned refs, you can also use:

```bash
# Use --ref instead of relying on shell environment-variable placement
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/v0.6.0/install.sh" | bash -s -- --yes --mode vibe --ref v0.6.0

# Resolve a branch or tag to a copy-pasteable pinned SHA command
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh" | bash -s -- --pin-ref --ref main

# Fetch checksums from a different ref (advanced)
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/v0.6.0/install.sh" | bash -s -- --yes --mode vibe --ref v0.6.0 --checksums-ref main
```

## Finding Version Tags

View available releases:

```bash
# List all tags
curl -s "https://api.github.com/repos/Dicklesworthstone/agentic_coding_flywheel_setup/tags" | jq -r '.[].name'

# Or visit: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/releases
```

## Verifying Your Installation

After installation, check which version is installed:

```bash
cat ~/.acfs/VERSION
# Outputs: 0.6.0

# Check the ref used (if recorded)
cat ~/.acfs/INSTALL_REF 2>/dev/null || echo "main (default)"
```

## Updating Pinned Installations

To update a pinned installation:

```bash
# Option 1: Re-run with new pin
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/v0.7.0/install.sh" | bash -s -- --yes --mode vibe --ref v0.7.0

# Option 2: Use acfs update (updates to main)
acfs update

# Option 3: Force ACFS to reinstall managed tools from the pinned ref
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/v0.7.0/install.sh" | bash -s -- --yes --mode vibe --ref v0.7.0 --force-reinstall
```

## Best Practices

1. **Document Your Pin** - Record the exact ref used in your deployment docs
2. **Test Before Production** - Try the pinned version on a test machine first
3. **Monitor for Security Updates** - Subscribe to release notifications
4. **Use Tags Over Commits** - Tags are more readable and documented
5. **Keep a Rollback Plan** - Know how to restore if an update breaks things
