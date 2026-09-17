import { strict as assert } from 'node:assert';
import { createHash } from 'node:crypto';
import { spawn, execFileSync } from 'node:child_process';
import { chmodSync, existsSync, linkSync, mkdtempSync, readFileSync, renameSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:https';
import { fileURLToPath } from 'node:url';
import { extname } from 'node:path';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { buildPluginInstallPlan, type PlannablePluginModule, type PluginInstallPlan } from './plugin-plan.js';
import { detectPluginInstallTarget, downloadPluginInstaller, executePluginInstallPlan, parsePluginHostRelease, PluginInstallError } from './plugin-runtime.js';

const digest = (value: Buffer): string => createHash('sha256').update(value).digest('hex');
const nonRoot = process.getuid!() !== 0;
function fixture(sources: string[], verify?: string[]) {
  const home = mkdtempSync(join(tmpdir(), 'acfs-plugin-execution-'));
  const bytes = sources.map((source) => Buffer.from(source));
  const modules: PlannablePluginModule[] = sources.map((_, index) => ({
    id: `plugin.example.tool${index}`, phase: 6, run_as: 'target_user', enabled_by_default: false,
    install: [], dependencies: index ? [`plugin.example.tool${index - 1}`] : ['base.system'],
    verify: [`command -v -- ${verify?.[index] ?? `acfs_fixture_${index}`} >/dev/null 2>&1`],
    plugin: { packageId: 'example', version: '1.0.0', sourceCommit: 'a'.repeat(40), pluginSha256: 'b'.repeat(64) },
    verified_installer: { tool: `tool${index}`, url: `https://example.com/install${index}.sh`, runner: 'bash', args: [] },
  }));
  const input = { modules, firstPartyModules: [{ id: 'base.system', phase: 1, verify: ['command -v bash'] }],
    installers: Object.fromEntries(bytes.map((data, index) => [`tool${index}`, { url: `https://example.com/install${index}.sh`, sha256: digest(data) }])),
    only: [modules.at(-1)!.id], target: detectPluginInstallTarget(),
    trust: { manifestSha256: 'c'.repeat(64), checksumsSha256: 'd'.repeat(64) } };
  let downloads = 0;
  const download = async (action: { id: string }): Promise<Buffer> => { downloads++; return bytes[Number(action.id.at(-1))]!; };
  return { home, input, bytes, plan: buildPluginInstallPlan(input), download, count: () => downloads };
}
function installer(index: number, extra = ''): string {
  return `set -eu\nmkdir -p "$HOME/.local/bin"\nprintf '#!/bin/sh\\nexit 0\\n' > "$HOME/.local/bin/acfs_fixture_${index}"\nchmod 755 "$HOME/.local/bin/acfs_fixture_${index}"\nprintf '${index}\\n' >> "$HOME/install-order"\n${extra}\n`;
}
const receiptPath = (home: string, plan: PluginInstallPlan): string => join(home, '.acfs/plugin-installs', plan.planSha256 + '.json');
const rejected = (code: string) => (error: unknown): boolean => error instanceof PluginInstallError && error.code === code;
const integration = { skip: nonRoot ? false : 'Run these real execution cases as an unprivileged Linux user' };

test('parses release metadata without evaluating shell expressions', () => {
  assert.deepEqual(parsePluginHostRelease('ID=ubuntu\nVERSION_ID="26.04"\nPRETTY_NAME="$(touch attack)"'), { os: 'ubuntu', version: '26.04' });
  for (const text of ['ID=ubuntu\nVERSION_ID="$(id)"', 'ID=ubuntu\nID=arch\nVERSION_ID=26.04', 'VERSION_ID=26.04']) {
    assert.throws(() => parsePluginHostRelease(text), PluginInstallError);
  }
});

test('rejects root before state or downloads', { skip: nonRoot }, async () => {
  const item = fixture([installer(0)]);
  await assert.rejects(executePluginInstallPlan(item.plan, item), rejected('plugin_root_execution_refused'));
  assert.equal(item.count(), 0); assert.equal(existsSync(join(item.home, '.acfs')), false);
});

test('installs in dependency order, stores private receipts, and rechecks successful reruns without downloads', integration, async () => {
  const item = fixture([installer(0), installer(1)]);
  const result = await executePluginInstallPlan(item.plan, item);
  assert.equal(result.status, 'complete'); assert.equal(item.count(), 2);
  assert.equal(readFileSync(join(item.home, 'install-order'), 'utf8'), '0\n1\n');
  assert.equal(statSync(receiptPath(item.home, item.plan)).mode & 0o777, 0o600);
  assert.equal(statSync(join(item.home, '.acfs/plugin-installs')).mode & 0o777, 0o700);
  assert.equal((await executePluginInstallPlan(item.plan, item)).status, 'complete');
  assert.equal(item.count(), 2);
  assert.equal(readFileSync(join(item.home, 'install-order'), 'utf8'), '0\n1\n');
});

test('checksum failure in a later installer prevents ALL installer execution', integration, async () => {
  const item = fixture([installer(0), installer(1)]);
  item.bytes[1] = Buffer.from('touch "$HOME/ATTACK"');
  await assert.rejects(executePluginInstallPlan(item.plan, item), rejected('plugin_installer_hash_mismatch'));
  assert.equal(existsSync(join(item.home, 'install-order')), false);
  assert.equal(existsSync(join(item.home, 'ATTACK')), false);
});

test('missing prerequisites prevent installer downloads and execution', integration, async () => {
  const item = fixture([installer(0)]);
  item.input.firstPartyModules[0]!.verify = ['false'];
  const plan = buildPluginInstallPlan(item.input);
  await assert.rejects(executePluginInstallPlan(plan, item), rejected('plugin_prerequisite_missing'));
  assert.equal(item.count(), 0); assert.equal(existsSync(join(item.home, 'install-order')), false);
});

test('failed installer persists its exact exit and later retries do not reinstall completed dependencies', integration, async () => {
  const item = fixture([installer(0), 'test -f "$HOME/allow" || exit 17\n' + installer(1)]);
  await assert.rejects(executePluginInstallPlan(item.plan, item), rejected('plugin_install_failed'));
  const failed = JSON.parse(readFileSync(receiptPath(item.home, item.plan), 'utf8'));
  assert.equal(failed.status, 'failed'); assert.equal(failed.actions['plugin.example.tool1'].exitCode, 17);
  writeFileSync(join(item.home, 'allow'), 'yes');
  assert.equal((await executePluginInstallPlan(item.plan, item)).status, 'complete');
  assert.equal(readFileSync(join(item.home, 'install-order'), 'utf8'), '0\n1\n');
  assert.equal(item.count(), 3);
});

test('exit zero cannot claim success without the declared executable', integration, async () => {
  const item = fixture(['exit 0']);
  await assert.rejects(executePluginInstallPlan(item.plan, item), rejected('plugin_install_failed'));
  const state = JSON.parse(readFileSync(receiptPath(item.home, item.plan), 'utf8'));
  assert.equal(state.status, 'failed'); assert.equal(state.actions['plugin.example.tool0'].exitCode, 1);
});

test('executes reviewed sh entrypoints with positional arguments', integration, async () => {
  const item = fixture([installer(0, 'test "$1" = "literal value"')]);
  item.input.modules[0]!.verified_installer!.runner = 'sh';
  item.input.modules[0]!.verified_installer!.args = ['literal value'];
  assert.equal((await executePluginInstallPlan(buildPluginInstallPlan(item.input), item)).status, 'complete');
});

test('missing binary invalidates a successful checkpoint and triggers repair', integration, async () => {
  const item = fixture([installer(0)]);
  await executePluginInstallPlan(item.plan, item);
  renameSync(join(item.home, '.local/bin/acfs_fixture_0'), join(item.home, '.local/bin/old_fixture_0'));
  await executePluginInstallPlan(item.plan, item);
  assert.equal(item.count(), 2); assert.equal(readFileSync(join(item.home, 'install-order'), 'utf8'), '0\n0\n');
});

test('final sweep catches a later installer invalidating an earlier executable', integration, async () => {
  const item = fixture([installer(0), installer(1, 'mv "$HOME/.local/bin/acfs_fixture_0" "$HOME/old-tool"')]);
  await assert.rejects(executePluginInstallPlan(item.plan, item), rejected('plugin_verification_failed'));
  assert.equal(JSON.parse(readFileSync(receiptPath(item.home, item.plan), 'utf8')).status, 'failed');
});

test('rechecks target and plan digest before any persistent changes', integration, async () => {
  const item = fixture([installer(0)]);
  const bad = structuredClone(item.plan); bad.actions[0]!.installer.args.push('unreviewed');
  await assert.rejects(executePluginInstallPlan(bad, item), rejected('plugin_plan_changed'));
  const target = structuredClone(item.plan); target.target.version = 'unreviewed';
  await assert.rejects(executePluginInstallPlan(target, item), rejected('plugin_target_unsupported'));
  assert.equal(existsSync(join(item.home, '.acfs')), false); assert.equal(item.count(), 0);
});

test('does not follow symlinked state parents or repair unsafe permissions', integration, async () => {
  const item = fixture([installer(0)]); const other = mkdtempSync(join(tmpdir(), 'acfs-other-'));
  symlinkSync(other, join(item.home, '.acfs'));
  await assert.rejects(executePluginInstallPlan(item.plan, item), rejected('plugin_state_unsafe'));
  assert.equal(existsSync(join(other, 'plugin-installs')), false);
  const unsafe = fixture([installer(0)]); chmodSync(unsafe.home, 0o777);
  await assert.rejects(executePluginInstallPlan(unsafe.plan, unsafe), rejected('plugin_state_unsafe'));
});

test('refuses malformed, hardlinked and interrupted receipts without destroying evidence', integration, async () => {
  const item = fixture([installer(0)]); await executePluginInstallPlan(item.plan, item);
  const path = receiptPath(item.home, item.plan); const valid = readFileSync(path, 'utf8');
  writeFileSync(path, '{broken');
  await assert.rejects(executePluginInstallPlan(item.plan, item), rejected('plugin_state_invalid'));
  assert.equal(readFileSync(path, 'utf8'), '{broken');
  const state = JSON.parse(valid); state.actions['plugin.example.tool0'].status = 'running';
  writeFileSync(path, JSON.stringify(state));
  await assert.rejects(executePluginInstallPlan(item.plan, item), rejected('plugin_install_interrupted'));
  writeFileSync(path, valid); linkSync(path, join(item.home, 'receipt-hardlink'));
  await assert.rejects(executePluginInstallPlan(item.plan, item), rejected('plugin_state_unsafe'));
  assert.equal(readFileSync(path, 'utf8'), valid);
});

test('serializes concurrent installs with a real kernel lock and releases it after failure', integration, async () => {
  const item = fixture([installer(0)]);
  let arrived!: () => void; let proceed!: () => void;
  const ready = new Promise<void>((accept) => { arrived = accept; });
  const barrier = new Promise<void>((accept) => { proceed = accept; });
  const running = executePluginInstallPlan(item.plan, { ...item, download: async () => { arrived(); await barrier; return item.bytes[0]!; } });
  await ready;
  await assert.rejects(executePluginInstallPlan(item.plan, item), rejected('plugin_install_busy'));
  proceed(); await running;
  assert.equal((await executePluginInstallPlan(item.plan, item)).status, 'complete');
});

test('uses literal arguments, strips shell startup/credential environment, and enables no-new-privs', integration, async () => {
  const extra = 'test -z "${BASH_ENV-}"\ntest -z "${ACFS_TEST_SECRET-}"\n' +
    'grep -Eq "^NoNewPrivs:[[:space:]]+1$" /proc/self/status\nprintf "%s" "$1" > "$HOME/literal-arg"';
  const item = fixture([installer(0, extra)]);
  const poison = join(item.home, 'poison'); writeFileSync(poison, 'touch "$HOME/POISONED"');
  const previousBash = process.env.BASH_ENV; const previousSecret = process.env.ACFS_TEST_SECRET;
  process.env.BASH_ENV = poison; process.env.ACFS_TEST_SECRET = 'not-for-the-child';
  item.input.modules[0]!.verified_installer!.args = ['$(touch "$HOME/INJECTED")'];
  try {
    await executePluginInstallPlan(buildPluginInstallPlan(item.input), item);
    assert.equal(readFileSync(join(item.home, 'literal-arg'), 'utf8'), '$(touch "$HOME/INJECTED")');
    assert.equal(existsSync(join(item.home, 'INJECTED')), false); assert.equal(existsSync(join(item.home, 'POISONED')), false);
  } finally {
    if (previousBash === undefined) delete process.env.BASH_ENV; else process.env.BASH_ENV = previousBash;
    if (previousSecret === undefined) delete process.env.ACFS_TEST_SECRET; else process.env.ACFS_TEST_SECRET = previousSecret;
  }
});

test('enforces bounded runtime even when an installer ignores TERM', integration, async () => {
  const item = fixture(['trap "" TERM\nwhile :; do sleep 1; done']);
  const start = Date.now();
  await assert.rejects(executePluginInstallPlan(item.plan, { ...item, timeoutSeconds: 1 }), rejected('plugin_install_failed'));
  assert.ok(Date.now() - start < 8000);
  assert.equal(JSON.parse(readFileSync(receiptPath(item.home, item.plan), 'utf8')).status, 'failed');
});

test('cancellation records failure rather than success and releases the lock', integration, async () => {
  const item = fixture(['sleep 30\n' + installer(0)]); const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 250);
  try { await assert.rejects(executePluginInstallPlan(item.plan, { ...item, signal: controller.signal })); }
  finally { clearTimeout(timer); }
  const path = receiptPath(item.home, item.plan);
  const state = JSON.parse(readFileSync(path, 'utf8'));
  assert.equal(state.status, 'failed'); assert.equal(state.actions['plugin.example.tool0'].exitCode, 130);
  const lockResult = execFileSync('/usr/bin/flock', ['-n', join(item.home, '.acfs/plugin-installs/install.lock'), '/usr/bin/true']);
  assert.equal(lockResult.length, 0);
});

for (const url of ['http://example.com/install.sh', 'https://user:password@example.com/install.sh', 'https://example.com/install.sh#fragment']) {
  test(`refuses noncanonical download URL ${url}`, async () => {
    const item = fixture([installer(0)]); const action = structuredClone(item.plan.actions[0]!); action.installer.url = url;
    await assert.rejects(downloadPluginInstaller(action, new AbortController().signal), rejected('plugin_download_refused'));
  });
}

test('real TLS transport verifies bytes and refuses downgrade, bad certificates, loops, truncation and oversized data', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'acfs-plugin-tls-'));
  const key = join(directory, 'key.pem'); const cert = join(directory, 'cert.pem');
  execFileSync('/usr/bin/openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
    '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
    '-keyout', key, '-out', cert], { stdio: 'ignore' });
  const script = Buffer.from('echo verified\n');
  const server = createServer({ key: readFileSync(key), cert: readFileSync(cert) }, (request, response) => {
    switch (request.url) {
      case '/redirect': response.writeHead(302, { location: '/ok' }); response.end(); break;
      case '/loop': response.writeHead(302, { location: '/loop' }); response.end(); break;
      case '/downgrade': response.writeHead(302, { location: 'http://localhost/never' }); response.end(); break;
      case '/wrong': response.end('wrong bytes'); break;
      case '/empty': response.end(); break;
      case '/encoded': response.writeHead(200, { 'content-encoding': 'gzip' }); response.end(script); break;
      case '/large': response.end(Buffer.alloc(8 * 1024 * 1024 + 1)); break;
      case '/partial': response.writeHead(200, { 'content-length': '100' }); response.end('short'); break;
      case '/slow': break;
      default: response.end(script);
    }
  });
  await new Promise<void>((accept) => server.listen(0, '127.0.0.1', accept));
  const address = server.address(); assert.ok(address && typeof address !== 'string');
  const extension = extname(fileURLToPath(import.meta.url));
  const moduleUrl = new URL(`./plugin-runtime${extension}`, import.meta.url).href;
  async function request(path: string, trustCertificate = true, disableTls = false) {
    const action = { id: 'plugin.example.tool', verify: ['true'], installer: {
      tool: 'tool', url: `https://127.0.0.1:${address && typeof address !== 'string' ? address.port : 0}${path}`,
      sha256: digest(script), runner: 'bash', args: [] } };
    const code = `import {downloadPluginInstaller} from ${JSON.stringify(moduleUrl)};
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), ${path === '/slow' || path === '/partial' ? 300 : 5000});
      try { const value = await downloadPluginInstaller(${JSON.stringify(action)}, controller.signal);
        console.log(JSON.stringify({ok:true,content:value.toString()})); }
      catch(error) { console.log(JSON.stringify({ok:false,code:error.code,message:error.message})); }
      finally { clearTimeout(timer); }`;
    const args = process.versions.bun ? ['--eval', code] : ['--input-type=module', '--eval', code];
    return new Promise<{ ok: boolean; content?: string; code?: string; message?: string }>((accept, reject) => {
      const child = spawn(process.execPath, args, { env: { ...process.env,
        NODE_EXTRA_CA_CERTS: trustCertificate ? cert : '', NODE_TLS_REJECT_UNAUTHORIZED: disableTls ? '0' : '1' },
        stdio: ['ignore', 'pipe', 'pipe'] });
      let output = ''; let errors = '';
      child.stdout.on('data', (chunk) => { output += chunk.toString(); });
      child.stderr.on('data', (chunk) => { errors += chunk.toString(); });
      child.once('error', reject);
      child.once('close', (status) => {
        try { assert.equal(status, 0, errors); accept(JSON.parse(output)); } catch (error) { reject(error); }
      });
    });
  }
  try {
    for (const path of ['/ok', '/redirect']) assert.deepEqual(await request(path), { ok: true, content: script.toString() });
    assert.equal((await request('/wrong')).code, 'plugin_installer_hash_mismatch');
    for (const path of ['/loop', '/downgrade']) assert.equal((await request(path)).code, 'plugin_download_refused');
    for (const path of ['/empty', '/encoded', '/large', '/partial', '/slow']) {
      assert.equal((await request(path)).ok, false, path);
    }
    assert.equal((await request('/ok', false)).ok, false);
    assert.equal((await request('/ok', false, true)).ok, false, 'explicit TLS policy must override a poisoned environment');
  } finally { server.closeAllConnections(); await new Promise<void>((accept) => server.close(() => accept())); }
});
