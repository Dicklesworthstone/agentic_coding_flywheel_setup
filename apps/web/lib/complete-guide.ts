export const COMPLETE_GUIDE_REVIEWED_ON = "November 25, 2026";
export const COMPLETE_GUIDE_PROMPT_COUNT = 42;
export const COMPLETE_GUIDE_PHASE_COUNT = 13;

export const COMPLETE_GUIDE_MODELS = {
  primaryPlanner: "GPT-6.2 Astra",
  primaryPlannerSurface: "ChatGPT Work",
  claudePlanner: "Claude Fable 5.2",
  claudeExecutor: "Claude Opus 5.5",
  claudeFallback: "Claude Sonnet 5.5",
  googlePlanner: "Gemini 4 Carbon",
  antigravity: "Gemini 4 Neon (XHigh)",
  xaiPlanner: "Grok 4.7",
  restrictedPreview: "Claude Mythos 5.2",
} as const;

export const COMPLETE_GUIDE_MODEL_SOURCES = [
  {
    provider: "OpenAI",
    href: "https://help.openai.com/en/articles/20001354-gpt-6-and-other-models-in-chatgpt",
    note: "GPT-6.2 Astra and Sol availability in ChatGPT Work and Codex",
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
  {
    provider: "9to5Google on Gemini 4 Carbon",
    href: "https://9to5google.com/2026/11/10/gemini-app-4-carbon/",
    note: "Gemini app availability for Google AI Ultra subscribers",
  },
  {
    provider: "xAI models",
    href: "https://docs.x.ai/docs/models",
    note: "Grok 4.7 availability and intended workloads",
  },
] as const;

export const VALIDATION_GATES = [
  [
    "Foundation",
    "Goals, workflows, stack, architecture direction, AGENTS.md, and best-practices guides exist and are coherent",
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
