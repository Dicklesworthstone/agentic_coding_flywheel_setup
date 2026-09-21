/** Handler/effect integration uses the real file-review controller, with React/preferences/canonical-validator doubles. */
import { strict as assert } from "node:assert";
import { webcrypto } from "node:crypto";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const require = createRequire(import.meta.url);
const ts = require("typescript");
const text = (node) =>
  Array.isArray(node)
    ? node.map(text).join("")
    : node && typeof node === "object"
      ? text(node.props?.children)
      : typeof node === "string" || typeof node === "number"
        ? String(node)
        : "";
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
    (compiled.diagnostics ?? []).filter((item) => item.category === ts.DiagnosticCategory.Error),
    [],
  );
  const module = { exports: {} };
  runInContext(`(function(require,module,exports){${compiled.outputText}\n})`, scope)(
    (name) => {
      assert.ok(Object.hasOwn(dependencies, name), `unexpected dependency ${name}`);
      return dependencies[name];
    },
    module,
    module.exports,
  );
  return module.exports;
}
function fixture() {
  const prefs = {
    mode: "safe",
    profile: "full",
    ref: null,
    username: "ubuntu",
    host: "203.0.113.42",
    provider: { providerId: "other", ubuntuVersion: "26.04" },
  };
  const loaded = Object.fromEntries(Object.keys(prefs).map((key) => [key, true]));
  const calls = [];
  let cursor = 0;
  let dirty = false;
  let effects = [];
  const slots = [];
  let mounted = true;
  let updatesAfterUnmount = 0;
  const jsx = (type, props) => ({ type, props: props ?? {} });
  const same = (a, b) =>
    a && b && a.length === b.length && a.every((item, index) => Object.is(item, b[index]));
  const react = {
    useState(initial) {
      const at = cursor++;
      slots[at] ??= { value: typeof initial === "function" ? initial() : initial };
      return [
        slots[at].value,
        (next) => {
          if (!mounted) updatesAfterUnmount++;
          const value = typeof next === "function" ? next(slots[at].value) : next;
          if (!Object.is(value, slots[at].value)) dirty = true;
          slots[at].value = value;
        },
      ];
    },
    useMemo(fn, deps) {
      const at = cursor++;
      if (!slots[at] || !same(slots[at].deps, deps)) slots[at] = { deps, value: fn() };
      return slots[at].value;
    },
    useId() {
      cursor++;
      return "import-fixture";
    },
    useRef(value) {
      const at = cursor++;
      slots[at] ??= { current: value };
      return slots[at];
    },
    useEffect(fn, deps) {
      const at = cursor++;
      if (!slots[at] || !same(slots[at].deps, deps)) {
        const old = slots[at]?.cleanup;
        slots[at] = { deps };
        effects.push(() => {
          old?.();
          slots[at].cleanup = fn();
        });
      }
    },
  };
  const scope = createContext({ TextDecoder, TextEncoder, structuredClone, crypto: webcrypto });
  const review = load(
    new URL("../lib/teamProfileImport.ts", import.meta.url),
    {
      "./generated/manifest-modules": {
        manifestProvenance: { manifestSha256: "a".repeat(64), checksumsYamlSha256: "b".repeat(64) },
      },
      "./commandBuilder": {
        buildTeamProfileImportDiff(source, current) {
          calls.push({ source, current });
          const ok = !source.refuse;
          return {
            schema: "acfs.team-profile-import-diff.v1",
            schemaVersion: 1,
            dryRun: true,
            ok,
            profile: { profileId: "example", displayName: "Example team", schemaVersion: 1 },
            findings: ok
              ? []
              : [
                  {
                    code: "team_profile_checksums_mismatch",
                    path: "PRIVATE_PATH",
                    message: "PRIVATE_SECRET",
                  },
                ],
            safeDefaults: {
              changes: [{ field: "providerDefaults.region", current: null, next: "us-east" }],
            },
            installerCommand: {
              command: ok
                ? `bash install.sh --profile cloud-only --skip acfs.nightly --mode ${current.installMode}`
                : null,
              changes: [
                {
                  field: "install.profile",
                  current: current.moduleSelection.profile,
                  next: "cloud-only",
                },
              ],
            },
            dependencyClosure: ["lang.bun"],
            skips: {
              requested: ["acfs.nightly"],
              allowed: ok,
              warnings: ["Provider login may be required."],
            },
            secretSlots: {
              required: ["secret://acfs/team/github-auth"],
              optional: ["secret://acfs/team/cloudflare-auth"],
            },
            incompatibilities: [],
            refusals: [],
          };
        },
      },
    },
    scope,
  );
  const preference = (key) => () => [
    prefs[key],
    () => assert.fail("Import must not mutate saved preferences"),
    loaded[key],
  ];
  const component = load(
    new URL("./team-profile-import-panel.tsx", import.meta.url),
    {
      react,
      "react/jsx-runtime": { jsx, jsxs: jsx, Fragment: "fragment" },
      "@/components/ui/button": { Button: "button" },
      "@/components/command-card": { CommandCard: "command-card" },
      "@/lib/userPreferences": {
        useSavedInstallMode: preference("mode"),
        useSavedModuleProfile: preference("profile"),
        useSavedACFSRef: preference("ref"),
        useSavedSSHUsername: preference("username"),
        useVPSIP: preference("host"),
        useVPSReadinessSelection: preference("provider"),
      },
      "@/lib/wizardInstallation": { useWizardInstallation: () => null },
      "@/lib/vpsProviders": { VPS_UBUNTU_IMAGE_OPTIONS: ["26.04", "24.04", "22.04"] },
      "@/lib/teamProfileImport": review,
    },
    scope,
  );
  function render() {
    let nodes;
    for (let attempts = 0; attempts < 10; attempts++) {
      cursor = 0;
      dirty = false;
      effects = [];
      nodes = [];
      function visit(node) {
        if (Array.isArray(node)) {
          node.forEach(visit);
          return;
        }
        if (!node || typeof node !== "object") return;
        if (typeof node.type === "function") {
          visit(node.type(node.props));
          return;
        }
        nodes.push(node);
        visit(node.props.children);
      }
      visit(component.TeamProfileImportPanel());
      effects.forEach((effect) => effect());
      if (!dirty) break;
      assert.ok(attempts < 9, "render effects must converge");
    }
    const one = (predicate) => {
      const found = nodes.find(predicate);
      assert.ok(found, "expected UI element");
      return found;
    };
    return {
      nodes,
      text: () => nodes.map(text).join(""),
      arch: () => one((node) => node.type === "select" && node.props.id.endsWith("-arch")),
      image: () => one((node) => node.type === "select" && node.props.id.endsWith("-image")),
      file: () => one((node) => node.type === "input" && node.props.type === "file"),
      confirmation: () => one((node) => node.type === "input" && node.props.type === "checkbox"),
      button: (label) => one((node) => node.type === "button" && text(node) === label),
      command: () => nodes.find((node) => node.type === "command-card"),
      errors: () =>
        nodes
          .filter((node) => node.props.role === "alert")
          .map(text)
          .join("\n"),
      busy: () => nodes.some((node) => node.props.role === "status" && /Reading/.test(text(node))),
    };
  }
  function choose(blob = new Blob(["{}"])) {
    const event = { currentTarget: { files: [blob], value: "PRIVATE_FILENAME.json" } };
    render().file().props.onChange(event);
    assert.equal(event.currentTarget.value, "");
  }
  async function settled() {
    for (let i = 0; i < 100; i++) {
      await new Promise((done) => setTimeout(done, 1));
      const view = render();
      if (!view.busy()) return view;
    }
    assert.fail("file operation did not settle");
  }
  function ready() {
    render()
      .arch()
      .props.onChange({ target: { value: "x86_64" } });
    return render();
  }
  return {
    render,
    prefs,
    loaded,
    calls,
    choose,
    settled,
    ready,
    scope,
    review,
    unmount() {
      mounted = false;
      for (const slot of slots) slot?.cleanup?.();
    },
    updatesAfterUnmount: () => updatesAfterUnmount,
    component,
  };
}

test("requires explicit architecture and loaded target context; no file is read on first render", () => {
  const item = fixture();
  let view = item.render();
  assert.equal(view.file().props.disabled, true);
  assert.equal(view.arch().props.value, "");
  assert.equal(item.calls.length, 0);
  view = item.ready();
  assert.equal(view.file().props.disabled, false);
  item.prefs.host = null;
  view = item.render();
  assert.equal(view.file().props.disabled, true);
});

test("every preference hydration gate remains closed before file ingestion", () => {
  for (const key of ["mode", "profile", "ref", "username", "host", "provider"]) {
    const item = fixture();
    item.loaded[key] = false;
    const view = item.ready();
    assert.equal(view.file().props.disabled, true, key);
    assert.equal(item.calls.length, 0);
  }
});

test("local file shows all review groups without exposing an executable before approval", async () => {
  const item = fixture();
  item.ready();
  item.choose();
  const view = await item.settled();
  for (const value of [
    "Example team",
    "File SHA-256:",
    "providerDefaults.region",
    "install.profile",
    "lang.bun",
    "acfs.nightly",
    "secret://acfs/team/github-auth",
    "secret://acfs/team/cloudflare-auth",
  ])
    assert.ok(view.text().includes(value));
  assert.equal(view.command(), undefined);
  assert.equal(view.button("Approve profile command").props.disabled, true);
  view.button("Approve profile command").props.onClick();
  assert.equal(item.render().command(), undefined);
  assert.equal(item.calls.length, 1);
  assert.doesNotMatch(view.text(), /PRIVATE_FILENAME|203\.0\.113\.42/);
});

test("confirmation revalidates and reveals the exact regenerated command without changing wizard settings", async () => {
  const item = fixture();
  const before = JSON.stringify(item.prefs);
  item.ready();
  item.choose();
  let view = await item.settled();
  view.confirmation().props.onChange({ target: { checked: true } });
  view = item.render();
  assert.equal(view.button("Approve profile command").props.disabled, false);
  view.button("Approve profile command").props.onClick();
  view = item.render();
  assert.match(view.command().props.command, /--skip acfs.nightly/);
  assert.equal(view.command().props.persistKey, undefined);
  assert.equal(view.command().props.showCheckbox, undefined);
  assert.equal(item.calls.length, 2);
  assert.equal(JSON.stringify(item.prefs), before);
  view.confirmation().props.onChange({ target: { checked: false } });
  assert.equal(item.render().command(), undefined);
});

for (const [name, value] of [
  ["host", "203.0.113.99"],
  ["mode", "vibe"],
  ["profile", "minimal"],
  ["ref", "other-tag"],
  ["username", "developer"],
]) {
  test(`changing ${name} removes the previous review and approval`, async () => {
    const item = fixture();
    item.ready();
    item.choose();
    let view = await item.settled();
    view.confirmation().props.onChange({ target: { checked: true } });
    item.render().button("Approve profile command").props.onClick();
    assert.ok(item.render().command());
    item.prefs[name] = value;
    view = item.render();
    assert.equal(view.command(), undefined);
    assert.doesNotMatch(view.text(), /Review Example team/);
  });
}

test("changing target image or architecture invalidates the previous snapshot", async () => {
  for (const field of ["image", "arch"]) {
    const item = fixture();
    item.ready();
    item.choose();
    let view = await item.settled();
    view.confirmation().props.onChange({ target: { checked: true } });
    item.render().button("Approve profile command").props.onClick();
    item
      .render()
      [field]()
      .props.onChange({ target: { value: field === "image" ? "24.04" : "aarch64" } });
    view = item.render();
    assert.equal(view.command(), undefined);
    assert.doesNotMatch(view.text(), /Review Example team/);
  }
});

test("refused second file cannot leave an earlier approved command visible or echo its secrets", async () => {
  const item = fixture();
  item.ready();
  item.choose();
  let view = await item.settled();
  view.confirmation().props.onChange({ target: { checked: true } });
  item.render().button("Approve profile command").props.onClick();
  item.choose(new Blob(['{"refuse":true}']));
  assert.equal(item.render().command(), undefined);
  view = await item.settled();
  assert.match(view.errors(), /team_profile_checksums_mismatch/);
  assert.doesNotMatch(view.text(), /PRIVATE_|Review Example team/);
  assert.equal(view.command(), undefined);
});

test("clearing during an asynchronous read prevents the stale file from reappearing", async () => {
  const item = fixture();
  item.ready();
  let resume;
  const wait = new Promise((done) => {
    resume = done;
  });
  item.choose({
    size: 2,
    slice() {
      return {
        async arrayBuffer() {
          await wait;
          return new TextEncoder().encode("{}").buffer;
        },
      };
    },
  });
  let view = item.render();
  assert.equal(view.busy(), true);
  view.button("Clear imported profile").props.onClick();
  resume();
  await new Promise((done) => setTimeout(done, 10));
  view = item.render();
  assert.equal(view.command(), undefined);
  assert.doesNotMatch(view.text(), /Review Example team/);
  assert.equal(view.busy(), false);
});

test("later file wins over a slow earlier read", async () => {
  const item = fixture();
  item.ready();
  let resume;
  const wait = new Promise((done) => {
    resume = done;
  });
  item.choose({
    size: 2,
    slice() {
      return {
        async arrayBuffer() {
          await wait;
          return new TextEncoder().encode("{}").buffer;
        },
      };
    },
  });
  item.choose(new Blob(['{"refuse":true}']));
  await item.settled();
  resume();
  await new Promise((done) => setTimeout(done, 10));
  const view = item.render();
  assert.match(view.errors(), /refused/);
  assert.equal(view.command(), undefined);
  assert.doesNotMatch(view.text(), /Review Example team/);
});

test("context change during read prevents stale approval and resets the busy state", async () => {
  const item = fixture();
  item.ready();
  let resume;
  const wait = new Promise((done) => {
    resume = done;
  });
  item.choose({
    size: 2,
    slice() {
      return {
        async arrayBuffer() {
          await wait;
          return new TextEncoder().encode("{}").buffer;
        },
      };
    },
  });
  item.prefs.host = "203.0.113.100";
  item.render();
  resume();
  await new Promise((done) => setTimeout(done, 10));
  const view = item.render();
  assert.equal(view.busy(), false);
  assert.doesNotMatch(view.text(), /Review Example team/);
});

test("leaving and returning to an earlier target does not resurrect its approval", async () => {
  const item = fixture();
  item.ready();
  item.choose();
  let view = await item.settled();
  view.confirmation().props.onChange({ target: { checked: true } });
  item.render().button("Approve profile command").props.onClick();
  assert.ok(item.render().command());
  const original = item.prefs.host;
  item.prefs.host = "203.0.113.111";
  item.render();
  item.prefs.host = original;
  view = item.render();
  assert.equal(view.command(), undefined);
  assert.doesNotMatch(view.text(), /Review Example team/);
});

test("unmounting abandons a pending file without updating the departed component", async () => {
  const item = fixture();
  item.ready();
  let resume;
  const wait = new Promise((done) => {
    resume = done;
  });
  item.choose({
    size: 2,
    slice() {
      return {
        async arrayBuffer() {
          await wait;
          return new TextEncoder().encode("{}").buffer;
        },
      };
    },
  });
  item.unmount();
  resume();
  await new Promise((done) => setTimeout(done, 10));
  assert.equal(item.updatesAfterUnmount(), 0);
});

test("malformed files and unavailable hashing never expose a command", async () => {
  const item = fixture();
  item.ready();
  item.choose(new Blob(['{"a":1,"a":2}']));
  let view = await item.settled();
  assert.match(view.errors(), /duplicate/);
  assert.equal(item.calls.length, 0);
  item.scope.crypto = null;
  item.choose();
  view = await item.settled();
  assert.match(view.errors(), /hashing/);
  assert.equal(view.command(), undefined);
});

test("route layout retains the original installer page and mounts the import panel", () => {
  const scope = createContext({});
  const jsx = (type, props) => ({ type, props });
  const layout = load(
    new URL("../app/wizard/run-installer/layout.tsx", import.meta.url),
    {
      "react/jsx-runtime": { jsx, jsxs: jsx },
      "@/components/team-profile-import-panel": { TeamProfileImportPanel: "import-panel" },
    },
    scope,
  );
  const page = { type: "original-installer-page" };
  const result = layout.default({ children: page });
  assert.equal(result.props.children[0], page);
  assert.equal(result.props.children[1].type, "import-panel");
});
