/**
 * The parts of the two long-form guides, in reading order.
 *
 * One list per guide drives each guide's section headings, its navigation
 * (sidebar, phone rail and contents sheet), the "Up next" links between
 * parts, the cover's contents card, and the guide covers on the landing page.
 * lib/complete-guide.test.ts checks every list against the page that renders
 * it, along with the prompt and exhibit counts below.
 */

export interface GuidePart {
  /** Fragment id of the part's <section>. */
  id: string;
  /** Part number ("1"…); empty for an unnumbered interlude. */
  number: string;
  /** Short label for navigation. */
  label: string;
  /** The part's heading. */
  title: string;
}

export const COMPLETE_GUIDE_OUTLINE: readonly GuidePart[] = [
  { id: "workflow", number: "1", label: "Workflow", title: "The Complete Workflow" },
  { id: "philosophy", number: "2", label: "Why plan first", title: "Why Planning Is 85% of the Work" },
  { id: "planning", number: "3", label: "The plan", title: "Creating & Refining the Markdown Plan" },
  { id: "beads", number: "4", label: "Plan → beads", title: "Converting the Plan into Beads" },
  { id: "polishing", number: "5", label: "Polish beads", title: "Check Your Beads N Times, Implement Once" },
  { id: "idea-wizard", number: "", label: "Existing projects", title: "Adding Features to Existing Projects" },
  { id: "coordination", number: "6", label: "Coordination", title: "The Coordination Stack" },
  { id: "swarm", number: "7", label: "The swarm", title: "Launching & Running the Swarm" },
  { id: "review", number: "8", label: "Review & harden", title: "Review, Testing & Hardening" },
  { id: "toolchain", number: "9", label: "Toolchain", title: "The Complete Toolchain" },
  { id: "flywheel", number: "10", label: "Flywheel", title: "The Flywheel Effect" },
];

export const CORE_FLYWHEEL_OUTLINE: readonly GuidePart[] = [
  { id: "why", number: "1", label: "Why start here", title: "Why a Simpler Starting Point" },
  { id: "terms", number: "2", label: "Five terms", title: "Five Terms You Need" },
  { id: "core-loop", number: "3", label: "The core loop", title: "The Core Loop" },
  { id: "three-tools", number: "4", label: "One machine", title: "The Three Tools Are a Single Machine" },
  { id: "artifact-ladder", number: "5", label: "Artifact ladder", title: "The Artifact Ladder" },
  { id: "example", number: "6", label: "Worked example", title: "A Concrete Example: Atlas Notes" },
  { id: "operating-rhythm", number: "7", label: "Operating rhythm", title: "The Operating Rhythm" },
  { id: "operator", number: "8", label: "The human’s job", title: "The Human’s Job" },
  { id: "failure-modes", number: "9", label: "Failure modes", title: "Common Failure Modes" },
  { id: "what-it-feels-like", number: "10", label: "When it clicks", title: "What It Feels Like Once It Clicks" },
  { id: "helpers", number: "11", label: "Helper tools", title: "Helper Utilities: DCG, UBS & CASS" },
  { id: "getting-started", number: "12", label: "Getting started", title: "Getting Started" },
];

/**
 * Stable, readable fragment ids for sub-headings ("planning-the-foundation-bundle")
 * and prompts ("prompt-" + slug of the title).
 */
export function guideSlug(text: string): string {
  return text
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 72)
    .replace(/-+$/, "");
}

/** Numbered parts only: an interlude is not a part. */
export function guidePartCount(outline: readonly GuidePart[]): number {
  return outline.filter((part) => part.number).length;
}

/** Interactive exhibits rendered on each page (checked against the page source). */
export const COMPLETE_GUIDE_EXHIBIT_COUNT = 11;
export const CORE_FLYWHEEL_EXHIBIT_COUNT = 7;

/** PromptBlock count on the core guide (the complete guide's lives in lib/complete-guide.ts). */
export const CORE_FLYWHEEL_PROMPT_COUNT = 5;

export const CORE_FLYWHEEL_REVIEWED_ON = "November 25, 2026";

export const GUIDE_SOURCE_BASE =
  "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/blob/main/apps/web/app";
export const GUIDE_ISSUES_URL =
  "https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup/issues";
