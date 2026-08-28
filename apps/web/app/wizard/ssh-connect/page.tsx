"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Terminal, ChevronDown, BookOpen } from "lucide-react";
import { Button } from "@/components/ui/button";
import { CommandCard } from "@/components/command-card";
import { AlertCard, OutputPreview } from "@/components/alert-card";
import { TwoComputersExplainer } from "@/components/connection-check";
import { formatSshHost, formatSshTarget } from "@/lib/commandBuilder";
import { cn } from "@/lib/utils";
import Link from "next/link";
import { markStepComplete, useWizardForwardNav } from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { useVPSIP, useUserOS } from "@/lib/userPreferences";
import { withCurrentSearch } from "@/lib/utils";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
  GuideCaution,
} from "@/components/simpler-guide";
import { Jargon } from "@/components/jargon";

interface TroubleshootingItem {
  error: string;
  causes: string[];
  solutions: string[];
}

const TROUBLESHOOTING: TroubleshootingItem[] = [
  {
    error: "Connection refused",
    causes: [
      "VPS is still starting up",
      "SSH service not running on the VPS",
      "Firewall blocking port 22",
    ],
    solutions: [
      "Wait 2-5 minutes for the VPS to fully boot",
      "Check your VPS provider's status page",
      "Use the VPS console in your provider's control panel to check",
    ],
  },
  {
    error: "Connection timed out",
    causes: [
      "Wrong IP address",
      "VPS is offline",
      "Network issue between you and the VPS",
    ],
    solutions: [
      "Double-check the IP address in your provider's control panel",
      "Try pinging the IP: ping YOUR_IP",
      "Check if your VPS is running in the control panel",
    ],
  },
  {
    error: "Permission denied",
    causes: [
      "Wrong password",
      "Password authentication might be disabled",
      "Trying wrong username",
    ],
    solutions: [
      "Double-check the password from your provider",
      "Some providers email the password - check your inbox",
      "Use root first; if your provider disables root login, connect as ubuntu and run sudo -i before continuing",
    ],
  },
  {
    error: "Host key verification failed",
    causes: [
      "You've connected to this IP before with a different VPS",
      "The server was reinstalled",
    ],
    solutions: [
      "Remove the old key: ssh-keygen -R YOUR_IP",
      "Then try connecting again",
    ],
  },
];

function TroubleshootingSection({
  item,
  isExpanded,
  onToggle,
}: {
  item: TroubleshootingItem;
  isExpanded: boolean;
  onToggle: () => void;
}) {
  return (
    <div className="rounded-lg border">
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={isExpanded}
        className="flex w-full items-center justify-between p-3 text-left hover:bg-muted/50"
      >
        <span className="font-medium text-destructive">{item.error}</span>
        <ChevronDown
          className={cn(
            "h-4 w-4 text-muted-foreground transition-transform",
            isExpanded && "rotate-180"
          )}
        />
      </button>
      {isExpanded && (
        <div className="space-y-3 border-t px-3 pb-3 pt-2 text-sm">
          <div>
            <p className="font-medium">Possible causes:</p>
            <ul className="mt-1 list-disc space-y-1 pl-5 text-muted-foreground">
              {item.causes.map((cause, i) => (
                <li key={i}>{cause}</li>
              ))}
            </ul>
          </div>
          <div>
            <p className="font-medium">Solutions:</p>
            <ul className="mt-1 list-disc space-y-1 pl-5 text-muted-foreground">
              {item.solutions.map((solution, i) => (
                <li key={i}>{solution}</li>
              ))}
            </ul>
          </div>
        </div>
      )}
    </div>
  );
}

export default function SSHConnectPage() {
  const router = useRouter();
  const [vpsIP, , vpsIPLoaded] = useVPSIP();
  const [os, , osLoaded] = useUserOS();
  const [expandedError, setExpandedError] = useState<string | null>(null);
  const [isNavigating, setIsNavigating] = useState(false);
  const ready = vpsIPLoaded && osLoaded;

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "ssh_connect",
    stepNumber: 6,
    stepTitle: "SSH Connect",
  });

  // Redirect if missing required data (after hydration)
  useEffect(() => {
    if (!ready) return;
    // Prerequisite redirects use replace() so Back does not land here again.
    if (vpsIP === null) {
      router.replace(withCurrentSearch("/wizard/create-vps"));
    } else if (os === null) {
      router.replace(withCurrentSearch("/wizard/os-selection"));
    }
  }, [ready, vpsIP, os, router]);

  const handleContinue = useCallback(() => {
    markComplete();
    markStepComplete(6);
    setIsNavigating(true);
    router.push(withCurrentSearch("/wizard/accounts"));
  }, [router, markComplete]);

  useWizardForwardNav({ onContinue: handleContinue, disabled: isNavigating, loading: isNavigating });

  if (!ready || !vpsIP || !os) {
    return (
      <div className="flex items-center justify-center py-12">
        <Terminal className="h-8 w-8 animate-pulse text-muted-foreground" />
      </div>
    );
  }

  // Password-first flow: connect as root with password
  const sshHost = formatSshHost(vpsIP);
  const rootTarget = formatSshTarget("root", vpsIP);
  const ubuntuTarget = formatSshTarget("ubuntu", vpsIP);
  const sshCommand = `ssh ${rootTarget}`;
  const sshCommandWindows = `ssh ${rootTarget}`;
  // Fallback if provider uses ubuntu user
  const sshCommandUbuntu = `ssh ${ubuntuTarget}`;
  const sshCommandUbuntuWindows = `ssh ${ubuntuTarget}`;
  const becomeRootCommand = "sudo -i";

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/20">
            <Terminal className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              <Jargon term="ssh" gradientHeading>SSH</Jargon> into your <Jargon term="vps" gradientHeading>VPS</Jargon>
            </h1>
            <p className="text-sm text-muted-foreground">
              ~1 min
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          Connect to your new <Jargon term="vps">VPS</Jargon> for the first time.
        </p>
      </div>

      {/* Two Computers Mental Model - CRITICAL for beginners */}
      <TwoComputersExplainer />

      {/* IP confirmation */}
      <AlertCard variant="info" icon={Terminal}>
        Connecting to:{" "}
        <code className="ml-1 rounded bg-primary/15 px-2 py-0.5 font-mono font-bold text-primary">{vpsIP}</code>
      </AlertCard>

      {/* CRITICAL: Password distinction warning */}
      <AlertCard variant="warning" title="Which password to use">
        <div className="space-y-2">
          <p>
            You&apos;ll need the <strong className="text-foreground">VPS root password</strong> — this is{" "}
            <strong className="text-foreground">NOT</strong> the same as your VPS provider account password!
          </p>
          <ul className="mt-2 list-disc space-y-1 pl-5 text-sm">
            <li>
              <span className="text-green">✓ Correct:</span>{" "}
              <strong>VPS root password</strong> — the password you set when creating this specific VPS,
              or the one your provider emailed you
            </li>
            <li>
              <span className="text-destructive">✗ Wrong:</span>{" "}
              Your OVH/Contabo <em>account</em> login password
            </li>
          </ul>
          <p className="text-xs text-muted-foreground mt-2">
            If you can&apos;t find it, check your email or your VPS provider&apos;s control panel for the VPS-specific password.
          </p>
        </div>
      </AlertCard>

      {/* Primary command */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">Run this command</h2>
        <CommandCard
          command={sshCommand}
          windowsCommand={sshCommandWindows}
          description="Connect as root with password"
          runLocation="local"
          showCheckbox
          persistKey="ssh-connect-root"
        />
      </div>

      {/* "Type yes" prompt explanation - show users what the scary message looks like */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">What you&apos;ll see first</h2>
        <p className="text-sm text-muted-foreground">
          The first time you connect, you&apos;ll see a scary-looking security message.
          <strong className="text-foreground"> This is completely normal!</strong> It just means SSH hasn&apos;t seen this server before.
        </p>
        <OutputPreview title="You'll see something like:">
          <div className="space-y-1">
            <p className="text-amber">The authenticity of host &apos;{sshHost} ({vpsIP})&apos; can&apos;t be established.</p>
            <p className="text-muted-foreground">ED25519 key fingerprint is SHA256:xYz123abc456def...</p>
            <p className="text-amber">Are you sure you want to continue connecting (yes/no/[fingerprint])?</p>
          </div>
          <p className="mt-3 text-xs text-muted-foreground">
            This looks alarming, but it&apos;s just SSH confirming you want to trust this new server.
          </p>
        </OutputPreview>
        <AlertCard variant="success" title="Type 'yes' and press Enter">
          This is safe! You&apos;re telling SSH to remember this server. Type the full word{" "}
          <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs text-foreground">yes</code> (not just &quot;y&quot;), then press Enter.
        </AlertCard>
      </div>

      {/* Password prompt */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">Then enter your password</h2>
        <p className="text-sm text-muted-foreground">
          After typing &quot;yes&quot;, you&apos;ll be asked for your password:
        </p>
        <OutputPreview title="You'll see:">
          <p className="text-muted-foreground">{rootTarget}&apos;s password: <span className="animate-pulse">_</span></p>
        </OutputPreview>
        <AlertCard variant="info" title="The password won't appear as you type">
          <p>
            When you type your password, <strong>nothing will show on screen</strong> — no dots, no asterisks, nothing.
            This is a security feature, not a bug! Just type your password and press Enter.
          </p>
        </AlertCard>
      </div>

      {/* Fallback to ubuntu */}
      <div className="space-y-3">
        <h3 className="font-semibold">
          If &quot;root&quot; is disabled, try ubuntu and become root:
        </h3>
        <p className="text-sm text-muted-foreground">
          Some providers disable root login. If you get &quot;Permission denied&quot; with
          root, try the ubuntu account, then open a root shell before continuing.
          If <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">sudo -i</code>{" "}
          asks for a password, enter the ubuntu Linux account password, not your provider
          website password or a different root password. If the provider only gave you a
          root password, use the provider console or root SSH path instead.
        </p>
        <CommandCard
          command={sshCommandUbuntu}
          windowsCommand={sshCommandUbuntuWindows}
          description="Connect as ubuntu user (fallback)"
          runLocation="local"
        />
        <CommandCard
          command={becomeRootCommand}
          description="Switch the ubuntu fallback session into a root shell"
          runLocation="vps"
        />
      </div>

      {/* Success indicator */}
      <OutputPreview title="You're connected when you see:">
        <p className="text-green">
          root@vps:~# <span className="animate-pulse">_</span>
        </p>
        <p className="mt-2 text-muted-foreground">
          You should see a prompt with your username and &quot;vps&quot; or
          the server hostname. The &quot;#&quot; means you&apos;re logged in as root.
          If you used the ubuntu fallback, run{" "}
          <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">{becomeRootCommand}</code>{" "}
          first; continue only after your prompt ends with &quot;#&quot;.
        </p>
      </OutputPreview>

      {/* Post-connection verification */}
      <div className="space-y-3">
        <h3 className="font-semibold">Verify you&apos;re on the VPS</h3>
        <p className="text-muted-foreground">
          Try this command to confirm you&apos;re controlling the VPS, not your laptop:
        </p>
        <CommandCard
          command="hostname"
          description="Show this computer's name"
          runLocation="vps"
        />
        <OutputPreview title="You should see something like:">
          <p className="text-green">vps-12345</p>
          <p className="mt-2 text-xs text-muted-foreground">
            (Your VPS hostname — not your laptop&apos;s name like &quot;MacBook-Pro&quot; or &quot;DESKTOP-ABC123&quot;)
          </p>
        </OutputPreview>
        <AlertCard variant="info">
          <strong>You&apos;re now remote-controlling the VPS!</strong> Everything you type happens on the VPS.
          If you type <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ls</code>, you see VPS files.
          If you install something, it installs on the VPS. Your laptop is just the remote control.
        </AlertCard>
      </div>

      {/* Troubleshooting */}
      <div className="space-y-3">
        <h2 className="font-semibold">Having trouble?</h2>
        <div className="space-y-2">
          {TROUBLESHOOTING.map((item) => (
            <TroubleshootingSection
              key={item.error}
              item={item}
              isExpanded={expandedError === item.error}
              onToggle={() =>
                setExpandedError((prev) =>
                  prev === item.error ? null : item.error
                )
              }
            />
          ))}
        </div>
      </div>

      {/* Beginner Guide */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="SSH (Secure Shell)">
            SSH is a way to securely connect to another computer over the internet.
            It&apos;s like making a phone call to your VPS. Once connected, everything
            you type appears on the VPS, not your local computer.
            <br /><br />
            When you &quot;SSH into&quot; a computer, you&apos;re essentially remote-controlling it
            through text commands.
          </GuideExplain>

          <GuideSection title="Step-by-Step Connection Guide">
            <div className="space-y-4">
              <GuideStep number={1} title="Open your terminal">
                Open your terminal app (Ghostty, WezTerm, Windows Terminal, or your Linux terminal emulator).
              </GuideStep>

              <GuideStep number={2} title="Copy the SSH command">
                Look at the gray command box above. Click the <strong>copy button</strong>
                on the right side (it looks like two overlapping squares).
              </GuideStep>

              <GuideStep number={3} title="Paste the command">
                Click inside your terminal window, then paste:
                <ul className="mt-2 list-disc space-y-1 pl-5">
                  <li><strong>Mac:</strong> <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">⌘</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">V</kbd></li>
                  <li><strong>Linux:</strong> <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Ctrl</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Shift</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">V</kbd></li>
                  <li><strong>Windows:</strong> Right-click inside the terminal, or <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Ctrl</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">V</kbd></li>
                </ul>
              </GuideStep>

              <GuideStep number={4} title="Press Enter">
                Press the <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd> key to run the command.
              </GuideStep>

              <GuideStep number={5} title="Say 'yes' to the security question">
                You&apos;ll see a scary-looking message about &quot;authenticity of host&quot;
                and a &quot;fingerprint&quot;. This is normal for first-time connections!
                <br /><br />
                Type <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">yes</kbd> (spelled out, not just &quot;y&quot;)
                and press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd>.
              </GuideStep>

              <GuideStep number={6} title="Enter your password">
                Now it will ask for your password. Type the password you set during VPS
                creation (or the one your provider emailed you).
                <br /><br />
                <strong>Important:</strong> The password won&apos;t show as you type—no dots
                or asterisks. Just type it and press Enter. This is normal security behavior!
              </GuideStep>

              <GuideStep number={7} title="You're connected!">
                If successful, you&apos;ll see a new prompt like:
                <code className="mt-2 block overflow-x-auto rounded bg-muted px-3 py-2 font-mono text-sm">
                  root@vps:~#
                </code>
                The &quot;root@vps&quot; part means you&apos;re now controlling the VPS!
                If you connected as ubuntu instead, run{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">{becomeRootCommand}</code>{" "}
                so your prompt changes to root before you continue.
                Everything you type from now on runs on the VPS, not your laptop.
              </GuideStep>
            </div>
          </GuideSection>

          <GuideSection title="Understanding What You See">
            <p className="mb-3">
              After connecting, your terminal looks different because you&apos;re now
              &quot;inside&quot; the VPS:
            </p>
            <ul className="space-y-2">
              <li>
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">root@</code>
                is your username on the VPS (you&apos;re the admin!)
              </li>
              <li>
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">vps</code>
                is the VPS hostname (might be different)
              </li>
              <li>
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">~</code>
                means you&apos;re in your &quot;home&quot; folder
              </li>
              <li>
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">#</code>
                means you&apos;re logged in as root (vs <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">$</code> for regular users)
              </li>
            </ul>
          </GuideSection>

          <GuideTip>
            To disconnect from the VPS and return to your local computer, type{" "}
            <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">exit</code>
            and press Enter. You can always reconnect using the same SSH command.
          </GuideTip>

          <GuideCaution>
            <strong>&quot;Permission denied&quot; error?</strong> Double-check your password.
            Some providers email the password instead of letting you set it—check your inbox.
            If root login is disabled, use the ubuntu fallback command above and then run{" "}
            <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">{becomeRootCommand}</code>.
          </GuideCaution>

          <div className="rounded-lg border border-primary/20 bg-primary/5 p-4">
            <Link href="/learn/ssh-basics" className="flex items-center gap-3 text-sm">
              <BookOpen className="h-5 w-5 text-primary" />
              <div>
                <span className="font-medium text-foreground">Want to learn more about SSH?</span>
                <p className="text-muted-foreground">
                  Check out the SSH & Persistence lesson in the Learning Hub →
                </p>
              </div>
            </Link>
          </div>
        </div>
      </SimplerGuide>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg" disableMotion>
          {isNavigating ? "Loading..." : "I'm connected, continue"}
        </Button>
      </div>
    </div>
  );
}
