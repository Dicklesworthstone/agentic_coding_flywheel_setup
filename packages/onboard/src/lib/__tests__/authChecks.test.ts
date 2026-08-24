import { describe, test, expect } from 'bun:test';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { createAuthChecks } from '../authChecks';

const HOME = '/home/tester';

type AuthCheckOverrides = NonNullable<Parameters<typeof createAuthChecks>[0]>;

const baseDeps: AuthCheckOverrides = {
  execSync: (_command: string) => {
    throw new Error('unexpected command');
  },
  existsSync: (_path: string) => false,
  readFileSync: (_path: string) => '',
  homedir: () => HOME,
  env: {} as NodeJS.ProcessEnv,
  commandExists: (_command: string) => false,
};

const makeDeps = (overrides: AuthCheckOverrides = {}) => ({
  ...baseDeps,
  ...overrides,
});

describe('authChecks', () => {
  test('checkTailscale returns IP details when running', () => {
    const execSync = (command: string) => {
      if (command === 'tailscale status --json') {
        return JSON.stringify({ BackendState: 'Running' });
      }
      if (command === 'tailscale ip -4') {
        return '100.64.0.12\n';
      }
      throw new Error(`unexpected command: ${command}`);
    };

    const checks = createAuthChecks(
      makeDeps({
        execSync,
        commandExists: (command) => command === 'tailscale',
      }),
    );

    expect(checks.checkTailscale()).toEqual({ authenticated: true, details: 'IP: 100.64.0.12' });
  });

  test('checkClaude requires OAuth credentials and returns email when config has user email', () => {
    const credentialsPath = path.join(HOME, '.claude', '.credentials.json');
    const configPath = path.join(HOME, '.claude', 'config.json');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'claude',
        existsSync: (filePath) => filePath === credentialsPath || filePath === configPath,
        readFileSync: (filePath) =>
          filePath === credentialsPath
            ? JSON.stringify({ claudeAiOauth: { accessToken: 'token' } })
            : JSON.stringify({ user: { email: 'user@example.com' } }),
      }),
    );

    expect(checks.checkClaude()).toEqual({ authenticated: true, details: 'user@example.com' });
  });

  test('checkClaude rejects config-only state without OAuth credentials', () => {
    const configPath = path.join(HOME, '.claude', 'config.json');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'claude',
        existsSync: (filePath) => filePath === configPath,
        readFileSync: () => JSON.stringify({ user: { email: 'user@example.com' } }),
      }),
    );

    expect(checks.checkClaude()).toEqual({ authenticated: false });
  });

  test('checkClaude rejects blank OAuth credentials', () => {
    const credentialsPath = path.join(HOME, '.claude', '.credentials.json');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'claude',
        existsSync: (filePath) => filePath === credentialsPath,
        readFileSync: () => JSON.stringify({ claudeAiOauth: { accessToken: '   ' } }),
      }),
    );

    expect(checks.checkClaude()).toEqual({ authenticated: false });
  });

  test('checkClaude rejects placeholder OAuth credentials', () => {
    const credentialsPath = path.join(HOME, '.claude', '.credentials.json');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'claude',
        existsSync: (filePath) => filePath === credentialsPath,
        readFileSync: () => JSON.stringify({ claudeAiOauth: { accessToken: 'your-token-here' } }),
      }),
    );

    expect(checks.checkClaude()).toEqual({ authenticated: false });
  });

  test('checkClaude keeps searching config fallbacks until it finds a valid email', () => {
    const credentialsPath = path.join(HOME, '.claude', '.credentials.json');
    const primaryConfigPath = path.join(HOME, '.claude', 'config.json');
    const fallbackConfigPath = path.join(HOME, '.config', 'claude', 'config.json');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'claude',
        existsSync: (filePath) =>
          filePath === credentialsPath ||
          filePath === primaryConfigPath ||
          filePath === fallbackConfigPath,
        readFileSync: (filePath) => {
          if (filePath === credentialsPath) {
            return JSON.stringify({ claudeAiOauth: { accessToken: 'token' } });
          }
          if (filePath === primaryConfigPath) {
            return JSON.stringify({ user: {} });
          }
          return JSON.stringify({ user: { email: 'fallback@example.com' } });
        },
      }),
    );

    expect(checks.checkClaude()).toEqual({ authenticated: true, details: 'fallback@example.com' });
  });

  test('checkClaude rejects stale credentials when claude is not installed', () => {
    const credentialsPath = path.join(HOME, '.claude', '.credentials.json');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === credentialsPath,
        readFileSync: () => JSON.stringify({ claudeAiOauth: { accessToken: 'token' } }),
      }),
    );

    expect(checks.checkClaude()).toEqual({ authenticated: false });
  });

  test('checkCodex accepts nested OAuth access token', () => {
    const authPath = path.join(HOME, '.codex', 'auth.json');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'codex',
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ tokens: { access_token: 'token' } }),
      }),
    );

    expect(checks.checkCodex()).toEqual({ authenticated: true });
  });

  test('checkCodex accepts legacy API-key auth in auth.json', () => {
    const authPath = path.join(HOME, '.codex', 'auth.json');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'codex',
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ OPENAI_API_KEY: 'sk-test' }),
      }),
    );

    expect(checks.checkCodex()).toEqual({ authenticated: true });
  });

  test('checkCodex rejects stale auth when codex is not installed', () => {
    const authPath = path.join(HOME, '.codex', 'auth.json');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ tokens: { access_token: 'token' } }),
      }),
    );

    expect(checks.checkCodex()).toEqual({ authenticated: false });
  });

  test('checkCodex rejects blank auth tokens', () => {
    const authPath = path.join(HOME, '.codex', 'auth.json');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'codex',
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ OPENAI_API_KEY: '   ' }),
      }),
    );

    expect(checks.checkCodex()).toEqual({ authenticated: false });
  });

  test('checkCodex rejects placeholder auth tokens', () => {
    const authPath = path.join(HOME, '.codex', 'auth.json');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'codex',
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ tokens: { access_token: 'your_token_here' } }),
      }),
    );

    expect(checks.checkCodex()).toEqual({ authenticated: false });
  });

  test('checkCodex respects the injected PATH when using the default command lookup', () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'acfs-auth-checks-'));
    const fakeCodexPath = path.join(tempDir, 'codex');
    fs.writeFileSync(fakeCodexPath, '#!/bin/sh\nexit 0\n', 'utf-8');
    fs.chmodSync(fakeCodexPath, 0o755);

    const authPath = path.join(HOME, '.codex', 'auth.json');
    const originalPath = process.env.PATH;
    process.env.PATH = tempDir;

    try {
      const checks = createAuthChecks({
        execSync: baseDeps.execSync,
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ tokens: { access_token: 'token' } }),
        homedir: () => HOME,
        env: { PATH: '', CODEX_HOME: path.join(HOME, '.codex') } as NodeJS.ProcessEnv,
      });

      expect(checks.checkCodex()).toEqual({ authenticated: false });
    } finally {
      process.env.PATH = originalPath;
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  });

  test('checkAntigravity returns authenticated when the Antigravity OAuth token exists', () => {
    const tokenPath = path.join(HOME, '.gemini', 'antigravity-cli', 'antigravity-oauth-token');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'agy',
        existsSync: (filePath) => filePath === tokenPath,
        readFileSync: (filePath) => (filePath === tokenPath ? 'antigravity-token' : ''),
      }),
    );

    expect(checks.checkAntigravity()).toEqual({ authenticated: true });
  });

  test('checkAntigravity rejects placeholder Antigravity token values', () => {
    const tokenPath = path.join(HOME, '.gemini', 'antigravity-cli', 'antigravity-oauth-token');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'agy',
        existsSync: (filePath) => filePath === tokenPath,
        readFileSync: (filePath) => (filePath === tokenPath ? 'your-token-here' : ''),
      }),
    );

    expect(checks.checkAntigravity()).toEqual({ authenticated: false });
  });

  test('checkAntigravity rejects stale credentials when agy is not installed', () => {
    const tokenPath = path.join(HOME, '.gemini', 'antigravity-cli', 'antigravity-oauth-token');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === tokenPath,
        readFileSync: (filePath) => (filePath === tokenPath ? 'antigravity-token' : ''),
      }),
    );

    expect(checks.checkAntigravity()).toEqual({ authenticated: false });
  });

  test('checkAntigravity respects ANTIGRAVITY_HOME when locating the OAuth token', () => {
    const antigravityHome = '/tmp/antigravity-home';
    const tokenPath = path.join(antigravityHome, 'antigravity-oauth-token');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'agy',
        env: { ANTIGRAVITY_HOME: antigravityHome } as NodeJS.ProcessEnv,
        existsSync: (filePath) => filePath === tokenPath,
        readFileSync: (filePath) => (filePath === tokenPath ? 'antigravity-token' : ''),
      }),
    );

    expect(checks.checkAntigravity()).toEqual({ authenticated: true });
  });

  test('checkGitHub reads gh auth status when available', () => {
    const execSync = (command: string) => {
      if (command === 'gh auth status -h github.com') {
        return 'Logged in to github.com as octocat';
      }
      throw new Error(`unexpected command: ${command}`);
    };

    const checks = createAuthChecks(
      makeDeps({
        execSync,
        commandExists: (command) => command === 'gh',
      }),
    );

    expect(checks.checkGitHub()).toEqual({ authenticated: true, details: 'octocat' });
  });

  test('checkGitHub falls back to the github.com hosts entry when gh is unavailable', () => {
    const hostsPath = path.join(HOME, '.config', 'gh', 'hosts.yml');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === hostsPath,
        readFileSync: () =>
          [
            'github.com:',
            '    oauth_token: gho_testtoken',
            '    user: octocat',
            '    git_protocol: https',
            'example.internal:',
            '    oauth_token: ignored',
            '    user: enterprise-user',
          ].join('\n'),
      }),
    );

    expect(checks.checkGitHub()).toEqual({ authenticated: true, details: 'octocat' });
  });

  test('checkGitHub rejects hosts files without a github.com oauth token', () => {
    const hostsPath = path.join(HOME, '.config', 'gh', 'hosts.yml');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === hostsPath,
        readFileSync: () =>
          [
            'github.com:',
            '    user: octocat',
            'example.internal:',
            '    oauth_token: valid-enterprise-token',
            '    user: enterprise-user',
          ].join('\n'),
      }),
    );

    expect(checks.checkGitHub()).toEqual({ authenticated: false });
  });

  test('checkGitHub rejects placeholder oauth tokens in hosts.yml', () => {
    const hostsPath = path.join(HOME, '.config', 'gh', 'hosts.yml');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === hostsPath,
        readFileSync: () =>
          [
            'github.com:',
            '    oauth_token: your_github_token',
            '    user: octocat',
          ].join('\n'),
      }),
    );

    expect(checks.checkGitHub()).toEqual({ authenticated: false });
  });

  test('checkVercel returns authenticated with legacy ~/.vercel/auth.json token', () => {
    const authPath = path.join(HOME, '.vercel', 'auth.json');
    const validVercelCredential = ['vercel', 'credential'].join('-');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ token: validVercelCredential, user: { email: 'me@example.com' } }),
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: true, details: 'me@example.com' });
  });

  test('checkVercel rejects auth.json without a token', () => {
    const authPath = path.join(HOME, '.vercel', 'auth.json');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ user: { email: 'me@example.com' } }),
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test('checkVercel returns authenticated with VERCEL_TOKEN env var', () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { VERCEL_TOKEN: 'token-123' } as NodeJS.ProcessEnv,
        commandExists: (command) => command === 'vercel',
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: true, details: 'via VERCEL_TOKEN' });
  });

  test('checkVercel rejects blank VERCEL_TOKEN values', () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { VERCEL_TOKEN: '   ' } as NodeJS.ProcessEnv,
        commandExists: (command) => command === 'vercel',
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test('checkVercel rejects placeholder VERCEL_TOKEN values', () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { VERCEL_TOKEN: 'your-token-here' } as NodeJS.ProcessEnv,
        commandExists: (command) => command === 'vercel',
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test('checkVercel rejects placeholder auth.json tokens', () => {
    const authPath = path.join(HOME, '.config', 'vercel', 'auth.json');
    const placeholderVercelCredential = ['your', 'vercel', 'token'].join('_');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ token: placeholderVercelCredential }),
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test('checkVercel uses the last shell config assignment for token values', () => {
    const configPath = path.join(HOME, '.zshrc.local');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'vercel',
        existsSync: (filePath) => filePath === configPath,
        readFileSync: () =>
          ['export VERCEL_TOKEN=your_vercel_token', 'export VERCEL_TOKEN=vercel-token'].join('\n'),
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: true, details: 'via VERCEL_TOKEN' });
  });

  test('checkVercel rejects shell config tokens overwritten by placeholders', () => {
    const configPath = path.join(HOME, '.zshrc.local');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'vercel',
        existsSync: (filePath) => filePath === configPath,
        readFileSync: () =>
          ['export VERCEL_TOKEN=vercel-token', 'export VERCEL_TOKEN=your_vercel_token'].join('\n'),
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test.each([
    'export VERCEL_TOKEN=$VERCEL_TOKEN',
    'export VERCEL_TOKEN="${VERCEL_TOKEN:-fallback}"',
    'export VERCEL_TOKEN=$(read-token)',
    'export VERCEL_TOKEN=`read-token`',
  ])('checkVercel rejects unresolved shell config expression: %s', (assignment) => {
    const configPath = path.join(HOME, '.zshrc.local');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'vercel',
        existsSync: (filePath) => filePath === configPath,
        readFileSync: () => assignment,
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test('checkVercel treats a later unresolved shell expression as the effective assignment', () => {
    const configPath = path.join(HOME, '.zshrc.local');
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === 'vercel',
        existsSync: (filePath) => filePath === configPath,
        readFileSync: () =>
          ['export VERCEL_TOKEN=vercel-token', 'export VERCEL_TOKEN=$LATER_TOKEN'].join('\n'),
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test('checkSupabase returns authenticated with access token file', () => {
    const tokenPath = path.join(HOME, '.supabase', 'access-token');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === tokenPath,
        readFileSync: () => 'token-value',
      }),
    );

    expect(checks.checkSupabase()).toEqual({ authenticated: true });
  });

  test('checkSupabase uses SUPABASE_ACCESS_TOKEN when set', () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { SUPABASE_ACCESS_TOKEN: 'token' } as NodeJS.ProcessEnv,
      }),
    );

    expect(checks.checkSupabase()).toEqual({ authenticated: true, details: 'via SUPABASE_ACCESS_TOKEN' });
  });

  test('checkSupabase rejects blank SUPABASE_ACCESS_TOKEN values', () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { SUPABASE_ACCESS_TOKEN: '   ' } as NodeJS.ProcessEnv,
      }),
    );

    expect(checks.checkSupabase()).toEqual({ authenticated: false });
  });

  test('checkSupabase rejects placeholder SUPABASE_ACCESS_TOKEN values', () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { SUPABASE_ACCESS_TOKEN: 'YOUR_SUPABASE_ACCESS_TOKEN' } as NodeJS.ProcessEnv,
      }),
    );

    expect(checks.checkSupabase()).toEqual({ authenticated: false });
  });

  test('checkSupabase rejects placeholder access token files', () => {
    const tokenPath = path.join(HOME, '.supabase', 'access-token');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === tokenPath,
        readFileSync: () => 'your_supabase_access_token',
      }),
    );

    expect(checks.checkSupabase()).toEqual({ authenticated: false });
  });

  test('checkWrangler reads email from whoami output', () => {
    const execSync = (command: string) => {
      if (command === 'wrangler whoami') {
        return 'email: dev@example.com\n';
      }
      throw new Error(`unexpected command: ${command}`);
    };

    const checks = createAuthChecks(
      makeDeps({
        execSync,
        commandExists: (command) => command === 'wrangler',
      }),
    );

    expect(checks.checkWrangler()).toEqual({ authenticated: true, details: 'dev@example.com' });
  });

  test('checkWrangler rejects blank CLOUDFLARE_API_TOKEN values', () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { CLOUDFLARE_API_TOKEN: '   ' } as NodeJS.ProcessEnv,
      }),
    );

    expect(checks.checkWrangler()).toEqual({ authenticated: false });
  });

  test('checkWrangler rejects placeholder CLOUDFLARE_API_TOKEN values', () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { CLOUDFLARE_API_TOKEN: 'your-token-here' } as NodeJS.ProcessEnv,
      }),
    );

    expect(checks.checkWrangler()).toEqual({ authenticated: false });
  });

  test('checkAllServices exposes all expected service ids', () => {
    const checks = createAuthChecks(makeDeps());
    const ids = Object.keys(checks.AUTH_CHECKS).sort();
    expect(ids).toEqual(
      ['tailscale', 'claude-code', 'codex-cli', 'antigravity-cli', 'github', 'vercel', 'supabase', 'cloudflare'].sort(),
    );
  });
});
