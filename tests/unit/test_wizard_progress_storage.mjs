/**
 * Dependency-free regression harness for the real wizard persistence module.
 * Run with Node 22.16+: node --experimental-vm-modules tests/unit/test_wizard_progress_storage.mjs
 * React/query/browser APIs are boundaries; the production TypeScript is loaded
 * and type-stripped, not copied or reimplemented. No dependency install needed.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { SourceTextModule, SyntheticModule, createContext } from 'node:vm';
import { test } from 'node:test';

const source = readFileSync(new URL('../../apps/web/lib/wizardSteps.ts', import.meta.url), 'utf8');
const key = 'agent-flywheel-wizard-completed-steps';

async function browser({ stored, search = '', blockStorage = false, blockHistory = false } = {}) {
  const storage = new Map(stored === undefined ? [] : [[key, JSON.stringify(stored)]]);
  const events = [];
  let url = new URL(`https://example.test/wizard/os-selection${search}`);
  const controls = { blockStorage, blockHistory };
  const window = {
    get location() { return url; },
    history: {
      state: { nextRouterState: 'preserved' },
      replaceState(state, _title, next) {
        if (controls.blockHistory) throw new Error('history blocked');
        this.state = state;
        url = new URL(next);
      },
    },
    dispatchEvent(event) { events.push(event); },
  };
  const context = createContext({ window, URL, URLSearchParams, CustomEvent });
  const modules = {
    '@tanstack/react-query': { useMutation() {}, useQuery() {}, useQueryClient() {} },
    react: { createContext() { return {}; }, useCallback() {}, useContext() {}, useEffect() {}, useState() {} },
    './installerCheckpoint': { isRenderedCheckpointComplete() { return false; } },
    './userPreferences': {
      detectOS() {}, getCreateVPSChecklist() {}, getUserOS() {}, getVPSIP() {},
      isCreateVPSChecklistComplete() {}, setUserOS() {},
    },
    './utils': {
      safeGetJSON(name) {
        try { return JSON.parse(storage.get(name) ?? 'null'); } catch { return null; }
      },
      safeSetJSON(name, value) {
        if (controls.blockStorage) return false;
        storage.set(name, JSON.stringify(value));
        return true;
      },
      // This boundary stands in for the separately tested privacy sanitizer.
      stripSensitiveQueryState(search) {
        const params = new URLSearchParams(search);
        for (const name of ['ip', 'user', 'ref']) params.delete(name);
        return params.toString();
      },
    },
  };
  const module = new SourceTextModule(stripTypeScriptTypes(source), { context });
  await module.link((name) => {
    assert.ok(Object.hasOwn(modules, name), `unexpected dependency: ${name}`);
    const values = modules[name];
    return new SyntheticModule(Object.keys(values), function () {
      for (const [key, value] of Object.entries(values)) this.setExport(key, value);
    }, { context });
  });
  await module.evaluate();
  return {
    api: module.namespace, controls, events, storage, window,
    steps: () => Array.from(module.namespace.getCompletedSteps()),
    params: () => url.searchParams,
  };
}

test('a failed write over existing storage remains visible and unlocks the next step', async () => {
  const b = await browser({ stored: [1], blockStorage: true });
  assert.equal(b.api.setCompletedSteps([1, 2]), true);
  assert.deepEqual(b.steps(), [1, 2]);
  assert.equal(b.api.canAccessWizardStep(b.steps(), 3), true);
  assert.equal(b.api.getNextReachableWizardStep(b.steps()).id, 3);
  assert.equal(b.storage.get(key), '[1]', 'do not delete or overwrite the durable snapshot');
  assert.deepEqual(Array.from(b.events.at(-1).detail.steps), [1, 2]);
});

test('consecutive failed writes accumulate rather than forgetting the preceding step', async () => {
  const b = await browser({ stored: [1], blockStorage: true });
  b.api.markStepComplete(2);
  b.api.markStepComplete(3);
  assert.deepEqual(b.steps(), [1, 2, 3]);
});

test('a fresh module after reload resumes the fallback against the same durable snapshot', async () => {
  const before = await browser({ stored: [1], blockStorage: true });
  before.api.markStepComplete(2);
  const after = await browser({ stored: [1], search: `?${before.params()}`, blockStorage: true });
  assert.deepEqual(after.steps(), [1, 2]);
});

test('fallback can reset progress even when an old storage entry cannot be changed', async () => {
  const b = await browser({ stored: [1, 2, 3], blockStorage: true });
  assert.equal(b.api.setCompletedSteps([]), true);
  assert.deepEqual(b.steps(), []);
  assert.equal(b.api.getNextReachableWizardStep(b.steps()).id, 1);
  const after = await browser({ stored: [1, 2, 3], search: `?${b.params()}`, blockStorage: true });
  assert.deepEqual(after.steps(), []);
});

test('ordinary stale URL progress never overrides valid durable progress', async () => {
  const b = await browser({ stored: [1, 2], search: '?steps=1,2,3,4' });
  assert.deepEqual(b.steps(), [1, 2]);
});

test('a changed durable snapshot supersedes an older fallback', async () => {
  const b = await browser({ stored: [1], blockStorage: true });
  b.api.setCompletedSteps([1, 2]);
  b.storage.set(key, '[1,2,3]');
  assert.deepEqual(b.steps(), [1, 2, 3]);
  b.storage.set(key, '[]');
  assert.deepEqual(b.steps(), [], 'another tab may intentionally reset progress');
});

test('recovered storage persists accumulated progress and removes fallback metadata', async () => {
  const b = await browser({ stored: [1], blockStorage: true, search: '?keep=yes&ip=192.0.2.1#guide' });
  b.api.markStepComplete(2);
  b.controls.blockStorage = false;
  b.api.markStepComplete(3);
  assert.deepEqual(b.steps(), [1, 2, 3]);
  assert.equal(b.storage.get(key), '[1,2,3]');
  assert.equal(b.params().get('steps'), null);
  assert.equal(b.params().get('stepsBase'), null);
  assert.equal(b.params().get('ip'), null);
  assert.equal(b.params().get('keep'), 'yes');
  assert.equal(b.window.location.hash, '#guide');
  assert.deepEqual(b.window.history.state, { nextRouterState: 'preserved' });
});

test('complete storage failure with no durable snapshot still uses the URL', async () => {
  const b = await browser({ blockStorage: true });
  assert.equal(b.api.setCompletedSteps([2, 1, 2, 99, -1, NaN]), true);
  assert.deepEqual(b.steps(), [1, 2]);
  const legacy = await browser({ search: '?steps=1,2' });
  assert.deepEqual(legacy.steps(), [1, 2]);
});

test('failure of both writes preserves old progress and emits no completion event', async () => {
  const b = await browser({ stored: [1], blockStorage: true, blockHistory: true });
  assert.equal(b.api.setCompletedSteps([1, 2]), false);
  assert.deepEqual(b.steps(), [1]);
  assert.equal(b.events.length, 0);
});

test('malformed fallback data cannot hide stored progress', async () => {
  for (const search of [
    '?steps=garbage&stepsBase=1', '?steps=1%2C%202&stepsBase=1',
    '?stepsBase=1', '?steps=1,2&stepsBase=not-a-snapshot',
  ]) {
    const b = await browser({ stored: [1], search });
    assert.deepEqual(b.steps(), [1], search);
  }
});

test('a successful storage write wins even if stale URL cleanup fails', async () => {
  const b = await browser({ stored: [1], blockStorage: true });
  b.api.setCompletedSteps([1, 2]);
  b.controls.blockStorage = false;
  b.controls.blockHistory = true;
  assert.equal(b.api.setCompletedSteps([1]), true);
  assert.deepEqual(b.steps(), [1]);
  b.controls.blockStorage = true;
  b.controls.blockHistory = false;
  assert.equal(b.api.setCompletedSteps([1, 2]), true);
  assert.deepEqual(b.steps(), [1, 2]);
});
