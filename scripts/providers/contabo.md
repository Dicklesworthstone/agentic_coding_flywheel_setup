# Contabo VPS Setup Guide

Set up a VPS on Contabo for running ACFS and coding agents.

---

## Provider Overview

**Contabo** is a German hosting provider known for exceptional value - high specs at low prices.

| Aspect | Details |
|--------|---------|
| **Recommended Tier** | Cloud VPS 16 (64GB RAM, ~$43/mo); Cloud VPS 12 (48GB RAM, ~$29/mo) on a budget |
| **ACFS Target** | 48-64GB RAM for a multi-agent swarm (32GB is a tight minimum) |
| **Best For** | Best value overall: the most RAM per dollar |
| **Signup** | [contabo.com](https://contabo.com/en-us/vps/) |

### Pros
- Incredible value (most RAM/storage for price)
- German engineering and data protection
- Simple control panel
- No hidden fees

### Cons
- Activation usually takes minutes but can take up to ~1 hour
- Support is email-only
- Fewer data center locations

---

## Step 1: Create an Account

1. Go to [contabo.com](https://contabo.com)
2. Click "Cloud VPS" in the menu
3. Select a plan and click "Configure"

---

## Step 2: Choose Your VPS Plan

Contabo offers exceptional specs for the price:

| Plan | vCPU | RAM | Storage | Price |
|------|------|-----|---------|-------|
| **Cloud VPS 16** | 16 | 64GB | 500GB SSD | ~$43/mo (EUR 37 list) |
| Cloud VPS 12 | 12 | 48GB | 400GB SSD | ~$29/mo (EUR 25 list) |

**Recommended**: Cloud VPS 16 for serious multi-agent work; Cloud VPS 12 is the budget option.

USD prices are approximate conversions of Contabo's EUR list price (24-month introductory rate, incl. VAT). Month-to-month terms and US datacenters can cost more; the checkout page shows the final price. These figures mirror `apps/web/lib/vpsProviders.ts`, the single source the wizard renders from.

---

## Step 3: Select Data Center Region

Choose a location closest to you:
- **US**: good default for users in North America
- **EU**: good default for users in Europe
- **Asia** or **AU**: use only if it is close to you or your users

---

## Step 4: Choose Operating System

1. Under "Image", select **Ubuntu 26.04 LTS**
2. Leave default storage type (SSD)

---

## Step 5: Set Root Password

Contabo requires a root password during setup.

1. Enter a strong password (you'll change this later)
2. Save this password temporarily

---

## Step 6: Skip Provider SSH Key Setup

For the ACFS beginner flow, use Contabo's root password login first and let the installer handle SSH keys.

1. Scroll through the "Add-ons" section
2. Leave the SSH key option empty unless you are intentionally reusing an existing server key
3. Keep the root password from Step 5; you need it for the first login

ACFS creates the `ubuntu` user after the first root-password login, then either sets up SSH key access automatically or prints the exact follow-up command to run.

---

## Step 7: Complete the Order

1. Review your configuration
2. Accept terms of service
3. Complete payment

**Note**: Contabo activation is not instant: usually minutes, occasionally up to about an hour.
You'll receive an email when your VPS is ready.

---

## Step 8: Find Your IP Address

When you receive the "VPS Ready" email:

1. Log into [my.contabo.com](https://my.contabo.com)
2. Go to "Your services" > "VPS"
3. Copy the **IP address**

---

## Step 9: First Login

Contabo uses `root` as the default user:

```bash
ssh root@YOUR_IP_ADDRESS
```

You'll be prompted to enter the root password from Step 5.

---

## Step 10: Run the ACFS Installer

Do not create the `ubuntu` user manually. Run ACFS from the initial `root` session:

```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh | bash -s -- --yes --mode vibe
```

ACFS creates the `ubuntu` user and enables passwordless sudo for that user in vibe mode. If you deliberately added a root SSH key in Contabo, ACFS copies that key into `/home/ubuntu/.ssh/authorized_keys`.

When the installer finishes, read its final summary before reconnecting. If there is no SSH-key follow-up warning, reconnect from your local machine:

```bash
exit
ssh -i ~/.ssh/acfs_ed25519 ubuntu@YOUR_IP_ADDRESS
```

If you followed the recommended password-first path and the installer does print an SSH-key follow-up warning, run this from your local machine. It asks for the Contabo root password once, then installs your ACFS public key for `ubuntu`:

```bash
cat ~/.ssh/acfs_ed25519.pub | ssh root@YOUR_IP_ADDRESS "read -r acfs_pubkey && test ! -L /home/ubuntu/.ssh && install -d -m 700 -o ubuntu -g ubuntu /home/ubuntu/.ssh && test ! -L /home/ubuntu/.ssh/authorized_keys && touch /home/ubuntu/.ssh/authorized_keys && { [ ! -s /home/ubuntu/.ssh/authorized_keys ] || tail -c 1 /home/ubuntu/.ssh/authorized_keys | od -An -t u1 | grep -qw 10 || printf '\n' >> /home/ubuntu/.ssh/authorized_keys; } && if ! grep -qxF \"\$acfs_pubkey\" /home/ubuntu/.ssh/authorized_keys; then printf '%s\n' \"\$acfs_pubkey\" >> /home/ubuntu/.ssh/authorized_keys; fi && chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys && chmod 600 /home/ubuntu/.ssh/authorized_keys"
```

---

## Contabo-Specific Notes

### Default User
Contabo uses `root` by default. ACFS creates and configures the `ubuntu` user during Step 10.

### Provisioning Time
Contabo activation is usually minutes but can take up to about an hour, slower than providers
that create servers instantly. Wait for the "VPS ready" email before trying to connect.

### Firewall
No firewall is enabled by default. Consider setting up UFW:
```bash
sudo ufw allow OpenSSH
sudo ufw enable
```

### Support
- Email: support@contabo.com
- Knowledge Base: [contabo.com/support](https://contabo.com/en/support/)

---

## Next Step

Once connected as `ubuntu`, run the ACFS doctor:

```bash
acfs doctor
```

---

*This guide is text-only on purpose: provider consoles change often and screenshots go stale
silently. If a button label differs from the one named above, look for the closest equivalent;
the plan, Ubuntu 26.04 LTS image, and root-password choices are what matter.*
