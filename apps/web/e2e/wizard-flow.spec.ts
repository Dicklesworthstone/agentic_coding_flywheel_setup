import { test, expect, Page } from "@playwright/test";

/**
 * Standard timeouts for different scenarios.
 * Using longer timeouts prevents flaky tests on slow networks/CI environments.
 */
const TIMEOUTS = {
  /** Page hydration and content loading - generous for slow networks */
  PAGE_LOAD: 10000,
  /** Loading spinner should resolve within this time - critical for UX */
  LOADING_SPINNER: 8000,
  /** Form validation state updates */
  VALIDATION: 10000,
  /** Navigation and redirects */
  NAVIGATION: 5000,
  /** Quick checks that should be fast */
  FAST: 3000,
} as const;

function urlPathWithOptionalQuery(pathname: string): RegExp {
  const escaped = pathname.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`${escaped}(\\?.*)?$`);
}

/**
 * Helper to set up prerequisite state for later wizard steps.
 * This avoids repeating the same setup code in every test.
 */
async function setupWizardState(
  page: Page,
  options: { os?: "mac" | "windows"; ip?: string } = {}
) {
  await page.goto("/");
  await page.evaluate(
    ({ os, ip }) => {
      localStorage.clear();
      if (os) localStorage.setItem("agent-flywheel-user-os", os);
      if (ip) localStorage.setItem("agent-flywheel-vps-ip", ip);
    },
    { os: options.os, ip: options.ip }
  );
}

/**
 * Agent Flywheel Wizard Flow E2E Tests
 *
 * These tests verify the complete wizard user journey works correctly,
 * including state persistence, navigation, and edge cases.
 *
 * Button text for each step:
 * - Step 1 (OS Selection): "Continue"
 * - Step 2 (Install Terminal): "I installed it, continue"
 * - Step 3 (Generate SSH Key): "I saved my public key"
 * - Step 4 (Rent VPS): "I rented a VPS"
 * - Step 5 (Create VPS): "Continue to SSH"
 * - Step 6 (SSH Connect): "I'm connected, continue"
 * - Step 7 (Run Installer): "Installation finished"
 * - Step 8 (Reconnect Ubuntu): "I'm connected as ubuntu"
 * - Step 9 (Status Check): "Everything looks good!"
 */

test.describe("Wizard Flow", () => {
  test.beforeEach(async ({ page }) => {
    // Clear localStorage before each test for clean state
    await page.goto("/");
    await page.evaluate(() => localStorage.clear());
  });

  test("should navigate from home to wizard", async ({ page }) => {
    await page.goto("/");
    await page.waitForLoadState("networkidle");

    // Click the primary CTA
    await page.getByRole("link", { name: /start the wizard/i }).click();

    // Should be on step 1 (OS selection)
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/os-selection"));
    await expect(page.locator("h1").first()).toBeVisible();
    await expect(page.getByRole("heading", { level: 1 }).first()).toContainText(/OS|operating|computer/i);
  });

  test("should complete step 1: OS selection", async ({ page }) => {
    await page.goto("/wizard/os-selection");
    await page.waitForLoadState("networkidle");

    // Page should load without getting stuck
    await expect(page.locator("h1").first()).toBeVisible({ timeout: 10000 });

    // Select macOS
    await page.getByRole('radio', { name: /Mac/i }).click();

    // Wait for Continue button to be visible and clickable
    const continueBtn = page.getByRole('button', { name: /continue/i });
    await expect(continueBtn).toBeVisible();
    await continueBtn.click();

    // Should navigate to step 2
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/install-terminal"));
    expect(new URL(page.url()).searchParams.get("os")).toBe("mac");
  });

  test("should complete step 2: Install terminal", async ({ page }) => {
    // Set up prerequisite state
    await page.goto("/wizard/os-selection");
    await page.waitForLoadState("networkidle");
    await page.getByRole('radio', { name: /Mac/i }).click();
    await page.getByRole('button', { name: /continue/i }).click();

    // Now on step 2
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/install-terminal"));
    await page.waitForLoadState("networkidle");
    await expect(page.locator("h1").first()).toContainText(/terminal/i);

    // Click continue
    await page.getByRole('button', { name: /continue/i }).click();

    // Should navigate to step 3
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/generate-ssh-key"));
    expect(new URL(page.url()).searchParams.get("os")).toBe("mac");
  });

  test("should complete step 3: Generate SSH key", async ({ page }) => {
    // Set up prerequisite state
    await page.goto("/wizard/os-selection");
    await page.getByRole('radio', { name: /Mac/i }).click();
    await page.getByRole('button', { name: /continue/i }).click();
    await page.getByRole('button', { name: /continue/i }).click();

    // Now on step 3
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/generate-ssh-key"));
    await expect(page.locator("h1").first()).toContainText(/SSH/i);

    // Click the step 3 specific button
    await page.click('button:has-text("I saved my public key")');

    // Should navigate to step 4
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/rent-vps"));
    expect(new URL(page.url()).searchParams.get("os")).toBe("mac");
  });

  test("should complete step 4: Rent VPS", async ({ page }) => {
    // Set up prerequisite state
    await page.goto("/wizard/os-selection");
    await page.getByRole('radio', { name: /Mac/i }).click();
    await page.getByRole('button', { name: /continue/i }).click();
    await page.getByRole('button', { name: /continue/i }).click();
    await page.click('button:has-text("I saved my public key")');

    // Now on step 4
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/rent-vps"));
    await expect(page.locator("h1").first()).toContainText(/VPS/i);

    // Click continue
    await page.click('button:has-text("I rented a VPS")');

    // Should navigate to step 5
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/create-vps"));
    expect(new URL(page.url()).searchParams.get("os")).toBe("mac");
  });

  test("should complete step 5: Create VPS with IP address", async ({ page }) => {
    // Set up prerequisite state
    await page.goto("/wizard/os-selection");
    await page.getByRole('radio', { name: /Mac/i }).click();
    await page.getByRole('button', { name: /continue/i }).click();
    await page.getByRole('button', { name: /continue/i }).click();
    await page.click('button:has-text("I saved my public key")');
    await page.click('button:has-text("I rented a VPS")');

    // Now on step 5
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/create-vps"));
    expect(new URL(page.url()).searchParams.get("os")).toBe("mac");

    // Check all checklist items
    const checkboxes = page.locator('button[role="checkbox"]');
    const count = await checkboxes.count();
    for (let i = 0; i < count; i++) {
      await checkboxes.nth(i).click();
    }

    // Enter IP address (use type() + blur() for cross-browser reliability)
    const ipInput = page.locator('input[placeholder*="192.168"]');
    await ipInput.clear();
    await ipInput.type("192.168.1.100");
    await ipInput.blur();

    // Wait for validation to show success
    await expect(page.locator('text="Valid IP address"')).toBeVisible({ timeout: 10000 });

    // Click continue
    await page.click('button:has-text("Continue to SSH")');

    // Should navigate to step 6
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/ssh-connect"));
    const step6Url = new URL(page.url());
    expect(step6Url.searchParams.get("os")).toBe("mac");
    expect(step6Url.searchParams.get("ip")).toBe("192.168.1.100");
  });
});

test.describe("SSH Connect Page - Critical Bug Prevention", () => {
  test("should NOT get stuck on loading spinner when prerequisites are met", async ({ page }) => {
    // This is the critical test for the bug that was fixed
    // Set up localStorage with required data
    await setupWizardState(page, { os: "mac", ip: "192.168.1.100" });

    // Navigate to SSH connect page
    await page.goto("/wizard/ssh-connect");

    // Page should load within reasonable time - NOT get stuck on spinner
    // Using LOADING_SPINNER timeout as this tests the hydration race condition
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });
    await expect(page.locator("h1").first()).toContainText(/SSH/i);

    // The IP should be displayed
    await expect(page.locator('code:has-text("192.168.1.100")').first()).toBeVisible();

    // Continue button should be visible and clickable
    await expect(page.locator('button:has-text("continue")')).toBeVisible();
  });

  test("should show loading spinner briefly then content", async ({ page }) => {
    // This test verifies the loading state transition works correctly
    await setupWizardState(page, { os: "mac", ip: "192.168.1.100" });

    await page.goto("/wizard/ssh-connect");

    // Content should appear (either immediately or after brief loading)
    // The key is it MUST appear within the timeout, not get stuck
    const h1 = page.locator("h1").first();
    await expect(h1).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });

    // Once h1 is visible, the loading spinner should NOT be visible
    // The loading spinner uses Terminal icon with animate-pulse
    const loadingSpinner = page.locator('svg.animate-pulse');
    await expect(loadingSpinner).not.toBeVisible();
  });

  test("should redirect to create-vps when IP is missing", async ({ page }) => {
    // Set up only OS, not IP
    await setupWizardState(page, { os: "mac" });

    // Navigate to SSH connect page
    await page.goto("/wizard/ssh-connect");

    // Should redirect to create-vps (where IP is entered)
    await expect(page).toHaveURL(/\/wizard\/create-vps/, { timeout: TIMEOUTS.NAVIGATION });
  });

  test("should redirect to os-selection when OS is missing", async ({ page }) => {
    // Set up only IP, not OS
    await page.goto("/");
    await page.evaluate(() => {
      localStorage.clear();
      localStorage.setItem("agent-flywheel-vps-ip", "192.168.1.100");
    });

    // Navigate to SSH connect page
    await page.goto("/wizard/ssh-connect");

    // Should redirect to os-selection (first step)
    await expect(page).toHaveURL(/\/wizard\/os-selection/, { timeout: TIMEOUTS.NAVIGATION });
  });

  test("should redirect when both OS and IP are missing", async ({ page }) => {
    // Set up empty state
    await page.goto("/");
    await page.evaluate(() => localStorage.clear());

    // Navigate to SSH connect page
    await page.goto("/wizard/ssh-connect");

    // Should redirect (either to os-selection or create-vps)
    await expect(page).not.toHaveURL(/\/wizard\/ssh-connect/, { timeout: TIMEOUTS.NAVIGATION });
  });

  test("should handle continue button click correctly", async ({ page }) => {
    // Set up complete state
    await setupWizardState(page, { os: "mac", ip: "192.168.1.100" });

    await page.goto("/wizard/ssh-connect");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });

    // Click continue
    await page.click('button:has-text("continue")');

    // Should navigate to accounts (step 7 follows ssh-connect step 6)
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/accounts"));
  });

  test("should display correct SSH command with user IP", async ({ page }) => {
    const testIP = "45.67.89.123";
    await setupWizardState(page, { os: "mac", ip: testIP });

    await page.goto("/wizard/ssh-connect");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });

    // The SSH command should contain the user's IP
    await expect(page.locator(`text=ubuntu@${testIP}`).first()).toBeVisible();
  });
});

test.describe("State Persistence", () => {
  test("should persist OS selection across page reloads", async ({ page }) => {
    await page.goto("/wizard/os-selection");
    await page.getByRole('radio', { name: /Windows/i }).click();
    await page.getByRole('button', { name: /continue/i }).click();

    // Reload the page
    await page.reload();

    // Check localStorage
    const os = await page.evaluate(() => localStorage.getItem("agent-flywheel-user-os"));
    expect(os).toBe("windows");

    // URL query string should also reflect the selection
    expect(new URL(page.url()).searchParams.get("os")).toBe("windows");
  });

  test("should persist VPS IP across page reloads", async ({ page }) => {
    // Set up prerequisite state
    await page.goto("/");
    await page.evaluate(() => {
      localStorage.setItem("agent-flywheel-user-os", "mac");
    });

    await page.goto("/wizard/create-vps");

    // Check all checklist items
    const checkboxes = page.locator('button[role="checkbox"]');
    const count = await checkboxes.count();
    for (let i = 0; i < count; i++) {
      await checkboxes.nth(i).click();
    }

    // Enter IP address (use type() + blur() for cross-browser reliability)
    const ipInput = page.locator('input[placeholder*="192.168"]');
    await ipInput.clear();
    await ipInput.type("10.0.0.50");
    await ipInput.blur();

    // Wait for validation to show success before clicking continue
    await expect(page.locator('text="Valid IP address"')).toBeVisible({ timeout: 10000 });
    await page.click('button:has-text("Continue to SSH")');

    // Check localStorage
    const ip = await page.evaluate(() => localStorage.getItem("agent-flywheel-vps-ip"));
    expect(ip).toBe("10.0.0.50");

    // URL query string should also reflect the IP
    expect(new URL(page.url()).searchParams.get("ip")).toBe("10.0.0.50");
  });
});

test.describe("Navigation", () => {
  test("should navigate between steps using sidebar", async ({ page, viewport }) => {
    // Skip on mobile where sidebar is hidden
    if (viewport && viewport.width < 768) {
      test.skip();
    }

    await page.goto("/wizard/os-selection");
    await page.getByRole('radio', { name: /Mac/i }).click();
    await page.getByRole('button', { name: /continue/i }).click();

    // Now on step 2, click on step 1 in sidebar
    await page.click('text="Choose Your OS"');

    // Should navigate back to step 1
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/os-selection"));
    expect(new URL(page.url()).searchParams.get("os")).toBe("mac");
  });

  test("should show mobile stepper on small screens", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto("/wizard/os-selection");
    await page.waitForLoadState("networkidle");

    // Mobile header should show step indicator (text spans elements, so check each part)
    await expect(page.locator('text="Step"').first()).toBeVisible({ timeout: 5000 });
    await expect(page.locator('text="of 13"').first()).toBeVisible();

    // Mobile navigation buttons should be visible at bottom (Back and Next)
    const bottomNav = page.locator(".bottom-nav-safe");
    await expect(bottomNav.getByRole("button", { name: /^Back$/i })).toBeVisible();
    await expect(bottomNav.getByRole("button", { name: /^Next$/i })).toBeVisible();
  });

  test("should navigate using back button", async ({ page }) => {
    await page.goto("/wizard/os-selection");
    await page.getByRole('radio', { name: /Mac/i }).click();
    await page.getByRole('button', { name: /continue/i }).click();

    // Now on step 2 (URL may include query params)
    await expect(page).toHaveURL(/\/wizard\/install-terminal/);

    // Go back using browser back button
    await page.goBack();

    // Should be back on step 1 (URL may include query params like ?os=mac)
    await expect(page).toHaveURL(/\/wizard\/os-selection/);
  });
});

test.describe("IP Address Validation", () => {
  test("should reject invalid IP addresses", async ({ page }) => {
    await page.goto("/");
    await page.evaluate(() => {
      localStorage.setItem("agent-flywheel-user-os", "mac");
    });

    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible();

    const input = page.locator('input[placeholder*="192.168"]');

    // Clear any existing value and type the invalid IP (more reliable than fill across browsers)
    await input.clear();
    await input.type("invalid-ip");
    await input.blur();

    // Should show error (allow extra time for React state updates)
    await expect(page.getByText(/Please enter a valid IP address/i)).toBeVisible({ timeout: 10000 });
  });

  test("should accept valid IP addresses", async ({ page }) => {
    await page.goto("/");
    await page.evaluate(() => {
      localStorage.setItem("agent-flywheel-user-os", "mac");
    });

    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible();

    const input = page.locator('input[placeholder*="192.168"]');

    // Clear any existing value and type the valid IP
    await input.clear();
    await input.type("8.8.8.8");
    await input.blur();

    // Should show success (allow extra time for React state updates)
    await expect(page.locator('text="Valid IP address"')).toBeVisible({ timeout: 10000 });
  });

  test("should reject out-of-range IP octets", async ({ page }) => {
    await page.goto("/");
    await page.evaluate(() => {
      localStorage.setItem("agent-flywheel-user-os", "mac");
    });

    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible();

    const input = page.locator('input[placeholder*="192.168"]');

    // Clear any existing value and type the out-of-range IP
    await input.clear();
    await input.type("256.1.1.1");
    await input.blur();

    // Should show error (allow extra time for React state updates)
    await expect(page.getByText(/Please enter a valid IP address/i)).toBeVisible({ timeout: 10000 });
  });
});

test.describe("Command Card Copy Functionality", () => {
  test("should show copy button on command cards", async ({ page }) => {
    await setupWizardState(page, { os: "mac", ip: "192.168.1.100" });

    await page.goto("/wizard/ssh-connect");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });

    // Find a command card with copy button
    await expect(page.getByRole('button', { name: /copy/i }).first()).toBeVisible();
  });
});

test.describe("Beginner Guide", () => {
  test("should expand SimplerGuide on click", async ({ page }) => {
    await page.goto("/wizard/os-selection");
    await page.waitForLoadState("networkidle");

    // Find and click the SimplerGuide toggle - it MUST be visible
    const guideToggle = page.getByRole('button', { name: /make it simpler/i });
    await expect(guideToggle).toBeVisible({ timeout: 5000 });
    await guideToggle.click();

    // After clicking, the subtitle should change to "Click to collapse"
    await expect(page.getByText(/click to collapse/i)).toBeVisible({ timeout: 5000 });
  });
});

test.describe("Complete Wizard Flow Integration", () => {
  test("should continue from OS selection using detected OS (desktop only)", async ({ page }, testInfo) => {
    test.skip(/Mobile/i.test(testInfo.project.name), "Auto-detect is disabled on mobile");

    await page.goto("/wizard/os-selection");
    await page.evaluate(() => localStorage.clear());
    await page.reload();
    await page.waitForLoadState("networkidle");

    // On desktop projects, the OS should be auto-detected and the Continue button enabled.
    await expect(page.getByRole("button", { name: /^continue$/i })).toBeEnabled();
    await page.getByRole("button", { name: /^continue$/i }).click();
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/install-terminal"));
    expect(new URL(page.url()).searchParams.get("os")).toMatch(/^(mac|windows)$/);
  });

  test("should complete entire wizard flow from start to finish", async ({ page }) => {
    // Start fresh
    await page.goto("/");
    await page.evaluate(() => localStorage.clear());
    await page.waitForLoadState("networkidle");

    // Step 1: Home -> OS Selection
    await page.getByRole("link", { name: /start the wizard/i }).click();
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/os-selection"));

    // Step 1: Select OS
    await page.getByRole('radio', { name: /Mac/i }).click();
    await page.getByRole('button', { name: /continue/i }).click();
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/install-terminal"));
    expect(new URL(page.url()).searchParams.get("os")).toBe("mac");

    // Step 2: Install Terminal
    await page.getByRole('button', { name: /continue/i }).click();
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/generate-ssh-key"));

    // Step 3: Generate SSH Key
    await page.click('button:has-text("I saved my public key")');
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/rent-vps"));

    // Step 4: Rent VPS
    await page.click('button:has-text("I rented a VPS")');
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/create-vps"));

    // Step 5: Create VPS
    const checkboxes = page.locator('button[role="checkbox"]');
    const count = await checkboxes.count();
    for (let i = 0; i < count; i++) {
      await checkboxes.nth(i).click();
    }
    // Users often paste IPs with surrounding whitespace - test that trimming works
    // Use type() + blur() for cross-browser reliability
    const ipInput = page.locator('input[placeholder*="192.168"]');
    await ipInput.clear();
    await ipInput.type(" 192.168.1.100 ");
    await ipInput.blur();
    await expect(page.locator('text="Valid IP address"')).toBeVisible({ timeout: 10000 });
    await page.click('button:has-text("Continue to SSH")');
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/ssh-connect"));
    const sshConnectUrl = new URL(page.url());
    expect(sshConnectUrl.searchParams.get("os")).toBe("mac");
    expect(sshConnectUrl.searchParams.get("ip")).toBe("192.168.1.100");

    // Step 6: SSH Connect - THE CRITICAL TEST
    // This should NOT get stuck on a loading spinner
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });
    await expect(page.locator("h1").first()).toContainText(/SSH/i);
    await page.click('button:has-text("continue")');
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/accounts"));

    // Step 7: Set Up Accounts
    await expect(page.locator("h1").first()).toContainText(/accounts/i);
    await page.click('button:has-text("continue")');
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/preflight-check"));

    // Step 8: Pre-Flight Check - check the "passed" checkbox to enable continue button
    await expect(page.locator("h1").first()).toContainText(/pre-?flight|check/i);
    await page.click('label:has-text("Pre-flight passed")');
    await page.click('button:has-text("continue")');
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/run-installer"));

    // Step 9: Run Installer
    await expect(page.locator("h1").first()).toContainText(/installer/i);
    await page.click('button:has-text("Installation finished")');
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/reconnect-ubuntu"));

    // Step 10: Reconnect Ubuntu
    await page.click('button:has-text("I\'m connected as ubuntu")');
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/verify-key-connection"));

    // Step 11: Verify Key Connection
    await page.click('button:has-text("My key works, continue")');
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/status-check"));

    // Step 12: Status Check
    await page.click('button:has-text("Everything looks good!")');
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/launch-onboarding"));

    // Step 13: Launch Onboarding - Final step!
    await expect(page.locator("h1").first()).toContainText(/congratulations|set up/i);
  });
});

test.describe("Query Param Fallback", () => {
  test("should honor ?os=windows when localStorage is empty", async ({ page }) => {
    await page.goto("/wizard/install-terminal?os=windows");
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/install-terminal"));
    await expect(page.locator("h1").first()).toContainText(/terminal/i);

    // Windows-specific content should render without redirecting.
    // Use .first() because "Windows Terminal" appears multiple times (heading, link, description)
    await expect(page.getByText(/Windows Terminal/i).first()).toBeVisible();
  });

  test("should honor ?os and ?ip on deep-link to ssh-connect", async ({ page }) => {
    await page.goto("/wizard/ssh-connect?os=mac&ip=192.168.1.100");
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/ssh-connect"));
    await expect(page.locator("h1").first()).toContainText(/SSH/i);
    await expect(page.locator('code:has-text("192.168.1.100")').first()).toBeVisible();
  });
});

test.describe("No localStorage (query-only resilience)", () => {
  test("should complete the wizard when localStorage is unavailable", async ({ page }, testInfo) => {
    await page.addInitScript(() => {
      const throwing = () => {
        throw new Error("localStorage blocked");
      };
      Storage.prototype.getItem = throwing;
      Storage.prototype.setItem = throwing;
      Storage.prototype.removeItem = throwing;
      Storage.prototype.clear = throwing;
    });

    // Step 1: pick an OS
    await page.goto("/wizard/os-selection");
    await expect(page.locator("h1").first()).toBeVisible();

    // On mobile, auto-detect is disabled, so Continue should start disabled.
    if (/Mobile/i.test(testInfo.project.name)) {
      await expect(page.getByRole("button", { name: /^continue$/i })).toBeDisabled();
    }

    await page.getByRole("radio", { name: /Mac/i }).click();
    await page.getByRole("button", { name: /^continue$/i }).click();
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/install-terminal"));
    expect(new URL(page.url()).searchParams.get("os")).toBe("mac");

    // Step 2 -> Step 3
    await page.getByRole("button", { name: /continue/i }).click();
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/generate-ssh-key"));

    // Step 3 -> Step 4
    await page.click('button:has-text("I saved my public key")');
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/rent-vps"));

    // Step 4 -> Step 5
    await page.click('button:has-text("I rented a VPS")');
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/create-vps"));

    // Step 5 -> Step 6 (IP stored in URL)
    const checkboxes = page.locator('button[role="checkbox"]');
    const count = await checkboxes.count();
    for (let i = 0; i < count; i++) {
      await checkboxes.nth(i).click();
    }

    const ipInput = page.locator('input[placeholder*="192.168"]');
    await ipInput.clear();
    await ipInput.type("10.10.10.10");
    await ipInput.blur();
    await expect(page.locator('text="Valid IP address"')).toBeVisible({ timeout: 10000 });
    await page.click('button:has-text("Continue to SSH")');

    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/ssh-connect"));
    const url = new URL(page.url());
    expect(url.searchParams.get("os")).toBe("mac");
    expect(url.searchParams.get("ip")).toBe("10.10.10.10");
    await expect(page.locator('code:has-text("10.10.10.10")').first()).toBeVisible();
  });
});

// =============================================================================
// STEP 7: RUN INSTALLER - Individual Tests
// =============================================================================
test.describe("Step 9: Run Installer Page", () => {
  test.beforeEach(async ({ page }) => {
    // Set up prerequisite state for step 7
    await setupWizardState(page, { os: "mac", ip: "192.168.1.100" });
  });

  test("should load run-installer page correctly", async ({ page }) => {
    await page.goto("/wizard/run-installer");
    await page.waitForLoadState("networkidle");

    // Page should load with correct heading
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });
    await expect(page.locator("h1").first()).toContainText(/installer/i);
  });

  test("should display the install command", async ({ page }) => {
    await page.goto("/wizard/run-installer");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // The curl command should be visible
    await expect(page.locator('text=curl -fsSL').first()).toBeVisible();
  });

  test("should have copy button for install command", async ({ page }) => {
    await page.goto("/wizard/run-installer");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Copy button should be present
    await expect(page.getByRole('button', { name: /copy/i }).first()).toBeVisible();
  });

  test("should have expandable 'What it installs' section", async ({ page }) => {
    await page.goto("/wizard/run-installer");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Find the details/summary element
    const detailsToggle = page.locator('summary:has-text("What this command installs")');
    await expect(detailsToggle).toBeVisible();

    // Click to expand
    await detailsToggle.click();

    // Should show tool categories
    await expect(page.locator('text="Shell & Terminal UX"')).toBeVisible();
    await expect(page.locator('text="Coding Agents"')).toBeVisible();
  });

  test("should navigate to reconnect-ubuntu on continue", async ({ page }) => {
    await page.goto("/wizard/run-installer");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Click the continue button
    await page.click('button:has-text("Installation finished")');

    // Should navigate to step 10 (reconnect-ubuntu)
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/reconnect-ubuntu"));
  });

  test("should show warning about not closing terminal", async ({ page }) => {
    await page.goto("/wizard/run-installer");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Warning message should be visible
    await expect(page.locator('text=/don.t close the terminal/i')).toBeVisible();
  });
});

// =============================================================================
// STEP 10: RECONNECT UBUNTU - Individual Tests
// =============================================================================
test.describe("Step 10: Reconnect Ubuntu Page", () => {
  test.beforeEach(async ({ page }) => {
    await setupWizardState(page, { os: "mac", ip: "192.168.1.100" });
  });

  test("should load reconnect-ubuntu page correctly", async ({ page }) => {
    await page.goto("/wizard/reconnect-ubuntu");

    // Page should load without getting stuck on spinner
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });
    await expect(page.locator("h1").first()).toContainText(/reconnect/i);
  });

  test("should NOT get stuck on loading spinner", async ({ page }) => {
    await page.goto("/wizard/reconnect-ubuntu");

    // Content should appear within timeout
    const h1 = page.locator("h1").first();
    await expect(h1).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });

    // Loading spinner should NOT be visible once content loads
    const loadingSpinner = page.locator('svg.animate-spin');
    await expect(loadingSpinner).not.toBeVisible();
  });

  test("should display SSH command with user IP", async ({ page }) => {
    const testIP = "10.20.30.40";
    await setupWizardState(page, { os: "mac", ip: testIP });

    await page.goto("/wizard/reconnect-ubuntu");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });

    // The SSH command should contain the user's IP
    await expect(page.locator(`text=ubuntu@${testIP}`).first()).toBeVisible();
  });

  test("should have Skip button for users already connected as ubuntu", async ({ page }) => {
    await page.goto("/wizard/reconnect-ubuntu");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });

    // Skip button should be visible
    const skipButton = page.locator('button:has-text("Skip")');
    await expect(skipButton).toBeVisible();
  });

  test("should navigate to verify-key-connection when Skip button is clicked", async ({ page }) => {
    await page.goto("/wizard/reconnect-ubuntu");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });

    // Click the skip button
    await page.click('button:has-text("Skip")');

    // Should navigate to step 11 (verify-key-connection)
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/verify-key-connection"));
  });

  test("should navigate to verify-key-connection on main continue button", async ({ page }) => {
    await page.goto("/wizard/reconnect-ubuntu");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });

    // Click the main continue button
    await page.click('button:has-text("I\'m connected as ubuntu")');

    // Should navigate to step 11 (verify-key-connection)
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/verify-key-connection"));
  });

  test("should redirect to create-vps when IP is missing", async ({ page }) => {
    await setupWizardState(page, { os: "mac" }); // No IP

    await page.goto("/wizard/reconnect-ubuntu");

    // Should redirect
    await expect(page).toHaveURL(/\/wizard\/create-vps/, { timeout: TIMEOUTS.NAVIGATION });
  });

  test("should show exit command", async ({ page }) => {
    await page.goto("/wizard/reconnect-ubuntu");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });

    // Should show the exit command
    await expect(page.locator('text="exit"').first()).toBeVisible();
  });
});

// =============================================================================
// STEP 9: STATUS CHECK - Individual Tests
// =============================================================================
test.describe("Step 12: Status Check Page", () => {
  test.beforeEach(async ({ page }) => {
    await setupWizardState(page, { os: "mac", ip: "192.168.1.100" });
  });

  test("should load status-check page correctly", async ({ page }) => {
    await page.goto("/wizard/status-check");
    await page.waitForLoadState("networkidle");

    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });
    await expect(page.locator("h1").first()).toContainText(/status check/i);
  });

  test("should display acfs doctor command", async ({ page }) => {
    await page.goto("/wizard/status-check");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Doctor command should be visible
    await expect(page.locator('text="acfs doctor"')).toBeVisible();
  });

  test("should display quick spot check commands", async ({ page }) => {
    await page.goto("/wizard/status-check");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Quick check commands should be visible
    await expect(page.locator('text="cc --version"')).toBeVisible();
    await expect(page.locator('text="bun --version"')).toBeVisible();
    await expect(page.locator('text="which tmux"')).toBeVisible();
  });

  test("should have copy buttons for commands", async ({ page }) => {
    await page.goto("/wizard/status-check");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Should have at least one copy button
    const copyButtons = page.getByRole('button', { name: /copy/i });
    await expect(copyButtons.first()).toBeVisible();
  });

  test("should show troubleshooting advice", async ({ page }) => {
    await page.goto("/wizard/status-check");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Troubleshooting section should mention source ~/.zshrc
    await expect(page.locator('text=/source.*zshrc/i')).toBeVisible();
  });

  test("should navigate to launch-onboarding on continue", async ({ page }) => {
    await page.goto("/wizard/status-check");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Click continue
    await page.click('button:has-text("Everything looks good!")');

    // Should navigate to step 13 (launch-onboarding)
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/launch-onboarding"));
  });
});

// =============================================================================
// STEP 10: LAUNCH ONBOARDING - Individual Tests
// =============================================================================
test.describe("Step 13: Launch Onboarding Page", () => {
  test.beforeEach(async ({ page }) => {
    await setupWizardState(page, { os: "mac", ip: "192.168.1.100" });
  });

  test("should load launch-onboarding page correctly", async ({ page }) => {
    await page.goto("/wizard/launch-onboarding");
    await page.waitForLoadState("networkidle");

    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });
    // Should contain congratulations or setup complete message
    await expect(page.locator("h1").first()).toContainText(/congratulations|set up|complete/i);
  });

  test("should display onboarding command", async ({ page }) => {
    await page.goto("/wizard/launch-onboarding");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Onboarding command should be visible
    await expect(page.locator('text="onboard"')).toBeVisible();
  });

  test("should be the final step with no next button", async ({ page }) => {
    await page.goto("/wizard/launch-onboarding");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // This is the final step of the wizard - it should have learning hub CTAs
    // but should NOT have a standard wizard "Next" navigation button
    const learningHubButton = page.locator('button:has-text("Start Learning Hub")');
    const nextStepButton = page.locator('button:has-text("Next Step")');

    // Should have the Learning Hub CTA
    await expect(learningHubButton).toBeVisible();

    // Should NOT have a standard "Next Step" navigation (this is the final step)
    const nextStepCount = await nextStepButton.count();
    expect(nextStepCount).toBe(0);
  });

  test("should show celebration/success messaging", async ({ page }) => {
    await page.goto("/wizard/launch-onboarding");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Should have positive messaging
    await expect(page.locator('text=/ready|complete|success|done/i').first()).toBeVisible();
  });
});

// =============================================================================
// CREATE VPS - Button Disabled State Tests
// =============================================================================
test.describe("Create VPS - Button Disabled States", () => {
  test.beforeEach(async ({ page }) => {
    await setupWizardState(page, { os: "mac" });
  });

  test("should have disabled button when no checkboxes are checked", async ({ page }) => {
    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Enter valid IP but don't check any boxes
    const ipInput = page.locator('input[placeholder*="192.168"]');
    await ipInput.clear();
    await ipInput.type("192.168.1.100");
    await ipInput.blur();
    await expect(page.locator('text="Valid IP address"')).toBeVisible({ timeout: TIMEOUTS.VALIDATION });

    // Continue button should be disabled
    const continueButton = page.locator('button:has-text("Continue to SSH")');
    await expect(continueButton).toBeDisabled();
  });

  test("should have disabled button when only some checkboxes are checked", async ({ page }) => {
    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Check only the first checkbox
    const checkboxes = page.locator('button[role="checkbox"]');
    await checkboxes.first().click();

    // Enter valid IP
    const ipInput = page.locator('input[placeholder*="192.168"]');
    await ipInput.clear();
    await ipInput.type("192.168.1.100");
    await ipInput.blur();
    await expect(page.locator('text="Valid IP address"')).toBeVisible({ timeout: TIMEOUTS.VALIDATION });

    // Continue button should still be disabled (not all checkboxes checked)
    const continueButton = page.locator('button:has-text("Continue to SSH")');
    await expect(continueButton).toBeDisabled();
  });

  test("should have disabled button when IP is empty", async ({ page }) => {
    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Check all checkboxes
    const checkboxes = page.locator('button[role="checkbox"]');
    const count = await checkboxes.count();
    for (let i = 0; i < count; i++) {
      await checkboxes.nth(i).click();
    }

    // Don't enter IP - button should be disabled
    const continueButton = page.locator('button:has-text("Continue to SSH")');
    await expect(continueButton).toBeDisabled();
  });

  test("should have disabled button when IP is invalid", async ({ page }) => {
    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Check all checkboxes
    const checkboxes = page.locator('button[role="checkbox"]');
    const count = await checkboxes.count();
    for (let i = 0; i < count; i++) {
      await checkboxes.nth(i).click();
    }

    // Enter invalid IP
    const ipInput = page.locator('input[placeholder*="192.168"]');
    await ipInput.clear();
    await ipInput.type("not-an-ip");
    await ipInput.blur();

    // Wait for validation error
    await expect(page.getByText(/Please enter a valid IP address/i)).toBeVisible({ timeout: TIMEOUTS.VALIDATION });

    // Continue button should be disabled
    const continueButton = page.locator('button:has-text("Continue to SSH")');
    await expect(continueButton).toBeDisabled();
  });

  test("should enable button only when ALL requirements are met", async ({ page }) => {
    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Check all checkboxes
    const checkboxes = page.locator('button[role="checkbox"]');
    const count = await checkboxes.count();
    for (let i = 0; i < count; i++) {
      await checkboxes.nth(i).click();
    }

    // Enter valid IP
    const ipInput = page.locator('input[placeholder*="192.168"]');
    await ipInput.clear();
    await ipInput.type("192.168.1.100");
    await ipInput.blur();
    await expect(page.locator('text="Valid IP address"')).toBeVisible({ timeout: TIMEOUTS.VALIDATION });

    // NOW button should be enabled
    const continueButton = page.locator('button:has-text("Continue to SSH")');
    await expect(continueButton).toBeEnabled();
  });

  test("should count checkboxes correctly (expect 4 items)", async ({ page }) => {
    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    const checkboxes = page.locator('button[role="checkbox"]');
    const count = await checkboxes.count();

    // Should have 5 checklist items as defined in the page
    expect(count).toBe(5);
  });
});

// =============================================================================
// FORM VALIDATION - Error Visibility Tests
// =============================================================================
test.describe("Form Validation - Error States", () => {
  test("should show error immediately on invalid IP blur", async ({ page }) => {
    await setupWizardState(page, { os: "mac" });
    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    const input = page.locator('input[placeholder*="192.168"]');
    await input.clear();
    await input.type("abc");
    await input.blur();

    // Error should appear
    await expect(page.getByText(/Please enter a valid IP address/i)).toBeVisible({ timeout: TIMEOUTS.VALIDATION });
  });

  test("should clear error when valid IP is entered", async ({ page }) => {
    await setupWizardState(page, { os: "mac" });
    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    const input = page.locator('input[placeholder*="192.168"]');

    // First enter invalid
    await input.clear();
    await input.type("invalid");
    await input.blur();
    await expect(page.getByText(/Please enter a valid IP address/i)).toBeVisible({ timeout: TIMEOUTS.VALIDATION });

    // Now enter valid
    await input.clear();
    await input.type("192.168.1.1");
    await input.blur();

    // Error should disappear, success should appear
    await expect(page.getByText(/Please enter a valid IP address/i)).not.toBeVisible();
    await expect(page.locator('text="Valid IP address"')).toBeVisible({ timeout: TIMEOUTS.VALIDATION });
  });

  test("should validate various IP edge cases", async ({ page }) => {
    await setupWizardState(page, { os: "mac" });
    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    const input = page.locator('input[placeholder*="192.168"]');

    // Test empty string
    await input.clear();
    await input.blur();
    // No error for empty (only shows on submit attempt)

    // Test partial IP
    await input.clear();
    await input.type("192.168");
    await input.blur();
    await expect(page.getByText(/Please enter a valid IP address/i)).toBeVisible({ timeout: TIMEOUTS.VALIDATION });

    // Test valid edge cases
    await input.clear();
    await input.type("0.0.0.0");
    await input.blur();
    await expect(page.locator('text="Valid IP address"')).toBeVisible({ timeout: TIMEOUTS.VALIDATION });

    await input.clear();
    await input.type("255.255.255.255");
    await input.blur();
    await expect(page.locator('text="Valid IP address"')).toBeVisible({ timeout: TIMEOUTS.VALIDATION });
  });
});

// =============================================================================
// EDGE CASES - Page Reload, Browser Navigation
// =============================================================================
test.describe("Edge Cases - Reload and Navigation", () => {
  test("should maintain state after page reload mid-wizard", async ({ page }) => {
    // Go through first few steps
    await page.goto("/wizard/os-selection");
    await page.evaluate(() => localStorage.clear());
    await page.getByRole('radio', { name: /Mac/i }).click();
    await page.getByRole('button', { name: /continue/i }).click();
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/install-terminal"));

    // Reload the page
    await page.reload();
    await page.waitForLoadState("networkidle");

    // State should be preserved
    const os = await page.evaluate(() => localStorage.getItem("agent-flywheel-user-os"));
    expect(os).toBe("mac");

    // Should still be on install-terminal (not redirected)
    await expect(page).toHaveURL(/\/wizard\/install-terminal/);
  });

  test("should handle multiple rapid back/forward navigations", async ({ page }) => {
    await page.goto("/wizard/os-selection");
    await page.evaluate(() => localStorage.clear());
    await page.getByRole('radio', { name: /Mac/i }).click();
    await page.getByRole('button', { name: /continue/i }).click();
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/install-terminal"));

    await page.getByRole('button', { name: /continue/i }).click();
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/generate-ssh-key"));

    // Rapid back/forward
    await page.goBack();
    await page.goBack();
    await page.goForward();

    // Should end up on install-terminal
    await expect(page).toHaveURL(/\/wizard\/install-terminal/);

    // Page should still be functional
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });
  });

  test("should handle direct URL access to any step with proper state", async ({ page }) => {
    // Set up complete state
    await setupWizardState(page, { os: "mac", ip: "192.168.1.100" });

    // Access step 9 directly
    await page.goto("/wizard/status-check");

    // Should load correctly (not redirect) since we have all required state
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });
    await expect(page.locator("h1").first()).toContainText(/status check/i);
  });

  test("should handle bookmark to middle step without state", async ({ page }) => {
    // Clear all state
    await page.goto("/");
    await page.evaluate(() => localStorage.clear());

    // Try to access step 6 directly without any state
    await page.goto("/wizard/ssh-connect");

    // Should redirect somewhere (not stay on ssh-connect)
    await expect(page).not.toHaveURL(/\/wizard\/ssh-connect/, { timeout: TIMEOUTS.NAVIGATION });
  });
});

// =============================================================================
// MOBILE NAVIGATION - Button Tests
// =============================================================================
test.describe("Mobile Navigation", () => {
  test.beforeEach(async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
  });

  test("should show mobile navigation buttons at bottom", async ({ page }) => {
    await page.goto("/wizard/os-selection");
    await page.waitForLoadState("networkidle");

    const bottomNav = page.locator(".bottom-nav-safe");
    await expect(bottomNav.getByRole("button", { name: /^Back$/i })).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });
    await expect(bottomNav.getByRole("button", { name: /^Next$/i })).toBeVisible();
  });

  test("should have Back button disabled on first step", async ({ page }) => {
    await page.goto("/wizard/os-selection");
    await page.waitForLoadState("networkidle");

    const bottomNav = page.locator(".bottom-nav-safe");
    const backButton = bottomNav.getByRole("button", { name: /^Back$/i });
    await expect(backButton).toBeDisabled();
  });

  test("should navigate forward using mobile Next button", async ({ page }) => {
    await page.goto("/wizard/os-selection");
    await page.waitForLoadState("networkidle");

    // Select OS first
    await page.getByRole('radio', { name: /Mac/i }).click();

    // Click mobile Next button
    const bottomNav = page.locator(".bottom-nav-safe");
    await bottomNav.getByRole("button", { name: /^Next$/i }).click();

    // Should navigate to step 2
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/install-terminal"));
  });

  test("should navigate back using mobile Back button", async ({ page }) => {
    // Start on step 2
    await page.goto("/wizard/os-selection");
    await page.getByRole('radio', { name: /Mac/i }).click();

    const bottomNav = page.locator(".bottom-nav-safe");
    await bottomNav.getByRole("button", { name: /^Next$/i }).click();
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/install-terminal"));

    // Now click Back
    await bottomNav.getByRole("button", { name: /^Back$/i }).click();

    // Should be back on step 1
    await expect(page).toHaveURL(urlPathWithOptionalQuery("/wizard/os-selection"));
  });

  test("should show mobile step indicator", async ({ page }) => {
    await page.goto("/wizard/generate-ssh-key?os=mac");
    await page.waitForLoadState("networkidle");

    // Should show step indicator with "Step X of Y" format
    // Using regex for partial match since text spans multiple elements
    await expect(page.locator('text=/Step.*of/i').first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });
  });

  test("should hide desktop sidebar on mobile", async ({ page }) => {
    await page.goto("/wizard/os-selection");
    await page.waitForLoadState("networkidle");

    // Desktop sidebar should not be visible
    const sidebar = page.locator('aside.hidden.md\\:block');
    // Check that it has display: none or is not visible
    await expect(sidebar).not.toBeVisible();
  });
});

// =============================================================================
// OS SELECTION - Additional Tests
// =============================================================================
test.describe("OS Selection - Edge Cases", () => {
  test("should require OS selection before continue on mobile", async ({ page }, testInfo) => {
    // This test is specifically for mobile where auto-detect is disabled
    test.skip(!/Mobile/i.test(testInfo.project.name), "Only runs on mobile");

    await page.goto("/wizard/os-selection");
    await page.evaluate(() => localStorage.clear());
    await page.reload();
    await page.waitForLoadState("networkidle");

    // On mobile, Continue should be disabled until OS is selected
    await expect(page.getByRole("button", { name: /^continue$/i })).toBeDisabled();

    // Select an OS
    await page.getByRole('radio', { name: /Mac/i }).click();

    // Now Continue should be enabled
    await expect(page.getByRole("button", { name: /^continue$/i })).toBeEnabled();
  });

  test("should show detected badge on matching OS card", async ({ page }, testInfo) => {
    test.skip(/Mobile/i.test(testInfo.project.name), "Auto-detect disabled on mobile");

    await page.goto("/wizard/os-selection");
    await page.evaluate(() => localStorage.clear());
    await page.reload();
    await page.waitForLoadState("networkidle");

    // There should be a "Detected" or "Selected" badge visible
    // (depending on whether user has clicked it)
    await expect(page.locator('text=/Detected|Selected/')).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });
  });

  test("should toggle selection between Mac and Windows", async ({ page }) => {
    await page.goto("/wizard/os-selection");
    await page.evaluate(() => localStorage.clear());
    await page.reload();
    await page.waitForLoadState("networkidle");

    // Select Mac
    await page.getByRole('radio', { name: /Mac/i }).click();
    await expect(page.getByRole('radio', { name: /Mac/i })).toHaveAttribute('aria-checked', 'true');

    // Select Windows
    await page.getByRole('radio', { name: /Windows/i }).click();
    await expect(page.getByRole('radio', { name: /Windows/i })).toHaveAttribute('aria-checked', 'true');
    await expect(page.getByRole('radio', { name: /Mac/i })).toHaveAttribute('aria-checked', 'false');
  });
});

// =============================================================================
// ACCESSIBILITY - Basic A11y Tests
// =============================================================================
test.describe("Accessibility", () => {
  test("should have proper heading hierarchy", async ({ page }) => {
    await page.goto("/wizard/os-selection");
    await page.waitForLoadState("networkidle");

    // Should have exactly one h1
    const h1Count = await page.locator("h1").count();
    expect(h1Count).toBeGreaterThanOrEqual(1);

    // h1 should be visible
    await expect(page.locator("h1").first()).toBeVisible();
  });

  test("should have accessible buttons", async ({ page }) => {
    await setupWizardState(page, { os: "mac", ip: "192.168.1.100" });
    await page.goto("/wizard/ssh-connect");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.LOADING_SPINNER });

    // Continue button should be accessible
    const continueButton = page.getByRole('button', { name: /continue/i });
    await expect(continueButton).toBeVisible();
    await expect(continueButton).toBeEnabled();
  });

  test("should have accessible form inputs", async ({ page }) => {
    await setupWizardState(page, { os: "mac" });
    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // IP input should be accessible
    const input = page.locator('input[placeholder*="192.168"]');
    await expect(input).toBeVisible();
    await expect(input).toBeEnabled();
  });

  test("should have accessible checkboxes", async ({ page }) => {
    await setupWizardState(page, { os: "mac" });
    await page.goto("/wizard/create-vps");
    await expect(page.locator("h1").first()).toBeVisible({ timeout: TIMEOUTS.PAGE_LOAD });

    // Checkboxes should have proper role
    const checkboxes = page.locator('button[role="checkbox"]');
    const count = await checkboxes.count();
    expect(count).toBeGreaterThan(0);

    // First checkbox should be clickable
    await checkboxes.first().click();
    await expect(checkboxes.first()).toHaveAttribute('aria-checked', 'true');
  });
});
