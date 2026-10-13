import { errors, expect, test, type Page } from "@playwright/test";
import { LESSONS } from "../lib/lessons";

/**
 * Regression guard for the 2026-10-07 contrast sweep (bd-hsncl, bd-152ke):
 * axe-core color-contrast reported 0 nodes at 390px and only the exempt
 * decoration below at 1280px. Covers the routes and densest lessons that
 * sweep fixed; every Playwright project (desktop and mobile) runs it.
 */
// Playwright compiles specs here to CommonJS, so require.resolve is available.
const AXE_SOURCE = require.resolve("axe-core/axe.min.js");

// The 8rem section numerals on long guides are aria-hidden, unselectable pure
// decoration (WCAG 1.4.3 exempts it). Nothing else is excluded.
const DECORATIVE = '[aria-hidden="true"].select-none';

const ROUTES = [
  "/",
  "/learn",
  "/learn/welcome",
  "/learn/github-cli",
  "/learn/real-world-case-study",
  "/learn/bv",
  "/core-flywheel",
  "/complete-guide",
  "/tldr",
  "/cloud-agents",
  "/wizard/os-selection",
];

// Scroll-reveal content below the fold is still fading in until it has been in
// view; measure the settled colors a reader sees, not an animation frame.
async function settle(page: Page): Promise<void> {
  await page.evaluate(async () => {
    const step = Math.max(200, Math.floor(window.innerHeight * 0.8));
    for (let y = 0; y < document.documentElement.scrollHeight; y += step) {
      window.scrollTo(0, y);
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    window.scrollTo(0, 0);
    const running = document.getAnimations().map((animation) => animation.finished.catch(() => undefined));
    await Promise.race([Promise.all(running), new Promise((resolve) => setTimeout(resolve, 3000))]);
  });
}

async function contrastViolations(page: Page): Promise<string[]> {
  await settle(page);
  await page.addScriptTag({ path: AXE_SOURCE });
  return page.evaluate(async (decorative) => {
    type AxeNode = { target: string[]; failureSummary?: string };
    type AxeResult = { violations: { nodes: AxeNode[] }[] };
    const axe = (window as unknown as { axe: { run: (context: unknown, options: unknown) => Promise<AxeResult> } }).axe;
    const result = await axe.run(
      { include: [["body"]], exclude: [[decorative]] },
      { runOnly: { type: "rule", values: ["color-contrast"] }, resultTypes: ["violations"] },
    );
    return result.violations.flatMap((violation) =>
      violation.nodes.map((node) => `${node.target.join(" ")} :: ${(node.failureSummary ?? "").split("\n")[1] ?? ""}`.trim()),
    );
  }, DECORATIVE);
}

test.describe("Color contrast (WCAG 1.4.3)", () => {
  test.use({ contextOptions: { reducedMotion: "reduce" } });

  for (const route of ROUTES) {
    test(`${route} has no color-contrast violations`, async ({ page }) => {
      await page.goto(route);
      await page.waitForLoadState("networkidle", { timeout: 10000 }).catch(() => {});
      expect(await contrastViolations(page)).toEqual([]);
    });
  }
});

/** Informative text must meet our 12px design floor after CSS/SVG scaling. */
async function tinyLabels(page: Page): Promise<string[]> {
  const requireLessonBody = new URL(page.url()).pathname.startsWith("/learn/");
  return page.evaluate(({ decorative, requireLessonBody }) => {
    const root = document.querySelector("main");
    if (!root) throw new Error("Missing instructional main content");
    const failures: string[] = [];
    let bodyLabels = 0;
    for (const element of root.querySelectorAll("*")) {
      // Measure the actual text-bearing element, not an ancestor inheriting
      // the same font. Visually hidden accessibility text is not a label.
      if (element.closest(`${decorative}, .sr-only`)) continue;
      const text = Array.from(element.childNodes)
        .filter((node) => node.nodeType === Node.TEXT_NODE)
        .map((node) => node.textContent ?? "")
        .join(" ").trim();
      if (!text) continue;
      const rect = element.getBoundingClientRect();
      if (!rect.width || !rect.height) continue;
      let hidden = false;
      let cssScale = 1;
      for (let ancestor: Element | null = element; ancestor; ancestor = ancestor.parentElement) {
        const style = getComputedStyle(ancestor);
        if (style.visibility !== "visible" || Number(style.opacity) === 0) {
          hidden = true;
          break;
        }
        if (style.transform !== "none") {
          const matrix = new DOMMatrixReadOnly(style.transform);
          cssScale *= Math.min(
            Math.hypot(matrix.m11, matrix.m12, matrix.m13),
            Math.hypot(matrix.m21, matrix.m22, matrix.m23),
          );
        }
        if (style.scale && style.scale !== "none") {
          const axes = style.scale.split(/\s+/).slice(0, 2).map((value) =>
            Number.parseFloat(value) / (value.endsWith("%") ? 100 : 1),
          );
          cssScale *= Math.min(...axes);
        }
      }
      if (hidden) continue;
      if (element.closest("article")) bodyLabels += 1;
      let size = Number.parseFloat(getComputedStyle(element).fontSize);
      if (element instanceof SVGGraphicsElement) {
        const matrix = element.getScreenCTM();
        if (!matrix) throw new Error("Missing rendered SVG text transform");
        size *= Math.min(Math.hypot(matrix.a, matrix.b), Math.hypot(matrix.c, matrix.d));
      } else {
        size *= cssScale;
      }
      if (size < 11.95) failures.push(`${element.tagName}: ${text.slice(0, 90)} (${size.toFixed(2)}px)`);
    }
    if (requireLessonBody && bodyLabels === 0) {
      throw new Error("No visible instructional text was measured in the lesson body");
    }
    return failures;
  }, { decorative: DECORATIVE, requireLessonBody });
}

test.describe("Instructional text readability (bd-64cg3)", () => {
  test.use({ contextOptions: { reducedMotion: "reduce" } });
  const readingRoutes = [
    ...LESSONS.map((lesson) => `/learn/${lesson.slug}`),
    "/complete-guide", "/core-flywheel", "/tldr", "/cloud-agents", "/",
  ];

  test.beforeEach(async ({ page }) => {
    await page.addInitScript((ids) => {
      localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify(ids));
    }, LESSONS.map((lesson) => lesson.id));
  });

  for (const route of readingRoutes) {
    test(`${route} keeps readable labels and contains horizontal overflow`, async ({ page }) => {
      test.setTimeout(60000);
      const runtimeErrors: string[] = [];
      page.on("pageerror", (error) => runtimeErrors.push(error.message));
      await page.goto(route);
      await expect(page.locator("main")).toBeVisible();
      if (route.startsWith("/learn/")) {
        await expect(page.locator("main article section").first()).toBeVisible();
        await expect(page.getByRole("status", { name: "Loading lesson" })).toHaveCount(0);
        expect(await page.locator("main article").innerText()).not.toContain("Lesson content not found");
      }
      await settle(page);
      expect(await tinyLabels(page)).toEqual([]);
      const widths = await page.evaluate(() => ({
        content: document.documentElement.scrollWidth,
        viewport: document.documentElement.clientWidth,
      }));
      expect(widths.content).toBe(widths.viewport);
      expect(runtimeErrors).toEqual([]);
    });
  }

  test("font guard detects a tiny informative label", async ({ page }) => {
    await page.goto("/learn/welcome");
    await expect(page.locator("main")).toBeVisible();
    await settle(page);
    await page.evaluate(() => {
      const label = document.createElement("p");
      label.textContent = "Readability negative control";
      label.style.fontSize = "10px";
      document.querySelector("main")!.append(label);
      const scaledLabel = document.createElement("p");
      scaledLabel.textContent = "Scaled readability negative control";
      scaledLabel.style.fontSize = "12px";
      scaledLabel.style.transform = "scale(0.75)";
      document.querySelector("main")!.append(scaledLabel);
      const individualScale = document.createElement("p");
      individualScale.textContent = "Individual scale negative control";
      individualScale.style.fontSize = "12px";
      individualScale.style.scale = "0.75";
      document.querySelector("main")!.append(individualScale);

      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      svg.setAttribute("viewBox", "0 0 200 80");
      svg.setAttribute("width", "100");
      svg.setAttribute("height", "40");
      for (const [index, [text, fontSize]] of [
        ["Tiny SVG negative control", "10"],
        ["Scaled SVG negative control", "12"],
      ].entries()) {
        const label = document.createElementNS(svg.namespaceURI, "text");
        label.textContent = text;
        label.setAttribute("x", "0");
        label.setAttribute("y", String(20 + index * 30));
        label.setAttribute("font-size", fontSize);
        svg.append(label);
      }
      document.querySelector("main")!.append(svg);
    });
    expect(await tinyLabels(page)).toContain("P: Readability negative control (10.00px)");
    expect(await tinyLabels(page)).toContain("P: Scaled readability negative control (9.00px)");
    expect(await tinyLabels(page)).toContain("P: Individual scale negative control (9.00px)");
    expect(await tinyLabels(page)).toContain("text: Tiny SVG negative control (5.00px)");
    expect(await tinyLabels(page)).toContain("text: Scaled SVG negative control (6.00px)");
  });

  test("reduced motion hydrates cleanly and follows preference changes", async ({ page }) => {
    const runtimeErrors: string[] = [];
    page.on("pageerror", (error) => runtimeErrors.push(error.message));
    await page.goto("/core-flywheel");
    const stillDot = page.locator('svg[aria-label="Core loop diagram with six stages arranged in a circle"] circle[r="4"][fill-opacity="0.8"]');
    await expect(stillDot).toHaveCount(1);
    await page.emulateMedia({ reducedMotion: "no-preference" });
    await expect(stillDot).toHaveCount(0);
    await page.emulateMedia({ reducedMotion: "reduce" });
    await expect(stillDot).toHaveCount(1);
    expect(runtimeErrors).toEqual([]);
  });

  test("font guard rejects an empty lesson body", async ({ page }) => {
    await page.goto("/learn/welcome");
    await expect(page.locator("main article section").first()).toBeVisible();
    await page.evaluate(() => {
      document.querySelector("main article")!.replaceChildren();
    });
    await expect(tinyLabels(page)).rejects.toThrow("No visible instructional text was measured in the lesson body");
  });

  test("reduced-motion synergy content stays visible before scroll reveal", async ({ page }) => {
    await page.goto("/tldr");
    const scroller = page.getByRole("region", { name: "Tool synergy diagram (scrolls sideways when needed)" });
    // Playwright visibility and the font inspector both allow opacity-zero
    // content. Require real visual opacity without firing scroll observers.
    await expect.poll(() => scroller.evaluate((element) => {
      let opacity = 1;
      for (let node: Element | null = element; node; node = node.parentElement) {
        opacity *= Number(getComputedStyle(node).opacity);
      }
      return opacity;
    })).toBe(1);
    const label = scroller.locator("text").filter({ hasText: "FLYWHEEL" });
    await expect.poll(() => label.evaluate((element) => {
      let opacity = 1;
      for (let node: Element | null = element; node; node = node.parentElement) {
        opacity *= Number(getComputedStyle(node).opacity);
      }
      return opacity;
    })).toBe(1);
  });

  test("diagram keyboard scrolling preserves the lesson, while main navigation still works", async ({ page }) => {
    await page.goto("/learn/ntm-core");
    // The hotkey handler is deliberately inactive until stored progress loads.
    await expect(page.locator('a[aria-label="Next lesson"]')).toHaveAttribute("href", "/learn/ntm-palette");
    await settle(page);
    const scroller = page.getByRole("region", { name: "NTM cockpit diagram (scrolls sideways on small screens)" });
    await expect(scroller).toBeVisible();
    // Force a narrow, realistic nested container even in the desktop project.
    await scroller.evaluate((element) => {
      element.style.maxWidth = "300px";
      element.scrollLeft = 0;
    });
    const originalURL = page.url();
    await scroller.focus();
    await scroller.press("ArrowRight");
    // Router navigation is asynchronous; an immediate URL check can pass before
    // the wrong shortcut navigates. Only a bounded navigation timeout is expected.
    await expect(page.waitForURL((url) => url.href !== originalURL, { timeout: 1000 }))
      .rejects.toBeInstanceOf(errors.TimeoutError);
    await expect.poll(() => scroller.evaluate((element) => element.scrollLeft)).toBeGreaterThan(0);
    await page.locator("main").focus();
    await page.keyboard.press("ArrowRight");
    await expect(page).toHaveURL(/\/learn\/ntm-palette$/);
  });

  test("core diagram arrow keys preserve native panning and unrelated controls", async ({ page }) => {
    await page.goto("/core-flywheel");
    await settle(page);
    const scroller = page.locator('[role="region"][aria-label="Core loop diagram (scrolls sideways when needed)"]');
    const exhibit = scroller.locator("../..");
    // The phone layout uses stage controls instead of this desktop SVG.
    if (await scroller.isVisible()) {
      await scroller.evaluate((element) => {
        element.style.maxWidth = "250px";
        element.scrollLeft = 0;
        element.scrollIntoView({ block: "center", behavior: "instant" });
      });
      await expect.poll(() => scroller.evaluate((element) => element.scrollWidth - element.clientWidth)).toBeGreaterThan(0);
      await expect(exhibit.getByRole("heading", { name: "Plan", exact: true })).toBeVisible();
      await scroller.focus();
      await expect(scroller).toBeFocused();
      await page.waitForTimeout(250);
      await scroller.press("ArrowRight");
      await expect.poll(() => scroller.evaluate((element) => element.scrollLeft)).toBeGreaterThan(0);
      await page.waitForTimeout(500);
      await expect(exhibit.getByRole("heading", { name: "Plan", exact: true })).toBeVisible();
    }
    // Space must activate the real stage button, not the window's auto-tour.
    const stageButton = page.getByRole("button", { name: "Go to stage: Encode" });
    await stageButton.focus();
    await stageButton.press("Space");
    await expect(exhibit.getByRole("heading", { name: "Encode", exact: true })).toBeVisible();
    await page.locator("main").evaluate((element) => element.focus({ preventScroll: true }));
    await page.keyboard.press("ArrowLeft");
    await expect(exhibit.getByRole("heading", { name: "Plan", exact: true })).toBeVisible();
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.keyboard.press("ArrowRight");
    await page.waitForTimeout(500);
    await expect(exhibit.getByRole("heading", { name: "Plan", exact: true })).toBeVisible();
  });
});
