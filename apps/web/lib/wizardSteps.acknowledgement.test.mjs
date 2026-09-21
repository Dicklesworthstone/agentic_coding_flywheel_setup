/** Shared step validators use the real checkpoint/step code, with only storage and DOM contracts doubled. */
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { createContext, runInContext } from "node:vm";

const require = createRequire(import.meta.url);
const ts = require("typescript");
function fixture() {
  let controls = [];
  let legacyReads = 0;
  const storage = new Map([
    ["acfs-command-flywheel-doctor", "true"],
    ["acfs-command-run-flywheel-installer", "true"],
  ]);
  const scope = createContext({
    document: {
      getElementById: () => null,
      querySelectorAll(selector) {
        return controls.filter((control) => selector.includes(control.prefix));
      },
    },
  });
  function load(name, dependencies) {
    const code = ts.transpileModule(readFileSync(new URL(name, import.meta.url), "utf8"), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
      reportDiagnostics: true,
    });
    assert.deepEqual(
      code.diagnostics?.filter((item) => item.category === ts.DiagnosticCategory.Error),
      [],
    );
    const module = { exports: {} };
    runInContext(`(function(require,module,exports){${code.outputText}\n})`, scope)(
      (name) => {
        assert.ok(Object.hasOwn(dependencies, name), name);
        return dependencies[name];
      },
      module,
      module.exports,
    );
    return module.exports;
  }
  const helper = load("./installerCheckpoint.ts", {});
  const steps = load("./wizardSteps.ts", {
    "./installerCheckpoint": helper,
    react: { createContext: () => ({}) },
    "@tanstack/react-query": {},
    "./utils": {
      safeGetItem(key) {
        legacyReads++;
        return storage.get(key) ?? null;
      },
      safeGetJSON: () => [],
      safeSetJSON: () => true,
    },
    "./userPreferences": {
      getUserOS: () => "linux",
      detectOS: () => null,
      getVPSIP: () => "203.0.113.7",
      getCreateVPSChecklist: () => [],
      isCreateVPSChecklistComplete: () => true,
      setUserOS: () => {},
    },
  });
  function control(kind, state = "checked", disabled = false) {
    const prefix = kind === "doctor" ? "flywheel-doctor-v2-" : "run-flywheel-installer-v2-";
    return {
      prefix,
      tagName: "BUTTON",
      getAttribute(name) {
        return name === "data-state"
          ? state
          : name === "data-acfs-completion-key"
            ? prefix + "a".repeat(64)
            : null;
      },
      hasAttribute(name) {
        return name === "disabled" && disabled;
      },
      closest: () => null,
    };
  }
  return {
    steps,
    control,
    setControls: (values) => {
      controls = values;
    },
    legacyReads: () => legacyReads,
    scope,
  };
}
for (const [id, kind] of [
  [9, "installer"],
  [12, "doctor"],
]) {
  test(`step ${id} ignores global legacy flags when its scoped control is absent`, () => {
    const f = fixture();
    const result = f.steps.validateStep(id);
    assert.equal(result.valid, false);
    assert.equal(f.legacyReads(), 0);
    assert.ok(result.errors.length);
    assert.ok(result.focusSelector);
  });
  test(`step ${id} accepts its current scoped check without requiring storage persistence`, () => {
    const f = fixture();
    f.setControls([f.control(kind)]);
    assert.equal(f.steps.validateStep(id).valid, true);
    assert.equal(f.legacyReads(), 0);
  });
  test(`step ${id} refuses unchecked, disabled or duplicate scoped controls`, () => {
    const f = fixture();
    for (const controls of [
      [f.control(kind, "unchecked")],
      [f.control(kind, "checked", true)],
      [f.control(kind), f.control(kind)],
    ]) {
      f.setControls(controls);
      assert.equal(f.steps.validateStep(id).valid, false);
    }
  });
  test(`step ${id} cannot reuse the other checkpoint domain`, () => {
    const f = fixture();
    f.setControls([f.control(kind === "doctor" ? "installer" : "doctor")]);
    assert.equal(f.steps.validateStep(id).valid, false);
  });
}

test("unmounted pages and server rendering cannot restore old completion", () => {
  const f = fixture();
  f.setControls([f.control("doctor")]);
  assert.equal(f.steps.validateStep(12).valid, true);
  f.setControls([]);
  assert.equal(f.steps.validateStep(12).valid, false);
  delete f.scope.document;
  assert.equal(f.steps.validateStep(9).valid, false);
  assert.equal(f.steps.validateStep(12).valid, false);
});

test("unrelated OS/VPS validators and step reachability remain unchanged", () => {
  const f = fixture();
  assert.equal(f.steps.validateStep(1).valid, true);
  assert.equal(f.steps.validateStep(5).valid, true);
  assert.equal(f.steps.validateStep(7).valid, true);
  assert.equal(f.steps.canAccessWizardStep([1, 2, 3], 4), true);
  assert.equal(f.steps.canAccessWizardStep([1, 2, 3], 5), false);
  assert.equal(f.steps.getStepBySlug("windows-terminal-setup").id, 11);
});
