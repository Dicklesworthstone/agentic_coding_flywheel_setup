"use client";

import { useCallback, useState } from "react";
import { useRouter } from "next/navigation";
import { ExternalLink, Check, Server, ChevronDown, Cloud } from "lucide-react";
import { Button } from "@/components/ui/button";
import { AlertCard } from "@/components/alert-card";
import { cn } from "@/lib/utils";
import { markStepComplete } from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
import {
  SimplerGuide,
  GuideSection,
  GuideStep,
  GuideExplain,
  GuideTip,
  GuideCaution,
} from "@/components/simpler-guide";
import { Jargon } from "@/components/jargon";

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

  // Analytics tracking for this wizard step
  const { markComplete } = useWizardAnalytics({
    step: "rent_vps",
    stepNumber: 4,
    stepTitle: "Rent a VPS",
  });

  const handleToggleProvider = useCallback((providerId: string) => {
    setExpandedProvider((prev) => (prev === providerId ? null : providerId));
  }, []);

  const handleContinue = useCallback(() => {
    markComplete({ expanded_provider: expandedProvider });
    markStepComplete(4);
    setIsNavigating(true);
    router.push("/wizard/create-vps");
  }, [router, markComplete, expandedProvider]);

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
              Rent a <Jargon term="vps">VPS</Jargon> ($35-60/month)
            </h1>
            <p className="text-sm text-muted-foreground">
              ~5 min
            </p>
          </div>
        </div>
        <p className="text-muted-foreground">
          Pick a <Jargon term="vps">VPS</Jargon> provider and rent a server. This is where your <Jargon term="ai-agents">coding agents</Jargon> will live.
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
        Any provider with <Jargon term="ubuntu">Ubuntu</Jargon> <Jargon term="vps">VPS</Jargon> and <Jargon term="ssh">SSH</Jargon> key login works. Just make sure
        you can add your <Jargon term="public-key">SSH public key</Jargon> during setup.
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

          <GuideSection title="Why 32GB RAM?">
            <div className="rounded-lg border border-[oklch(0.78_0.16_75/0.3)] bg-[oklch(0.78_0.16_75/0.08)] p-4 mb-4">
              <p className="font-medium text-foreground mb-2">⚡ This matters a lot!</p>
              <p className="text-sm text-muted-foreground">
                Each AI coding agent (like Claude Code) uses about 2GB of RAM when running.
                To get the full power of this approach, you&apos;ll want to run 10+ agents
                simultaneously. That&apos;s 20GB+ just for the agents, plus room for your
                development tools and databases.
              </p>
            </div>
            <ul className="space-y-2 text-sm">
              <li>
                <strong>16GB RAM</strong> — Bare minimum. Can run 3-5 agents. Good for testing.
              </li>
              <li>
                <strong>32GB RAM</strong> — Sweet spot. Run 10+ agents comfortably. Recommended!
              </li>
              <li>
                <strong>64GB+ RAM</strong> — Power user mode. Run 20+ agents with headroom.
              </li>
            </ul>
          </GuideSection>

          <GuideSection title="The Full Investment (Optional but Recommended)">
            <p className="mb-4 text-sm text-muted-foreground">
              To get the FULL benefit of this approach with many parallel agents, you&apos;ll
              also need subscriptions to AI services. This is optional — you can start
              smaller and scale up!
            </p>
            <div className="space-y-3">
              <div className="rounded-lg border border-border/50 bg-card/50 p-3">
                <p className="font-medium text-foreground">Claude Max — $200/month</p>
                <p className="text-sm text-muted-foreground">
                  Unlimited Claude Code usage. For serious multi-agent workflows, consider
                  2 accounts ($400/month) to maximize parallel capacity.
                </p>
              </div>
              <div className="rounded-lg border border-border/50 bg-card/50 p-3">
                <p className="font-medium text-foreground">GPT Pro — $200/month</p>
                <p className="text-sm text-muted-foreground">
                  Access to OpenAI&apos;s Codex and o1 models. Great for redundancy and
                  comparing outputs from different AI systems.
                </p>
              </div>
              <div className="rounded-lg border border-primary/20 bg-primary/5 p-3">
                <p className="font-medium text-foreground">Total for full setup:</p>
                <p className="text-sm text-muted-foreground">
                  VPS ($40) + Claude Max x2 ($400) + GPT Pro ($200) = <strong>~$640/month</strong>
                  <br /><br />
                  <em>This sounds like a lot, but if it helps you build and ship faster,
                  it pays for itself quickly!</em>
                </p>
              </div>
            </div>
            <p className="mt-4 text-sm text-muted-foreground">
              <strong>Starting small?</strong> Just get a VPS ($35-40) and one Claude Pro
              subscription ($20). You can scale up as you see results!
            </p>
          </GuideSection>

          <GuideSection title="Which provider should I choose?">
            <p className="mb-4">
              Both providers we recommend are great. Here&apos;s how to choose:
            </p>
            <ul className="space-y-3">
              <li>
                <strong>Contabo</strong> — Our top recommendation! Best specs for the price.
                Their 32GB RAM VPS is only ~$35/month. Interface is basic but functional.
                Instant activation — no waiting.
              </li>
              <li>
                <strong>OVH</strong> — Good alternative with excellent support. Slightly more
                expensive but more polished interface. Great EU data centers. Also instant
                activation.
              </li>
            </ul>
          </GuideSection>

          <GuideSection title="Step-by-Step: Signing Up (Contabo Example)">
            <div className="space-y-4">
              <GuideStep number={1} title="Go to Contabo's website">
                Click on &quot;Contabo&quot; above, or go to{" "}
                <a href="https://contabo.com/en/vps/" target="_blank" rel="noopener noreferrer" className="text-primary underline">
                  contabo.com/en/vps
                </a>
              </GuideStep>

              <GuideStep number={2} title="Choose the Cloud VPS L plan">
                Look for &quot;Cloud VPS L&quot; — it has 6 vCPU, 32GB RAM, and 400GB storage
                for about $35/month. Click &quot;Configure&quot; or &quot;Order&quot;.
              </GuideStep>

              <GuideStep number={3} title="Configure your VPS">
                <ul className="mt-2 list-disc space-y-1 pl-5">
                  <li><strong>Region:</strong> Choose closest to you (US or EU)</li>
                  <li><strong>Storage:</strong> Keep the default SSD option</li>
                  <li><strong>Image:</strong> Select &quot;Ubuntu 24.04&quot; or newer</li>
                </ul>
              </GuideStep>

              <GuideStep number={4} title="Create an account">
                Click &quot;Sign up&quot; or &quot;Register&quot;. You&apos;ll need:
                <ul className="mt-2 list-disc space-y-1 pl-5">
                  <li>An email address</li>
                  <li>A password (make it strong!)</li>
                  <li>Your name and address</li>
                </ul>
              </GuideStep>

              <GuideStep number={5} title="Add payment method">
                Contabo accepts credit cards and PayPal. You&apos;ll be charged for the
                first month upfront.
                <br /><br />
                <strong>Tip:</strong> Monthly billing is fine to start. You can switch to
                annual billing later for a small discount.
              </GuideStep>

              <GuideStep number={6} title="Complete the order">
                Review your order and complete checkout. Contabo activates servers
                quickly — usually within minutes!
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
                <strong>vCPU (6-8)</strong> — The &quot;brain&quot; of the computer. More = faster.
                6 is comfortable, 8 is great.
              </li>
              <li>
                <strong>RAM (32 GB)</strong> — Short-term memory. This is crucial for running
                multiple AI agents! 32GB lets you run 10+ agents comfortably.
              </li>
              <li>
                <strong>Storage (200GB+ SSD)</strong> — Long-term storage for files, databases,
                and AI model caches. SSD means it&apos;s fast. 200GB is a good starting point.
              </li>
              <li>
                <strong>Ubuntu</strong> — The operating system we&apos;ll install. It&apos;s like
                Windows or macOS, but for servers. It&apos;s free and widely used.
              </li>
            </ul>
          </GuideSection>

          <GuideTip>
            <strong>Start with Contabo&apos;s Cloud VPS L</strong> for the best balance of
            price and power. At ~$35/month for 32GB RAM, it&apos;s hard to beat. Both
            Contabo and OVH activate servers instantly — no waiting period!
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
