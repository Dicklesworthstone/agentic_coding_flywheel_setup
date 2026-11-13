/** Component-handler tests with hook/clipboard doubles; not browser or React-renderer tests. */
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const require = createRequire(import.meta.url);
const ts = require("typescript");
// Imported application modules share a realm, just as they do in the browser.
const context = createContext({
  URL,
  window: {
    location: {
      origin: "https://agent-flywheel.example",
      pathname: "/wizard/launch-onboarding",
    },
  },
});
function loadSource(url, dependencies = {}) {
  const source = readFileSync(url, "utf8");
  const compiled = ts.transpileModule(source, {
    fileName: fileURLToPath(url),
    reportDiagnostics: true,
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
      jsx: ts.JsxEmit.ReactJSX,
      esModuleInterop: true,
    },
  });
  assert.deepEqual(
    (compiled.diagnostics ?? []).filter((entry) => entry.category === ts.DiagnosticCategory.Error),
    [],
  );
  const cjs = { exports: {} };
  const run = runInContext(
    `(function(require, module, exports) {\n${compiled.outputText}\n})`,
    context,
    { filename: fileURLToPath(url), timeout: 5000 },
  );
  run(
    (name) => {
      assert.ok(Object.hasOwn(dependencies, name), `unexpected dependency ${name}`);
      return dependencies[name];
    },
    cjs,
    cjs.exports,
  );
  return cjs.exports;
}
const catalogue = loadSource(new URL("../lib/generated/manifest-modules.ts", import.meta.url));
// The catalogue and resolver are the production source, not fixture metadata.
const selection = loadSource(new URL("../lib/moduleSelection.ts", import.meta.url), {
  "./generated/manifest-modules": catalogue,
});
const validation = loadSource(new URL("../lib/inputValidation.ts", import.meta.url));
const commands = loadSource(new URL("../lib/commandBuilder.ts", import.meta.url), {
  "./generated/manifest-modules": catalogue,
  "./inputValidation": validation,
  "./moduleSelection": selection,
  "./vpsProviders": loadSource(new URL("../lib/vpsProviders.ts", import.meta.url)),
});
const text = (value) =>
  Array.isArray(value)
    ? value.map(text).join("")
    : value && typeof value === "object"
      ? text(value.props?.children)
      : typeof value === "string" || typeof value === "number"
        ? String(value)
        : "";
const plain = (value) => JSON.parse(JSON.stringify(value));

function fixture() {
  let cursor = 0;
  let id = 0;
  let rendering = false;
  let renderAgain = false;
  const states = [];
  const preferences = {
    ip: "203.0.113.42",
    os: "linux",
    mode: "safe",
    username: "ubuntu",
    ref: null,
    profile: "full",
    setupProfile: null,
  };
  const loaded = Object.fromEntries(
    ["ip", "os", "mode", "username", "ref", "profile", "selection"].map((key) => [key, true]),
  );
  const buildCalls = [];
  const shares = [];
  const copies = [];
  const jsx = (type, props) => ({ type, props: props ?? {} });
  const preference = (key) => () => [
    preferences[key],
    (value) => {
      preferences[key] = value;
    },
    loaded[key],
  ];
  const component = loadSource(new URL("./command-builder-panel.tsx", import.meta.url), {
    "react/jsx-runtime": { jsx, jsxs: jsx, Fragment: "fragment" },
    react: {
      useState(initial) {
        const index = cursor++;
        if (!(index in states)) states[index] = typeof initial === "function" ? initial() : initial;
        return [
          states[index],
          (next) => {
            const value = typeof next === "function" ? next(states[index]) : next;
            if (!Object.is(states[index], value)) {
              states[index] = value;
              if (rendering) renderAgain = true;
            }
          },
        ];
      },
      useId: () => `fixture-${++id}`,
      useMemo: (fn) => fn(),
      useCallback: (fn) => fn,
      useEffect: () => {},
      useRef: () => ({ current: null }),
    },
    "lucide-react": Object.fromEntries(
      [
        "Terminal",
        "Link2",
        "Check",
        "Copy",
        "Server",
        "Monitor",
        "Settings2",
        "ChevronDown",
        "Boxes",
      ].map((name) => [name, `icon-${name}`]),
    ),
    "@/components/ui/button": { Button: (props) => jsx("button", props) },
    "@/components/ui/code-block": { CopyStatus: () => null },
    "@/lib/utils": { cn: (...values) => values.filter(Boolean).join(" ") },
    "@/lib/hooks/useCopyFeedback": {
      useCopyFeedback: () => ({
        state: "idle",
        copy: async (value) => {
          copies.push(value);
        },
      }),
    },
    "@/lib/userPreferences": {
      useVPSIP: preference("ip"),
      useUserOS: preference("os"),
      useInstallMode: preference("mode"),
      useSSHUsername: preference("username"),
      useACFSRef: preference("ref"),
      useModuleProfile: preference("profile"),
      useSavedModuleSelection: () => [
        selection.getGuidedModuleSelection(
          preferences.profile,
          preferences.setupProfile === preferences.profile,
        ),
        loaded.profile && loaded.selection,
      ],
      ...validation,
    },
    "@/lib/moduleSelection": selection,
    "@/lib/wizardInstallation": { useWizardInstallation: () => null },
    "@/lib/generated/manifest-modules": catalogue,
    "@/lib/commandBuilder": {
      buildCommands(input) {
        buildCalls.push(plain(input));
        return commands.buildCommands(input);
      },
      buildShareURL(input) {
        shares.push(plain(input));
        return commands.buildShareURL(input);
      },
    },
  });
  function render() {
    const nodes = [];
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
    // React settles updates to the rendering component before exposing its
    // controls. Keep that behavior explicit rather than relying on a second
    // manual test render to clear a superseded draft.
    let attempts = 0;
    do {
      assert.ok(attempts++ < 10, "component render updates must settle");
      cursor = 0;
      id = 0;
      nodes.length = 0;
      renderAgain = false;
      rendering = true;
      try {
        visit(component.CommandBuilderPanel());
      } finally {
        rendering = false;
      }
    } while (renderAgain);
    const find = (predicate) => {
      const node = nodes.find(predicate);
      assert.ok(node, "expected component element");
      return node;
    };
    return {
      nodes,
      command: () =>
        nodes
          .filter((node) => node.type === "code")
          .map((node) => text(node))
          .join("\n"),
      button: (label) =>
        find(
          (node) =>
            node.type === "button" &&
            (node.props["aria-label"] === label || text(node).trim() === label),
        ),
      input: (inputId) => find((node) => node.type === "input" && node.props.id === inputId),
      picker: (kind) => {
        const label = find((node) => node.type === "label" && text(node) === `Exclude ${kind}`);
        return find((node) => node.type === "select" && node.props.id === label.props.htmlFor);
      },
      alert: () =>
        nodes
          .filter((node) => node.props.role === "alert")
          .map(text)
          .join("\n"),
      status: () =>
        nodes
          .filter((node) => node.props.role === "status")
          .map(text)
          .join("\n"),
    };
  }
  return { render, preferences, loaded, buildCalls, shares, copies };
}

test("panel pickers derive all categories and tags from the production catalogue", () => {
  const item = fixture();
  const view = item.render();
  for (const kind of ["category", "tag"]) {
    const picker = view.picker(kind);
    const options = view.nodes.filter((node) => node.type === "option" && node.props.value);
    const expected =
      kind === "category"
        ? new Set(catalogue.manifestModules.map((module) => module.category))
        : new Set(catalogue.manifestModules.flatMap((module) => module.tags));
    const children = picker.props.children.flat(Infinity).filter((node) => node?.type === "option");
    assert.deepEqual(
      new Set(children.filter((node) => node.props.value).map((node) => node.props.value)),
      expected,
    );
    assert.ok(options.length >= expected.size);
  }
  assert.match(view.command(), /--mode safe/);
  assert.equal(view.button("Share link").props.disabled, false);
});

test("adding and removing groups updates the copyable exact installer flags", async () => {
  const item = fixture();
  item
    .render()
    .picker("tag")
    .props.onChange({ target: { value: "maintenance" } });
  let view = item.render();
  assert.match(view.command(), /--skip "acfs.nightly"/);
  assert.equal(view.button("Share link").props.disabled, true);
  await view.button("Copy Run installer command").props.onClick();
  assert.match(item.copies.at(-1), /--skip "acfs.nightly"/);
  view.picker("category").props.onChange({ target: { value: "network" } });
  view = item.render();
  assert.match(view.command(), /--skip "network.tailscale"/);
  assert.match(view.command(), /--skip "network.ssh_keepalive"/);
  view.button("Remove excluded tag maintenance").props.onClick();
  view = item.render();
  assert.doesNotMatch(view.command(), /acfs.nightly/);
  assert.match(view.command(), /network.tailscale/);
  view.button("Clear all exclusions").props.onClick();
  view = item.render();
  assert.doesNotMatch(view.command(), /--skip/);
  assert.equal(view.button("Share link").props.disabled, false);
});

test("a dependency conflict suppresses command building without throwing or granting noDeps", () => {
  const item = fixture();
  item
    .render()
    .picker("category")
    .props.onChange({ target: { value: "lang" } });
  const previous = item.buildCalls.length;
  const view = item.render();
  assert.match(view.alert(), /Install plan blocked/);
  assert.match(view.alert(), /depends on skipped/);
  assert.equal(view.command(), "");
  assert.equal(
    item.buildCalls.length,
    previous,
    "invalid selections must not reach the command builder",
  );
  assert.equal(view.button("Share link").props.disabled, true);
  view.button("Clear all exclusions").props.onClick();
  assert.ok(item.render().command());
});

test("custom exclusions survive profile switches but never silently enter a lossy share link", () => {
  const item = fixture();
  item
    .render()
    .picker("tag")
    .props.onChange({ target: { value: "maintenance" } });
  item.preferences.profile = "minimal";
  const view = item.render();
  assert.match(view.command(), /--profile "minimal"/);
  assert.match(view.command(), /--skip "acfs.nightly"/);
  view.button("Share link").props.onClick(); // Guard still applies to direct handler invocation.
  assert.equal(item.shares.length, 0);
  assert.equal(item.copies.length, 0);
  view.button("Clear all exclusions").props.onClick();
  item.render().button("Share link").props.onClick();
  assert.equal(item.shares.length, 1);
});

test("switching to a conflicting explicit profile blocks commands until exclusion removal", () => {
  const item = fixture();
  item
    .render()
    .picker("category")
    .props.onChange({ target: { value: "cloud" } });
  assert.ok(item.render().command());
  item.preferences.profile = "cloud-only";
  const view = item.render();
  assert.equal(view.command(), "");
  assert.match(view.alert(), /was requested/);
  view.button("Remove excluded category cloud").props.onClick();
  assert.match(item.render().command(), /--profile "cloud-only"/);
});

test("the panel can preview exclusions without a stored host and rejects unknown option values", () => {
  const item = fixture();
  item.preferences.ip = "";
  item
    .render()
    .picker("tag")
    .props.onChange({ target: { value: "maintenance" } });
  let view = item.render();
  assert.equal(view.command(), "");
  assert.equal(item.buildCalls.length, 0);
  view.picker("tag").props.onChange({ target: { value: "unknown-tag" } });
  item.preferences.ip = "203.0.113.42";
  view = item.render();
  assert.match(view.command(), /acfs.nightly/);
  assert.doesNotMatch(view.command(), /unknown-tag/);
  assert.deepEqual(item.buildCalls.at(-1).moduleSelection.skipTags, ["maintenance"]);
});

for (const profile of ["agents-only", "cloud-only", "stack-only"]) {
  test(`the ${profile} handoff retains opted-in setup modules and refuses a lossy share link`, async () => {
    const item = fixture();
    item.preferences.profile = profile;
    item.preferences.setupProfile = profile;
    const view = item.render();
    await view.button("Copy Run installer command").props.onClick();
    const copied = item.copies.at(-1);
    for (const id of ["base.system", "users.ubuntu", "base.filesystem", "acfs.doctor"]) {
      assert.ok(copied.includes(`--only "${id}"`), `${id} must survive the guided handoff`);
    }
    if (profile === "cloud-only") {
      for (const id of ["cloud.wrangler", "cloud.supabase", "cloud.vercel"]) {
        assert.ok(copied.includes(`--only "${id}"`));
      }
      assert.doesNotMatch(copied, /--only-phase/, "cloud-only must not expand to database tools");
    } else {
      assert.ok(copied.includes(`--only-phase "${profile === "agents-only" ? "7" : "9"}"`));
    }
    assert.doesNotMatch(copied, /--profile/);
    assert.match(view.command(), /acfs doctor/);
    assert.doesNotMatch(view.command(), /\bonboard\b/);
    assert.equal(view.button("Share link").props.disabled, true);
    view.button("Share link").props.onClick();
    assert.equal(item.shares.length, 0, "a direct handler call cannot share a widened selection");
    assert.deepEqual(item.copies, [copied]);
  });
}

test("local exclusions compose with guided roots and cannot silently remove required setup", async () => {
  const item = fixture();
  item.preferences.profile = "agents-only";
  item.preferences.setupProfile = "agents-only";
  let view = item.render();
  await view.button("Copy Run installer command").props.onClick();
  const original = item.copies.at(-1);
  view.picker("tag").props.onChange({ target: { value: "maintenance" } });
  view = item.render();
  assert.match(view.command(), /--only "acfs.doctor"/);
  assert.match(view.command(), /--skip "acfs.nightly"/);
  view.picker("category").props.onChange({ target: { value: "acfs" } });
  const previousCalls = item.buildCalls.length;
  view = item.render();
  assert.equal(view.command(), "");
  assert.match(view.alert(), /acfs\.doctor/);
  assert.equal(item.buildCalls.length, previousCalls);
  view.button("Clear all exclusions").props.onClick();
  view = item.render();
  await view.button("Copy Run installer command").props.onClick();
  assert.equal(item.copies.at(-1), original);
  assert.equal(view.button("Share link").props.disabled, true);
});

test("setup authorization follows the saved profile and is restored only for that profile", () => {
  const item = fixture();
  item.preferences.profile = "agents-only";
  item.preferences.setupProfile = "agents-only";
  assert.match(item.render().command(), /--only "acfs.doctor"/);
  item.preferences.profile = "cloud-only";
  let view = item.render();
  assert.match(view.command(), /--profile "cloud-only"/);
  assert.doesNotMatch(view.command(), /acfs doctor/);
  assert.equal(view.button("Share link").props.disabled, false);
  item.preferences.profile = "agents-only";
  view = item.render();
  assert.match(view.command(), /--only "acfs.doctor"/);
  assert.equal(view.button("Share link").props.disabled, true);
  item.preferences.setupProfile = null;
  view = item.render();
  assert.match(view.command(), /--profile "agents-only"/);
  assert.doesNotMatch(view.command(), /acfs doctor/);
  assert.equal(view.button("Share link").props.disabled, false);
});

for (const key of ["ip", "os", "mode", "username", "ref", "profile", "selection"]) {
  test(`no copyable command or share link is exposed while ${key} is loading`, () => {
    const item = fixture();
    item.loaded[key] = false;
    const view = item.render();
    assert.equal(view.command(), "");
    assert.equal(item.buildCalls.length, 0);
    assert.match(view.status(), /Loading.*installation/);
    assert.equal(view.nodes.some((node) => node.type === "button" && text(node) === "Share link"), false);
  });
}

test("settled preferences replace hydration defaults before the first copyable command", async () => {
  const item = fixture();
  item.loaded.selection = false;
  item.loaded.username = false;
  item.loaded.ref = false;
  assert.equal(item.render().command(), "");
  item.preferences.profile = "cloud-only";
  item.preferences.setupProfile = "cloud-only";
  item.preferences.username = "dev-user";
  item.preferences.ref = "v1.2.3";
  item.loaded.selection = true;
  item.loaded.username = true;
  item.loaded.ref = true;
  const view = item.render();
  await view.button("Copy Run installer command").props.onClick();
  const copied = item.copies.at(-1);
  assert.match(copied, /TARGET_USER="dev-user"/);
  assert.match(copied, /--ref "v1\.2\.3"/);
  assert.match(copied, /--only "acfs.doctor"/);
  assert.match(copied, /--only "cloud.wrangler"/);
  assert.doesNotMatch(copied, /--only-phase/, "the cloud profile must retain its exact roots");
  assert.doesNotMatch(copied, /\/main\/|--profile "full"/);
});

test("observing another saved username permanently discards the previous uncommitted draft", async () => {
  const item = fixture();
  item.render().button("Advanced").props.onClick();
  let view = item.render();
  view.input("cb-user").props.onChange({ target: { value: "local-user" } });
  view = item.render();
  assert.equal(item.preferences.username, "ubuntu", "typing has not committed the draft");
  await view.button("Copy Run installer command").props.onClick();
  assert.match(item.copies.at(-1), /TARGET_USER="local-user"/);

  item.preferences.username = "team-user";
  view = item.render();
  assert.equal(view.input("cb-user").props.value, "team-user");
  await view.button("Copy Run installer command").props.onClick();
  assert.match(item.copies.at(-1), /TARGET_USER="team-user"/);

  item.preferences.username = "ubuntu";
  view = item.render();
  assert.equal(view.input("cb-user").props.value, "ubuntu");
  await view.button("Copy Run installer command").props.onClick();
  assert.doesNotMatch(item.copies.at(-1), /TARGET_USER=|local-user|team-user/);
  assert.equal(item.buildCalls.at(-1).username, "ubuntu");
});

test("observing another saved ref permanently discards the previous uncommitted draft", async () => {
  const item = fixture();
  item.preferences.ref = "v1.2.3";
  item.render().button("Advanced").props.onClick();
  let view = item.render();
  view.input("cb-ref").props.onChange({ target: { value: "v1.2.3-local" } });
  view = item.render();
  assert.equal(item.preferences.ref, "v1.2.3", "typing has not committed the draft");
  await view.button("Copy Run installer command").props.onClick();
  assert.match(item.copies.at(-1), /--ref "v1\.2\.3-local"/);

  item.preferences.ref = "v2.0.0";
  view = item.render();
  assert.equal(view.input("cb-ref").props.value, "v2.0.0");
  await view.button("Copy Run installer command").props.onClick();
  assert.match(item.copies.at(-1), /--ref "v2\.0\.0"/);

  item.preferences.ref = "v1.2.3";
  view = item.render();
  assert.equal(view.input("cb-ref").props.value, "v1.2.3");
  await view.button("Copy Run installer command").props.onClick();
  assert.match(item.copies.at(-1), /--ref "v1\.2\.3"/);
  assert.doesNotMatch(item.copies.at(-1), /v1\.2\.3-local|v2\.0\.0/);
  assert.equal(item.buildCalls.at(-1).ref, "v1.2.3");
});
