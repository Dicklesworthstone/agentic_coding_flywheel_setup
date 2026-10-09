import { expect, type Page, test } from "@playwright/test";

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
    "Only runs against production",
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
      page.getByText("curl -fsSL https://agent-flywheel.com/install | bash").first(),
    ).toBeVisible();

    // Copy button gives visible feedback.
    await page.getByRole("button", { name: "Copy install command" }).first().click();
    await expect(page.getByText("Copied").first()).toBeVisible();

    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });

  test("cloud agent page selects and copies provider-specific setup instructions", async ({ page }) => {
    const { jsErrors, failedRequests } = setupErrorMonitoring(page);

    await page.goto("/cloud-agents");
    await waitForPageSettled(page);

    await expect(page.locator("h1").first()).toBeVisible();
    const claudeSteps = page.getByRole("list", { name: "Claude Code setup walkthrough" });
    await expect(claudeSteps.getByRole("img")).toHaveCount(4);
    for (const image of await claudeSteps.getByRole("img").all()) {
      await image.scrollIntoViewIfNeeded();
      await expect.poll(() => image.evaluate((node) => {
        const element = node as HTMLImageElement;
        return element.complete && element.naturalWidth > 0;
      })).toBe(true);
    }
    await expect(
      page.getByRole("region", { name: "Setup script for a Claude Code cloud environment" }),
    ).toContainText("scripts/claude-code-web-setup.sh | bash");

    await page.getByRole("button", { name: "Copy setup script" }).click();
    await expect(page.getByText("Copied").first()).toBeVisible();
    await page.getByRole("button", { name: "ChatGPT / Codex Hosted test" }).click();
    await expect(page.getByRole("list", { name: "ChatGPT / Codex setup walkthrough" }).getByRole("img")).toHaveCount(4);
    await expect(page.getByRole("region", { name: "Install script for a Codex cloud environment" }))
      .toContainText('ACFS_CLOUD_AGENT=codex ACFS_CLOUD_ROOT="$acfs_cloud_root/.acfs-cloud" bash');
    await expect(page.getByRole("region", { name: "Install script for a Codex cloud environment" }))
      .toContainText('ACFS_CLOUD_SKILL_DIR="$acfs_cloud_root/.agents/skills/acfs-cloud-tools"');
    const codexCopy = page.getByRole("button", { name: "Copy Codex install script" });
    await codexCopy.click();
    await expect(codexCopy).toHaveText("Copied");
    await expect(page.getByRole("region", { name: "Codex Start skill instructions" }))
      .toContainText('export PATH="$acfs_cloud_root/.local/bin:$PATH"');
    const taskCopy = page.getByRole("button", { name: "Copy Codex task instructions" });
    await taskCopy.click();
    await expect(taskCopy).toHaveText("Copied");
    await expect(page.getByText(/Automatic Start\/repository-skill discovery did not work/)).toBeVisible();
    await page.getByRole("button", { name: "Amp Orbs Documented workflow" }).click();
    await expect(page.getByRole("region", { name: "Setup script for Amp Orbs" }))
      .toContainText("ACFS_CLOUD_AGENT=generic bash");
    await page.getByRole("button", { name: "Meta Muse Needs investigation" }).click();
    await expect(page.getByRole("heading", { name: "Check the VM before installing" })).toBeVisible();
    await page.getByRole("button", { name: "Open Linux template" }).click();
    await expect(page.getByRole("region", { name: "Other Linux agent task instructions" }))
      .toContainText("$HOME/.acfs/cloud/AGENTS.md");

    await page.goto("/claude-code-web#codex-cloud");
    await expect(page).toHaveURL(/\/cloud-agents#codex-cloud$/);
    await expect(page.getByRole("region", { name: "Install script for a Codex cloud environment" })).toBeVisible();

    await page.goto("/cloud-agents#codex-step-install-script");
    await expect(page.getByRole("heading", { name: "Paste into the Install script editor" })).toBeInViewport();
    await expect(page.getByRole("region", { name: "Install script for a Codex cloud environment" }))
      .toContainText("bash || exit 1");

    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });
});
