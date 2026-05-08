import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  buildAgentReadinessReport,
  type AgentReadinessReport,
  type AgentReadinessCommandRunner,
  type AgentReadinessFileSystem,
  type CommandRunResult,
  type DirectoryEntryResult,
  type PathStatResult,
  type ReadDirResult,
  type ReadFileResult,
} from './agent-readiness-audit.js';

type FixtureEntry =
  | { kind: 'file'; content?: string; executable?: boolean; readable?: boolean }
  | { kind: 'directory'; readable?: boolean };

const HOME = '/home/test';
const PATH = '/bin';
const REDACTION_SAMPLE = ['opaque', 'credential', 'sample'].join('-');
const PROVIDERS = ['claude', 'codex', 'gemini'] as const;
const AUDIT_SCRIPT = join(dirname(fileURLToPath(import.meta.url)), 'agent-readiness-audit.ts');

class FixtureFileSystem implements AgentReadinessFileSystem {
  private readonly entries: Map<string, FixtureEntry>;

  constructor(entries: Record<string, FixtureEntry>) {
    this.entries = new Map(
      Object.entries(entries).map(([path, entry]) => [resolve(path), entry])
    );
  }

  stat(path: string): PathStatResult {
    const key = resolve(path);
    const entry = this.entries.get(key);
    if (entry?.kind === 'file') {
      if (entry.readable === false) {
        return { kind: 'unreadable', detail: 'permission denied' };
      }
      return { kind: 'file', executable: Boolean(entry.executable) };
    }
    if (entry?.kind === 'directory') {
      if (entry.readable === false) {
        return { kind: 'unreadable', detail: 'permission denied' };
      }
      return { kind: 'directory' };
    }
    return this.hasChildren(key) ? { kind: 'directory' } : { kind: 'missing' };
  }

  readFile(path: string): ReadFileResult {
    const key = resolve(path);
    const entry = this.entries.get(key);
    if (!entry) return { kind: 'missing' };
    if (entry.kind !== 'file' || entry.readable === false) {
      return { kind: 'unreadable', detail: 'permission denied' };
    }
    return { kind: 'ok', content: entry.content ?? '' };
  }

  readDir(path: string): ReadDirResult {
    const key = resolve(path);
    const entry = this.entries.get(key);
    if (entry?.kind === 'file') {
      return { kind: 'unreadable', detail: 'not a directory' };
    }
    if (entry?.kind === 'directory' && entry.readable === false) {
      return { kind: 'unreadable', detail: 'permission denied' };
    }

    const children = new Map<string, DirectoryEntryResult>();
    const prefix = `${key}/`;
    for (const [entryPath, child] of this.entries) {
      if (!entryPath.startsWith(prefix)) continue;
      const rest = entryPath.slice(prefix.length);
      const [name] = rest.split('/');
      if (!name) continue;
      const directPath = `${prefix}${name}`;
      const directEntry = this.entries.get(directPath);
      const kind = directEntry?.kind === 'file'
        ? 'file'
        : directEntry?.kind === 'directory' || entryPath !== directPath
          ? 'directory'
          : child.kind === 'file'
            ? 'file'
            : 'directory';
      children.set(name, { name, kind });
    }

    if (!entry && children.size === 0) return { kind: 'missing' };
    return {
      kind: 'ok',
      entries: Array.from(children.values()).sort((a, b) => a.name.localeCompare(b.name)),
    };
  }

  private hasChildren(path: string): boolean {
    const prefix = `${path}/`;
    for (const entryPath of this.entries.keys()) {
      if (entryPath.startsWith(prefix)) return true;
    }
    return false;
  }
}

class FixtureCommandRunner implements AgentReadinessCommandRunner {
  run(commandPath: string): CommandRunResult {
    return {
      status: 0,
      stdout: `${commandPath.split('/').at(-1)} 1.2.3\n`,
      stderr: '',
    };
  }
}

function executable(path: string): FixtureEntry {
  return { kind: 'file', executable: true, content: '#!/usr/bin/env bash\n' };
}

function jsonFile(value: unknown): FixtureEntry {
  return { kind: 'file', content: JSON.stringify(value) };
}

function profile(provider: string, name: string): Record<string, FixtureEntry> {
  return {
    [`${HOME}/.local/share/caam/profiles/${provider}/${name}/profile.json`]: jsonFile({
      name,
      provider,
      auth_mode: 'oauth',
    }),
  };
}

function baseEntries(): Record<string, FixtureEntry> {
  return {
    '/bin/claude': executable('/bin/claude'),
    '/bin/codex': executable('/bin/codex'),
    '/bin/gemini': executable('/bin/gemini'),
    '/bin/caam': executable('/bin/caam'),
    [`${HOME}/.claude/.credentials.json`]: jsonFile({ claudeAiOauth: { accessToken: REDACTION_SAMPLE } }),
    [`${HOME}/.codex/auth.json`]: jsonFile({ tokens: { access_token: REDACTION_SAMPLE } }),
    [`${HOME}/.gemini/settings.json`]: jsonFile({ selectedAuthType: 'oauth-personal' }),
    [`${HOME}/.gemini/oauth_creds.json`]: jsonFile({ access_token: REDACTION_SAMPLE }),
    [`${HOME}/.config/caam/config.json`]: jsonFile({
      default_profiles: {
        claude: 'work',
        codex: 'work',
        gemini: 'work',
      },
    }),
    ...profile('claude', 'work'),
    ...profile('codex', 'work'),
    ...profile('gemini', 'work'),
  };
}

function reportFor(entries: Record<string, FixtureEntry>) {
  return buildAgentReadinessReport({
    home: HOME,
    env: {
      HOME,
      PATH,
    },
    pathEntries: [PATH],
    fileSystem: new FixtureFileSystem(entries),
    commandRunner: new FixtureCommandRunner(),
    generatedAt: '2026-01-01T00:00:00Z',
  });
}

function writeRealFile(path: string, content: string, executableFile = false): void {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
  if (executableFile) {
    chmodSync(path, 0o755);
  }
}

function createCliFixture() {
  const root = mkdtempSync(join(tmpdir(), 'acfs-agent-readiness-'));
  const home = join(root, 'home');
  const bin = join(root, 'bin');
  const secret = `${REDACTION_SAMPLE}-cli`;

  mkdirSync(home, { recursive: true });
  mkdirSync(bin, { recursive: true });
  for (const command of ['claude', 'codex', 'gemini', 'caam']) {
    writeRealFile(join(bin, command), `#!/usr/bin/env bash\nprintf '%s 1.2.3\\n' '${command}'\n`, true);
  }

  writeRealFile(join(home, '.claude', '.credentials.json'), JSON.stringify({
    claudeAiOauth: { accessToken: secret },
  }));
  writeRealFile(join(home, '.codex', 'auth.json'), JSON.stringify({
    tokens: { access_token: secret },
  }));
  writeRealFile(join(home, '.gemini', 'settings.json'), JSON.stringify({
    selectedAuthType: 'oauth-personal',
  }));
  writeRealFile(join(home, '.gemini', 'oauth_creds.json'), JSON.stringify({
    access_token: secret,
  }));
  writeRealFile(join(home, '.config', 'caam', 'config.json'), JSON.stringify({
    default_profiles: {
      claude: 'work',
      codex: 'work',
      gemini: 'work',
    },
  }));
  for (const provider of PROVIDERS) {
    writeRealFile(
      join(home, '.local', 'share', 'caam', 'profiles', provider, 'work', 'profile.json'),
      JSON.stringify({ name: 'work', provider, auth_mode: 'oauth', token: secret })
    );
  }

  return { root, home, bin, secret };
}

function runAuditCli(
  fixture: ReturnType<typeof createCliFixture>,
  args: string[],
  env: Record<string, string | undefined> = {}
) {
  return spawnSync(process.execPath, [
    AUDIT_SCRIPT,
    ...args,
    '--home',
    fixture.home,
    '--path',
    fixture.bin,
  ], {
    encoding: 'utf8',
    env: {
      HOME: fixture.home,
      PATH: fixture.bin,
      ...env,
    },
  });
}

function parseCliJsonReport(stdout: string): AgentReadinessReport {
  try {
    return JSON.parse(stdout) as AgentReadinessReport;
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`agent readiness CLI emitted invalid JSON: ${detail}`);
  }
}

describe('agent readiness audit', () => {
  test('passes authenticated fixture without leaking secret values', () => {
    const report = reportFor(baseEntries());

    expect(report.ok).toBe(true);
    expect(report.summary.fail).toBe(0);
    const toolsById = Object.fromEntries(report.tools.map((tool) => [tool.id, tool]));
    for (const provider of PROVIDERS) {
      const tool = toolsById[provider];
      expect(tool?.status).toBe('pass');
      expect(tool?.auth?.status).toBe('pass');
    }
    expect(report.tools.find((item) => item.id === 'caam')?.status).toBe('pass');
    expect(JSON.stringify(report)).not.toContain(REDACTION_SAMPLE);
  });

  test('CLI JSON and human output preserve readiness states without leaking secrets', () => {
    const fixture = createCliFixture();
    const envSecret = `${fixture.secret}-env`;

    const jsonRun = runAuditCli(fixture, ['--json', '--no-version'], {
      OPENAI_API_KEY: envSecret,
    });

    expect(jsonRun.status).toBe(0);
    const report = parseCliJsonReport(jsonRun.stdout);
    expect(report.ok).toBe(true);
    expect(report.summary).toEqual({ pass: 4, warn: 0, fail: 0, unknown: 0 });
    expect(report.tools.map((tool) => [tool.id, tool.status])).toEqual([
      ['claude', 'pass'],
      ['codex', 'pass'],
      ['gemini', 'pass'],
      ['caam', 'pass'],
    ]);
    expect(jsonRun.stdout).not.toContain(fixture.secret);
    expect(jsonRun.stdout).not.toContain(envSecret);

    const humanRun = runAuditCli(fixture, ['--no-version'], {
      OPENAI_API_KEY: envSecret,
    });

    expect(humanRun.status).toBe(0);
    expect(humanRun.stdout).toContain('ACFS agent readiness audit');
    expect(humanRun.stdout).toContain('Summary: pass=4 warn=0 unknown=0 fail=0');
    expect(humanRun.stdout).toContain('[PASS] Claude Code (claude)');
    expect(humanRun.stdout).toContain('[PASS] Codex CLI (codex)');
    expect(humanRun.stdout).toContain('[PASS] Gemini CLI (gemini)');
    expect(humanRun.stdout).toContain('[PASS] Coding Agent Account Manager (caam)');
    expect(humanRun.stdout).not.toContain(fixture.secret);
    expect(humanRun.stdout).not.toContain(envSecret);
    expect(fixture.root).toContain('acfs-agent-readiness-');
  });

  test('warns when a CLI is present but auth is missing', () => {
    const entries = baseEntries();
    delete entries[`${HOME}/.codex/auth.json`];

    const report = reportFor(entries);
    const codex = report.tools.find((item) => item.id === 'codex');

    expect(report.ok).toBe(true);
    expect(codex?.status).toBe('warn');
    expect(codex?.auth?.status).toBe('warn');
    expect(codex?.nextActions.join('\n')).toContain('codex');
  });

  test('fails malformed auth or config JSON', () => {
    const entries = baseEntries();
    entries[`${HOME}/.codex/auth.json`] = { kind: 'file', content: '{not-json' };

    const report = reportFor(entries);
    const codex = report.tools.find((item) => item.id === 'codex');

    expect(report.ok).toBe(false);
    expect(codex?.status).toBe('fail');
    expect(codex?.auth?.detail).toContain('malformed JSON');
  });

  test('fails when an agent CLI is missing', () => {
    const entries = baseEntries();
    delete entries['/bin/gemini'];

    const report = reportFor(entries);
    const gemini = report.tools.find((item) => item.id === 'gemini');

    expect(report.ok).toBe(false);
    expect(gemini?.cli.status).toBe('fail');
    expect(gemini?.cli.detail).toContain('gemini was not found');
  });

  test('does not treat system binaries as ACFS command aliases', () => {
    const entries = {
      ...baseEntries(),
      '/usr/bin/cc': executable('/usr/bin/cc'),
    };
    const report = buildAgentReadinessReport({
      home: HOME,
      env: {
        HOME,
        PATH: '/usr/bin:/bin',
      },
      pathEntries: ['/usr/bin', '/bin'],
      fileSystem: new FixtureFileSystem(entries),
      commandRunner: new FixtureCommandRunner(),
      generatedAt: '2026-01-01T00:00:00Z',
    });
    const claude = report.tools.find((item) => item.id === 'claude');

    expect(claude?.cli.status).toBe('pass');
    expect(claude?.cli.aliases.cc).toBeUndefined();
  });

  test('fails stale CAAM defaults that point to absent profiles', () => {
    const entries = baseEntries();
    entries[`${HOME}/.config/caam/config.json`] = jsonFile({
      default_profiles: {
        claude: 'work',
        codex: 'missing-profile',
        gemini: 'work',
      },
    });

    const report = reportFor(entries);
    const caam = report.tools.find((item) => item.id === 'caam');
    const codexState = caam?.caam?.providers.find((provider) => provider.provider === 'codex');

    expect(report.ok).toBe(false);
    expect(caam?.status).toBe('fail');
    expect(codexState?.detail).toContain('stale');
  });

  test('reports unreadable config as unknown without exposing contents', () => {
    const entries = baseEntries();
    entries[`${HOME}/.gemini/settings.json`] = {
      kind: 'file',
      content: JSON.stringify({ credential: REDACTION_SAMPLE }),
      readable: false,
    };
    delete entries[`${HOME}/.gemini/oauth_creds.json`];

    const report = reportFor(entries);
    const gemini = report.tools.find((item) => item.id === 'gemini');

    expect(report.ok).toBe(true);
    expect(gemini?.status).toBe('unknown');
    expect(gemini?.auth?.status).toBe('unknown');
    expect(JSON.stringify(report)).not.toContain(REDACTION_SAMPLE);
  });
});
