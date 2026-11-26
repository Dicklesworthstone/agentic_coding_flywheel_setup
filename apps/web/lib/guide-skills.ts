// Skills from jeffreys-skills.md that the guides recommend at the step they
// package (rendered by SkillNote in components/complete-guide/guide-components).
// Every slug was a published skill page when it was added; lib/complete-guide.test.ts
// keeps this list and the notes on both guide pages in step.

export const SKILLS_SITE_URL = "https://jeffreys-skills.md";

export const GUIDE_SKILLS = [
  // Planning
  "planning-workflow",
  "multi-model-triangulation",
  // Beads
  "beads-workflow",
  "beads-br",
  "beads-bv",
  "fixing-beads-problems",
  // New features in existing projects
  "idea-wizard",
  "dueling-idea-wizards",
  // Coordination and safety
  "agent-mail",
  "agent-fungibility-philosophy",
  "dcg",
  "slb",
  // Running the swarm
  "ntm",
  "vibing-with-ntm",
  "open-beads-weighted-tmux-agent-sessions",
  "just-say-no-to-process-porn-and-ceremony",
  "caam",
  // Review, testing and polish
  "mock-code-finder",
  "testing-real-service-e2e-no-mocks",
  "ui-polish",
  "ux-audit",
  "web-frontend-ui-ux-excellence-on-desktop-and-mobile",
  "de-slopify",
  "multi-pass-bug-hunting",
  "code-review-gemini-swarm-with-ntm",
  "reality-check-for-project",
  "beads-compliance-and-completion-verification",
  "readme-writing",
  "simplify-and-refactor-code-isomorphically",
  // Choosing skills
  "choose-the-best-skills-for-me-to-run-in-this-project",
  // The flywheel
  "cass",
  "cass-memory",
  "operationalizing-expertise",
  "agent-ergonomics-and-intuitiveness-maximization-for-cli-tools",
  "world-class-doctor-mode-for-cli-tools",
  "profiling-software-performance",
  "extreme-software-optimization",
  "repeatedly-apply-skill",
] as const;

export type GuideSkill = (typeof GUIDE_SKILLS)[number];

export function skillUrl(skill: GuideSkill): string {
  return `${SKILLS_SITE_URL}/skills/${skill}`;
}
