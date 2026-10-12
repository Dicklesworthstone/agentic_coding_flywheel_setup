import { expect, type Page, test } from "@playwright/test";

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
  await page.evaluate(
    ({ key, selection }) => {
      localStorage.clear();
      localStorage.setItem("agent-flywheel-user-os", "mac");
      localStorage.setItem(
        "agent-flywheel-wizard-completed-steps",
        JSON.stringify(Array.from({ length: 13 }, (_, index) => index + 1)),
      );
      if (selection !== null) localStorage.setItem(key, JSON.stringify(selection));
    },
    { key: STORAGE_KEY, selection: saved },
  );
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
    await expect(page.getByTestId("provider-readiness-check")).toContainText(
      "Ready for the selected target.",
    );
    await expect.poll(() => storedImage(page)).toBe("26.04");
    await page.reload();
    await expect(page.getByLabel("Ubuntu image", { exact: true })).toHaveValue("26.04");
  });

  test("saved unsafe choices stay visible until explicitly corrected", async ({ page }) => {
    await openPlanner(page, {
      ...host,
      ubuntuVersion: "25.10",
      planName: "Cloud VPS 8",
      region: "retired-region",
    });
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
    await expect(page.getByTestId("provider-readiness-check")).toContainText(
      "upgrades it in place to Ubuntu 26.04 LTS (24.04 → 26.04;",
    );
    await expect.poll(() => storedImage(page)).toBe("24.04");
  });

  test("planner edits survive unavailable storage without inventing a persisted host", async ({ page }) => {
    await page.addInitScript((key) => {
      const originalSetItem = Storage.prototype.setItem;
      Storage.prototype.setItem = function (name, value) {
        if (name === key) throw new DOMException("Storage is unavailable", "QuotaExceededError");
        originalSetItem.call(this, name, value);
      };
    }, STORAGE_KEY);
    await openPlanner(page);
    const image = page.getByLabel("Ubuntu image", { exact: true });
    await image.selectOption("24.04");
    await expect(image).toHaveValue("24.04");
    await expect(page.getByTestId("provider-readiness-check")).toContainText("upgrades it in place");
    expect(await storedImage(page)).toBeNull();
    await page.reload();
    await expect(image).toHaveValue("26.04");
  });

  test("planner follows a cross-tab saved choice and storage clear", async ({ page }) => {
    await openPlanner(page, host);
    const image = page.getByLabel("Ubuntu image", { exact: true });
    await image.selectOption("24.04");
    await expect.poll(() => storedImage(page)).toBe("24.04");
    await page.evaluate(({ key, selection }) => {
      const oldValue = localStorage.getItem(key);
      const newValue = JSON.stringify(selection);
      localStorage.setItem(key, newValue);
      window.dispatchEvent(new StorageEvent("storage", { key, oldValue, newValue, storageArea: localStorage }));
    }, { key: STORAGE_KEY, selection: { ...host, ubuntuVersion: "25.10" } });
    await expect(image).toHaveValue("25.10");
    await expect(page.getByTestId("provider-readiness-check")).toContainText("Do not choose this combination");
    await page.evaluate(() => {
      localStorage.clear();
      window.dispatchEvent(new StorageEvent("storage", { key: null, storageArea: localStorage }));
    });
    await expect(image).toHaveValue("26.04");
  });

  test("rapid planner edits retain the final explicit choice", async ({ page }) => {
    await openPlanner(page, { ...host, ubuntuVersion: "25.10" });
    const image = page.getByLabel("Ubuntu image", { exact: true });
    await image.evaluate((element) => {
      const select = element as HTMLSelectElement;
      for (const value of ["24.04", "22.04", "26.04"]) {
        select.value = value;
        select.dispatchEvent(new Event("change", { bubbles: true }));
      }
    });
    await expect(image).toHaveValue("26.04");
    await expect.poll(() => storedImage(page)).toBe("26.04");
    await page.reload();
    await expect(image).toHaveValue("26.04");
  });
});

test.describe("analytics document privacy boundary", () => {
  test.skip(process.env.ACFS_E2E_EXPECT_ANALYTICS !== "1", "Requires isolated build with a test GA measurement ID and intercepted vendor requests");

  test("public documents load GA after installing the navigation boundary", async ({ page }) => {
    const attempts: string[] = [];
    await page.route("https://www.googletagmanager.com/**", async (route) => {
      attempts.push(route.request().url());
      await route.fulfill({ status: 200, contentType: "application/javascript", body: "" });
    });
    await page.goto("/?mode=safe");
    await expect.poll(() => attempts.length).toBeGreaterThan(0);
    await page.evaluate(() => {
      window.history.pushState({}, "", "/?mode=safe&token=sk-proj-abcdefghijklmnopqrstuvwxyz012345");
    });
    await expect(page).not.toHaveURL(/sk-proj-/);
    expect(attempts.every((url) => !url.includes("sk-proj-"))).toBe(true);
  });

  test("initial sensitive and private documents never mount the vendor runtime", async ({ page }) => {
    const attempts: string[] = [];
    await page.route("https://www.googletagmanager.com/**", async (route) => {
      attempts.push(route.request().url());
      await route.fulfill({ status: 200, contentType: "application/javascript", body: "" });
    });
    for (const url of ["/?ip=203.0.113.42", "/wizard/rent-vps"]) {
      await page.goto(url);
      await page.waitForLoadState("networkidle");
      expect(attempts).toEqual([]);
    }
  });
});
