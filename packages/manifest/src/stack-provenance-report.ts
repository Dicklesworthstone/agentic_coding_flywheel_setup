#!/usr/bin/env bun
/**
 * Cross-tool provenance and upstream release report for ACFS stack tools.
 */

import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { parse as parseYaml } from 'yaml';
import { parseManifestFile, validateManifestData } from './parser.js';
import { validateManifest as validateManifestAdvanced } from './validate.js';
import { resolveModuleCategory } from './utils.js';
import type { Manifest, Module } from './types.js';

export type ReportStatus = 'pass' | 'warn' | 'fail' | 'unknown' | 'skip';
export type NetworkMode = 'skip' | 'check';
export type RepositoryResolution = 'github' | 'unsupported_href' | 'missing_href';

export interface InstallerChecksumEntry {
  url: string;
  sha256: string;
}

export interface ChecksumsFile {
  generatedAt?: string;
  installers: Record<string, InstallerChecksumEntry>;
}

export interface ChecksumDiff {
  tool: string;
  kind: 'added' | 'removed' | 'url_changed' | 'sha256_changed' | 'url_and_sha256_changed';
  current?: InstallerChecksumEntry;
  candidate?: InstallerChecksumEntry;
}

export interface GitHubReleaseFixture {
  status: 'ok' | 'missing' | 'error';
  tagName?: string;
  publishedAt?: string;
  htmlUrl?: string;
  detail?: string;
}

export interface ReleaseFetchResponse {
  ok: boolean;
  status: number;
  json(): Promise<unknown>;
  text(): Promise<string>;
}

export type ReleaseFetcher = (url: string) => Promise<ReleaseFetchResponse>;

export interface BuildReportOptions {
  manifest: Manifest;
  currentChecksums: ChecksumsFile;
  network: NetworkMode;
  candidateChecksums?: ChecksumsFile;
  githubReleases?: Record<string, GitHubReleaseFixture>;
  fetcher?: ReleaseFetcher;
  generatedAt?: string;
}

export interface LocalProvenanceResult {
  status: ReportStatus;
  detail: string;
}

export interface CandidateResult {
  status: ReportStatus;
  detail: string;
  diff?: ChecksumDiff;
}

export interface ReleaseResult {
  status: ReportStatus;
  relation: 'skipped' | 'same_or_older' | 'newer_upstream_release' | 'missing_release' | 'unknown';
  detail: string;
  tagName?: string;
  publishedAt?: string;
  htmlUrl?: string;
}

export interface StackToolReport {
  moduleId: string;
  displayName: string;
  cliName?: string;
  toolKey?: string;
  repositoryResolution: RepositoryResolution;
  sourceHref?: string;
  repo?: string;
  repoName?: string;
  verifiedInstaller: boolean;
  manifestInstallerUrl?: string;
  checksumUrl?: string;
  checksumSha256?: string;
  status: ReportStatus;
  local: LocalProvenanceResult;
  candidate: CandidateResult;
  release: ReleaseResult;
  advisories: string[];
}

export interface StackProvenanceReport {
  ok: boolean;
  generatedAt: string;
  mode: {
    network: NetworkMode;
    candidateSource: 'skipped' | 'provided' | 'generated' | 'unavailable';
  };
  summary: Record<ReportStatus, number>;
  checksums: {
    generatedAt?: string;
    installerCount: number;
  };
  tools: StackToolReport[];
  checksumDiffs: {
    stack: ChecksumDiff[];
    unrelated: ChecksumDiff[];
  };
  advisories: string[];
}

interface StackToolSource {
  module: Module;
  displayName: string;
  cliName?: string;
  toolKey?: string;
  repositoryResolution: RepositoryResolution;
  sourceHref?: string;
  repo?: string;
  repoName?: string;
  verifiedInstaller: boolean;
  manifestInstallerUrl?: string;
  checksumEntry?: InstallerChecksumEntry;
}

const SCRIPT_FILE = fileURLToPath(import.meta.url);
const DEFAULT_ROOT = resolve(dirname(SCRIPT_FILE), '../../..');
const GITHUB_OWNER = 'Dicklesworthstone';
const SHA256_PATTERN = /^[a-f0-9]{64}$/i;
const STATUS_RANK: Record<ReportStatus, number> = {
  pass: 0,
  skip: 1,
  unknown: 2,
  warn: 3,
  fail: 4,
};

function asRecord(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function asString(value: unknown): string | undefined {
  return typeof value === 'string' ? value : undefined;
}

function statusMax(statuses: ReportStatus[]): ReportStatus {
  return statuses.reduce<ReportStatus>(
    (max, status) => (STATUS_RANK[status] > STATUS_RANK[max] ? status : max),
    'pass'
  );
}

function combinedToolStatus(statuses: ReportStatus[]): ReportStatus {
  const actionable = statuses.filter((status) => status !== 'skip');
  return actionable.length > 0 ? statusMax(actionable) : 'skip';
}

function summarizeStatus(tools: StackToolReport[], unrelatedDiffs: ChecksumDiff[]): Record<ReportStatus, number> {
  const summary: Record<ReportStatus, number> = {
    pass: 0,
    warn: 0,
    fail: 0,
    unknown: 0,
    skip: 0,
  };

  for (const tool of tools) {
    summary[tool.local.status] += 1;
    summary[tool.candidate.status] += 1;
    summary[tool.release.status] += 1;
  }

  if (unrelatedDiffs.length > 0) {
    summary.fail += 1;
  }

  return summary;
}

function parseChecksumsGeneratedAt(content: string): string | undefined {
  const match = content.match(/^# checksums\.yaml - Auto-generated (.+)$/m);
  return match?.[1]?.trim();
}

export function parseChecksumsYaml(content: string): ChecksumsFile {
  const parsed = asRecord(parseYaml(content));
  const installersRaw = asRecord(parsed.installers);
  const installers: Record<string, InstallerChecksumEntry> = {};

  for (const [tool, rawEntry] of Object.entries(installersRaw)) {
    const entry = asRecord(rawEntry);
    const url = asString(entry.url);
    const sha256 = asString(entry.sha256);
    if (url && sha256) {
      installers[tool] = { url, sha256 };
    }
  }

  return {
    generatedAt: parseChecksumsGeneratedAt(content),
    installers,
  };
}

function githubRepoFromHref(href: string | undefined): { repo: string; repoName: string } | undefined {
  if (!href) return undefined;

  const match = href.match(/^https:\/\/github\.com\/([^/]+)\/([^/#?]+)(?:[/?#].*)?$/);
  if (!match) return undefined;

  const owner = match[1];
  const repoName = match[2];
  if (owner !== GITHUB_OWNER) return undefined;

  return {
    repo: `${owner}/${repoName}`,
    repoName,
  };
}

function inferToolKey(module: Module, repoName: string | undefined, checksums: ChecksumsFile): string | undefined {
  if (module.verified_installer?.tool) {
    return module.verified_installer.tool;
  }

  if (repoName) {
    for (const [tool, entry] of Object.entries(checksums.installers)) {
      if (entry.url.includes(`/${GITHUB_OWNER}/${repoName}/`)) {
        return tool;
      }
    }
  }

  const cliName = module.web?.cli_name;
  if (cliName && checksums.installers[cliName]) {
    return cliName;
  }

  for (const alias of module.web?.cli_aliases ?? []) {
    if (checksums.installers[alias]) {
      return alias;
    }
  }

  return undefined;
}

function collectStackTools(manifest: Manifest, checksums: ChecksumsFile): StackToolSource[] {
  const tools: StackToolSource[] = [];

  for (const module of manifest.modules) {
    if (resolveModuleCategory(module) !== 'stack') continue;

    const sourceHref = module.web?.href;
    const repoInfo = githubRepoFromHref(sourceHref);
    const repositoryResolution: RepositoryResolution = repoInfo
      ? 'github'
      : sourceHref
        ? 'unsupported_href'
        : 'missing_href';
    const repo = repoInfo?.repo;
    const repoName = repoInfo?.repoName;
    const toolKey = inferToolKey(module, repoName, checksums);
    const checksumEntry = toolKey ? checksums.installers[toolKey] : undefined;
    const manifestInstallerUrl = module.verified_installer?.url;

    tools.push({
      module,
      displayName: module.web?.display_name ?? module.description,
      cliName: module.web?.cli_name,
      toolKey,
      repositoryResolution,
      sourceHref,
      repo,
      repoName,
      verifiedInstaller: Boolean(module.verified_installer),
      manifestInstallerUrl,
      checksumEntry,
    });
  }

  return tools.sort((a, b) => a.module.id.localeCompare(b.module.id));
}

function evaluateLocalProvenance(tool: StackToolSource): LocalProvenanceResult {
  if (!tool.verifiedInstaller) {
    if (tool.checksumEntry) {
      return {
        status: 'warn',
        detail: 'module uses custom install commands even though a checksum entry exists',
      };
    }
    return {
      status: 'warn',
      detail: 'module uses custom install commands without a verified installer checksum entry',
    };
  }

  if (!tool.toolKey) {
    return {
      status: 'fail',
      detail: 'verified installer has no tool key',
    };
  }

  if (!tool.checksumEntry) {
    return {
      status: 'fail',
      detail: `checksums.yaml is missing installer entry ${tool.toolKey}`,
    };
  }

  if (!SHA256_PATTERN.test(tool.checksumEntry.sha256)) {
    return {
      status: 'fail',
      detail: `checksums.yaml has invalid sha256 for ${tool.toolKey}`,
    };
  }

  if (tool.manifestInstallerUrl && tool.manifestInstallerUrl !== tool.checksumEntry.url) {
    return {
      status: 'fail',
      detail: `manifest URL differs from checksums.yaml for ${tool.toolKey}`,
    };
  }

  return {
    status: 'pass',
    detail: `verified installer ${tool.toolKey} has matching checksum provenance`,
  };
}

function diffEntryKind(
  current: InstallerChecksumEntry | undefined,
  candidate: InstallerChecksumEntry | undefined
): ChecksumDiff['kind'] | undefined {
  if (!current && candidate) return 'added';
  if (current && !candidate) return 'removed';
  if (!current || !candidate) return undefined;

  const urlChanged = current.url !== candidate.url;
  const shaChanged = current.sha256 !== candidate.sha256;
  if (urlChanged && shaChanged) return 'url_and_sha256_changed';
  if (urlChanged) return 'url_changed';
  if (shaChanged) return 'sha256_changed';
  return undefined;
}

export function diffChecksums(current: ChecksumsFile, candidate: ChecksumsFile): ChecksumDiff[] {
  const tools = new Set([...Object.keys(current.installers), ...Object.keys(candidate.installers)]);
  const diffs: ChecksumDiff[] = [];

  for (const tool of Array.from(tools).sort()) {
    const currentEntry = current.installers[tool];
    const candidateEntry = candidate.installers[tool];
    const kind = diffEntryKind(currentEntry, candidateEntry);
    if (kind) {
      diffs.push({
        tool,
        kind,
        current: currentEntry,
        candidate: candidateEntry,
      });
    }
  }

  return diffs;
}

function evaluateCandidate(
  tool: StackToolSource,
  diff: ChecksumDiff | undefined,
  network: NetworkMode,
  candidateAvailable: boolean
): CandidateResult {
  if (network === 'skip') {
    return {
      status: 'skip',
      detail: 'network checksum candidate check skipped',
    };
  }

  if (!candidateAvailable) {
    return {
      status: 'unknown',
      detail: 'checksum candidate unavailable',
    };
  }

  if (!tool.toolKey) {
    return {
      status: 'unknown',
      detail: 'no checksum tool key is available for candidate comparison',
    };
  }

  if (!diff) {
    return {
      status: 'pass',
      detail: 'candidate checksum entry matches checked-in provenance',
    };
  }

  return {
    status: 'fail',
    detail: `candidate checksum differs for ${tool.toolKey} (${diff.kind})`,
    diff,
  };
}

function parseDate(value: string | undefined): Date | undefined {
  if (!value) return undefined;
  const time = Date.parse(value);
  return Number.isNaN(time) ? undefined : new Date(time);
}

function fixtureForRepo(
  fixtures: Record<string, GitHubReleaseFixture> | undefined,
  repo: string | undefined,
  repoName: string | undefined
): GitHubReleaseFixture | undefined {
  if (!fixtures || !repo || !repoName) return undefined;
  return fixtures[repo] ?? fixtures[repoName];
}

async function fetchLatestRelease(
  tool: StackToolSource,
  fixture: GitHubReleaseFixture | undefined,
  fetcher: ReleaseFetcher | undefined
): Promise<GitHubReleaseFixture> {
  if (fixture) return fixture;
  if (!tool.repo) {
    return { status: 'error', detail: 'repository is unresolved' };
  }

  const activeFetcher = fetcher ?? defaultReleaseFetcher;
  const url = `https://api.github.com/repos/${tool.repo}/releases/latest`;

  try {
    const response = await activeFetcher(url);
    if (response.status === 404) {
      return {
        status: 'missing',
        detail: 'GitHub reports no latest release',
      };
    }
    if (!response.ok) {
      const body = await response.text().catch(() => '');
      return {
        status: 'error',
        detail: `GitHub latest release request failed with HTTP ${response.status}${body ? `: ${body.slice(0, 120)}` : ''}`,
      };
    }

    const body = asRecord(await response.json());
    return {
      status: 'ok',
      tagName: asString(body.tag_name),
      publishedAt: asString(body.published_at) ?? asString(body.created_at),
      htmlUrl: asString(body.html_url),
    };
  } catch (error) {
    return {
      status: 'error',
      detail: error instanceof Error ? error.message : String(error),
    };
  }
}

async function defaultReleaseFetcher(url: string): Promise<ReleaseFetchResponse> {
  const fetchFn = globalThis.fetch;
  if (!fetchFn) {
    throw new Error('fetch is not available in this runtime');
  }

  return fetchFn(url, {
    headers: {
      Accept: 'application/vnd.github+json',
      'User-Agent': 'acfs-stack-provenance-report',
    },
  }) as Promise<ReleaseFetchResponse>;
}

function evaluateRelease(
  tool: StackToolSource,
  latest: GitHubReleaseFixture,
  checksumsGeneratedAt: string | undefined,
  network: NetworkMode
): ReleaseResult {
  if (tool.repositoryResolution !== 'github') {
    return {
      status: 'unknown',
      relation: 'unknown',
      detail: tool.repositoryResolution === 'missing_href'
        ? 'module has no repository href'
        : `module href is not a supported ${GITHUB_OWNER} GitHub repository: ${tool.sourceHref}`,
    };
  }

  if (network === 'skip') {
    return {
      status: 'skip',
      relation: 'skipped',
      detail: 'GitHub latest release check skipped',
    };
  }

  if (latest.status === 'missing') {
    return {
      status: 'warn',
      relation: 'missing_release',
      detail: latest.detail ?? 'GitHub has no latest release metadata for this repo',
    };
  }

  if (latest.status === 'error') {
    return {
      status: 'unknown',
      relation: 'unknown',
      detail: latest.detail ?? 'GitHub latest release metadata unavailable',
    };
  }

  const latestDate = parseDate(latest.publishedAt);
  const checksumDate = parseDate(checksumsGeneratedAt);
  if (!latestDate || !checksumDate) {
    return {
      status: 'unknown',
      relation: 'unknown',
      detail: 'release date or checksums snapshot date is unavailable',
      tagName: latest.tagName,
      publishedAt: latest.publishedAt,
      htmlUrl: latest.htmlUrl,
    };
  }

  if (latestDate.getTime() > checksumDate.getTime()) {
    const rchSpecial = tool.toolKey === 'rch';
    return {
      status: rchSpecial ? 'fail' : 'warn',
      relation: 'newer_upstream_release',
      detail: rchSpecial
        ? 'rch release is newer than the checksum snapshot; checksum refresh review is mandatory'
        : 'latest release is newer than the checksum snapshot',
      tagName: latest.tagName,
      publishedAt: latest.publishedAt,
      htmlUrl: latest.htmlUrl,
    };
  }

  return {
    status: 'pass',
    relation: 'same_or_older',
    detail: 'latest release is not newer than the checksum snapshot',
    tagName: latest.tagName,
    publishedAt: latest.publishedAt,
    htmlUrl: latest.htmlUrl,
  };
}

function buildAdvisories(
  tool: StackToolSource,
  local: LocalProvenanceResult,
  candidate: CandidateResult,
  release: ReleaseResult
): string[] {
  const advisories: string[] = [];

  if (tool.toolKey === 'rch' && release.relation === 'newer_upstream_release') {
    advisories.push('rch requires canonical checksum refresh review after release changes');
  }
  if (tool.toolKey === 'rch' && candidate.status === 'fail') {
    advisories.push('rch installer candidate changed; review checksums.yaml before release');
  }
  if (local.status === 'warn' && !tool.verifiedInstaller) {
    advisories.push('custom install path is outside verified_installer coverage');
  }
  if (candidate.status === 'fail') {
    advisories.push('do not replace checksums.yaml until this diff is reviewed');
  }

  return advisories;
}

function assertManifestSemanticallyValid(manifest: Manifest): void {
  const basicValidation = validateManifestData(manifest);
  if (!basicValidation.valid) {
    throw new Error(
      `Manifest semantic validation failed: ${basicValidation.errors
        .map(({ path, message }) => `${path}: ${message}`)
        .join('; ')}`
    );
  }
  const advancedValidation = validateManifestAdvanced(manifest);
  if (!advancedValidation.valid) {
    throw new Error(
      `Manifest semantic validation failed: ${advancedValidation.errors
        .map(({ code, message }) => `${code}: ${message}`)
        .join('; ')}`
    );
  }
}

export async function buildStackProvenanceReport(options: BuildReportOptions): Promise<StackProvenanceReport> {
  assertManifestSemanticallyValid(options.manifest);
  const generatedAt = options.generatedAt ?? new Date().toISOString();
  const stackTools = collectStackTools(options.manifest, options.currentChecksums);
  const checksumDiffs = options.candidateChecksums
    ? diffChecksums(options.currentChecksums, options.candidateChecksums)
    : [];
  const stackToolKeys = new Set(stackTools.map((tool) => tool.toolKey).filter((tool): tool is string => Boolean(tool)));
  const stackDiffs = checksumDiffs.filter((diff) => stackToolKeys.has(diff.tool));
  const unrelatedDiffs = checksumDiffs.filter((diff) => !stackToolKeys.has(diff.tool));
  const reports: StackToolReport[] = [];

  for (const tool of stackTools) {
    const local = evaluateLocalProvenance(tool);
    const diff = tool.toolKey ? stackDiffs.find((candidateDiff) => candidateDiff.tool === tool.toolKey) : undefined;
    const candidate = evaluateCandidate(tool, diff, options.network, Boolean(options.candidateChecksums));
    const latest = options.network === 'skip' || tool.repositoryResolution !== 'github'
      ? { status: 'error' as const, detail: 'GitHub latest release check skipped' }
      : await fetchLatestRelease(
          tool,
          fixtureForRepo(options.githubReleases, tool.repo, tool.repoName),
          options.fetcher
        );
    const release = evaluateRelease(tool, latest, options.currentChecksums.generatedAt, options.network);
    const advisories = buildAdvisories(tool, local, candidate, release);
    const status = combinedToolStatus([local.status, candidate.status, release.status]);

    reports.push({
      moduleId: tool.module.id,
      displayName: tool.displayName,
      cliName: tool.cliName,
      toolKey: tool.toolKey,
      repositoryResolution: tool.repositoryResolution,
      sourceHref: tool.sourceHref,
      repo: tool.repo,
      repoName: tool.repoName,
      verifiedInstaller: tool.verifiedInstaller,
      manifestInstallerUrl: tool.manifestInstallerUrl,
      checksumUrl: tool.checksumEntry?.url,
      checksumSha256: tool.checksumEntry?.sha256,
      status,
      local,
      candidate,
      release,
      advisories,
    });
  }

  const advisories: string[] = [];
  if (unrelatedDiffs.length > 0) {
    advisories.push('candidate checksum output includes unrelated installer changes; investigate before updating checksums.yaml');
  }

  const summary = summarizeStatus(reports, unrelatedDiffs);

  return {
    ok: summary.fail === 0,
    generatedAt,
    mode: {
      network: options.network,
      candidateSource: options.network === 'skip'
        ? 'skipped'
        : options.candidateChecksums
          ? 'provided'
          : 'unavailable',
    },
    summary,
    checksums: {
      generatedAt: options.currentChecksums.generatedAt,
      installerCount: Object.keys(options.currentChecksums.installers).length,
    },
    tools: reports,
    checksumDiffs: {
      stack: stackDiffs,
      unrelated: unrelatedDiffs,
    },
    advisories,
  };
}

function readChecksumsFile(path: string): ChecksumsFile {
  return parseChecksumsYaml(readFileSync(path, 'utf8'));
}

function generateCandidateChecksums(root: string): { checksums?: ChecksumsFile; detail?: string } {
  const script = join(root, 'scripts/lib/security.sh');
  const result = spawnSync('bash', [script, '--update-checksums'], {
    cwd: root,
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  });

  if (result.status !== 0) {
    return {
      detail: result.stderr.trim() || result.stdout.trim() || `checksum updater exited with status ${result.status ?? 'unknown'}`,
    };
  }

  return {
    checksums: parseChecksumsYaml(result.stdout),
  };
}

interface CliOptions {
  root: string;
  manifestPath: string;
  checksumsPath: string;
  candidatePath?: string;
  githubFixturePath?: string;
  network: NetworkMode;
  json: boolean;
  quiet: boolean;
}

function parseArgs(args: string[]): CliOptions {
  const options: CliOptions = {
    root: DEFAULT_ROOT,
    manifestPath: join(DEFAULT_ROOT, 'acfs.manifest.yaml'),
    checksumsPath: join(DEFAULT_ROOT, 'checksums.yaml'),
    network: 'skip',
    json: false,
    quiet: false,
  };

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    switch (arg) {
      case '--json':
        options.json = true;
        break;
      case '--quiet':
        options.quiet = true;
        break;
      case '--network=skip':
        options.network = 'skip';
        break;
      case '--network=check':
        options.network = 'check';
        break;
      case '--root':
        i += 1;
        options.root = resolve(args[i] ?? '');
        options.manifestPath = join(options.root, 'acfs.manifest.yaml');
        options.checksumsPath = join(options.root, 'checksums.yaml');
        break;
      case '--manifest':
        i += 1;
        options.manifestPath = resolve(args[i] ?? '');
        break;
      case '--checksums':
        i += 1;
        options.checksumsPath = resolve(args[i] ?? '');
        break;
      case '--candidate-checksums':
        i += 1;
        options.candidatePath = resolve(args[i] ?? '');
        break;
      case '--github-fixture':
        i += 1;
        options.githubFixturePath = resolve(args[i] ?? '');
        break;
      case '--help':
      case '-h':
        printUsage();
        process.exit(0);
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return options;
}

function printUsage(): void {
  console.log(`Usage: scripts/stack-provenance-report.sh [--json] [--quiet] [--network=skip|check]

Reports local and upstream provenance for ACFS Agent Flywheel stack tools.

Options:
  --network=skip             Offline mode. Report local manifest/checksum consistency.
  --network=check            Fetch GitHub latest releases and checksum candidates.
  --candidate-checksums PATH Use a pre-generated checksum candidate instead of fetching.
  --github-fixture PATH      Use fixture release metadata keyed by owner/repo or repo name.
  --manifest PATH            Override acfs.manifest.yaml path.
  --checksums PATH           Override checksums.yaml path.
  --root PATH                Override repository root.
`);
}

function loadGitHubFixture(path: string | undefined): Record<string, GitHubReleaseFixture> | undefined {
  if (!path) return undefined;
  try {
    return asRecord(JSON.parse(readFileSync(path, 'utf8'))) as Record<string, GitHubReleaseFixture>;
  } catch (error) {
    throw new Error(`failed to read GitHub fixture ${path}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function printHumanReport(report: StackProvenanceReport, quiet: boolean): void {
  if (quiet) return;

  console.log('ACFS stack provenance report');
  console.log(`Mode: network=${report.mode.network} candidate=${report.mode.candidateSource}`);
  console.log(`Summary: pass=${report.summary.pass} warn=${report.summary.warn} unknown=${report.summary.unknown} skip=${report.summary.skip} fail=${report.summary.fail}`);
  console.log('');

  for (const tool of report.tools) {
    console.log(`[${tool.status.toUpperCase()}] ${tool.moduleId} (${tool.toolKey ?? 'no-checksum-key'}) - ${tool.repo ?? tool.sourceHref ?? 'unresolved-repository'}`);
    console.log(`  local: [${tool.local.status}] ${tool.local.detail}`);
    console.log(`  candidate: [${tool.candidate.status}] ${tool.candidate.detail}`);
    console.log(`  release: [${tool.release.status}] ${tool.release.detail}`);
    for (const advisory of tool.advisories) {
      console.log(`  advisory: ${advisory}`);
    }
  }

  if (report.checksumDiffs.unrelated.length > 0) {
    console.log('');
    console.log('Unrelated checksum diffs:');
    for (const diff of report.checksumDiffs.unrelated) {
      console.log(`  [FAIL] ${diff.tool}: ${diff.kind}`);
    }
  }

  for (const advisory of report.advisories) {
    console.log(`advisory: ${advisory}`);
  }
}

async function runCli(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));
  const manifestResult = parseManifestFile(options.manifestPath);
  if (!manifestResult.success || !manifestResult.data) {
    throw new Error(manifestResult.error?.message ?? 'failed to parse manifest');
  }
  // Reject invalid execution graphs before checksum generation or network I/O.
  assertManifestSemanticallyValid(manifestResult.data);

  let candidateChecksums = options.candidatePath ? readChecksumsFile(options.candidatePath) : undefined;
  let candidateGenerationDetail: string | undefined;
  if (options.network === 'check' && !candidateChecksums) {
    const generated = generateCandidateChecksums(options.root);
    candidateChecksums = generated.checksums;
    candidateGenerationDetail = generated.detail;
  }

  const report = await buildStackProvenanceReport({
    manifest: manifestResult.data,
    currentChecksums: readChecksumsFile(options.checksumsPath),
    candidateChecksums,
    githubReleases: loadGitHubFixture(options.githubFixturePath),
    network: options.network,
  });

  if (options.network === 'check' && candidateChecksums && report.mode.candidateSource === 'provided') {
    report.mode.candidateSource = options.candidatePath ? 'provided' : 'generated';
  }
  if (options.network === 'check' && !candidateChecksums && candidateGenerationDetail) {
    report.advisories.push(`checksum candidate unavailable: ${candidateGenerationDetail}`);
    report.summary.warn += 1;
  }

  if (options.json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    printHumanReport(report, options.quiet);
  }

  if (!report.ok) {
    process.exit(1);
  }
}

if (import.meta.main) {
  runCli().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(2);
  });
}
