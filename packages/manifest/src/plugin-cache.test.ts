import { strict as assert } from 'node:assert';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import {
  chmodSync, cpSync, existsSync, linkSync, mkdirSync, mkdtempSync, readFileSync,
  readdirSync, renameSync, statSync, symlinkSync, truncateSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { buildPluginInstallPlan, type PluginPlanInput } from './plugin-plan.js';
import { loadPluginInstallerCache, preparePluginInstallerCache, PluginCacheError, PLUGIN_CACHE_LIMITS } from './plugin-cache.js';

const NOW = Date.parse('2026-09-17T12:00:00.000Z');
const hash = (bytes: Buffer): string => createHash('sha256').update(bytes).digest('hex');
function fixture(sources = [Buffer.from('echo one\n'), Buffer.from('echo two\n')]) {
  const parent = mkdtempSync(join(tmpdir(), 'acfs-plugin-cache-'));
  const output = join(parent, 'portable-cache');
  const provenance = { packageId: 'example', version: '1.0.0', sourceCommit: 'a'.repeat(40), pluginSha256: 'b'.repeat(64) };
  const input: PluginPlanInput = {
    modules: sources.map((bytes, index) => ({ id: `plugin.example.tool${index}`, phase: 6,
      run_as: 'target_user', enabled_by_default: false, install: [],
      verify: [`command -v -- fixture${index} >/dev/null 2>&1`], plugin: provenance,
      verified_installer: { tool: `tool${index}`, url: `https://example.com/${hash(bytes)}.sh`, runner: 'bash', args: [] } })),
    firstPartyModules: [], installers: Object.fromEntries(sources.map((bytes, index) =>
      [`tool${index}`, { url: `https://example.com/${hash(bytes)}.sh`, sha256: hash(bytes) }])),
    target: { os: 'ubuntu', version: '26.04', arch: 'x86_64', libc: 'glibc' },
    trust: { manifestSha256: 'c'.repeat(64), checksumsSha256: 'd'.repeat(64) },
    only: sources.map((_, index) => `plugin.example.tool${index}`),
  };
  const plan = buildPluginInstallPlan(input);
  let calls = 0;
  const download = async (action: { id: string }): Promise<Buffer> => {
    calls++; return sources[Number(action.id.replace(/^.*tool/, ''))]!;
  };
  const create = () => preparePluginInstallerCache(plan, output, download, { now: NOW });
  const load = (now = NOW) => loadPluginInstallerCache(output, plan, { now });
  const manifestPath = join(output, 'manifest.json');
  const scriptPath = (index = 0) => join(output, 'scripts', hash(sources[index]!) + '.sh');
  // Test mutations are deliberate corruptions of owned fixture files, not source rewrites.
  const mutate = (update: (data: any) => void) => {
    const data = JSON.parse(readFileSync(manifestPath, 'utf8')); update(data);
    writeFileSync(manifestPath, JSON.stringify(data, null, 2) + '\n');
  };
  return { parent, output, sources, plan, input, download, create, load, manifestPath, scriptPath, mutate, calls: () => calls };
}
const refused = (code?: string) => (error: unknown): boolean => error instanceof PluginCacheError && (!code || error.code === code);

test('prepares and reads all selected scripts with private files and an explicit entrypoint-only contract', async () => {
  const item = fixture(); const built = await item.create(); const cache = item.load();
  assert.deepEqual(cache.summary, built);
  assert.equal(built.moduleCount, 2); assert.equal(built.artifactCount, 2); assert.equal(item.calls(), 2);
  assert.equal(built.entrypointFetchMode, 'cache_only'); assert.equal(built.executionNetworkMode, 'may_be_required');
  assert.equal(built.transitiveClosure, 'not_bundled'); assert.equal(built.planSha256, item.plan.planSha256);
  assert.equal(built.totalBytes, item.sources.reduce((total, bytes) => total + bytes.length, 0));
  assert.deepEqual(readdirSync(item.output).sort(), ['manifest.json', 'scripts']);
  assert.equal(statSync(item.output).mode & 0o777, 0o700);
  assert.equal(statSync(item.manifestPath).mode & 0o777, 0o600);
  assert.equal(statSync(item.scriptPath()).mode & 0o777, 0o600);
  for (let index = 0; index < item.plan.actions.length; index++) {
    assert.deepEqual(await cache.download(item.plan.actions[index]!, new AbortController().signal), item.sources[index]);
  }
});

test('deduplicates identical source/digest acquisitions and content without dropping module coverage', async () => {
  const bytes = Buffer.from('echo shared\n'); const item = fixture([bytes, bytes, bytes]);
  const built = await item.create(); assert.equal(item.calls(), 1);
  assert.equal(built.moduleCount, 3); assert.equal(built.artifactCount, 1); assert.equal(built.totalBytes, bytes.length);
  const cache = item.load();
  for (const action of item.plan.actions) assert.deepEqual(await cache.download(action, new AbortController().signal), bytes);
});

test('a cache can be transported to another directory without encoding local paths or environment', async () => {
  const item = fixture(); await item.create();
  const destination = join(item.parent, 'transferred'); cpSync(item.output, destination, { recursive: true });
  const cache = loadPluginInstallerCache(destination, item.plan, { now: NOW });
  assert.equal(cache.summary.planSha256, item.plan.planSha256);
  assert.ok(!readFileSync(item.manifestPath, 'utf8').includes(item.parent));
  assert.ok(!JSON.stringify(cache.summary).includes(item.parent));
});

test('only selected modules are acquired, not every module in the package', async () => {
  const item = fixture(); item.input.only = ['plugin.example.tool0'];
  const plan = buildPluginInstallPlan(item.input);
  const summary = await preparePluginInstallerCache(plan, item.output, item.download, { now: NOW });
  assert.equal(summary.moduleCount, 1); assert.equal(item.calls(), 1);
  assert.throws(() => loadPluginInstallerCache(item.output, item.plan, { now: NOW }), refused('plugin_cache_plan_mismatch'));
});

test('loaded bytes are immutable snapshots; on-disk replacement and caller buffer mutation cannot substitute scripts', async () => {
  const item = fixture(); await item.create(); const cache = item.load();
  writeFileSync(item.scriptPath(), 'changed after validation');
  const first = await cache.download(item.plan.actions[0]!, new AbortController().signal); first.fill(0);
  assert.deepEqual(await cache.download(item.plan.actions[0]!, new AbortController().signal), item.sources[0]);
  assert.throws(() => item.load(), refused('plugin_cache_hash_mismatch'));
});

test('the snapshot provider refuses unknown actions and substitutions of arguments, checks, tools or URL', async () => {
  const item = fixture(); await item.create(); const cache = item.load();
  for (const change of ['id', 'args', 'url', 'verify', 'tool']) {
    const action = structuredClone(item.plan.actions[0]!);
    if (change === 'id') action.id = 'plugin.example.other';
    if (change === 'args') action.installer.args = ['unreviewed'];
    if (change === 'url') action.installer.url = 'https://example.com/other';
    if (change === 'verify') action.verify = ['other'];
    if (change === 'tool') action.installer.tool = 'other';
    await assert.rejects(cache.download(action, new AbortController().signal), refused('plugin_cache_plan_mismatch'));
  }
});

test('download or hash failure leaves no published or partial output and never executes a script', async () => {
  for (const failAt of [0, 1]) {
    const item = fixture();
    item.sources[failAt] = Buffer.from('touch "$HOME/should-never-run"');
    await assert.rejects(item.create(), refused('plugin_cache_hash_mismatch'));
    assert.equal(existsSync(item.output), false);
  }
  const item = fixture();
  await assert.rejects(preparePluginInstallerCache(item.plan, item.output, async () => {
    throw new Error('download SECRET_PRIVATE_PATH');
  }, { now: NOW }), (error: unknown) => refused()(error) && !(error as Error).message.includes('SECRET'));
  assert.equal(existsSync(item.output), false);
});

test('never merges into or overwrites an existing destination, even an empty one', async () => {
  for (const marker of [false, true]) {
    const item = fixture(); mkdirSync(item.output, { mode: 0o700 });
    if (marker) writeFileSync(join(item.output, 'keep'), 'preserved');
    await assert.rejects(item.create(), refused('plugin_cache_output_exists'));
    assert.equal(item.calls(), 0);
    assert.deepEqual(readdirSync(item.output), marker ? ['keep'] : []);
  }
});

test('a competing publisher appearing during acquisition is not overwritten', async () => {
  const item = fixture(); let once = false;
  await assert.rejects(preparePluginInstallerCache(item.plan, item.output, async (action) => {
    if (!once) { once = true; mkdirSync(item.output, { mode: 0o700 }); writeFileSync(join(item.output, 'keep'), 'other build'); }
    return item.download(action);
  }, { now: NOW }), refused('plugin_cache_output_exists'));
  assert.equal(readFileSync(join(item.output, 'keep'), 'utf8'), 'other build');
  assert.deepEqual(readdirSync(item.output), ['keep']);
});

test('cancelled acquisition never publishes a usable cache and cancelled reads return no bytes', async () => {
  const item = fixture(); const controller = new AbortController(); controller.abort();
  await assert.rejects(preparePluginInstallerCache(item.plan, item.output, item.download, { now: NOW, signal: controller.signal }), refused('plugin_cache_cancelled'));
  assert.equal(item.calls(), 0); assert.equal(existsSync(item.output), false);
  const later = new AbortController();
  await assert.rejects(preparePluginInstallerCache(item.plan, item.output, async (action) => {
    later.abort(); return item.download(action);
  }, { now: NOW, signal: later.signal }), refused('plugin_cache_cancelled'));
  assert.equal(existsSync(item.output), false);
  await item.create();
  assert.throws(() => loadPluginInstallerCache(item.output, item.plan, { now: NOW, signal: later.signal }), refused('plugin_cache_cancelled'));
  const cache = item.load();
  await assert.rejects(cache.download(item.plan.actions[0]!, later.signal), refused('plugin_cache_cancelled'));
});

test('future-dated, expired and malformed clocks are refused at exact boundaries', async () => {
  const item = fixture(); await item.create();
  assert.equal(item.load(NOW + PLUGIN_CACHE_LIMITS.lifetimeMs - 1).summary.moduleCount, 2);
  assert.throws(() => item.load(NOW + PLUGIN_CACHE_LIMITS.lifetimeMs), refused('plugin_cache_expired'));
  assert.throws(() => item.load(NOW - 1), refused('plugin_cache_expired'));
  for (const now of [NaN, Infinity, -1, 1.5]) assert.throws(() => item.load(now), refused('plugin_cache_invalid'));
});

for (const [label, update] of [
  ['schema', (data: any) => { data.schema = 'other'; }],
  ['unknown field', (data: any) => { data.ignored = true; }],
  ['live fallback', (data: any) => { data.policy.entrypointFetchMode = 'live_allowed'; }],
  ['false offline claim', (data: any) => { data.policy.executionNetworkMode = 'offline'; }],
  ['unknown policy', (data: any) => { data.policy.extra = true; }],
  ['plan', (data: any) => { data.planSha256 = 'e'.repeat(64); }],
  ['package', (data: any) => { data.packageSha256 = 'e'.repeat(64); }],
  ['expired', (data: any) => { data.expiresAt = new Date(NOW).toISOString(); }],
  ['extended validity', (data: any) => { data.expiresAt = new Date(NOW + 2 * PLUGIN_CACHE_LIMITS.lifetimeMs).toISOString(); }],
  ['invalid timestamp', (data: any) => { data.generatedAt = '2026-02-30T00:00:00.000Z'; }],
  ['missing entry', (data: any) => { data.entries.pop(); }],
  ['duplicate entry', (data: any) => { data.entries[1] = data.entries[0]; }],
  ['entry extra field', (data: any) => { data.entries[0].ignored = true; }],
  ['URL substitution', (data: any) => { data.entries[0].url = 'https://example.com/different'; }],
  ['tool substitution', (data: any) => { data.entries[0].tool = 'different'; }],
  ['digest substitution', (data: any) => { data.entries[0].sha256 = 'e'.repeat(64); }],
  ['size substitution', (data: any) => { data.entries[0].sizeBytes++; }],
  ['path traversal', (data: any) => { data.entries[0].path = '../private'; }],
  ['absolute path', (data: any) => { data.entries[0].path = '/private'; }],
  ['empty entry', (data: any) => { data.entries[0] = null; }],
  ['negative size', (data: any) => { data.entries[0].sizeBytes = -1; }],
] as const) {
  test(`refuses cache metadata mutation: ${label}`, async () => {
    const item = fixture(); await item.create(); item.mutate(update);
    assert.throws(() => item.load(), refused());
    assert.equal(item.calls(), 2, 'cache reading cannot call the live downloader');
  });
}

test('rejects missing acceptance markers and undeclared files without a fallback', async () => {
  for (const location of ['root', 'scripts', 'manifest']) {
    const item = fixture(); await item.create();
    if (location === 'manifest') renameSync(item.manifestPath, join(item.parent, 'saved-manifest'));
    else writeFileSync(join(item.output, location === 'root' ? 'unexpected' : 'scripts/unexpected.sh'), 'extra');
    assert.throws(() => item.load(), refused()); assert.equal(item.calls(), 2);
  }
});

for (const location of ['root', 'scripts', 'manifest', 'entrypoint']) {
  test(`refuses symlinks at ${location} including intermediate directory components`, async () => {
    const item = fixture(); await item.create();
    const path = location === 'root' ? item.output : location === 'scripts' ? join(item.output, 'scripts')
      : location === 'manifest' ? item.manifestPath : item.scriptPath();
    const saved = join(item.parent, 'original-' + location); renameSync(path, saved); symlinkSync(saved, path);
    assert.throws(() => item.load(), refused());
  });
}

test('does not prepare beneath a symlinked ancestor or an unsafe writable output parent', async () => {
  const item = fixture(); const alias = join(item.parent, 'alias'); symlinkSync(item.parent, alias);
  await assert.rejects(preparePluginInstallerCache(item.plan, join(alias, 'cache'), item.download, { now: NOW }), refused());
  chmodSync(item.parent, 0o777);
  await assert.rejects(item.create(), refused('plugin_cache_path_unsafe'));
  assert.equal(item.calls(), 0);
});

test('rejects hardlinks, FIFOs, directories, writable files, and oversized sparse members', async () => {
  for (const kind of ['hardlink', 'fifo', 'directory', 'writable', 'oversized', 'empty']) {
    const item = fixture(); await item.create(); const file = item.scriptPath();
    if (kind === 'hardlink') linkSync(file, join(item.parent, 'hardlink'));
    if (kind === 'writable') chmodSync(file, 0o666);
    if (kind === 'oversized') truncateSync(file, PLUGIN_CACHE_LIMITS.entrypointBytes + 1);
    if (kind === 'empty') truncateSync(file, 0);
    if (kind === 'fifo' || kind === 'directory') {
      renameSync(file, join(item.parent, 'original'));
      if (kind === 'fifo') execFileSync('mkfifo', [file]); else mkdirSync(file);
    }
    assert.throws(() => item.load(), refused(), kind);
  }
});

test('rejects duplicate JSON keys, malformed UTF-8, BOMs, noncanonical JSON, and oversized metadata', async () => {
  const item = fixture(); await item.create(); const original = readFileSync(item.manifestPath);
  for (const data of [Buffer.from('{"schema":"x","schema":"x"}'), Buffer.from([0xff]),
    Buffer.concat([Buffer.from('\ufeff'), original]), Buffer.from(original.toString().trim())]) {
    writeFileSync(item.manifestPath, data); assert.throws(() => item.load(), refused());
  }
  truncateSync(item.manifestPath, PLUGIN_CACHE_LIMITS.manifestBytes + 1);
  assert.throws(() => item.load(), refused('plugin_cache_file_unsafe'));
});

test('valid manifest entry reordering does not change action bindings', async () => {
  const item = fixture(); await item.create(); item.mutate((data) => data.entries.reverse());
  const cache = item.load();
  assert.deepEqual(await cache.download(item.plan.actions[0]!, new AbortController().signal), item.sources[0]);
});

test('bounds individual and total entrypoint bytes during preparation before output creation', async () => {
  const oversized = fixture([Buffer.alloc(PLUGIN_CACHE_LIMITS.entrypointBytes + 1, 1)]);
  await assert.rejects(oversized.create(), refused('plugin_cache_hash_mismatch')); assert.equal(existsSync(oversized.output), false);
  const large = fixture(Array.from({ length: 5 }, (_, index) => Buffer.alloc(PLUGIN_CACHE_LIMITS.entrypointBytes, index)));
  await assert.rejects(large.create(), refused('plugin_cache_too_large')); assert.equal(existsSync(large.output), false);
});

test('rejects modified plan inputs before downloading or reading cache files', async () => {
  const item = fixture(); const changed = structuredClone(item.plan); changed.actions[0]!.installer.args.push('new');
  await assert.rejects(preparePluginInstallerCache(changed, item.output, item.download, { now: NOW }), refused('plugin_cache_plan_mismatch'));
  assert.equal(item.calls(), 0);
  assert.throws(() => loadPluginInstallerCache('/MISSING_PRIVATE_LOCATION', changed, { now: NOW }), refused('plugin_cache_plan_mismatch'));
});

test('preparation snapshots the caller plan before yielding to downloads', async () => {
  const item = fixture(); const caller = structuredClone(item.plan);
  await preparePluginInstallerCache(caller, item.output, async (action) => {
    caller.actions[0]!.installer.args.push('late mutation'); return item.download(action);
  }, { now: NOW });
  assert.equal(item.load().summary.planSha256, item.plan.planSha256);
});

test('all cache diagnostics redact caller paths and raw external exceptions', async () => {
  const item = fixture();
  try { loadPluginInstallerCache('/MISSING_SUPER_PRIVATE_LOCATION', item.plan, { now: NOW }); assert.fail(); }
  catch (error) { assert.ok(error instanceof PluginCacheError); assert.ok(!error.message.includes('PRIVATE')); }
  await assert.rejects(preparePluginInstallerCache(item.plan, item.output, async () => {
    throw new Error('RAW_INSTALLER_SECRET_OUTPUT');
  }, { now: NOW }), (error: unknown) => refused()(error) && !(error as Error).message.includes('SECRET'));
});
