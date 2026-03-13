import { test, expect, type Page } from "@playwright/test";

/**
 * E2E tests for pages that depend on manifest-generated data.
 *
 * These pages consume data from apps/web/lib/generated/* which is
 * derived from acfs.manifest.yaml via the manifest generator.
 *
 * Related bead: bd-31ps.1.4
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
      // Ignore expected console errors (favicon, analytics, etc.)
      const text = msg.text();
      const ignoredPatterns = [
        "favicon",
        "404",
        "Failed to load resource",
        "net::ERR_",
        "analytics",
        "gtag",
      ];
      const shouldIgnore = ignoredPatterns.some((pattern) =>
        text.toLowerCase().includes(pattern.toLowerCase())
      );
      if (!shouldIgnore) {
        collector.jsErrors.push(`Console: ${text}`);
      }
    }
  });

  page.on("pageerror", (error) => {
    collector.jsErrors.push(`Page Error: ${error.message}`);
  });

  page.on("response", (response) => {
    // Track 4xx/5xx responses for critical JS/CSS assets only
    if (response.status() >= 400) {
      const url = response.url();
      // Only flag critical JS failures (not chunks that may be lazy-loaded)
      if (
        (url.includes(".js") && url.includes("/_next/static/chunks/pages/")) ||
        (url.includes(".js") && url.includes("/_next/static/chunks/app/"))
      ) {
        collector.failedRequests.push({ url, status: response.status() });
      }
    }
  });

  return collector;
}

async function waitForPageSettled(page: Page): Promise<void> {
  await page.waitForLoadState("domcontentloaded");
  // Allow some slack for pages with background requests
  await page.waitForLoadState("networkidle", { timeout: 5000 }).catch(() => {});
}

/** Wait for tools page hydration - stats text indicates client component has mounted */
async function waitForToolsPageHydrated(page: Page): Promise<void> {
  await waitForPageSettled(page);
  // Wait for client component hydration by checking for dynamic content
  // Use expect with auto-retry for more robustness
  await expect(page.getByText(/Showing \d+ of \d+ tools/)).toBeVisible({ timeout: 15000 });
}

test.describe("Flywheel Page (generated data)", () => {
  test("loads without JS errors or failed requests", async ({ page }) => {
    const { jsErrors, failedRequests } = setupErrorMonitoring(page);

    await page.goto("/flywheel");
    await waitForPageSettled(page);

    // Page has main heading
    await expect(page.locator("h1").first()).toBeVisible();

    // No errors
    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });

  test("renders tool cards from generated data", async ({ page }) => {
    await page.goto("/flywheel");
    await waitForPageSettled(page);

    // Flywheel page should have substantial content
    const textContent = await page.textContent("body");
    expect(textContent?.length).toBeGreaterThan(1000);

    // Page should have multiple elements (indicating tools are rendered)
    const elements = page.locator("div, section, article");
    const count = await elements.count();
    expect(count).toBeGreaterThan(10);
  });

  test("has functional navigation links", async ({ page }) => {
    await page.goto("/flywheel");
    await waitForPageSettled(page);

    // Check for link elements on the page
    const links = page.locator("a[href]");
    const count = await links.count();
    expect(count).toBeGreaterThan(0);
  });
});

test.describe("TL;DR Page (generated data)", () => {
  test("loads without JS errors or failed requests", async ({ page }) => {
    const { jsErrors, failedRequests } = setupErrorMonitoring(page);

    await page.goto("/tldr");
    await waitForPageSettled(page);

    // Page has main heading
    await expect(page.locator("h1").first()).toBeVisible();

    // No errors
    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });

  test("renders tool summaries from generated data", async ({ page }) => {
    await page.goto("/tldr");
    await waitForPageSettled(page);

    // TL;DR page should have tool summaries displayed
    // Check for presence of content sections
    const contentSections = page.locator("section, article, [class*='tool'], [class*='card']");
    const count = await contentSections.count();
    expect(count).toBeGreaterThan(0);

    // Page should have substantial content (not empty)
    const textContent = await page.textContent("body");
    expect(textContent?.length).toBeGreaterThan(500);
  });

  test("shows tech stack or feature information", async ({ page }) => {
    await page.goto("/tldr");
    await waitForPageSettled(page);

    // TL;DR page should have substantial content from generated data
    const textContent = await page.textContent("body");
    expect(textContent?.length).toBeGreaterThan(1000);

    // Page should have multiple elements
    const elements = page.locator("div, section, article");
    const count = await elements.count();
    expect(count).toBeGreaterThan(10);
  });
});

test.describe("Learn Commands Page (generated data)", () => {
  test("loads without JS errors or failed requests", async ({ page }) => {
    const { jsErrors, failedRequests } = setupErrorMonitoring(page);

    await page.goto("/learn/commands");
    await waitForPageSettled(page);

    await expect(page.locator("h1").first()).toBeVisible();

    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });

  test("renders command entries from generated data", async ({ page }) => {
    await page.goto("/learn/commands");
    await waitForPageSettled(page);

    // Commands page should have substantial content
    const textContent = await page.textContent("body");
    expect(textContent?.length).toBeGreaterThan(500);

    // Page should have multiple elements
    const elements = page.locator("div, section, article, table, tr");
    const count = await elements.count();
    expect(count).toBeGreaterThan(5);
  });

  test("includes manifest-generated utility commands", async ({ page }) => {
    await page.goto("/learn/commands");
    await waitForPageSettled(page);

    await expect(page.getByText("giil", { exact: true })).toBeVisible();
    await expect(
      page.getByText("Get Image from Internet Link", { exact: true })
    ).toBeVisible();
  });

  test("finds PCR by acronym after generated command-name changes", async ({ page }) => {
    await page.goto("/learn/commands");
    await waitForPageSettled(page);

    await page.getByLabel("Search commands").fill("pcr");

    await expect(
      page.getByText("claude-post-compact-reminder", { exact: true })
    ).toBeVisible();
    await expect(
      page.getByText("Post-Compact Reminder", { exact: true })
    ).toBeVisible();
  });

  test("prefers canonical generated examples for matching manual commands", async ({ page }) => {
    await page.goto("/learn/commands");
    await waitForPageSettled(page);

    const search = page.getByLabel("Search commands");

    await search.fill("cass");
    await expect(page.getByText('cass search "auth error" --robot')).toBeVisible();
    await expect(page.getByText("cass --help")).toHaveCount(0);

    await search.fill("cm");
    await expect(page.getByText('cm context "task" --json')).toBeVisible();
    await expect(page.getByText("cm --help")).toHaveCount(0);

    await search.fill("ru");
    await expect(page.getByText("ru sync --parallel 4")).toBeVisible();
    await expect(page.getByText("ru sync -j4")).toHaveCount(0);
  });
});

test.describe("Learn Dashboard (generated data)", () => {
  test("loads without JS errors or failed requests", async ({ page }) => {
    const { jsErrors, failedRequests } = setupErrorMonitoring(page);

    await page.goto("/learn");
    await waitForPageSettled(page);

    await expect(page.locator("h1").first()).toBeVisible();

    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });

  test("shows lesson navigation from generated index", async ({ page }) => {
    await page.goto("/learn");
    await waitForPageSettled(page);

    // Learn dashboard should show navigation links
    const links = page.locator("a[href]");
    const count = await links.count();
    expect(count).toBeGreaterThan(0);

    // Page should have substantial navigation content
    const navElements = page.locator("nav, [role='navigation'], [class*='nav'], ul li a");
    const navCount = await navElements.count();
    expect(navCount + count).toBeGreaterThan(3);
  });
});

test.describe("Tools Status Page (generated data)", () => {
  test("loads without JS errors or failed requests", async ({ page }) => {
    const { jsErrors, failedRequests } = setupErrorMonitoring(page);

    await page.goto("/tools");
    await waitForPageSettled(page);

    // Page has main heading
    await expect(page.locator("h1").first()).toBeVisible();

    // No errors
    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });

  test("renders tool cards from generated manifest data", async ({ page }) => {
    await page.goto("/tools");
    await waitForPageSettled(page);

    // Page should have substantial content from manifest tools
    const textContent = await page.textContent("body");
    expect(textContent?.length).toBeGreaterThan(1000);

    // Should have multiple tool card elements
    const elements = page.locator("div, section, article");
    const count = await elements.count();
    expect(count).toBeGreaterThan(10);
  });

  test("displays category filters", async ({ page }) => {
    await page.goto("/tools");
    await waitForToolsPageHydrated(page);

    // Check for category filter buttons
    const allButton = page.getByRole("button", { name: "All" });
    await expect(allButton).toBeVisible();

    // Page should have filter buttons for categories
    const buttons = page.locator("button");
    const buttonCount = await buttons.count();
    expect(buttonCount).toBeGreaterThan(1);
  });

  test("has search input element", async ({ page }) => {
    await page.goto("/tools");
    await waitForToolsPageHydrated(page);

    // Find search input
    const searchInput = page.locator("input[type='text'], input[placeholder*='earch']");
    await expect(searchInput.first()).toBeVisible();
  });

  test("stats bar shows tool counts", async ({ page }) => {
    await page.goto("/tools");
    await waitForToolsPageHydrated(page);

    // Stats bar should show "Showing X of Y tools"
    const statsText = page.getByText(/Showing \d+ of \d+ tools/);
    await expect(statsText).toBeVisible();
  });
});

test.describe("Tool Detail Pages (generated data)", () => {
  // Sample tool pages - these use hand-maintained tool-data.tsx
  // which is merged with manifest data via manifest-adapter
  const toolSlugs = ["agent-mail", "beads", "cass", "dcg", "ru", "srps"];

  for (const slug of toolSlugs) {
    test(`/learn/tools/${slug} loads without JS errors`, async ({ page }) => {
      const { jsErrors, failedRequests } = setupErrorMonitoring(page);

      await page.goto(`/learn/tools/${slug}`);
      await waitForPageSettled(page);

      // Page should have content
      const heading = page.locator("h1").first();
      await expect(heading).toBeVisible();

      // Filter out non-critical console errors (404 for missing optional resources)
      const criticalErrors = jsErrors.filter(
        (err) =>
          !err.includes("favicon") &&
          !err.includes("404") &&
          !err.includes("Failed to load resource")
      );
      expect(failedRequests).toEqual([]);
      expect(criticalErrors).toEqual([]);
    });
  }

  test("/learn/tools/ntm uses the canonical repository link", async ({ page }) => {
    await page.goto("/learn/tools/ntm");
    await waitForPageSettled(page);

    const html = await page.content();
    expect(html).toContain("https://github.com/Dicklesworthstone/ntm");
  });

  test("/learn/tools/pcr shows a hook usage example, not a raw installer pipe", async ({
    page,
  }) => {
    await page.goto("/learn/tools/pcr");
    await waitForPageSettled(page);

    const bodyText = await page.textContent("body");
    expect(bodyText).toContain("claude-post-compact-reminder");
    expect(bodyText).not.toContain("install-post-compact-reminder.sh");
    expect(bodyText).not.toContain("curl -fsSL");
  });

  test("/learn/tools/pt prefers the canonical robot-mode example", async ({ page }) => {
    await page.goto("/learn/tools/pt");
    await waitForPageSettled(page);

    const bodyText = await page.textContent("body");
    expect(bodyText).toContain("pt --robot --top 10");
    expect(bodyText).not.toContain("pt --help");
  });

  test("/learn/tools/rch and /learn/tools/casr prefer canonical manifest examples", async ({
    page,
  }) => {
    await page.goto("/learn/tools/rch");
    await waitForPageSettled(page);

    let bodyText = await page.textContent("body");
    expect(bodyText).toContain("rch status");
    expect(bodyText).not.toContain("rch exec -- cargo build --release");

    await page.goto("/learn/tools/casr");
    await waitForPageSettled(page);

    bodyText = await page.textContent("body");
    expect(bodyText).toContain("casr export --from claude");
    expect(bodyText).not.toContain("casr providers");
  });
});
