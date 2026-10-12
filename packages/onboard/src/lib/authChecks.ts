import * as childProcess from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

export interface AuthStatus {
  // True only after a successful provider check. Stored candidates use configured.
  authenticated: boolean;
  configured?: boolean;
  details?: string;
  credential?: CredentialMetadata;
}

export type CredentialService = "claude" | "codex" | "gemini" | "vercel" | "supabase" | "wrangler";
export type CredentialState = "missing" | "placeholder" | "shell_configured" | "file_configured" |
  "expired" | "refresh_required" | "vault_backed" | "unknown";
export interface CredentialMetadata {
  service: CredentialService;
  state: CredentialState;
  source: "none" | "environment" | "file" | "vault";
  requirement: "optional" | "required";
  authentication: "unverified";
  remediation: "replace_or_unset_placeholder" | "inspect_local_config" | "configure_when_needed" |
    "validate_before_use" | "refresh_or_reauthenticate" | "resolve_vault_reference";
}
export interface CredentialReport {
  schema_version: 1;
  kind: "acfs.credential_status";
  status: "pass" | "warn";
  read_only: true;
  services: CredentialMetadata[];
  summary: { required_unmet: number };
  safety: { raw_secret_values_printed: false; files_mutated: false; provider_validation_performed: false };
}

const CREDENTIAL_SERVICES: readonly CredentialService[] = ["claude", "codex", "gemini", "vercel", "supabase", "wrangler"];
const CREDENTIAL_BYTE_LIMIT = 1048576;
const READY_CREDENTIAL_STATES: ReadonlySet<CredentialState> = new Set(["shell_configured", "file_configured"]);
const FINAL_FILE_STATES: ReadonlySet<CredentialState> = new Set(["file_configured", "vault_backed", "unknown"]);
const INTERACTIVE_CANDIDATE_STATES: ReadonlySet<CredentialState> = new Set(["missing", "file_configured", "shell_configured"]);
const ACTIVE_CREDENTIAL_SOURCES: ReadonlySet<CredentialMetadata["source"]> = new Set(["environment", "vault"]);
const REMEDIATION_BY_STATE: Record<CredentialState, CredentialMetadata["remediation"]> = {
  missing: "configure_when_needed", placeholder: "replace_or_unset_placeholder",
  shell_configured: "validate_before_use", file_configured: "validate_before_use",
  expired: "refresh_or_reauthenticate", refresh_required: "refresh_or_reauthenticate",
  vault_backed: "resolve_vault_reference", unknown: "inspect_local_config",
};

function readCredentialSnapshot(filePath: string): string {
  const descriptor = fs.openSync(filePath, "r");
  try {
    if (!fs.fstatSync(descriptor).isFile()) return "";
    const bytes = Buffer.alloc(CREDENTIAL_BYTE_LIMIT + 1);
    let length = 0;
    while (length < bytes.length) {
      const count = fs.readSync(descriptor, bytes, length, bytes.length - length, null);
      if (count === 0) break;
      length += count;
    }
    if (length > CREDENTIAL_BYTE_LIMIT || bytes.subarray(0, length).includes(0)) {
      throw new Error("invalid credential bytes");
    }
    return bytes.subarray(0, length).toString("utf8");
  } finally {
    fs.closeSync(descriptor);
  }
}

type ExecSync = (
  command: string,
  options: childProcess.ExecSyncOptionsWithStringEncoding,
) => string;

interface AuthCheckDeps {
  execSync: ExecSync;
  existsSync: (filePath: string) => boolean;
  readFileSync: (filePath: string, encoding: "utf8" | "utf-8") => string;
  homedir: () => string;
  env: NodeJS.ProcessEnv;
  commandExists: (command: string) => boolean;
  readCredentialSnapshot: (filePath: string) => string;
  now: () => number;
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
  const pathValue = env.PATH ?? "";
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
  readCredentialSnapshot,
  now: Date.now,
};

function safeReadJson<T>(readFileSync: AuthCheckDeps["readFileSync"], filePath: string): T | null {
  try {
    const raw = readFileSync(filePath, "utf-8");
    if (Buffer.byteLength(raw, "utf8") > CREDENTIAL_BYTE_LIMIT || raw.includes("\0")) return null;
    const parsed: unknown = JSON.parse(raw);
    return hasNulString(parsed) ? null : parsed as T;
  } catch {
    return null;
  }
}

function hasNonBlankString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
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

function stripShellInlineComment(value: string): string {
  let quote: '"' | "'" | null = null;
  for (let i = 0; i < value.length; i += 1) {
    const char = value[i];
    if (quote) {
      if (char === "\\") {
        i += 1;
        continue;
      }
      if (char === quote) {
        quote = null;
      }
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      continue;
    }
    if (char === "#" && (i === 0 || /\s/.test(value[i - 1] ?? ""))) {
      return value.slice(0, i).trimEnd();
    }
  }
  return value.trim();
}

function hasUnresolvedShellExpression(value: string): boolean {
  // Shell startup files are inspected as text, never evaluated. Treat any
  // expansion syntax as unresolved instead of mistaking the expression itself
  // for a credential. Real environment values have already been expanded and
  // are handled separately by getConfiguredSecret.
  return value.includes("$") || value.includes("`");
}

// Mirrored by is_placeholder_secret in doctor.sh and onboard.sh and by
// services_setup_is_placeholder_secret; authChecks.test.ts pins all four.
export const PLACEHOLDER_SECRETS = new Set([
  "your-token-here",
  "your_token_here",
  "your-token",
  "your_token",
  "your_api_key",
  "your-api-key",
  "your_github_token",
  "your_openai_api_key",
  "your_claude_token",
  "your_vercel_token",
  "your_supabase_access_token",
  "your_cloudflare_api_token",
  "your_gemini_api_key",
  "your-gemini-api-key",
  "your_google_api_key",
  "your_project_id",
  "your_project_location",
  "replace-me",
  "change-me",
  "changeme",
  "<token>",
  "<api-key>",
  "<secret>",
]);

function isPlaceholderSecret(value: unknown): boolean {
  if (!hasNonBlankString(value)) {
    return false;
  }
  return PLACEHOLDER_SECRETS.has(normalizeConfigValue(value).toLowerCase());
}

function hasUsableSecret(value: unknown): value is string {
  if (!hasNonBlankString(value) || value.includes("\0")) return false;
  const normalized = normalizeConfigValue(value);
  return normalized.length > 0 && !normalized.toLowerCase().startsWith("vault://") && !isPlaceholderSecret(value);
}

function vaultReferenceState(raw: string): CredentialState {
  const value = normalizeConfigValue(raw);
  const match = value.match(/^vault:\/\/([a-zA-Z0-9_.-]+(?:\/[a-zA-Z0-9_.-]+)+)#([a-zA-Z0-9_.-]+)$/);
  if (!match || value.length > 2048) return "unknown";
  const components = [...match[1].split("/"), match[2]];
  return components.some((part) => part === "." || part === ".." || isPlaceholderSecret(part)) ? "unknown" : "vault_backed";
}

function candidateState(candidate: string): CredentialState {
  if (candidate.includes("\0")) return "unknown";
  const normalized = normalizeConfigValue(candidate);
  if (/^vault:\/\//i.test(normalized)) return vaultReferenceState(candidate);
  if (hasUsableSecret(candidate)) return "file_configured";
  return isPlaceholderSecret(candidate) ? "placeholder" : "missing";
}

function hasNulString(value: unknown): boolean {
  if (typeof value === "string") return value.includes("\0");
  if (Array.isArray(value)) return value.some(hasNulString);
  return value !== null && typeof value === "object" && Object.values(value).some(hasNulString);
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function readConfiguredValueFromFile(
  readFileSync: AuthCheckDeps["readFileSync"],
  filePath: string,
  variableName: string,
): string | null {
  try {
    const contents = readFileSync(filePath, "utf-8");
    const assignmentRegex = new RegExp(
      `^\\s*(?:export\\s+)?${escapeRegex(variableName)}\\s*=\\s*(.*?)\\s*$`,
    );
    let configuredValue: string | null = null;

    for (const line of contents.split(/\r?\n/)) {
      const match = line.match(assignmentRegex);
      if (!match) {
        continue;
      }

      const [, rawValue = ""] = match;
      const value = stripShellInlineComment(rawValue);
      const normalized = normalizeConfigValue(value);
      configuredValue = normalized && !hasUnresolvedShellExpression(normalized) ? normalized : null;
    }

    return configuredValue;
  } catch {
    return null;
  }
}

function extractYamlTopLevelBlock(contents: string, topLevelKey: string): string | null {
  const escapedKey = topLevelKey.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = contents.match(
    new RegExp(`(?:^|\\n)${escapedKey}:\\s*\\n((?:[ \\t]+.*(?:\\n|$))+)`, "m"),
  );
  return match?.[1] ?? null;
}

function parseGitHubHostsEntry(contents: string): AuthStatus | null {
  const block = extractYamlTopLevelBlock(contents, "github.com");
  if (!block) {
    return null;
  }

  const tokenMatch = block.match(/^[ \t]+oauth_token:\s*(["']?)([^"'\n#]+)\1\s*$/m);
  if (!hasUsableSecret(tokenMatch?.[2])) {
    return null;
  }

  const userMatch = block.match(/^[ \t]+user:\s*(["']?)([^"'\n#]+)\1\s*$/m);
  const username = userMatch?.[2]?.trim();
  return username ? { authenticated: false, configured: true, details: username } : { authenticated: false, configured: true };
}

export function createAuthChecks(overrides: Partial<AuthCheckDeps> = {}) {
  const deps: AuthCheckDeps = { ...defaultDeps, ...overrides };
  if (overrides.readFileSync && !overrides.readCredentialSnapshot) {
    deps.readCredentialSnapshot = (filePath) => overrides.readFileSync!(filePath, "utf8");
  }
  if (!overrides.commandExists) {
    deps.commandExists = (command: string) => defaultCommandExists(deps.env, command);
  }
  const homedir = deps.homedir();
  const shellConfigPaths = [
    path.join(homedir, ".zshrc.local"),
    path.join(homedir, ".zshrc"),
    path.join(homedir, ".bashrc"),
    path.join(homedir, ".profile"),
  ];
  const antigravityHome =
    deps.env.ANTIGRAVITY_HOME ?? path.join(homedir, ".gemini", "antigravity-cli");

  const credentialFileState = (filePath: string, format: CredentialService): CredentialState => {
    if (!deps.existsSync(filePath)) return "missing";
    try {
      const contents = deps.readCredentialSnapshot(filePath);
      if (contents.includes("\0") || Buffer.byteLength(contents, "utf8") > CREDENTIAL_BYTE_LIMIT) return "unknown";
      if (!contents) return "missing";
      if (format === "wrangler") return "unknown"; // OAuth TOML parsing is not claimed.
      if (format === "supabase") return candidateState(contents);
      const document: unknown = JSON.parse(contents);
      if (!document || typeof document !== "object" || Array.isArray(document) || hasNulString(document)) return "unknown";
      const object = document as Record<string, unknown>;
      if (format === "claude" || format === "gemini") {
        const oauth = format === "claude" ? object.claudeAiOauth : object;
        if (oauth != null && (typeof oauth !== "object" || Array.isArray(oauth))) return "unknown";
        const fields = (oauth ?? {}) as Record<string, unknown>;
        const access = fields[format === "claude" ? "accessToken" : "access_token"];
        const refresh = fields[format === "claude" ? "refreshToken" : "refresh_token"];
        const expiry = fields[format === "claude" ? "expiresAt" : "expiry_date"];
        if ((access != null && typeof access !== "string") || (refresh != null && typeof refresh !== "string")) return "unknown";
        const accessState = candidateState((access ?? "") as string);
        const refreshState = candidateState((refresh ?? "") as string);
        const invalidExpiry = expiry != null && (typeof expiry !== "number" || !Number.isInteger(expiry) || expiry < 0 || expiry > 253402300799999);
        if (accessState === "vault_backed" || accessState === "unknown") return accessState;
        if (accessState === "file_configured") {
          if (invalidExpiry) return "unknown";
          return typeof expiry === "number" && expiry <= deps.now() ? "expired" : "file_configured";
        }
        if (accessState === "placeholder") return "placeholder";
        if (refreshState === "vault_backed" || refreshState === "unknown") return refreshState;
        if (refreshState === "file_configured") return invalidExpiry ? "unknown" : "refresh_required";
        return refreshState;
      }
      let candidates: unknown[];
      if (format === "codex") {
        if (object.tokens != null && (typeof object.tokens !== "object" || Array.isArray(object.tokens))) return "unknown";
        const tokens = object.tokens as Record<string, unknown> | null | undefined;
        candidates = [tokens?.access_token, object.access_token, object.accessToken, object.OPENAI_API_KEY];
      } else candidates = [object.token];
      let placeholder = false;
      for (const value of candidates) {
        if (typeof value !== "string") continue;
        const state = candidateState(value);
        if (FINAL_FILE_STATES.has(state)) return state;
        switch (state) { case "placeholder": placeholder = true; }
      }
      return placeholder ? "placeholder" : "missing";
    } catch {
      return "unknown";
    }
  };

  let metadataSnapshot: Map<CredentialService, CredentialMetadata> | null = null;
  const credentialMetadata = (service: CredentialService, required = false): CredentialMetadata => {
    const captured = metadataSnapshot?.get(service);
    if (captured) return { ...captured, requirement: required ? "required" : "optional" };
    const envNames: Record<CredentialService, string[]> = {
      claude: ["ANTHROPIC_API_KEY"], codex: ["OPENAI_API_KEY"], gemini: ["GEMINI_API_KEY", "GOOGLE_API_KEY"],
      vercel: ["VERCEL_TOKEN"], supabase: ["SUPABASE_ACCESS_TOKEN"], wrangler: ["CLOUDFLARE_API_TOKEN"],
    };
    const files: Record<CredentialService, string[]> = {
      claude: [path.join(homedir, ".claude", ".credentials.json")],
      codex: [path.join(deps.env.CODEX_HOME || path.join(homedir, ".codex"), "auth.json")],
      gemini: [path.join(homedir, ".gemini", "oauth_creds.json")],
      vercel: [path.join(homedir, ".config", "vercel", "auth.json"), path.join(homedir, ".vercel", "auth.json")],
      supabase: [path.join(homedir, ".supabase", "access-token"), path.join(homedir, ".config", "supabase", "access-token")],
      wrangler: [path.join(homedir, ".config", ".wrangler", "config", "default.toml"), path.join(homedir, ".wrangler", "config", "default.toml")],
    };
    let state: CredentialState = "missing";
    let source: CredentialMetadata["source"] = "none";
    for (const name of envNames[service]) {
      const value = deps.env[name];
      if (!hasNonBlankString(value)) continue;
      state = candidateState(value);
      source = /^vault:\/\//i.test(normalizeConfigValue(value)) ? "vault" : "environment";
      switch (state) { case "file_configured": state = "shell_configured"; }
      break;
    }
    const vaultRef = deps.env[`ACFS_${service.toUpperCase()}_VAULT_REF`];
    if (source === "none" && hasNonBlankString(vaultRef)) {
      state = vaultReferenceState(vaultRef); source = "vault";
    }
    if (source === "none") {
      for (const file of files[service]) {
        const fileState = credentialFileState(file, service);
        if (READY_CREDENTIAL_STATES.has(fileState)) { state = fileState; source = "file"; break; }
        switch (state) {
          case "missing":
            switch (fileState) { case "missing": break; default: state = fileState; source = "file"; }
            break;
        }
      }
    }
    switch (state) { case "vault_backed": source = "vault"; }
    const remediation = REMEDIATION_BY_STATE[state];
    return { service, state, source, requirement: required ? "required" : "optional", authentication: "unverified", remediation };
  };

  const getCredentialStatus = (required: readonly CredentialService[] = []): CredentialReport => {
    if (required.some((service) => !CREDENTIAL_SERVICES.includes(service))) throw new Error("invalid credential requirement");
    const services = CREDENTIAL_SERVICES.map((service) => credentialMetadata(service, required.includes(service)));
    const required_unmet = services.filter((entry) => entry.requirement === "required" && !READY_CREDENTIAL_STATES.has(entry.state)).length;
    return { schema_version: 1, kind: "acfs.credential_status", status: required_unmet ? "warn" : "pass", read_only: true,
      services, summary: { required_unmet }, safety: { raw_secret_values_printed: false, files_mutated: false, provider_validation_performed: false } };
  };

  const configuredStatus = (service: CredentialService): AuthStatus => {
    const metadata = credentialMetadata(service);
    return READY_CREDENTIAL_STATES.has(metadata.state) ?
      { authenticated: false, configured: true } : { authenticated: false };
  };

  const runCommand = (
    command: string,
    options: { allowStderrFallback?: boolean } = {},
  ): string | null => {
    try {
      const output = deps.execSync(command, {
        encoding: "utf-8",
        stdio: ["ignore", "pipe", "ignore"],
        timeout: 5000,
      });
      const trimmed = output.trim();
      if (trimmed) return trimmed;

      // Some CLIs (notably `gh auth status`) write human output to stderr.
      // Only fall back to stderr capture when stdout is empty to avoid breaking
      // JSON parsing for commands that emit JSON on stdout.
      if (options.allowStderrFallback) {
        const mergedOutput = deps.execSync(`${command} 2>&1`, {
          encoding: "utf-8",
          stdio: ["ignore", "pipe", "ignore"],
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

  const getConfiguredSecret = (variableName: string, filePaths: string[] = []): string | null => {
    const envValue = deps.env[variableName];
    if (hasUsableSecret(envValue)) {
      return normalizeConfigValue(envValue);
    }
    for (const filePath of filePaths) {
      if (!deps.existsSync(filePath)) {
        continue;
      }
      const configuredValue = readConfiguredValueFromFile(
        deps.readFileSync,
        filePath,
        variableName,
      );
      if (hasUsableSecret(configuredValue)) {
        return configuredValue;
      }
    }
    return null;
  };

  const checkTailscale = (): AuthStatus => {
    if (!deps.commandExists("tailscale")) {
      return { authenticated: false };
    }
    try {
      const result = runCommand("tailscale status --json");
      if (!result) {
        return { authenticated: false };
      }
      const status = JSON.parse(result) as { BackendState?: string } | null;
      if (status?.BackendState === "Running") {
        const ip = runCommand("tailscale ip -4");
        return ip ? { authenticated: true, details: `IP: ${ip}` } : { authenticated: true };
      }
      return { authenticated: false };
    } catch {
      return { authenticated: false };
    }
  };

  const checkClaude = (): AuthStatus => {
    if (!deps.commandExists("claude")) {
      return { authenticated: false };
    }

    const candidate = configuredStatus("claude");
    if (!candidate.configured) {
      return { authenticated: false };
    }

    const configPaths = [
      path.join(homedir, ".claude", "config.json"),
      path.join(homedir, ".config", "claude", "config.json"),
    ];

    for (const configPath of configPaths) {
      if (deps.existsSync(configPath)) {
        const config = safeReadJson<{ user?: { email?: string } }>(deps.readFileSync, configPath);
        if (hasNonBlankString(config?.user?.email)) {
          return { ...candidate, details: config?.user?.email.trim() };
        }
      }
    }
    return candidate;
  };

  const checkCodex = (): AuthStatus => {
    if (!deps.commandExists("codex")) {
      return { authenticated: false };
    }

    return configuredStatus("codex");
  };

  const checkGemini = (): AuthStatus => deps.commandExists("gemini") ? configuredStatus("gemini") : { authenticated: false };

  const checkAntigravity = (): AuthStatus => {
    if (!deps.commandExists("agy")) {
      return { authenticated: false };
    }

    const tokenPath = path.join(antigravityHome, "antigravity-oauth-token");
    if (!deps.existsSync(tokenPath)) {
      return { authenticated: false };
    }
    try {
      const token = deps.readFileSync(tokenPath, "utf-8");
      if (hasUsableSecret(token)) {
        return { authenticated: false, configured: true };
      }
    } catch {
      return { authenticated: false };
    }

    return { authenticated: false };
  };

  const checkGitHub = (): AuthStatus => {
    if (deps.commandExists("gh")) {
      const output = runCommand("gh auth status -h github.com", { allowStderrFallback: true });
      if (output && output.includes("Logged in to")) {
        const match = output.match(/Logged in to .* as ([^\s]+)/i);
        return { authenticated: true, details: match?.[1] };
      }
    }

    const hostsPath = path.join(homedir, ".config", "gh", "hosts.yml");
    if (deps.existsSync(hostsPath)) {
      try {
        const contents = deps.readFileSync(hostsPath, "utf-8");
        return parseGitHubHostsEntry(contents) ?? { authenticated: false };
      } catch {
        return { authenticated: false };
      }
    }
    return { authenticated: false };
  };

  const checkVercel = (): AuthStatus => {
    const metadata = credentialMetadata("vercel");
    const state = metadata.state;
    if (ACTIVE_CREDENTIAL_SOURCES.has(metadata.source) && !READY_CREDENTIAL_STATES.has(state)) return { authenticated: false };
    if (!INTERACTIVE_CANDIDATE_STATES.has(state)) return { authenticated: false };
    if (deps.commandExists("vercel")) {
      if (getConfiguredSecret("VERCEL_TOKEN", shellConfigPaths)) {
        return { authenticated: false, configured: true, details: "via VERCEL_TOKEN" };
      }

      const output = runCommand("vercel whoami");
      if (output && !output.toLowerCase().includes("not logged")) {
        return { authenticated: true, details: output };
      }
    }

    const authPaths = [
      path.join(homedir, ".config", "vercel", "auth.json"),
      path.join(homedir, ".vercel", "auth.json"),
    ];
    for (const authPath of authPaths) {
      if (!deps.existsSync(authPath)) {
        continue;
      }
      const auth = safeReadJson<{ token?: string; user?: { email?: string } }>(
        deps.readFileSync,
        authPath,
      );
      if (hasUsableSecret(auth?.token)) {
        if (hasNonBlankString(auth?.user?.email)) {
          return { authenticated: false, configured: true, details: auth.user.email.trim() };
        }
        return { authenticated: false, configured: true };
      }
      // File exists but contains no valid token - not authenticated
    }
    return { authenticated: false };
  };

  const checkSupabase = (): AuthStatus => {
    const metadata = credentialMetadata("supabase");
    const state = metadata.state;
    if (ACTIVE_CREDENTIAL_SOURCES.has(metadata.source) && !READY_CREDENTIAL_STATES.has(state)) return { authenticated: false };
    if (!INTERACTIVE_CANDIDATE_STATES.has(state)) return { authenticated: false };
    if (getConfiguredSecret("SUPABASE_ACCESS_TOKEN", shellConfigPaths)) {
      return { authenticated: false, configured: true, details: "via SUPABASE_ACCESS_TOKEN" };
    }

    const tokenPaths = [
      path.join(homedir, ".supabase", "access-token"),
      path.join(homedir, ".config", "supabase", "access-token"),
    ];
    for (const tokenPath of tokenPaths) {
      if (!deps.existsSync(tokenPath)) {
        continue;
      }
      try {
        const token = deps.readFileSync(tokenPath, "utf-8").trim();
        if (hasUsableSecret(token)) {
          return { authenticated: false, configured: true };
        }
      } catch {}
    }
    // Note: config.toml existence alone doesn't indicate authentication
    // It's created by `supabase init` but contains no credentials
    return { authenticated: false };
  };

  const checkWrangler = (): AuthStatus => {
    const metadata = credentialMetadata("wrangler");
    const state = metadata.state;
    if (ACTIVE_CREDENTIAL_SOURCES.has(metadata.source) && !READY_CREDENTIAL_STATES.has(state)) return { authenticated: false };
    // Unsupported cached TOML remains unknown; live whoami may validate it.
    switch (state) { case "vault_backed": case "placeholder": return { authenticated: false }; }
    if (getConfiguredSecret("CLOUDFLARE_API_TOKEN", shellConfigPaths)) {
      return { authenticated: false, configured: true, details: "via CLOUDFLARE_API_TOKEN" };
    }
    if (deps.commandExists("wrangler")) {
      const output = runCommand("wrangler whoami");
      if (output) {
        if (!output.toLowerCase().includes("not authenticated")) {
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
    "claude-code": checkClaude,
    "codex-cli": checkCodex,
    "gemini-cli": checkGemini,
    "antigravity-cli": checkAntigravity,
    github: checkGitHub,
    vercel: checkVercel,
    supabase: checkSupabase,
    cloudflare: checkWrangler,
  };

  const checkAllServices = (): Record<string, AuthStatus> => {
    const results: Record<string, AuthStatus> = {};
    const report = getCredentialStatus();
    metadataSnapshot = new Map(report.services.map((entry) => [entry.service, entry]));
    try {
      for (const [id, check] of Object.entries(AUTH_CHECKS)) {
        try {
          results[id] = check();
        } catch {
          results[id] = { authenticated: false };
        }
      }
    } finally {
      metadataSnapshot = null;
    }
    const ids: Record<CredentialService, string> = { claude: "claude-code", codex: "codex-cli", gemini: "gemini-cli",
      vercel: "vercel", supabase: "supabase", wrangler: "cloudflare" };
    for (const credential of report.services) {
      results[ids[credential.service]].credential = credential;
    }
    return results;
  };

  return {
    checkTailscale,
    checkClaude,
    checkCodex,
    checkGemini,
    checkAntigravity,
    checkGitHub,
    checkVercel,
    checkSupabase,
    checkWrangler,
    AUTH_CHECKS,
    checkAllServices,
    getCredentialStatus,
  };
}

const {
  checkTailscale,
  checkClaude,
  checkCodex,
  checkGemini,
  checkAntigravity,
  checkGitHub,
  checkVercel,
  checkSupabase,
  checkWrangler,
  AUTH_CHECKS,
  checkAllServices,
  getCredentialStatus,
} = createAuthChecks();

export {
  AUTH_CHECKS,
  checkAllServices,
  checkAntigravity,
  checkClaude,
  checkCodex,
  checkGemini,
  checkGitHub,
  checkSupabase,
  checkTailscale,
  checkVercel,
  checkWrangler,
  getCredentialStatus,
};
