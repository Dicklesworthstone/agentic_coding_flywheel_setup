import type { ModuleSelectionInput } from "./moduleSelection";
import { normalizeGitRef, normalizeSSHUsername, type InstallMode } from "./userPreferences";
import { buildInstallCommand } from "./commandBuilder";
import {
  calculateRequiredSpecs,
  evaluatePlan,
  getWorkloadProfile,
  validateVPSReadiness,
  VPS_PROVIDERS,
  PRICING_LAST_UPDATED,
} from "./vpsProviders";
import type {
  EvaluatedProviderPlan,
  PlanStatus,
  RequiredSpecs,
  VPSPlan,
  VPSReadinessCheck,
  VPSReadinessInput,
  VPSReadinessStatus,
  WorkloadId,
} from "./vpsProviders";

export const PROVIDER_PROVISIONING_PACKET_SCHEMA = "acfs.provider-provisioning-packet.v1";
export const PROVIDER_PROVISIONING_PACKET_SCHEMA_VERSION = 1;

export type ProviderProvisioningPacketStage =
  | "draft"
  | "ready_for_manual_provider_checkout"
  | "ready_for_api_provisioning"
  | "provider_server_created"
  | "installer_ready"
  | "verified"
  | "blocked";

export type ProviderProvisioningPacketActor =
  | "acfs-web-wizard"
  | "acfs-installer"
  | "provider-adapter"
  | "operator";

export interface ProviderProvisioningPacketPrivacy {
  supportBundleSafe: true;
  rawProviderCredentialsIncluded: false;
  rawTargetHostIncluded: false;
  rawPrivateKeyIncluded: false;
  rawPrivateKeyPathIncluded: false;
  rawCloudInitIncludedInSupportBundle: false;
  exactInstallCommandIncluded: true;
  targetUsernameMayAppear: true;
  publicSshKeyMaterialMayAppear: true;
  redactedFieldPaths: string[];
  forbiddenFieldNames: string[];
}

export interface ProviderProvisioningPacketProvenance {
  generatedBy: ProviderProvisioningPacketActor;
  generatedAt: string;
  sourceRef: string;
  wizardStep: "rent-vps" | "run-installer" | "provider-adapter";
  readinessSource: "validateVPSReadiness";
  capacitySource: "calculateRequiredSpecs/evaluatePlan";
  pricingLastUpdated: string;
}

export interface ProviderProvisioningPacketProvider {
  id: string;
  name: string;
  productUrl: string;
  automationLevel: "manual" | "cloud_init_only" | "api_supported";
  manualCheckoutRequired: boolean;
  manualStepsRemaining: string[];
}

export interface ProviderProvisioningPacketRegion {
  id: string;
  label: string;
  readinessStatus: Extract<VPSReadinessStatus, "supported" | "borderline" | "unknown">;
  providerSpecificCode?: string;
}

export interface ProviderProvisioningPacketSize {
  planName: string;
  ramGB: number;
  vCPU: number;
  storageGB: number;
  priceUSD?: number;
  sourcePlan: VPSPlan | null;
}

export interface ProviderProvisioningPacketOsImage {
  distribution: "ubuntu";
  version: string;
  minimumVersion: string;
  preferredVersions: string[];
  readinessStatus: VPSReadinessStatus;
  providerImageId?: string;
}

export interface ProviderProvisioningPacketAccess {
  username: string;
  rootLoginExpected: boolean;
  sshPublicKeyLabel: string;
  sshPublicKeyFingerprint?: string;
  sshPublicKeyMaterial?: string;
  sshPrivateKeyIncluded: false;
  sshPrivateKeyPathIncluded: false;
}

export interface ProviderProvisioningPacketCloudInit {
  mode: "none" | "manual_paste" | "provider_user_data" | "api_user_data";
  userDataIncluded: boolean;
  userDataSha256?: string;
  templateRef?: string;
  redactedPreview?: string;
  notes: string[];
}

export interface ProviderProvisioningPacketInstall {
  mode: InstallMode;
  sourceRef: string;
  command: string;
  commandRunLocation: "vps-root-shell" | "cloud-init" | "provider-api";
  moduleSelection?: ModuleSelectionInput;
}

export interface ProviderProvisioningPacketVerificationCommand {
  id: string;
  label: string;
  command: string;
  runLocation: "local" | "vps";
  expectedStatus: "pass" | "warn" | "fail";
  supportBundleSafe: boolean;
}

export interface ProviderProvisioningPacketExpectedArtifact {
  id: string;
  pathPattern: string;
  producedBy: "provider" | "installer" | "operator";
  supportBundleSafe: boolean;
  redactionRequired: boolean;
}

export interface ProviderProvisioningPacketCompatibility {
  workloadId: WorkloadId;
  targetAgents: number;
  requiredSpecs: RequiredSpecs;
  selectedPlanStatus: PlanStatus | "unknown";
  selectedPlanSafeAgents: number | null;
  selectedPlanRecommendedAgents: number | null;
  readinessStatus: VPSReadinessStatus;
  readinessChecks: VPSReadinessCheck[];
}

export interface ProviderProvisioningPacket {
  schema: typeof PROVIDER_PROVISIONING_PACKET_SCHEMA;
  schemaVersion: typeof PROVIDER_PROVISIONING_PACKET_SCHEMA_VERSION;
  stage: ProviderProvisioningPacketStage;
  privacy: ProviderProvisioningPacketPrivacy;
  provenance: ProviderProvisioningPacketProvenance;
  provider: ProviderProvisioningPacketProvider;
  region: ProviderProvisioningPacketRegion;
  size: ProviderProvisioningPacketSize;
  osImage: ProviderProvisioningPacketOsImage;
  access: ProviderProvisioningPacketAccess;
  cloudInit: ProviderProvisioningPacketCloudInit;
  install: ProviderProvisioningPacketInstall;
  compatibility: ProviderProvisioningPacketCompatibility;
  verificationCommands: ProviderProvisioningPacketVerificationCommand[];
  expectedArtifacts: ProviderProvisioningPacketExpectedArtifact[];
}

export interface ProviderProvisioningPacketInput extends VPSReadinessInput {
  installMode: InstallMode;
  sourceRef: string | null;
  username: string;
  moduleSelection?: ModuleSelectionInput;
  targetHost?: string;
  sshPublicKeyLabel?: string;
  sshPublicKeyFingerprint?: string;
  sshPublicKeyMaterial?: string;
  generatedAt?: string;
}

interface ProviderPacketPreset {
  id: string;
  name: string;
  productUrl: string;
  automationLevel: ProviderProvisioningPacketProvider["automationLevel"];
  cloudInitMode: ProviderProvisioningPacketCloudInit["mode"];
  cloudInitTemplateRef?: string;
}

export const PROVIDER_PACKET_REQUIRED_FIELD_PATHS = [
  "schema",
  "schemaVersion",
  "stage",
  "privacy.redactedFieldPaths",
  "privacy.forbiddenFieldNames",
  "provenance.generatedBy",
  "provenance.generatedAt",
  "provenance.sourceRef",
  "provider.id",
  "provider.name",
  "provider.automationLevel",
  "provider.manualStepsRemaining",
  "region.id",
  "region.readinessStatus",
  "size.planName",
  "size.ramGB",
  "size.vCPU",
  "size.storageGB",
  "osImage.distribution",
  "osImage.version",
  "access.username",
  "access.sshPublicKeyLabel",
  "access.sshPrivateKeyIncluded",
  "access.sshPrivateKeyPathIncluded",
  "cloudInit.mode",
  "cloudInit.userDataIncluded",
  "install.mode",
  "install.sourceRef",
  "install.command",
  "compatibility.workloadId",
  "compatibility.targetAgents",
  "compatibility.requiredSpecs",
  "compatibility.readinessStatus",
  "verificationCommands",
  "expectedArtifacts",
] as const;

export const PROVIDER_PACKET_FORBIDDEN_FIELD_NAMES = [
  "api_key",
  "apiToken",
  "authorization",
  "credential",
  "dashboardCookie",
  "home",
  "hostname",
  "ip",
  "password",
  "privateKey",
  "private_key",
  "provider_api_key",
  "secret",
  "sshKeyPath",
  "sshPrivateKey",
  "token",
] as const;

export const PROVIDER_PACKET_REDACTED_FIELD_PATHS = [
  "targetHost.address",
  "provider.accountId",
  "provider.orderId",
  "provider.projectId",
  "provider.dashboardSession",
  "access.sshPrivateKey",
  "access.sshPrivateKeyPath",
  "access.providerToken",
  "cloudInit.rawUserData",
  "cloudInit.rawRenderedTemplate",
  "install.environment",
  "provenance.operatorLocalPath",
] as const;

export const PROVIDER_PACKET_SUPPORT_BUNDLE_SAFE_PATHS = [
  "schema",
  "schemaVersion",
  "stage",
  "provenance.generatedBy",
  "provenance.sourceRef",
  "provenance.readinessSource",
  "provenance.capacitySource",
  "provider.id",
  "provider.name",
  "provider.automationLevel",
  "region.id",
  "region.readinessStatus",
  "size.planName",
  "size.ramGB",
  "size.vCPU",
  "size.storageGB",
  "osImage.distribution",
  "osImage.version",
  "access.username",
  "access.sshPublicKeyLabel",
  "access.sshPublicKeyFingerprint",
  "cloudInit.mode",
  "cloudInit.userDataSha256",
  "install.mode",
  "install.sourceRef",
  "compatibility.workloadId",
  "compatibility.targetAgents",
  "compatibility.selectedPlanStatus",
  "compatibility.readinessStatus",
  "verificationCommands[].id",
  "expectedArtifacts[].id",
  "expectedArtifacts[].pathPattern",
] as const;

export const PROVIDER_PACKET_EXPECTED_ARTIFACTS = [
  {
    id: "provider-order-confirmation",
    pathPattern: "provider-console://orders/<redacted-order-id>",
    producedBy: "provider",
    supportBundleSafe: false,
    redactionRequired: true,
  },
  {
    id: "installer-log",
    pathPattern: "~/.acfs/logs/install-*.log",
    producedBy: "installer",
    supportBundleSafe: true,
    redactionRequired: true,
  },
  {
    id: "support-report",
    pathPattern: "~/.acfs/support/<timestamp>/support-report.md",
    producedBy: "installer",
    supportBundleSafe: true,
    redactionRequired: true,
  },
  {
    id: "support-manifest",
    pathPattern: "~/.acfs/support/<timestamp>/manifest.json",
    producedBy: "installer",
    supportBundleSafe: true,
    redactionRequired: true,
  },
] as const satisfies readonly ProviderProvisioningPacketExpectedArtifact[];

export const PROVIDER_PACKET_BASE_VERIFICATION_COMMANDS = [
  {
    id: "ssh-root",
    label: "Root SSH reaches the new VPS",
    command: "ssh root@YOUR_VPS_IP",
    runLocation: "local",
    expectedStatus: "pass",
    supportBundleSafe: false,
  },
  {
    id: "installer",
    label: "ACFS installer exits successfully",
    command: "ACFS_INSTALL_COMMAND_FROM_PACKET",
    runLocation: "vps",
    expectedStatus: "pass",
    supportBundleSafe: true,
  },
  {
    id: "doctor",
    label: "ACFS doctor passes or reports only documented warnings",
    command: "acfs doctor",
    runLocation: "vps",
    expectedStatus: "pass",
    supportBundleSafe: true,
  },
  {
    id: "support-bundle",
    label: "Redacted support bundle can be produced",
    command: "acfs support-bundle",
    runLocation: "vps",
    expectedStatus: "pass",
    supportBundleSafe: true,
  },
] as const satisfies readonly ProviderProvisioningPacketVerificationCommand[];

export const PROVIDER_PACKET_MANUAL_STEPS_BY_PROVIDER: Record<string, string[]> = {
  contabo: [
    "Log in to the provider console and choose the ACFS-recommended VPS product.",
    "Select the desired region and Ubuntu image from the provider UI.",
    "Use the provider password flow, keep root as the initial login user, and save the temporary VPS root password.",
    "Complete checkout and payment manually.",
    "Copy the assigned host address into the wizard; do not store it in a support-safe packet projection.",
  ],
  ovh: [
    "Log in to the provider console and choose the ACFS-recommended VPS product.",
    "Select the desired region and Ubuntu image from the provider UI.",
    "Choose password authentication, skip the provider SSH key section for now, and save the temporary VPS root password.",
    "Complete checkout and payment manually.",
    "Copy the assigned host address into the wizard; do not store it in a support-safe packet projection.",
  ],
  hetzner: [
    "Create or choose a Hetzner Cloud project manually.",
    "Select an Ubuntu image and a server type that meets the packet capacity warning.",
    "Attach the public SSH key in the provider console.",
    "Paste the ACFS cloud-init template when using cloud-init mode.",
    "Complete checkout and payment manually.",
    "Copy the assigned host address into the wizard; do not store it in a support-safe packet projection.",
  ],
  other: [
    "Verify the provider offers SSH access, Ubuntu 24.04 or newer, and enough RAM, CPU, and NVMe storage.",
    "Complete account, checkout, and payment steps manually.",
    "Record the assigned host address outside the support-safe packet projection.",
  ],
};

export function manualStepsForProvider(providerId: string): string[] {
  return PROVIDER_PACKET_MANUAL_STEPS_BY_PROVIDER[providerId] ?? PROVIDER_PACKET_MANUAL_STEPS_BY_PROVIDER.other;
}

const PROVIDER_PACKET_PRESETS: Record<string, ProviderPacketPreset> = {
  hetzner: {
    id: "hetzner",
    name: "Hetzner",
    productUrl: "https://www.hetzner.com/cloud/",
    automationLevel: "cloud_init_only",
    cloudInitMode: "manual_paste",
    cloudInitTemplateRef: "scripts/providers/hetzner-cloud-init.yml",
  },
};

function collapsePacketText(value: string): string {
  return value.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim();
}

function looksSensitivePacketText(value: string): boolean {
  if (/-----begin [a-z ]*private key-----/i.test(value)) return true;
  if (/^[a-z][a-z0-9+.-]*:\/\/[^/\s:@]+:[^@\s]+@/i.test(value)) return true;
  if (/\bbearer\s+\S+/i.test(value)) return true;
  if (/(?:token|api[_-]?key|secret|password|private[_-]?key|cookie|session|credential|client[_-]?secret|webhook[_-]?secret|vault[_-]?token)/i.test(value)) {
    return true;
  }
  if (/(?:^|[^0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:[^0-9]|$)/.test(value)) {
    return true;
  }

  const compact = value.replace(/[^A-Za-z0-9]/g, "");
  return compact.length >= 40 && /[A-Za-z]/.test(compact) && /[0-9]/.test(compact);
}

function safePacketText(value: string | null | undefined, fallback: string, maxLength = 80): string {
  const collapsed = collapsePacketText(value ?? "");
  if (!collapsed || looksSensitivePacketText(collapsed)) return fallback;
  return collapsed.slice(0, maxLength);
}

function safePacketSlug(value: string | null | undefined, fallback: string): string {
  const slug = safePacketText(value, fallback, 80)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^[._-]+|[._-]+$/g, "")
    .slice(0, 64);
  return slug || fallback;
}

function safePacketUbuntuVersion(value: string | null | undefined): string {
  const safe = safePacketText(value, "25.10", 16);
  return /^[0-9]{2}\.[0-9]{2}$/.test(safe) ? safe : "25.10";
}

function readinessCheckStatus(
  checks: VPSReadinessCheck[],
  id: VPSReadinessCheck["id"],
): VPSReadinessStatus {
  return checks.find((check) => check.id === id)?.status ?? "unknown";
}

function providerPresetFor(providerId: string): ProviderPacketPreset {
  const normalizedProviderId = safePacketSlug(providerId, "other");
  const provider = VPS_PROVIDERS.find((entry) => entry.id === normalizedProviderId);
  if (provider) {
    return {
      id: provider.id,
      name: provider.name,
      productUrl: provider.url,
      automationLevel: "manual",
      cloudInitMode: "none",
    };
  }

  return PROVIDER_PACKET_PRESETS[normalizedProviderId] ?? {
    id: normalizedProviderId || "other",
    name: normalizedProviderId === "other" || !normalizedProviderId
      ? "Other provider"
      : safePacketText(providerId, "Other provider"),
    productUrl: "",
    automationLevel: "manual",
    cloudInitMode: "none",
  };
}

function stageForPacket(
  readinessStatus: VPSReadinessStatus,
  automationLevel: ProviderProvisioningPacketProvider["automationLevel"],
): ProviderProvisioningPacketStage {
  if (readinessStatus === "unsupported") return "blocked";
  if (readinessStatus === "unknown") return "draft";
  if (automationLevel === "api_supported") return "ready_for_api_provisioning";
  return "ready_for_manual_provider_checkout";
}

function evaluatedSelectedPlan(
  plan: VPSPlan | null,
  workloadId: WorkloadId,
  targetAgents: number,
): Pick<EvaluatedProviderPlan, "recommendedAgents" | "safeAgents" | "status"> | null {
  if (!plan) return null;
  return evaluatePlan(plan, getWorkloadProfile(workloadId), targetAgents);
}

function buildVerificationCommands(
  installCommand: string,
): ProviderProvisioningPacketVerificationCommand[] {
  return PROVIDER_PACKET_BASE_VERIFICATION_COMMANDS.map((command) => ({
    ...command,
    command: command.id === "installer" ? installCommand : command.command,
  }));
}

function buildCloudInit(
  preset: ProviderPacketPreset,
): ProviderProvisioningPacketCloudInit {
  const userDataIncluded = preset.cloudInitMode !== "none";
  return {
    mode: preset.cloudInitMode,
    userDataIncluded,
    templateRef: preset.cloudInitTemplateRef,
    redactedPreview: userDataIncluded
      ? "ACFS cloud-init user-data available as a template reference; raw rendered user-data is excluded from support-safe packets."
      : undefined,
    notes: userDataIncluded
      ? ["Paste or submit only after reviewing the generated user-data in the provider console."]
      : ["Run the exact installer command manually from the VPS root SSH session."],
  };
}

export function buildProviderProvisioningPacket(
  input: ProviderProvisioningPacketInput,
): ProviderProvisioningPacket {
  const rawProviderId = safePacketText(input.providerId, "other");
  const providerId = safePacketSlug(rawProviderId, "other");
  const planName = safePacketText(input.planName, "custom plan");
  const ubuntuVersion = safePacketUbuntuVersion(input.ubuntuVersion);
  const regionId = safePacketSlug(input.region, "not-listed");
  const regionLabel = safePacketText(input.region, "Not listed");
  const preset = providerPresetFor(rawProviderId || providerId);
  const requestedAgents = Number.isFinite(input.targetAgents) ? input.targetAgents : 10;
  const targetAgents = Math.max(1, Math.floor(requestedAgents));
  const targetUsername = normalizeSSHUsername(input.username) ?? "ubuntu";
  const readiness = validateVPSReadiness({
    providerId,
    planName,
    ubuntuVersion,
    region: regionId,
    targetAgents,
    workloadId: input.workloadId,
  });
  const workload = getWorkloadProfile(input.workloadId);
  const requiredSpecs = calculateRequiredSpecs(targetAgents, workload, true);
  const selectedPlan = evaluatedSelectedPlan(readiness.plan, input.workloadId, targetAgents);
  const sourceRef = normalizeGitRef(input.sourceRef) ?? "main";
  const installCommand = buildInstallCommand(
    input.installMode,
    sourceRef === "main" ? null : sourceRef,
    targetUsername,
    input.moduleSelection,
  );
  const regionReadiness = readinessCheckStatus(readiness.checks, "region");
  const osReadiness = readinessCheckStatus(readiness.checks, "os");

  return {
    schema: PROVIDER_PROVISIONING_PACKET_SCHEMA,
    schemaVersion: PROVIDER_PROVISIONING_PACKET_SCHEMA_VERSION,
    stage: stageForPacket(readiness.status, preset.automationLevel),
    privacy: {
      supportBundleSafe: true,
      rawProviderCredentialsIncluded: false,
      rawTargetHostIncluded: false,
      rawPrivateKeyIncluded: false,
      rawPrivateKeyPathIncluded: false,
      rawCloudInitIncludedInSupportBundle: false,
      exactInstallCommandIncluded: true,
      targetUsernameMayAppear: true,
      publicSshKeyMaterialMayAppear: true,
      redactedFieldPaths: [...PROVIDER_PACKET_REDACTED_FIELD_PATHS],
      forbiddenFieldNames: [...PROVIDER_PACKET_FORBIDDEN_FIELD_NAMES],
    },
    provenance: {
      generatedBy: "acfs-web-wizard",
      generatedAt: input.generatedAt ?? new Date().toISOString(),
      sourceRef,
      wizardStep: "run-installer",
      readinessSource: "validateVPSReadiness",
      capacitySource: "calculateRequiredSpecs/evaluatePlan",
      pricingLastUpdated: PRICING_LAST_UPDATED,
    },
    provider: {
      id: preset.id,
      name: preset.name,
      productUrl: preset.productUrl,
      automationLevel: preset.automationLevel,
      manualCheckoutRequired: true,
      manualStepsRemaining: manualStepsForProvider(preset.id),
    },
    region: {
      id: regionId,
      label: regionLabel,
      readinessStatus: regionReadiness === "unsupported" ? "unknown" : regionReadiness,
      providerSpecificCode: regionId === "not-listed" ? undefined : regionId,
    },
    size: {
      planName,
      ramGB: readiness.plan?.ramGB ?? requiredSpecs.ramGB,
      vCPU: readiness.plan?.vCPU ?? requiredSpecs.vCPU,
      storageGB: readiness.plan?.storageGB ?? requiredSpecs.storageGB,
      priceUSD: readiness.plan?.priceUSD,
      sourcePlan: readiness.plan,
    },
    osImage: {
      distribution: "ubuntu",
      version: ubuntuVersion,
      minimumVersion: readiness.provider?.readiness.minimumUbuntu ?? "22.04",
      preferredVersions: readiness.provider?.readiness.preferredUbuntuVersions ?? ["25.10", "24.04"],
      readinessStatus: osReadiness,
    },
    access: {
      username: targetUsername,
      rootLoginExpected: true,
      sshPublicKeyLabel: input.sshPublicKeyLabel ?? "acfs_ed25519.pub",
      sshPublicKeyFingerprint: input.sshPublicKeyFingerprint,
      sshPublicKeyMaterial: input.sshPublicKeyMaterial,
      sshPrivateKeyIncluded: false,
      sshPrivateKeyPathIncluded: false,
    },
    cloudInit: buildCloudInit(preset),
    install: {
      mode: input.installMode,
      sourceRef,
      command: installCommand,
      commandRunLocation: preset.cloudInitMode === "none" ? "vps-root-shell" : "cloud-init",
      moduleSelection: input.moduleSelection,
    },
    compatibility: {
      workloadId: input.workloadId,
      targetAgents,
      requiredSpecs,
      selectedPlanStatus: selectedPlan?.status ?? "unknown",
      selectedPlanSafeAgents: selectedPlan?.safeAgents ?? null,
      selectedPlanRecommendedAgents: selectedPlan?.recommendedAgents ?? null,
      readinessStatus: readiness.status,
      readinessChecks: readiness.checks,
    },
    verificationCommands: buildVerificationCommands(installCommand),
    expectedArtifacts: [...PROVIDER_PACKET_EXPECTED_ARTIFACTS],
  };
}

export function serializeProviderProvisioningPacketJson(
  packet: ProviderProvisioningPacket,
): string {
  return `${JSON.stringify(packet, null, 2)}\n`;
}
