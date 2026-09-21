/** Actual command-card handlers with explicit React/query/mutation-scheduler doubles. */
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const require = createRequire(import.meta.url);
const ts = require("typescript");
function fixture() {
  const entries = new Map();
  const cache = new Map();
  const events = [];
  const listeners = new Map();
  const writes = [];
  const analytics = [];
  const copies = [];
  const hooks = [];
  let cursor = 0;
  let effects = [];
  let latestMutation;
  const pending = [];
  let queryStatus = "success";
  let storageAvailable = true;
  let completeCalls = 0;
  const same = (a, b) => a && b && a.length === b.length && a.every((v, i) => Object.is(v, b[i]));
  const jsx = (type, props) => ({ type, props: props ?? {} });
  const keyFor = (queryKey) => JSON.stringify(queryKey);
  const queryClient = {
    setQueryData(key, value) {
      cache.set(keyFor(key), value);
      writes.push({ key, value });
    },
  };
  const dependencies = {
    react: {
      useState(initial) {
        const at = cursor++;
        hooks[at] ??= { value: initial };
        return [
          hooks[at].value,
          (value) => {
            hooks[at].value = value;
          },
        ];
      },
      useRef(initial) {
        const at = cursor++;
        hooks[at] ??= { current: initial };
        return hooks[at];
      },
      useCallback(fn) {
        cursor++;
        return fn;
      },
      useEffect(fn, deps) {
        const at = cursor++;
        if (!hooks[at] || !same(deps, hooks[at].deps)) {
          const previous = hooks[at]?.cleanup;
          hooks[at] = { deps };
          effects.push(() => {
            previous?.();
            hooks[at].cleanup = fn();
          });
        }
      },
    },
    "react/jsx-runtime": { jsx, jsxs: jsx, Fragment: "fragment" },
    "@tanstack/react-query": {
      useQueryClient: () => queryClient,
      useQuery(options) {
        const key = keyFor(options.queryKey);
        if (options.enabled !== false && queryStatus === "success" && !cache.has(key))
          cache.set(key, options.queryFn());
        return { data: cache.get(key), status: queryStatus };
      },
      // Model an async mutation settling after the observer's options update.
      // The replacement deliberately has no asynchronous mutation at all.
      useMutation(options) {
        latestMutation = options;
        return {
          mutate(value) {
            const result = options.mutationFn(value);
            pending.push(async () => latestMutation.onSuccess(await result));
          },
        };
      },
    },
    "lucide-react": Object.fromEntries(
      ["Check", "Copy", "Terminal", "CheckCircle2", "Server", "Monitor"].map((name) => [
        name,
        name,
      ]),
    ),
    "@/components/motion": {
      motion: { div: "motion-div" },
      AnimatePresence: "presence",
      springs: { snappy: {} },
    },
    "@/components/ui/button": { Button: "button" },
    "@/components/ui/checkbox": { Checkbox: "checkbox" },
    "@/components/ui/code-block": { CopyStatus: "copy-status" },
    "@/lib/utils": {
      cn: (...items) => items.filter(Boolean).join(" "),
      safeGetItem: (key) => (storageAvailable ? (entries.get(key) ?? null) : null),
      safeSetItem: (key, value) => {
        if (!storageAvailable) return false;
        entries.set(key, value);
        return true;
      },
    },
    "@/lib/userPreferences": { useUserOS: () => ["linux"], useDetectedOS: () => "linux" },
    "@/lib/hooks/useReducedMotion": { useReducedMotion: () => false },
    "@/lib/hooks/useCopyFeedback": {
      useCopyFeedback: () => ({
        state: "idle",
        copy: async (value) => {
          copies.push(value);
          return true;
        },
      }),
    },
    "@/lib/analytics": {
      commandCopyAnalyticsProperties: (value) => ({ length: value.length }),
      trackInteraction: (...args) => analytics.push(args),
    },
  };
  const source = readFileSync(new URL("./command-card.tsx", import.meta.url), "utf8");
  const compiled = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
      jsx: ts.JsxEmit.ReactJSX,
    },
    reportDiagnostics: true,
  });
  assert.deepEqual(
    compiled.diagnostics?.filter((item) => item.category === ts.DiagnosticCategory.Error),
    [],
  );
  const module = { exports: {} };
  const dispatch = (event) => {
    events.push(event);
    for (const listener of listeners.get(event.type) ?? []) listener(event);
  };
  runInNewContext(
    compiled.outputText,
    {
      module,
      exports: module.exports,
      require(name) {
        assert.ok(Object.hasOwn(dependencies, name), name);
        return dependencies[name];
      },
      CustomEvent: class {
        constructor(type, options) {
          this.type = type;
          this.detail = options.detail;
        }
      },
      window: {
        dispatchEvent: dispatch,
        addEventListener(type, listener) {
          if (!listeners.has(type)) listeners.set(type, new Set());
          listeners.get(type).add(listener);
        },
        removeEventListener(type, listener) {
          listeners.get(type)?.delete(listener);
        },
      },
    },
    { timeout: 5000 },
  );
  const props = {
    command: "acfs doctor",
    showCheckbox: true,
    persistKey: `flywheel-doctor-v2-${"a".repeat(64)}`,
    checkboxId: "flywheel-doctor",
    onComplete: () => {
      completeCalls++;
    },
  };
  function render() {
    cursor = 0;
    effects = [];
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
    visit(module.exports.CommandCard(props));
    effects.forEach((effect) => effect());
    return {
      nodes,
      checkbox: () => nodes.find((node) => node.type === "checkbox"),
      label: () => nodes.find((node) => node.type === "label"),
      copy: () => nodes.find((node) => node.type === "button"),
    };
  }
  return {
    props,
    entries,
    cache,
    writes,
    events,
    copies,
    analytics,
    listeners,
    render,
    dispatch,
    completeCalls: () => completeCalls,
    flush: async () => {
      while (pending.length) await pending.shift()();
    },
    status: (value) => {
      queryStatus = value;
    },
    storage: (value) => {
      storageAvailable = value;
    },
    unmount: () => {
      for (const hook of hooks) hook?.cleanup?.();
    },
  };
}

test("stable accessible checkbox ID stays separate from its opaque context key", () => {
  const f = fixture();
  const v = f.render();
  assert.equal(v.checkbox().props.id, "flywheel-doctor");
  assert.equal(v.label().props.htmlFor, v.checkbox().props.id);
  assert.equal(v.checkbox().props["data-acfs-completion-key"], f.props.persistKey);
  assert.equal(v.checkbox().props.checked, false);
});

test("local acknowledgement completes synchronously and cannot settle into a later context", async () => {
  const f = fixture();
  const oldKey = f.props.persistKey;
  f.render().checkbox().props.onCheckedChange(true);
  assert.equal(f.completeCalls(), 1, "No asynchronous mutation should defer acknowledgement");
  f.props.persistKey = `flywheel-doctor-v2-${"b".repeat(64)}`;
  f.props.command = "acfs doctor --deep";
  assert.equal(f.render().checkbox().props.checked, false);
  await f.flush();
  assert.equal(f.render().checkbox().props.checked, false);
  assert.equal(f.entries.get(`acfs-command-${oldKey}`), "true");
  assert.equal(f.entries.has(`acfs-command-${f.props.persistKey}`), false);
  assert.equal(f.completeCalls(), 1);
});

test("unchecking cannot be overwritten by an older completion microtask", async () => {
  const f = fixture();
  f.render().checkbox().props.onCheckedChange(true);
  f.render().checkbox().props.onCheckedChange(false);
  await f.flush();
  assert.equal(f.render().checkbox().props.checked, false);
  assert.equal(f.entries.get(`acfs-command-${f.props.persistKey}`), "false");
  assert.equal(f.completeCalls(), 1);
});

for (const status of ["pending", "error"]) {
  test(`cannot acknowledge a context before its storage query is ready: ${status}`, async () => {
    const f = fixture();
    f.status(status);
    const view = f.render();
    assert.equal(view.checkbox().props.disabled, true);
    view.checkbox().props.onCheckedChange(true);
    await f.flush();
    assert.equal(f.entries.size, 0);
    assert.equal(f.completeCalls(), 0);
  });
}

test("indeterminate is not a success acknowledgement", () => {
  const f = fixture();
  f.render().checkbox().props.onCheckedChange("indeterminate");
  assert.equal(f.entries.get(`acfs-command-${f.props.persistKey}`), "false");
  assert.equal(f.completeCalls(), 0);
});

test("storage clear events revoke current completion", async () => {
  const f = fixture();
  f.render().checkbox().props.onCheckedChange(true);
  await f.flush();
  assert.equal(f.render().checkbox().props.checked, true);
  f.entries.clear();
  f.dispatch({ type: "storage", key: null, newValue: null });
  assert.equal(f.render().checkbox().props.checked, false);
});

test("queued storage events read current bytes instead of reviving an older true payload", () => {
  const f = fixture();
  f.render();
  f.entries.set(`acfs-command-${f.props.persistKey}`, "false");
  f.dispatch({ type: "storage", key: `acfs-command-${f.props.persistKey}`, newValue: "true" });
  assert.equal(f.render().checkbox().props.checked, false);
});

test("ignores completion events for another key or with nonboolean values", () => {
  const f = fixture();
  f.render();
  f.dispatch({
    type: "acfs:command-completion-changed",
    detail: { key: `acfs-command-${f.props.persistKey}`, completed: "true" },
  });
  assert.equal(f.render().checkbox().props.checked, false);
  f.dispatch({
    type: "acfs:command-completion-changed",
    detail: { key: "other", completed: true },
  });
  assert.equal(f.render().checkbox().props.checked, false);
});

test("same-tab checked state works when browser storage refuses writes", async () => {
  const f = fixture();
  f.storage(false);
  f.render().checkbox().props.onCheckedChange(true);
  await f.flush();
  assert.equal(f.render().checkbox().props.checked, true);
  assert.equal(f.entries.size, 0);
});

test("leaving a card removes its synchronization listeners", () => {
  const f = fixture();
  f.render();
  assert.equal(f.listeners.get("storage").size, 1);
  f.unmount();
  assert.equal(f.listeners.get("storage").size, 0);
  assert.equal(f.listeners.get("acfs:command-completion-changed").size, 0);
});

test("unscoped cards retain their existing IDs and command copy behavior", async () => {
  const f = fixture();
  delete f.props.checkboxId;
  f.props.persistKey = "tutorial-command";
  const view = f.render();
  assert.equal(view.checkbox().props.id, "tutorial-command");
  await view.copy().props.onClick();
  assert.deepEqual(f.copies, ["acfs doctor"]);
});
