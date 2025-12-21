"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { RefreshCw, Check, UserCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { CommandCard } from "@/components/command-card";
import { OutputPreview } from "@/components/alert-card";
import { markStepComplete } from "@/lib/wizardSteps";
import { useVPSIP } from "@/lib/userPreferences";
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
  const [isNavigating, setIsNavigating] = useState(false);
  const ready = vpsIPLoaded;

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "reconnect_ubuntu",
    stepNumber: 8,
    stepTitle: "Reconnect as Ubuntu",
  });

  // Redirect if no VPS IP (after hydration)
  useEffect(() => {
    if (!ready) return;
    if (vpsIP === null) {
      router.push("/wizard/create-vps");
    }
  }, [ready, vpsIP, router]);

  const handleContinue = useCallback(() => {
    markComplete();
    markStepComplete(8);
    setIsNavigating(true);
    router.push("/wizard/status-check");
  }, [router, markComplete]);

  const handleSkip = useCallback(() => {
    markComplete({ skipped: true });
    markStepComplete(8);
    setIsNavigating(true);
    router.push("/wizard/status-check");
  }, [router, markComplete]);

  if (!ready || !vpsIP) {
    return (
      <div className="flex items-center justify-center py-12">
        <RefreshCw className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  const sshCommand = `ssh -i ~/.ssh/acfs_ed25519 ubuntu@${vpsIP}`;
  const sshCommandWindows = `ssh -i $HOME\\.ssh\\acfs_ed25519 ubuntu@${vpsIP}`;

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
              Reconnect as ubuntu
            </h1>
            <p className="text-sm text-muted-foreground">
              ~1 min
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          If you ran the installer as <Jargon term="root-user">root</Jargon>, reconnect as the <Jargon term="ubuntu-user">ubuntu user</Jargon> to get
          the full shell experience.
        </p>
      </div>

      {/* Already ubuntu? */}
      <div className="rounded-xl border border-[oklch(0.72_0.19_145/0.3)] bg-[oklch(0.72_0.19_145/0.08)] p-4">
        <div className="flex items-start gap-3">
          <Check className="mt-0.5 h-5 w-5 text-[oklch(0.72_0.19_145)]" />
          <div>
            <p className="font-medium text-foreground">Already connected as ubuntu?</p>
            <p className="text-sm text-muted-foreground">
              If your prompt shows <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">ubuntu@</code>, you can skip this step.
            </p>
            <Button
              variant="outline"
              size="sm"
              className="mt-2"
              onClick={handleSkip}
            >
              Skip, I&apos;m already ubuntu
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
          <CommandCard command="exit" description="Close root session" />
        </div>

        <div className="space-y-3">
          <p className="text-sm text-muted-foreground">
            2. Reconnect as ubuntu:
          </p>
          <CommandCard
            command={sshCommand}
            windowsCommand={sshCommandWindows}
            description="Reconnect as ubuntu user"
            showCheckbox
            persistKey="reconnect-ubuntu"
          />
        </div>
      </div>

      {/* Verification */}
      <OutputPreview title="You'll know it worked when:">
        <ul className="space-y-1 text-sm">
          <li className="text-[oklch(0.72_0.19_145)]">
            • Your prompt shows <code className="text-muted-foreground">ubuntu@</code> (not <code className="text-muted-foreground">root@</code>)
          </li>
          <li className="text-[oklch(0.72_0.19_145)]">• You see the colorful powerlevel10k prompt</li>
          <li className="text-[oklch(0.72_0.19_145)]">• The shell feels more responsive</li>
        </ul>
      </OutputPreview>

      {/* Beginner Guide */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="Why reconnect as ubuntu?">
            During installation, you may have connected as &quot;root&quot; — the super-admin
            account. Now we want you to use the &quot;ubuntu&quot; account instead because:
            <br /><br />
            <strong>1. Safety</strong> — The root account can accidentally break things.
            The ubuntu account is safer for everyday use.
            <br /><br />
            <strong>2. Better experience</strong> — The installer set up special features
            (like the colorful prompt) for the ubuntu user.
          </GuideExplain>

          <GuideSection title="How do I know which user I am?">
            <p>Look at your terminal prompt:</p>
            <ul className="mt-2 space-y-2">
              <li>
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">root@vps:~#</code>
                — You&apos;re logged in as root (note the <strong>#</strong> symbol)
              </li>
              <li>
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ubuntu@vps:~$</code>
                — You&apos;re logged in as ubuntu (note the <strong>$</strong> symbol)
              </li>
            </ul>
          </GuideSection>

          <GuideSection title="Step-by-Step: Switching to Ubuntu">
            <div className="space-y-4">
              <GuideStep number={1} title="Disconnect from the current session">
                Type <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">exit</code>
                and press Enter. This closes your connection to the VPS.
              </GuideStep>

              <GuideStep number={2} title="Connect as ubuntu">
                Copy and paste the SSH command shown above (the one with{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ubuntu@</code>)
                and press Enter.
              </GuideStep>

              <GuideStep number={3} title="Verify you're ubuntu">
                Your prompt should now show &quot;ubuntu@&quot; at the beginning.
                You might also see a fancy colorful prompt!
              </GuideStep>
            </div>
          </GuideSection>

          <GuideTip>
            If you were already connected as ubuntu (skip button above applies to you),
            just click &quot;Skip&quot; or &quot;Continue&quot; — you don&apos;t need to do anything!
          </GuideTip>
        </div>
      </SimplerGuide>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg">
          {isNavigating ? "Loading..." : "I'm connected as ubuntu"}
        </Button>
      </div>
    </div>
  );
}
