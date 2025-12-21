"use client";

import { useEffect } from "react";
import { PartyPopper, Rocket, BookOpen, ExternalLink, Sparkles, ArrowRight } from "lucide-react";
import { Card } from "@/components/ui/card";
import { CommandCard } from "@/components/command-card";
import { markStepComplete, setCompletedSteps, TOTAL_STEPS } from "@/lib/wizardSteps";
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

export default function LaunchOnboardingPage() {
  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "launch_onboarding",
    stepNumber: 10,
    stepTitle: "Launch Onboarding",
  });

  // Mark all steps complete on reaching this page
  useEffect(() => {
    markComplete({ wizard_completed: true });
    markStepComplete(10);
    // Mark all steps as completed
    const allSteps = Array.from({ length: TOTAL_STEPS }, (_, i) => i + 1);
    setCompletedSteps(allSteps);
  }, [markComplete]);

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

      {/* Launch onboard */}
      <Card className="border-primary/20 bg-primary/5 p-6">
        <div className="space-y-4">
          <div className="flex items-center gap-3">
            <Rocket className="h-6 w-6 text-primary" />
            <h2 className="text-xl font-semibold">Start the onboarding tutorial</h2>
          </div>
          <p className="text-muted-foreground">
            Learn the basics of your new environment with an interactive tutorial:
          </p>
          <CommandCard
            command="onboard"
            description="Launch interactive onboarding"
          />
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
                <strong>A powerful shell (zsh)</strong> — A modern command-line interface
                with auto-suggestions and beautiful colors
              </li>
              <li>
                <strong>AI coding assistants</strong> — Claude Code, Codex, and Gemini CLI
                are ready to help you write code
              </li>
              <li>
                <strong>Development tools</strong> — Fast search (ripgrep), git interface
                (lazygit), and more
              </li>
              <li>
                <strong>Programming languages</strong> — JavaScript/TypeScript (bun),
                Python (uv), Rust, and Go
              </li>
            </ul>
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
            Part One is complete! Continue to Part Two to learn the powerful multi-agent
            workflow that lets you build production-ready software at incredible speed.
            You&apos;ll learn how to orchestrate multiple AI agents working in parallel,
            use the &quot;best of all worlds&quot; planning technique, and run agent swarms
            that build features while you sleep.
          </p>
          <Link href="/workflow">
            <Button size="lg" className="w-full sm:w-auto">
              Continue to Part Two: The Workflow
              <ArrowRight className="ml-2 h-4 w-4" />
            </Button>
          </Link>
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
