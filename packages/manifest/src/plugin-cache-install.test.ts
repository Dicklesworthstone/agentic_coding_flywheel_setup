import { strict as assert } from 'node:assert';
import { createHash } from 'node:crypto';
import { spawn, spawnSync, execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdtempSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:https';
import { tmpdir } from 'node:os';
import { extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { buildPluginInstallPlan, type PluginPlanInput } from './plugin-plan.js';
import { detectPluginInstallTarget, executePluginInstallPlan, PluginInstallError, type PluginInstallReceipt } from './plugin-runtime.js';
import { executeCachedPluginInstallPlan, preparePluginInstallerCache, PluginCacheError, PLUGIN_CACHE_LIMITS, type PluginCacheSummary } from './plugin-cache.js';
import { pluginInstallMain, parsePluginInstallArguments, type PluginInstallCommandServices } from './plugin-install.js';

const hash = (bytes: Buffer): string => createHash('sha256').update(bytes).digest('hex');
const nonRoot = typeof process.getuid === 'function' && process.getuid() !== 0;
const linux = process.platform === 'linux';
const execution = { skip: linux && nonRoot ? false : 'Requires an unprivileged Linux/glibc user and system execution tools' };
function script(index: number): Buffer {
  return Buffer.from(`set -eu\nmkdir -p "$HOME/.local/bin"\nprintf '#!/bin/sh\\nexit 0\\n' > "$HOME/.local/bin/cache_fixture_${index}"\nchmod 755 "$HOME/.local/bin/cache_fixture_${index}"\nprintf '${index}\\n' >> "$HOME/install-order"\n`);
}
function fixture(scripts = [script(0), script(1)]) {
  const parent = mkdtempSync(join(tmpdir(), 'acfs-cache-command-'));
  const home = mkdtempSync(join(tmpdir(), 'acfs-cache-user-'));
  const cacheDir = join(parent, 'entrypoints');
  const target = linux ? detectPluginInstallTarget() : { os: 'ubuntu', version: '26.04', arch: 'x86_64', libc: 'glibc' };
  const input: PluginPlanInput = {
    modules: scripts.map((bytes, index) => ({ id: `plugin.example.tool${index}`, phase: 6,
      run_as: 'target_user', enabled_by_default: false, install: [], dependencies: index ? ['plugin.example.tool0'] : ['base.system'],
      verify: [`command -v -- cache_fixture_${index} >/dev/null 2>&1`],
      plugin: { packageId: 'example', version: '1.0.0', sourceCommit: 'a'.repeat(40), pluginSha256: 'b'.repeat(64) },
      verified_installer: { tool: `tool${index}`, url: `https://example.com/${hash(bytes)}.sh`, runner: index ? 'sh' : 'bash' } })),
    firstPartyModules: [{ id: 'base.system', phase: 1, verify: ['command -v bash'] }],
    installers: Object.fromEntries(scripts.map((bytes, index) => [`tool${index}`, { url: `https://example.com/${hash(bytes)}.sh`, sha256: hash(bytes) }])),
    target, trust: { manifestSha256: 'c'.repeat(64), checksumsSha256: 'd'.repeat(64) }, only: [`plugin.example.tool${scripts.length - 1}`],
  };
  const plan = buildPluginInstallPlan(input);
  const base = ['--archive', 'package.tar.gz', '--review', 'review.json', '--target',
    `${target.os}/${target.version}/${target.arch}/${target.libc}`, '--only', input.only[0]!, '--json'];
  const approve = ['--yes', '--accept-plan', plan.planSha256];
  const output: string[] = []; const calls = { plan: 0, prepare: 0, cached: 0, live: 0, downloads: 0 };
  const download = async (action: { id: string }): Promise<Buffer> => { calls.downloads++; return scripts[Number(action.id.at(-1))]!; };
  const services: PluginInstallCommandServices = {
    loadPlan: async () => { calls.plan++; return plan; },
    prepareCache: async (selected, directory, signal) => { calls.prepare++; return preparePluginInstallerCache(selected, directory, download, { signal }); },
    executeCached: async (selected, directory, signal) => { calls.cached++; return executeCachedPluginInstallPlan(selected, directory, { home, signal }); },
    execute: async (selected, signal) => { calls.live++; return executePluginInstallPlan(selected, { home, signal, download }); },
    write: (value) => output.push(value),
  };
  return { parent, home, cacheDir, input, plan, scripts, base, approve, output, calls, download, services,
    manifestPath: join(cacheDir, 'manifest.json'),
    receiptPath: join(home, '.acfs', 'plugin-installs', plan.planSha256 + '.json') };
}

test('cache preparation and cache-only modes remain read-only previews without explicit approval', async () => {
  for (const option of ['--prepare-cache', '--installer-cache']) {
    const item = fixture();
    assert.equal(await pluginInstallMain([...item.base, option, item.cacheDir], item.services), 0);
    assert.equal(existsSync(item.cacheDir), false); assert.equal(existsSync(join(item.home, '.acfs')), false);
    assert.deepEqual(item.calls, { plan: 1, prepare: 0, cached: 0, live: 0, downloads: 0 });
    const result = JSON.parse(item.output[0]!);
    assert.equal(result.status, 'planned'); assert.equal(result.cacheValidated, false);
    assert.equal(result.operation, option === '--prepare-cache' ? 'prepare-cache' : 'install');
    assert.equal(result.acquisition, option === '--installer-cache' ? 'cache_required' : 'https');
    assert.equal(result.executionNetworkMode, 'may_be_required');
    assert.ok(!item.output[0]!.includes(item.parent));
  }
});

test('approved preparation produces the complete cache but never executes installers or creates receipts', async () => {
  const item = fixture();
  assert.equal(await pluginInstallMain([...item.base, '--prepare-cache', item.cacheDir, ...item.approve], item.services), 0);
  const result = JSON.parse(item.output[0]!);
  assert.equal(result.status, 'cache_prepared'); assert.equal(result.mode, 'prepare-cache');
  assert.equal(result.cache.planSha256, item.plan.planSha256); assert.equal(result.cache.moduleCount, 2);
  assert.equal(existsSync(item.manifestPath), true); assert.equal(existsSync(join(item.home, '.acfs')), false);
  assert.equal(existsSync(join(item.home, 'install-order')), false);
  assert.deepEqual(item.calls, { plan: 1, prepare: 1, cached: 0, live: 0, downloads: 2 });
});

test('stale plan approval prevents cache preparation and installation before acquisition', async () => {
  for (const option of ['--prepare-cache', '--installer-cache']) {
    const item = fixture();
    assert.equal(await pluginInstallMain([...item.base, option, item.cacheDir, '--yes', '--accept-plan', 'f'.repeat(64)], item.services), 1);
    assert.equal(item.calls.prepare, 0); assert.equal(item.calls.cached, 0); assert.equal(item.calls.live, 0); assert.equal(item.calls.downloads, 0);
    assert.equal(JSON.parse(item.output[0]!).diagnostic.code, 'plugin_plan_changed');
  }
});

for (const extra of [
  ['--prepare-cache', 'a', '--installer-cache', 'b'], ['--prepare-cache', 'a', '--status'],
  ['--installer-cache', 'a', '--status'], ['--prepare-cache', 'a', '--prepare-cache', 'b'],
  ['--installer-cache', 'a', '--installer-cache', 'b'], ['--prepare-cache'], ['--installer-cache'],
  ['--prepare-cache', 'a\nb'], ['--installer-cache', 'a\0b'],
  ['--prepare-cache', 'a', '--recover', '--yes', '--accept-plan', 'a'.repeat(64), '--accept-receipt', 'b'.repeat(64)],
  ['--installer-cache', 'a', '--recover', '--yes', '--accept-plan', 'a'.repeat(64), '--accept-receipt', 'b'.repeat(64)],
]) {
  test(`refuses ambiguous cache mode combination ${JSON.stringify(extra)}`, () => {
    assert.throws(() => parsePluginInstallArguments([...fixture().base, ...extra]));
  });
}

test('cache-only mode never falls through to live execution when unavailable or corrupt', async () => {
  for (const unavailable of [true, false]) {
    const item = fixture();
    if (unavailable) item.services.executeCached = undefined;
    else item.services.executeCached = async () => { throw new PluginCacheError('plugin_cache_invalid', 'Cache validation failed'); };
    assert.equal(await pluginInstallMain([...item.base, '--installer-cache', item.cacheDir, ...item.approve], item.services), 1);
    assert.equal(item.calls.live, 0); assert.equal(item.calls.downloads, 0); assert.equal(existsSync(item.receiptPath), false);
  }
});

test('false preparation summaries cannot claim successful cache publication', async () => {
  for (const field of ['schema', 'planSha256', 'packageSha256', 'moduleCount', 'artifactCount', 'totalBytes', 'entrypointFetchMode', 'executionNetworkMode', 'transitiveClosure', 'expiresAt']) {
    const item = fixture();
    const valid: PluginCacheSummary = { schema: 'acfs.plugin-entrypoint-cache-summary.v1', planSha256: item.plan.planSha256,
      packageSha256: item.plan.package.pluginSha256, moduleCount: 2, artifactCount: 2, totalBytes: 42,
      expiresAt: new Date(Date.now() + 1000).toISOString(), entrypointFetchMode: 'cache_only', executionNetworkMode: 'may_be_required', transitiveClosure: 'not_bundled' };
    const corrupted = { ...valid, [field]: field.endsWith('Count') || field === 'totalBytes' ? -1 : 'incorrect' };
    item.services.prepareCache = async () => corrupted as PluginCacheSummary;
    assert.equal(await pluginInstallMain([...item.base, '--prepare-cache', item.cacheDir, ...item.approve], item.services), 1);
    assert.equal(JSON.parse(item.output[0]!).diagnostic.code, 'plugin_cache_invalid');
    assert.equal(item.calls.live, 0);
  }
});

test('cancelled preparation cannot emit success and does not leave signal handlers installed', async () => {
  const item = fixture(); const before = [process.listenerCount('SIGINT'), process.listenerCount('SIGTERM')];
  item.services.prepareCache = async () => { process.emit('SIGINT'); throw new Error('PRIVATE_LOCATION'); };
  assert.equal(await pluginInstallMain([...item.base, '--prepare-cache', item.cacheDir, ...item.approve], item.services), 130);
  assert.equal(JSON.parse(item.output[0]!).diagnostic.code, 'plugin_install_cancelled');
  assert.ok(!item.output[0]!.includes('PRIVATE_LOCATION'));
  assert.deepEqual([process.listenerCount('SIGINT'), process.listenerCount('SIGTERM')], before);
});

test('ambient cache variables cannot change the explicit CLI acquisition mode', async () => {
  const item = fixture(); const old = process.env.ACFS_VERIFIED_INSTALLER_CACHE;
  process.env.ACFS_VERIFIED_INSTALLER_CACHE = item.cacheDir;
  try {
    assert.equal(await pluginInstallMain(item.base, item.services), 0);
    assert.equal(JSON.parse(item.output[0]!).acquisition, 'https');
  } finally { if (old === undefined) delete process.env.ACFS_VERIFIED_INSTALLER_CACHE; else process.env.ACFS_VERIFIED_INSTALLER_CACHE = old; }
});

test('public help and invalid-input JSON load without canonical manifest dependencies', () => {
  const extension = extname(fileURLToPath(import.meta.url));
  const file = fileURLToPath(new URL(`./plugin-install${extension}`, import.meta.url));
  const help = spawnSync(process.execPath, [file, '--help'], { encoding: 'utf8' });
  assert.equal(help.status, 0, help.stderr); assert.match(help.stdout, /--prepare-cache/); assert.match(help.stdout, /--installer-cache/);
  assert.match(help.stdout, /not an air-gap bundle/);
  const failed = spawnSync(process.execPath, [file, '--installer-cache', '/PRIVATE_LOCATION', '--json'], { encoding: 'utf8' });
  assert.equal(failed.status, 2, failed.stderr); assert.equal(JSON.parse(failed.stdout).status, 'failed');
  assert.ok(!failed.stdout.includes('PRIVATE_LOCATION'));
});

test('cache preparation followed by real Bash/sh install and retry uses no additional entrypoint downloads', execution, async () => {
  const item = fixture();
  const prepare = [...item.base, '--prepare-cache', item.cacheDir, ...item.approve];
  const apply = [...item.base, '--installer-cache', item.cacheDir, ...item.approve];
  assert.equal(await pluginInstallMain(prepare, item.services), 0);
  assert.equal(await pluginInstallMain(apply, item.services), 0, item.output.at(-1));
  assert.equal(await pluginInstallMain(apply, item.services), 0, item.output.at(-1));
  assert.deepEqual(item.calls, { plan: 3, prepare: 1, cached: 2, live: 0, downloads: 2 });
  assert.equal(readFileSync(join(item.home, 'install-order'), 'utf8'), '0\n1\n');
  assert.equal(JSON.parse(readFileSync(item.receiptPath, 'utf8')).status, 'complete');
  assert.equal(JSON.parse(item.output.at(-1)!).acquisition, 'cache_required');
});

test('a corrupted later cached script prevents every installer and even receipt creation', execution, async () => {
  const item = fixture();
  await preparePluginInstallerCache(item.plan, item.cacheDir, item.download);
  const later = join(item.cacheDir, 'scripts', item.plan.actions[1]!.installer.sha256 + '.sh');
  writeFileSync(later, 'touch "$HOME/UNTRUSTED"');
  assert.equal(await pluginInstallMain([...item.base, '--installer-cache', item.cacheDir, ...item.approve], item.services), 1);
  assert.equal(item.calls.live, 0); assert.equal(item.calls.downloads, 2);
  assert.equal(existsSync(join(item.home, 'install-order')), false); assert.equal(existsSync(join(item.home, '.acfs')), false);
  assert.equal(existsSync(join(item.home, 'UNTRUSTED')), false);
});

test('cache-backed failure retries only the failed action and keeps verified dependency checkpoints', execution, async () => {
  const item = fixture([script(0), Buffer.concat([Buffer.from('test -f "$HOME/allow" || exit 17\n'), script(1)])]);
  await preparePluginInstallerCache(item.plan, item.cacheDir, item.download);
  await assert.rejects(executeCachedPluginInstallPlan(item.plan, item.cacheDir, { home: item.home }),
    (error: unknown) => error instanceof PluginInstallError && error.code === 'plugin_install_failed');
  assert.equal(JSON.parse(readFileSync(item.receiptPath, 'utf8')).actions['plugin.example.tool1'].exitCode, 17);
  writeFileSync(join(item.home, 'allow'), 'yes');
  assert.equal((await executeCachedPluginInstallPlan(item.plan, item.cacheDir, { home: item.home })).status, 'complete');
  assert.equal(item.calls.downloads, 2); assert.equal(readFileSync(join(item.home, 'install-order'), 'utf8'), '0\n1\n');
});

test('a cache miss on a later invocation cannot silently reuse receipts or use a live fallback', execution, async () => {
  const item = fixture(); await preparePluginInstallerCache(item.plan, item.cacheDir, item.download);
  await executeCachedPluginInstallPlan(item.plan, item.cacheDir, { home: item.home });
  const previous = readFileSync(item.receiptPath); renameSync(item.manifestPath, join(item.parent, 'saved-manifest'));
  let fallback = 0;
  const options = { home: item.home, download: async () => { fallback++; return Buffer.from('never'); } };
  await assert.rejects(executeCachedPluginInstallPlan(item.plan, item.cacheDir, options), PluginCacheError);
  assert.equal(fallback, 0); assert.deepEqual(readFileSync(item.receiptPath), previous);
});

test('the cached execution helper ignores untyped downloader overrides and enforces the actual target', execution, async () => {
  const item = fixture(); await preparePluginInstallerCache(item.plan, item.cacheDir, item.download);
  let fallback = 0;
  const options = { home: item.home, download: async () => { fallback++; return Buffer.from('never'); } };
  assert.equal((await executeCachedPluginInstallPlan(item.plan, item.cacheDir, options)).status, 'complete');
  assert.equal(fallback, 0);
  const other = fixture(); other.input.target.version = 'unsupported'; const plan = buildPluginInstallPlan(other.input);
  await preparePluginInstallerCache(plan, other.cacheDir, other.download);
  await assert.rejects(executeCachedPluginInstallPlan(plan, other.cacheDir, { home: other.home }),
    (error: unknown) => error instanceof PluginInstallError && error.code === 'plugin_target_unsupported');
  assert.equal(existsSync(join(other.home, '.acfs')), false);
});

test('a valid cache never grants root execution authority', { skip: !linux || nonRoot }, async () => {
  const item = fixture(); await preparePluginInstallerCache(item.plan, item.cacheDir, item.download);
  await assert.rejects(executeCachedPluginInstallPlan(item.plan, item.cacheDir, { home: item.home }),
    (error: unknown) => error instanceof PluginInstallError && error.code === 'plugin_root_execution_refused');
  assert.equal(existsSync(join(item.home, '.acfs')), false);
});

test('deduplication never hides a selected execution set larger than the runtime staging budget', async () => {
  const bytes = Buffer.alloc(PLUGIN_CACHE_LIMITS.entrypointBytes, 1);
  const item = fixture(Array(5).fill(bytes)); item.input.only = item.input.modules.map((module) => module.id);
  const plan = buildPluginInstallPlan(item.input);
  await assert.rejects(preparePluginInstallerCache(plan, item.cacheDir, item.download),
    (error: unknown) => error instanceof PluginCacheError && error.code === 'plugin_cache_too_large');
  assert.equal(existsSync(item.cacheDir), false);
});

test('real HTTPS acquisition followed by server shutdown and transported-cache execution', execution, async () => {
  const item = fixture([script(0)]);
  const key = join(item.parent, 'server-key.pem'); const cert = join(item.parent, 'server-cert.pem');
  execFileSync('/usr/bin/openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
    '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1', '-keyout', key, '-out', cert], { stdio: 'ignore' });
  let requests = 0;
  const server = createServer({ key: readFileSync(key), cert: readFileSync(cert) }, (_request, response) => { requests++; response.end(item.scripts[0]); });
  await new Promise<void>((accept) => server.listen(0, '127.0.0.1', accept));
  const address = server.address(); assert.ok(address && typeof address !== 'string');
  const url = `https://127.0.0.1:${address.port}/entrypoint.sh`;
  item.input.installers.tool0!.url = url; item.input.modules[0]!.verified_installer!.url = url;
  const plan = buildPluginInstallPlan(item.input);
  const extension = extname(fileURLToPath(import.meta.url));
  const cacheModule = new URL(`./plugin-cache${extension}`, import.meta.url).href;
  const runtimeModule = new URL(`./plugin-runtime${extension}`, import.meta.url).href;
  const code = `import {preparePluginInstallerCache} from ${JSON.stringify(cacheModule)};
    import {downloadPluginInstaller} from ${JSON.stringify(runtimeModule)};
    console.log(JSON.stringify(await preparePluginInstallerCache(${JSON.stringify(plan)}, ${JSON.stringify(item.cacheDir)}, downloadPluginInstaller)));`;
  try {
    const output = await new Promise<string>((accept, reject) => {
      const args = process.versions.bun ? ['--eval', code] : ['--input-type=module', '--eval', code];
      const child = spawn(process.execPath, args, { env: { ...process.env, NODE_EXTRA_CA_CERTS: cert }, stdio: ['ignore', 'pipe', 'pipe'] });
      let text = ''; let errors = '';
      child.stdout.on('data', (chunk) => { text += chunk.toString(); });
      child.stderr.on('data', (chunk) => { errors += chunk.toString(); });
      child.once('error', reject);
      child.once('close', (status) => { if (status === 0) accept(text); else reject(new Error(errors)); });
    });
    assert.equal(JSON.parse(output).moduleCount, 1); assert.equal(requests, 1);
  } finally { server.closeAllConnections(); await new Promise<void>((accept) => server.close(() => accept())); }
  const transported = join(item.parent, 'transported'); cpSync(item.cacheDir, transported, { recursive: true });
  const receipt: PluginInstallReceipt = await executeCachedPluginInstallPlan(plan, transported, { home: item.home });
  assert.equal(receipt.status, 'complete'); assert.equal(requests, 1);
  assert.equal(readFileSync(join(item.home, 'install-order'), 'utf8'), '0\n');
});
