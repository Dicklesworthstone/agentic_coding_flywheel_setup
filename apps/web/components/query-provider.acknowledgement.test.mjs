/** Provider configuration and native TanStack persistence tests; not browser-renderer tests. */
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { runInNewContext } from "node:vm";

const require = createRequire(import.meta.url);
const ts = require("typescript");
const { QueryClient, dehydrate } = require("@tanstack/react-query");
const { createSyncStoragePersister } = require("@tanstack/query-sync-storage-persister");
const { persistQueryClientRestore, persistQueryClientSave } = require(
  "@tanstack/react-query-persist-client",
);
function fixture(storage, nativePersistence = false) {
  const slots = [];
  let cursor = 0;
  const persisters = [];
  const cjs = { exports: {} };
  const output = ts.transpileModule(
    readFileSync(new URL("./query-provider.tsx", import.meta.url), "utf8"),
    {
      compilerOptions: {
        target: ts.ScriptTarget.ES2022,
        module: ts.ModuleKind.CommonJS,
        jsx: ts.JsxEmit.ReactJSX,
      },
      reportDiagnostics: true,
    },
  );
  assert.deepEqual(
    output.diagnostics?.filter((entry) => entry.category === ts.DiagnosticCategory.Error),
    [],
  );
  const deps = {
    "@tanstack/react-query": { QueryClient: nativePersistence ? QueryClient : class {} },
    "@tanstack/react-query-persist-client": { PersistQueryClientProvider: "persist-provider" },
    "@tanstack/query-sync-storage-persister": {
      createSyncStoragePersister: (input) => {
        persisters.push(input);
        return nativePersistence ? createSyncStoragePersister(input) : input;
      },
    },
    react: {
      useState(initial) {
        const at = cursor++;
        if (!(at in slots)) slots[at] = initial();
        return [slots[at], () => {}];
      },
    },
    "react/jsx-runtime": { jsx: (type, props) => ({ type, props }) },
    "../lib/wizardSteps": { wizardStepsKeys: { completedSteps: ["wizardSteps", "completed"] } },
  };
  runInNewContext(output.outputText, {
    module: cjs,
    exports: cjs.exports,
    ...(storage ? { window: { localStorage: storage } } : {}),
    console: { warn: () => {} },
    require(name) {
      assert.ok(Object.hasOwn(deps, name));
      return deps[name];
    },
  });
  return {
    persisters,
    render() {
      cursor = 0;
      return cjs.exports.QueryProvider({ children: "page" });
    },
  };
}

test("command acknowledgement queries are never dehydrated, regardless of domain or value", () => {
  const filter = fixture().render().props.persistOptions.dehydrateOptions.shouldDehydrateQuery;
  for (const name of [
    "acfs-command-flywheel-doctor",
    "acfs-command-flywheel-doctor-v2-" + "a".repeat(64),
    "acfs-command-run-flywheel-installer-v2-" + "b".repeat(64),
    "acfs-command-auth-example",
  ]) {
    for (const data of [true, false])
      assert.equal(filter({ queryKey: ["commandCompletion", name], state: { data } }), false);
  }
  assert.equal(filter({ queryKey: ["userPreferences", "vpsIP"] }), false);
  assert.equal(filter({ queryKey: ["wizardSteps", "completed"] }), false);
  assert.equal(filter({ queryKey: ["installerCheckpoint", { host: "203.0.113.42" }] }), false);
  assert.equal(filter({ queryKey: ["unrelated", "data"] }), true);
});

test("old snapshots use a different buster without changing canonical storage flags", () => {
  const values = new Map([
    ["acfs-command-example", "true"],
    ["agent-flywheel-wizard-completed-steps", "[1]"],
  ]);
  const storage = {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    removeItem: (key) => values.delete(key),
  };
  const f = fixture(storage);
  const output = f.render();
  assert.equal(output.props.persistOptions.buster, "acfs-private-installation-checkpoints-v2");
  assert.deepEqual(
    [...values],
    [
      ["acfs-command-example", "true"],
      ["agent-flywheel-wizard-completed-steps", "[1]"],
    ],
  );
  assert.equal(f.persisters[0].key, "acfs-query-cache");
});

test("provider/client/options identity remains stable across rerenders", () => {
  const f = fixture();
  const first = f.render();
  const next = f.render();
  assert.equal(first.props.client, next.props.client);
  assert.equal(first.props.persistOptions, next.props.persistOptions);
  assert.equal(f.persisters.length, 1);
  assert.equal(first.props.children, "page");
});

test("server rendering and unavailable storage keep the no-op persistence path", () => {
  for (const storage of [
    undefined,
    {
      setItem() {
        throw new Error("blocked");
      },
    },
  ]) {
    const f = fixture(storage);
    const output = f.render();
    assert.equal(output.type, "persist-provider");
    assert.equal(f.persisters[0].storage, undefined);
    assert.equal(
      output.props.persistOptions.dehydrateOptions.shouldDehydrateQuery({
        queryKey: ["commandCompletion", "x"],
      }),
      false,
    );
  }
});

test("actual cache serialization excludes raw checkpoints and preserves unrelated queries", async () => {
  const values = new Map([["agent-flywheel-wizard-completed-steps", "[1,2]"]]);
  let saved;
  const written = new Promise((resolve) => {
    saved = resolve;
  });
  const storage = {
    getItem: (key) => values.get(key) ?? null,
    setItem(key, value) {
      values.set(key, value);
      if (key === "acfs-query-cache") saved();
    },
    removeItem: (key) => values.delete(key),
  };
  const { client, persistOptions } = fixture(storage, true).render().props;
  const privateInput = {
    host: "203.0.113.42",
    command: "bash install.sh --only agents.claude --user private-user --ref private-ref",
    manifestSha256: "a".repeat(64),
    checksumsYamlSha256: "b".repeat(64),
  };
  const checkpointKey = ["installerCheckpoint", privateInput];
  client.setQueryData(checkpointKey, {
    ...privateInput,
    persistKey: `run-flywheel-installer-v2-${"c".repeat(64)}`,
  });
  client.setQueryData(["commandCompletion", "acfs-command-example"], true);
  client.setQueryData(["unrelated", "public-help"], { title: "Getting started" });
  await persistQueryClientSave({ queryClient: client, ...persistOptions });
  await written;
  const serialized = values.get("acfs-query-cache");
  assert.ok(serialized);
  for (const value of [privateInput.host, privateInput.command, "installerCheckpoint", "private-user", "private-ref"])
    assert.ok(!serialized.includes(value), "private checkpoint was written to localStorage");
  assert.ok(!serialized.includes("acfs-command-example"));
  assert.ok(serialized.includes("Getting started"));
  assert.equal(values.get("agent-flywheel-wizard-completed-steps"), "[1,2]");

  const restored = fixture(storage, true).render().props;
  await persistQueryClientRestore({ queryClient: restored.client, ...restored.persistOptions });
  assert.equal(restored.client.getQueryData(checkpointKey), undefined);
  assert.deepEqual(restored.client.getQueryData(["unrelated", "public-help"]), {
    title: "Getting started",
  });
  client.clear();
  restored.client.clear();
});

test("restoring an old raw checkpoint snapshot removes it without clearing canonical wizard progress", async () => {
  const previous = new QueryClient({ defaultOptions: { queries: { gcTime: Infinity } } });
  const checkpointKey = ["installerCheckpoint", { host: "203.0.113.42", command: "private-command" }];
  previous.setQueryData(checkpointKey, { host: "203.0.113.42", command: "private-command" });
  const values = new Map([
    [
      "acfs-query-cache",
      JSON.stringify({
        timestamp: Date.now(),
        buster: "acfs-canonical-command-completion-v1",
        clientState: dehydrate(previous),
      }),
    ],
    ["agent-flywheel-wizard-completed-steps", "[1,2,3]"],
    ["acfs-command-example", "true"],
    ["agent-flywheel-install-mode", "safe"],
  ]);
  const storage = {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value),
    removeItem: (key) => values.delete(key),
  };
  const { client, persistOptions } = fixture(storage, true).render().props;
  await persistQueryClientRestore({ queryClient: client, ...persistOptions });
  assert.equal(client.getQueryData(checkpointKey), undefined);
  assert.equal(values.has("acfs-query-cache"), false);
  assert.deepEqual([...values], [
    ["agent-flywheel-wizard-completed-steps", "[1,2,3]"],
    ["acfs-command-example", "true"],
    ["agent-flywheel-install-mode", "safe"],
  ]);
  previous.clear();
  client.clear();
});
