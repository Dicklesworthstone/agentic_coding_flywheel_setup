# OVHcloud VPS Setup Guide

Set up a VPS on OVHcloud for running ACFS and coding agents.

---

## Provider Overview

**OVHcloud** is a European hosting provider with global presence and competitive pricing.

| Aspect | Details |
|--------|---------|
| **Recommended Tier** | VPS-4 (24GB RAM, from ~$24/mo), the largest OVH VPS |
| **ACFS Target** | 48-64GB RAM; OVH's VPS range tops out below that, so pick Contabo for a full swarm |
| **Best For** | Small hosts only (about 4-6 standard agents on VPS-4) |
| **Signup** | [us.ovhcloud.com](https://us.ovhcloud.com/vps/) |

### Pros
- Very competitive pricing
- European data centers (GDPR compliance)
- Good network performance
- No hidden fees

### Cons
- Control panel can be complex
- Support response can be slow
- Some features require technical knowledge

---

## Step 1: Create an Account

1. Go to [ovhcloud.com](https://www.ovhcloud.com)
2. Click "Sign up" or "Create an account"
3. Complete identity verification

![OVH Step 1: Create account](screenshots/ovh-step1-create-account.png)

---

## Step 2: Navigate to VPS Section

1. Log into the OVH Control Panel
2. Click "Bare Metal Cloud" in the top menu
3. Select "VPS" from the sidebar

![OVH Step 2: Select VPS](screenshots/ovh-step2-select-vps.png)

---

## Step 3: Choose Your VPS Plan

| Plan | vCore | RAM | Storage | Price |
|------|-------|-----|---------|-------|
| **VPS-4** | 8 | 24GB | 200GB NVMe | from $23.37/mo (12-month term) |
| VPS-3 | 6 | 12GB | 100GB NVMe | from $12.32/mo (12-month term) |

**Recommended**: VPS-4, the largest VPS OVH sells. Both plans are below the 48GB ACFS
recommendation: VPS-4 suits about 4-6 standard agents, and VPS-3 only trying ACFS with
1-2 agents. Choose Contabo (Cloud VPS 12/16) for 48-64GB. "From" prices assume a 12-month
term; month-to-month costs more. These figures mirror `apps/web/lib/vpsProviders.ts`.

![OVH Step 3: Choose plan](screenshots/ovh-step3-choose-plan.png)

---

## Step 4: Select Operating System

1. Choose **Ubuntu 26.04 LTS**
2. Leave other options at defaults

![OVH Step 4: Select Ubuntu](screenshots/ovh-step4-select-os.png)

---

## Step 5: Choose Password Authentication

For the ACFS beginner flow, use password authentication for the first login and let the installer handle SSH keys.

1. In the order form, find the authentication or login method section
2. Choose **Password** authentication
3. Skip the SSH key section for now
4. Save the VPS root password or temporary provider password somewhere safe

ACFS creates the `ubuntu` user after the first password login, then either sets up SSH key access automatically or prints the exact follow-up command to run.

![OVH Step 5: Choose authentication](screenshots/ovh-step5-add-ssh-key.png)

---

## Step 6: Choose Data Center Location

Select a location closest to you:
- **US East** or **US West**: good defaults for users in North America
- **Canada**: good default for users in Canada
- **EU**: good default for users in Europe
- **Asia**: use only if it is close to you or your users

![OVH Step 6: Select location](screenshots/ovh-step6-select-location.png)

---

## Step 7: Complete the Order

1. Review your configuration
2. Accept terms of service
3. Complete payment

Your VPS will be provisioned within minutes.

![OVH Step 7: Complete order](screenshots/ovh-step7-complete-order.png)

---

## Step 8: Find Your IP Address

After provisioning:

1. Go to "Bare Metal Cloud" > "VPS"
2. Click on your new VPS
3. Copy the **IPv4 address**

![OVH Step 8: Find IP](screenshots/ovh-step8-find-ip.png)

---

## Step 9: Connect via SSH

Start with the root password login:

```bash
ssh root@YOUR_IP_ADDRESS
```

If OVH disables direct root login for your selected image and gives you an `ubuntu` admin account, connect as `ubuntu` and become root before installing. If `sudo -i` asks for a password, enter the `ubuntu` Linux account password. Do not enter your OVH account password or a different root password at the sudo prompt. If OVH only gave you a root password, use the provider console or root SSH path instead.

```bash
ssh ubuntu@YOUR_IP_ADDRESS
sudo -i
```

---

## OVH-Specific Notes

### Default User
Some OVH Ubuntu images default to `ubuntu` or disable direct root login. ACFS should still be run from a root shell, so use `sudo -i` before starting the installer when the first login lands on `ubuntu`. A sudo password prompt belongs to the `ubuntu` Linux account, not to your OVH website account.

### Firewall
OVH has a basic firewall in the control panel. For most setups, the default configuration works fine.

### Reboot After Updates
After running `apt upgrade`, reboot the VPS:
```bash
sudo reboot
```

### Support
- Knowledge Base: [help.ovhcloud.com](https://help.ovhcloud.com)
- Community Forum: [community.ovh.com](https://community.ovh.com)

---

## Next Step

Once connected as root, run the ACFS installer:

```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh | bash -s -- --yes --mode vibe
```

When the installer finishes, follow its reconnect command for the `ubuntu` user. If it prints an SSH-key follow-up warning, run the printed command from your local machine once, then reconnect with the ACFS SSH key.

---

*Screenshots are placeholders. Replace with actual screenshots from OVH control panel.*
