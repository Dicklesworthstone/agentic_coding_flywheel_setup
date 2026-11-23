/** Full-checkout contract: real canonical validators, catalogue, and command generation. */
import { strict as assert } from "node:assert";
import { test } from "node:test";
import {
  buildInstallCommand,
  buildTeamProfile,
  buildTeamProfileImportDiff,
  formatTeamProfileReviewMarkdown,
  serializeTeamProfileJson,
  type TeamProfileInputs,
} from "./commandBuilder";
import { resolveModuleSelection } from "./moduleSelection";
import {
  activateTeamProfileInstallation,
  approveTeamProfileReview,
  reviewTeamProfileFile,
  TeamProfileImportError,
  type TeamProfileReviewContext,
} from "./teamProfileImport";

function sessionStorage() {
  const entries = new Map<string, string>();
  return {
    getItem: (key: string) => entries.get(key) ?? null,
    setItem: (key: string, value: string) => { entries.set(key, value); },
    removeItem: (key: string) => { entries.delete(key); },
  };
}

function inputs(): TeamProfileInputs {
  return {
    ip: "203.0.113.7",
    os: "linux",
    username: "dev-user",
    mode: "safe",
    ref: "v1.2.3",
    generatedAt: "2026-09-17T00:00:00Z",
    architecture: "x86_64",
    moduleSelection: { profile: "full", skipTags: ["maintenance"], skipCategories: ["cloud"] },
  };
}
function context(): TeamProfileReviewContext {
  return {
    targetHost: "203.0.113.7",
    current: {
      installMode: "vibe",
      username: "ubuntu",
      ref: null,
      architecture: "x86_64",
      ubuntuVersion: "26.04",
      moduleSelection: { profile: "full" },
    },
  };
}
function expectedCommand(profile: ReturnType<typeof buildTeamProfile>): string {
  // Export canonically sorts exact skips; compare the command to those stored
  // selectors, not the input group's possibly different enumeration order.
  return buildInstallCommand(
    profile.install.mode,
    profile.install.ref.value,
    profile.providerDefaults.sshUser,
    {
      profile: profile.install.profile,
      onlyModules: profile.install.modules.only,
      onlyPhases: profile.install.modules.onlyPhases,
      skipModules: profile.install.modules.skip,
      noDeps: false,
    },
  );
}

test("canonical profile export, bounded file review, and approval preserve the exact narrowed command", async () => {
  const requested = inputs();
  const profile = buildTeamProfile(requested);
  const json = serializeTeamProfileJson(profile);
  const current = context();
  const review = await reviewTeamProfileFile(new Blob([json]), current);
  assert.equal(review.diff.ok, true);
  assert.equal(review.diff.installerCommand.command, null);
  assert.ok(review.diff.skips.requested.includes("acfs.nightly"));
  assert.ok(review.diff.skips.requested.includes("cloud.wrangler"));
  const result = approveTeamProfileReview(review, current, true);
  assert.equal(result.command, expectedCommand(profile));
  const originalPlan = resolveModuleSelection(requested.moduleSelection);
  assert.equal(originalPlan.ok, true);
  assert.deepEqual(
    profile.install.modulePlan.included,
    originalPlan.included.map((entry) => entry.id),
  );
  assert.equal(
    serializeTeamProfileJson(profile),
    json,
    "ingestion must not alter the source profile",
  );
});

test("canonical checksum, selection, architecture and dependency-policy refusals prevent file approval", async () => {
  for (const mutation of ["checksums", "module", "architecture", "noDeps"]) {
    const profile = buildTeamProfile(inputs());
    if (mutation === "checksums") profile.provenance.source.checksumsYamlSha256 = "f".repeat(64);
    if (mutation === "module") profile.install.modules.only = ["agents.not_real"];
    if (mutation === "architecture") profile.compatibility.architectures = ["aarch64"];
    if (mutation === "noDeps") Object.assign(profile.install.modules, { noDeps: true });
    await assert.rejects(
      reviewTeamProfileFile(new Blob([serializeTeamProfileJson(profile)]), context()),
      (error: unknown) =>
        error instanceof TeamProfileImportError && error.code === "team_profile_review_blocked",
      mutation,
    );
  }
});

test("commands in allowed extension data cannot substitute for canonical command generation", async () => {
  const requested = inputs();
  const profile = {
    ...buildTeamProfile(requested),
    extensions: { command: "echo not-the-approved-installer" },
  };
  const current = context();
  const review = await reviewTeamProfileFile(new Blob([JSON.stringify(profile)]), current);
  const approved = approveTeamProfileReview(review, current, true);
  assert.equal(approved.command, expectedCommand(profile));
  assert.ok(!approved.command.includes("not-the-approved-installer"));
});

test("a real canonical review is not transferable to another VPS or deserialized review", async () => {
  const current = context();
  const review = await reviewTeamProfileFile(
    new Blob([serializeTeamProfileJson(buildTeamProfile(inputs()))]),
    current,
  );
  assert.throws(
    () => approveTeamProfileReview(review, { ...current, targetHost: "203.0.113.8" }, true),
    (error: unknown) =>
      error instanceof TeamProfileImportError && error.code === "team_profile_review_changed",
  );
  assert.throws(
    () => approveTeamProfileReview(structuredClone(review), current, true),
    (error: unknown) =>
      error instanceof TeamProfileImportError && error.code === "team_profile_review_changed",
  );
});

for (const architecture of ["x86_64", "aarch64"] as const) {
  test(`review, adoption, and export retain the approved ${architecture}-only target policy`, async () => {
    const requested = inputs();
    const source = buildTeamProfile({ ...requested, architecture });
    source.compatibility.architectures = [architecture];
    source.compatibility.targetUbuntuVersions = ["24.04", "26.04"];
    const before = serializeTeamProfileJson(source);
    const current = context();
    current.current.architecture = architecture;
    current.current.ubuntuVersion = "24.04";
    const review = await reviewTeamProfileFile(new Blob([before]), current);
    const installation = activateTeamProfileInstallation(review, current, true, sessionStorage());
    const exported = buildTeamProfile({
      ...requested,
      mode: installation.mode,
      ref: installation.ref,
      username: installation.username,
      architecture: installation.architecture,
      moduleSelection: installation.moduleSelection,
      compatibilityTargets: installation.compatibilityTargets,
      providerSelection: {
        providerId: "other", planName: "custom plan", region: "not-listed",
        targetAgents: 10, workloadId: "standard", ubuntuVersion: installation.ubuntuVersion,
      },
    });
    assert.deepEqual(exported.compatibility.architectures, [architecture]);
    assert.deepEqual(exported.compatibility.targetUbuntuVersions, ["24.04", "26.04"]);
    assert.equal(exported.providerDefaults.operatingSystem, "ubuntu-24.04");
    assert.equal(expectedCommand(exported), installation.command);
    assert.deepEqual(exported.install.modulePlan.included, source.install.modulePlan.included);
    assert.equal(serializeTeamProfileJson(source), before);
    assert.throws(() => {
      (installation.compatibilityTargets.architectures as string[]).push("other");
    }, TypeError);
    const retained = await reviewTeamProfileFile(new Blob([serializeTeamProfileJson(exported)]), current);
    assert.equal(approveTeamProfileReview(retained, current, true).command, installation.command);
    const otherArchitecture = architecture === "x86_64" ? "aarch64" : "x86_64";
    await assert.rejects(
      reviewTeamProfileFile(new Blob([serializeTeamProfileJson(exported)]), {
        ...current,
        current: { ...current.current, architecture: otherArchitecture },
      }),
      (error: unknown) => error instanceof TeamProfileImportError &&
        error.findingCodes.includes("team_profile_arch_unsupported"),
    );
    await assert.rejects(
      reviewTeamProfileFile(new Blob([serializeTeamProfileJson(exported)]), {
        ...current,
        current: { ...current.current, ubuntuVersion: "22.04" },
      }),
      (error: unknown) => error instanceof TeamProfileImportError &&
        error.findingCodes.includes("team_profile_ubuntu_unsupported"),
    );
  });
}

for (const [name, offlinePack] of [
  ["required cache", { required: true, pathHint: null }],
  ["cache path", { required: false, pathHint: "acfs-installer-cache" }],
  ["missing required policy", { pathHint: null }],
  ["nonboolean required policy", { required: "false", pathHint: null }],
  ["missing path policy", { required: false }],
  ["unknown cache policy", { required: false, pathHint: null, offline: true }],
  ["null cache policy", null],
  ["array cache policy", []],
] as const) {
  test(`a profile with ${name} cannot be approved as an ordinary network install`, async () => {
    const source = buildTeamProfile(inputs());
    Object.assign(source.install, { offlinePack });
    const before = serializeTeamProfileJson(source);
    const diff = buildTeamProfileImportDiff(source, context().current);
    assert.equal(diff.ok, false);
    assert.equal(diff.installerCommand.command, null);
    assert.ok(diff.findings.some((finding) => finding.code === "team_profile_offline_unsupported"));
    assert.ok(!formatTeamProfileReviewMarkdown(source).includes("curl -fsSL"));
    await assert.rejects(
      reviewTeamProfileFile(new Blob([before]), context()),
      (error: unknown) => error instanceof TeamProfileImportError &&
        error.code === "team_profile_review_blocked" &&
        error.findingCodes.includes("team_profile_offline_unsupported"),
    );
    assert.equal(serializeTeamProfileJson(source), before);
  });
}

test("absent and explicit optional-cache metadata keep the supported network handoff", async () => {
  const exported = buildTeamProfile(inputs());
  const { offlinePack, ...withoutCache } = exported.install;
  assert.deepEqual(offlinePack, { required: false, pathHint: null });
  for (const install of [exported.install, withoutCache]) {
    const source = { ...exported, install };
    const current = context();
    const review = await reviewTeamProfileFile(new Blob([JSON.stringify(source)]), current);
    assert.equal(approveTeamProfileReview(review, current, true).command, expectedCommand(exported));
  }
});

for (const [name, compatibilityTargets] of [
  ["null policy", null],
  ["missing architecture list", { targetUbuntuVersions: ["26.04"] }],
  ["empty architecture list", { architectures: [], targetUbuntuVersions: ["26.04"] }],
  ["unknown architecture", { architectures: ["other"], targetUbuntuVersions: ["26.04"] }],
  ["excluded architecture", { architectures: ["aarch64"], targetUbuntuVersions: ["26.04"] }],
  ["missing image list", { architectures: ["x86_64"] }],
  ["empty image list", { architectures: ["x86_64"], targetUbuntuVersions: [] }],
  ["unsupported image", { architectures: ["x86_64"], targetUbuntuVersions: ["99.99"] }],
  ["excluded image", { architectures: ["x86_64"], targetUbuntuVersions: ["24.04"] }],
] as const) {
  test(`re-export cannot replace a ${name} with broader target defaults`, () => {
    assert.throws(
      () => buildTeamProfile({
        ...inputs(),
        compatibilityTargets: compatibilityTargets as unknown as TeamProfileInputs["compatibilityTargets"],
      }),
      /approved profile's compatibility targets/,
    );
  });
}
