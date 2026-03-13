import { defineConfig, devices } from "@playwright/test";
import os from "node:os";

/**
 * Playwright configuration for Agent Flywheel web e2e testing.
 * @see https://playwright.dev/docs/test-configuration
 */
const isCI = !!process.env.CI;

const DEFAULT_LOCAL_WORKERS = 4;

const DEFAULT_PORT = 3000;
const parsedPort = Number.parseInt(process.env.PW_PORT || process.env.PORT || "", 10);
const port = Number.isFinite(parsedPort) && parsedPort > 0 ? parsedPort : DEFAULT_PORT;

const baseURL = process.env.PLAYWRIGHT_BASE_URL || `http://127.0.0.1:${port}`;

// Skip local webServer when testing against external URL (e.g., production)
const isExternalUrl = !!process.env.PLAYWRIGHT_BASE_URL;

const parsePositiveInt = (raw: string | undefined): number | undefined => {
  if (!raw) return undefined;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
};

const resolvedWorkers = (() => {
  if (isCI) return 1;

  // Allow local override for faster/slower runs.
  const envWorkers = parsePositiveInt(process.env.PW_WORKERS);
  if (envWorkers !== undefined) return envWorkers;

  // Default local runs to a small pool to avoid overloading a single Next.js server
  // (which can cause intermittent console/page errors in highly-parallel suites).
  const available =
    typeof os.availableParallelism === "function" ? os.availableParallelism() : os.cpus().length;
  const safeAvailable = Number.isFinite(available) && available > 0 ? available : DEFAULT_LOCAL_WORKERS;

  return Math.min(DEFAULT_LOCAL_WORKERS, safeAvailable);
})();

const webServerCommand = (() => {
  const isolatedScope = `playwright-${port}`;

  // Default to production server for stability (matches CI behavior).
  // Override locally with PW_USE_DEV_SERVER=1 if needed.
  if (!isCI && process.env.PW_USE_DEV_SERVER === "1") {
    return `bun run dev -- -H 127.0.0.1 --port ${port}`;
  }
  return `ACFS_NEXT_DIST_SCOPE=${isolatedScope} bun run build:isolated && ACFS_NEXT_DIST_SCOPE=${isolatedScope} bun run start:isolated -- -H 127.0.0.1 -p ${port}`;
})();

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: resolvedWorkers,
  reporter: process.env.CI ? "github" : "html",
  // Increase timeout for CI environments
  timeout: process.env.CI ? 60000 : 30000,
  // Give actions more time in CI
  expect: {
    timeout: process.env.CI ? 10000 : 5000,
  },

  use: {
    baseURL,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    // Increase action timeout for CI
    actionTimeout: process.env.CI ? 15000 : 10000,
    navigationTimeout: process.env.CI ? 30000 : 15000,
  },

  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "firefox",
      use: { ...devices["Desktop Firefox"] },
    },
    {
      name: "webkit",
      use: { ...devices["Desktop Safari"] },
    },
    {
      name: "Mobile Chrome",
      use: { ...devices["Pixel 5"] },
    },
    {
      name: "Mobile Safari",
      use: { ...devices["iPhone 12"] },
    },
  ],

  // Skip webServer when testing against external URL (production smoke tests)
  webServer: isExternalUrl
    ? undefined
    : {
        command: webServerCommand,
        url: baseURL,
        env: {
          ...process.env,
          // Disable third-party scripts during e2e to avoid flakiness from external requests.
          NEXT_PUBLIC_GA_MEASUREMENT_ID: "",
          GA_API_SECRET: "",
          NEXT_PUBLIC_GTM_ID: "",
          NEXT_PUBLIC_CLARITY_PROJECT_ID: "",
          NEXT_PUBLIC_ENABLE_VERCEL_ANALYTICS: "false",
          NEXT_PUBLIC_ENABLE_SPEED_INSIGHTS: "false",
        },
        reuseExistingServer: !isCI,
        timeout: 180000, // 3 minutes for build + start
      },
});
