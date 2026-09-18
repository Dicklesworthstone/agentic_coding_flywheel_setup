"use client";

import { useCallback, useEffect, useRef, useState } from "react";
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
} from "@/components/command-card";
import { AlertCard, OutputPreview } from "@/components/alert-card";
import { WhereAmICheck } from "@/components/connection-check";
import {
  canAccessWizardStep,
  getCompletedSteps,
  getNextReachableWizardStep,
  markStepComplete,
  useWizardForwardNav,
  validateStep,
} from "@/lib/wizardSteps";
import {
  getSelectedAuthServices,
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
import { formatSshTarget } from "@/lib/commandBuilder";
import { withCurrentSearch } from "@/lib/utils";
import { DOCTOR_COMMAND, useInstallationHealth } from "@/lib/hooks/useInstallationHealth";

const QUICK_CHECKS = [
  {
    moduleId: "agents.claude",
    command: "claude --version",
    description: "Check Claude Code is installed",
  },
  {
    moduleId: "lang.bun",
    command: "bun --version",
    description: "Check bun is installed",
  },
  {
    moduleId: "stack.meta_skill",
    command: "ms --version",
    description: "Check Meta Skill is installed",
  },
  {
    moduleId: "cli.modern",
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
  if (service.id === "cloudflare") {
    // Cloudflare's "command" opens ~/.zshrc in an editor; there is no login.
    return "Optional: I added my token to ~/.zshrc";
  }
  return service.tier === "essential"
    ? "Recommended: I logged in to this tool"
    : "Optional: I logged in to this tool";
}

function getAuthCompletedLabel(service: Service): string {
  if (service.id === "cloudflare") {
    return "Optional token added to ~/.zshrc";
  }
  return service.tier === "essential"
    ? "Recommended login completed"
    : "Optional login completed";
}

export default function StatusCheckPage() {
  const router = useRouter();
  const [isNavigating, setIsNavigating] = useState(false);
  const { ready, vpsIP, sshUsername, selectedPlan, reinstallCommand, activeCheckpoint,
    hashFailed, completionKey, doctorConfirmed } = useInstallationHealth();
  const effectiveVpsIP = vpsIP ?? "";
  const effectiveSSHUsername = sshUsername;
  const reconnectTarget = formatSshTarget(effectiveSSHUsername, effectiveVpsIP);
  const reconnectCommand = `ssh -i ~/.ssh/acfs_ed25519 ${reconnectTarget}`;
  const reconnectWindowsCommand = `ssh -i $HOME\\.ssh\\acfs_ed25519 ${reconnectTarget}`;
  const codexTunnelCommand = `ssh -i ~/.ssh/acfs_ed25519 -L 1455:localhost:1455 ${reconnectTarget}`;
  const codexTunnelWindowsCommand = `ssh -i $HOME\\.ssh\\acfs_ed25519 -L 1455:localhost:1455 ${reconnectTarget}`;
  // Stale registered callbacks cannot advance a newer host or a withdrawn check.
  const currentCompletion = useRef<string | null>(null);
  useEffect(() => {
    currentCompletion.current = doctorConfirmed ? completionKey : null;
    return () => { currentCompletion.current = null; };
  }, [doctorConfirmed, completionKey]);
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
    if (!ready || !reinstallCommand || isNavigating || !doctorConfirmed || !completionKey
        || currentCompletion.current !== completionKey) return;
    const result = validateStep(12);
    if (!result.valid) {
      return;
    }

    markComplete();
    markStepComplete(12);
    setIsNavigating(true);
    router.push(withCurrentSearch("/wizard/launch-onboarding"));
  }, [ready, reinstallCommand, isNavigating, doctorConfirmed, completionKey, router, markComplete]);

  const forwardCtaRef = useWizardForwardNav({
    onContinue: handleContinue,
    disabled: isNavigating || !doctorConfirmed,
    loading: isNavigating,
    label: "Everything looks good!",
  });

  const selectedModules = new Set(selectedPlan?.included.map((entry) => entry.id) ?? []);
  const quickChecks = QUICK_CHECKS.filter((check) => selectedModules.has(check.moduleId));
  const authServices = getSelectedAuthServices(selectedModules);
  const selectedServices = Object.values(authServices).flat();
  const hasService = (id: string) => selectedServices.some((service) => service.id === id);

  if (!ready || vpsIP === null) {
    return (
      <div className="flex items-center justify-center py-12">
        <Stethoscope className="h-8 w-8 animate-pulse text-muted-foreground" />
      </div>
    );
  }

  if (!reinstallCommand) {
    return <AlertCard variant="error" title="Status check blocked">
      <p>The current host, installation choices, or reviewed command cannot be validated.
        No recovery or authentication commands are available.</p>
      <Link href={withCurrentSearch("/wizard/run-installer")} className="inline-flex min-h-11 items-center underline">
        Return to Run Installer and review the selected installation
      </Link>
    </AlertCard>;
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
      {hasService("claude-code") && <AlertCard variant="error" icon={AlertCircle} title="Common Mistake: Claude Desktop vs Claude Code">
        <div className="space-y-2">
          <p>
            <strong>Claude Code is NOT the Claude Desktop app</strong> you download to your computer.
          </p>
          <p className="text-sm">
            Claude Code is a command-line tool selected for <strong>your VPS</strong>.
            After verifying its installation:
          </p>
          <ol className="list-decimal list-inside space-y-1 text-sm">
            <li>SSH into your VPS first (using the command above)</li>
            <li>Then run <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">claude</code> or <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">cc</code> commands</li>
          </ol>
          <p className="text-sm text-muted-foreground">
            If you&apos;re seeing &quot;command not found&quot; in PowerShell or Terminal on your laptop, you&apos;re in the wrong place!
          </p>
        </div>
      </AlertCard>}

      {/* Where Am I? Check */}
      <WhereAmICheck />

      {/* Doctor command */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold text-foreground">Run the doctor command</h2>
        <p className="text-sm text-muted-foreground">
          Run the health check on this VPS and inspect the actual results. This page
          knows your selected plan, not what succeeded remotely. The doctor may report
          tools outside a narrow selection; compare findings with the selected modules below.
        </p>
        <CommandCard
          command={DOCTOR_COMMAND}
          description="Run Agent Flywheel health check"
          runLocation="vps"
          showCheckbox={Boolean(activeCheckpoint)}
          checkboxLabel="I ran acfs doctor for this installation and reviewed the results"
          completedLabel="Doctor run acknowledged for this installation"
          persistKey={activeCheckpoint?.persistKey}
          checkboxId="flywheel-doctor"
        />
        {!activeCheckpoint && <p role={hashFailed ? "alert" : "status"} className="text-sm text-muted-foreground">
          {hashFailed
            ? "Secure browser hashing failed. The command remains available, but completion is blocked; reload in a browser with Web Crypto support."
            : "Binding the acknowledgement to this host and exact installation..."}
        </p>}
        <details className="rounded-lg border border-border/50 p-3">
          <summary className="min-h-11 cursor-pointer py-2">Selected installation: {selectedPlan?.selectedCount} modules</summary>
          <p className="break-words font-mono text-xs">{[...selectedModules].join(", ") || "No modules selected."}</p>
          {selectedPlan?.warnings.map((warning, index) => <p key={index} className="text-sm text-muted-foreground">{warning}</p>)}
        </details>
      </div>

      {/* Expected output */}
      <OutputPreview title="How to read the actual doctor report">
        <div className="space-y-1 font-mono text-xs">
          <p className="text-muted-foreground">Agent Flywheel Doctor - System Health Check</p>
          <p className="text-muted-foreground">{"=".repeat(32)}</p>
          <p className="text-green">✔ A passing check reports what worked on the VPS.</p>
          <p className="text-destructive">✘ Investigate failures affecting your selected modules.</p>
          <p className="mt-2 text-foreground">No remote results are collected or verified by this page.</p>
        </div>
      </OutputPreview>

      {/* Quick spot checks */}
      {quickChecks.length > 0 && <div className="space-y-4">
        <h2 className="text-xl font-semibold">Quick spot checks</h2>
        <p className="text-sm text-muted-foreground">
          These commands cover tools in your selected plan, including dependencies:
        </p>
        <div className="space-y-3">
          {quickChecks.map((check, i) => (
            <CommandCard
              key={i}
              command={check.command}
              description={check.description}
              runLocation="vps"
            />
          ))}
        </div>
      </div>}

      {/* Authenticate your services */}
      {selectedServices.length > 0 ? <div className="space-y-6">
        <div className="flex items-center gap-3">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-primary/10 text-primary">
            <KeyRound className="h-5 w-5" />
          </div>
          <div>
            <h2 className="text-xl font-semibold">Authenticate your services</h2>
            <p className="text-sm text-muted-foreground">
              Only services from the selected modules are shown. Verify the CLI exists before signing in.
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
              <li>Run the matching login or auth command below for a tool you intend to use</li>
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
        {hasService("codex-cli") && <AlertCard variant="warning" icon={AlertCircle} title="Codex CLI: Special Headless Setup">
          <div className="space-y-2">
            <p>
              <strong>Codex requires extra steps</strong> because its OAuth callback expects{" "}
              <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">localhost:1455</code>,
              which doesn&apos;t work on a remote VPS.
            </p>
            <p className="text-sm font-medium">Option 1: Device Auth (Recommended)</p>
            <ol className="list-decimal list-inside space-y-1 text-sm pl-2">
              <li>Go to <a href="https://chatgpt.com/settings/security" target="_blank" rel="noopener noreferrer" className="inline-flex min-h-6 items-center text-primary underline">ChatGPT Settings → Security</a></li>
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
        </AlertCard>}

        {/* Wrangler (Cloudflare) headless auth note */}
        {hasService("cloudflare") && <AlertCard variant="warning" icon={AlertCircle} title="Wrangler: Headless VPS Setup">
          <div className="space-y-2">
            <p>
              <strong>Wrangler requires a browser</strong> for{" "}
              <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">wrangler login</code>,
              which doesn&apos;t work on a headless VPS.
            </p>
            <p className="text-sm font-medium">Solution: Use API Token</p>
            <ol className="list-decimal list-inside space-y-1 text-sm pl-2">
              <li>Go to <a href="https://dash.cloudflare.com/profile/api-tokens" target="_blank" rel="noopener noreferrer" className="inline-flex min-h-6 items-center text-primary underline">Cloudflare → API Tokens</a></li>
              <li>Create a token with the permissions you need (e.g., Workers, Pages)</li>
              <li>Add to your <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">~/.zshrc</code>:</li>
            </ol>
            <CodeBlock code={`export CLOUDFLARE_API_TOKEN="your-token-here"\nexport CLOUDFLARE_ACCOUNT_ID="your-account-id"`} language="bash" className="mt-1" />
            <p className="text-xs text-muted-foreground mt-1">
              Then run <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">source ~/.zshrc</code> or start a new shell.
            </p>
          </div>
        </AlertCard>}

        {/* Other cloud tools headless auth */}
        {(hasService("supabase") || hasService("vercel")) && <AlertCard variant="warning" icon={AlertCircle} title="Selected cloud tools: Headless VPS Setup">
          <div className="space-y-2">
            <p>
              Use the authentication method for the selected CLI. Credentials belong
              in its normal login flow, never in a shared team profile.
            </p>
            <div className="text-sm space-y-2">
              {hasService("supabase") && <>
              <p className="font-medium">Supabase:</p>
              <ol className="list-decimal list-inside space-y-1 pl-2 text-sm">
                <li>Go to <a href="https://supabase.com/dashboard/account/tokens" target="_blank" rel="noopener noreferrer" className="inline-flex min-h-6 items-center text-primary underline">Supabase → Access Tokens</a></li>
                <li>Create a token, then add to <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">~/.zshrc</code>:</li>
              </ol>
              <CodeBlock code={`export SUPABASE_ACCESS_TOKEN="your-token-here"`} language="bash" />
              </>}

              {hasService("vercel") && <>
              <p className="font-medium mt-2">Vercel:</p>
              <ol className="list-decimal list-inside space-y-1 pl-2 text-sm">
                <li>Run <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">vercel login</code> on the VPS</li>
                <li>Open the device-login URL on your laptop and approve the prompt</li>
                <li>If you need automation or CI auth, export <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">VERCEL_TOKEN</code> instead of using the interactive flow</li>
              </ol>
              </>}
            </div>
          </div>
        </AlertCard>}

        <AlertCard variant="success" icon={Bot} title="You don't need to log into everything right now">
          <div className="space-y-2 text-sm">
            <p className="text-muted-foreground">Start with the selected tools you need now:</p>
            <ul className="list-disc space-y-1 pl-5">
              {selectedServices.map((service) => <li key={service.id}>{service.name}</li>)}
            </ul>
            <p className="text-xs text-muted-foreground">
              Skipping a login does not change the installation plan. Check the tool&apos;s
              actual availability on the VPS; these checkboxes are personal notes, not auth verification.
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
                    showCheckbox={Boolean(activeCheckpoint)}
                    checkboxLabel={getAuthCheckboxLabel(service)}
                    completedLabel={getAuthCompletedLabel(service)}
                    persistKey={activeCheckpoint ? `auth-${service.id}-${activeCheckpoint.persistKey}` : undefined}
                  />
                ))}
              </div>
            </div>
          );
        })}
      </div> : <p className="text-sm text-muted-foreground">No service sign-ins are mapped to this selected installation.</p>}

      {/* Troubleshooting */}
      <AlertCard variant="warning" icon={AlertCircle} title="Something not working?">
        {selectedModules.has("shell.omz") ? <>Try running{" "}
        <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">source ~/.zshrc</code> to
        reload your shell config, then try the doctor again.</>
          : <>Open a fresh login shell as the configured user and check the installation log.
            A missing tool outside your selection is not permission to install everything.</>}
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
                    <span className="text-green">✔ Green checkmarks</span> = Working correctly!
                  </li>
                  <li>
                    <span className="text-destructive">✘ Red X marks</span> = Something needs attention
                  </li>
                </ul>
              </GuideStep>
            </div>
          </GuideSection>

          {quickChecks.length > 0 && <GuideSection title="Understanding the Quick Spot Checks">
            <p className="mb-3">
              We also show some simple commands you can run to double-check specific tools:
            </p>
            <ul className="space-y-3">
              {quickChecks.map((check) => <li key={check.moduleId}>
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">{check.command}</code>
                <p className="text-sm text-muted-foreground">{check.description}. Read the actual terminal output.</p>
              </li>)}
            </ul>
          </GuideSection>}

          <GuideSection title="What If Something Failed?">
            <p className="mb-3">
              Don&apos;t panic! Here are some common fixes:
            </p>
            <div className="space-y-4">
              {selectedModules.has("shell.omz") && <div>
                <p className="font-medium">&quot;Command not found&quot; error</p>
                <p className="text-sm text-muted-foreground">
                  This usually means your shell config hasn&apos;t loaded yet. Run this command
                  to reload it:
                </p>
                <CommandCard command="source ~/.zshrc" runLocation="vps" className="mt-1" />
                <p className="mt-1 text-sm text-muted-foreground">
                  Then try the doctor command again.
                </p>
              </div>}

              <div>
                <p className="font-medium">A specific tool shows ✘</p>
                <p className="text-sm text-muted-foreground">
                  Inspect the log first and wait for any active install or upgrade to finish.
                  Then retry this exact selection in the intended VPS root shell, following
                  any resume instructions from the log. This command does not add excluded modules:
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

          {selectedServices.length > 0 && <GuideSection title="Authenticating Your Services">
            <p className="mb-3">
              The services you signed up for need to be connected to your VPS.
              Some tools open a browser flow on your laptop, while others use
              device-code auth or access tokens that work cleanly on a headless VPS.
            </p>
            <div className="space-y-4">
              <GuideStep number={1} title="Run the login command">
                Use a command from the selected service list above after verifying
                that CLI is installed. Excluded services are not prerequisites for continuing.
              </GuideStep>

              <GuideStep number={2} title="Finish the matching auth flow">
                Follow the instructions for that specific tool. You might open a
                URL in your laptop&apos;s browser, complete a device-code flow, or
                supply a provider token through its documented login method.
                Do not paste credentials into this page or a team profile.
              </GuideStep>

              <GuideStep number={3} title="Return to terminal">
                Once you&apos;ve logged in, the terminal will confirm the connection.
                If you authenticate optional tools now, use their checkboxes as notes.
                They do not block the final step.
              </GuideStep>
            </div>
          </GuideSection>}

          <GuideTip>
            Review failures and warnings against the selected installation. Once the
            tools you need are working, acknowledge this doctor run and continue.
            The browser does not inspect the remote report or certify its results.
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
            ref={forwardCtaRef}
            data-wizard-primary-cta
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
