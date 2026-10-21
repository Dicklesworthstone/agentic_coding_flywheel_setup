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
  return scanContrast(page);
}

/** Scan an already-settled page without traversing it a second time. */
async function scanContrast(page: Page): Promise<string[]> {
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

/** Informative SVG labels must not depend on faint, translucent white paint. */
async function faintWhiteSvgLabels(page: Page): Promise<string[]> {
  return page.evaluate((decorative) => {
    const failures: string[] = [];
    for (const label of document.querySelectorAll("main svg text")) {
      if (label.closest(`${decorative}, .sr-only`)) continue;
      const text = label.textContent?.trim();
      const bounds = label.getBoundingClientRect();
      if (!text || !bounds.width || !bounds.height) continue;
      const style = getComputedStyle(label);
      const paint = style.fill.match(/^rgba?\(([^)]+)\)$/)?.[1].split(/[,\s/]+/).map(Number);
      if (!paint || paint.slice(0, 3).some((channel) => channel !== 255)) continue;
      let opacity = (paint[3] ?? 1) * Number(style.fillOpacity);
      let visible = true;
      for (let ancestor: Element | null = label; ancestor; ancestor = ancestor.parentElement) {
        const inherited = getComputedStyle(ancestor);
        if (inherited.visibility !== "visible" || Number(inherited.opacity) === 0) {
          visible = false;
          break;
        }
        opacity *= Number(inherited.opacity);
      }
      if (visible && opacity <= 0.55) failures.push(`${text.slice(0, 90)} (${opacity.toFixed(2)} alpha)`);
    }
    return failures;
  }, DECORATIVE);
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
      if (route.startsWith("/learn/")) {
        // Secondary lesson colors must work without the old inherited repair.
        // This is a no-op for migrated pages and reveals legacy class regressions.
        await page.locator("main").evaluate((main) => main.classList.remove("text-aa-floor"));
        expect(await scanContrast(page)).toEqual([]);
        expect(await faintWhiteSvgLabels(page)).toEqual([]);
      }
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

  test("contrast guard rejects faint text and accepts the semantic token", async ({ page }) => {
    await page.goto("/learn/welcome");
    await expect(page.locator("main article section").first()).toBeVisible();
    await settle(page);
    await page.evaluate(() => {
      const label = document.createElement("p");
      label.id = "lesson-contrast-control";
      label.textContent = "Readable secondary text control";
      Object.assign(label.style, {
        position: "fixed", top: "80px", left: "80px", zIndex: "9999",
        padding: "12px", fontSize: "16px", backgroundColor: "#000",
        color: "rgba(255,255,255,0.3)",
      });
      document.querySelector("main")!.append(label);
    });
    const faint = await scanContrast(page);
    expect(faint.some((violation) => violation.includes("lesson-contrast-control"))).toBe(true);
    await page.evaluate(() => {
      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      svg.id = "lesson-svg-color-control";
      svg.setAttribute("width", "280");
      svg.setAttribute("height", "48");
      Object.assign(svg.style, { position: "fixed", top: "140px", left: "40px", zIndex: "9999" });
      const label = document.createElementNS(svg.namespaceURI, "text");
      label.textContent = "SVG color policy control";
      label.setAttribute("x", "8");
      label.setAttribute("y", "24");
      label.setAttribute("font-size", "16");
      label.setAttribute("fill", "rgba(255,255,255,0.35)");
      svg.append(label);
      document.querySelector("main")!.append(svg);
    });
    expect(await faintWhiteSvgLabels(page)).toContain("SVG color policy control (0.35 alpha)");
    await page.locator("#lesson-svg-color-control").evaluate((svg) => {
      svg.style.opacity = "0.25";
      svg.querySelector("text")!.setAttribute("fill", "white");
    });
    // Even reduced-motion CSS finishes a transition on the next paint.
    await expect.poll(() => faintWhiteSvgLabels(page)).toContain("SVG color policy control (0.25 alpha)");
    await page.locator("#lesson-contrast-control").evaluate((label) => {
      label.style.removeProperty("color");
      label.classList.add("text-muted-foreground");
    });
    await page.locator("#lesson-svg-color-control").evaluate((svg) => {
      svg.querySelector("text")!.setAttribute("fill", "var(--muted-foreground)");
      svg.style.removeProperty("opacity");
    });
    await expect.poll(() => scanContrast(page)).toEqual([]);
    await expect.poll(() => faintWhiteSvgLabels(page)).toEqual([]);
  });

  test("graph controls wait for hydration", async ({ browser, baseURL }) => {
    const context = await browser.newContext({ javaScriptEnabled: false, baseURL });
    try {
      const page = await context.newPage();
      await page.goto("/learn/bv");
      await expect(page.getByRole("button", { name: "Run Triage", exact: true, includeHidden: true })).toBeDisabled();
      const database = page.getByRole("button", { name: /^DB:/, includeHidden: true });
      await expect(database).toHaveAttribute("aria-disabled", "true");
      await expect(database).toHaveAttribute("tabindex", "-1");
    } finally {
      await context.close();
    }
  });

  test("graph nodes support keyboard selection without lesson navigation", async ({ page }) => {
    await page.goto("/learn/bv");
    const region = page.getByRole("region", { name: "Beads dependency graph (scrolls sideways when needed)", exact: true });
    const database = region.getByRole("button", { name: /^DB:/ });
    await expect(database).toHaveAttribute("aria-disabled", "false");
    await region.focus();
    await page.keyboard.press("Tab");
    await expect(database).toBeFocused();
    const ring = database.locator('[data-node-focus-ring="DB"]');
    await expect.poll(() => ring.evaluate((element) => Number(getComputedStyle(element).opacity))).toBe(1);
    await expect(database).toHaveAttribute("aria-pressed", "false");
    await page.keyboard.press("Enter");
    await expect(database).toHaveAttribute("aria-pressed", "true");
    await page.keyboard.press("Space");
    await expect(database).toHaveAttribute("aria-pressed", "false");
    await expect(database).toBeFocused();
    expect(new URL(page.url()).pathname).toBe("/learn/bv");
    await page.keyboard.press("Tab");
    const auth = region.getByRole("button", { name: /^AUTH:/ });
    await expect(auth).toBeFocused();
    // SVG node focus must stay local for both native arrow panning and the
    // letter shortcut used by the surrounding lesson. Wait for asynchronous
    // navigation, so an immediate URL check cannot hide a leaked shortcut.
    const originalURL = page.url();
    for (const key of ["ArrowRight", "l"]) {
      await auth.press(key);
      await expect(page.waitForURL((url) => url.href !== originalURL, { timeout: 1000 }))
        .rejects.toBeInstanceOf(errors.TimeoutError);
      await expect(auth).toBeFocused();
    }
    const run = page.getByRole("button", { name: "Run Triage", exact: true });
    // Keep the control above the fixed phone lesson-navigation bar. A native
    // click still has to pass visibility, stability and pointer-hit checks.
    await run.evaluate((button) => button.scrollIntoView({ block: "center", behavior: "instant" }));
    await run.click();
    await expect(page.getByRole("button", { name: "Quick Wins", exact: true })).toBeVisible();
    await auth.focus();
    await page.keyboard.press("Enter");
    await expect(auth).toHaveAttribute("aria-pressed", "true");
    const details = page.getByRole("region", { name: "Details for AUTH", exact: true });
    await expect(details).toContainText("Auth refactor");
    await page.keyboard.press("Space");
    await expect(auth).toHaveAttribute("aria-pressed", "false");
    await expect(details).toHaveCount(0);
    expect(new URL(page.url()).pathname).toBe("/learn/bv");
  });

  test("graph analysis keeps dimmed node identifiers readable", async ({ page }) => {
    await page.goto("/learn/bv");
    await expect(page.locator("main article section").first()).toBeVisible();
    const run = page.getByRole("button", { name: "Run Triage", exact: true });
    await run.evaluate((button) => button.scrollIntoView({ block: "center", behavior: "instant" }));
    await run.click();
    await expect(page.getByRole("button", { name: "Quick Wins", exact: true })).toBeVisible();
    for (const mode of ["Quick Wins", "Critical Path", "Bottlenecks", "Cycles"]) {
      const control = page.getByRole("button", { name: mode, exact: true });
      await control.evaluate((button) => button.scrollIntoView({ block: "center", behavior: "instant" }));
      await control.click();
      await expect(control).toHaveAttribute("aria-pressed", "true");
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(
        await page.evaluate(() => document.documentElement.clientWidth),
      );
      const dimmedShapes = page.locator('main svg g[opacity="0.3"], main svg g[opacity="0.25"]');
      expect(await dimmedShapes.count()).toBeGreaterThan(0);
      // The analysis still dims non-matching shapes, but their identifiers
      // must not inherit that dimming or disappear from the graph.
      await expect(dimmedShapes.locator("text")).toHaveCount(0);
      const identifiers = page.locator('main svg text').filter({ hasText: /^(DB|AUTH|API)$/ });
      await expect(identifiers).toHaveCount(3);
      expect(await faintWhiteSvgLabels(page)).toEqual([]);
    }
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

test.describe("Complete guide crash recovery", () => {
  test.use({ contextOptions: { reducedMotion: "no-preference" } });

  async function readProgress(page: Page): Promise<number> {
    const value = await page.getByRole("progressbar", { name: "ScarletCave progress" }).getAttribute("aria-valuenow");
    if (value === null || !/^\d+$/.test(value)) throw new Error("Missing numeric simulation progress");
    return Number(value);
  }

  test("pause, manual advance and resume control real simulation progress", async ({ page }) => {
    await page.goto("/complete-guide");
    const simulation = page.getByRole("region", { name: "Fungible Agent Crash Recovery", exact: true });
    await simulation.scrollIntoViewIfNeeded();
    await expect.poll(() => readProgress(page)).toBeGreaterThan(10);
    await simulation.getByRole("button", { name: "Pause simulation", exact: true }).click();
    const paused = await readProgress(page);
    await page.waitForTimeout(600);
    expect(await readProgress(page)).toBe(paused);
    await simulation.getByRole("button", { name: "Advance simulation by one second" }).click();
    await expect.poll(() => readProgress(page)).toBeGreaterThan(paused);
    const advanced = await readProgress(page);
    await simulation.getByRole("button", { name: "Resume simulation", exact: true }).click();
    await expect.poll(() => readProgress(page)).toBeGreaterThan(advanced);
  });

  test("reduced motion allows manual recovery and completion without autoplay", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto("/complete-guide");
    const simulation = page.getByRole("region", { name: "Fungible Agent Crash Recovery", exact: true });
    await simulation.scrollIntoViewIfNeeded();
    const progress = simulation.getByRole("progressbar", { name: "ScarletCave progress" });
    await expect(progress).toHaveAttribute("aria-valuenow", "10");
    await page.waitForTimeout(600);
    await expect(progress).toHaveAttribute("aria-valuenow", "10");
    const agent = simulation.getByRole("button", { name: "Kill agent ScarletCave", exact: true });
    await agent.click();
    if (await agent.getByText("Tap Again to Kill", { exact: true }).isVisible()) await agent.click();
    await expect(simulation.getByRole("button", { name: "Agent ScarletCave is crashed" })).toBeDisabled();
    const advance = simulation.getByRole("button", { name: "Advance simulation by one second" });
    // The real simulation advances at least one percent per tick. Sixty
    // manual seconds cover all eight beads without mocking its randomness.
    for (let step = 0; step < 60 && await advance.isEnabled(); step++) await advance.click();
    await expect(simulation.getByText(/^Recovered:/)).toHaveText(/Recovered:\s*[1-9]/);
    await expect(simulation.getByText(/^Completed:/)).toHaveText("Completed: 8");
    await expect(advance).toBeDisabled();
    await page.emulateMedia({ reducedMotion: "no-preference" });
    await expect(simulation.getByRole("button", { name: "Pause simulation", exact: true })).toBeDisabled();
    await expect(simulation.locator(".animate-pulse")).toHaveCount(0);
    await page.emulateMedia({ reducedMotion: "reduce" });
    await simulation.getByRole("button", { name: "Reset Swarm" }).click();
    await expect(progress).toHaveAttribute("aria-valuenow", "10");
    await page.waitForTimeout(600);
    await expect(progress).toHaveAttribute("aria-valuenow", "10");
    await expect(advance).toBeEnabled();
    // With every worker crashed, preserve one bookkeeping step before idle.
    const workers = simulation.getByRole("button", { name: /^Kill agent / });
    while (await workers.count() > 0) {
      const worker = workers.first();
      await worker.click();
      if (await worker.getByText("Tap Again to Kill", { exact: true }).isVisible()) await worker.click();
    }
    await advance.click();
    await expect(simulation.getByText(/^Orphaned:/)).toHaveText("Orphaned: 6");
    await expect(advance).toBeDisabled();
  });

  test("scrolling away stops progress and returning resumes it", async ({ page }) => {
    await page.goto("/complete-guide");
    const simulation = page.getByRole("region", { name: "Fungible Agent Crash Recovery", exact: true });
    await simulation.scrollIntoViewIfNeeded();
    await expect.poll(() => readProgress(page)).toBeGreaterThan(10);
    await page.evaluate(() => window.scrollTo({ top: 0, behavior: "instant" }));
    await expect.poll(async () => {
      const bounds = await simulation.boundingBox();
      return bounds !== null && bounds.y > (page.viewportSize()?.height ?? 0);
    }).toBe(true);
    await page.waitForTimeout(300);
    const offscreen = await readProgress(page);
    await page.waitForTimeout(600);
    expect(await readProgress(page)).toBe(offscreen);
    await simulation.scrollIntoViewIfNeeded();
    await expect.poll(() => readProgress(page)).toBeGreaterThan(offscreen);
  });
});
