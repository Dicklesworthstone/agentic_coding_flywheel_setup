import { strict as assert } from "node:assert";
import { test } from "node:test";
import {
  buildInstallSelectorArgs,
  formatModuleSelectionPlan,
  resolveModuleSelection,
  type ModuleSelectionInput,
} from "./moduleSelection";
import {
  manifestModules,
  manifestSelectionProfiles,
  type ManifestModuleMetadata,
} from "./generated/manifest-modules";

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
  ["null", null], ["array", []], ["string", "agents.codex"], ["number", 1],
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
    get: () => { calls++; return []; },
  });
  refuse(value);
  assert.equal(calls, 0);
});

test("undefined optional fields and intentionally empty arrays retain default semantics", () => {
  const expected = resolveModuleSelection();
  const actual = resolveModuleSelection({
    profile: undefined, onlyModules: [], onlyPhases: [], skipModules: [],
    skipTags: [], skipCategories: [], noDeps: undefined,
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
    { id: "lang.fixture", description: "Runtime", category: "lang", phase: 6,
      dependencies: [], tags: [], enabledByDefault: false, optional: true },
    { id: "agents.fixture", description: "Agent", category: "agents", phase: 7,
      dependencies: ["lang.fixture"], tags: [], enabledByDefault: true, optional: false },
  ];
  const plan = resolveModuleSelection({}, modules, []);
  assert.equal(plan.ok, true);
  assert.deepEqual(plan.included.map((entry) => entry.id), ["lang.fixture", "agents.fixture"]);
  assert.deepEqual(plan.excluded, []);
});

test("explicit noDeps permits skipping a known dependency, never an explicitly requested module", () => {
  const plan = resolveModuleSelection({ onlyModules: ["agents.codex"], skipModules: ["lang.bun"], noDeps: true });
  assert.equal(plan.ok, true);
  assert.deepEqual(plan.included.map((entry) => entry.id), ["agents.codex"]);
  assert.match(plan.warnings.join("\n"), /--no-deps/);
  refuse({ onlyModules: ["agents.codex"], skipModules: ["agents.codex"], noDeps: true });
});

for (const mutation of ["duplicate", "missing", "cycle", "later-phase", "bad-phase", "order"] as const) {
  test(`corrupt manifest ${mutation} never emits an executable plan, even with noDeps`, () => {
    const modules = structuredClone(manifestModules);
    const codex = modules.find((module) => module.id === "agents.codex")!;
    const bun = modules.find((module) => module.id === "lang.bun")!;
    if (mutation === "duplicate") modules.push({ ...codex });
    if (mutation === "missing") codex.dependencies = ["lang.missing"];
    if (mutation === "cycle") { codex.phase = 6; bun.dependencies = [codex.id]; }
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
  const input: ModuleSelectionInput = { onlyModules: ["agents.codex"], skipModules: ["tools.vault"] };
  const before = JSON.stringify({ input, manifestModules, manifestSelectionProfiles });
  Object.freeze(input.onlyModules); Object.freeze(input.skipModules); Object.freeze(input);
  resolveModuleSelection(input); buildInstallSelectorArgs(input);
  assert.equal(JSON.stringify({ input, manifestModules, manifestSelectionProfiles }), before);
});
