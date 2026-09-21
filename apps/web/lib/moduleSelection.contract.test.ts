import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { test } from "node:test";
import {
  type ManifestModuleMetadata,
  manifestModules,
  manifestSelectionProfiles,
} from "./generated/manifest-modules";
import {
  buildInstallSelectorArgs,
  formatModuleSelectionPlan,
  type ModuleSelectionInput,
  resolveModuleSelection,
} from "./moduleSelection";

function refuse(input: unknown): void {
  const plan = resolveModuleSelection(input as ModuleSelectionInput);
  assert.equal(plan.ok, false);
  assert.equal(plan.selectedCount, 0);
  assert.deepEqual(plan.included, []);
  assert.ok(plan.errors.length > 0);
  assert.match(formatModuleSelectionPlan(plan), /Status: error/);
  assert.throws(() => buildInstallSelectorArgs(input as ModuleSelectionInput));
}

for (const [name, value] of [
  ["null", null],
  ["array", []],
  ["string", "agents.codex"],
  ["number", 1],
  ["blank module", { onlyModules: [""] }],
  ["blank module mixed with valid module", { onlyModules: ["agents.codex", ""] }],
  ["null modules", { onlyModules: null }],
  ["string modules", { onlyModules: "agents.codex" }],
  ["numeric module", { onlyModules: [1] }],
  ["padded module", { onlyModules: [" agents.codex "] }],
  ["blank phase", { onlyPhases: [""] }],
  ["null phases", { onlyPhases: null }],
  ["string phases", { onlyPhases: "agents" }],
  ["numeric phase", { onlyPhases: [7] }],
  ["blank skipped module", { skipModules: [""] }],
  ["null skipped modules", { skipModules: null }],
  ["string skipped modules", { skipModules: "agents.codex" }],
  ["blank skipped tag", { skipTags: [""] }],
  ["null skipped tags", { skipTags: null }],
  ["numeric skipped category", { skipCategories: [0] }],
  ["blank profile", { profile: "" }],
  ["null profile", { profile: null }],
  ["false profile", { profile: false }],
  ["string noDeps", { noDeps: "true" }],
  ["null noDeps", { noDeps: null }],
  ["misspelled selector", { onlyModule: ["agents.codex"] }],
  ["unknown skip tag", { skipTags: ["not-a-real-tag"] }],
  ["unknown skip category", { skipCategories: ["not-a-real-category"] }],
  ["sparse selection", { onlyModules: Array(2) }],
  ["inherited selectors", Object.create({ onlyModules: [] })],
  ["oversized selection", { onlyModules: Array(1025).fill("agents.codex") }],
] as const) {
  test(`malformed ${name} cannot become a default/full install`, () => refuse(value));
}

test("refuses accessor-backed selection without evaluating it", () => {
  let calls = 0;
  const value = Object.defineProperty({}, "onlyModules", {
    enumerable: true,
    get: () => {
      calls++;
      return [];
    },
  });
  refuse(value);
  assert.equal(calls, 0);
});

test("undefined optional fields and intentionally empty arrays retain default semantics", () => {
  const expected = resolveModuleSelection();
  const actual = resolveModuleSelection({
    profile: undefined,
    onlyModules: [],
    onlyPhases: [],
    skipModules: [],
    skipTags: [],
    skipCategories: [],
    noDeps: undefined,
  });
  assert.deepEqual(actual, expected);
  assert.deepEqual(buildInstallSelectorArgs({ onlyModules: [] }), []);
});

test("every real generated profile and every exact module resolves without widening its dependency closure", () => {
  for (const profile of manifestSelectionProfiles) {
    const plan = resolveModuleSelection({ profile: profile.id });
    assert.equal(plan.ok, true, JSON.stringify(plan.errors));
    assert.ok(plan.selectedCount > 0);
  }
  const byId = new Map(manifestModules.map((module) => [module.id, module]));
  for (const module of manifestModules) {
    const expected = new Set([module.id]);
    for (const id of expected) {
      for (const dependency of byId.get(id)!.dependencies) expected.add(dependency);
    }
    const plan = resolveModuleSelection({ onlyModules: [module.id] });
    assert.equal(plan.ok, true, JSON.stringify(plan.errors));
    assert.deepEqual(new Set(plan.included.map((entry) => entry.id)), expected);
  }
});

test("a dependency added from disabled defaults is not also reported as excluded", () => {
  const modules: ManifestModuleMetadata[] = [
    {
      id: "lang.fixture",
      description: "Runtime",
      category: "lang",
      phase: 6,
      dependencies: [],
      tags: [],
      enabledByDefault: false,
      optional: true,
    },
    {
      id: "agents.fixture",
      description: "Agent",
      category: "agents",
      phase: 7,
      dependencies: ["lang.fixture"],
      tags: [],
      enabledByDefault: true,
      optional: false,
    },
  ];
  const plan = resolveModuleSelection({}, modules, []);
  assert.equal(plan.ok, true);
  assert.deepEqual(
    plan.included.map((entry) => entry.id),
    ["lang.fixture", "agents.fixture"],
  );
  assert.deepEqual(plan.excluded, []);
});

test("explicit noDeps permits skipping a known dependency, never an explicitly requested module", () => {
  const plan = resolveModuleSelection({
    onlyModules: ["agents.codex"],
    skipModules: ["lang.bun"],
    noDeps: true,
  });
  assert.equal(plan.ok, true);
  assert.deepEqual(
    plan.included.map((entry) => entry.id),
    ["agents.codex"],
  );
  assert.match(plan.warnings.join("\n"), /--no-deps/);
  refuse({ onlyModules: ["agents.codex"], skipModules: ["agents.codex"], noDeps: true });
});

for (const mutation of [
  "duplicate",
  "missing",
  "cycle",
  "later-phase",
  "bad-phase",
  "order",
] as const) {
  test(`corrupt manifest ${mutation} never emits an executable plan, even with noDeps`, () => {
    const modules = structuredClone(manifestModules);
    const codex = modules.find((module) => module.id === "agents.codex")!;
    const bun = modules.find((module) => module.id === "lang.bun")!;
    if (mutation === "duplicate") modules.push({ ...codex });
    if (mutation === "missing") codex.dependencies = ["lang.missing"];
    if (mutation === "cycle") {
      codex.phase = 6;
      bun.dependencies = [codex.id];
    }
    if (mutation === "later-phase") bun.phase = 8;
    if (mutation === "bad-phase") bun.phase = NaN;
    if (mutation === "order") modules.reverse();
    for (const noDeps of [false, true]) {
      const plan = resolveModuleSelection({ onlyModules: [codex.id], noDeps }, modules, []);
      assert.equal(plan.ok, false, mutation);
      assert.deepEqual(plan.included, []);
      assert.equal(plan.selectedCount, 0);
    }
  });
}

test("valid selection never mutates caller arrays or the generated catalogue", () => {
  const input: ModuleSelectionInput = {
    onlyModules: ["agents.codex"],
    skipModules: ["tools.vault"],
  };
  const before = JSON.stringify({ input, manifestModules, manifestSelectionProfiles });
  Object.freeze(input.onlyModules);
  Object.freeze(input.skipModules);
  Object.freeze(input);
  resolveModuleSelection(input);
  buildInstallSelectorArgs(input);
  assert.equal(JSON.stringify({ input, manifestModules, manifestSelectionProfiles }), before);
});

/** Parse exactly the argv that Bash receives, not a hand-split command string. */
function selectorRoundTrip(input: ModuleSelectionInput): ModuleSelectionInput {
  const args = buildInstallSelectorArgs(input);
  const result = spawnSync(
    "/bin/bash",
    [
      "--noprofile",
      "--norc",
      "-c",
      `capture() { printf '%s\\0' "$@"; }; capture ${args.join(" ")}`,
    ],
    { encoding: "utf8", env: { PATH: "/usr/bin:/bin", LANG: "C.UTF-8" }, timeout: 5000 },
  );
  assert.equal(result.status, 0, result.stderr);
  const argv = args.length ? result.stdout.split("\0").slice(0, -1) : [];
  const decoded: ModuleSelectionInput = { onlyModules: [], onlyPhases: [], skipModules: [] };
  for (let index = 0; index < argv.length; index++) {
    const flag = argv[index];
    if (flag === "--no-deps") {
      decoded.noDeps = true;
      continue;
    }
    const value = argv[++index];
    assert.ok(value, "a selector flag lost its argument");
    if (flag === "--profile") decoded.profile = value as ModuleSelectionInput["profile"];
    else if (flag === "--only") decoded.onlyModules!.push(value);
    else if (flag === "--only-phase") decoded.onlyPhases!.push(value);
    else if (flag === "--skip") decoded.skipModules!.push(value);
    else assert.fail(`unsupported installer flag ${flag}`);
  }
  return decoded;
}

test("tag exclusions lower to exact skips including matching disabled defaults", () => {
  const input: ModuleSelectionInput = { skipTags: ["cloud", "maintenance"] };
  const decoded = selectorRoundTrip(input);
  assert.deepEqual(
    decoded.skipModules,
    manifestModules
      .filter((module) => module.tags.some((tag) => input.skipTags!.includes(tag)))
      .map((module) => module.id),
  );
  assert.ok(decoded.skipModules!.includes("tools.vault"));
  assert.ok(decoded.skipModules!.includes("acfs.nightly"));
  assert.deepEqual(
    resolveModuleSelection(decoded).included,
    resolveModuleSelection(input).included,
  );
});

test("category and tag exclusions deduplicate overlaps and preserve explicit skips", () => {
  const input: ModuleSelectionInput = {
    skipModules: ["tools.vault", "tools.vault"],
    skipTags: ["vpn", "networking", "cloud"],
    skipCategories: ["cloud", "network"],
  };
  const decoded = selectorRoundTrip(input);
  assert.equal(decoded.skipModules![0], "tools.vault");
  assert.equal(new Set(decoded.skipModules).size, decoded.skipModules!.length);
  assert.ok(decoded.skipModules!.includes("network.tailscale"));
  assert.ok(decoded.skipModules!.includes("network.ssh_keepalive"));
  assert.deepEqual(
    resolveModuleSelection(decoded).included,
    resolveModuleSelection(input).included,
  );
  assert.deepEqual(
    buildInstallSelectorArgs(input),
    buildInstallSelectorArgs({
      ...input,
      skipTags: [...input.skipTags!].reverse(),
      skipCategories: [...input.skipCategories!].reverse(),
    }),
  );
});

test("group exclusions do not widen a narrow request or bypass dependency conflicts", () => {
  const input: ModuleSelectionInput = { onlyModules: ["agents.codex"], skipCategories: ["cloud"] };
  const decoded = selectorRoundTrip(input);
  assert.deepEqual(decoded.onlyModules, ["agents.codex"]);
  assert.deepEqual(
    resolveModuleSelection(decoded).included,
    resolveModuleSelection(input).included,
  );
  assert.throws(
    () => buildInstallSelectorArgs({ onlyModules: ["agents.codex"], skipTags: ["runtime"] }),
    /depends on skipped/,
  );
  const expert = selectorRoundTrip({
    onlyModules: ["agents.codex"],
    skipTags: ["runtime"],
    noDeps: true,
  });
  assert.equal(expert.noDeps, true);
  assert.deepEqual(
    resolveModuleSelection(expert).included.map((entry) => entry.id),
    ["agents.codex"],
  );
  assert.throws(
    () =>
      buildInstallSelectorArgs({
        onlyModules: ["agents.codex"],
        skipCategories: ["agents"],
        noDeps: true,
      }),
    /was requested/,
  );
});

test("phase profiles retain their profile selection while excluding a matching member", () => {
  const input: ModuleSelectionInput = { profile: "agents-only", skipTags: ["legacy"] };
  const decoded = selectorRoundTrip(input);
  assert.equal(decoded.profile, "agents-only");
  assert.deepEqual(decoded.skipModules, ["agents.gemini"]);
  assert.deepEqual(
    resolveModuleSelection(decoded).included,
    resolveModuleSelection(input).included,
  );
});

const exclusionGroups: ModuleSelectionInput[] = [
  ...[...new Set(manifestModules.flatMap((module) => module.tags))].map((tag) => ({
    skipTags: [tag],
  })),
  ...[...new Set(manifestModules.map((module) => module.category))].map((category) => ({
    skipCategories: [category],
  })),
];
for (const profile of manifestSelectionProfiles) {
  test(`all exclusion groups preserve the exact ${profile.id} profile plan through real Bash argv`, () => {
    for (const group of exclusionGroups) {
      for (const noDeps of [false, true]) {
        const input: ModuleSelectionInput = { ...group, profile: profile.id, noDeps };
        const before = JSON.stringify(input);
        const expected = resolveModuleSelection(input);
        if (!expected.ok) {
          assert.throws(() => buildInstallSelectorArgs(input));
        } else {
          const decoded = selectorRoundTrip(input);
          const actual = resolveModuleSelection(decoded);
          assert.equal(actual.ok, true, JSON.stringify({ input, actual }));
          assert.deepEqual(
            actual.included.map((entry) => entry.id),
            expected.included.map((entry) => entry.id),
          );
          assert.equal(new Set(decoded.skipModules).size, decoded.skipModules!.length);
          assert.deepEqual(actual.warnings, expected.warnings);
        }
        assert.equal(JSON.stringify(input), before);
      }
    }
  });
}
