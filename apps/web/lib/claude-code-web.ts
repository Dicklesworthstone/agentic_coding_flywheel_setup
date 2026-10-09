/**
 * Content for /cloud-agents: prebuilt tools and provider-specific cloud recipes.
 * The installer retains its original filename; its generic mode is agent-neutral.
 *
 * The script is the source of truth. claude-code-web.test.ts parses it and
 * fails if the tool list, option defaults, or script URL here drift from it,
 * or if the README stops showing the same setup script.
 */

export const CLAUDE_CODE_WEB_SCRIPT_PATH = "scripts/claude-code-web-setup.sh";

export const CLAUDE_CODE_WEB_SCRIPT_URL = `https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/${CLAUDE_CODE_WEB_SCRIPT_PATH}`;

export const CLAUDE_CODE_WEB_SCRIPT_SOURCE_URL = `https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/blob/main/${CLAUDE_CODE_WEB_SCRIPT_PATH}`;

/** What to paste into the environment dialog's "Setup script" field. */
export const CLAUDE_CODE_WEB_SETUP_SCRIPT = `#!/bin/bash\ncurl -fsSL ${CLAUDE_CODE_WEB_SCRIPT_URL} | bash`;

export const CLAUDE_CODE_WEB_DOCS_URL = "https://code.claude.com/docs/en/cloud-environments";

export const CODEX_CLOUD_DOCS_URL = "https://learn.chatgpt.com/docs/environments/cloud-environments";
export const CODEX_CLOUD_SETUP_SCRIPT = `#!/bin/bash\nset -o pipefail\nacfs_cloud_root="$(git rev-parse --show-toplevel)" || exit 1\ncurl -fsSL ${CLAUDE_CODE_WEB_SCRIPT_URL} | ACFS_CLOUD_SKILL_DIR="$acfs_cloud_root/.agents/skills/acfs-cloud-tools" ACFS_CLOUD_AGENT=codex ACFS_CLOUD_ROOT="$acfs_cloud_root/.acfs-cloud" bash || exit 1\nprintf '/.acfs-cloud/\\n/.agents/skills/acfs-cloud-tools/\\n' >> "$(git rev-parse --git-path info/exclude)"`;
export const CODEX_CLOUD_START_SKILL = `Find the repository root with git rev-parse --show-toplevel.
Read <repo>/.acfs-cloud/.codex/AGENTS.md for the installed flywheel tools and <repo>/.acfs-cloud/.acfs/cloud/setup.log for failures.
In each task shell, run acfs_cloud_root="$(git rev-parse --show-toplevel)/.acfs-cloud"; export PATH="$acfs_cloud_root/.local/bin:$PATH" before using the tools.
Follow the guide's JFP_HOME export in each task shell so JFP caches prompts in the writable workspace; preserve an existing JFP_HOME and keep any XDG_CONFIG_HOME writable.
Check br --version, bv --version, ubs --version and jsm --version before starting work.
Use br ready --json and bv --robot-triage; never open their interactive TUIs.`;

export const GENERIC_CLOUD_SETUP_SCRIPT = `#!/bin/bash\nset -o pipefail\ncurl -fsSL ${CLAUDE_CODE_WEB_SCRIPT_URL} | ACFS_CLOUD_AGENT=generic bash`;
export const GENERIC_CLOUD_TASK_INSTRUCTIONS = `Read $HOME/.acfs/cloud/AGENTS.md and $HOME/.acfs/cloud/setup.log before starting work.
In each task shell, run export PATH="$HOME/.local/bin:$PATH".
If using a custom writable data root, follow the guide's JFP_HOME export in each task shell; preserve an existing JFP_HOME and keep any XDG_CONFIG_HOME writable.
Check br --version, bv --version, ubs --version and jsm --version; report missing tools from the setup log.
Use the existing repository tracker with br ready --json and bv --robot-triage. Never open their interactive TUIs.
Agent Mail is available as a CLI. This setup does not configure this agent's MCP servers.`;

export const CLOUD_AGENT_ROUTE = "/cloud-agents";
export const CLOUD_AGENT_RESEARCH_DATE = "2026-10-08";
export type CloudAgent = {
  id: string;
  name: string;
  initials: string;
  evidence: "Hosted test" | "Documented workflow" | "Needs investigation" | "Linux template";
  summary: string;
  caveat: string;
  docs: string;
  script?: string;
  instructions?: string;
};

export const CLOUD_AGENTS: CloudAgent[] = [
  {
    id: "claude", name: "Claude Code", initials: "CC", evidence: "Hosted test",
    summary: "Install once in the environment. Claude loads the tool guide and starts Agent Mail on demand.",
    caveat: "Full and default Trusted hosted runs installed all eleven executables and passed Agent Mail MCP health. The cold Trusted run took 53 seconds using verified public fallbacks. Organization policies may still block those downloads; inspect the setup summary.",
    docs: CLAUDE_CODE_WEB_DOCS_URL, script: CLAUDE_CODE_WEB_SETUP_SCRIPT,
  },
  {
    id: "codex", name: "ChatGPT / Codex", initials: "CX", evidence: "Hosted test",
    summary: "Keep the tools in the writable repository workspace, then load their guide in each task.",
    caveat: "Fresh hosted tasks reused all eleven executables. Automatic Start/repository-skill discovery did not work in those tests. Explicit guide loading is required; hosted MCP is not configured.",
    docs: CODEX_CLOUD_DOCS_URL, script: CODEX_CLOUD_SETUP_SCRIPT, instructions: CODEX_CLOUD_START_SKILL,
  },
  {
    id: "amp", name: "Amp Orbs", initials: "AO", evidence: "Documented workflow",
    summary: "Use the project snapshot's setup phase to prepare tools before an orb starts.",
    caveat: "Amp documents Debian 12 orbs. These bundles were tested on Ubuntu 24.04; Debian library compatibility and hosted persistence have not been accepted. Unavailable binaries are reported without source builds.",
    docs: "https://ampcode.com/docs/orbs/customizing", script: GENERIC_CLOUD_SETUP_SCRIPT, instructions: GENERIC_CLOUD_TASK_INSTRUCTIONS,
  },
  {
    id: "devin", name: "Devin", initials: "DV", evidence: "Documented workflow",
    summary: "Include prebuilt tools in a Linux environment blueprint and reuse its snapshot.",
    caveat: "Devin documents Linux snapshots, run steps and knowledge entries. This ACFS recipe has not been tested in Devin; check CPU architecture and runtime libraries first. macOS and Windows blueprints are outside this bundle target.",
    docs: "https://docs.devin.ai/onboard-devin/environment/blueprints", script: GENERIC_CLOUD_SETUP_SCRIPT, instructions: GENERIC_CLOUD_TASK_INSTRUCTIONS,
  },
  {
    id: "grok", name: "Grok Bot", initials: "GB", evidence: "Documented workflow",
    summary: "Enterprise Team Setup runs shell scripts on every team member's cloud computer.",
    caveat: "Team Setup is Enterprise-only and runs scripts as the computer user on Linux team computers. ACFS has not been accepted there. Grok Bot, the Grok Build CLI and chat Build Mode are different integration surfaces.",
    docs: "https://docs.x.ai/grok-bot/private-networks", script: GENERIC_CLOUD_SETUP_SCRIPT, instructions: GENERIC_CLOUD_TASK_INSTRUCTIONS,
  },
  {
    id: "muse", name: "Meta Muse", initials: "MM", evidence: "Needs investigation",
    summary: "Muse has a persistent Linux cloud computer; an ACFS setup hook has not been established.",
    caveat: "No Muse hosted install or supported startup hook has been verified. Muse Code is Meta's separate terminal/CI agent; its Linux CLI is not evidence that the personal Muse VM supports this setup.",
    docs: "https://research.meta.ai/blog/security-and-safety-for-ai-agents-our-approach-with-muse",
  },
  {
    id: "generic", name: "Other Linux agent", initials: "SH", evidence: "Linux template",
    summary: "A provider-neutral guide for a cloud machine where you can run shell commands.",
    caveat: "Ubuntu 24.04 is the tested OS. Other images and CPUs need version checks. With ACFS_CLOUD_ROOT, substitute that root for $HOME in the task instructions. No agent configuration or MCP registration is changed.",
    docs: CLAUDE_CODE_WEB_SCRIPT_SOURCE_URL, script: GENERIC_CLOUD_SETUP_SCRIPT, instructions: GENERIC_CLOUD_TASK_INSTRUCTIONS,
  },
];

/**
 * The selected agent's own recipe, installing only `tools`. Keeping the
 * recipe's ACFS_CLOUD_AGENT means a Claude user never copies generic mode
 * (which skips CLAUDE.md and MCP registration) by accident.
 */
export function cloudSubsetRecipe(agentId: string, tools = "br bv am ubs"): string {
  const script = CLOUD_AGENTS.find((agent) => agent.id === agentId)?.script ?? GENERIC_CLOUD_SETUP_SCRIPT;
  return script.replace(" | ", ` | ACFS_CLOUD_TOOLS="${tools}" `);
}

export type ClaudeCodeWebToolGroup = "Plan" | "Coordinate" | "Check" | "Remember" | "Skills";

export type ClaudeCodeWebTool = {
  /** Tool id as the script's ACFS_CLOUD_TOOLS spells it. */
  id: string;
  name: string;
  command: string;
  role: string;
  group: ClaudeCodeWebToolGroup;
  /** Extra executables the same bundle puts on PATH. */
  alsoInstalls?: string[];
};

/** In the script's default install order. */
export const CLAUDE_CODE_WEB_TOOLS: ClaudeCodeWebTool[] = [
  {
    id: "br",
    name: "BeadsRust",
    command: "br",
    role: "Dependency-aware issues that live in the repo's .beads/ and travel with the code.",
    group: "Plan",
  },
  {
    id: "bv",
    name: "Beads Viewer",
    command: "bv --robot-triage",
    role: "Graph-aware triage: what to work on next and what it unblocks.",
    group: "Plan",
  },
  {
    id: "am",
    name: "MCP Agent Mail",
    command: "am",
    role: "Agent messaging and file reservations. Claude gets stdio MCP registration; other agents get CLI access.",
    group: "Coordinate",
    alsoInstalls: ["mcp-agent-mail"],
  },
  {
    id: "ubs",
    name: "Ultimate Bug Scanner",
    command: "ubs <files>",
    role: "Scans changed files for bugs before every commit.",
    group: "Check",
  },
  {
    id: "cass",
    name: "Session Search",
    command: 'cass search "query" --robot',
    role: "Searches the agent session history on this VM.",
    group: "Remember",
  },
  {
    id: "cm",
    name: "CASS Memory",
    command: 'cm context "task" --json',
    role: "Procedural memory pulled in before a task starts.",
    group: "Remember",
  },
  {
    id: "ms",
    name: "Meta Skill",
    command: "ms",
    role: "Local skill search and management.",
    group: "Skills",
  },
  {
    id: "ast-grep",
    name: "ast-grep",
    command: "ast-grep",
    role: "Structural code search and UBS scan dependency.",
    group: "Check",
  },
  {
    id: "jsm",
    name: "Jeffrey's Skills",
    command: "jsm",
    role: "Skill manager for the jeffreys-skills.md library.",
    group: "Skills",
  },
  {
    id: "jfp",
    name: "JeffreysPrompts",
    command: "jfp",
    role: "The battle-tested prompt library, from the terminal.",
    group: "Skills",
  },
];

/** Every command the default bundle puts on PATH (Agent Mail ships two). */
export const CLOUD_EXECUTABLES: string[] = CLAUDE_CODE_WEB_TOOLS.flatMap((tool) => [
  tool.command.split(" ")[0],
  ...(tool.alsoInstalls ?? []),
]);

export type ClaudeCodeWebOption = {
  name: string;
  defaultValue: string;
  effect: string;
};

export const CLAUDE_CODE_WEB_OPTIONS: ClaudeCodeWebOption[] = [
  {
    name: "ACFS_CLOUD_AGENT",
    defaultValue: "claude",
    effect: "claude writes ~/.claude/CLAUDE.md and registers stdio MCP; codex writes a Codex guide; generic writes .acfs/cloud/AGENTS.md without provider configuration. Any other value installs nothing.",
  },
  {
    name: "ACFS_CLOUD_ROOT",
    defaultValue: "$HOME",
    effect: "Writable absolute data root (not /) for binaries and logs. In Codex mode a custom root also holds the explicitly loaded guide.",
  },
  {
    name: "ACFS_CLOUD_SKILL_DIR",
    defaultValue: "",
    effect: "Optional absolute Codex repository skill directory. Creates a tool-guide skill without replacing existing skills; hosted catalog loading still needs verification.",
  },
  {
    name: "ACFS_CLOUD_TOOLS",
    defaultValue: CLAUDE_CODE_WEB_TOOLS.map((tool) => tool.id).join(" "),
    effect: "Which tools to install.",
  },
  {
    name: "ACFS_CLOUD_TIMEOUT",
    defaultValue: "180",
    effect: "Deadline in seconds, from 1 to 180, for each tool's job: download, install and version checks. Jobs run in parallel; an out-of-range value installs nothing.",
  },
  {
    name: "ACFS_CLOUD_REINSTALL",
    defaultValue: "0",
    effect: "Set to 1 to reinstall tools already on PATH, e.g. to update inside a running session.",
  },
  {
    name: "ACFS_REF",
    defaultValue: "main",
    effect: "The ACFS git ref whose cloud-mirror.json pins prebuilt bundle hashes.",
  },
];

export type ClaudeCodeWebOmission = {
  name: string;
  reason: string;
};

export const CLAUDE_CODE_WEB_LEFT_OUT: ClaudeCodeWebOmission[] = [
  {
    name: "Machine provisioning",
    reason:
      "Users, zsh theming, the Ubuntu upgrade, systemd services, Tailscale, PostgreSQL, Vault, and cloud CLIs belong to a long-lived VPS. A cloud VM is disposable and already has its toolchains.",
  },
  {
    name: "ntm",
    reason: "The tmux cockpit is outside this tool bundle. These recipes focus on commands an agent can call in task shells.",
  },
  {
    name: "dcg",
    reason:
      "dcg works as a Claude Code hook. Cloud sessions run hooks from the repository's .claude/settings.json, not from user-level settings, and this installer never edits your repository.",
  },
  {
    name: "rch",
    reason: "Remote compilation needs SSH access to your own build workers.",
  },
  {
    name: "caam, ru, slb",
    reason:
      "Account switching, multi-repo sync, and the two-person rule all assume a machine you keep using.",
  },
];
