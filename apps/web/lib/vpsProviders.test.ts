import { describe, expect, test } from "bun:test";
import {
  ACFS_RECOMMENDED_MIN_RAM_GB,
  PRICING_LAST_UPDATED,
  VPS_PROVIDERS,
  VPS_TOP_PICK,
  calculateRequiredSpecs,
  describePlan,
  getWorkloadProfile,
  isBelowRamRecommendation,
  validateVPSReadiness,
  type VPSReadinessCheckId,
  type VPSReadinessInput,
  type VPSReadinessResult,
  type VPSReadinessStatus,
} from "./vpsProviders";

function checkStatus(result: VPSReadinessResult, id: string) {
  return result.checks.find((check) => check.id === id)?.status;
}

type ProviderReadinessScenario = {
  category: string;
  selectedRecommendation: string;
  artifactPath: string;
  input: VPSReadinessInput;
  expectedStatus: VPSReadinessStatus;
  expectedChecks: Partial<Record<VPSReadinessCheckId, VPSReadinessStatus>>;
};

describe("VPS provider table", () => {
  test("records when the plan data was last verified", () => {
    expect(PRICING_LAST_UPDATED).toMatch(/^\d{4}-(0[1-9]|1[0-2])$/);
  });

  test("steers beginners to a provider whose plans meet the RAM recommendation", () => {
    expect(VPS_TOP_PICK.id).toBe("contabo");
    expect(VPS_TOP_PICK.recommended.ramGB).toBeGreaterThanOrEqual(64);
    expect(VPS_TOP_PICK.budget.ramGB).toBeGreaterThanOrEqual(ACFS_RECOMMENDED_MIN_RAM_GB);
    expect(isBelowRamRecommendation(VPS_TOP_PICK.recommended)).toBe(false);
    expect(isBelowRamRecommendation(VPS_TOP_PICK.budget)).toBe(false);
  });

  test("flags every listed plan below the RAM recommendation with a note", () => {
    const flagged = VPS_PROVIDERS.flatMap((provider) => [provider.recommended, provider.budget])
      .filter(isBelowRamRecommendation);

    expect(flagged.map((plan) => plan.name)).toEqual(["VPS-4", "VPS-3"]);
    for (const plan of flagged) {
      expect(plan.note).toContain(`${ACFS_RECOMMENDED_MIN_RAM_GB} GB`);
    }
  });

  test("describes plans for guide prose from the data table", () => {
    expect(describePlan(VPS_TOP_PICK.recommended)).toBe(
      "Cloud VPS 16 (64GB RAM, 16 vCPU): ~$43/month"
    );
  });
});

describe("VPS capacity sizing", () => {
  test("keeps the wizard calculator aligned with the standard ACFS profile", () => {
    const standard = getWorkloadProfile("standard");
    const heavy = getWorkloadProfile("heavy");

    expect(calculateRequiredSpecs(10, standard, true)).toEqual({
      ramGB: 64,
      vCPU: 16,
      storageGB: 250,
    });
    expect(calculateRequiredSpecs(25, heavy, true)).toEqual({
      ramGB: 192,
      vCPU: 96,
      storageGB: 250,
    });
  });
});

describe("validateVPSReadiness", () => {
  test("covers supported, unknown, and unsafe provider choices as a readiness matrix", () => {
    const scenarios: ProviderReadinessScenario[] = [
      {
        category: "supported",
        selectedRecommendation: "Contabo Cloud VPS 16",
        artifactPath: "apps/web/lib/vpsProviders.test.ts#provider-readiness-matrix",
        input: {
          providerId: "contabo",
          planName: "Cloud VPS 16",
          ubuntuVersion: "25.10",
          region: "us",
          targetAgents: 10,
          workloadId: "standard",
        },
        expectedStatus: "supported",
        expectedChecks: {
          provider: "supported",
          plan: "supported",
          os: "supported",
          region: "supported",
          capacity: "supported",
        },
      },
      {
        category: "unknown",
        selectedRecommendation: "manual spec comparison",
        artifactPath: "apps/web/lib/vpsProviders.test.ts#provider-readiness-matrix",
        input: {
          providerId: "other",
          planName: "custom plan",
          ubuntuVersion: "25.10",
          region: "not-listed",
          targetAgents: 10,
          workloadId: "standard",
        },
        expectedStatus: "unknown",
        expectedChecks: {
          provider: "unknown",
          plan: "unknown",
          os: "unknown",
          region: "unknown",
        },
      },
      {
        category: "unsafe",
        selectedRecommendation: "choose Ubuntu 24.04+ and a larger host",
        artifactPath: "apps/web/lib/vpsProviders.test.ts#provider-readiness-matrix",
        input: {
          providerId: "ovh",
          planName: "VPS-4",
          ubuntuVersion: "20.04",
          region: "us-east",
          targetAgents: 25,
          workloadId: "heavy",
        },
        expectedStatus: "unsupported",
        expectedChecks: {
          provider: "supported",
          plan: "borderline",
          os: "unsupported",
          region: "supported",
          capacity: "unsupported",
        },
      },
    ];

    for (const scenario of scenarios) {
      const result = validateVPSReadiness(scenario.input);

      expect(result.status).toBe(scenario.expectedStatus);
      for (const [checkId, status] of Object.entries(scenario.expectedChecks) as Array<
        [VPSReadinessCheckId, VPSReadinessStatus]
      >) {
        expect(checkStatus(result, checkId)).toBe(status);
      }
      expect(scenario.artifactPath).toContain("vpsProviders.test.ts");
      expect(scenario.selectedRecommendation.length).toBeGreaterThan(0);
    }
  });

  test("supports a recommended provider plan, Ubuntu image, region, and target", () => {
    const result = validateVPSReadiness({
      providerId: "contabo",
      planName: "Cloud VPS 16",
      ubuntuVersion: "25.10",
      region: "us",
      targetAgents: 10,
      workloadId: "standard",
    });

    expect(result.status).toBe("supported");
    expect(result.provider?.name).toBe("Contabo");
    expect(result.plan?.name).toBe("Cloud VPS 16");
    expect(checkStatus(result, "capacity")).toBe("supported");
  });

  test("marks a below-recommendation plan as borderline even when the target fits", () => {
    const result = validateVPSReadiness({
      providerId: "ovh",
      planName: "VPS-4",
      ubuntuVersion: "25.10",
      region: "us-east",
      targetAgents: 3,
      workloadId: "light",
    });

    expect(checkStatus(result, "capacity")).toBe("supported");
    expect(checkStatus(result, "plan")).toBe("borderline");
    expect(result.status).toBe("borderline");
    expect(result.checks.find((check) => check.id === "plan")?.message).toContain(
      `below the ${ACFS_RECOMMENDED_MIN_RAM_GB}GB ACFS recommendation`
    );
  });

  test("marks a budget plan as borderline when the target leaves little headroom", () => {
    const result = validateVPSReadiness({
      providerId: "contabo",
      planName: "Cloud VPS 12",
      ubuntuVersion: "24.04",
      region: "us",
      targetAgents: 10,
      workloadId: "standard",
    });

    expect(result.status).toBe("borderline");
    expect(checkStatus(result, "capacity")).toBe("borderline");
    expect(result.summary).toContain("Workable");
  });

  test("marks too-small capacity and old Ubuntu images as unsupported", () => {
    const result = validateVPSReadiness({
      providerId: "ovh",
      planName: "VPS-4",
      ubuntuVersion: "20.04",
      region: "us-east",
      targetAgents: 25,
      workloadId: "heavy",
    });

    expect(result.status).toBe("unsupported");
    expect(checkStatus(result, "capacity")).toBe("unsupported");
    expect(checkStatus(result, "os")).toBe("unsupported");
  });

  test("surfaces weak provider regions as advisory warnings", () => {
    const result = validateVPSReadiness({
      providerId: "contabo",
      planName: "Cloud VPS 16",
      ubuntuVersion: "25.10",
      region: "asia",
      targetAgents: 10,
      workloadId: "standard",
    });

    expect(result.status).toBe("borderline");
    expect(checkStatus(result, "region")).toBe("borderline");
  });

  test("keeps unknown providers advisory instead of pretending they are safe", () => {
    const result = validateVPSReadiness({
      providerId: "other",
      planName: "custom plan",
      ubuntuVersion: "25.10",
      region: "not-listed",
      targetAgents: 10,
      workloadId: "standard",
    });

    expect(result.status).toBe("unknown");
    expect(result.provider).toBeNull();
    expect(result.plan).toBeNull();
    expect(checkStatus(result, "provider")).toBe("unknown");
    expect(checkStatus(result, "plan")).toBe("unknown");
  });

  test("keeps unknown plans advisory even for a known provider", () => {
    // Cloud VPS 8 is a real Contabo plan (24 GB) that ACFS deliberately does not list.
    const result = validateVPSReadiness({
      providerId: "contabo",
      planName: "Cloud VPS 8",
      ubuntuVersion: "25.10",
      region: "us",
      targetAgents: 10,
      workloadId: "standard",
    });

    expect(result.status).toBe("unknown");
    expect(result.provider?.name).toBe("Contabo");
    expect(result.plan).toBeNull();
    expect(checkStatus(result, "plan")).toBe("unknown");
  });
});
