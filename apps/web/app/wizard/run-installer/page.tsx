"use client";

import { useCallback, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Sparkles,
  Clock,
  ExternalLink,
  Check,
  Rocket,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { CommandCard } from "@/components/command-card";
import { AlertCard, OutputPreview, DetailsSection } from "@/components/alert-card";
import { markStepComplete } from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
  GuideCaution,
} from "@/components/simpler-guide";
import { Jargon } from "@/components/jargon";

const INSTALL_COMMAND = `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh?$(date +%s)" | bash -s -- --yes --mode vibe`;

const WHAT_IT_INSTALLS = [
  {
    category: "Shell & Terminal UX",
    items: ["zsh + oh-my-zsh + powerlevel10k", "atuin (shell history)", "fzf", "zoxide", "lsd"],
  },
  {
    category: "Languages & Package Managers",
    items: ["bun (JavaScript/TypeScript)", "uv (Python)", "rust/cargo", "go"],
  },
  {
    category: "Dev Tools",
    items: ["tmux", "ripgrep", "ast-grep", "lazygit", "bat"],
  },
  {
    category: "Coding Agents",
    items: ["Claude Code", "Codex CLI", "Gemini CLI"],
  },
  {
    category: "Cloud & Database",
    items: ["PostgreSQL 18", "Vault", "Wrangler", "Supabase CLI", "Vercel CLI"],
  },
  {
    category: "Dicklesworthstone Stack",
    items: ["ntm", "mcp_agent_mail", "beads_viewer", "and 5 more tools"],
  },
];

export default function RunInstallerPage() {
  const router = useRouter();
  const [isNavigating, setIsNavigating] = useState(false);

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "run_installer",
    stepNumber: 7,
    stepTitle: "Run Installer",
  });

  const handleContinue = useCallback(() => {
    markComplete();
    markStepComplete(7);
    setIsNavigating(true);
    router.push("/wizard/reconnect-ubuntu");
  }, [router, markComplete]);

  return (
    <div className="space-y-8">
      {/* Header with sparkle */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="relative flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br from-primary/30 to-[oklch(0.7_0.2_330/0.3)] shadow-lg shadow-primary/20">
            <Rocket className="h-6 w-6 text-primary" />
            <Sparkles className="absolute -right-1 -top-1 h-4 w-4 text-[oklch(0.78_0.16_75)] animate-pulse" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-primary via-foreground to-[oklch(0.7_0.2_330)] bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              Run the Agent Flywheel installer
            </h1>
            <p className="text-sm text-muted-foreground">
              ~15 min
            </p>
          </div>
        </div>
        <p className="text-lg text-muted-foreground">
          This is the magic moment. One command sets everything up.
        </p>
      </div>

      {/* Warning */}
      <AlertCard variant="warning" title="Don't close the terminal">
        Stay connected during installation. If disconnected, <Jargon term="ssh">SSH</Jargon> back in
        and check if it&apos;s still running.
      </AlertCard>

      {/* The command */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">
          Paste this command in your SSH session
        </h2>
        <CommandCard
          command={INSTALL_COMMAND}
          description="Agent Flywheel installer one-liner"
          showCheckbox
          persistKey="run-flywheel-installer"
          className="border-2 border-primary/20"
        />
      </div>

      {/* Time estimate */}
      <div className="flex items-center gap-2 text-muted-foreground">
        <Clock className="h-5 w-5" />
        <span>Takes about 10-15 minutes depending on your VPS speed</span>
      </div>

      {/* What it installs - collapsible */}
      <DetailsSection summary="What this command installs">
        <div className="grid gap-4 sm:grid-cols-2">
          {WHAT_IT_INSTALLS.map((group) => (
            <div key={group.category}>
              <h4 className="mb-2 font-medium text-foreground">{group.category}</h4>
              <ul className="space-y-1 text-sm text-muted-foreground">
                {group.items.map((item, i) => (
                  <li key={i} className="flex items-center gap-2">
                    <Check className="h-3 w-3 text-[oklch(0.72_0.19_145)]" />
                    {item}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </DetailsSection>

      {/* View source */}
      <div className="flex items-center gap-2 text-sm">
        <span className="text-muted-foreground">
          Want to see exactly what it does?
        </span>
        <a
          href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/blob/main/install.sh"
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1 font-medium text-primary hover:underline"
        >
          View install.sh source
          <ExternalLink className="h-3 w-3" />
        </a>
      </div>

      {/* Success signs */}
      <OutputPreview title="You'll know it's done when you see:">
        <p className="text-[oklch(0.72_0.19_145)]">✔ Agent Flywheel installation complete!</p>
        <p className="text-muted-foreground">
          Please reconnect as: ssh ubuntu@YOUR_IP
        </p>
      </OutputPreview>

      {/* Beginner Guide */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="What is this command doing?">
            This command downloads and runs a setup script that automatically installs
            everything you need on your VPS. Think of it like running an installer
            on your computer — but this one installs dozens of tools at once!
            <br /><br />
            The script is <Jargon term="idempotent">&quot;idempotent&quot;</Jargon> which means it&apos;s safe to run multiple times.
            If something fails, you can just run it again.
          </GuideExplain>

          <GuideSection title="Step-by-Step">
            <div className="space-y-4">
              <GuideStep number={1} title="Make sure you're connected to your VPS">
                Your <Jargon term="terminal">terminal</Jargon> should show something like{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ubuntu@vps:~$</code>
                or <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">root@vps:~#</code>.
                <br /><br />
                If it shows your regular computer name, you need to SSH in first!
              </GuideStep>

              <GuideStep number={2} title="Copy the install command">
                Click the copy button on the purple command box above. The command
                is quite long — make sure you copy the whole thing!
              </GuideStep>

              <GuideStep number={3} title="Paste and run">
                In your SSH terminal (where you&apos;re connected to the VPS), paste
                the command and press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd>.
                <br /><br />
                You&apos;ll see lots of text scrolling by — this is normal!
              </GuideStep>

              <GuideStep number={4} title="Wait patiently (10-15 minutes)">
                The installation takes time because it&apos;s downloading and installing
                many tools. You&apos;ll see progress messages like:
                <ul className="mt-2 list-disc space-y-1 pl-5">
                  <li><code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">[1/8] Installing zsh...</code></li>
                  <li><code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">[2/8] Installing bun...</code></li>
                  <li>etc.</li>
                </ul>
                <br />
                <strong>Don&apos;t close the terminal!</strong> Let it run until you see
                &quot;Installation complete&quot;.
              </GuideStep>
            </div>
          </GuideSection>

          <GuideSection title="What gets installed?">
            <p className="mb-3">
              The installer sets up a complete development environment including:
            </p>
            <ul className="space-y-2">
              <li>
                <strong>Modern shell (zsh)</strong> — A better terminal experience with
                colors and suggestions
              </li>
              <li>
                <strong>Programming languages</strong> — JavaScript/TypeScript, Python,
                Rust, and Go
              </li>
              <li>
                <strong>AI coding assistants</strong> — Claude Code, Codex, and Gemini CLI
              </li>
              <li>
                <strong>Developer tools</strong> — Git interface, file searchers, and more
              </li>
            </ul>
          </GuideSection>

          <GuideTip>
            If your internet connection drops during installation, just SSH back in
            and run the command again. The installer will pick up where it left off!
          </GuideTip>

          <GuideCaution>
            <strong>Don&apos;t close the terminal window</strong> while the installation
            is running. If you accidentally close it, SSH back in and run the
            command again — it will resume from where it stopped.
          </GuideCaution>
        </div>
      </SimplerGuide>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg">
          {isNavigating ? "Loading..." : "Installation finished"}
        </Button>
      </div>
    </div>
  );
}
