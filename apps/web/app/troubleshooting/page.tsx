"use client";

import Link from "next/link";
import { useState, useMemo } from "react";
import {
  AlertTriangle,
  ArrowLeft,
  ChevronDown,
  Lightbulb,
  Search,
  Terminal,
  Wifi,
  Key,
  HardDrive,
  RefreshCw,
  ShieldAlert,
  Clock,
} from "lucide-react";
import { Card } from "@/components/ui/card";
import { CommandCard } from "@/components/command-card";
import { buildRootKeyRepairCommand, buildUserKeyRepairCommand } from "@/lib/commandBuilder";

type TroubleshootingCategory = "all" | "ssh" | "installation" | "agents" | "network";
type CommandRunLocation = "vps" | "local";

interface TroubleshootingIssue {
  id: string;
  title: string;
  category: Exclude<TroubleshootingCategory, "all">;
  symptoms: string[];
  causes: string[];
  solutions: Array<{
    title: string;
    steps: string[];
    command?: string;
    runLocation?: CommandRunLocation;
  }>;
  prevention?: string;
  searchable: string;
}

const CATEGORY_META: Record<Exclude<TroubleshootingCategory, "all">, { label: string; icon: React.ReactNode; color: string }> = {
  ssh: { label: "SSH & Connection", icon: <Key className="h-4 w-4" />, color: "oklch(0.75 0.18 195)" },
  installation: { label: "Installation", icon: <HardDrive className="h-4 w-4" />, color: "oklch(0.78 0.16 75)" },
  agents: { label: "AI Agents", icon: <Terminal className="h-4 w-4" />, color: "oklch(0.7 0.2 330)" },
  network: { label: "Network", icon: <Wifi className="h-4 w-4" />, color: "oklch(0.72 0.19 145)" },
};

const DEFAULT_TROUBLESHOOTING_USER = "ubuntu";
const TROUBLESHOOTING_HOST_PLACEHOLDER = "YOUR_VPS_IP";
const userKeyRepairCommand = buildUserKeyRepairCommand(
  DEFAULT_TROUBLESHOOTING_USER,
  TROUBLESHOOTING_HOST_PLACEHOLDER,
);
const rootKeyRepairCommand = buildRootKeyRepairCommand(
  DEFAULT_TROUBLESHOOTING_USER,
  TROUBLESHOOTING_HOST_PLACEHOLDER,
);

const ISSUES: Omit<TroubleshootingIssue, "searchable">[] = [
  {
    id: "ssh-connection-refused",
    title: "SSH Connection Refused",
    category: "ssh",
    symptoms: [
      "Error: Connection refused",
      "ssh: connect to host ... port 22: Connection refused",
    ],
    causes: [
      "VPS is still starting up (not fully booted)",
      "SSH service not running on the VPS",
      "Firewall blocking port 22",
      "Wrong IP address",
    ],
    solutions: [
      {
        title: "Wait for VPS to fully start",
        steps: [
          "New VPS instances can take 2-5 minutes to fully boot",
          "Check your VPS provider's dashboard to confirm status is 'Running'",
          "Wait another minute after the dashboard shows 'Running'",
        ],
      },
      {
        title: "Verify the IP address",
        steps: [
          "Double-check the IP in your VPS provider's dashboard",
          "Make sure you're not mixing up IPs from multiple VPS instances",
        ],
      },
      {
        title: "Check if port 22 is open",
        steps: [
          "Some providers require you to enable SSH in security settings",
          "Look for 'Security Groups' or 'Firewall Rules' in your provider's dashboard",
        ],
      },
    ],
    prevention: "Always wait for the VPS status to show 'Running' before attempting to connect.",
  },
  {
    id: "ssh-timeout",
    title: "SSH Connection Times Out",
    category: "ssh",
    symptoms: [
      "Connection timed out",
      "SSH hangs without any response",
      "Operation timed out",
    ],
    causes: [
      "Wrong IP address",
      "Firewall blocking your IP",
      "Network issues between you and the VPS",
      "VPS is in a region with poor connectivity to you",
    ],
    solutions: [
      {
        title: "Verify connectivity",
        steps: [
          "Try pinging the IP address to check basic connectivity",
          "If ping works but SSH doesn't, it's likely a firewall issue",
        ],
        command: "ping YOUR_VPS_IP",
      },
      {
        title: "Check your local network",
        steps: [
          "Try from a different network (e.g., mobile hotspot)",
          "Disable VPN if you're using one",
          "Check if your ISP or corporate firewall blocks port 22",
        ],
      },
    ],
    prevention: "Choose a VPS region geographically close to you for better connectivity.",
  },
  {
    id: "ssh-permission-denied",
    title: "Permission Denied (publickey)",
    category: "ssh",
    symptoms: [
      "Permission denied (publickey)",
      "No more authentication methods to try",
      "Permission denied (publickey,keyboard-interactive)",
    ],
    causes: [
      "The installer did not finish adding the ACFS key to the configured SSH user",
      "Using root for a post-install key-based login instead of the configured SSH user",
      "SSH key file has wrong permissions",
      "Using wrong SSH key file",
    ],
    solutions: [
      {
        title: "Verify you're using the right username",
        steps: [
          "For post-install key logins, use ubuntu by default, not root",
          "If you configured a different SSH user, use that username instead",
          "For the first password login before installing, follow the wizard's root SSH step instead",
        ],
        command: "ssh -i ~/.ssh/acfs_ed25519 ubuntu@YOUR_VPS_IP",
      },
      {
        title: "Check SSH key permissions",
        steps: [
          "SSH keys must have restricted permissions (600 or 400)",
          "Run the chmod command to fix permissions",
        ],
        command: "chmod 600 ~/.ssh/acfs_ed25519",
      },
      {
        title: "Use password authentication first",
        steps: [
          "If you are still before the installer step, connect as root with the VPS password first",
          "If root login is disabled, connect as ubuntu and run sudo -i before continuing",
          "If sudo -i asks for a password, use the ubuntu Linux account password; if you only have the VPS root password, use the provider console or root SSH path instead",
          "Then run the installer so ACFS can set up key-based login for your normal SSH user",
        ],
      },
      {
        title: "Copy the ACFS key through ubuntu first",
        steps: [
          "If the installer finished but warned that no root SSH key was available, use the follow-up command printed in the installer summary",
          "This local command uses the ubuntu account and does not ask for the VPS root password",
          "This default troubleshooting command targets ubuntu; if you chose a different SSH user, use the personalized command from the installer summary or wizard handoff runbook",
        ],
        command: userKeyRepairCommand,
        runLocation: "local",
      },
      {
        title: "Use the root fallback if ubuntu still cannot connect",
        steps: [
          "Use this when the ubuntu repair command cannot connect or asks for a password you do not know",
          "This local command asks for the VPS root password once, then installs your ACFS public key for ubuntu",
          "This default troubleshooting command targets ubuntu; if you chose a different SSH user, use the personalized root-fallback command from the installer summary or wizard handoff runbook",
          "After it completes, retry the key-based SSH command for ubuntu or your configured SSH user",
        ],
        command: rootKeyRepairCommand,
        runLocation: "local",
      },
    ],
    prevention: "Use password authentication for the first root login, then follow the installer summary before switching to key-based SSH.",
  },
  {
    id: "session-disconnected",
    title: "SSH Session Disconnected",
    category: "ssh",
    symptoms: [
      "Connection reset by peer",
      "Broken pipe",
      "Session terminates unexpectedly",
    ],
    causes: [
      "Network instability",
      "Idle timeout (no activity)",
      "VPS ran out of memory",
    ],
    solutions: [
      {
        title: "Use tmux/ntm to persist sessions",
        steps: [
          "Always work inside a tmux session using ntm",
          "Even if disconnected, your work continues",
          "Just reconnect and reattach to your session",
        ],
        command: "ntm new myproject",
      },
      {
        title: "Configure SSH keep-alive",
        steps: [
          "Add ServerAliveInterval to your SSH config",
          "This sends periodic keep-alive packets",
        ],
      },
    ],
    prevention: "Always work inside tmux sessions. Use 'ntm new projectname' before starting work.",
  },
  {
    id: "install-curl-fails",
    title: "Installer Download Fails",
    category: "installation",
    symptoms: [
      "curl: (6) Could not resolve host",
      "curl: (7) Failed to connect",
      "404 Not Found when downloading installer",
    ],
    causes: [
      "DNS resolution issues on VPS",
      "GitHub is temporarily unreachable",
      "Network configuration problem",
    ],
    solutions: [
      {
        title: "Check DNS resolution",
        steps: [
          "Test if DNS is working",
          "If it fails, you may need to configure DNS manually",
        ],
        command: "ping -c 3 github.com",
      },
      {
        title: "Wait and retry",
        steps: [
          "GitHub occasionally has brief outages",
          "Wait a few minutes and try again",
        ],
      },
    ],
  },
  {
    id: "install-permission-denied",
    title: "Installation Permission Denied",
    category: "installation",
    symptoms: [
      "Permission denied during installation",
      "Cannot write to /home/ubuntu",
      "sudo: command not found",
    ],
    causes: [
      "Installer was run from a non-root shell",
      "Incorrect sudo configuration",
      "Filesystem permissions issue",
    ],
    solutions: [
      {
        title: "Verify you're in a root shell",
        steps: [
          "Check your current user",
          "For the first install, the prompt should show root@...#",
          "If it shows ubuntu@...$, run sudo -i before continuing",
          "If sudo -i asks for a password, use the ubuntu Linux account password; if you only have the VPS root password, use the provider console or root SSH path instead",
        ],
        command: "whoami",
        runLocation: "vps",
      },
      {
        title: "Re-run installer from root",
        steps: [
          "Run the ACFS install command only after you're in the root shell",
          "After the installer completes, reconnect as the configured SSH user (ubuntu by default) for daily work",
        ],
      },
    ],
  },
  {
    id: "install-disk-full",
    title: "Disk Space Exhausted",
    category: "installation",
    symptoms: [
      "No space left on device",
      "Cannot allocate memory",
      "Installation stops partway through",
    ],
    causes: [
      "VPS disk is too small",
      "Previous installation left junk files",
      "Log files consuming space",
    ],
    solutions: [
      {
        title: "Check available disk space",
        steps: [
          "View disk usage",
          "You need at least 10GB free for ACFS",
        ],
        command: "df -h",
      },
      {
        title: "Clean up if needed",
        steps: [
          "Clear apt cache",
          "Remove old log files",
        ],
        command: "sudo apt clean && sudo journalctl --vacuum-time=1d",
      },
    ],
    prevention: "Use a VPS with at least 40GB disk for comfortable development.",
  },
  {
    id: "claude-auth-fail",
    title: "Claude Code Authentication Fails",
    category: "agents",
    symptoms: [
      "Authentication failed",
      "Invalid API key",
      "Unable to verify subscription",
    ],
    causes: [
      "No active Claude subscription",
      "Authentication URL expired",
      "Browser blocking the auth redirect",
    ],
    solutions: [
      {
        title: "Complete authentication flow",
        steps: [
          "Run 'claude' in terminal",
          "Copy the URL displayed",
          "Open in your laptop's browser (not on VPS)",
          "Log in with your Anthropic account",
          "Return to terminal after success message",
        ],
        command: "claude",
      },
      {
        title: "Check your subscription",
        steps: [
          "Verify you have an active Claude subscription",
          "Visit console.anthropic.com to check status",
        ],
      },
    ],
  },
  {
    id: "agent-rate-limited",
    title: "AI Agent Rate Limited",
    category: "agents",
    symptoms: [
      "Rate limit exceeded",
      "Too many requests",
      "429 error",
    ],
    causes: [
      "Too many concurrent requests",
      "Hitting daily/monthly limits",
      "Multiple agents running simultaneously",
    ],
    solutions: [
      {
        title: "Wait and retry",
        steps: [
          "Rate limits usually reset within minutes",
          "Check your subscription tier's limits",
        ],
      },
      {
        title: "Reduce concurrent usage",
        steps: [
          "Don't run multiple AI sessions simultaneously",
          "Close unused agent sessions",
        ],
      },
    ],
    prevention: "Monitor your API usage in each provider's dashboard.",
  },
  {
    id: "p10k-wizard-stuck",
    title: "Powerlevel10k Wizard Appears",
    category: "installation",
    symptoms: [
      "Colorful terminal wizard appears on first login",
      "Prompts about font configuration",
      "Terminal looks different after installation",
    ],
    causes: [
      "Normal behavior - P10k configuration wizard runs once",
    ],
    solutions: [
      {
        title: "Skip or configure",
        steps: [
          "Press 'q' to quit and use ACFS defaults",
          "Or follow the prompts to customize your terminal appearance",
          "Either option is fine - ACFS already set sensible defaults",
        ],
      },
    ],
    prevention: "This is expected on first login. Just press 'q' to skip if unsure.",
  },
  {
    id: "ssh-host-key-changed",
    title: "Host Key Verification Failed",
    category: "ssh",
    symptoms: [
      "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!",
      "Host key verification failed",
      "Offending key in known_hosts",
    ],
    causes: [
      "You recreated your VPS but kept the same IP address",
      "The VPS was reinstalled with a new OS",
      "You're connecting to a different server with the same IP",
    ],
    solutions: [
      {
        title: "Remove the old host key (Mac/Linux)",
        steps: [
          "If you just recreated your VPS, this is expected",
          "Remove the old key and connect again",
          "You'll be prompted to accept the new key",
        ],
        command: "ssh-keygen -R YOUR_VPS_IP",
      },
      {
        title: "Remove the old host key (Windows)",
        steps: [
          "Open the known_hosts file in Notepad",
          "Delete the line containing your VPS IP",
          "Save and try connecting again",
        ],
        command: "notepad %USERPROFILE%\\.ssh\\known_hosts",
      },
    ],
    prevention: "This warning is a security feature. Only remove old keys if you know why the key changed (e.g., VPS reinstall).",
  },
  {
    id: "ssh-too-many-auth",
    title: "Too Many Authentication Failures",
    category: "ssh",
    symptoms: [
      "Too many authentication failures",
      "Received disconnect from host: Too many authentication failures",
      "Connection closed by remote host",
    ],
    causes: [
      "You have multiple SSH keys and the client tries them all",
      "Too many failed login attempts",
      "SSH agent has too many keys loaded",
    ],
    solutions: [
      {
        title: "Specify the exact key to use",
        steps: [
          "Tell SSH to only use your specific key file",
          "The IdentitiesOnly option prevents trying other keys",
        ],
        command: "ssh -i ~/.ssh/acfs_ed25519 -o IdentitiesOnly=yes ubuntu@YOUR_VPS_IP",
      },
      {
        title: "Clear SSH agent keys",
        steps: [
          "If you have many keys loaded in your SSH agent",
          "Clear them all and add only the one you need",
        ],
        command: "ssh-add -D && ssh-add ~/.ssh/acfs_ed25519",
      },
    ],
    prevention: "Use an SSH config file to specify which key to use for each server.",
  },
  {
    id: "ssh-slow-connection",
    title: "SSH Connection is Slow",
    category: "ssh",
    symptoms: [
      "Connection takes 30+ seconds",
      "Hangs after 'Connecting to...'",
      "Delays after password/key accepted",
    ],
    causes: [
      "DNS reverse lookup on the server",
      "GSSAPI authentication trying to connect to Kerberos",
      "Slow network route between you and VPS",
    ],
    solutions: [
      {
        title: "Disable GSSAPI authentication (quick fix)",
        steps: [
          "Add this option to skip Kerberos authentication",
          "This often fixes slow connections immediately",
        ],
        command: "ssh -o GSSAPIAuthentication=no ubuntu@YOUR_VPS_IP",
      },
      {
        title: "Make it permanent in SSH config",
        steps: [
          "Add to your ~/.ssh/config file:",
          "Host *",
          "  GSSAPIAuthentication no",
          "  ServerAliveInterval 60",
        ],
      },
    ],
    prevention: "Configure SSH options in ~/.ssh/config for persistent settings.",
  },
  {
    id: "vps-provider-verification",
    title: "VPS Provider Account Verification Pending",
    category: "network",
    symptoms: [
      "Cannot log into VPS provider dashboard",
      "Account pending verification",
      "Payment not processed",
    ],
    causes: [
      "New accounts often require identity verification",
      "Credit card verification still processing",
      "Email not verified",
    ],
    solutions: [
      {
        title: "Complete email verification",
        steps: [
          "Check your email inbox and spam folder",
          "Click the verification link from the provider",
          "Some providers require you to reply to a verification email",
        ],
      },
      {
        title: "Wait for payment processing",
        steps: [
          "New credit cards can take up to 24 hours to verify",
          "Prepaid cards may not be accepted",
          "Contact provider support if payment is stuck",
        ],
      },
      {
        title: "Check for identity verification request",
        steps: [
          "Some providers (especially Contabo) require ID verification",
          "Check your email for requests for additional documents",
          "This is more common for new accounts with large orders",
        ],
      },
    ],
    prevention: "Use a verified payment method and respond promptly to verification emails.",
  },
  {
    id: "installer-slow-network-cache",
    title: "Installer Downloads Timing Out or Slow Network",
    category: "installation",
    symptoms: [
      "curl errors or timeout during installer execution",
      "Verified installer script downloads hanging or timing out",
      "Flaky VPS connection repeatedly interrupting installation",
    ],
    causes: [
      "VPS network route has low bandwidth or high latency to upstream CDNs",
      "Transient network drops interrupting live tool script downloads",
    ],
    solutions: [
      {
        title: "Re-run the installer (idempotent resume)",
        steps: [
          "The installer is checkpointed and idempotent",
          "Simply re-run the one-liner command; it will resume from the last completed phase",
        ],
        command: "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh | bash -s -- --yes --mode vibe",
        runLocation: "vps",
      },
      {
        title: "Build and transfer a verified installer cache",
        steps: [
          "Build the verified installer cache on a high-speed connected machine",
          "Transfer the cache directory to your VPS using scp",
          "Run the installer pointing to the local verified installer cache directory",
        ],
        command: "acfs installer-cache build --output /tmp/acfs-cache && scp -r /tmp/acfs-cache/acfs-installer-cache root@YOUR_VPS_IP:/tmp/acfs-installer-cache",
        runLocation: "local",
      },
      {
        title: "Run installer with cache flag on VPS",
        steps: [
          "Run install.sh with --verified-installer-cache flag pointing to the transferred directory",
          "Note: VPS still requires basic internet access for APT packages and Cargo crates",
        ],
        command: "curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh | bash -s -- --verified-installer-cache /tmp/acfs-installer-cache --yes --mode vibe",
        runLocation: "vps",
      },
    ],
    prevention: "Pre-building the verified installer cache avoids live entrypoint downloads during VPS installation.",
  },
];

// Build searchable index
const ISSUES_WITH_SEARCH: TroubleshootingIssue[] = ISSUES.map((issue) => ({
  ...issue,
  searchable: [
    issue.title,
    ...issue.symptoms,
    ...issue.causes,
    ...issue.solutions.flatMap((s) => [s.title, ...s.steps, s.command ?? ""]),
  ]
    .join(" ")
    .toLowerCase(),
}));

function IssueCard({ issue, isOpen, onToggle }: { issue: TroubleshootingIssue; isOpen: boolean; onToggle: () => void }) {
  const categoryMeta = CATEGORY_META[issue.category];

  return (
    <Card
      id={issue.id}
      className="border-border/50 bg-card/60 overflow-hidden scroll-mt-24"
    >
      <button
        type="button"
        onClick={onToggle}
        className="w-full flex items-start justify-between gap-4 p-5 text-left transition-colors hover:bg-muted/10"
        aria-expanded={isOpen}
      >
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2 mb-2">
            <span
              className="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs"
              style={{
                borderColor: `${categoryMeta.color}40`,
                backgroundColor: `${categoryMeta.color}10`,
                color: categoryMeta.color,
              }}
            >
              {categoryMeta.icon}
              {categoryMeta.label}
            </span>
          </div>
          <h2 className="text-lg font-semibold text-foreground">{issue.title}</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            {issue.symptoms[0]}
          </p>
        </div>
        <ChevronDown
          className={`mt-1 h-5 w-5 shrink-0 text-muted-foreground transition-transform ${isOpen ? "rotate-180" : ""}`}
        />
      </button>

      {isOpen && (
        <div className="border-t border-border/40 p-5 space-y-6">
          {/* Symptoms */}
          <div>
            <h3 className="text-xs font-bold uppercase tracking-wider text-muted-foreground mb-3 flex items-center gap-2">
              <AlertTriangle className="h-4 w-4" />
              Symptoms
            </h3>
            <ul className="space-y-1.5">
              {issue.symptoms.map((symptom, i) => (
                <li key={i} className="text-sm text-foreground flex items-start gap-2">
                  <span className="text-red-400 mt-0.5">•</span>
                  <code className="font-mono text-xs bg-muted/50 px-1.5 py-0.5 rounded">
                    {symptom}
                  </code>
                </li>
              ))}
            </ul>
          </div>

          {/* Causes */}
          <div>
            <h3 className="text-xs font-bold uppercase tracking-wider text-muted-foreground mb-3 flex items-center gap-2">
              <ShieldAlert className="h-4 w-4" />
              Possible Causes
            </h3>
            <ul className="space-y-1.5">
              {issue.causes.map((cause, i) => (
                <li key={i} className="text-sm text-muted-foreground flex items-start gap-2">
                  <span className="text-amber-400 mt-0.5">•</span>
                  {cause}
                </li>
              ))}
            </ul>
          </div>

          {/* Solutions */}
          <div>
            <h3 className="text-xs font-bold uppercase tracking-wider text-muted-foreground mb-3 flex items-center gap-2">
              <Lightbulb className="h-4 w-4" />
              Solutions
            </h3>
            <div className="space-y-4">
              {issue.solutions.map((solution, i) => (
                <div
                  key={i}
                  className="rounded-xl border border-emerald-500/20 bg-emerald-500/5 p-4"
                >
                  <h4 className="font-medium text-foreground mb-2 flex items-center gap-2">
                    <span className="flex h-5 w-5 items-center justify-center rounded-full bg-emerald-500 text-xs text-white font-bold">
                      {i + 1}
                    </span>
                    {solution.title}
                  </h4>
                  <ul className="space-y-1 mb-3">
                    {solution.steps.map((step, j) => (
                      <li key={j} className="text-sm text-muted-foreground pl-7">
                        {step}
                      </li>
                    ))}
                  </ul>
                  {solution.command && (
                    <div className="pl-7">
                      <CommandCard command={solution.command} runLocation={solution.runLocation} />
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>

          {/* Prevention */}
          {issue.prevention && (
            <div className="rounded-xl border border-primary/20 bg-primary/5 p-4">
              <h3 className="text-xs font-bold uppercase tracking-wider text-primary mb-2 flex items-center gap-2">
                <Clock className="h-4 w-4" />
                Prevention
              </h3>
              <p className="text-sm text-foreground">{issue.prevention}</p>
            </div>
          )}
        </div>
      )}
    </Card>
  );
}

export default function TroubleshootingPage() {
  const [searchQuery, setSearchQuery] = useState("");
  const [category, setCategory] = useState<TroubleshootingCategory>("all");
  const [openIssueId, setOpenIssueId] = useState<string | null>(null);

  const normalizedQuery = searchQuery.trim().toLowerCase();

  const filteredIssues = useMemo(() => {
    return ISSUES_WITH_SEARCH.filter((issue) => {
      if (category !== "all" && issue.category !== category) {
        return false;
      }
      if (!normalizedQuery) return true;
      return issue.searchable.includes(normalizedQuery);
    });
  }, [category, normalizedQuery]);

  return (
    <div role="main" className="relative min-h-screen bg-background">
      {/* Background effects */}
      <div className="pointer-events-none fixed inset-0 bg-gradient-cosmic opacity-50" />
      <div className="pointer-events-none fixed inset-0 bg-grid-pattern opacity-20" />

      <div className="relative mx-auto max-w-4xl px-6 py-8 md:px-12 md:py-12">
        {/* Header */}
        <div className="mb-8 flex items-center justify-between">
          <Link
            href="/"
            className="flex items-center gap-2 text-muted-foreground transition-colors hover:text-foreground"
          >
            <ArrowLeft className="h-4 w-4" />
            <span className="text-sm">Home</span>
          </Link>
          <Link
            href="/wizard/os-selection"
            className="flex items-center gap-2 text-muted-foreground transition-colors hover:text-foreground"
          >
            <Terminal className="h-4 w-4" />
            <span className="text-sm">Setup Wizard</span>
          </Link>
        </div>

        {/* Hero */}
        <div className="mb-10 text-center">
          <div className="mb-4 flex justify-center">
            <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-amber-500/10 shadow-lg shadow-amber-500/20">
              <RefreshCw className="h-8 w-8 text-amber-500" />
            </div>
          </div>
          <h1 className="mb-3 text-3xl font-bold tracking-tight md:text-4xl">
            Troubleshooting
          </h1>
          <p className="mx-auto max-w-xl text-lg text-muted-foreground">
            Common issues and their solutions. Search for error messages or browse by category.
          </p>
        </div>

        {/* Search */}
        <div className="relative mb-6">
          <Search className="absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search issues (e.g., 'connection refused', 'permission denied')..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            aria-label="Search troubleshooting issues"
            className="w-full rounded-xl border border-border/50 bg-card/50 py-3 pl-12 pr-4 text-foreground placeholder:text-muted-foreground focus:border-primary/40 focus:outline-none focus:ring-2 focus:ring-primary/20"
          />
        </div>

        {/* Category filter */}
        <div className="mb-6 flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => setCategory("all")}
            className={`rounded-full border px-3 py-1.5 text-sm transition-colors ${
              category === "all"
                ? "border-primary/40 bg-primary/10 text-primary"
                : "border-border/50 bg-card/40 text-muted-foreground hover:border-primary/30 hover:bg-primary/5"
            }`}
          >
            All
          </button>
          {(Object.keys(CATEGORY_META) as Array<Exclude<TroubleshootingCategory, "all">>).map((cat) => {
            const meta = CATEGORY_META[cat];
            return (
              <button
                key={cat}
                type="button"
                onClick={() => setCategory(cat)}
                className={`rounded-full border px-3 py-1.5 text-sm transition-colors inline-flex items-center gap-1.5 ${
                  category === cat
                    ? "border-primary/40 bg-primary/10 text-primary"
                    : "border-border/50 bg-card/40 text-muted-foreground hover:border-primary/30 hover:bg-primary/5"
                }`}
              >
                {meta.icon}
                {meta.label}
              </button>
            );
          })}
        </div>

        <p className="mb-8 text-sm text-muted-foreground">
          Showing{" "}
          <span className="font-mono text-foreground">{filteredIssues.length}</span>{" "}
          of{" "}
          <span className="font-mono text-foreground">{ISSUES_WITH_SEARCH.length}</span>{" "}
          issues.
        </p>

        {/* Issues */}
        <div className="space-y-4">
          {filteredIssues.length > 0 ? (
            filteredIssues.map((issue) => (
              <IssueCard
                key={issue.id}
                issue={issue}
                isOpen={openIssueId === issue.id}
                onToggle={() => setOpenIssueId(openIssueId === issue.id ? null : issue.id)}
              />
            ))
          ) : (
            <div className="py-12 text-center">
              <Search className="mx-auto mb-4 h-12 w-12 text-muted-foreground/50" />
              <p className="text-muted-foreground mb-4">
                No issues match your search.
              </p>
              <p className="text-sm text-muted-foreground">
                Try different keywords or{" "}
                <button
                  type="button"
                  onClick={() => { setSearchQuery(""); setCategory("all"); }}
                  className="text-primary hover:underline"
                >
                  clear all filters
                </button>
                .
              </p>
            </div>
          )}
        </div>

        {/* Help section */}
        <Card className="mt-12 border-primary/20 bg-primary/5 p-6">
          <h2 className="text-lg font-semibold mb-3">Still stuck?</h2>
          <div className="space-y-3 text-sm text-muted-foreground">
            <p>
              If you can&apos;t find your issue here, try these resources:
            </p>
            <ul className="space-y-2 pl-4">
              <li className="flex items-start gap-2">
                <span className="text-primary">•</span>
                <span>
                  Check the{" "}
                  <Link href="/glossary" className="text-primary hover:underline">
                    Glossary
                  </Link>{" "}
                  for unfamiliar terms
                </span>
              </li>
              <li className="flex items-start gap-2">
                <span className="text-primary">•</span>
                <span>
                  Visit the{" "}
                  <a
                    href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-primary hover:underline"
                  >
                    GitHub Issues
                  </a>{" "}
                  page for community help
                </span>
              </li>
              <li className="flex items-start gap-2">
                <span className="text-primary">•</span>
                <span>
                  Review the{" "}
                  <Link href="/learn" className="text-primary hover:underline">
                    Learning Hub
                  </Link>{" "}
                  for guided tutorials
                </span>
              </li>
            </ul>
          </div>
        </Card>
      </div>
    </div>
  );
}
