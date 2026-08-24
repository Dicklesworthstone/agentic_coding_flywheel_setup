#!/usr/bin/env bun
/**
 * Safe local readiness audit for agent CLIs and CAAM account state.
 */

import { accessSync, constants, readFileSync, readdirSync, statSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

export type ReadinessStatus = 'pass' | 'warn' | 'fail' | 'unknown';

export interface PathStatResult {
  kind: 'missing' | 'file' | 'directory' | 'other' | 'unreadable';
  executable?: boolean;
  detail?: string;
}

export interface DirectoryEntryResult {
  name: string;
  kind: 'file' | 'directory' | 'other';
}

export interface ReadFileResult {
  kind: 'ok' | 'missing' | 'unreadable';
  content?: string;
  detail?: string;
}

export interface ReadDirResult {
  kind: 'ok' | 'missing' | 'unreadable';
  entries?: DirectoryEntryResult[];
  detail?: string;
}

export interface AgentReadinessFileSystem {
  stat(path: string): PathStatResult;
  readFile(path: string): ReadFileResult;
  readDir(path: string): ReadDirResult;
}

export interface CommandRunResult {
  status: number | null;
  stdout: string;
  stderr: string;
  error?: string;
}

export interface AgentReadinessCommandRunner {
  run(commandPath: string, args: string[], timeoutMs: number): CommandRunResult;
}

export interface CliCheckResult {
  status: ReadinessStatus;
  command: string;
  path?: string;
  aliases: Record<string, string | undefined>;
  version?: string;
  detail: string;
}

export interface ComponentResult {
  status: ReadinessStatus;
  detail: string;
  paths: string[];
}

export interface CaamProviderState {
  provider: 'claude' | 'codex' | 'agy';
  defaultProfile?: string;
  profileCount: number;
  vaultProfileCount: number;
  isolatedProfileCount: number;
  status: ReadinessStatus;
  detail: string;
}

export interface AgentToolReport {
  id: 'claude' | 'codex' | 'agy' | 'caam';
  displayName: string;
  status: ReadinessStatus;
  docsUrl: string;
  command: string;
  aliases: string[];
  cli: CliCheckResult;
  auth?: ComponentResult;
  config?: ComponentResult;
  caam?: {
    config: ComponentResult;
    profiles: ComponentResult;
    providers: CaamProviderState[];
  };
  nextActions: string[];
}

export interface AgentReadinessReport {
  ok: boolean;
  generatedAt: string;
  home: string;
  summary: Record<ReadinessStatus, number>;
  tools: AgentToolReport[];
  redaction: {
    secretValuesIncluded: false;
    note: string;
  };
}

export interface BuildAgentReadinessOptions {
  home: string;
  env?: Record<string, string | undefined>;
  pathEntries?: string[];
  acfsBinDir?: string;
  fileSystem?: AgentReadinessFileSystem;
  commandRunner?: AgentReadinessCommandRunner;
  collectVersions?: boolean;
  generatedAt?: string;
}

interface AuthFileCandidate {
  label: string;
  path: string;
  json: boolean;
  validateJson?: (value: unknown) => string | null;
}

interface ProviderDefinition {
  id: 'claude' | 'codex' | 'agy';
  displayName: string;
  command: string;
  aliases: string[];
  docsUrl: string;
  authFiles: (context: PathContext) => AuthFileCandidate[];
  configFiles: (context: PathContext) => AuthFileCandidate[];
  envCredentials: string[];
  nextActions: string[];
}

interface PathContext {
  home: string;
  env: Record<string, string | undefined>;
}

interface JsonProbe {
  status: ReadinessStatus;
  path: string;
  detail: string;
  exists: boolean;
}

interface ProfileInventory {
  profiles: Set<string>;
  status: ReadinessStatus;
  detail: string;
  roots: string[];
}

interface CliOptions {
  home: string;
  pathEntries?: string[];
  json: boolean;
  quiet: boolean;
  collectVersions: boolean;
}

const SCRIPT_FILE = fileURLToPath(import.meta.url);
const DEFAULT_ROOT = resolve(dirname(SCRIPT_FILE), '../../..');
const STATUS_RANK: Record<ReadinessStatus, number> = {
  pass: 0,
  warn: 1,
  unknown: 2,
  fail: 3,
};
const AGENT_PROVIDERS = ['claude', 'codex', 'agy'] as const;

function directoryEntryKind(entry: { isDirectory(): boolean; isFile(): boolean }): DirectoryEntryResult['kind'] {
  if (entry.isDirectory()) {
    return 'directory';
  }
  if (entry.isFile()) {
    return 'file';
  }
  return 'other';
}

class NodeReadinessFileSystem implements AgentReadinessFileSystem {
  stat(path: string): PathStatResult {
    try {
      const stat = statSync(path);
      let kind: PathStatResult['kind'] = 'other';
      if (stat.isFile()) {
        kind = 'file';
      } else if (stat.isDirectory()) {
        kind = 'directory';
      }
      let executable = false;
      if (kind === 'file') {
        try {
          accessSync(path, constants.X_OK);
          executable = true;
        } catch {
          executable = false;
        }
      }
      return { kind, executable };
    } catch (error) {
      return errorCode(error) === 'ENOENT'
        ? { kind: 'missing' }
        : { kind: 'unreadable', detail: errorMessage(error) };
    }
  }

  readFile(path: string): ReadFileResult {
    try {
      return { kind: 'ok', content: readFileSync(path, 'utf8') };
    } catch (error) {
      return errorCode(error) === 'ENOENT'
        ? { kind: 'missing' }
        : { kind: 'unreadable', detail: errorMessage(error) };
    }
  }

  readDir(path: string): ReadDirResult {
    try {
      const entries = readdirSync(path, { withFileTypes: true }).map((entry) => ({
        name: entry.name,
        kind: directoryEntryKind(entry),
      }));
      return { kind: 'ok', entries };
    } catch (error) {
      return errorCode(error) === 'ENOENT'
        ? { kind: 'missing' }
        : { kind: 'unreadable', detail: errorMessage(error) };
    }
  }
}

class SpawnCommandRunner implements AgentReadinessCommandRunner {
  run(commandPath: string, args: string[], timeoutMs: number): CommandRunResult {
    const result = spawnSync(commandPath, args, {
      encoding: 'utf8',
      timeout: timeoutMs,
      maxBuffer: 1024 * 1024,
    });
    return {
      status: result.status,
      stdout: result.stdout ?? '',
      stderr: result.stderr ?? '',
      error: result.error?.message,
    };
  }
}

function errorCode(error: unknown): string | undefined {
  return typeof error === 'object' && error !== null && 'code' in error
    ? String((error as { code?: unknown }).code)
    : undefined;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function statusMax(statuses: ReadinessStatus[]): ReadinessStatus {
  return statuses.reduce<ReadinessStatus>(
    (max, status) => (STATUS_RANK[status] > STATUS_RANK[max] ? status : max),
    'pass'
  );
}

function statusRank(status: ReadinessStatus): number {
  return STATUS_RANK[status];
}

function isStatus(status: ReadinessStatus, expected: ReadinessStatus): boolean {
  return statusRank(status) - statusRank(expected) === 0;
}

function unique(values: Array<string | undefined>): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    if (!value) continue;
    if (seen.has(value)) continue;
    seen.add(value);
    result.push(value);
  }
  return result;
}

function redactPath(path: string, home: string): string {
  const normalizedHome = resolve(home);
  const normalizedPath = resolve(path);
  if (normalizedPath === normalizedHome) return '$HOME';
  if (normalizedPath.startsWith(`${normalizedHome}/`)) {
    return `$HOME/${normalizedPath.slice(normalizedHome.length + 1)}`;
  }
  return normalizedPath;
}

function pathContext(home: string, env: Record<string, string | undefined>): PathContext {
  return { home: resolve(home), env };
}

function xdgConfigHome(context: PathContext): string {
  return context.env.XDG_CONFIG_HOME ? resolve(context.env.XDG_CONFIG_HOME) : join(context.home, '.config');
}

function xdgDataHome(context: PathContext): string {
  return context.env.XDG_DATA_HOME ? resolve(context.env.XDG_DATA_HOME) : join(context.home, '.local', 'share');
}

function credentialEnvPresent(env: Record<string, string | undefined>, names: string[]): string[] {
  return names.filter((name) => Boolean(env[name]?.trim()));
}

const ANTIGRAVITY_EXPECTED_SETTINGS: Record<string, string | boolean> = {
  model: 'Gemini 3.1 Pro (High)',
  toolPermission: 'always-proceed',
  artifactReviewPolicy: 'always-proceed',
  enableTelemetry: false,
  enableTerminalSandbox: false,
  allowNonWorkspaceAccess: true,
  notifications: false,
  showTips: false,
  showFeedbackSurvey: false,
  useG1Credits: false,
  verbosity: 'high',
  runningLightSpeed: 'medium',
  colorScheme: 'terminal',
  editor: 'auto',
  altScreenMode: 'never',
};

function isJsonObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function validateAntigravitySettings(value: unknown): string | null {
  if (!isJsonObject(value)) {
    return 'settings root must be a JSON object';
  }

  for (const [key, expected] of Object.entries(ANTIGRAVITY_EXPECTED_SETTINGS)) {
    if (value[key] !== expected) {
      return `missing ACFS-pinned ${key}=${JSON.stringify(expected)}`;
    }
  }

  return null;
}

function providerDefinitions(): ProviderDefinition[] {
  return [
    {
      id: 'claude',
      displayName: 'Claude Code',
      command: 'claude',
      aliases: ['cc'],
      docsUrl: 'https://code.claude.com/docs/en/authentication',
      authFiles: (context) => {
        const claudeConfigDir = context.env.CLAUDE_CONFIG_DIR
          ? resolve(context.env.CLAUDE_CONFIG_DIR)
          : join(xdgConfigHome(context), 'claude-code');
        return [
          { label: 'Claude OAuth credentials', path: join(context.home, '.claude', '.credentials.json'), json: true },
          { label: 'Claude Code auth file', path: join(claudeConfigDir, 'auth.json'), json: true },
        ];
      },
      configFiles: (context) => [
        { label: 'Claude session state', path: join(context.home, '.claude.json'), json: true },
        { label: 'Claude user settings', path: join(context.home, '.claude', 'settings.json'), json: true },
        { label: 'Claude config settings', path: join(xdgConfigHome(context), 'claude', 'settings.json'), json: true },
        { label: 'Claude Code config settings', path: join(xdgConfigHome(context), 'claude-code', 'settings.json'), json: true },
      ],
      envCredentials: ['ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'CLAUDE_CODE_OAUTH_TOKEN'],
      nextActions: [
        'Run `claude` and complete browser sign-in; use `/login` inside Claude Code to switch accounts.',
        'For headless environments, run `claude setup-token` and set `CLAUDE_CODE_OAUTH_TOKEN`.',
      ],
    },
    {
      id: 'codex',
      displayName: 'Codex CLI',
      command: 'codex',
      aliases: ['cod'],
      docsUrl: 'https://developers.openai.com/codex/cli',
      authFiles: (context) => {
        const codexHome = context.env.CODEX_HOME ? resolve(context.env.CODEX_HOME) : join(context.home, '.codex');
        return [
          { label: 'Codex auth file', path: join(codexHome, 'auth.json'), json: true },
        ];
      },
      configFiles: (context) => {
        const codexHome = context.env.CODEX_HOME ? resolve(context.env.CODEX_HOME) : join(context.home, '.codex');
        return [
          { label: 'Codex auth file', path: join(codexHome, 'auth.json'), json: true },
        ];
      },
      envCredentials: ['OPENAI_API_KEY'],
      nextActions: [
        'Run `codex` and complete the first-run sign-in prompt with a ChatGPT account or API key.',
        'Upgrade with `bun install -g @openai/codex@latest` if the installed CLI is stale.',
      ],
    },
    {
      id: 'agy',
      displayName: 'Antigravity CLI',
      command: 'agy',
      aliases: ['agy-locked', 'gmi'],
      docsUrl: 'https://github.com/google-antigravity/antigravity-cli',
      authFiles: (context) => {
        const antigravityHome = context.env.ANTIGRAVITY_HOME
          ? resolve(context.env.ANTIGRAVITY_HOME)
          : join(context.home, '.gemini', 'antigravity-cli');
        return [
          { label: 'Antigravity OAuth token', path: join(antigravityHome, 'antigravity-oauth-token'), json: false },
        ];
      },
      configFiles: (context) => {
        const antigravityHome = context.env.ANTIGRAVITY_HOME
          ? resolve(context.env.ANTIGRAVITY_HOME)
          : join(context.home, '.gemini', 'antigravity-cli');
        return [
          {
            label: 'Antigravity settings',
            path: join(antigravityHome, 'settings.json'),
            json: true,
            validateJson: validateAntigravitySettings,
          },
        ];
      },
      envCredentials: [],
      nextActions: [
        'Run `agy-locked --acfs-prime-settings` to restore ACFS-pinned settings and the DCG hook.',
        'Run `agy` and complete Google authentication.',
        'Use the Google account tied to eligible Gemini access for Antigravity.',
      ],
    },
  ];
}

function executableSearchDirs(home: string, options: BuildAgentReadinessOptions): string[] {
  return unique([
    ...managedExecutableDirs(home, options),
    ...pathSearchDirs(options),
  ]).map(resolveLookupRoot);
}

function managedExecutableDirs(home: string, options: BuildAgentReadinessOptions): string[] {
  const env = options.env ?? process.env;
  return unique([
    options.acfsBinDir,
    env.ACFS_BIN_DIR,
    join(home, '.local', 'bin'),
    join(home, '.bun', 'bin'),
    join(home, '.cargo', 'bin'),
  ]);
}

function pathSearchDirs(options: BuildAgentReadinessOptions): string[] {
  const env = options.env ?? process.env;
  return options.pathEntries ?? (env.PATH ?? '').split(':').filter(Boolean);
}

function resolveLookupRoot(path: string): string {
  return resolve(path);
}

function findExecutable(
  command: string,
  aliases: string[],
  options: BuildAgentReadinessOptions,
  fs: AgentReadinessFileSystem
): CliCheckResult {
  const dirs = executableSearchDirs(options.home, options);
  const aliasDirs = managedExecutableDirs(options.home, options).map(resolveLookupRoot);
  const aliasesFound: Record<string, string | undefined> = {};
  let commandPath: string | undefined;

  for (const candidate of [command, ...aliases]) {
    const searchDirs = candidate === command ? dirs : aliasDirs;
    for (const dir of searchDirs) {
      const path = join(dir, candidate);
      const stat = fs.stat(path);
      if (stat.kind === 'file' && stat.executable) {
        if (candidate === command && !commandPath) {
          commandPath = path;
        } else if (candidate !== command && !aliasesFound[candidate]) {
          aliasesFound[candidate] = path;
        }
        break;
      }
    }
  }

  if (!commandPath) {
    return {
      status: 'fail',
      command,
      aliases: aliasesFound,
      detail: `${command} was not found in ACFS or PATH bin directories`,
    };
  }

  return {
    status: 'pass',
    command,
    path: commandPath,
    aliases: aliasesFound,
    detail: `${command} is executable at ${commandPath}`,
  };
}

function attachVersion(
  cli: CliCheckResult,
  runner: AgentReadinessCommandRunner,
  collectVersions: boolean
): CliCheckResult {
  if (!collectVersions || !cli.path) return cli;
  const result = runner.run(cli.path, ['--version'], 4000);
  if (result.status === 0) {
    const version = firstOutputLine(result.stdout || result.stderr);
    return {
      ...cli,
      version,
      detail: version ? `${cli.detail}; version: ${version}` : `${cli.detail}; version command returned no output`,
    };
  }
  return {
    ...cli,
    detail: `${cli.detail}; version unavailable${result.error ? `: ${result.error}` : ''}`,
  };
}

function firstOutputLine(output: string): string | undefined {
  const line = output.split(/\r?\n/).map((part) => part.trim()).find(Boolean);
  return line ? line.slice(0, 160) : undefined;
}

function parseJsonProbe(candidate: AuthFileCandidate, fs: AgentReadinessFileSystem, home: string): JsonProbe {
  const read = fs.readFile(candidate.path);
  if (read.kind === 'missing') {
    return {
      status: 'warn',
      path: candidate.path,
      detail: `${candidate.label} is missing at ${redactPath(candidate.path, home)}`,
      exists: false,
    };
  }
  if (read.kind === 'unreadable') {
    return {
      status: 'unknown',
      path: candidate.path,
      detail: `${candidate.label} could not be read at ${redactPath(candidate.path, home)}: ${read.detail ?? 'permission denied'}`,
      exists: true,
    };
  }
  if (candidate.json) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(read.content ?? '');
    } catch {
      // Never include the parser's message: for auth files it can quote the
      // offending token ("Unexpected identifier \"sk\"..."), which would put a
      // credential fragment into the audit output.
      return {
        status: 'fail',
        path: candidate.path,
        detail: `${candidate.label} is malformed JSON at ${redactPath(candidate.path, home)} (parser message withheld for an auth file)`,
        exists: true,
      };
    }
    const validationError = candidate.validateJson?.(parsed);
    if (validationError) {
      return {
        status: 'fail',
        path: candidate.path,
        detail: `${candidate.label} failed validation at ${redactPath(candidate.path, home)}: ${validationError}`,
        exists: true,
      };
    }
  } else if (!(read.content ?? '').trim()) {
    return {
      status: 'warn',
      path: candidate.path,
      detail: `${candidate.label} is empty at ${redactPath(candidate.path, home)}`,
      exists: true,
    };
  }
  return {
    status: 'pass',
    path: candidate.path,
    detail: `${candidate.label} is present and parseable at ${redactPath(candidate.path, home)}`,
    exists: true,
  };
}

function evaluateAuth(
  definition: ProviderDefinition,
  context: PathContext,
  fs: AgentReadinessFileSystem
): ComponentResult {
  const envCreds = credentialEnvPresent(context.env, definition.envCredentials);
  const probes = definition.authFiles(context).map((candidate) => parseJsonProbe(candidate, fs, context.home));
  const presentProbe = probes.find((probe) => isStatus(probe.status, 'pass'));
  const failedProbe = probes.find((probe) => isStatus(probe.status, 'fail'));
  const unreadableProbe = probes.find((probe) => isStatus(probe.status, 'unknown'));
  const paths = probes.map((probe) => probe.path);

  if (failedProbe) {
    return {
      status: 'fail',
      detail: failedProbe.detail,
      paths,
    };
  }
  if (envCreds.length > 0) {
    return {
      status: 'pass',
      detail: `credential environment variable is set (${envCreds.join(', ')}); value not inspected`,
      paths,
    };
  }
  if (presentProbe) {
    return {
      status: 'pass',
      detail: presentProbe.detail,
      paths,
    };
  }
  if (unreadableProbe) {
    return {
      status: 'unknown',
      detail: unreadableProbe.detail,
      paths,
    };
  }
  return {
    status: 'warn',
    detail: `no ${definition.displayName} auth artifact was found`,
    paths,
  };
}

function evaluateConfig(
  definition: ProviderDefinition,
  context: PathContext,
  fs: AgentReadinessFileSystem
): ComponentResult {
  const probes = definition.configFiles(context).map((candidate) => parseJsonProbe(candidate, fs, context.home));
  const failedProbe = probes.find((probe) => isStatus(probe.status, 'fail'));
  const unreadableProbe = probes.find((probe) => isStatus(probe.status, 'unknown'));
  const presentCount = probes.filter((probe) => probe.exists && isStatus(probe.status, 'pass')).length;

  if (failedProbe) {
    return {
      status: 'fail',
      detail: failedProbe.detail,
      paths: probes.map((probe) => probe.path),
    };
  }
  if (unreadableProbe) {
    return {
      status: 'unknown',
      detail: unreadableProbe.detail,
      paths: probes.map((probe) => probe.path),
    };
  }
  return {
    status: 'pass',
    detail: presentCount > 0
      ? `${presentCount} config/auth JSON file(s) are parseable`
      : 'no malformed JSON config files detected',
    paths: probes.map((probe) => probe.path),
  };
}

function evaluateProvider(
  definition: ProviderDefinition,
  context: PathContext,
  options: BuildAgentReadinessOptions,
  fs: AgentReadinessFileSystem,
  runner: AgentReadinessCommandRunner
): AgentToolReport {
  const cli = attachVersion(
    findExecutable(definition.command, definition.aliases, options, fs),
    runner,
    options.collectVersions ?? true
  );
  const auth = evaluateAuth(definition, context, fs);
  const config = evaluateConfig(definition, context, fs);
  const status = statusMax([cli.status, auth.status, config.status]);
  const nextActions = isStatus(status, 'pass') ? [] : definition.nextActions;

  return {
    id: definition.id,
    displayName: definition.displayName,
    status,
    docsUrl: definition.docsUrl,
    command: definition.command,
    aliases: definition.aliases,
    cli,
    auth,
    config,
    nextActions,
  };
}

function caamConfigPath(context: PathContext): string {
  return join(xdgConfigHome(context), 'caam', 'config.json');
}

function caamProfileStorePath(context: PathContext): string {
  if (context.env.CAAM_HOME) return join(resolve(context.env.CAAM_HOME), 'data', 'profiles');
  return join(xdgDataHome(context), 'caam', 'profiles');
}

function caamVaultPath(context: PathContext): string {
  if (context.env.CAAM_HOME) return join(resolve(context.env.CAAM_HOME), 'data', 'vault');
  return join(xdgDataHome(context), 'caam', 'vault');
}

function listProfiles(
  root: string,
  provider: string,
  metadataFile: string,
  fs: AgentReadinessFileSystem,
  home: string
): ProfileInventory {
  const providerDir = join(root, provider);
  const dir = fs.readDir(providerDir);
  if (dir.kind === 'missing') {
    return {
      profiles: new Set<string>(),
      status: 'pass',
      detail: `${redactPath(providerDir, home)} has no profiles`,
      roots: [providerDir],
    };
  }
  if (dir.kind === 'unreadable') {
    return {
      profiles: new Set<string>(),
      status: 'unknown',
      detail: `could not list ${redactPath(providerDir, home)}: ${dir.detail ?? 'permission denied'}`,
      roots: [providerDir],
    };
  }

  const profiles = new Set<string>();
  const failures: string[] = [];
  const unknowns: string[] = [];
  for (const entry of dir.entries ?? []) {
    if (entry.kind !== 'directory') continue;
    const profileName = entry.name;
    if (!isSafeCaamSegment(profileName)) {
      failures.push(`${profileName}: unsafe profile directory name`);
      continue;
    }
    profiles.add(profileName);
    const metaPath = caamProfileMetadataPath(providerDir, profileName, metadataFile);
    const meta = fs.stat(metaPath);
    if (meta.kind === 'missing') continue;
    const read = fs.readFile(metaPath);
    if (read.kind === 'unreadable') {
      unknowns.push(`${profileName}: ${read.detail ?? 'unreadable metadata'}`);
      continue;
    }
    if (read.kind === 'ok') {
      try {
        JSON.parse(read.content ?? '');
      } catch (error) {
        failures.push(`${profileName}: ${errorMessage(error)}`);
      }
    }
  }

  if (failures.length > 0) {
    return {
      profiles,
      status: 'fail',
      detail: `malformed ${metadataFile} in ${redactPath(providerDir, home)} (${failures.join('; ')})`,
      roots: [providerDir],
    };
  }
  if (unknowns.length > 0) {
    return {
      profiles,
      status: 'unknown',
      detail: `metadata unreadable in ${redactPath(providerDir, home)} (${unknowns.join('; ')})`,
      roots: [providerDir],
    };
  }

  return {
    profiles,
    status: 'pass',
    detail: `${profiles.size} profile(s) listed under ${redactPath(providerDir, home)}`,
    roots: [providerDir],
  };
}

function parseDefaultProfiles(config: ComponentResult, configPath: string, fs: AgentReadinessFileSystem): Record<string, string> {
  if (!isStatus(config.status, 'pass')) return {};
  const read = fs.readFile(configPath);
  if (read.kind !== 'ok') return {};
  let parsed: { default_profiles?: unknown };
  try {
    parsed = JSON.parse(read.content ?? '{}') as { default_profiles?: unknown };
  } catch {
    return {};
  }
  const defaults = parsed.default_profiles;
  if (defaults === null || typeof defaults !== 'object' || Array.isArray(defaults)) return {};

  const result: Record<string, string> = {};
  for (const [provider, value] of Object.entries(defaults)) {
    if (typeof value === 'string' && value.trim()) {
      result[provider] = value.trim();
    }
  }
  return result;
}

function evaluateCaamConfig(context: PathContext, fs: AgentReadinessFileSystem): ComponentResult {
  const configPath = caamConfigPath(context);
  const probe = parseJsonProbe({ label: 'CAAM config', path: configPath, json: true }, fs, context.home);
  if (isStatus(probe.status, 'pass')) {
    return {
      status: 'pass',
      detail: `CAAM config is parseable at ${redactPath(configPath, context.home)}`,
      paths: [configPath],
    };
  }
  if (isStatus(probe.status, 'warn')) {
    return {
      status: 'warn',
      detail: `CAAM config is missing at ${redactPath(configPath, context.home)}; defaults are not configured`,
      paths: [configPath],
    };
  }
  return {
    status: probe.status,
    detail: probe.detail,
    paths: [configPath],
  };
}

function unionProfiles(a: Set<string>, b: Set<string>): Set<string> {
  return new Set([...a, ...b]);
}

function isSafeCaamSegment(name: string): boolean {
  return name.trim() !== '' && name !== '.' && name !== '..' && !name.includes('/') && !name.includes('\\') && !name.includes('\0');
}

function caamProfileMetadataPath(providerDir: string, profileName: string, metadataFile: string): string {
  const safeProfileName = basename(profileName);
  const safeMetadataFile = basename(metadataFile);
  const profileDir = resolve(providerDir, safeProfileName);
  const metadataPath = resolve(profileDir, safeMetadataFile);
  const containment = relative(profileDir, metadataPath);
  if (containment === '' || containment.startsWith('..') || isAbsolute(containment)) {
    return resolve(providerDir, '__invalid_profile__', '__invalid_metadata__');
  }
  return metadataPath;
}

function evaluateCaamProviders(
  context: PathContext,
  fs: AgentReadinessFileSystem,
  config: ComponentResult
): { profiles: ComponentResult; providers: CaamProviderState[] } {
  const defaults = parseDefaultProfiles(config, caamConfigPath(context), fs);
  const storeRoot = caamProfileStorePath(context);
  const vaultRoot = caamVaultPath(context);
  const providers: CaamProviderState[] = [];
  const componentStatuses: ReadinessStatus[] = [];
  const details: string[] = [];
  const paths = [storeRoot, vaultRoot];

  for (const provider of AGENT_PROVIDERS) {
    const isolated = listProfiles(storeRoot, provider, 'profile.json', fs, context.home);
    const vault = listProfiles(vaultRoot, provider, 'meta.json', fs, context.home);
    const profiles = unionProfiles(isolated.profiles, vault.profiles);
    const defaultProfile = defaults[provider];
    let status = statusMax([isolated.status, vault.status]);
    let detail = `${profiles.size} total profile(s)`;

    if (defaultProfile && !profiles.has(defaultProfile)) {
      status = 'fail';
      detail = `default profile '${defaultProfile}' is stale for ${provider}; no matching profile exists in CAAM profile store or vault`;
    } else if (defaultProfile) {
      detail = `default profile '${defaultProfile}' exists for ${provider}`;
    } else if (profiles.size === 0) {
      status = statusMax([status, 'warn']);
      detail = `no CAAM profile is stored for ${provider}`;
    } else {
      status = statusMax([status, 'warn']);
      detail = `${profiles.size} profile(s) exist for ${provider}, but no default is configured`;
    }

    providers.push({
      provider,
      defaultProfile,
      profileCount: profiles.size,
      vaultProfileCount: vault.profiles.size,
      isolatedProfileCount: isolated.profiles.size,
      status,
      detail,
    });
    componentStatuses.push(status, isolated.status, vault.status);
    details.push(`${provider}: ${detail}`);
    if (!isStatus(isolated.status, 'pass')) details.push(`${provider} isolated profiles: ${isolated.detail}`);
    if (!isStatus(vault.status, 'pass')) details.push(`${provider} vault profiles: ${vault.detail}`);
  }

  return {
    providers,
    profiles: {
      status: statusMax(componentStatuses),
      detail: details.join('; '),
      paths,
    },
  };
}

function evaluateCaam(
  context: PathContext,
  options: BuildAgentReadinessOptions,
  fs: AgentReadinessFileSystem,
  runner: AgentReadinessCommandRunner
): AgentToolReport {
  const cli = attachVersion(
    findExecutable('caam', [], options, fs),
    runner,
    options.collectVersions ?? true
  );
  const config = evaluateCaamConfig(context, fs);
  const { profiles, providers } = evaluateCaamProviders(context, fs, config);
  const status = statusMax([cli.status, config.status, profiles.status]);
  const nextActions = isStatus(status, 'pass')
    ? []
    : [
        'Run `caam profile ls <provider>` and `caam ls <provider>` to inspect stored profiles.',
        'Run `caam use <provider> <profile>` to repair stale or missing defaults.',
      ];

  return {
    id: 'caam',
    displayName: 'Coding Agent Account Manager',
    status,
    docsUrl: 'https://github.com/Dicklesworthstone/coding_agent_account_manager',
    command: 'caam',
    aliases: [],
    cli,
    caam: {
      config,
      profiles,
      providers,
    },
    nextActions,
  };
}

function summarize(tools: AgentToolReport[]): Record<ReadinessStatus, number> {
  const summary: Record<ReadinessStatus, number> = {
    pass: 0,
    warn: 0,
    fail: 0,
    unknown: 0,
  };
  for (const tool of tools) {
    summary[tool.status] += 1;
  }
  return summary;
}

export function buildAgentReadinessReport(options: BuildAgentReadinessOptions): AgentReadinessReport {
  const home = resolve(options.home);
  const env = options.env ?? process.env;
  const context = pathContext(home, env);
  const fs = options.fileSystem ?? new NodeReadinessFileSystem();
  const runner = options.commandRunner ?? new SpawnCommandRunner();
  const providerReports = providerDefinitions().map((definition) =>
    evaluateProvider(definition, context, { ...options, home }, fs, runner)
  );
  const caam = evaluateCaam(context, { ...options, home }, fs, runner);
  const tools = [...providerReports, caam];
  const summary = summarize(tools);

  return {
    ok: summary.fail === 0,
    generatedAt: options.generatedAt ?? new Date().toISOString(),
    home,
    summary,
    tools,
    redaction: {
      secretValuesIncluded: false,
      note: 'The audit reports file existence, parseability, and environment variable names only; secret values and file contents are never included.',
    },
  };
}

function parseArgs(args: string[]): CliOptions {
  const options: CliOptions = {
    home: process.env.HOME ? resolve(process.env.HOME) : process.cwd(),
    json: false,
    quiet: false,
    collectVersions: true,
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
      case '--no-version':
        options.collectVersions = false;
        break;
      case '--home':
        i += 1;
        options.home = resolve(args[i] ?? '');
        break;
      case '--path':
        i += 1;
        options.pathEntries = (args[i] ?? '').split(':').filter(Boolean);
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
  console.log(`Usage: scripts/agent-readiness-audit.sh [--json] [--quiet] [--no-version] [--home PATH] [--path PATH]

Audits Claude Code, Codex CLI, Antigravity CLI, and CAAM account readiness without
printing token values or auth file contents.

Options:
  --json        Emit machine-readable JSON.
  --quiet       Suppress human output.
  --no-version  Skip CLI --version probes.
  --home PATH   Audit a specific home directory.
  --path PATH   Override executable search PATH entries.
  --help, -h    Show this help.`);
}

function printHumanReport(report: AgentReadinessReport, quiet: boolean): void {
  if (quiet) return;
  console.log('ACFS agent readiness audit');
  console.log(`Home: ${report.home}`);
  console.log(`Summary: pass=${report.summary.pass} warn=${report.summary.warn} unknown=${report.summary.unknown} fail=${report.summary.fail}`);
  console.log('');

  for (const tool of report.tools) {
    console.log(`[${tool.status.toUpperCase()}] ${tool.displayName} (${tool.command})`);
    console.log(`  cli: [${tool.cli.status}] ${tool.cli.detail}`);
    if (tool.auth) {
      console.log(`  auth: [${tool.auth.status}] ${tool.auth.detail}`);
    }
    if (tool.config) {
      console.log(`  config: [${tool.config.status}] ${tool.config.detail}`);
    }
    if (tool.caam) {
      console.log(`  config: [${tool.caam.config.status}] ${tool.caam.config.detail}`);
      console.log(`  profiles: [${tool.caam.profiles.status}] ${tool.caam.profiles.detail}`);
    }
    for (const action of tool.nextActions) {
      console.log(`  next: ${action}`);
    }
    console.log(`  docs: ${tool.docsUrl}`);
  }
}

async function runCli(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));
  const report = buildAgentReadinessReport({
    home: options.home,
    pathEntries: options.pathEntries,
    env: process.env,
    collectVersions: options.collectVersions,
    acfsBinDir: process.env.ACFS_BIN_DIR ?? join(DEFAULT_ROOT, 'bin'),
  });

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
    console.error(errorMessage(error));
    process.exit(2);
  });
}
