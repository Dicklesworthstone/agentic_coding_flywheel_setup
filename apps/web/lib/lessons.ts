/**
 * Lesson Data
 *
 * Static lesson definitions for the ACFS Learning Hub.
 * This file contains only static data and pure functions,
 * so it can be imported by both Server and Client Components.
 *
 * For progress tracking hooks, see lessonProgress.ts.
 */

export interface Lesson {
  /** Lesson number (0-indexed) */
  id: number;
  /** URL slug for routing */
  slug: string;
  /** Display title */
  title: string;
  /** Brief description */
  description: string;
  /** Estimated reading time */
  duration: string;
  /** Source markdown file name */
  file: string;
}

export const LESSONS: Lesson[] = [
  {
    id: 0,
    slug: "welcome",
    title: "Welcome & Overview",
    description: "Understand what you have and what you're about to learn",
    duration: "5 min",
    file: "00_welcome.md",
  },
  {
    id: 1,
    slug: "linux-basics",
    title: "Linux Navigation",
    description: "Navigate the filesystem with confidence",
    duration: "8 min",
    file: "01_linux_basics.md",
  },
  {
    id: 2,
    slug: "ssh-basics",
    title: "SSH & Persistence",
    description: "Master secure connections and stay connected",
    duration: "6 min",
    file: "02_ssh_basics.md",
  },
  {
    id: 3,
    slug: "tmux-basics",
    title: "tmux Basics",
    description: "Keep your work running when you disconnect",
    duration: "7 min",
    file: "03_tmux_basics.md",
  },
  {
    id: 4,
    slug: "git-basics",
    title: "Git Essentials",
    description: "Version control and recognizing dangerous operations",
    duration: "10 min",
    file: "04_git_basics.md",
  },
  {
    id: 5,
    slug: "github-cli",
    title: "GitHub CLI",
    description: "Manage issues, PRs, releases, and actions",
    duration: "8 min",
    file: "05_github_cli.md",
  },
  {
    id: 6,
    slug: "agent-commands",
    title: "Agent Commands",
    description: "Talk to Claude, Codex, and Antigravity",
    duration: "10 min",
    file: "06_agents_login.md",
  },
  {
    id: 7,
    slug: "ntm-core",
    title: "NTM Command Center",
    description: "Orchestrate your terminal sessions",
    duration: "8 min",
    file: "07_ntm_core.md",
  },
  {
    id: 8,
    slug: "ntm-palette",
    title: "NTM Prompt Palette",
    description: "Quick access to common commands",
    duration: "6 min",
    file: "08_ntm_command_palette.md",
  },
  {
    id: 9,
    slug: "flywheel-loop",
    title: "The Flywheel Loop",
    description: "Put it all together for maximum velocity",
    duration: "10 min",
    file: "09_flywheel_loop.md",
  },
  {
    id: 10,
    slug: "keeping-updated",
    title: "Keeping Updated",
    description: "Maintain and upgrade your environment",
    duration: "4 min",
    file: "10_keeping_updated.md",
  },
  {
    id: 11,
    slug: "ubs",
    title: "UBS: Code Quality Guardrails",
    description: "Catch bugs before they reach production",
    duration: "8 min",
    file: "11_ubs.md",
  },
  {
    id: 12,
    slug: "agent-mail",
    title: "Agent Mail Coordination",
    description: "Multi-agent messaging and file reservations",
    duration: "10 min",
    file: "12_agent_mail.md",
  },
  {
    id: 13,
    slug: "cass",
    title: "CASS: Learning from History",
    description: "Search across all past agent sessions",
    duration: "8 min",
    file: "13_cass.md",
  },
  {
    id: 14,
    slug: "cm",
    title: "The Memory System",
    description: "Build procedural memory for agents",
    duration: "8 min",
    file: "14_cm.md",
  },
  {
    id: 15,
    slug: "beads",
    title: "Beads: Issue Tracking",
    description: "Graph-aware task management with dependencies",
    duration: "8 min",
    file: "15_beads.md",
  },
  {
    id: 16,
    slug: "safety-tools",
    title: "Safety Tools: SLB & CAAM",
    description: "Two-person rule and account management",
    duration: "6 min",
    file: "16_safety_tools.md",
  },
  {
    id: 17,
    slug: "prompt-engineering",
    title: "The Art of Agent Direction",
    description: "Prompting patterns that produce excellent results",
    duration: "12 min",
    file: "17_prompt_engineering.md",
  },
  {
    id: 18,
    slug: "real-world-case-study",
    title: "Case Study: cass-memory",
    description: "Build a complex project in one day with agent swarms",
    duration: "15 min",
    file: "18_real_world_case_study.md",
  },
  {
    id: 19,
    slug: "slb-case-study",
    title: "Case Study: SLB",
    description: "From tweet to working tool in one evening",
    duration: "12 min",
    file: "19_slb_case_study.md",
  },
  {
    id: 20,
    slug: "ru",
    title: "RU: Multi-Repo Mastery",
    description: "Sync repos and automate commits with AI",
    duration: "10 min",
    file: "20_ru.md",
  },
  {
    id: 21,
    slug: "dcg",
    title: "DCG: Pre-Execution Safety",
    description: "Block dangerous commands before they cause damage",
    duration: "8 min",
    file: "21_dcg.md",
  },
  {
    id: 22,
    slug: "ms",
    title: "Meta Skill: Local Skills",
    description: "Manage and share Claude Code skills locally",
    duration: "10 min",
    file: "22_meta_skill.md",
  },
  {
    id: 23,
    slug: "srps",
    title: "SRPS: System Protection",
    description: "Keep your workstation responsive under heavy agent load",
    duration: "8 min",
    file: "23_srps.md",
  },
  {
    id: 24,
    slug: "jfp",
    title: "JFP: Prompt Library",
    description: "Discover and install curated prompts as Claude Code skills",
    duration: "6 min",
    file: "24_jfp.md",
  },
  {
    id: 25,
    slug: "apr",
    title: "APR: Automated Plan Reviser",
    description: "AI-powered iterative specification refinement",
    duration: "8 min",
    file: "25_apr.md",
  },
  {
    id: 26,
    slug: "pt",
    title: "PT: Process Triage",
    description: "Intelligent process management with Bayesian scoring",
    duration: "6 min",
    file: "26_pt.md",
  },
  {
    id: 27,
    slug: "xf",
    title: "XF: X Archive Search",
    description: "Blazingly fast search across your X/Twitter archive",
    duration: "6 min",
    file: "27_xf.md",
  },
  {
    id: 28,
    slug: "rch",
    title: "RCH: Remote Compilation",
    description: "Offload Rust builds to remote workers for faster compilation",
    duration: "8 min",
    file: "28_rch.md",
  },
  {
    id: 29,
    slug: "wa",
    title: "WA: WezTerm Automata",
    description: "Real-time terminal observation and automation for AI agents",
    duration: "8 min",
    file: "29_wa.md",
  },
  {
    id: 30,
    slug: "brenner",
    title: "Brenner Bot: Research",
    description: "Coordinate multi-agent AI research with scientific methodology",
    duration: "10 min",
    file: "30_brenner.md",
  },
  {
    id: 31,
    slug: "giil",
    title: "GIIL: Cloud Image Downloads",
    description: "Download cloud-hosted images for visual debugging",
    duration: "6 min",
    file: "31_giil.md",
  },
  {
    id: 32,
    slug: "s2p",
    title: "S2P: Source to Prompt",
    description: "Combine source code into LLM-ready prompts with token counting",
    duration: "6 min",
    file: "32_s2p.md",
  },
  {
    id: 33,
    slug: "fsfs",
    title: "FSFS: Hybrid Local Search",
    description: "Two-tier lexical + semantic search with progressive delivery",
    duration: "6 min",
    file: "33_fsfs.md",
  },
  {
    id: 34,
    slug: "sbh",
    title: "SBH: Disk Pressure Defense",
    description: "Protect against out-of-space crashes with storage ballast",
    duration: "5 min",
    file: "34_sbh.md",
  },
  {
    id: 35,
    slug: "casr",
    title: "CASR: Cross-Agent Sessions",
    description: "Resume coding sessions across AI providers seamlessly",
    duration: "6 min",
    file: "35_casr.md",
  },
  {
    id: 36,
    slug: "dsr",
    title: "DSR: Self-Releaser",
    description: "Build and publish releases locally when CI is throttled",
    duration: "5 min",
    file: "36_dsr.md",
  },
  {
    id: 37,
    slug: "asb",
    title: "ASB: Agent Settings Backup",
    description: "Back up and restore AI agent configurations across machines",
    duration: "5 min",
    file: "37_asb.md",
  },
  {
    id: 38,
    slug: "pcr",
    title: "PCR: Post-Compact Reminder",
    description: "Keep agents aligned after context compaction",
    duration: "4 min",
    file: "38_pcr.md",
  },
  {
    id: 39,
    slug: "csctf",
    title: "CSCTF: Chat Archiver",
    description: "Convert AI share links to Markdown for permanent archiving",
    duration: "5 min",
    file: "39_csctf.md",
  },
  {
    id: 40,
    slug: "tru",
    title: "TRU: Token Compression",
    description: "Compress source code to fit more context in LLM requests",
    duration: "5 min",
    file: "40_tru.md",
  },
  {
    id: 41,
    slug: "mdwb",
    title: "MDWB: Web to Markdown",
    description: "Convert web pages to clean Markdown for AI consumption",
    duration: "5 min",
    file: "41_mdwb.md",
  },
  {
    id: 42,
    slug: "rano",
    title: "RANO: Network Observer",
    description: "Monitor and debug AI CLI network traffic",
    duration: "6 min",
    file: "42_rano.md",
  },
  {
    id: 43,
    slug: "caut",
    title: "CAUT: Usage Tracker",
    description: "Track LLM provider usage and costs across agents",
    duration: "5 min",
    file: "43_caut.md",
  },
  {
    id: 44,
    slug: "aadc",
    title: "AADC: Diagram Corrector",
    description: "Fix malformed ASCII art diagrams with AI assistance",
    duration: "4 min",
    file: "44_aadc.md",
  },
  {
    id: 45,
    slug: "rust-proxy",
    title: "Rust Proxy: Traffic Inspector",
    description: "Transparent proxy for debugging network traffic",
    duration: "5 min",
    file: "45_rust_proxy.md",
  },
  {
    id: 46,
    slug: "bv",
    title: "BV: Graph-Aware Triage",
    description: "Analyze issue dependencies with graph metrics and robot mode",
    duration: "8 min",
    file: "46_bv.md",
  },
  {
    id: 47,
    slug: "caam",
    title: "CAAM: Account Rotation",
    description: "Manage multi-provider API accounts with automatic rate limit rotation",
    duration: "6 min",
    file: "47_caam.md",
  },
  {
    id: 48,
    slug: "swarm-coordination",
    title: "Agent Swarm Coordination",
    description: "Orchestrate multi-agent swarms with NTM, WA, Agent Mail, and BV",
    duration: "10 min",
    file: "48_swarm_coordination.md",
  },
  {
    id: 49,
    slug: "debugging-agents",
    title: "Debugging Agent Issues",
    description: "Diagnose rate limits, network failures, and cost overruns with RANO, CAUT, WA, and CASS",
    duration: "8 min",
    file: "49_debugging_agents.md",
  },
  {
    id: 50,
    slug: "context-mastery",
    title: "Context Window Mastery",
    description: "Maximize agent context efficiency with TRU, S2P, CASS, and CM",
    duration: "8 min",
    file: "50_context_mastery.md",
  },
  {
    id: 51,
    slug: "ci-cd",
    title: "CI/CD for Agent Code",
    description: "Build automated quality gates with UBS, Beads, and DSR",
    duration: "8 min",
    file: "51_ci_cd.md",
  },
  {
    id: 52,
    slug: "project-bootstrap",
    title: "Project Bootstrap",
    description: "Set up a new multi-agent project with issue tracking, safety, and coordination",
    duration: "7 min",
    file: "52_project_bootstrap.md",
  },
  {
    id: 53,
    slug: "ast-grep",
    title: "ast-grep: Structural Search",
    description: "Find and replace code by AST shape, not string matching — powers DCG and UBS",
    duration: "7 min",
    file: "53_ast_grep.md",
  },
  {
    id: 54,
    slug: "agents-md",
    title: "AGENTS.md Mastery",
    description: "Write effective AGENTS.md files that make any project agent-ready",
    duration: "8 min",
    file: "54_agents_md.md",
  },
  {
    id: 55,
    slug: "modern-cli",
    title: "Modern CLI Toolkit",
    description: "Level up with lazygit, atuin, zoxide, fzf, bat, and lsd",
    duration: "8 min",
    file: "55_modern_cli.md",
  },
  {
    id: 56,
    slug: "tailscale",
    title: "Tailscale & Network Security",
    description: "Secure your VPS with mesh VPN, SSH hardening, and firewall lockdown",
    duration: "7 min",
    file: "56_tailscale.md",
  },
  {
    id: 57,
    slug: "lang-runtimes",
    title: "Language Runtimes",
    description: "Master Bun, uv, Rust/cargo, Go, and nvm — the five language runtimes in your stack",
    duration: "8 min",
    file: "57_lang_runtimes.md",
  },
  {
    id: 58,
    slug: "cloud-infra",
    title: "Cloud & Database Tools",
    description: "Deploy with PostgreSQL, Supabase, Vercel, and Wrangler",
    duration: "8 min",
    file: "58_cloud_infra.md",
  },
  {
    id: 59,
    slug: "security-layers",
    title: "Security Deep Dive",
    description: "Three-layer defense with DCG, SLB, and CAAM for safe agent autonomy",
    duration: "10 min",
    file: "59_security_layers.md",
  },
  {
    id: 60,
    slug: "acfs-doctor",
    title: "ACFS Doctor & Maintenance",
    description: "Keep your environment healthy with doctor checks, nightly updates, and SRPS",
    duration: "7 min",
    file: "60_acfs_doctor.md",
  },
];

/**
 * Slugs for lessons that double as always-available reference material.
 *
 * These appear in the Learning Hub "Quick Reference" section alongside
 * standalone routes like `/learn/commands` and `/learn/glossary`. Visitors
 * must be able to open them as reference at any time, so they are exempt from
 * the sequential progress lock-gating that applies to the curriculum flow.
 */
export const REFERENCE_LESSON_SLUGS: ReadonlySet<string> = new Set([
  "agent-commands",
  "ntm-palette",
]);

/** Whether a lesson is an always-available reference lesson (never locked). */
export function isReferenceLesson(lessonId: number): boolean {
  const lesson = getLessonById(lessonId);
  return lesson ? REFERENCE_LESSON_SLUGS.has(lesson.slug) : false;
}

/** Total number of lessons */
export const TOTAL_LESSONS = LESSONS.length;

/** Get a lesson by its ID (0-indexed) */
export function getLessonById(id: number): Lesson | undefined {
  return LESSONS.find((lesson) => lesson.id === id);
}

/** Get a lesson by its URL slug */
export function getLessonBySlug(slug: string): Lesson | undefined {
  return LESSONS.find((lesson) => lesson.slug === slug);
}

/** Get the next lesson after the current one */
export function getNextLesson(currentId: number): Lesson | undefined {
  return LESSONS.find((lesson) => lesson.id === currentId + 1);
}

/** Get the previous lesson before the current one */
export function getPreviousLesson(currentId: number): Lesson | undefined {
  return LESSONS.find((lesson) => lesson.id === currentId - 1);
}
