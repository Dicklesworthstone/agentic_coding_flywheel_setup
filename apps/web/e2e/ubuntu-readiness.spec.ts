import { test, expect, type Page } from "@playwright/test";

const STORAGE_KEY = "agent-flywheel-vps-readiness-selection";
const host = {
  providerId: "contabo",
  planName: "Cloud VPS 16",
  ubuntuVersion: "26.04",
  region: "us",
  targetAgents: 10,
  workloadId: "standard",
};

async function openPlanner(page: Page, saved: unknown = null) {
  await page.goto("/");
  await page.evaluate(({ key, selection }) => {
    localStorage.clear();
    localStorage.setItem("agent-flywheel-user-os", "mac");
    localStorage.setItem("agent-flywheel-wizard-completed-steps", JSON.stringify(
      Array.from({ length: 13 }, (_, index) => index + 1),
    ));
    if (selection !== null) localStorage.setItem(key, JSON.stringify(selection));
  }, { key: STORAGE_KEY, selection: saved });
  await page.goto("/wizard/rent-vps");
  await expect(page.getByTestId("provider-readiness-check")).toBeVisible({ timeout: 10000 });
}

async function storedImage(page: Page) {
  return page.evaluate((key) => {
    const value = localStorage.getItem(key);
    return value ? JSON.parse(value).ubuntuVersion : null;
  }, STORAGE_KEY);
}

test.describe("Ubuntu lifecycle readiness", () => {
  test("new planners use and persist the reviewed LTS recommendation", async ({ page }) => {
    await openPlanner(page);
    await expect(page.getByLabel("Ubuntu image", { exact: true })).toHaveValue("26.04");
    await expect(page.getByTestId("provider-readiness-check")).toContainText("Ready for the selected target.");
    await expect.poll(() => storedImage(page)).toBe("26.04");
    await page.reload();
    await expect(page.getByLabel("Ubuntu image", { exact: true })).toHaveValue("26.04");
  });

  test("saved unsafe choices stay visible until explicitly corrected", async ({ page }) => {
    await openPlanner(page, { ...host, ubuntuVersion: "25.10", planName: "Cloud VPS 8", region: "retired-region" });
    const readiness = page.getByTestId("provider-readiness-check");
    const image = page.getByLabel("Ubuntu image", { exact: true });
    await expect(image).toHaveValue("25.10");
    await expect(image.locator("option:checked")).toContainText("unsupported saved image");
    await expect(page.getByLabel("Plan", { exact: true })).toHaveValue("custom plan");
    await expect(page.getByLabel("Region", { exact: true })).toHaveValue("not-listed");
    await expect(readiness).toContainText("Do not choose this combination for ACFS.");
    await expect.poll(() => storedImage(page)).toBe("25.10");

    await page.reload();
    await expect(image).toHaveValue("25.10");
    await expect(readiness).toContainText("Do not choose this combination for ACFS.");

    await image.selectOption("26.04");
    await page.getByLabel("Plan", { exact: true }).selectOption("Cloud VPS 16");
    await page.getByLabel("Region", { exact: true }).selectOption("us");
    await expect(readiness).toContainText("Ready for the selected target.");
    await expect.poll(() => storedImage(page)).toBe("26.04");
  });

  test("an invalid stored image is not displayed as a supported default", async ({ page }) => {
    await openPlanner(page, { ...host, ubuntuVersion: "Debian 26.04" });
    const image = page.getByLabel("Ubuntu image", { exact: true });
    await expect(image).toHaveValue("unknown");
    await expect(image.locator("option:checked")).toContainText("Image unknown");
    await expect.poll(() => storedImage(page)).toBe("unknown");
    await page.reload();
    await expect(image).toHaveValue("unknown");
  });

  test("older supported LTS hosts retain their upgrade warning", async ({ page }) => {
    await openPlanner(page, { ...host, ubuntuVersion: "24.04" });
    const image = page.getByLabel("Ubuntu image", { exact: true });
    await expect(image).toHaveValue("24.04");
    await expect(image.locator("option:checked")).toContainText("upgrade review required");
    await expect(page.getByTestId("provider-readiness-check")).toContainText("legacy automatic upgrade path");
    await expect.poll(() => storedImage(page)).toBe("24.04");
  });
});
