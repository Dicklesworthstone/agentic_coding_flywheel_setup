import { strict as assert } from "node:assert";
import { test } from "node:test";
import {
  buildTeamProfile,
  buildTeamProfileImportDiff,
  formatTeamProfileImportDiffMarkdown,
  formatTeamProfileReviewMarkdown,
  serializeTeamProfileJson,
  type TeamProfileInputs,
} from "./commandBuilder";
import { ACFS_RECOMMENDED_UBUNTU, VPS_UBUNTU_IMAGE_OPTIONS } from "./vpsProviders";

function inputs(ubuntuVersion?: string): TeamProfileInputs {
  return {
    ip: "203.0.113.42",
    os: "linux",
    username: "dev-user",
    mode: "safe",
    ref: "a1b6c2f34aac7596e676688c36cb57cbbb869f3c",
    generatedAt: "2026-09-17T00:00:00Z",
    moduleSelection: { onlyModules: ["lang.bun"] },
    ...(ubuntuVersion === undefined
      ? {}
      : {
          providerSelection: {
            providerId: "other",
            planName: "custom plan",
            ubuntuVersion,
            region: "not-listed",
            targetAgents: 10,
            workloadId: "standard" as const,
          },
        }),
  };
}
const blockedText = "Blocked until incompatibilities and refusals are resolved.";

function assertBlockedProfile(version: string): void {
  const profile = buildTeamProfile(inputs(version));
  const before = serializeTeamProfileJson(profile);
  const diff = buildTeamProfileImportDiff(profile, { ubuntuVersion: version });
  const review = formatTeamProfileReviewMarkdown(profile);
  assert.equal(profile.install.modulePlan.ok, false);
  assert.ok(profile.install.modulePlan.errors.length > 0);
  assert.equal(diff.ok, false);
  assert.equal(diff.installerCommand.command, null);
  assert.ok(review.includes(blockedText));
  assert.ok(!review.includes("curl -fsSL"));
  assert.ok(formatTeamProfileImportDiffMarkdown(diff).includes(blockedText));
  assert.equal(
    serializeTeamProfileJson(profile),
    before,
    "review/import must not rewrite the selected image",
  );
}

test("new default profiles use the same LTS recommendation as install commands", () => {
  const profile = buildTeamProfile(inputs());
  assert.equal(profile.providerDefaults.operatingSystem, `ubuntu-${ACFS_RECOMMENDED_UBUNTU}`);
  assert.deepEqual(profile.compatibility.targetUbuntuVersions, [ACFS_RECOMMENDED_UBUNTU]);
  assert.equal(profile.install.modulePlan.ok, true);
  const diff = buildTeamProfileImportDiff(profile);
  assert.equal(diff.ok, true, JSON.stringify(diff.findings));
  assert.ok(diff.installerCommand.command?.includes("--target-ubuntu=26.04"));
  assert.ok(!serializeTeamProfileJson(profile).includes("203.0.113.42"));
});

for (const version of VPS_UBUNTU_IMAGE_OPTIONS) {
  test(`preserves reviewed starting image ${version} while explicitly targeting the recommended LTS`, () => {
    const profile = buildTeamProfile(inputs(version));
    const diff = buildTeamProfileImportDiff(profile, {
      providerSelection: { ubuntuVersion: version },
      ref: profile.install.ref.value,
      username: profile.providerDefaults.sshUser,
      moduleSelection: { onlyModules: ["lang.bun"] },
    });
    assert.equal(profile.providerDefaults.operatingSystem, `ubuntu-${version}`);
    assert.deepEqual(profile.compatibility.targetUbuntuVersions, [version]);
    assert.equal(profile.install.modulePlan.ok, true);
    assert.equal(diff.ok, true, JSON.stringify(diff.findings));
    assert.ok(
      !diff.safeDefaults.changes.some(
        (change) => change.field === "providerDefaults.operatingSystem",
      ),
    );
    assert.ok(diff.installerCommand.command?.includes("--target-ubuntu=26.04"));
    assert.ok(diff.installerCommand.command?.includes('--only "lang.bun"'));
    assert.ok(diff.installerCommand.command?.includes(`--ref "${profile.install.ref.value}"`));
    const review = formatTeamProfileReviewMarkdown(profile);
    assert.ok(review.includes(`Operating system: ubuntu-${version}`));
    assert.ok(review.includes("Installer destination: Ubuntu 26.04 LTS"));
    assert.ok(review.includes("curl -fsSL"));
    assert.ok(!review.includes(blockedText));
    assert.equal(
      profile.install.modulePlan.warnings.some((warning) =>
        warning.includes("upgrades and reboots"),
      ),
      version !== ACFS_RECOMMENDED_UBUNTU,
    );
  });
}

for (const version of ["25.10", "25.04", "24.10", "20.04", "26.10", "99.99"]) {
  test(`unsupported source ${version} is preserved but cannot produce a runnable profile`, () => {
    assertBlockedProfile(version);
    const profile = buildTeamProfile(inputs(version));
    assert.equal(profile.providerDefaults.operatingSystem, `ubuntu-${version}`);
    assert.deepEqual(profile.compatibility.targetUbuntuVersions, [version]);
  });
}

for (const version of [
  "",
  "   ",
  "Debian 26.04",
  "26.04; touch /tmp/INJECTED",
  "Bearer PRIVATE_VALUE",
  "203.0.113.42",
]) {
  test(`malformed saved source ${JSON.stringify(version)} is blocked instead of silently approved`, () => {
    assertBlockedProfile(version);
    const profile = buildTeamProfile(inputs(version));
    assert.equal(profile.providerDefaults.operatingSystem, "ubuntu-unreviewed");
    const serialized = serializeTeamProfileJson(profile);
    assert.ok(!serialized.includes("PRIVATE_VALUE"));
    assert.ok(!serialized.includes("INJECTED"));
    assert.ok(!serialized.includes("203.0.113.42"));
  });
}

test("missing provider state defaults safely, unlike a saved explicitly empty release", () => {
  const profile = buildTeamProfile({ ...inputs(), providerSelection: null });
  assert.equal(buildTeamProfileImportDiff(profile).ok, true);
  assertBlockedProfile("");
});

for (const version of ["25.10", "26.10", "99.99"]) {
  test(`a mixed compatibility list cannot hide unreviewed ${version} behind a valid current image`, () => {
    const profile = buildTeamProfile(inputs("26.04"));
    profile.compatibility.targetUbuntuVersions.push(version);
    const diff = buildTeamProfileImportDiff(profile, { ubuntuVersion: "26.04" });
    assert.equal(diff.ok, false);
    assert.equal(diff.installerCommand.command, null);
    assert.ok(
      diff.findings.some(
        (finding) =>
          finding.code === "team_profile_ubuntu_unsupported" &&
          finding.path === "compatibility.targetUbuntuVersions",
      ),
    );
    assert.ok(!formatTeamProfileReviewMarkdown(profile).includes("curl -fsSL"));
  });
}

test("accepts an explicitly reviewed list of supported LTS starting images", () => {
  const profile = buildTeamProfile(inputs("24.04"));
  profile.compatibility.targetUbuntuVersions = [...VPS_UBUNTU_IMAGE_OPTIONS];
  for (const ubuntuVersion of VPS_UBUNTU_IMAGE_OPTIONS) {
    const diff = buildTeamProfileImportDiff(profile, { providerSelection: { ubuntuVersion } });
    assert.equal(diff.ok, true, JSON.stringify(diff.findings));
    assert.ok(diff.installerCommand.command?.includes("--target-ubuntu=26.04"));
  }
});

test("saved provider image participates in import compatibility when explicit current OS is absent", () => {
  const profile = buildTeamProfile(inputs("26.04"));
  const diff = buildTeamProfileImportDiff(profile, {
    providerSelection: { ubuntuVersion: "24.04" },
  });
  assert.equal(diff.ok, false);
  assert.equal(diff.installerCommand.command, null);
  assert.ok(diff.findings.some((finding) => finding.code === "team_profile_ubuntu_unsupported"));
  assert.ok(
    diff.safeDefaults.changes.some(
      (change) =>
        change.field === "providerDefaults.operatingSystem" &&
        change.current === "ubuntu-24.04" &&
        change.next === "ubuntu-26.04",
    ),
  );
});

test("an explicit current OS takes precedence over saved provider image metadata", () => {
  const profile = buildTeamProfile(inputs("26.04"));
  const diff = buildTeamProfileImportDiff(profile, {
    ubuntuVersion: "26.04",
    providerSelection: { ubuntuVersion: "24.04" },
  });
  assert.equal(diff.ok, true, JSON.stringify(diff.findings));
  assert.ok(
    !diff.safeDefaults.changes.some(
      (change) => change.field === "providerDefaults.operatingSystem",
    ),
  );
});

test("an unsupported current source is refused even when package defaults are valid", () => {
  const profile = buildTeamProfile(inputs("26.04"));
  const diff = buildTeamProfileImportDiff(profile, {
    providerSelection: { ubuntuVersion: "25.10" },
  });
  assert.equal(diff.ok, false);
  assert.equal(diff.installerCommand.command, null);
  assert.ok(
    diff.findings.some(
      (finding) =>
        finding.code === "team_profile_ubuntu_unsupported" &&
        finding.path === "current.ubuntuVersion",
    ),
  );
});

test("tampering with cached success flags cannot approve an unsupported release", () => {
  const profile = buildTeamProfile(inputs("25.10"));
  profile.install.modulePlan.ok = true;
  profile.install.modulePlan.errors = [];
  const diff = buildTeamProfileImportDiff(profile, { ubuntuVersion: "25.10" });
  assert.equal(diff.ok, false);
  assert.equal(diff.installerCommand.command, null);
  assert.ok(!formatTeamProfileReviewMarkdown(profile).includes("curl -fsSL"));
});

test("provider defaults cannot name an unsupported release even if compatibility lists the recommended LTS", () => {
  const profile = buildTeamProfile(inputs("26.04"));
  profile.providerDefaults.operatingSystem = "ubuntu-25.10";
  const diff = buildTeamProfileImportDiff(profile);
  assert.equal(diff.installerCommand.command, null);
  assert.ok(
    diff.findings.some(
      (finding) =>
        finding.path === "providerDefaults.operatingSystem" &&
        finding.code === "team_profile_ubuntu_unsupported",
    ),
  );
});

test("profile review revalidates selectors without throwing or printing a runnable command", () => {
  const profile = buildTeamProfile({
    ...inputs("26.04"),
    moduleSelection: { onlyModules: ["not.real"] },
  });
  const review = formatTeamProfileReviewMarkdown(profile);
  assert.ok(review.includes(blockedText));
  assert.ok(!review.includes("curl -fsSL"));
  assert.equal(profile.install.modulePlan.ok, false);
});

test("profile review refuses stale checksum provenance even if the cached module plan says ready", () => {
  const profile = buildTeamProfile(inputs("26.04"));
  profile.provenance.source.checksumsYamlSha256 = "f".repeat(64);
  assert.equal(profile.install.modulePlan.ok, true);
  const review = formatTeamProfileReviewMarkdown(profile);
  assert.ok(review.includes(blockedText));
  assert.ok(!review.includes("curl -fsSL"));
});
