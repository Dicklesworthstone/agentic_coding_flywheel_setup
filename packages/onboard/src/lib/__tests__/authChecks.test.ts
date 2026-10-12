import { describe, expect, test } from "bun:test";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as childProcess from "child_process";
import { createAuthChecks, PLACEHOLDER_SECRETS } from "../authChecks";

const HOME = "/home/tester";

type AuthCheckOverrides = NonNullable<Parameters<typeof createAuthChecks>[0]>;

const baseDeps: AuthCheckOverrides = {
  execSync: (_command: string) => {
    throw new Error("unexpected command");
  },
  existsSync: (_path: string) => false,
  readFileSync: (_path: string) => "",
  homedir: () => HOME,
  env: {} as NodeJS.ProcessEnv,
  commandExists: (_command: string) => false,
};

const makeDeps = (overrides: AuthCheckOverrides = {}) => ({
  ...baseDeps,
  ...overrides,
});

// A fixture filesystem records path-to-content mappings, just as a filesystem
// does. Filename dispatch never compares credential values or grants auth.
function fixtureFiles(entries: readonly (readonly [string, string])[]) {
  const files = new Map(entries);
  return {
    existsSync: (file: fs.PathLike) => files.has(String(file)),
    readFileSync: (file: fs.PathOrFileDescriptor) => {
      const contents = files.get(String(file));
      if (contents === undefined) throw new Error("missing fixture file");
      return contents;
    },
  };
}

function installedCommands(...names: string[]) {
  const installed = new Set(names);
  return (command: string) => installed.has(command);
}

describe("authChecks", () => {
  test("checkTailscale returns IP details when running", () => {
    const execSync = (command: string) => {
      if (command === "tailscale status --json") {
        return JSON.stringify({ BackendState: "Running" });
      }
      if (command === "tailscale ip -4") {
        return "100.64.0.12\n";
      }
      throw new Error(`unexpected command: ${command}`);
    };

    const checks = createAuthChecks(
      makeDeps({
        execSync,
        commandExists: (command) => command === "tailscale",
      }),
    );

    expect(checks.checkTailscale()).toEqual({ authenticated: true, details: "IP: 100.64.0.12" });
  });

  test("checkClaude requires OAuth credentials and returns email when config has user email", () => {
    const credentialsPath = path.join(HOME, ".claude", ".credentials.json");
    const configPath = path.join(HOME, ".claude", "config.json");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: installedCommands("claude"),
        ...fixtureFiles([[credentialsPath, JSON.stringify({ claudeAiOauth: { accessToken: "token" } })],
          [configPath, JSON.stringify({ user: { email: "user@example.com" } })]]),
      }),
    );

    expect(checks.checkClaude()).toEqual({ authenticated: false, configured: true, details: "user@example.com" });
  });

  test("checkClaude rejects config-only state without OAuth credentials", () => {
    const configPath = path.join(HOME, ".claude", "config.json");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === "claude",
        existsSync: (filePath) => filePath === configPath,
        readFileSync: () => JSON.stringify({ user: { email: "user@example.com" } }),
      }),
    );

    expect(checks.checkClaude()).toEqual({ authenticated: false });
  });

  test("checkClaude rejects blank OAuth credentials", () => {
    const credentialsPath = path.join(HOME, ".claude", ".credentials.json");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: installedCommands("claude"),
        ...fixtureFiles([[credentialsPath, JSON.stringify({ claudeAiOauth: { accessToken: "   " } })]]),
      }),
    );

    expect(checks.checkClaude()).toEqual({ authenticated: false });
  });

  test("checkClaude rejects placeholder OAuth credentials", () => {
    const credentialsPath = path.join(HOME, ".claude", ".credentials.json");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: installedCommands("claude"),
        ...fixtureFiles([[credentialsPath, JSON.stringify({ claudeAiOauth: { accessToken: "your-token-here" } })]]),
      }),
    );

    expect(checks.checkClaude()).toEqual({ authenticated: false });
  });

  test("checkClaude keeps searching config fallbacks until it finds a valid email", () => {
    const credentialsPath = path.join(HOME, ".claude", ".credentials.json");
    const primaryConfigPath = path.join(HOME, ".claude", "config.json");
    const fallbackConfigPath = path.join(HOME, ".config", "claude", "config.json");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: installedCommands("claude"),
        ...fixtureFiles([[credentialsPath, JSON.stringify({ claudeAiOauth: { accessToken: "token" } })],
          [primaryConfigPath, JSON.stringify({ user: {} })],
          [fallbackConfigPath, JSON.stringify({ user: { email: "fallback@example.com" } })]]),
      }),
    );

    expect(checks.checkClaude()).toEqual({ authenticated: false, configured: true, details: "fallback@example.com" });
  });

  test("checkClaude rejects stale credentials when claude is not installed", () => {
    const credentialsPath = path.join(HOME, ".claude", ".credentials.json");
    const checks = createAuthChecks(
      makeDeps({
        ...fixtureFiles([[credentialsPath, JSON.stringify({ claudeAiOauth: { accessToken: "token" } })]]),
      }),
    );

    expect(checks.checkClaude()).toEqual({ authenticated: false });
  });

  test("checkCodex accepts nested OAuth access token", () => {
    const authPath = path.join(HOME, ".codex", "auth.json");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === "codex",
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ tokens: { access_token: "token" } }),
      }),
    );

    expect(checks.checkCodex()).toEqual({ authenticated: false, configured: true });
  });

  test("checkCodex accepts legacy API-key auth in auth.json", () => {
    const authPath = path.join(HOME, ".codex", "auth.json");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === "codex",
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ OPENAI_API_KEY: "sk-test" }),
      }),
    );

    expect(checks.checkCodex()).toEqual({ authenticated: false, configured: true });
  });

  test("checkCodex rejects stale auth when codex is not installed", () => {
    const authPath = path.join(HOME, ".codex", "auth.json");
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ tokens: { access_token: "token" } }),
      }),
    );

    expect(checks.checkCodex()).toEqual({ authenticated: false });
  });

  test("checkCodex rejects blank auth tokens", () => {
    const authPath = path.join(HOME, ".codex", "auth.json");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === "codex",
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ OPENAI_API_KEY: "   " }),
      }),
    );

    expect(checks.checkCodex()).toEqual({ authenticated: false });
  });

  test("checkCodex rejects placeholder auth tokens", () => {
    const authPath = path.join(HOME, ".codex", "auth.json");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === "codex",
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ tokens: { access_token: "your_token_here" } }),
      }),
    );

    expect(checks.checkCodex()).toEqual({ authenticated: false });
  });

  test("checkCodex respects the injected PATH when using the default command lookup", async () => {
    const tempDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "acfs-auth-checks-"));
    const fakeCodexPath = path.join(tempDir, "codex");
    await fs.promises.writeFile(fakeCodexPath, "#!/bin/sh\nexit 0\n", "utf-8");
    await fs.promises.chmod(fakeCodexPath, 0o755);

    const authPath = path.join(HOME, ".codex", "auth.json");
    const originalPath = process.env.PATH;
    process.env.PATH = tempDir;

    try {
      const checks = createAuthChecks({
        execSync: baseDeps.execSync,
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ tokens: { access_token: "token" } }),
        homedir: () => HOME,
        env: { PATH: "", CODEX_HOME: path.join(HOME, ".codex") } as NodeJS.ProcessEnv,
      });

      expect(checks.checkCodex()).toEqual({ authenticated: false });
    } finally {
      process.env.PATH = originalPath;
      // Retain the isolated fixture for diagnosis; repository policy forbids deletion.
    }
  });

  test("checkAntigravity reports configured when the Antigravity OAuth token exists", () => {
    const tokenPath = path.join(HOME, ".gemini", "antigravity-cli", "antigravity-oauth-token");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === "agy",
        existsSync: (filePath) => filePath === tokenPath,
        readFileSync: (filePath) => (filePath === tokenPath ? "antigravity-token" : ""),
      }),
    );

    expect(checks.checkAntigravity()).toEqual({ authenticated: false, configured: true });
  });

  test("checkAntigravity rejects placeholder Antigravity token values", () => {
    const tokenPath = path.join(HOME, ".gemini", "antigravity-cli", "antigravity-oauth-token");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === "agy",
        existsSync: (filePath) => filePath === tokenPath,
        readFileSync: (filePath) => (filePath === tokenPath ? "your-token-here" : ""),
      }),
    );

    expect(checks.checkAntigravity()).toEqual({ authenticated: false });
  });

  test("checkAntigravity rejects stale credentials when agy is not installed", () => {
    const tokenPath = path.join(HOME, ".gemini", "antigravity-cli", "antigravity-oauth-token");
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === tokenPath,
        readFileSync: (filePath) => (filePath === tokenPath ? "antigravity-token" : ""),
      }),
    );

    expect(checks.checkAntigravity()).toEqual({ authenticated: false });
  });

  test("checkAntigravity respects ANTIGRAVITY_HOME when locating the OAuth token", () => {
    const antigravityHome = "/tmp/antigravity-home";
    const tokenPath = path.join(antigravityHome, "antigravity-oauth-token");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === "agy",
        env: { ANTIGRAVITY_HOME: antigravityHome } as NodeJS.ProcessEnv,
        existsSync: (filePath) => filePath === tokenPath,
        readFileSync: (filePath) => (filePath === tokenPath ? "antigravity-token" : ""),
      }),
    );

    expect(checks.checkAntigravity()).toEqual({ authenticated: false, configured: true });
  });

  test("checkGitHub reads gh auth status when available", () => {
    const execSync = (command: string) => {
      if (command === "gh auth status -h github.com") {
        return "Logged in to github.com as octocat";
      }
      throw new Error(`unexpected command: ${command}`);
    };

    const checks = createAuthChecks(
      makeDeps({
        execSync,
        commandExists: (command) => command === "gh",
      }),
    );

    expect(checks.checkGitHub()).toEqual({ authenticated: true, details: "octocat" });
  });

  test("checkGitHub falls back to the github.com hosts entry when gh is unavailable", () => {
    const hostsPath = path.join(HOME, ".config", "gh", "hosts.yml");
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === hostsPath,
        readFileSync: () =>
          [
            "github.com:",
            "    oauth_token: gho_testtoken",
            "    user: octocat",
            "    git_protocol: https",
            "example.internal:",
            "    oauth_token: ignored",
            "    user: enterprise-user",
          ].join("\n"),
      }),
    );

    expect(checks.checkGitHub()).toEqual({ authenticated: false, configured: true, details: "octocat" });
  });

  test("checkGitHub rejects hosts files without a github.com oauth token", () => {
    const hostsPath = path.join(HOME, ".config", "gh", "hosts.yml");
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === hostsPath,
        readFileSync: () =>
          [
            "github.com:",
            "    user: octocat",
            "example.internal:",
            "    oauth_token: valid-enterprise-token",
            "    user: enterprise-user",
          ].join("\n"),
      }),
    );

    expect(checks.checkGitHub()).toEqual({ authenticated: false });
  });

  test("checkGitHub rejects placeholder oauth tokens in hosts.yml", () => {
    const hostsPath = path.join(HOME, ".config", "gh", "hosts.yml");
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === hostsPath,
        readFileSync: () =>
          ["github.com:", "    oauth_token: your_github_token", "    user: octocat"].join("\n"),
      }),
    );

    expect(checks.checkGitHub()).toEqual({ authenticated: false });
  });

  test("checkVercel reports configured with legacy ~/.vercel/auth.json token", () => {
    const authPath = path.join(HOME, ".vercel", "auth.json");
    const validVercelCredential = ["vercel", "credential"].join("-");
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () =>
          JSON.stringify({ token: validVercelCredential, user: { email: "me@example.com" } }),
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false, configured: true, details: "me@example.com" });
  });

  test("checkVercel rejects auth.json without a token", () => {
    const authPath = path.join(HOME, ".vercel", "auth.json");
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ user: { email: "me@example.com" } }),
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test("checkVercel reports configured with VERCEL_TOKEN env var", () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { VERCEL_TOKEN: "token-123" } as NodeJS.ProcessEnv,
        commandExists: (command) => command === "vercel",
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false, configured: true, details: "via VERCEL_TOKEN" });
  });

  test("checkVercel rejects blank VERCEL_TOKEN values", () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { VERCEL_TOKEN: "   " } as NodeJS.ProcessEnv,
        commandExists: (command) => command === "vercel",
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test("checkVercel rejects placeholder VERCEL_TOKEN values", () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { VERCEL_TOKEN: "your-token-here" } as NodeJS.ProcessEnv,
        commandExists: (command) => command === "vercel",
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test("checkVercel rejects placeholder auth.json tokens", () => {
    const authPath = path.join(HOME, ".config", "vercel", "auth.json");
    const placeholderVercelCredential = ["your", "vercel", "token"].join("_");
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === authPath,
        readFileSync: () => JSON.stringify({ token: placeholderVercelCredential }),
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test("checkVercel uses the last shell config assignment for token values", () => {
    const configPath = path.join(HOME, ".zshrc.local");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === "vercel",
        existsSync: (filePath) => filePath === configPath,
        readFileSync: () =>
          ["export VERCEL_TOKEN=your_vercel_token", "export VERCEL_TOKEN=vercel-token"].join("\n"),
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false, configured: true, details: "via VERCEL_TOKEN" });
  });

  test("checkVercel rejects shell config tokens overwritten by placeholders", () => {
    const configPath = path.join(HOME, ".zshrc.local");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === "vercel",
        existsSync: (filePath) => filePath === configPath,
        readFileSync: () =>
          ["export VERCEL_TOKEN=vercel-token", "export VERCEL_TOKEN=your_vercel_token"].join("\n"),
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test.each([
    "$VERCEL_TOKEN",
    '"${VERCEL_TOKEN:-fallback}"',
    "$(read-token)",
    "`read-token`",
  ])("checkVercel rejects unresolved shell config expression: %s", (expression) => {
    const assignment = `export VERCEL_TOKEN=${expression}`;
    const configPath = path.join(HOME, ".zshrc.local");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === "vercel",
        existsSync: (filePath) => filePath === configPath,
        readFileSync: () => assignment,
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test("checkVercel treats a later unresolved shell expression as the effective assignment", () => {
    const configPath = path.join(HOME, ".zshrc.local");
    const checks = createAuthChecks(
      makeDeps({
        commandExists: (command) => command === "vercel",
        existsSync: (filePath) => filePath === configPath,
        readFileSync: () =>
          ["export VERCEL_TOKEN=vercel-token", "export VERCEL_TOKEN=$LATER_TOKEN"].join("\n"),
      }),
    );

    expect(checks.checkVercel()).toEqual({ authenticated: false });
  });

  test("checkSupabase reports configured with access token file", () => {
    const tokenPath = path.join(HOME, ".supabase", "access-token");
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === tokenPath,
        readFileSync: () => "token-value",
      }),
    );

    expect(checks.checkSupabase()).toEqual({ authenticated: false, configured: true });
  });

  test("checkSupabase uses SUPABASE_ACCESS_TOKEN when set", () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { SUPABASE_ACCESS_TOKEN: "token" } as NodeJS.ProcessEnv,
      }),
    );

    expect(checks.checkSupabase()).toEqual({
      authenticated: false,
      configured: true,
      details: "via SUPABASE_ACCESS_TOKEN",
    });
  });

  test("checkSupabase rejects blank SUPABASE_ACCESS_TOKEN values", () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { SUPABASE_ACCESS_TOKEN: "   " } as NodeJS.ProcessEnv,
      }),
    );

    expect(checks.checkSupabase()).toEqual({ authenticated: false });
  });

  test("checkSupabase rejects placeholder SUPABASE_ACCESS_TOKEN values", () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { SUPABASE_ACCESS_TOKEN: "YOUR_SUPABASE_ACCESS_TOKEN" } as NodeJS.ProcessEnv,
      }),
    );

    expect(checks.checkSupabase()).toEqual({ authenticated: false });
  });

  test("checkSupabase rejects placeholder access token files", () => {
    const tokenPath = path.join(HOME, ".supabase", "access-token");
    const checks = createAuthChecks(
      makeDeps({
        existsSync: (filePath) => filePath === tokenPath,
        readFileSync: () => "your_supabase_access_token",
      }),
    );

    expect(checks.checkSupabase()).toEqual({ authenticated: false });
  });

  test("checkWrangler reads email from whoami output", () => {
    const execSync = (command: string) => {
      if (command === "wrangler whoami") {
        return "email: dev@example.com\n";
      }
      throw new Error(`unexpected command: ${command}`);
    };

    const checks = createAuthChecks(
      makeDeps({
        execSync,
        commandExists: (command) => command === "wrangler",
      }),
    );

    expect(checks.checkWrangler()).toEqual({ authenticated: true, details: "dev@example.com" });
  });

  test("checkWrangler rejects blank CLOUDFLARE_API_TOKEN values", () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { CLOUDFLARE_API_TOKEN: "   " } as NodeJS.ProcessEnv,
      }),
    );

    expect(checks.checkWrangler()).toEqual({ authenticated: false });
  });

  test("checkWrangler rejects placeholder CLOUDFLARE_API_TOKEN values", () => {
    const checks = createAuthChecks(
      makeDeps({
        env: { CLOUDFLARE_API_TOKEN: "your-token-here" } as NodeJS.ProcessEnv,
      }),
    );

    expect(checks.checkWrangler()).toEqual({ authenticated: false });
  });

  test("checkAllServices exposes all expected service ids", () => {
    const checks = createAuthChecks(makeDeps());
    const ids = Object.keys(checks.AUTH_CHECKS).sort();
    expect(ids).toEqual(
      [
        "tailscale",
        "claude-code",
        "codex-cli",
        "gemini-cli",
        "antigravity-cli",
        "github",
        "vercel",
        "supabase",
        "cloudflare",
      ].sort(),
    );
  });
});

describe("placeholder secret vocabulary", () => {
  // The same list is copied into three shell entry points; services-setup's
  // copy had silently dropped "your-gemini-api-key", so it accepted a value
  // doctor and onboarding rejected.
  const repoRoot = path.resolve(import.meta.dir, "../../../../..");

  async function shellPlaceholders(file: string, fn: string): Promise<string[]> {
    const text = await fs.promises.readFile(path.join(repoRoot, file), "utf8");
    const start = text.indexOf(`\n${fn}() {\n`);
    expect(start).toBeGreaterThan(-1);
    const body = text.slice(start, text.indexOf("\n}\n", start));
    const match = body.match(/case "\$normalized" in\n\s*([^\n]+)\)\n/);
    expect(match).not.toBeNull();
    return match![1].split("|").map((entry) => entry.replace(/^"(.*)"$/, "$1"));
  }

  test.each([
    ["scripts/lib/doctor.sh", "is_placeholder_secret"],
    ["packages/onboard/onboard.sh", "is_placeholder_secret"],
    ["scripts/services-setup.sh", "services_setup_is_placeholder_secret"],
  ])("%s %s matches authChecks.ts", async (file, fn) => {
    expect((await shellPlaceholders(file, fn)).sort()).toEqual([...PLACEHOLDER_SECRETS].sort());
  });
});

describe("passive credential lifecycle parity", () => {
  const repoRoot = path.resolve(import.meta.dir, "../../../../..");
  const vaultRef = "vault://secret/fixture-private-path#fixture-private-field";
  const knownEnv = ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY", "VERCEL_TOKEN",
    "SUPABASE_ACCESS_TOKEN", "CLOUDFLARE_API_TOKEN", "CODEX_HOME", ...["CLAUDE", "CODEX", "GEMINI", "VERCEL", "SUPABASE", "WRANGLER"].map((id) => `ACFS_${id}_VAULT_REF`)];
  const scenarios: { name: string; file?: string; contents?: string; env?: NodeJS.ProcessEnv;
    service: "claude" | "codex" | "gemini" | "vercel" | "supabase" | "wrangler"; state: string }[] = [
    { name: "optional missing", service: "claude", state: "missing" },
    { name: "empty credential file", service: "supabase", state: "missing", file: ".supabase/access-token", contents: "" },
    { name: "exported key", service: "claude", state: "shell_configured", env: { ANTHROPIC_API_KEY: "fixture-private-key" } },
    { name: "quoted placeholder", service: "vercel", state: "placeholder", env: { VERCEL_TOKEN: '"your_vercel_token"' } },
    { name: "quoted empty export", service: "vercel", state: "missing", env: { VERCEL_TOKEN: '""' } },
    { name: "expired Claude", service: "claude", state: "expired", file: ".claude/.credentials.json", contents: '{"claudeAiOauth":{"accessToken":"fixture-private-key","expiresAt":0}}' },
    { name: "future Claude", service: "claude", state: "file_configured", file: ".claude/.credentials.json", contents: '{"claudeAiOauth":{"accessToken":"fixture-private-key","expiresAt":4102444800000}}' },
    { name: "refresh-only Claude", service: "claude", state: "refresh_required", file: ".claude/.credentials.json", contents: '{"claudeAiOauth":{"refreshToken":"fixture-private-key"}}' },
    { name: "expired Gemini", service: "gemini", state: "expired", file: ".gemini/oauth_creds.json", contents: '{"access_token":"fixture-private-key","expiry_date":0}' },
    { name: "refresh-only Gemini", service: "gemini", state: "refresh_required", file: ".gemini/oauth_creds.json", contents: '{"refresh_token":"fixture-private-key"}' },
    { name: "invalid expiry", service: "gemini", state: "unknown", file: ".gemini/oauth_creds.json", contents: '{"access_token":"fixture-private-key","expiry_date":"4102444800000"}' },
    { name: "fraction expiry", service: "gemini", state: "unknown", file: ".gemini/oauth_creds.json", contents: '{"access_token":"fixture-private-key","expiry_date":0.5}' },
    { name: "null expiry", service: "gemini", state: "file_configured", file: ".gemini/oauth_creds.json", contents: '{"access_token":"fixture-private-key","expiry_date":null}' },
    { name: "wrong token type", service: "claude", state: "unknown", file: ".claude/.credentials.json", contents: '{"claudeAiOauth":{"accessToken":42}}' },
    { name: "malformed token container", service: "codex", state: "unknown", file: ".codex/auth.json", contents: '{"tokens":"fixture-private-key"}' },
    { name: "cached Codex", service: "codex", state: "file_configured", file: ".codex/auth.json", contents: '{"tokens":{"access_token":"fixture-private-key"}}' },
    { name: "cached Vercel", service: "vercel", state: "file_configured", file: ".vercel/auth.json", contents: '{"token":"fixture-private-key"}' },
    { name: "plain Supabase", service: "supabase", state: "file_configured", file: ".supabase/access-token", contents: "fixture-private-key\n" },
    { name: "unsupported Wrangler", service: "wrangler", state: "unknown", file: ".wrangler/config/default.toml", contents: 'oauth_token="fixture-private-key"' },
    { name: "multiple JSON documents", service: "codex", state: "unknown", file: ".codex/auth.json", contents: '{"access_token":"fixture-private-key"}\n{}' },
    { name: "raw NUL", service: "codex", state: "unknown", file: ".codex/auth.json", contents: '{"access_token":"fixture-private-key"}\0' },
    { name: "escaped NUL", service: "vercel", state: "unknown", file: ".vercel/auth.json", contents: '{"token":"fixture-private\\u0000-key"}' },
    { name: "oversized newlines", service: "supabase", state: "unknown", file: ".supabase/access-token", contents: "\n".repeat(1048577) },
    { name: "Vault annotation", service: "claude", state: "vault_backed", env: { ACFS_CLAUDE_VAULT_REF: vaultRef } },
    { name: "quoted Vault annotation", service: "supabase", state: "vault_backed", env: { ACFS_SUPABASE_VAULT_REF: `"${vaultRef}"` } },
    { name: "Vault token literal", service: "codex", state: "vault_backed", env: { OPENAI_API_KEY: vaultRef } },
    { name: "Vault file literal", service: "supabase", state: "vault_backed", file: ".supabase/access-token", contents: vaultRef },
    { name: "embedded LF in Vault JSON literal", service: "codex", state: "unknown", file: ".codex/auth.json", contents: JSON.stringify({ access_token: `${vaultRef}\nfixture-private-extra` }) },
    { name: "Vault OAuth literal", service: "gemini", state: "vault_backed", file: ".gemini/oauth_creds.json", contents: JSON.stringify({ access_token: vaultRef }) },
    { name: "invalid Vault traversal", service: "vercel", state: "unknown", env: { ACFS_VERCEL_VAULT_REF: "vault://secret/../private#token" } },
    { name: "invalid Vault placeholder", service: "vercel", state: "unknown", env: { ACFS_VERCEL_VAULT_REF: "vault://secret/your_token#token" } },
    { name: "invalid Vault credentials", service: "vercel", state: "unknown", env: { ACFS_VERCEL_VAULT_REF: "vault://user:password@private/path#token" } },
    { name: "invalid Vault expression", service: "vercel", state: "unknown", env: { ACFS_VERCEL_VAULT_REF: "$(touch fixture-private-marker)" } },
    { name: "materialized key overrides Vault", service: "claude", state: "shell_configured", env: { ANTHROPIC_API_KEY: "fixture-private-key", ACFS_CLAUDE_VAULT_REF: vaultRef } },
    { name: "placeholder shadows Vault and cached file", service: "vercel", state: "placeholder", env: { VERCEL_TOKEN: "your_vercel_token", ACFS_VERCEL_VAULT_REF: vaultRef }, file: ".vercel/auth.json", contents: '{"token":"fixture-private-key"}' },
    { name: "Vault annotation shadows cached file", service: "vercel", state: "vault_backed", env: { ACFS_VERCEL_VAULT_REF: vaultRef }, file: ".vercel/auth.json", contents: '{"token":"fixture-private-key"}' },
  ];

  test.each(scenarios)("$name: actual file/environment reports match Bash", async (scenario) => {
    const home = await fs.promises.mkdtemp(path.join(os.tmpdir(), "acfs-credential-parity-"));
    const env: NodeJS.ProcessEnv = { ...process.env, ...scenario.env, HOME: home };
    for (const key of knownEnv) if (!(key in (scenario.env ?? {}))) delete env[key];
    if (scenario.file) {
      const file = path.join(home, scenario.file);
      await fs.promises.mkdir(path.dirname(file), { recursive: true });
      await fs.promises.writeFile(file, scenario.contents!);
    }
    let invoked = false;
    const checks = createAuthChecks({ homedir: () => home, env, execSync: () => { invoked = true; throw new Error("provider invocation forbidden"); } });
    const report = checks.getCredentialStatus([scenario.service, scenario.service]);
    const shell = childProcess.execFileSync(env.ACFS_TEST_BASH ?? "/usr/bin/bash", ["-c",
      'source "$1" >/dev/null || exit 2; TARGET_HOME="$2"; SERVICES_SETUP_REQUIRED=("$3" "$3"); services_setup_credential_status_json || [[ $? == 1 ]]',
      "_", path.join(repoRoot, "scripts/services-setup.sh"), home, scenario.service], { env, encoding: "utf8", timeout: 10000 });
    let bashReport: unknown;
    try { bashReport = JSON.parse(shell); }
    catch (error) { throw new Error("Bash credential report is not valid JSON", { cause: error }); }
    expect(report).toEqual(bashReport);
    expect(report.services.find((entry) => entry.service === scenario.service)?.state).toBe(scenario.state);
    expect(report.summary.required_unmet).toBe(["shell_configured", "file_configured"].includes(scenario.state) ? 0 : 1);
    expect(JSON.stringify(report)).not.toContain("fixture-private");
    expect(invoked).toBe(false);
    if (scenario.file) expect(await fs.promises.readFile(path.join(home, scenario.file), "utf8")).toBe(scenario.contents!);
  });

  test("CODEX_HOME and normal TypeScript consumers use canonical source metadata", async () => {
    const home = await fs.promises.mkdtemp(path.join(os.tmpdir(), "acfs-credential-consumer-"));
    const codexHome = path.join(home, "custom-codex");
    await fs.promises.mkdir(codexHome);
    await fs.promises.writeFile(path.join(codexHome, "auth.json"), '{"tokens":{"access_token":"fixture-private-key"}}');
    const checks = createAuthChecks({ homedir: () => home, env: { CODEX_HOME: codexHome }, commandExists: (name) => name === "codex" });
    expect(checks.checkCodex()).toEqual({ authenticated: false, configured: true });
    expect(checks.checkAllServices()["codex-cli"]).toEqual({ authenticated: false, configured: true,
      credential: { service: "codex", state: "file_configured", source: "file", requirement: "optional", authentication: "unverified", remediation: "validate_before_use" } });
  });

  test.each(["expired", "refresh_required", "vault_backed"])("normal Claude check rejects %s readiness", async (state) => {
    const home = await fs.promises.mkdtemp(path.join(os.tmpdir(), "acfs-credential-attention-"));
    await fs.promises.mkdir(path.join(home, ".claude"));
    await fs.promises.writeFile(path.join(home, ".claude", ".credentials.json"), state === "refresh_required" ?
      '{"claudeAiOauth":{"refreshToken":"fixture-private-key"}}' : '{"claudeAiOauth":{"accessToken":"fixture-private-key","expiresAt":0}}');
    const checks = createAuthChecks({ homedir: () => home, env: state === "vault_backed" ? { ACFS_CLAUDE_VAULT_REF: vaultRef } : {}, commandExists: () => true });
    expect(checks.checkClaude()).toEqual({ authenticated: false });
  });

  test("checkAllServices derives metadata and readiness from one credential snapshot", () => {
    let reads = 0;
    const file = path.join(HOME, ".claude", ".credentials.json");
    const snapshots = [4102444800000, 0].map((expiresAt) => JSON.stringify({ claudeAiOauth: { accessToken: "fixture-private-key", expiresAt } }));
    const checks = createAuthChecks(makeDeps({ existsSync: (candidate) => candidate === file,
      commandExists: (command) => command === "claude",
      readFileSync: () => {
        reads += 1;
        const snapshot = snapshots.shift();
        if (snapshot === undefined) throw new Error("credential snapshot read more than expected");
        return snapshot;
      } }));
    const result = checks.checkAllServices()["claude-code"];
    expect(reads).toBe(1);
    expect(result.configured).toBe(true);
    expect(result.authenticated).toBe(false);
    expect(result.credential?.state).toBe("file_configured");
    expect(checks.getCredentialStatus().services[0].state).toBe("expired");
  });

  test.each(["vercel", "supabase", "wrangler"])("%s does not fall back around an active quoted-empty export", (service) => {
    const variable = { vercel: "VERCEL_TOKEN", supabase: "SUPABASE_ACCESS_TOKEN", wrangler: "CLOUDFLARE_API_TOKEN" }[service]!;
    const checks = createAuthChecks(makeDeps({ env: { [variable]: '""' }, commandExists: () => true,
      existsSync: (file) => file === path.join(HOME, ".zshrc.local"),
      readFileSync: () => `export ${variable}=fixture-private-key` }));
    const check = { vercel: checks.checkVercel, supabase: checks.checkSupabase, wrangler: checks.checkWrangler }[service]!;
    expect(check()).toEqual({ authenticated: false });
  });

  test("a directory at the credential-file location is missing rather than configured", async () => {
    const home = await fs.promises.mkdtemp(path.join(os.tmpdir(), "acfs-credential-directory-"));
    await fs.promises.mkdir(path.join(home, ".supabase", "access-token"), { recursive: true });
    const checks = createAuthChecks({ homedir: () => home, env: {} });
    expect(checks.getCredentialStatus(["supabase"]).services.find((entry) => entry.service === "supabase")?.state).toBe("missing");
  });
});
