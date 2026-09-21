"use client";

import { Globe, Key, Lock, Shield, ShieldCheck, Zap } from "lucide-react";
import {
  CodeBlock,
  Divider,
  FeatureCard,
  FeatureGrid,
  GoalBanner,
  Highlight,
  Paragraph,
  Section,
  TipBox,
} from "./lesson-components";

export function TailscaleLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Secure your VPS with Tailscale mesh VPN and SSH hardening — access your development server
        from anywhere without exposing ports to the internet.
      </GoalBanner>

      {/* Why Tailscale? */}
      <Section title="Why Tailscale?" icon={<Shield className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          Your VPS has a <Highlight>public IP</Highlight> that bots scan constantly. Automated
          scripts probe SSH ports, try default credentials, and exploit known vulnerabilities around
          the clock.
        </Paragraph>
        <Paragraph>
          <Highlight>Tailscale</Highlight> creates a private mesh network (WireGuard-based) with
          zero config. No open ports, no port forwarding, no firewall rules to manage.
        </Paragraph>

        <div className="mt-6">
          <FeatureGrid>
            <FeatureCard
              icon={<Shield className="h-5 w-5" />}
              title="Zero Config VPN"
              description="WireGuard under the hood, automatic key exchange"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Globe className="h-5 w-5" />}
              title="MagicDNS"
              description="Access machines by name, not IP"
              gradient="from-sky-500/20 to-blue-500/20"
            />
            <FeatureCard
              icon={<Lock className="h-5 w-5" />}
              title="SSH over Tailscale"
              description="Encrypted tunnel, no exposed SSH port"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<ShieldCheck className="h-5 w-5" />}
              title="ACLs"
              description="Fine-grained access control per device"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* Quick Setup */}
      <Section title="Quick Setup" icon={<Zap className="h-5 w-5" />} delay={0.15}>
        <Paragraph>Install and connect in 2 commands:</Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Install Tailscale (ACFS does this automatically)
curl -fsSL https://tailscale.com/install.sh | sh

# Authenticate and join your tailnet
sudo tailscale up

# Check your Tailscale IP
tailscale ip -4
# → 100.x.y.z (your private Tailscale IP)

# See all devices on your tailnet
tailscale status
# → Shows all connected machines with their Tailscale IPs

# Enable MagicDNS (in Tailscale admin console)
# Then access your VPS by name:
ssh ubuntu@my-vps    # Instead of ssh ubuntu@203.0.113.42`}
            language="bash"
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            After Tailscale is running, you can SSH using the Tailscale IP (100.x.y.z) instead of
            the public IP. This means SSH traffic never touches the public internet.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* SSH Hardening */}
      <Section title="SSH Hardening" icon={<Lock className="h-5 w-5" />} delay={0.2}>
        <Paragraph>Once Tailscale is set up, lock down the public SSH port:</Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Step 1: Verify Tailscale SSH works
ssh ubuntu@100.x.y.z    # Use your Tailscale IP

# Step 2: Configure SSH keepalive (prevents disconnects)
# /etc/ssh/sshd_config
ClientAliveInterval 60
ClientAliveCountMax 3
# → Server pings client every 60s, disconnects after 3 missed

# Step 3: Disable password authentication
# /etc/ssh/sshd_config
PasswordAuthentication no
ChallengeResponseAuthentication no

# Step 4: Restrict SSH to Tailscale interface only
# /etc/ssh/sshd_config
ListenAddress 100.x.y.z    # Only listen on Tailscale IP
# → Public IP SSH is now closed!

# Step 5: Restart SSH (CAREFUL — test first!)
sudo systemctl restart sshd

# Step 6: Verify from another terminal
ssh ubuntu@100.x.y.z    # Should work
ssh ubuntu@public-ip     # Should be refused`}
            language="bash"
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="warning">
            ALWAYS test SSH access over Tailscale in a separate terminal BEFORE restricting SSH to
            Tailscale-only. If Tailscale goes down and SSH is restricted, you could lock yourself
            out.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Tailscale SSH (No Keys Needed) */}
      <Section
        title="Tailscale SSH (No Keys Needed)"
        icon={<Key className="h-5 w-5" />}
        delay={0.25}
      >
        <Paragraph>
          Tailscale can handle SSH authentication itself — no SSH keys to manage:
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Enable Tailscale SSH on your VPS
sudo tailscale up --ssh

# Now connect from any device on your tailnet:
ssh ubuntu@my-vps
# → Authenticated via Tailscale identity, no SSH key needed!

# This works because:
# 1. Tailscale verifies your identity (OAuth/SSO)
# 2. Creates ephemeral SSH certificates
# 3. No permanent SSH keys to rotate or leak

# Check Tailscale SSH status
tailscale ssh-status

# ACL control (in admin console):
# "ssh": [{
#   "action": "accept",
#   "src": ["group:devs"],
#   "dst": ["tag:servers"],
#   "users": ["ubuntu"]
# }]`}
            language="bash"
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            Tailscale SSH means you never need to manage ~/.ssh/authorized_keys again. Add a new
            team member? They join the tailnet and get SSH access automatically based on ACLs.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Multi-VPS Networking */}
      <Section title="Multi-VPS Networking" icon={<Globe className="h-5 w-5" />} delay={0.3}>
        <Paragraph>Connect multiple VPS instances into a private network:</Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Your tailnet connects all machines:
# Laptop → 100.100.1.1
# VPS-1  → 100.100.1.2  (coding server)
# VPS-2  → 100.100.1.3  (build worker / RCH)
# VPS-3  → 100.100.1.4  (database server)

# All machines can reach each other directly
# No port forwarding, no NAT traversal needed

# RCH workers communicate over Tailscale
rch workers probe --all
# → Workers reachable at 100.x.y.z addresses

# PostgreSQL over Tailscale (no public exposure)
psql -h 100.100.1.4 -U postgres
# → Database only accessible on tailnet

# Forward a port through Tailscale
# On VPS: Next.js dev server on port 3000
# On laptop: access via http://100.100.1.2:3000
# → No ngrok, no port forwarding needed`}
            language="bash"
            showLineNumbers
          />
        </div>
      </Section>

      <Divider />

      {/* Firewall Lockdown */}
      <Section title="Firewall Lockdown" icon={<ShieldCheck className="h-5 w-5" />} delay={0.35}>
        <Paragraph>Final hardening: close everything except Tailscale.</Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Allow Tailscale traffic
sudo ufw allow in on tailscale0

# Allow SSH only from Tailscale
sudo ufw allow in on tailscale0 to any port 22

# Block public SSH
sudo ufw deny 22/tcp

# Enable firewall
sudo ufw enable
sudo ufw status
# → Only Tailscale interface accepts connections

# Verify your VPS is locked down
# From external machine:
nmap public-ip    # → All ports filtered/closed
# From tailnet:
ssh ubuntu@100.x.y.z    # → Works perfectly`}
            language="bash"
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            Tailscale + UFW = zero public attack surface. Your VPS is invisible to the internet but
            fully accessible to you and your agents over the encrypted mesh.
          </TipBox>
        </div>
      </Section>
    </div>
  );
}
