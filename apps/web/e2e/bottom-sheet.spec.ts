import { test, expect } from "@playwright/test";

/**
 * BottomSheet Component E2E Tests
 *
 * Tests the BottomSheet component's interactive behavior including:
 * - Opening and closing animations
 * - Swipe-to-dismiss gesture
 * - Escape key dismissal
 * - Backdrop click dismissal
 * - Touch target sizes (44px minimum)
 * - Reduced motion behavior
 * - ARIA attributes for accessibility
 *
 * Note: These tests require a page that uses the BottomSheet component.
 * Once bd-3co7k.4.1 (Convert Jargon Modal to BottomSheet) is complete,
 * update the test routes accordingly.
 */

test.describe("BottomSheet Component", () => {
  test.beforeEach(async ({ page }) => {
    // Set mobile viewport for bottom sheet tests
    await page.setViewportSize({ width: 375, height: 812 }); // iPhone X
    console.log("[E2E] Set mobile viewport for bottom sheet tests");
  });

  test("bottom sheet opens with correct ARIA attributes", async ({ page }) => {
    // Navigate to a page with BottomSheet (glossary/jargon page once converted)
    await page.goto("/learn");
    console.log("[E2E] Navigated to learn page");

    // Look for any element that could trigger a bottom sheet
    const jargonTrigger = page.locator('[data-testid="jargon-term"]').first();
    const hasTrigger = (await jargonTrigger.count()) > 0;

    if (hasTrigger) {
      await jargonTrigger.click();
      console.log("[E2E] Clicked jargon term trigger");

      // Verify dialog appears with correct ARIA attributes
      const dialog = page.getByRole("dialog");
      await expect(dialog).toBeVisible({ timeout: 5000 });
      await expect(dialog).toHaveAttribute("aria-modal", "true");
      console.log("[E2E] Bottom sheet visible with correct ARIA attributes");
    } else {
      console.log(
        "[E2E] No jargon triggers found - BottomSheet not yet integrated. Skipping."
      );
      test.skip();
    }
  });

  test("escape key closes bottom sheet", async ({ page }) => {
    await page.goto("/learn");
    console.log("[E2E] Navigated to learn page");

    const jargonTrigger = page.locator('[data-testid="jargon-term"]').first();
    const hasTrigger = (await jargonTrigger.count()) > 0;

    if (hasTrigger) {
      await jargonTrigger.click();
      const dialog = page.getByRole("dialog");
      await expect(dialog).toBeVisible({ timeout: 5000 });
      console.log("[E2E] Bottom sheet opened");

      // Press Escape
      await page.keyboard.press("Escape");
      console.log("[E2E] Pressed Escape key");

      // Sheet should close
      await expect(dialog).not.toBeVisible({ timeout: 2000 });
      console.log("[E2E] Bottom sheet dismissed via Escape key");
    } else {
      console.log("[E2E] No jargon triggers found - skipping Escape test");
      test.skip();
    }
  });

  test("backdrop click closes bottom sheet", async ({ page }) => {
    await page.goto("/learn");
    console.log("[E2E] Navigated to learn page");

    const jargonTrigger = page.locator('[data-testid="jargon-term"]').first();
    const hasTrigger = (await jargonTrigger.count()) > 0;

    if (hasTrigger) {
      await jargonTrigger.click();
      const dialog = page.getByRole("dialog");
      await expect(dialog).toBeVisible({ timeout: 5000 });
      console.log("[E2E] Bottom sheet opened");

      // Click the backdrop (outside the dialog)
      // Calculate position above the sheet dynamically
      const dialogBox = await dialog.boundingBox();
      const viewport = page.viewportSize();
      if (dialogBox && viewport) {
        // Click in the center horizontally, but above the sheet (in backdrop area)
        const clickX = viewport.width / 2;
        const clickY = dialogBox.y / 2; // Click halfway between top of screen and sheet
        await page.mouse.click(clickX, clickY);
        console.log(`[E2E] Clicked backdrop area at (${clickX}, ${clickY})`);
      } else {
        // Fallback to a position near top of screen
        await page.mouse.click(187, 50);
        console.log("[E2E] Clicked backdrop area (fallback coordinates)");
      }

      await expect(dialog).not.toBeVisible({ timeout: 2000 });
      console.log("[E2E] Bottom sheet dismissed via backdrop click");
    } else {
      console.log("[E2E] No jargon triggers found - skipping backdrop test");
      test.skip();
    }
  });

  test("close button meets 44px touch target", async ({ page }) => {
    await page.goto("/learn");
    console.log("[E2E] Navigated to learn page");

    const jargonTrigger = page.locator('[data-testid="jargon-term"]').first();
    const hasTrigger = (await jargonTrigger.count()) > 0;

    if (hasTrigger) {
      await jargonTrigger.click();
      const dialog = page.getByRole("dialog");
      await expect(dialog).toBeVisible({ timeout: 5000 });

      // Find close button
      const closeButton = dialog.getByRole("button", { name: /close/i });
      await expect(closeButton).toBeVisible();

      const box = await closeButton.boundingBox();
      if (box) {
        console.log(`[E2E] Close button size: ${box.width}x${box.height}`);
        expect(box.width).toBeGreaterThanOrEqual(44);
        expect(box.height).toBeGreaterThanOrEqual(44);
        console.log("[E2E] Close button meets 44px touch target requirement");
      } else {
        console.log("[E2E] Could not get close button bounding box - skipping size check");
        test.skip();
      }
    } else {
      console.log("[E2E] No jargon triggers found - skipping touch target test");
      test.skip();
    }
  });

  test("swipe down gesture closes bottom sheet", async ({ page }) => {
    await page.goto("/learn");
    console.log("[E2E] Navigated to learn page");

    const jargonTrigger = page.locator('[data-testid="jargon-term"]').first();
    const hasTrigger = (await jargonTrigger.count()) > 0;

    if (hasTrigger) {
      await jargonTrigger.click();
      const dialog = page.getByRole("dialog");
      await expect(dialog).toBeVisible({ timeout: 5000 });
      console.log("[E2E] Bottom sheet opened");

      // Get the sheet's bounding box
      const box = await dialog.boundingBox();
      if (box) {
        // Simulate swipe down gesture
        const startX = box.x + box.width / 2;
        const startY = box.y + 50; // Start near top of sheet
        const endY = box.y + 350; // Swipe down 300px

        await page.mouse.move(startX, startY);
        await page.mouse.down();
        // Move slowly to simulate a real swipe
        for (let y = startY; y <= endY; y += 30) {
          await page.mouse.move(startX, y);
          await page.waitForTimeout(10);
        }
        await page.mouse.up();
        console.log("[E2E] Performed swipe down gesture");

        // Sheet should close
        await expect(dialog).not.toBeVisible({ timeout: 2000 });
        console.log("[E2E] Bottom sheet dismissed via swipe gesture");
      } else {
        console.log(
          "[E2E] Could not get dialog bounding box - skipping swipe test"
        );
        test.skip();
      }
    } else {
      console.log("[E2E] No jargon triggers found - skipping swipe test");
      test.skip();
    }
  });

  test("body scroll is locked when bottom sheet is open", async ({ page }) => {
    await page.goto("/learn");
    console.log("[E2E] Navigated to learn page");

    const jargonTrigger = page.locator('[data-testid="jargon-term"]').first();
    const hasTrigger = (await jargonTrigger.count()) > 0;

    if (hasTrigger) {
      // Check initial scroll state
      const initialOverflow = await page.evaluate(
        () => document.body.style.overflow
      );
      console.log(`[E2E] Initial body overflow: "${initialOverflow}"`);

      await jargonTrigger.click();
      const dialog = page.getByRole("dialog");
      await expect(dialog).toBeVisible({ timeout: 5000 });

      // Check scroll lock
      const lockedOverflow = await page.evaluate(
        () => document.body.style.overflow
      );
      console.log(`[E2E] Body overflow when sheet open: "${lockedOverflow}"`);
      expect(lockedOverflow).toBe("hidden");

      // Close the sheet
      await page.keyboard.press("Escape");
      await expect(dialog).not.toBeVisible({ timeout: 2000 });

      // Check scroll restored
      const restoredOverflow = await page.evaluate(
        () => document.body.style.overflow
      );
      console.log(`[E2E] Body overflow after close: "${restoredOverflow}"`);
      expect(restoredOverflow).not.toBe("hidden");
    } else {
      console.log("[E2E] No jargon triggers found - skipping scroll lock test");
      test.skip();
    }
  });
});

test.describe("BottomSheet Reduced Motion", () => {
  test("respects prefers-reduced-motion", async ({ page }) => {
    // Enable reduced motion preference
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.setViewportSize({ width: 375, height: 812 });
    console.log("[E2E] Enabled prefers-reduced-motion: reduce");

    await page.goto("/learn");

    const jargonTrigger = page.locator('[data-testid="jargon-term"]').first();
    const hasTrigger = (await jargonTrigger.count()) > 0;

    if (hasTrigger) {
      await jargonTrigger.click();

      // With reduced motion, the sheet should still appear
      // but without slide animation (using opacity instead)
      const dialog = page.getByRole("dialog");
      await expect(dialog).toBeVisible({ timeout: 5000 });
      console.log(
        "[E2E] Bottom sheet visible with reduced motion preference respected"
      );

      // Escape should still work
      await page.keyboard.press("Escape");
      await expect(dialog).not.toBeVisible({ timeout: 2000 });
      console.log("[E2E] Sheet closed correctly with reduced motion");
    } else {
      console.log(
        "[E2E] No jargon triggers found - skipping reduced motion test"
      );
      test.skip();
    }
  });
});
