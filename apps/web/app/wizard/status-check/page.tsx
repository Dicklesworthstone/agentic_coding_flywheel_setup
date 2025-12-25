"use client";

import { useCallback, useState } from "react";
import { useRouter } from "next/navigation";
import {
  AlertCircle,
  Stethoscope,
  KeyRound,
  Shield,
  Bot,
  Cloud,
  Wrench,
  BookOpen,
  Laptop,
} from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { CommandCard } from "@/components/command-card";
import { AlertCard, OutputPreview } from "@/components/alert-card";
import { WhereAmICheck } from "@/components/connection-check";
import { markStepComplete } from "@/lib/wizardSteps";
import {
  SERVICES,
  CATEGORY_NAMES,
  type Service,
  type ServiceCategory,
} from "@/lib/services";
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
import { withCurrentSearch } from "@/lib/utils";

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

// Category icons for auth section
const AUTH_CATEGORY_ICONS: Record<ServiceCategory, React.ReactNode> = {
  access: <Shield className="h-5 w-5" />,
  agent: <Bot className="h-5 w-5" />,
  cloud: <Cloud className="h-5 w-5" />,
  devtools: <Wrench className="h-5 w-5" />,
};

// Get services that have auth commands, grouped by category
function getAuthServices(): Record<ServiceCategory, Service[]> {
  const groups: Record<ServiceCategory, Service[]> = {
    access: [],
    agent: [],
    cloud: [],
    devtools: [],
  };
  for (const service of SERVICES) {
    if (service.postInstallCommand && service.installedByAcfs) {
      groups[service.category].push(service);
    }
  }
  return groups;
}

export default function StatusCheckPage() {
  const router = useRouter();
  const [isNavigating, setIsNavigating] = useState(false);

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "status_check",
    stepNumber: 12,
    stepTitle: "Status Check",
  });

  const handleContinue = useCallback(() => {
    markComplete();
    markStepComplete(12);
    setIsNavigating(true);
    router.push(withCurrentSearch("/wizard/launch-onboarding"));
  }, [router, markComplete]);

  // Compute auth services once, not on every category iteration
  const authServices = getAuthServices();

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

      {/* Reconnection Reminder */}
      <AlertCard variant="warning" icon={AlertCircle} title="Before running these commands">
        <div className="space-y-2">
          <p>
            Make sure you&apos;re connected to your <strong>VPS</strong>, not running commands on your laptop!
          </p>
          <p className="text-sm">
            If you&apos;re in PowerShell or Terminal on your laptop, first run your SSH command:
          </p>
          <code className="mt-1 block overflow-x-auto rounded bg-background/50 px-3 py-2 font-mono text-xs">
            ssh -i ~/.ssh/acfs_ed25519 ubuntu@YOUR_VPS_IP
          </code>
          <p className="text-sm text-muted-foreground">
            Once you see <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ubuntu@</code> in your prompt, you&apos;re ready.
          </p>
        </div>
      </AlertCard>

      {/* Common Mistake Warning */}
      <AlertCard variant="error" icon={AlertCircle} title="Common Mistake: Claude Desktop vs Claude Code">
        <div className="space-y-2">
          <p>
            <strong>Claude Code is NOT the Claude Desktop app</strong> you download to your computer.
          </p>
          <p className="text-sm">
            Claude Code is a command-line tool that&apos;s already installed <strong>on your VPS</strong>.
            To use it:
          </p>
          <ol className="list-decimal list-inside space-y-1 text-sm">
            <li>SSH into your VPS first (using the command above)</li>
            <li>Then run <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">claude</code> or <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">cc</code> commands</li>
          </ol>
          <p className="text-sm text-muted-foreground">
            If you&apos;re seeing &quot;command not found&quot; in PowerShell or Terminal on your laptop, you&apos;re in the wrong place!
          </p>
        </div>
      </AlertCard>

      {/* Where Am I? Check */}
      <WhereAmICheck />

      {/* Doctor command */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold text-foreground">Run the doctor command</h2>
        <p className="text-sm text-muted-foreground">
          This checks all installed tools and reports any issues:
        </p>
        <CommandCard
          command="acfs doctor"
          description="Run Agent Flywheel health check"
          runLocation="vps"
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
              runLocation="vps"
            />
          ))}
        </div>
      </div>

      {/* Authenticate your services */}
      <div className="space-y-6">
        <div className="flex items-center gap-3">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10 text-primary">
            <KeyRound className="h-5 w-5" />
          </div>
          <div>
            <h2 className="text-xl font-semibold">Authenticate your services</h2>
            <p className="text-sm text-muted-foreground">
              Log in to the tools you plan to use now (you can do the rest later)
            </p>
          </div>
        </div>

        {/* Headless auth flow explanation */}
        <AlertCard variant="info" icon={Laptop} title="Authentication on a Headless Server">
          <div className="space-y-2">
            <p>
              Your VPS doesn&apos;t have a web browser, so authentication works differently:
            </p>
            <ol className="list-decimal list-inside space-y-1 text-sm">
              <li>Run a login command below (like <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">claude</code>)</li>
              <li>The terminal will display a URL and possibly a code</li>
              <li><strong>Copy that URL and open it in your laptop&apos;s browser</strong></li>
              <li>Complete the login in your browser</li>
              <li>Return to your terminal — it should confirm success</li>
            </ol>
            <p className="mt-2 text-xs text-muted-foreground">
              If you see &quot;Opening browser...&quot; but nothing happens, that&apos;s normal!
              Just copy the URL shown and open it manually on your laptop.
            </p>
          </div>
        </AlertCard>

        <AlertCard variant="success" icon={Bot} title="You don't need to log into everything right now">
          <div className="space-y-2 text-sm">
            <p className="text-muted-foreground">
              Most people start with <strong className="text-foreground">one</strong> coding agent and add
              the rest later.
            </p>
            <ul className="list-disc space-y-1 pl-5">
              <li><strong>Recommended now:</strong> Claude Code (so you can start coding immediately)</li>
              <li><strong>Optional now:</strong> Codex, Gemini (only if you plan to use them)</li>
              <li><strong>Optional later:</strong> Cloud tools (Wrangler / Supabase / Convex / Vercel) and anything else you don&apos;t need yet</li>
            </ul>
            <p className="text-xs text-muted-foreground">
              If you skip a login, the tool is still installed — it just won&apos;t work until you authenticate.
            </p>
          </div>
        </AlertCard>

        {/* Auth commands grouped by category */}
        {(["access", "agent", "cloud"] as const).map((category) => {
          const services = authServices[category];
          if (services.length === 0) return null;

          return (
            <div key={category} className="space-y-3">
              <div className="flex items-center gap-2">
                <div className="flex h-6 w-6 items-center justify-center rounded-md bg-muted text-muted-foreground">
                  {AUTH_CATEGORY_ICONS[category]}
                </div>
                <h3 className="text-sm font-medium text-muted-foreground">
                  {CATEGORY_NAMES[category]}
                </h3>
              </div>
              <div className="space-y-2 pl-8">
                {services.map((service) => (
                  <CommandCard
                    key={service.id}
                    command={service.postInstallCommand!}
                    description={`Log in to ${service.name}`}
                    runLocation="vps"
                    showCheckbox
                    persistKey={`auth-${service.id}`}
                  />
                ))}
              </div>
            </div>
          );
        })}
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
                  This checks Claude Code, the AI coding assistant. You should see
                  a version number like &quot;1.0.3&quot;.
                </span>
              </li>
              <li>
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">bun --version</code>
                <br />
                <span className="text-sm text-muted-foreground">
                  This checks Bun, a fast JavaScript runtime. You should see
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
                <code className="mt-1 block overflow-x-auto rounded bg-muted px-2 py-1 font-mono text-xs">
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
                <code className="mt-1 block overflow-x-auto rounded bg-muted px-2 py-1 font-mono text-xs">
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

          <GuideSection title="Authenticating Your Services">
            <p className="mb-3">
              The services you signed up for need to be connected to your VPS.
              Each command displays a URL to open in your laptop&apos;s browser:
            </p>
            <div className="space-y-4">
              <GuideStep number={1} title="Run the login command">
                Copy and run a command like{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">claude</code> or{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">vercel login</code>.
              </GuideStep>

              <GuideStep number={2} title="Complete browser login">
                A URL will appear in your terminal. Open it in your browser and
                sign in with the account you created earlier.
              </GuideStep>

              <GuideStep number={3} title="Return to terminal">
                Once you&apos;ve logged in, the terminal will confirm the connection.
                Check the box next to each command as you complete it.
              </GuideStep>
            </div>
          </GuideSection>

          <GuideTip>
            If most things show green checkmarks (✔), you&apos;re good to go! Don&apos;t worry
            about one or two yellow warnings; those are usually optional tools.
            Click &quot;Everything looks good!&quot; to continue.
          </GuideTip>

          <GuideCaution>
            <strong>If you see many red X marks:</strong> Don&apos;t continue yet. Try the
            troubleshooting steps above, or re-run the installer. If problems persist,
            you can ask for help in the project&apos;s GitHub issues.
          </GuideCaution>

          <div className="rounded-lg border border-primary/20 bg-primary/5 p-4">
            <Link href="/learn/welcome" className="flex items-center gap-3 text-sm">
              <BookOpen className="h-5 w-5 text-primary" />
              <div>
                <span className="font-medium text-foreground">New to this environment?</span>
                <p className="text-muted-foreground">
                  Start with the Welcome lesson to understand what you now have →
                </p>
              </div>
            </Link>
          </div>

          <div className="rounded-lg border border-primary/20 bg-primary/5 p-4">
            <Link href="/learn/flywheel-loop" className="flex items-center gap-3 text-sm">
              <BookOpen className="h-5 w-5 text-primary" />
              <div>
                <span className="font-medium text-foreground">Ready for the full workflow?</span>
                <p className="text-muted-foreground">
                  See the Flywheel Loop lesson to connect all the tools →
                </p>
              </div>
            </Link>
          </div>
        </div>
      </SimplerGuide>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg" disableMotion>
          {isNavigating ? "Loading..." : "Everything looks good!"}
        </Button>
      </div>
    </div>
  );
}
