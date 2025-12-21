import * as childProcess from 'child_process';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

export interface AuthStatus {
  authenticated: boolean;
  details?: string;
}

type ExecSync = (command: string, options?: childProcess.ExecSyncOptions & { encoding?: 'utf-8' }) => string;

interface AuthCheckDeps {
  execSync: ExecSync;
  existsSync: typeof fs.existsSync;
  readFileSync: typeof fs.readFileSync;
  homedir: () => string;
  env: NodeJS.ProcessEnv;
  commandExists: (command: string) => boolean;
}

function isExecutable(filePath: string): boolean {
  try {
    fs.accessSync(filePath, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function defaultCommandExists(command: string): boolean {
  const pathValue = process.env.PATH ?? '';
  if (!pathValue) {
    return false;
  }
  for (const dir of pathValue.split(path.delimiter)) {
    if (!dir) {
      continue;
    }
    const candidate = path.join(dir, command);
    try {
      const stat = fs.statSync(candidate);
      if (!stat.isFile()) {
        continue;
      }
      if (isExecutable(candidate)) {
        return true;
      }
    } catch {
      // ignore missing or unreadable entries
    }
  }
  return false;
}

const defaultDeps: AuthCheckDeps = {
  execSync: childProcess.execSync,
  existsSync: fs.existsSync,
  readFileSync: fs.readFileSync,
  homedir: os.homedir,
  env: process.env,
  commandExists: defaultCommandExists,
};

function safeReadJson<T>(readFileSync: typeof fs.readFileSync, filePath: string): T | null {
  try {
    const raw = readFileSync(filePath, 'utf-8');
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export function createAuthChecks(overrides: Partial<AuthCheckDeps> = {}) {
  const deps: AuthCheckDeps = { ...defaultDeps, ...overrides };
  const homedir = deps.homedir();

  const runCommand = (command: string): string | null => {
    try {
      const output = deps.execSync(command, {
        encoding: 'utf-8',
        stdio: ['ignore', 'pipe', 'ignore'],
      });
      return output.trim();
    } catch {
      return null;
    }
  };

  const checkTailscale = (): AuthStatus => {
    if (!deps.commandExists('tailscale')) {
      return { authenticated: false };
    }
    try {
      const result = runCommand('tailscale status --json');
      if (!result) {
        return { authenticated: false };
      }
      const status = JSON.parse(result) as { BackendState?: string };
      if (status.BackendState === 'Running') {
        const ip = runCommand('tailscale ip -4');
        return ip ? { authenticated: true, details: `IP: ${ip}` } : { authenticated: true };
      }
      return { authenticated: false };
    } catch {
      return { authenticated: false };
    }
  };

  const checkClaude = (): AuthStatus => {
    const configPaths = [
      path.join(homedir, '.claude', 'config.json'),
      path.join(homedir, '.config', 'claude', 'config.json'),
    ];

    for (const configPath of configPaths) {
      if (deps.existsSync(configPath)) {
        const config = safeReadJson<{ user?: { email?: string } }>(deps.readFileSync, configPath);
        if (config?.user?.email) {
          return { authenticated: true, details: config.user.email };
        }
        return { authenticated: true };
      }
    }
    return { authenticated: false };
  };

  const checkCodex = (): AuthStatus => {
    const codexHome = deps.env.CODEX_HOME ?? path.join(homedir, '.codex');
    const authPath = path.join(codexHome, 'auth.json');
    if (!deps.existsSync(authPath)) {
      return { authenticated: false };
    }
    const auth = safeReadJson<{ access_token?: string; accessToken?: string }>(deps.readFileSync, authPath);
    if (auth?.access_token || auth?.accessToken) {
      return { authenticated: true };
    }
    return { authenticated: false };
  };

  const checkGemini = (): AuthStatus => {
    // Gemini CLI uses OAuth web login (like Claude Code and Codex CLI)
    // Users authenticate via `gemini` command which opens browser login
    // Credentials are stored in config files, NOT via API keys
    const credPath = path.join(homedir, '.config', 'gemini', 'credentials.json');
    if (deps.existsSync(credPath)) {
      return { authenticated: true };
    }
    const legacyConfigPath = path.join(homedir, '.gemini', 'config');
    if (deps.existsSync(legacyConfigPath)) {
      return { authenticated: true };
    }
    // Note: Just having the config directory is not enough - we need actual credential files
    return { authenticated: false };
  };

  const checkGitHub = (): AuthStatus => {
    if (deps.commandExists('gh')) {
      const output = runCommand('gh auth status -h github.com');
      if (output && output.includes('Logged in to')) {
        const match = output.match(/Logged in to .* as ([^\s]+)/i);
        return { authenticated: true, details: match?.[1] };
      }
    }

    const hostsPath = path.join(homedir, '.config', 'gh', 'hosts.yml');
    if (deps.existsSync(hostsPath)) {
      try {
        const contents = deps.readFileSync(hostsPath, 'utf-8');
        const match = contents.match(/^\s*user:\s*([^\s]+)/m);
        return { authenticated: true, details: match?.[1] };
      } catch {
        return { authenticated: true };
      }
    }
    return { authenticated: false };
  };

  const checkVercel = (): AuthStatus => {
    if (deps.commandExists('vercel')) {
      const output = runCommand('vercel whoami');
      if (output && !output.toLowerCase().includes('not logged')) {
        return { authenticated: true, details: output };
      }
    }

    const authPaths = [
      path.join(homedir, '.config', 'vercel', 'auth.json'),
      path.join(homedir, '.vercel', 'auth.json'),
    ];
    for (const authPath of authPaths) {
      if (!deps.existsSync(authPath)) {
        continue;
      }
      const auth = safeReadJson<{ token?: string; user?: { email?: string } }>(deps.readFileSync, authPath);
      if (auth?.user?.email) {
        return { authenticated: true, details: auth.user.email };
      }
      if (auth?.token) {
        return { authenticated: true };
      }
      // File exists but contains no valid token or user - not authenticated
    }
    return { authenticated: false };
  };

  const checkSupabase = (): AuthStatus => {
    if (deps.env.SUPABASE_ACCESS_TOKEN) {
      return { authenticated: true, details: 'via SUPABASE_ACCESS_TOKEN' };
    }

    const tokenPaths = [
      path.join(homedir, '.supabase', 'access-token'),
      path.join(homedir, '.config', 'supabase', 'access-token'),
    ];
    for (const tokenPath of tokenPaths) {
      if (!deps.existsSync(tokenPath)) {
        continue;
      }
      try {
        const token = deps.readFileSync(tokenPath, 'utf-8').trim();
        return token ? { authenticated: true } : { authenticated: false };
      } catch {
        // File exists but unreadable - cannot confirm authentication
        continue;
      }
    }
    const configPath = path.join(homedir, '.supabase', 'config.toml');
    if (deps.existsSync(configPath)) {
      return { authenticated: true };
    }
    return { authenticated: false };
  };

  const checkWrangler = (): AuthStatus => {
    if (deps.env.CLOUDFLARE_API_TOKEN) {
      return { authenticated: true, details: 'via CLOUDFLARE_API_TOKEN' };
    }
    if (deps.commandExists('wrangler')) {
      const output = runCommand('wrangler whoami');
      if (output) {
        if (!output.toLowerCase().includes('not authenticated')) {
          const match = output.match(/email:\s*([^\s]+)/i);
          return { authenticated: true, details: match?.[1] };
        }
        return { authenticated: false };
      }
    }

    const configPaths = [
      path.join(homedir, '.config', 'wrangler', 'config', 'default.toml'),
      path.join(homedir, '.wrangler', 'config', 'default.toml'),
    ];
    for (const configPath of configPaths) {
      if (deps.existsSync(configPath)) {
        return { authenticated: true };
      }
    }
    return { authenticated: false };
  };

  const AUTH_CHECKS: Record<string, () => AuthStatus> = {
    tailscale: checkTailscale,
    'claude-code': checkClaude,
    'codex-cli': checkCodex,
    'gemini-cli': checkGemini,
    github: checkGitHub,
    vercel: checkVercel,
    supabase: checkSupabase,
    cloudflare: checkWrangler,
  };

  const checkAllServices = (): Record<string, AuthStatus> => {
    const results: Record<string, AuthStatus> = {};
    for (const [id, check] of Object.entries(AUTH_CHECKS)) {
      try {
        results[id] = check();
      } catch {
        results[id] = { authenticated: false };
      }
    }
    return results;
  };

  return {
    checkTailscale,
    checkClaude,
    checkCodex,
    checkGemini,
    checkGitHub,
    checkVercel,
    checkSupabase,
    checkWrangler,
    AUTH_CHECKS,
    checkAllServices,
  };
}

const {
  checkTailscale,
  checkClaude,
  checkCodex,
  checkGemini,
  checkGitHub,
  checkVercel,
  checkSupabase,
  checkWrangler,
  AUTH_CHECKS,
  checkAllServices,
} = createAuthChecks();

export {
  checkTailscale,
  checkClaude,
  checkCodex,
  checkGemini,
  checkGitHub,
  checkVercel,
  checkSupabase,
  checkWrangler,
  AUTH_CHECKS,
  checkAllServices,
};
