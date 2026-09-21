/** Native file/hash/session tests; canonical validation is explicitly doubled. */
import { strict as assert } from "node:assert";
import { webcrypto } from "node:crypto";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const require = createRequire(import.meta.url);
const ts = require("typescript");
const clone = (value) => JSON.parse(JSON.stringify(value));
function fixture() {
  const metadata = { manifestSha256: "a".repeat(64), checksumsYamlSha256: "b".repeat(64) };
  const context = {
    targetHost: "203.0.113.7",
    current: {
      architecture: "aarch64",
      ubuntuVersion: "24.04",
      username: "ubuntu",
      installMode: "vibe",
      ref: null,
      moduleSelection: { profile: "full" },
      providerSelection: { providerId: "other" },
    },
  };
  const profile = {
    profileId: "team-example",
    displayName: "Team Example",
    providerDefaults: {
      sshUser: "team-user",
      architecture: "aarch64",
      operatingSystem: "ubuntu-26.04",
    },
    install: {
      mode: "safe",
      profile: "full",
      ref: { value: "v1.2.3" },
      modules: { only: ["agents.claude"], onlyPhases: [], skip: ["acfs.nightly"], noDeps: false },
    },
    command: "NEVER_EXECUTE_IMPORTED_COMMAND",
  };
  let valid = true;
  let revision = "";
  let validations = 0;
  const source = readFileSync(new URL("./teamProfileImport.ts", import.meta.url), "utf8");
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    reportDiagnostics: true,
  });
  assert.deepEqual(
    (compiled.diagnostics ?? []).filter((entry) => entry.category === ts.DiagnosticCategory.Error),
    [],
  );
  const module = { exports: {} };
  runInNewContext(
    compiled.outputText,
    {
      module,
      exports: module.exports,
      TextDecoder,
      crypto: webcrypto,
      structuredClone,
      require: (name) => {
        if (name === "./generated/manifest-modules") return { manifestProvenance: metadata };
        assert.equal(name, "./commandBuilder");
        return {
          buildTeamProfileImportDiff(input) {
            validations++;
            return {
              schema: "acfs.team-profile-import-diff.v1",
              dryRun: true,
              ok: valid,
              profile: { profileId: input.profileId, displayName: input.displayName },
              findings: valid ? [] : [{ code: "team_profile_manifest_mismatch" }],
              installerCommand: {
                command: `canonical-${input.install.mode}-${input.install.ref.value}${revision}`,
                changes: [],
              },
              skips: { allowed: valid, requested: input.install.modules.skip, warnings: [] },
              safeDefaults: { changes: [] },
              dependencyClosure: [],
              secretSlots: { required: [], optional: [] },
              incompatibilities: [],
              refusals: [],
            };
          },
        };
      },
    },
    { timeout: 5000 },
  );
  const api = module.exports;
  const entries = new Map([["other-preference", "preserve"]]);
  const calls = [];
  const storage = {
    getItem(key) {
      calls.push(["get", key]);
      return entries.get(key) ?? null;
    },
    setItem(key, value) {
      calls.push(["set", key, value]);
      entries.set(key, value);
    },
    removeItem(key) {
      calls.push(["remove", key]);
      entries.delete(key);
    },
  };
  return {
    api,
    profile,
    context,
    storage,
    entries,
    calls,
    metadata,
    refuse: () => {
      valid = false;
    },
    changePlan: () => {
      revision = "-changed";
    },
    validations: () => validations,
    review: () => api.reviewTeamProfileFile(new Blob([JSON.stringify(profile)]), context),
  };
}

test("activation uses one immutable source-derived settings snapshot without importing provider claims", async () => {
  const f = fixture();
  const review = await f.review();
  const before = JSON.stringify([f.profile, f.context]);
  const active = f.api.activateTeamProfileInstallation(review, f.context, true, f.storage);
  assert.equal(f.validations(), 2);
  assert.equal(active.command, "canonical-safe-v1.2.3");
  assert.equal(active.mode, "safe");
  assert.equal(active.username, "team-user");
  assert.equal(active.ref, "v1.2.3");
  assert.equal(active.architecture, "aarch64");
  assert.equal(active.ubuntuVersion, "24.04");
  assert.deepEqual(clone(active.moduleSelection), {
    profile: "full",
    onlyModules: ["agents.claude"],
    onlyPhases: [],
    skipModules: ["acfs.nightly"],
    noDeps: false,
  });
  assert.equal(JSON.stringify([f.profile, f.context]), before);
  assert.ok(f.api.teamProfileInstallationMatches(active, f.context));
  assert.throws(
    () => active.moduleSelection.skipModules.push("other"),
    (error) => error.name === "TypeError",
  );
  assert.throws(() => {
    active.username = "different";
  }, TypeError);
  assert.ok(!JSON.stringify(active).includes("NEVER_EXECUTE"));
  assert.ok(!JSON.stringify(active).includes("203.0.113.7"));
});

test("only the reload guard is persisted; no profile, source digest, host, command, or credentials", async () => {
  const f = fixture();
  const review = await f.review();
  f.api.activateTeamProfileInstallation(review, f.context, true, f.storage);
  assert.deepEqual(
    [...f.entries],
    [
      ["other-preference", "preserve"],
      [f.api.TEAM_PROFILE_SESSION_KEY, "review-required"],
    ],
  );
  assert.equal(f.api.readTeamProfileSessionGuard(f.storage), "review_required");
  assert.equal(
    f.api.teamProfileInstallationMatches(JSON.parse(JSON.stringify(review)), f.context),
    false,
  );
});

test("main is kept as an unpinned command ref, avoiding a changed approved command", async () => {
  const f = fixture();
  f.profile.install.ref.value = "main";
  const active = f.api.activateTeamProfileInstallation(
    await f.review(),
    f.context,
    true,
    f.storage,
  );
  assert.equal(active.ref, null);
  assert.equal(active.command, "canonical-safe-main");
});

for (const mutation of [
  "host",
  "image",
  "architecture",
  "username",
  "mode",
  "ref",
  "selection",
  "provider",
  "manifest",
  "checksums",
]) {
  test(`changed ${mutation} invalidates activation before any storage mutation`, async () => {
    const f = fixture();
    const review = await f.review();
    if (mutation === "host") f.context.targetHost = "203.0.113.8";
    if (mutation === "image") f.context.current.ubuntuVersion = "26.04";
    if (mutation === "architecture") f.context.current.architecture = "x86_64";
    if (mutation === "username") f.context.current.username = "other";
    if (mutation === "mode") f.context.current.installMode = "safe";
    if (mutation === "ref") f.context.current.ref = "v2.0.0";
    if (mutation === "selection") f.context.current.moduleSelection = { profile: "minimal" };
    if (mutation === "provider") f.context.current.providerSelection.providerId = "another";
    if (mutation === "manifest") f.metadata.manifestSha256 = "c".repeat(64);
    if (mutation === "checksums") f.metadata.checksumsYamlSha256 = "c".repeat(64);
    assert.throws(
      () => f.api.activateTeamProfileInstallation(review, f.context, true, f.storage),
      /changed/,
    );
    assert.equal(f.calls.length, 0);
  });
}

test("rejects deserialized reviews and every non-true confirmation", async () => {
  const f = fixture();
  const review = await f.review();
  for (const value of [false, undefined, "true", 1, null]) {
    assert.throws(
      () => f.api.activateTeamProfileInstallation(review, f.context, value, f.storage),
      /approve/,
    );
  }
  assert.throws(
    () => f.api.activateTeamProfileInstallation(clone(review), f.context, true, f.storage),
    /changed/,
  );
  assert.equal(f.calls.length, 0);
});

for (const condition of ["refused", "changed"]) {
  test(`reruns canonical validation and refuses ${condition} plans before publishing settings`, async () => {
    const f = fixture();
    const review = await f.review();
    condition === "refused" ? f.refuse() : f.changePlan();
    assert.throws(() => f.api.activateTeamProfileInstallation(review, f.context, true, f.storage));
    assert.equal(f.validations(), 2);
    assert.equal(f.calls.length, 0);
  });
}

for (const condition of ["throw-write", "silent-write", "throw-read"]) {
  test(`unavailable session storage cannot create an active installation: ${condition}`, async () => {
    const f = fixture();
    const review = await f.review();
    if (condition === "throw-write")
      f.storage.setItem = () => {
        throw new Error("PRIVATE");
      };
    if (condition === "silent-write") f.storage.setItem = () => {};
    if (condition === "throw-read")
      f.storage.getItem = () => {
        throw new Error("PRIVATE");
      };
    assert.throws(
      () => f.api.activateTeamProfileInstallation(review, f.context, true, f.storage),
      (error) =>
        error.code === "team_profile_session_unavailable" && !error.message.includes("PRIVATE"),
    );
    // The existing manual approval path remains available without session adoption.
    assert.equal(
      f.api.approveTeamProfileReview(review, f.context, true).command,
      "canonical-safe-v1.2.3",
    );
  });
}

test("explicit discard touches only the marker and verifies its removal", () => {
  const f = fixture();
  f.entries.set(f.api.TEAM_PROFILE_SESSION_KEY, "review-required");
  f.api.discardTeamProfileInstallation(f.storage);
  assert.equal(f.api.readTeamProfileSessionGuard(f.storage), "clear");
  assert.deepEqual([...f.entries], [["other-preference", "preserve"]]);
  f.entries.set(f.api.TEAM_PROFILE_SESSION_KEY, "review-required");
  f.storage.removeItem = () => {};
  assert.throws(() => f.api.discardTeamProfileInstallation(f.storage), /No default installation/);
});

test("unknown nonempty/empty markers block restoration rather than inventing stored approval", () => {
  const f = fixture();
  for (const value of ["", "true", "{}", "old-version"]) {
    f.entries.set(f.api.TEAM_PROFILE_SESSION_KEY, value);
    assert.equal(f.api.readTeamProfileSessionGuard(f.storage), "review_required");
  }
  assert.equal(
    f.api.readTeamProfileSessionGuard({
      getItem() {
        throw new Error();
      },
    }),
    "unavailable",
  );
});

test("the session cannot be transferred as serialized or manually fabricated installation settings", async () => {
  const f = fixture();
  const review = await f.review();
  const active = f.api.activateTeamProfileInstallation(review, f.context, true, f.storage);
  assert.equal(f.api.teamProfileInstallationMatches(clone(active), f.context), false);
  assert.equal(f.api.teamProfileInstallationMatches(active, null), false);
  assert.equal(f.api.teamProfileInstallationMatches(null, f.context), false);
  f.context.targetHost = "203.0.113.9";
  assert.equal(f.api.teamProfileInstallationMatches(active, f.context), false);
});
