/** Portable, plan-bound plugin entrypoints. Execution may still require networking. */
import { createHash } from 'node:crypto';
import {
  closeSync, constants, fstatSync, fsyncSync, lstatSync, mkdirSync, openSync,
  readdirSync, readSync, writeFileSync,
} from 'node:fs';
import { dirname, join, parse, resolve } from 'node:path';
import { TextDecoder } from 'node:util';
import type { PluginInstallAction, PluginInstallPlan } from './plugin-plan.js';
import type { PluginInstallReceipt, PluginRuntimeOptions } from './plugin-runtime.js';

export const PLUGIN_CACHE_LIMITS = Object.freeze({
  entrypointBytes: 8 * 1024 * 1024,
  totalBytes: 32 * 1024 * 1024,
  manifestBytes: 1024 * 1024,
  entries: 1024,
  lifetimeMs: 30 * 24 * 60 * 60 * 1000,
});
const POLICY = Object.freeze({
  entrypointFetchMode: 'cache_only',
  executionNetworkMode: 'may_be_required',
  transitiveClosure: 'not_bundled',
});
export class PluginCacheError extends Error {
  constructor(public readonly code: string, message: string) {
    super(message); this.name = 'PluginCacheError';
  }
}
export type PluginInstallerDownload = (action: PluginInstallAction, signal: AbortSignal) => Promise<Buffer>;
interface CacheEntry {
  moduleId: string; tool: string; url: string; sha256: string; sizeBytes: number; path: string;
}
interface CacheManifest {
  schema: 'acfs.plugin-entrypoint-cache.v1';
  planSha256: string;
  packageSha256: string;
  generatedAt: string;
  expiresAt: string;
  policy: typeof POLICY;
  entries: CacheEntry[];
}
export interface PluginCacheSummary {
  schema: 'acfs.plugin-entrypoint-cache-summary.v1';
  planSha256: string;
  packageSha256: string;
  moduleCount: number;
  artifactCount: number;
  totalBytes: number;
  expiresAt: string;
  entrypointFetchMode: 'cache_only';
  executionNetworkMode: 'may_be_required';
  transitiveClosure: 'not_bundled';
}
export interface PluginCacheOptions { signal?: AbortSignal; now?: number }
export interface LoadedPluginInstallerCache {
  summary: PluginCacheSummary;
  /** Returns fresh copies of verified snapshots, never rereads mutable cache paths. */
  download: PluginInstallerDownload;
}
const hash = (bytes: Uint8Array): string => createHash('sha256').update(bytes).digest('hex');
const serialize = (value: unknown): string => JSON.stringify(value, null, 2) + '\n';
const HEX = /^[a-f0-9]{64}$/;
function refuse(code: string, message: string): never { throw new PluginCacheError(code, message); }
function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function keys(value: object, expected: string): boolean {
  return Object.keys(value).sort().join(',') === expected;
}
function cancelled(signal?: AbortSignal): void {
  if (signal?.aborted) refuse('plugin_cache_cancelled', 'Plugin cache operation cancelled');
}
function clock(now: number): number {
  if (!Number.isSafeInteger(now) || now < 0 || now > 8_640_000_000_000_000 - PLUGIN_CACHE_LIMITS.lifetimeMs) {
    refuse('plugin_cache_invalid', 'Plugin cache clock is invalid');
  }
  return now;
}
function canonicalTime(value: unknown): number {
  if (typeof value !== 'string') return refuse('plugin_cache_invalid', 'Plugin cache timestamp is invalid');
  const time = Date.parse(value);
  if (!Number.isFinite(time) || new Date(time).toISOString() !== value) {
    return refuse('plugin_cache_invalid', 'Plugin cache timestamp must be canonical UTC');
  }
  return time;
}

/** Plans must come from the canonical reviewed loader; their digest is not a signature. */
function snapshotPlan(plan: PluginInstallPlan): PluginInstallPlan {
  const copy: PluginInstallPlan = structuredClone(plan);
  const { planSha256, ...payload } = copy;
  if (!HEX.test(planSha256) || hash(Buffer.from(JSON.stringify(payload))) !== planSha256
      || copy.schema !== 'acfs.plugin-install-plan.v1' || !HEX.test(copy.package.pluginSha256)
      || !Array.isArray(copy.actions) || copy.actions.length < 1 || copy.actions.length > PLUGIN_CACHE_LIMITS.entries
      || new Set(copy.actions.map((action) => action.id)).size !== copy.actions.length) {
    return refuse('plugin_cache_plan_mismatch', 'Plugin cache requires an unchanged reviewed install plan');
  }
  for (const action of copy.actions) {
    const installer = action.installer;
    if (!/^plugin\.[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$/.test(action.id)
        || !/^[a-z][a-z0-9_]*$/.test(installer.tool) || !HEX.test(installer.sha256)
        || !['bash', 'sh'].includes(installer.runner)) {
      refuse('plugin_cache_plan_mismatch', 'Plugin plan has invalid installer metadata');
    }
    const url = new URL(installer.url);
    if (url.protocol !== 'https:' || url.username || url.password || url.hash) {
      refuse('plugin_cache_plan_mismatch', 'Plugin installer source must be credential-free HTTPS');
    }
  }
  return copy;
}

/** Reject symlinked components, not merely a symlink at the final filename. */
function realDirectory(path: string, allowStickyParent = false): void {
  let current = parse(path).root;
  for (const part of path.slice(current.length).split('/').filter(Boolean)) {
    current = join(current, part);
    const stat = lstatSync(current);
    if (!stat.isDirectory() || stat.isSymbolicLink()) {
      refuse('plugin_cache_path_unsafe', 'Plugin cache has a non-directory or symlinked path component');
    }
  }
  const stat = lstatSync(path);
  if ((stat.mode & 0o022) !== 0 && !(allowStickyParent && (stat.mode & 0o1000) !== 0 && stat.uid === 0)) {
    refuse('plugin_cache_path_unsafe', 'Plugin cache directory is writable by other users');
  }
}
function cachePath(value: string): string {
  if (typeof value !== 'string' || !value.length || /[\x00-\x1f\x7f]/.test(value)) {
    return refuse('plugin_cache_path_unsafe', 'Plugin cache path is invalid');
  }
  return resolve(value);
}
function readSnapshot(path: string, limit: number): Buffer {
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const before = fstatSync(fd);
    if (!before.isFile() || before.nlink !== 1 || before.size < 1 || before.size > limit
        || (before.mode & 0o022) !== 0) {
      refuse('plugin_cache_file_unsafe', 'Cache members must be bounded, nonempty single-link regular files without unsafe permissions');
    }
    const bytes = Buffer.alloc(before.size + 1);
    let offset = 0;
    while (offset < bytes.length) {
      const count = readSync(fd, bytes, offset, bytes.length - offset, null);
      if (!count) break;
      offset += count;
    }
    const after = fstatSync(fd);
    if (offset !== before.size || after.size !== before.size || after.nlink !== 1
        || after.mtimeMs !== before.mtimeMs || after.ctimeMs !== before.ctimeMs) {
      refuse('plugin_cache_changed', 'Plugin cache member changed during snapshot acquisition');
    }
    return bytes.subarray(0, offset);
  } finally { closeSync(fd); }
}
function exclusiveWrite(path: string, bytes: Uint8Array): void {
  const fd = openSync(path, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  try { writeFileSync(fd, bytes); fsyncSync(fd); } finally { closeSync(fd); }
}
function syncDirectory(path: string): void {
  const fd = openSync(path, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
  try { fsyncSync(fd); } finally { closeSync(fd); }
}
function summary(manifest: CacheManifest, blobs: Map<string, Buffer>): PluginCacheSummary {
  return { schema: 'acfs.plugin-entrypoint-cache-summary.v1', planSha256: manifest.planSha256,
    packageSha256: manifest.packageSha256, moduleCount: manifest.entries.length,
    artifactCount: blobs.size, totalBytes: [...blobs.values()].reduce((total, bytes) => total + bytes.length, 0),
    expiresAt: manifest.expiresAt, ...POLICY };
}
function safeError(error: unknown): never {
  if (error instanceof PluginCacheError) throw error;
  return refuse('plugin_cache_unavailable', 'Plugin cache could not be read or prepared safely; no live entrypoint fallback is permitted');
}

/** Acquire all selected scripts, then publish a new directory with manifest.json LAST. */
export async function preparePluginInstallerCache(
  input: PluginInstallPlan,
  outputDirectory: string,
  download: PluginInstallerDownload,
  options: PluginCacheOptions = {},
): Promise<PluginCacheSummary> {
  try {
    const signal = options.signal ?? new AbortController().signal;
    cancelled(signal);
    const plan = snapshotPlan(input);
    const generatedAt = clock(options.now ?? Date.now());
    const output = cachePath(outputDirectory);
    realDirectory(dirname(output), true);
    try {
      lstatSync(output);
      refuse('plugin_cache_output_exists', 'Cache output already exists; choose a new directory');
    } catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
    const blobs = new Map<string, Buffer>();
    const acquired = new Map<string, string>();
    const entries: CacheEntry[] = [];
    let total = 0;
    let executionBytes = 0;
    for (const action of plan.actions) {
      cancelled(signal);
      const identity = JSON.stringify([action.installer.url, action.installer.sha256]);
      const path = `scripts/${action.installer.sha256}.sh`;
      const existing = acquired.get(identity);
      let bytes = existing ? blobs.get(existing) : undefined;
      if (!bytes) {
        bytes = Buffer.from(await download(structuredClone(action), signal));
        cancelled(signal);
        if (!bytes.length || bytes.length > PLUGIN_CACHE_LIMITS.entrypointBytes || hash(bytes) !== action.installer.sha256) {
          refuse('plugin_cache_hash_mismatch', 'Entrypoint bytes do not match the reviewed canonical digest');
        }
        acquired.set(identity, path);
      }
      if (!blobs.has(path)) {
        total += bytes.length;
        if (total > PLUGIN_CACHE_LIMITS.totalBytes) refuse('plugin_cache_too_large', 'Selected entrypoints exceed the cache size budget');
        blobs.set(path, bytes);
      }
      executionBytes += bytes.length;
      if (executionBytes > PLUGIN_CACHE_LIMITS.totalBytes) {
        refuse('plugin_cache_too_large', 'Selected actions exceed the runtime staging budget');
      }
      entries.push({ moduleId: action.id, tool: action.installer.tool, url: action.installer.url,
        sha256: action.installer.sha256, sizeBytes: bytes.length, path });
    }
    const manifest: CacheManifest = { schema: 'acfs.plugin-entrypoint-cache.v1', planSha256: plan.planSha256,
      packageSha256: plan.package.pluginSha256, generatedAt: new Date(generatedAt).toISOString(),
      expiresAt: new Date(generatedAt + PLUGIN_CACHE_LIMITS.lifetimeMs).toISOString(), policy: POLICY, entries };
    const manifestBytes = Buffer.from(serialize(manifest));
    if (manifestBytes.length > PLUGIN_CACHE_LIMITS.manifestBytes) refuse('plugin_cache_too_large', 'Cache metadata exceeds its size budget');
    cancelled(signal);
    realDirectory(dirname(output), true);
    // mkdir reserves the destination atomically. Never merge or replace existing user data.
    try { mkdirSync(output, { mode: 0o700 }); }
    catch (error) {
      if ((error as NodeJS.ErrnoException).code === 'EEXIST') refuse('plugin_cache_output_exists', 'Cache output already exists; choose a new directory');
      throw error;
    }
    mkdirSync(join(output, 'scripts'), { mode: 0o700 });
    for (const [path, bytes] of blobs) {
      cancelled(signal); exclusiveWrite(join(output, path), bytes);
    }
    syncDirectory(join(output, 'scripts'));
    cancelled(signal);
    // A failed publication is retained for inspection, not deleted or marked complete.
    exclusiveWrite(join(output, 'manifest.json'), manifestBytes);
    syncDirectory(output); syncDirectory(dirname(output));
    return summary(manifest, blobs);
  } catch (error) { return safeError(error); }
}

/** Check the COMPLETE selected cache before exposing any executable byte snapshots. */
export function loadPluginInstallerCache(
  directory: string,
  input: PluginInstallPlan,
  options: PluginCacheOptions = {},
): LoadedPluginInstallerCache {
  try {
    cancelled(options.signal);
    const plan = snapshotPlan(input);
    const now = clock(options.now ?? Date.now());
    const root = cachePath(directory);
    realDirectory(root); realDirectory(join(root, 'scripts'));
    if (readdirSync(root).sort().join(',') !== 'manifest.json,scripts') {
      refuse('plugin_cache_invalid', 'Plugin cache contains undeclared root members');
    }
    const bytes = readSnapshot(join(root, 'manifest.json'), PLUGIN_CACHE_LIMITS.manifestBytes);
    const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
    const data: unknown = JSON.parse(text);
    if (!record(data) || serialize(data) !== text
        || !keys(data, 'entries,expiresAt,generatedAt,packageSha256,planSha256,policy,schema')
        || data.schema !== 'acfs.plugin-entrypoint-cache.v1'
        || !record(data.policy) || !keys(data.policy, 'entrypointFetchMode,executionNetworkMode,transitiveClosure')
        || data.policy.entrypointFetchMode !== POLICY.entrypointFetchMode
        || data.policy.executionNetworkMode !== POLICY.executionNetworkMode
        || data.policy.transitiveClosure !== POLICY.transitiveClosure) {
      refuse('plugin_cache_invalid', 'Plugin cache schema, canonical JSON, or entrypoint-only policy is invalid');
    }
    if (data.planSha256 !== plan.planSha256 || data.packageSha256 !== plan.package.pluginSha256) {
      refuse('plugin_cache_plan_mismatch', 'Cache does not match the current reviewed selection, target, package, or trust inputs');
    }
    const generated = canonicalTime(data.generatedAt);
    const expires = canonicalTime(data.expiresAt);
    if (generated > now || expires <= now || expires - generated !== PLUGIN_CACHE_LIMITS.lifetimeMs) {
      refuse('plugin_cache_expired', 'Plugin cache is expired, future-dated, or has an invalid validity interval');
    }
    if (!Array.isArray(data.entries) || data.entries.length !== plan.actions.length) {
      refuse('plugin_cache_incomplete', 'Cache must cover every selected plugin action exactly once');
    }
    const blobs = new Map<string, Buffer>();
    const byAction = new Map<string, { action: string; path: string }>();
    const actions = new Map(plan.actions.map((action) => [action.id, action]));
    let total = 0;
    let executionBytes = 0;
    for (const entry of data.entries) {
      cancelled(options.signal);
      if (!record(entry) || !keys(entry, 'moduleId,path,sha256,sizeBytes,tool,url') || typeof entry.moduleId !== 'string') {
        refuse('plugin_cache_invalid', 'Plugin cache entry is malformed');
      }
      const action = actions.get(entry.moduleId);
      if (!action || byAction.has(entry.moduleId) || entry.tool !== action.installer.tool
          || entry.url !== action.installer.url || entry.sha256 !== action.installer.sha256
          || entry.path !== `scripts/${action.installer.sha256}.sh`
          || !Number.isSafeInteger(entry.sizeBytes) || (entry.sizeBytes as number) < 1
          || (entry.sizeBytes as number) > PLUGIN_CACHE_LIMITS.entrypointBytes) {
        refuse('plugin_cache_plan_mismatch', 'Cache entry is missing, duplicated, unsafe, or differs from the reviewed installer');
      }
      const path = entry.path as string;
      let script = blobs.get(path);
      if (!script) {
        script = readSnapshot(join(root, path), PLUGIN_CACHE_LIMITS.entrypointBytes);
        total += script.length;
        if (total > PLUGIN_CACHE_LIMITS.totalBytes) refuse('plugin_cache_too_large', 'Cache exceeds its total entrypoint budget');
        if (hash(script) !== action.installer.sha256) refuse('plugin_cache_hash_mismatch', 'Cached entrypoint digest does not match canonical checksums');
        blobs.set(path, script);
      }
      if (script.length !== entry.sizeBytes) refuse('plugin_cache_hash_mismatch', 'Cached entrypoint size differs from its declaration');
      executionBytes += script.length;
      if (executionBytes > PLUGIN_CACHE_LIMITS.totalBytes) {
        refuse('plugin_cache_too_large', 'Selected actions exceed the runtime staging budget');
      }
      byAction.set(entry.moduleId, { path, action: JSON.stringify(action) });
    }
    const expectedFiles = [...blobs.keys()].map((path) => path.slice('scripts/'.length)).sort();
    if (JSON.stringify(readdirSync(join(root, 'scripts')).sort()) !== JSON.stringify(expectedFiles)) {
      refuse('plugin_cache_invalid', 'Plugin cache contains undeclared script members');
    }
    cancelled(options.signal);
    const result = summary(data as unknown as CacheManifest, blobs);
    return {
      summary: result,
      download: async (action, signal) => {
        cancelled(signal);
        const expected = byAction.get(action.id);
        if (!expected || expected.action !== JSON.stringify(action)) {
          return refuse('plugin_cache_plan_mismatch', 'Requested action was not verified in this cache snapshot');
        }
        return Buffer.from(blobs.get(expected.path)!);
      },
    };
  } catch (error) { return safeError(error); }
}

/** The selected cache is the ONLY acquisition channel; never retry through HTTPS. */
export async function executeCachedPluginInstallPlan(
  input: PluginInstallPlan,
  directory: string,
  options: Omit<PluginRuntimeOptions, 'download'> = {},
): Promise<PluginInstallReceipt> {
  const plan = snapshotPlan(input);
  const cache = loadPluginInstallerCache(directory, plan, { signal: options.signal });
  const { executePluginInstallPlan } = await import('./plugin-runtime.js');
  // Assign download last: an untyped caller cannot accidentally override cache-only acquisition.
  return executePluginInstallPlan(plan, { ...options, download: cache.download });
}
