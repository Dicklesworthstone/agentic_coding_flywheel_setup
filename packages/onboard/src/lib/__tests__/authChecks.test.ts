import { describe, test, expect } from 'bun:test';
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

  test('checkClaude returns email when config has user email', () => {
    const configPath = path.join(HOME, '.claude', 'config.json');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === configPath,
        readFileSync: () => JSON.stringify({ user: { email: 'user@example.com' } }),
      }),
    );

    expect(checks.checkClaude()).toEqual({ authenticated: true, details: 'user@example.com' });
  });

  test('checkCodex requires access token', () => {
    const authPath = path.join(HOME, '.codex', 'auth.json');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ access_token: 'token' }),
      }),
    );

    expect(checks.checkCodex()).toEqual({ authenticated: true });
  });

  test('checkGemini returns authenticated when credentials.json exists', () => {
    const credPath = path.join(HOME, '.config', 'gemini', 'credentials.json');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === credPath,
      }),
    );

    expect(checks.checkGemini()).toEqual({ authenticated: true });
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

  test('checkVercel returns authenticated with legacy ~/.vercel/auth.json', () => {
    const authPath = path.join(HOME, '.vercel', 'auth.json');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ token: 'vercel-token', user: { email: 'me@example.com' } }),
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: true, details: 'me@example.com' });
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

  test('checkConvex returns authenticated with credentials file', () => {
    const tokenPath = path.join(HOME, '.config', 'convex', 'credentials.json');
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === tokenPath,
        readFileSync: () => 'token-value',
      }),
    );

    expect(checks.checkConvex()).toEqual({ authenticated: true });
  });

  test('checkConvex uses CONVEX_DEPLOYMENT when set', () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { CONVEX_DEPLOYMENT: 'dev:playground' } as NodeJS.ProcessEnv,
      }),
    );

    expect(checks.checkConvex()).toEqual({ authenticated: true, details: 'via CONVEX_DEPLOYMENT' });
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

  test('checkAllServices exposes all expected service ids', () => {
    const checks = createAuthChecks(makeDeps());
    const ids = Object.keys(checks.AUTH_CHECKS).sort();
    expect(ids).toEqual(
      ['tailscale', 'claude-code', 'codex-cli', 'gemini-cli', 'github', 'vercel', 'supabase', 'convex', 'cloudflare'].sort(),
    );
  });
});
