import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { buildPluginInstallPlan, PluginPlanError, type PluginPlanInput, type PlannablePluginModule } from './plugin-plan.js';

function module(id: string, dependencies: string[] = []): PlannablePluginModule {
  return { id: `plugin.example.${id}`, phase: 6, run_as: 'target_user', enabled_by_default: false,
    dependencies, install: [], verify: [`command -v -- ${id} >/dev/null 2>&1`],
    plugin: { packageId: 'example', version: '1.0.0', sourceCommit: 'a'.repeat(40), pluginSha256: 'b'.repeat(64) },
    verified_installer: { tool: 'example', url: 'https://example.com/install.sh', runner: 'bash', args: [], env: [] } };
}
function input(): PluginPlanInput {
  return { modules: [module('app', ['plugin.example.lib', 'lang.bun']), module('lib'), module('unused')],
    firstPartyModules: [{ id: 'lang.bun', phase: 6, dependencies: ['base.system'], verify: ['bun --version'] },
      { id: 'base.system', phase: 1, verify: ['command -v curl'] }],
    installers: { example: { url: 'https://example.com/install.sh', sha256: 'c'.repeat(64) } },
    target: { os: 'ubuntu', version: '26.04', arch: 'x86_64', libc: 'glibc' },
    trust: { manifestSha256: 'd'.repeat(64), checksumsSha256: 'e'.repeat(64) }, only: ['plugin.example.app'] };
}
function invalid(change: (config: PluginPlanInput) => void): void {
  const config = input(); change(config);
  assert.throws(() => buildPluginInstallPlan(config), PluginPlanError);
}

test('explicit selection includes transitive dependencies but never the rest of the package', () => {
  const plan = buildPluginInstallPlan(input());
  assert.deepEqual(plan.actions.map((action) => action.id), ['plugin.example.lib', 'plugin.example.app']);
  assert.deepEqual(plan.prerequisites.map((entry) => entry.id), ['base.system', 'lang.bun']);
  assert.deepEqual(plan.actions[1]!.verify, ['app']);
  assert.equal(plan.actions[0]!.installer.sha256, 'c'.repeat(64));
  assert.ok(!JSON.stringify(plan).includes('unused'));
});

test('same selected graph is deterministic across module and dependency enumeration', () => {
  const config = input(); const plan = buildPluginInstallPlan(config);
  config.modules = [...config.modules].reverse(); config.firstPartyModules = [...config.firstPartyModules].reverse();
  config.modules.find((entry) => entry.id.endsWith('.app'))!.dependencies!.reverse();
  assert.deepEqual(buildPluginInstallPlan(config), plan);
});

test('plan owns and freezes all nested values without freezing or mutating caller input', () => {
  const config = input(); const before = JSON.stringify(config); const plan = buildPluginInstallPlan(config);
  assert.equal(JSON.stringify(config), before);
  assert.throws(() => plan.actions[0]!.installer.args.push('x'), TypeError);
  config.modules[1]!.verified_installer!.args!.push('new');
  assert.deepEqual(plan.actions[0]!.installer.args, []);
});

for (const only of [[], [''], ['plugin.example.missing'], ['base.system'], ['../escape'],
  ['plugin.example.app', 'plugin.example.app'], [1] as unknown as string[]]) {
  test(`refuses invalid explicit selection ${JSON.stringify(only)}`, () => invalid((config) => { config.only = only; }));
}
for (const skip of [['plugin.example.app'], ['plugin.example.lib'], ['base.system'], ['missing'],
  ['plugin.example.unused', 'plugin.example.unused']]) {
  test(`refuses contradictory or malformed skips ${JSON.stringify(skip)}`, () => invalid((config) => { config.skip = skip; }));
}

test('allows skipping unselected modules without widening the plan', () => {
  const config = input(); config.skip = ['plugin.example.unused'];
  assert.equal(buildPluginInstallPlan(config).actions.length, 2);
});
for (const issue of ['cycle', 'unknown', 'phase', 'duplicate', 'first-party-edge']) {
  test(`rejects invalid dependency graph: ${issue}`, () => invalid((config) => {
    if (issue === 'cycle') config.modules[1]!.dependencies = ['plugin.example.app'];
    if (issue === 'unknown') config.modules[1]!.dependencies = ['lang.missing'];
    if (issue === 'phase') config.modules[1]!.phase = 9;
    if (issue === 'duplicate') config.modules = [...config.modules, config.modules[0]!];
    if (issue === 'first-party-edge') config.firstPartyModules[1]!.dependencies = ['plugin.example.lib'];
  }));
}
for (const change of [
  (config: PluginPlanInput) => { config.modules[0]!.run_as = 'root'; },
  (config: PluginPlanInput) => { config.modules[0]!.run_as = 'current'; },
  (config: PluginPlanInput) => { config.modules[0]!.enabled_by_default = true; },
  (config: PluginPlanInput) => { config.modules[0]!.install = ['touch injected']; },
  (config: PluginPlanInput) => { config.modules[0]!.verify = ['echo injected']; },
  (config: PluginPlanInput) => { config.modules[0]!.verify = []; },
  (config: PluginPlanInput) => { config.modules[0]!.plugin!.pluginSha256 = 'f'.repeat(64); },
  (config: PluginPlanInput) => { config.modules[0]!.plugin!.packageId = 'other'; },
  (config: PluginPlanInput) => { config.modules[0]!.verified_installer!.env = ['BASH_ENV=attack']; },
  (config: PluginPlanInput) => { config.modules[0]!.verified_installer!.runner = 'python'; },
  (config: PluginPlanInput) => { config.modules[0]!.verified_installer!.fallback_url = 'https://example.com/evil'; },
  (config: PluginPlanInput) => { config.modules[0]!.verified_installer!.args = ['--']; },
  (config: PluginPlanInput) => { config.modules[0]!.verified_installer!.args = ['\0']; },
  (config: PluginPlanInput) => { config.installers = {}; },
  (config: PluginPlanInput) => { config.installers.example!.sha256 = 'bad'; },
  (config: PluginPlanInput) => { config.installers.example!.url = 'https://example.com/other'; },
  (config: PluginPlanInput) => { config.trust.manifestSha256 = ''; },
  (config: PluginPlanInput) => { config.target.libc = ''; },
  (config: PluginPlanInput) => { config.firstPartyModules[0]!.verify = []; },
]) {
  test(`rejects execution-boundary mutation ${change.toString()}`, () => invalid(change));
}

test('binds every execution-relevant change into the plan fingerprint', () => {
  const original = buildPluginInstallPlan(input()).planSha256;
  for (const change of [
    (config: PluginPlanInput) => { config.modules[0]!.verified_installer!.args = ['--yes']; },
    (config: PluginPlanInput) => { config.modules[0]!.verify = ['command -v -- other >/dev/null 2>&1']; },
    (config: PluginPlanInput) => { config.installers.example!.sha256 = 'f'.repeat(64); },
    (config: PluginPlanInput) => { config.firstPartyModules[0]!.verify = ['bun --revision']; },
    (config: PluginPlanInput) => { config.trust.checksumsSha256 = 'f'.repeat(64); },
    (config: PluginPlanInput) => { config.target.arch = 'aarch64'; },
  ]) {
    const config = input(); change(config);
    assert.notEqual(buildPluginInstallPlan(config).planSha256, original);
  }
});

test('refuses inherited installer entries', () => invalid((config) => {
  config.installers = Object.create({ example: config.installers.example });
}));
