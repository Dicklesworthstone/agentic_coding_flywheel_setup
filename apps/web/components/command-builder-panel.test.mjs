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
const context = createContext({});
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
  const module = { exports: {} };
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
    module,
    module.exports,
  );
  return module.exports;
}
const catalogue = loadSource(new URL("../lib/generated/manifest-modules.ts", import.meta.url));
// The catalogue and resolver are the production source, not fixture metadata.
const selection = loadSource(new URL("../lib/moduleSelection.ts", import.meta.url), {
  "./generated/manifest-modules": catalogue,
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
  const states = [];
  const preferences = {
    ip: "203.0.113.42",
    os: "linux",
    mode: "safe",
    username: "ubuntu",
    ref: null,
    profile: "full",
  };
  const buildCalls = [];
  const shares = [];
  const copies = [];
  const jsx = (type, props) => ({ type, props: props ?? {} });
  const preference = (key) => () => [
    preferences[key],
    (value) => {
      preferences[key] = value;
    },
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
            states[index] = typeof next === "function" ? next(states[index]) : next;
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
      isValidIP: (value) => /^\d+\.\d+\.\d+\.\d+$/.test(value),
      normalizeGitRef: (value) => value,
      normalizeSSHUsername: (value) => value,
    },
    "@/lib/moduleSelection": selection,
    "@/lib/wizardInstallation": { useWizardInstallation: () => null },
    "@/lib/generated/manifest-modules": catalogue,
    "@/lib/commandBuilder": {
      buildCommands(input) {
        buildCalls.push(plain(input));
        return [
          {
            id: "installer",
            label: "Run installer",
            description: "Fixture command row",
            runLocation: "vps",
            command: `bash install.sh --mode ${input.mode} ${selection.buildInstallSelectorArgs(input.moduleSelection).join(" ")}`,
          },
        ];
      },
      buildShareURL(input) {
        shares.push(plain(input));
        return "https://example.invalid/profile";
      },
    },
  });
  function render() {
    cursor = 0;
    id = 0;
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
    visit(component.CommandBuilderPanel());
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
      picker: (kind) => {
        const label = find((node) => node.type === "label" && text(node) === `Exclude ${kind}`);
        return find((node) => node.type === "select" && node.props.id === label.props.htmlFor);
      },
      alert: () =>
        nodes
          .filter((node) => node.props.role === "alert")
          .map(text)
          .join("\n"),
    };
  }
  return { render, preferences, buildCalls, shares, copies };
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
