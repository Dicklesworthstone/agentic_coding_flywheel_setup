"use client";

import { AlertCircle, Monitor, Server, ArrowRight, Terminal, HelpCircle } from "lucide-react";
import { formatSshTarget } from "@/lib/commandBuilder";
import { cn } from "@/lib/utils";

interface ConnectionCheckProps {
  /** The VPS IP address to show in examples */
  vpsIP?: string;
  /** The SSH username to show in reconnect examples */
  sshUser?: string;
  /** Whether the reconnect example should use the generated SSH key */
  useIdentityFile?: boolean;
  /** Additional class names */
  className?: string;
  /** Whether to show the "Two Computers" explainer */
  showExplainer?: boolean;
  /** Whether to show the "Where Am I?" section */
  showWhereAmI?: boolean;
}

/**
 * A prominent visual component that helps users understand if they're
 * connected to their VPS before running commands.
 */
export function ConnectionCheck({
  vpsIP = "YOUR_VPS_IP",
  sshUser = "ubuntu",
  useIdentityFile = true,
  className,
  showExplainer = false,
  showWhereAmI = true,
}: ConnectionCheckProps) {
  const sshTarget = formatSshTarget(sshUser, vpsIP);
  const promptSuffix = sshUser === "root" ? "#" : "$";
  const alternatePrompt =
    sshUser === "root" ? "ubuntu@vps:~$" : "root@vps:~#";
  const sshCommand = useIdentityFile
    ? `ssh -i ~/.ssh/acfs_ed25519 ${sshTarget}`
    : `ssh ${sshTarget}`;
  const windowsSshCommand = useIdentityFile
    ? `ssh -i %USERPROFILE%\\.ssh\\acfs_ed25519 ${sshTarget}`
    : `ssh ${sshTarget}`;

  return (
    <div className={cn("space-y-4", className)}>
      {/* Main Warning */}
      <div className="rounded-xl border-2 border-[oklch(0.65_0.22_25/0.4)] bg-[oklch(0.65_0.22_25/0.08)] p-4">
        <div className="flex items-start gap-3">
          <AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-[oklch(0.65_0.22_25)]" />
          <div className="space-y-3">
            <div>
              <p className="font-semibold text-[oklch(0.85_0.15_25)]">
                STOP! Are you connected to your VPS?
              </p>
              <p className="mt-1 text-sm text-muted-foreground">
                The command below runs on your <strong className="text-foreground">VPS</strong>, not on your laptop.
                If you&apos;re not connected, the command will fail.
              </p>
            </div>

            {/* Visual comparison */}
            <div className="grid gap-3 sm:grid-cols-2">
              {/* Wrong - Local */}
              <div className="rounded-lg border border-[oklch(0.65_0.22_25/0.3)] bg-[oklch(0.65_0.22_25/0.05)] p-3">
                <div className="flex items-center gap-2 text-sm font-medium text-[oklch(0.65_0.22_25)]">
                  <Monitor className="h-4 w-4" />
                  <span>Wrong - You&apos;re on your laptop</span>
                </div>
                <div className="mt-2 rounded bg-[oklch(0.12_0.01_260)] px-3 py-2 font-mono text-xs">
                  <span className="text-muted-foreground">C:\Users\YourName&gt;</span>
                  <span className="animate-pulse"> _</span>
                </div>
                <p className="mt-2 text-xs text-muted-foreground">
                  or: <code className="text-foreground/70">YourMac:~ yourname$</code>
                </p>
              </div>

              {/* Right - VPS */}
              <div className="rounded-lg border border-[oklch(0.72_0.19_145/0.3)] bg-[oklch(0.72_0.19_145/0.05)] p-3">
                <div className="flex items-center gap-2 text-sm font-medium text-[oklch(0.72_0.19_145)]">
                  <Server className="h-4 w-4" />
                  <span>Correct - You&apos;re on the VPS</span>
                </div>
                <div className="mt-2 rounded bg-[oklch(0.12_0.01_260)] px-3 py-2 font-mono text-xs">
                  <span className="text-[oklch(0.72_0.19_145)]">{sshUser}@vps:~{promptSuffix}</span>
                  <span className="animate-pulse"> _</span>
                </div>
                <p className="mt-2 text-xs text-muted-foreground">
                  or: <code className="text-foreground/70">{alternatePrompt}</code>
                </p>
              </div>
            </div>

            {/* How to connect */}
            <div className="rounded-lg border border-border/50 bg-card/50 p-3">
              <p className="text-sm font-medium">Not connected? Run this first:</p>
              <code className="mt-2 block overflow-x-auto rounded bg-muted px-3 py-2 font-mono text-xs">
                {sshCommand}
              </code>
              <p className="mt-2 text-xs text-muted-foreground">
                On Windows: <code className="text-foreground/70">{windowsSshCommand}</code>
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Two Computers Explainer */}
      {showExplainer && <TwoComputersExplainer />}

      {/* Where Am I section */}
      {showWhereAmI && <WhereAmICheck />}
    </div>
  );
}

/**
 * Explains the "two computers" mental model for beginners
 */
export function TwoComputersExplainer({ className }: { className?: string }) {
  return (
    <div className={cn("rounded-xl border border-[oklch(0.75_0.18_195/0.3)] bg-[oklch(0.75_0.18_195/0.05)] p-4", className)}>
      <div className="flex items-start gap-3">
        <HelpCircle className="mt-0.5 h-5 w-5 shrink-0 text-[oklch(0.75_0.18_195)]" />
        <div className="space-y-3">
          <p className="font-semibold text-foreground">
            Understanding: You have TWO computers
          </p>

          <div className="flex flex-col items-center gap-2 sm:flex-row sm:gap-4">
            {/* Your Computer */}
            <div className="flex-1 rounded-lg border border-border/50 bg-card/50 p-3 text-center">
              <Monitor className="mx-auto h-8 w-8 text-[oklch(0.78_0.16_75)]" />
              <p className="mt-2 font-medium">Your Computer</p>
              <p className="text-xs text-muted-foreground">
                (laptop/desktop)
              </p>
              <p className="mt-1 text-xs text-muted-foreground">
                Windows or Mac
              </p>
            </div>

            {/* Arrow */}
            <div className="flex flex-col items-center">
              <ArrowRight className="h-6 w-6 rotate-90 text-primary sm:rotate-0" />
              <p className="text-xs font-medium text-primary">SSH</p>
            </div>

            {/* VPS */}
            <div className="flex-1 rounded-lg border border-[oklch(0.72_0.19_145/0.3)] bg-[oklch(0.72_0.19_145/0.05)] p-3 text-center">
              <Server className="mx-auto h-8 w-8 text-[oklch(0.72_0.19_145)]" />
              <p className="mt-2 font-medium">Your VPS</p>
              <p className="text-xs text-muted-foreground">
                (remote server)
              </p>
              <p className="mt-1 text-xs text-muted-foreground">
                Linux in the cloud
              </p>
            </div>
          </div>

          <div className="space-y-2 text-sm text-muted-foreground">
            <p>
              <strong className="text-foreground">SSH</strong> is like a phone call to your VPS.
              When you&apos;re &quot;connected via SSH&quot;, everything you type happens on the VPS, not your laptop.
            </p>
            <p>
              <strong className="text-foreground">PowerShell, Command Prompt, or Terminal</strong> on your laptop
              is where you <em>start</em> the SSH connection. But once connected, you&apos;re controlling the VPS.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

/**
 * Quick check to help users verify where they are
 */
export function WhereAmICheck({ className }: { className?: string }) {
  return (
    <details className={cn("group rounded-xl border border-border/50 bg-card/30", className)}>
      <summary className="flex cursor-pointer items-center gap-2 p-4 font-medium hover:bg-muted/50 rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-inset">
        <Terminal className="h-4 w-4 text-primary" />
        <span>How do I know if I&apos;m connected to my VPS?</span>
      </summary>
      <div className="border-t border-border/50 p-4 pt-3">
        <div className="space-y-4 text-sm">
          <p className="text-muted-foreground">
            Look at your terminal prompt (the text before where you type):
          </p>

          <div className="space-y-3">
            <div className="rounded-lg border border-[oklch(0.72_0.19_145/0.3)] bg-[oklch(0.72_0.19_145/0.05)] p-3">
              <p className="font-medium text-[oklch(0.72_0.19_145)]">You ARE connected to your VPS if you see:</p>
              <ul className="mt-2 list-disc space-y-1 pl-5 text-muted-foreground">
                <li><code className="text-foreground">ubuntu@...</code> or <code className="text-foreground">root@...</code></li>
                <li>The prompt ends with <code className="text-foreground">$</code> or <code className="text-foreground">#</code></li>
                <li>A colorful prompt (if you ran the installer already)</li>
              </ul>
            </div>

            <div className="rounded-lg border border-[oklch(0.65_0.22_25/0.3)] bg-[oklch(0.65_0.22_25/0.05)] p-3">
              <p className="font-medium text-[oklch(0.65_0.22_25)]">You are NOT connected (still on your laptop) if you see:</p>
              <ul className="mt-2 list-disc space-y-1 pl-5 text-muted-foreground">
                <li><code className="text-foreground">C:\Users\YourName&gt;</code> (Windows Command Prompt)</li>
                <li><code className="text-foreground">PS C:\Users\YourName&gt;</code> (PowerShell)</li>
                <li><code className="text-foreground">YourMac:~ yourname$</code> (Mac Terminal)</li>
                <li>Any mention of your laptop&apos;s name or your Windows/Mac username</li>
              </ul>
            </div>
          </div>

          <p className="text-muted-foreground">
            <strong className="text-foreground">Still confused?</strong> Type{" "}
            <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">hostname</code>{" "}
            and press Enter. If it shows your laptop&apos;s name (like &quot;DESKTOP-ABC123&quot; or &quot;MacBook-Pro&quot;),
            you&apos;re not connected. If it shows something like &quot;vps-12345&quot;, you&apos;re on the VPS.
          </p>
        </div>
      </div>
    </details>
  );
}
