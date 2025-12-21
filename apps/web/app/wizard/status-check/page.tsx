"use client";

import { useCallback, useState } from "react";
import { useRouter } from "next/navigation";
import { AlertCircle, Stethoscope } from "lucide-react";
import { Button } from "@/components/ui/button";
import { CommandCard } from "@/components/command-card";
import { AlertCard, OutputPreview } from "@/components/alert-card";
import { markStepComplete } from "@/lib/wizardSteps";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
  GuideCaution,
} from "@/components/simpler-guide";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { Jargon } from "@/components/jargon";

const QUICK_CHECKS = [
  {
    command: "cc --version",
    description: "Check Claude Code is installed",
  },
  {
    command: "bun --version",
    description: "Check bun is installed",
  },
  {
    command: "which tmux",
    description: "Check tmux is installed",
  },
];

export default function StatusCheckPage() {
  const router = useRouter();
  const [isNavigating, setIsNavigating] = useState(false);

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "status_check",
    stepNumber: 9,
    stepTitle: "Status Check",
  });

  const handleContinue = useCallback(() => {
    markComplete();
    markStepComplete(9);
    setIsNavigating(true);
    router.push("/wizard/launch-onboarding");
  }, [router, markComplete]);

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/20">
            <Stethoscope className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              Agent Flywheel status check
            </h1>
            <p className="text-sm text-muted-foreground">
              ~1 min
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          Let&apos;s verify everything installed correctly on your <Jargon term="vps">VPS</Jargon>.
        </p>
      </div>

      {/* Doctor command */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold text-foreground">Run the doctor command</h2>
        <p className="text-sm text-muted-foreground">
          This checks all installed tools and reports any issues:
        </p>
        <CommandCard
          command="acfs doctor"
          description="Run Agent Flywheel health check"
          showCheckbox
          persistKey="flywheel-doctor"
        />
      </div>

      {/* Expected output */}
      <OutputPreview title="Expected output">
        <div className="space-y-1 font-mono text-xs">
          <p className="text-muted-foreground">Agent Flywheel Doctor - System Health Check</p>
          <p className="text-muted-foreground">================================</p>
          <p className="text-[oklch(0.72_0.19_145)]">✔ Shell: zsh with oh-my-zsh</p>
          <p className="text-[oklch(0.72_0.19_145)]">✔ Languages: bun, uv, rust, go</p>
          <p className="text-[oklch(0.72_0.19_145)]">✔ Tools: <Jargon term="tmux">tmux</Jargon>, <Jargon term="ripgrep">ripgrep</Jargon>, <Jargon term="lazygit">lazygit</Jargon></p>
          <p className="text-[oklch(0.72_0.19_145)]">✔ Agents: claude-code, codex</p>
          <p className="mt-2 text-foreground">All checks passed!</p>
        </div>
      </OutputPreview>

      {/* Quick spot checks */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">Quick spot checks</h2>
        <p className="text-sm text-muted-foreground">
          Try a few commands to verify key tools:
        </p>
        <div className="space-y-3">
          {QUICK_CHECKS.map((check, i) => (
            <CommandCard
              key={i}
              command={check.command}
              description={check.description}
            />
          ))}
        </div>
      </div>

      {/* Troubleshooting */}
      <AlertCard variant="warning" icon={AlertCircle} title="Something not working?">
        Try running{" "}
        <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">source ~/.zshrc</code> to
        reload your shell config, then try the doctor again.
      </AlertCard>

      {/* Beginner Guide */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="What is the 'doctor' command?">
            The &quot;doctor&quot; command is like a health checkup for your VPS. Just like
            a doctor checks your heart, lungs, and reflexes, this command checks
            that all the software tools were installed correctly.
            <br /><br />
            It goes through a list of tools (programming languages, coding assistants,
            utilities) and reports which ones are working and which ones might have
            problems.
          </GuideExplain>

          <GuideSection title="Step-by-Step: Running the Doctor">
            <div className="space-y-4">
              <GuideStep number={1} title="Make sure you're connected to your VPS">
                Your terminal should show{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ubuntu@</code>
                at the beginning of your prompt. If it shows your laptop&apos;s name,
                you need to SSH in first!
              </GuideStep>

              <GuideStep number={2} title="Copy the doctor command">
                Click the copy button on the{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">acfs doctor</code>
                command box above.
              </GuideStep>

              <GuideStep number={3} title="Paste and run">
                Paste the command in your terminal and press{" "}
                <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd>.
              </GuideStep>

              <GuideStep number={4} title="Read the results">
                You&apos;ll see a list with checkmarks (✔) or X marks (✘):
                <ul className="mt-2 space-y-1">
                  <li>
                    <span className="text-[oklch(0.72_0.19_145)]">✔ Green checkmarks</span> = Working correctly!
                  </li>
                  <li>
                    <span className="text-destructive">✘ Red X marks</span> = Something needs attention
                  </li>
                </ul>
              </GuideStep>
            </div>
          </GuideSection>

          <GuideSection title="Understanding the Quick Spot Checks">
            <p className="mb-3">
              We also show some simple commands you can run to double-check specific tools:
            </p>
            <ul className="space-y-3">
              <li>
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">cc --version</code>
                <br />
                <span className="text-sm text-muted-foreground">
                  This checks Claude Code — the AI coding assistant. You should see
                  a version number like &quot;1.0.3&quot;.
                </span>
              </li>
              <li>
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">bun --version</code>
                <br />
                <span className="text-sm text-muted-foreground">
                  This checks Bun — a fast JavaScript runtime. You should see
                  something like &quot;1.1.38&quot;.
                </span>
              </li>
              <li>
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">which tmux</code>
                <br />
                <span className="text-sm text-muted-foreground">
                  This checks if tmux is installed. You should see a path like
                  &quot;/usr/bin/tmux&quot;.
                </span>
              </li>
            </ul>
          </GuideSection>

          <GuideSection title="What If Something Failed?">
            <p className="mb-3">
              Don&apos;t panic! Here are some common fixes:
            </p>
            <div className="space-y-4">
              <div>
                <p className="font-medium">&quot;Command not found&quot; error</p>
                <p className="text-sm text-muted-foreground">
                  This usually means your shell config hasn&apos;t loaded yet. Run this command
                  to reload it:
                </p>
                <code className="mt-1 block rounded bg-muted px-2 py-1 font-mono text-xs">
                  source ~/.zshrc
                </code>
                <p className="mt-1 text-sm text-muted-foreground">
                  Then try the doctor command again.
                </p>
              </div>

              <div>
                <p className="font-medium">A specific tool shows ✘</p>
                <p className="text-sm text-muted-foreground">
                  You can try re-running the installer. It&apos;s safe to run multiple times:
                </p>
                <code className="mt-1 block rounded bg-muted px-2 py-1 font-mono text-xs">
                  curl -fsSL &quot;https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh&quot; | bash -s -- --yes --mode vibe
                </code>
              </div>

              <div>
                <p className="font-medium">Nothing works at all</p>
                <p className="text-sm text-muted-foreground">
                  Make sure you&apos;re connected as the &quot;ubuntu&quot; user (not root).
                  The installer set up tools for the ubuntu user specifically.
                </p>
              </div>
            </div>
          </GuideSection>

          <GuideTip>
            If most things show green checkmarks (✔), you&apos;re good to go! Don&apos;t worry
            about one or two yellow warnings — those are usually optional tools.
            Click &quot;Everything looks good!&quot; to continue.
          </GuideTip>

          <GuideCaution>
            <strong>If you see many red X marks:</strong> Don&apos;t continue yet. Try the
            troubleshooting steps above, or re-run the installer. If problems persist,
            you can ask for help in the project&apos;s GitHub issues.
          </GuideCaution>
        </div>
      </SimplerGuide>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg">
          {isNavigating ? "Loading..." : "Everything looks good!"}
        </Button>
      </div>
    </div>
  );
}
