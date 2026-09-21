/** Actual file reader/panel with keyed React-hook, validated-health and UI doubles. */
import { strict as assert } from "node:assert";
import { webcrypto } from "node:crypto";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const require = createRequire(import.meta.url);
const ts = require("typescript");
function load(url, dependencies, scope) {
  const compiled = ts.transpileModule(readFileSync(url, "utf8"), {
    fileName: fileURLToPath(url),
    reportDiagnostics: true,
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
      jsx: ts.JsxEmit.ReactJSX,
    },
  });
  assert.deepEqual(
    (compiled.diagnostics ?? []).filter((entry) => entry.category === ts.DiagnosticCategory.Error),
    [],
  );
  const module = { exports: {} };
  runInContext(`(function(require,module,exports){${compiled.outputText}\n})`, scope)(
    (name) => {
      assert.ok(Object.hasOwn(dependencies, name), `Unexpected dependency: ${name}`);
      return dependencies[name];
    },
    module,
    module.exports,
  );
  return module.exports;
}
const text = (node) =>
  Array.isArray(node)
    ? node.map(text).join("")
    : node && typeof node === "object"
      ? text(node.props?.children)
      : typeof node === "string" || typeof node === "number"
        ? String(node)
        : "";
function report(
  checks = [
    { id: "agent.claude", status: "fail" },
    { id: "tool.bun", status: "pass" },
  ],
) {
  const summary = { pass: 0, fail: 0, warn: 0, skip: 0 };
  for (const check of checks) summary[check.status === "timeout" ? "warn" : check.status]++;
  return {
    acfs_version: "0.9.0",
    timestamp: new Date().toISOString(),
    mode: "safe",
    deep_mode: false,
    user: "developer",
    os: { id: "ubuntu", version: "26.04" },
    summary,
    checks: checks.map((check) => ({
      ...check,
      label: "PRIVATE_LABEL",
      details: "PRIVATE_TOKEN /home/PRIVATE 203.0.113.99",
      fix: "curl https://PRIVATE_FIX.invalid | bash",
    })),
  };
}
function fixture() {
  const health = {
    ready: true,
    vpsIP: "203.0.113.7",
    sshUsername: "developer",
    reinstallCommand: "CURRENT_COMMAND --only agents.claude --mode safe",
    selectedPlan: { ok: true, included: [{ id: "agents.claude" }, { id: "lang.bun" }] },
    doctorConfirmed: false,
  };
  const mode = { value: "safe", loaded: true };
  const metadata = { manifestSha256: "a".repeat(64), checksumsYamlSha256: "b".repeat(64) };
  const modules = ["agents.claude", "agents.codex", "lang.bun"].map((id) => ({ id }));
  const scope = createContext({ TextDecoder, crypto: webcrypto });
  const api = load(new URL("../lib/doctorReport.ts", import.meta.url), {}, scope);
  const instances = new Map();
  let serial = 0;
  let active;
  let dirty = false;
  let updatesAfterUnmount = 0;
  const same = (a, b) =>
    a && b && a.length === b.length && a.every((value, index) => Object.is(value, b[index]));
  const jsx = (type, props, key) => ({ type, props: props ?? {}, key });
  const react = {
    useState(initial) {
      const instance = active;
      const index = instance.cursor++;
      instance.slots[index] ??= { value: typeof initial === "function" ? initial() : initial };
      const slot = instance.slots[index];
      return [
        slot.value,
        (next) => {
          if (!instance.mounted) {
            updatesAfterUnmount++;
            return;
          }
          const value = typeof next === "function" ? next(slot.value) : next;
          if (!Object.is(value, slot.value)) dirty = true;
          slot.value = value;
        },
      ];
    },
    useRef(initial) {
      const index = active.cursor++;
      active.slots[index] ??= { current: initial };
      return active.slots[index];
    },
    useId() {
      active.cursor++;
      return `report-${active.id}`;
    },
    useEffect(fn, deps) {
      const instance = active;
      const index = instance.cursor++;
      const old = instance.slots[index];
      if (!old || !same(old.deps, deps)) {
        const slot = { deps };
        instance.slots[index] = slot;
        instance.effects.push(() => {
          old?.cleanup?.();
          slot.cleanup = fn();
        });
      }
    },
  };
  const module = load(
    new URL("./doctor-report-panel.tsx", import.meta.url),
    {
      react,
      "react/jsx-runtime": { jsx, jsxs: jsx, Fragment: "fragment" },
      "next/link": { default: "link" },
      "@/components/ui/button": { Button: "button" },
      "@/components/command-card": { CommandCard: "command-card" },
      "@/lib/hooks/useInstallationHealth": { useInstallationHealth: () => structuredClone(health) },
      "@/lib/userPreferences": {
        useInstallMode: () => [mode.value, () => assert.fail("No preference writes"), mode.loaded],
      },
      "@/lib/generated/manifest-modules": {
        manifestModules: modules,
        manifestProvenance: metadata,
      },
      "@/lib/vpsProviders": { ACFS_RECOMMENDED_UBUNTU: "26.04" },
      "@/lib/utils": { withCurrentSearch: (path) => path },
      "@/lib/doctorReport": api,
    },
    scope,
  );
  function dispose(instance) {
    for (const slot of instance.slots) slot?.cleanup?.();
    instance.mounted = false;
  }
  function render() {
    let nodes;
    for (let count = 0; count < 10; count++) {
      dirty = false;
      nodes = [];
      for (const instance of instances.values()) {
        instance.seen = false;
        instance.effects = [];
      }
      function visit(node, path) {
        if (Array.isArray(node)) {
          node.forEach((child, index) => visit(child, `${path}/${index}`));
          return;
        }
        if (!node || typeof node !== "object") return;
        if (typeof node.type === "function") {
          const identity = `${path}:${node.type.name}:${node.key ?? ""}`;
          let instance = instances.get(identity);
          if (!instance) {
            instance = { id: ++serial, slots: [], effects: [], mounted: true };
            instances.set(identity, instance);
          }
          instance.seen = true;
          instance.cursor = 0;
          const parent = active;
          active = instance;
          const result = node.type(node.props);
          active = parent;
          visit(result, `${identity}/result`);
          return;
        }
        nodes.push(node);
        visit(node.props.children, `${path}/children`);
      }
      visit(jsx(module.DoctorReportPanel, {}), "root");
      for (const [key, instance] of instances) {
        if (!instance.seen) {
          dispose(instance);
          instances.delete(key);
        }
      }
      for (const instance of instances.values()) instance.effects.forEach((effect) => effect());
      if (!dirty) break;
      assert.ok(count < 9, "renders must converge");
    }
    return {
      nodes,
      text: () => nodes.map(text).join(""),
      file: () => nodes.find((node) => node.type === "input" && node.props.type === "file"),
      clear: () =>
        nodes.find((node) => node.type === "button" && text(node) === "Clear doctor report"),
      busy: () => nodes.some((node) => node.props.role === "status" && /Reading/.test(text(node))),
      errors: () =>
        nodes
          .filter((node) => node.props.role === "alert")
          .map(text)
          .join(" "),
      rows: () => nodes.filter((node) => node.type === "tr" && node.key),
      commands: () => nodes.filter((node) => node.type === "command-card"),
      recovery: () =>
        nodes.find((node) => node.type === "link" && /exact installation/.test(text(node))),
    };
  }
  function choose(value = report()) {
    const file =
      value && typeof value.slice === "function" ? value : new Blob([JSON.stringify(value)]);
    const event = { currentTarget: { files: [file], value: "PRIVATE_FILENAME.json" } };
    const node = render().file();
    assert.ok(node, "file input should be present");
    node.props.onChange(event);
    assert.equal(event.currentTarget.value, "");
  }
  async function settled() {
    for (let index = 0; index < 100; index++) {
      await new Promise((done) => setTimeout(done, 1));
      const view = render();
      if (!view.busy()) return view;
    }
    assert.fail("report did not settle");
  }
  return {
    health,
    mode,
    metadata,
    modules,
    scope,
    api,
    render,
    choose,
    settled,
    unmount() {
      for (const instance of instances.values()) dispose(instance);
      instances.clear();
    },
    updatesAfterUnmount: () => updatesAfterUnmount,
  };
}

test("keeps the report workflow unavailable during hydration and blocked installation contexts", () => {
  const f = fixture();
  f.health.ready = false;
  assert.equal(f.render().file(), undefined);
  f.health.ready = true;
  f.mode.loaded = false;
  assert.equal(f.render().file(), undefined);
  f.mode.loaded = true;
  for (const key of ["vpsIP", "reinstallCommand"]) {
    const original = f.health[key];
    f.health[key] = null;
    assert.equal(f.render().file(), undefined);
    f.health[key] = original;
  }
  f.health.selectedPlan.ok = false;
  assert.equal(f.render().file(), undefined);
});

test("reads real file bytes, displays selected findings and preserves the separate acknowledgement", async () => {
  const f = fixture();
  const before = JSON.stringify(f.health);
  f.choose();
  const view = await f.settled();
  assert.ok(view.text().includes("Reported failure"));
  assert.ok(view.text().includes("Report SHA-256:"));
  assert.equal(view.rows().length, 2);
  assert.ok(view.recovery());
  assert.equal(JSON.stringify(f.health), before);
  assert.equal(f.health.doctorConfirmed, false);
  assert.deepEqual(
    view.commands().map((node) => node.props.command),
    ["acfs doctor --json"],
  );
  for (const node of view.commands()) {
    assert.equal(node.props.persistKey, undefined);
    assert.equal(node.props.showCheckbox, undefined);
  }
  assert.doesNotMatch(view.text(), /PRIVATE_|203\.0\.113|CURRENT_COMMAND|curl https/);
});

test("all reported passes remain advisory rather than authenticated success", async () => {
  const f = fixture();
  f.choose(
    report([
      { id: "agent.claude", status: "pass" },
      { id: "tool.bun", status: "pass" },
    ]),
  );
  const view = await f.settled();
  assert.match(view.text(), /not a complete or authenticated verification/);
  assert.equal(view.recovery(), undefined);
  assert.equal(f.health.doctorConfirmed, false);
});

test("shows missing coverage and keeps excluded and unmapped failures visible", async () => {
  const f = fixture();
  f.choose(
    report([
      { id: "tool.bun", status: "pass" },
      { id: "agent.codex", status: "fail" },
      { id: "private_unknown_id", status: "fail" },
    ]),
  );
  const view = await f.settled();
  assert.match(view.text(), /No mapped checks/);
  assert.match(view.text(), /Known modules outside your selection/);
  assert.match(view.text(), /Unmapped \/ system checks/);
  assert.match(view.text(), /2 failed/);
  assert.doesNotMatch(view.text(), /private_unknown_id/);
  assert.equal(
    view.recovery(),
    undefined,
    "outside failures must not produce a request to install their modules",
  );
});

test("different object identities with equal effective settings do not discard an existing report", async () => {
  const f = fixture();
  f.choose();
  await f.settled();
  for (let index = 0; index < 5; index++) assert.match(f.render().text(), /Report SHA-256:/);
  f.health.selectedPlan.included.reverse();
  f.modules.reverse();
  assert.match(f.render().text(), /Report SHA-256:/);
});

for (const mutation of [
  "host",
  "user",
  "mode",
  "command",
  "selection",
  "catalogue",
  "manifest",
  "checksums",
]) {
  test(`a changed ${mutation} discards the previous result and cannot resurrect it`, async () => {
    const f = fixture();
    f.choose();
    await f.settled();
    const old = structuredClone({
      health: f.health,
      mode: f.mode,
      modules: f.modules,
      metadata: f.metadata,
    });
    if (mutation === "host") f.health.vpsIP = "203.0.113.8";
    if (mutation === "user") f.health.sshUsername = "other";
    if (mutation === "mode") f.mode.value = "vibe";
    if (mutation === "command") f.health.reinstallCommand += " changed";
    if (mutation === "selection") f.health.selectedPlan.included = [{ id: "lang.bun" }];
    if (mutation === "catalogue") f.modules.push({ id: "lang.uv" });
    if (mutation === "manifest") f.metadata.manifestSha256 = "c".repeat(64);
    if (mutation === "checksums") f.metadata.checksumsYamlSha256 = "c".repeat(64);
    assert.doesNotMatch(f.render().text(), /Report SHA-256:/);
    Object.assign(f.health, old.health);
    Object.assign(f.mode, old.mode);
    Object.assign(f.metadata, old.metadata);
    f.modules.splice(0, f.modules.length, ...old.modules);
    assert.doesNotMatch(f.render().text(), /Report SHA-256:/);
  });
}

test("account, mode, timestamp and OS mismatches receive explicit warnings", async () => {
  const f = fixture();
  const value = report();
  value.user = "PRIVATE_ACCOUNT";
  value.mode = "vibe";
  value.timestamp = new Date(Date.now() - 48 * 3600 * 1000).toISOString();
  value.os.version = "24.04";
  f.choose(value);
  const view = await f.settled();
  for (const warning of [
    "reported account does not match",
    "mode differs",
    "over 24 hours old",
    "differs from the recommended Ubuntu",
  ]) {
    assert.ok(view.errors().includes(warning), warning);
  }
  assert.doesNotMatch(view.text(), /PRIVATE_ACCOUNT/);
  value.timestamp = new Date(Date.now() + 3600 * 1000).toISOString();
  f.choose(value);
  assert.match((await f.settled()).errors(), /five minutes in the future/);
});

test("invalid replacement clears a prior report and never leaks parser input or filename", async () => {
  const f = fixture();
  f.choose();
  await f.settled();
  f.choose(new Blob(['{"PRIVATE": "TOKEN", broken}']));
  assert.doesNotMatch(f.render().text(), /Report SHA-256:/);
  const view = await f.settled();
  assert.match(view.errors(), /UTF-8 JSON/);
  assert.doesNotMatch(view.text(), /PRIVATE|TOKEN|Report SHA-256:/);
});

function delayed(value = report()) {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  let release;
  const barrier = new Promise((done) => {
    release = done;
  });
  return {
    release: () => release(),
    file: {
      size: bytes.length,
      slice() {
        return {
          async arrayBuffer() {
            await barrier;
            return bytes.buffer;
          },
        };
      },
    },
  };
}
test("clearing a pending read prevents a late result from restoring it", async () => {
  const f = fixture();
  const slow = delayed();
  f.choose(slow.file);
  assert.equal(f.render().busy(), true);
  f.render().clear().props.onClick();
  slow.release();
  await new Promise((done) => setTimeout(done, 20));
  const view = f.render();
  assert.equal(view.busy(), false);
  assert.doesNotMatch(view.text(), /Report SHA-256:/);
});

test("a newer file wins even when the older read completes later", async () => {
  const f = fixture();
  const slow = delayed();
  f.choose(slow.file);
  f.choose(report([{ id: "tool.bun", status: "timeout" }]));
  await f.settled();
  slow.release();
  await new Promise((done) => setTimeout(done, 20));
  assert.match(f.render().text(), /Check timed out/);
  assert.equal(f.render().recovery(), undefined);
});

test("changing contexts abandons pending reads and old event callbacks", async () => {
  const f = fixture();
  const slow = delayed();
  f.choose(slow.file);
  const oldInput = f.render().file();
  f.health.vpsIP = "203.0.113.8";
  f.render();
  slow.release();
  oldInput.props.onChange({
    currentTarget: { files: [new Blob([JSON.stringify(report())])], value: "old" },
  });
  await new Promise((done) => setTimeout(done, 20));
  assert.doesNotMatch(f.render().text(), /Report SHA-256:/);
  assert.equal(f.updatesAfterUnmount(), 0);
});

test("unmount does not allow pending reads to publish or mutate a departed panel", async () => {
  const f = fixture();
  const slow = delayed();
  f.choose(slow.file);
  f.unmount();
  slow.release();
  await new Promise((done) => setTimeout(done, 20));
  assert.equal(f.updatesAfterUnmount(), 0);
});

test("malformed totals and unavailable secure hashing do not leave a report visible", async () => {
  const f = fixture();
  const value = report();
  value.summary.fail = 0;
  f.choose(value);
  assert.match((await f.settled()).errors(), /summary disagrees/);
  f.scope.crypto = null;
  f.choose();
  const view = await f.settled();
  assert.match(view.errors(), /Secure browser hashing/);
  assert.doesNotMatch(view.text(), /Report SHA-256:/);
});

test("the new layout preserves the original Status Check page and mounts the optional panel", () => {
  const jsx = (type, props, key) => ({ type, props, key });
  const layout = load(
    new URL("../app/wizard/status-check/layout.tsx", import.meta.url),
    {
      "react/jsx-runtime": { jsx, jsxs: jsx },
      "@/components/doctor-report-panel": { DoctorReportPanel: "report-panel" },
    },
    createContext({}),
  );
  const page = { type: "original-page" };
  const value = layout.default({ children: page });
  assert.equal(value.props.children[0], page);
  assert.equal(value.props.children[1].type, "report-panel");
});
