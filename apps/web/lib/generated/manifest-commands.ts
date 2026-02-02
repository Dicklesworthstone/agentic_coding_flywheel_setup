// ============================================================
// AUTO-GENERATED FROM acfs.manifest.yaml — DO NOT EDIT
// Regenerate: bun run generate (from packages/manifest)
// ============================================================

export interface ManifestCommand {
  moduleId: string;
  cliName: string;
  cliAliases: string[];
  description: string;
  commandExample?: string;
  docsUrl?: string;
}

export const manifestCommands: ManifestCommand[] = [
  {
    moduleId: "stack.automated_plan_reviser",
    cliName: "apr",
    cliAliases: [],
    description: "Automated iterative spec refinement with extended AI reasoning (apr)",
  },
  {
    moduleId: "stack.beads_rust",
    cliName: "br",
    cliAliases: [],
    description: "beads_rust (br) - Rust issue tracker with graph-aware dependencies",
    commandExample: "br ready --json",
  },
  {
    moduleId: "stack.beads_viewer",
    cliName: "bv",
    cliAliases: [],
    description: "bv TUI for Beads tasks",
    commandExample: "bv --robot-triage",
  },
  {
    moduleId: "stack.brenner_bot",
    cliName: "brenner",
    cliAliases: [],
    description: "Brenner Bot - research session manager with hypothesis tracking",
  },
  {
    moduleId: "stack.caam",
    cliName: "caam",
    cliAliases: [],
    description: "Instant auth switching for agent CLIs",
    commandExample: "caam status",
  },
  {
    moduleId: "stack.cass",
    cliName: "cass",
    cliAliases: [],
    description: "Unified search across agent session history",
    commandExample: "cass search \"auth error\" --robot",
  },
  {
    moduleId: "stack.cm",
    cliName: "cm",
    cliAliases: [],
    description: "Procedural memory for agents (cass-memory)",
    commandExample: "cm context \"task\" --json",
  },
  {
    moduleId: "stack.dcg",
    cliName: "dcg",
    cliAliases: [],
    description: "Destructive Command Guard - Claude Code hook blocking dangerous git/fs commands",
    commandExample: "dcg doctor",
  },
  {
    moduleId: "stack.jeffreysprompts",
    cliName: "jfp",
    cliAliases: [],
    description: "Curated battle-tested prompts for AI agents - browse and install as skills (jfp)",
  },
  {
    moduleId: "stack.mcp_agent_mail",
    cliName: "am",
    cliAliases: [],
    description: "Like gmail for coding agents; MCP HTTP server + token; installs beads tools",
  },
  {
    moduleId: "stack.meta_skill",
    cliName: "ms",
    cliAliases: [],
    description: "Local-first knowledge management with hybrid semantic search (ms)",
  },
  {
    moduleId: "stack.ntm",
    cliName: "ntm",
    cliAliases: [],
    description: "Named tmux manager (agent cockpit)",
  },
  {
    moduleId: "stack.process_triage",
    cliName: "pt",
    cliAliases: [],
    description: "Find and terminate stuck/zombie processes with intelligent scoring (pt)",
  },
  {
    moduleId: "stack.rch",
    cliName: "rch",
    cliAliases: [],
    description: "Remote Compilation Helper - transparent build offloading for AI coding agents",
  },
  {
    moduleId: "stack.ru",
    cliName: "ru",
    cliAliases: [],
    description: "Repo Updater - multi-repo sync + AI-driven commit automation",
    commandExample: "ru sync --parallel 4",
  },
  {
    moduleId: "stack.slb",
    cliName: "slb",
    cliAliases: [],
    description: "Two-person rule for dangerous commands (optional guardrails)",
  },
  {
    moduleId: "stack.srps",
    cliName: "sysmoni",
    cliAliases: [],
    description: "System Resource Protection Script - ananicy-cpp rules + TUI monitor for responsive dev workstations",
  },
  {
    moduleId: "stack.ultimate_bug_scanner",
    cliName: "ubs",
    cliAliases: [],
    description: "UBS bug scanning (easy-mode)",
    commandExample: "ubs file.ts",
  },
  {
    moduleId: "stack.wezterm_automata",
    cliName: "wa",
    cliAliases: [],
    description: "WezTerm Automata (wa) - terminal automation and orchestration for AI agents",
  },
  {
    moduleId: "utils.giil",
    cliName: "giil",
    cliAliases: [],
    description: "Get Image from Internet Link - download cloud images for visual debugging",
  },
  {
    moduleId: "utils.s2p",
    cliName: "s2p",
    cliAliases: [],
    description: "source_to_prompt_tui (s2p) - Code to LLM prompt generator with TUI",
  },
  {
    moduleId: "utils.xf",
    cliName: "xf",
    cliAliases: [],
    description: "xf - Ultra-fast X/Twitter archive search with Tantivy",
  },
];
