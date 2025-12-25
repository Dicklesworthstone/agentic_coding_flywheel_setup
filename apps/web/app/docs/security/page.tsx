"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Shield, Sparkles, ExternalLink, AlertTriangle, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Card } from "@/components/ui/card";
import { AlertCard } from "@/components/alert-card";
import { safeGetJSON, safeSetJSON } from "@/lib/utils";

type ChecklistItem = {
  id: string;
  label: string;
  href?: string;
};

const CHECKLIST_STORAGE_KEY = "acfs-security-checklist-v1";

const CHECKLIST_ITEMS: ChecklistItem[] = [
  {
    id: "google-2sv",
    label: "Enable Google 2‑Step Verification (use an authenticator app, not SMS).",
    href: "https://myaccount.google.com/signinoptions/two-step-verification",
  },
  {
    id: "google-recovery",
    label: "Set recovery email + recovery phone (so you can recover access).",
    href: "https://myaccount.google.com/security",
  },
  {
    id: "google-permissions",
    label: "Review and revoke unknown connected apps.",
    href: "https://myaccount.google.com/permissions",
  },
  {
    id: "password-manager",
    label: "Use a password manager for anything that isn’t Google SSO.",
  },
  {
    id: "github-2fa",
    label: "Enable GitHub 2FA (email/password services need their own 2FA).",
    href: "https://github.com/settings/security",
  },
  {
    id: "cloudflare-2fa",
    label: "Enable Cloudflare 2FA (email/password service).",
    href: "https://dash.cloudflare.com/profile/authentication",
  },
];

function linkHost(href: string): string {
  try {
    return new URL(href).host;
  } catch {
    return href;
  }
}

export default function SecurityDocsPage() {
  const itemsById = useMemo(() => new Map(CHECKLIST_ITEMS.map((i) => [i.id, i])), []);
  const [checked, setChecked] = useState<Set<string>>(new Set());

  useEffect(() => {
    const saved = safeGetJSON<string[]>(CHECKLIST_STORAGE_KEY);
    if (Array.isArray(saved)) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- localStorage access must happen after mount (SSR-safe)
      setChecked(new Set(saved.filter((id) => itemsById.has(id))));
    }
  }, [itemsById]);

  const persist = useCallback((next: Set<string>) => {
    safeSetJSON(CHECKLIST_STORAGE_KEY, Array.from(next));
  }, []);

  const toggle = useCallback(
    (id: string) => {
      setChecked((prev) => {
        const next = new Set(prev);
        if (next.has(id)) next.delete(id);
        else next.add(id);
        persist(next);
        return next;
      });
    },
    [persist]
  );

  const reset = useCallback(() => {
    const next = new Set<string>();
    setChecked(next);
    persist(next);
  }, [persist]);

  return (
    <div className="relative mx-auto max-w-3xl space-y-10 px-6 py-12">
      <div className="pointer-events-none absolute inset-0 -z-10 bg-gradient-cosmic opacity-35" />

      {/* Header */}
      <div className="space-y-3">
        <div className="flex items-start gap-3">
          <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-primary/20">
            <Shield className="h-5 w-5 text-primary" />
          </div>
          <div className="min-w-0">
            <h1 className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              Security best practices (Google SSO strategy)
            </h1>
            <p className="mt-1 text-sm text-muted-foreground">
              ACFS is built for velocity. This page covers account security so your “one login everywhere” setup stays safe.
            </p>
          </div>
        </div>

        <div className="text-sm text-muted-foreground">
          <Link href="/" className="text-primary hover:underline">Home</Link>
          <span className="px-2">/</span>
          <span className="text-foreground/80">Docs</span>
          <span className="px-2">/</span>
          <span className="text-foreground/80">Security</span>
        </div>
      </div>

      <AlertCard variant="warning" icon={AlertTriangle} title="Scope note">
        This is <span className="font-medium">account security</span> (SSO, passwords, recovery). It’s not a full VPS-hardening guide.
      </AlertCard>

      {/* Strategy */}
      <Card className="space-y-4 p-6">
        <div className="flex items-center gap-2">
          <Sparkles className="h-4 w-4 text-[oklch(0.78_0.16_75)]" />
          <h2 className="text-lg font-semibold tracking-tight">Why we recommend Google SSO</h2>
        </div>
        <ul className="list-disc space-y-2 pl-5 text-sm text-muted-foreground">
          <li>
            <span className="text-foreground/80">Fewer passwords</span> means fewer weak points.
          </li>
          <li>
            <span className="text-foreground/80">One identity across services</span> makes setup smoother (especially for beginners).
          </li>
          <li>
            <span className="text-foreground/80">Faster recovery</span>: if you lose access to a service, you recover through Google.
          </li>
        </ul>

        <div className="rounded-xl border border-border/50 bg-card/50 p-4 text-sm text-muted-foreground">
          <div className="font-medium text-foreground/90">The model:</div>
          <div className="mt-2 font-mono text-xs leading-relaxed text-muted-foreground">
            Your Google Account
            <br />
            ├── Tailscale (VPS access)
            <br />
            ├── Claude (primary coding agent)
            <br />
            ├── ChatGPT / Codex (secondary agent)
            <br />
            ├── Gemini (optional agent)
            <br />
            ├── Vercel (deployments)
            <br />
            └── Supabase / Convex / Cloudflare (optional)
          </div>
        </div>
      </Card>

      <AlertCard variant="warning" title="The trade-off">
        Centralizing access is powerful, but it creates a{" "}
        <span className="font-medium">single point of failure</span>. That’s why securing your Google account is step zero.
      </AlertCard>

      {/* How to secure Google */}
      <Card className="space-y-4 p-6">
        <h2 className="text-lg font-semibold tracking-tight">Secure your Google account</h2>
        <div className="space-y-3 text-sm text-muted-foreground">
          <p>
            If you do only one thing: enable 2‑Step Verification with an authenticator app (not SMS).
          </p>
          <div className="flex flex-wrap gap-2">
            <a
              href="https://myaccount.google.com/signinoptions/two-step-verification"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1 rounded-lg border border-border/50 bg-card/50 px-3 py-2 text-xs font-medium text-muted-foreground hover:border-primary/30 hover:text-foreground"
            >
              Enable 2‑Step Verification
              <ExternalLink className="h-3 w-3" />
            </a>
            <a
              href="https://landing.google.com/advancedprotection/"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1 rounded-lg border border-border/50 bg-card/50 px-3 py-2 text-xs font-medium text-muted-foreground hover:border-primary/30 hover:text-foreground"
            >
              Advanced Protection Program (security keys)
              <ExternalLink className="h-3 w-3" />
            </a>
          </div>
        </div>
      </Card>

      {/* Services without SSO */}
      <Card className="space-y-4 p-6">
        <h2 className="text-lg font-semibold tracking-tight">Services without Google SSO</h2>
        <p className="text-sm text-muted-foreground">
          Some services don&apos;t support Google SSO (or you may choose not to use it). For those:
        </p>
        <ul className="list-disc space-y-2 pl-5 text-sm text-muted-foreground">
          <li>Use a strong, unique password (password manager recommended).</li>
          <li>Enable the service&apos;s built-in 2FA.</li>
          <li>Prefer authenticator apps or security keys over SMS.</li>
        </ul>
      </Card>

      {/* Password manager */}
      <Card className="space-y-4 p-6">
        <h2 className="text-lg font-semibold tracking-tight">Password manager recommendations</h2>
        <p className="text-sm text-muted-foreground">
          For services without Google SSO, use a password manager to generate and store strong, unique passwords.
        </p>
        <div className="grid gap-3 sm:grid-cols-3">
          <a
            href="https://1password.com/"
            target="_blank"
            rel="noopener noreferrer"
            className="rounded-xl border border-primary/30 bg-primary/5 p-4 transition-colors hover:bg-primary/10"
          >
            <div className="font-medium text-foreground">1Password</div>
            <p className="mt-1 text-xs text-muted-foreground">Best overall. Great UX, developer tools.</p>
          </a>
          <a
            href="https://bitwarden.com/"
            target="_blank"
            rel="noopener noreferrer"
            className="rounded-xl border border-border/50 bg-card/50 p-4 transition-colors hover:border-primary/30"
          >
            <div className="font-medium text-foreground">Bitwarden</div>
            <p className="mt-1 text-xs text-muted-foreground">Best free option. Open-source.</p>
          </a>
          <div className="rounded-xl border border-border/50 bg-card/50 p-4">
            <div className="font-medium text-foreground">Apple Keychain</div>
            <p className="mt-1 text-xs text-muted-foreground">Built into macOS/iOS. Good if already in Apple ecosystem.</p>
          </div>
        </div>
      </Card>

      {/* What if compromised */}
      <Card className="space-y-4 p-6">
        <h2 className="text-lg font-semibold tracking-tight">What if Google gets compromised?</h2>
        <p className="text-sm text-muted-foreground">
          If you suspect unauthorized access, act immediately:
        </p>
        <ol className="list-decimal space-y-2 pl-5 text-sm text-muted-foreground">
          <li><span className="text-foreground/80">Change your Google password</span> from a trusted device.</li>
          <li>
            <span className="text-foreground/80">Revoke all app permissions</span> at{" "}
            <a href="https://myaccount.google.com/permissions" target="_blank" rel="noopener noreferrer" className="text-primary hover:underline">
              myaccount.google.com/permissions
            </a>.
          </li>
          <li>
            <span className="text-foreground/80">Check recent activity</span> at{" "}
            <a href="https://myaccount.google.com/device-activity" target="_blank" rel="noopener noreferrer" className="text-primary hover:underline">
              myaccount.google.com/device-activity
            </a>.
          </li>
          <li><span className="text-foreground/80">Re-authenticate all SSO services</span> (log out and back in).</li>
          <li><span className="text-foreground/80">Enable Advanced Protection</span> to prevent future compromises.</li>
        </ol>
      </Card>

      {/* Checklist */}
      <Card className="space-y-5 p-6">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="space-y-1">
            <h2 className="text-lg font-semibold tracking-tight">Quick security checklist</h2>
            <p className="text-sm text-muted-foreground">
              Track your progress here (saved to localStorage on this device).
            </p>
          </div>
          <Button variant="outline" size="sm" onClick={reset}>
            <RotateCcw className="mr-2 h-4 w-4" />
            Reset
          </Button>
        </div>

        <div className="space-y-3">
          {CHECKLIST_ITEMS.map((item) => {
            const isChecked = checked.has(item.id);
            return (
              <div key={item.id} className="flex items-start gap-3">
                <Checkbox checked={isChecked} onCheckedChange={() => toggle(item.id)} className="mt-0.5" />
                <div className="min-w-0">
                  <div className="text-sm text-foreground/90">{item.label}</div>
                  {item.href && (
                    <a
                      href={item.href}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="mt-1 inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
                    >
                      {linkHost(item.href)}
                      <ExternalLink className="h-3 w-3" />
                    </a>
                  )}
                </div>
              </div>
            );
          })}
        </div>

        <div className="text-xs text-muted-foreground">
          Tip: if you’re in the wizard, go back to <span className="font-mono">Accounts</span> after you’ve secured your Google account.
        </div>
      </Card>
    </div>
  );
}
