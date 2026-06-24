"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { KeyRound, ShieldCheck, Terminal } from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { CommandCard } from "@/components/command-card";
import { AlertCard, OutputPreview } from "@/components/alert-card";
import { buildRootKeyRepairCommand, buildUserKeyRepairCommand, formatSshTarget } from "@/lib/commandBuilder";
import { markStepComplete } from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { useSSHUsername, useVPSIP } from "@/lib/userPreferences";
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

export default function VerifyKeyConnectionPage() {
  const router = useRouter();
  const [vpsIP, , vpsIPLoaded] = useVPSIP();
  const [sshUsername, , sshUsernameLoaded] = useSSHUsername();
  const [isNavigating, setIsNavigating] = useState(false);
  const ready = vpsIPLoaded && sshUsernameLoaded;

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "verify_key_connection",
    stepNumber: 11,
    stepTitle: "Verify Key Connection",
  });

  // Redirect if no VPS IP (after hydration)
  useEffect(() => {
    if (!ready) return;
    if (vpsIP === null) {
      router.push(withCurrentSearch("/wizard/create-vps"));
    }
  }, [ready, vpsIP, router]);

  const handleContinue = useCallback(() => {
    markComplete();
    markStepComplete(11);
    setIsNavigating(true);
    router.push(withCurrentSearch("/wizard/status-check"));
  }, [router, markComplete]);

  if (!ready || !vpsIP) {
    return (
      <div className="flex items-center justify-center py-12">
        <KeyRound className="h-8 w-8 animate-pulse text-muted-foreground" />
      </div>
    );
  }

  const effectiveUsername = sshUsername.trim() || "ubuntu";
  const userTarget = formatSshTarget(effectiveUsername, vpsIP);
  const userPrompt = `${effectiveUsername}@`;
  const sshKeyCommand = `ssh -i ~/.ssh/acfs_ed25519 ${userTarget}`;
  const sshKeyCommandWindows = `ssh -i %USERPROFILE%\\.ssh\\acfs_ed25519 ${userTarget}`;
  const userKeyRepairCommand = buildUserKeyRepairCommand(effectiveUsername, vpsIP);
  const rootKeyRepairCommand = buildRootKeyRepairCommand(effectiveUsername, vpsIP);

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/20">
            <KeyRound className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              Verify key-based connection
            </h1>
            <p className="text-sm text-muted-foreground">
              ~1 min
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          Make sure your <Jargon term="ssh">SSH</Jargon> key works so you never need the password again.
        </p>
      </div>

      <AlertCard variant="info" icon={ShieldCheck} title="Why this matters">
        This confirms the installer set up your key correctly and that future logins are fast and secure.
      </AlertCard>

      {/* Step 1: Disconnect */}
      <div className="space-y-3">
        <h2 className="text-xl font-semibold">Step 1: Disconnect</h2>
        <p className="text-sm text-muted-foreground">
          Exit your current SSH session to return to your local terminal.
        </p>
        <CommandCard command="exit" description="Close the current session" runLocation="vps" />
      </div>

      {/* Step 2: Reconnect with key */}
      <div className="space-y-3">
        <h2 className="text-xl font-semibold">Step 2: Reconnect using your SSH key</h2>
        <p className="text-sm text-muted-foreground">
          Connect without a password prompt using the key you generated earlier.
        </p>
        <CommandCard
          command={sshKeyCommand}
          windowsCommand={sshKeyCommandWindows}
          description="Key-based login (no password)"
          runLocation="local"
          showCheckbox
          persistKey="verify-key-connection"
        />
      </div>

      {/* Success indicator */}
      <OutputPreview title="Success looks like:">
        <div className="space-y-2 text-sm">
          <p className="text-[oklch(0.72_0.19_145)]">• You were not asked for a password</p>
          <p className="text-[oklch(0.72_0.19_145)]">• Your prompt shows: {userPrompt}vps:~$</p>
        </div>
      </OutputPreview>

      {/* Windows Terminal tip */}
      <div className="rounded-xl border border-[oklch(0.75_0.18_195/0.3)] bg-[oklch(0.75_0.18_195/0.08)] p-4">
        <Link
          href={withCurrentSearch("/wizard/windows-terminal-setup?from=verify-key-connection")}
          className="flex items-start gap-3"
        >
          <Terminal className="mt-0.5 h-5 w-5 text-[oklch(0.75_0.18_195)]" />
          <div>
            <p className="font-medium text-foreground">
              Windows User? Set up one-click VPS access
            </p>
            <p className="text-sm text-muted-foreground">
              Create a Windows Terminal profile to connect to your VPS with a single click →
            </p>
          </div>
        </Link>
      </div>

      {/* Troubleshooting */}
      <div className="space-y-3">
        <h2 className="text-xl font-semibold">Troubleshooting</h2>
        <div className="space-y-3">
          <AlertCard variant="warning" title="Still asks for a password?">
            <div className="space-y-2">
              <p>
                If you can still sign in as {effectiveUsername}, copy your local ACFS public key into that account:
              </p>
              <CommandCard command={userKeyRepairCommand} runLocation="local" />
              <p className="text-xs text-muted-foreground">
                This uses the {effectiveUsername} account and does not ask for the VPS root password.
              </p>
              <p className="pt-2">
                If that cannot connect, use the root fallback:
              </p>
              <CommandCard command={rootKeyRepairCommand} runLocation="local" />
              <p className="text-xs text-muted-foreground">
                This asks for the VPS root password once. ACFS skips exact duplicate public key lines on reruns.
              </p>
            </div>
          </AlertCard>
          <AlertCard variant="warning" title="Permission denied (publickey)">
            Your key file permissions may be too open. Fix with:
            <div className="mt-2">
              <CommandCard command="chmod 600 ~/.ssh/acfs_ed25519" runLocation="local" />
            </div>
          </AlertCard>
          <AlertCard variant="warning" title="Connection refused">
            Your VPS might still be rebooting. Wait 1-2 minutes and try again.
          </AlertCard>
        </div>
      </div>

      {/* Beginner Guide */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="Key-based authentication">
            Instead of typing a password, your computer proves it has a secret key that matches
            the public key stored on your VPS. It&apos;s faster and more secure than passwords.
          </GuideExplain>

          <GuideSection title="Step-by-step verification">
            <div className="space-y-4">
              <GuideStep number={1} title="Exit the current session">
                Type <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">exit</code> and
                press Enter to return to your local terminal.
              </GuideStep>

              <GuideStep number={2} title="Reconnect with your key">
                Paste the SSH command above (with <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">-i</code>)
                and press Enter. You should NOT be asked for a password.
              </GuideStep>

              <GuideStep number={3} title="Confirm the prompt">
                Look for <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">{userPrompt}</code> and a
                <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">$</code> at the end.
              </GuideStep>
            </div>
          </GuideSection>

          <GuideTip>
            If you see a password prompt, stop and fix it now—this step prevents future login headaches.
          </GuideTip>

          <GuideCaution>
            <strong>Using a different key?</strong> Make sure you&apos;re pointing to the same key you created earlier:
            <code className="ml-1 rounded bg-muted px-1.5 py-0.5 font-mono text-xs">~/.ssh/acfs_ed25519</code>.
          </GuideCaution>
        </div>
      </SimplerGuide>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg" disableMotion>
          {isNavigating ? "Loading..." : "My key works, continue"}
        </Button>
      </div>
    </div>
  );
}
