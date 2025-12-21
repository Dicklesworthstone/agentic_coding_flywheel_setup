"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Key } from "lucide-react";
import { Button } from "@/components/ui/button";
import { CommandCard } from "@/components/command-card";
import { AlertCard, DetailsSection } from "@/components/alert-card";
import { markStepComplete } from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import { useUserOS } from "@/lib/userPreferences";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
  GuideCaution,
} from "@/components/simpler-guide";
import { Jargon } from "@/components/jargon";

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
      router.push("/wizard/os-selection");
    }
  }, [ready, os, router]);

  const handleContinue = useCallback(() => {
    markComplete();
    markStepComplete(3);
    setIsNavigating(true);
    router.push("/wizard/rent-vps");
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
        your computer) and a <Jargon term="public-key">public key</Jargon> (you&apos;ll paste into your <Jargon term="vps">VPS</Jargon>{" "}
        provider). Think of it like a lock and key — you share the lock, but
        only you have the key.
      </AlertCard>

      {/* Step 1: Generate */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">Step 1: Generate the key</h2>
        <p className="text-sm text-muted-foreground">
          Run this command in your <Jargon term="terminal">terminal</Jargon>. Press <strong>Enter</strong> twice
          when asked for a passphrase (leave it empty for now).
        </p>
        <CommandCard
          command='ssh-keygen -t ed25519 -C "acfs" -f ~/.ssh/acfs_ed25519'
          windowsCommand='ssh-keygen -t ed25519 -C "acfs" -f $HOME\\.ssh\\acfs_ed25519'
          showCheckbox
          persistKey="generate-ssh-key"
        />
      </div>

      {/* Step 2: Copy public key */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">Step 2: Copy your public key</h2>
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
      <AlertCard variant="warning" title="Keep your public key handy">
        You&apos;ll paste this in the next step when setting up your VPS.
        Copy it somewhere safe like a notes app.
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
          <GuideExplain term="SSH Key">
            An SSH key is like a special password that lets you securely connect
            to another computer over the internet.
            <br /><br />
            Unlike regular passwords that you type, SSH keys are files stored on
            your computer. There are always <strong>two files</strong>:
            <br /><br />
            <strong>1. Private key</strong> — This is your secret key. It stays on YOUR
            computer and you never share it with anyone. It&apos;s like the key to
            your house.
            <br /><br />
            <strong>2. Public key</strong> — This is the one you share. You&apos;ll give
            this to your VPS provider. It&apos;s like giving someone a copy of your
            lock so they know it&apos;s really you when you connect.
          </GuideExplain>

          <GuideSection title="Detailed Step-by-Step Instructions">
            <div className="space-y-4">
              <GuideStep number={1} title="Open your terminal">
                {os === "mac" ? (
                  <>
                    Open the terminal app you installed (Ghostty or WezTerm).
                    You can press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">⌘</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Space</kbd>,
                    type the name, and press Enter.
                  </>
                ) : (
                  <>
                    Open Windows Terminal. Click Start, type &quot;Terminal&quot;,
                    and click on Windows Terminal.
                  </>
                )}
              </GuideStep>

              <GuideStep number={2} title="Copy the command">
                Look at the gray box above that shows the ssh-keygen command.
                Click the <strong>copy button</strong> (it looks like two overlapping squares)
                on the right side of the box. This copies the command to your clipboard.
              </GuideStep>

              <GuideStep number={3} title="Paste and run the command">
                Click inside the terminal window to make sure it&apos;s active.
                Then paste the command:
                <ul className="mt-2 list-disc space-y-1 pl-5">
                  <li><strong>Mac:</strong> Press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">⌘</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">V</kbd></li>
                  <li><strong>Windows:</strong> Right-click inside the terminal OR press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Ctrl</kbd> + <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">V</kbd></li>
                </ul>
                <p className="mt-2">Then press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd> to run it.</p>
              </GuideStep>

              <GuideStep number={4} title="Answer the prompts">
                The terminal will ask you two questions. For both, just press
                <kbd className="ml-1 rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd> without typing anything:
                <br /><br />
                <strong>First prompt:</strong> &quot;Enter passphrase&quot;
                → Just press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd> (leave it empty)
                <br /><br />
                <strong>Second prompt:</strong> &quot;Enter same passphrase again&quot;
                → Press <kbd className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">Enter</kbd> again
                <br /><br />
                <em className="text-xs">
                  Note: Not using a passphrase is fine for this purpose. It makes things simpler.
                </em>
              </GuideStep>

              <GuideStep number={5} title="Success!">
                You should see a message like &quot;Your identification has been saved&quot;
                and some ASCII art that looks like a random pattern in a box.
                This means your key was created!
              </GuideStep>
            </div>
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
                  <li><strong>Windows:</strong> Triple-click to select, then right-click to copy</li>
                </ul>
              </GuideStep>

              <GuideStep number={3} title="Save it somewhere safe">
                Open a notes app (like Notes on Mac, or Notepad on Windows) and paste your
                public key there. You&apos;ll need it in the next step when setting up your VPS.
              </GuideStep>
            </div>
          </GuideSection>

          <GuideTip>
            Your public key looks something like this:
            <code className="mt-2 block overflow-x-auto rounded bg-muted p-2 font-mono text-xs">
              ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGx... acfs
            </code>
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
              <strong>&quot;Command not found&quot;</strong> — Make sure you&apos;re in the terminal,
              not in a web browser or text editor.
              <br /><br />
              <strong>&quot;Permission denied&quot;</strong> — Try this command first, then run the
              ssh-keygen command again:
              <code className="my-2 block rounded bg-muted px-3 py-2 font-mono text-xs">
                mkdir -p ~/.ssh && chmod 700 ~/.ssh
              </code>
              <strong>&quot;File already exists&quot;</strong> — You already have a key! You can
              use your existing key, or type &quot;y&quot; and press Enter to overwrite it.
            </p>
          </GuideSection>
        </div>
      </SimplerGuide>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg">
          {isNavigating ? "Loading..." : "I copied my public key"}
        </Button>
      </div>
    </div>
  );
}
