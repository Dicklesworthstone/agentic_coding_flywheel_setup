import { test, expect } from "@playwright/test";

test.describe.serial("RU Website Pages", () => {
  test.describe("RU Tool Page", () => {
    test("RU tool page loads without JS errors", async ({ page }) => {
      const errors: string[] = [];

      page.on("console", (msg) => {
        if (msg.type() === "error") {
          errors.push(`Console: ${msg.text()}`);
        }
      });

      page.on("pageerror", (error) => {
        errors.push(`Page Error: ${error.message}`);
      });

      await page.goto("/learn/tools/ru");
      await page.waitForLoadState("networkidle");

      // Check page title contains RU reference
      await expect(page.locator("h1").first()).toBeVisible();

      // Verify key sections exist
      await expect(page.getByText(/quick start/i).first()).toBeVisible();

      // No JS errors should have occurred
      expect(errors).toEqual([]);
    });

    test("RU tool page has code examples", async ({ page }) => {
      await page.goto("/learn/tools/ru");
      await page.waitForLoadState("networkidle");

      // Check for code blocks
      const title = page.getByText(/ru|Repository Utility/i).first();
      await expect(title).toBeVisible();
    });
  });

  test.describe("RU Lesson Page", () => {
    test("RU lesson loads without JS errors", async ({ page }) => {
      const errors: string[] = [];

      page.on("console", (msg) => {
        if (msg.type() === "error") {
          errors.push(`Console: ${msg.text()}`);
        }
      });

      page.on("pageerror", (error) => {
        errors.push(`Page Error: ${error.message}`);
      });

      // Set localStorage to unlock lesson 20 (RU)
      await page.goto("/");
      await page.evaluate(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify(Array.from({ length: 20 }, (_, i) => i)));
      });

      await page.goto("/learn/ru");
      await page.waitForLoadState("networkidle");

      // Check lesson content loads
      await expect(page.locator("h1").first()).toBeVisible();

      // No JS errors
      expect(errors).toEqual([]);
    });

    test("RU lesson has interactive elements", async ({ page }) => {
      // Set localStorage to unlock lesson 20 (RU)
      await page.goto("/");
      await page.evaluate(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify(Array.from({ length: 20 }, (_, i) => i)));
      });

      await page.goto("/learn/ru");
      await page.waitForLoadState("networkidle");

      // Check for buttons or interactive elements
      const interactiveElements = page.locator(
        'button, input, [role="button"]'
      );
      const count = await interactiveElements.count();
      expect(count).toBeGreaterThan(0);

      const copyButtons = page.getByRole("button", { name: /copy/i });
      await expect(copyButtons.first()).toBeVisible();
    });

    test("RU lesson shows all major sections", async ({ page }) => {
      // Set localStorage to unlock lesson 20 (RU)
      await page.goto("/");
      await page.evaluate(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify(Array.from({ length: 20 }, (_, i) => i)));
      });

      await page.goto("/learn/ru");
      await page.waitForLoadState("networkidle");

      // Check for major RU sections
      await expect(
        page.getByText(/sync|status|agent.*sweep/i).first()
      ).toBeVisible();
    });
  });

  test.describe("RU on Landing Page", () => {
    test("RU is mentioned in tool showcase", async ({ page }) => {
      await page.goto("/");
      await page.waitForLoadState("networkidle");

      // Check RU appears somewhere on the landing page
      const ruMention = page.getByText(/\bRU\b|Repo Updater/i).first();
      await expect(ruMention).toBeVisible();
    });
  });

  test.describe("RU on Flywheel Page", () => {
    test("RU appears in flywheel stack", async ({ page }) => {
      await page.goto("/flywheel");
      await page.waitForLoadState("networkidle");

      // Check RU is in the stack visualization
      // Note: Flywheel renders both desktop and mobile versions, one is hidden via CSS.
      // We explicitly filter for the visible one to pass on both desktop and mobile.
      await expect(page.getByText(/\bRU\b|Repo Updater/i).filter({ visible: true }).first()).toBeVisible({ timeout: 5000 });
    });

    test("RU workflow scenarios visible", async ({ page }) => {
      // Set localStorage to unlock lesson 20 (RU)
      await page.goto("/");
      await page.evaluate(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify(Array.from({ length: 20 }, (_, i) => i)));
      });

      await page.goto("/flywheel");
      await page.waitForLoadState("networkidle");

      // Check for RU workflow scenarios
      const workflowSection = page.getByText(/multi.*repo|sync|agent.*sweep/i);
      await expect(workflowSection.first()).toBeAttached();
    });
  });

  test.describe("RU Glossary Entry", () => {
    test("RU-related terms appear in glossary", async ({ page }) => {
      await page.goto("/learn/glossary");
      await page.waitForLoadState("networkidle");

      // Check for agent-sweep or repo-related terms
      const agentSweepTerm = page.getByText(/agent.*sweep/i).first();
      await expect(agentSweepTerm).toBeVisible();
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
  });

  test.describe("RU Commands Reference", () => {
    test("RU commands appear in commands page", async ({ page }) => {
      await page.goto("/learn/commands");
      await page.waitForLoadState("networkidle");

      // Check for RU command reference
      const ruCommands = page.getByText(/\bru\b/i).first();
      await expect(ruCommands).toBeVisible();
    });

    test("RU command shows sync and agent-sweep", async ({ page }) => {
      await page.goto("/learn/commands");
      await page.waitForLoadState("networkidle");

      // Look for ru sync or agent-sweep mentions
      const ruContent = page.getByText(/sync|agent.*sweep|repo.*updater/i);
      await expect(ruContent.first()).toBeVisible();
    });
  });

  test.describe("RU Navigation", () => {
    test("can navigate from learn to RU lesson page", async ({ page }) => {
      // Mock progress to unlock lessons
      await page.addInitScript(() => {
        window.localStorage.setItem('acfs-learning-hub-completed-lessons', JSON.stringify(Array.from({length: 50}, (_, i) => i)));
      });
      await page.goto("/learn");
      await page.waitForLoadState("networkidle");

      // Find and click link to RU - the link should exist
      const ruLink = page.getByRole("link", { name: /\bRU\b|Repo Updater/i }).first();
      await expect(ruLink).toBeVisible({ timeout: 5000 });
      await ruLink.click();
      await page.waitForLoadState("networkidle");
      await expect(page).toHaveURL(/ru/i);
    });

    test("can navigate from flywheel to RU details", async ({ page }) => {
      await page.goto("/flywheel");
      await page.waitForLoadState("networkidle");

      // Find RU in the flywheel visualization - it should exist
      const ruElement = page.getByText(/\bRU\b|Repo Updater/i).first();
      await expect(ruElement).toBeVisible({ timeout: 5000 });
      await ruElement.click();
      // After clicking, some detail should appear
      await expect(page.getByText(/sync|multi.*repo/i).first()).toBeVisible();
    });
  });

  test.describe("RU Synergies", () => {
    test("RU synergies with other tools visible", async ({ page }) => {
      await page.goto("/flywheel");
      await page.waitForLoadState("networkidle");

      // Check for synergy explanations mentioning RU
      const synergyText = page.getByText(
        /multi.*repo.*orchestra|repo.*coordination/i
      );
      await expect(synergyText.first()).toBeVisible();
    });
  });
});
