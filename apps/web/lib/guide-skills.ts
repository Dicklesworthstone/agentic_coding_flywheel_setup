// Skills from jeffreys-skills.md that the guides recommend at the step they
// package (rendered by SkillNote in components/complete-guide/guide-components).
// Every slug was a published skill page when it was added; lib/complete-guide.test.ts
// keeps this list and the notes on both guide pages in step.

export const SKILLS_SITE_URL = "https://jeffreys-skills.md";

export const GUIDE_SKILLS = [
  // Planning
  "planning-workflow",
  "multi-model-triangulation",
  "modes-of-reasoning-project-analysis",
  // Beads
  "beads-workflow",
  "beads-br",
  "beads-bv",
  "fixing-beads-problems",
  // New features in existing projects
  "idea-wizard",
  "dueling-idea-wizards",
  "research-software",
  "codebase-archaeology",
  // Coordination, git and security
  "agent-mail",
  "agent-fungibility-philosophy",
  "dcg",
  "slb",
  "git-worktree-branch-rationalization",
  "git-stash-janitor",
  "codebase-audit",
  "security-audit-for-saas",
  // Running the swarm
  "ntm",
  "vibing-with-ntm",
  "multi-agent-swarm-workflow",
  "wezterm",
  "open-beads-weighted-tmux-agent-sessions",
  "just-say-no-to-process-porn-and-ceremony",
  "system-performance-remediation",
  "caam",
  // Testing
  "mock-code-finder",
  "testing-real-service-e2e-no-mocks",
  "e2e-testing-for-webapps",
  "testing-golden-artifacts",
  "testing-fuzzing",
  "testing-metamorphic",
  "testing-conformance-harnesses",
  "ubs",
  "rch",
  // Review and polish
  "ui-polish",
  "ux-audit",
  "web-frontend-ui-ux-excellence-on-desktop-and-mobile",
  "de-slopify",
  "multi-pass-bug-hunting",
  "code-review-gemini-swarm-with-ntm",
  "deadlock-finder-and-fixer",
  "git-repo-janitor",
  "reality-check-for-project",
  "beads-compliance-and-completion-verification",
  "readme-writing",
  "simplify-and-refactor-code-isomorphically",
  "de-monolithize-your-codebase-isomorphically",
  // Choosing skills
  "choose-the-best-skills-for-me-to-run-in-this-project",
  // The flywheel
  "cass",
  "cass-memory",
  "operationalizing-expertise",
  "automating-your-automations",
  "agent-ergonomics-and-intuitiveness-maximization-for-cli-tools",
  "world-class-doctor-mode-for-cli-tools",
  "mcp-server-design",
  "installer-workmanship",
  "profiling-software-performance",
  "extreme-software-optimization",
  "repeatedly-apply-skill",
] as const;

export type GuideSkill = (typeof GUIDE_SKILLS)[number];

export function skillUrl(skill: GuideSkill): string {
  return `${SKILLS_SITE_URL}/skills/${skill}`;
}
