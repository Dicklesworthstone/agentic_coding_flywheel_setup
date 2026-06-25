"use client";

import { useCallback, useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
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
import {
  CommandCard,
  CodeBlock,
  commandCompletionKeys,
} from "@/components/command-card";
import { AlertCard, OutputPreview } from "@/components/alert-card";
import { WhereAmICheck } from "@/components/connection-check";
import {
  canAccessWizardStep,
  getCompletedSteps,
  getNextReachableWizardStep,
  markStepComplete,
  validateStep,
} from "@/lib/wizardSteps";
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
import { buildInstallCommand, formatSshTarget } from "@/lib/commandBuilder";
import { useACFSRef, useInstallMode, useSSHUsername, useVPSIP } from "@/lib/userPreferences";
import { safeGetItem, withCurrentSearch } from "@/lib/utils";

const STATUS_CHECK_COMPLETION_KEY = "acfs-command-flywheel-doctor";
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
    command: "ms --version",
    description: "Check Meta Skill is installed",
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

function getAuthCommandDescription(service: Service): string {
  switch (service.id) {
    case "github":
      return "Authenticate GitHub CLI";
    case "tailscale":
      return "Bring Tailscale up and approve this machine";
    case "codex-cli":
      return "Authenticate Codex with device auth";
    case "antigravity-cli":
      return "Open Antigravity and complete Google auth";
    case "gemini-cli":
      return "Legacy Gemini CLI auth";
    case "vercel":
      return "Start Vercel's device login flow";
    case "supabase":
      return "Authenticate Supabase with an access token";
    case "cloudflare":
      return "Set your Cloudflare API token";
    default:
      return `Log in to ${service.name}`;
  }
}

function getAuthCheckboxLabel(service: Service): string {
  return service.tier === "essential"
    ? "Recommended: I logged in to this tool"
    : "Optional: I logged in to this tool";
}

function getAuthCompletedLabel(service: Service): string {
  return service.tier === "essential"
    ? "Recommended login completed"
    : "Optional login completed";
}

export default function StatusCheckPage() {
  const router = useRouter();
  const [isNavigating, setIsNavigating] = useState(false);
  const [vpsIP, , vpsIPLoaded] = useVPSIP();
  const [sshUsername, , sshUsernameLoaded] = useSSHUsername();
  const [installMode, , installModeLoaded] = useInstallMode();
  const [acfsRef, , acfsRefLoaded] = useACFSRef();
  const ready =
    vpsIPLoaded && sshUsernameLoaded && installModeLoaded && acfsRefLoaded;
  const { data: doctorConfirmed = false } = useQuery({
    queryKey: commandCompletionKeys.completion(STATUS_CHECK_COMPLETION_KEY),
    queryFn: () => safeGetItem(STATUS_CHECK_COMPLETION_KEY) === "true",
    staleTime: Infinity,
    gcTime: Infinity,
  });
  const effectiveVpsIP = vpsIP ?? "";
  const effectiveSSHUsername = sshUsername.trim() || "ubuntu";
  const reconnectTarget = formatSshTarget(effectiveSSHUsername, effectiveVpsIP);
  const reconnectCommand = `ssh -i ~/.ssh/acfs_ed25519 ${reconnectTarget}`;
  const reconnectWindowsCommand = `ssh -i %USERPROFILE%\\.ssh\\acfs_ed25519 ${reconnectTarget}`;
  const codexTunnelCommand = `ssh -i ~/.ssh/acfs_ed25519 -L 1455:localhost:1455 ${reconnectTarget}`;
  const codexTunnelWindowsCommand = `ssh -i %USERPROFILE%\\.ssh\\acfs_ed25519 -L 1455:localhost:1455 ${reconnectTarget}`;
  const reinstallCommand = buildInstallCommand(
    installModeLoaded ? installMode : "vibe",
    acfsRefLoaded ? acfsRef : null,
    effectiveSSHUsername,
  );
  const promptPrefix = `${effectiveSSHUsername}@`;

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "status_check",
    stepNumber: 12,
    stepTitle: "Status Check",
  });

  useEffect(() => {
    if (!ready) return;

    const completedSteps = getCompletedSteps();
    if (!canAccessWizardStep(completedSteps, 12)) {
      const redirectStep = getNextReachableWizardStep(completedSteps);
      router.replace(withCurrentSearch(`/wizard/${redirectStep.slug}`));
      return;
    }

    if (vpsIP === null) {
      router.replace(withCurrentSearch("/wizard/create-vps"));
    }
  }, [ready, router, vpsIP]);

  const handleContinue = useCallback(() => {
    const result = validateStep(12);
    if (!result.valid) {
      return;
    }

    markComplete();
    markStepComplete(12);
    setIsNavigating(true);
    router.push(withCurrentSearch("/wizard/launch-onboarding"));
  }, [router, markComplete]);

  // Compute auth services once, not on every category iteration
  const authServices = getAuthServices();

  if (!ready || vpsIP === null) {
    return (
      <div className="flex items-center justify-center py-12">
        <Stethoscope className="h-8 w-8 animate-pulse text-muted-foreground" />
      </div>
    );
  }

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
          <CommandCard
            command={reconnectCommand}
            windowsCommand={reconnectWindowsCommand}
            runLocation="local"
            className="mt-1"
          />
          <p className="text-sm text-muted-foreground">
            Once you see <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">{promptPrefix}</code> in your prompt, you&apos;re ready.
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
          This checks all installed tools and reports any issues. This is the only
          checkbox required to continue.
        </p>
        <CommandCard
          command="acfs doctor"
          description="Run Agent Flywheel health check"
          runLocation="vps"
          showCheckbox
          checkboxLabel="I ran acfs doctor"
          completedLabel="Doctor completed"
          persistKey="flywheel-doctor"
        />
      </div>

      {/* Expected output */}
      <OutputPreview title="Expected output">
        <div className="space-y-1 font-mono text-xs">
          <p className="text-muted-foreground">Agent Flywheel Doctor - System Health Check</p>
          <p className="text-muted-foreground">{"=".repeat(32)}</p>
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
              <li>Run a login or auth command below (for example <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">claude</code>)</li>
              <li>Agent CLIs usually print a URL or device code; cloud CLIs may instead ask for an access token</li>
              <li><strong>Complete the browser step on your laptop</strong> or create the token there if needed</li>
              <li>Return to your terminal and finish the prompt or export the token in your shell</li>
            </ol>
            <p className="mt-2 text-xs text-muted-foreground">
              If you see &quot;Opening browser...&quot; but nothing happens, that&apos;s normal.
              Open the URL manually on your laptop, or use the token-based alternative described below.
            </p>
          </div>
        </AlertCard>

        {/* Codex-specific auth note */}
        <AlertCard variant="warning" icon={AlertCircle} title="Codex CLI: Special Headless Setup">
          <div className="space-y-2">
            <p>
              <strong>Codex requires extra steps</strong> because its OAuth callback expects{" "}
              <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">localhost:1455</code>,
              which doesn&apos;t work on a remote VPS.
            </p>
            <p className="text-sm font-medium">Option 1: Device Auth (Recommended)</p>
            <ol className="list-decimal list-inside space-y-1 text-sm pl-2">
              <li>Go to <a href="https://chatgpt.com/settings/security" target="_blank" rel="noopener noreferrer" className="text-primary underline">ChatGPT Settings → Security</a></li>
              <li>Enable &quot;Device code login&quot; (may be in beta)</li>
              <li>Then run: <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">codex login --device-auth</code></li>
            </ol>
            <p className="text-sm font-medium mt-2">Option 2: SSH Tunnel</p>
            <ol className="list-decimal list-inside space-y-1 text-sm pl-2">
              <li>On your laptop, open the SSH tunnel shown below</li>
              <li>In that SSH session (on VPS): <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">codex login</code></li>
              <li>The OAuth redirect will reach your VPS through the tunnel</li>
            </ol>
            <CommandCard
              command={codexTunnelCommand}
              windowsCommand={codexTunnelWindowsCommand}
              runLocation="local"
              className="mt-1"
            />
          </div>
        </AlertCard>

        {/* Wrangler (Cloudflare) headless auth note */}
        <AlertCard variant="warning" icon={AlertCircle} title="Wrangler: Headless VPS Setup">
          <div className="space-y-2">
            <p>
              <strong>Wrangler requires a browser</strong> for{" "}
              <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">wrangler login</code>,
              which doesn&apos;t work on a headless VPS.
            </p>
            <p className="text-sm font-medium">Solution: Use API Token</p>
            <ol className="list-decimal list-inside space-y-1 text-sm pl-2">
              <li>Go to <a href="https://dash.cloudflare.com/profile/api-tokens" target="_blank" rel="noopener noreferrer" className="text-primary underline">Cloudflare → API Tokens</a></li>
              <li>Create a token with the permissions you need (e.g., Workers, Pages)</li>
              <li>Add to your <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">~/.zshrc</code>:</li>
            </ol>
            <CodeBlock code={`export CLOUDFLARE_API_TOKEN="your-token-here"\nexport CLOUDFLARE_ACCOUNT_ID="your-account-id"`} language="bash" className="mt-1" />
            <p className="text-xs text-muted-foreground mt-1">
              Then run <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">source ~/.zshrc</code> or start a new shell.
            </p>
          </div>
        </AlertCard>

        {/* Other cloud tools headless auth */}
        <AlertCard variant="warning" icon={AlertCircle} title="Supabase & Vercel: Headless VPS Setup">
          <div className="space-y-2">
            <p>
              Supabase works best with an access token on a VPS. Vercel CLI now supports
              a device-login flow directly from a headless terminal, so you usually do not
              need a manual token just to sign in.
            </p>
            <div className="text-sm space-y-2">
              <p className="font-medium">Supabase:</p>
              <ol className="list-decimal list-inside space-y-1 pl-2 text-sm">
                <li>Go to <a href="https://supabase.com/dashboard/account/tokens" target="_blank" rel="noopener noreferrer" className="text-primary underline">Supabase → Access Tokens</a></li>
                <li>Create a token, then add to <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">~/.zshrc</code>:</li>
              </ol>
              <CodeBlock code={`export SUPABASE_ACCESS_TOKEN="your-token-here"`} language="bash" />

              <p className="font-medium mt-2">Vercel:</p>
              <ol className="list-decimal list-inside space-y-1 pl-2 text-sm">
                <li>Run <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">vercel login</code> on the VPS</li>
                <li>Open the device-login URL on your laptop and approve the prompt</li>
                <li>If you need automation or CI auth, export <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">VERCEL_TOKEN</code> instead of using the interactive flow</li>
              </ol>
            </div>
          </div>
        </AlertCard>

        <AlertCard variant="success" icon={Bot} title="You don't need to log into everything right now">
          <div className="space-y-2 text-sm">
            <p className="text-muted-foreground">
              Most people start with <strong className="text-foreground">one</strong> coding agent and add
              the rest later.
            </p>
            <ul className="list-disc space-y-1 pl-5">
              <li><strong>Recommended now:</strong> GitHub CLI and Claude Code (so you can save code and start coding immediately)</li>
              <li><strong>Optional now:</strong> Codex, Gemini, and Tailscale (only if you plan to use them)</li>
              <li><strong>Optional later:</strong> Cloud tools (Wrangler / Supabase / Vercel) and anything else you don&apos;t need yet</li>
            </ul>
            <p className="text-xs text-muted-foreground">
              If you skip a login, the tool is still installed — it just won&apos;t work until you authenticate.
            </p>
            <p className="rounded-md border border-border/60 bg-muted/30 px-3 py-2 text-xs text-muted-foreground">
              Only the doctor checkbox is required to continue. The login checkboxes below
              are optional notes for the tools you decide to authenticate now.
            </p>
          </div>
        </AlertCard>

        {/* Auth commands grouped by category */}
        {(["devtools", "agent", "access", "cloud"] as const).map((category) => {
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
                    description={getAuthCommandDescription(service)}
                    runLocation="vps"
                    showCheckbox
                    checkboxLabel={getAuthCheckboxLabel(service)}
                    completedLabel={getAuthCompletedLabel(service)}
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
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">{promptPrefix}</code>
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
                <CommandCard command="source ~/.zshrc" runLocation="vps" className="mt-1" />
                <p className="mt-1 text-sm text-muted-foreground">
                  Then try the doctor command again.
                </p>
              </div>

              <div>
                <p className="font-medium">A specific tool shows ✘</p>
                <p className="text-sm text-muted-foreground">
                  You can try re-running the installer. It&apos;s safe to run multiple times:
                </p>
                <CommandCard command={reinstallCommand} runLocation="vps" className="mt-1" />
              </div>

              <div>
                <p className="font-medium">Nothing works at all</p>
                <p className="text-sm text-muted-foreground">
                  Make sure you&apos;re connected as the <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">{effectiveSSHUsername}</code> user (not root).
                  The installer set up tools for that configured account specifically.
                </p>
              </div>
            </div>
          </GuideSection>

          <GuideSection title="Authenticating Your Services">
            <p className="mb-3">
              The services you signed up for need to be connected to your VPS.
              Some tools open a browser flow on your laptop, while others use
              device-code auth or access tokens that work cleanly on a headless VPS.
            </p>
            <div className="space-y-4">
              <GuideStep number={1} title="Run the login command">
                Copy and run a command like{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">claude</code> or{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">codex login --device-auth</code>.
              </GuideStep>

              <GuideStep number={2} title="Finish the matching auth flow">
                Follow the instructions for that specific tool. You might open a
                URL in your laptop&apos;s browser, complete a device-code flow, or
                add a token such as <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">GEMINI_API_KEY</code>,{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">SUPABASE_ACCESS_TOKEN</code>, or{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">CLOUDFLARE_API_TOKEN</code>.
              </GuideStep>

              <GuideStep number={3} title="Return to terminal">
                Once you&apos;ve logged in, the terminal will confirm the connection.
                If you authenticate optional tools now, use their checkboxes as notes.
                They do not block the final step.
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
      <div className="space-y-2 pt-4">
        {!doctorConfirmed && (
          <p className="text-sm text-muted-foreground">
            Check off the doctor command above to unlock the final step.
          </p>
        )}
        <div className="flex justify-end">
          <Button
            onClick={handleContinue}
            disabled={isNavigating || !doctorConfirmed}
            size="lg"
            disableMotion
          >
            {isNavigating ? "Loading..." : "Everything looks good!"}
          </Button>
        </div>
      </div>
    </div>
  );
}
