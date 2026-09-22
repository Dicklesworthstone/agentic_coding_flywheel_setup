/**
 * Dependency-free integration harness for the actual wizard TypeScript modules.
 * Run with Node 22.16+: node --experimental-vm-modules tests/unit/test_wizard_progress_storage.mjs
 * Storage, progress, preferences, input validation and privacy/navigation code
 * execute together. React/query/browser APIs and provider/profile catalogues
 * are fixtures; this does not replace a real browser or the full Bun suite.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { SourceTextModule, SyntheticModule, createContext } from 'node:vm';
import { test } from 'node:test';

const sources = Object.fromEntries(
  ['wizardSteps', 'userPreferences', 'utils', 'inputValidation'].map((name) => [
    `./${name}`,
    readFileSync(new URL(`../../apps/web/lib/${name}.ts`, import.meta.url), 'utf8'),
  ]),
);
const key = 'agent-flywheel-wizard-completed-steps';
const checklistKey = 'agent-flywheel-create-vps-checklist';
const servicesKey = 'agent-flywheel-checked-services';
const requiredChecklist = ['ubuntu', 'region', 'password', 'created'];

async function browser({ stored, search = '', blockStorage = false, blockHistory = false } = {}) {
  const storage = new Map(stored === undefined ? [] : [[key, JSON.stringify(stored)]]);
  const events = [];
  const controls = { blockStorage, blockHistory };
  const target = new EventTarget();
  let url = new URL(`https://example.test/wizard/os-selection${search}`);
  let sanitizeHistory = (value) => value;
  const localStorage = {
    getItem(name) { return storage.get(name) ?? null; },
    setItem(name, value) {
      if (controls.blockStorage) throw new Error('storage blocked');
      storage.set(name, String(value));
    },
    removeItem(name) {
      if (controls.blockStorage) throw new Error('storage blocked');
      storage.delete(name);
    },
  };
  const window = {
    get location() { return url; },
    localStorage,
    history: {
      state: { nextRouterState: 'preserved' },
      replaceState(state, _title, next) {
        if (controls.blockHistory) throw new Error('history blocked');
        const sanitized = sanitizeHistory(next, url.href);
        this.state = state;
        url = new URL(sanitized, url);
      },
    },
    addEventListener: target.addEventListener.bind(target),
    removeEventListener: target.removeEventListener.bind(target),
    dispatchEvent(event) { events.push(event); return target.dispatchEvent(event); },
  };
  const context = createContext({ window, localStorage, URL, URLSearchParams, Event, CustomEvent });
  const cache = new Map();
  const queries = new Map();
  const queryClient = {
    getQueryData(queryKey) { return cache.get(JSON.stringify(queryKey)); },
    setQueryData(queryKey, value) { cache.set(JSON.stringify(queryKey), value); },
    invalidateQueries({ queryKey }) {
      const query = queries.get(JSON.stringify(queryKey));
      if (query) this.setQueryData(queryKey, query());
    },
    async cancelQueries() {},
  };
  const modules = {
    '@tanstack/react-query': {
      useMutation(options) { return { mutate: options.mutationFn }; },
      useQuery({ queryKey, queryFn }) {
        queries.set(JSON.stringify(queryKey), queryFn);
        const data = queryFn();
        queryClient.setQueryData(queryKey, data);
        return { data, status: 'success' };
      },
      useQueryClient() { return queryClient; },
    },
    react: {
      createContext() { return {}; }, useCallback(fn) { return fn; },
      useContext() {}, useEffect(fn) { fn(); }, useMemo(fn) { return fn(); },
      useState(initial) { return [initial, () => {}]; },
    },
    clsx: { clsx: (...values) => values.join(' ') },
    'tailwind-merge': { twMerge: (value) => value },
    './installerCheckpoint': { isRenderedCheckpointComplete() { return false; } },
    './generated/manifest-modules': { manifestSelectionProfiles: [{ id: 'full' }, { id: 'minimal' }] },
    './wizardInstallation': {
      useInstallationPreference(saved) { return saved; }, useWizardInstallation() { return null; },
    },
    './vpsProviders': {
      VPS_PROVIDERS: [],
      validateUbuntuImage(value) {
        return { status: /^(?:22\.04|24\.04|25\.10|26\.04)$/.test(value) ? 'known' : 'unknown' };
      },
    },
  };
  const moduleCache = new Map();
  function load(name) {
    if (moduleCache.has(name)) return moduleCache.get(name);
    let module;
    if (Object.hasOwn(sources, name)) {
      module = new SourceTextModule(stripTypeScriptTypes(sources[name]), { context, identifier: name });
    } else {
      assert.ok(Object.hasOwn(modules, name), `unexpected dependency: ${name}`);
      const values = modules[name];
      module = new SyntheticModule(Object.keys(values), function () {
        for (const [key, value] of Object.entries(values)) this.setExport(key, value);
      }, { context, identifier: name });
    }
    moduleCache.set(name, module);
    return module;
  }
  const module = load('./wizardSteps');
  await module.link(load);
  await module.evaluate();
  const utils = load('./utils').namespace;
  sanitizeHistory = utils.sanitizeSensitiveNavigationUrl;
  return {
    api: module.namespace, prefs: load('./userPreferences').namespace, utils,
    controls, context, events, storage, window, queryClient,
    steps: () => Array.from(module.namespace.getCompletedSteps()),
    params: () => url.searchParams,
    navigate(path) {
      window.history.replaceState(window.history.state, '', utils.withCurrentSearch(path));
      window.dispatchEvent(new Event('popstate'));
    },
    storageEvent(key) {
      const event = new Event('storage');
      Object.defineProperty(event, 'key', { value: key });
      window.dispatchEvent(event);
    },
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
  const b = await browser({ stored: [1], blockStorage: true, search: '?utm_source=test&ip=192.0.2.1#guide' });
  b.api.markStepComplete(2);
  b.controls.blockStorage = false;
  b.api.markStepComplete(3);
  assert.deepEqual(b.steps(), [1, 2, 3]);
  assert.equal(b.storage.get(key), '[1,2,3]');
  assert.equal(b.params().get('steps'), null);
  assert.equal(b.params().get('stepsBase'), null);
  assert.equal(b.params().get('ip'), null);
  assert.equal(b.params().get('utm_source'), 'test');
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

test('fallback remains authoritative through real privacy-safe route navigation', async () => {
  const b = await browser({ stored: [1], blockStorage: true });
  b.api.markStepComplete(2);
  b.navigate('/wizard/generate-ssh-key');
  assert.deepEqual(b.steps(), [1, 2]);
  assert.equal(b.params().get('stepsBase'), '1');
  assert.equal(b.utils.urlContainsSensitiveState(b.window.location.href), false);
  b.api.markStepComplete(3);
  b.navigate('/wizard/rent-vps');
  assert.deepEqual(b.steps(), [1, 2, 3]);
});

test('explicit fallback resets survive route navigation and reload', async () => {
  const b = await browser({ stored: [1, 2, 3], blockStorage: true });
  b.api.setCompletedSteps([]);
  b.navigate('/wizard/os-selection');
  assert.equal(b.params().get('steps'), '');
  assert.deepEqual(b.steps(), []);
  const reloaded = await browser({ stored: [1, 2, 3], search: `?${b.params()}` });
  assert.deepEqual(reloaded.steps(), []);
});

test('an explicit destination step list cannot inherit an unrelated fallback baseline', async () => {
  const b = await browser({ stored: [1], blockStorage: true });
  b.api.setCompletedSteps([1, 2]);
  b.navigate('/wizard/rent-vps?steps=1,2,3');
  assert.equal(b.params().get('stepsBase'), null);
  assert.deepEqual(b.steps(), [1]);
});

test('fallback metadata cannot carry hosts, arbitrary text, credentials, or unbounded lists', async () => {
  const b = await browser();
  for (const value of ['192.0.2.1', 'operator-name', 'token=example', '1,'.repeat(80) + '2', '0', '-1']) {
    const search = `?stepsBase=${encodeURIComponent(value)}`;
    assert.equal(b.utils.queryContainsSensitiveState(search), true, value);
    assert.equal(new URLSearchParams(b.utils.stripSensitiveQueryState(search)).has('stepsBase'), false);
  }
  for (const value of ['', '-', '1,2,3']) {
    assert.equal(b.utils.queryContainsSensitiveState(`?stepsBase=${encodeURIComponent(value)}`), false);
  }
});

test('storage-blocked VPS setup can satisfy the real step validator without exposing host details', async () => {
  const b = await browser({ blockStorage: true });
  assert.equal(b.prefs.setVPSIP('192.0.2.42'), true);
  assert.equal(b.prefs.setCreateVPSChecklist(requiredChecklist), true);
  assert.deepEqual(Array.from(b.prefs.getCreateVPSChecklist()), requiredChecklist);
  assert.equal(b.api.validateStep(5).valid, true);
  b.navigate('/wizard/ssh-connect');
  assert.equal(b.api.validateStep(5).valid, true);
  assert.equal(b.window.location.href.includes('192.0.2.42'), false);
  assert.equal(b.storage.has(checklistKey), false);
});

test('checkbox hooks and validators share accepted state rather than only an optimistic query cache', async () => {
  const b = await browser({ blockStorage: true });
  b.prefs.setVPSIP('192.0.2.43');
  const [, setChecklist] = b.prefs.useCreateVPSChecklist();
  setChecklist(requiredChecklist);
  assert.equal(b.api.validateStep(5).valid, true);
  b.queryClient.setQueryData(b.prefs.userPreferencesKeys.createVPSChecklist, []);
  assert.equal(b.api.validateStep(5).valid, true);
  assert.deepEqual(Array.from(b.prefs.getCreateVPSChecklist()), requiredChecklist);
});

test('readiness selections remain usable and retain the actual Ubuntu source under blocked storage', async () => {
  const b = await browser({ blockStorage: true });
  const selection = {
    providerId: 'other', planName: 'custom plan', ubuntuVersion: '25.10',
    region: 'not-listed', targetAgents: 20, workloadId: 'heavy',
  };
  assert.equal(b.prefs.setVPSReadinessSelection(selection), true);
  assert.deepEqual(JSON.parse(JSON.stringify(b.prefs.getVPSReadinessSelection())), selection);
  assert.equal(b.prefs.setVPSReadinessSelection(null), false);
  assert.equal(b.prefs.getVPSReadinessSelection().ubuntuVersion, '25.10');
  assert.equal(b.window.location.search, '');
});

test('account toggles use accepted state even when the query cache is stale', async () => {
  const b = await browser({ blockStorage: true });
  const [, toggleService] = b.prefs.useCheckedServices();
  toggleService('claude');
  b.queryClient.setQueryData(b.prefs.userPreferencesKeys.checkedServices, ['stale-cache-value']);
  toggleService('codex');
  assert.deepEqual(Array.from(b.prefs.getCheckedServices()), ['claude', 'codex']);
  toggleService('claude');
  assert.deepEqual(Array.from(b.prefs.getCheckedServices()), ['codex']);
});

test('private fallback values and returned arrays cannot be mutated by their callers', async () => {
  const b = await browser({ blockStorage: true });
  const input = ['claude'];
  b.prefs.setCheckedServices(input);
  input.push('unexpected');
  const returned = b.prefs.getCheckedServices();
  returned.push('also-unexpected');
  assert.deepEqual(Array.from(b.prefs.getCheckedServices()), ['claude']);
});

test('a private fallback yields to a different durable value', async () => {
  const b = await browser({ blockStorage: true });
  b.storage.set(checklistKey, '[]');
  b.prefs.setCreateVPSChecklist(requiredChecklist);
  assert.deepEqual(Array.from(b.prefs.getCreateVPSChecklist()), requiredChecklist);
  b.storage.set(checklistKey, ' ["ubuntu"] ');
  assert.deepEqual(Array.from(b.prefs.getCreateVPSChecklist()), ['ubuntu']);
});

test('cross-tab storage events clear only the affected private fallback, including clear-all', async () => {
  const b = await browser({ blockStorage: true });
  b.prefs.useCreateVPSChecklist();
  b.prefs.setCreateVPSChecklist(requiredChecklist);
  b.prefs.setCheckedServices(['claude']);
  b.storageEvent(servicesKey);
  assert.deepEqual(Array.from(b.prefs.getCheckedServices()), []);
  assert.deepEqual(Array.from(b.prefs.getCreateVPSChecklist()), requiredChecklist);
  b.storageEvent(null);
  assert.deepEqual(Array.from(b.prefs.getCreateVPSChecklist()), []);
});

test('private fallback is document-scoped, and recovered durable writes survive new documents', async () => {
  const b = await browser({ blockStorage: true });
  b.prefs.setCreateVPSChecklist(requiredChecklist);
  const oldDocument = b.context.window;
  b.context.window = { ...oldDocument };
  assert.deepEqual(Array.from(b.prefs.getCreateVPSChecklist()), []);
  b.context.window = oldDocument;
  assert.deepEqual(Array.from(b.prefs.getCreateVPSChecklist()), requiredChecklist);
  b.controls.blockStorage = false;
  assert.equal(b.prefs.setCreateVPSChecklist(requiredChecklist), true);
  b.context.window = { ...oldDocument };
  assert.deepEqual(Array.from(b.prefs.getCreateVPSChecklist()), requiredChecklist);
});

test('server-side calls cannot create or observe document-private fallback state', async () => {
  const b = await browser({ blockStorage: true });
  b.prefs.setCheckedServices(['claude']);
  delete b.context.window;
  assert.equal(b.prefs.setCheckedServices(['codex']), false);
  assert.deepEqual(Array.from(b.prefs.getCheckedServices()), []);
});

const usernameKey = 'agent-flywheel-ssh-username';
const profileKey = 'agent-flywheel-module-profile';
const refKey = 'agent-flywheel-acfs-ref';

function seedNonDefaultInstallerPreferences(b) {
  b.storage.set(usernameKey, 'old_operator');
  b.storage.set(profileKey, 'minimal');
  b.storage.set(refKey, 'release/old');
}

function assertDefaultInstallerPreferences(b) {
  assert.equal(b.prefs.getSSHUsername(), 'ubuntu');
  assert.equal(b.prefs.getModuleProfile(), 'full');
  assert.equal(b.prefs.getACFSRef(), null);
}

test('restoring default installer choices overrides read-only non-default storage', async () => {
  const b = await browser({ blockStorage: true });
  seedNonDefaultInstallerPreferences(b);
  assert.equal(b.prefs.setSSHUsername('ubuntu'), true);
  assert.equal(b.prefs.setModuleProfile('full'), true);
  assert.equal(b.prefs.setACFSRef(null), true);
  assertDefaultInstallerPreferences(b);
  assert.equal(b.storage.get(usernameKey), 'old_operator');
  assert.equal(b.storage.get(profileKey), 'minimal');
  assert.equal(b.storage.get(refKey), 'release/old');
  assert.equal(b.params().get('user'), 'ubuntu');
  assert.equal(b.params().get('profile'), 'full');
  assert.equal(b.params().get('ref'), '', 'explicitly cleared pin is distinct from an absent override');
});

test('default installer choices survive privacy-safe navigation and reload', async () => {
  const b = await browser({ blockStorage: true });
  seedNonDefaultInstallerPreferences(b);
  b.prefs.setSSHUsername('ubuntu');
  b.prefs.setModuleProfile('full');
  b.prefs.setACFSRef('   ');
  b.navigate('/wizard/run-installer');
  assertDefaultInstallerPreferences(b);
  assert.equal(b.utils.urlContainsSensitiveState(b.window.location.href), false);
  const reloaded = await browser({ search: b.window.location.search, blockStorage: true });
  seedNonDefaultInstallerPreferences(reloaded);
  assertDefaultInstallerPreferences(reloaded);
});

test('saved-preference hooks expose accepted defaults, not old command inputs', async () => {
  const b = await browser({ blockStorage: true });
  seedNonDefaultInstallerPreferences(b);
  b.prefs.useSavedSSHUsername()[1]('ubuntu');
  b.prefs.useSavedModuleProfile()[1]('full');
  b.prefs.useSavedACFSRef()[1](null);
  assert.equal(b.queryClient.getQueryData(b.prefs.userPreferencesKeys.sshUsername), 'ubuntu');
  assert.equal(b.queryClient.getQueryData(b.prefs.userPreferencesKeys.moduleProfile), 'full');
  assert.equal(b.queryClient.getQueryData(b.prefs.userPreferencesKeys.acfsRef), null);
});

test('recovered storage saves defaults and removes their URL overrides', async () => {
  const b = await browser({ blockStorage: true });
  seedNonDefaultInstallerPreferences(b);
  b.prefs.setSSHUsername('ubuntu');
  b.prefs.setModuleProfile('full');
  b.prefs.setACFSRef(null);
  b.controls.blockStorage = false;
  assert.equal(b.prefs.setSSHUsername('ubuntu'), true);
  assert.equal(b.prefs.setModuleProfile('full'), true);
  assert.equal(b.prefs.setACFSRef(null), true);
  assertDefaultInstallerPreferences(b);
  assert.equal(b.params().has('user'), false);
  assert.equal(b.params().has('profile'), false);
  assert.equal(b.params().has('ref'), false);
  assert.equal(b.storage.get(usernameKey), 'ubuntu');
  assert.equal(b.storage.get(profileKey), 'full');
  assert.equal(b.storage.get(refKey), '');
});

test('an explicit ref reset can be replaced by a valid new pin but not invalid input', async () => {
  const b = await browser({ blockStorage: true });
  b.storage.set(refKey, 'release/old');
  assert.equal(b.prefs.setACFSRef(null), true);
  assert.equal(b.prefs.getACFSRef(), null);
  assert.equal(b.prefs.setACFSRef('bad ref'), false);
  assert.equal(b.prefs.getACFSRef(), null);
  assert.equal(b.prefs.setACFSRef('release/new'), true);
  assert.equal(b.prefs.getACFSRef(), 'release/new');
  assert.equal(b.utils.queryContainsSensitiveState('?ref='), false);
  assert.equal(b.utils.queryContainsSensitiveState('?ref=bad%20ref'), true);
});

test('failed storage and history writes do not claim that installer defaults were restored', async () => {
  const b = await browser({ blockStorage: true, blockHistory: true });
  seedNonDefaultInstallerPreferences(b);
  assert.equal(b.prefs.setSSHUsername('ubuntu'), false);
  assert.equal(b.prefs.setModuleProfile('full'), false);
  assert.equal(b.prefs.setACFSRef(null), false);
  assert.equal(b.prefs.getSSHUsername(), 'old_operator');
  assert.equal(b.prefs.getModuleProfile(), 'minimal');
  assert.equal(b.prefs.getACFSRef(), 'release/old');
  assert.equal(b.events.length, 0);
});
