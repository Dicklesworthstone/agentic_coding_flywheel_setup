/**
 * AgentHeroCard / agentPersonalities Tests
 *
 * Structural tests for the agent-card system after the gmi -> agy migration
 * (bd-47kjh.10.1.1). Runtime rendering of the hero-card carousel is covered by
 * Playwright E2E (e2e/antigravity-pages.spec.ts).
 *
 * These tests verify:
 * - The AgentHeroCard component export exists and is callable
 * - agentPersonalities is exhaustive over the AgentType union (the
 *   Record<AgentType, ...> exhaustiveness that gates `next build`)
 * - antigravity is a first-class agent with a non-empty, distinct entry
 * - The legacy gemini entry is retained (no over-migration)
 */

import { describe, test, expect } from "bun:test";
import {
  AgentHeroCard,
  agentPersonalities,
  type AgentType,
} from "./AgentHeroCard";

// Compile-time exhaustiveness guard: if a member is added to AgentType without a
// matching agentPersonalities entry (or vice-versa), this line fails type-check.
const _exhaustive: Record<AgentType, unknown> = agentPersonalities;
void _exhaustive;

const EXPECTED_AGENTS: AgentType[] = [
  "claude",
  "codex",
  "antigravity",
  "gemini",
];

describe("AgentHeroCard component", () => {
  test("AgentHeroCard is exported as a function", () => {
    expect(typeof AgentHeroCard).toBe("function");
  });

  test("AgentHeroCard is a valid React component (has name)", () => {
    expect(AgentHeroCard.name).toBe("AgentHeroCard");
  });
});

describe("agentPersonalities exhaustiveness", () => {
  test("has exactly the expected agent keys", () => {
    expect(Object.keys(agentPersonalities).sort()).toEqual(
      [...EXPECTED_AGENTS].sort(),
    );
  });

  test("every agent has a non-empty gradient and tagline", () => {
    for (const agent of EXPECTED_AGENTS) {
      const p = agentPersonalities[agent];
      expect(p).toBeDefined();
      expect(typeof p.gradient).toBe("string");
      expect(p.gradient.length).toBeGreaterThan(0);
      expect(typeof p.tagline).toBe("string");
      expect(p.tagline.length).toBeGreaterThan(0);
    }
  });
});

describe("antigravity is a first-class agent", () => {
  test("antigravity entry exists with a full (non-stub) personality", () => {
    const agy = agentPersonalities.antigravity;
    expect(agy).toBeDefined();
    // The pinned model is the defining trait of the Antigravity CLI.
    expect(agy.tagline).toContain("Gemini 3.8 Flash");
    expect(agy.gradient).toContain("purple");
    expect(agy.glowColor.length).toBeGreaterThan(0);
    expect(agy.bgGlow.length).toBeGreaterThan(0);
    expect(agy.borderHover.length).toBeGreaterThan(0);
  });

  test("antigravity has a visually distinct gradient from gemini", () => {
    expect(agentPersonalities.antigravity.gradient).not.toBe(
      agentPersonalities.gemini.gradient,
    );
  });
});

describe("legacy gemini retained (no over-migration)", () => {
  test("gemini entry is still present and labeled legacy", () => {
    expect(agentPersonalities.gemini).toBeDefined();
    expect(agentPersonalities.gemini.tagline.toLowerCase()).toContain("legacy");
  });
});
