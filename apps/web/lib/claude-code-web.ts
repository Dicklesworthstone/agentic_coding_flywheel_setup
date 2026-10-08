/**
 * Content for /claude-code-web: the lightweight ACFS setup script for Claude
 * Code cloud environments (scripts/claude-code-web-setup.sh).
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

export type ClaudeCodeWebTool = {
  /** Tool id as the script's ACFS_CLOUD_TOOLS spells it. */
  id: string;
  name: string;
  command: string;
  role: string;
};

/** In the script's default install order. */
export const CLAUDE_CODE_WEB_TOOLS: ClaudeCodeWebTool[] = [
  {
    id: "br",
    name: "BeadsRust",
    command: "br",
    role: "Dependency-aware issues that live in the repo's .beads/ and travel with the code.",
  },
  {
    id: "bv",
    name: "Beads Viewer",
    command: "bv --robot-triage",
    role: "Graph-aware triage: what to work on next and what it unblocks.",
  },
  {
    id: "am",
    name: "MCP Agent Mail",
    command: "am",
    role: "Agent messaging and file reservations, registered with Claude Code as a stdio MCP server.",
  },
  {
    id: "ubs",
    name: "Ultimate Bug Scanner",
    command: "ubs <files>",
    role: "Scans changed files for bugs before every commit.",
  },
  {
    id: "cass",
    name: "Session Search",
    command: "cass search --robot",
    role: "Searches the agent session history on this VM.",
  },
  {
    id: "cm",
    name: "CASS Memory",
    command: "cm context",
    role: "Procedural memory pulled in before a task starts.",
  },
  {
    id: "ms",
    name: "Meta Skill",
    command: "ms",
    role: "Local skill search and management.",
  },
  {
    id: "ast-grep",
    name: "ast-grep",
    command: "ast-grep",
    role: "Structural code search and UBS scan dependency.",
  },
  {
    id: "jsm",
    name: "Jeffrey's Skills",
    command: "jsm",
    role: "Skill manager for the jeffreys-skills.md library.",
  },
  {
    id: "jfp",
    name: "JeffreysPrompts",
    command: "jfp",
    role: "The battle-tested prompt library, from the terminal.",
  },
];

export type ClaudeCodeWebOption = {
  name: string;
  defaultValue: string;
  effect: string;
};

export const CLAUDE_CODE_WEB_OPTIONS: ClaudeCodeWebOption[] = [
  {
    name: "ACFS_CLOUD_TOOLS",
    defaultValue: CLAUDE_CODE_WEB_TOOLS.map((tool) => tool.id).join(" "),
    effect: "Which tools to install.",
  },
  {
    name: "ACFS_CLOUD_TIMEOUT",
    defaultValue: "180",
    effect: "Whole tool download/install deadline in seconds, from 1 to 180.",
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
    reason: "The tmux agent cockpit needs an interactive terminal, and a cloud session has none.",
  },
  {
    name: "dcg",
    reason:
      "It installs a user-level Claude Code hook. Cloud sessions only run hooks from the repository's .claude/settings.json.",
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
