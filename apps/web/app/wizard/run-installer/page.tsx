"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Sparkles,
  Clock,
  ExternalLink,
  Check,
  Rocket,
  ShieldCheck,
  Code,
  Wifi,
  Pin,
  Info,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { CommandCard } from "@/components/command-card";
import { AlertCard, OutputPreview, DetailsSection } from "@/components/alert-card";
import { TrackedLink } from "@/components/tracked-link";
import {
  canAccessWizardStep,
  getCompletedSteps,
  getNextReachableWizardStep,
  markStepComplete,
} from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { withCurrentSearch } from "@/lib/utils";
import { buildInstallCommand, formatSshTarget } from "@/lib/commandBuilder";
import { normalizeGitRef, useACFSRef, useInstallMode, useSSHUsername, useVPSIP } from "@/lib/userPreferences";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
  GuideCaution,
} from "@/components/simpler-guide";
import { Jargon } from "@/components/jargon";

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
    items: ["ntm", "mcp_agent_mail", "beads_viewer", "and 15+ more tools"],
  },
];

export default function RunInstallerPage() {
  const router = useRouter();
  const [isNavigating, setIsNavigating] = useState(false);
  const [installMode, , installModeLoaded] = useInstallMode();
  const [pinnedRef, setPinnedRef, acfsRefLoaded] = useACFSRef();
  const [vpsIP, , vpsIPLoaded] = useVPSIP();
  const [sshUsername, , sshUsernameLoaded] = useSSHUsername();
  const [pinEditorOpen, setPinEditorOpen] = useState(false);
  const [refDraftOverride, setRefDraftOverride] = useState<string | null>(null);
  const usePinnedRef = pinEditorOpen || pinnedRef !== null;
  const refDraft = pinEditorOpen
    ? (refDraftOverride ?? pinnedRef ?? "main")
    : (pinnedRef ?? "main");
  const safePinnedRef = useMemo(() => normalizeGitRef(refDraft), [refDraft]);
  const ready =
    installModeLoaded && acfsRefLoaded && vpsIPLoaded && sshUsernameLoaded;
  const effectiveInstallMode = installMode;
  const effectiveRef = usePinnedRef ? safePinnedRef : null;
  const effectiveVpsIP = vpsIP ?? "";
  const effectiveSSHUsername = sshUsername.trim() || "ubuntu";
  const reconnectCommand = useMemo(
    () => `ssh -i ~/.ssh/acfs_ed25519 ${formatSshTarget(effectiveSSHUsername, effectiveVpsIP)}`,
    [effectiveSSHUsername, effectiveVpsIP],
  );
  const effectiveSourceRef = useMemo(
    () => (usePinnedRef && safePinnedRef ? safePinnedRef : "main"),
    [usePinnedRef, safePinnedRef],
  );

  const handlePinnedRefToggle = useCallback((checked: boolean) => {
    if (!checked) {
      setPinEditorOpen(false);
      setRefDraftOverride(null);
      setPinnedRef(null);
      return;
    }
    const nextRef = pinnedRef ?? "main";
    setRefDraftOverride(nextRef);
    setPinEditorOpen(true);
    if (!pinnedRef || !pinnedRef.trim()) {
      setPinnedRef("main");
    }
  }, [pinnedRef, setPinnedRef]);

  const handlePinnedRefChange = useCallback((value: string) => {
    setPinEditorOpen(true);
    setRefDraftOverride(value);

    const trimmed = value.trim();
    if (!trimmed) {
      setPinnedRef(null);
      return;
    }

    const normalized = normalizeGitRef(trimmed);
    if (normalized) {
      setPinnedRef(normalized);
    }
  }, [setPinnedRef]);

  // Build command dynamically based on pinning options
  const installCommand = useMemo(
    () => buildInstallCommand(effectiveInstallMode, effectiveRef, effectiveSSHUsername),
    [effectiveInstallMode, effectiveRef, effectiveSSHUsername],
  );

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "run_installer",
    stepNumber: 9,
    stepTitle: "Run Installer",
  });

  useEffect(() => {
    if (!ready) return;

    const completedSteps = getCompletedSteps();
    if (!canAccessWizardStep(completedSteps, 9)) {
      const redirectStep = getNextReachableWizardStep(completedSteps);
      router.replace(withCurrentSearch(`/wizard/${redirectStep.slug}`));
      return;
    }

    if (vpsIP === null) {
      router.replace(withCurrentSearch("/wizard/create-vps"));
    }
  }, [ready, router, vpsIP]);

  const handleContinue = useCallback(() => {
    markComplete();
    markStepComplete(9);
    setIsNavigating(true);
    router.push(withCurrentSearch("/wizard/reconnect-ubuntu"));
  }, [router, markComplete]);

  if (!ready || vpsIP === null) {
    return (
      <div className="flex items-center justify-center py-12">
        <Rocket className="h-8 w-8 animate-pulse text-muted-foreground" />
      </div>
    );
  }

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

      {/* CRITICAL: SSH Key Prompt Warning */}
      <AlertCard variant="error" title="WATCH FOR: SSH Key Prompt">
        <div className="space-y-3">
          <p>
            <strong>Early in the installation</strong>, you&apos;ll see a prompt asking for your SSH public key:
          </p>
          <OutputPreview title="You'll see something like:" className="my-3">
            <pre className="text-muted-foreground whitespace-pre">{`════════════════════════════════════════
  SSH Key Setup
════════════════════════════════════════`}</pre>
            <p className="text-[oklch(0.78_0.16_75)] mt-2">Paste your public key: <span className="animate-pulse">_</span></p>
          </OutputPreview>
          <p>
            <strong className="text-foreground">This is when you paste the key you saved earlier!</strong>{" "}
            It&apos;s the one that starts with <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ssh-ed25519 AAAA...</code>
          </p>
          <p className="text-sm text-muted-foreground">
            If you miss this prompt or press Enter without pasting, you won&apos;t be able to connect as the{" "}
            <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ubuntu</code> user with your SSH key later.
            (You can fix this manually if needed.)
          </p>
        </div>
      </AlertCard>

      {/* The command */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">
          Paste this command in your SSH session
        </h2>

        {/* Pinned ref toggle (bd-31ps.8.2) */}
        <div className="rounded-lg border border-border/50 bg-card/50 p-4 space-y-3">
          <div className="flex items-start gap-3">
            <Checkbox
              id="pin-ref"
              checked={usePinnedRef}
              onCheckedChange={(checked) => handlePinnedRefToggle(checked === true)}
              className="mt-0.5"
            />
            <div className="flex-1 space-y-1">
              <label
                htmlFor="pin-ref"
                className="flex items-center gap-2 text-sm font-medium cursor-pointer"
              >
                <Pin className="h-4 w-4 text-muted-foreground" />
                Pin to specific version
              </label>
              <p className="text-xs text-muted-foreground">
                Use a specific commit or tag for reproducible installs across multiple machines.
              </p>
            </div>
          </div>

          {usePinnedRef && (
            <div className="ml-7 space-y-2">
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  value={refDraft}
                  onChange={(e) => handlePinnedRefChange(e.target.value)}
                  placeholder="main, v1.0.0, or commit SHA"
                  className="flex-1 rounded-md border border-input bg-background px-3 py-1.5 text-sm font-mono placeholder:text-muted-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
                />
              </div>
              <div className="flex items-start gap-1.5 text-xs text-muted-foreground">
                <Info className="h-3.5 w-3.5 mt-0.5 shrink-0" />
                <span>
                  Use <code className="rounded bg-muted px-1 py-0.5">main</code> for latest,
                  a tag like <code className="rounded bg-muted px-1 py-0.5">v1.0.0</code> for stable releases,
                  or a full SHA for exact reproducibility.
                </span>
              </div>
              {refDraft.trim() && !safePinnedRef && (
                <p className="text-xs text-[oklch(0.72_0.19_145)]">
                  Invalid ref format. Allowed characters: letters, numbers, <code className="rounded bg-muted px-1 py-0.5">.</code>,
                  <code className="rounded bg-muted px-1 py-0.5">_</code>, <code className="rounded bg-muted px-1 py-0.5">-</code>,
                  and <code className="rounded bg-muted px-1 py-0.5">/</code>. Falling back to <code className="rounded bg-muted px-1 py-0.5">main</code>.
                </p>
              )}
            </div>
          )}
        </div>

        {installModeLoaded ? (
          <CommandCard
            command={installCommand}
            description="Agent Flywheel installer one-liner"
            runLocation="vps"
            showCheckbox
            persistKey="run-flywheel-installer"
            className="border-2 border-primary/20"
          />
        ) : (
          <div className="rounded-lg border-2 border-primary/20 bg-card/30 p-4 text-sm text-muted-foreground">
            Loading your saved install mode...
          </div>
        )}
      </div>

      {/* Connection drop reassurance */}
      <AlertCard variant="info" icon={Wifi} title="What if my connection drops?">
        <div className="space-y-2">
          <p>
            <strong>Don&apos;t panic!</strong> If your SSH connection drops during installation:
          </p>
          <ol className="list-decimal list-inside space-y-1 text-sm">
            <li>The installer keeps running on the VPS</li>
            <li>Just SSH back in using the same command</li>
            <li>Run the installer command again — it will resume where it left off</li>
          </ol>
          <p className="text-sm text-muted-foreground">
            The installer is designed to be run multiple times safely. If anything fails,
            you can always re-run it.
          </p>
        </div>
      </AlertCard>

      {/* Transparency & trust */}
      <div className="flex gap-3 rounded-xl border border-[oklch(0.72_0.19_145/0.25)] bg-[oklch(0.72_0.19_145/0.05)] p-3 sm:p-4">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-[oklch(0.72_0.19_145/0.15)] sm:h-9 sm:w-9">
          <ShieldCheck className="h-4 w-4 text-[oklch(0.72_0.19_145)] sm:h-5 sm:w-5" />
        </div>
        <div className="min-w-0 space-y-2">
          <p className="text-[13px] font-medium leading-tight text-[oklch(0.82_0.12_145)] sm:text-sm">
            Fully transparent &amp; open source
          </p>
          <p className="text-[12px] leading-relaxed text-muted-foreground sm:text-[13px]">
            This script only runs on <strong className="text-foreground/80">your VPS</strong>, not your local computer.
            You can inspect every line before running it:
          </p>
          <div className="flex flex-wrap gap-2">
            <TrackedLink
              href={`https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/blob/${effectiveSourceRef}/install.sh`}
              trackingId="install-sh-source"
              className="inline-flex items-center gap-1.5 rounded-lg border border-[oklch(0.75_0.18_195/0.3)] bg-[oklch(0.75_0.18_195/0.1)] px-2.5 py-1.5 text-xs font-medium text-[oklch(0.75_0.18_195)] transition-colors hover:bg-[oklch(0.75_0.18_195/0.2)]"
            >
              <Code className="h-3 w-3" />
              View install.sh source
              <ExternalLink className="h-2.5 w-2.5" />
            </TrackedLink>
            <TrackedLink
              href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup"
              trackingId="github-repo"
              className="inline-flex items-center gap-1.5 rounded-lg border border-border/50 bg-card/50 px-2.5 py-1.5 text-xs font-medium text-muted-foreground transition-colors hover:border-primary/30 hover:text-foreground"
            >
              Full repository
              <ExternalLink className="h-2.5 w-2.5" />
            </TrackedLink>
          </div>
        </div>
      </div>

      {/* Time estimate */}
      <div className="flex items-center gap-2 text-muted-foreground">
        <Clock className="h-5 w-5" />
        <span>Takes about 10-15 minutes depending on your VPS speed</span>
      </div>

      {/* Command breakdown for curious users */}
      <DetailsSection summary="What does this command actually do? (technical breakdown)">
        <div className="space-y-3 text-sm">
          <p className="text-muted-foreground">
            Here&apos;s what each part of the command means:
          </p>
          <div className="space-y-4 font-mono text-xs">
            <div>
              <code className="text-[oklch(0.75_0.18_195)]">curl -fsSL &quot;https://...&quot;</code>
              <p className="mt-1 font-sans text-muted-foreground">
                Downloads the script from GitHub.{" "}
                <code className="text-foreground/80">-f</code> = fail on HTTP errors,{" "}
                <code className="text-foreground/80">-s</code> = silent mode,{" "}
                <code className="text-foreground/80">-S</code> = show errors,{" "}
                <code className="text-foreground/80">-L</code> = follow redirects.
              </p>
            </div>
            <div>
              <code className="text-[oklch(0.75_0.18_195)]">| bash</code>
              <p className="mt-1 font-sans text-muted-foreground">
                Pipes the downloaded script to bash (the shell) to run it.
              </p>
            </div>
            <div>
              <code className="text-[oklch(0.75_0.18_195)]">-s -- --yes</code>
              <p className="mt-1 font-sans text-muted-foreground">
                Passes <code className="text-foreground/80">--yes</code> to the script, meaning &quot;don&apos;t ask for confirmation, just install.&quot;
              </p>
            </div>
            <div>
              <code className="text-[oklch(0.75_0.18_195)]">--mode {installMode}</code>
              <p className="mt-1 font-sans text-muted-foreground">
                Tells the installer which mode to use based on your wizard selection.
              </p>
            </div>
            {usePinnedRef && safePinnedRef && (
              <div>
                <code className="text-[oklch(0.75_0.18_195)]">--ref &quot;{safePinnedRef}&quot;</code>
                <p className="mt-1 font-sans text-muted-foreground">
                  Keeps downloaded installer files pinned to <code className="text-foreground/80">{safePinnedRef}</code>.
                </p>
              </div>
            )}
          </div>
          <AlertCard variant="info" title="Is curl | bash safe?">
            <p className="text-sm">
              You&apos;re right to be cautious! Piping scripts directly to bash is only safe when you trust the source.
              This script is <strong>fully open source</strong> — you can read every line before running it.
              It only runs on your VPS, not your local computer.
            </p>
          </AlertCard>
        </div>
      </DetailsSection>

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
        <TrackedLink
          href={`https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/blob/${effectiveSourceRef}/install.sh`}
          trackingId="install-sh-source-inline"
          className="inline-flex items-center gap-1 font-medium text-primary hover:underline"
        >
          View install.sh source
          <ExternalLink className="h-3 w-3" />
        </TrackedLink>
      </div>

      {/* Installation output guide */}
      <AlertCard variant="info" title="Understanding the installation output">
        <div className="space-y-2 text-sm">
          <p>You&apos;ll see lots of text scrolling by. Here&apos;s what to look for:</p>
          <ul className="list-inside list-disc space-y-1">
            <li><span className="text-[oklch(0.72_0.19_145)] font-medium">✔ Green checkmarks</span> = Step completed successfully</li>
            <li><span className="text-[oklch(0.78_0.16_75)] font-medium">⚠ Yellow warnings</span> = Non-critical issue, installer continues</li>
            <li><span className="text-[oklch(0.65_0.22_25)] font-medium">✖ Red X</span> = Something failed, but installer will retry or skip</li>
          </ul>
          <p className="text-muted-foreground">
            Just wait for the final &quot;Installation complete&quot; message. If you see errors,
            you can always re-run the installer—it will retry failed steps.
          </p>
        </div>
      </AlertCard>

      {/* Success signs */}
      <OutputPreview title="You'll know it's done when you see:">
        <p className="text-[oklch(0.72_0.19_145)]">✔ Agent Flywheel installation complete!</p>
        <p className="text-muted-foreground">
          Please reconnect as: {reconnectCommand}
        </p>
      </OutputPreview>

      {/* Beginner Guide */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="What is this command doing?">
            This command downloads and runs a setup script that automatically installs
            everything you need on your VPS. Think of it like running an installer
            on your computer, but this one installs dozens of tools at once!
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
                is quite long, so make sure you copy the whole thing!
              </GuideStep>

              <GuideStep number={3} title="Paste and run">
                In your SSH terminal (where you&apos;re connected to the VPS), paste
                the command and press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd>.
                <br /><br />
                You&apos;ll see lots of text scrolling by. This is normal!
              </GuideStep>

              <GuideStep number={4} title="Wait patiently (10-15 minutes)">
                The installation takes time because it&apos;s downloading and installing
                many tools. You&apos;ll see progress messages scroll by:
                <OutputPreview title="What you'll see" className="mt-3">
                  <p className="text-[oklch(0.72_0.19_145)]">[1/8] Installing zsh + oh-my-zsh...</p>
                  <p className="text-[oklch(0.72_0.19_145)]">[2/8] Installing bun...</p>
                  <p className="text-[oklch(0.72_0.19_145)]">[3/8] Installing development tools...</p>
                  <p className="text-muted-foreground">... lots of download output ...</p>
                  <p className="text-[oklch(0.72_0.19_145)]">[8/8] Installing AI coding agents...</p>
                  <p className="text-[oklch(0.72_0.19_145)] font-medium mt-1">✔ Agent Flywheel installation complete!</p>
                </OutputPreview>
                <p className="mt-3">
                  <strong>Don&apos;t close the terminal!</strong> Let it run until you see
                  the green &quot;Installation complete&quot; message.
                </p>
              </GuideStep>
            </div>
          </GuideSection>

          <GuideSection title="What gets installed?">
            <p className="mb-3">
              The installer sets up a complete development environment including:
            </p>
            <ul className="space-y-2">
              <li>
                <strong>Modern shell (zsh):</strong> A better terminal experience with
                colors and suggestions
              </li>
              <li>
                <strong>Programming languages:</strong> JavaScript/TypeScript, Python,
                Rust, and Go
              </li>
              <li>
                <strong>AI coding assistants:</strong> Claude Code, Codex, and Gemini CLI
              </li>
              <li>
                <strong>Developer tools:</strong> Git interface, file searchers, and more
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
            command again. It will resume from where it stopped.
          </GuideCaution>

          <GuideSection title="If Installation Seems Stuck">
            <p className="mb-3">
              Installation can look &quot;stuck&quot; at certain points. Here&apos;s what&apos;s actually happening:
            </p>
            <ul className="space-y-3">
              <li>
                <strong>Stuck on &quot;Installing Rust...&quot;</strong> — Rust is a large download (~300MB).
                This step can take 2-5 minutes depending on your VPS speed. Just wait.
              </li>
              <li>
                <strong>Stuck on &quot;Setting up oh-my-zsh...&quot;</strong> — This step downloads
                plugins from GitHub. If GitHub is slow, it can take a minute. Wait it out.
              </li>
              <li>
                <strong>No output for 2+ minutes</strong> — Some steps don&apos;t show progress.
                If the terminal cursor is still blinking, it&apos;s still running. Wait.
              </li>
              <li>
                <strong>Actual error message appears</strong> — If you see red error text or
                &quot;Failed&quot;, SSH back in and run the install command again. The installer
                will skip completed steps and retry the failed one.
              </li>
            </ul>
            <GuideTip className="mt-4">
              The entire installation rarely takes more than 20 minutes. If it&apos;s been
              30+ minutes with no progress at all, SSH back in and check if the script
              is still running. If not, just run the install command again.
            </GuideTip>
          </GuideSection>
        </div>
      </SimplerGuide>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg" disableMotion>
          {isNavigating ? "Loading..." : "Installation finished"}
        </Button>
      </div>
    </div>
  );
}
