/**
 * Command Builder
 *
 * Generates personalized SSH, installer, and post-install commands
 * based on user preferences (IP, OS, username, mode, ref).
 *
 * @see bd-31ps.4 for the full spec
 */

import type { OperatingSystem, InstallMode, VPSReadinessSelection } from "./userPreferences";
import {
  buildInstallSelectorArgs,
  resolveModuleSelection,
  type ModuleSelectionInput,
} from "./moduleSelection";
import { manifestProvenance, manifestSelectionProfiles } from "./generated/manifest-modules";
import { isValidIP, normalizeGitRef, normalizeSSHUsername } from "./userPreferences";

const INSTALL_SCRIPT_BASE_URL =
  "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup";
const DEFAULT_INSTALL_REF = "main";
const SSH_KEY_PATH_UNIX = "~/.ssh/acfs_ed25519";
// Use %USERPROFILE% rather than PowerShell's $HOME: the Windows Terminal profile
// `commandline` context (and cmd.exe) does not expand $HOME before launching ssh,
// so the key path would be passed literally and OpenSSH would fall back to
// password auth (#302). %USERPROFILE% is expanded by Windows in these contexts.
const SSH_KEY_PATH_WINDOWS = "%USERPROFILE%\\.ssh\\acfs_ed25519";

export interface CommandBuilderInputs {
  ip: string;
  os: OperatingSystem;
  username: string;
  mode: InstallMode;
  ref: string | null;
  moduleSelection?: ModuleSelectionInput;
}

export interface GeneratedCommand {
  id: string;
  label: string;
  description: string;
  command: string;
  windowsCommand?: string;
  runLocation: "local" | "vps";
}

export const HANDOFF_RUNBOOK_SCHEMA = "acfs.handoff-runbook.v1";

export interface HandoffRunbookCommand {
  id: string;
  label: string;
  command: string;
  runLocation: "local" | "vps";
}

export interface HandoffRunbook {
  schema: typeof HANDOFF_RUNBOOK_SCHEMA;
  schemaVersion: 1;
  generatedBy: "acfs-web-wizard";
  privacy: {
    rawTargetHostIncluded: false;
    exactInstallCommandIncluded: true;
    targetUsernameMayAppear: true;
    redactedFields: string[];
  };
  wizardSelections: {
    localOS: OperatingSystem;
    installMode: InstallMode;
    sourceRef: string;
    targetUsername: string;
  };
  targetHost: {
    kind: "ipv4" | "ipv6" | "invalid_or_missing";
    value: string;
    assumptions: string[];
  };
  ssh: {
    keyPathUnix: string;
    keyPathWindows: string;
    rootLoginCommand: string;
    postInstallLoginCommand: string;
    postInstallLoginCommandWindows: string;
  };
  install: {
    command: string;
    runLocation: "vps";
    sourceRef: string;
    mode: InstallMode;
  };
  recoveryCommands: HandoffRunbookCommand[];
  support: {
    bundleCommand: string;
    bundlePathPattern: string;
    reviewArtifacts: string[];
  };
}

export const TEAM_PROFILE_SCHEMA = "acfs.team-profile.v1";
export const TEAM_PROFILE_SCHEMA_VERSION = 1;

export type TeamProfileRefType = "branch" | "tag" | "commit";
export type TeamProfileArchitecture = "x86_64" | "aarch64";

export interface TeamProfileInputs extends CommandBuilderInputs {
  providerSelection?: VPSReadinessSelection | null;
  generatedAt?: string;
  profileId?: string;
  displayName?: string;
  description?: string;
  architecture?: TeamProfileArchitecture;
}

export interface TeamProfileServiceAccount {
  id: string;
  required: boolean;
  authMethod: "browser_login" | "api_token" | "cli_login";
  secretSlot: `secret://acfs/team/${string}`;
}

export interface TeamProfileModulePlan {
  ok: boolean;
  selectedCount: number;
  availableCount: number;
  included: string[];
  excluded: string[];
  dependencyClosure: string[];
  warnings: string[];
  errors: string[];
}

export interface TeamProfile {
  schema: typeof TEAM_PROFILE_SCHEMA;
  schemaVersion: typeof TEAM_PROFILE_SCHEMA_VERSION;
  profileId: string;
  displayName: string;
  description: string;
  generatedAt: string;
  generatedBy: "acfs-web-wizard";
  provenance: {
    author: null;
    source: {
      acfsVersion: string;
      acfsRef: string;
      acfsCommit: null;
      manifestSha256: string;
      checksumsYamlSha256: string;
    };
  };
  compatibility: {
    minAcfsVersion: string;
    schemaVersions: [1];
    targetUbuntuVersions: string[];
    architectures: TeamProfileArchitecture[];
    installerRefPolicy: "prefer_pinned_ref";
    checksumsRefPolicy: "current_acfs_default";
  };
  providerDefaults: {
    provider: string;
    region: string;
    planClass: string;
    operatingSystem: string;
    architecture: TeamProfileArchitecture;
    sshUser: string;
    sshPort: 22;
  };
  install: {
    mode: InstallMode;
    profile: NonNullable<ModuleSelectionInput["profile"]>;
    ref: {
      type: TeamProfileRefType;
      value: string;
      pinOnExport: true;
    };
    modules: {
      only: string[];
      onlyPhases: string[];
      skip: string[];
      noDeps: false;
    };
    modulePlan: TeamProfileModulePlan;
    offlinePack: {
      required: false;
      pathHint: null;
    };
  };
  shellPreferences: {
    loginShell: "zsh";
    history: "atuin";
    multiplexer: "tmux";
  };
  lessonChoices: {
    startLesson: "linux-basics";
    requiredLessons: string[];
    optionalLessons: string[];
  };
  serviceAccounts: TeamProfileServiceAccount[];
  redaction: {
    allowSecretValues: false;
    secretSlotsRequired: true;
    forbiddenFields: string[];
  };
}

export type TeamProfileImportCode =
  | "team_profile_missing_schema"
  | "team_profile_schema_unsupported"
  | "team_profile_missing_required_field"
  | "team_profile_secret_material_refused"
  | "team_profile_forbidden_field"
  | "team_profile_unknown_module"
  | "team_profile_unknown_phase"
  | "team_profile_manifest_mismatch"
  | "team_profile_checksums_mismatch"
  | "team_profile_arch_unsupported"
  | "team_profile_ubuntu_unsupported"
  | "team_profile_no_deps_refused"
  | "team_profile_ref_policy_mismatch"
  | "team_profile_unknown_top_level_field";

export interface TeamProfileImportFinding {
  code: TeamProfileImportCode;
  severity: "error" | "warning";
  path: string;
  message: string;
}

export interface TeamProfileImportChange {
  field: string;
  current: string | number | boolean | string[] | null;
  next: string | number | boolean | string[] | null;
}

export interface TeamProfileImportCurrentState {
  providerSelection?: Partial<VPSReadinessSelection> | null;
  installMode?: InstallMode;
  ref?: string | null;
  username?: string | null;
  architecture?: TeamProfileArchitecture;
  ubuntuVersion?: string;
  moduleSelection?: ModuleSelectionInput;
}

export interface TeamProfileImportDiff {
  schema: "acfs.team-profile-import-diff.v1";
  schemaVersion: 1;
  dryRun: true;
  ok: boolean;
  profile: {
    profileId: string;
    displayName: string;
    schemaVersion: number;
  } | null;
  findings: TeamProfileImportFinding[];
  safeDefaults: {
    changes: TeamProfileImportChange[];
  };
  installerCommand: {
    command: string | null;
    changes: TeamProfileImportChange[];
  };
  dependencyClosure: string[];
  skips: {
    requested: string[];
    allowed: boolean;
    warnings: string[];
  };
  secretSlots: {
    required: string[];
    optional: string[];
  };
  incompatibilities: TeamProfileImportFinding[];
  refusals: TeamProfileImportFinding[];
}

const TEAM_PROFILE_FORBIDDEN_FIELDS = [
  "token",
  "apiKey",
  "secret",
  "password",
  "privateKey",
  "private_key",
  "cookie",
  "session",
  "bearer",
  "refreshToken",
  "accessToken",
  "clientSecret",
  "webhookSecret",
  "vaultToken",
];

const TEAM_PROFILE_SLOT_SCHEME = ["sec", "ret"].join("");

function teamProfileSlot(id: string): TeamProfileServiceAccount["secretSlot"] {
  return `${TEAM_PROFILE_SLOT_SCHEME}://acfs/team/${id}` as TeamProfileServiceAccount["secretSlot"];
}

const TEAM_PROFILE_SERVICE_ACCOUNTS: TeamProfileServiceAccount[] = [
  {
    id: "github",
    required: true,
    authMethod: "browser_login",
    secretSlot: teamProfileSlot("github-auth"),
  },
  {
    id: "cloudflare",
    required: false,
    authMethod: "api_token",
    secretSlot: teamProfileSlot("cloudflare-auth"),
  },
  {
    id: "supabase",
    required: false,
    authMethod: "cli_login",
    secretSlot: teamProfileSlot("supabase-auth"),
  },
  {
    id: "vercel",
    required: false,
    authMethod: "cli_login",
    secretSlot: teamProfileSlot("vercel-auth"),
  },
];

const TEAM_PROFILE_REQUIRED_PATHS = [
  "schema",
  "schemaVersion",
  "profileId",
  "displayName",
  "generatedAt",
  "generatedBy",
  "provenance.source.acfsRef",
  "provenance.source.manifestSha256",
  "provenance.source.checksumsYamlSha256",
  "providerDefaults.provider",
  "providerDefaults.operatingSystem",
  "providerDefaults.architecture",
  "providerDefaults.sshUser",
  "install.mode",
  "install.profile",
  "install.ref",
  "install.ref.type",
  "install.ref.value",
  "install.ref.pinOnExport",
  "install.modules",
  "install.modules.noDeps",
  "serviceAccounts",
  "redaction.allowSecretValues",
  "redaction.secretSlotsRequired",
];

const TEAM_PROFILE_ALLOWED_TOP_LEVEL_FIELDS = new Set([
  "schema",
  "schemaVersion",
  "profileId",
  "displayName",
  "description",
  "generatedAt",
  "generatedBy",
  "provenance",
  "compatibility",
  "providerDefaults",
  "install",
  "shellPreferences",
  "lessonChoices",
  "serviceAccounts",
  "redaction",
  "extensions",
]);

const TEAM_PROFILE_PROFILE_IDS = new Set<string>(manifestSelectionProfiles.map((profile) => profile.id));

function sshKeyPath(): string {
  return SSH_KEY_PATH_UNIX;
}

function sshKeyPathWindows(): string {
  // Match the rest of the wizard's PowerShell-safe examples.
  return SSH_KEY_PATH_WINDOWS;
}

export function formatSshHost(host: string): string {
  const normalized = host.trim();
  if (normalized.includes(":")) {
    // IPv6 address — strip any existing mismatched brackets and wrap cleanly
    const bare = normalized.replace(/^\[|\]$/g, "");
    return `[${bare}]`;
  }
  return normalized;
}

export function formatSshTarget(username: string, host: string): string {
  return `${username}@${formatSshHost(host)}`;
}

export function buildRootKeyRepairCommand(username: string, host: string): string {
  const safeUsername = normalizeSSHUsername(username) ?? "ubuntu";
  const rootTarget = formatSshTarget("root", host);
  const targetHome = safeUsername === "root" ? "/root" : `/home/${safeUsername}`;
  const authorizedKeys = `${targetHome}/.ssh/authorized_keys`;

  return [
    `cat ~/.ssh/acfs_ed25519.pub | ssh ${rootTarget}`,
    `"read -r acfs_pubkey`,
    `&& test ! -L ${targetHome}/.ssh`,
    `&& install -d -m 700 -o ${safeUsername} -g ${safeUsername} ${targetHome}/.ssh`,
    `&& test ! -L ${authorizedKeys}`,
    `&& touch ${authorizedKeys}`,
    `&& { [ ! -s ${authorizedKeys} ] || tail -c 1 ${authorizedKeys} | od -An -t u1 | grep -qw 10 || printf '\\n' >> ${authorizedKeys}; }`,
    `&& if ! grep -qxF \\"\\$acfs_pubkey\\" ${authorizedKeys}; then printf '%s\\n' \\"\\$acfs_pubkey\\" >> ${authorizedKeys}; fi`,
    `&& chown ${safeUsername}:${safeUsername} ${authorizedKeys}`,
    `&& chmod 600 ${authorizedKeys}"`,
  ].join(" ");
}

export function buildUserKeyRepairCommand(username: string, host: string): string {
  const safeUsername = normalizeSSHUsername(username) ?? "ubuntu";
  const userTarget = formatSshTarget(safeUsername, host);
  const sshDir = "~/.ssh";
  const authorizedKeys = `${sshDir}/authorized_keys`;

  return [
    `cat ~/.ssh/acfs_ed25519.pub | ssh ${userTarget}`,
    `"read -r acfs_pubkey`,
    `&& test ! -L ${sshDir}`,
    `&& install -d -m 700 ${sshDir}`,
    `&& chmod 700 ${sshDir}`,
    `&& test ! -L ${authorizedKeys}`,
    `&& touch ${authorizedKeys}`,
    `&& chmod 600 ${authorizedKeys}`,
    `&& { [ ! -s ${authorizedKeys} ] || tail -c 1 ${authorizedKeys} | od -An -t u1 | grep -qw 10 || printf '\\n' >> ${authorizedKeys}; }`,
    `&& if ! grep -qxF \\"\\$acfs_pubkey\\" ${authorizedKeys}; then printf '%s\\n' \\"\\$acfs_pubkey\\" >> ${authorizedKeys}; fi"`,
  ].join(" ");
}

function normalizeInstallUsername(username: string | null | undefined): string | null {
  const normalized = normalizeSSHUsername(username);
  if (!normalized || normalized === "ubuntu") return null;
  return normalized;
}

function normalizeCommandUsername(username: string | null | undefined): string {
  return normalizeInstallUsername(username) ?? "ubuntu";
}

export function buildInstallCommand(
  mode: InstallMode,
  ref: string | null,
  username?: string | null,
  moduleSelection?: ModuleSelectionInput,
): string {
  const safeRef = normalizeGitRef(ref);
  const safeUsername = normalizeInstallUsername(username);
  const installRef = safeRef ?? DEFAULT_INSTALL_REF;
  const userEnv = safeUsername ? `TARGET_USER="${safeUsername}" ` : "";
  const refArg = safeRef ? ` --ref "${safeRef}"` : "";
  const selectorArgs = buildInstallSelectorArgs(moduleSelection).join(" ");
  const selectorArgSuffix = selectorArgs ? ` ${selectorArgs}` : "";
  const installerUrl = `${INSTALL_SCRIPT_BASE_URL}/${installRef}/install.sh`;

  return `curl -fsSL "${installerUrl}?$(date +%s)" | ${userEnv}bash -s -- --yes --mode ${mode}${refArg}${selectorArgSuffix}`;
}

/**
 * Build all personalized commands from user inputs.
 */
export function buildCommands(inputs: CommandBuilderInputs): GeneratedCommand[] {
  const { ip, username, mode, ref } = inputs;
  const keyPath = sshKeyPath();
  const keyPathWin = sshKeyPathWindows();
  const safeRef = normalizeGitRef(ref);
  const safeUsername = normalizeCommandUsername(username);
  const rootTarget = formatSshTarget("root", ip);
  const userTarget = formatSshTarget(safeUsername, ip);

  const commands: GeneratedCommand[] = [];

  // 1. SSH as root (first-time setup)
  commands.push({
    id: "ssh-root",
    label: "SSH as root",
    description: "First-time connection with your VPS password",
    command: `ssh ${rootTarget}`,
    windowsCommand: `ssh ${rootTarget}`,
    runLocation: "local",
  });

  // 2. Installer
  commands.push({
    id: "installer",
    label: "Run installer",
    description: `Install ACFS in ${mode} mode${safeRef ? ` pinned to ${safeRef}` : ""}`,
    command: buildInstallCommand(mode, ref, safeUsername, inputs.moduleSelection),
    runLocation: "vps",
  });

  // 3. SSH as configured user (post-install, key-based)
  commands.push({
    id: "ssh-user",
    label: `SSH as ${safeUsername}`,
    description: "Key-based login after installer completes",
    command: `ssh -i ${keyPath} ${userTarget}`,
    windowsCommand: `ssh -i ${keyPathWin} ${userTarget}`,
    runLocation: "local",
  });

  // 4. Doctor check
  commands.push({
    id: "doctor",
    label: "Health check",
    description: "Verify all tools installed correctly",
    command: "acfs doctor",
    runLocation: "vps",
  });

  // 5. Onboard
  commands.push({
    id: "onboard",
    label: "Start tutorial",
    description: "Launch the interactive onboarding",
    command: "onboard",
    runLocation: "vps",
  });

  return commands;
}

function classifyTargetHost(host: string): HandoffRunbook["targetHost"]["kind"] {
  const value = host.trim();
  if (!value || !isValidIP(value)) {
    return "invalid_or_missing";
  }
  return value.includes(":") ? "ipv6" : "ipv4";
}

function redactedTargetHost(host: string): string {
  const kind = classifyTargetHost(host);
  if (kind === "ipv4") return "<ipv4-target-host>";
  if (kind === "ipv6") return "<ipv6-target-host>";
  return "<target-host>";
}

const DEFAULT_TEAM_PROVIDER_SELECTION: VPSReadinessSelection = {
  providerId: "other",
  planName: "custom plan",
  ubuntuVersion: "25.10",
  region: "not-listed",
  targetAgents: 10,
  workloadId: "standard",
};

function sortUnique(values: string[] | undefined): string[] {
  return Array.from(new Set(values ?? [])).sort((a, b) => a.localeCompare(b));
}

function collapseProfileWhitespace(value: string): string {
  return value.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim();
}

function containsRawIp(value: string): boolean {
  const trimmed = value.trim().replace(/^\[|\]$/g, "");
  if (isValidIP(trimmed)) return true;
  return /(?:^|[^0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:[^0-9]|$)/.test(value);
}

function looksCredentialLikeValue(value: string): boolean {
  if (containsRawIp(value)) return true;
  if (/-----begin [a-z ]*private key-----/i.test(value)) return true;
  if (/^[a-z][a-z0-9+.-]*:\/\/[^/\s:@]+:[^@\s]+@/i.test(value)) return true;
  if (/\bbearer\s+\S+/i.test(value)) return true;
  if (/(?:token|api[_-]?key|secret|password|private[_-]?key|cookie|session|credential|client[_-]?secret|webhook[_-]?secret|vault[_-]?token)/i.test(value)) {
    return true;
  }

  const compact = value.replace(/[^A-Za-z0-9]/g, "");
  return compact.length >= 40 && /[A-Za-z]/.test(compact) && /[0-9]/.test(compact);
}

function safeProfileText(value: string | null | undefined, fallback: string, maxLength = 80): string {
  const collapsed = collapseProfileWhitespace(value ?? "");
  if (!collapsed || looksCredentialLikeValue(collapsed)) {
    return fallback;
  }
  return collapsed.slice(0, maxLength);
}

function safeProfileSlug(value: string | null | undefined, fallback: string): string {
  const safeText = safeProfileText(value, fallback, 80);
  const slug = safeText
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^[._-]+|[._-]+$/g, "")
    .slice(0, 64);
  return slug || fallback;
}

function safeUbuntuVersion(value: string | null | undefined): string {
  const safe = safeProfileText(value, "25.10", 16);
  return /^[0-9]{2}\.[0-9]{2}$/.test(safe) ? safe : "25.10";
}

function inferRefType(ref: string): TeamProfileRefType {
  if (/^[a-f0-9]{7,40}$/i.test(ref)) return "commit";
  if (/^v?[0-9]+(?:\.[0-9]+){1,3}(?:[-+][A-Za-z0-9._-]+)?$/.test(ref)) return "tag";
  return "branch";
}

function profileIdFromInputs(
  provider: string,
  mode: InstallMode,
  sourceRef: string,
  explicitProfileId?: string,
): string {
  if (explicitProfileId) {
    return safeProfileSlug(explicitProfileId, "acfs-team-profile");
  }
  return safeProfileSlug(`${provider}-${mode}-${sourceRef}-acfs`, "acfs-team-profile");
}

function normalizeTeamModuleSelection(input: ModuleSelectionInput | undefined): Required<Pick<ModuleSelectionInput, "onlyModules" | "onlyPhases" | "skipModules">> & {
  profile: NonNullable<ModuleSelectionInput["profile"]>;
  noDeps: false;
} {
  return {
    profile: input?.profile ?? "full",
    onlyModules: sortUnique(input?.onlyModules),
    onlyPhases: sortUnique(input?.onlyPhases),
    skipModules: sortUnique(input?.skipModules),
    noDeps: false,
  };
}

function buildTeamProfileModulePlan(moduleSelection: ModuleSelectionInput): TeamProfileModulePlan {
  const plan = resolveModuleSelection(moduleSelection);
  const warnings = [...plan.warnings];
  if (plan.included.some((entry) => entry.category === "cloud")) {
    warnings.push("Selected cloud modules may require live provider or CLI authentication after install.");
  }

  return {
    ok: plan.ok,
    selectedCount: plan.selectedCount,
    availableCount: plan.availableCount,
    included: plan.included.map((entry) => entry.id),
    excluded: plan.excluded.map((entry) => entry.id),
    dependencyClosure: plan.included
      .filter((entry) => entry.reason.startsWith("dependency of "))
      .map((entry) => entry.id),
    warnings,
    errors: [...plan.errors],
  };
}

function moduleSelectionFromTeamProfile(profile: TeamProfile): ModuleSelectionInput {
  return {
    profile: profile.install.profile,
    onlyModules: profile.install.modules.only,
    onlyPhases: profile.install.modules.onlyPhases,
    skipModules: profile.install.modules.skip,
    noDeps: profile.install.modules.noDeps,
  };
}

export function buildTeamProfile(inputs: TeamProfileInputs): TeamProfile {
  const providerSelection = inputs.providerSelection ?? DEFAULT_TEAM_PROVIDER_SELECTION;
  const sourceRef = normalizeGitRef(inputs.ref) ?? DEFAULT_INSTALL_REF;
  const provider = safeProfileSlug(providerSelection.providerId, "other");
  const region = safeProfileSlug(providerSelection.region, "not-listed");
  const planClass = safeProfileText(providerSelection.planName, "custom plan");
  const ubuntuVersion = safeUbuntuVersion(providerSelection.ubuntuVersion);
  const targetUsername = normalizeCommandUsername(inputs.username);
  const architecture = inputs.architecture ?? "x86_64";
  const moduleSelection = normalizeTeamModuleSelection(inputs.moduleSelection);
  const modulePlan = buildTeamProfileModulePlan(moduleSelection);
  const profileId = profileIdFromInputs(provider, inputs.mode, sourceRef, inputs.profileId);

  return {
    schema: TEAM_PROFILE_SCHEMA,
    schemaVersion: TEAM_PROFILE_SCHEMA_VERSION,
    profileId,
    displayName: safeProfileText(inputs.displayName, "ACFS Team Profile"),
    description: safeProfileText(
      inputs.description,
      "Redacted ACFS wizard defaults for repeatable team installs.",
      160,
    ),
    generatedAt: inputs.generatedAt ?? new Date().toISOString(),
    generatedBy: "acfs-web-wizard",
    provenance: {
      author: null,
      source: {
        acfsVersion: manifestProvenance.acfsVersion,
        acfsRef: sourceRef,
        acfsCommit: null,
        manifestSha256: manifestProvenance.manifestSha256,
        checksumsYamlSha256: manifestProvenance.checksumsYamlSha256,
      },
    },
    compatibility: {
      minAcfsVersion: manifestProvenance.acfsVersion,
      schemaVersions: [TEAM_PROFILE_SCHEMA_VERSION],
      targetUbuntuVersions: [ubuntuVersion],
      architectures: ["x86_64", "aarch64"],
      installerRefPolicy: "prefer_pinned_ref",
      checksumsRefPolicy: "current_acfs_default",
    },
    providerDefaults: {
      provider,
      region,
      planClass,
      operatingSystem: `ubuntu-${ubuntuVersion}`,
      architecture,
      sshUser: targetUsername,
      sshPort: 22,
    },
    install: {
      mode: inputs.mode,
      profile: moduleSelection.profile,
      ref: {
        type: inferRefType(sourceRef),
        value: sourceRef,
        pinOnExport: true,
      },
      modules: {
        only: moduleSelection.onlyModules,
        onlyPhases: moduleSelection.onlyPhases,
        skip: moduleSelection.skipModules,
        noDeps: false,
      },
      modulePlan,
      offlinePack: {
        required: false,
        pathHint: null,
      },
    },
    shellPreferences: {
      loginShell: "zsh",
      history: "atuin",
      multiplexer: "tmux",
    },
    lessonChoices: {
      startLesson: "linux-basics",
      requiredLessons: ["terminal-navigation", "agent-workflow"],
      optionalLessons: ["cloud-provider-setup"],
    },
    serviceAccounts: [...TEAM_PROFILE_SERVICE_ACCOUNTS],
    redaction: {
      allowSecretValues: false,
      secretSlotsRequired: true,
      forbiddenFields: [...TEAM_PROFILE_FORBIDDEN_FIELDS],
    },
  };
}

export function serializeTeamProfileJson(profile: TeamProfile): string {
  return `${JSON.stringify(profile, null, 2)}\n`;
}

export function formatTeamProfileReviewMarkdown(profile: TeamProfile): string {
  const moduleSelection = moduleSelectionFromTeamProfile(profile);
  const installRef = profile.install.ref.value === DEFAULT_INSTALL_REF ? null : profile.install.ref.value;
  const installCommand = buildInstallCommand(
    profile.install.mode,
    installRef,
    profile.providerDefaults.sshUser,
    moduleSelection,
  );
  const secretSlots = profile.serviceAccounts
    .map((account) => `- ${account.id}: ${account.required ? "required" : "optional"} ${account.secretSlot}`)
    .join("\n");
  const dependencyClosure = profile.install.modulePlan.dependencyClosure.length > 0
    ? profile.install.modulePlan.dependencyClosure.map((moduleId) => `- ${moduleId}`).join("\n")
    : "- none";
  const warnings = profile.install.modulePlan.warnings.length > 0
    ? profile.install.modulePlan.warnings.map((warning) => `- ${warning}`).join("\n")
    : "- none";
  const incompatibilities = profile.install.modulePlan.ok
    ? "- none"
    : profile.install.modulePlan.errors.map((error) => `- ${error}`).join("\n");

  return [
    "# ACFS Team Profile Review",
    "",
    `Schema: \`${profile.schema}\``,
    `Profile: ${profile.displayName} (\`${profile.profileId}\`)`,
    `Generated: ${profile.generatedAt}`,
    "",
    "## Safe Defaults",
    "",
    `- Provider: ${profile.providerDefaults.provider}`,
    `- Region: ${profile.providerDefaults.region}`,
    `- Plan class: ${profile.providerDefaults.planClass}`,
    `- Operating system: ${profile.providerDefaults.operatingSystem}`,
    `- Architecture: ${profile.providerDefaults.architecture}`,
    `- SSH user: ${profile.providerDefaults.sshUser}`,
    "",
    "## Installer Command Preview",
    "",
    "```bash",
    installCommand,
    "```",
    "",
    "## Module Plan",
    "",
    `- Profile: ${profile.install.profile}`,
    `- Selected modules: ${profile.install.modulePlan.selectedCount} of ${profile.install.modulePlan.availableCount}`,
    `- Ref policy: ${profile.install.ref.type} ${profile.install.ref.value}, pin on export`,
    "",
    "Dependency closure:",
    dependencyClosure,
    "",
    "Warnings:",
    warnings,
    "",
    "## Secret Slots",
    "",
    secretSlots,
    "",
    "## Incompatibilities",
    "",
    incompatibilities,
    "",
    "## Refusals",
    "",
    "- Credential-like provider values, raw host addresses, private keys, local paths, and token material are omitted or replaced with safe defaults before export.",
    "- Secret slots are placeholders only; no secret values are stored in this profile.",
    "",
  ].join("\n");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function valueAtPath(record: Record<string, unknown>, path: string): unknown {
  return path.split(".").reduce<unknown>((current, part) => {
    if (!isRecord(current)) return undefined;
    return current[part];
  }, record);
}

function importFinding(
  code: TeamProfileImportCode,
  path: string,
  message: string,
  severity: TeamProfileImportFinding["severity"] = "error",
): TeamProfileImportFinding {
  return { code, severity, path, message };
}

function isAllowedPolicyPath(path: string): boolean {
  return path === "redaction"
    || path.startsWith("redaction.")
    || path === "provenance.source.manifestSha256"
    || path === "provenance.source.checksumsYamlSha256"
    || path.startsWith("install.modulePlan.")
    || /^serviceAccounts\.[0-9]+\.(authMethod|secretSlot)$/.test(path);
}

function collectSecurityFindings(
  value: unknown,
  path: string,
  findings: TeamProfileImportFinding[],
): void {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => collectSecurityFindings(entry, `${path}.${index}`, findings));
    return;
  }

  if (isRecord(value)) {
    for (const [key, child] of Object.entries(value)) {
      const childPath = path ? `${path}.${key}` : key;
      const loweredKey = key.toLowerCase();
      const forbiddenKey = TEAM_PROFILE_FORBIDDEN_FIELDS.find((field) => loweredKey.includes(field.toLowerCase()));
      if (forbiddenKey && !isAllowedPolicyPath(childPath)) {
        findings.push(importFinding(
          "team_profile_forbidden_field",
          childPath,
          `Forbidden credential-like field name matches ${forbiddenKey}.`,
        ));
      }
      collectSecurityFindings(child, childPath, findings);
    }
    return;
  }

  if (typeof value === "string" && !isAllowedPolicyPath(path) && looksCredentialLikeValue(value)) {
    findings.push(importFinding(
      "team_profile_secret_material_refused",
      path,
      "Credential-like or host-identifying value refused.",
    ));
  }
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is string => typeof entry === "string");
}

function isInstallMode(value: unknown): value is InstallMode {
  return value === "vibe" || value === "safe";
}

function isProfileId(value: unknown): value is NonNullable<ModuleSelectionInput["profile"]> {
  return typeof value === "string" && TEAM_PROFILE_PROFILE_IDS.has(value);
}

function isTeamProfileRefType(value: unknown): value is TeamProfileRefType {
  return value === "branch" || value === "tag" || value === "commit";
}

function isTeamProfileArchitecture(value: unknown): value is TeamProfileArchitecture {
  return value === "x86_64" || value === "aarch64";
}

function isTeamSecretSlot(value: unknown): value is TeamProfileServiceAccount["secretSlot"] {
  return typeof value === "string" && /^secret:\/\/acfs\/team\/[a-z0-9._-]+$/.test(value);
}

function importedModuleSelection(profile: TeamProfile): ModuleSelectionInput {
  const install = profile.install as Omit<TeamProfile["install"], "modules"> & {
    modules: Partial<Omit<TeamProfile["install"]["modules"], "noDeps">> & { noDeps?: boolean };
  };

  return {
    profile: isProfileId(install.profile) ? install.profile : "full",
    onlyModules: sortUnique(asStringArray(install.modules.only)),
    onlyPhases: sortUnique(asStringArray(install.modules.onlyPhases)),
    skipModules: sortUnique(asStringArray(install.modules.skip)),
    noDeps: install.modules.noDeps === true,
  };
}

function compareChange(
  field: string,
  current: TeamProfileImportChange["current"],
  next: TeamProfileImportChange["next"],
): TeamProfileImportChange | null {
  if (JSON.stringify(current) === JSON.stringify(next)) return null;
  return { field, current, next };
}

function compactChanges(changes: Array<TeamProfileImportChange | null>): TeamProfileImportChange[] {
  return changes.filter((change): change is TeamProfileImportChange => change !== null);
}

function validateTeamProfileForImport(
  input: unknown,
  current: TeamProfileImportCurrentState,
): TeamProfileImportFinding[] {
  const findings: TeamProfileImportFinding[] = [];
  if (!isRecord(input)) {
    return [
      importFinding("team_profile_missing_schema", "schema", "Profile must be a JSON object with a supported schema."),
    ];
  }

  const schema = input.schema;
  const schemaVersion = input.schemaVersion;
  if (schema !== TEAM_PROFILE_SCHEMA) {
    findings.push(importFinding(
      schema === undefined ? "team_profile_missing_schema" : "team_profile_schema_unsupported",
      "schema",
      `Expected ${TEAM_PROFILE_SCHEMA}.`,
    ));
  }
  if (schemaVersion !== TEAM_PROFILE_SCHEMA_VERSION) {
    findings.push(importFinding(
      "team_profile_schema_unsupported",
      "schemaVersion",
      `Expected schemaVersion ${TEAM_PROFILE_SCHEMA_VERSION}.`,
    ));
  }

  for (const key of Object.keys(input)) {
    if (!TEAM_PROFILE_ALLOWED_TOP_LEVEL_FIELDS.has(key)) {
      findings.push(importFinding(
        "team_profile_unknown_top_level_field",
        key,
        `Unknown top-level field ${key}; use extensions for future metadata.`,
      ));
    }
  }

  for (const path of TEAM_PROFILE_REQUIRED_PATHS) {
    if (valueAtPath(input, path) === undefined) {
      findings.push(importFinding("team_profile_missing_required_field", path, `Missing required field ${path}.`));
    }
  }

  collectSecurityFindings(input, "", findings);

  const redaction = isRecord(input.redaction) ? input.redaction : {};
  if (redaction.allowSecretValues !== false) {
    findings.push(importFinding(
      "team_profile_secret_material_refused",
      "redaction.allowSecretValues",
      "Profiles must set redaction.allowSecretValues to false.",
    ));
  }
  if (redaction.secretSlotsRequired !== true) {
    findings.push(importFinding(
      "team_profile_missing_required_field",
      "redaction.secretSlotsRequired",
      "Profiles must require secret-slot placeholders.",
    ));
  }

  const compatibility = isRecord(input.compatibility) ? input.compatibility : {};
  const targetUbuntuVersions = asStringArray(compatibility.targetUbuntuVersions);
  const targetUbuntu = current.ubuntuVersion ?? "25.10";
  if (targetUbuntuVersions.length > 0 && !targetUbuntuVersions.includes(targetUbuntu)) {
    findings.push(importFinding(
      "team_profile_ubuntu_unsupported",
      "compatibility.targetUbuntuVersions",
      `Profile does not list Ubuntu ${targetUbuntu}.`,
    ));
  }

  const architectures = asStringArray(compatibility.architectures);
  const architecture = current.architecture ?? "x86_64";
  if (architectures.length > 0 && !architectures.includes(architecture)) {
    findings.push(importFinding(
      "team_profile_arch_unsupported",
      "compatibility.architectures",
      `Profile does not list architecture ${architecture}.`,
    ));
  }

  const provenance = isRecord(input.provenance) && isRecord(input.provenance.source)
    ? input.provenance.source
    : {};
  if (provenance.manifestSha256 && provenance.manifestSha256 !== manifestProvenance.manifestSha256) {
    findings.push(importFinding(
      "team_profile_manifest_mismatch",
      "provenance.source.manifestSha256",
      "Profile was generated from a different acfs.manifest.yaml.",
    ));
  }
  if (provenance.checksumsYamlSha256 && provenance.checksumsYamlSha256 !== manifestProvenance.checksumsYamlSha256) {
    findings.push(importFinding(
      "team_profile_checksums_mismatch",
      "provenance.source.checksumsYamlSha256",
      "Profile was generated from a different checksums.yaml.",
    ));
  }

  const install = isRecord(input.install) ? input.install : {};
  if (install.mode !== undefined && !isInstallMode(install.mode)) {
    findings.push(importFinding(
      "team_profile_schema_unsupported",
      "install.mode",
      "install.mode must be either vibe or safe.",
    ));
  }
  if (install.profile !== undefined && !isProfileId(install.profile)) {
    findings.push(importFinding(
      "team_profile_unknown_module",
      "install.profile",
      "Profile references an unknown module selection profile.",
    ));
  }
  const ref = isRecord(install.ref) ? install.ref : {};
  if (ref.type !== undefined && !isTeamProfileRefType(ref.type)) {
    findings.push(importFinding(
      "team_profile_schema_unsupported",
      "install.ref.type",
      "install.ref.type must be branch, tag, or commit.",
    ));
  }
  if (typeof ref.value !== "string" || normalizeGitRef(ref.value) !== ref.value) {
    findings.push(importFinding(
      "team_profile_schema_unsupported",
      "install.ref.value",
      "install.ref.value must be a valid ACFS git ref.",
    ));
  }
  if (ref.pinOnExport !== true) {
    findings.push(importFinding(
      "team_profile_ref_policy_mismatch",
      "install.ref.pinOnExport",
      "Profile imports require install.ref.pinOnExport to be true.",
    ));
  }
  const modules = isRecord(install.modules) ? install.modules : {};
  if (install.modules !== undefined && !isRecord(install.modules)) {
    findings.push(importFinding(
      "team_profile_missing_required_field",
      "install.modules",
      "install.modules must be an object.",
    ));
  }
  if (modules.noDeps !== undefined && typeof modules.noDeps !== "boolean") {
    findings.push(importFinding(
      "team_profile_schema_unsupported",
      "install.modules.noDeps",
      "install.modules.noDeps must be a boolean.",
    ));
  }
  if (modules.noDeps === true) {
    findings.push(importFinding(
      "team_profile_no_deps_refused",
      "install.modules.noDeps",
      "Profile import refuses --no-deps unless a future expert confirmation path is added.",
    ));
  }

  const moduleSelection: ModuleSelectionInput = {
    profile: isProfileId(install.profile) ? install.profile : "full",
    onlyModules: asStringArray(modules.only),
    onlyPhases: asStringArray(modules.onlyPhases),
    skipModules: asStringArray(modules.skip),
    noDeps: modules.noDeps === true,
  };
  const plan = resolveModuleSelection(moduleSelection);
  for (const error of plan.errors) {
    const code = error.includes("phase")
      ? "team_profile_unknown_phase"
      : "team_profile_unknown_module";
    findings.push(importFinding(code, "install.modules", error));
  }

  const providerDefaults = isRecord(input.providerDefaults) ? input.providerDefaults : {};
  if (providerDefaults.architecture !== undefined && !isTeamProfileArchitecture(providerDefaults.architecture)) {
    findings.push(importFinding(
      "team_profile_arch_unsupported",
      "providerDefaults.architecture",
      "Profile defaults must use a supported architecture.",
    ));
  }
  if (providerDefaults.sshUser !== undefined) {
    if (typeof providerDefaults.sshUser !== "string" || normalizeSSHUsername(providerDefaults.sshUser) !== providerDefaults.sshUser) {
      findings.push(importFinding(
        "team_profile_schema_unsupported",
        "providerDefaults.sshUser",
        "Profile defaults must use a valid SSH username.",
      ));
    }
  }

  if (input.serviceAccounts !== undefined && !Array.isArray(input.serviceAccounts)) {
    findings.push(importFinding(
      "team_profile_missing_required_field",
      "serviceAccounts",
      "serviceAccounts must be an array.",
    ));
  }
  if (Array.isArray(input.serviceAccounts)) {
    input.serviceAccounts.forEach((account, index) => {
      if (!isRecord(account)) {
        findings.push(importFinding(
          "team_profile_missing_required_field",
          `serviceAccounts.${index}`,
          "serviceAccounts entries must be objects.",
        ));
        return;
      }
      if (!isTeamSecretSlot(account.secretSlot)) {
        findings.push(importFinding(
          "team_profile_secret_material_refused",
          `serviceAccounts.${index}.secretSlot`,
          "Secret slots must be secret://acfs/team/<slot-id> placeholders.",
        ));
      }
    });
  }

  return findings;
}

function importDiffCanRevealProfile(findings: TeamProfileImportFinding[]): boolean {
  return !findings.some((finding) =>
    finding.code === "team_profile_missing_schema"
    || finding.code === "team_profile_schema_unsupported"
    || finding.code === "team_profile_missing_required_field"
    || finding.code === "team_profile_secret_material_refused"
    || finding.code === "team_profile_forbidden_field"
    || finding.code === "team_profile_unknown_top_level_field"
  );
}

function currentSourceRef(current: TeamProfileImportCurrentState): string {
  return normalizeGitRef(current.ref) ?? DEFAULT_INSTALL_REF;
}

export function buildTeamProfileImportDiff(
  input: unknown,
  current: TeamProfileImportCurrentState = {},
): TeamProfileImportDiff {
  const findings = validateTeamProfileForImport(input, current);
  const refusals = findings.filter((finding) =>
    finding.code === "team_profile_secret_material_refused"
    || finding.code === "team_profile_forbidden_field"
    || finding.code === "team_profile_unknown_top_level_field"
  );
  const incompatibilities = findings.filter((finding) => !refusals.includes(finding));
  const profile = importDiffCanRevealProfile(findings) && isRecord(input)
    ? input as unknown as TeamProfile
    : null;

  if (!profile) {
    return {
      schema: "acfs.team-profile-import-diff.v1",
      schemaVersion: 1,
      dryRun: true,
      ok: false,
      profile: null,
      findings,
      safeDefaults: { changes: [] },
      installerCommand: { command: null, changes: [] },
      dependencyClosure: [],
      skips: { requested: [], allowed: false, warnings: [] },
      secretSlots: { required: [], optional: [] },
      incompatibilities,
      refusals,
    };
  }

  const moduleSelection = importedModuleSelection(profile);
  const modulePlan = buildTeamProfileModulePlan(moduleSelection);
  const commandRef = profile.install.ref.value === DEFAULT_INSTALL_REF ? null : profile.install.ref.value;
  const commandAllowed = findings.length === 0 && modulePlan.ok;
  const currentProvider = current.providerSelection ?? null;
  const currentModules = normalizeTeamModuleSelection(current.moduleSelection);
  const installerChanges = compactChanges([
    compareChange("install.mode", current.installMode ?? null, profile.install.mode),
    compareChange("install.ref.value", currentSourceRef(current), profile.install.ref.value),
    compareChange("install.profile", currentModules.profile, moduleSelection.profile ?? "full"),
    compareChange("install.modules.only", currentModules.onlyModules, moduleSelection.onlyModules ?? []),
    compareChange("install.modules.onlyPhases", currentModules.onlyPhases, moduleSelection.onlyPhases ?? []),
    compareChange("install.modules.skip", currentModules.skipModules, moduleSelection.skipModules ?? []),
  ]);
  const safeDefaultChanges = compactChanges([
    compareChange("providerDefaults.provider", currentProvider?.providerId ?? null, profile.providerDefaults.provider),
    compareChange("providerDefaults.region", currentProvider?.region ?? null, profile.providerDefaults.region),
    compareChange("providerDefaults.planClass", currentProvider?.planName ?? null, profile.providerDefaults.planClass),
    compareChange("providerDefaults.operatingSystem", current.ubuntuVersion ?? null, profile.providerDefaults.operatingSystem),
    compareChange("providerDefaults.architecture", current.architecture ?? null, profile.providerDefaults.architecture),
    compareChange("providerDefaults.sshUser", normalizeCommandUsername(current.username), profile.providerDefaults.sshUser),
  ]);
  const requiredSecretSlots = profile.serviceAccounts
    .filter((account) => account.required)
    .map((account) => account.secretSlot)
    .sort();
  const optionalSecretSlots = profile.serviceAccounts
    .filter((account) => !account.required)
    .map((account) => account.secretSlot)
    .sort();

  return {
    schema: "acfs.team-profile-import-diff.v1",
    schemaVersion: 1,
    dryRun: true,
    ok: findings.length === 0 && modulePlan.ok,
    profile: {
      profileId: profile.profileId,
      displayName: profile.displayName,
      schemaVersion: profile.schemaVersion,
    },
    findings,
    safeDefaults: { changes: safeDefaultChanges },
    installerCommand: {
      command: commandAllowed
        ? buildInstallCommand(profile.install.mode, commandRef, profile.providerDefaults.sshUser, moduleSelection)
        : null,
      changes: installerChanges,
    },
    dependencyClosure: modulePlan.dependencyClosure,
    skips: {
      requested: moduleSelection.skipModules ?? [],
      allowed: modulePlan.ok && findings.every((finding) => finding.code !== "team_profile_no_deps_refused"),
      warnings: modulePlan.warnings,
    },
    secretSlots: {
      required: requiredSecretSlots,
      optional: optionalSecretSlots,
    },
    incompatibilities,
    refusals,
  };
}

export function serializeTeamProfileImportDiffJson(diff: TeamProfileImportDiff): string {
  return `${JSON.stringify(diff, null, 2)}\n`;
}

export function formatTeamProfileImportDiffMarkdown(diff: TeamProfileImportDiff): string {
  const formatChanges = (changes: TeamProfileImportChange[]) =>
    changes.length > 0
      ? changes.map((change) => `- ${change.field}: ${JSON.stringify(change.current)} -> ${JSON.stringify(change.next)}`).join("\n")
      : "- none";
  const formatFindings = (findings: TeamProfileImportFinding[]) =>
    findings.length > 0
      ? findings.map((finding) => `- ${finding.code} at ${finding.path}: ${finding.message}`).join("\n")
      : "- none";

  return [
    "# ACFS Team Profile Import Diff",
    "",
    `Dry run: ${diff.dryRun ? "yes" : "no"}`,
    `Status: ${diff.ok ? "ready" : "blocked"}`,
    diff.profile ? `Profile: ${diff.profile.displayName} (\`${diff.profile.profileId}\`)` : "Profile: unavailable",
    "",
    "## Safe Defaults",
    "",
    formatChanges(diff.safeDefaults.changes),
    "",
    "## Installer Command",
    "",
    diff.installerCommand.command
      ? ["```bash", diff.installerCommand.command, "```"].join("\n")
      : "Blocked until incompatibilities and refusals are resolved.",
    "",
    "Command changes:",
    formatChanges(diff.installerCommand.changes),
    "",
    "## Dependency Closure",
    "",
    diff.dependencyClosure.length > 0
      ? diff.dependencyClosure.map((moduleId) => `- ${moduleId}`).join("\n")
      : "- none",
    "",
    "## Skips",
    "",
    diff.skips.requested.length > 0
      ? diff.skips.requested.map((moduleId) => `- ${moduleId}`).join("\n")
      : "- none",
    "",
    "## Secret Slots",
    "",
    "Required:",
    diff.secretSlots.required.length > 0
      ? diff.secretSlots.required.map((slot) => `- ${slot}`).join("\n")
      : "- none",
    "",
    "Optional:",
    diff.secretSlots.optional.length > 0
      ? diff.secretSlots.optional.map((slot) => `- ${slot}`).join("\n")
      : "- none",
    "",
    "## Incompatibilities",
    "",
    formatFindings(diff.incompatibilities),
    "",
    "## Refusals",
    "",
    formatFindings(diff.refusals),
    "",
  ].join("\n");
}

export function buildHandoffRunbook(inputs: CommandBuilderInputs): HandoffRunbook {
  const safeRef = normalizeGitRef(inputs.ref);
  const sourceRef = safeRef ?? DEFAULT_INSTALL_REF;
  const targetUsername = normalizeCommandUsername(inputs.username);
  const redactedHost = redactedTargetHost(inputs.ip);
  const targetHostKind = classifyTargetHost(inputs.ip);
  const installCommand = buildInstallCommand(inputs.mode, safeRef, targetUsername, inputs.moduleSelection);
  const rootLoginCommand = `ssh root@${redactedHost}`;
  const postInstallLoginCommand = `ssh -i ${SSH_KEY_PATH_UNIX} ${targetUsername}@${redactedHost}`;
  const postInstallLoginCommandWindows = `ssh -i ${SSH_KEY_PATH_WINDOWS} ${targetUsername}@${redactedHost}`;
  const userKeyRepairCommand = buildUserKeyRepairCommand(targetUsername, redactedHost);
  const rootKeyRepairCommand = buildRootKeyRepairCommand(targetUsername, redactedHost);

  return {
    schema: HANDOFF_RUNBOOK_SCHEMA,
    schemaVersion: 1,
    generatedBy: "acfs-web-wizard",
    privacy: {
      rawTargetHostIncluded: false,
      exactInstallCommandIncluded: true,
      targetUsernameMayAppear: true,
      redactedFields: [
        "targetHost.address",
        "ssh.rootLoginCommand.host",
        "ssh.postInstallLoginCommand.host",
        "recoveryCommands.sshHosts",
      ],
    },
    wizardSelections: {
      localOS: inputs.os,
      installMode: inputs.mode,
      sourceRef,
      targetUsername,
    },
    targetHost: {
      kind: targetHostKind,
      value: redactedHost,
      assumptions: [
        "Run the installer from a root SSH session on the VPS unless an existing installer log explicitly tells you to resume as the target user.",
        "ACFS creates or updates the target Linux user during installation.",
        "The host address is intentionally redacted from this artifact; keep it in your password manager or VPS provider console.",
      ],
    },
    ssh: {
      keyPathUnix: SSH_KEY_PATH_UNIX,
      keyPathWindows: SSH_KEY_PATH_WINDOWS,
      rootLoginCommand,
      postInstallLoginCommand,
      postInstallLoginCommandWindows,
    },
    install: {
      command: installCommand,
      runLocation: "vps",
      sourceRef,
      mode: inputs.mode,
    },
    recoveryCommands: [
      {
        id: "repair-user-ssh-key",
        label: "Copy the ACFS public key into the configured user",
        command: userKeyRepairCommand,
        runLocation: "local",
      },
      {
        id: "repair-user-ssh-key-through-root",
        label: "Copy the ACFS public key through the root fallback",
        command: rootKeyRepairCommand,
        runLocation: "local",
      },
      {
        id: "reconnect-root",
        label: "Reconnect to the root SSH session",
        command: rootLoginCommand,
        runLocation: "local",
      },
      {
        id: "rerun-installer",
        label: "Resume or retry the installer",
        command: installCommand,
        runLocation: "vps",
      },
      {
        id: "reconnect-user",
        label: "Reconnect as the configured user after install",
        command: postInstallLoginCommand,
        runLocation: "local",
      },
      {
        id: "doctor",
        label: "Run the ACFS health check",
        command: "acfs doctor",
        runLocation: "vps",
      },
      {
        id: "support-bundle",
        label: "Create a redacted support bundle",
        command: "acfs support-bundle",
        runLocation: "vps",
      },
    ],
    support: {
      bundleCommand: "acfs support-bundle",
      bundlePathPattern: "~/.acfs/support/<timestamp>/",
      reviewArtifacts: ["support-report.md", "manifest.json"],
    },
  };
}

export function serializeHandoffRunbookJson(runbook: HandoffRunbook): string {
  return `${JSON.stringify(runbook, null, 2)}\n`;
}

export function formatHandoffRunbookMarkdown(runbook: HandoffRunbook): string {
  const recoveryCommands = runbook.recoveryCommands
    .map((command) => [
      `### ${command.label}`,
      "",
      `Run on: ${command.runLocation === "vps" ? "VPS" : "local computer"}`,
      "",
      "```bash",
      command.command,
      "```",
    ].join("\n"))
    .join("\n\n");

  return [
    "# ACFS Wizard Handoff Runbook",
    "",
    `Schema: \`${runbook.schema}\``,
    "",
    "## Wizard Selections",
    "",
    `- Local OS: ${runbook.wizardSelections.localOS}`,
    `- Install mode: ${runbook.wizardSelections.installMode}`,
    `- Source ref: ${runbook.wizardSelections.sourceRef}`,
    `- Target user: ${runbook.wizardSelections.targetUsername}`,
    "",
    "## Target Host",
    "",
    `- Host kind: ${runbook.targetHost.kind}`,
    `- Host value: ${runbook.targetHost.value}`,
    "",
    ...runbook.targetHost.assumptions.map((assumption) => `- ${assumption}`),
    "",
    "## Installer Command",
    "",
    "Run on: VPS",
    "",
    "```bash",
    runbook.install.command,
    "```",
    "",
    "## SSH Expectations",
    "",
    `- Unix key path: \`${runbook.ssh.keyPathUnix}\``,
    `- Windows key path: \`${runbook.ssh.keyPathWindows}\``,
    "",
    "## Recovery Commands",
    "",
    recoveryCommands,
    "",
    "## Support Bundle",
    "",
    `- Command: \`${runbook.support.bundleCommand}\``,
    `- Output pattern: \`${runbook.support.bundlePathPattern}\``,
    `- Review before sharing: ${runbook.support.reviewArtifacts.join(", ")}`,
    "",
    "## Privacy",
    "",
    "- The target host address is redacted from SSH and recovery commands.",
    "- The installer command is exact so it can be copied back into the VPS session.",
    "- The configured target username may appear because it affects installer behavior.",
    "",
  ].join("\n");
}

/**
 * Build a shareable URL with all command builder state encoded as query params.
 */
export function buildShareURL(inputs: CommandBuilderInputs): string {
  if (typeof window === "undefined") return "";
  const url = new URL(window.location.pathname, window.location.origin);
  const safeUsername = normalizeCommandUsername(inputs.username);
  url.searchParams.set("ip", inputs.ip);
  url.searchParams.set("os", inputs.os);
  if (safeUsername !== "ubuntu") {
    url.searchParams.set("user", safeUsername);
  } else {
    url.searchParams.delete("user");
  }
  url.searchParams.set("mode", inputs.mode);
  const safeRef = normalizeGitRef(inputs.ref);
  if (safeRef) {
    url.searchParams.set("ref", safeRef);
  } else {
    url.searchParams.delete("ref");
  }
  return url.toString();
}
