import { describe, expect, test } from "bun:test";
import {
  buildRootKeyRepairCommand,
  buildUserKeyRepairCommand,
  buildCommands,
  buildHandoffRunbook,
  buildInstallCommand,
  buildTeamProfile,
  buildTeamProfileImportDiff,
  buildShareURL,
  formatSshTarget,
  formatHandoffRunbookMarkdown,
  formatTeamProfileImportDiffMarkdown,
  formatTeamProfileReviewMarkdown,
  serializeTeamProfileImportDiffJson,
  serializeHandoffRunbookJson,
  serializeTeamProfileJson,
} from "./commandBuilder";

describe("formatSshTarget", () => {
  test("formats valid IPv4 and IPv6 SSH targets", () => {
    expect(formatSshTarget("root", "203.0.113.42")).toBe("root@203.0.113.42");
    expect(formatSshTarget("ubuntu", "2001:db8::42")).toBe("ubuntu@[2001:db8::42]");
    expect(formatSshTarget("ubuntu", "[2001:db8::42]")).toBe("ubuntu@[2001:db8::42]");
    expect(formatSshTarget("ubuntu", "YOUR_VPS_IPV4")).toBe("ubuntu@YOUR_VPS_IPV4");
  });

  test("does not serialize shell metacharacters into copyable SSH targets", () => {
    const target = formatSshTarget("bad user;sudo", "203.0.113.42; touch /tmp/acfs-owned");

    expect(target).toBe("ubuntu@YOUR_VPS_IP");
    expect(target).not.toContain(";");
    expect(target).not.toContain("touch");
    expect(target).not.toContain("bad user");
  });
});

describe("buildRootKeyRepairCommand", () => {
  test("copies the ACFS public key through root without appending duplicates", () => {
    const command = buildRootKeyRepairCommand("dev-user", "203.0.113.42");

    expect(command).toContain("cat ~/.ssh/acfs_ed25519.pub | ssh root@203.0.113.42");
    expect(command).toContain("read -r acfs_pubkey");
    expect(command).toContain("test ! -L /home/dev-user/.ssh");
    expect(command).toContain("tail -c 1 /home/dev-user/.ssh/authorized_keys");
    expect(command).toContain("grep -qw 10");
    expect(command).toContain('if ! grep -qxF \\"\\$acfs_pubkey\\" /home/dev-user/.ssh/authorized_keys; then');
    expect(command).toContain('printf \'%s\\n\' \\"\\$acfs_pubkey\\" >> /home/dev-user/.ssh/authorized_keys');
    expect(command).not.toContain("cat >> /home/dev-user/.ssh/authorized_keys");
  });

  test("preserves public key quoting after local shell parsing", () => {
    const command = buildRootKeyRepairCommand("ubuntu", "203.0.113.42");
    const result = Bun.spawnSync({
      cmd: ["bash", "-lc", `ssh() { printf '%s\\n' "$2"; }\n${command}`],
      env: { ...process.env, HOME: "/tmp/acfs-missing-home-for-test" },
      stderr: "pipe",
      stdout: "pipe",
    });

    expect(result.exitCode).toBe(0);

    const remoteCommand = new TextDecoder().decode(result.stdout);
    expect(remoteCommand).toContain('grep -qxF "$acfs_pubkey" /home/ubuntu/.ssh/authorized_keys');
    expect(remoteCommand).toContain('printf \'%s\\n\' "$acfs_pubkey" >> /home/ubuntu/.ssh/authorized_keys');
    expect(remoteCommand).not.toContain("grep -qxF $acfs_pubkey");
    expect(remoteCommand).not.toContain("printf '%s\\n' $acfs_pubkey");
  });

  test("falls back to ubuntu for usernames the installer would reject", () => {
    const command = buildRootKeyRepairCommand("Bad User", "2001:db8::42");

    expect(command).toContain("ssh root@[2001:db8::42]");
    expect(command).toContain("/home/ubuntu/.ssh/authorized_keys");
    expect(command).not.toContain("Bad User");
  });

  test("treats root as the bootstrap account, not the ACFS target user", () => {
    const command = buildRootKeyRepairCommand("root", "203.0.113.42");

    expect(command).toContain("ssh root@203.0.113.42");
    expect(command).toContain("/home/ubuntu/.ssh/authorized_keys");
    expect(command).not.toContain("/root/.ssh/authorized_keys");
  });
});

describe("buildUserKeyRepairCommand", () => {
  test("copies the ACFS public key through the configured user without root", () => {
    const command = buildUserKeyRepairCommand("dev-user", "203.0.113.42");

    expect(command).toContain("cat ~/.ssh/acfs_ed25519.pub | ssh dev-user@203.0.113.42");
    expect(command).toContain("read -r acfs_pubkey");
    expect(command).toContain("test ! -L ~/.ssh");
    expect(command).toContain("install -d -m 700 ~/.ssh");
    expect(command).toContain("tail -c 1 ~/.ssh/authorized_keys");
    expect(command).toContain('if ! grep -qxF \\"\\$acfs_pubkey\\" ~/.ssh/authorized_keys; then');
    expect(command).toContain('printf \'%s\\n\' \\"\\$acfs_pubkey\\" >> ~/.ssh/authorized_keys');
    expect(command).not.toContain("ssh root@");
    expect(command).not.toContain("sudo");
    expect(command).not.toContain("cat >> ~/.ssh/authorized_keys");
  });

  test("preserves public key quoting after local shell parsing", () => {
    const command = buildUserKeyRepairCommand("ubuntu", "203.0.113.42");
    const result = Bun.spawnSync({
      cmd: ["bash", "-lc", `ssh() { printf '%s\\n' "$2"; }\n${command}`],
      env: { ...process.env, HOME: "/tmp/acfs-missing-home-for-test" },
      stderr: "pipe",
      stdout: "pipe",
    });

    expect(result.exitCode).toBe(0);

    const remoteCommand = new TextDecoder().decode(result.stdout);
    expect(remoteCommand).toContain('grep -qxF "$acfs_pubkey" ~/.ssh/authorized_keys');
    expect(remoteCommand).toContain('printf \'%s\\n\' "$acfs_pubkey" >> ~/.ssh/authorized_keys');
    expect(remoteCommand).not.toContain("grep -qxF $acfs_pubkey");
    expect(remoteCommand).not.toContain("printf '%s\\n' $acfs_pubkey");
  });

  test("falls back to ubuntu for usernames the installer would reject", () => {
    const command = buildUserKeyRepairCommand("Bad User", "2001:db8::42");

    expect(command).toContain("ssh ubuntu@[2001:db8::42]");
    expect(command).not.toContain("Bad User");
  });
});

describe("buildInstallCommand", () => {
  test("omits TARGET_USER for the default ubuntu user", () => {
    const command = buildInstallCommand("vibe", null, "ubuntu");

    expect(command).not.toContain("TARGET_USER=");
    expect(command).toContain("--mode vibe");
  });

  test("includes TARGET_USER and --ref for a customized install", () => {
    const command = buildInstallCommand("safe", "v1.2.3", "admin");

    expect(command).toContain('TARGET_USER="admin"');
    expect(command).toContain('--ref "v1.2.3"');
    expect(command).toContain("/v1.2.3/install.sh");
    expect(command).toContain("--mode safe");
  });

  test("omits TARGET_USER when the username does not match the installer contract", () => {
    const command = buildInstallCommand("vibe", null, "Admin");

    expect(command).not.toContain("TARGET_USER=");
    expect(command).not.toContain("Admin");
  });

  test("omits TARGET_USER for root so setup targets ubuntu instead", () => {
    const command = buildInstallCommand("vibe", null, "root");

    expect(command).not.toContain("TARGET_USER=");
    expect(command).not.toContain('TARGET_USER="root"');
  });

  test("rejects the legacy master branch in generated install commands", () => {
    const command = buildInstallCommand("vibe", "master", "ubuntu");

    expect(command).toContain("/main/install.sh");
    expect(command).not.toContain("/master/install.sh");
    expect(command).not.toContain('--ref "master"');
  });

  test("appends manifest-backed module selectors for profile previews", () => {
    const command = buildInstallCommand("vibe", null, "ubuntu", {
      profile: "cloud-only",
    });

    expect(command).toContain('--only "cloud.wrangler"');
    expect(command).toContain('--only "cloud.supabase"');
    expect(command).toContain('--only "cloud.vercel"');
    expect(command).not.toContain("--profile");
    expect(command).not.toContain("db.postgres18");
  });

  test("refuses invalid module selectors instead of serializing them", () => {
    expect(() =>
      buildInstallCommand("vibe", null, "ubuntu", {
        onlyModules: ["agents.codex;sudo"],
      }),
    ).toThrow("Unknown module id in --only: agents.codex;sudo");
  });
});

describe("buildCommands", () => {
  test("propagates the customized username into installer and SSH commands", () => {
    const commands = buildCommands({
      ip: "10.20.30.40",
      os: "windows",
      username: "admin",
      mode: "safe",
      ref: null,
    });

    const installer = commands.find((command) => command.id === "installer");
    const sshUser = commands.find((command) => command.id === "ssh-user");

    expect(installer?.command).toContain('TARGET_USER="admin"');
    expect(sshUser?.command).toContain("admin@10.20.30.40");
    expect(sshUser?.windowsCommand).toBe("ssh -i %USERPROFILE%\\.ssh\\acfs_ed25519 admin@10.20.30.40");
  });

  test("falls back to ubuntu when the username input is invalid", () => {
    const commands = buildCommands({
      ip: "10.20.30.40",
      os: "mac",
      username: "bad user",
      mode: "vibe",
      ref: null,
    });

    const installer = commands.find((command) => command.id === "installer");
    const sshUser = commands.find((command) => command.id === "ssh-user");

    expect(installer?.command).not.toContain("TARGET_USER=");
    expect(sshUser?.label).toBe("SSH as ubuntu");
    expect(sshUser?.command).toContain("ubuntu@10.20.30.40");
  });

  test("falls back to ubuntu when the username input is root", () => {
    const commands = buildCommands({
      ip: "10.20.30.40",
      os: "mac",
      username: "root",
      mode: "vibe",
      ref: null,
    });

    const installer = commands.find((command) => command.id === "installer");
    const sshUser = commands.find((command) => command.id === "ssh-user");

    expect(installer?.command).not.toContain("TARGET_USER=");
    expect(sshUser?.label).toBe("SSH as ubuntu");
    expect(sshUser?.command).toContain("ubuntu@10.20.30.40");
  });

  test("accepts lowercase usernames with dots and hyphens", () => {
    const commands = buildCommands({
      ip: "10.20.30.40",
      os: "linux",
      username: "dev-user.1",
      mode: "vibe",
      ref: null,
    });

    const installer = commands.find((command) => command.id === "installer");
    const sshUser = commands.find((command) => command.id === "ssh-user");

    expect(installer?.command).toContain('TARGET_USER="dev-user.1"');
    expect(sshUser?.label).toBe("SSH as dev-user.1");
    expect(sshUser?.command).toContain("dev-user.1@10.20.30.40");
  });

  test("propagates optional module selection into the installer command", () => {
    const commands = buildCommands({
      ip: "10.20.30.40",
      os: "mac",
      username: "ubuntu",
      mode: "vibe",
      ref: null,
      moduleSelection: { profile: "stack-only" },
    });

    const installer = commands.find((command) => command.id === "installer");

    expect(installer?.command).toContain('--only-phase "9"');
  });
});

describe("buildHandoffRunbook", () => {
  const forbiddenCommandSnippets = /\bmaster\b|rm\s+-rf|git\s+reset|git\s+clean|\b(?:npm|yarn|pnpm)\b/i;

  function expectSafeHandoffArtifacts(artifacts: string[], rawHost: string | null) {
    for (const artifact of artifacts) {
      expect(artifact).not.toMatch(forbiddenCommandSnippets);
      if (rawHost) {
        expect(artifact).not.toContain(rawHost);
      }
    }
  }

  test("records the exact installer command while redacting the target host", () => {
    const runbook = buildHandoffRunbook({
      ip: "203.0.113.42",
      os: "mac",
      username: "dev-user",
      mode: "safe",
      ref: "v1.2.3",
    });

    const json = serializeHandoffRunbookJson(runbook);

    expect(runbook.schema).toBe("acfs.handoff-runbook.v1");
    expect(runbook.install.command).toContain('TARGET_USER="dev-user"');
    expect(runbook.install.command).toContain('--ref "v1.2.3"');
    expect(runbook.install.command).toContain("/v1.2.3/install.sh");
    expect(runbook.recoveryCommands[0]).toMatchObject({
      id: "repair-user-ssh-key",
      runLocation: "local",
    });
    expect(runbook.recoveryCommands[0]?.command).toContain("ssh dev-user@YOUR_VPS_IPV4");
    expect(runbook.recoveryCommands[0]?.command).not.toContain("ssh root@");
    const rootFallbackRepair = runbook.recoveryCommands.find(
      (command) => command.id === "repair-user-ssh-key-through-root",
    );
    expect(rootFallbackRepair).toMatchObject({
      runLocation: "local",
    });
    expect(rootFallbackRepair?.command).toContain("ssh root@YOUR_VPS_IPV4");
    expect(rootFallbackRepair?.command).toContain("/home/dev-user/.ssh/authorized_keys");
    expect(runbook.targetHost.kind).toBe("ipv4");
    expect(runbook.targetHost.value).toBe("YOUR_VPS_IPV4");
    expect(runbook.privacy.rawTargetHostIncluded).toBe(false);
    expect(json).not.toContain("203.0.113.42");
    expect(json).toContain("YOUR_VPS_IPV4");
  });

  test("uses a missing host placeholder when wizard state has no valid target", () => {
    const runbook = buildHandoffRunbook({
      ip: "",
      os: "windows",
      username: "bad user",
      mode: "vibe",
      ref: "bad ref",
    });

    expect(runbook.targetHost.kind).toBe("invalid_or_missing");
    expect(runbook.targetHost.value).toBe("YOUR_VPS_IP");
    expect(runbook.wizardSelections.targetUsername).toBe("ubuntu");
    expect(runbook.wizardSelections.sourceRef).toBe("main");
    expect(runbook.install.command).not.toContain("TARGET_USER=");
    expect(runbook.install.command).not.toContain("--ref");
  });

  test("renders a deterministic markdown handoff with support bundle references", () => {
    const runbook = buildHandoffRunbook({
      ip: "2001:db8::42",
      os: "linux",
      username: "ubuntu",
      mode: "vibe",
      ref: null,
    });

    const markdown = formatHandoffRunbookMarkdown(runbook);

    expect(markdown).toContain("# ACFS Wizard Handoff Runbook");
    expect(markdown).toContain("Schema: `acfs.handoff-runbook.v1`");
    expect(markdown).toContain("Host kind: ipv6");
    expect(markdown).toContain("ssh root@YOUR_VPS_IPV6");
    expect(markdown).toContain("Copy the ACFS public key through the root fallback");
    expect(markdown).toContain("/home/ubuntu/.ssh/authorized_keys");
    expect(markdown).toContain("acfs support-bundle");
    expect(markdown).not.toContain("2001:db8::42");
  });

  test("keeps handoff artifacts safe across normal missing and malformed wizard state", () => {
    const scenarios = [
      {
        name: "normal IPv4 wizard state",
        inputs: { ip: "203.0.113.42", os: "mac" as const, username: "ubuntu", mode: "vibe" as const, ref: null },
        expectedHostKind: "ipv4",
        expectedSourceRef: "main",
        rawHost: "203.0.113.42",
      },
      {
        name: "missing target host and invalid optional fields",
        inputs: { ip: "", os: "windows" as const, username: "bad user", mode: "safe" as const, ref: "bad ref" },
        expectedHostKind: "invalid_or_missing",
        expectedSourceRef: "main",
        rawHost: null,
      },
      {
        name: "malformed target host and legacy branch input",
        inputs: {
          ip: "192.0.2.10; rm -rf /",
          os: "linux" as const,
          username: "Admin;sudo",
          mode: "vibe" as const,
          ref: "master",
        },
        expectedHostKind: "invalid_or_missing",
        expectedSourceRef: "main",
        rawHost: "192.0.2.10",
      },
    ];

    for (const scenario of scenarios) {
      const runbook = buildHandoffRunbook(scenario.inputs);
      const json = serializeHandoffRunbookJson(runbook);
      const markdown = formatHandoffRunbookMarkdown(runbook);

      expect(runbook.targetHost.kind).toBe(scenario.expectedHostKind);
      expect(runbook.targetHost.value).not.toBe(scenario.rawHost);
      expect(runbook.wizardSelections.sourceRef).toBe(scenario.expectedSourceRef);
      expect(runbook.install.command).toContain(`/${scenario.expectedSourceRef}/install.sh`);
      expect(runbook.support.bundleCommand).toBe("acfs support-bundle");
      expect(runbook.support.reviewArtifacts).toEqual(["support-report.md", "manifest.json"]);
      expect(runbook.recoveryCommands.map((command) => command.command)).toContain("acfs support-bundle");
      for (const command of runbook.recoveryCommands) {
        expect(command.command).not.toMatch(/<[^>]+>/);
      }

      expectSafeHandoffArtifacts([json, markdown, ...runbook.recoveryCommands.map((command) => command.command)], scenario.rawHost);
    }
  });
});

describe("buildTeamProfile", () => {
  const generatedAt = "2026-05-08T00:00:00Z";

  test("exports normal wizard state as a deterministic redacted team profile", () => {
    const profile = buildTeamProfile({
      ip: "203.0.113.42",
      os: "mac",
      username: "dev-user",
      mode: "safe",
      ref: "v1.2.3",
      generatedAt,
      providerSelection: {
        providerId: "contabo",
        planName: "Cloud VPS 50",
        ubuntuVersion: "25.10",
        region: "us",
        targetAgents: 10,
        workloadId: "standard",
      },
      moduleSelection: {
        profile: "cloud-only",
      },
    });
    const json = serializeTeamProfileJson(profile);
    const review = formatTeamProfileReviewMarkdown(profile);

    expect(profile.schema).toBe("acfs.team-profile.v1");
    expect(profile.schemaVersion).toBe(1);
    expect(profile.profileId).toBe("contabo-safe-v1.2.3-acfs");
    expect(profile.providerDefaults).toMatchObject({
      provider: "contabo",
      region: "us",
      planClass: "Cloud VPS 50",
      operatingSystem: "ubuntu-25.10",
      sshUser: "dev-user",
      sshPort: 22,
    });
    expect(profile.install.profile).toBe("cloud-only");
    expect(profile.install.ref).toEqual({
      type: "tag",
      value: "v1.2.3",
      pinOnExport: true,
    });
    expect(profile.install.modulePlan.included).toContain("cloud.vercel");
    expect(profile.install.modulePlan.warnings).toContain(
      "Selected cloud modules may require live provider or CLI authentication after install.",
    );
    expect(review).toContain("# ACFS Team Profile Review");
    expect(review).toContain('--only "cloud.wrangler"');
    expect(json).not.toContain("203.0.113.42");
    expect(review).not.toContain("203.0.113.42");
  });

  test("falls back to safe defaults for empty or malformed wizard state", () => {
    const profile = buildTeamProfile({
      ip: "",
      os: "windows",
      username: "Bad User",
      mode: "vibe",
      ref: "bad ref",
      generatedAt,
      providerSelection: null,
    });
    const json = serializeTeamProfileJson(profile);

    expect(profile.profileId).toBe("other-vibe-main-acfs");
    expect(profile.providerDefaults.provider).toBe("other");
    expect(profile.providerDefaults.region).toBe("not-listed");
    expect(profile.providerDefaults.planClass).toBe("custom plan");
    expect(profile.providerDefaults.operatingSystem).toBe("ubuntu-25.10");
    expect(profile.providerDefaults.sshUser).toBe("ubuntu");
    expect(profile.install.ref.value).toBe("main");
    expect(profile.install.ref.type).toBe("branch");
    expect(profile.install.modules.noDeps).toBe(false);
    expect(profile.install.modulePlan.ok).toBe(true);
    expect(json).not.toContain("Bad User");
    expect(json).not.toContain("bad ref");
  });

  test("redacts credential-looking provider values before serialization", () => {
    const profile = buildTeamProfile({
      ip: "198.51.100.10",
      os: "linux",
      username: "admin",
      mode: "safe",
      ref: null,
      generatedAt,
      providerSelection: {
        providerId: "Bearer <credential>",
        planName: "postgres://<user>:<password>@example.invalid/db",
        ubuntuVersion: "25.10",
        region: "203.0.113.42",
        targetAgents: 4,
        workloadId: "light",
      },
    });
    const json = serializeTeamProfileJson(profile);

    expect(profile.providerDefaults.provider).toBe("other");
    expect(profile.providerDefaults.region).toBe("not-listed");
    expect(profile.providerDefaults.planClass).toBe("custom plan");
    expect(json).not.toContain("Bearer");
    expect(json).not.toContain("postgres://");
    expect(json).not.toContain("203.0.113.42");
    expect(json).not.toContain("198.51.100.10");
  });

  test("keeps safe unknown provider choices without weakening the schema", () => {
    const profile = buildTeamProfile({
      ip: "",
      os: "mac",
      username: "ubuntu",
      mode: "vibe",
      ref: "feature/team-profiles",
      generatedAt,
      providerSelection: {
        providerId: "Internal Dev Provider",
        planName: "Prototype Plan",
        ubuntuVersion: "24.04",
        region: "eu-central-1",
        targetAgents: 6,
        workloadId: "standard",
      },
    });

    expect(profile.providerDefaults.provider).toBe("internal-dev-provider");
    expect(profile.providerDefaults.region).toBe("eu-central-1");
    expect(profile.providerDefaults.planClass).toBe("Prototype Plan");
    expect(profile.compatibility.targetUbuntuVersions).toEqual(["24.04"]);
    expect(profile.install.ref).toEqual({
      type: "branch",
      value: "feature/team-profiles",
      pinOnExport: true,
    });
  });

  test("emits v1 schema provenance and secret-slot metadata only", () => {
    const profile = buildTeamProfile({
      ip: "",
      os: "linux",
      username: "ubuntu",
      mode: "vibe",
      ref: null,
      generatedAt,
    });

    expect(profile.schema).toBe("acfs.team-profile.v1");
    expect(profile.schemaVersion).toBe(1);
    expect(profile.provenance.source.manifestSha256).toMatch(/^[a-f0-9]{64}$/);
    expect(profile.provenance.source.checksumsYamlSha256).toMatch(/^[a-f0-9]{64}$/);
    expect(profile.redaction.allowSecretValues).toBe(false);
    expect(profile.redaction.secretSlotsRequired).toBe(true);
    expect(profile.serviceAccounts.every((account) => account.secretSlot.startsWith("secret://acfs/team/"))).toBe(true);
  });
});

describe("buildTeamProfileImportDiff", () => {
  const generatedAt = "2026-05-08T00:00:00Z";

  function sampleProfile() {
    return buildTeamProfile({
      ip: "203.0.113.42",
      os: "mac",
      username: "dev-user",
      mode: "safe",
      ref: "v1.2.3",
      generatedAt,
      providerSelection: {
        providerId: "contabo",
        planName: "Cloud VPS 50",
        ubuntuVersion: "25.10",
        region: "us",
        targetAgents: 10,
        workloadId: "standard",
      },
      moduleSelection: {
        profile: "cloud-only",
      },
    });
  }

  test("builds a machine-readable dry-run diff for a compatible profile", () => {
    const diff = buildTeamProfileImportDiff(sampleProfile(), {
      providerSelection: {
        providerId: "other",
        planName: "custom plan",
        region: "not-listed",
      },
      installMode: "vibe",
      ref: null,
      username: "ubuntu",
      moduleSelection: { profile: "full" },
    });
    const json = serializeTeamProfileImportDiffJson(diff);
    const markdown = formatTeamProfileImportDiffMarkdown(diff);

    expect(diff.schema).toBe("acfs.team-profile-import-diff.v1");
    expect(diff.dryRun).toBe(true);
    expect(diff.ok).toBe(true);
    expect(diff.safeDefaults.changes.map((change) => change.field)).toContain("providerDefaults.provider");
    expect(diff.installerCommand.command).toContain('--ref "v1.2.3"');
    expect(diff.installerCommand.command).toContain('--only "cloud.wrangler"');
    expect(diff.secretSlots.required).toEqual(["secret://acfs/team/github-auth"]);
    expect(json).toContain("\"dryRun\": true");
    expect(markdown).toContain("Status: ready");
    expect(markdown).toContain("## Installer Command");
  });

  test("blocks newer schemas before exposing profile contents", () => {
    const profile = {
      ...sampleProfile(),
      schemaVersion: 2,
    };
    const diff = buildTeamProfileImportDiff(profile);

    expect(diff.ok).toBe(false);
    expect(diff.profile).toBeNull();
    expect(diff.incompatibilities.map((finding) => finding.code)).toContain("team_profile_schema_unsupported");
    expect(diff.installerCommand.command).toBeNull();
  });

  test("reports missing required fields without generating commands", () => {
    const profile = sampleProfile();
    const incomplete = {
      ...profile,
      providerDefaults: {
        ...profile.providerDefaults,
      },
    };
    delete (incomplete.providerDefaults as Partial<typeof incomplete.providerDefaults>).provider;

    const diff = buildTeamProfileImportDiff(incomplete);

    expect(diff.ok).toBe(false);
    expect(diff.profile).toBeNull();
    expect(diff.findings).toContainEqual(expect.objectContaining({
      code: "team_profile_missing_required_field",
      path: "providerDefaults.provider",
    }));
    expect(diff.installerCommand.command).toBeNull();
  });

  test("refuses secret-bearing profiles without echoing credential-like values", () => {
    const credentialLikeValue = ["Bea", "rer <credential>"].join("");
    const profile = {
      ...sampleProfile(),
      extensions: {
        providerToken: credentialLikeValue,
      },
    };
    const diff = buildTeamProfileImportDiff(profile);
    const json = serializeTeamProfileImportDiffJson(diff);

    expect(diff.ok).toBe(false);
    expect(diff.profile).toBeNull();
    expect(diff.refusals.map((finding) => finding.code)).toContain("team_profile_forbidden_field");
    expect(diff.refusals.map((finding) => finding.code)).toContain("team_profile_secret_material_refused");
    expect(json).not.toContain("Bearer");
    expect(json).not.toContain("<credential>");
  });

  test("rejects invalid import refs before building a command preview", () => {
    const malformedRef = "feature/test;touch /tmp/acfs";
    const profile = {
      ...sampleProfile(),
      install: {
        ...sampleProfile().install,
        ref: {
          ...sampleProfile().install.ref,
          value: malformedRef,
        },
      },
    };
    const diff = buildTeamProfileImportDiff(profile);
    const json = serializeTeamProfileImportDiffJson(diff);

    expect(diff.ok).toBe(false);
    expect(diff.profile).toBeNull();
    expect(diff.incompatibilities).toContainEqual(expect.objectContaining({
      code: "team_profile_schema_unsupported",
      path: "install.ref.value",
    }));
    expect(diff.installerCommand.command).toBeNull();
    expect(json).not.toContain(malformedRef);
  });

  test("rejects malformed credential-slot placeholders before exposing import details", () => {
    const rawCredential = ["Bea", "rer should-not-appear"].join("");
    const profile = {
      ...sampleProfile(),
      serviceAccounts: [
        {
          ...sampleProfile().serviceAccounts[0],
          secretSlot: rawCredential,
        },
      ],
    };
    const diff = buildTeamProfileImportDiff(profile);
    const json = serializeTeamProfileImportDiffJson(diff);

    expect(diff.ok).toBe(false);
    expect(diff.profile).toBeNull();
    expect(diff.refusals).toContainEqual(expect.objectContaining({
      code: "team_profile_secret_material_refused",
      path: "serviceAccounts.0.secretSlot",
    }));
    expect(diff.installerCommand.command).toBeNull();
    expect(json).not.toContain(rawCredential);
  });

  test("shows provider mismatches as safe default changes", () => {
    const diff = buildTeamProfileImportDiff(sampleProfile(), {
      providerSelection: {
        providerId: "hetzner",
        planName: "CX51",
        region: "eu-central",
      },
      installMode: "safe",
      ref: "v1.2.3",
      username: "dev-user",
      moduleSelection: { profile: "cloud-only" },
    });

    expect(diff.ok).toBe(true);
    expect(diff.safeDefaults.changes).toContainEqual({
      field: "providerDefaults.provider",
      current: "hetzner",
      next: "contabo",
    });
    expect(diff.safeDefaults.changes).toContainEqual({
      field: "providerDefaults.planClass",
      current: "CX51",
      next: "Cloud VPS 50",
    });
    expect(diff.installerCommand.changes).toEqual([]);
  });

  test("blocks dry-run command output when module selectors are incompatible", () => {
    const profile = {
      ...sampleProfile(),
      install: {
        ...sampleProfile().install,
        profile: "full",
        modules: {
          only: ["not.real"],
          onlyPhases: [],
          skip: [],
          noDeps: false,
        },
      },
    };
    const diff = buildTeamProfileImportDiff(profile);
    const markdown = formatTeamProfileImportDiffMarkdown(diff);

    expect(diff.ok).toBe(false);
    expect(diff.incompatibilities.map((finding) => finding.code)).toContain("team_profile_unknown_module");
    expect(diff.installerCommand.command).toBeNull();
    expect(markdown).toContain("Blocked until incompatibilities and refusals are resolved.");
  });

  test("blocks unknown module selection profiles instead of silently falling back to full", () => {
    const profile = {
      ...sampleProfile(),
      install: {
        ...sampleProfile().install,
        profile: "not-a-real-profile",
      },
    };
    const diff = buildTeamProfileImportDiff(profile);

    expect(diff.ok).toBe(false);
    expect(diff.incompatibilities).toContainEqual(expect.objectContaining({
      code: "team_profile_unknown_module",
      path: "install.profile",
    }));
    expect(diff.installerCommand.command).toBeNull();
  });
});

describe("buildShareURL", () => {
  test("drops unrelated query params from the current page URL", () => {
    const originalWindow = globalThis.window;

    Object.defineProperty(globalThis, "window", {
      value: {
        location: {
          href: "https://acfs.dev/wizard/launch-onboarding?utm_source=share",
          origin: "https://acfs.dev",
          pathname: "/wizard/launch-onboarding",
        },
      },
      configurable: true,
    });

    try {
      const shareURL = buildShareURL({
        ip: "10.20.30.40",
        os: "mac",
        username: "ubuntu",
        mode: "vibe",
        ref: null,
      });

      expect(shareURL).toBe("https://acfs.dev/wizard/launch-onboarding?ip=10.20.30.40&os=mac&mode=vibe");
      expect(shareURL).not.toContain("utm_source=");
    } finally {
      Object.defineProperty(globalThis, "window", {
        value: originalWindow,
        configurable: true,
      });
    }
  });

  test("drops usernames that the installer would reject", () => {
    const originalWindow = globalThis.window;

    Object.defineProperty(globalThis, "window", {
      value: {
        location: {
          href: "https://acfs.dev/wizard/launch-onboarding",
          origin: "https://acfs.dev",
          pathname: "/wizard/launch-onboarding",
        },
      },
      configurable: true,
    });

    try {
      const shareURL = buildShareURL({
        ip: "10.20.30.40",
        os: "linux",
        username: "Admin",
        mode: "safe",
        ref: null,
      });

      expect(shareURL).toBe("https://acfs.dev/wizard/launch-onboarding?ip=10.20.30.40&os=linux&mode=safe");
    } finally {
      Object.defineProperty(globalThis, "window", {
        value: originalWindow,
        configurable: true,
      });
    }
  });
});
