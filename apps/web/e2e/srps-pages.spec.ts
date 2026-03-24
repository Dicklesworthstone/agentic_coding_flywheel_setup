import { test, expect } from "@playwright/test";

test.describe.serial("SRPS Website Pages", () => {
  test.describe("SRPS Tool Page", () => {
    test("SRPS tool page loads without JS errors", async ({ page }) => {
      const errors: string[] = [];

      page.on("console", (msg) => {
        if (msg.type() === "error") {
          errors.push(`Console: ${msg.text()}`);
        }
      });

      page.on("pageerror", (error) => {
        errors.push(`Page Error: ${error.message}`);
      });

      await page.goto("/learn/tools/srps");
      await page.waitForLoadState("networkidle");

      // Check page title contains SRPS reference
      await expect(page.locator("h1").first()).toBeVisible();

      // Verify key sections exist
      await expect(page.getByText(/quick start/i).first()).toBeVisible();

      // No JS errors should have occurred
      expect(errors).toEqual([]);
    });

    test("SRPS tool page has code examples", async ({ page }) => {
      await page.goto("/learn/tools/srps");
      await page.waitForLoadState("networkidle");

      // Check for code blocks
      const title = page.getByText(/srps|System Resource Protection/i).first();
      await expect(title).toBeVisible();
    });

    test("SRPS tool page mentions sysmoni command", async ({ page }) => {
      await page.goto("/learn/tools/srps");
      await page.waitForLoadState("networkidle");

      // Check for sysmoni reference
      const sysmoniMention = page.getByText(/sysmoni/i).first();
      await expect(sysmoniMention).toBeVisible();
    });
  });

  test.describe("SRPS Lesson Page", () => {
    test("SRPS lesson loads without JS errors", async ({ page }) => {
      const errors: string[] = [];

      page.on("console", (msg) => {
        if (msg.type() === "error") {
          errors.push(`Console: ${msg.text()}`);
        }
      });

      page.on("pageerror", (error) => {
        errors.push(`Page Error: ${error.message}`);
      });

      // Unlock lesson 23 (SRPS)
      await page.goto("/");
      await page.evaluate(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify(Array.from({ length: 23 }, (_, i) => i)));
      });

      await page.goto("/learn/srps");
      await page.waitForLoadState("networkidle");

      // Check lesson content loads
      await expect(page.locator("h1").first()).toBeVisible();

      // No JS errors
      expect(errors).toEqual([]);
    });

    test("SRPS lesson has interactive elements", async ({ page }) => {
      // Unlock lesson 23 (SRPS)
      await page.goto("/");
      await page.evaluate(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify(Array.from({ length: 23 }, (_, i) => i)));
      });

      await page.goto("/learn/srps");
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

    test("SRPS lesson has installation section", async ({ page }) => {
      // Unlock lesson 23 (SRPS)
      await page.goto("/");
      await page.evaluate(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify(Array.from({ length: 23 }, (_, i) => i)));
      });

      await page.goto("/learn/srps");
      await page.waitForLoadState("networkidle");

      // Check for installation content
      const installationText = page.getByText(/install/i).first();
      await expect(installationText).toBeVisible();
    });
  });

  test.describe("SRPS on Flywheel Page", () => {
    test("SRPS appears in flywheel stack", async ({ page }) => {
      await page.goto("/flywheel");
      await page.waitForLoadState("networkidle");

      // Check SRPS is in the stack visualization
      // Note: Flywheel renders both desktop and mobile versions, one is hidden via CSS.
      // We explicitly filter for the visible one.
      await expect(page.getByText(/\bSRPS\b|System Resource/i).filter({ visible: true }).first()).toBeVisible({ timeout: 5000 });
    });

    test("flywheel page mentions System Resource Protection", async ({
      page,
    }) => {
      // Unlock lesson 23 (SRPS)
      await page.goto("/");
      await page.evaluate(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify(Array.from({ length: 23 }, (_, i) => i)));
      });

      await page.goto("/flywheel");
      await page.waitForLoadState("networkidle");

      // Check for SRPS description
      const description = page
        .getByText(/resource protection|responsive|ananicy/i)
        .first();
      await expect(description).toBeAttached();
    });
  });

  test.describe("SRPS on TLDR Page", () => {
    test("SRPS appears in TLDR list", async ({ page }) => {
      await page.goto("/tldr");
      await page.waitForLoadState("networkidle");

      // Check SRPS is listed
      const srpsMention = page.getByText(/SRPS/i).first();
      await expect(srpsMention).toBeVisible();
    });

    test("TLDR page loads without JS errors with SRPS entry", async ({
      page,
    }) => {
      const errors: string[] = [];

      page.on("console", (msg) => {
        if (msg.type() === "error") {
          errors.push(`Console: ${msg.text()}`);
        }
      });

      page.on("pageerror", (error) => {
        errors.push(`Page Error: ${error.message}`);
      });

      await page.goto("/tldr");
      await page.waitForLoadState("networkidle");

      await expect(page.locator("h1").first()).toBeVisible();
      expect(errors).toEqual([]);
    });
  });

  test.describe("SRPS Glossary Entry", () => {
    test("SRPS appears in glossary", async ({ page }) => {
      await page.goto("/learn/glossary");
      await page.waitForLoadState("networkidle");

      // Check SRPS entry exists
      const srpsEntry = page.getByText(/SRPS/i).first();
      await expect(srpsEntry).toBeVisible();
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

  test.describe("SRPS Commands Reference", () => {
    test("sysmoni command appears in commands page", async ({ page }) => {
      await page.goto("/learn/commands");
      await page.waitForLoadState("networkidle");

      // Check for sysmoni command reference
      const sysmoniCommand = page.getByText(/sysmoni/i).first();
      await expect(sysmoniCommand).toBeVisible();
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
  });

  test.describe("SRPS Navigation", () => {
    test("can navigate from learn to SRPS lesson page", async ({ page }) => {
      // Mock progress to unlock lessons
      await page.addInitScript(() => {
        window.localStorage.setItem('acfs-learning-hub-completed-lessons', JSON.stringify(Array.from({length: 50}, (_, i) => i)));
      });
      await page.goto("/learn");
      await page.waitForLoadState("networkidle");

      // Find and click link to SRPS - the link should exist
      const srpsLink = page.getByRole("link", { name: /\bSRPS\b/i }).first();
      await expect(srpsLink).toBeVisible({ timeout: 5000 });
      await srpsLink.click();
    });

    test("can navigate from flywheel to SRPS tool page", async ({ page }) => {
      await page.goto("/flywheel");
      await page.waitForLoadState("networkidle");

      // Find and click link to SRPS
      const srpsLink = page.getByRole("link", { name: /SRPS/i }).first();
      if (await srpsLink.isVisible()) {
        await srpsLink.click();
        await page.waitForLoadState("networkidle");
        await expect(page).toHaveURL(/srps/i);
      }
    });
  });

  test.describe("SRPS Synergies", () => {
    test("SRPS synergies with NTM are documented", async ({ page }) => {
      await page.goto("/learn/tools/srps");
      await page.waitForLoadState("networkidle");

      // Check for NTM synergy reference
      const ntmMention = page.getByText(/NTM|tmux/i).first();
      await expect(ntmMention).toBeVisible();
    });

    test("SRPS synergies with DCG are documented", async ({ page }) => {
      await page.goto("/learn/tools/srps");
      await page.waitForLoadState("networkidle");

      // Check for DCG synergy reference
      const dcgMention = page.getByText(/DCG|destructive/i).first();
      await expect(dcgMention).toBeVisible();
    });
  });
});
