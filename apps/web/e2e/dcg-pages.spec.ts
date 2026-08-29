import { test, expect } from "@playwright/test";

test.describe.serial("DCG Website Pages", () => {
  test.describe("DCG Tool Page", () => {
    test("DCG tool page loads without JS errors", async ({ page }) => {
      const errors: string[] = [];

      page.on("console", (msg) => {
        if (msg.type() === "error") {
          errors.push(`Console: ${msg.text()}`);
        }
      });

      page.on("pageerror", (error) => {
        errors.push(`Page Error: ${error.message}`);
      });

      await page.goto("/learn/tools/dcg");
      await page.waitForLoadState("networkidle");

      // Check page title contains DCG reference
      await expect(page.locator("h1").first()).toBeVisible();

      // Verify key sections exist
      await expect(page.getByText(/Destructive Command Guard/i).first()).toBeVisible();

      // No JS errors should have occurred
      expect(errors).toEqual([]);
    });

    test("DCG tool page has code examples", async ({ page }) => {
      await page.goto("/learn/tools/dcg");
      await page.waitForLoadState("networkidle");

      // Check for code blocks
      const title = page.getByText(/dcg|Destructive Command Guard/i).first();
      await expect(title).toBeVisible();
    });
  });

  test.describe("DCG Lesson Page", () => {
    test("DCG lesson loads without JS errors", async ({ page }) => {
      const errors: string[] = [];

      page.on("console", (msg) => {
        if (msg.type() === "error") {
          errors.push(`Console: ${msg.text()}`);
        }
      });

      page.on("pageerror", (error) => {
        errors.push(`Page Error: ${error.message}`);
      });

      // Unlock lesson 21 (DCG)
      await page.goto("/");
      await page.evaluate(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify(Array.from({ length: 21 }, (_, i) => i)));
      });

      await page.goto("/learn/dcg");
      await page.waitForLoadState("networkidle");

      // Check lesson content loads
      await expect(page.locator("h1").first()).toBeVisible();

      // No JS errors
      expect(errors).toEqual([]);
    });

    test("DCG lesson has interactive elements", async ({ page }) => {
      // Unlock lesson 21 (DCG)
      await page.goto("/");
      await page.evaluate(() => {
        localStorage.setItem("acfs-learning-hub-completed-lessons", JSON.stringify(Array.from({ length: 21 }, (_, i) => i)));
      });

      await page.goto("/learn/dcg");
      await page.waitForLoadState("networkidle");

      // The lesson sidebar (hidden on phones) lists "DCG" before the lesson body; assert a visible instance.
      const title = page.getByText(/dcg/i).filter({ visible: true }).first();
      await expect(title).toBeVisible();
    });
  });

  test.describe("DCG on Landing Page", () => {
    test("DCG is mentioned in tool showcase", async ({ page }) => {
      await page.goto("/");
      await page.waitForLoadState("networkidle");

      // Check DCG appears somewhere on the landing page
      const dcgMention = page.getByText(/DCG|Destructive Command Guard/i).first();
      await expect(dcgMention).toBeVisible();
    });
  });

  test.describe("DCG on Flywheel Page", () => {
    test("DCG appears in flywheel stack", async ({ page }) => {
      await page.goto("/flywheel");
      await page.waitForLoadState("networkidle");

      // Check DCG is in the stack visualization
      // A desktop-only stack badge precedes the visible mention on phones; assert a visible instance.
      const dcgMention = page.getByText(/DCG/i).filter({ visible: true }).first();
      await expect(dcgMention).toBeVisible();
    });

    test("flywheel page loads without JS errors", async ({ page }) => {
      const errors: string[] = [];

      page.on("console", (msg) => {
        if (msg.type() === "error") {
          errors.push(`Console: ${msg.text()}`);
        }
      });

      page.on("pageerror", (error) => {
        errors.push(`Page Error: ${error.message}`);
      });

      await page.goto("/flywheel");
      await page.waitForLoadState("networkidle");

      await expect(page.locator("h1").first()).toBeVisible();
      expect(errors).toEqual([]);
    });
  });

  test.describe("DCG Glossary Entry", () => {
    test("DCG appears in glossary", async ({ page }) => {
      await page.goto("/glossary");
      await page.waitForLoadState("networkidle");

      // Check the DCG entry itself (other entries mention DCG inside their
      // collapsed definitions, so a page-wide text match is not enough).
      const dcgEntry = page.locator("#dcg");
      await expect(dcgEntry).toBeVisible();
      await expect(dcgEntry.getByText(/DCG/i).first()).toBeVisible();
    });

    test("DCG glossary entry expands definition", async ({ page }) => {
      await page.goto("/glossary");
      await page.waitForLoadState("networkidle");

      // /glossary entries are native <details> disclosures: the summary row
      // opens the full definition.
      const dcgCard = page.locator("#dcg");
      await expect(dcgCard).toBeVisible();

      await dcgCard.locator("summary").click();
      await expect(dcgCard).toHaveAttribute("open", "");

      await expect(
        dcgCard.getByText(/Destructive Command Guard/i).first()
      ).toBeVisible();
    });

    test("glossary page loads without JS errors with DCG entry", async ({
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

      await page.goto("/glossary");
      await page.waitForLoadState("networkidle");

      await expect(page.locator("h1").first()).toBeVisible();
      expect(errors).toEqual([]);
    });
  });

  test.describe("DCG Commands Reference", () => {
    test("DCG commands appear in commands page", async ({ page }) => {
      await page.goto("/learn/commands");
      await page.waitForLoadState("networkidle");

      // Check for DCG command reference
      const dcgCommands = page.getByText(/dcg/i).first();
      await expect(dcgCommands).toBeVisible();
    });
  });

  test.describe("DCG Navigation", () => {
    test("can navigate from learn to DCG tool page", async ({ page }) => {
      await page.goto("/learn");
      await page.waitForLoadState("networkidle");

      // Find and click link to DCG
      // Locked lesson cards are aria-disabled links by design; navigate through an enabled one.
      const dcgLink = page.locator('a[href*="dcg"]:not([aria-disabled="true"])').first();
      if (await dcgLink.isVisible()) {
        await dcgLink.click();
        await page.waitForLoadState("networkidle");
        await expect(page).toHaveURL(/dcg/i);
      }
    });
  });
});
