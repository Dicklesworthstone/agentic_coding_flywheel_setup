"use client";

import { useCallback, useState } from "react";
import { useRouter } from "next/navigation";
import { ExternalLink, Check, Server, ChevronDown, Cloud } from "lucide-react";
import { Button } from "@/components/ui/button";
import { AlertCard } from "@/components/alert-card";
import { cn } from "@/lib/utils";
import { markStepComplete } from "@/lib/wizardSteps";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
  GuideCaution,
} from "@/components/simpler-guide";

interface ProviderInfo {
  id: string;
  name: string;
  tagline: string;
  url: string;
  pros: string[];
  recommended?: string;
}

const PROVIDERS: ProviderInfo[] = [
  {
    id: "contabo",
    name: "Contabo",
    tagline: "Best value for high specs",
    url: "https://contabo.com/en/vps/",
    pros: [
      "32GB RAM for ~$35/month",
      "Excellent specs-to-price ratio",
      "EU and US data centers",
      "Instant activation",
    ],
    recommended: "Cloud VPS L (6 vCPU, 32GB RAM) — ~$35/mo",
  },
  {
    id: "ovh",
    name: "OVH",
    tagline: "Reliable, good support",
    url: "https://www.ovhcloud.com/en/vps/",
    pros: [
      "Great EU data centers",
      "Good customer support",
      "Solid network performance",
      "Instant activation",
    ],
    recommended: "VPS Comfort (4 vCPU, 16GB) or VPS Elite (8 vCPU, 32GB)",
  },
];

interface ProviderCardProps {
  provider: ProviderInfo;
  isExpanded: boolean;
  onToggle: () => void;
}

function ProviderCard({ provider, isExpanded, onToggle }: ProviderCardProps) {
  return (
    <div className={cn(
      "overflow-hidden rounded-xl border transition-all duration-200",
      isExpanded
        ? "border-primary/30 bg-card/80 shadow-md"
        : "border-border/50 bg-card/50 hover:border-primary/20"
    )}>
      <button
        type="button"
        onClick={onToggle}
        aria-expanded={isExpanded}
        className="flex w-full items-center justify-between p-4 text-left"
      >
        <div className="flex items-center gap-3">
          <div className={cn(
            "flex h-10 w-10 items-center justify-center rounded-lg font-bold transition-colors",
            isExpanded
              ? "bg-primary text-primary-foreground"
              : "bg-muted text-muted-foreground"
          )}>
            {provider.name[0]}
          </div>
          <div>
            <h3 className="font-semibold text-foreground">{provider.name}</h3>
            <p className="text-sm text-muted-foreground">{provider.tagline}</p>
          </div>
        </div>
        <ChevronDown
          className={cn(
            "h-5 w-5 text-muted-foreground transition-transform duration-200",
            isExpanded && "rotate-180"
          )}
        />
      </button>

      {isExpanded && (
        <div className="border-t border-border/50 px-4 pb-4 pt-3 space-y-4">
          <div className="space-y-2">
            <h4 className="text-sm font-medium text-foreground">Why {provider.name}:</h4>
            <ul className="space-y-1">
              {provider.pros.map((pro, i) => (
                <li key={i} className="flex items-start gap-2 text-sm">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-[oklch(0.72_0.19_145)]" />
                  <span className="text-muted-foreground">{pro}</span>
                </li>
              ))}
            </ul>
          </div>

          {provider.recommended && (
            <div className="rounded-lg border border-primary/20 bg-primary/5 p-3">
              <p className="text-sm">
                <span className="font-medium text-foreground">Recommended plan:</span>{" "}
                <span className="text-muted-foreground">
                  {provider.recommended}
                </span>
              </p>
            </div>
          )}

          <a
            href={provider.url}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 text-sm font-medium text-primary hover:underline"
          >
            Go to {provider.name}
            <ExternalLink className="h-4 w-4" />
          </a>
        </div>
      )}
    </div>
  );
}

const SPEC_CHECKLIST = [
  { label: "OS", value: "Ubuntu 25.x (or newest Ubuntu)" },
  { label: "CPU", value: "6-8 vCPU" },
  { label: "RAM", value: "32 GB (minimum 16 GB)" },
  { label: "Storage", value: "200GB+ NVMe SSD" },
  { label: "Price", value: "$35-60/month" },
];

export default function RentVPSPage() {
  const router = useRouter();
  const [expandedProvider, setExpandedProvider] = useState<string | null>(null);
  const [isNavigating, setIsNavigating] = useState(false);

  const handleToggleProvider = useCallback((providerId: string) => {
    setExpandedProvider((prev) => (prev === providerId ? null : providerId));
  }, []);

  const handleContinue = useCallback(() => {
    markStepComplete(4);
    setIsNavigating(true);
    router.push("/wizard/create-vps");
  }, [router]);

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="space-y-2">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary/20">
            <Cloud className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h1 className="bg-gradient-to-r from-foreground via-foreground to-muted-foreground bg-clip-text text-2xl font-bold tracking-tight text-transparent sm:text-3xl">
              Rent a VPS ($35-60/month)
            </h1>
            <p className="text-sm text-muted-foreground">
              ~5 min
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          Pick a VPS provider and rent a server. This is where your coding
          agents will live.
        </p>
      </div>

      {/* Spec checklist */}
      <div className="rounded-xl border border-border/50 bg-card/50 p-4">
        <h2 className="mb-3 flex items-center gap-2 font-semibold text-foreground">
          <Server className="h-5 w-5 text-primary" />
          What to choose
        </h2>
        <div className="grid gap-2 sm:grid-cols-2">
          {SPEC_CHECKLIST.map((spec) => (
            <div key={spec.label} className="flex gap-2 text-sm">
              <span className="font-medium text-muted-foreground min-w-20">
                {spec.label}:
              </span>
              <span className="text-foreground">{spec.value}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Provider cards */}
      <div className="space-y-4">
        <h2 className="font-semibold">Recommended providers</h2>
        <div className="space-y-3">
          {PROVIDERS.map((provider) => (
            <ProviderCard
              key={provider.id}
              provider={provider}
              isExpanded={expandedProvider === provider.id}
              onToggle={() => handleToggleProvider(provider.id)}
            />
          ))}
        </div>
      </div>

      {/* Other providers note */}
      <AlertCard variant="tip" title="Using a different provider?">
        Any provider with Ubuntu VPS and SSH key login works. Just make sure
        you can add your SSH public key during setup.
      </AlertCard>

      {/* Beginner Guide */}
      <SimplerGuide>
        <div className="space-y-6">
          <GuideExplain term="VPS (Virtual Private Server)">
            A VPS is like renting a computer that lives in a data center somewhere
            in the world. It runs 24/7, even when your laptop is closed.
            <br /><br />
            Think of it like renting an apartment: you don&apos;t own the building,
            but you have your own private space to use however you want.
            <br /><br />
            <strong>Why do you need one?</strong>
            <br />
            AI coding assistants work best on a dedicated server that&apos;s always on.
            Running them on your laptop would drain your battery and slow everything down.
            With a VPS, your AI assistants can work even when you&apos;re asleep!
          </GuideExplain>

          <GuideSection title="Which provider should I choose?">
            <p className="mb-4">
              All three providers we recommend are good choices. Here&apos;s a simple guide:
            </p>
            <ul className="space-y-3">
              <li>
                <strong>Hetzner</strong> — Best for most people. Clean interface, fair prices,
                popular with developers. We recommend this if you&apos;re unsure.
              </li>
              <li>
                <strong>OVH</strong> — Great if you&apos;re in Europe or want European data centers.
                Slightly more complex signup process.
              </li>
              <li>
                <strong>Contabo</strong> — Cheapest option for high specs. Good if budget is
                a concern, but their interface is a bit dated.
              </li>
            </ul>
          </GuideSection>

          <GuideSection title="Step-by-Step: Signing Up (Hetzner Example)">
            <div className="space-y-4">
              <GuideStep number={1} title="Go to the provider's website">
                Click on &quot;Hetzner&quot; above, or go to{" "}
                <a href="https://www.hetzner.com/cloud" target="_blank" rel="noopener noreferrer" className="text-primary underline">
                  hetzner.com/cloud
                </a>
              </GuideStep>

              <GuideStep number={2} title="Create an account">
                Click &quot;Sign up&quot; or &quot;Register&quot;. You&apos;ll need:
                <ul className="mt-2 list-disc space-y-1 pl-5">
                  <li>An email address</li>
                  <li>A password (make it strong!)</li>
                  <li>Your name and address</li>
                </ul>
              </GuideStep>

              <GuideStep number={3} title="Verify your email">
                Check your email for a verification link. Click it to confirm
                your account. <em>Check your spam folder if you don&apos;t see it!</em>
              </GuideStep>

              <GuideStep number={4} title="Add payment method">
                Most providers require a credit card or PayPal. This is normal —
                you&apos;ll only be charged for what you use.
                <br /><br />
                <strong>Expected cost:</strong> Around $30-60/month depending on
                the plan you choose. You can cancel anytime.
              </GuideStep>

              <GuideStep number={5} title="That's it for now!">
                Once your account is verified and payment is set up, you&apos;re ready
                for the next step where we&apos;ll actually create the VPS.
              </GuideStep>
            </div>
          </GuideSection>

          <GuideSection title="Understanding the specs">
            <p className="mb-3">
              When choosing a plan, you&apos;ll see terms like vCPU, RAM, and SSD.
              Here&apos;s what they mean:
            </p>
            <ul className="space-y-2">
              <li>
                <strong>vCPU (4-8)</strong> — The &quot;brain&quot; of the computer. More = faster.
                4 is minimum, 8 is comfortable.
              </li>
              <li>
                <strong>RAM (8-16 GB)</strong> — Short-term memory. More = can do more things
                at once. 8GB minimum, 16GB is better.
              </li>
              <li>
                <strong>Storage (100GB+ SSD)</strong> — Long-term storage for files and programs.
                SSD means it&apos;s fast. 100GB is plenty to start.
              </li>
              <li>
                <strong>Ubuntu</strong> — The operating system we&apos;ll install. It&apos;s like
                Windows or macOS, but for servers. It&apos;s free and widely used.
              </li>
            </ul>
          </GuideSection>

          <GuideTip>
            Don&apos;t overthink the provider choice! All three work great. Pick one,
            sign up, and you can always switch later if needed. The setup process
            is similar for all of them.
          </GuideTip>

          <GuideCaution>
            <strong>Keep your account credentials safe!</strong> Write down your
            login email and password somewhere secure. You&apos;ll need them to
            manage your VPS later.
          </GuideCaution>
        </div>
      </SimplerGuide>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg">
          {isNavigating ? "Loading..." : "I rented a VPS"}
        </Button>
      </div>
    </div>
  );
}
