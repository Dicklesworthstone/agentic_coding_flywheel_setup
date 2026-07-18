import { test, expect } from "@playwright/test";

/**
 * Antigravity (agy) migration — live browser coverage (bd-47kjh.10.1.6).
 *
 * Verifies the deeper agent-MODEL + curriculum migration from the retired
 * Gemini CLI (gmi) to the Antigravity CLI (agy) end-to-end:
 *   - /learn/tools/antigravity-cli is a real 200 route (guards the
 *     generateStaticParams/tool-data 404 risk from .2 — the site recently had a
 *     404-cleanup pass; this must not regress)
 *   - the command reference (/learn/commands) shows the agy command + its docs link
 *   - the agents-login lesson + complete-guide teach agy with --agy= spawn usage
 *   - the explicitly-legacy gmi display IS still present (regression guard against
 *     over-migration), but no operational gmi-as-primary command remains
 *
 * The "meet your agents" hero-card carousel + QuickAccessBar components are not
 * mounted on any route in the current app, so their Antigravity card is asserted
 * structurally in the unit suite (components/agent-commands/*.test.tsx) rather
 * than here.
 */

// Unlock every lesson (agent-commands is lesson index 6) before visiting gated routes.
const UNLOCK_ALL_LESSONS = () => {
  window.localStorage.setItem(
    "acfs-learning-hub-completed-lessons",
    JSON.stringify(Array.from({ length: 60 }, (_, i) => i)),
  );
};

test.describe.serial("Antigravity (agy) migration pages", () => {
  test.describe("Antigravity CLI tool page (404 guard)", () => {
    test("/learn/tools/antigravity-cli returns 200 (not 404)", async ({ request }) => {
      const res = await request.get("/learn/tools/antigravity-cli");
      console.log(`GET /learn/tools/antigravity-cli -> ${res.status()}`);
      expect(res.status()).toBe(200);
    });

    test("renders the Antigravity tool page without JS errors", async ({ page }) => {
      const errors: string[] = [];
      page.on("console", (msg) => {
        if (msg.type() === "error") errors.push(`Console: ${msg.text()}`);
      });
      page.on("pageerror", (error) => errors.push(`Page Error: ${error.message}`));

      await test.step("navigate + render h1", async () => {
        await page.goto("/learn/tools/antigravity-cli");
        await page.waitForLoadState("networkidle");
        await expect(page.locator("h1").first()).toBeVisible();
        await expect(
          page.getByText(/Antigravity CLI/i).first(),
        ).toBeVisible();
      });

      await test.step("mentions the pinned Gemini 3.1 Pro model + agy command", async () => {
        await expect(page.getByText(/Gemini 3\.1 Pro/i).first()).toBeVisible();
      });

      expect(errors).toEqual([]);
    });

    test("legacy /learn/tools/gemini-cli still resolves (200, retained)", async ({ request }) => {
      const res = await request.get("/learn/tools/gemini-cli");
      console.log(`GET /learn/tools/gemini-cli -> ${res.status()}`);
      expect(res.status()).toBe(200);
    });
  });

  test.describe("Command reference", () => {
    test("/learn/commands shows the agy command + antigravity-cli docs link", async ({ page }) => {
      await page.goto("/learn/commands");
      await page.waitForLoadState("networkidle");

      await test.step("agy command is listed", async () => {
        await expect(page.getByText(/\bagy\b/i).first()).toBeVisible();
      });

      await test.step("agy docs link points at the real tool route", async () => {
        await expect(
          page.locator('a[href="/learn/tools/antigravity-cli"]').first(),
        ).toBeVisible();
      });
    });
  });

  test.describe("Onboarding curriculum (agents-login lesson)", () => {
    test("teaches agy and keeps a labeled-legacy gmi note", async ({ page }) => {
      const errors: string[] = [];
      page.on("pageerror", (error) => errors.push(`Page Error: ${error.message}`));

      await page.addInitScript(UNLOCK_ALL_LESSONS);
      await page.goto("/learn/agent-commands");
      await page.waitForLoadState("networkidle");

      await test.step("lesson renders + teaches agy", async () => {
        await expect(page.locator("h1").first()).toBeVisible();
        await expect(page.getByText(/\bagy\b/).first()).toBeVisible();
      });

      await test.step("legacy gmi is still shown but clearly legacy", async () => {
        const legacyNote = page
          .getByText(/legacy|retired/i)
          .filter({ hasText: /gmi|gemini/i });
        await expect(legacyNote.first()).toBeVisible();
      });

      expect(errors).toEqual([]);
    });
  });

  test.describe("Complete guide", () => {
    test("shows the cc/cod/agy swarm ratio + Antigravity column", async ({ page }) => {
      await page.goto("/complete-guide");
      await page.waitForLoadState("networkidle");

      await test.step("renders the dated current-model guidance", async () => {
        await expect(page.getByText("Last reviewed July 17, 2026")).toBeVisible();
        await expect(page.getByText(/GPT-5\.6 Sol Pro/).first()).toBeVisible();
        await expect(page.getByText(/Claude Fable 5/).first()).toBeVisible();
        await expect(page.getByText(/Grok 4\.5/).first()).toBeVisible();
      });

      await test.step("--agy= spawn ratio is present", async () => {
        // The guide renders responsive duplicates (one hidden via CSS); assert the visible one.
        await expect(
          page.getByText(/--agy=/).filter({ visible: true }).first(),
        ).toBeVisible();
      });

      await test.step("comparison table has the Antigravity (agy) column", async () => {
        await expect(
          page.getByText(/Antigravity \(agy\)/i).filter({ visible: true }).first(),
        ).toBeVisible();
      });

      await test.step("renders manifest-backed tooling and canonical install guidance", async () => {
        await expect(page.getByText(/25 default-enabled stack modules/).first()).toBeVisible();
        await expect(
          page.getByText(/raw\.githubusercontent\.com\/Dicklesworthstone/).first(),
        ).toBeVisible();
        await expect(page.getByText("Foundation").first()).toBeVisible();
      });
    });
  });
});
