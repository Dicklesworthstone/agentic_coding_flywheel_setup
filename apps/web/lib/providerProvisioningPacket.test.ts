import { describe, expect, test } from "bun:test";
import {
  buildProviderProvisioningPacket,
  PROVIDER_PACKET_BASE_VERIFICATION_COMMANDS,
  PROVIDER_PACKET_EXPECTED_ARTIFACTS,
  PROVIDER_PACKET_FORBIDDEN_FIELD_NAMES,
  PROVIDER_PACKET_REDACTED_FIELD_PATHS,
  PROVIDER_PACKET_REQUIRED_FIELD_PATHS,
  PROVIDER_PACKET_SUPPORT_BUNDLE_SAFE_PATHS,
  PROVIDER_PROVISIONING_PACKET_SCHEMA,
  PROVIDER_PROVISIONING_PACKET_SCHEMA_VERSION,
  manualStepsForProvider,
  serializeProviderProvisioningPacketJson,
} from "./providerProvisioningPacket";
import { VPS_PROVIDERS } from "./vpsProviders";

describe("provider provisioning packet contract", () => {
  test("pins a stable v1 schema id", () => {
    expect(PROVIDER_PROVISIONING_PACKET_SCHEMA).toBe("acfs.provider-provisioning-packet.v1");
    expect(PROVIDER_PROVISIONING_PACKET_SCHEMA_VERSION).toBe(1);
  });

  test("requires the fields needed by provider automation and support handoff", () => {
    expect(PROVIDER_PACKET_REQUIRED_FIELD_PATHS).toEqual(
      expect.arrayContaining([
        "provider.id",
        "region.id",
        "size.planName",
        "size.ramGB",
        "size.vCPU",
        "size.storageGB",
        "osImage.version",
        "access.username",
        "access.sshPublicKeyLabel",
        "cloudInit.mode",
        "install.command",
        "compatibility.requiredSpecs",
        "compatibility.readinessStatus",
        "verificationCommands",
        "expectedArtifacts",
      ]),
    );
  });

  test("keeps support-bundle projection away from raw host and credential fields", () => {
    const safePathText = PROVIDER_PACKET_SUPPORT_BUNDLE_SAFE_PATHS.join("\n").toLowerCase();

    expect(safePathText).not.toContain("targethost.address");
    expect(safePathText).not.toContain("privatekey");
    expect(safePathText).not.toContain("token");
    expect(safePathText).not.toContain("password");
    expect(safePathText).not.toContain("rawuserdata");
    expect(PROVIDER_PACKET_FORBIDDEN_FIELD_NAMES).toEqual(
      expect.arrayContaining(["provider_api_key", "sshPrivateKey", "token", "password", "ip", "hostname"]),
    );
    expect(PROVIDER_PACKET_REDACTED_FIELD_PATHS).toEqual(
      expect.arrayContaining([
        "targetHost.address",
        "cloudInit.rawUserData",
        "access.sshPrivateKey",
        "install.environment",
      ]),
    );
  });

  test("defines support-safe verification commands and expected artifact metadata", () => {
    const commandIds = PROVIDER_PACKET_BASE_VERIFICATION_COMMANDS.map((command) => command.id);
    const supportSafeCommandIds = PROVIDER_PACKET_BASE_VERIFICATION_COMMANDS
      .filter((command) => command.supportBundleSafe)
      .map((command) => command.id);
    const artifactIds = PROVIDER_PACKET_EXPECTED_ARTIFACTS.map((artifact) => artifact.id);

    expect(commandIds).toEqual(["ssh-root", "installer", "doctor", "support-bundle"]);
    expect(supportSafeCommandIds).toEqual(["installer", "doctor", "support-bundle"]);
    for (const command of PROVIDER_PACKET_BASE_VERIFICATION_COMMANDS) {
      expect(command.command).not.toMatch(/<[^>]+>/);
    }
    expect(artifactIds).toEqual([
      "provider-order-confirmation",
      "installer-log",
      "support-report",
      "support-manifest",
    ]);
    expect(PROVIDER_PACKET_EXPECTED_ARTIFACTS.every((artifact) => artifact.redactionRequired)).toBe(true);
  });

  test("documents manual remaining steps for every current wizard provider", () => {
    for (const provider of VPS_PROVIDERS) {
      const steps = manualStepsForProvider(provider.id);

      expect(steps.length).toBeGreaterThanOrEqual(4);
      expect(steps.join("\n").toLowerCase()).toContain("manually");
    }
  });

  test("keeps manual wizard providers aligned with the password-first setup flow", () => {
    const contaboSteps = manualStepsForProvider("contabo").join("\n").toLowerCase();
    const ovhSteps = manualStepsForProvider("ovh").join("\n").toLowerCase();
    const forbiddenProviderKeyActions = [
      "paste or select the public ssh key",
      "attach the public ssh key",
      "upload the public ssh key",
      "add the public ssh key",
    ];

    for (const steps of [contaboSteps, ovhSteps]) {
      expect(steps).toContain("password");
      expect(steps).toContain("root");
      for (const phrase of forbiddenProviderKeyActions) {
        expect(steps).not.toContain(phrase);
      }
    }
    expect(ovhSteps).toContain("password authentication");
    expect(ovhSteps).toContain("skip the provider ssh key section");
  });

  test("falls back to generic manual steps for unknown providers", () => {
    const steps = manualStepsForProvider("not-listed");

    expect(steps.join("\n")).toContain("Verify the provider offers SSH access");
    expect(steps.join("\n").toLowerCase()).toContain("manually");
  });
});

describe("buildProviderProvisioningPacket", () => {
  const baseInput = {
    providerId: "contabo",
    planName: "Cloud VPS 50",
    ubuntuVersion: "25.10",
    region: "us",
    targetAgents: 10,
    workloadId: "standard" as const,
    installMode: "vibe" as const,
    sourceRef: "main",
    username: "ubuntu",
    targetHost: "203.0.113.42",
    generatedAt: "2026-05-08T20:00:00.000Z",
  };

  test("generates a deterministic, redacted Contabo packet from readiness data", () => {
    const packet = buildProviderProvisioningPacket(baseInput);
    const json = serializeProviderProvisioningPacketJson(packet);

    expect(packet.schema).toBe(PROVIDER_PROVISIONING_PACKET_SCHEMA);
    expect(packet.stage).toBe("ready_for_manual_provider_checkout");
    expect(packet.provider).toMatchObject({
      id: "contabo",
      name: "Contabo",
      automationLevel: "manual",
      manualCheckoutRequired: true,
    });
    expect(packet.compatibility).toMatchObject({
      workloadId: "standard",
      targetAgents: 10,
      selectedPlanStatus: "pass",
      readinessStatus: "supported",
    });
    expect(packet.install.command).toContain("--mode vibe");
    expect(packet.install.commandRunLocation).toBe("vps-root-shell");
    expect(packet.verificationCommands.map((command) => command.id)).toEqual([
      "ssh-root",
      "installer",
      "doctor",
      "support-bundle",
    ]);
    expect(packet.verificationCommands[1]?.command).toBe(packet.install.command);
    expect(json).toBe(serializeProviderProvisioningPacketJson(packet));
    expect(json).not.toContain("203.0.113.42");
    expect(json).not.toContain("BEGIN OPENSSH PRIVATE KEY");
  });

  test("marks Hetzner packets as cloud-init template handoffs with manual confirmations", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      providerId: "hetzner",
      planName: "CX52",
      region: "fsn1",
    });

    expect(packet.provider).toMatchObject({
      id: "hetzner",
      name: "Hetzner",
      automationLevel: "cloud_init_only",
    });
    expect(packet.stage).toBe("draft");
    expect(packet.cloudInit).toMatchObject({
      mode: "manual_paste",
      userDataIncluded: true,
      templateRef: "scripts/providers/hetzner-cloud-init.yml",
    });
    expect(packet.install.commandRunLocation).toBe("cloud-init");
    expect(packet.compatibility.readinessStatus).toBe("unknown");
    expect(packet.provider.manualStepsRemaining.join("\n")).toContain("Paste the ACFS cloud-init template");
  });

  test("blocks known provider packets with unsupported Ubuntu images", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      providerId: "ovh",
      planName: "VPS-5",
      ubuntuVersion: "20.04",
      region: "us-east",
    });

    expect(packet.provider.name).toBe("OVH");
    expect(packet.stage).toBe("blocked");
    expect(packet.osImage.readinessStatus).toBe("unsupported");
    expect(packet.compatibility.readinessChecks.find((check) => check.id === "os")?.status)
      .toBe("unsupported");
  });

  test("flags plan-size mismatches as unsupported capacity without losing the selected plan", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      providerId: "ovh",
      planName: "VPS-4",
      ubuntuVersion: "25.10",
      region: "us-east",
      targetAgents: 25,
      workloadId: "heavy",
    });

    expect(packet.stage).toBe("blocked");
    expect(packet.size.sourcePlan?.name).toBe("VPS-4");
    expect(packet.compatibility.selectedPlanStatus).toBe("fail");
    expect(packet.compatibility.readinessStatus).toBe("unsupported");
    expect(packet.compatibility.readinessChecks.find((check) => check.id === "capacity")?.status)
      .toBe("unsupported");
  });

  test("keeps unknown providers advisory and support-safe", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      providerId: "Linode",
      planName: "Shared 32 GB",
      region: "newark",
      sshPublicKeyFingerprint: "SHA256:fixture",
      sshPublicKeyMaterial: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixturePublicKey acfs",
    });
    const json = serializeProviderProvisioningPacketJson(packet);

    expect(packet.stage).toBe("draft");
    expect(packet.provider).toMatchObject({
      id: "linode",
      name: "Linode",
      automationLevel: "manual",
    });
    expect(packet.compatibility.selectedPlanStatus).toBe("unknown");
    expect(packet.compatibility.readinessStatus).toBe("unknown");
    expect(packet.size.sourcePlan).toBeNull();
    expect(packet.access.sshPrivateKeyIncluded).toBe(false);
    expect(json).not.toContain("203.0.113.42");
    expect(json).not.toContain("PRIVATE");
  });

  test("carries ref pins and module profile selectors into the install command", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      installMode: "safe",
      sourceRef: "v1.2.3",
      username: "dev-user",
      moduleSelection: { profile: "cloud-only" },
    });

    expect(packet.access.username).toBe("dev-user");
    expect(packet.provenance.sourceRef).toBe("v1.2.3");
    expect(packet.install.sourceRef).toBe("v1.2.3");
    expect(packet.install.moduleSelection).toEqual({ profile: "cloud-only" });
    expect(packet.install.command).toContain('TARGET_USER="dev-user"');
    expect(packet.install.command).toContain('--ref "v1.2.3"');
    expect(packet.install.command).toContain("/v1.2.3/install.sh");
    expect(packet.install.command).toContain('--only "cloud.wrangler"');
    expect(packet.install.command).toContain('--only "cloud.supabase"');
    expect(packet.install.command).toContain('--only "cloud.vercel"');
  });
});
