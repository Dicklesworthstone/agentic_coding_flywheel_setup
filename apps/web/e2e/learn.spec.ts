import { test, expect } from "@playwright/test";

test.describe.serial("Learning Hub", () => {
  test("learn dashboard loads without JS errors", async ({ page }) => {
    const errors: string[] = [];

    // Capture console errors
    page.on("console", (msg) => {
      if (msg.type() === "error") {
        errors.push(`Console: ${msg.text()}`);
      }
    });

    // Capture page errors (uncaught exceptions)
    page.on("pageerror", (error) => {
      errors.push(`Page Error: ${error.message}`);
    });

    await page.goto("/learn");
    await page.waitForLoadState("networkidle");

    // Basic content check - use first() for strict mode compatibility
    await expect(page.locator("h1").first()).toBeVisible();

    // No JS errors should have occurred
    expect(errors).toEqual([]);
  });

  test("lesson page loads without JS errors", async ({ page }) => {
    const errors: string[] = [];

    page.on("console", (msg) => {
      if (msg.type() === "error") {
        errors.push(`Console: ${msg.text()}`);
      }
    });

    page.on("pageerror", (error) => {
      errors.push(`Page Error: ${error.message}`);
    });

    await page.goto("/learn/welcome");
    await page.waitForLoadState("networkidle");

    // Check content loaded - use first() as markdown content may have additional h1 elements
    await expect(page.locator("h1").first()).toBeVisible();

    // No JS errors
    expect(errors).toEqual([]);
  });

  test("current lesson does not expose locked next-lesson links before completion", async ({ page }) => {
    await page.goto("/learn/welcome");
    await page.waitForLoadState("networkidle");

    await expect(page.locator('main a[href="/learn/linux-basics"]')).toHaveCount(0);
    await expect(page.locator('div.fixed a[href="/learn/linux-basics"]')).toHaveCount(0);
  });

  test("locked quick-reference lesson cards are not clickable before they unlock", async ({ page }) => {
    await page.goto("/learn");
    await page.waitForLoadState("networkidle");

    await expect(page.locator('a[href="/learn/agent-commands"]')).toHaveCount(0);
    await expect(page.locator('a[href="/learn/ntm-palette"]')).toHaveCount(0);
    await expect(page.locator('a[href="/learn/commands"]')).toHaveCount(1);
    await expect(page.locator('a[href="/learn/glossary"]')).toHaveCount(1);
  });

  test("locked lessons ignore the complete shortcut", async ({ page }) => {
    await page.goto("/learn/agent-commands");
    await page.waitForLoadState("networkidle");

    await expect(page.getByText("Lesson Locked")).toBeVisible();
    await page.keyboard.press("c");

    const storedLessons = await page.evaluate(() =>
      localStorage.getItem("acfs-learning-hub-completed-lessons")
    );
    expect(storedLessons).toBeNull();
  });

  test("lesson completion fails cleanly when browser storage rejects writes", async ({ page }) => {
    await page.addInitScript(() => {
      const originalSetItem = Storage.prototype.setItem;
      Object.defineProperty(Storage.prototype, "setItem", {
        configurable: true,
        writable: true,
        value(key: string, value: string) {
          if (key === "acfs-learning-hub-completed-lessons") {
            throw new Error("storage blocked");
          }
          return originalSetItem.call(this, key, value);
        },
      });
    });

    await page.goto("/learn/welcome");
    await page.waitForLoadState("networkidle");

    await page.getByRole("button", { name: "Mark Complete" }).first().click();

    await expect(
      page.getByText(
        "Unable to save lesson progress. Check your browser storage settings and try again."
      )
    ).toBeVisible();
    await expect(page).toHaveURL(/\/learn\/welcome$/);

    const storedLessons = await page.evaluate(() =>
      localStorage.getItem("acfs-learning-hub-completed-lessons")
    );
    expect(storedLessons).toBeNull();
  });

  test("glossary page loads without JS errors", async ({ page }) => {
    const errors: string[] = [];

    page.on("console", (msg) => {
      if (msg.type() === "error") {
        errors.push(`Console: ${msg.text()}`);
      }
    });

    page.on("pageerror", (error) => {
      errors.push(`Page Error: ${error.message}`);
    });

    await page.goto("/learn/glossary");
    await page.waitForLoadState("networkidle");

    await expect(page.locator("h1").first()).toBeVisible();
    expect(errors).toEqual([]);
  });

  test("commands page loads without JS errors", async ({ page }) => {
    const errors: string[] = [];

    page.on("console", (msg) => {
      if (msg.type() === "error") {
        errors.push(`Console: ${msg.text()}`);
      }
    });

    page.on("pageerror", (error) => {
      errors.push(`Page Error: ${error.message}`);
    });

    await page.goto("/learn/commands");
    await page.waitForLoadState("networkidle");

    await expect(page.locator("h1").first()).toBeVisible();
    expect(errors).toEqual([]);
  });

  test("generated command docs prefer internal ACFS tool lessons when available", async ({ page }) => {
    await page.goto("/learn/commands");
    await page.waitForLoadState("networkidle");

    const rchDocsLink = page.locator('a[href="/learn/tools/rch"]').first();
    const agentMailDocsLink = page.locator('a[href="/learn/tools/agent-mail"]').first();
    const ruDocsLink = page.locator('a[href="/learn/tools/ru"]').first();
    await expect(rchDocsLink).toBeVisible();
    await expect(agentMailDocsLink).toBeVisible();
    await expect(ruDocsLink).toBeVisible();
    await expect(
      page.locator('a[href="https://github.com/Dicklesworthstone/remote_compilation_helper"]')
    ).toHaveCount(0);
    await expect(
      page.locator('a[href="https://github.com/Dicklesworthstone/mcp_agent_mail"]')
    ).toHaveCount(0);
    await expect(
      page.locator('a[href="https://github.com/Dicklesworthstone/repo_updater"]')
    ).toHaveCount(0);
  });

  test("dashboard shortcuts do not override focused interactive controls", async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem(
        "acfs-learning-hub-completed-lessons",
        JSON.stringify([0, 1])
      );
    });

    await page.goto("/learn");
    await page.waitForLoadState("networkidle");

    await page.keyboard.press("j");
    await page.keyboard.press("j");

    const continueLink = page.locator('a[href="/learn/ssh-basics"]').first();
    await continueLink.focus();
    await page.keyboard.press("Enter");

    await expect(page).toHaveURL(/\/learn\/ssh-basics$/);
  });

  test("lesson shortcuts ignore browser modifier combinations", async ({ page }) => {
    const unlockedLessons = JSON.stringify(Array.from({ length: 10 }, (_, index) => index));

    await page.addInitScript((lessons) => {
      localStorage.setItem("acfs-learning-hub-completed-lessons", lessons);
    }, unlockedLessons);

    await page.goto("/learn/keeping-updated");
    await page.waitForLoadState("networkidle");

    await page.keyboard.press("ControlOrMeta+c");

    const storedLessons = await page.evaluate(() =>
      localStorage.getItem("acfs-learning-hub-completed-lessons")
    );
    expect(storedLessons).toBe(unlockedLessons);
  });

});
