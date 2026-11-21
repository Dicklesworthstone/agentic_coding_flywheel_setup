import { describe, expect, test } from "bun:test";
import { buildInstallCommand } from "./commandBuilder";
import { type ModuleSelectionInput, resolveModuleSelection } from "./moduleSelection";
import {
  buildProviderProvisioningPacket,
  manualStepsForProvider,
  PROVIDER_PACKET_BASE_VERIFICATION_COMMANDS,
  PROVIDER_PACKET_EXPECTED_ARTIFACTS,
  PROVIDER_PACKET_FORBIDDEN_FIELD_NAMES,
  PROVIDER_PACKET_REDACTED_FIELD_PATHS,
  PROVIDER_PACKET_REQUIRED_FIELD_PATHS,
  PROVIDER_PACKET_SUPPORT_BUNDLE_SAFE_PATHS,
  PROVIDER_PROVISIONING_PACKET_SCHEMA,
  PROVIDER_PROVISIONING_PACKET_SCHEMA_VERSION,
  type ProviderProvisioningPacketInput,
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
      expect.arrayContaining([
        "provider_api_key",
        "sshPrivateKey",
        "token",
        "password",
        "ip",
        "hostname",
      ]),
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
    const supportSafeCommandIds = PROVIDER_PACKET_BASE_VERIFICATION_COMMANDS.filter(
      (command) => command.supportBundleSafe,
    ).map((command) => command.id);
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
    expect(PROVIDER_PACKET_EXPECTED_ARTIFACTS.every((artifact) => artifact.redactionRequired)).toBe(
      true,
    );
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
    planName: "Cloud VPS 16",
    ubuntuVersion: "26.04",
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
    expect(packet.install.command).not.toContain("$(date +%s)");
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
    expect(packet.provider.manualStepsRemaining.join("\n")).toContain(
      "Paste the ACFS cloud-init template",
    );
  });

  const customCloudInitChoices: Array<{ name: string; choices: Partial<ProviderProvisioningPacketInput> }> = [
    { name: "safe mode", choices: { installMode: "safe" } },
    { name: "custom user", choices: { username: "developer" } },
    { name: "tag pin", choices: { sourceRef: "v1.2.3" } },
    { name: "commit pin", choices: { sourceRef: "a".repeat(40) } },
    { name: "agent subset", choices: { moduleSelection: { profile: "agents-only" } } },
    { name: "explicit module roots", choices: { moduleSelection: { onlyModules: ["agents.codex"] } } },
    { name: "module exclusions", choices: { moduleSelection: { profile: "full", skipTags: ["cloud"] } } },
    { name: "dependency override", choices: { moduleSelection: { noDeps: true } } },
    { name: "mode override profile", choices: { moduleSelection: { profile: "safe" } } },
  ];
  for (const { name, choices } of customCloudInitChoices) {
    test(`routes ${name} through the exact manual command instead of the fixed cloud-init template`, () => {
      const input = { ...baseInput, providerId: "hetzner", planName: "CX52", region: "fsn1", ...choices };
      const packet = buildProviderProvisioningPacket(input);
      expect(packet.cloudInit.mode).toBe("none");
      expect(packet.cloudInit.userDataIncluded).toBe(false);
      expect(packet.cloudInit.templateRef).toBeUndefined();
      expect(packet.install.commandRunLocation).toBe("vps-root-shell");
      expect(packet.install.command).toBe(buildInstallCommand(
        input.installMode,
        input.sourceRef === "main" ? null : input.sourceRef,
        input.username,
        input.moduleSelection,
      ));
      expect(packet.verificationCommands.find((command) => command.id === "installer")?.command)
        .toBe(packet.install.command);
      expect(packet.cloudInit.notes.join(" ")).toContain("exact installer command");
      expect(packet.provider.manualStepsRemaining.join(" ")).toContain("Leave cloud-init user data blank");
      expect(packet.provider.manualStepsRemaining.join(" ")).not.toContain("Paste the ACFS cloud-init template");
    });
  }

  for (const ubuntuVersion of ["22.04", "24.04"]) {
    test(`preserves the existing readiness gate for Ubuntu ${ubuntuVersion} cloud-init handoffs`, () => {
      const packet = buildProviderProvisioningPacket({
        ...baseInput, providerId: "hetzner", planName: "CX52", region: "fsn1", ubuntuVersion,
      });
      expect(packet.cloudInit.mode).toBe("none");
      expect(packet.cloudInit.userDataIncluded).toBe(false);
      expect(packet.cloudInit.templateRef).toBeUndefined();
      expect(packet.install.commandRunLocation).toBe("vps-root-shell");
      expect(packet.install.command).not.toContain("curl");
      expect(packet.verificationCommands.find((command) => command.id === "installer")?.expectedStatus)
        .toBe("fail");
      expect(packet.provider.manualStepsRemaining.join(" ")).toContain("Leave cloud-init user data blank");
      expect(packet.provider.manualStepsRemaining.join(" ")).not.toContain("Paste the ACFS cloud-init template");
    });
  }

  for (const [index, choices] of [
    {},
    { moduleSelection: {} },
    { moduleSelection: { profile: "full" } },
    { moduleSelection: { profile: "vibe" } },
    { moduleSelection: { onlyModules: [], onlyPhases: [], skipModules: [], skipTags: [], skipCategories: [], noDeps: false } },
    { sourceRef: null, ubuntuVersion: "Ubuntu 26.04.1 LTS" },
  ].entries()) {
    test(`retains cloud-init for equivalent default installation ${index + 1}`, () => {
      const packet = buildProviderProvisioningPacket({
        ...baseInput,
        providerId: "hetzner",
        planName: "CX52",
        region: "fsn1",
        ...choices,
      } as ProviderProvisioningPacketInput);
      expect(packet.cloudInit.mode).toBe("manual_paste");
      expect(packet.cloudInit.userDataIncluded).toBe(true);
      expect(packet.cloudInit.templateRef).toBe("scripts/providers/hetzner-cloud-init.yml");
      expect(packet.install.commandRunLocation).toBe("cloud-init");
      expect(packet.provider.manualStepsRemaining.join(" ")).toContain("Paste the ACFS cloud-init template");
    });
  }

  test("blocks known provider packets with unsupported Ubuntu images", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      providerId: "ovh",
      planName: "VPS-4",
      ubuntuVersion: "20.04",
      region: "us-east",
    });

    expect(packet.provider.name).toBe("OVH");
    expect(packet.stage).toBe("blocked");
    expect(packet.osImage.readinessStatus).toBe("unsupported");
    expect(packet.compatibility.readinessChecks.find((check) => check.id === "os")?.status).toBe(
      "unsupported",
    );
  });

  test("flags plan-size mismatches as unsupported capacity without losing the selected plan", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      providerId: "ovh",
      planName: "VPS-4",
      ubuntuVersion: "26.04",
      region: "us-east",
      targetAgents: 25,
      workloadId: "heavy",
    });

    expect(packet.stage).toBe("blocked");
    expect(packet.size.sourcePlan?.name).toBe("VPS-4");
    expect(packet.compatibility.selectedPlanStatus).toBe("fail");
    expect(packet.compatibility.readinessStatus).toBe("unsupported");
    expect(
      packet.compatibility.readinessChecks.find((check) => check.id === "capacity")?.status,
    ).toBe("unsupported");
  });

  test("keeps unknown providers advisory and support-safe", () => {
    const publicKeyMaterial = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixturePublicKey acfs";
    const publicKeyFingerprint = "SHA256:0123456789ABCDEFGHIJKLMNOPQRSTUVWXYabcdefghi";
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      providerId: "Linode",
      planName: "Shared 32 GB",
      region: "newark",
      sshPublicKeyFingerprint: publicKeyFingerprint,
      sshPublicKeyMaterial: publicKeyMaterial,
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
    expect(packet.access.sshPublicKeyFingerprint).toBe(publicKeyFingerprint);
    expect(packet.access.sshPublicKeyMaterial).toBe(publicKeyMaterial);
    expect(json).not.toContain("203.0.113.42");
    expect(json).not.toContain("PRIVATE");
  });

  test("normalizes common Ubuntu labels without changing the selected version", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      providerId: "contabo",
      ubuntuVersion: "Ubuntu 24.04 LTS",
    });

    expect(packet.osImage.version).toBe("24.04");
    expect(packet.osImage.readinessStatus).toBe("borderline");
    expect(packet.stage).toBe("draft");
    expect(packet.install.command).not.toContain("curl");
  });

  test("sanitizes free-form provider metadata before support-safe serialization", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      providerId: "Linode\napi_token=sbp_1234567890123456",
      planName: "sbp_1234567890123456",
      ubuntuVersion: "24.04 bearer abcdef",
      region: "newark 203.0.113.42",
      sshPublicKeyFingerprint: "SHA256:fixture",
    });
    const json = serializeProviderProvisioningPacketJson(packet);

    expect(packet.provider.id).toBe("other");
    expect(packet.provider.name).toBe("Other provider");
    expect(packet.size.planName).toBe("custom plan");
    expect(packet.osImage.version).toBe("unknown");
    expect(packet.osImage.readinessStatus).toBe("unknown");
    expect(packet.region.id).toBe("not-listed");
    expect(json).not.toContain("sbp_1234567890123456");
    expect(json).not.toContain("bearer abcdef");
    expect(json).not.toContain("203.0.113.42");
  });

  test("redacts embedded IPv6 literals and rejects non-canonical provenance timestamps", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      providerId: "host=[2001:db8::7]",
      region: "edge 2001:db8::8",
      generatedAt: "203.0.113.42 bearer secret",
    });
    const json = serializeProviderProvisioningPacketJson(packet);

    expect(packet.provider.id).toBe("other");
    expect(packet.region.id).toBe("not-listed");
    expect(packet.provenance.generatedAt).toBe(
      new Date(packet.provenance.generatedAt).toISOString(),
    );
    expect(json).not.toContain("2001:db8::7");
    expect(json).not.toContain("2001:db8::8");
    expect(json).not.toContain("203.0.113.42");
    expect(json).not.toContain("bearer secret");
  });

  test("omits unsafe SSH public key fields from support-safe packets", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      sshPublicKeyLabel: "password=hunter2",
      sshPublicKeyFingerprint: "SHA256:AKIAABCDEFGHIJKLMNOP",
      sshPublicKeyMaterial: "ssh-ed25519 AKIAABCDEFGHIJKLMNOP acfs",
    });
    const json = serializeProviderProvisioningPacketJson(packet);

    expect(packet.access.sshPublicKeyLabel).toBe("acfs_ed25519.pub");
    expect(packet.access.sshPublicKeyFingerprint).toBeUndefined();
    expect(packet.access.sshPublicKeyMaterial).toBeUndefined();
    expect(packet.access.sshPrivateKeyIncluded).toBe(false);
    expect(json).not.toContain("hunter2");
    expect(json).not.toContain("AKIAABCDEFGHIJKLMNOP");
  });

  test("omits private-key material pasted into the public-key field", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      sshPublicKeyMaterial:
        "-----BEGIN OPENSSH PRIVATE KEY-----\nsecret\n-----END OPENSSH PRIVATE KEY-----",
    });
    const json = serializeProviderProvisioningPacketJson(packet);

    expect(packet.access.sshPublicKeyMaterial).toBeUndefined();
    expect(packet.access.sshPrivateKeyIncluded).toBe(false);
    expect(json).not.toContain("BEGIN OPENSSH PRIVATE KEY");
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
    expect(packet.install.command).toContain('--profile "cloud-only"');
    expect(packet.install.command).not.toContain('--only "cloud.wrangler"');
    expect(packet.install.command).not.toContain('--only "cloud.supabase"');
    expect(packet.install.command).not.toContain('--only "cloud.vercel"');
  });

  test("stores only known module selection fields in support-safe packets", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      moduleSelection: {
        profile: "cloud-only",
        secretToken: "AKIAABCDEFGHIJKLMNOP",
        skipModules: ["tools.vault"],
      } as unknown as ProviderProvisioningPacketInput["moduleSelection"],
    });
    const json = serializeProviderProvisioningPacketJson(packet);

    expect(packet.install.moduleSelection).toEqual({
      profile: "cloud-only",
      skipModules: ["tools.vault"],
    });
    expect(packet.install.command).toContain('--skip "tools.vault"');
    expect(json).not.toContain("secretToken");
    expect(json).not.toContain("AKIAABCDEFGHIJKLMNOP");
  });

  for (const [name, moduleSelection] of [
    ["null selection", null],
    ["scalar selection", "agents.codex"],
    ["array selection", ["agents.codex"]],
    ["scalar onlyModules", { onlyModules: "agents.codex" }],
    ["empty module ID", { onlyModules: [""] }],
    ["partially valid modules", { onlyModules: ["agents.codex", 42] }],
    ["null phases", { onlyPhases: null }],
    ["scalar phase", { onlyPhases: "agents" }],
    ["numeric phase", { onlyPhases: [7] }],
    ["scalar skipModules", { skipModules: "tools.vault" }],
    ["partially valid skips", { skipModules: ["tools.vault", null] }],
    ["scalar skipTags", { skipTags: "cloud" }],
    ["scalar skipCategories", { skipCategories: "cloud" }],
    ["null profile", { profile: null }],
    ["blank profile", { profile: "" }],
    ["nonboolean noDeps", { onlyModules: ["agents.codex"], noDeps: "true" }],
    ["null noDeps", { noDeps: null }],
    ["unknown module", { onlyModules: ["agents.missing"] }],
    ["conflicting skips", { onlyModules: ["agents.codex"], skipModules: ["lang.bun"] }],
    ["sparse modules", { onlyModules: Array(2) }],
    ["oversized modules", { onlyModules: Array(1025).fill("agents.codex") }],
    ["inherited selection", Object.create({ onlyModules: ["agents.codex"] })],
  ] as const) {
    test(`refuses ${name} instead of emitting a different installation scope`, () => {
      expect(resolveModuleSelection(moduleSelection as ModuleSelectionInput).ok).toBe(false);
      expect(() => buildProviderProvisioningPacket({
        ...baseInput,
        moduleSelection: moduleSelection as ModuleSelectionInput,
      })).toThrow("invalid module selection");
    });
  }

  test("rejects malformed scope even when provider readiness already blocks installation", () => {
    expect(() => buildProviderProvisioningPacket({
      ...baseInput,
      ubuntuVersion: "20.04",
      moduleSelection: { onlyModules: "agents.codex" } as unknown as ModuleSelectionInput,
    })).toThrow("invalid module selection");
  });

  test("does not evaluate selection accessors or echo secret selector values on rejection", () => {
    let calls = 0;
    const moduleSelection = Object.defineProperty({}, "onlyModules", {
      enumerable: true,
      get() {
        calls++;
        return ["agents.codex"];
      },
    });
    expect(() => buildProviderProvisioningPacket({ ...baseInput, moduleSelection })).toThrow(
      "invalid module selection",
    );
    expect(calls).toBe(0);

    try {
      buildProviderProvisioningPacket({
        ...baseInput,
        moduleSelection: { onlyModules: ["AKIAABCDEFGHIJKLMNOP"] },
      });
      throw new Error("malformed selection was accepted");
    } catch (error) {
      expect(String(error)).toContain("invalid module selection");
      expect(String(error)).not.toContain("AKIAABCDEFGHIJKLMNOP");
    }
  });

  const validSelections: ModuleSelectionInput[] = [
    {},
    { onlyModules: [], onlyPhases: [], skipModules: [], noDeps: false },
    { profile: "full" },
    { onlyModules: ["agents.codex"] },
    { profile: "agents-only", skipModules: ["agents.gemini"] },
    { onlyModules: ["acfs.doctor"], onlyPhases: ["agents"], skipModules: ["agents.gemini"] },
    { skipTags: ["cloud"], skipCategories: ["network"] },
    { onlyModules: ["agents.codex"], skipModules: ["lang.bun"], noDeps: true },
  ];
  for (const [index, moduleSelection] of validSelections.entries()) {
    test(`preserves valid selection ${index + 1} in the packet and executable command`, () => {
      const before = structuredClone(moduleSelection);
      const packet = buildProviderProvisioningPacket({ ...baseInput, moduleSelection });
      expect(packet.install.command).toBe(buildInstallCommand("vibe", null, "ubuntu", before));
      expect(resolveModuleSelection(packet.install.moduleSelection).included).toEqual(
        resolveModuleSelection(before).included,
      );
      expect(moduleSelection).toEqual(before);
      if (moduleSelection.onlyModules?.length) {
        moduleSelection.onlyModules.push("lang.go");
        expect(packet.install.moduleSelection?.onlyModules).toEqual(before.onlyModules);
        moduleSelection.onlyModules.pop();
      }
    });
  }

  for (const ubuntuVersion of [
    "",
    "Debian 26.04",
    "26.04 trailing text",
    "99.99",
    "28.04",
    "password=secret",
  ]) {
    test(`does not turn an invalid image into a ready packet: ${JSON.stringify(ubuntuVersion)}`, () => {
      const packet = buildProviderProvisioningPacket({ ...baseInput, ubuntuVersion });
      expect(packet.osImage.version).toBe("unknown");
      expect(packet.osImage.readinessStatus).toBe("unknown");
      expect(packet.stage).toBe("draft");
      expect(packet.install.command).toContain("ACFS install blocked");
      expect(packet.install.command).not.toContain("curl");
      expect(packet.verificationCommands[1]?.command).toBe(packet.install.command);
      expect(packet.verificationCommands[1]?.expectedStatus).toBe("fail");
    });
  }

  for (const providerId of ["contabo", "hetzner", "other"]) {
    for (const ubuntuVersion of ["24.10", "25.04", "25.10"]) {
      test(`withholds installer and cloud-init handoffs for ${providerId} on ${ubuntuVersion}`, () => {
        const packet = buildProviderProvisioningPacket({ ...baseInput, providerId, ubuntuVersion });
        expect(packet.stage).toBe("blocked");
        expect(packet.osImage.version).toBe(ubuntuVersion);
        expect(packet.osImage.readinessStatus).toBe("unsupported");
        expect(packet.install.command).toContain("ACFS install blocked");
        expect(packet.install.command).not.toContain("curl");
        expect(packet.cloudInit.mode).toBe("none");
        expect(packet.cloudInit.userDataIncluded).toBe(false);
        expect(packet.cloudInit.templateRef).toBeUndefined();
        expect(packet.verificationCommands[1]?.expectedStatus).toBe("fail");
      });
    }
  }

  test("normalizes supported point releases and uses the current recommendation for unknown providers", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      providerId: "other",
      ubuntuVersion: "Ubuntu 26.04.1 LTS",
    });
    expect(packet.osImage.version).toBe("26.04");
    expect(packet.osImage.readinessStatus).toBe("supported");
    expect(packet.osImage.preferredVersions).toEqual(["26.04"]);
    expect(packet.stage).toBe("draft");
    expect(packet.install.command).toContain("--mode vibe");
  });

  test("does not export an executable installer for an undersized plan on a supported image", () => {
    const packet = buildProviderProvisioningPacket({
      ...baseInput,
      targetAgents: 100,
      workloadId: "heavy",
    });
    expect(packet.osImage.readinessStatus).toBe("supported");
    expect(packet.stage).toBe("blocked");
    expect(packet.install.command).not.toContain("curl");
    expect(packet.install.command).toContain("ACFS install blocked");
    expect(packet.verificationCommands[1]?.expectedStatus).toBe("fail");
  });
});
