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

  test("desktop lesson sidebar stays visible while the lesson scrolls", async ({ page }, testInfo) => {
    test.skip(
      testInfo.project.name.startsWith("Mobile"),
      "The lesson sidebar is intentionally hidden on mobile"
    );

    await page.addInitScript(() => {
      localStorage.setItem(
        "acfs-learning-hub-completed-lessons",
        JSON.stringify(Array.from({ length: 50 }, (_, index) => index))
      );
    });

    await page.goto("/learn/debugging-agents");
    await page.waitForLoadState("networkidle");

    const sidebar = page.getByTestId("lesson-sidebar");
    await expect(sidebar).toBeVisible();

    await page.evaluate(() =>
      window.scrollTo(0, document.documentElement.scrollHeight)
    );
    await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(0);

    await expect
      .poll(() =>
        sidebar.evaluate((element) => Math.round(element.getBoundingClientRect().top))
      )
      .toBe(0);
  });

  test("first visit to a deep lesson reveals the current lesson in the sidebar", async ({ page }, testInfo) => {
    test.skip(
      testInfo.project.name.startsWith("Mobile"),
      "The lesson sidebar is intentionally hidden on mobile"
    );

    await page.addInitScript(() => {
      localStorage.setItem(
        "acfs-learning-hub-completed-lessons",
        JSON.stringify(Array.from({ length: 49 }, (_, index) => index))
      );
    });

    await page.goto("/learn/debugging-agents");
    await page.waitForLoadState("networkidle");

    const lessonNav = page.getByRole("navigation", { name: "Lessons" });

    await expect
      .poll(() =>
        lessonNav.evaluate((nav) => {
          const currentLesson = nav.querySelector('[aria-current="page"]');
          if (!currentLesson) return false;
          const navRect = nav.getBoundingClientRect();
          const lessonRect = currentLesson.getBoundingClientRect();
          return lessonRect.top >= navRect.top && lessonRect.bottom <= navRect.bottom;
        })
      )
      .toBe(true);
  });

  test("desktop lesson sidebar remembers its scroll position between lessons", async ({ page }, testInfo) => {
    test.skip(
      testInfo.project.name.startsWith("Mobile"),
      "The lesson sidebar is intentionally hidden on mobile"
    );

    await page.addInitScript(() => {
      localStorage.setItem(
        "acfs-learning-hub-completed-lessons",
        JSON.stringify(Array.from({ length: 50 }, (_, index) => index))
      );
    });

    await page.goto("/learn/debugging-agents");
    await page.waitForLoadState("networkidle");

    const lessonNav = page.getByRole("navigation", { name: "Lessons" });

    const savedScrollTop = await lessonNav.evaluate((element) => {
      const maxScrollTop = element.scrollHeight - element.clientHeight;
      element.scrollTop = Math.floor(maxScrollTop * 0.65);
      return element.scrollTop;
    });
    expect(savedScrollTop).toBeGreaterThan(0);

    await expect
      .poll(async () => {
        const stored = await page.evaluate(() =>
          Number(sessionStorage.getItem("acfs-learning-hub-sidebar-scroll-top"))
        );
        return Math.abs(stored - savedScrollTop);
      })
      .toBeLessThanOrEqual(2);

    // Navigate to the next lesson via the keyboard shortcut.
    await page.keyboard.press("ArrowRight");
    await expect(page).toHaveURL(/\/learn\/context-mastery$/);

    const restoredNav = page.getByRole("navigation", { name: "Lessons" });
    await expect
      .poll(() =>
        restoredNav.evaluate(
          (element, expected) => Math.abs(element.scrollTop - expected),
          savedScrollTop
        )
      )
      .toBeLessThanOrEqual(2);
  });

  test("lesson route server-renders lesson content before progress hydration", async ({ request }) => {
    const response = await request.get("/learn/welcome");
    expect(response.ok()).toBeTruthy();

    const html = await response.text();
    expect(html).toContain("What You Now Have");
    expect(html).not.toContain("Loading Progress");
  });

  test("current lesson does not expose locked next-lesson links before completion", async ({ page }) => {
    await page.goto("/learn/welcome");
    await page.waitForLoadState("networkidle");

    await expect(page.locator('main a[href="/learn/linux-basics"]')).toHaveCount(0);
    await expect(page.locator('div.fixed a[href="/learn/linux-basics"]')).toHaveCount(0);
  });

  test("reference quick-reference lesson cards are always reachable", async ({ page }) => {
    await page.goto("/learn");
    await page.waitForLoadState("networkidle");

    // Reference lessons (#294) behave like the standalone Command Reference and
    // Glossary tiles: always linked, even for a brand-new visitor who has not
    // completed any earlier lessons. The Quick Reference card plus the All
    // Lessons grid card both render a link, so each href appears twice.
    await expect(page.locator('a[href="/learn/agent-commands"]')).toHaveCount(2);
    await expect(page.locator('a[href="/learn/ntm-palette"]')).toHaveCount(2);
    await expect(page.locator('a[href="/learn/commands"]')).toHaveCount(1);
    await expect(page.locator('a[href="/learn/glossary"]')).toHaveCount(1);
  });

  test("a still-locked lesson ignores the complete shortcut", async ({ page }) => {
    await page.goto("/learn/git-basics");
    await page.waitForLoadState("networkidle");

    await expect(page.getByText("Lesson Locked")).toBeVisible();
    await page.keyboard.press("c");

    const storedLessons = await page.evaluate(() =>
      localStorage.getItem("acfs-learning-hub-completed-lessons")
    );
    expect(storedLessons).toBeNull();
  });

  test("reference lessons show their content instead of a lock gate", async ({ page }) => {
    await page.goto("/learn/agent-commands");
    await page.waitForLoadState("networkidle");

    // No lock gate, and the actual lesson content renders for a fresh visitor.
    await expect(page.getByText("Lesson Locked")).toHaveCount(0);
    await expect(
      page.getByRole("heading", { name: "Agent Commands", level: 1 })
    ).toBeVisible();
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

  test("command docs links avoid locked lesson routes", async ({ page }) => {
    await page.goto("/learn/commands");
    await page.waitForLoadState("networkidle");

    await expect(page.locator('a[href="/learn/tools/claude-code"]').first()).toBeVisible();
    await expect(page.locator('a[href="/learn/tools/codex-cli"]').first()).toBeVisible();
    await expect(page.locator('a[href="/learn/tools/antigravity-cli"]').first()).toBeVisible();
    await expect(page.locator('a[href="/learn/tools/gemini-cli"]').first()).toBeVisible();
    await expect(page.locator('a[href="/learn/tools/ntm"]').first()).toBeVisible();
    await expect(page.locator('a[href="/learn/tools/beads"]').first()).toBeVisible();

    await expect(page.locator('a[href="/learn/agent-commands"]')).toHaveCount(0);
    await expect(page.locator('a[href="/learn/ntm-palette"]')).toHaveCount(0);
    await expect(page.locator('a[href="/learn/beads"]')).toHaveCount(0);
    await expect(page.locator('a[href="/learn/bv"]')).toHaveCount(0);
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
