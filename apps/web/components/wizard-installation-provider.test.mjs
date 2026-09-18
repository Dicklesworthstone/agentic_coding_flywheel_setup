/** Real review/session and preference code; React/query/canonical-validator contracts are doubled. */
import { strict as assert } from 'node:assert';
import { webcrypto } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { test } from 'node:test';
import { createContext, runInContext } from 'node:vm';
const require = createRequire(import.meta.url);
const ts = require('typescript');
const plain = (value) => JSON.parse(JSON.stringify(value));
const key = 'acfs-reviewed-installation-pending-v1';
const text = (node) => Array.isArray(node) ? node.map(text).join(' ')
  : node && typeof node === 'object' ? text(node.props?.children) : typeof node === 'string' ? node : '';

function fixture(sessionEntries = new Map(), initialPath = '/wizard/run-installer') {
  const local = new Map([
    ['agent-flywheel-vps-ip', '203.0.113.7'], ['agent-flywheel-ssh-username', 'ubuntu'],
    ['agent-flywheel-module-profile', 'full'], ['agent-flywheel-install-mode', 'vibe'],
    ['agent-flywheel-user-os', 'linux'],
    ['agent-flywheel-vps-readiness-selection', JSON.stringify({ providerId: 'other', planName: 'custom plan',
      region: 'not-listed', ubuntuVersion: '24.04', targetAgents: 10, workloadId: 'standard' })],
  ]);
  const storageWrites = []; const queryWrites = []; let loaded = true; let path = initialPath;
  const storage = {
    getItem: (name) => sessionEntries.get(name) ?? null,
    setItem(name, value) { storageWrites.push([name, value]); sessionEntries.set(name, value); },
    removeItem(name) { storageWrites.push([name, null]); sessionEntries.delete(name); },
  };
  const window = new EventTarget();
  window.sessionStorage = storage;
  window.location = { href: 'https://example.invalid/wizard/run-installer', search: '' };
  window.history = { state: null, replaceState(_state, _unused, address) {
    window.location.href = address; window.location.search = new URL(address).search;
  } };
  const instances = new Map(); let instance; let index; let changed = false;
  const equal = (a, b) => a && b && a.length === b.length && a.every((value, n) => Object.is(value, b[n]));
  function slot() { const n = index++; return [instance, n]; }
  const react = {
    createContext: (value) => ({ value, Provider: Symbol('provider') }),
    useContext: (context) => context.value,
    useState(initial) {
      const [owner, n] = slot();
      if (!owner.slots[n]) owner.slots[n] = { value: typeof initial === 'function' ? initial() : initial };
      return [owner.slots[n].value, (next) => {
        const previous = owner.slots[n].value; const value = typeof next === 'function' ? next(previous) : next;
        if (!Object.is(previous, value)) { owner.slots[n].value = value; changed = true; }
      }];
    },
    useRef(value) { const [owner, n] = slot(); return owner.slots[n] ??= { current: value }; },
    useMemo(fn, deps) {
      const [owner, n] = slot(); const previous = owner.slots[n];
      if (!previous || !equal(previous.deps, deps)) owner.slots[n] = { value: fn(), deps };
      return owner.slots[n].value;
    },
    useCallback(fn, deps) { return react.useMemo(() => fn, deps); },
    useEffect(fn, deps) {
      const [owner, n] = slot(); const previous = owner.slots[n];
      if (!previous || !equal(previous.deps, deps)) {
        owner.effects.push(() => { previous?.cleanup?.(); const cleanup = fn(); owner.slots[n].cleanup = cleanup; });
        owner.slots[n] = { deps, cleanup: previous?.cleanup };
      }
    },
  };
  const jsx = (type, props) => ({ type, props: props ?? {} });
  const vm = createContext({ window, URL, URLSearchParams, Event, TextDecoder, crypto: webcrypto, structuredClone });
  function load(url, dependencies) {
    const source = readFileSync(url, 'utf8');
    const compiled = ts.transpileModule(source, { fileName: url.pathname, reportDiagnostics: true,
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, jsx: ts.JsxEmit.ReactJSX } });
    assert.deepEqual((compiled.diagnostics ?? []).filter((entry) => entry.category === ts.DiagnosticCategory.Error), []);
    const module = { exports: {} };
    const invoke = runInContext(`(function(require,module,exports){${compiled.outputText}\n})`, vm, { timeout: 5000 });
    invoke((name) => { assert.ok(Object.hasOwn(dependencies, name), `Unexpected import ${name}`); return dependencies[name]; }, module, module.exports);
    return module.exports;
  }
  const catalogue = { manifestProvenance: { manifestSha256: 'a'.repeat(64), checksumsYamlSha256: 'b'.repeat(64) },
    manifestSelectionProfiles: ['full', 'minimal', 'agents-only', 'cloud-only', 'stack-only', 'safe', 'vibe'].map((id) =>
      ({ id, label: id, onlyModules: [], onlyPhases: [], ...(['safe', 'vibe'].includes(id) ? { mode: id } : {}) })) };
  const contextModule = load(new URL('../lib/wizardInstallation.ts', import.meta.url), { react });
  const queryClient = { invalidateQueries() {}, getQueryData() { return undefined; },
    setQueryData(queryKey, value) { queryWrites.push([plain(queryKey), plain(value)]); } };
  const preferences = load(new URL('../lib/userPreferences.ts', import.meta.url), {
    react, './wizardInstallation': contextModule,
    '@tanstack/react-query': { useQuery: ({ queryFn }) => ({ data: queryFn(), status: loaded ? 'success' : 'pending' }), useQueryClient: () => queryClient },
    './inputValidation': {
      isValidIP: (value) => /^203\.0\.113\.\d+$/.test(value),
      normalizeGitRef: (value) => typeof value === 'string' && /^[a-zA-Z0-9/_.-]+$/.test(value.trim()) ? value.trim() : null,
      normalizeSSHUsername: (value) => typeof value === 'string' && /^[a-z][a-z0-9_-]*$/.test(value.trim()) ? value.trim() : null,
    },
    './utils': {
      safeGetItem: (name) => local.get(name) ?? null,
      safeGetJSON: (name) => local.has(name) ? JSON.parse(local.get(name)) : null,
      safeSetItem: (name, value) => { local.set(name, value); return true; },
      safeSetJSON: (name, value) => { local.set(name, JSON.stringify(value)); return true; },
      stripSensitiveQueryState: (search) => search, urlContainsSensitiveState: () => false,
    },
    './vpsProviders': { VPS_PROVIDERS: [], validateUbuntuImage: () => ({ status: 'supported' }) },
    './generated/manifest-modules': catalogue,
  });
  let validate = true; let revision = ''; let commandRevision = '';
  const command = (mode, ref, username, selection) => `${mode}|${ref ?? 'main'}|${username}|${JSON.stringify(selection)}`;
  const commands = { buildInstallCommand: (...args) => command(...args) + commandRevision,
    buildTeamProfileImportDiff(source) {
      return { schema: 'acfs.team-profile-import-diff.v1', dryRun: true, ok: validate,
        profile: { profileId: source.profileId, displayName: source.displayName },
        findings: validate ? [] : [{ code: 'team_profile_manifest_mismatch' }],
        installerCommand: { command: command(source.install.mode, source.install.ref.value === 'main' ? null : source.install.ref.value,
          source.providerDefaults.sshUser, { profile: source.install.profile, onlyModules: source.install.modules.only,
            onlyPhases: source.install.modules.onlyPhases, skipModules: source.install.modules.skip, noDeps: false }) + revision, changes: [] },
        skips: { allowed: validate, requested: source.install.modules.skip, warnings: [] },
        safeDefaults: { changes: [] }, dependencyClosure: [], secretSlots: { required: [], optional: [] },
        incompatibilities: [], refusals: [] };
    } };
  const core = load(new URL('../lib/teamProfileImport.ts', import.meta.url), {
    './commandBuilder': commands, './generated/manifest-modules': catalogue,
  });
  const component = load(new URL('./wizard-installation-provider.tsx', import.meta.url), {
    react, 'react/jsx-runtime': { jsx, jsxs: jsx, Fragment: 'fragment' },
    'next/navigation': { usePathname: () => path },
    '@/components/ui/button': { Button: 'button' },
    '@/components/team-profile-import-panel': { TeamProfileImportPanel: 'review-panel' },
    '@/lib/userPreferences': preferences, '@/lib/wizardInstallation': contextModule,
    '@/lib/teamProfileImport': core, '@/lib/commandBuilder': commands,
  });
  function invoke(name, fn, effects = true) {
    instance = instances.get(name) ?? { slots: [], effects: [] }; instances.set(name, instance);
    let result; let attempts = 0;
    do {
      assert.ok(attempts++ < 10, 'render loop'); changed = false; index = 0;
      result = fn();
      if (effects) { const queue = instance.effects.splice(0); for (const effect of queue) effect(); }
    } while (effects && changed);
    return result;
  }
  let tree;
  function render(effects = true) {
    tree = invoke('provider', () => component.WizardInstallationProvider({ children: jsx('wizard-children', {}) }), effects);
    contextModule.WizardInstallationContext.value = tree.type === contextModule.WizardInstallationContext.Provider ? tree.props.value : null;
    return tree;
  }
  function context() {
    return { targetHost: preferences.getVPSIP(), current: {
      providerSelection: preferences.getVPSReadinessSelection(), installMode: preferences.getInstallMode(),
      ref: preferences.getACFSRef(), username: preferences.getSSHUsername(), architecture: 'aarch64', ubuntuVersion: '24.04',
      moduleSelection: { profile: preferences.getModuleProfile() },
    } };
  }
  const profile = { profileId: 'team-example', displayName: 'Team Example', providerDefaults: { sshUser: 'team-user' },
    install: { mode: 'safe', profile: 'full', ref: { value: 'v1.2.3' },
      modules: { only: ['agents.claude'], onlyPhases: [], skip: ['acfs.nightly'], noDeps: false } } };
  return { render, core, context, profile, preferences, storage, sessionEntries, local, storageWrites, queryWrites, catalogue,
    session: () => contextModule.WizardInstallationContext.value,
    hooks: () => invoke('consumer', () => ({ user: preferences.useSSHUsername(), mode: preferences.useInstallMode(),
      ref: preferences.useACFSRef(), profile: preferences.useModuleProfile(), selection: preferences.useModuleSelection() })),
    review: () => core.reviewTeamProfileFile(new Blob([JSON.stringify(profile)]), context()),
    navigate: (value) => { path = value; return render(); },
    refuse: () => { validate = false; }, changeValidation: () => { revision = '-changed'; },
    changeCommand: () => { commandRevision = '-changed'; }, setLoaded: (value) => { loaded = value; },
    event: (name) => { window.dispatchEvent(new Event(name)); return render(); },
    unmount: () => { for (const item of instances.values()) for (const slot of item.slots) slot?.cleanup?.(); },
    hasChildren: () => text(tree).includes('never-used') || JSON.stringify(tree).includes('wizard-children'),
  };
}

async function activeFixture() {
  const f = fixture(); f.render();
  f.session().activate(await f.review(), f.context(), true); f.render();
  assert.equal(f.session().status, 'active'); return f;
}

test('SSR and unhydrated queries never expose a default command subtree', () => {
  const f = fixture(); const server = f.render(false);
  assert.match(text(server), /Loading installation/); assert.equal(f.hasChildren(), false);
  f.setLoaded(false); f.render(); assert.equal(f.session().status, 'loading'); assert.equal(f.hasChildren(), false);
  f.setLoaded(true); f.render(); assert.equal(f.session().status, 'saved'); assert.equal(f.hasChildren(), true);
});

test('review activation atomically changes every install preference without saved or query writes', async () => {
  const f = fixture(); f.render(); const localBefore = [...f.local]; const queriesBefore = plain(f.queryWrites);
  f.session().activate(await f.review(), f.context(), true); f.render();
  const values = f.hooks();
  assert.equal(values.user[0], 'team-user'); assert.equal(values.mode[0], 'safe'); assert.equal(values.ref[0], 'v1.2.3');
  assert.deepEqual(plain(values.selection[0]), { profile: 'full', onlyModules: ['agents.claude'], onlyPhases: [], skipModules: ['acfs.nightly'], noDeps: false });
  assert.equal(values.user[2], true); assert.equal(values.selection[1], true);
  assert.deepEqual([...f.local], localBefore); assert.deepEqual(f.queryWrites, queriesBefore);
  assert.deepEqual(f.storageWrites, [[key, 'review-required']]);
  assert.equal(f.preferences.getSSHUsername(), 'ubuntu', 'saved getter must not become an imported value');
});

for (const route of ['reconnect-ubuntu', 'verify-key-connection', 'status-check', 'launch-onboarding', 'windows-terminal-setup']) {
  test(`the approved username and exact selection survive client navigation to ${route}`, async () => {
    const f = await activeFixture(); const first = f.session().installation;
    f.navigate(`/wizard/${route}`);
    assert.equal(f.session().installation, first);
    assert.equal(f.hooks().user[0], 'team-user'); assert.equal(f.hasChildren(), true);
  });
}

test('visiting a public route leaves its preference consumers unchanged and retains the wizard session', async () => {
  const f = await activeFixture(); const first = f.session().installation;
  f.navigate('/'); assert.equal(f.session(), null); assert.equal(f.hooks().user[0], 'ubuntu');
  f.navigate('/wizard/run-installer'); assert.equal(f.session().installation, first);
});

test('reload cannot reconstruct an approval or silently show saved/default wizard commands', async () => {
  const first = await activeFixture(); first.unmount();
  const f = fixture(first.sessionEntries); f.render();
  assert.equal(f.session().status, 'review_required'); assert.equal(f.session().installation, null);
  assert.equal(f.hasChildren(), false); assert.match(text(f.render()), /Reloading never restores approval/);
  assert.equal(f.hooks().selection[1], false);
  f.session().activate(await f.review(), f.context(), true); f.render();
  assert.equal(f.session().status, 'active');
});

for (const [field, storageKey, value] of [
  ['host', 'agent-flywheel-vps-ip', '203.0.113.8'], ['username', 'agent-flywheel-ssh-username', 'different'],
  ['mode', 'agent-flywheel-install-mode', 'safe'], ['ref', 'agent-flywheel-acfs-ref', 'v2.0.0'],
  ['profile', 'agent-flywheel-module-profile', 'minimal'],
  ['provider', 'agent-flywheel-vps-readiness-selection', JSON.stringify({ ubuntuVersion: '26.04' })],
]) {
  test(`out-of-band ${field} edits block immediately and restoring old settings does not resurrect approval`, async () => {
    const f = await activeFixture(); const previous = f.local.get(storageKey);
    f.local.set(storageKey, value); f.event('storage');
    assert.equal(f.session().status, 'review_required'); assert.equal(f.hasChildren(), false);
    previous === undefined ? f.local.delete(storageKey) : f.local.set(storageKey, previous);
    f.render(); assert.equal(f.session().status, 'review_required');
  });
}

for (const event of ['popstate', 'pageshow', 'focus', 'acfs:user-preferences-updated']) {
  test(`${event} rechecks raw host state rather than trusting a stale query snapshot`, async () => {
    const f = await activeFixture(); f.local.set('agent-flywheel-vps-ip', '203.0.113.9'); f.event(event);
    assert.equal(f.session().status, 'review_required'); assert.equal(f.hasChildren(), false);
  });
}

test('late activation handlers re-read saved context before writing an approval guard', async () => {
  const f = fixture(); f.render(); const review = await f.review(); const context = f.context(); const activate = f.session().activate;
  f.local.set('agent-flywheel-vps-ip', '203.0.113.9');
  assert.throws(() => activate(review, context, true), /changed/); assert.deepEqual(f.storageWrites, []);
});

test('changing generated trust metadata or the regenerated command invalidates an active installation', async () => {
  for (const mutate of [(f) => { f.catalogue.manifestProvenance.manifestSha256 = 'c'.repeat(64); }, (f) => f.changeCommand()]) {
    const f = await activeFixture(); mutate(f); f.render();
    assert.equal(f.session().status, 'review_required'); assert.equal(f.hasChildren(), false);
  }
});

test('active settings controls cannot partially write the saved username, mode, ref or profile', async () => {
  const f = await activeFixture(); const before = [...f.local]; const values = f.hooks();
  values.user[1]('different'); values.mode[1]('vibe'); values.ref[1]('v9.0.0'); values.profile[1]('minimal'); f.render();
  assert.deepEqual([...f.local], before); assert.equal(f.session().status, 'active');
  assert.match(text(f.render()), /Discard the reviewed installation explicitly/);
});

test('explicit discard clears only its guard and restores the unchanged saved settings', async () => {
  const f = await activeFixture(); f.sessionEntries.set('unrelated', 'preserve'); const before = [...f.local];
  f.session().discard(); f.render();
  assert.equal(f.session().status, 'saved'); assert.equal(f.hooks().user[0], 'ubuntu');
  assert.deepEqual([...f.local], before); assert.deepEqual([...f.sessionEntries], [['unrelated', 'preserve']]);
  f.hooks().user[1]('new-user'); f.render(); assert.equal(f.hooks().user[0], 'new-user');
});

for (const failure of ['get', 'write', 'readback', 'remove']) {
  test(`sessionStorage ${failure} failure never exposes a restored/default installation`, async () => {
    const f = fixture(new Map([[key, 'review-required']])); f.render();
    if (failure === 'get') f.storage.getItem = () => { throw new Error('PRIVATE'); };
    if (failure === 'write') f.storage.setItem = () => { throw new Error('PRIVATE'); };
    if (failure === 'readback') f.storage.setItem = () => { f.storage.getItem = () => { throw new Error('PRIVATE'); }; };
    if (failure === 'remove') f.storage.removeItem = () => {};
    if (failure === 'remove') f.session().discard();
    if (failure === 'write' || failure === 'readback') {
      const review = await f.review(); assert.throws(() => f.session().activate(review, f.context(), true));
    }
    f.render(); assert.notEqual(f.session().status, 'saved'); assert.equal(f.hasChildren(), false);
    assert.ok(!text(f.render()).includes('PRIVATE'));
  });
}

test('an unresolved pathname cannot bypass hydration and render wizard commands', () => {
  const f = fixture(new Map(), null); f.render();
  assert.equal(f.hasChildren(), false); assert.equal(f.session().status, 'loading');
});

test('lost guard blocks commands instead of reviving the active object', async () => {
  const f = await activeFixture(); f.sessionEntries.delete(key); f.event('focus');
  assert.equal(f.session().status, 'review_required'); assert.equal(f.hasChildren(), false);
});

test('refused/changed canonical validation and fabricated reviews cannot activate a session', async () => {
  for (const mutation of ['refused', 'changed', 'fabricated']) {
    const f = fixture(); f.render(); const review = await f.review();
    if (mutation === 'refused') f.refuse();
    if (mutation === 'changed') f.changeValidation();
    assert.throws(() => f.session().activate(mutation === 'fabricated' ? plain(review) : review, f.context(), true));
    assert.deepEqual(f.storageWrites, []); assert.equal(f.session().installation, null);
  }
});

test('unmounted activation/discard callbacks cannot mutate storage', async () => {
  const f = fixture(); f.render(); const review = await f.review(); const session = f.session(); f.unmount();
  assert.throws(() => session.activate(review, f.context(), true), /Wait/); session.discard();
  assert.deepEqual(f.storageWrites, []);
});
