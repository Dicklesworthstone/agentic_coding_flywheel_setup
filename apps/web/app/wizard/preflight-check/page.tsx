"use client";

import { useCallback, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { ShieldCheck, AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { CommandCard } from "@/components/command-card";
import { AlertCard, OutputPreview, DetailsSection } from "@/components/alert-card";
import { ConnectionCheck } from "@/components/connection-check";
import { formatSshTarget } from "@/lib/commandBuilder";
import { markStepComplete, useWizardForwardNav } from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { normalizeGitRef, useACFSRef, useVPSIP } from "@/lib/userPreferences";
import { withCurrentSearch } from "@/lib/utils";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideCaution,
} from "@/components/simpler-guide";
import { Jargon } from "@/components/jargon";

const PREFLIGHT_SCRIPT_BASE_URL =
  "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup";
const DEFAULT_PREFLIGHT_REF = "main";

const TROUBLESHOOTING = [
  {
    title: "'bash' is not recognized / Get-Date error (Windows)",
    fixes: [
      "You're running this on your Windows computer, not on the VPS!",
      "First, connect to your VPS with: ssh root@YOUR_VPS_IP",
      "If root login is disabled, use: ssh ubuntu@YOUR_VPS_IP and then run: sudo -i",
      "If sudo asks for a password, use the ubuntu Linux account password, not the VPS root password or provider website password",
      "If you only have the VPS root password, use the provider console or root SSH path instead",
      "Wait until you see 'root@vps:~#' or similar",
      "THEN paste the preflight command",
      "The preflight command only works on the Linux VPS, not on Windows",
    ],
  },
  {
    title: "APT is locked by another process",
    fixes: [
      "Wait 1-2 minutes (auto updates often finish quickly)",
      "If it keeps failing, reboot the VPS, reconnect, and rerun preflight",
      "Optional diagnostic: sudo fuser -v /var/lib/dpkg/lock-frontend || true",
    ],
  },
  {
    title: "Cannot reach github.com (network/firewall)",
    fixes: [
      "Check that your VPS has outbound internet access",
      "Retry in a minute (provider networking sometimes lags)",
      "If on a corporate network, check firewall rules",
    ],
  },
  {
    title: "Insufficient disk space",
    fixes: [
      "Upgrade your VPS storage plan (recommended 20GB+ free)",
      "If you just created the VPS, choose a larger disk size",
    ],
  },
  {
    title: "Unsupported architecture",
    fixes: [
      "Use x86_64 or aarch64 VPS images",
      "Most providers default to x86_64 if not specified",
    ],
  },
];

export default function PreflightCheckPage() {
  const router = useRouter();
  const [vpsIP, , vpsIPLoaded] = useVPSIP();
  const [acfsRef, , acfsRefLoaded] = useACFSRef();
  const [ackPassed, setAckPassed] = useState(false);
  const [ackFailed, setAckFailed] = useState(false);
  const [isNavigating, setIsNavigating] = useState(false);
  const ready = vpsIPLoaded && acfsRefLoaded;

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "preflight_check",
    stepNumber: 8,
    stepTitle: "Pre-Flight Check",
  });

  const displayIP = vpsIP || "YOUR_VPS_IP";
  const rootTarget = formatSshTarget("root", displayIP);
  const ubuntuTarget = formatSshTarget("ubuntu", displayIP);
  const preflightRef = normalizeGitRef(acfsRef) ?? DEFAULT_PREFLIGHT_REF;
  const preflightCommand = useMemo(
    () =>
      `curl -fsSL "${PREFLIGHT_SCRIPT_BASE_URL}/${preflightRef}/scripts/preflight.sh" | bash`,
    [preflightRef],
  );

  const canContinue = ackPassed || ackFailed;

  const goNext = useCallback(() => {
    markComplete();
    markStepComplete(8);
    setIsNavigating(true);
    router.push(withCurrentSearch("/wizard/run-installer"));
  }, [router, markComplete]);

  const handleContinue = useCallback(() => {
    if (!canContinue) return;
    goNext();
  }, [canContinue, goNext]);

  const handleSkip = useCallback(() => {
    goNext();
  }, [goNext]);

  // Dock "Next" mirrors "Continue to installer"; the advanced skip stays inline.
  useWizardForwardNav({
    onContinue: handleContinue,
    disabled: !canContinue || isNavigating,
    loading: isNavigating,
  });

  if (!ready) {
    return (
      <div
        className="flex items-center justify-center py-12"
        role="status"
        aria-label="Loading pre-flight settings"
      >
        <ShieldCheck className="h-8 w-8 animate-pulse text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/20">
            <ShieldCheck className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              Pre-flight check your VPS
            </h1>
            <p className="text-sm text-muted-foreground">
              ~1 min
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          Before installing, let&apos;s confirm your <Jargon term="vps">VPS</Jargon> is ready.
        </p>
      </div>

      {/* CRITICAL: Connection check */}
      <ConnectionCheck
        vpsIP={displayIP}
        sshUser="root"
        useIdentityFile={false}
        showExplainer
        showWhereAmI
      />

      {/* Why this matters */}
      <AlertCard variant="info" icon={ShieldCheck} title="Fast safety check">
        This quick scan validates OS, disk space, network access, and APT locks.
        Warnings are okay — you can still continue.
      </AlertCard>

      {/* Windows-specific warning - CRITICAL for confused users */}
      <AlertCard variant="error" icon={AlertTriangle} title="Windows users: Common mistake!">
        <div className="space-y-2">
          <p>
            If you paste this command and see errors like <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">&apos;bash&apos; is not recognized</code> or
            <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">Get-Date : Cannot bind parameter</code>:
          </p>
          <p className="font-semibold">
            You&apos;re running this on your Windows computer, NOT on the VPS!
          </p>
          <p>
            Go back to your terminal, type <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">ssh {rootTarget}</code>,
            enter your VPS password, and THEN paste the preflight command.
          </p>
          <p className="text-sm text-muted-foreground">
            If your provider disabled root login, use{" "}
            <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">ssh {ubuntuTarget}</code>,
            then run <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">sudo -i</code>.
            If sudo asks for a password, use the ubuntu Linux account password,
            not the VPS root password or provider website password. If you only have the VPS root password,
            use the provider console or root SSH path instead.
            Continue only after your prompt ends with <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">#</code>.
          </p>
        </div>
      </AlertCard>

      {/* Command */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">Run this command</h2>
        <CommandCard
          command={preflightCommand}
          description="ACFS pre-flight validation"
          runLocation="vps"
          showCheckbox
          persistKey="preflight-check"
        />
      </div>

      {/* Expected output */}
      <OutputPreview title="Expected output (example)">
        <div className="space-y-1 font-mono text-xs">
          <p className="text-muted-foreground">ACFS Pre-Flight Check</p>
          <p className="text-muted-foreground">---------------------</p>
          <p className="text-green">[✓] Operating System: Ubuntu 25.10 (or 24.04 before upgrade)</p>
          <p className="text-green">[✓] Architecture: x86_64</p>
          <p className="text-green">[✓] Disk Space: 45GB free</p>
          <p className="text-amber">[!] Warning: Cannot reach https://claude.ai</p>
          <p className="text-muted-foreground">Result: 0 errors, 1 warning</p>
        </div>
      </OutputPreview>

      {/* Proceed acknowledgement */}
      <div className="rounded-xl border border-border/50 bg-card/50 p-4">
        <h3 className="mb-3 font-semibold">Before you continue</h3>
        <div className="space-y-3 text-sm">
          <label className="flex min-h-11 cursor-pointer items-start gap-3 py-2">
            <Checkbox
              checked={ackPassed}
              onCheckedChange={(checked) => {
                const isChecked = checked === true;
                setAckPassed(isChecked);
                if (isChecked) setAckFailed(false);
              }}
            />
            <span className="text-foreground">
              Pre-flight passed (all green, or only warnings)
            </span>
          </label>
          <label className="flex min-h-11 cursor-pointer items-start gap-3 py-2">
            <Checkbox
              checked={ackFailed}
              onCheckedChange={(checked) => {
                const isChecked = checked === true;
                setAckFailed(isChecked);
                if (isChecked) setAckPassed(false);
              }}
            />
            <span className="text-foreground">
              I understand some checks failed and I&apos;m choosing to continue
            </span>
          </label>
        </div>
      </div>

      {/* Troubleshooting */}
      <div className="space-y-3">
        <h2 className="text-xl font-semibold">Troubleshooting common failures</h2>
        <div className="space-y-3">
          {TROUBLESHOOTING.map((item) => (
            <DetailsSection key={item.title} summary={item.title}>
              <ul className="list-disc space-y-1 pl-5 text-sm text-muted-foreground">
                {item.fixes.map((fix, i) => (
                  <li key={i}>{fix}</li>
                ))}
              </ul>
            </DetailsSection>
          ))}
        </div>
      </div>

      {/* Help */}
      <AlertCard variant="warning" icon={AlertTriangle} title="Seeing red errors?">
        Fix the red errors before installing. The installer will likely fail otherwise.
      </AlertCard>

      {/* Actions */}
      <div className="space-y-2">
        {!canContinue && (
          <p id="preflight-continue-hint" className="text-sm text-muted-foreground">
            Tick one of the two boxes above to continue.
          </p>
        )}
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
          <Button
            onClick={handleContinue}
            className="bg-primary text-primary-foreground"
            disabled={!canContinue || isNavigating}
            aria-describedby={!canContinue ? "preflight-continue-hint" : undefined}
          >
            Continue to installer
          </Button>
          <Button variant="outline" onClick={handleSkip} disabled={isNavigating}>
            Skip pre-flight (advanced)
          </Button>
        </div>
      </div>

      {/* Beginner Guide */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="What is a pre-flight check?">
            A quick diagnostic that confirms your VPS meets the requirements before the full install.
          </GuideExplain>

          <GuideSection title="Step-by-Step">
            <div className="space-y-4">
              <GuideStep number={1} title="Copy the command">
                Click the copy button in the command box above.
              </GuideStep>
              <GuideStep number={2} title="Paste and run">
                Paste into your terminal (make sure you&apos;re connected to your VPS).
              </GuideStep>
              <GuideStep number={3} title="Read the results">
                Green lines are good. Yellow warnings are okay. Red errors should be fixed.
              </GuideStep>
            </div>
          </GuideSection>

          <GuideCaution>
            <strong>Warnings are okay:</strong> Warnings mean something might be imperfect but not
            critical. If you see errors, fix those first or use a larger VPS plan.
          </GuideCaution>
        </div>
      </SimplerGuide>

    </div>
  );
}
