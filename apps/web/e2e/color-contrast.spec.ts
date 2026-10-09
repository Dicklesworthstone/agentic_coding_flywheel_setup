import { expect, test, type Page } from "@playwright/test";

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
