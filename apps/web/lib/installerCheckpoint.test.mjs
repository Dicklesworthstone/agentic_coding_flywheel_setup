/** Native Web Crypto tests for the context-bound wizard acknowledgement key. */
import { strict as assert } from 'node:assert';
import { createHash, webcrypto } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { createContext, runInContext } from 'node:vm';

const require = createRequire(import.meta.url);
const ts = require('typescript');
const sourceUrl = new URL('./installerCheckpoint.ts', import.meta.url);
const compiled = ts.transpileModule(readFileSync(sourceUrl, 'utf8'), {
  fileName: fileURLToPath(sourceUrl), reportDiagnostics: true,
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
});
assert.deepEqual((compiled.diagnostics ?? []).filter((entry) => entry.category === ts.DiagnosticCategory.Error), []);
function load(crypto = webcrypto) {
  const context = createContext({ crypto, TextEncoder });
  const module = { exports: {} };
  runInContext(`(function(module,exports){${compiled.outputText}\n})`, context)(module, module.exports);
  return module.exports;
}
const api = load();
const input = () => ({ command: 'bash install.sh --profile "cloud-only" --mode safe --ref "reviewed-tag"',
  host: '203.0.113.42', manifestSha256: 'a'.repeat(64), checksumsYamlSha256: 'b'.repeat(64) });
const expected = (value) => 'run-flywheel-installer-v2-' + createHash('sha256').update(JSON.stringify([
  'acfs.installer-acknowledgement.v1', value.command, value.host, value.manifestSha256, value.checksumsYamlSha256,
])).digest('hex');

test('native Web Crypto matches the independently computed SHA-256 and produces an opaque key', async () => {
  const value = input(); const checkpoint = await api.createInstallerCheckpoint(value);
  assert.equal(checkpoint.persistKey, expected(value));
  assert.match(checkpoint.persistKey, /^run-flywheel-installer-v2-[a-f0-9]{64}$/);
  for (const privateValue of [value.host, value.command, 'reviewed-tag']) {
    assert.ok(!checkpoint.persistKey.includes(privateValue));
  }
  assert.equal(api.installerCheckpointMatches(checkpoint, value), true);
  assert.ok(Object.isFrozen(checkpoint));
});

test('identical context is stable across calls and property enumeration order', async () => {
  const value = input(); const a = await api.createInstallerCheckpoint(value);
  const b = await api.createInstallerCheckpoint(Object.fromEntries(Object.entries(value).reverse()));
  assert.equal(a.persistKey, b.persistKey);
  assert.equal((await api.createInstallerCheckpoint({ ...value })).persistKey, a.persistKey);
});

for (const [field, replacement] of [
  ['command', 'bash install.sh --profile "full" --mode vibe'], ['host', '203.0.113.43'],
  ['manifestSha256', 'c'.repeat(64)], ['checksumsYamlSha256', 'd'.repeat(64)],
]) {
  test(`binds ${field} into both the digest and late-result check`, async () => {
    const value = input(); const old = await api.createInstallerCheckpoint(value);
    const next = { ...value, [field]: replacement }; const changed = await api.createInstallerCheckpoint(next);
    assert.notEqual(old.persistKey, changed.persistKey);
    assert.equal(api.installerCheckpointMatches(old, next), false);
    assert.equal(api.installerCheckpointMatches(changed, next), true);
  });
}

test('captures immutable context before awaiting the digest', async () => {
  let resolve;
  let captured;
  const pending = new Promise((done) => { resolve = done; });
  const deferred = load({ subtle: { digest: async (algorithm, bytes) => {
    captured = await webcrypto.subtle.digest(algorithm, bytes); await pending; return captured;
  } } });
  const value = input(); const before = { ...value }; const promise = deferred.createInstallerCheckpoint(value);
  value.host = '203.0.113.99'; value.command = 'different-command'; value.manifestSha256 = 'f'.repeat(64);
  resolve();
  const result = await promise;
  assert.equal(result.persistKey, expected(before));
  assert.equal(result.host, before.host); assert.equal(result.command, before.command);
  assert.equal(deferred.installerCheckpointMatches(result, value), false);
});

test('JSON framing prevents ambiguity between command and host components', async () => {
  const a = { ...input(), command: 'a|b', host: 'c' };
  const b = { ...input(), command: 'a', host: 'b|c' };
  assert.notEqual((await api.createInstallerCheckpoint(a)).persistKey, (await api.createInstallerCheckpoint(b)).persistKey);
});

test('accepts IPv6 and Unicode command data without evaluating any command text', async () => {
  const value = { ...input(), host: '2001:db8::1', command: 'echo "日本語 $(not-executed)"' };
  assert.equal((await api.createInstallerCheckpoint(value)).persistKey, expected(value));
});

for (const [label, value] of [
  ['missing context', null], ['empty command', { ...input(), command: '' }],
  ['oversized command', { ...input(), command: 'x'.repeat(65_537) }],
  ['NUL in command', { ...input(), command: 'private\0command' }],
  ['empty host', { ...input(), host: '' }], ['padded host', { ...input(), host: ' 203.0.113.42' }],
  ['control in host', { ...input(), host: 'private\nhost' }],
  ['oversized host', { ...input(), host: 'x'.repeat(257) }],
  ['missing manifest binding', { ...input(), manifestSha256: undefined }],
  ['invalid checksum binding', { ...input(), checksumsYamlSha256: 'SECRET' }],
]) {
  test(`refuses ${label} without exposing input values`, async () => {
    await assert.rejects(api.createInstallerCheckpoint(value), (error) => {
      assert.match(error.message, /complete installer context/);
      assert.doesNotMatch(error.message, /SECRET|private|203\.0\.113/); return true;
    });
  });
}

test('fails closed without browser crypto instead of falling back to a shared completion key', async () => {
  const noCrypto = load(null);
  await assert.rejects(noCrypto.createInstallerCheckpoint(input()), /Secure browser hashing is unavailable/);
});

test('missing, unbound, and malformed checkpoint results never match', async () => {
  const value = input(); const valid = await api.createInstallerCheckpoint(value);
  assert.equal(api.installerCheckpointMatches(undefined, value), false);
  assert.equal(api.installerCheckpointMatches(valid, null), false);
  assert.equal(api.installerCheckpointMatches({ ...valid, persistKey: 'run-flywheel-installer' }, value), false);
  assert.equal(api.installerCheckpointMatches({ ...valid, persistKey: undefined }, value), false);
});
