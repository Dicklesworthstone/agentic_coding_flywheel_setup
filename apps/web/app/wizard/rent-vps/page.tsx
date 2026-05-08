"use client";

import { useCallback, useState } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import {
  AlertTriangle,
  Calculator,
  Check,
  ChevronDown,
  Cloud,
  Cpu,
  ExternalLink,
  HardDrive,
  Heart,
  Info,
  Server,
  Users,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { AlertCard } from "@/components/alert-card";
import { TrackedLink } from "@/components/tracked-link";
import { VPSComparison } from "@/components/wizard/VPSComparison";
import { cn } from "@/lib/utils";
import { VPS_PROVIDERS, type VPSPlan } from "@/lib/vpsProviders";
import { markStepComplete } from "@/lib/wizardSteps";
import { useWizardAnalytics } from "@/lib/hooks/useWizardAnalytics";
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
    url: "https://contabo.com/en-us/vps/",
    pros: [
      "Best specs-to-price ratio on the market",
      "Cloud VPS 50 (64GB RAM, 16 vCPU): ~$56/month (US datacenter)",
      "Cloud VPS 40 (48GB RAM, 12 vCPU): ~$36/month (US datacenter)",
      "Prices are month-to-month, no commitment required",
    ],
    recommended: "Cloud VPS 50 (64GB RAM, 16 vCPU, ~$56/month US) - our top pick for serious multi-agent work",
  },
  {
    id: "ovh",
    name: "OVH",
    tagline: "Reliable, good support",
    url: "https://us.ovhcloud.com/vps/",
    pros: [
      "Great EU and US data centers with anti-DDoS included",
      "VPS-5 (64GB RAM, 16 vCore): ~$40/month (no commitment)",
      "VPS-4 (48GB RAM, 12 vCore): ~$26/month (no commitment)",
      "Prices are month-to-month; longer commitments offer 5-15% discounts",
    ],
    recommended: "VPS-5 (64GB RAM, 16 vCore, ~$40/month) for best multi-agent performance",
  },
];

type ScreenshotSpec = {
  file: string;
  alt: string;
  caption: string;
};

const SCREENSHOT_BASE =
  "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/research_screenshots";

function screenshotUrl(file: string): string {
  return `${SCREENSHOT_BASE}/${file}`;
}

function ScreenshotFigure({ file, alt, caption }: ScreenshotSpec) {
  const src = screenshotUrl(file);
  return (
    <figure className="mt-3 space-y-1">
      <a
        href={src}
        target="_blank"
        rel="noopener noreferrer"
        className="block overflow-hidden rounded-xl border border-border/50 bg-muted/10 transition hover:border-primary/30"
      >
        <Image
          src={src}
          alt={alt}
          width={1440}
          height={1000}
          unoptimized
          className="h-auto w-full"
        />
      </a>
      <figcaption className="text-xs text-muted-foreground">
        {caption}{" "}
        <span className="sr-only">(opens full size in a new tab)</span>
      </figcaption>
    </figure>
  );
}

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

          <TrackedLink
            href={provider.url}
            trackingId={`vps-provider-${provider.id}`}
            className="inline-flex items-center gap-2 text-sm font-medium text-primary hover:underline"
          >
            Go to {provider.name}
            <ExternalLink className="h-4 w-4" />
          </TrackedLink>
        </div>
      )}
    </div>
  );
}

const SPEC_CHECKLIST = [
  { label: "OS", value: "Ubuntu 24.x or newer" },
  { label: "CPU", value: "12-16 vCPU" },
  { label: "RAM", value: "64GB recommended (48GB workable, 32GB minimum)" },
  { label: "Storage", value: "250GB+ NVMe SSD" },
  { label: "Price", value: "~$40-56/month for 64GB (month-to-month)" },
];

type WorkloadId = "light" | "standard" | "heavy";
type PlanStatus = "pass" | "warn" | "fail";

interface WorkloadProfile {
  id: WorkloadId;
  label: string;
  summary: string;
  ramPerAgentGB: number;
  cpuPerAgent: number;
}

interface RequiredSpecs {
  ramGB: number;
  vCPU: number;
  storageGB: number;
}

interface EvaluatedProviderPlan {
  providerName: string;
  plan: VPSPlan;
  recommendedAgents: number;
  safeAgents: number;
  status: PlanStatus;
}

const WORKLOAD_PROFILES: WorkloadProfile[] = [
  {
    id: "light",
    label: "Light",
    summary: "reviews, docs, small edits",
    ramPerAgentGB: 2,
    cpuPerAgent: 0.5,
  },
  {
    id: "standard",
    label: "Standard",
    summary: "mixed coding and tests",
    ramPerAgentGB: 3,
    cpuPerAgent: 1,
  },
  {
    id: "heavy",
    label: "Heavy",
    summary: "Rust builds, browsers, large repos",
    ramPerAgentGB: 4,
    cpuPerAgent: 2,
  },
];

const AGENT_COUNT_PRESETS = [5, 10, 15, 25, 50];
const RAM_TIERS = [32, 48, 64, 96, 128, 192, 256, 384];
const CPU_TIERS = [8, 12, 16, 24, 32, 48, 64, 96, 128, 160];
const STORAGE_TIERS = [250, 400, 640, 800, 1000];
const COMFORTABLE_STATUSES = new Set<PlanStatus>(["pass"]);
const PLAN_STATUS_COPY: Record<PlanStatus, { label: string; className: string }> = {
  pass: {
    label: "Comfortable",
    className: "border-[oklch(0.72_0.19_145/0.35)] bg-[oklch(0.72_0.19_145/0.08)] text-[oklch(0.72_0.19_145)]",
  },
  warn: {
    label: "Tight",
    className: "border-[oklch(0.78_0.16_75/0.35)] bg-[oklch(0.78_0.16_75/0.08)] text-[oklch(0.78_0.16_75)]",
  },
  fail: {
    label: "Undersized",
    className: "border-destructive/35 bg-destructive/10 text-destructive",
  },
};

function roundUpToTier(value: number, tiers: number[]): number {
  return tiers.find((tier) => tier >= value) ?? tiers[tiers.length - 1];
}

function calculateRequiredSpecs(
  agentCount: number,
  workload: WorkloadProfile,
  comfortable: boolean
): RequiredSpecs {
  const targetSafeAgents = comfortable ? Math.ceil(agentCount / 0.7) : agentCount;
  const rawRamGB = (targetSafeAgents * workload.ramPerAgentGB + 4) / 0.9;
  const rawVcpu = targetSafeAgents * workload.cpuPerAgent;
  const rawStorageGB = 10 + targetSafeAgents * 2;

  return {
    ramGB: roundUpToTier(rawRamGB, RAM_TIERS),
    vCPU: roundUpToTier(rawVcpu, CPU_TIERS),
    storageGB: roundUpToTier(rawStorageGB, STORAGE_TIERS),
  };
}

function evaluatePlan(
  plan: VPSPlan,
  workload: WorkloadProfile,
  agentCount: number
): Pick<EvaluatedProviderPlan, "recommendedAgents" | "safeAgents" | "status"> {
  const usableRamGB = Math.max(0, plan.ramGB - Math.max(4, plan.ramGB * 0.1));
  const usableStorageGB = Math.max(0, plan.storageGB - 10);
  const memoryLimitedAgents = Math.floor(usableRamGB / workload.ramPerAgentGB);
  const cpuLimitedAgents = Math.floor(plan.vCPU / workload.cpuPerAgent);
  const diskLimitedAgents = Math.floor(usableStorageGB / 2);
  const safeAgents = Math.min(memoryLimitedAgents, cpuLimitedAgents, diskLimitedAgents);
  const recommendedAgents = safeAgents > 0 ? Math.max(1, Math.floor(safeAgents * 0.7)) : 0;
  const status =
    agentCount <= recommendedAgents ? "pass" : agentCount <= safeAgents ? "warn" : "fail";

  return { recommendedAgents, safeAgents, status };
}

function evaluateProviderPlans(
  workload: WorkloadProfile,
  agentCount: number
): EvaluatedProviderPlan[] {
  return VPS_PROVIDERS.flatMap((provider) =>
    (["budget", "recommended"] as const).map((tier) => {
      const plan = provider[tier];
      return {
        providerName: provider.name,
        plan,
        ...evaluatePlan(plan, workload, agentCount),
      };
    })
  ).sort((a, b) => a.plan.priceUSD - b.plan.priceUSD);
}

function statusCopy(status: PlanStatus): { label: string; className: string } {
  return PLAN_STATUS_COPY[status];
}

function isComfortableStatus(status: PlanStatus | undefined): boolean {
  return status !== undefined && COMFORTABLE_STATUSES.has(status);
}

function CapacityPlanner() {
  const [agentCount, setAgentCount] = useState(10);
  const [workloadId, setWorkloadId] = useState<WorkloadId>("standard");
  const workload =
    WORKLOAD_PROFILES.find((profile) => profile.id === workloadId) ?? WORKLOAD_PROFILES[1];
  const minimumSpecs = calculateRequiredSpecs(agentCount, workload, false);
  const recommendedSpecs = calculateRequiredSpecs(agentCount, workload, true);
  const evaluatedPlans = evaluateProviderPlans(workload, agentCount);
  const comfortablePlan = evaluatedPlans.find((entry) => entry.status === "pass");
  const safePlan = evaluatedPlans.find((entry) => entry.status === "warn");
  const bestListedPlan = comfortablePlan ?? safePlan;

  return (
    <section
      data-testid="vps-plan-calculator"
      className="space-y-5 rounded-xl border border-border/50 bg-card/50 p-4"
    >
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="space-y-1">
          <h2 className="flex items-center gap-2 font-semibold text-foreground">
            <Calculator className="h-5 w-5 text-primary" />
            Plan calculator
          </h2>
          <p className="text-sm text-muted-foreground">
            Capacity uses the same conservative model as <code className="rounded bg-muted px-1">acfs capacity</code>:
            reserve host headroom, then size RAM, CPU, and disk per active agent.
          </p>
        </div>
        <a
          href="#recommended-providers"
          className="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline"
        >
          Compare providers
          <ChevronDown className="h-4 w-4" />
        </a>
      </div>

      <div className="grid gap-5 lg:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
        <div className="space-y-5">
          <div className="space-y-3">
            <div className="flex items-center justify-between gap-3">
              <label htmlFor="agent-count" className="flex items-center gap-2 text-sm font-medium text-foreground">
                <Users className="h-4 w-4 text-primary" />
                Target agent count
              </label>
              <span className="font-mono text-lg font-semibold text-foreground">{agentCount}</span>
            </div>
            <input
              id="agent-count"
              type="range"
              min={5}
              max={50}
              step={5}
              value={agentCount}
              onChange={(event) => setAgentCount(Number(event.target.value))}
              className="h-2 w-full cursor-pointer accent-primary"
              aria-label="Target agent count"
            />
            <div className="grid grid-cols-5 gap-2" aria-label="Agent count presets">
              {AGENT_COUNT_PRESETS.map((count) => (
                <button
                  key={count}
                  type="button"
                  onClick={() => setAgentCount(count)}
                  className={cn(
                    "rounded-md border px-2 py-1 text-xs font-medium transition-colors",
                    agentCount === count
                      ? "border-primary/50 bg-primary/15 text-primary"
                      : "border-border/50 bg-background/40 text-muted-foreground hover:text-foreground"
                  )}
                >
                  {count}
                </button>
              ))}
            </div>
          </div>

          <div className="space-y-3">
            <p className="text-sm font-medium text-foreground">Workload intensity</p>
            <div className="grid gap-2" role="group" aria-label="Workload intensity">
              {WORKLOAD_PROFILES.map((profile) => (
                <button
                  key={profile.id}
                  type="button"
                  onClick={() => setWorkloadId(profile.id)}
                  className={cn(
                    "rounded-lg border p-3 text-left transition-colors",
                    workloadId === profile.id
                      ? "border-primary/50 bg-primary/10"
                      : "border-border/50 bg-background/40 hover:border-primary/25"
                  )}
                >
                  <span className="flex items-center justify-between gap-3">
                    <span className="font-medium text-foreground">{profile.label}</span>
                    <span className="font-mono text-xs text-muted-foreground">
                      {profile.ramPerAgentGB}GB / {profile.cpuPerAgent} vCPU
                    </span>
                  </span>
                  <span className="mt-1 block text-xs text-muted-foreground">
                    {profile.summary}
                  </span>
                </button>
              ))}
            </div>
          </div>
        </div>

        <div data-testid="vps-calculator-summary" className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="rounded-lg border border-border/50 bg-background/40 p-3">
              <p className="text-xs font-medium uppercase text-muted-foreground">Minimum host</p>
              <p className="mt-1 text-lg font-semibold text-foreground">
                {minimumSpecs.ramGB} GB RAM / {minimumSpecs.vCPU} vCPU
              </p>
              <p className="mt-1 text-xs text-muted-foreground">
                Enough to try {agentCount} {workload.label.toLowerCase()} agents with little spare room.
              </p>
            </div>
            <div className="rounded-lg border border-primary/25 bg-primary/5 p-3">
              <p className="text-xs font-medium uppercase text-primary">Recommended host</p>
              <p className="mt-1 text-lg font-semibold text-foreground">
                {recommendedSpecs.ramGB} GB RAM / {recommendedSpecs.vCPU} vCPU
              </p>
              <p className="mt-1 text-xs text-muted-foreground">
                Keeps the target inside the 70% comfort band used by the capacity model.
              </p>
            </div>
          </div>

          <div className="grid gap-2 sm:grid-cols-3">
            <div className="flex items-center gap-2 rounded-lg border border-border/50 bg-background/40 p-2 text-sm">
              <Server className="h-4 w-4 text-primary" />
              <span>{recommendedSpecs.ramGB} GB RAM</span>
            </div>
            <div className="flex items-center gap-2 rounded-lg border border-border/50 bg-background/40 p-2 text-sm">
              <Cpu className="h-4 w-4 text-primary" />
              <span>{recommendedSpecs.vCPU} vCPU</span>
            </div>
            <div className="flex items-center gap-2 rounded-lg border border-border/50 bg-background/40 p-2 text-sm">
              <HardDrive className="h-4 w-4 text-primary" />
              <span>{recommendedSpecs.storageGB} GB NVMe</span>
            </div>
          </div>

          <div
            className={cn(
              "rounded-lg border p-3",
              bestListedPlan
                ? statusCopy(bestListedPlan.status).className
                : "border-destructive/35 bg-destructive/10 text-destructive"
            )}
          >
            <div className="flex items-start gap-2">
              {isComfortableStatus(bestListedPlan?.status) ? (
                <Check className="mt-0.5 h-4 w-4 shrink-0" />
              ) : (
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              )}
              <div className="space-y-1">
                <p className="font-medium">
                  {bestListedPlan
                    ? `${bestListedPlan.providerName} ${bestListedPlan.plan.name} is the closest listed fit`
                    : "The listed 48/64 GB VPS plans are undersized for this target"}
                </p>
                <p className="text-sm opacity-90">
                  {bestListedPlan
                    ? `It supports about ${bestListedPlan.recommendedAgents} comfortable / ${bestListedPlan.safeAgents} safe ${workload.label.toLowerCase()} agents at roughly $${bestListedPlan.plan.priceUSD}/month.`
                    : "Split the swarm across multiple hosts or choose a larger VPS/dedicated server before launching this many agents."}
                </p>
              </div>
            </div>
          </div>

          <div className="space-y-2">
            {evaluatedPlans.map((entry) => {
              const copy = statusCopy(entry.status);
              return (
                <div
                  key={`${entry.providerName}-${entry.plan.name}`}
                  className="flex flex-col gap-2 rounded-lg border border-border/50 bg-background/35 p-3 sm:flex-row sm:items-center sm:justify-between"
                >
                  <div>
                    <p className="text-sm font-medium text-foreground">
                      {entry.providerName} {entry.plan.name}
                    </p>
                    <p className="text-xs text-muted-foreground">
                      {entry.plan.ramGB} GB RAM, {entry.plan.vCPU} vCPU, ${entry.plan.priceUSD}/mo approx.
                    </p>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className={cn("rounded-full border px-2 py-0.5 text-xs font-medium", copy.className)}>
                      {copy.label}
                    </span>
                    <span className="font-mono text-xs text-muted-foreground">
                      {entry.recommendedAgents}/{entry.safeAgents}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </section>
  );
}

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
    router.push(withCurrentSearch("/wizard/create-vps"));
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
              Rent a <Jargon term="vps" gradientHeading>VPS</Jargon>
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

      <CapacityPlanner />

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

      {/* Quick comparison table */}
      <VPSComparison />

      {/* Credit card and verification warning */}
      <AlertCard variant="warning" title="Before you sign up">
        <div className="space-y-2 text-sm">
          <p>
            <strong className="text-foreground">Credit card required:</strong> Both providers require
            a valid credit card for signup. Prepaid cards may not work.
          </p>
          <p>
            <strong className="text-foreground">Email verification:</strong> You&apos;ll need to verify
            your email address. Check your spam folder if you don&apos;t see the verification email.
          </p>
          <p className="text-muted-foreground">
            Some providers (especially Contabo) may require additional identity verification for
            new accounts. This usually takes a few minutes but can occasionally take up to 24 hours.
          </p>
        </div>
      </AlertCard>

      {/* Provider cards */}
      <div id="recommended-providers" className="space-y-4 scroll-mt-24">
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

      {/* Honest disclaimer */}
      <div className="relative overflow-hidden rounded-xl border border-[oklch(0.6_0.02_260/0.3)] bg-gradient-to-br from-[oklch(0.15_0.01_260)] to-[oklch(0.12_0.015_280)] p-3 sm:p-4">
        {/* Subtle decorative element */}
        <div className="pointer-events-none absolute -right-8 -top-8 h-32 w-32 rounded-full bg-[oklch(0.5_0.03_260/0.15)] blur-2xl" />

        <div className="relative flex gap-2.5 sm:gap-3">
          <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-[oklch(0.65_0.18_350/0.15)] sm:h-8 sm:w-8">
            <Heart className="h-3.5 w-3.5 text-[oklch(0.75_0.15_350)] sm:h-4 sm:w-4" />
          </div>
          <div className="min-w-0 space-y-1 sm:space-y-1.5">
            <p className="text-[13px] font-medium leading-tight text-[oklch(0.85_0.02_260)] sm:text-sm">
              No affiliate deals, just honest recommendations
            </p>
            <p className="text-[13px] leading-relaxed text-[oklch(0.65_0.02_260)] sm:text-sm">
              I&apos;m Jeffrey Emanuel, and I have <span className="font-medium text-[oklch(0.75_0.02_260)]">zero financial relationship</span> with
              Contabo, OVH, or any cloud provider. No affiliate links, no kickbacks, no sponsored content.
              I recommend these because I use them myself. They offer beefy machines (48GB+ RAM) at
              a fraction of what AWS, GCP, or Azure charge. On those big providers, equivalent specs
              would cost <span className="font-medium text-[oklch(0.75_0.02_260)]">3-5× more</span>.
            </p>
          </div>
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
          <GuideExplain term="a VPS (Virtual Private Server)">
            A dedicated server in a data center that runs 24/7, even when your laptop is closed.
            You get root access and full control.
            <br /><br />
            <strong>Why do you need one?</strong>
            <br />
            AI coding assistants work best on a dedicated server that&apos;s always on.
            Running them on your laptop would drain your battery and slow everything down.
            With a VPS, your AI assistants can work even when you&apos;re asleep.
          </GuideExplain>

          <GuideSection title="Why 64GB RAM?">
            <div className="rounded-lg border border-[oklch(0.78_0.16_75/0.3)] bg-[oklch(0.78_0.16_75/0.08)] p-4 mb-4">
              <p className="font-medium text-foreground mb-2">⚡ This matters a lot!</p>
              <p className="text-sm text-muted-foreground">
                Each AI coding agent (like Claude Code) uses about 2GB of RAM when running.
                To get the full power of this approach, you&apos;ll want enough room for 10-16
                standard agents on one host, with more capacity for light work or multi-host
                swarms. That&apos;s significant RAM just for agents, plus room for your development
                tools and databases.
              </p>
            </div>
            <ul className="space-y-2 text-sm">
              <li>
                <strong>32GB RAM:</strong> Absolute minimum. Can run 5-8 agents. Not recommended.
              </li>
              <li>
                <strong>48GB RAM:</strong> Workable but tight. Run 10+ agents. (~$26-36/month)
              </li>
              <li>
                <strong>64GB RAM:</strong> Just get this. Run 10-16 standard agents, or around 20 light agents, with headroom. (~$40-56/month)
              </li>
            </ul>
            <div className="mt-4 rounded-lg border border-primary/20 bg-primary/5 p-3">
              <p className="text-sm text-muted-foreground">
                <strong>Just get 64GB.</strong> You&apos;re spending $400+/month on AI subscriptions, so the
                extra $14-20/month for 64GB vs 48GB is noise. Don&apos;t bottleneck a $400+/month
                investment to save $20. The headroom matters when you&apos;re running 15+ agents
                plus databases, build tools, and language servers.
              </p>
            </div>
          </GuideSection>

          <GuideSection title="The Reality of VPS Performance">
            <p className="mb-3 text-sm text-muted-foreground">
              A VPS isn&apos;t a dedicated machine. It&apos;s a slice of a larger physical server shared
              with other customers. Understanding this helps you set realistic expectations:
            </p>
            <ul className="space-y-3 text-sm">
              <li>
                <strong>Shared resources:</strong> Your &quot;16 vCPU&quot; VPS shares the physical CPU
                with other tenants. When neighbors run heavy workloads, your performance dips.
                This is normal and expected.
              </li>
              <li>
                <strong>Overselling is common:</strong> Providers bet that not everyone uses their
                full allocation simultaneously. When you&apos;re sleeping, they effectively reuse that
                capacity. This is how they offer low prices, and why performance can be inconsistent.
              </li>
              <li>
                <strong>Dedicated servers exist:</strong> If you want guaranteed, consistent performance,
                bare-metal dedicated servers are available, but they cost 3-10× more. For most users,
                VPS is the right price/performance tradeoff.
              </li>
            </ul>
            <div className="mt-4 rounded-lg border border-[oklch(0.65_0.15_220/0.3)] bg-[oklch(0.65_0.15_220/0.08)] p-3">
              <p className="text-sm text-muted-foreground">
                <strong>💡 This is another reason to get 64GB:</strong> You won&apos;t always get the full
                performance you&apos;d expect from those specs. Having headroom means your agents keep
                running smoothly even when the underlying hardware is contested. Think of the extra
                RAM as insurance against noisy neighbors.
              </p>
            </div>
          </GuideSection>

          <GuideSection title="The Full Investment">
            <p className="mb-4 text-sm text-muted-foreground">
              To use the agentic coding approach, you&apos;ll need subscriptions to AI services
              in addition to your VPS. Here&apos;s what the full setup looks like:
            </p>
            <div className="space-y-3">
              <div className="rounded-lg border border-border/50 bg-card/50 p-3">
                <p className="font-medium text-foreground">Claude Max ($200/month)</p>
                <p className="text-sm text-muted-foreground">
                  Unlimited Claude Code usage. For serious multi-agent workflows, consider
                  2 accounts ($400/month) to maximize parallel capacity.
                </p>
              </div>
              <div className="rounded-lg border border-border/50 bg-card/50 p-3">
                <p className="font-medium text-foreground">ChatGPT Pro ($200/month): Critical for Planning</p>
                <p className="text-sm text-muted-foreground">
                  Access to GPT 5.2 Pro with Extended Thinking in the ChatGPT webapp. This is
                  <strong> the key to making this approach work</strong>: you use it to write,
                  revise, and iterate on comprehensive plan documents in markdown. Everything
                  depends on having an extremely detailed, granular plan, which you then convert
                  into trackable tasks using <Jargon term="beads">Beads</Jargon>. The extended thinking capability is unmatched
                  for this kind of strategic planning work.
                </p>
              </div>
              <div className="rounded-lg border border-primary/20 bg-primary/5 p-3">
                <p className="font-medium text-foreground">Total for full setup:</p>
                <p className="text-sm text-muted-foreground">
                  VPS (~$56) + Claude Max x2 ($400) + ChatGPT Pro ($200) = <strong>~$656/month</strong>
                  <br /><br />
                  <em>This sounds like a lot, but compare it to hiring: a junior developer in the US
                  costs $100k+/year (~$8,300+/month). For less than 10% of that, you get AI agents
                  working 24/7 with no vacation, no onboarding, and instant scaling.</em>
                </p>
              </div>
            </div>
            <div className="mt-4 rounded-lg border border-[oklch(0.65_0.12_30/0.3)] bg-[oklch(0.65_0.12_30/0.08)] p-3">
              <p className="text-sm text-muted-foreground">
                <strong>⚠️ Realistic minimum investment:</strong> VPS (~$40-56/month for 64GB) + Claude Max ($200/month) + ChatGPT Pro ($200/month) = <strong>~$440-456/month</strong>.
                The $20/month Claude Pro tier does <em>not</em> have enough capacity for agentic workflows; you&apos;ll
                hit rate limits almost immediately. Claude Max is required for execution, and ChatGPT Pro&apos;s extended
                thinking is essential for creating the detailed plan documents that make this approach work.
                <br /><br />
                <strong>Perspective:</strong> A junior US developer costs ~$8k+/month. This is ~5% of that, for AI agents that work 24/7.
              </p>
            </div>
          </GuideSection>

          <GuideSection title="Which provider should I choose?">
            <p className="mb-4">
              Both providers we recommend are great. Here&apos;s how to choose:
            </p>
            <ul className="space-y-3">
              <li>
                <strong>Contabo:</strong> Our top recommendation! Best specs for the price.
                Cloud VPS 50 (64GB RAM, ~$56/month US) is our top pick. Cloud VPS 40 (48GB RAM, ~$36/month US)
                for budget. Interface is basic but functional. Usually activates within minutes (occasionally up to ~1 hour).
              </li>
              <li>
                <strong>OVH:</strong> Great alternative with polished interface.
                VPS-5 (64GB RAM, ~$40/month) or VPS-4 (48GB RAM, ~$26/month).
                Great EU and US data centers. Typically activates within minutes.
              </li>
            </ul>
            <div className="mt-4 rounded-lg border border-[oklch(0.65_0.15_220/0.3)] bg-[oklch(0.65_0.15_220/0.08)] p-3">
              <p className="text-sm text-muted-foreground">
                <strong>💡 About pricing:</strong> All prices shown are <strong>month-to-month with no commitment</strong>.
                Both providers offer 5-20% discounts if you prepay for 6-12 months, but we recommend starting
                monthly so you can cancel anytime. Contabo US pricing includes the ~$10/month US datacenter fee.
              </p>
            </div>
          </GuideSection>

          <GuideSection title="Step-by-Step: Signing Up (Contabo Example)">
            <div className="space-y-4">
              <GuideStep number={1} title="Go to Contabo's website">
                Click on &quot;Contabo&quot; above, or go to{" "}
                <TrackedLink href="https://contabo.com/en-us/vps/" trackingId="contabo-guide-link" className="text-primary underline">
                  contabo.com/en-us/vps
                </TrackedLink>
                <ScreenshotFigure
                  file="contabo_us_01_main.png"
                  alt="Contabo VPS page showing plan tiles and pricing"
                  caption="Contabo VPS page (US) — you’ll pick a plan from here."
                />
              </GuideStep>

              <GuideStep number={2} title="Choose a plan with enough resources">
                Look for a plan with <strong>12+ vCPU</strong> and <strong>48GB+ RAM</strong> (32GB absolute minimum).
                NVMe storage is standard on all recommended plans. Click &quot;Configure&quot; or &quot;Order&quot;.
                <ScreenshotFigure
                  file="contabo_us_02_plans.png"
                  alt="Contabo plans list highlighting Cloud VPS options"
                  caption="Plans list — pick Cloud VPS 50 (64GB) or Cloud VPS 40 (48GB)."
                />
              </GuideStep>

              <GuideStep number={3} title="Configure your VPS">
                <ul className="mt-2 list-disc space-y-1 pl-5">
                  <li><strong>Region:</strong> Choose closest to you (US or EU)</li>
                  <li><strong>Storage:</strong> Keep the default NVMe option</li>
                  <li><strong>Image:</strong> Select &quot;Ubuntu 25.10&quot; or newest available</li>
                </ul>
                <p className="mt-2 text-xs text-muted-foreground">
                  If 25.10 isn&apos;t offered, Ubuntu 24.04 LTS is fine — ACFS upgrades to 25.10 automatically.
                </p>
                <ScreenshotFigure
                  file="contabo_us_03_order_page.png"
                  alt="Contabo order/configure page with region and image selections"
                  caption="Configure page — choose region + Ubuntu image, then continue checkout."
                />
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
                quickly, usually within minutes (occasionally up to ~1 hour).
              </GuideStep>
            </div>
          </GuideSection>

          <GuideSection title="Step-by-Step: Signing Up (OVH Example)">
            <div className="space-y-4">
              <GuideStep number={1} title="Go to OVH's VPS page">
                Click on &quot;OVH&quot; above, or go to{" "}
                <TrackedLink href="https://us.ovhcloud.com/vps/" trackingId="ovh-guide-link" className="text-primary underline">
                  us.ovhcloud.com/vps
                </TrackedLink>
                <ScreenshotFigure
                  file="ovh_us_01_main.png"
                  alt="OVH VPS page showing plan tiers and call-to-action buttons"
                  caption="OVH VPS page (US) — pick a VPS tier to start ordering."
                />
              </GuideStep>

              <GuideStep number={2} title="Choose VPS-5 (64GB) or VPS-4 (48GB)">
                We recommend:
                <ul className="mt-2 list-disc space-y-1 pl-5">
                  <li><strong>VPS-5:</strong> 64GB RAM (best for multi-agent work)</li>
                  <li><strong>VPS-4:</strong> 48GB RAM (budget option)</li>
                </ul>
                Click &quot;Order&quot; to continue.
                <ScreenshotFigure
                  file="ovh_us_02_plans.png"
                  alt="OVH plans list showing VPS-4 and VPS-5 options"
                  caption="Plans list — select VPS-5 (64GB) or VPS-4 (48GB), then click Order."
                />
              </GuideStep>

              <GuideStep number={3} title="Configure your order">
                During configuration, look for:
                <ul className="mt-2 list-disc space-y-1 pl-5">
                  <li><strong>Image/OS:</strong> Ubuntu 25.10 (or latest available)</li>
                  <li><strong>Region:</strong> Closest to you (US-East/US-West/EU)</li>
                  <li><strong>Authentication:</strong> Password (skip SSH keys for now)</li>
                </ul>
                <ScreenshotFigure
                  file="ovh_us_03_order.png"
                  alt="OVH order/configuration flow showing OS and region selections"
                  caption="Order flow — pick Ubuntu + region, then continue to checkout."
                />
                <p className="mt-2 text-xs text-muted-foreground">
                  If Ubuntu 25.10 isn&apos;t available, Ubuntu 24.04 LTS is fine — ACFS upgrades automatically.
                </p>
              </GuideStep>

              <GuideStep number={4} title="Create an account + pay">
                OVH will prompt you to create an account and add a payment method.
                Once the order completes, activation is usually instant.
              </GuideStep>
            </div>
          </GuideSection>

          <GuideSection title="Understanding the specs">
            <p className="mb-3">
              When choosing a plan, you&apos;ll see terms like vCPU, RAM, and NVMe.
              Here&apos;s what they mean:
            </p>
            <ul className="space-y-2">
              <li>
                <strong>vCPU (12+):</strong> The &quot;brain&quot; of the computer. More = faster.
                12 vCPU is comfortable for multi-agent work, 16 is great.
              </li>
              <li>
                <strong>RAM (48–64 GB):</strong> Short-term memory. This is crucial for running
                multiple AI agents. 32GB is absolute minimum; 48GB+ is recommended.
              </li>
              <li>
                <strong>Storage (250GB+ NVMe):</strong> Long-term storage for files, databases,
                and AI model caches. NVMe is fast. 250GB is a good starting point.
              </li>
              <li>
                <strong>Ubuntu:</strong> The operating system we&apos;ll install. It&apos;s like
                Windows or macOS, but for servers. It&apos;s free and widely used.
              </li>
            </ul>
          </GuideSection>

          <GuideSection title="Backup Strategy">
            <p className="mb-3 text-sm text-muted-foreground">
              Both providers offer VPS snapshots (~$2-5/month) for quick restore points. But for code,
              <strong> <Jargon term="github">GitHub</Jargon> is your real backup</strong>:
            </p>
            <ul className="space-y-2 text-sm">
              <li>
                <strong>Push to GitHub regularly.</strong> If your VPS dies, your code is safe. We install the{" "}
                <code className="rounded bg-muted px-1">gh</code> CLI for easy GitHub access.
              </li>
              <li>
                <strong>Open-source = free everything.</strong> Public repos, unlimited Actions, GitHub Pages, all free.
              </li>
              <li>
                <strong>Private projects:</strong> Free tier works for individuals. Teams or heavy CI/CD may need
                GitHub Pro ($4/month) or Team ($4/user/month) for more Actions minutes.
              </li>
            </ul>
          </GuideSection>

          <GuideTip>
            <strong>TL;DR:</strong> Get Contabo <strong>Cloud VPS 50</strong> (64GB RAM, 16 vCPU, ~$56/month US).
            Don&apos;t overthink it. 64GB is the right choice when you&apos;re investing $400+/month in AI subscriptions.
            Contabo can take up to an hour to provision (usually minutes); OVH is typically faster.
          </GuideTip>

          <GuideCaution>
            <strong>Keep your account credentials safe!</strong> Write down your
            login email and password somewhere secure. You&apos;ll need them to
            manage your VPS later.
          </GuideCaution>
        </div>
      </SimplerGuide>

      {/* Transition to next step */}
      <AlertCard variant="info" icon={Info} title="Account created?">
        Next, you&apos;ll create and launch your actual VPS instance.
      </AlertCard>

      {/* Continue button */}
      <div className="flex justify-end pt-4">
        <Button onClick={handleContinue} disabled={isNavigating} size="lg" disableMotion>
          {isNavigating ? "Loading..." : "I rented a VPS"}
        </Button>
      </div>
    </div>
  );
}
