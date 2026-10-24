import { expect, type Page, test } from "@playwright/test";

/**
 * Production smoke tests, followed by cloud regressions that also run locally.
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
    // One provider picker drives the hand-off brief, the guide and the URL.
    const provider = (name: string) => page.getByRole("radio", { name, exact: true });
    const pick = (name: string) => page.locator("label").filter({ has: provider(name) }).click();
    await expect(provider("Claude Code Hosted test")).toBeChecked();
    const fullInstructions = page.getByRole("button", { name: "Copy full instructions for Claude Code", exact: true });
    await expect(fullInstructions).toBeVisible();
    await fullInstructions.click();
    await expect(fullInstructions).toHaveText("Full instructions copied");
    await pick("ChatGPT / Codex Hosted test");
    await expect(provider("ChatGPT / Codex Hosted test")).toBeChecked();
    await expect(page).toHaveURL(/\/cloud-agents#codex$/);
    await expect(page.getByRole("button", { name: "Copy full instructions for ChatGPT / Codex", exact: true })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Set up ChatGPT / Codex" })).toBeVisible();
    await pick("Claude Code Hosted test");
    const claudeSteps = page.getByRole("list", { name: "Claude Code setup walkthrough" });
    await expect(page.getByRole("link", { name: "Claude Code documentation", exact: true })).toHaveCount(0);
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
    await pick("ChatGPT / Codex Hosted test");
    await expect(provider("ChatGPT / Codex Hosted test")).toBeChecked();
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
    await pick("Amp Orbs Documented workflow");
    await expect(page.getByRole("region", { name: "Setup script for Amp Orbs" }))
      .toContainText("ACFS_CLOUD_AGENT=generic bash");
    await pick("Meta Muse Needs investigation");
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

  test("cloud agent guide annotates screenshots, tracks progress and keeps options agent-specific", async ({ page }) => {
    const { jsErrors, failedRequests } = setupErrorMonitoring(page);

    await page.goto("/cloud-agents");
    await waitForPageSettled(page);

    // The brief preview shows exactly what the copy button hands to a browser agent.
    const preview = page.getByRole("button", { name: "Preview brief" });
    const brief = page.getByRole("region", { name: "Full agent instructions for Claude Code" });
    // Under load a click can land before hydration; click only while the brief is absent.
    await expect(async () => {
      if (await brief.count() === 0) await preview.click();
      await expect(brief).toContainText("# Set up Agent Flywheel for Claude Code", { timeout: 1000 });
    }).toPass({ timeout: 20000 });
    await expect(brief).toContainText("Controls to use, in order: (1) Environment chip; (2) Cloud.");
    await page.getByRole("button", { name: "Hide brief" }).click();
    await expect(brief).toHaveCount(0);

    // Highlighted controls are listed in text and survive into the enlarged view.
    const firstStep = page.locator("#claude-step-cloud-menu");
    await expect(firstStep.getByRole("list", { name: "Highlighted controls" })).toContainText("Environment chip");
    const enlarge = firstStep.getByRole("button", { name: /^Enlarge screenshot: / });
    await enlarge.click();
    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole("list", { name: "Highlighted controls" })).toContainText("Cloud");
    await page.keyboard.press("Escape");
    await expect(dialog).toHaveCount(0);
    await expect(enlarge).toBeFocused();

    // Step progress is local, per provider, and survives a reload.
    const done = page.getByRole("button", { name: "Mark as done: Open the Cloud menu" });
    await done.click();
    await expect(done).toHaveAttribute("aria-pressed", "true");
    await page.reload();
    await waitForPageSettled(page);
    await expect(page.getByRole("button", { name: "Mark as done: Open the Cloud menu" })).toHaveAttribute("aria-pressed", "true");

    // The subset example keeps the selected agent's own mode.
    await page.getByText("Options and environment variables").click();
    const claudeSubset = page.getByRole("region", { name: "Subset install example for Claude Code" });
    await expect(claudeSubset).toContainText('| ACFS_CLOUD_TOOLS="br bv am ubs" bash');
    await expect(claudeSubset).not.toContainText("ACFS_CLOUD_AGENT");
    await page.locator("label").filter({ has: page.getByRole("radio", { name: "Devin Documented workflow", exact: true }) }).click();
    await expect(page.getByRole("region", { name: "Subset install example for Devin" })).toContainText("ACFS_CLOUD_AGENT=generic bash");

    expect(failedRequests).toEqual([]);
    expect(jsErrors).toEqual([]);
  });
});

// Keep the live-site guard above intact. These exercise the real cloud page on
// localhost too, with only browser storage refusal controlled by the tests.
test.describe("Cloud walkthrough progress", () => {
  const progressKey = "acfs-cloud-agents-progress-v1";
  const unsavedNotice = "Checklist changes are kept for this visit only. Browser storage could not save them; reloading may lose them.";
  type StorageProbe = Window & { cloudProgressWritesAllowed: boolean };

  async function seedReadOnlyProgress(page: Page) {
    await page.addInitScript(({ key }) => {
      if (localStorage.getItem(key) === null) {
        localStorage.setItem(key, JSON.stringify({ claude: ["cloud-menu"], codex: ["cloud"] }));
      }
      const probe = window as unknown as StorageProbe;
      probe.cloudProgressWritesAllowed = false;
      const write = Storage.prototype.setItem;
      Storage.prototype.setItem = function (name, value) {
        if (this === localStorage && name === key && !probe.cloudProgressWritesAllowed) {
          throw new DOMException("Storage quota exceeded", "QuotaExceededError");
        }
        return write.call(this, name, value);
      };
    }, { key: progressKey });
  }

  function doneButton(page: Page, anchor: string) {
    return page.locator(`#${anchor}`).getByRole("button", { name: /^Mark as done:/ });
  }

  async function chooseProvider(page: Page, name: string) {
    await page.locator("label").filter({
      has: page.getByRole("radio", { name, exact: true }),
    }).click();
  }

  test("a fresh visit still supports reversible steps when storage reads and writes are blocked", async ({ page }) => {
    const errors = setupErrorMonitoring(page);
    await page.addInitScript(({ key }) => {
      const read = Storage.prototype.getItem;
      const write = Storage.prototype.setItem;
      Storage.prototype.getItem = function (name) {
        if (this === localStorage && name === key) throw new DOMException("Storage access denied", "SecurityError");
        return read.call(this, name);
      };
      Storage.prototype.setItem = function (name, value) {
        if (this === localStorage && name === key) throw new DOMException("Storage access denied", "SecurityError");
        return write.call(this, name, value);
      };
    }, { key: progressKey });
    await page.goto("/cloud-agents");
    await waitForPageSettled(page);
    const first = doneButton(page, "claude-step-cloud-menu");
    await expect(first).toHaveAttribute("aria-pressed", "false");
    await first.click();
    await expect(first).toHaveAttribute("aria-pressed", "true");
    await first.click();
    await expect(first).toHaveAttribute("aria-pressed", "false");
    expect(errors.jsErrors).toEqual([]);
    expect(errors.failedRequests).toEqual([]);
  });

  test("existing readable progress does not discard toggles when writes fail", async ({ page }, testInfo) => {
    const errors = setupErrorMonitoring(page);
    await seedReadOnlyProgress(page);
    await page.goto("/cloud-agents");
    await waitForPageSettled(page);
    const first = doneButton(page, "claude-step-cloud-menu");
    const second = doneButton(page, "claude-step-add-environment");
    await expect(first).toHaveAttribute("aria-pressed", "true");
    await second.click();
    await expect(second).toHaveAttribute("aria-pressed", "true");
    await expect(page.getByRole("status").filter({ hasText: unsavedNotice })).toBeVisible();
    await expect(page.getByRole("status").filter({ hasText: unsavedNotice })).toBeInViewport();
    const widths = await page.evaluate(() => ({ content: document.documentElement.scrollWidth, viewport: document.documentElement.clientWidth }));
    expect(widths.content).toBe(widths.viewport);
    await page.screenshot({ path: testInfo.outputPath("cloud-progress-storage-failed.png") });
    // Failed writes preserve the previous durable record, while clicks remain
    // reversible within this visit rather than claiming persistence.
    expect(await page.evaluate((key) => JSON.parse(localStorage.getItem(key)!), progressKey)).toEqual({ claude: ["cloud-menu"], codex: ["cloud"] });
    await second.click();
    await expect(second).toHaveAttribute("aria-pressed", "false");
    await first.click();
    await expect(first).toHaveAttribute("aria-pressed", "false");
    expect(errors.jsErrors).toEqual([]);
    expect(errors.failedRequests).toEqual([]);
  });

  test("visit-only provider changes persist together once storage accepts writes again", async ({ page }) => {
    const errors = setupErrorMonitoring(page);
    await seedReadOnlyProgress(page);
    await page.goto("/cloud-agents");
    await waitForPageSettled(page);
    await doneButton(page, "claude-step-add-environment").click();
    await expect(doneButton(page, "claude-step-add-environment")).toHaveAttribute("aria-pressed", "true");
    await chooseProvider(page, "ChatGPT / Codex Hosted test");
    await expect(doneButton(page, "codex-step-cloud")).toHaveAttribute("aria-pressed", "true");
    await doneButton(page, "codex-step-create-environment").click();
    await expect(doneButton(page, "codex-step-create-environment")).toHaveAttribute("aria-pressed", "true");
    await chooseProvider(page, "Claude Code Hosted test");
    await expect(doneButton(page, "claude-step-add-environment")).toHaveAttribute("aria-pressed", "true");
    await page.evaluate(() => { (window as unknown as StorageProbe).cloudProgressWritesAllowed = true; });
    await doneButton(page, "claude-step-network").click();
    await expect(doneButton(page, "claude-step-network")).toHaveAttribute("aria-pressed", "true");
    await expect(page.getByRole("status").filter({ hasText: unsavedNotice })).toHaveCount(0);
    expect(await page.evaluate((key) => JSON.parse(localStorage.getItem(key)!), progressKey)).toEqual({
      claude: ["cloud-menu", "add-environment", "network"], codex: ["cloud", "create-environment"],
    });
    await page.reload();
    await waitForPageSettled(page);
    await expect(doneButton(page, "claude-step-cloud-menu")).toHaveAttribute("aria-pressed", "true");
    await expect(doneButton(page, "claude-step-add-environment")).toHaveAttribute("aria-pressed", "true");
    await expect(doneButton(page, "claude-step-network")).toHaveAttribute("aria-pressed", "true");
    expect(errors.jsErrors).toEqual([]);
    expect(errors.failedRequests).toEqual([]);
  });

  test("cross-tab changes and removal clear cached progress without reviving old steps", async ({ page, context }) => {
    const errors = setupErrorMonitoring(page);
    await page.goto("/cloud-agents");
    await waitForPageSettled(page);
    const other = await context.newPage();
    await other.goto("/cloud-agents");
    await waitForPageSettled(other);
    await doneButton(page, "claude-step-cloud-menu").click();
    await expect(doneButton(other, "claude-step-cloud-menu")).toHaveAttribute("aria-pressed", "true");
    await doneButton(other, "claude-step-add-environment").click();
    await expect(doneButton(page, "claude-step-add-environment")).toHaveAttribute("aria-pressed", "true");
    // These dispatch genuine storage events to the other browsing context.
    await other.evaluate((key) => localStorage.removeItem(key), progressKey);
    await expect(doneButton(page, "claude-step-cloud-menu")).toHaveAttribute("aria-pressed", "false");
    await expect(doneButton(page, "claude-step-add-environment")).toHaveAttribute("aria-pressed", "false");
    await other.evaluate((key) => localStorage.setItem(key, JSON.stringify({ claude: ["network"] })), progressKey);
    await expect(doneButton(page, "claude-step-network")).toHaveAttribute("aria-pressed", "true");
    await other.evaluate(() => localStorage.clear());
    await expect(doneButton(page, "claude-step-network")).toHaveAttribute("aria-pressed", "false");
    expect(errors.jsErrors).toEqual([]);
    expect(errors.failedRequests).toEqual([]);
  });

  test("returning to the guide observes storage changes made while its subscriptions were unmounted", async ({ page, context }) => {
    const errors = setupErrorMonitoring(page);
    await page.goto("/cloud-agents");
    await waitForPageSettled(page);
    await doneButton(page, "claude-step-cloud-menu").click();
    await expect(doneButton(page, "claude-step-cloud-menu")).toHaveAttribute("aria-pressed", "true");
    await page.getByRole("navigation", { name: "Site", exact: true }).getByRole("link", { name: "Agent Flywheel", exact: true }).click();
    await expect(page).toHaveURL(/\/$/);
    const other = await context.newPage();
    await other.goto("/cloud-agents");
    await waitForPageSettled(other);
    await other.evaluate((key) => localStorage.setItem(key, JSON.stringify({ claude: ["network"] })), progressKey);
    await page.goBack();
    await expect(doneButton(page, "claude-step-cloud-menu")).toHaveAttribute("aria-pressed", "false");
    await expect(doneButton(page, "claude-step-network")).toHaveAttribute("aria-pressed", "true");
    expect(errors.jsErrors).toEqual([]);
    expect(errors.failedRequests).toEqual([]);
  });

  test("unrelated cross-tab storage writes retain this visit's unsaved progress", async ({ page, context }) => {
    const errors = setupErrorMonitoring(page);
    await seedReadOnlyProgress(page);
    await page.goto("/cloud-agents");
    await waitForPageSettled(page);
    await doneButton(page, "claude-step-add-environment").click();
    await expect(doneButton(page, "claude-step-add-environment")).toHaveAttribute("aria-pressed", "true");
    const other = await context.newPage();
    await other.goto("/cloud-agents");
    await waitForPageSettled(other);
    await other.evaluate(() => localStorage.setItem("unrelated-cloud-regression", "updated"));
    await expect(doneButton(page, "claude-step-add-environment")).toHaveAttribute("aria-pressed", "true");
    await expect(page.getByRole("status").filter({ hasText: unsavedNotice })).toBeVisible();
    expect(errors.jsErrors).toEqual([]);
    expect(errors.failedRequests).toEqual([]);
  });
});

test.describe("Cloud walkthrough provider navigation", () => {
  test("switching from a later guide step brings the new instructions into view and transfers focus", async ({ page }, testInfo) => {
    const errors = setupErrorMonitoring(page);
    await page.goto("/cloud-agents#claude");
    await waitForPageSettled(page);
    await page.locator("#guide li[id]").last().scrollIntoViewIfNeeded();
    await expect(page.locator("#guide-heading")).not.toBeInViewport();
    const viewport = page.viewportSize();
    if (!viewport) throw new Error("The provider-navigation test requires an emulated viewport");
    const mobile = viewport.width < 1024;
    if (mobile) await page.getByRole("button", { name: "Steps", exact: true }).click();
    const switcher = page.locator(mobile ? "#guide-agent-mobile" : "#guide-agent-desktop");
    await switcher.focus();
    await switcher.selectOption("generic");
    const heading = page.getByRole("heading", { name: "Set up Other Linux agent", exact: true });
    await expect(heading).toBeVisible();
    await expect.poll(() => heading.evaluate((node) => {
      const rect = node.getBoundingClientRect();
      return { focused: document.activeElement === node, inViewport: rect.top >= 0 && rect.bottom <= window.innerHeight };
    })).toEqual({ focused: true, inViewport: true });
    await expect(page).toHaveURL(/#generic$/);
    await expect(page.locator("#guide-step-menu")).toHaveCount(0);
    await page.screenshot({ path: testInfo.outputPath("cloud-provider-switch.png") });
    expect(errors.jsErrors).toEqual([]);
    expect(errors.failedRequests).toEqual([]);
  });

  test("top provider choices retain keyboard focus and leave the picker in view", async ({ page }) => {
    const errors = setupErrorMonitoring(page);
    await page.goto("/cloud-agents");
    await waitForPageSettled(page);
    const codex = page.getByRole("radio", { name: "ChatGPT / Codex Hosted test", exact: true });
    await codex.focus();
    await codex.press("Space");
    await expect(codex).toBeChecked();
    await expect(codex).toBeFocused();
    await expect(page.locator("#choose-agent")).toBeInViewport();
    await expect(page).toHaveURL(/#codex$/);
    expect(errors.jsErrors).toEqual([]);
    expect(errors.failedRequests).toEqual([]);
  });

  test("a direct provider step link still opens the requested instructions without stealing focus", async ({ page }) => {
    const errors = setupErrorMonitoring(page);
    await page.goto("/cloud-agents#codex-step-create-environment");
    await waitForPageSettled(page);
    await expect(page.getByRole("heading", { name: "Set up ChatGPT / Codex", exact: true })).toBeVisible();
    await expect(page.locator("#codex-step-create-environment")).toBeInViewport();
    await expect(page.locator("#guide-heading")).not.toBeFocused();
    await expect(page).toHaveURL(/#codex-step-create-environment$/);
    expect(errors.jsErrors).toEqual([]);
    expect(errors.failedRequests).toEqual([]);
  });
});
