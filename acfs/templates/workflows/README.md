# ACFS Workflow Templates

Ready-to-use GitHub Actions workflow templates for ACFS-owned tool repositories.

## Available Templates

| Template | Use Case |
|----------|----------|
| `notify-acfs-root.yml` | Repos with `install.sh` at repository root |
| `notify-acfs-scripts.yml` | Repos with `install.sh` in `scripts/` directory |

## Quick Setup

1. **Create PAT**: Generate a Personal Access Token with `contents:read` on the `agentic_coding_flywheel_setup` repo

2. **Add Secret**: In your tool repo, create a secret named `ACFS_REPO_DISPATCH_TOKEN` with the PAT value

3. **Copy Template**: Copy the appropriate template to `.github/workflows/notify-acfs.yml`

4. **Test**: Trigger the workflow manually or push a change to your install script

## Which Template to Use

Check your `checksums.yaml` entry to see the installer path:

```yaml
# Root install.sh → use notify-acfs-root.yml
ntm:
  url: "https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh"

# scripts/install.sh → use notify-acfs-scripts.yml
mcp_agent_mail:
  url: "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh"
```

## Full Documentation

See `acfs/docs/repo-dispatch-setup.md` for complete setup instructions, troubleshooting, and security considerations.
