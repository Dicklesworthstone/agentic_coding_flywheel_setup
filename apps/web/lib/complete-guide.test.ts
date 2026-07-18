import { describe, expect, test } from "bun:test";

import { buildInstallCommand } from "./commandBuilder";
import {
  COMPLETE_GUIDE_MODELS,
  COMPLETE_GUIDE_PHASE_COUNT,
  COMPLETE_GUIDE_PROMPT_COUNT,
  VALIDATION_GATES,
} from "./complete-guide";
import { manifestModules } from "./generated/manifest-modules";
import { manifestTools } from "./generated/manifest-tools";

const enabledStackModuleIds = new Set(
  manifestModules
    .filter((module) => module.category === "stack" && module.enabledByDefault)
    .map((module) => module.id),
);
const completeGuideStackTools = manifestTools.filter((tool) =>
  enabledStackModuleIds.has(tool.moduleId),
);

const pageSource = await Bun.file(
  new URL("../app/complete-guide/page.tsx", import.meta.url),
).text();
const openGraphSource = await Bun.file(
  new URL("../app/complete-guide/opengraph-image.tsx", import.meta.url),
).text();
const twitterSource = await Bun.file(
  new URL("../app/complete-guide/twitter-image.tsx", import.meta.url),
).text();
const planEvolutionSource = await Bun.file(
  new URL("../components/complete-guide/plan-evolution-studio.tsx", import.meta.url),
).text();

describe("complete guide derived claims", () => {
  test("prompt count matches the rendered prompt blocks", () => {
    expect(pageSource.match(/<PromptBlock\b/g)?.length ?? 0).toBe(
      COMPLETE_GUIDE_PROMPT_COUNT,
    );
  });

  test("validation gates and workflow phase count remain explicit", () => {
    expect(VALIDATION_GATES).toHaveLength(6);
    expect(COMPLETE_GUIDE_PHASE_COUNT).toBe(13);
  });

  test("the tool list is a unique projection of the generated manifest", () => {
    expect(completeGuideStackTools.length).toBeGreaterThan(11);
    expect(new Set(completeGuideStackTools.map((tool) => tool.moduleId)).size).toBe(
      completeGuideStackTools.length,
    );
  });

  test("intentional current-model exceptions remain explicit", () => {
    expect(COMPLETE_GUIDE_MODELS.antigravity).toBe("Gemini 3.1 Pro (High)");
    expect(COMPLETE_GUIDE_MODELS.restrictedPreview).toBe("Claude Mythos Preview");
    expect(pageSource).toContain("is not generally available");
    expect(pageSource).not.toContain("Grok Heavy");
    expect(pageSource).not.toContain("Claude Code (Opus)");
    expect(planEvolutionSource).toContain("COMPLETE_GUIDE_MODELS");
  });

  test("installer examples come from the canonical builder contract", () => {
    expect(buildInstallCommand("vibe", null)).toBe(
      'curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh?$(date +%s)" | bash -s -- --yes --mode vibe',
    );
    expect(pageSource).toContain("CURRENT_INSTALL_COMMAND");
    expect(pageSource).toContain("PINNED_INSTALL_COMMAND");
  });

  test("social cards consume shared counts instead of stale literals", () => {
    for (const source of [openGraphSource, twitterSource]) {
      expect(source).toContain("COMPLETE_GUIDE_PROMPT_COUNT");
      expect(source).toContain("VALIDATION_GATES.length");
      expect(source).toContain("COMPLETE_GUIDE_PHASE_COUNT");
      expect(source).not.toContain("27 Core Prompts");
      expect(source).not.toContain("8 Validation Gates");
    }
  });
});
