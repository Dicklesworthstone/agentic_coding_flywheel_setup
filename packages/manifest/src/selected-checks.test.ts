import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { renderSelectedManifestChecks, type SelectedDoctorModule } from './selected-checks.js';

const quote = (text: string): string => `'${text.replace(/'/g, `'\\''`)}'`;
const encode = (text: string): string => text.replace(/\\/g, '\\\\').replace(/\t/g, '\\t').replace(/\n/g, '\\n');
interface Check { id: string; cmd: string; policy?: string; context?: string; soft?: boolean }
const checks = (): Check[] => [
  { id: 'base.system.1', cmd: 'printf "base\\n" >> "$TEST_TRACE"' },
  { id: 'base.system.2', cmd: 'true' },
  { id: 'tools.selected', cmd: 'printf "selected\\n" >> "$TEST_TRACE"', context: 'target_user' },
  { id: 'tools.excluded', cmd: 'printf "EXCLUDED\\n" >> "$TEST_TRACE"; exit 9' },
  { id: 'tools.optional', cmd: 'false', policy: 'optional' },
  { id: 'tools.soft', cmd: 'false', policy: 'optional', soft: true },
];
function metadata(entries: Check[]): SelectedDoctorModule[] {
  const modules = new Map<string, SelectedDoctorModule>();
  for (const entry of entries) {
    const module = entry.id.replace(/\.[0-9]+$/, '');
    const previous = modules.get(module);
    modules.set(module, { id: module, checks: [...(previous?.checks ?? []), { id: entry.id, soft: entry.soft ?? false }] });
  }
  return [...modules.values()];
}
function run(args: string[], config: {
  entries?: Check[]; modules?: SelectedDoctorModule[]; rows?: string[]; setup?: string; conditional?: boolean;
} = {}) {
  const entries = config.entries ?? checks();
  const rows = config.rows ?? entries.map((entry) => [entry.id, 'Fixture', encode(entry.cmd), entry.policy ?? 'required', entry.context ?? 'root'].join('\t'));
  const directory = mkdtempSync(join(tmpdir(), 'acfs-selected-check-'));
  const trace = join(directory, 'trace');
  const script = [
    'set -euo pipefail',
    'declare -A ACFS_MODULE_FAMILIES=()',
    'acfs_generated_system_binary_path() { test "$1" = timeout && printf /usr/bin/timeout; }',
    'run_manifest_check_command() { printf "context:%s:budget:%s\\n" "$1" "$3" >> "$TEST_TRACE"; /bin/bash -p -o pipefail -c "$2"; }',
    renderSelectedManifestChecks(config.modules ?? metadata(entries)),
    `MANIFEST_CHECKS=(${rows.map(quote).join(' ')})`,
    config.setup ?? '',
    config.conditional
      ? `if run_selected_manifest_checks ${args.map(quote).join(' ')}; then exit 0; else exit $?; fi`
      : `run_selected_manifest_checks ${args.map(quote).join(' ')}`,
  ].join('\n');
  const result = spawnSync('/bin/bash', ['-p', '-c', script], {
    encoding: 'utf8', timeout: 5000, env: { PATH: '/usr/bin:/bin', TEST_TRACE: trace },
  });
  assert.ifError(result.error);
  return { ...result, trace: existsSync(trace) ? readFileSync(trace, 'utf8') : '' };
}

test('runs exactly selected modules and their complete check sets in manifest order', () => {
  const result = run(['--', 'tools.selected', 'base.system']);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /3 passed, 0 failed/);
  assert.match(result.trace, /base\n[\s\S]*selected\n/);
  assert.ok(!result.trace.includes('EXCLUDED'));
  assert.match(result.trace, /context:target_user:budget:30/);
});

test('failed selected check propagates without aborting checks for another selected module', () => {
  const result = run(['--', 'tools.excluded', 'tools.selected']);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /1 passed, 1 failed/);
  assert.match(result.trace, /selected/);
});

test('an implicitly included optional module remains a warning', () => {
  const result = run(['--', 'tools.optional']);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /0 passed, 0 failed, 1 warnings/);
});

test('explicitly requesting an optional module makes its failed delivery fatal', () => {
  const result = run(['--require-module', 'tools.optional', '--', 'tools.optional']);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /0 passed, 1 failed, 0 warnings/);
});

test('deliberately soft individual checks remain warnings even in a required module', () => {
  const result = run(['--require-module', 'tools.soft', '--', 'tools.soft']);
  assert.equal(result.status, 0);
  assert.match(result.stderr, /1 warnings/);
});

for (const args of [[], ['--'], ['tools.selected'], ['--all'], ['--only', 'tools.selected'],
  ['--', 'tools.missing'], ['--', 'tools.selected', 'tools.selected'], ['--', '$(touch attack)'],
  ['--', 'tools.selected;id'], ['--require-module'], ['--require-module', 'tools.optional', '--', 'tools.selected'],
  ['--require-module', 'tools.selected', '--require-module', 'tools.selected', '--', 'tools.selected'],
  ['--', ...Array(1025).fill('tools.selected')]]) {
  test(`refuses invalid selection ${JSON.stringify(args).slice(0, 140)}`, () => {
    const result = run(args);
    assert.equal(result.status, 2, result.stderr);
    assert.equal(result.trace, '');
  });
}

test('missing coverage for a later selected module stops before any checks execute', () => {
  const entries = checks();
  const result = run(['--', 'base.system', 'tools.selected'], { entries: entries.filter((entry) => entry.id !== 'tools.selected'), modules: metadata(entries) });
  assert.equal(result.status, 2);
  assert.equal(result.trace, '');
});

test('a module with no verification commands cannot be called verified', () => {
  const result = run(['--', 'tools.empty'], { modules: [...metadata(checks()), { id: 'tools.empty', checks: [] }] });
  assert.equal(result.status, 2);
  assert.equal(result.trace, '');
});

for (const row of [
  'tools.selected\tFixture\ttrue\trequired',
  'tools.selected\tFixture\ttrue\trequired\troot\textra',
  'tools.selected\tFixture\ttrue\tignore\troot',
  'tools.selected\tFixture\ttrue\trequired\tunknown',
  'evil;id\tFixture\ttrue\trequired\troot',
  'tools.unknown\tFixture\ttrue\trequired\troot',
  'tools.selected\tFixture\t\trequired\troot',
]) {
  test(`refuses malformed check data before execution: ${JSON.stringify(row)}`, () => {
    const result = run(['--', 'base.system'], { rows: [row] });
    assert.equal(result.status, 2);
    assert.equal(result.trace, '');
  });
}

test('duplicate check identities cannot conceal a failure', () => {
  const entries = checks(); entries.push({ ...entries[0]!, cmd: 'false' });
  const result = run(['--', 'base.system'], { entries, modules: metadata(checks()) });
  assert.equal(result.status, 2);
  assert.equal(result.trace, '');
});

test('family restrictions skip only the canonical incompatible module', () => {
  const result = run(['--', 'base.system', 'tools.selected'], {
    setup: "ACFS_MODULE_FAMILIES[tools.selected]='ubuntu'; ACFS_DISTRO_FAMILY=arch",
  });
  assert.equal(result.status, 0);
  assert.match(result.stderr, /2 passed, 0 failed, 0 warnings, 1 not applicable/);
  assert.ok(!result.trace.includes('selected'));
});

test('family-compatible checks do execute', () => {
  const result = run(['--', 'tools.selected'], {
    setup: "ACFS_MODULE_FAMILIES[tools.selected]='ubuntu debian'; ACFS_DISTRO_FAMILY=debian",
  });
  assert.equal(result.status, 0);
  assert.match(result.trace, /selected/);
});

test('missing family detection is not a successful skip', () => {
  const result = run(['--', 'tools.selected'], { setup: "ACFS_MODULE_FAMILIES[tools.selected]='ubuntu'" });
  assert.equal(result.status, 2);
  assert.equal(result.trace, '');
});

test('refuses unavailable bounded runner even when all checks are optional', () => {
  const result = run(['--', 'tools.optional'], { setup: 'acfs_generated_system_binary_path() { return 1; }' });
  assert.equal(result.status, 2);
  assert.equal(result.trace, '');
});

test('check commands preserve newlines, tabs, pipes and literal backslashes', () => {
  const result = run(['--', 'tools.literal'], { entries: [{
    id: 'tools.literal', cmd: 'value="line\\t"\n[[ "$value" == "line\\t" ]]\nprintf "hello\\tworld\\n" | grep -q world',
  }] });
  assert.equal(result.status, 0, result.stderr);
});

test('raw check output and command strings never enter the status report', () => {
  const result = run(['--', 'tools.private'], { entries: [{ id: 'tools.private', cmd: 'echo PRIVATE_TOKEN >&2; exit 17' }] });
  assert.equal(result.status, 1);
  assert.ok(!result.stdout.includes('PRIVATE_TOKEN'));
  assert.ok(!result.stderr.includes('PRIVATE_TOKEN'));
  assert.match(result.stderr, /verification exit 17/);
});

test('required timeout is failure, not completion', () => {
  const result = run(['--', 'tools.selected'], { setup: 'run_manifest_check_command() { return 124; }' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /verification exit 124/);
});

test('failure handling remains correct when called from a Bash conditional', () => {
  const result = run(['--', 'tools.excluded', 'base.system'], { conditional: true });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /2 passed, 1 failed/);
});

test('emitter refuses duplicate or unsafe catalogue identities', () => {
  for (const modules of [
    [{ id: 'tools.bad;id', checks: [] }],
    [{ id: 'tools.one', checks: [] }, { id: 'tools.one', checks: [] }],
    [{ id: 'tools.one', checks: [{ id: 'bad;id', soft: false }] }],
    [{ id: 'tools.one', checks: [{ id: 'tools.one', soft: false }, { id: 'tools.one', soft: true }] }],
  ]) assert.throws(() => renderSelectedManifestChecks(modules));
});
