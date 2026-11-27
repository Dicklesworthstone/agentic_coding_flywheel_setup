export const COMPLETE_GUIDE_REVIEWED_ON = "November 26, 2026";
export const COMPLETE_GUIDE_PROMPT_COUNT = 49;
export const COMPLETE_GUIDE_PHASE_COUNT = 13;

export const COMPLETE_GUIDE_MODELS = {
  /** The lead planner, in charge of the whole project: plan, reviews, beads, swarm. */
  leadPlanner: "Claude Fable 5.2",
  leadPlannerSurface: "Claude Code",
  claudeExecutor: "Claude Opus 5.5",
  claudeFallback: "Claude Sonnet 5.5",
  /**
   * The "GPT Pro" option in ChatGPT (Pro effort; every ChatGPT Pro tier has it).
   * Writes a competing first draft and runs the plan-review rounds. It is a Chat
   * option with its own limits, separate from GPT-6.2 Astra in Work and Codex.
   */
  gptPro: "GPT-6 Pro",
  gptProSurface: "ChatGPT",
  /** Writes a competing plan and audits the lead's, in Codex. */
  openaiPlanner: "GPT-6.2 Astra",
  /** The model the ACFS `cod` alias runs (acfs/zsh/acfs.zshrc), at xhigh effort. */
  codexExecutor: "GPT-6.2 Sol",
  /** The model the ACFS `agy` alias is pinned to; also writes a competing plan. */
  antigravity: "Gemini 4 Neon (XHigh)",
  restrictedPreview: "Claude Mythos 5.2",
} as const;

export const COMPLETE_GUIDE_MODEL_SOURCES = [
  {
    provider: "OpenAI",
    href: "https://help.openai.com/en/articles/20001354-gpt-6-and-other-models-in-chatgpt",
    note: "GPT-6 Pro in Chat on every Pro tier; GPT-6.2 Astra and Sol in ChatGPT Work and Codex",
  },
  {
    provider: "ChatGPT Pro",
    href: "https://help.openai.com/en/articles/9793128-what-is-chatgpt-pro",
    note: "Pro plan tiers and usage limits",
  },
  {
    provider: "Anthropic Fable",
    href: "https://www.anthropic.com/claude/fable",
    note: "Fable 5.2 availability and intended workloads",
  },
  {
    provider: "Anthropic Opus",
    href: "https://www.anthropic.com/claude/opus",
    note: "Opus 5.5 availability and intended workloads",
  },
  {
    provider: "Anthropic Sonnet",
    href: "https://www.anthropic.com/claude/sonnet",
    note: "Sonnet 5.5 availability and intended workloads",
  },
  {
    provider: "Claude models",
    href: "https://platform.claude.com/docs/en/about-claude/models/overview",
    note: "Current Claude model lineup and API identifiers",
  },
  {
    provider: "CNBC on Mythos 5.2",
    href: "https://www.cnbc.com/2026/11/09/anthropic-claude-fable-5-2-mythos-5-2.html",
    note: "Mythos 5.2 access restrictions",
  },
  {
    provider: "Google models",
    href: "https://ai.google.dev/gemini-api/docs/models",
    note: "Gemini 4 Carbon, Neon, Hydrogen, and Argon lineup",
  },
] as const;

export const VALIDATION_GATES = [
  [
    "Foundation",
    "The kickoff states the goals and workflows, names the earlier plans to model on and the foundations to build on, and every foundation the plan relies on is checked at a pinned revision",
  ],
  [
    "Plan",
    "Markdown plan covers workflows, architecture, sequencing, constraints, testing expectations, and major failure paths",
  ],
  [
    "Translation",
    "Every material plan element maps to one or more beads, checked in both directions",
  ],
  [
    "Bead",
    "Beads are self-contained, dependency-correct, rich in context, and explicit about test obligations",
  ],
  [
    "Launch",
    "Agent Mail, file reservations, bead IDs, bv, AGENTS.md, and staggered startup are all ready",
  ],
  [
    "Ship",
    "Reviews, tests, UBS, remaining-work beads, and feedback capture into reusable artifacts are complete",
  ],
] as const;
