import { strict as assert } from "node:assert";
import { execFileSync } from "node:child_process";
import { test } from "node:test";
import {
  buildHandoffRunbook,
  buildInstallCommand,
  buildTeamProfile,
  buildTeamProfileImportDiff,
  formatTeamProfileReviewMarkdown,
  serializeTeamProfileJson,
  type TeamProfileInputs,
} from "./commandBuilder";
import { lowerModuleSelectionGroups, resolveModuleSelection, type ModuleSelectionInput } from "./moduleSelection";
import { manifestModules, manifestSelectionProfiles } from "./generated/manifest-modules";

const inputs = (moduleSelection: ModuleSelectionInput = {}): TeamProfileInputs => ({
  ip: "203.0.113.7", os: "linux", username: "dev-user", mode: "safe", ref: "v1.2.3",
  generatedAt: "2026-09-17T00:00:00Z", moduleSelection,
});
const ids = (selection: ModuleSelectionInput): string[] => {
  const plan = resolveModuleSelection(selection);
  assert.equal(plan.ok, true, plan.errors.join("\n"));
  return plan.included.map((entry) => entry.id);
};
function commandSelection(command: string): ModuleSelectionInput {
  // The real generated curl|bash string receives a harmless argument printer.
  // No download, installer, host mutation, or dependency command is executed.
  const prefix = "curl() { printf '%s\\n' '#!/bin/bash' 'printf \"%s\\0\" \"$@\"'; }; ";
  const args = execFileSync("/bin/bash", ["-c", prefix + command]).toString().split("\0").filter(Boolean);
  const result: ModuleSelectionInput = { onlyModules: [], onlyPhases: [], skipModules: [] };
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (arg === "--only") result.onlyModules!.push(args[++index]!);
    else if (arg === "--only-phase") result.onlyPhases!.push(args[++index]!);
    else if (arg === "--skip") result.skipModules!.push(args[++index]!);
    else if (arg === "--profile") result.profile = args[++index] as ModuleSelectionInput["profile"];
    else if (arg === "--no-deps") result.noDeps = true;
    else if (arg === "--mode" || arg === "--ref") index++;
    else assert.ok(arg === "--yes" || arg === "--target-ubuntu=26.04", `Unexpected argument: ${arg}`);
  }
  return result;
}

for (const profile of manifestSelectionProfiles) {
  test(`team profile ${profile.id} preserves every accepted tag/category exclusion through real Bash arguments`, () => {
    const tags = [...new Set(manifestModules.flatMap((module) => module.tags))];
    const categories = [...new Set(manifestModules.map((module) => module.category))];
    const groups: ModuleSelectionInput[] = [
      ...tags.map((tag) => ({ profile: profile.id, skipTags: [tag] })),
      ...categories.map((category) => ({ profile: profile.id, skipCategories: [category] })),
    ];
    let accepted = 0;
    for (const selection of groups) {
      const original = resolveModuleSelection(selection);
      if (!original.ok) {
        assert.throws(() => buildTeamProfile(inputs(selection)), /selection/);
        continue;
      }
      accepted++;
      const exported = buildTeamProfile(inputs(selection));
      const imported = buildTeamProfileImportDiff(JSON.parse(serializeTeamProfileJson(exported)));
      assert.equal(imported.ok, true, JSON.stringify(imported.findings));
      assert.deepEqual(exported.install.modulePlan.included, original.included.map((entry) => entry.id));
      assert.deepEqual(ids(commandSelection(imported.installerCommand.command!)), exported.install.modulePlan.included);
      assert.deepEqual(ids(commandSelection(buildHandoffRunbook(inputs(selection)).install.command)), exported.install.modulePlan.included);
    }
    assert.ok(accepted > 0, "The catalogue must exercise accepted as well as refused selections");
  });
}

test("group lowering preserves profiles without mixing their derived selectors with explicit selectors", () => {
  const result = lowerModuleSelectionGroups({ profile: "minimal", skipTags: ["maintenance"] });
  assert.equal(result.profile, "minimal");
  assert.deepEqual(result.onlyModules, []);
  assert.deepEqual(result.onlyPhases, []);
  assert.ok(result.skipModules!.includes("acfs.nightly"));
  assert.equal(resolveModuleSelection(result).ok, true);
});

test("overlapping group and exact skips are deduplicated, including disabled defaults", () => {
  const selection: ModuleSelectionInput = { onlyModules: ["agents.claude"], skipCategories: ["cloud"],
    skipTags: ["cloud"], skipModules: ["cloud.wrangler", "cloud.wrangler"] };
  const profile = buildTeamProfile(inputs(selection));
  const expected = manifestModules.filter((module) => module.category === "cloud" || module.tags.includes("cloud")).map((module) => module.id).sort();
  assert.deepEqual([...profile.install.modules.skip].sort(), expected);
  assert.deepEqual(ids(commandSelection(buildTeamProfileImportDiff(profile).installerCommand.command!)), ids(selection));
});

test("a dependency-group conflict is refused before export rather than dropped", () => {
  const selection: ModuleSelectionInput = { onlyModules: ["agents.codex"], skipCategories: ["lang"] };
  assert.equal(resolveModuleSelection(selection).ok, false);
  assert.throws(() => buildTeamProfile(inputs(selection)), /selection/);
});

test("current group exclusions and imported exact skips compare without a false selection change", () => {
  const selection: ModuleSelectionInput = { profile: "full", skipCategories: ["cloud"], skipTags: ["maintenance"] };
  const profile = buildTeamProfile(inputs(selection));
  const diff = buildTeamProfileImportDiff(profile, { moduleSelection: selection });
  assert.equal(diff.ok, true, JSON.stringify(diff.findings));
  assert.ok(!diff.installerCommand.changes.some((entry) => entry.field.startsWith("install.modules")));
  const cleared = buildTeamProfileImportDiff(profile, { moduleSelection: {} });
  assert.ok(cleared.installerCommand.changes.some((entry) => entry.field === "install.modules.skip"));
});

test("lowering does not mutate or alias input selections", () => {
  const selection: ModuleSelectionInput = { onlyModules: ["agents.claude", "agents.claude"], onlyPhases: [],
    skipTags: ["maintenance"], skipModules: [] };
  const before = JSON.stringify(selection);
  const lowered = lowerModuleSelectionGroups(selection);
  assert.equal(JSON.stringify(selection), before);
  lowered.onlyModules!.push("lang.bun");
  lowered.skipModules!.push("cloud.vercel");
  assert.equal(JSON.stringify(selection), before);
});

test("phase aliases, mode-only profiles, pinned refs and target usernames survive profile transfer", () => {
  const selection: ModuleSelectionInput = { profile: "safe", onlyPhases: ["AGENTS"], skipTags: ["maintenance"] };
  const config = inputs(selection);
  config.ref = "0123456789abcdef0123456789abcdef01234567";
  const profile = buildTeamProfile(config);
  assert.deepEqual(profile.install.modules.onlyPhases, ["7"]);
  const diff = buildTeamProfileImportDiff(profile);
  assert.equal(diff.ok, true, JSON.stringify(diff.findings));
  assert.match(diff.installerCommand.command!, /TARGET_USER="dev-user"/);
  assert.ok(diff.installerCommand.command!.includes(config.ref!));
  assert.deepEqual(ids(commandSelection(diff.installerCommand.command!)), ids(selection));
  assert.ok(!serializeTeamProfileJson(profile).includes(config.ip));
});

const invalidSelections: unknown[] = [
  null, [], "full", { onlyModules: [""] }, { onlyModules: "agents.claude" },
  { onlyModules: new Array(1) }, { skipTags: ["not-a-real-tag"] }, { skipCategories: ["not-a-category"] },
  { onlyModule: ["agents.claude"] }, { profile: "no-such-profile" }, { noDeps: "false" }, { noDeps: true },
  Object.create({ onlyModules: ["agents.claude"] }),
];
for (const [index, value] of invalidSelections.entries()) {
  test(`invalid selection ${index} cannot be exported or compared as a valid full install`, () => {
    assert.throws(() => buildTeamProfile(inputs(value as ModuleSelectionInput)));
    const diff = buildTeamProfileImportDiff(buildTeamProfile(inputs()), { moduleSelection: value as ModuleSelectionInput });
    assert.equal(diff.ok, false);
    assert.equal(diff.installerCommand.command, null);
    assert.ok(diff.findings.some((finding) => finding.path === "current.moduleSelection"));
  });
}

test("accessors are not evaluated while validating an exported selection", () => {
  let accesses = 0;
  const selection = Object.defineProperty({}, "skipTags", { enumerable: true, get() { accesses++; return ["maintenance"]; } });
  assert.throws(() => buildTeamProfile(inputs(selection)));
  assert.equal(accesses, 0);
});

for (const field of ["skipTags", "skipCategories", "onlyModules", "ignored"]) {
  test(`unknown imported selector field ${field} is refused rather than ignored`, () => {
    const profile = buildTeamProfile(inputs());
    Object.assign(profile.install.modules, { [field]: ["maintenance"] });
    const diff = buildTeamProfileImportDiff(profile);
    assert.equal(diff.ok, false);
    assert.equal(diff.installerCommand.command, null);
  });
}

test("sparse imported selector arrays cannot collapse to default installation", () => {
  for (const key of ["only", "onlyPhases", "skip"] as const) {
    const profile = buildTeamProfile(inputs());
    profile.install.modules[key] = new Array(2);
    assert.equal(buildTeamProfileImportDiff(profile).installerCommand.command, null);
  }
});

test("stale provenance and patched cached-ready flags cannot authorize a command", () => {
  for (const key of ["manifestSha256", "checksumsYamlSha256"] as const) {
    const profile = buildTeamProfile(inputs({ skipTags: ["maintenance"] }));
    profile.provenance.source[key] = "a".repeat(64);
    profile.install.modulePlan.ok = true;
    assert.equal(buildTeamProfileImportDiff(profile).installerCommand.command, null);
    assert.ok(!formatTeamProfileReviewMarkdown(profile).includes("```bash"));
  }
});

test("ordinary default and explicit-selector exports retain matching commands", () => {
  for (const selection of [{}, { onlyModules: ["agents.claude"] }, { profile: "cloud-only" as const }]) {
    const profile = buildTeamProfile(inputs(selection));
    const diff = buildTeamProfileImportDiff(profile);
    assert.equal(diff.ok, true, JSON.stringify(diff.findings));
    assert.deepEqual(ids(commandSelection(diff.installerCommand.command!)), ids(commandSelection(buildInstallCommand("safe", "v1.2.3", "dev-user", selection))));
  }
});

test("known session-related module IDs are public selector data, not a credential exemption for unknown values", () => {
  const selection = { onlyModules: ["stack.cross_agent_session_resumer"] };
  const profile = buildTeamProfile(inputs(selection));
  assert.equal(buildTeamProfileImportDiff(profile).ok, true);
  profile.install.modules.only = ["stack.cross_agent_session_resumer_PRIVATE_CREDENTIAL"];
  const diff = buildTeamProfileImportDiff(profile);
  assert.equal(diff.ok, false);
  assert.equal(diff.installerCommand.command, null);
  assert.ok(diff.findings.some((finding) => finding.code === "team_profile_secret_material_refused"));
});
