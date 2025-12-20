"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Key, AlertCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { CommandCard } from "@/components/command-card";
import { markStepComplete } from "@/lib/wizardSteps";
import { useUserOS, useMounted } from "@/lib/userPreferences";

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
        <h1 className="text-3xl font-bold tracking-tight">
          Create your SSH key
        </h1>
        <p className="text-lg text-muted-foreground">
          This is your secure &quot;login key&quot; for connecting to your VPS.
        </p>
      </div>

      {/* Explanation */}
      <Card className="border-blue-200 bg-blue-50 p-4 dark:border-blue-900 dark:bg-blue-950">
        <p className="text-sm text-blue-800 dark:text-blue-200">
          You&apos;re creating a <strong>key pair</strong>: a private key (stays on
          your computer) and a public key (you&apos;ll paste into your VPS
          provider). Think of it like a lock and key — you share the lock, but
          only you have the key.
        </p>
      </Card>

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
      <Card className="border-amber-200 bg-amber-50 p-4 dark:border-amber-900 dark:bg-amber-950">
        <div className="flex gap-3">
          <AlertCircle className="mt-0.5 h-5 w-5 shrink-0 text-amber-600 dark:text-amber-400" />
          <div className="space-y-1">
            <p className="font-medium text-amber-800 dark:text-amber-200">
              Keep your public key handy
            </p>
            <p className="text-sm text-amber-700 dark:text-amber-300">
              You&apos;ll paste this in the next step when setting up your VPS.
              Copy it somewhere safe like a notes app.
            </p>
          </div>
        </div>
      </Card>

      {/* Troubleshooting */}
      <details className="group">
        <summary className="cursor-pointer text-sm font-medium text-muted-foreground hover:text-foreground">
          Having trouble? Click for common fixes
        </summary>
        <div className="mt-4 space-y-3 rounded-lg border bg-muted/30 p-4 text-sm">
          <div>
            <p className="font-medium">
              &quot;No such file or directory&quot; error
            </p>
            <p className="text-muted-foreground">
              Create the .ssh folder first:{" "}
              <code className="rounded bg-muted px-1">mkdir -p ~/.ssh</code>
            </p>
          </div>
          <div>
            <p className="font-medium">&quot;Permission denied&quot; error</p>
            <p className="text-muted-foreground">
              Fix folder permissions:{" "}
              <code className="rounded bg-muted px-1">chmod 700 ~/.ssh</code>
            </p>
          </div>
          <div>
            <p className="font-medium">
              Key file already exists
            </p>
            <p className="text-muted-foreground">
              If you already have a key, you can use that one. Just copy the
              .pub file content.
            </p>
          </div>
        </div>
      </details>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg">
          {isNavigating ? "Loading..." : "I copied my public key"}
        </Button>
      </div>
    </div>
  );
}
