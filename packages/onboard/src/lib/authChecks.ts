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

function defaultCommandExists(env: NodeJS.ProcessEnv, command: string): boolean {
  const pathValue = env.PATH ?? '';
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
  commandExists: (command) => defaultCommandExists(process.env, command),
};

function safeReadJson<T>(readFileSync: typeof fs.readFileSync, filePath: string): T | null {
  try {
    const raw = readFileSync(filePath, 'utf-8');
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

function hasNonBlankString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function normalizeConfigValue(value: string): string {
  const trimmed = value.trim();
  if (
    trimmed.length >= 2 &&
    ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
      (trimmed.startsWith("'") && trimmed.endsWith("'")))
  ) {
    return trimmed.slice(1, -1).trim();
  }
  return trimmed;
}

const PLACEHOLDER_SECRETS = new Set([
  'your-token-here',
  'your-token',
  'your_api_key',
  'your-api-key',
  'your_vercel_token',
  'your_supabase_access_token',
  'your_cloudflare_api_token',
  'your_gemini_api_key',
  'your_google_api_key',
  'your_project_id',
  'your_project_location',
  'replace-me',
  'change-me',
  'changeme',
  '<token>',
  '<api-key>',
  '<secret>',
]);

function isPlaceholderSecret(value: unknown): boolean {
  if (!hasNonBlankString(value)) {
    return false;
  }
  return PLACEHOLDER_SECRETS.has(normalizeConfigValue(value).toLowerCase());
}

function hasUsableSecret(value: unknown): value is string {
  return hasNonBlankString(value) && !isPlaceholderSecret(value);
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function readConfiguredValueFromFile(
  readFileSync: typeof fs.readFileSync,
  filePath: string,
  variableName: string,
): string | null {
  try {
    const contents = readFileSync(filePath, 'utf-8');
    const match = contents.match(
      new RegExp(
        `^\\s*(?:export\\s+)?${escapeRegex(variableName)}\\s*=\\s*(.+?)\\s*$`,
        'm',
      ),
    );
    if (!match?.[1]) {
      return null;
    }
    let value = match[1].trim();
    if (!value.startsWith('"') && !value.startsWith("'")) {
      value = value.replace(/\s+#.*$/, '').trim();
    }
    const normalized = normalizeConfigValue(value);
    return normalized || null;
  } catch {
    return null;
  }
}

function extractYamlTopLevelBlock(contents: string, topLevelKey: string): string | null {
  const escapedKey = topLevelKey.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = contents.match(new RegExp(`(?:^|\\n)${escapedKey}:\\s*\\n((?:[ \\t]+.*(?:\\n|$))+)`, 'm'));
  return match?.[1] ?? null;
}

function parseGitHubHostsEntry(contents: string): AuthStatus | null {
  const block = extractYamlTopLevelBlock(contents, 'github.com');
  if (!block) {
    return null;
  }

  const tokenMatch = block.match(/^[ \t]+oauth_token:\s*(["']?)([^"'\n#]+)\1\s*$/m);
  if (!tokenMatch?.[2]?.trim()) {
    return null;
  }

  const userMatch = block.match(/^[ \t]+user:\s*(["']?)([^"'\n#]+)\1\s*$/m);
  const username = userMatch?.[2]?.trim();
  return username ? { authenticated: true, details: username } : { authenticated: true };
}

export function createAuthChecks(overrides: Partial<AuthCheckDeps> = {}) {
  const deps: AuthCheckDeps = { ...defaultDeps, ...overrides };
  if (!overrides.commandExists) {
    deps.commandExists = (command: string) => defaultCommandExists(deps.env, command);
  }
  const homedir = deps.homedir();
  const shellConfigPaths = [
    path.join(homedir, '.zshrc.local'),
    path.join(homedir, '.zshrc'),
    path.join(homedir, '.bashrc'),
    path.join(homedir, '.profile'),
  ];
  const geminiHome = deps.env.GEMINI_CLI_HOME ?? homedir;
  const geminiConfigPaths = [path.join(geminiHome, '.gemini', '.env'), ...shellConfigPaths];

  const runCommand = (
    command: string,
    options: { allowStderrFallback?: boolean } = {},
  ): string | null => {
    try {
      const output = deps.execSync(command, {
        encoding: 'utf-8',
        stdio: ['ignore', 'pipe', 'ignore'],
        timeout: 5000,
      });
      const trimmed = output.trim();
      if (trimmed) return trimmed;

      // Some CLIs (notably `gh auth status`) write human output to stderr.
      // Only fall back to stderr capture when stdout is empty to avoid breaking
      // JSON parsing for commands that emit JSON on stdout.
      if (options.allowStderrFallback) {
        const mergedOutput = deps.execSync(`${command} 2>&1`, {
          encoding: 'utf-8',
          stdio: ['ignore', 'pipe', 'ignore'],
          timeout: 5000,
        });
        const mergedTrimmed = mergedOutput.trim();
        return mergedTrimmed ? mergedTrimmed : null;
      }

      return null;
    } catch {
      return null;
    }
  };

  const getConfiguredValue = (variableName: string, filePaths: string[] = []): string | null => {
    const envValue = deps.env[variableName];
    if (hasNonBlankString(envValue) && !isPlaceholderSecret(envValue)) {
      return normalizeConfigValue(envValue);
    }
    for (const filePath of filePaths) {
      if (!deps.existsSync(filePath)) {
        continue;
      }
      const configuredValue = readConfiguredValueFromFile(deps.readFileSync, filePath, variableName);
      if (hasNonBlankString(configuredValue) && !isPlaceholderSecret(configuredValue)) {
        return configuredValue;
      }
    }
    return null;
  };

  const getConfiguredSecret = (variableName: string, filePaths: string[] = []): string | null => {
    const envValue = deps.env[variableName];
    if (hasUsableSecret(envValue)) {
      return normalizeConfigValue(envValue);
    }
    for (const filePath of filePaths) {
      if (!deps.existsSync(filePath)) {
        continue;
      }
      const configuredValue = readConfiguredValueFromFile(deps.readFileSync, filePath, variableName);
      if (hasUsableSecret(configuredValue)) {
        return configuredValue;
      }
    }
    return null;
  };

  const hasTruthyConfiguredValue = (variableName: string, filePaths: string[] = []): boolean => {
    const configuredValue = getConfiguredValue(variableName, filePaths);
    if (!hasNonBlankString(configuredValue)) {
      return false;
    }
    return ['1', 'true', 'yes', 'on'].includes(configuredValue.toLowerCase());
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
    if (!deps.commandExists('claude')) {
      return { authenticated: false };
    }

    const credentialsPath = path.join(homedir, '.claude', '.credentials.json');
    const credentials = safeReadJson<{ claudeAiOauth?: { accessToken?: string } }>(
      deps.readFileSync,
      credentialsPath,
    );
    if (!hasNonBlankString(credentials?.claudeAiOauth?.accessToken)) {
      return { authenticated: false };
    }

    const configPaths = [
      path.join(homedir, '.claude', 'config.json'),
      path.join(homedir, '.config', 'claude', 'config.json'),
    ];

    for (const configPath of configPaths) {
      if (deps.existsSync(configPath)) {
        const config = safeReadJson<{ user?: { email?: string } }>(deps.readFileSync, configPath);
        if (hasNonBlankString(config?.user?.email)) {
          return { authenticated: true, details: config.user.email.trim() };
        }
      }
    }
    return { authenticated: true };
  };

  const checkCodex = (): AuthStatus => {
    if (!deps.commandExists('codex')) {
      return { authenticated: false };
    }

    const codexHome = deps.env.CODEX_HOME ?? path.join(homedir, '.codex');
    const authPath = path.join(codexHome, 'auth.json');
    if (!deps.existsSync(authPath)) {
      return { authenticated: false };
    }
    const auth = safeReadJson<{
      tokens?: { access_token?: string };
      access_token?: string;
      accessToken?: string;
      OPENAI_API_KEY?: string | null;
    }>(deps.readFileSync, authPath);
    if (
      [
        auth?.tokens?.access_token,
        auth?.access_token,
        auth?.accessToken,
        auth?.OPENAI_API_KEY,
      ].some(hasNonBlankString)
    ) {
      return { authenticated: true };
    }
    return { authenticated: false };
  };

  const checkGemini = (): AuthStatus => {
    if (!deps.commandExists('gemini')) {
      return { authenticated: false };
    }

    const geminiApiKey = getConfiguredSecret('GEMINI_API_KEY', geminiConfigPaths);
    if (geminiApiKey) {
      return { authenticated: true, details: 'via GEMINI_API_KEY' };
    }

    const vertexModeEnabled = hasTruthyConfiguredValue('GOOGLE_GENAI_USE_VERTEXAI', geminiConfigPaths);
    if (vertexModeEnabled) {
      const googleApiKey = getConfiguredSecret('GOOGLE_API_KEY', geminiConfigPaths);
      if (googleApiKey) {
        return { authenticated: true, details: 'via GOOGLE_API_KEY (Vertex AI)' };
      }

      const vertexProject =
        getConfiguredValue('GOOGLE_CLOUD_PROJECT', geminiConfigPaths) ??
        getConfiguredValue('GOOGLE_CLOUD_PROJECT_ID', geminiConfigPaths);
      const vertexLocation = getConfiguredValue('GOOGLE_CLOUD_LOCATION', geminiConfigPaths);
      const serviceAccountPath = getConfiguredValue('GOOGLE_APPLICATION_CREDENTIALS', geminiConfigPaths);

      if (
        hasNonBlankString(vertexProject) &&
        hasNonBlankString(vertexLocation) &&
        hasNonBlankString(serviceAccountPath) &&
        deps.existsSync(serviceAccountPath)
      ) {
        return { authenticated: true, details: 'via GOOGLE_APPLICATION_CREDENTIALS (Vertex AI)' };
      }

      if (
        hasNonBlankString(vertexProject) &&
        hasNonBlankString(vertexLocation) &&
        deps.commandExists('gcloud') &&
        runCommand('gcloud auth application-default print-access-token')
      ) {
        return { authenticated: true, details: 'via gcloud ADC (Vertex AI)' };
      }
    }

    const googleAccountsPath = path.join(geminiHome, '.gemini', 'google_accounts.json');
    const googleAccounts = safeReadJson<{ active?: string | null }>(
      deps.readFileSync,
      googleAccountsPath,
    );
    if (hasNonBlankString(googleAccounts?.active)) {
      return { authenticated: true, details: googleAccounts.active.trim() };
    }

    const oauthCredsPath = path.join(geminiHome, '.gemini', 'oauth_creds.json');
    const oauthCreds = safeReadJson<{ access_token?: string; refresh_token?: string }>(
      deps.readFileSync,
      oauthCredsPath,
    );
    if (
      hasNonBlankString(oauthCreds?.access_token) ||
      hasNonBlankString(oauthCreds?.refresh_token)
    ) {
      return { authenticated: true };
    }

    return { authenticated: false };
  };

  const checkGitHub = (): AuthStatus => {
    if (deps.commandExists('gh')) {
      const output = runCommand('gh auth status -h github.com', { allowStderrFallback: true });
      if (output && output.includes('Logged in to')) {
        const match = output.match(/Logged in to .* as ([^\s]+)/i);
        return { authenticated: true, details: match?.[1] };
      }
    }

    const hostsPath = path.join(homedir, '.config', 'gh', 'hosts.yml');
    if (deps.existsSync(hostsPath)) {
      try {
        const contents = deps.readFileSync(hostsPath, 'utf-8');
        return parseGitHubHostsEntry(contents) ?? { authenticated: false };
      } catch {
        return { authenticated: false };
      }
    }
    return { authenticated: false };
  };

  const checkVercel = (): AuthStatus => {
    if (deps.commandExists('vercel')) {
      if (getConfiguredSecret('VERCEL_TOKEN', shellConfigPaths)) {
        return { authenticated: true, details: 'via VERCEL_TOKEN' };
      }

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
      if (hasNonBlankString(auth?.user?.email)) {
        return { authenticated: true, details: auth.user.email.trim() };
      }
      if (hasNonBlankString(auth?.token)) {
        return { authenticated: true };
      }
      // File exists but contains no valid token or user - not authenticated
    }
    return { authenticated: false };
  };

  const checkSupabase = (): AuthStatus => {
    if (getConfiguredSecret('SUPABASE_ACCESS_TOKEN', shellConfigPaths)) {
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
    // Note: config.toml existence alone doesn't indicate authentication
    // It's created by `supabase init` but contains no credentials
    return { authenticated: false };
  };

  const checkWrangler = (): AuthStatus => {
    if (getConfiguredSecret('CLOUDFLARE_API_TOKEN', shellConfigPaths)) {
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

    // Note: config file existence alone doesn't indicate authentication
    // wrangler whoami is the reliable check; if it's not available or fails,
    // we cannot confirm authentication
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
