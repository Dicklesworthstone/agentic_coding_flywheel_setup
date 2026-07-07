"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { RefreshCw, Check, UserCheck, BookOpen } from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { CommandCard } from "@/components/command-card";
import { AlertCard, OutputPreview } from "@/components/alert-card";
import { buildRootKeyRepairCommand, buildUserKeyRepairCommand, formatSshTarget } from "@/lib/commandBuilder";
import { markStepComplete } from "@/lib/wizardSteps";
import { useSSHUsername, useVPSIP } from "@/lib/userPreferences";
import { withCurrentSearch } from "@/lib/utils";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
} from "@/components/simpler-guide";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { Jargon } from "@/components/jargon";

export default function ReconnectUbuntuPage() {
  const router = useRouter();
  const [vpsIP, , vpsIPLoaded] = useVPSIP();
  const [sshUsername, , sshUsernameLoaded] = useSSHUsername();
  const [isNavigating, setIsNavigating] = useState(false);
  const ready = vpsIPLoaded && sshUsernameLoaded;

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "reconnect_ubuntu",
    stepNumber: 10,
    stepTitle: "Reconnect as Ubuntu",
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
    markStepComplete(10);
    setIsNavigating(true);
    router.push(withCurrentSearch("/wizard/verify-key-connection"));
  }, [router, markComplete]);

  const handleSkip = useCallback(() => {
    markComplete({ skipped: true });
    markStepComplete(10);
    setIsNavigating(true);
    router.push(withCurrentSearch("/wizard/verify-key-connection"));
  }, [router, markComplete]);

  if (!ready || !vpsIP) {
    return (
      <div className="flex items-center justify-center py-12">
        <RefreshCw className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  const effectiveUsername = sshUsername.trim() || "ubuntu";
  const userTarget = formatSshTarget(effectiveUsername, vpsIP);
  const userPrompt = `${effectiveUsername}@`;
  const sshCommand = `ssh -i ~/.ssh/acfs_ed25519 ${userTarget}`;
  const sshCommandWindows = `ssh -i %USERPROFILE%\\.ssh\\acfs_ed25519 ${userTarget}`;
  const userKeyRepairCommand = buildUserKeyRepairCommand(effectiveUsername, vpsIP);
  const rootKeyRepairCommand = buildRootKeyRepairCommand(effectiveUsername, vpsIP);

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/20">
            <UserCheck className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              Reconnect with your SSH user
            </h1>
            <p className="text-sm text-muted-foreground">
              ~1 min
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          If you ran the installer as <Jargon term="root-user">root</Jargon>, reconnect as your normal SSH user (
          <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">{effectiveUsername}</code>) to get the full shell experience.
        </p>
      </div>

      {/* Already ubuntu? */}
      <div className="rounded-xl border border-[oklch(0.72_0.19_145/0.3)] bg-[oklch(0.72_0.19_145/0.08)] p-4">
        <div className="flex items-start gap-3">
          <Check className="mt-0.5 h-5 w-5 text-[oklch(0.72_0.19_145)]" />
          <div>
            <p className="font-medium text-foreground">Already connected as {effectiveUsername}?</p>
            <p className="text-sm text-muted-foreground">
              If your prompt shows <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">{userPrompt}</code>, you can skip this step.
            </p>
            <Button
              variant="outline"
              size="sm"
              className="mt-2"
              onClick={handleSkip}
            >
              Skip, I&apos;m already {effectiveUsername}
            </Button>
          </div>
        </div>
      </div>

      {/* Reconnect steps */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">If you connected as root:</h2>

        <div className="space-y-3">
          <p className="text-sm text-muted-foreground">
            1. Type <code className="rounded bg-muted px-1">exit</code> to close
            the current session
          </p>
          <CommandCard command="exit" description="Close root session" runLocation="vps" />
        </div>

        <div className="space-y-3">
          <p className="text-sm text-muted-foreground">
            2. Reconnect as {effectiveUsername}:
          </p>

          <div className="space-y-3">
            <h3 className="font-semibold">Notice something different?</h3>
            <p className="text-sm text-muted-foreground">
              This SSH command uses your SSH key (the{" "}
              <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">
                -i ~/.ssh/acfs_ed25519
              </code>{" "}
              part — or on Windows{" "}
              <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">
                -i %USERPROFILE%\.ssh\acfs_ed25519
              </code>
              ) instead of a password. The installer set this up for you.
            </p>
            <AlertCard variant="success" title="No password needed!">
              When you run this command, you should connect immediately without typing a password.
              SSH keys are more secure <strong>and</strong> more convenient.
            </AlertCard>
          </div>

          <CommandCard
            command={sshCommand}
            windowsCommand={sshCommandWindows}
            description={`Reconnect as ${effectiveUsername}`}
            runLocation="local"
            showCheckbox
            persistKey="reconnect-ubuntu"
          />

          {/* Common mistake: using wrong credentials */}
          <AlertCard variant="error" title="Getting 'Permission denied' or asked for password?">
            <div className="space-y-2 text-sm">
              <p>This means one of two things:</p>
              <ol className="list-decimal list-inside space-y-1 mt-2">
                <li>
                  <strong className="text-foreground">SSH key wasn&apos;t set up correctly</strong> —
                  the installer needs to complete successfully for this to work
                </li>
                <li>
                  <strong className="text-foreground">You&apos;re using the wrong credentials</strong> —
                  your configured SSH user (<code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">{effectiveUsername}</code>) uses your <em>SSH key</em>, NOT the root password
                </li>
              </ol>
              <p className="mt-3 font-medium text-foreground">
                If you can still sign in as {effectiveUsername}, copy your key into that account first:
              </p>
              <CommandCard command={userKeyRepairCommand} runLocation="local" className="mt-2" />
              <p className="mt-2 text-xs text-muted-foreground">
                This uses the {effectiveUsername} account and does not ask for the VPS root password.
              </p>
              <p className="mt-3 font-medium text-foreground">
                If that cannot connect, use the root fallback:
              </p>
              <CommandCard command={rootKeyRepairCommand} runLocation="local" className="mt-2" />
              <p className="mt-2 text-xs text-muted-foreground">
                This asks for the VPS root password once. Then retry the SSH command above.
              </p>
            </div>
          </AlertCard>
        </div>
      </div>

      {/* Verification */}
      <OutputPreview title="You'll know it worked when:">
        <ul className="space-y-1 text-sm">
          <li className="text-[oklch(0.72_0.19_145)]">
            • Your prompt shows <code className="text-muted-foreground">{userPrompt}</code> (not <code className="text-muted-foreground">root@</code>)
          </li>
          <li className="text-[oklch(0.72_0.19_145)]">• You see the colorful powerlevel10k prompt</li>
          <li className="text-[oklch(0.72_0.19_145)]">• The shell feels more responsive</li>
        </ul>
      </OutputPreview>

      <AlertCard variant="tip" title="Prompt customization wizard?">
        <p>
          The first time you connect, you might see a &quot;Powerlevel10k configuration wizard&quot;
          asking about fonts and prompt style.
        </p>
        <ul className="mt-2 list-disc space-y-1 pl-5">
          <li>
            Press{" "}
            <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">q</kbd>{" "}
            to quit and use defaults (recommended for now)
          </li>
          <li>Or go through it if you want to customize how your prompt looks</li>
        </ul>
        <p className="mt-2 text-xs text-muted-foreground">
          You can always run{" "}
          <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">
            p10k configure
          </code>{" "}
          later to customize.
        </p>
      </AlertCard>

      {/* Beginner Guide */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="Why reconnect with your SSH user?">
            During installation, you may have connected as &quot;root&quot;, the super-admin
            account. Now we want you to use your normal SSH user instead because:
            <br /><br />
            <strong>1. Safety:</strong> Day-to-day ACFS work should happen from a non-root login whenever possible.
            That keeps routine commands away from the most dangerous account.
            <br /><br />
            <strong>2. Better experience:</strong> The installer set up special features
            (like the colorful prompt) for your configured SSH user.
          </GuideExplain>

          <GuideSection title="How do I know which user I am?">
            <p>Look at your terminal prompt:</p>
            <ul className="mt-2 space-y-2">
              <li>
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">root@vps:~#</code>
                means you&apos;re logged in as root (note the <strong>#</strong> symbol)
              </li>
              <li>
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">{userPrompt}vps:~$</code>
                means you&apos;re logged in as {effectiveUsername} (note the <strong>$</strong> symbol)
              </li>
            </ul>
          </GuideSection>

          <GuideSection title="Step-by-step: switching users">
            <div className="space-y-4">
              <GuideStep number={1} title="Disconnect from the current session">
                Type <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">exit</code>
                and press Enter. This closes your connection to the VPS.
              </GuideStep>

              <GuideStep number={2} title={`Connect as ${effectiveUsername}`}>
                Copy and paste the SSH command shown above (the one with{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">{userPrompt}</code>)
                and press Enter.
              </GuideStep>

              <GuideStep number={3} title="Verify you&apos;re using the right user">
                Your prompt should now show <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">{userPrompt}</code> at the beginning.
                You might also see a fancy colorful prompt!
              </GuideStep>
            </div>
          </GuideSection>

          <GuideTip>
            If you were already connected as {effectiveUsername} (skip button above applies to you),
            just click &quot;Skip&quot; or &quot;Continue&quot;; you don&apos;t need to do anything!
          </GuideTip>

          <div className="rounded-lg border border-primary/20 bg-primary/5 p-4">
            <Link href="/learn/linux-basics" className="flex items-center gap-3 text-sm">
              <BookOpen className="h-5 w-5 text-primary" />
              <div>
                <span className="font-medium text-foreground">New to Linux?</span>
                <p className="text-muted-foreground">
                  Learn the basics of navigating the filesystem →
                </p>
              </div>
            </Link>
          </div>
        </div>
      </SimplerGuide>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg" disableMotion>
          {isNavigating ? "Loading..." : `I'm connected as ${effectiveUsername}`}
        </Button>
      </div>
    </div>
  );
}
