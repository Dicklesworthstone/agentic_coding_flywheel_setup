/** Full-checkout contract: real canonical validators, catalogue, and command generation. */
import { strict as assert } from "node:assert";
import { test } from "node:test";
import {
  buildInstallCommand, buildTeamProfile, serializeTeamProfileJson,
  type TeamProfileInputs,
} from "./commandBuilder";
import { resolveModuleSelection } from "./moduleSelection";
import {
  approveTeamProfileReview, reviewTeamProfileFile, TeamProfileImportError,
  type TeamProfileReviewContext,
} from "./teamProfileImport";

function inputs(): TeamProfileInputs {
  return {
    ip: "203.0.113.7", os: "linux", username: "dev-user", mode: "safe", ref: "v1.2.3",
    generatedAt: "2026-09-17T00:00:00Z", architecture: "x86_64",
    moduleSelection: { profile: "full", skipTags: ["maintenance"], skipCategories: ["cloud"] },
  };
}
function context(): TeamProfileReviewContext {
  return { targetHost: "203.0.113.7", current: {
    installMode: "vibe", username: "ubuntu", ref: null, architecture: "x86_64",
    ubuntuVersion: "26.04", moduleSelection: { profile: "full" },
  } };
}
function expectedCommand(profile: ReturnType<typeof buildTeamProfile>): string {
  // Export canonically sorts exact skips; compare the command to those stored
  // selectors, not the input group's possibly different enumeration order.
  return buildInstallCommand(profile.install.mode, profile.install.ref.value,
    profile.providerDefaults.sshUser, { profile: profile.install.profile,
      onlyModules: profile.install.modules.only, onlyPhases: profile.install.modules.onlyPhases,
      skipModules: profile.install.modules.skip, noDeps: false });
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
  assert.deepEqual(profile.install.modulePlan.included, originalPlan.included.map((entry) => entry.id));
  assert.equal(serializeTeamProfileJson(profile), json, "ingestion must not alter the source profile");
});

test("canonical checksum, selection, architecture and dependency-policy refusals prevent file approval", async () => {
  for (const mutation of ["checksums", "module", "architecture", "noDeps"]) {
    const profile = buildTeamProfile(inputs());
    if (mutation === "checksums") profile.provenance.source.checksumsYamlSha256 = "f".repeat(64);
    if (mutation === "module") profile.install.modules.only = ["agents.not_real"];
    if (mutation === "architecture") profile.compatibility.architectures = ["aarch64"];
    if (mutation === "noDeps") Object.assign(profile.install.modules, { noDeps: true });
    await assert.rejects(reviewTeamProfileFile(new Blob([serializeTeamProfileJson(profile)]), context()),
      (error: unknown) => error instanceof TeamProfileImportError && error.code === "team_profile_review_blocked",
      mutation);
  }
});

test("commands in allowed extension data cannot substitute for canonical command generation", async () => {
  const requested = inputs();
  const profile = { ...buildTeamProfile(requested), extensions: { command: "echo not-the-approved-installer" } };
  const current = context();
  const review = await reviewTeamProfileFile(new Blob([JSON.stringify(profile)]), current);
  const approved = approveTeamProfileReview(review, current, true);
  assert.equal(approved.command, expectedCommand(profile));
  assert.ok(!approved.command.includes("not-the-approved-installer"));
});

test("a real canonical review is not transferable to another VPS or deserialized review", async () => {
  const current = context();
  const review = await reviewTeamProfileFile(new Blob([serializeTeamProfileJson(buildTeamProfile(inputs()))]), current);
  assert.throws(() => approveTeamProfileReview(review, { ...current, targetHost: "203.0.113.8" }, true),
    (error: unknown) => error instanceof TeamProfileImportError && error.code === "team_profile_review_changed");
  assert.throws(() => approveTeamProfileReview(structuredClone(review), current, true),
    (error: unknown) => error instanceof TeamProfileImportError && error.code === "team_profile_review_changed");
});
