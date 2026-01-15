# Repo-Dispatch Checksum Update Setup

This document explains how to configure ACFS-owned tool repositories to automatically notify ACFS when their installer scripts change, reducing the checksum mismatch window.

## Overview

When an ACFS tool (ntm, dcg, bv, etc.) updates its `install.sh`, ACFS's `checksums.yaml` becomes stale. Currently, ACFS polls every 2 hours to detect changes. With repo-dispatch hooks, tool repos can **immediately** notify ACFS when installer scripts change, reducing the mismatch window from hours to minutes.

## Architecture

```
┌──────────────────────┐
│  Tool Repo           │
│  (e.g., ntm, dcg)    │
│                      │
│  Push to install.sh  │
│         │            │
│         ▼            │
│  notify-acfs.yml     │
│         │            │
└─────────┼────────────┘
          │ repository_dispatch
          │ type: upstream-changed
          ▼
┌──────────────────────┐
│  ACFS Repo           │
│                      │
│  checksum-monitor.yml│
│         │            │
│         ▼            │
│  Regenerate checksums│
│  Commit & push       │
└──────────────────────┘
```

## Setup Instructions

### Step 1: Create a Personal Access Token (PAT)

1. Go to GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Create a new token with:
   - **Token name**: `acfs-checksum-dispatch`
   - **Expiration**: 1 year (or never for convenience)
   - **Repository access**: Select "Only select repositories" → choose `agentic_coding_flywheel_setup`
   - **Permissions**:
     - Contents: Read-only (to trigger workflows)
     - Metadata: Read-only (required)

   Alternatively, use a classic PAT with `repo` scope (simpler but broader access).

3. Copy the token value.

### Step 2: Add Secret to Tool Repo

1. Go to your tool repo (e.g., `Dicklesworthstone/ntm`) → Settings → Secrets and variables → Actions
2. Create a new repository secret:
   - **Name**: `ACFS_REPO_DISPATCH_TOKEN`
   - **Value**: The PAT from Step 1

### Step 3: Add Workflow to Tool Repo

Create `.github/workflows/notify-acfs.yml` in your tool repo:

```yaml
# .github/workflows/notify-acfs.yml
#
# Notifies ACFS when installer scripts change, triggering checksum updates.
# Related: agentic_coding_flywheel_setup-b04c
#
name: Notify ACFS of Installer Changes

on:
  push:
    branches: [main, master]
    paths:
      # Adjust this path to match your install script location
      - 'install.sh'
      # For repos with scripts/install.sh:
      # - 'scripts/install.sh'
  workflow_dispatch:  # Manual trigger for testing

jobs:
  notify-acfs:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger ACFS checksum update
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.ACFS_REPO_DISPATCH_TOKEN }}
          repository: Dicklesworthstone/agentic_coding_flywheel_setup
          event-type: upstream-changed
          client-payload: |
            {
              "tool": "${{ github.event.repository.name }}",
              "ref": "${{ github.ref }}",
              "sha": "${{ github.sha }}",
              "actor": "${{ github.actor }}",
              "timestamp": "${{ github.event.head_commit.timestamp }}"
            }

      - name: Log dispatch
        run: |
          echo "✅ Dispatched upstream-changed event to ACFS"
          echo "   Tool: ${{ github.event.repository.name }}"
          echo "   SHA: ${{ github.sha }}"
          echo "   Triggered by: ${{ github.actor }}"
```

## Tool-Specific Path Configuration

Different tools have different installer locations. Adjust the `paths` trigger accordingly:

| Tool | Repo | Installer Path |
|------|------|----------------|
| giil | `Dicklesworthstone/giil` | `install.sh` |
| cass | `Dicklesworthstone/coding_agent_session_search` | `install.sh` |
| mcp_agent_mail | `Dicklesworthstone/mcp_agent_mail` | `scripts/install.sh` |
| dcg | `Dicklesworthstone/destructive_command_guard` | `install.sh` |
| ntm | `Dicklesworthstone/ntm` | `install.sh` |
| cm | `Dicklesworthstone/cass_memory_system` | `install.sh` |
| caam | `Dicklesworthstone/coding_agent_account_manager` | `install.sh` |
| ubs | `Dicklesworthstone/ultimate_bug_scanner` | `install.sh` |
| slb | `Dicklesworthstone/simultaneous_launch_button` | `scripts/install.sh` |
| ru | `Dicklesworthstone/repo_updater` | `install.sh` |
| bv | `Dicklesworthstone/beads_viewer` | `install.sh` |
| csctf | `Dicklesworthstone/chat_shared_conversation_to_file` | `install.sh` |

## Workflow Template Variations

### For repos with `install.sh` at root:

```yaml
on:
  push:
    branches: [main, master]
    paths:
      - 'install.sh'
```

### For repos with `scripts/install.sh`:

```yaml
on:
  push:
    branches: [main, master]
    paths:
      - 'scripts/install.sh'
```

### For repos with multiple installer-related files:

```yaml
on:
  push:
    branches: [main, master]
    paths:
      - 'install.sh'
      - 'scripts/*.sh'
      - 'setup.py'  # If installer calls setup.py
```

## Testing the Setup

1. **Manual trigger**: Go to Actions → "Notify ACFS of Installer Changes" → Run workflow
2. **Check ACFS**: The `checksum-monitor` workflow should trigger within minutes
3. **Verify logs**: Check the ACFS workflow run for the `repository_dispatch` payload

## Troubleshooting

### Dispatch not triggering ACFS

1. Verify the PAT has correct permissions
2. Check the secret name is exactly `ACFS_REPO_DISPATCH_TOKEN`
3. Ensure the ACFS repo name is correct: `Dicklesworthstone/agentic_coding_flywheel_setup`
4. Check GitHub Actions is enabled on both repos

### PAT expired

1. Generate a new PAT following Step 1
2. Update the `ACFS_REPO_DISPATCH_TOKEN` secret in the tool repo

### Path filter not matching

1. Check the exact path of your install script
2. Use `git log --oneline -- path/to/install.sh` to verify git tracks the file at that path

## Security Considerations

- The PAT should have **minimal** permissions (only `contents:read` on ACFS repo)
- Store PATs as repository secrets, never in code
- Consider using fine-grained PATs over classic PATs
- Audit PAT usage periodically

## ACFS Receiver Configuration

The ACFS checksum-monitor workflow already handles `upstream-changed` events:

```yaml
# In checksum-monitor.yml (already configured)
on:
  repository_dispatch:
    types: [upstream-changed]
```

When triggered, it:
1. Logs the dispatch payload (tool name, SHA, etc.)
2. Verifies all checksums
3. Regenerates `checksums.yaml` if needed
4. Commits and pushes updates
5. Creates an issue for external (non-Dicklesworthstone) changes

## Monitoring

Check dispatch activity:
- Tool repo: Actions → "Notify ACFS of Installer Changes"
- ACFS repo: Actions → "Auto-Update Upstream Checksums" (filter by `repository_dispatch`)

---

*Related: bead `agentic_coding_flywheel_setup-b04c`*
