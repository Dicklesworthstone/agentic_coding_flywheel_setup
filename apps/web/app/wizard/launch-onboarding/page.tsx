"use client";

import { useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { PartyPopper, BookOpen, ExternalLink, Sparkles, ArrowRight, GraduationCap, Terminal, RefreshCw, FolderPlus, FolderOpen } from "lucide-react";
import { Card } from "@/components/ui/card";
import { CommandCard, CodeBlock } from "@/components/command-card";
import { AlertCard } from "@/components/alert-card";
import {
  getCompletedSteps,
  markStepComplete,
  setCompletedSteps,
  TOTAL_STEPS,
  validateStep,
} from "@/lib/wizardSteps";
import { trackConversion } from "@/lib/analytics";
import { Button } from "@/components/ui/button";
import Link from "next/link";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
} from "@/components/simpler-guide";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { Jargon } from "@/components/jargon";
import { formatSshTarget } from "@/lib/commandBuilder";
import { useSSHUsername, useVPSIP } from "@/lib/userPreferences";
import { withCurrentSearch } from "@/lib/utils";
import { CommandBuilderPanel } from "@/components/command-builder-panel";

// Confetti colors
const CONFETTI_COLORS = [
  "oklch(0.75 0.18 195)", // cyan
  "oklch(0.78 0.16 75)",  // amber
  "oklch(0.7 0.2 330)",   // magenta
  "oklch(0.72 0.19 145)", // green
];

interface ConfettiParticleData {
  id: number;
  delay: number;
  left: number;
  color: string;
  size: number;
  rotation: number;
  duration: number;
  isRound: boolean;
}

const CONFETTI_PARTICLES: ConfettiParticleData[] = Array.from({ length: 50 }, (_, i) => {
  const seed = i + 1;

  return {
    id: i,
    delay: (seed * 97) % 1000,
    left: (seed * 37) % 100,
    color: CONFETTI_COLORS[seed % CONFETTI_COLORS.length],
    size: 6 + ((seed * 13) % 7),
    rotation: (seed * 137) % 360,
    duration: 2500 + ((seed * 101) % 1500),
    isRound: seed % 3 === 0,
  };
});

// Confetti particle component - all random values passed as props for deterministic rendering
function ConfettiParticle({ delay, left, color, size, rotation, duration, isRound }: Omit<ConfettiParticleData, 'id'>) {
  return (
    <div
      className="pointer-events-none fixed animate-confetti-fall"
      style={{
        left: `${left}%`,
        top: "-20px",
        animationDelay: `${delay}ms`,
        animationDuration: `${duration}ms`,
      }}
    >
      <div
        style={{
          width: size,
          height: size,
          backgroundColor: color,
          transform: `rotate(${rotation}deg)`,
          borderRadius: isRound ? "50%" : "2px",
        }}
      />
    </div>
  );
}

export default function LaunchOnboardingStep() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [isUnlocked, setIsUnlocked] = useState(false);
  const hasStatusCheckHandoff = searchParams?.get("handoff") === "status-check";

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "launch_onboarding",
    stepNumber: 13,
    stepTitle: "Launch Onboarding",
  });

  // Get user's VPS IP for reconnection instructions
  const [vpsIP] = useVPSIP();
  const [sshUsername, , sshUsernameLoaded] = useSSHUsername();
  const displayIP = vpsIP || "YOUR_VPS_IP";
  const effectiveUsername = sshUsername.trim() || "ubuntu";
  const userTarget = formatSshTarget(effectiveUsername, displayIP);
  const homeDir = effectiveUsername === "root" ? "/root" : `/home/${effectiveUsername}`;
  const sshConfigSnippet = `Host myserver\n    HostName ${displayIP}\n    User ${effectiveUsername}\n    IdentityFile ~/.ssh/acfs_ed25519`;

  // Only persist full completion when the user actually reached the final step
  // through the normal flow. A direct visit/bookmark should not unlock the wizard.
  useEffect(() => {
    const completedSteps = getCompletedSteps();
    const canAccess =
      hasStatusCheckHandoff ||
      (completedSteps.includes(12) && validateStep(12).valid);

    if (!canAccess) {
      router.replace(withCurrentSearch("/wizard/status-check"));
      return;
    }

    markComplete({ wizard_completed: true });
    markStepComplete(13);
    const allSteps = Array.from({ length: TOTAL_STEPS }, (_, i) => i + 1);
    setCompletedSteps(allSteps);
    // Use setTimeout to avoid the ESLint set-state-in-effect rule, since
    // this unlock is logically part of the navigation guard check above.
    setTimeout(() => setIsUnlocked(true), 0);
  }, [hasStatusCheckHandoff, markComplete, router]);

  if (!isUnlocked || !sshUsernameLoaded) {
    return (
      <div className="flex items-center justify-center py-12">
        <RefreshCw className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Confetti */}
      <div className="pointer-events-none fixed inset-0 z-50 overflow-hidden" aria-hidden="true">
        {CONFETTI_PARTICLES.map((p) => (
          <ConfettiParticle
            key={p.id}
            delay={p.delay}
            left={p.left}
            color={p.color}
            size={p.size}
            rotation={p.rotation}
            duration={p.duration}
            isRound={p.isRound}
          />
        ))}
      </div>

      {/* Celebration header */}
      <div className="space-y-4 text-center">
        <div className="flex justify-center">
          <div className="relative rounded-full bg-[oklch(0.72_0.19_145/0.2)] p-4 shadow-lg shadow-[oklch(0.72_0.19_145/0.3)]">
            <PartyPopper className="h-12 w-12 text-[oklch(0.72_0.19_145)]" />
            <Sparkles className="absolute -right-1 -top-1 h-6 w-6 text-[oklch(0.78_0.16_75)] animate-pulse" />
          </div>
        </div>
        <h1 className="bg-gradient-to-r from-[oklch(0.72_0.19_145)] via-primary to-[oklch(0.7_0.2_330)] bg-clip-text text-3xl font-bold tracking-tight text-transparent">
          Congratulations! You&apos;re all set up!
        </h1>
        <p className="text-lg text-muted-foreground">
          Your <Jargon term="vps">VPS</Jargon> is now a powerful coding environment ready for <Jargon term="agentic">AI-assisted</Jargon> development.
        </p>
      </div>

      {/* Powerlevel10k Configuration Warning */}
      <AlertCard variant="warning" title="First login: You may see a configuration wizard">
        <div className="space-y-2 text-sm">
          <p>
            When you first connect to your VPS after installation, you might see the{" "}
            <strong className="text-foreground">Powerlevel10k configuration wizard</strong> — a colorful
            terminal setup screen.
          </p>
          <p className="text-muted-foreground">
            <strong className="text-foreground">Don&apos;t worry, this is optional!</strong> You can press{" "}
            <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">q</kbd> to skip it, or follow
            the prompts to customize your terminal appearance. ACFS already configured sensible defaults,
            so skipping is perfectly fine.
          </p>
        </div>
      </AlertCard>

      {/* Personalized command quick-reference */}
      <CommandBuilderPanel />

      {/* Important: Authenticate Your AI Tools First */}
      <Card className="border-[oklch(0.78_0.16_75/0.3)] bg-[oklch(0.78_0.16_75/0.08)] p-6">
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <Sparkles className="h-6 w-6 text-[oklch(0.78_0.16_75)]" />
            <h2 className="text-xl font-semibold">First: Authenticate Your AI Tools</h2>
          </div>
          <p className="text-muted-foreground">
            <strong className="text-foreground">Before using AI coding assistants, you need to authenticate them.</strong>{" "}
            This is a one-time setup that links your subscriptions:
          </p>
          <div className="space-y-3">
            <div className="flex gap-3">
              <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-[oklch(0.78_0.16_75)] text-[oklch(0.15_0.02_75)] font-bold text-sm">1</div>
              <div className="space-y-3">
                <p className="font-medium">Claude Code</p>
                <CommandCard
                  command="claude"
                  description="Follow the prompts. If it prints a URL, open it on your laptop to log in."
                  runLocation="vps"
                />
                {/* Detailed OAuth flow explanation */}
                <div className="rounded-lg border border-[oklch(0.78_0.16_75/0.3)] bg-[oklch(0.78_0.16_75/0.05)] p-3 text-sm space-y-2">
                  <p className="font-medium text-[oklch(0.78_0.16_75)]">How the authentication works:</p>
                  <ol className="list-decimal list-inside space-y-1 text-muted-foreground">
                    <li>The terminal shows a URL like <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">https://claude.ai/oauth/...</code></li>
                    <li><strong className="text-foreground">Copy that URL</strong> and paste it into your web browser (on your laptop)</li>
                    <li>Log in to Claude in your browser</li>
                    <li>The browser shows a <strong className="text-foreground">code</strong> (like &quot;ABCD-1234&quot;)</li>
                    <li><strong className="text-foreground">Copy that code</strong> and paste it back into your <strong className="text-foreground">terminal window</strong> (the same one running Claude)</li>
                  </ol>
                  <p className="text-xs text-muted-foreground mt-2">
                    When your browser says &quot;Paste this into Claude Code&quot; — that means paste the code into the terminal window where you typed <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">claude</code>.
                  </p>
                </div>
              </div>
            </div>
            <div className="flex gap-3">
              <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-[oklch(0.78_0.16_75)] text-[oklch(0.15_0.02_75)] font-bold text-sm">2</div>
              <div>
                <p className="font-medium">Codex CLI (if using OpenAI)</p>
                <CommandCard
                  command="codex login --device-auth"
                  description="Recommended on a VPS. It uses device auth instead of the localhost callback flow."
                  runLocation="vps"
                />
              </div>
            </div>
            <div className="flex gap-3">
              <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-[oklch(0.78_0.16_75)] text-[oklch(0.15_0.02_75)] font-bold text-sm">3</div>
              <div>
                <p className="font-medium">Gemini CLI (optional)</p>
                <CommandCard
                  command='export GEMINI_API_KEY="your-gemini-api-key"'
                  description="Recommended on a headless VPS. Add the key to ~/.gemini/.env or your shell config, then run gemini."
                  runLocation="vps"
                />
              </div>
            </div>
          </div>
          <GuideTip>
            After authenticating, you can use the shortcuts (vibe mode):{" "}
            <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">cc</code> (Claude),{" "}
            <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">cod</code> (Codex),{" "}
            <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">gmi</code> (Gemini).
          </GuideTip>
        </div>
      </Card>

      {/* Learning Hub CTA - Primary */}
      <Card className="border-primary/20 bg-primary/5 p-6">
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <GraduationCap className="h-6 w-6 text-primary" />
            <h2 className="text-xl font-semibold">Continue Your Learning Journey</h2>
          </div>
          <p className="text-muted-foreground">
            Master your new environment with 9 guided lessons covering Linux basics,
            tmux sessions, AI agents, and advanced workflows.
          </p>
          <Link href="/learn" onClick={() => trackConversion('learning_hub_started')}>
            <Button size="lg" className="w-full sm:w-auto">
              <BookOpen className="mr-2 h-4 w-4" />
              Start Learning Hub
            </Button>
          </Link>
          <div className="flex items-center gap-2 pt-2 text-sm text-muted-foreground">
            <Terminal className="h-4 w-4" />
            <span>
              Prefer the terminal? Run{" "}
              <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">onboard</code>{" "}
              for the CLI version.
            </span>
          </div>
        </div>
      </Card>

      {/* Your Daily Workflow - Key pattern for ongoing use */}
      <Card className="border-[oklch(0.78_0.16_75/0.3)] bg-[oklch(0.78_0.16_75/0.05)] p-6">
        <div className="space-y-4">
          <div className="flex items-center gap-2">
            <RefreshCw className="h-5 w-5 text-[oklch(0.78_0.16_75)]" />
            <h2 className="text-xl font-semibold">Your Daily Workflow</h2>
          </div>
          <p className="text-muted-foreground">
            Here&apos;s what working with your VPS looks like day-to-day:
          </p>
        </div>

        <div className="mt-6 space-y-6">
          <div className="flex gap-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[oklch(0.78_0.16_75)] text-[oklch(0.15_0.02_75)] font-bold">
              1
            </div>
            <div className="space-y-2">
              <h3 className="font-medium">Connect to your VPS</h3>
              <CommandCard
                command={`ssh -i ~/.ssh/acfs_ed25519 ${userTarget}`}
                windowsCommand={`ssh -i $HOME\\.ssh\\acfs_ed25519 ${userTarget}`}
                runLocation="local"
              />
              <p className="text-sm text-muted-foreground">Open your terminal and SSH in.</p>
            </div>
          </div>

          <div className="flex gap-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[oklch(0.78_0.16_75)] text-[oklch(0.15_0.02_75)] font-bold">
              2
            </div>
            <div className="space-y-2">
              <h3 className="font-medium">Resume or create a session</h3>
              <div className="space-y-2">
                <CommandCard command="ntm list" description="See existing sessions" runLocation="vps" />
              </div>
              <div className="flex flex-col gap-2 sm:flex-row sm:gap-4">
                <div className="flex-1">
                  <CommandCard command="ntm attach myproject" description="Resume a session" runLocation="vps" />
                </div>
                <div className="flex-1">
                  <CommandCard command="ntm new myproject" description="Or create new" runLocation="vps" />
                </div>
              </div>
            </div>
          </div>

          <div className="flex gap-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[oklch(0.78_0.16_75)] text-[oklch(0.15_0.02_75)] font-bold">
              3
            </div>
            <div className="space-y-2">
              <h3 className="font-medium">Start coding with AI</h3>
              <CommandCard command="cc" description="Launch Claude Code" runLocation="vps" />
            </div>
          </div>

          <div className="flex gap-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[oklch(0.78_0.16_75)] text-[oklch(0.15_0.02_75)] font-bold">
              4
            </div>
            <div className="space-y-2">
              <h3 className="font-medium">When you&apos;re done for the day</h3>
              <div className="flex flex-col gap-3 sm:flex-row sm:gap-4">
                <div className="flex-1 rounded-lg border border-border/50 bg-card/50 p-3">
                  <p className="text-sm text-muted-foreground mb-2">Detach from session:</p>
                  <div className="flex items-center gap-1.5">
                    <kbd className="rounded bg-muted px-2 py-1 font-mono text-sm">Ctrl</kbd>
                    <span className="text-muted-foreground">+</span>
                    <kbd className="rounded bg-muted px-2 py-1 font-mono text-sm">A</kbd>
                    <span className="text-muted-foreground mx-1">then</span>
                    <kbd className="rounded bg-muted px-2 py-1 font-mono text-sm">D</kbd>
                  </div>
                </div>
                <div className="flex-1">
                  <CommandCard command="exit" description="Disconnect from VPS" runLocation="vps" />
                </div>
              </div>
              <p className="text-sm text-muted-foreground">
                Your session keeps running! Come back tomorrow and everything is exactly where you left it.
              </p>
            </div>
          </div>
        </div>

        <div className="mt-6 rounded-lg border border-[oklch(0.78_0.16_75/0.3)] bg-[oklch(0.78_0.16_75/0.1)] p-4 text-center">
          <p className="text-sm font-medium">
            💡 <strong>Remember:</strong> Connect → Session → Code → Detach
          </p>
        </div>
      </Card>

      {/* Starting a New Project - How to begin real work */}
      <Card className="border-[oklch(0.75_0.18_195/0.3)] bg-[oklch(0.75_0.18_195/0.05)] p-6">
        <div className="space-y-4">
          <div className="flex items-center gap-2">
            <FolderPlus className="h-5 w-5 text-[oklch(0.75_0.18_195)]" />
            <h2 className="text-xl font-semibold">Starting a New Project</h2>
          </div>
          <p className="text-muted-foreground">
            Ready to build something? Here&apos;s the pattern:
          </p>
        </div>

        <div className="mt-6 space-y-4">
          <div className="space-y-2">
            <h3 className="font-medium">1. Create a session for your project</h3>
            <CommandCard command="ntm new my-awesome-app" runLocation="vps" />
            <p className="text-sm text-muted-foreground">
              This creates a persistent workspace named &quot;my-awesome-app&quot;.
            </p>
          </div>

          <div className="space-y-2">
            <h3 className="font-medium">2. Create and navigate to a project folder</h3>
            <CommandCard command="mkdir /data/projects/my-awesome-app && cd /data/projects/my-awesome-app" runLocation="vps" />
          </div>

          <div className="space-y-2">
            <h3 className="font-medium">3. Start Claude and describe your project</h3>
            <CommandCard command="cc" runLocation="vps" />
            <p className="text-sm text-muted-foreground">
              Tell Claude what you want to build. For example:
            </p>
            <div className="rounded-lg bg-muted px-4 py-3 font-mono text-sm">
              &quot;Create a React app with TypeScript that shows a todo list&quot;
            </div>
          </div>

          <GuideTip>
            Claude will set up the project structure, install dependencies, and start
            building. You can guide it step by step or give it the whole vision at once.
          </GuideTip>
        </div>
      </Card>

      {/* Finding Your Way Around - Filesystem orientation */}
      <Card className="border-[oklch(0.7_0.2_330/0.3)] bg-[oklch(0.7_0.2_330/0.05)] p-6">
        <div className="flex items-center gap-2 mb-4">
          <FolderOpen className="h-5 w-5 text-[oklch(0.7_0.2_330)]" />
          <h2 className="text-xl font-semibold">Finding Your Way Around</h2>
        </div>

        <div className="space-y-4">
          <div className="space-y-2">
            <p className="font-medium">Your home folder</p>
            <p className="text-sm text-muted-foreground">
              Everything you create lives in <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">{homeDir}</code> (or just <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">~</code>).
            </p>
            <CommandCard command="cd ~" description="Go to your home folder" runLocation="vps" />
          </div>

          <div className="space-y-2">
            <p className="font-medium">See what&apos;s here</p>
            <CommandCard command="lsd" description="List files (with icons!)" runLocation="vps" />
            <p className="text-sm text-muted-foreground">
              We installed <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">lsd</code> — a prettier version of <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">ls</code>.
            </p>
          </div>

          <div className="space-y-2">
            <p className="font-medium">Navigate into a folder</p>
            <div className="flex flex-col gap-2 sm:flex-row sm:gap-4">
              <div className="flex-1">
                <CommandCard command="cd /data/projects" description="Enter a folder" runLocation="vps" />
              </div>
              <div className="flex-1">
                <CommandCard command="cd .." description="Go back up" runLocation="vps" />
              </div>
            </div>
          </div>

          <div className="space-y-2">
            <p className="font-medium">Find files fast</p>
            <div className="flex flex-col gap-2 sm:flex-row sm:gap-4">
              <div className="flex-1">
                <CommandCard command='rg "search term"' description="Search file contents" runLocation="vps" />
              </div>
              <div className="flex-1">
                <CommandCard command="fd filename" description="Find files by name" runLocation="vps" />
              </div>
            </div>
          </div>

          <GuideTip>
            Pro tip: Use <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">z</code> (zoxide) to jump to folders you&apos;ve visited before.
            Just type <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">z proj</code> to jump to your projects folder!
          </GuideTip>
        </div>
      </Card>

      {/* Your First 5 Minutes */}
      <Card className="border-primary/30 bg-primary/5 p-6">
        <div className="space-y-4">
          <div className="flex items-center gap-2">
            <Sparkles className="h-5 w-5 text-[oklch(0.78_0.16_75)]" />
            <h2 className="text-xl font-semibold">Your First 5 Minutes</h2>
          </div>
          <p className="text-muted-foreground">
            Let&apos;s make sure everything works with a quick test run.
          </p>
        </div>

        <div className="mt-6 space-y-6">
          <div className="flex gap-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground font-bold">
              1
            </div>
            <div className="space-y-2">
              <h3 className="font-medium">Create a project folder</h3>
              <CommandCard command="mkdir -p /data/projects/my_first_project && cd /data/projects/my_first_project" runLocation="vps" />
            </div>
          </div>

          <div className="flex gap-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground font-bold">
              2
            </div>
            <div className="space-y-2">
              <h3 className="font-medium">Authenticate Claude</h3>
              <CommandCard command="claude" runLocation="vps" />
              <p className="text-sm text-muted-foreground">
                The terminal will display a URL. Copy it and open in your laptop&apos;s
                browser to log in, then return to your terminal.
              </p>
            </div>
          </div>

          <div className="flex gap-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground font-bold">
              3
            </div>
            <div className="space-y-2">
              <h3 className="font-medium">Start Claude Code</h3>
              <CommandCard command="cc" runLocation="vps" />
              <p className="text-sm text-muted-foreground">
                After authenticating, this launches Claude Code.
              </p>
            </div>
          </div>

          <div className="flex gap-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground font-bold">
              4
            </div>
            <div className="space-y-2">
              <h3 className="font-medium">Your first prompt</h3>
              <p className="text-sm text-muted-foreground">
                In the Claude prompt, type:
              </p>
              <div className="rounded-lg bg-muted px-4 py-3 font-mono text-sm">
                Create a simple Python script that prints &quot;Hello from AI!&quot; and run it
              </div>
            </div>
          </div>

          <div className="flex gap-4">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground font-bold">
              5
            </div>
            <div className="space-y-2">
              <h3 className="font-medium">Watch the magic!</h3>
              <p className="text-sm text-muted-foreground">
                Claude will:
              </p>
              <ul className="space-y-1 text-sm text-muted-foreground">
                <li>✓ Create a file called <span className="font-mono">hello.py</span></li>
                <li>✓ Write the Python code</li>
                <li>✓ Run the script for you</li>
                <li>✓ Show &quot;Hello from AI!&quot; in the output</li>
              </ul>
            </div>
          </div>
        </div>

        <div className="mt-6 rounded-lg border border-[oklch(0.72_0.19_145/0.3)] bg-[oklch(0.72_0.19_145/0.1)] p-4 text-center">
          <p className="text-lg font-medium">
            🎉 Congratulations! You just used AI to write and run code!
          </p>
        </div>
      </Card>

      {/* Getting Back In */}
      <Card className="border-[oklch(0.75_0.18_195/0.3)] bg-[oklch(0.75_0.18_195/0.05)] p-6">
        <div className="flex items-center gap-3 mb-4">
          <Terminal className="h-6 w-6 text-[oklch(0.75_0.18_195)]" />
          <h2 className="text-xl font-semibold">Getting Back In</h2>
        </div>

        <p className="text-muted-foreground mb-4">
          Closed your terminal? Here&apos;s how to reconnect:
        </p>

        <div className="space-y-4">
          <div>
            <h3 className="font-medium">1. Open your terminal app</h3>
            <p className="text-sm text-muted-foreground">
              Ghostty, WezTerm, or Windows Terminal
            </p>
          </div>

          <div>
            <h3 className="font-medium">2. Connect to your VPS</h3>
            <CommandCard
              command={`ssh -i ~/.ssh/acfs_ed25519 ${userTarget}`}
              windowsCommand={`ssh -i $HOME\\.ssh\\acfs_ed25519 ${userTarget}`}
              runLocation="local"
            />
          </div>

          <div className="space-y-2">
            <h3 className="font-medium">3. Resume your session (if using NTM)</h3>
            <CommandCard command="ntm list" description="See your sessions" runLocation="vps" />
            <CommandCard command="ntm attach myproject" description="Resume a session" runLocation="vps" />
            <p className="text-sm text-muted-foreground mt-2">
              This brings back exactly where you left off — including any running Claude sessions!
            </p>
          </div>
        </div>

        {/* SSH Config tip */}
        <details className="mt-6 group">
          <summary className="cursor-pointer font-medium text-[oklch(0.75_0.18_195)] hover:text-[oklch(0.65_0.18_195)] transition-colors rounded outline-none focus-visible:ring-2 focus-visible:ring-ring">
            💡 Pro tip: Set up SSH config for easier access
          </summary>
          <div className="mt-4 space-y-4 pl-6 border-l-2 border-[oklch(0.75_0.18_195/0.3)]">
            <p className="text-sm text-muted-foreground">
              Add this to your local <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">~/.ssh/config</code> file:
            </p>
            <CodeBlock code={sshConfigSnippet} language="ssh-config" />
            <p className="text-sm text-muted-foreground">
              Then just type: <code className="rounded bg-muted px-2 py-1 font-mono text-xs">ssh myserver</code>
            </p>
          </div>
        </details>

        {/* Windows Terminal tip */}
        <div className="mt-6 rounded-lg border border-[oklch(0.75_0.18_195/0.3)] bg-[oklch(0.75_0.18_195/0.1)] p-4">
          <Link
            href={withCurrentSearch("/wizard/windows-terminal-setup?from=launch-onboarding")}
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
      </Card>

      {/* What you can do now */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">What you can do now</h2>
        <div className="grid gap-4 sm:grid-cols-2">
          <Card className="p-4">
            <h3 className="mb-2 font-medium">Start Claude Code</h3>
            <p className="mb-3 text-sm text-muted-foreground">
              Launch your AI coding assistant
            </p>
            <code className="rounded bg-muted px-2 py-1 text-sm">cc</code>
          </Card>
          <Card className="p-4">
            <h3 className="mb-2 font-medium">Use <Jargon term="tmux">tmux</Jargon> with <Jargon term="ntm">ntm</Jargon></h3>
            <p className="mb-3 text-sm text-muted-foreground">
              Manage terminal sessions
            </p>
            <code className="rounded bg-muted px-2 py-1 text-sm">ntm new myproject</code>
          </Card>
          <Card className="p-4">
            <h3 className="mb-2 font-medium">Search with <Jargon term="ripgrep">ripgrep</Jargon></h3>
            <p className="mb-3 text-sm text-muted-foreground">
              Fast code search
            </p>
            <code className="rounded bg-muted px-2 py-1 text-sm">rg &quot;pattern&quot;</code>
          </Card>
          <Card className="p-4">
            <h3 className="mb-2 font-medium"><Jargon term="git">Git</Jargon> with <Jargon term="lazygit">lazygit</Jargon></h3>
            <p className="mb-3 text-sm text-muted-foreground">
              Visual git interface
            </p>
            <code className="rounded bg-muted px-2 py-1 text-sm">lazygit</code>
          </Card>
        </div>
      </div>

      {/* Manual editing escape hatch */}
      <Card className="border-border/50 bg-card/50 p-4 backdrop-blur-sm">
        <details className="group">
          <summary className="cursor-pointer font-semibold text-foreground hover:text-primary transition-colors rounded outline-none focus-visible:ring-2 focus-visible:ring-ring">
            How to edit files manually (when AI gets something wrong)
          </summary>
          <div className="mt-4 space-y-6 pl-4 border-l-2 border-primary/20">
            <div>
              <h3 className="font-medium">Quick edits with nano</h3>
              <p className="mt-2 text-sm text-muted-foreground">
                For simple fixes, nano is already installed on your VPS:
              </p>
              <CommandCard command="nano hello.py" description="Open a file in nano" runLocation="vps" />
              <p className="mt-3 text-sm text-muted-foreground">Nano shortcuts:</p>
              <ul className="mt-2 list-disc list-inside space-y-1 text-sm text-muted-foreground">
                <li>
                  <kbd className="rounded bg-muted px-1 py-0.5 font-mono text-xs">Ctrl</kbd> +{" "}
                  <kbd className="rounded bg-muted px-1 py-0.5 font-mono text-xs">O</kbd>, then{" "}
                  <kbd className="rounded bg-muted px-1 py-0.5 font-mono text-xs">Enter</kbd> — Save
                </li>
                <li>
                  <kbd className="rounded bg-muted px-1 py-0.5 font-mono text-xs">Ctrl</kbd> +{" "}
                  <kbd className="rounded bg-muted px-1 py-0.5 font-mono text-xs">X</kbd> — Exit
                </li>
                <li>
                  <kbd className="rounded bg-muted px-1 py-0.5 font-mono text-xs">Ctrl</kbd> +{" "}
                  <kbd className="rounded bg-muted px-1 py-0.5 font-mono text-xs">W</kbd> — Search
                </li>
              </ul>
            </div>

            <div>
              <h3 className="font-medium">Full IDE with Cursor (recommended)</h3>
              <p className="mt-2 text-sm text-muted-foreground">
                Cursor is an AI-native code editor with great remote editing support (like VS Code Remote SSH).
              </p>
              <ol className="mt-2 list-decimal list-inside space-y-1 text-sm text-muted-foreground">
                <li>
                  Download Cursor from{" "}
                  <a
                    href="https://cursor.com"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1 font-medium text-primary hover:underline"
                  >
                    cursor.com
                    <ExternalLink className="h-3 w-3" />
                  </a>
                </li>
                <li>
                  Open the command palette:{" "}
                  <kbd className="rounded bg-muted px-1 py-0.5 font-mono text-xs">Cmd</kbd>/
                  <kbd className="rounded bg-muted px-1 py-0.5 font-mono text-xs">Ctrl</kbd> +{" "}
                  <kbd className="rounded bg-muted px-1 py-0.5 font-mono text-xs">Shift</kbd> +{" "}
                  <kbd className="rounded bg-muted px-1 py-0.5 font-mono text-xs">P</kbd>
                </li>
                <li>Search: <span className="font-mono">Remote-SSH: Connect to Host</span></li>
                <li>
                  Connect to <span className="font-mono">{userTarget}</span> (it will use your SSH key)
                </li>
              </ol>
              <GuideTip className="mt-4">
                Cursor is built on VS Code, so extensions work the same way — including Remote SSH.
                You get a full IDE experience (syntax highlighting, file explorer, extensions) while editing files
                directly on your VPS.
              </GuideTip>
            </div>
          </div>
        </details>
      </Card>

      {/* Resources */}
      <Card className="p-4">
        <div className="flex items-start gap-3">
          <BookOpen className="mt-0.5 h-5 w-5 text-muted-foreground" />
          <div>
            <h3 className="font-medium">Learn more</h3>
            <ul className="mt-2 space-y-1 text-sm">
              <li>
                <a
                  href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1 text-primary hover:underline"
                >
                  Agent Flywheel GitHub Repository
                  <ExternalLink className="h-3 w-3" />
                </a>
              </li>
              <li>
                <a
                  href="https://docs.anthropic.com/claude-code"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1 text-primary hover:underline"
                >
                  Claude Code Documentation
                  <ExternalLink className="h-3 w-3" />
                </a>
              </li>
            </ul>
          </div>
        </div>
      </Card>

      {/* Beginner Guide */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="What just happened?">
            You&apos;ve just finished setting up a professional-grade cloud development
            environment! Your VPS now has:
            <ul className="mt-3 space-y-2">
              <li>
                <strong>A powerful shell (zsh):</strong> A modern command-line interface
                with auto-suggestions and beautiful colors
              </li>
              <li>
                <strong>AI coding assistants:</strong> Claude Code, Codex, and Gemini CLI
                are ready to help you write code
              </li>
              <li>
                <strong>Development tools:</strong> Fast search (ripgrep), git interface
                (lazygit), and more
              </li>
              <li>
                <strong>Programming languages:</strong> JavaScript/TypeScript (bun),
                Python (uv), Rust, and Go
              </li>
            </ul>
          </GuideExplain>

          <GuideExplain term="What is tmux and ntm?">
            <p>
              <strong>The problem:</strong> When you SSH into your VPS and then close your laptop
              or lose internet, your terminal session dies. Any running commands stop.
            </p>
            <p className="mt-3">
              <strong>The solution:</strong> <Jargon term="tmux">tmux</Jargon> creates &quot;sessions&quot; that keep
              running on the VPS even when you disconnect. Your processes continue regardless of your connection state.
            </p>
            <p className="mt-3">
              <strong>NTM</strong> (Named Tmux Manager) makes tmux easier. Instead of cryptic commands,
              you get simple ones:
            </p>
            <ul className="mt-2 list-disc list-inside space-y-1 text-sm text-muted-foreground">
              <li><code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ntm new myproject</code> — Start a new session</li>
              <li><code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ntm attach myproject</code> — Resume a session</li>
              <li><code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ntm list</code> — See all your sessions</li>
            </ul>
            <p className="mt-3 text-sm">
              This is why you can start a Claude task, close your laptop, go to bed, and come back
              to find it completed. The session keeps running on the VPS.
            </p>
          </GuideExplain>

          <GuideSection title="Understanding the Tools">
            <div className="space-y-4">
              <div>
                <p className="font-medium text-foreground">cc (Claude Code)</p>
                <p className="text-sm text-muted-foreground">
                  This is your primary AI coding assistant. Type <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">cc</code>
                  in any project folder and Claude will help you write, debug, and improve
                  your code. It can read your files, make changes, run tests, and more.
                </p>
              </div>
              <div>
                <p className="font-medium text-foreground">ntm (Named Tmux Manager)</p>
                <p className="text-sm text-muted-foreground">
                  This manages your terminal &quot;sessions&quot;. When you run{" "}
                  <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ntm new myproject</code>,
                  it creates a persistent workspace that stays running even if you disconnect.
                  Perfect for long-running tasks!
                </p>
              </div>
              <div>
                <p className="font-medium text-foreground">rg (ripgrep)</p>
                <p className="text-sm text-muted-foreground">
                  Ultra-fast code search. Type <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">rg &quot;searchterm&quot;</code>
                  to find any text across all your files in milliseconds. Essential for
                  navigating large codebases.
                </p>
              </div>
              <div>
                <p className="font-medium text-foreground">lazygit</p>
                <p className="text-sm text-muted-foreground">
                  A visual interface for Git. Much easier than remembering git commands!
                  Type <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">lazygit</code>
                  in any git repository to stage, commit, push, and manage branches visually.
                </p>
              </div>
            </div>
          </GuideSection>

          <GuideSection title="Your First Steps">
            <div className="space-y-4">
              <GuideStep number={1} title="Run the onboarding tutorial">
                Type <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">onboard</code>
                and press Enter. This interactive tutorial teaches you the basics of your
                new environment.
              </GuideStep>

              <GuideStep number={2} title="Create your first project session">
                Type <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ntm new hello-world</code>
                to create a dedicated workspace for a test project.
              </GuideStep>

              <GuideStep number={3} title="Try Claude Code">
                In your project folder, type <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">cc</code>
                and ask it to &quot;create a simple hello world script in Python&quot;. Watch
                the magic happen!
              </GuideStep>
            </div>
          </GuideSection>

          <GuideTip>
            <strong>Bookmark this page!</strong> You can always come back here to review
            the basic commands. Once you&apos;re comfortable with these basics, continue to
            Part Two to learn the advanced multi-agent workflow that makes this setup truly
            powerful.
          </GuideTip>
        </div>
      </SimplerGuide>

      {/* Continue to Part Two */}
      <Card className="border-2 border-[oklch(0.7_0.2_330/0.3)] bg-gradient-to-r from-[oklch(0.7_0.2_330/0.05)] to-[oklch(0.75_0.18_195/0.05)] p-6">
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <Sparkles className="h-6 w-6 text-[oklch(0.7_0.2_330)]" />
            <h2 className="text-xl font-semibold">Ready for the Advanced Workflow?</h2>
          </div>
          <p className="text-muted-foreground">
            After completing the Learning Hub basics, dive into the powerful multi-agent
            workflow that lets you build production-ready software at incredible speed.
            You&apos;ll learn how to orchestrate multiple AI agents working in parallel,
            use the &quot;best of all worlds&quot; planning technique, and run agent swarms
            that build features while you sleep.
          </p>
          <div className="flex flex-col gap-3 sm:flex-row">
            <Link href="/learn" onClick={() => trackConversion('learning_hub_started')}>
              <Button variant="outline" size="lg" className="w-full sm:w-auto">
                <BookOpen className="mr-2 h-4 w-4" />
                Start with Basics
              </Button>
            </Link>
            <Link href="/workflow">
              <Button size="lg" className="w-full sm:w-auto">
                Skip to Advanced
                <ArrowRight className="ml-2 h-4 w-4" />
              </Button>
            </Link>
          </div>
        </div>
      </Card>

      {/* Final message */}
      <div className="rounded-lg border-2 border-dashed border-primary/30 p-6 text-center">
        <p className="text-lg font-medium">
          Happy coding!
        </p>
        <p className="mt-1 text-muted-foreground">
          Your agentic coding flywheel is ready to spin.
        </p>
      </div>
    </div>
  );
}
