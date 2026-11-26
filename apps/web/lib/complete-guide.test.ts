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
import {
  COMPLETE_GUIDE_EXHIBIT_COUNT,
  COMPLETE_GUIDE_OUTLINE,
  CORE_FLYWHEEL_EXHIBIT_COUNT,
  CORE_FLYWHEEL_OUTLINE,
  CORE_FLYWHEEL_PROMPT_COUNT,
  guidePartCount,
  guideSlug,
} from "./guide-outlines";
import { GUIDE_SKILLS, skillUrl } from "./guide-skills";

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
const coreSource = await Bun.file(new URL("../app/core-flywheel/page.tsx", import.meta.url)).text();
const planEvolutionSource = await Bun.file(
  new URL("../components/complete-guide/plan-evolution-studio.tsx", import.meta.url),
).text();

describe("complete guide derived claims", () => {
  test("prompt count matches the rendered prompt blocks", () => {
    expect(pageSource.match(/<PromptBlock\b/g)?.length ?? 0).toBe(COMPLETE_GUIDE_PROMPT_COUNT);
  });

  test("the core flywheel's prompt count matches its prompt blocks", () => {
    expect(coreSource.match(/<PromptBlock\b/g)?.length ?? 0).toBe(CORE_FLYWHEEL_PROMPT_COUNT);
  });

  test("each guide's outline lists the sections its page renders, in order", () => {
    for (const [source, outline, name] of [
      [pageSource, COMPLETE_GUIDE_OUTLINE, "COMPLETE_GUIDE_OUTLINE"],
      [coreSource, CORE_FLYWHEEL_OUTLINE, "CORE_FLYWHEEL_OUTLINE"],
    ] as const) {
      const sections = [...source.matchAll(/<GuideSection\s+id="([^"]+)"/g)].map(([, id]) => id);
      expect(sections.length).toBeGreaterThan(5);
      expect(outline.map((part) => part.id)).toEqual(sections);
      // Each page hands its own outline to the article and the navigation.
      expect(source).toContain(`<GuideArticle outline={${name}}>`);
      expect(source).toContain(`items={${name}}`);
    }
  });

  test("each outline numbers its parts 1..n, with only interludes unnumbered", () => {
    for (const outline of [COMPLETE_GUIDE_OUTLINE, CORE_FLYWHEEL_OUTLINE]) {
      const numbers = outline.map((part) => part.number).filter(Boolean);
      expect(numbers).toEqual(numbers.map((_, index) => String(index + 1)));
      expect(guidePartCount(outline)).toBe(numbers.length);
      expect(new Set(outline.map((part) => part.id)).size).toBe(outline.length);
      for (const part of outline) expect(part.label && part.title).toBeTruthy();
    }
  });

  test("exhibit counts match the interactive exhibits each page renders", () => {
    const exhibits = (source: string) => source.match(/<[A-Z]\w*(?:Viz|Diagram|Studio|Ladder)\b/g)?.length ?? 0;
    expect(exhibits(pageSource)).toBe(COMPLETE_GUIDE_EXHIBIT_COUNT);
    expect(exhibits(coreSource)).toBe(CORE_FLYWHEEL_EXHIBIT_COUNT);
  });

  test("skill notes and the guide skill list stay in step", () => {
    const sources = [pageSource, coreSource];
    const notes = sources.flatMap((source) => [...source.matchAll(/<SkillNote\s+skills=\{\[([^\]]*)\]\}/g)]);
    // Every note is parsed: one the pattern missed would hide its slugs from the check below.
    expect(notes.length).toBe(sources.flatMap((source) => [...source.matchAll(/<SkillNote\b/g)]).length);
    const named = notes.flatMap(([, list]) => [...list.matchAll(/"([^"]+)"/g)].map(([, slug]) => slug));
    // Every listed skill is recommended somewhere, so the list holds no dead entries.
    expect([...new Set(named)].sort()).toEqual([...GUIDE_SKILLS].sort());
    expect(skillUrl("beads-workflow")).toBe("https://jeffreys-skills.md/skills/beads-workflow");
  });

  test("prompt titles make unique anchor ids on each page", () => {
    for (const source of [pageSource, coreSource]) {
      const titles = [...source.matchAll(/<PromptBlock\s+title="([^"]+)"/g)].map(([, title]) => title);
      expect(titles.length).toBe(source.match(/<PromptBlock\b/g)?.length ?? -1);
      const ids = titles.map((title) => guideSlug(title));
      expect(new Set(ids).size).toBe(ids.length);
    }
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
    expect(COMPLETE_GUIDE_MODELS.antigravity).toBe("Gemini 4 Neon (XHigh)");
    expect(COMPLETE_GUIDE_MODELS.restrictedPreview).toBe("Claude Mythos 5.2");
    // JSX prose may be re-wrapped by the formatter; compare rendered spacing.
    expect(pageSource.replace(/\s+/g, " ")).toContain("is not generally available");
    expect(pageSource).not.toContain("Grok Heavy");
    expect(pageSource).not.toContain("Claude Code (Opus)");
    expect(planEvolutionSource).toContain("COMPLETE_GUIDE_MODELS");
  });

  test("the core flywheel names models through the shared table", async () => {
    // A literal name here would go stale on the next model refresh while the
    // complete guide (which reads COMPLETE_GUIDE_MODELS) moved on.
    const coreSources = await Promise.all(
      ["../app/core-flywheel/page.tsx", "../components/core-flywheel/human-agent-timeline-viz.tsx"].map(
        (path) => Bun.file(new URL(path, import.meta.url)).text(),
      ),
    );
    for (const source of coreSources) {
      expect(source).toContain("COMPLETE_GUIDE_MODELS");
      for (const model of Object.values(COMPLETE_GUIDE_MODELS)) {
        expect(source).not.toContain(model.replace(/^Claude /, ""));
      }
    }
  });

  test("installer examples come from the canonical builder contract", () => {
    expect(buildInstallCommand("vibe", null)).toBe(
      'curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/agentic_coding_flywheel_setup/main/install.sh" | bash -s -- --yes --mode vibe --target-ubuntu=26.04',
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
