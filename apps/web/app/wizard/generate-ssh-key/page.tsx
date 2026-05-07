"use client";

import type { ReactNode } from "react";
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Key, ShieldCheck, ExternalLink } from "lucide-react";
import { Button } from "@/components/ui/button";
import { CommandCard } from "@/components/command-card";
import { CodeBlock } from "@/components/ui/code-block";
import { AlertCard, DetailsSection, OutputPreview } from "@/components/alert-card";
import { markStepComplete } from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { useUserOS, type OperatingSystem } from "@/lib/userPreferences";
import { withCurrentSearch } from "@/lib/utils";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
  GuideCaution,
} from "@/components/simpler-guide";
import { Jargon } from "@/components/jargon";

const GENERATE_SSH_KEY_COMMAND = [
  "if [ -f ~/.ssh/acfs_ed25519 ]; then",
  "ssh-keygen -y -f ~/.ssh/acfs_ed25519 > ~/.ssh/acfs_ed25519.pub;",
  "else",
  'ssh-keygen -t ed25519 -C "acfs" -f ~/.ssh/acfs_ed25519 -N "";',
  "fi",
].join(" ");

const GENERATE_SSH_KEY_WINDOWS_COMMAND = [
  "if (Test-Path $HOME\\.ssh\\acfs_ed25519) {",
  "ssh-keygen -y -f $HOME\\.ssh\\acfs_ed25519 | Set-Content $HOME\\.ssh\\acfs_ed25519.pub",
  "} else {",
  'ssh-keygen -t ed25519 -C "acfs" -f $HOME\\.ssh\\acfs_ed25519 -N ""',
  "}",
].join(" ");

const OS_DISPLAY_NAMES: Record<OperatingSystem, string> = {
  mac: "Mac",
  linux: "Linux",
  windows: "Windows",
};

const SSH_FOLDER_PATHS: Record<OperatingSystem, string> = {
  mac: "/Users/yourname/.ssh/",
  linux: "/home/yourname/.ssh/",
  windows: "C:\\Users\\yourname\\.ssh\\",
};

const OPEN_TERMINAL_INSTRUCTIONS: Record<OperatingSystem, ReactNode> = {
  mac: (
    <>
      Open the terminal app you installed (Ghostty or WezTerm).
      You can press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">⌘</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Space</kbd>,
      type the name, and press Enter.
    </>
  ),
  linux: (
    <>
      Open your terminal emulator. On most Linux distributions,
      press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Ctrl</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Alt</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">T</kbd>,
      or find Terminal in your applications menu.
    </>
  ),
  windows: (
    <>
      Open Windows Terminal. Click Start, type &quot;Terminal&quot;,
      and click on Windows Terminal.
    </>
  ),
};

export default function GenerateSSHKeyPage() {
  const router = useRouter();
  const [os, , osLoaded] = useUserOS();
  const [isNavigating, setIsNavigating] = useState(false);
  const ready = osLoaded;

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "generate_ssh_key",
    stepNumber: 3,
    stepTitle: "Generate SSH Key",
  });

  // Redirect if no OS selected (after hydration)
  useEffect(() => {
    if (!ready) return;
    if (os === null) {
      router.push(withCurrentSearch("/wizard/os-selection"));
    }
  }, [ready, os, router]);

  const handleContinue = useCallback(() => {
    markComplete();
    markStepComplete(3);
    setIsNavigating(true);
    router.push(withCurrentSearch("/wizard/rent-vps"));
  }, [router, markComplete]);

  if (!ready || !os) {
    return (
      <div className="flex items-center justify-center py-12">
        <Key className="h-8 w-8 animate-pulse text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/20">
            <Key className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              Create your SSH key
            </h1>
            <p className="text-sm text-muted-foreground">
              ~2 min
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          This is your secure &quot;login key&quot; for connecting to your <Jargon term="vps">VPS</Jargon>.
        </p>
      </div>

      {/* Explanation */}
      <AlertCard variant="info" title="How SSH keys work">
        You&apos;re creating a <strong className="text-foreground">key pair</strong>: a <Jargon term="private-key">private key</Jargon> (stays on
        your computer) and a <Jargon term="public-key">public key</Jargon> (safe to share when setting up server login).
        Think of it like a lock and key: you share the lock, but only you have the key.
      </AlertCard>

      {/* ~/.ssh folder explanation */}
      <AlertCard variant="tip" title="Where are SSH keys stored?">
        <p className="mb-2">
          SSH keys are stored in a special folder called <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">~/.ssh</code> on your computer.
        </p>
        <ul className="space-y-1 text-sm">
          <li>
            <strong className="text-foreground">On {OS_DISPLAY_NAMES[os]}:</strong>{" "}
            <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">
              {SSH_FOLDER_PATHS[os]}
            </code>
          </li>
          <li className="text-muted-foreground">
            The <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">~</code> symbol is shorthand for your home folder.
          </li>
          <li className="text-muted-foreground">
            The <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">.</code> prefix makes it a hidden folder (that&apos;s normal for config files).
          </li>
        </ul>
      </AlertCard>

      {/* Privacy assurance */}
      <div className="flex gap-3 rounded-xl border border-[oklch(0.72_0.19_145/0.25)] bg-[oklch(0.72_0.19_145/0.05)] p-3 sm:p-4">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-[oklch(0.72_0.19_145/0.15)] sm:h-9 sm:w-9">
          <ShieldCheck className="h-4 w-4 text-[oklch(0.72_0.19_145)] sm:h-5 sm:w-5" />
        </div>
        <div className="min-w-0 space-y-1">
          <p className="text-[13px] font-medium leading-tight text-[oklch(0.82_0.12_145)] sm:text-sm">
            Your keys never leave your computer
          </p>
          <p className="text-[12px] leading-relaxed text-muted-foreground sm:text-[13px]">
            These commands run <strong className="text-foreground/80">entirely on your machine</strong>. This website cannot see, access, or store your SSH keys.
            We&apos;re just showing you what to type. The{" "}
            <a
              href="https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-0.5 font-medium text-[oklch(0.75_0.18_195)] hover:underline"
            >
              entire codebase is open source
              <ExternalLink className="h-3 w-3" />
            </a>.
          </p>
        </div>
      </div>

      {/* Step 1: Prepare SSH directory */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">Step 1: Make sure the SSH folder exists</h2>
        <p className="text-sm text-muted-foreground">
          This creates the folder where your key files will be saved. On Windows, PowerShell only creates it if it is missing.
        </p>
        <CommandCard
          command="mkdir -p ~/.ssh && chmod 700 ~/.ssh"
          windowsCommand="if (!(Test-Path $HOME\\.ssh)) { New-Item -ItemType Directory -Path $HOME\\.ssh | Out-Null }"
          showCheckbox
          persistKey="prepare-ssh-folder"
        />
      </div>

      <div className="space-y-4">
        <h2 className="text-xl font-semibold">Step 2: Generate or reuse the key</h2>
        <p className="text-sm text-muted-foreground">
          Run this command in your <Jargon term="terminal">terminal</Jargon>. It is safe to rerun:
          if the ACFS key already exists, it reuses it and refreshes the public key file.
        </p>
        <div className="rounded-lg border border-border/50 bg-muted/30 p-3 text-sm">
          <div className="space-y-2">
            <p><strong className="text-foreground">If the key is missing:</strong> <span className="text-muted-foreground">it creates a new Ed25519 key with an empty passphrase.</span></p>
            <p><strong className="text-foreground">If the key already exists:</strong> <span className="text-muted-foreground">it does not overwrite your private key.</span></p>
            <p><strong className="text-foreground">No prompts expected:</strong> <span className="text-muted-foreground">you should not need to answer an overwrite or passphrase question.</span></p>
          </div>
        </div>
        <CommandCard
          command={GENERATE_SSH_KEY_COMMAND}
          windowsCommand={GENERATE_SSH_KEY_WINDOWS_COMMAND}
          showCheckbox
          persistKey="generate-ssh-key"
        />
      </div>

      {/* Step 3: Copy public key */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">Step 3: Copy your public key</h2>
        <p className="text-sm text-muted-foreground">
          Run this command and copy the entire output. It starts with{" "}
          <code className="rounded bg-muted px-1 py-0.5 text-xs">
            ssh-ed25519
          </code>
          .
        </p>
        <CommandCard
          command="cat ~/.ssh/acfs_ed25519.pub"
          windowsCommand="type $HOME\\.ssh\\acfs_ed25519.pub"
          showCheckbox
          persistKey="copy-ssh-pubkey"
        />
      </div>

      {/* Important note */}
      <AlertCard variant="warning" title="Save your public key for later">
        Save this somewhere safe like a notes app. If your VPS was created with password-only access,
        you may need it for the follow-up SSH key command after installation. Do not paste the same
        public key into multiple setup steps; if that already happened, ACFS skips exact duplicate
        key lines when it copies server keys.
      </AlertCard>

      {/* Troubleshooting */}
      <DetailsSection summary="Having trouble? Click for common fixes">
        <div className="space-y-4 text-sm">
          <div>
            <p className="font-medium text-foreground">
              &quot;No such file or directory&quot; error
            </p>
            <p className="text-muted-foreground">
              Create the .ssh folder first:{" "}
              <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">mkdir -p ~/.ssh</code>
            </p>
          </div>
          <div>
            <p className="font-medium text-foreground">&quot;Permission denied&quot; error</p>
            <p className="text-muted-foreground">
              Fix folder permissions:{" "}
              <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">chmod 700 ~/.ssh</code>
            </p>
          </div>
          <div>
            <p className="font-medium text-foreground">
              Key file already exists
            </p>
            <p className="text-muted-foreground">
              If you already have a key, you can use that one. Just copy the
              .pub file content.
            </p>
          </div>
        </div>
      </DetailsSection>

      {/* Beginner Guide */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="an SSH Key">
            An SSH key is like a special password that lets you securely connect
            to another computer over the internet.
            <br /><br />
            Unlike regular passwords that you type, SSH keys are files stored on
            your computer. There are always <strong>two files</strong>:
            <br /><br />
            <strong>1. Private key:</strong> This is your secret key. It stays on YOUR
            computer and you never share it with anyone. It&apos;s like the key to
            your house.
            <br /><br />
            <strong>2. Public key:</strong> This is the one you share. You&apos;ll give
            this to your VPS provider. It&apos;s like giving someone a copy of your
            lock so they know it&apos;s really you when you connect.
          </GuideExplain>

          <GuideSection title="Detailed Step-by-Step Instructions">
            <div className="space-y-4">
              <GuideStep number={1} title="Open your terminal">
                {OPEN_TERMINAL_INSTRUCTIONS[os]}
              </GuideStep>

              <GuideStep number={2} title="Copy the command">
                Look at the gray box above that shows the key command.
                Click the <strong>copy button</strong> (it looks like two overlapping squares)
                on the right side of the box. This copies the command to your clipboard.
              </GuideStep>

              <GuideStep number={3} title="Paste and run the command">
                Click inside the terminal window to make sure it&apos;s active.
                Then paste the command:
                <ul className="mt-2 list-disc space-y-1 pl-5">
                  <li><strong>Mac:</strong> Press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">⌘</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">V</kbd></li>
                  <li><strong>Linux:</strong> Press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Ctrl</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Shift</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">V</kbd></li>
                  <li><strong>Windows:</strong> Right-click inside the terminal OR press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Ctrl</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">V</kbd></li>
                </ul>
                <p className="mt-2">Then press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd> to run it.</p>
              </GuideStep>

              <GuideStep number={4} title="Let the command finish">
                The command handles the file path and empty passphrase for you. It also checks
                for an existing ACFS key before creating anything new.

                <div className="mt-4 space-y-4">
                  <div>
                    <p className="mb-2 font-medium text-foreground">If this is your first run</p>
                    <OutputPreview title="You will see:">
                      <p className="text-[oklch(0.72_0.19_145)]">Your identification has been saved in /Users/you/.ssh/acfs_ed25519</p>
                      <p className="text-[oklch(0.72_0.19_145)]">Your public key has been saved in /Users/you/.ssh/acfs_ed25519.pub</p>
                    </OutputPreview>
                    <p className="mt-2 text-sm text-muted-foreground">
                      The new key was created without asking you where to save it or what passphrase to use.
                    </p>
                    <div className="mt-2 rounded border border-border/30 bg-muted/20 p-2 text-xs text-muted-foreground">
                      <strong className="text-foreground">What this means:</strong> The path shown (like{" "}
                      <code className="rounded bg-muted px-1 py-0.5 font-mono">/Users/you/.ssh/acfs_ed25519</code>) is where your
                      key files will be saved. The <code className="rounded bg-muted px-1 py-0.5 font-mono">.ssh</code> folder
                      is a standard location for SSH keys on all computers.
                    </div>
                  </div>

                  <div>
                    <p className="mb-2 font-medium text-foreground">If you already ran this before</p>
                    <OutputPreview title="You may see little or no output">
                      <p className="text-[oklch(0.72_0.19_145)]">The command rebuilds acfs_ed25519.pub from your existing private key.</p>
                    </OutputPreview>
                    <p className="mt-2 text-sm text-muted-foreground">
                      It should not ask whether to overwrite your existing key.
                    </p>
                    <div className="mt-2 rounded border border-border/30 bg-muted/20 p-2 text-xs text-muted-foreground">
                      <strong className="text-foreground">Why no passphrase?</strong> A passphrase would add an extra password
                      you&apos;d have to type every time you connect. For a development VPS that you control, this extra
                      security isn&apos;t necessary and would slow you down. Your private key file itself is already secure
                      because it never leaves your computer.
                    </div>
                  </div>
                </div>
              </GuideStep>

              <GuideStep number={5} title="Success!">
                When a new key is created, you&apos;ll see a confirmation:
                <div className="mt-3">
                  <OutputPreview title="You will see something like:">
                    <p className="text-[oklch(0.72_0.19_145)]">Your identification has been saved in /Users/you/.ssh/acfs_ed25519</p>
                    <p className="text-[oklch(0.72_0.19_145)]">Your public key has been saved in /Users/you/.ssh/acfs_ed25519.pub</p>
                    <p className="mt-2 text-muted-foreground">The key fingerprint is:</p>
                    <p className="text-muted-foreground">SHA256:xYz123abc... acfs</p>
                    <p className="mt-2 text-muted-foreground">The key&apos;s randomart image is:</p>
                    <pre className="text-xs text-muted-foreground">{`+--[ED25519 256]--+
|     .o+*o.      |
|    . o.=o+ .    |
|     . =.= o     |
|      o + = .    |
|     . S o = .   |
|      o + o +    |
|     . = = * o   |
|    . o.=.X.*.   |
|     ..+.o+E=.   |
+----[SHA256]-----+`}</pre>
                  </OutputPreview>
                </div>
                <p className="mt-3 text-sm">
                  <strong className="text-[oklch(0.72_0.19_145)]">The randomart pattern means it worked!</strong> You now have SSH keys.
                </p>
              </GuideStep>
            </div>
          </GuideSection>

          <GuideSection title="Verify Your Key Was Created">
            <p className="mb-4">
              Let&apos;s make sure your keys were created correctly:
            </p>
            <div className="space-y-4">
              <GuideStep number={1} title="Check the files exist">
                <CommandCard
                  command="ls -la ~/.ssh/acfs_*"
                  windowsCommand="dir $HOME\\.ssh\\acfs_*"
                  description="List your new key files"
                />
                <p className="mt-3 text-sm text-muted-foreground">
                  You should see two files:
                </p>
                <ul className="mt-2 list-disc space-y-1 pl-5 text-sm">
                  <li>
                    <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">acfs_ed25519</code>
                    <span className="text-muted-foreground"> — Your <strong className="text-foreground">private key</strong> (keep this secret!)</span>
                  </li>
                  <li>
                    <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">acfs_ed25519.pub</code>
                    <span className="text-muted-foreground"> — Your <strong className="text-foreground">public key</strong> (this gets shared)</span>
                  </li>
                </ul>
              </GuideStep>
            </div>

            <GuideTip>
              Think of it like a mailbox: the <strong>public key</strong> is your address
              (you share it so people can send you mail), and the <strong>private key</strong>
              is your mailbox key (only you have it to open your mail).
            </GuideTip>
          </GuideSection>

          <GuideSection title="Now Copy Your Public Key">
            <div className="space-y-4">
              <GuideStep number={1} title="Run the second command">
                Now look at the second gray command box (the &quot;cat&quot; or &quot;type&quot; command).
                Click its copy button and paste it into the terminal, then press Enter.
              </GuideStep>

              <GuideStep number={2} title="Select and copy the output">
                You&apos;ll see a long string of text that starts with{" "}
                <code className="rounded bg-muted px-1 py-0.5 font-mono text-xs">ssh-ed25519</code>.
                This is your public key!
                <br /><br />
                <strong>To copy it:</strong>
                <ul className="mt-2 list-disc space-y-1 pl-5">
                  <li><strong>Mac:</strong> Triple-click to select the whole line, then <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">⌘</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">C</kbd></li>
                  <li><strong>Linux:</strong> Triple-click to select the whole line, then <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Ctrl</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Shift</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">C</kbd></li>
                  <li><strong>Windows:</strong> Triple-click to select, then right-click to copy</li>
                </ul>
              </GuideStep>

              <GuideStep number={3} title="Save it somewhere safe">
                Open a notes app (like Notes on Mac, Notepad on Windows, or any text editor on Linux) and paste your
                public key there. You may need it later for the follow-up SSH key command after the installer finishes
                (not when creating the VPS—we&apos;ll use a password for that).
              </GuideStep>
            </div>
          </GuideSection>

          <GuideTip>
            Your public key looks something like this:
            <div className="mt-2">
              <CodeBlock code="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGx... acfs" variant="compact" />
            </div>
            Make sure you copy the WHOLE thing, from &quot;ssh-ed25519&quot; to &quot;acfs&quot;!
          </GuideTip>

          <GuideCaution>
            <strong>Never share your private key!</strong> The private key is the file
            WITHOUT &quot;.pub&quot; at the end. Only share the public key (the one
            that ends in &quot;.pub&quot;). If anyone asks for your private key,
            that&apos;s a scam.
          </GuideCaution>

          <GuideSection title="What if something went wrong?">
            <p>
              <strong>&quot;Command not found&quot;:</strong> Make sure you&apos;re in the terminal,
              not in a web browser or text editor.
              <br /><br />
              <strong>&quot;Permission denied&quot;:</strong> Try this command first, then run the
              ssh-keygen command again:
              <div className="my-2">
                <CodeBlock code="mkdir -p ~/.ssh && chmod 700 ~/.ssh" variant="compact" />
              </div>
              <strong>&quot;File already exists&quot;:</strong> Make sure you copied the full command
              from Step 2. The ACFS command checks for an existing private key first and should
              not ask to overwrite it.
            </p>
          </GuideSection>
        </div>
      </SimplerGuide>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg" disableMotion>
          {isNavigating ? "Loading..." : "I saved my public key"}
        </Button>
      </div>
    </div>
  );
}
