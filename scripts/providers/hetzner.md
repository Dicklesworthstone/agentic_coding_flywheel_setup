# Hetzner Cloud VPS Setup Guide

Set up a VPS on Hetzner Cloud for running ACFS and coding agents.

---

## Provider Overview

**Hetzner** is a German hosting provider with excellent performance, modern UI, and competitive European pricing.

| Aspect | Details |
|--------|---------|
| **ACFS Target** | 48-64GB RAM for a multi-agent swarm (32GB is a tight minimum) |
| **Best For** | Developers who want a modern cloud experience and instant provisioning |
| **Signup** | [hetzner.com/cloud](https://www.hetzner.com/cloud/) |

### Pros
- Excellent price-to-performance ratio
- Beautiful, modern control panel
- Fast provisioning (< 1 minute)
- Great API and CLI tools
- Terraform support

### Cons
- Fewer global locations (Germany, Finland, US, Singapore)
- Plans with 32GB+ RAM cost noticeably more than Contabo or OVH; Hetzner raised Cloud prices on
  15 June 2026 ([price adjustment](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/))
- Not in the wizard's priced provider table, so compare specs yourself
- Requires identity verification for new accounts

---

## Step 1: Create an Account

1. Go to [accounts.hetzner.com](https://accounts.hetzner.com)
2. Click "Register" and create an account
3. Complete identity verification (may require ID upload)

---

## Step 2: Access Hetzner Cloud Console

1. Log into [console.hetzner.cloud](https://console.hetzner.cloud)
2. Create a new project (if first time)
3. Click "Add Server"

---

## Step 3: Choose Location

Select a data center:
- **Europe**: Nuremberg, Falkenstein, Helsinki
- **Americas**: Ashburn (Virginia), Hillsboro (Oregon)
- **Asia**: Singapore

Pick the closest location to you for best latency.

---

## Step 4: Select Operating System

1. Under "Image", click "Ubuntu"
2. Select **Ubuntu 26.04** (Hetzner's `ubuntu-26.04` image, available since May 2026)

---

## Step 5: Choose Server Type

Pick a server type by RAM, not by the cheapest price. Several coding agents, language servers and
builds run at once, so:

- **32GB RAM** is a tight minimum (a few agents at a time)
- **48-64GB RAM** is the ACFS target for a multi-agent swarm
- **160GB+ SSD**; the installer refuses to start with less than 20GB free

Hetzner's shared-CPU lines top out around 32GB; larger sizes are on the dedicated-vCPU (CCX) line.
Check current specs and prices on [hetzner.com/cloud](https://www.hetzner.com/cloud/) before
buying; plan names and prices change.

---

## Step 6: Add Your SSH Key

This is the recommended way to access your server.

1. Click "Add SSH Key"
2. Paste your public SSH key
3. Give it a name

If you don't have the ACFS key yet (the wizard's "Generate SSH key" step creates the same one):
```bash
ssh-keygen -t ed25519 -f ~/.ssh/acfs_ed25519 -C "acfs"
cat ~/.ssh/acfs_ed25519.pub
```

---

## Step 7: Configure Networking

Leave defaults:
- **Public IPv4**: Enabled
- **Public IPv6**: Enabled
- **Private Network**: Optional

---

## Step 8: Name Your Server

1. Enter a memorable name (e.g., "acfs-dev")
2. Review configuration
3. Click "Create & Buy now"

Your server will be ready in under 1 minute!

---

## Step 9: Find Your IP Address

Once created:

1. Click on your server in the dashboard
2. Copy the **IPv4 address** from the overview

---

## Step 10: Connect via SSH

```bash
ssh -i ~/.ssh/acfs_ed25519 root@YOUR_IP_ADDRESS
```

Hetzner uses `root` by default with the SSH key you added in Step 6.

---

## Step 11: Run the ACFS Installer

Do not create the `ubuntu` user manually. Run ACFS from the initial `root` session:

```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh | bash -s -- --yes --mode vibe
```

ACFS creates the `ubuntu` user, enables passwordless sudo for it in vibe mode, and copies the root
SSH key from Step 6 into `/home/ubuntu/.ssh/authorized_keys`. When the installer finishes, read its
final summary, then reconnect from your local machine:

```bash
exit
ssh -i ~/.ssh/acfs_ed25519 ubuntu@YOUR_IP_ADDRESS
```

---

## Hetzner-Specific Notes

### Cloud-Init Template
For automated server bootstrap, use the companion cloud-init template. It installs ACFS on first
boot and refuses any image other than Ubuntu 26.04 LTS (it never upgrades the OS):

```bash
hcloud server-type list   # pick a type with at least 32GB RAM (see Step 5)
hcloud server create \
  --name acfs-dev \
  --type YOUR_SERVER_TYPE \
  --image ubuntu-26.04 \
  --ssh-key your-key-name \
  --user-data-from-file scripts/providers/hetzner-cloud-init.yml
```

### Default User
Hetzner uses `root` by default. The ACFS installer creates the `ubuntu` user (see Step 11).

### Firewall
Hetzner Cloud has a built-in firewall feature (free). Consider creating rules:
1. Go to "Firewalls" in the sidebar
2. Create a new firewall
3. Allow SSH (port 22)
4. Apply to your server

### CLI Tool
Hetzner has an excellent CLI:
```bash
# Install
brew install hcloud  # macOS
# or
curl -o hcloud.tar.gz -L https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz

# Use
hcloud server list
hcloud server ssh my-server
```

### Snapshots
Take snapshots before major changes:
- Go to server > Snapshots
- Click "Take Snapshot"
- Can restore anytime

### Support
- Documentation: [docs.hetzner.com](https://docs.hetzner.com)
- Community: [community.hetzner.com](https://community.hetzner.com)

---

## Next Step

Once connected as `ubuntu`, run the ACFS doctor:

```bash
acfs doctor
```

---

*This guide is text-only on purpose: provider consoles change often and screenshots go stale
silently. If a button label differs from the one named above, look for the closest equivalent;
the server size, Ubuntu 26.04 LTS image, and SSH key choices are what matter.*
