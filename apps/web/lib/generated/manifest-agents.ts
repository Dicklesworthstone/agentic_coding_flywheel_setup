// ============================================================
// AUTO-GENERATED FROM acfs.manifest.yaml - DO NOT EDIT DIRECTLY
// To regenerate: bun run --cwd packages/manifest generate
// ============================================================

export type ManifestAgentStatus = "default" | "optional" | "legacy";

export interface ManifestAgent {
  moduleId: string;
  displayName: string;
  vendor?: string;
  cli: string;
  aliases: string[];
  auth: string;
  docsUrl: string;
  summary: string;
  status: ManifestAgentStatus;
}

export const manifestAgents: ManifestAgent[] = [
  {
    moduleId: "agents.antigravity",
    displayName: "Antigravity CLI",
    vendor: "Google",
    cli: "agy",
    aliases: [
      "agy",
      "gmi",
    ],
    auth: "agy",
    docsUrl: "https://antigravity.google/cli",
    summary: "Google's successor to the Gemini CLI; ACFS pins its model and permissions via agy-locked.",
    status: "default",
  },
  {
    moduleId: "agents.claude",
    displayName: "Claude Code",
    vendor: "Anthropic",
    cli: "claude",
    aliases: [
      "cc",
    ],
    auth: "claude auth login",
    docsUrl: "https://docs.claude.com/en/docs/claude-code/overview",
    summary: "Long autonomous runs with deep tool use; the ACFS default driver.",
    status: "default",
  },
  {
    moduleId: "agents.codex",
    displayName: "Codex CLI",
    vendor: "OpenAI",
    cli: "codex",
    aliases: [
      "cod",
    ],
    auth: "codex login --device-auth",
    docsUrl: "https://github.com/openai/codex",
    summary: "Runs on a ChatGPT plan; --device-auth is the login path on a headless VPS.",
    status: "default",
  },
  {
    moduleId: "agents.grok",
    displayName: "Grok CLI",
    vendor: "xAI",
    cli: "grok",
    aliases: [],
    auth: "grok login",
    docsUrl: "https://x.ai/cli",
    summary: "xAI's terminal agent; also accepts GROK_DEPLOYMENT_KEY for headless use.",
    status: "optional",
  },
  {
    moduleId: "agents.omp",
    displayName: "oh-my-pi",
    cli: "omp",
    aliases: [],
    auth: "omp auth-broker login <provider>",
    docsUrl: "https://omp.sh",
    summary: "Community fork of the Pi agent with its own model roster and credential broker.",
    status: "optional",
  },
  {
    moduleId: "agents.opencode",
    displayName: "OpenCode",
    cli: "opencode",
    aliases: [],
    auth: "opencode auth login",
    docsUrl: "https://opencode.ai/docs",
    summary: "Multi-provider harness; drives Claude, GPT, and Gemini models from one TUI.",
    status: "optional",
  },
  {
    moduleId: "agents.gemini",
    displayName: "Gemini CLI",
    vendor: "Google",
    cli: "gemini",
    aliases: [],
    auth: "gemini",
    docsUrl: "https://github.com/google-gemini/gemini-cli",
    summary: "Retired upstream on 2026-06-18; kept installable for existing setups, use Antigravity instead.",
    status: "legacy",
  },
];

/** Agents installed unless explicitly skipped. */
export const defaultManifestAgents: ManifestAgent[] = manifestAgents.filter((agent) => agent.status === "default");
