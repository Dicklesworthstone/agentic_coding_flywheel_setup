/**
 * VPS provider data for the comparison table in the wizard.
 *
 * Prices are as of early 2026 and should be reviewed periodically.
 * Provider data is separated from UI so it's easy to update without
 * touching component code.
 *
 * @see bd-w8fx
 */

export interface VPSPlan {
  /** Plan name as shown by the provider */
  name: string;
  /** RAM in GB */
  ramGB: number;
  /** Number of virtual CPUs */
  vCPU: number;
  /** Storage in GB */
  storageGB: number;
  /** Monthly price in USD (no-commitment) */
  priceUSD: number;
}

export type VPSRegionStatus = "supported" | "borderline";

export interface VPSRegionOption {
  id: string;
  label: string;
  status: VPSRegionStatus;
  aliases: string[];
  note: string;
}

export interface VPSProviderReadiness {
  recommendedUbuntu: string;
  preferredUbuntuVersions: string[];
  minimumUbuntu: string;
  cautionBelowUbuntu: string;
}

export interface VPSProvider {
  id: string;
  name: string;
  /** One-line description */
  tagline: string;
  /** URL to VPS product page */
  url: string;
  /** Recommended plan tier for 64GB or best available */
  recommended: VPSPlan;
  /** Budget plan tier for 48GB or best available */
  budget: VPSPlan;
  /** Typical activation time */
  activationTime: string;
  /** Key differentiator */
  bestFor: string;
  /** Data center regions available */
  regions: string;
  /** Structured region guidance for purchase-time validation */
  regionOptions: VPSRegionOption[];
  /** Structured OS image guidance for purchase-time validation */
  readiness: VPSProviderReadiness;
  /** Whether this provider is our top recommendation */
  isTopPick?: boolean;
  /** Additional notes */
  note?: string;
}

export type WorkloadId = "light" | "standard" | "heavy";
export type PlanStatus = "pass" | "warn" | "fail";

export const VPS_UBUNTU_IMAGE_OPTIONS = ["25.10", "24.04", "22.04", "20.04"] as const;

export interface WorkloadProfile {
  id: WorkloadId;
  label: string;
  summary: string;
  ramPerAgentGB: number;
  cpuPerAgent: number;
}

export interface RequiredSpecs {
  ramGB: number;
  vCPU: number;
  storageGB: number;
}

export interface EvaluatedProviderPlan {
  providerName: string;
  plan: VPSPlan;
  recommendedAgents: number;
  safeAgents: number;
  status: PlanStatus;
}

export type VPSReadinessStatus =
  | "supported"
  | "borderline"
  | "unsupported"
  | "unknown";

export type VPSReadinessCheckId =
  | "provider"
  | "plan"
  | "os"
  | "region"
  | "capacity";

export interface VPSReadinessCheck {
  id: VPSReadinessCheckId;
  label: string;
  status: VPSReadinessStatus;
  message: string;
}

export interface VPSReadinessInput {
  providerId: string;
  planName: string;
  ubuntuVersion: string;
  region: string;
  targetAgents: number;
  workloadId: WorkloadId;
}

export interface VPSReadinessResult {
  status: VPSReadinessStatus;
  summary: string;
  provider: VPSProvider | null;
  plan: VPSPlan | null;
  checks: VPSReadinessCheck[];
}

export const VPS_WORKLOAD_PROFILES: WorkloadProfile[] = [
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

const RAM_TIERS = [32, 48, 64, 96, 128, 192, 256, 384];
const CPU_TIERS = [8, 12, 16, 24, 32, 48, 64, 96, 128, 160];
const STORAGE_TIERS = [250, 400, 640, 800, 1000];
const READINESS_SUMMARIES: Record<VPSReadinessStatus, string> = {
  supported: "Ready for the selected target.",
  borderline: "Workable, but verify the warning before purchase.",
  unsupported: "Do not choose this combination for ACFS.",
  unknown: "Not in the ACFS provider table; compare the specs manually.",
};

export const VPS_PROVIDERS: VPSProvider[] = [
  {
    id: "contabo",
    name: "Contabo",
    tagline: "Best specs-to-price ratio",
    url: "https://contabo.com/en-us/vps/",
    recommended: {
      name: "Cloud VPS 50",
      ramGB: 64,
      vCPU: 16,
      storageGB: 400,
      priceUSD: 56,
    },
    budget: {
      name: "Cloud VPS 40",
      ramGB: 48,
      vCPU: 12,
      storageGB: 300,
      priceUSD: 36,
    },
    activationTime: "Minutes (up to ~1 hr)",
    bestFor: "Best value overall",
    regions: "US, EU, Asia, AU",
    regionOptions: [
      {
        id: "us",
        label: "US",
        status: "supported",
        aliases: ["us", "usa", "united states", "us-east", "us-west"],
        note: "Good default for users in North America.",
      },
      {
        id: "eu",
        label: "EU",
        status: "supported",
        aliases: ["eu", "europe", "germany"],
        note: "Good default for users in Europe.",
      },
      {
        id: "asia",
        label: "Asia",
        status: "borderline",
        aliases: ["asia", "singapore"],
        note: "Use this only if it is close to you or your users.",
      },
      {
        id: "au",
        label: "AU",
        status: "borderline",
        aliases: ["au", "australia"],
        note: "Use this only if it is close to you or your users.",
      },
    ],
    readiness: {
      recommendedUbuntu: "25.10",
      preferredUbuntuVersions: ["25.10", "24.04"],
      minimumUbuntu: "22.04",
      cautionBelowUbuntu: "24.04",
    },
    isTopPick: true,
    note: "US datacenter pricing includes ~$10/mo surcharge",
  },
  {
    id: "ovh",
    name: "OVH",
    tagline: "Polished interface, fast activation",
    url: "https://us.ovhcloud.com/vps/",
    recommended: {
      name: "VPS-5",
      ramGB: 64,
      vCPU: 16,
      storageGB: 640,
      priceUSD: 40,
    },
    budget: {
      name: "VPS-4",
      ramGB: 48,
      vCPU: 12,
      storageGB: 480,
      priceUSD: 26,
    },
    activationTime: "Minutes",
    bestFor: "Lowest 64GB price",
    regions: "US, EU, CA, Asia",
    regionOptions: [
      {
        id: "us-east",
        label: "US East",
        status: "supported",
        aliases: ["us-east", "us east", "virginia", "vint hill", "us"],
        note: "Good default for users in eastern or central North America.",
      },
      {
        id: "us-west",
        label: "US West",
        status: "supported",
        aliases: ["us-west", "us west", "hillsboro"],
        note: "Good default for users in western North America.",
      },
      {
        id: "ca",
        label: "Canada",
        status: "supported",
        aliases: ["ca", "canada"],
        note: "Good default for users in Canada.",
      },
      {
        id: "eu",
        label: "EU",
        status: "supported",
        aliases: ["eu", "europe", "france", "germany"],
        note: "Good default for users in Europe.",
      },
      {
        id: "asia",
        label: "Asia",
        status: "borderline",
        aliases: ["asia", "singapore", "apac"],
        note: "Use this only if it is close to you or your users.",
      },
    ],
    readiness: {
      recommendedUbuntu: "25.10",
      preferredUbuntuVersions: ["25.10", "24.04"],
      minimumUbuntu: "22.04",
      cautionBelowUbuntu: "24.04",
    },
  },
];

/** Date the pricing data was last verified */
export const PRICING_LAST_UPDATED = "2026-01";

function roundUpToTier(value: number, tiers: number[]): number {
  return tiers.find((tier) => tier >= value) ?? tiers[tiers.length - 1];
}

function normalizeText(value: string): string {
  return value.trim().toLowerCase();
}

function parseUbuntuVersion(value: string): [number, number] | null {
  const match = value.match(/(\d{2})\.(\d{2})/);
  if (!match) return null;
  return [Number(match[1]), Number(match[2])];
}

function compareVersion(left: string, right: string): number | null {
  const parsedLeft = parseUbuntuVersion(left);
  const parsedRight = parseUbuntuVersion(right);
  if (!parsedLeft || !parsedRight) return null;
  const [leftMajor, leftMinor] = parsedLeft;
  const [rightMajor, rightMinor] = parsedRight;
  if (leftMajor !== rightMajor) return leftMajor - rightMajor;
  return leftMinor - rightMinor;
}

function combineStatuses(checks: VPSReadinessCheck[]): VPSReadinessStatus {
  if (checks.some((check) => check.status === "unsupported")) return "unsupported";
  if (checks.some((check) => check.status === "unknown")) return "unknown";
  if (checks.some((check) => check.status === "borderline")) return "borderline";
  return "supported";
}

function readinessSummary(status: VPSReadinessStatus): string {
  return READINESS_SUMMARIES[status];
}

export function getWorkloadProfile(workloadId: WorkloadId): WorkloadProfile {
  return (
    VPS_WORKLOAD_PROFILES.find((profile) => profile.id === workloadId) ??
    VPS_WORKLOAD_PROFILES[1]
  );
}

export function calculateRequiredSpecs(
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

export function evaluatePlan(
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

export function evaluateProviderPlans(
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

export function getProviderPlan(
  provider: VPSProvider,
  planName: string
): VPSPlan | null {
  const normalizedPlan = normalizeText(planName);
  if (normalizedPlan === "recommended") return provider.recommended;
  if (normalizedPlan === "budget") return provider.budget;

  return (
    ([provider.recommended, provider.budget] as const).find(
      (plan) => normalizeText(plan.name) === normalizedPlan
    ) ?? null
  );
}

export function validateVPSReadiness(
  input: VPSReadinessInput
): VPSReadinessResult {
  const provider =
    VPS_PROVIDERS.find((entry) => normalizeText(entry.id) === normalizeText(input.providerId)) ??
    null;
  const workload = getWorkloadProfile(input.workloadId);
  const requestedAgents = Number.isFinite(input.targetAgents) ? input.targetAgents : 10;
  const targetAgents = Math.max(1, Math.floor(requestedAgents));
  const checks: VPSReadinessCheck[] = [];

  if (!provider) {
    checks.push({
      id: "provider",
      label: "Provider",
      status: "unknown",
      message:
        "This provider is not in the ACFS table. Use the calculator specs and verify Ubuntu support, SSH access, and region manually.",
    });
    checks.push({
      id: "plan",
      label: "Plan",
      status: "unknown",
      message:
        "Plan capacity is unknown. Compare RAM, vCPU, and NVMe storage against the recommended host size before purchase.",
    });
    checks.push({
      id: "os",
      label: "Ubuntu image",
      status: "unknown",
      message: "Confirm the provider offers Ubuntu 24.04 or newer.",
    });
    checks.push({
      id: "region",
      label: "Region",
      status: "unknown",
      message: "Choose the closest region with normal VPS availability.",
    });

    return {
      status: "unknown",
      summary: readinessSummary("unknown"),
      provider,
      plan: null,
      checks,
    };
  }

  checks.push({
    id: "provider",
    label: "Provider",
    status: "supported",
    message: `${provider.name} is in the ACFS guidance table.`,
  });

  const plan = getProviderPlan(provider, input.planName);
  if (!plan) {
    checks.push({
      id: "plan",
      label: "Plan",
      status: "unknown",
      message: `${provider.name} ${input.planName || "plan"} is not in the ACFS table. Compare its RAM, vCPU, and NVMe storage manually.`,
    });
  } else {
    const capacity = evaluatePlan(plan, workload, targetAgents);
    const capacityStatus: VPSReadinessStatus =
      capacity.status === "pass"
        ? "supported"
        : capacity.status === "warn"
          ? "borderline"
          : "unsupported";
    checks.push({
      id: "plan",
      label: "Plan",
      status: "supported",
      message: `${provider.name} ${plan.name} has ${plan.ramGB}GB RAM, ${plan.vCPU} vCPU, and ${plan.storageGB}GB storage.`,
    });
    checks.push({
      id: "capacity",
      label: "Capacity",
      status: capacityStatus,
      message:
        capacity.status === "pass"
          ? `Comfortable for about ${capacity.recommendedAgents} ${workload.label.toLowerCase()} agents.`
          : capacity.status === "warn"
            ? `Borderline: safe ceiling is about ${capacity.safeAgents} ${workload.label.toLowerCase()} agents, with little headroom.`
            : `Undersized: safe ceiling is about ${capacity.safeAgents} ${workload.label.toLowerCase()} agents.`,
    });
  }

  const ubuntuComparison = compareVersion(input.ubuntuVersion, provider.readiness.minimumUbuntu);
  const cautionComparison = compareVersion(input.ubuntuVersion, provider.readiness.cautionBelowUbuntu);
  if (ubuntuComparison === null) {
    checks.push({
      id: "os",
      label: "Ubuntu image",
      status: "unknown",
      message: "Choose Ubuntu, not Debian or another image, unless you plan to validate the installer yourself.",
    });
  } else if (ubuntuComparison < 0) {
    checks.push({
      id: "os",
      label: "Ubuntu image",
      status: "unsupported",
      message: `Ubuntu ${input.ubuntuVersion} is below the ACFS minimum of ${provider.readiness.minimumUbuntu}.`,
    });
  } else if (cautionComparison !== null && cautionComparison < 0) {
    checks.push({
      id: "os",
      label: "Ubuntu image",
      status: "borderline",
      message: `Ubuntu ${input.ubuntuVersion} can install, but ${provider.readiness.cautionBelowUbuntu}+ avoids extra upgrade hops.`,
    });
  } else if (provider.readiness.preferredUbuntuVersions.includes(input.ubuntuVersion)) {
    checks.push({
      id: "os",
      label: "Ubuntu image",
      status: "supported",
      message: `Ubuntu ${input.ubuntuVersion} is a preferred ACFS image.`,
    });
  } else {
    checks.push({
      id: "os",
      label: "Ubuntu image",
      status: "supported",
      message: `Ubuntu ${input.ubuntuVersion} is new enough for ACFS.`,
    });
  }

  const normalizedRegion = normalizeText(input.region);
  const region = provider.regionOptions.find(
    (option) =>
      normalizeText(option.id) === normalizedRegion ||
      option.aliases.some((alias) => normalizeText(alias) === normalizedRegion)
  );
  if (!region) {
    checks.push({
      id: "region",
      label: "Region",
      status: "borderline",
      message: "This region is not in the ACFS table. Prefer a nearby US, Canada, or EU region when available.",
    });
  } else {
    checks.push({
      id: "region",
      label: "Region",
      status: region.status,
      message: `${region.label}: ${region.note}`,
    });
  }

  const status = combineStatuses(checks);
  return {
    status,
    summary: readinessSummary(status),
    provider,
    plan,
    checks,
  };
}
