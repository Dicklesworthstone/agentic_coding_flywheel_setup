import { describe, expect, test } from "bun:test";
import { LESSONS } from "./lessons";
import { recommendLearningPath, type LearningPathInput } from "./learningPath";
import { resolveModuleSelection } from "./moduleSelection";

describe("local learning recommendations", () => {
  test("no-state beginner receives an accessible first lesson and useful fallback", () => {
    const path = recommendLearningPath({ completedLessons: [] });
    expect(path.persona).toBe("getting-started");
    expect(path.fallbackReason).toBe("no-selection");
    expect(path.recommendations.map((entry) => entry.href)).toEqual(["/learn/welcome", "/learn/commands"]);
  });
  test.each(["minimal", "full", "agents-only", "stack-only"] as const)("%s uses its actual selected modules", (profile) => {
    const selection = { profile };
    const path = recommendLearningPath({ completedLessons: [0, 1], selection });
    expect(path.recommendations[0].href).toBe("/learn/ssh-basics");
    expect(path.recommendations).toHaveLength(3);
    const plan = resolveModuleSelection(selection);
    expect(plan.ok).toBe(true);
    expect(path.signalIds).toContain("selected-modules");
    expect(path.recommendations.some((entry) => entry.href.startsWith("/learn/tools/"))).toBe(true);
    expect(path.recommendations.every((entry) => !entry.reason.includes("installed"))).toBe(true);
  });
  test("team workflow with a full profile prioritizes coordination and selected Agent Mail", () => {
    const path = recommendLearningPath({ completedLessons: [0], selection: { profile: "full" }, goal: "swarm" });
    expect(path.persona).toBe("team");
    expect(path.recommendations.map((entry) => entry.href)).toEqual(["/core-flywheel", "/learn/linux-basics", "/learn/tools/agent-mail"]);
  });
  test.each([{ goal: "recover" as const }, { doctorNeedsAttention: true }])("failed-install context prioritizes diagnostic recovery", (signal) => {
    const path = recommendLearningPath({ completedLessons: [0], ...signal });
    expect(path.persona).toBe("recovery");
    expect(path.recommendations[0].href).toBe("/wizard/status-check");
    expect(path.recommendations[0].kind).toBe("recovery");
    expect(path.recommendations[0].reason).not.toContain("run the installer");
  });
  test("invalid selection produces a review action without accepting unknown modules", () => {
    const path = recommendLearningPath({ completedLessons: [], selection: { onlyModules: ["PRIVATE_INVALID_MODULE"] } });
    expect(path.fallbackReason).toBe("invalid-selection");
    expect(path.recommendations[0].id).toBe("review-selection");
    expect(JSON.stringify(path)).not.toContain("PRIVATE_INVALID_MODULE");
    expect(path.recommendations.some((entry) => entry.id.startsWith("tool-"))).toBe(false);
  });
  test("excluded modules never reappear as recommended tool references", () => {
    const path = recommendLearningPath({ completedLessons: [0], selection: { profile: "minimal", skipModules: ["stack.beads_rust", "stack.mcp_agent_mail"], noDeps: true } });
    expect(path.recommendations.some((entry) => ["tool-beads", "tool-agent-mail"].includes(entry.id))).toBe(false);
  });
  test("every recommended sequential lesson is the actual first unfinished lesson", () => {
    for (let count = 0; count <= LESSONS.length; count++) {
      const completedLessons = LESSONS.slice(0, count).map((lesson) => lesson.id);
      const path = recommendLearningPath({ completedLessons, selection: { profile: "full" } });
      const suggested = path.recommendations.filter((entry) => entry.kind === "lesson");
      expect(suggested.map((entry) => entry.href)).toEqual(count === LESSONS.length ? [] : [`/learn/${LESSONS[count].slug}`]);
      expect(new Set(path.recommendations.map((entry) => entry.id)).size).toBe(path.recommendations.length);
      expect(path.recommendations.length).toBeLessThanOrEqual(3);
    }
  });
  test("complete and malformed progress have safe, deterministic results without mutation", () => {
    const input: LearningPathInput = { completedLessons: [0, 0, -1, NaN, 99999, 1.5] };
    const before = [...input.completedLessons];
    expect(recommendLearningPath(input)).toEqual(recommendLearningPath(input));
    expect(input.completedLessons).toEqual(before);
    expect(recommendLearningPath(input).recommendations[0].href).toBe("/learn/linux-basics");
    const done = recommendLearningPath({ completedLessons: LESSONS.map((lesson) => lesson.id) });
    expect(done.persona).toBe("all-complete");
    expect(done.recommendations[0].href).toBe("/learn/commands");
  });
});
