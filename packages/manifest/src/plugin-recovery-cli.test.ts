import { strict as assert } from 'node:assert';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { extname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { buildPluginInstallPlan } from './plugin-plan.js';
import { parsePluginInstallArguments, pluginInstallMain, type PluginInstallCommandServices } from './plugin-install.js';
import { detectPluginInstallTarget, executePluginInstallPlan, inspectPluginInstallPlan, recoverPluginInstallPlan,
  PluginInstallError, type PluginInstallInspection, type PluginInstallReceipt, type PluginInstallRecovery } from './plugin-runtime.js';

const target = { os: 'ubuntu', version: '26.04', arch: 'x86_64', libc: 'glibc' };
const base = ['--archive', 'package.tar.gz', '--review', 'review.json', '--target', 'ubuntu/26.04/x86_64/glibc', '--only', 'plugin.example.cli'];
const receiptDigest = 'f'.repeat(64);
function fixture() {
  const plan = buildPluginInstallPlan({ modules: [{ id: 'plugin.example.cli', phase: 6, run_as: 'target_user',
    enabled_by_default: false, dependencies: [], install: [], verify: ['command -v -- acfs_recovery_cli >/dev/null 2>&1'],
    plugin: { packageId: 'example', version: '1.0.0', sourceCommit: 'a'.repeat(40), pluginSha256: 'b'.repeat(64) },
    verified_installer: { tool: 'example', url: 'https://example.com/install.sh', runner: 'bash' } }],
    firstPartyModules: [], installers: { example: { url: 'https://example.com/install.sh', sha256: 'c'.repeat(64) } },
    target, trust: { manifestSha256: 'd'.repeat(64), checksumsSha256: 'e'.repeat(64) }, only: ['plugin.example.cli'] });
  const receipt: PluginInstallReceipt = { schema: 'acfs.plugin-install-receipt.v1', planSha256: plan.planSha256,
    packageSha256: plan.package.pluginSha256, status: 'failed', updatedAt: new Date().toISOString(),
    executionProtocol: 'inherited-lock-v1', recoveredFrom: receiptDigest,
    actions: { 'plugin.example.cli': { status: 'failed', exitCode: null } } };
  const inspection: PluginInstallInspection = { schema: 'acfs.plugin-install-status.v1', planSha256: plan.planSha256,
    status: 'interrupted', receiptSha256: receiptDigest, receipt: { ...receipt, status: 'running',
      actions: { 'plugin.example.cli': { status: 'running', exitCode: null } } }, recoveryEligible: true, healthChecked: false };
  const recovery: PluginInstallRecovery = { schema: 'acfs.plugin-install-recovery.v1', planSha256: plan.planSha256,
    previousReceiptSha256: receiptDigest, preservedReceipt: `${plan.planSha256}.interrupted-${receiptDigest}.json`,
    retryModuleIds: ['plugin.example.cli'], receipt };
  const counters = { load: 0, install: 0, inspect: 0, recover: 0 };
  const output: string[] = [];
  const services: PluginInstallCommandServices = {
    loadPlan: async () => { counters.load++; return plan; },
    execute: async () => { counters.install++; return { ...receipt, status: 'complete',
      actions: { 'plugin.example.cli': { status: 'complete', exitCode: 0 } } }; },
    inspect: async (input, signal) => { counters.inspect++; assert.equal(input, plan); assert.equal(signal.aborted, false); return inspection; },
    recover: async (input, digest, signal) => { counters.recover++; assert.equal(input, plan); assert.equal(digest, receiptDigest);
      assert.equal(signal.aborted, false); return recovery; },
    write: (message) => output.push(message),
  };
  const recoverArgs = [...base, '--recover', '--yes', '--accept-plan', plan.planSha256, '--accept-receipt', receiptDigest, '--json'];
  return { plan, receipt, inspection, recovery, counters, output, services, recoverArgs };
}

test('status is a read-only operation distinct from dry-run or application', () => {
  const options = parsePluginInstallArguments([...base, '--status', '--json']);
  assert.equal(options.status, true); assert.equal(options.recover, false); assert.equal(options.apply, false);
  assert.equal(options.acceptReceipt, undefined); assert.equal(options.acceptPlan, undefined);
});

for (const extra of [
  ['--status', '--yes', '--accept-plan', 'a'.repeat(64)], ['--status', '--recover'], ['--status', '--dry-run'],
  ['--status', '--accept-receipt', receiptDigest], ['--status', '--status'], ['--recover'], ['--recover', '--yes'],
  ['--recover', '--yes', '--accept-plan', 'a'.repeat(64)], ['--recover', '--accept-receipt', receiptDigest],
  ['--yes', '--accept-plan', 'a'.repeat(64), '--accept-receipt', receiptDigest],
  ['--recover', '--yes', '--accept-plan', 'a'.repeat(64), '--accept-receipt', 'bad'],
  ['--recover', '--yes', '--accept-plan', 'a'.repeat(64), '--accept-receipt', receiptDigest, '--dry-run'],
]) {
  test(`refuses ambiguous or incomplete recovery consent ${JSON.stringify(extra)}`, async () => {
    const item = fixture();
    assert.equal(await pluginInstallMain([...base, ...extra, '--json'], item.services), 2);
    assert.deepEqual(item.counters, { load: 0, install: 0, inspect: 0, recover: 0 });
  });
}

test('status reloads validation and never routes to the installer', async () => {
  const item = fixture();
  assert.equal(await pluginInstallMain([...base, '--status', '--json'], item.services), 0);
  assert.deepEqual(item.counters, { load: 1, install: 0, inspect: 1, recover: 0 });
  assert.deepEqual(JSON.parse(item.output[0]!), { status: 'inspected', mode: 'status', inspection: item.inspection });
});

test('recorded completion and a busy lock cannot be represented as a fresh health check', async () => {
  for (const status of ['complete', 'busy', 'not_started'] as const) {
    const item = fixture(); item.inspection.status = status; item.inspection.recoveryEligible = false;
    assert.equal(await pluginInstallMain([...base, '--status'], item.services), 0);
    assert.match(item.output[0]!, /No health checks or installers ran/);
    assert.match(item.output[0]!, /not a current health assessment/);
    assert.equal(item.counters.install, 0);
  }
});

test('recovery requires the current plan and exact receipt fingerprint and never installs', async () => {
  const item = fixture();
  assert.equal(await pluginInstallMain(item.recoverArgs, item.services), 0);
  assert.deepEqual(item.counters, { load: 1, install: 0, inspect: 0, recover: 1 });
  const output = JSON.parse(item.output[0]!);
  assert.equal(output.status, 'recovered'); assert.equal(output.mode, 'recovery');
  assert.equal(output.recovery.receipt.status, 'failed');
});

test('stale plan approval stops before receipt recovery', async () => {
  const item = fixture();
  const args = [...item.recoverArgs]; args[args.indexOf('--accept-plan') + 1] = 'a'.repeat(64);
  assert.equal(await pluginInstallMain(args, item.services), 1);
  assert.deepEqual(item.counters, { load: 1, install: 0, inspect: 0, recover: 0 });
  assert.equal(JSON.parse(item.output[0]!).diagnostic.code, 'plugin_plan_changed');
});

test('expired or invalid package review cannot be bypassed by status or recovery', async () => {
  for (const operation of ['status', 'recover']) {
    const item = fixture();
    item.services.loadPlan = async () => { throw new Error('PRIVATE_REVIEW_DETAIL'); };
    assert.equal(await pluginInstallMain(operation === 'status' ? [...base, '--status', '--json'] : item.recoverArgs, item.services), 1);
    assert.equal(item.counters.inspect + item.counters.recover + item.counters.install, 0);
    assert.ok(!item.output.join('').includes('PRIVATE_REVIEW_DETAIL'));
  }
});

test('missing operation services fail closed rather than falling back to installation', async () => {
  for (const operation of ['inspect', 'recover'] as const) {
    const item = fixture(); delete item.services[operation];
    assert.equal(await pluginInstallMain(operation === 'inspect' ? [...base, '--status', '--json'] : item.recoverArgs, item.services), 1);
    assert.equal(item.counters.install, 0);
    assert.equal(JSON.parse(item.output[0]!).diagnostic.code, 'plugin_operation_unavailable');
  }
});

for (const mutation of ['plan', 'receipt', 'evidence', 'success', 'no-actions', 'unknown-action', 'invented-exit']) {
  test(`does not claim recovery with inconsistent result: ${mutation}`, async () => {
    const item = fixture();
    if (mutation === 'plan') item.recovery.planSha256 = 'a'.repeat(64);
    if (mutation === 'receipt') item.recovery.previousReceiptSha256 = 'a'.repeat(64);
    if (mutation === 'evidence') item.recovery.preservedReceipt = 'wrong.json';
    if (mutation === 'success') item.receipt.status = 'complete';
    if (mutation === 'no-actions') item.recovery.retryModuleIds = [];
    if (mutation === 'unknown-action') item.recovery.retryModuleIds = ['plugin.other.cli'];
    if (mutation === 'invented-exit') item.receipt.actions['plugin.example.cli']!.exitCode = 0;
    assert.equal(await pluginInstallMain(item.recoverArgs, item.services), 1);
    assert.equal(JSON.parse(item.output[0]!).status, 'failed');
    assert.equal(item.counters.install, 0);
  });
}

test('interruption during recovery cannot emit a recovered or installed success', async () => {
  const before = [process.listenerCount('SIGINT'), process.listenerCount('SIGTERM')];
  const item = fixture();
  item.services.recover = async (_plan, _digest, signal) => {
    process.emit('SIGINT'); assert.equal(signal.aborted, true); return item.recovery;
  };
  assert.equal(await pluginInstallMain(item.recoverArgs, item.services), 130);
  assert.equal(JSON.parse(item.output[0]!).diagnostic.code, 'plugin_install_cancelled');
  assert.equal(item.counters.install, 0);
  assert.deepEqual([process.listenerCount('SIGINT'), process.listenerCount('SIGTERM')], before);
});

test('ordinary preview and separately approved install retain their original routes', async () => {
  const preview = fixture();
  assert.equal(await pluginInstallMain([...base, '--json'], preview.services), 0);
  assert.equal(JSON.parse(preview.output[0]!).status, 'planned');
  assert.deepEqual(preview.counters, { load: 1, install: 0, inspect: 0, recover: 0 });
  const apply = fixture();
  assert.equal(await pluginInstallMain([...base, '--yes', '--accept-plan', apply.plan.planSha256, '--json'], apply.services), 0);
  assert.equal(JSON.parse(apply.output[0]!).status, 'complete');
  assert.deepEqual(apply.counters, { load: 1, install: 1, inspect: 0, recover: 0 });
});

test('CLI subprocess help and consent errors work without canonical dependency loading', () => {
  const script = fileURLToPath(new URL(`./plugin-install${extname(fileURLToPath(import.meta.url))}`, import.meta.url));
  const help = spawnSync(process.execPath, [script, '--help'], { encoding: 'utf8' });
  assert.equal(help.status, 0, help.stderr); assert.match(help.stdout, /--accept-receipt/); assert.match(help.stdout, /never installs/);
  const invalid = spawnSync(process.execPath, [script, ...base, '--recover', '--json'], { encoding: 'utf8' });
  assert.equal(invalid.status, 2, invalid.stderr);
  assert.equal(JSON.parse(invalid.stdout).diagnostic.code, 'plugin_install_arguments_invalid');
});

test('CLI status and recovery use the real receipt store, preserving evidence before separate execution',
  { skip: process.platform !== 'linux' || process.getuid?.() === 0 }, async () => {
  const item = fixture();
  const home = mkdtempSync(join(tmpdir(), 'acfs-recovery-cli-'));
  const payload = { ...item.plan, target: detectPluginInstallTarget() };
  const { planSha256: _oldDigest, ...data } = payload;
  const plan = { ...data, planSha256: createHash('sha256').update(JSON.stringify(data)).digest('hex') };
  const receipt: PluginInstallReceipt = { ...item.inspection.receipt!, planSha256: plan.planSha256 };
  const directory = join(home, '.acfs/plugin-installs'); mkdirSync(directory, { recursive: true, mode: 0o700 });
  writeFileSync(join(directory, 'install.lock'), '', { mode: 0o600 });
  const path = join(directory, `${plan.planSha256}.json`);
  const original = Buffer.from(JSON.stringify(receipt) + '\n'); writeFileSync(path, original, { mode: 0o600 });
  const digest = createHash('sha256').update(original).digest('hex');
  const args = [...base]; args[args.indexOf('--target') + 1] = Object.values(plan.target).join('/');
  let downloads = 0;
  const services: PluginInstallCommandServices = { loadPlan: async () => plan,
    inspect: (input, signal) => inspectPluginInstallPlan(input, { home, signal }),
    recover: (input, expected, signal) => recoverPluginInstallPlan(input, expected, { home, signal }),
    execute: (input, signal) => executePluginInstallPlan(input, { home, signal, download: async () => {
      downloads++; throw new PluginInstallError('fixture_download_refused', 'No live download is allowed in this test');
    } }), write: (message) => item.output.push(message) };
  const before = readdirSync(directory);
  assert.equal(await pluginInstallMain([...args, '--status', '--json'], services), 0);
  assert.deepEqual(readdirSync(directory), before); assert.deepEqual(readFileSync(path), original);
  const status = JSON.parse(item.output.pop()!); assert.equal(status.inspection.receiptSha256, digest);
  assert.equal(await pluginInstallMain([...args, '--yes', '--accept-plan', plan.planSha256, '--json'], services), 1);
  assert.equal(JSON.parse(item.output.pop()!).diagnostic.code, 'plugin_install_interrupted');
  assert.equal(downloads, 0);
  assert.equal(await pluginInstallMain([...args, '--recover', '--yes', '--accept-plan', plan.planSha256,
    '--accept-receipt', digest, '--json'], services), 0);
  const result = JSON.parse(item.output.pop()!); assert.equal(result.status, 'recovered');
  assert.deepEqual(readFileSync(join(directory, result.recovery.preservedReceipt)), original);
  assert.equal(existsSync(join(home, '.local')), false); assert.equal(downloads, 0);
  assert.equal(await pluginInstallMain([...args, '--yes', '--accept-plan', plan.planSha256, '--json'], services), 1);
  assert.equal(downloads, 1, 'only the separate install invocation may reach a download');
});
