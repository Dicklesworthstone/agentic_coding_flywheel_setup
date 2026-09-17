#!/usr/bin/env bun
/** Explicit two-step plugin planning/install command; never activates generator inputs. */
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { buildPluginInstallPlan, PluginPlanError, type PluginInstallPlan, type PluginPlanTarget } from './plugin-plan.js';
import { executePluginInstallPlan, PluginInstallError, type PluginInstallReceipt } from './plugin-runtime.js';

export interface PluginInstallArguments {
  archive: string;
  review: string;
  target: PluginPlanTarget;
  only: string[];
  skip: string[];
  apply: boolean;
  acceptPlan?: string;
  json: boolean;
}
export function parsePluginInstallArguments(args: readonly string[]): PluginInstallArguments {
  const values = new Map<string, string>();
  const flags = new Set<string>();
  for (let index = 0; index < args.length; index++) {
    const option = args[index]!;
    if (['--yes', '--dry-run', '--json'].includes(option)) {
      if (flags.has(option)) throw new Error('Duplicate plugin install option');
      flags.add(option); continue;
    }
    if (!['--archive', '--review', '--target', '--only', '--skip', '--accept-plan'].includes(option)
        || values.has(option)) throw new Error('Unknown or duplicate plugin install option');
    const value = args[++index];
    if (!value || value.startsWith('--')) throw new Error('Plugin install option requires a value');
    values.set(option, value);
  }
  for (const required of ['--archive', '--review', '--target', '--only']) {
    if (!values.has(required)) throw new Error('Explicit archive, review, target and module selection are required');
  }
  const parts = values.get('--target')!.split('/');
  if (parts.length !== 4 || parts.some((part) => !/^[a-z0-9][a-z0-9_.-]{0,63}$/.test(part))) {
    throw new Error('Target must be os/version/arch/libc');
  }
  const parseIds = (key: string): string[] => {
    const value = values.get(key);
    if (value === undefined) return [];
    const ids = value.split(',');
    if (ids.length > 1024 || ids.some((id) => !/^plugin\.[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/.test(id))
        || new Set(ids).size !== ids.length) throw new Error('Module selections must be unique exact plugin IDs');
    return ids;
  };
  const apply = flags.has('--yes');
  const acceptPlan = values.get('--accept-plan');
  if ((apply && flags.has('--dry-run')) || (apply !== (acceptPlan !== undefined))
      || (acceptPlan !== undefined && !/^[a-f0-9]{64}$/.test(acceptPlan))) {
    throw new Error('Installation requires --yes and the exact --accept-plan digest; --dry-run cannot be combined with installation');
  }
  return { archive: values.get('--archive')!, review: values.get('--review')!,
    target: { os: parts[0]!, version: parts[1]!, arch: parts[2]!, libc: parts[3]! },
    only: parseIds('--only'), skip: parseIds('--skip'), apply, acceptPlan, json: flags.has('--json') };
}

/** Load one immutable pair of canonical trust files, then validate the reviewed archive. */
export async function loadPluginInstallPlan(options: PluginInstallArguments): Promise<PluginInstallPlan> {
  const { readPluginInputFile } = await import('./plugin-archive.js');
  const { readReviewedPluginArchive } = await import('./plugin-review.js');
  // Reject untrusted archives before importing the canonical manifest dependencies.
  readReviewedPluginArchive(options.archive, options.review, options.target);
  const { parseManifestString } = await import('./parser.js');
  const { parse: parseYaml } = await import('yaml');
  const { loadReviewedPluginPackage } = await import('./plugin-verify.js');
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
  const manifestBytes = readPluginInputFile(join(root, 'acfs.manifest.yaml'), 4 * 1024 * 1024);
  const checksumBytes = readPluginInputFile(join(root, 'checksums.yaml'), 1024 * 1024);
  const manifest = parseManifestString(manifestBytes.toString('utf8'));
  const checksumData: unknown = parseYaml(checksumBytes.toString('utf8'));
  if (!manifest.success || !manifest.data || typeof checksumData !== 'object' || checksumData === null
      || !('installers' in checksumData) || typeof checksumData.installers !== 'object'
      || checksumData.installers === null || Array.isArray(checksumData.installers)) {
    throw new PluginInstallError('plugin_trust_inputs_invalid', 'Canonical manifest or checksum database is invalid');
  }
  const installers: Record<string, { url: string; sha256: string }> = {};
  for (const [tool, value] of Object.entries(checksumData.installers)) {
    if (!/^[a-z][a-z0-9_]*$/.test(tool) || typeof value !== 'object' || value === null
        || !('url' in value) || typeof value.url !== 'string'
        || !('sha256' in value) || typeof value.sha256 !== 'string') {
      throw new PluginInstallError('plugin_trust_inputs_invalid', 'Canonical installer checksum entry is malformed');
    }
    installers[tool] = { url: value.url, sha256: value.sha256 };
  }
  const result = await loadReviewedPluginPackage(options.archive, options.review, {
    firstPartyManifest: manifest.data, installers, target: options.target,
  });
  if (!result.valid || result.diagnostics.length > 0) {
    throw new PluginInstallError('plugin_validation_failed', 'Archive/review or canonical manifest validation refused this package; run plugin:verify for diagnostics');
  }
  const hash = (bytes: Buffer): string => createHash('sha256').update(bytes).digest('hex');
  return buildPluginInstallPlan({ modules: result.manifestModules, firstPartyModules: manifest.data.modules,
    installers, target: options.target, only: options.only, skip: options.skip,
    trust: { manifestSha256: hash(manifestBytes), checksumsSha256: hash(checksumBytes) } });
}

/** Dependency seams are for in-process tests; no CLI or environment flag overrides trust. */
export interface PluginInstallCommandServices {
  loadPlan: (options: PluginInstallArguments) => Promise<PluginInstallPlan>;
  execute: (plan: PluginInstallPlan, signal: AbortSignal) => Promise<PluginInstallReceipt>;
  write: (message: string) => void;
}
export async function pluginInstallMain(
  args: readonly string[],
  services: PluginInstallCommandServices = {
    loadPlan: loadPluginInstallPlan,
    execute: (plan, signal) => executePluginInstallPlan(plan, { signal }),
    write: (message) => console.log(message),
  },
): Promise<number> {
  if (args.length === 1 && ['--help', '-h'].includes(args[0]!)) {
    services.write('Usage: bun run plugin:install --archive package.tar.gz --review trusted-review.json --target os/version/arch/libc --only plugin.package.module[,id...] [--skip id,...] [--json]\nDefault: read-only plan; no network, installers, or state writes.\nApply: repeat the same inputs with --yes --accept-plan <planSha256>. Run as the target user, never root.');
    return 0;
  }
  const json = args.includes('--json');
  const controller = new AbortController();
  let cancelCode = 0;
  const interrupt = (): void => { cancelCode = 130; controller.abort(); };
  const terminate = (): void => { cancelCode = 143; controller.abort(); };
  process.once('SIGINT', interrupt); process.once('SIGTERM', terminate);
  let parsed = false;
  try {
    const options = parsePluginInstallArguments(args); parsed = true;
    const plan = await services.loadPlan(options);
    controller.signal.throwIfAborted();
    if (!options.apply) {
      services.write(json ? JSON.stringify({ status: 'planned', mode: 'dry-run', plan })
        : `Plugin plan ${plan.planSha256}\nInstall: ${plan.actions.map((action) => action.id).join(', ')}\nExisting prerequisites: ${plan.prerequisites.map((entry) => entry.id).join(', ') || 'none'}\nNo changes made. Apply with the same inputs plus --yes --accept-plan ${plan.planSha256}`);
      return 0;
    }
    if (options.acceptPlan !== plan.planSha256) {
      throw new PluginInstallError('plugin_plan_changed', 'Plan changed since review; preview the current plan before installation');
    }
    const receipt = await services.execute(plan, controller.signal);
    controller.signal.throwIfAborted();
    if (receipt.status !== 'complete' || receipt.planSha256 !== plan.planSha256
        || receipt.packageSha256 !== plan.package.pluginSha256
        || Object.keys(receipt.actions).sort().join(',') !== plan.actions.map((action) => action.id).sort().join(',')
        || Object.values(receipt.actions).some((action) => action.status !== 'complete' || action.exitCode !== 0)) {
      throw new PluginInstallError('plugin_install_incomplete', 'Installation did not produce a complete verified receipt');
    }
    services.write(json ? JSON.stringify({ status: 'complete', mode: 'install', receipt })
      : `Plugin installation verified: ${plan.actions.map((action) => action.id).join(', ')}\nReceipt: ~/.acfs/plugin-installs/${plan.planSha256}.json`);
    return 0;
  } catch (error) {
    const known = error instanceof PluginInstallError || error instanceof PluginPlanError;
    const diagnostic = { code: cancelCode ? 'plugin_install_cancelled' : known ? error.code : parsed ? 'plugin_trust_inputs_unavailable' : 'plugin_install_arguments_invalid',
      message: cancelCode ? 'Plugin installation cancelled; no success was recorded'
        : known ? error.message : parsed ? 'Package verification could not complete; check trust inputs and manifest dependencies'
          : 'Invalid install options; use --help for explicit selection and plan approval syntax' };
    services.write(json ? JSON.stringify({ status: 'failed', diagnostic }) : `${diagnostic.code}: ${diagnostic.message}`);
    return cancelCode || (parsed ? 1 : 2);
  } finally { process.removeListener('SIGINT', interrupt); process.removeListener('SIGTERM', terminate); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.exitCode = await pluginInstallMain(process.argv.slice(2));
}
