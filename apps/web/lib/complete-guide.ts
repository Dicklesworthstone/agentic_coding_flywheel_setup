export const COMPLETE_GUIDE_REVIEWED_ON = "July 17, 2026";
export const COMPLETE_GUIDE_PROMPT_COUNT = 42;
export const COMPLETE_GUIDE_PHASE_COUNT = 13;

export const COMPLETE_GUIDE_MODELS = {
  primaryPlanner: "GPT-5.6 Sol Pro",
  primaryPlannerSurface: "ChatGPT Pro",
  claudePlanner: "Claude Fable 5",
  claudeExecutor: "Claude Sonnet 5",
  claudeFallback: "Claude Opus 4.8",
  googlePlanner: "Gemini 3.1 Pro with Deep Think",
  antigravity: "Gemini 3.1 Pro (High)",
  xaiPlanner: "Grok 4.5",
  restrictedPreview: "Claude Mythos Preview",
} as const;

export const COMPLETE_GUIDE_MODEL_SOURCES = [
  {
    provider: "OpenAI",
    href: "https://openai.com/index/gpt-5-6/",
    note: "GPT-5.6 Sol and Sol Pro availability and reasoning modes",
  },
  {
    provider: "Anthropic Fable",
    href: "https://www.anthropic.com/claude/fable",
    note: "Fable 5 availability and intended workloads",
  },
  {
    provider: "Anthropic Sonnet",
    href: "https://www.anthropic.com/claude/sonnet",
    note: "Sonnet 5 availability and intended workloads",
  },
  {
    provider: "Anthropic Opus",
    href: "https://www.anthropic.com/claude/opus",
    note: "Opus 4.8 availability and intended workloads",
  },
  {
    provider: "Anthropic Glasswing",
    href: "https://www.anthropic.com/glasswing",
    note: "Mythos Preview access restrictions",
  },
  {
    provider: "Google Deep Think",
    href: "https://support.google.com/gemini/answer/16275805",
    note: "Gemini app model selection and Deep Think access requirements",
  },
  {
    provider: "Google models",
    href: "https://ai.google.dev/gemini-api/docs/models",
    note: "Current Gemini model lineup",
  },
  {
    provider: "xAI",
    href: "https://x.ai/news",
    note: "Grok 4.5 release and intended workloads",
  },
] as const;

export const VALIDATION_GATES = [
  ["Foundation", "Goals, workflows, stack, architecture direction, AGENTS.md, and best-practices guides exist and are coherent"],
  ["Plan", "Markdown plan covers workflows, architecture, sequencing, constraints, testing expectations, and major failure paths"],
  ["Translation", "Every material plan element maps to one or more beads, checked in both directions"],
  ["Bead", "Beads are self-contained, dependency-correct, rich in context, and explicit about test obligations"],
  ["Launch", "Agent Mail, file reservations, bead IDs, bv, AGENTS.md, and staggered startup are all ready"],
  ["Ship", "Reviews, tests, UBS, remaining-work beads, and feedback capture into reusable artifacts are complete"],
] as const;
