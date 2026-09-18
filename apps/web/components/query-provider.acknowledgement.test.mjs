/** Verify actual provider configuration; persistence-library behavior is not simulated as a browser run. */
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';
const require = createRequire(import.meta.url);
const ts = require('typescript');
function fixture(storage) {
  const slots = []; let cursor = 0; const persisters = [];
  const module = { exports: {} };
  const output = ts.transpileModule(readFileSync(new URL('./query-provider.tsx', import.meta.url), 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX }, reportDiagnostics: true,
  });
  assert.deepEqual(output.diagnostics?.filter((entry) => entry.category === ts.DiagnosticCategory.Error), []);
  const deps = {
    '@tanstack/react-query': { QueryClient: class {} },
    '@tanstack/react-query-persist-client': { PersistQueryClientProvider: 'persist-provider' },
    '@tanstack/query-sync-storage-persister': { createSyncStoragePersister: (input) => { persisters.push(input); return input; } },
    react: { useState(initial) { const at = cursor++; if (!(at in slots)) slots[at] = initial(); return [slots[at], () => {}]; } },
    'react/jsx-runtime': { jsx: (type, props) => ({ type, props }) },
    '../lib/wizardSteps': { wizardStepsKeys: { completedSteps: ['wizardSteps', 'completed'] } },
  };
  runInNewContext(output.outputText, { module, exports: module.exports,
    ...(storage ? { window: { localStorage: storage } } : {}), console: { warn: () => {} },
    require(name) { assert.ok(Object.hasOwn(deps, name)); return deps[name]; },
  });
  return { persisters, render() { cursor = 0; return module.exports.QueryProvider({ children: 'page' }); } };
}

test('command acknowledgement queries are never dehydrated, regardless of domain or value', () => {
  const filter = fixture().render().props.persistOptions.dehydrateOptions.shouldDehydrateQuery;
  for (const name of ['acfs-command-flywheel-doctor','acfs-command-flywheel-doctor-v2-' + 'a'.repeat(64),
    'acfs-command-run-flywheel-installer-v2-' + 'b'.repeat(64), 'acfs-command-auth-example']) {
    for (const data of [true, false]) assert.equal(filter({ queryKey: ['commandCompletion', name], state: { data } }), false);
  }
  assert.equal(filter({ queryKey: ['userPreferences', 'vpsIP'] }), false);
  assert.equal(filter({ queryKey: ['wizardSteps', 'completed'] }), false);
  assert.equal(filter({ queryKey: ['unrelated', 'data'] }), true);
});

test('old snapshots use a different buster without changing canonical storage flags', () => {
  const values = new Map([['acfs-command-example', 'true'], ['agent-flywheel-wizard-completed-steps', '[1]']]);
  const storage = { getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, value), removeItem: (key) => values.delete(key) };
  const f = fixture(storage); const output = f.render();
  assert.equal(output.props.persistOptions.buster, 'acfs-canonical-command-completion-v1');
  assert.deepEqual([...values], [['acfs-command-example','true'], ['agent-flywheel-wizard-completed-steps','[1]']]);
  assert.equal(f.persisters[0].key, 'acfs-query-cache');
});

test('provider/client/options identity remains stable across rerenders', () => {
  const f = fixture(); const first = f.render(); const next = f.render();
  assert.equal(first.props.client, next.props.client); assert.equal(first.props.persistOptions, next.props.persistOptions);
  assert.equal(f.persisters.length, 1); assert.equal(first.props.children, 'page');
});

test('server rendering and unavailable storage keep the no-op persistence path', () => {
  for (const storage of [undefined, { setItem() { throw new Error('blocked'); } }]) {
    const f = fixture(storage); const output = f.render();
    assert.equal(output.type, 'persist-provider'); assert.equal(f.persisters[0].storage, undefined);
    assert.equal(output.props.persistOptions.dehydrateOptions.shouldDehydrateQuery({ queryKey: ['commandCompletion','x'] }), false);
  }
});
