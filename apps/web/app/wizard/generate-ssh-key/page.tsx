"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Key } from "lucide-react";
import { Button } from "@/components/ui/button";
import { CommandCard } from "@/components/command-card";
import { AlertCard, DetailsSection } from "@/components/alert-card";
import { markStepComplete } from "@/lib/wizardSteps";
import { useUserOS, useMounted } from "@/lib/userPreferences";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
  GuideCaution,
} from "@/components/simpler-guide";

export default function GenerateSSHKeyPage() {
  const router = useRouter();
  const [os] = useUserOS();
  const [isNavigating, setIsNavigating] = useState(false);
  const mounted = useMounted();

  // Redirect if no OS selected (after hydration)
  useEffect(() => {
    if (mounted && os === null) {
      router.push("/wizard/os-selection");
    }
  }, [mounted, os, router]);

  const handleContinue = useCallback(() => {
    markStepComplete(3);
    setIsNavigating(true);
    router.push("/wizard/rent-vps");
  }, [router]);

  if (!mounted || !os) {
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
          This is your secure &quot;login key&quot; for connecting to your VPS.
        </p>
      </div>

      {/* Explanation */}
      <AlertCard variant="info" title="How SSH keys work">
        You&apos;re creating a <strong className="text-foreground">key pair</strong>: a private key (stays on
        your computer) and a public key (you&apos;ll paste into your VPS
        provider). Think of it like a lock and key — you share the lock, but
        only you have the key.
      </AlertCard>

      {/* Step 1: Generate */}
      <div className="space-y-4">
        <h2 className="text-xl font-semibold">Step 1: Generate the key</h2>
        <p className="text-sm text-muted-foreground">
          Run this command in your terminal. Press <strong>Enter</strong> twice
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

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg">
          {isNavigating ? "Loading..." : "I copied my public key"}
        </Button>
      </div>
    </div>
  );
}
