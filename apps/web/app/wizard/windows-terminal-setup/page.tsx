"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Terminal,
  Settings,
  Plus,
  Save,
  RefreshCw,
  Check,
  Copy,
  ExternalLink,
  ArrowLeft,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { AlertCard, OutputPreview } from "@/components/alert-card";
import { useVPSIP } from "@/lib/userPreferences";
import { withCurrentSearch } from "@/lib/utils";
import {
  SimplerGuide,
  GuideSection,
  GuideExplain,
  GuideTip,
} from "@/components/simpler-guide";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";

export default function WindowsTerminalSetupPage() {
  const router = useRouter();
  const [vpsIP, , vpsIPLoaded] = useVPSIP();
  const [copied, setCopied] = useState(false);
  const ready = vpsIPLoaded;

  // Analytics tracking for this wizard step
  useWizardAnalytics({
    step: "windows_terminal_setup",
    stepNumber: 0, // Bonus/optional step
    stepTitle: "Windows Terminal Setup",
  });

  // Redirect if no VPS IP (after hydration)
  useEffect(() => {
    if (!ready) return;
    if (vpsIP === null) {
      router.push(withCurrentSearch("/wizard/create-vps"));
    }
  }, [ready, vpsIP, router]);

  const handleBack = useCallback(() => {
    router.back();
  }, [router]);

  const displayIP = vpsIP || "YOUR_VPS_IP";
  const sshCommandLine = `ssh -i %USERPROFILE%\\.ssh\\acfs_ed25519 ubuntu@${displayIP}`;

  const handleCopy = useCallback(async () => {
    try {
      await navigator.clipboard.writeText(sshCommandLine);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback
      const textarea = document.createElement("textarea");
      textarea.value = sshCommandLine;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand("copy");
      document.body.removeChild(textarea);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  }, [sshCommandLine]);

  if (!ready || !vpsIP) {
    return (
      <div className="flex items-center justify-center py-12">
        <RefreshCw className="h-8 w-8 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[oklch(0.75_0.18_195/0.2)]">
            <Terminal className="h-5 w-5 text-[oklch(0.75_0.18_195)]" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              Windows Terminal: One-Click VPS Access
            </h1>
            <p className="text-sm text-muted-foreground">
              ~3 min (optional but very helpful)
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          Set up a custom profile in Windows Terminal so you can connect to your VPS with a single click.
        </p>
      </div>

      {/* Why this is helpful */}
      <AlertCard variant="success" icon={Terminal} title="Why set this up?">
        <div className="space-y-2">
          <p>
            Instead of opening PowerShell and typing your SSH command every time, you can:
          </p>
          <ul className="list-disc list-inside space-y-1 text-sm">
            <li>Click a tab in Windows Terminal to instantly connect to your VPS</li>
            <li>Give it a custom name like &quot;My VPS&quot; or &quot;ACFS Server&quot;</li>
            <li>Optionally set it as your default profile</li>
          </ul>
        </div>
      </AlertCard>

      {/* Step by Step */}
      <div className="space-y-6">
        <h2 className="text-xl font-semibold flex items-center gap-2">
          <Settings className="h-5 w-5 text-primary" />
          Step-by-Step Setup
        </h2>

        {/* Step 1 */}
        <div className="space-y-3 rounded-xl border border-border/50 bg-card/50 p-4">
          <div className="flex items-center gap-3">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground font-bold">
              1
            </div>
            <h3 className="font-semibold">Open Windows Terminal Settings</h3>
          </div>
          <p className="text-sm text-muted-foreground pl-11">
            Open Windows Terminal, then press{" "}
            <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Ctrl</kbd>
            {" + "}
            <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">,</kbd>
            {" "}(comma) to open Settings.
          </p>
          <p className="text-sm text-muted-foreground pl-11">
            Or click the dropdown arrow (▼) next to the tab bar and select &quot;Settings&quot;.
          </p>
        </div>

        {/* Step 2 */}
        <div className="space-y-3 rounded-xl border border-border/50 bg-card/50 p-4">
          <div className="flex items-center gap-3">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground font-bold">
              2
            </div>
            <h3 className="font-semibold">Add a New Profile</h3>
          </div>
          <p className="text-sm text-muted-foreground pl-11">
            In the left sidebar, scroll down and click{" "}
            <span className="inline-flex items-center gap-1 rounded bg-muted px-1.5 py-0.5 font-medium">
              <Plus className="h-3 w-3" /> Add a new profile
            </span>
          </p>
          <p className="text-sm text-muted-foreground pl-11">
            Then click &quot;New empty profile&quot;.
          </p>
        </div>

        {/* Step 3 */}
        <div className="space-y-3 rounded-xl border border-border/50 bg-card/50 p-4">
          <div className="flex items-center gap-3">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground font-bold">
              3
            </div>
            <h3 className="font-semibold">Configure the Profile</h3>
          </div>
          <div className="pl-11 space-y-4">
            <div>
              <p className="text-sm font-medium mb-2">Name:</p>
              <code className="block rounded bg-muted px-3 py-2 font-mono text-sm">
                My VPS
              </code>
              <p className="text-xs text-muted-foreground mt-1">
                (or whatever name you prefer, like &quot;ACFS Server&quot; or &quot;Ubuntu VPS&quot;)
              </p>
            </div>
            <div>
              <p className="text-sm font-medium mb-2">Command line:</p>
              <div className="relative">
                <code className="block rounded bg-muted px-3 py-2 pr-12 font-mono text-sm overflow-x-auto">
                  {sshCommandLine}
                </code>
                <Button
                  variant="ghost"
                  size="icon"
                  className="absolute right-1 top-1/2 -translate-y-1/2 h-8 w-8"
                  onClick={handleCopy}
                >
                  {copied ? (
                    <Check className="h-4 w-4 text-[oklch(0.72_0.19_145)]" />
                  ) : (
                    <Copy className="h-4 w-4" />
                  )}
                </Button>
              </div>
              <p className="text-xs text-muted-foreground mt-1">
                This is your personalized SSH command with your VPS IP ({displayIP}).
              </p>
            </div>
            <div>
              <p className="text-sm font-medium mb-2">Starting directory (optional):</p>
              <code className="block rounded bg-muted px-3 py-2 font-mono text-sm">
                %USERPROFILE%
              </code>
            </div>
            <div>
              <p className="text-sm font-medium mb-2">Icon (optional):</p>
              <p className="text-sm text-muted-foreground">
                You can pick any icon. The &quot;penguin&quot; emoji (🐧) or a cloud (☁️) work nicely for a Linux server.
              </p>
            </div>
          </div>
        </div>

        {/* Step 4 */}
        <div className="space-y-3 rounded-xl border border-border/50 bg-card/50 p-4">
          <div className="flex items-center gap-3">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary text-primary-foreground font-bold">
              4
            </div>
            <h3 className="font-semibold">Save and Test</h3>
          </div>
          <p className="text-sm text-muted-foreground pl-11">
            Click{" "}
            <span className="inline-flex items-center gap-1 rounded bg-primary/20 px-1.5 py-0.5 font-medium text-primary">
              <Save className="h-3 w-3" /> Save
            </span>
            {" "}at the bottom of the page.
          </p>
          <p className="text-sm text-muted-foreground pl-11">
            Now click the dropdown arrow (▼) next to your tabs — you should see your new &quot;My VPS&quot; profile!
            Click it to connect.
          </p>
        </div>
      </div>

      {/* What you'll see */}
      <OutputPreview title="When you click your new profile:">
        <div className="space-y-1 font-mono text-xs">
          <p className="text-muted-foreground">Connecting to ubuntu@{displayIP}...</p>
          <p className="text-[oklch(0.72_0.19_145)]">Welcome to Ubuntu 25.10</p>
          <p className="text-[oklch(0.72_0.19_145)]">ubuntu@vps:~$</p>
        </div>
      </OutputPreview>

      {/* Optional: Make it default */}
      <AlertCard variant="info" icon={Settings} title="Optional: Make it your default profile">
        <div className="space-y-2 text-sm">
          <p>
            If you want Windows Terminal to open directly to your VPS:
          </p>
          <ol className="list-decimal list-inside space-y-1">
            <li>Go to Settings → Startup</li>
            <li>Under &quot;Default profile&quot;, select your new &quot;My VPS&quot; profile</li>
            <li>Click Save</li>
          </ol>
          <p className="text-muted-foreground">
            Now every time you open Windows Terminal, it will connect to your VPS automatically!
          </p>
        </div>
      </AlertCard>

      {/* Beginner Guide */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="What is Windows Terminal?">
            Windows Terminal is Microsoft&apos;s modern terminal app. It&apos;s better than the
            old Command Prompt because it supports tabs, colors, and customization.
            <br /><br />
            If you don&apos;t have it installed, you can get it free from the{" "}
            <a
              href="https://apps.microsoft.com/detail/9n0dx20hk701"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1 text-primary hover:underline"
            >
              Microsoft Store
              <ExternalLink className="h-3 w-3" />
            </a>
            .
          </GuideExplain>

          <GuideSection title="Troubleshooting">
            <div className="space-y-4">
              <div>
                <p className="font-medium">&quot;Permission denied&quot; error</p>
                <p className="text-sm text-muted-foreground">
                  Make sure your SSH key file exists at{" "}
                  <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">
                    %USERPROFILE%\.ssh\acfs_ed25519
                  </code>
                  . If you used a different key name, update the command line accordingly.
                </p>
              </div>
              <div>
                <p className="font-medium">&quot;Connection refused&quot; error</p>
                <p className="text-sm text-muted-foreground">
                  Double-check that your VPS IP ({displayIP}) is correct and the server is running.
                </p>
              </div>
              <div>
                <p className="font-medium">&quot;Host key verification failed&quot;</p>
                <p className="text-sm text-muted-foreground">
                  This can happen if you rebuilt your VPS. You may need to remove the old key from{" "}
                  <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">
                    %USERPROFILE%\.ssh\known_hosts
                  </code>
                  .
                </p>
              </div>
            </div>
          </GuideSection>

          <GuideTip>
            You can create multiple profiles for different servers! Just repeat these steps
            with different names and IP addresses.
          </GuideTip>
        </div>
      </SimplerGuide>

      {/* Back button */}
      <div className="flex justify-start pt-4">
        <Button onClick={handleBack} variant="outline" size="lg" disableMotion>
          <ArrowLeft className="mr-2 h-4 w-4" />
          Back to previous page
        </Button>
      </div>
    </div>
  );
}
