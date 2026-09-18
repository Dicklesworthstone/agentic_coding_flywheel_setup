/** Production Bash JSON serialization, with controlled checks rather than live host probes. */
import { strict as assert } from 'node:assert';
import { execFileSync } from 'node:child_process';
import { webcrypto } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';
const require = createRequire(import.meta.url);
const ts = require('typescript');
const module = { exports: {} };
runInNewContext(ts.transpileModule(readFileSync(new URL('./doctorReport.ts', import.meta.url), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText, { module, exports: module.exports, crypto: webcrypto, TextDecoder });
const reader = module.exports;

// The override is a test-only seam for running a fetched emitter snapshot in a
// partial checkout. The default always reads the repository's real doctor.sh.
const source = readFileSync(process.env.ACFS_DOCTOR_TEST_SOURCE
  ?? new URL('../../../scripts/lib/doctor.sh', import.meta.url), 'utf8');
const start = source.indexOf('print_json() {');
const end = source.indexOf('\n# Main\n', start);
assert.ok(start >= 0 && end > start, 'the actual print_json function must be present');
const emitter = source.slice(start, end);
const quote = (value) => `'${value.replaceAll("'", "'\\''")}'`;

for (const deep of [false, true]) {
  test(`accepts actual print_json output with mixed check results (deep=${deep})`, async () => {
    const checks = [
      { id: 'tool.bun', status: 'pass' }, { id: 'agent.claude', status: 'fail' },
      { id: 'agent.codex', status: 'skip' }, { id: 'deep.cloud.gh_auth', status: 'timeout' },
      { id: 'updates.holds', status: 'warn' },
    ].map((check) => ({ ...check, label: 'PRIVATE "label"', details: 'PRIVATE path\nsecond line',
      fix: 'do-not-run --private-value' }));
    const script = [
      'set -euo pipefail', 'NODE_BINARY="$1"',
      `json_escape() { printf '%s' "$1" | "$NODE_BINARY" -e 'let text="";process.stdin.on("data",chunk=>text+=chunk);process.stdin.on("end",()=>process.stdout.write(JSON.stringify(text).slice(1,-1)));'; }`,
      `_acfs_doctor_resolve_current_user() { printf 'fixture-user'; }`,
      'ACFS_VERSION=0.9.0', 'ACFS_MODE=safe', `DEEP_MODE=${deep}`,
      'PASS_COUNT=1', 'FAIL_COUNT=1', 'SKIP_COUNT=1', 'WARN_COUNT=2',
      'DEEP_PASS_COUNT=0', 'DEEP_FAIL_COUNT=0', 'DEEP_WARN_COUNT=1', 'DEEP_CHECK_ELAPSED=1',
      `JSON_CHECKS=(${checks.map((check) => quote(JSON.stringify(check))).join(' ')})`,
      emitter, 'print_json',
    ].join('\n');
    const bytes = execFileSync('/bin/bash', ['-p', '-s', '--', process.execPath], {
      input: script, env: { PATH: '/usr/bin:/bin', LANG: 'C.UTF-8', TZ: 'UTC' }, timeout: 10000,
    });
    const raw = JSON.parse(bytes.toString()); assert.equal(raw.deep_mode, deep);
    assert.equal(raw.summary.warn, 2); assert.equal(raw.deep_summary !== undefined, deep);
    const value = await reader.reviewDoctorReportFile(new Blob([bytes]), {
      host: '203.0.113.7', username: 'fixture-user', mode: 'safe', installerCommand: 'fixture-installer',
      manifestSha256: 'a'.repeat(64), checksumsYamlSha256: 'b'.repeat(64),
      selectedModuleIds: ['lang.bun', 'agents.claude'], knownModuleIds: ['lang.bun', 'agents.claude', 'agents.codex'],
    });
    assert.equal(value.modules[0].status, 'pass'); assert.equal(value.modules[1].status, 'fail');
    assert.equal(value.unmapped.timeout, 1); assert.equal(value.unmapped.warn, 1);
    assert.equal(value.outsideSelection.skip, 1); assert.equal(value.userMatches, true);
    assert.equal(value.totals.timeout, 1); assert.equal(value.totals.warn, 1);
    assert.ok(!JSON.stringify(value).includes('PRIVATE')); assert.ok(!JSON.stringify(value).includes('do-not-run'));
  });
}
