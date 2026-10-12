import { manifestTools } from "./generated/manifest-tools";
import { manifestAgents } from "./generated/manifest-agents";
import { LESSONS } from "./lessons";
import { resolveModuleSelection, type ModuleSelectionInput } from "./moduleSelection";

export type LearningGoal = "learn" | "recover" | "swarm";
export interface LearningPathInput {
  completedLessons: readonly number[];
  selection?: ModuleSelectionInput;
  goal?: LearningGoal;
  /** Only a projected boolean from the current, locally reviewed doctor report. */
  doctorNeedsAttention?: boolean;
}
export interface LearningRecommendation {
  id: string;
  href: string;
  title: string;
  reason: string;
  kind: "lesson" | "reference" | "recovery";
}
export interface LearningPath {
  persona: "getting-started" | "minimal" | "selected-stack" | "team" | "recovery" | "all-complete";
  signalIds: string[];
  fallbackReason: "no-selection" | "invalid-selection" | "no-mapped-tools" | null;
  recommendations: LearningRecommendation[];
}

// Route names are the existing tool-reference IDs, not assumed CLI names.
const TOOL_ROUTES: Readonly<Record<string, string>> = {
  "stack.beads_rust": "beads",
  "stack.mcp_agent_mail": "agent-mail",
  "stack.ntm": "ntm",
  "stack.ultimate_bug_scanner": "ubs",
  "stack.cass": "cass",
  "stack.cm": "cm",
  "stack.rch": "rch",
  "stack.dcg": "dcg",
  "stack.ru": "ru",
  "agents.claude": "claude-code",
  "agents.codex": "codex-cli",
  "agents.antigravity": "antigravity-cli",
};
const TOOL_ORDER = Object.keys(TOOL_ROUTES);

/** Deterministic, local-only recommendations. A selection never proves installation. */
export function recommendLearningPath(input: LearningPathInput): LearningPath {
  const completed = new Set(input.completedLessons.filter((id) => Number.isInteger(id) && LESSONS.some((lesson) => lesson.id === id)));
  const next = LESSONS.find((lesson) => !completed.has(lesson.id));
  const goal = input.goal ?? "learn";
  const plan = input.selection ? resolveModuleSelection(input.selection) : null;
  const recommendations: LearningRecommendation[] = [];
  const signalIds: string[] = [];
  let persona: LearningPath["persona"] = !next ? "all-complete" : !plan ? "getting-started" :
    plan.profile === "minimal" ? "minimal" : "selected-stack";
  let fallbackReason: LearningPath["fallbackReason"] = !plan ? "no-selection" : !plan.ok ? "invalid-selection" : null;
  if (input.doctorNeedsAttention || goal === "recover") {
    persona = "recovery";
    signalIds.push(input.doctorNeedsAttention ? "doctor-needs-attention" : "requested-recovery");
    recommendations.push({ id: "review-installation", href: "/wizard/status-check", title: "Review installation health",
      reason: input.doctorNeedsAttention ? "Your locally reviewed doctor report has findings or coverage gaps to inspect." : "You chose help with an installation problem.", kind: "recovery" });
  } else if (plan && !plan.ok) {
    signalIds.push("invalid-selection");
    recommendations.push({ id: "review-selection", href: "/wizard/run-installer", title: "Review your stack selection",
      reason: "The saved selection cannot be resolved safely. Review it before choosing tool-specific lessons.", kind: "recovery" });
  } else if (goal === "swarm") {
    persona = "team";
    signalIds.push("requested-swarm-workflow");
    recommendations.push({ id: "coordinate-agents", href: "/core-flywheel", title: "Coordinate your agents",
      reason: "You chose a workflow with multiple agents. Start with task ownership and coordination.", kind: "reference" });
  }
  if (next) {
    signalIds.push(completed.size ? "lesson-progress" : "first-lesson");
    recommendations.push({ id: `lesson-${next.slug}`, href: `/learn/${next.slug}`, title: next.title,
      reason: completed.size ? "This is your next unfinished lesson in the guided sequence." : "Start here to learn how the environment fits together.", kind: "lesson" });
  }
  if (plan?.ok) {
    signalIds.push("selected-modules");
    const selected = new Set(plan.included.map((module) => module.id));
    const order = goal === "swarm" ? ["stack.mcp_agent_mail", "stack.ntm", ...TOOL_ORDER] : TOOL_ORDER;
    const added = new Set<string>();
    let mappedTools = 0;
    for (const moduleId of order) {
      if (!selected.has(moduleId) || added.has(moduleId)) continue;
      added.add(moduleId);
      const tool = manifestTools.find((entry) => entry.moduleId === moduleId) ?? manifestAgents.find((entry) => entry.moduleId === moduleId);
      const slug = TOOL_ROUTES[moduleId];
      if (!tool || !slug || completed.has(LESSONS.find((lesson) => lesson.slug === slug)?.id ?? -1)) continue;
      mappedTools++;
      recommendations.push({ id: `tool-${slug}`, href: `/learn/tools/${slug}`, title: `${tool.displayName} reference`,
        reason: "This tool is included in your selected stack. Its reference is available at any lesson level.", kind: "reference" });
      if (recommendations.length >= 3) break;
    }
    if (!mappedTools) fallbackReason = "no-mapped-tools";
  }
  if (recommendations.length < 3) {
    recommendations.push({ id: "command-reference", href: "/learn/commands", title: "Keep the commands handy",
      reason: next ? "Use the searchable command reference as you practice." : "All guided lessons are complete. Revisit commands whenever you need them.", kind: "reference" });
  }
  return { persona, signalIds, fallbackReason, recommendations: recommendations.slice(0, 3) };
}
