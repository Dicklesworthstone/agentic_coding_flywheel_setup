import { expect, test } from "@playwright/test";
import { resolveModuleSelection } from "../lib/moduleSelection";
import { ACFS_RECOMMENDED_UBUNTU } from "../lib/vpsProviders";

test.describe
  .serial("Learning Hub", () => {
    test("completion controls wait for saved progress hydration", async ({ browser, baseURL }) => {
      const context = await browser.newContext({ javaScriptEnabled: false, baseURL });
      try {
        const page = await context.newPage();
        await page.goto("/learn/welcome");
        await expect(page.getByRole("button", { name: "Mark Complete", exact: true, includeHidden: true })).toBeDisabled();
        await expect(page.getByRole("button", { name: "Complete", exact: true, includeHidden: true })).toBeDisabled();
      } finally {
        await context.close();
      }
    });
    test("local next steps explain their reasons and update for recovery and team goals", async ({ page }) => {
      await page.addInitScript(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", "[0,1]");
        localStorage.setItem("agent-flywheel-module-profile", "minimal");
      });
      await page.goto("/learn");
      const steps = page.getByTestId("learning-recommendations");
      await expect(steps).toBeVisible();
      await expect(steps).toHaveAttribute("data-persona", "minimal");
      await expect(steps.getByRole("link").first()).toHaveAttribute("href", "/learn/ssh-basics");
      await expect(steps).toContainText("selected stack");
      const goal = page.getByRole("combobox", { name: "What are you working on?" });
      await goal.selectOption("recover");
      await expect(steps).toHaveAttribute("data-persona", "recovery");
      await expect(steps.getByRole("link").first()).toHaveAttribute("href", "/wizard/status-check");
      await goal.selectOption("swarm");
      await expect(steps).toHaveAttribute("data-persona", "team");
      await expect(steps.getByRole("link").first()).toHaveAttribute("href", "/core-flywheel");
      await expect(steps).toContainText("Agent Mail");
      expect(await page.evaluate(() => localStorage.getItem("acfs-learning-hub-completed-lessons"))).toBe("[0,1]");
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
      const links = await steps.getByRole("link").evaluateAll((elements) => elements.map((element) => {
        const rect = element.getBoundingClientRect(); return { width: rect.width, height: rect.height };
      }));
      expect(links.every((rect) => rect.width >= 44 && rect.height >= 44)).toBe(true);
    });

    test("local doctor OS warnings drive recovery recommendations and clear on replacement", async ({ page }) => {
      await page.addInitScript(() => {
        localStorage.setItem("agent-flywheel-vps-ip", "203.0.113.7");
        localStorage.setItem("agent-flywheel-ssh-username", "developer");
        localStorage.setItem("agent-flywheel-install-mode", "safe");
        localStorage.setItem("agent-flywheel-module-profile", "minimal");
      });
      const plan = resolveModuleSelection({ profile: "minimal" });
      expect(plan.ok).toBe(true);
      const report = {
        acfs_version: "0.9.0", timestamp: new Date().toISOString(), mode: "safe", deep_mode: false,
        user: "developer", os: { id: "ubuntu", version: ACFS_RECOMMENDED_UBUNTU },
        summary: { pass: plan.included.length, fail: 0, warn: 0, skip: 0 },
        checks: plan.included.map((module) => ({ id: module.id, status: "pass",
          label: "PRIVATE_REPORT_LABEL", details: "PRIVATE_REPORT_DETAIL", fix: null })),
      };
      await page.goto("/learn");
      const steps = page.getByTestId("learning-recommendations");
      await expect(steps).toHaveAttribute("data-persona", "minimal");
      await page.getByText("Diagnose a doctor JSON report locally", { exact: true }).click();
      const input = page.getByLabel("Doctor JSON report (maximum 1 MiB)");
      const upload = async () => input.setInputFiles({
        name: "doctor.json", mimeType: "application/json", buffer: Buffer.from(JSON.stringify(report)),
      });
      await upload();
      await expect(page.getByText("Mapped checks report passes.", { exact: false })).toBeVisible();
      await expect(steps).toHaveAttribute("data-persona", "minimal");
      report.os.version = "24.04";
      await upload();
      await expect(page.getByText("differs from the recommended Ubuntu", { exact: false })).toBeVisible();
      await expect(steps).toHaveAttribute("data-persona", "recovery");
      await expect(steps.getByRole("link").first()).toHaveAttribute("href", "/wizard/status-check");
      report.os.version = ACFS_RECOMMENDED_UBUNTU;
      await upload();
      await expect(page.getByText("Mapped checks report passes.", { exact: false })).toBeVisible();
      await expect(steps).toHaveAttribute("data-persona", "minimal");
      await expect(page.locator("body")).not.toContainText("PRIVATE_REPORT_");
      await page.getByRole("button", { name: "Clear doctor report", exact: true }).click();
      await expect(page.getByText("Report SHA-256:", { exact: false })).toHaveCount(0);
      await expect(steps).toHaveAttribute("data-persona", "minimal");
      expect(await page.evaluate(() => localStorage.getItem("acfs-learning-hub-completed-lessons"))).toBeNull();
    });

    test("clearing progress in another tab resets the current learning recommendations", async ({ page, context }) => {
      await page.addInitScript(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", "[0,1]");
      });
      await page.goto("/learn");
      const next = page.getByTestId("learning-recommendations").getByRole("link").first();
      await expect(next).toHaveAttribute("href", "/learn/ssh-basics");
      const other = await context.newPage();
      try {
        await other.goto("/learn");
        await other.evaluate(() => localStorage.clear());
        await expect(next).toHaveAttribute("href", "/learn/welcome");
        await expect(page.getByTestId("learning-recommendations")).toHaveAttribute("data-persona", "getting-started");
      } finally {
        await other.close();
      }
    });

    test("complete lesson progress offers references without an inaccessible next lesson", async ({ page }) => {
      await page.addInitScript(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify(Array.from({ length: 100 }, (_, index) => index)));
      });
      await page.goto("/learn");
      const steps = page.getByTestId("learning-recommendations");
      await expect(steps).toHaveAttribute("data-persona", "all-complete");
      await expect(steps.locator('[data-recommendation-id^="lesson-"]')).toHaveCount(0);
      await expect(steps.getByRole("link")).not.toHaveCount(0);
    });

    test("lesson sidebar follows the narrow and wide viewport layouts", async ({ page }) => {
      await page.addInitScript(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify(Array.from({ length: 50 }, (_, index) => index)));
      });
      await page.setViewportSize({ width: 1024, height: 900 });
      await page.goto("/learn/debugging-agents");
      const sidebar = page.getByTestId("lesson-sidebar");
      await expect(sidebar).toHaveCount(1);
      await expect(sidebar).toBeHidden();
      await page.setViewportSize({ width: 1440, height: 900 });
      await expect(sidebar).toBeVisible();
    });

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

    test("desktop lesson sidebar stays visible while the lesson scrolls", async ({
      page,
    }, testInfo) => {
      test.skip(
        testInfo.project.name.startsWith("Mobile"),
        "The lesson sidebar is intentionally hidden on mobile",
      );
      // WebKit's classic scrollbar makes a 1280px window narrower than xl.
      await page.setViewportSize({ width: 1440, height: 900 });

      await page.addInitScript(() => {
        localStorage.setItem(
          "acfs-learning-hub-completed-lessons",
          JSON.stringify(Array.from({ length: 50 }, (_, index) => index)),
        );
      });

      await page.goto("/learn/debugging-agents");
      await page.waitForLoadState("networkidle");

      const sidebar = page.getByTestId("lesson-sidebar");
      await expect(sidebar).toBeVisible();

      await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
      await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(0);

      await expect
        .poll(() => sidebar.evaluate((element) => Math.round(element.getBoundingClientRect().top)))
        .toBe(0);
    });

    test("first visit to a deep lesson reveals the current lesson in the sidebar", async ({
      page,
    }, testInfo) => {
      test.skip(
        testInfo.project.name.startsWith("Mobile"),
        "The lesson sidebar is intentionally hidden on mobile",
      );
      await page.setViewportSize({ width: 1440, height: 900 });

      await page.addInitScript(() => {
        localStorage.setItem(
          "acfs-learning-hub-completed-lessons",
          JSON.stringify(Array.from({ length: 49 }, (_, index) => index)),
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
          }),
        )
        .toBe(true);
    });

    test("desktop lesson sidebar remembers its scroll position between lessons", async ({
      page,
    }, testInfo) => {
      test.skip(
        testInfo.project.name.startsWith("Mobile"),
        "The lesson sidebar is intentionally hidden on mobile",
      );
      await page.setViewportSize({ width: 1440, height: 900 });

      await page.addInitScript(() => {
        localStorage.setItem(
          "acfs-learning-hub-completed-lessons",
          JSON.stringify(Array.from({ length: 50 }, (_, index) => index)),
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
            Number(sessionStorage.getItem("acfs-learning-hub-sidebar-scroll-top")),
          );
          return Math.abs(stored - savedScrollTop);
        })
        .toBeLessThanOrEqual(2);

      // The shortcut is inert until lesson progress loads; the footer link to the
      // next lesson renders on exactly the condition the shortcut checks.
      await expect(
        page.getByRole("main").locator('a[href="/learn/context-mastery"]', { hasText: "Next" }),
      ).toBeVisible();

      // Navigate to the next lesson via the keyboard shortcut.
      await page.keyboard.press("ArrowRight");
      await expect(page).toHaveURL(/\/learn\/context-mastery$/);

      const restoredNav = page.getByRole("navigation", { name: "Lessons" });
      await expect
        .poll(() =>
          restoredNav.evaluate(
            (element, expected) => Math.abs(element.scrollTop - expected),
            savedScrollTop,
          ),
        )
        .toBeLessThanOrEqual(2);
    });

    test("lesson route server-renders lesson content before progress hydration", async ({
      request,
    }) => {
      const response = await request.get("/learn/welcome");
      expect(response.ok()).toBeTruthy();

      const html = await response.text();
      expect(html).toContain("What You Now Have");
      expect(html).not.toContain("Loading Progress");
    });

    test("current lesson does not expose locked next-lesson links before completion", async ({
      page,
    }) => {
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
      // The next-action fallback and the existing Quick Reference both link here.
      await expect(page.locator('a[href="/learn/commands"]')).toHaveCount(2);
      await expect(page.locator('a[href="/glossary"]')).toHaveCount(1);
    });

    test("a still-locked lesson ignores the complete shortcut", async ({ page }) => {
      await page.goto("/learn/git-basics");
      await page.waitForLoadState("networkidle");

      await expect(page.getByText("Lesson Locked")).toBeVisible();
      await page.keyboard.press("c");

      const storedLessons = await page.evaluate(() =>
        localStorage.getItem("acfs-learning-hub-completed-lessons"),
      );
      expect(storedLessons).toBeNull();
    });

    test("reference lessons show their content instead of a lock gate", async ({ page }) => {
      await page.goto("/learn/agent-commands");
      await page.waitForLoadState("networkidle");

      // No lock gate, and the actual lesson content renders for a fresh visitor.
      await expect(page.getByText("Lesson Locked")).toHaveCount(0);
      await expect(page.getByRole("heading", { name: "Agent Commands", level: 1 })).toBeVisible();
    });

    test("lesson completion fails cleanly when browser storage rejects writes", async ({
      page,
    }) => {
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
          "Unable to save lesson progress. Check your browser storage settings and try again.",
        ),
      ).toBeVisible();
      await expect(page).toHaveURL(/\/learn\/welcome$/);

      const storedLessons = await page.evaluate(() =>
        localStorage.getItem("acfs-learning-hub-completed-lessons"),
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

    test("generated command docs prefer internal ACFS tool lessons when available", async ({
      page,
    }) => {
      await page.goto("/learn/commands");
      await page.waitForLoadState("networkidle");

      const rchDocsLink = page.locator('a[href="/learn/tools/rch"]').first();
      const agentMailDocsLink = page.locator('a[href="/learn/tools/agent-mail"]').first();
      const ruDocsLink = page.locator('a[href="/learn/tools/ru"]').first();
      await expect(rchDocsLink).toBeVisible();
      await expect(agentMailDocsLink).toBeVisible();
      await expect(ruDocsLink).toBeVisible();
      await expect(
        page.locator('a[href="https://github.com/Dicklesworthstone/remote_compilation_helper"]'),
      ).toHaveCount(0);
      await expect(
        page.locator('a[href="https://github.com/Dicklesworthstone/mcp_agent_mail"]'),
      ).toHaveCount(0);
      await expect(
        page.locator('a[href="https://github.com/Dicklesworthstone/repo_updater"]'),
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
        localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify([0, 1]));
      });

      await page.goto("/learn");
      await page.waitForLoadState("networkidle");

      await page.keyboard.press("j");
      await page.keyboard.press("j");

      // The hub renders responsive duplicates of this link (one hidden per breakpoint); use the visible one.
      const continueLink = page
        .locator('a[href="/learn/ssh-basics"]')
        .filter({ visible: true })
        .first();
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
        localStorage.getItem("acfs-learning-hub-completed-lessons"),
      );
      expect(storedLessons).toBe(unlockedLessons);
    });
  });
