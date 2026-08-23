import { test, expect, type Page } from "@playwright/test";

/**
 * Production smoke tests that run against the live site.
 * These are critical for catching deployment issues.
 *
 * Run with: cd apps/web && PLAYWRIGHT_BASE_URL=https://agent-flywheel.com bun run test production
 */

type ErrorCollector = {
  jsErrors: string[];
  failedRequests: Array<{ url: string; status: number }>;
};

/** Helper to set up error/request monitoring on a page */
function setupErrorMonitoring(page: Page): ErrorCollector {
  const collector: ErrorCollector = { jsErrors: [], failedRequests: [] };

  page.on("console", (msg) => {
    if (msg.type() === "error") {
      // Ignore some expected console errors
      const text = msg.text();
      if (!text.includes("favicon")) {
        collector.jsErrors.push(`Console: ${text}`);
      }
    }
  });

  page.on("pageerror", (error) => {
    collector.jsErrors.push(`Page Error: ${error.message}`);
  });

  page.on("response", (response) => {
    // Track 4xx/5xx responses for scripts (indicates broken assets)
    if (response.status() >= 400) {
      const url = response.url();
      // Focus on JS/critical resources
      if (url.includes(".js") || url.includes("/_next/") || url.includes("/_vercel/")) {
        collector.failedRequests.push({ url, status: response.status() });
      }
    }
  });

  return collector;
}

async function waitForPageSettled(page: Page): Promise<void> {
  await page.waitForLoadState("domcontentloaded");
  // Some pages may keep background requests open (analytics, etc). Avoid flakiness by
  // attempting networkidle but not failing the test if it never becomes fully idle.
  await page.waitForLoadState("networkidle", { timeout: 5000 }).catch(() => {});
}

test.describe("Production Smoke Tests", () => {
  test.skip(
    !process.env.PLAYWRIGHT_BASE_URL?.includes("agent-flywheel.com"),
    "Only runs against production"
  );

  test("homepage loads without JS errors or failed requests", async ({ page }) => {
    const { jsErrors, failedRequests } = setupErrorMonitoring(page);

    await page.goto("/");
    await waitForPageSettled(page);

    await expect(page.locator("h1").first()).toBeVisible();
    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });

  test("learn dashboard loads without JS errors or failed requests", async ({ page }) => {
    const { jsErrors, failedRequests } = setupErrorMonitoring(page);

    await page.goto("/learn");
    await waitForPageSettled(page);

    await expect(page.locator("h1").first()).toBeVisible();
    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });

  test("lesson page loads without JS errors or failed requests", async ({ page }) => {
    const { jsErrors, failedRequests } = setupErrorMonitoring(page);

    await page.goto("/learn/welcome");
    await waitForPageSettled(page);

    await expect(page.locator("h1").first()).toBeVisible();
    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });

  test("commands page loads without JS errors or failed requests", async ({ page }) => {
    const { jsErrors, failedRequests } = setupErrorMonitoring(page);

    await page.goto("/learn/commands");
    await waitForPageSettled(page);

    await expect(page.locator("h1").first()).toBeVisible();
    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });

  test("wizard flow is accessible", async ({ page }) => {
    const { jsErrors, failedRequests } = setupErrorMonitoring(page);

    await page.goto("/wizard/os-selection");
    await waitForPageSettled(page);

    await expect(page.locator("h1").first()).toBeVisible();
    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });

  test("omarchy page loads without errors (WebGL hero is optional)", async ({ page }) => {
    const { jsErrors, failedRequests } = setupErrorMonitoring(page);

    await page.goto("/omarchy");
    await waitForPageSettled(page);

    // Hero + install command render regardless of WebGL availability.
    await expect(page.locator("h1").first()).toBeVisible();
    await expect(
      page.getByText("curl -fsSL https://agent-flywheel.com/install | bash").first()
    ).toBeVisible();

    // Copy button gives visible feedback.
    await page.getByRole("button", { name: "Copy install command" }).first().click();
    await expect(page.getByText("Copied").first()).toBeVisible();

    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });
});
