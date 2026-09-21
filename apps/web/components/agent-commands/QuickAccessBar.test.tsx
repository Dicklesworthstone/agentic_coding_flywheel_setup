/**
 * QuickAccessBar Tests
 *
 * Structural tests for the quick-launch bar after the gmi -> agy migration
 * (bd-47kjh.10.1.1). The button render + click-to-copy behavior is exercised
 * live in Playwright E2E (e2e/antigravity-pages.spec.ts); here we assert the
 * underlying quickCommands data.
 *
 * These tests verify:
 * - The QuickAccessBar component export exists and is callable
 * - An Antigravity row exists that copies exactly `agy`
 * - The legacy gmi row is retained and clearly labeled (no over-migration)
 */

import { describe, expect, test } from "bun:test";
import { QuickAccessBar, quickCommands } from "./QuickAccessBar";

describe("QuickAccessBar component", () => {
  test("QuickAccessBar is exported as a function", () => {
    expect(typeof QuickAccessBar).toBe("function");
  });

  test("QuickAccessBar is a valid React component (has name)", () => {
    expect(QuickAccessBar.name).toBe("QuickAccessBar");
  });
});

describe("quickCommands data", () => {
  test("forward trio is cc / cod / agy in order", () => {
    const aliases = quickCommands.map((c) => c.alias);
    expect(aliases.slice(0, 3)).toEqual(["cc", "cod", "agy"]);
  });

  test("the agy row maps to the antigravity agentType and copies exactly `agy`", () => {
    const agy = quickCommands.find((c) => c.alias === "agy");
    expect(agy).toBeDefined();
    expect(agy?.agentType).toBe("antigravity");
    // The copied text IS the alias (handleCopy copies command.alias verbatim).
    expect(agy?.alias).toBe("agy");
    expect(agy?.label).toBe("Antigravity");
  });

  test("legacy gmi row is retained and labeled legacy", () => {
    const gmi = quickCommands.find((c) => c.alias === "gmi");
    expect(gmi).toBeDefined();
    expect(gmi?.agentType).toBe("gemini");
    expect(gmi?.label.toLowerCase()).toContain("legacy");
  });

  test("every row has a non-empty icon gradient", () => {
    for (const c of quickCommands) {
      expect(typeof c.iconGradient).toBe("string");
      expect(c.iconGradient.length).toBeGreaterThan(0);
    }
  });
});
