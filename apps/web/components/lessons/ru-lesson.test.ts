/**
 * RU Lesson Component Tests
 *
 * Structural tests for the RuLesson component.
 * Runtime rendering is covered by Playwright E2E tests (e2e/ru-pages.spec.ts).
 *
 * These tests verify:
 * - Component export exists and is callable
 * - Lesson registry includes RU
 * - Commands data includes RU
 * - Flywheel data includes RU
 */

import { describe, expect, test } from "bun:test";
import { COMMANDS } from "../../lib/commands";
import { flywheelTools, synergyExplanations, workflowScenarios } from "../../lib/flywheel";
import { LESSONS } from "../../lib/lessons";
import { RuLesson } from "./ru-lesson";

describe("RuLesson component", () => {
  test("RuLesson is exported as a function", () => {
    expect(typeof RuLesson).toBe("function");
  });

  test("RuLesson is a valid React component (has name)", () => {
    expect(RuLesson.name).toBe("RuLesson");
  });
});

describe("RU lesson registry", () => {
  test("RU lesson exists in lessons array", () => {
    const ruLesson = LESSONS.find((l) => l.slug === "ru");
    expect(ruLesson).toBeDefined();
    expect(ruLesson?.title).toContain("RU");
  });

  test("RU lesson has required fields", () => {
    const ruLesson = LESSONS.find((l) => l.slug === "ru");
    expect(ruLesson?.id).toBeDefined();
    expect(ruLesson?.slug).toBe("ru");
    expect(ruLesson?.title).toBeDefined();
    expect(ruLesson?.description).toBeDefined();
    expect(ruLesson?.duration).toBeDefined();
  });

  test("RU lesson has valid duration", () => {
    const ruLesson = LESSONS.find((l) => l.slug === "ru");
    expect(ruLesson?.duration).toBeDefined();
    expect(typeof ruLesson?.duration).toBe("string");
    expect(ruLesson?.duration).toMatch(/\d+\s*min/); // e.g., "10 min"
  });
});

describe("RU in commands registry", () => {
  test("RU command exists", () => {
    const ruCommand = COMMANDS.find((c) => c.name === "ru");
    expect(ruCommand).toBeDefined();
  });

  test("RU command has proper metadata", () => {
    const ruCommand = COMMANDS.find((c) => c.name === "ru");
    expect(ruCommand?.fullName).toBe("Repo Updater");
    expect(ruCommand?.description).toBeDefined();
    expect(ruCommand?.category).toBe("stack");
  });
});

describe("RU in flywheel tools", () => {
  test("RU tool exists in flywheelTools", () => {
    const ruTool = flywheelTools.find((t) => t.id === "ru");
    expect(ruTool).toBeDefined();
  });

  test("RU tool has proper metadata", () => {
    const ruTool = flywheelTools.find((t) => t.id === "ru");
    expect(ruTool?.name).toBe("Repo Updater");
    expect(ruTool?.shortName).toBe("RU");
    expect(ruTool?.description).toBeDefined();
  });

  test("RU tool has connections to other tools", () => {
    const ruTool = flywheelTools.find((t) => t.id === "ru");
    expect(ruTool?.connectsTo).toBeDefined();
    expect(ruTool?.connectsTo?.length).toBeGreaterThan(0);
  });
});

describe("RU in workflow scenarios", () => {
  test("workflow scenarios include RU", () => {
    const hasRuScenario = workflowScenarios.some((s) =>
      s.steps?.some((step) => step.tool === "ru"),
    );
    expect(hasRuScenario).toBe(true);
  });

  test("RU workflow scenarios have valid structure", () => {
    const ruScenarios = workflowScenarios.filter((s) =>
      s.steps?.some((step) => step.tool === "ru"),
    );

    for (const scenario of ruScenarios) {
      expect(scenario.title).toBeDefined();
      expect(scenario.description).toBeDefined();
      expect(scenario.steps?.length).toBeGreaterThan(0);
    }
  });
});

describe("RU in synergy explanations", () => {
  test("synergy explanations include RU", () => {
    const hasRuSynergy = synergyExplanations.some((s) => s.tools?.includes("ru"));
    expect(hasRuSynergy).toBe(true);
  });

  test("RU synergies have proper structure", () => {
    const ruSynergies = synergyExplanations.filter((s) => s.tools?.includes("ru"));

    for (const synergy of ruSynergies) {
      expect(synergy.title).toBeDefined();
      expect(synergy.description).toBeDefined();
      expect(synergy.tools?.length).toBeGreaterThanOrEqual(2);
    }
  });
});
