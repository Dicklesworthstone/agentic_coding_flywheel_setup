import { describe, expect, test } from "bun:test";
import { normalizeVPSReadinessSelection } from "./userPreferences";
import { validateUbuntuImage } from "./vpsProviders";

const selectedHost = {
  providerId: "contabo",
  planName: "Cloud VPS 16",
  ubuntuVersion: "26.04",
  region: "us",
  targetAgents: 10,
  workloadId: "standard",
};

describe("saved VPS readiness is evidence, not a recommendation", () => {
  for (const ubuntuVersion of ["20.04", "23.10", "24.10", "25.04", "25.10"]) {
    test(`does not silently upgrade a saved Ubuntu ${ubuntuVersion} host`, () => {
      const restored = normalizeVPSReadinessSelection({ ...selectedHost, ubuntuVersion });
      expect(restored?.ubuntuVersion).toBe(ubuntuVersion);
      expect(validateUbuntuImage(restored!.ubuntuVersion).status).toBe("unsupported");
      expect(normalizeVPSReadinessSelection(restored)).toEqual(restored);
    });
  }

  for (const ubuntuVersion of ["22.04", "24.04"]) {
    test(`preserves the upgrade warning for Ubuntu ${ubuntuVersion}`, () => {
      const restored = normalizeVPSReadinessSelection({ ...selectedHost, ubuntuVersion });
      expect(restored?.ubuntuVersion).toBe(ubuntuVersion);
      expect(validateUbuntuImage(restored!.ubuntuVersion).status).toBe("borderline");
    });
  }

  for (const ubuntuVersion of [undefined, null, 26.04, "", "Debian 26.04", "Ubuntu 26.04 trailing text", "28.04", "password=secret"]) {
    test(`does not invent an installed image from ${JSON.stringify(ubuntuVersion)}`, () => {
      const restored = normalizeVPSReadinessSelection({ ...selectedHost, ubuntuVersion });
      expect(restored?.ubuntuVersion).toBe("unknown");
      expect(validateUbuntuImage(restored!.ubuntuVersion).status).toBe("unknown");
      expect(normalizeVPSReadinessSelection(restored)).toEqual(restored);
      expect(JSON.stringify(restored)).not.toContain("password=secret");
    });
  }

  for (const ubuntuVersion of ["26.04", "26.04.1", "Ubuntu 26.04.1 LTS", " ubuntu 26.04 lts "]) {
    test(`normalizes a reviewed image label ${JSON.stringify(ubuntuVersion)}`, () => {
      const restored = normalizeVPSReadinessSelection({ ...selectedHost, ubuntuVersion });
      expect(restored?.ubuntuVersion).toBe("26.04");
      expect(validateUbuntuImage(restored!.ubuntuVersion).status).toBe("supported");
    });
  }

  test("does not replace an unlisted small plan with the recommended larger plan", () => {
    const restored = normalizeVPSReadinessSelection({ ...selectedHost, planName: "Cloud VPS 8" });
    expect(restored?.planName).toBe("custom plan");
    expect(restored?.providerId).toBe("contabo");
    expect(normalizeVPSReadinessSelection(restored)).toEqual(restored);
  });

  test("does not replace an unrecognized region with the first supported region", () => {
    const restored = normalizeVPSReadinessSelection({ ...selectedHost, region: "not-a-reviewed-region" });
    expect(restored?.region).toBe("not-listed");
    expect(normalizeVPSReadinessSelection(restored)).toEqual(restored);
  });

  test("preserves known plan names and canonicalizes known provider/region aliases", () => {
    expect(normalizeVPSReadinessSelection({
      ...selectedHost,
      providerId: " CONTABO ",
      planName: " cloud vps 12 ",
      region: "united states",
    })).toEqual({ ...selectedHost, planName: "Cloud VPS 12" });
  });

  test("incomplete stored objects cannot become purchase-ready hosts", () => {
    expect(normalizeVPSReadinessSelection({ providerId: "contabo" })).toEqual({
      ...selectedHost,
      planName: "custom plan",
      ubuntuVersion: "unknown",
      region: "not-listed",
    });
  });

  test("drops arbitrary unreviewed provider metadata rather than persisting it", () => {
    const restored = normalizeVPSReadinessSelection({
      ...selectedHost,
      providerId: "password=secret",
      planName: "password=secret",
      region: "password=secret",
    });
    expect(restored?.providerId).toBe("other");
    expect(restored?.planName).toBe("custom plan");
    expect(restored?.region).toBe("not-listed");
    expect(JSON.stringify(restored)).not.toContain("password=secret");
  });

  test("retains existing numeric and workload normalization", () => {
    expect(normalizeVPSReadinessSelection({ ...selectedHost, targetAgents: 13, workloadId: "invalid" }))
      .toEqual({ ...selectedHost, targetAgents: 15 });
    expect(normalizeVPSReadinessSelection({ ...selectedHost, targetAgents: Infinity })?.targetAgents).toBe(10);
    expect(normalizeVPSReadinessSelection({ ...selectedHost, targetAgents: -10 })?.targetAgents).toBe(5);
    expect(normalizeVPSReadinessSelection({ ...selectedHost, targetAgents: 100 })?.targetAgents).toBe(50);
  });

  for (const value of [null, undefined, [], "26.04", 42]) {
    test(`rejects non-object saved state ${JSON.stringify(value)}`, () => {
      expect(normalizeVPSReadinessSelection(value)).toBeNull();
    });
  }
});
