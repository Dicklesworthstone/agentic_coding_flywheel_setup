/** Boundary tests use native Blob/UTF-8/WebCrypto and an explicit canonical-validator double. */
import { strict as assert } from 'node:assert';
import { createHash, webcrypto } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { createContext, runInContext } from 'node:vm';
const require = createRequire(import.meta.url);
const ts = require('typescript');
const url = new URL('./teamProfileImport.ts', import.meta.url);
const compiled = ts.transpileModule(readFileSync(url, 'utf8'), {
  fileName: fileURLToPath(url), reportDiagnostics: true,
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
});
assert.deepEqual((compiled.diagnostics ?? []).filter((item) => item.category === ts.DiagnosticCategory.Error), []);
const plain = (value) => JSON.parse(JSON.stringify(value));
function fixture() {
  const calls = []; let reject = false; let command = 'bash install.sh --profile "cloud-only" --skip "acfs.nightly"';
  const provenance = { manifestSha256: 'a'.repeat(64), checksumsYamlSha256: 'b'.repeat(64) };
  const context = { targetHost: '203.0.113.42', current: { architecture: 'x86_64', ubuntuVersion: '26.04',
    installMode: 'safe', username: 'ubuntu', ref: null, moduleSelection: { profile: 'full' } } };
  const dependencies = {
    './generated/manifest-modules': { manifestProvenance: provenance },
    './commandBuilder': { buildTeamProfileImportDiff(source, current) {
      calls.push({ source, current: plain(current) });
      return { schema: 'acfs.team-profile-import-diff.v1', schemaVersion: 1, dryRun: true, ok: !reject,
        profile: { profileId: 'example', displayName: 'Example', schemaVersion: 1 },
        findings: reject ? [{ code: 'team_profile_manifest_mismatch', path: 'PRIVATE_FIELD', message: 'PRIVATE_CONTENT' }] : [],
        safeDefaults: { changes: [] }, installerCommand: { command: reject ? null : command,
          changes: [{ field: 'install.profile', current: 'full', next: 'cloud-only' }] },
        dependencyClosure: ['lang.bun'], skips: { requested: ['acfs.nightly'], allowed: !reject, warnings: [] },
        secretSlots: { required: ['secret://acfs/team/github-auth'], optional: [] }, incompatibilities: [], refusals: [] };
    } },
  };
  const scope = createContext({ TextDecoder, TextEncoder, structuredClone, crypto: webcrypto });
  const module = { exports: {} };
  runInContext(`(function(require,module,exports){${compiled.outputText}\n})`, scope)((name) => {
    assert.ok(Object.hasOwn(dependencies, name), `unexpected dependency ${name}`); return dependencies[name];
  }, module, module.exports);
  return { api: module.exports, calls, context, provenance, scope,
    reject: () => { reject = true; }, changeCommand: () => { command += ' --no-deps'; } };
}
const file = (text = '{"schema":"fixture"}') => new Blob([text]);
const code = (expected) => (error) => error.code === expected;

test('reads real Blob bytes, binds independent SHA-256, and withholds command until confirmation', async () => {
  const item = fixture(); const text = '{ "schema": "fixture", "name":"日本語" }';
  const review = await item.api.reviewTeamProfileFile(file(text), item.context);
  assert.equal(review.sourceSha256, createHash('sha256').update(text).digest('hex'));
  assert.equal(review.diff.installerCommand.command, null);
  assert.equal(JSON.stringify(review).includes('203.0.113.42'), false);
  assert.equal(Object.isFrozen(review), true); assert.equal(Object.isFrozen(review.diff.installerCommand), true);
  assert.equal(Object.isFrozen(item.calls[0].source), true);
  assert.equal(item.api.teamProfileReviewMatches(review, item.context), true);
  const approved = item.api.approveTeamProfileReview(review, item.context, true);
  assert.match(approved.command, /--skip "acfs.nightly"/);
  assert.equal(item.calls.length, 2, 'approval must re-run the canonical validator');
  assert.equal(Object.isFrozen(approved), true);
});

for (const text of ['{"a":1,"a":2}', '{"a":1,"\\u0061":2}', '{"x":{"k":1,"k":2}}',
  '{"x":[{"k":1,"k":2}]}', '{"n":1e400}', '{"n":-1e400}', '\ufeff{}', '{"private":"SENSITIVE",oops}',
  '[]', 'null', '42', 'true', '"object"', '{} trailing']) {
  test(`rejects ambiguous or invalid JSON ${JSON.stringify(text)}`, async () => {
    const item = fixture();
    await assert.rejects(item.api.reviewTeamProfileFile(file(text), item.context), (error) => {
      assert.equal(error.code, 'team_profile_file_invalid'); assert.doesNotMatch(error.message, /SENSITIVE/); return true;
    });
    assert.equal(item.calls.length, 0);
  });
}

test('accepts escaped strings, harmless repeated names in different objects and standard whitespace', async () => {
  const item = fixture(); const value = { 'a"\\b': ['x', { same: 1 }, { same: 2 }], punctuation: '{},[]' };
  await item.api.reviewTeamProfileFile(file('\n\t' + JSON.stringify(value, null, 2)), item.context);
  assert.deepEqual(plain(item.calls[0].source), value);
});

test('enforces depth and node budgets before calling canonical validation', async () => {
  const item = fixture();
  for (const text of ['{"a":' + '['.repeat(34) + '0' + ']'.repeat(34) + '}',
    '{"a":' + JSON.stringify(Array(16_385).fill(0)) + '}']) {
    await assert.rejects(item.api.reviewTeamProfileFile(file(text), item.context), code('team_profile_file_invalid'));
  }
  assert.equal(item.calls.length, 0);
});

test('bounds file reads before allocation and enforces exact byte-count snapshots', async () => {
  const item = fixture(); let reads = 0;
  for (const size of [0, -1, NaN, 1.5, item.api.TEAM_PROFILE_FILE_LIMIT + 1]) {
    await assert.rejects(item.api.reviewTeamProfileFile({ size, slice() { reads++; } }, item.context), code('team_profile_file_invalid'));
  }
  assert.equal(reads, 0);
  const text = Buffer.from('{}');
  await assert.rejects(item.api.reviewTeamProfileFile({ size: 1, slice(start, end) {
    assert.equal(start, 0); assert.equal(end, 256 * 1024 + 1); return new Blob([text]);
  } }, item.context), code('team_profile_file_invalid'));
  const exact = '{"x":"' + 'a'.repeat(256 * 1024 - 8) + '"}';
  assert.equal(Buffer.byteLength(exact), 256 * 1024);
  await item.api.reviewTeamProfileFile(file(exact), item.context);
});

test('rejects invalid UTF-8 and redacts native read failures', async () => {
  const item = fixture();
  await assert.rejects(item.api.reviewTeamProfileFile(new Blob([Buffer.from([123, 34, 0xff, 34, 58, 49, 125])]), item.context), code('team_profile_file_invalid'));
  await assert.rejects(item.api.reviewTeamProfileFile({ size: 5, slice() { throw new Error('PRIVATE_PATH'); } }, item.context), (error) => {
    assert.equal(error.code, 'team_profile_read_failed'); assert.doesNotMatch(error.message, /PRIVATE/); return true;
  });
});

for (const confirmed of [false, undefined, 1, 'true']) {
  test(`requires actual explicit confirmation, not ${JSON.stringify(confirmed)}`, async () => {
    const item = fixture(); const review = await item.api.reviewTeamProfileFile(file(), item.context);
    assert.throws(() => item.api.approveTeamProfileReview(review, item.context, confirmed), code('team_profile_confirmation_required'));
    assert.equal(item.calls.length, 1);
  });
}

test('canonical refusal exposes only codes, not profile values, parser input or field paths', async () => {
  const item = fixture(); item.reject();
  await assert.rejects(item.api.reviewTeamProfileFile(file(), item.context), (error) => {
    assert.equal(error.code, 'team_profile_review_blocked');
    assert.deepEqual(plain(error.findingCodes), ['team_profile_manifest_mismatch']);
    assert.doesNotMatch(JSON.stringify(error) + error.message, /PRIVATE/); return true;
  });
});

for (const [name, change] of [
  ['host', (c) => { c.targetHost = '203.0.113.43'; }],
  ['architecture', (c) => { c.current.architecture = 'aarch64'; }],
  ['image', (c) => { c.current.ubuntuVersion = '24.04'; }],
  ['mode', (c) => { c.current.installMode = 'vibe'; }],
  ['ref', (c) => { c.current.ref = 'another'; }],
  ['username', (c) => { c.current.username = 'developer'; }],
  ['selection', (c) => { c.current.moduleSelection = { onlyModules: ['agents.claude'] }; }],
]) {
  test(`changed ${name} invalidates approval without reusing a retained command`, async () => {
    const item = fixture(); const review = await item.api.reviewTeamProfileFile(file(), item.context);
    change(item.context);
    assert.equal(item.api.teamProfileReviewMatches(review, item.context), false);
    assert.throws(() => item.api.approveTeamProfileReview(review, item.context, true), code('team_profile_review_changed'));
  });
}

test('changed canonical provenance and changed validator output both invalidate approval', async () => {
  const item = fixture(); const review = await item.api.reviewTeamProfileFile(file(), item.context);
  item.provenance.manifestSha256 = 'f'.repeat(64);
  assert.throws(() => item.api.approveTeamProfileReview(review, item.context, true), code('team_profile_review_changed'));
  const second = fixture(); const review2 = await second.api.reviewTeamProfileFile(file(), second.context);
  second.changeCommand();
  assert.throws(() => second.api.approveTeamProfileReview(review2, second.context, true), code('team_profile_review_changed'));
  second.reject();
  assert.throws(() => second.api.approveTeamProfileReview(review2, second.context, true), code('team_profile_review_blocked'));
});

test('deserialized or fabricated reviews cannot authorize a command', async () => {
  const item = fixture(); const review = await item.api.reviewTeamProfileFile(file(), item.context);
  for (const copy of [{}, structuredClone(review), { ...review }]) {
    assert.equal(item.api.teamProfileReviewMatches(copy, item.context), false);
    assert.throws(() => item.api.approveTeamProfileReview(copy, item.context, true), code('team_profile_review_changed'));
  }
  assert.equal(item.api.teamProfileReviewMatches(null, item.context), false);
  assert.equal(item.api.teamProfileReviewMatches(review, null), false);
});

test('context is captured before asynchronous file reads and cannot be reassociated afterwards', async () => {
  const item = fixture(); let resume;
  const wait = new Promise((done) => { resume = done; });
  const pending = item.api.reviewTeamProfileFile({ size: 2, slice() { return { async arrayBuffer() { await wait; return new TextEncoder().encode('{}').buffer; } }; } }, item.context);
  item.context.current.username = 'another-user'; resume();
  const review = await pending;
  assert.equal(item.calls[0].current.username, 'ubuntu');
  assert.equal(item.api.teamProfileReviewMatches(review, item.context), false);
});

test('missing secure crypto cannot mint a review', async () => {
  const item = fixture(); item.scope.crypto = null;
  await assert.rejects(item.api.reviewTeamProfileFile(file(), item.context), code('team_profile_hash_unavailable'));
  assert.equal(item.calls.length, 0);
});

test('explicit complete target context is required before reading', async () => {
  const item = fixture();
  for (const current of [{}, { architecture: 'aarch64' }, { architecture: 'unknown', ubuntuVersion: '26.04' }]) {
    await assert.rejects(item.api.reviewTeamProfileFile(file(), { ...item.context, current }), code('team_profile_context_required'));
  }
  await assert.rejects(item.api.reviewTeamProfileFile(file(), { ...item.context, targetHost: '' }), code('team_profile_context_required'));
});
